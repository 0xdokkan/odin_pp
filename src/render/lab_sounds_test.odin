package render

import "core:testing"
import audio "../engine/audio"
import gfx "../engine/gfx"
import game "../game"
import level "../level"

// Every card has its own sound, and every character sounds its steps, hurts
// and fall.
@(test)
test_lab_sounds_cover_every_card_and_character :: proc(t: ^testing.T) {
	seen: [audio.Lab_Sfx]bool
	for card in game.Card_Id {
		if card == .Count { continue }
		sfx, ok := lab_card_sfx(card)
		testing.expectf(t, ok, "%v has no sound", card)
		testing.expectf(t, !seen[sfx], "%v shares its sound", card)
		seen[sfx] = true
	}
	for character in gfx.Flipbook_Character {
		for action in ([?]gfx.Living_Action{.Move_Side, .Move_Up, .Move_Down, .Hurt, .Hurt_Back, .Death}) {
			_, ok := lab_actor_sfx(character, action, .Damage, 1)
			testing.expectf(t, ok, "%v %v has no sound", character, action)
		}
		_, ok := lab_actor_sfx(character, gfx.living_resolve(character, .Attack), .Damage, 0)
		testing.expectf(t, ok, "%v's attack has no sound", character)
	}
	// The pilgrim's own steps differ by direction; a brute's long run charges.
	side, _ := lab_actor_sfx(.Pilgrim, .Move_Side, .Move, 1)
	up, _ := lab_actor_sfx(.Pilgrim, .Move_Up, .Move, 1)
	testing.expect(t, side != up)
	walk, _ := lab_actor_sfx(.Brute, .Move_Side, .Move, 1)
	charge, _ := lab_actor_sfx(.Brute, .Move_Side, .Move, 3)
	testing.expect(t, walk == .Brute_Move && charge == .Brute_Charge)
	// A blocked step only bumps; a blow stopped by the ward is the block.
	_, bumped := lab_actor_sfx(.Pilgrim, .Block, .Move_Blocked, 0)
	ward, blocked := lab_actor_sfx(.Pilgrim, .Block, .Damage_Absorbed, 0)
	testing.expect(t, !bumped && blocked && ward == .Pilgrim_Block)
	// The telegraphs and the daze have their loops' sounds.
	aim, aims := lab_base_sfx(.Archer, .Windup)
	daze, dazed := lab_base_sfx(.Pilgrim, .Stunned)
	testing.expect(t, aims && aim == .Archer_Aim && dazed && daze == .Pilgrim_Stunned)
	_, idle := lab_base_sfx(.Ghoul, .Idle)
	testing.expect(t, !idle)
	// The ambience is the one loop.
	for sfx in audio.Lab_Sfx { testing.expect(t, audio.LAB_SFX_LOOP[sfx] == (sfx == .Amb_Crypt_Loop)) }
}

// A cue showing for many frames sounds once; the same effect twice at once
// is one sound; what is due waits for its moment.
@(test)
test_lab_sounds_play_each_event_once_and_on_time :: proc(t: ^testing.T) {
	s: Lab_Sounds
	event := game.Game_Event{kind = .Card_Played, source = game.PLAYER_ENTITY, card_definition = .Tesla_Coil, card_id = 4}
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, event, 10))
	testing.expect(t, lab_sound_heard(&s, .Card_Played, event, 10.5))
	other := event
	other.card_id = 5
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, other, 10.5))
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, event, 10+LAB_SOUND_HEARD_SECONDS+0.1))
	lab_sound_queue(&s, .Ui_Gold, 1)
	lab_sound_queue(&s, .Ui_Gold, 1.01)
	lab_sound_queue(&s, .Ui_Energy, 1.01)
	lab_sound_queue(&s, .Ui_Gold, 1.2)
	testing.expect_value(t, s.count, 3)
	renderer: Renderer
	renderer.tactical.lab_sounds = &s
	renderer.sprite_assets.elapsed = 1.1
	play_lab_sounds(&renderer, nil, 0)
	testing.expect_value(t, s.count, 1)
	testing.expect(t, s.played[.Ui_Gold] == 1 && s.played[.Ui_Energy] == 1)
	renderer.sprite_assets.elapsed = 1.3
	play_lab_sounds(&renderer, nil, 0)
	testing.expect(t, s.count == 0 && s.played[.Ui_Gold] == 2)
}

