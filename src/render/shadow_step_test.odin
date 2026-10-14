package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import level "../level"

// A small open room: the player in the middle holding one Movimento Ombra,
// one enemy far off.
shadow_view_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> (room: game.Room) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#...@...#", "#.......#", "#......>#", "#########"}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	made: bool
	player^, made = game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	_, added := game.add_owned_card(&player.deck, .Shadow_Step)
	testing.expect(t, added)
	testing.expect(t, game.configure_tactical(player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {7, 1}, health = 9, attack = 1}}
	built: bool
	room, built = game.create_room(data, player, {enemies = enemies[:]})
	testing.expect(t, built)
	return
}

shadow_view_test_renderer :: proc(data: ^level.Level, snapshot: ^Room_Presentation) -> ^Renderer {
	renderer := new(Renderer)
	renderer^ = create(960, 540, data)
	renderer.tactical = {enabled = true, snapshot = snapshot}
	renderer.sprite_assets.elapsed = 10
	return renderer
}

// One frame of the board: time passes on the sprite clock and in the cues,
// then the view reads the room.
shadow_view_test_frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
	renderer.sprite_assets.elapsed += f64(dt)
	update_renderer_event_timeline(renderer, dt)
	update_tactical_view(renderer, room, {}, false)
}

// The pool follows the room's shadow: it sinks with the card's own cue, eases
// out of each cell over the step's lockout, counts a diagonal on a beat as a
// critical, and comes out where the body rose with the rise's cue; meanwhile
// the world's clock stands still, then goes on from where it stopped.
@(test)
test_shadow_pool_follows_the_room_and_the_world_holds :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := shadow_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	update_tactical_view(renderer, &room, {}, false)
	s := &renderer.tactical.shadow
	testing.expect(t, !s.active && !tactical_shadow_showing(renderer))
	enemy := game.enemy_entity(room.enemies[0].id)
	testing.expect_value(t, living_clock(renderer, enemy), f64(10))

	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, s.active && s.sink_paced && s.frozen_at == 10)
	// The card plays first: the figure still stands.
	testing.expect_value(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY), f32(0))
	testing.expect_value(t, tactical_shadow_depth(renderer, enemy), f32(0))
	deepest := f32(0)
	for _ in 0..<200 {
		if !renderer_blocks_player_input(renderer) { break }
		shadow_view_test_frame(renderer, &room, 0.02)
		depth := tactical_shadow_depth(renderer, game.PLAYER_ENTITY)
		testing.expect(t, depth >= deepest)
		deepest = depth
	}
	testing.expect(t, !renderer_blocks_player_input(renderer))
	testing.expect_value(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY), SHADOW_DEPTH)
	testing.expect(t, s.frozen == 1)
	// The world's drawings hold the moment it stopped; the player's go on.
	testing.expect_value(t, living_clock(renderer, enemy), f64(10))
	testing.expect_value(t, living_clock(renderer, game.PLAYER_ENTITY), renderer.sprite_assets.elapsed)

	// A step: the shadow moves, the body stays; the pool leaves at once and is
	// mostly there a quarter into the lockout.
	body := player.position
	testing.expect_value(t, game.try_shadow_step(&room, .East), game.Action_Result.Moved)
	update_tactical_view(renderer, &room, {}, false)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, s.steps == 1 && s.criticals == 0)
	testing.expect_value(t, snapshot.player.position, presentation_position(body))
	testing.expect(t, !game.tactical_tick(&room, game.TACTICAL_SHADOW_STEP_SECONDS*0.25, true, false))
	shadow_view_test_frame(renderer, &room, 0.1)
	p := snapshot.player.position
	testing.expect(t, p.x > f32(body.x)+0.5 && p.x < f32(body.x)+1 && p.y == f32(body.y))
	testing.expect_value(t, player.position, body)
	testing.expect(t, s.at == p)

	// Two keys on the shadow's first beat: a diagonal, and a critical.
	for _ in 0..<40 {
		if game.tactical_shadow_beat_target(&room) != 0 { break }
		testing.expect(t, !game.tactical_tick(&room, 0.05, true, false))
		shadow_view_test_frame(renderer, &room, 0.05)
	}
	testing.expect(t, s.on_beat && s.beat_ahead)
	beat := game.tactical_shadow_beat_target(&room)
	testing.expect_value(t, game.try_shadow_step(&room, .South, {1, 1}, beat), game.Action_Result.Moved)
	shadow_view_test_frame(renderer, &room, 0)
	testing.expect(t, s.steps == 2 && s.criticals == 1 && s.critical_at == renderer.sprite_assets.elapsed)
	landing := game.add_position(body, {2, 1})
	testing.expect_value(t, player.tactical.shadow_position, landing)

	// The shadow's own beats strike as its clock runs; the world's do not.
	world := player.tactical.beat_index
	for _ in 0..<200 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.05, true, false))
		shadow_view_test_frame(renderer, &room, 0.05)
	}
	testing.expect(t, game.tactical_shadow_due(&room))
	testing.expect_value(t, s.beats, u32(game.TACTICAL_SHADOW_BEATS))
	testing.expect(t, !s.beat_ahead)
	testing.expect_value(t, player.tactical.beat_index, world)
	testing.expect_value(t, living_clock(renderer, enemy), f64(10))

	// The rise: the body lands on the shadow's cell, still under the floor
	// while the landing plays, then climbs out with the rise's cue.
	before = capture_room_presentation(&room)
	testing.expect(t, game.tactical_end_shadow(&room))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	risen := renderer.sprite_assets.elapsed
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !s.active && s.rising && s.rise_paced)
	testing.expect_value(t, player.position, landing)
	testing.expect_value(t, snapshot.player.position, presentation_position(landing))
	testing.expect_value(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY), SHADOW_DEPTH)
	// The world goes on from the moment it stopped.
	testing.expect_value(t, tactical_world_time(renderer), f64(10))
	testing.expect(t, abs(s.held-(risen-10)) < 1e-9)
	for _ in 0..<200 {
		if !renderer_blocks_player_input(renderer) { break }
		shadow_view_test_frame(renderer, &room, 0.02)
		testing.expect_value(t, snapshot.player.position, presentation_position(landing))
	}
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !s.rising && !tactical_shadow_showing(renderer))
	testing.expect_value(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY), f32(0))
	testing.expect(t, abs(living_clock(renderer, enemy)-(10+renderer.sprite_assets.elapsed-risen)) < 1e-9)
	testing.expect(t, s.frozen == 0)
}

