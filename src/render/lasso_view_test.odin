package render

import "core:math"
import "core:testing"
import game "../game"
import grid "../grid"
import level "../level"

// An open room with space for the widest ring round the player (in the
// middle, with one Lazzo): the foe to throw it at three cells east, another
// on the ring a turn's eighth on; both held where they stand.
lasso_view_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> (room: game.Room) {
	rows := [?]string{
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#.....@.....#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#..........>#",
		"#############",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	made: bool
	player^, made = game.create_player({max_health = 40, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	_, added := game.add_owned_card(&player.deck, .Lasso)
	testing.expect(t, added)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {9, 6}, health = 30, attack = 1}, {position = {9, 3}, health = 30, attack = 1}}
	built: bool
	room, built = game.create_room(data, player, {enemies = enemies[:]})
	testing.expect(t, built)
	for &enemy in room.enemies {
		enemy.recovery_pulses = 999
		enemy.intent, enemy.tactical_cooldown = {}, 0
	}
	game.plan_enemy_intents(&room)
	return
}

// One frame of the spinning room, as the controller runs one: its clock and
// beats, the rope's seconds (each batch's cues to the world's playback), then
// the board.
lasso_view_test_frame :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, dt: f32) {
	game.tactical_tick(room, dt, true, false)
	for room.tactical_pulse.pending {
		before := capture_room_presentation(room)
		if !game.continue_tactical_pulse(room) { break }
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { begin_renderer_world_timeline(renderer, before, &room.recent_events, &after) }
	}
	for game.tactical_lasso_due(room) {
		before := capture_room_presentation(room)
		testing.expect(t, game.resolve_lasso_spin(room))
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { testing.expect(t, begin_renderer_world_timeline(renderer, before, &room.recent_events, &after)) }
	}
	shadow_view_test_frame(renderer, room, dt)
}