// Outside the lab the board is silent.
@(test)
test_lab_sounds_only_in_the_lab :: proc(t: ^testing.T) {
	player: game.Player
	room := game.Room{player = &player, phase = .Combat}
	state: Living_State
	renderer: Renderer
	renderer.tactical.living_state = &state
	update_lab_sounds(&renderer, &room, 1)
	testing.expect(t, renderer.tactical.lab_sounds == nil)
	renderer.tactical.mechanics_lab = true
	snapshot: Room_Presentation
	renderer.tactical.snapshot = &snapshot
	update_lab_sounds(&renderer, &room, 1)
	testing.expect(t, renderer.tactical.lab_sounds != nil)
	destroy_lab_sounds(&renderer)
	testing.expect(t, renderer.tactical.lab_sounds == nil)
}

// The room's moments: the clock's beat, the window running out, the stun and
// the defence prompt.
@(test)
test_lab_sounds_hear_the_room :: proc(t: ^testing.T) {
	player: game.Player

	room := game.Room{player = &player, phase = .Combat}
	s: Lab_Sounds
	lab_watch_room(&s, &room, 0)
	testing.expect_value(t, s.count, 0)
	player.tactical.beat_index = 1
	lab_watch_room(&s, &room, 1)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Ui_Beat_Tick)
	player.tactical.phase, player.tactical.remaining = .Recovery, 2
	lab_watch_room(&s, &room, 2)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Window_End)
	player.tactical.phase = .Stunned
	lab_watch_room(&s, &room, 3)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Stun)
	room.qte.kind = .Defense
	lab_watch_room(&s, &room, 4)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Defense_Prompt)
}

// A card played sounds as that card, and the coil it sets down is not heard
// twice; a coil's discharge zaps once however many links it strikes.
@(test)
test_lab_sounds_of_cards_and_devices :: proc(t: ^testing.T) {
	renderer: Renderer
	snapshot: Room_Presentation
	renderer.tactical.snapshot = &snapshot
	s: Lab_Sounds
	impacts := 0
	played := Presentation_Cue{kind = .Card_Played, started = true,
		event = {kind = .Card_Played, source = game.PLAYER_ENTITY, card_definition = .Tesla_Coil}}
	lab_cue_sounds(&renderer, &s, &played, 1, &impacts)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Card_Tesla_Coil)
	coil := Presentation_Cue{kind = .Object_Spawned, started = true, event = {kind = .Object_Spawned, object_kind = .Tesla_Coil}}
	lab_cue_sounds(&renderer, &s, &coil, 1.2, &impacts)
	testing.expect_value(t, s.count, 1)
	lab_cue_sounds(&renderer, &s, &coil, 3, &impacts)
	testing.expect(t, s.count == 2 && s.queue[1].sfx == .World_Tesla_Deploy)
	zap := Presentation_Cue{kind = .Spell_Impact, started = true, event = {kind = .Spell_Impact, card_definition = .Tesla_Coil}}
	for _ in 0..<2 { lab_cue_sounds(&renderer, &s, &zap, 1, &impacts) }
	testing.expect_value(t, impacts, 2)
	boom := Presentation_Cue{kind = .Explosion, started = true, event = {kind = .Explosion, object_kind = .Barrel}}
	lab_cue_sounds(&renderer, &s, &boom, 1, &impacts)
	testing.expect(t, s.queue[s.count-1].sfx == .World_Barrel_Explosion)
	// Drawn cards are dealt one after the other.
	draw := Presentation_Cue{kind = .Card_Drawn, started = true, event = {kind = .Card_Drawn}}
	for _ in 0..<3 { lab_cue_sounds(&renderer, &s, &draw, 2, &impacts) }
	deals := 0
	for sound in s.queue[:s.count] { if sound.sfx == .Ui_Card_Draw { deals += 1 } }
	testing.expect_value(t, deals, 3)
	testing.expect(t, s.queue[s.count-1].at > s.queue[s.count-2].at)
}