// Without the card's cues (a board that missed them) the pool sinks and
// rises on its own clock; the world's cues wait while the player is in his
// shadow, and the counts the lab hears by survive a new shadow.
@(test)
test_shadow_holds_the_world_cues_and_keeps_its_own_pace :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := shadow_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	update_tactical_view(renderer, &room, {}, false)
	enemy := game.enemy_entity(room.enemies[0].id)
	walk: game.Event_Log
	game.record_event(&walk, {kind = .Moved, source = enemy, target = enemy, from_position = {7, 1}, to_position = {6, 1}})
	testing.expect(t, begin_renderer_world_timeline(renderer, capture_room_presentation(&room), &walk))
	cue := &renderer.world_playback.cues[0].cue
	testing.expect(t, update_renderer_frame_timeline(renderer, 0.01) == false)
	walked := cue.elapsed
	testing.expect(t, walked > 0)

	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	update_tactical_view(renderer, &room, {}, false)
	s := &renderer.tactical.shadow
	testing.expect(t, s.active && !s.sink_paced)
	renderer.sprite_assets.elapsed += SHADOW_SINK_SECONDS*0.5
	update_tactical_view(renderer, &room, {}, false)
	half := tactical_shadow_depth(renderer, game.PLAYER_ENTITY)
	testing.expect(t, half > 0 && half < SHADOW_DEPTH)
	// The enemy's walk waits with the world.
	for _ in 0..<10 { update_renderer_frame_timeline(renderer, 0.05) }
	testing.expect_value(t, cue.elapsed, walked)
	testing.expect(t, renderer.frame_simulation_dt > 0)

	for _ in 0..<200 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.25, true, false))
	}
	testing.expect(t, game.tactical_end_shadow(&room))
	renderer.sprite_assets.elapsed += 1
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, s.rising && !s.rise_paced)
	testing.expect_value(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY), SHADOW_DEPTH)
	renderer.sprite_assets.elapsed += SHADOW_RISE_SECONDS+0.01
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !tactical_shadow_showing(renderer))
	// The world moves again, from the step it had reached.
	update_renderer_frame_timeline(renderer, 0.05)
	testing.expect(t, renderer.world_playback.count == 0 || renderer.world_playback.cues[0].cue.elapsed > walked)
	// A new shadow keeps the counts the lab hears by; a fresh board forgets
	// the shadow altogether.
	s.steps = 3
	room.player.tactical.phase = .Shadow
	room.player.tactical.shadow_remaining, room.player.tactical.shadow_duration = 4, 4
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, s.active && s.steps == 3)
	forget_living_actors(renderer)
	testing.expect(t, !s.active && s.steps == 0 && s.held == 0)
}