// The board follows the room's rope: the card stands while the loop flies and
// cinches, is lifted, then pulled onto its ring; there it flies where the
// room's angle puts it, every frame, the camera eased back for the widest
// ring; the hit on the other foe flashes one star; a dodge lets go and the
// card drops where the room put it, the camera easing home.
@(test)
test_lasso_view_follows_the_rope_of_the_room :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := lasso_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	update_tactical_view(renderer, &room, {}, false)
	l := &renderer.tactical.lasso
	testing.expect(t, !l.active && !l.ending)
	testing.expect_value(t, lasso_camera_pull(renderer), f32(0))
	swung := room.enemies[0].id
	foe := game.enemy_entity(swung)
	other := game.enemy_entity(room.enemies[1].id)

	// The throw: the card's cue, stretched over the cast.
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(foe))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	fit_card_cast_timeline(renderer, player.tactical.cast_duration)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, l.active && l.enemy == foe && l.throws == 1)
	testing.expect_value(t, l.radius, i32(4))
	testing.expect(t, l.throw < LASSO_THROW_FLOWN)
	testing.expect(t, tactical_lasso_holds(renderer, foe) && !tactical_lasso_holds(renderer, other))
	testing.expect_value(t, tactical_lasso_lift(renderer, foe), f32(0))
	// Caught where it stood, though the room has it on its ring already.
	shown, found := presentation_actor_in_view(&snapshot, foe)
	testing.expect(t, found)
	testing.expect_value(t, shown.position, presentation_position(grid.Position{9, 6}))
	testing.expect_value(t, room.enemies[0].position, grid.Position{10, 6})
	lifted, pulled := false, false
	for frame := 0; frame < 600 && (game.tactical_is_casting(&room) || renderer_blocks_player_input(renderer)); frame += 1 {
		lasso_view_test_frame(t, renderer, &room, 0.02)
		if l.throw < LASSO_THROW_LIFTED && tactical_lasso_lift(renderer, foe) > LASSO_LIFT*0.5 { lifted = true }
		shown, _ = presentation_actor_in_view(&snapshot, foe)
		if l.throw > LASSO_THROW_LIFTED && l.throw < 1 && shown.position.x > 9.05 { pulled = true }
	}
	testing.expect(t, !game.tactical_is_casting(&room) && !renderer_blocks_player_input(renderer))
	testing.expect(t, lifted && pulled, "the card is lifted, then pulled onto its ring")
	testing.expect_value(t, l.throw, f32(1))
	testing.expect_value(t, room.lasso.turns, i32(0))

	// The spin: the board shows the room's angle every frame.
	for frame := 0; frame < 600 && room.lasso.active && (l.spawned_hits == 0 || l.whirrs == 0); frame += 1 {
		lasso_view_test_frame(t, renderer, &room, 1.0/60.0)
		if !room.lasso.active { break }
		shown, _ = presentation_actor_in_view(&snapshot, foe)
		testing.expect_value(t, shown.position, lasso_orbit_point(room.lasso.centre, room.lasso.radius, game.lasso_angle(&room.lasso)))
		testing.expect(t, abs(tactical_lasso_lift(renderer, foe)-LASSO_LIFT) <= 0.031)
		testing.expect_value(t, tactical_lasso_lift(renderer, other), f32(0))
	}
	testing.expect(t, room.lasso.active)
	testing.expect_value(t, room.lasso.hits, i32(1))
	testing.expect_value(t, l.spawned_hits, 1)
	testing.expect_value(t, l.spawned_smashes, 0)
	testing.expect(t, l.whirrs == int(room.lasso.turns) && l.whirrs >= 1)
	testing.expect(t, lasso_camera_pull(renderer) > 0.95)
	testing.expect_value(t, string(lasso_hud_status(&room)), "LAZZO: COLPI 1 / PROSSIMO 2 / SCHIVA: LO MOLLI")
	testing.expect_value(t, string(lasso_hand_hint(&room)), "LAZZO / SHIFT+WASD: LO MOLLI")

	// A dodge lets go: slack, the card drops onto the cell the room put it on.
	testing.expect(t, game.try_dodge_player(&room, .West))
	testing.expect(t, !room.lasso.active)
	index, alive := game.enemy_index_by_id(&room, swung)
	testing.expect(t, alive)
	landed := room.enemies[index].position
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !l.active && l.ending && !l.died)
	testing.expect(t, l.releases == 1 && l.drops == 1)
	high := tactical_lasso_lift(renderer, foe)
	testing.expect(t, high > 0)
	for _ in 0..<5 { shadow_view_test_frame(renderer, &room, 0.02) }
	testing.expect(t, tactical_lasso_lift(renderer, foe) < high)
	for _ in 0..<20 { shadow_view_test_frame(renderer, &room, 0.02) }
	testing.expect(t, !l.ending && !tactical_lasso_holds(renderer, foe))
	testing.expect_value(t, tactical_lasso_lift(renderer, foe), f32(0))
	shown, _ = presentation_actor_in_view(&snapshot, foe)
	testing.expect_value(t, shown.position, presentation_position(landed))
	for _ in 0..<100 { shadow_view_test_frame(renderer, &room, 0.02) }
	testing.expect(t, lasso_camera_pull(renderer) < 0.01)
	testing.expect_value(t, l.throws, 1)
}