// The charges' sounds wait for their blow: the Dado del Destino's die is
// heard as it shows, when the bump lands; RIFLESSO rings as the bolt it turns
// back reaches the player.
@(test)
test_lab_sounds_of_the_charges_wait_for_their_blow :: proc(t: ^testing.T) {
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	foe := game.enemy_entity(1)
	now := f64(5)
	renderer.sprite_assets.elapsed = now
	_, swung := play_attack_swing(renderer, game.PLAYER_ENTITY, foe, .Lantern, {2, 1})
	landing, pending := attack_fx_landing_in(renderer, foe, now, game.PLAYER_ENTITY)
	testing.expect(t, swung && pending && landing > 0)
	s: Lab_Sounds
	impacts := 0
	fate := Presentation_Cue{kind = .Fate_Rolled, started = true, event = {kind = .Fate_Rolled, source = game.PLAYER_ENTITY, target = foe}}
	lab_cue_sounds(renderer, &s, &fate, now, &impacts)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Ui_Fate_Die && abs(s.queue[0].at-(now+landing)) < 1e-9)
	archer := game.enemy_entity(2)
	_, flight, shot := play_attack_projectile(renderer, archer, game.PLAYER_ENTITY, .Bolt, {2, 2})
	testing.expect(t, shot && flight > 0)
	turned := Presentation_Cue{kind = .Attack_Deflected, started = true, event = {kind = .Attack_Deflected, source = archer, target = game.PLAYER_ENTITY}}
	lab_cue_sounds(renderer, &s, &turned, now, &impacts)
	testing.expect(t, s.count == 2 && s.queue[1].sfx == .Pilgrim_Deflect && abs(s.queue[1].at-(now+flight)) < 1e-6)
}

// A world cue with a sound of its own (a miss, energy...) still showing when
// the player sinks into his shadow is held with the world for the card and
// the four seconds, longer than a cue is remembered: it is heard once, not
// again in the shadow nor when the world goes on.
@(test)
test_lab_sounds_hear_a_cue_the_shadow_holds_once :: proc(t: ^testing.T) {
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
	// Both lanes, as the scene runs them: the world's cues hold in the shadow.
	frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
		renderer.sprite_assets.elapsed += f64(dt)
		update_renderer_frame_timeline(renderer, dt)
		update_tactical_view(renderer, room, {}, false)
		now := renderer.sprite_assets.elapsed
		living_observe(renderer, renderer.tactical.living_state, room, renderer.tactical.snapshot.player, .Pilgrim, now)
		update_lab_sounds(renderer, room, now)
		play_lab_sounds(renderer, nil, 0)
	}
	frame(renderer, &room, 0.01)
	sounds := renderer.tactical.lab_sounds
	world: game.Event_Log
	game.record_event(&world, {kind = .Attack_Missed, source = game.enemy_entity(room.enemies[0].id), target = game.PLAYER_ENTITY,
		from_position = {7, 1}, to_position = player.position})
	game.record_event(&world, {kind = .Energy_Gained, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, amount = 1})
	testing.expect(t, begin_renderer_world_timeline(renderer, capture_room_presentation(&room), &world))
	for _ in 0..<2 { frame(renderer, &room, 0.02) }
	testing.expect(t, sounds.played[.Ui_Miss] == 1 && sounds.played[.Ui_Energy] == 1)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	played := renderer.sprite_assets.elapsed
	for _ in 0..<400 {
		if game.tactical_shadow_due(&room) { break }
		if !renderer_blocks_player_input(renderer) { testing.expect(t, !game.tactical_tick(&room, 0.02, true, false)) }
		frame(renderer, &room, 0.02)
	}
	testing.expect(t, game.tactical_shadow_due(&room))
	testing.expect(t, renderer.sprite_assets.elapsed-played > LAB_SOUND_HEARD_SECONDS)
	testing.expect(t, sounds.played[.Ui_Miss] == 1 && sounds.played[.Ui_Energy] == 1)
	before = capture_room_presentation(&room)
	testing.expect(t, game.tactical_end_shadow(&room))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	for _ in 0..<150 { frame(renderer, &room, 0.02) }
	testing.expect(t, renderer.world_playback == nil || renderer.world_playback.count == 0)
	testing.expect_value(t, sounds.played[.Ui_Miss], 1)
	testing.expect_value(t, sounds.played[.Ui_Energy], 1)
}

// One frame of the board as the lab plays it: the view, the player's card
// reading its cues, then the lab's ears (the sounds are counted, not played).
lab_shadow_test_frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
	shadow_view_test_frame(renderer, room, dt)
	now := renderer.sprite_assets.elapsed
	living_observe(renderer, renderer.tactical.living_state, room, renderer.tactical.snapshot.player, .Pilgrim, now)
	update_lab_sounds(renderer, room, now)
	play_lab_sounds(renderer, nil, 0)
}