// A blow whose cue the world holds while the player is in his shadow gives
// one token: once it has dropped away the same blow, still showing, gives no
// second one until the world's own clock has moved on.
@(test)
test_shadow_held_blow_gives_a_single_token :: proc(t: ^testing.T) {
	state := new(Living_State)
	defer free(state)
	defer living_tokens_free(state)
	blow := game.Game_Event{kind = .Damaged, target = game.enemy_entity(3), source = game.PLAYER_ENTITY, amount = 4, pulse_count = 7}
	testing.expect(t, living_token_spawn(state, blow, false, 1, 1))
	for &token in state.tokens { if token.used { living_token_free(&token) } }
	// Seconds later on the sprite clock, the world still at the same moment.
	testing.expect(t, !living_token_spawn(state, blow, false, 4, 1.1))
	// The world moves on: a new blow of the same kind is a new token.
	testing.expect(t, living_token_spawn(state, blow, false, 6, 1+LIVING_TOKEN_SECONDS+0.1))
}

// A world cue aimed at the player that the shadow holds (a miss on him, its
// badge and sparks) stays where his body sank while the pool glides away;
// once he rises it is on him again, at the landing.
@(test)
test_shadow_holds_the_world_cues_on_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := shadow_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	update_tactical_view(renderer, &room, {}, false)
	body := player.position
	missed: game.Event_Log
	game.record_event(&missed, {kind = .Attack_Missed, source = game.enemy_entity(room.enemies[0].id), target = game.PLAYER_ENTITY,
		from_position = {7, 1}, to_position = body})
	testing.expect(t, begin_renderer_world_timeline(renderer, capture_room_presentation(&room), &missed))
	cue, found := renderer_active_cue_at(renderer, 0)
	testing.expect(t, found && cue.kind == .Attack_Missed)
	if !found { return }
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect_value(t, game.try_shadow_step(&room, .East), game.Action_Result.Moved)
	testing.expect(t, !game.tactical_tick(&room, game.TACTICAL_SHADOW_STEP_SECONDS, true, false))
	update_tactical_view(renderer, &room, {}, false)
	// The pool is a cell away; the miss is still where the body sank.
	pool := game.add_position(body, {1, 0})
	testing.expect_value(t, snapshot.player.position, presentation_position(pool))
	testing.expect_value(t, tactical_feedback_position(renderer, game.PLAYER_ENTITY, {}), rl.Vector3{f32(body.x)+0.5, 0.055, f32(body.y)+0.5})
	center, centered := presentation_event_center(renderer, cue.event)
	testing.expect(t, centered && center == tactical_project(renderer, {f32(body.x)+0.5, f32(body.y)+0.5}))
	// Risen on the shadow's cell, he carries it again.
	for _ in 0..<200 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.1, true, false))
	}
	testing.expect(t, game.tactical_end_shadow(&room))
	update_tactical_view(renderer, &room, {}, false)
	testing.expect_value(t, player.position, pool)
	testing.expect_value(t, tactical_feedback_position(renderer, game.PLAYER_ENTITY, {}), rl.Vector3{f32(pool.x)+0.5, 0.055, f32(pool.y)+0.5})
}