// The rope let go falls as the board shows what moved the player, MOLLATO over
// it and the slack heard with the fall: his dodge, the foreground's first cue,
// at once (not once the dodge has played, as the release's own cue would); a
// push in the world's beat whose walk waits for the brute's blow keeps the
// card hanging on the taut rope until that walk starts.
@(test)
test_lasso_lets_go_as_the_board_shows_the_move :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := lasso_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	l := &renderer.tactical.lasso
	foe := game.enemy_entity(room.enemies[0].id)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect_value(t, game.play_card(&room, player.deck.hand[0].id, game.entity_target(foe)).result, game.Card_Play_Result.Played)
	game.tactical_tick(&room, player.tactical.cast_remaining, true, false)
	for _ in 0..<30 { lasso_view_test_frame(t, renderer, &room, 1.0/60.0) }
	testing.expect(t, room.lasso.active && l.active && l.throw == 1 && l.releases == 0)
	// The dodge through the foreground, as the lane plays it.
	before := capture_room_presentation(&room)
	testing.expect(t, game.try_dodge_player(&room, .West))
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	update_tactical_view(renderer, &room, {}, false)
	// Not a frame of the dodge played yet: the card hangs on.
	testing.expect(t, l.active && !l.ending && l.releases == 0 && tactical_lasso_lift(renderer, foe) > 0)
	shadow_view_test_frame(renderer, &room, 1.0/60.0)
	testing.expect(t, !l.active && l.ending && !l.died && l.releases == 1 && l.released == renderer.sprite_assets.elapsed)
	// The release's own cue still waits behind the dodge's walk: the fall and
	// its MOLLATO did not.
	waiting := false
	for offset in 0..<renderer.timeline.count {
		cue, _ := presentation_cue_at(&renderer.timeline, offset)
		if cue.kind == .Lasso_Released { waiting = !cue.started }
	}
	testing.expect(t, waiting)
	cue := Presentation_Cue{kind = .Lasso_Released, started = true, event = {kind = .Lasso_Released, source = game.PLAYER_ENTITY, target = foe}}
	_, said := tactical_feedback_badges(renderer, &cue)
	testing.expect_value(t, said, 0)

	// A push in the world's beat: the player's walk waits for the blow.
	clear_event_timeline(&renderer.timeline)
	clear_renderer_world_playback(renderer)
	world := renderer.world_playback
	if !testing.expect(t, world != nil) { return }
	brute := game.enemy_entity(99)
	world.cues[0] = {cue = {kind = .Move, batch = 7, duration = 0.3, event = {kind = .Moved, source = brute, target = game.PLAYER_ENTITY}}, delay = 0.2}
	world.cues[1] = {cue = {kind = .Lasso_Released, batch = 7, started = true, duration = 0.16,
		event = {kind = .Lasso_Released, source = game.PLAYER_ENTITY, target = foe}}}
	world.count = 2
	testing.expect(t, lasso_release_waits(renderer, foe))
	world.cues[0].cue.started = true
	testing.expect(t, !lasso_release_waits(renderer, foe))
	// Another command's walk is no cause of this release; nor any, for another foe.
	world.cues[0].cue.started, world.cues[0].cue.batch = false, 6
	testing.expect(t, !lasso_release_waits(renderer, foe))
	world.cues[0].cue.batch = 7
	testing.expect(t, !lasso_release_waits(renderer, game.enemy_entity(98)))
	clear_renderer_world_playback(renderer)
}