// Movimento Ombra played for real: the card sounds as itself; the sinking
// waits for the card to start going down and the rise for it to start
// climbing out, after the landing; each step of the shadow is its own soft
// sound, a diagonal on a beat also stings and its beats tick. The boots and
// the card's scrape never play: no step starts a clip on the card.
@(test)
test_lab_sounds_follow_the_shadow_never_its_footsteps :: proc(t: ^testing.T) {
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
	s := &renderer.tactical.shadow

	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	lab_shadow_test_frame(renderer, &room, 0.02)
	testing.expect(t, sounds.played[.Card_Shadow_Step] == 1 && sounds.played[.Pilgrim_Cast] == 1)
	// The room is in the shadow, the card not yet going down: no sinking yet.
	testing.expect(t, s.active && s.sink == 0 && sounds.played[.Pilgrim_Shadow_Sink] == 0)
	early := false
	for _ in 0..<100 {
		if s.sink > 0 { break }
		lab_shadow_test_frame(renderer, &room, 0.02)
		if s.sink <= 0 && sounds.played[.Pilgrim_Shadow_Sink] > 0 { early = true }
	}
	testing.expect(t, !early, "the sinking sounded before the card went down")
	testing.expect_value(t, sounds.played[.Pilgrim_Shadow_Sink], 1)
	waited := sounds.last_played[.Pilgrim_Shadow_Sink]-sounds.last_played[.Card_Shadow_Step]
	testing.expectf(t, waited > f64(PRESENTATION_CARD_PLAY_DURATION)-0.021 && waited < f64(PRESENTATION_CARD_PLAY_DURATION)+0.05,
		"the sinking sounded %.3f s after the card", waited)
	for _ in 0..<200 {
		if !renderer_blocks_player_input(renderer) { break }
		lab_shadow_test_frame(renderer, &room, 0.02)
	}

	// A step straight, then two keys on the shadow's first beat: a diagonal.
	testing.expect_value(t, game.try_shadow_step(&room, .East), game.Action_Result.Moved)
	lab_shadow_test_frame(renderer, &room, 0)
	testing.expect(t, sounds.played[.Pilgrim_Shadow_Step] == 1 && sounds.played[.Ui_Critical] == 0)
	for _ in 0..<40 {
		if game.tactical_shadow_beat_target(&room) != 0 { break }
		testing.expect(t, !game.tactical_tick(&room, 0.05, true, false))
		lab_shadow_test_frame(renderer, &room, 0.05)
	}
	beat := game.tactical_shadow_beat_target(&room)
	testing.expect_value(t, game.try_shadow_step(&room, .South, {1, 1}, beat), game.Action_Result.Moved)
	lab_shadow_test_frame(renderer, &room, 0)
	testing.expect(t, sounds.played[.Pilgrim_Shadow_Step] == 2 && sounds.played[.Ui_Critical] == 1)
	for _ in 0..<200 {
		if game.tactical_shadow_due(&room) { break }
		testing.expect(t, !game.tactical_tick(&room, 0.05, true, false))
		lab_shadow_test_frame(renderer, &room, 0.05)
	}
	testing.expect_value(t, sounds.played[.Ui_Beat_Tick], game.TACTICAL_SHADOW_BEATS)

	// The rise: the landing's cue first, then the card climbs out.
	before = capture_room_presentation(&room)
	testing.expect(t, game.tactical_end_shadow(&room))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	ended := renderer.sprite_assets.elapsed
	lab_shadow_test_frame(renderer, &room, 0)
	testing.expect(t, !s.active && s.rising && sounds.played[.Pilgrim_Shadow_Rise] == 0)
	early = false
	for _ in 0..<200 {
		if !renderer_blocks_player_input(renderer) { break }
		lab_shadow_test_frame(renderer, &room, 0.02)
		if s.rise <= 0 && sounds.played[.Pilgrim_Shadow_Rise] > 0 { early = true }
	}
	testing.expect(t, !early, "the rise sounded before the card climbed out")
	lab_shadow_test_frame(renderer, &room, 0.02)
	testing.expect(t, !tactical_shadow_showing(renderer))
	testing.expect_value(t, sounds.played[.Pilgrim_Shadow_Rise], 1)
	landed := sounds.last_played[.Pilgrim_Shadow_Rise]-ended
	testing.expectf(t, landed > f64(PRESENTATION_NOTICE_DURATION)-0.021, "the rise sounded %.3f s after the shadow ended", landed)
	testing.expect_value(t, sounds.played[.Pilgrim_Shadow_Sink], 1)
	testing.expect_value(t, sounds.played[.Pilgrim_Shadow_Step], 2)
	testing.expect_value(t, sounds.played[.Ui_Critical], 1)
	steps := sounds.played[.Pilgrim_Move_Side]+sounds.played[.Pilgrim_Move_Up]+sounds.played[.Pilgrim_Move_Down]+sounds.played[.Pilgrim_Dodge]
	testing.expect_value(t, steps, 0)
}