// The player's card keeps its room from the labels while it stands on the
// board, casting the card before it sinks, as any figure; down in its shadow,
// a dark hood in its pool, it keeps none (the CRITICO of a diagonal step sits
// just over the pool); sprung out at the end of the rise, it has it again.
@(test)
test_shadow_card_under_the_floor_keeps_no_room_from_the_labels :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := shadow_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	renderer.tactical.scene_3d = true
	renderer.tactical.labels = new(Tactical_Label_Layout)
	defer free(renderer.tactical.labels)
	reserved :: proc(renderer: ^Renderer) -> bool {
		renderer.tactical.labels^ = {}
		reserve_tactical_actor_label_bounds(renderer, &renderer.tactical.snapshot.player)
		return renderer.tactical.labels.actor_count == 1
	}
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, reserved(renderer))
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, tactical_shadow_showing(renderer) && reserved(renderer))
	renderer.sprite_assets.elapsed += SHADOW_SINK_SECONDS*0.25
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, tactical_shadow_depth(renderer, game.PLAYER_ENTITY) > 0 && !reserved(renderer))
	for _ in 0..<200 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.1, true, false))
	}
	testing.expect(t, game.tactical_end_shadow(&room))
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !reserved(renderer))
	// Out of the pool with its spring past the floor, before the rise ends.
	sprung := false
	for _ in 0..<100 {
		if !tactical_shadow_showing(renderer) { break }
		renderer.sprite_assets.elapsed += 0.01
		update_tactical_view(renderer, &room, {}, false)
		if tactical_shadow_showing(renderer) && tactical_shadow_depth(renderer, game.PLAYER_ENTITY) <= 0 {
			sprung = true
			testing.expect(t, reserved(renderer))
		}
	}
	testing.expect(t, sprung && !tactical_shadow_showing(renderer) && reserved(renderer))
}

// A walk back over the cells of the last one before the shadow, once the
// player has risen where it began (a teleport back), is a walk like any other:
// the card plays its clip and slides, and the boots sound.
@(test)
test_shadow_walk_after_the_rise_over_the_last_walk_is_a_walk :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := shadow_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	renderer.tactical.mechanics_lab = true
	renderer.tactical.living_state = new(Living_State)
	defer free(renderer.tactical.living_state)
	defer destroy_lab_sounds(renderer)
	lab_shadow_test_frame(renderer, &room, 0)
	sounds := renderer.tactical.lab_sounds
	walk :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, direction: game.Move_Direction) {
		before := capture_room_presentation(room)
		game.clear_event_log(&room.recent_events)
		testing.expect_value(t, game.try_move_player(room, direction), game.Action_Result.Moved)
		after := capture_room_presentation(room)
		testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
		lab_shadow_test_frame(renderer, room, 0.02)
	}
	// Until the world's answer has played and the player is free again.
	settle :: proc(renderer: ^Renderer, room: ^game.Room) {
		for _ in 0..<400 {
			for room.tactical_pulse.pending { if !game.continue_tactical_pulse(room) { break } }
			if !renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) &&
			   room.player.tactical.phase == .Decision && !room.tactical_pulse.pending { break }
			_ = game.tactical_tick(room, 0.02, true, false)
			lab_shadow_test_frame(renderer, room, 0.02)
		}
		for _ in 0..<80 { lab_shadow_test_frame(renderer, room, 0.02) }
	}
	footsteps :: proc(sounds: ^Lab_Sounds) -> int {
		return sounds.played[.Pilgrim_Move_Side]+sounds.played[.Pilgrim_Move_Up]+sounds.played[.Pilgrim_Move_Down]
	}
	start := player.position
	walk(t, renderer, &room, .East)
	testing.expect_value(t, footsteps(sounds), 1)
	settle(renderer, &room)
	// Into the shadow, a step back West, and the rise there.
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	for _ in 0..<200 {
		if !renderer_blocks_player_input(renderer) { break }
		lab_shadow_test_frame(renderer, &room, 0.02)
	}
	testing.expect_value(t, game.try_shadow_step(&room, .West), game.Action_Result.Moved)
	for _ in 0..<400 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.05, true, false))
		lab_shadow_test_frame(renderer, &room, 0.05)
	}
	before = capture_room_presentation(&room)
	testing.expect(t, game.tactical_end_shadow(&room))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	settle(renderer, &room)
	testing.expect_value(t, player.position, start)
	// East again, over the same two cells as the walk before the shadow.
	slot := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	testing.expect(t, slot != nil)
	if slot == nil { return }
	started := slot.started
	walk(t, renderer, &room, .East)
	lab_shadow_test_frame(renderer, &room, 0.02)
	testing.expect(t, slot.started != started && slot.sliding)
	testing.expect_value(t, footsteps(sounds), 2)
}