// The HUD and the hand say a dodge lets the rope go only while one can be
// made (the window open, the dodge ready); at the window's end, in a stun or
// while the dodge recharges they say why not, and indeed no dodge goes. The
// plate's objective is the short one while the rope spins, the shrinking
// window's rule kept for when cards can be played.
@(test)
test_lasso_says_a_dodge_lets_go_only_when_one_can :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := lasso_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot := capture_room_presentation(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical = {enabled = true, snapshot = &snapshot}
	player.tactical.config.shrinking_window = true
	testing.expect_value(t, string(tactical_hud_objective(renderer, &room)), "MAX 20s / CARTE 0/6 / NEMICI 2")
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(room.enemies[0].id)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	game.tactical_tick(&room, player.tactical.cast_remaining, true, false)
	testing.expect(t, game.tactical_lasso_active(&room) && !game.tactical_is_casting(&room))
	testing.expect_value(t, string(tactical_hud_objective(renderer, &room)), "NEMICI 2")
	dodges :: proc(room: ^game.Room) -> bool { return game.tactical_dodge_ready(room) && game.tactical_allows_action(room, true) }
	Said :: struct {phase: game.Tactical_Phase, recovery: int, prompt: bit_set[game.Defense_Mode], status, hint: string}
	cases := [?]Said{
		{.Decision, 2, {}, "LAZZO: COLPI 0 / PROSSIMO 1 / SCHIVA FRA 2", "LAZZO / SCHIVA FRA 2"},
		{.Recovery, 0, {}, "LAZZO: COLPI 0 / PROSSIMO 1 / IN RECUPERO", "LAZZO / IN RECUPERO"},
		{.Stunned, 0, {}, "LAZZO: COLPI 0 / PROSSIMO 1 / STORDITO", "LAZZO / STORDITO"},
		// The defence prompt: its own dodge lets go, when it offers one.
		{.Resolving, 0, {.Block, .Dodge}, "LAZZO: COLPI 0 / PROSSIMO 1 / SCHIVA: LO MOLLI", "LAZZO / E, POI WASD: LO MOLLI"},
		{.Resolving, 0, {.Block}, "LAZZO: COLPI 0 / PROSSIMO 1 / DIFESA", "LAZZO / DIFESA"},
		{.Decision, 0, {}, "LAZZO: COLPI 0 / PROSSIMO 1 / SCHIVA: LO MOLLI", "LAZZO / SHIFT+WASD: LO MOLLI"},
	}
	for said in cases {
		player.tactical.phase, player.tactical.dodge_recovery = said.phase, said.recovery
		room.qte = {}
		if said.prompt != {} { room.qte = {kind = .Defense, enemy_id = room.enemies[1].id, defenses = said.prompt, remaining = 1} }
		testing.expect_value(t, string(lasso_hud_status(&room)), said.status)
		testing.expect_value(t, string(lasso_hand_hint(&room)), said.hint)
		way, _ := lasso_let_go(&room)
		testing.expect_value(t, way == .Dodge, dodges(&room))
		if way != .Dodge { testing.expect(t, !game.try_dodge_player(&room, .West) && room.lasso.active) }
	}
	room.qte = {}
	// (The lab's smoke measures the line with the game's font, in either window.)
	testing.expect(t, game.try_dodge_player(&room, .West) && !room.lasso.active)
}

// The throw's moments: the card stands while the loop flies and cinches,
// springs up past its height, is pulled on a raised curve, and ends on its
// ring at the height it keeps.
@(test)
test_lasso_throw_pose_stands_lifts_and_pulls :: proc(t: ^testing.T) {
	from := presentation_position(grid.Position{9, 6})
	orbit := lasso_orbit_point({6, 6}, 4, 0)
	testing.expect_value(t, orbit, presentation_position(grid.Position{10, 6}))
	at, lift := lasso_throw_pose(from, orbit, 0)
	testing.expect(t, at == from && lift == 0)
	at, lift = lasso_throw_pose(from, orbit, LASSO_THROW_CINCHED-0.01)
	testing.expect(t, at == from && lift == 0)
	_, lift = lasso_throw_pose(from, orbit, (LASSO_THROW_CINCHED+LASSO_THROW_LIFTED)*0.5)
	testing.expect(t, lift > LASSO_LIFT*0.5)
	at, lift = lasso_throw_pose(from, orbit, (LASSO_THROW_LIFTED+1)*0.5)
	testing.expect(t, at.x > from.x && at.x < orbit.x && lift > LASSO_LIFT)
	at, lift = lasso_throw_pose(from, orbit, 1)
	testing.expect(t, at == orbit && lift == LASSO_LIFT)
	// A quarter turn on (counter-clockwise on the board: north).
	north := lasso_orbit_point({6, 6}, 4, -math.PI/2)
	testing.expect(t, abs(north.x-6) < 1e-5 && abs(north.y-2) < 1e-5)
}

// The floor ring's bake: a dashed pixel circle at the radius (paper on it, ink
// either side), nothing anywhere else; the arc over a solid cell left out, red
// ticks where the free ring meets it.
@(test)
test_lasso_ring_bake_dashes_the_radius_and_leaves_walls_out :: proc(t: ^testing.T) {
	arcs, count := game.lasso_ring(2)
	testing.expect_value(t, count, 16)
	solid: [game.LASSO_MAX_RING_CELLS]bool
	pixels, size := lasso_ring_pixels(2, arcs[:count], solid[:count], context.temp_allocator)
	testing.expect_value(t, size, 5*LASSO_RING_TEXELS)
	T := f32(LASSO_RING_TEXELS)
	half := f32(size)*0.5
	paper_rgb := [3]u8{LIVING_TOKEN_PAPER.r, LIVING_TOKEN_PAPER.g, LIVING_TOKEN_PAPER.b}
	ink_rgb := [3]u8{LIVING_TOKEN_INK.r, LIVING_TOKEN_INK.g, LIVING_TOKEN_INK.b}
	red_rgb := [3]u8{LASSO_SMASH_RED.r, LASSO_SMASH_RED.g, LASSO_SMASH_RED.b}
	paper, ink := 0, 0
	for y in 0..<size {
		for x in 0..<size {
			at := (y*size+x)*4
			if pixels[at+3] == 0 { continue }
			u, w := (f32(x)+0.5-half)/T, (f32(y)+0.5-half)/T
			e := abs(math.sqrt(u*u+w*w)-2)*T
			testing.expectf(t, e <= 2, "a pixel off the ring at %d, %d", x, y)
			colour := [3]u8{pixels[at], pixels[at+1], pixels[at+2]}
			if colour == paper_rgb { paper += 1; testing.expect(t, e <= 1) }
			if colour == ink_rgb { ink += 1; testing.expect(t, e > 1) }
		}
	}
	testing.expect(t, paper > 0 && ink > 0)
	// Dashed: about two thirds of the circle's length is paper.
	circle := 2*math.PI*2*T
	testing.expect(t, f32(paper) > circle*0.5 && f32(paper) < circle*1.5)

	// South (+y) is a wall: no paper over its arc, red at its two ends.
	south, _ := game.lasso_locate(arcs[:count], math.PI/2)
	testing.expect_value(t, arcs[south].cell, grid.Position{0, 2})
	solid[south] = true
	walled, walled_size := lasso_ring_pixels(2, arcs[:count], solid[:count], context.temp_allocator)
	testing.expect_value(t, walled_size, size)
	red := 0
	for y in 0..<size {
		for x in 0..<size {
			at := (y*size+x)*4
			if walled[at+3] == 0 { continue }
			colour := [3]u8{walled[at], walled[at+1], walled[at+2]}
			if colour == red_rgb { red += 1; continue }
			theta := game.lasso_wrap(f64(math.atan2((f32(y)+0.5-half)/T, (f32(x)+0.5-half)/T)))
			arc, _ := game.lasso_locate(arcs[:count], theta)
			testing.expectf(t, arc != south, "the walled arc still shows at %d, %d", x, y)
		}
	}
	testing.expect(t, red >= 8, "the free ring's two ends at the wall are marked")
}

// The floor ring's bake is kept for its key: every arc counts in it, at every
// radius, so a ring whose solid cells differ anywhere (or another centre, or
// radius) bakes afresh, never reusing a stale picture.
@(test)
test_lasso_ring_key_tells_every_ring_apart :: proc(t: ^testing.T) {
	for radius in i32(1)..=game.LASSO_MAX_RADIUS {
		count := 8*int(radius)
		solid: [game.LASSO_MAX_RING_CELLS]bool
		free := lasso_ring_key({5, 5}, radius, solid[:count])
		testing.expect(t, free != lasso_ring_key({5, 6}, radius, solid[:count]) && free != lasso_ring_key({6, 5}, radius, solid[:count]))
		if radius > 1 { testing.expect(t, free != lasso_ring_key({5, 5}, radius-1, solid[:8*int(radius-1)])) }
		for arc in 0..<count {
			solid[arc] = true
			one := lasso_ring_key({5, 5}, radius, solid[:count])
			testing.expectf(t, one != free, "radius %d: arc %d solid keys as no solid", radius, arc)
			for other in 0..<arc {
				solid[other] = true
				two := lasso_ring_key({5, 5}, radius, solid[:count])
				testing.expectf(t, two != one && two != free, "radius %d: arcs %d and %d key as fewer", radius, other, arc)
				solid[other] = false
			}
			solid[arc] = false
		}
	}
}

// The card's words and the preview of its upgrade (its icon: card_icons_test).
@(test)
test_lasso_card_reads_its_hits_and_turns :: proc(t: ^testing.T) {
	testing.expect_value(t, string(card_short_name(.Lasso)), "LAZZO")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Lasso}, true)), "PRIMO COLPO 1 -> 2")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Lasso, upgrade_level = 4}, true)), "PRIMO COLPO 5 -> 6")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Lasso, upgrade_level = game.LASSO_MAX_UPGRADE_LEVEL}, true)), "MAX UPGRADE")
	first, second := gothic_card_lines({definition_id = .Lasso}, true)
	testing.expect_value(t, string(first), "COLPI 1, 2, 3...")
	testing.expect_value(t, string(second), "-1 VITA A OGNI GIRO")
}

// The lab hears the rope with its own sounds: the card, the throw at once and
// the loop cinching as it lands round the foe, a hit or a smash, a whirr for
// each full turn that climbs as the spin speeds up (to its top at the
// fourteenth), and the slack and the drop of a release.
@(test)
test_lasso_lab_sounds_follow_the_rope :: proc(t: ^testing.T) {
	player: game.Player
	room := game.Room{player = &player, phase = .Combat}
	state: Living_State
	snapshot: Room_Presentation
	renderer: Renderer
	renderer.tactical.living_state = &state
	renderer.tactical.snapshot = &snapshot
	renderer.tactical.mechanics_lab = true
	defer destroy_lab_sounds(&renderer)
	foe := game.enemy_entity(3)
	s: Lab_Sounds
	impacts := 0
	caught := Presentation_Cue{kind = .Lasso_Caught, started = true, duration = 2,
		event = {kind = .Lasso_Caught, source = game.PLAYER_ENTITY, target = foe, card_definition = .Lasso}}
	card, carded := lab_card_sfx(.Lasso)
	testing.expect(t, carded && card == .Card_Lasso)
	lab_cue_sounds(&renderer, &s, &caught, 1, &impacts)
	testing.expect_value(t, s.count, 2)
	testing.expect(t, s.queue[0].sfx == .Pilgrim_Lasso_Throw && s.queue[0].at == 1)
	testing.expect(t, s.queue[1].sfx == .World_Lasso_Wrap && abs(s.queue[1].at-(1+2*f64(LASSO_THROW_FLOWN))) < 1e-6)
	hit := Presentation_Cue{kind = .Lasso_Struck, started = true,
		event = {kind = .Lasso_Struck, source = foe, target = game.enemy_entity(4), amount = 1, card_definition = .Lasso}}
	lab_cue_sounds(&renderer, &s, &hit, 3, &impacts)
	testing.expect(t, s.count == 3 && s.queue[2].sfx == .World_Lasso_Hit)
	smash := Presentation_Cue{kind = .Lasso_Struck, started = true,
		event = {kind = .Lasso_Struck, source = foe, target = game.SYSTEM_ENTITY, amount = 2, card_definition = .Lasso}}
	lab_cue_sounds(&renderer, &s, &smash, 3.5, &impacts)
	testing.expect(t, s.count == 4 && s.queue[3].sfx == .World_Lasso_Smash)
	testing.expect(t, lab_whirr_pitch(0) == LAB_WHIRR_PITCH && lab_whirr_pitch(40) == lab_whirr_pitch(LAB_WHIRR_TURNS))
	testing.expect(t, lab_whirr_pitch(LAB_WHIRR_TURNS) > lab_whirr_pitch(LAB_WHIRR_TURNS-1))

	update_lab_sounds(&renderer, &room, 1)
	heard := renderer.tactical.lab_sounds
	if !testing.expect(t, heard != nil) { return }
	testing.expect_value(t, heard.count, 0)
	l := &renderer.tactical.lasso
	l.enemy, l.whirrs, l.turns = foe, 1, 1
	update_lab_sounds(&renderer, &room, 2)
	testing.expect(t, heard.count == 1 && heard.queue[0].sfx == .World_Lasso_Whirr)
	low := heard.queue[0].pitch
	l.whirrs, l.turns = 2, 6
	update_lab_sounds(&renderer, &room, 3)
	testing.expect(t, heard.count == 2 && heard.queue[1].sfx == .World_Lasso_Whirr && heard.queue[1].pitch > low)
	l.releases = 1
	update_lab_sounds(&renderer, &room, 4)
	testing.expect(t, heard.count == 3 && heard.queue[2].sfx == .World_Lasso_Release)
	// Nothing new: nothing heard again.
	update_lab_sounds(&renderer, &room, 5)
	testing.expect_value(t, heard.count, 3)
}

// A full turn's 1 shakes no card and pops a small token at once, beside no
// other; the rope's hits hurt the struck card but are no blow the pivot swings;
// the throw is his cast (arm up, no lantern blow and back flip).
@(test)
test_lasso_turns_pop_small_tokens_and_shake_nothing :: proc(t: ^testing.T) {
	foe := game.enemy_entity(3)
	turn := Presentation_Cue{kind = .Damage, started = true, event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = foe,
		amount = game.LASSO_TURN_DAMAGE, area_mask = game.EVENT_LASSO_BIT|game.EVENT_LASSO_TURN_BIT}}
	testing.expect(t, game.event_is_lasso(turn.event) && game.event_is_lasso_turn(turn.event))
	_, shaken := living_cue_action(&turn, foe)
	_, swung := living_cue_action(&turn, game.PLAYER_ENTITY)
	testing.expect(t, !shaken && !swung)
	hit := turn
	hit.event.area_mask, hit.event.amount = game.EVENT_LASSO_BIT, 2
	testing.expect(t, game.event_is_lasso(hit.event) && !game.event_is_lasso_turn(hit.event))
	action, hurt := living_cue_action(&hit, foe)
	testing.expect(t, hurt && action == .Hurt)
	_, attacked := living_cue_action(&hit, game.PLAYER_ENTITY)
	testing.expect(t, !attacked)
	throw := Presentation_Cue{kind = .Lasso_Caught, started = true, event = {kind = .Lasso_Caught, source = game.PLAYER_ENTITY, target = foe}}
	swing, thrown := living_cue_action(&throw, game.PLAYER_ENTITY)
	testing.expect(t, thrown && swing == .Cast)
	// His cast's own sound is the card's: the throw sounds with its own.
	_, voiced := lab_actor_sfx(.Pilgrim, swing, .Lasso_Caught, 0)
	testing.expect(t, !voiced)
	_, caught := living_cue_action(&throw, foe)
	testing.expect(t, !caught)

	state := new(Living_State)
	defer free(state)
	defer living_tokens_free(state)
	testing.expect(t, living_token_spawn(state, hit.event, false, 1))
	testing.expect(t, living_token_spawn(state, turn.event, false, 1, small = true))
	later := hit.event
	later.amount = 3
	testing.expect(t, living_token_spawn(state, later, false, 1.2))
	found := 0
	for token in state.tokens {
		if !token.used { continue }
		found += 1
		switch token.amount {
		case 2: testing.expect(t, !token.small && token.stack == 0 && token.born == 1+LIVING_TOKEN_DELAY)
		case 1: testing.expect(t, token.small && token.stack == 0 && token.born == 1)
		case 3: testing.expect(t, !token.small && token.stack == 1)
		}
	}
	testing.expect_value(t, found, 3)
}
