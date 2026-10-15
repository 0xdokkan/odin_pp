package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import audio "../engine/audio"
import game "../game"
import grid "../grid"
import level "../level"

// An open room, the player in the middle with one Pinball, the foe to strike
// beside him to the east and a bumper three cells further east; both held.
pinball_view_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> (room: game.Room) {
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
	_, added := game.add_owned_card(&player.deck, .Pinball)
	testing.expect(t, added)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1, archetype = .Archer}, {position = {10, 6}, health = 40, attack = 1}}
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

// One frame of the room, as the controller runs one: its clock and beats, the
// ball's seconds rolled out (each batch's cues to the world's playback), then
// the board.
pinball_view_test_frame :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, dt: f32) {
	// A window run out ends as the controller's own command ends it.
	if game.tactical_tick(room, dt, true, false) {
		before := capture_room_presentation(room)
		if game.tactical_expire_window(room) {
			after := capture_room_presentation(room)
			if room.recent_events.count > 0 { begin_renderer_world_timeline(renderer, before, &room.recent_events, &after) }
		}
	}
	for room.tactical_pulse.pending {
		before := capture_room_presentation(room)
		if !game.continue_tactical_pulse(room) { break }
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { begin_renderer_world_timeline(renderer, before, &room.recent_events, &after) }
	}
	for game.tactical_pinball_due(room) {
		before := capture_room_presentation(room)
		testing.expect(t, game.resolve_pinball_roll(room))
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { testing.expect(t, begin_renderer_world_timeline(renderer, before, &room.recent_events, &after)) }
	}
	shadow_view_test_frame(renderer, room, dt)
}

// The board follows the room's ball: the foe's card shows until the making's
// hide, then the ball swells past its size and settles; the swing is set at
// the strike's cue to land as the cast ends, while the world and the ball
// stand still; then the snapshot shows the foe where the ball rolls, every
// frame, a star for each contact; at its time it bursts, and its foe's card
// never shows again.
@(test)
test_pinball_view_follows_the_ball_of_the_room :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := pinball_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	update_tactical_view(renderer, &room, {}, false)
	b := &renderer.tactical.pinball
	testing.expect(t, !b.active && !tactical_pinball_holds(renderer, game.enemy_entity(room.enemies[0].id)))
	foe := game.enemy_entity(room.enemies[0].id)
	bumper := room.enemies[1].id
	// The strike: the card's cues, stretched over the cast.
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(foe))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	fit_card_cast_timeline(renderer, player.tactical.cast_duration)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, b.active && b.enemy == foe && b.made_paced && b.made == 0 && b.makes == 1 && b.archetype == .Archer)
	testing.expect(t, !tactical_pinball_holds(renderer, foe) && pinball_card_opacity(renderer, foe) == 1)
	scale, _ := pinball_ball_scale(b, renderer.sprite_assets.elapsed)
	testing.expect_value(t, scale, f32(0))
	lanterns := renderer.tactical.attack_fx.spawned[.Lantern]
	hidden, swelled, faded := false, false, false
	cast_end := f64(-1)
	for frame := 0; frame < 600 && (game.tactical_is_casting(&room) || renderer_blocks_player_input(renderer)); frame += 1 {
		was_casting := game.tactical_is_casting(&room)
		pinball_view_test_frame(t, renderer, &room, 1.0/60.0)
		if was_casting && !game.tactical_is_casting(&room) { cast_end = renderer.sprite_assets.elapsed }
		if tactical_pinball_holds(renderer, foe) { hidden = true }
		opacity := pinball_card_opacity(renderer, foe)
		if opacity > 0.05 && opacity < 0.95 { faded = true }
		if size, _ := pinball_ball_scale(b, renderer.sprite_assets.elapsed); size > 1.05 { swelled = true }
		// The world, and the ball, stand still through the cast.
		if game.tactical_is_casting(&room) { testing.expect(t, room.pinball.run == 0 && room.pinball.pending == 0) }
	}
	testing.expect(t, hidden && swelled && faded, "the card fades, the ball swells past its size")
	testing.expect(t, b.made == 1 && b.struck && b.strikes == 1)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Lantern], lanterns+1)
	testing.expect(t, cast_end > 0 && abs(b.contact-cast_end) <= 1.5/60.0, "the swing lands as the cast ends")
	scale, _ = pinball_ball_scale(b, renderer.sprite_assets.elapsed)
	testing.expect_value(t, scale, f32(1))
	// The roll, straight east into the bumper: the board shows the room's ball
	// every frame, its card held, its heart gone; a star a contact.
	room.pinball.heading = {1, 0}
	testing.expect_value(t, room.pinball.run, f64(0))
	for _ in 0..<90 {
		pinball_view_test_frame(t, renderer, &room, 1.0/60.0)
		if !room.pinball.active { break }
		p := game.pinball_position(&room.pinball)
		shown, found := presentation_actor_in_view(&snapshot, foe)
		testing.expect(t, found && abs(shown.position.x-f32(p.x)) < 1e-4 && abs(shown.position.y-f32(p.y)) < 1e-4)
		testing.expect(t, tactical_pinball_holds(renderer, foe) && !living_heart_shown(renderer, shown^))
		testing.expect(t, !tactical_pinball_holds(renderer, game.enemy_entity(bumper)))
		testing.expect_value(t, b.bumps, int(room.pinball.hits))
		testing.expect_value(t, b.bounces, int(room.pinball.bounces))
	}
	testing.expect(t, room.pinball.hits >= 1 && room.pinball.bounces >= 1)
	used := 0
	for impact in b.impacts { if impact.used { used += 1 } }
	testing.expect(t, used >= 3, "the strike's star, the bumper's and the wall's")
	// The rest of its time, and its burst.
	for _ in 0..<400 {
		if !room.pinball.active { break }
		pinball_view_test_frame(t, renderer, &room, 0.1)
	}
	testing.expect(t, !room.pinball.active)
	_, alive := game.enemy_index_by_id(&room, foe.id)
	testing.expect(t, !alive)
	testing.expect(t, b.ending && b.dead && b.bursts == 1 && tactical_pinball_holds(renderer, foe))
	swell, flash := pinball_ball_scale(b, renderer.sprite_assets.elapsed)
	testing.expect(t, swell >= 1 && flash >= 0)
	for _ in 0..<60 { shadow_view_test_frame(renderer, &room, 1.0/60.0) }
	testing.expect(t, !b.ending && b.dead && tactical_pinball_holds(renderer, foe) && b.bursts == 1)
	scale, _ = pinball_ball_scale(b, renderer.sprite_assets.elapsed)
	testing.expect_value(t, scale, f32(0))
	// A foe of the same id alive again (a new room's) is a card of its own.
	other := room.enemies[0]
	other.id, other.position = foe.id, {3, 3}
	append(&room.enemies, other)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !b.dead && !tactical_pinball_holds(renderer, foe))
}

// A board that first sees the ball after its strike (a fresh board) shows it
// made and struck: no swing set again, no card back.
@(test)
test_pinball_view_on_a_fresh_board_shows_the_ball_as_it_is :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := pinball_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	foe := game.enemy_entity(room.enemies[0].id)
	testing.expect_value(t, game.play_card(&room, player.deck.hand[0].id, game.entity_target(foe)).result, game.Card_Play_Result.Played)
	game.tactical_tick(&room, player.tactical.cast_remaining, true, false)
	b := &renderer.tactical.pinball
	lanterns := renderer.tactical.attack_fx.spawned[.Lantern]
	for _ in 0..<10 { pinball_view_test_frame(t, renderer, &room, 1.0/60.0) }
	testing.expect(t, b.active && b.made == 1 && b.struck && b.launched && tactical_pinball_holds(renderer, foe))
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Lantern], lanterns)
	// The fight over with the ball still rolling (the player fallen): its
	// card is back on its cell, no burst.
	room.phase = .Defeat
	game.tactical_end_combat(&room)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !b.active && !b.ending && !b.dead && b.bursts == 0 && !tactical_pinball_holds(renderer, foe))
}

pinball_test_pixel :: proc(pixels: []u8, x, y: int) -> rl.Color {
	at := (y*PINBALL_SPRITE+x)*4
	return {pixels[at], pixels[at+1], pixels[at+2], pixels[at+3]}
}

// The ball's sprite: steel in six tones inside an ink line, the white paper
// round it, its ink cut and the cut edge's shadow down and to the right only;
// a band of the foe's colour that moves as its axis turns.
@(test)
test_pinball_sprite_is_steel_in_white_paper :: proc(t: ^testing.T) {
	pixels: [PINBALL_SPRITE*PINBALL_SPRITE*4]u8
	band := pinball_band_color(.Archer)
	pinball_ball_pixels(band, {0, 1, 0}, pixels[:])
	row := PINBALL_SPRITE/2
	// Along the middle row, right of the centre (34.5): steel, its ink line,
	// paper, the cut.
	testing.expect_value(t, pinball_test_pixel(pixels[:], 64, row), LIVING_TOKEN_INK)
	testing.expect_value(t, pinball_test_pixel(pixels[:], 66, row), LIVING_TOKEN_PAPER)
	testing.expect_value(t, pinball_test_pixel(pixels[:], 67, row), LIVING_TOKEN_PAPER)
	testing.expect_value(t, pinball_test_pixel(pixels[:], 68, row), LIVING_TOKEN_INK)
	// The cut edge shows down and to the right, never up and to the left.
	testing.expect(t, pinball_test_pixel(pixels[:], 59, 59).a == 255)
	testing.expect(t, pinball_test_pixel(pixels[:], 10, 10).a == 0)
	// Above its middle steel; round its middle, with this axis, its band of
	// the foe's colour.
	upper := pinball_test_pixel(pixels[:], 34, 14)
	steel := false
	for tone in PINBALL_STEEL { steel = steel || tone == upper }
	testing.expect(t, steel)
	coloured := 0
	for y in 0..<PINBALL_SPRITE {
		for x in 0..<PINBALL_SPRITE {
			c := pinball_test_pixel(pixels[:], x, y)
			if c.a == 0 || c == LIVING_TOKEN_INK || c == LIVING_TOKEN_PAPER || c == LIVING_TOKEN_EDGE || c == rl.WHITE { continue }
			known := false
			for tone in PINBALL_STEEL { known = known || tone == c }
			if !known && c.b > c.r { coloured += 1 }
		}
	}
	testing.expect(t, coloured > 100, "the archer's blue band")
	// Turned, the band crosses the middle elsewhere: above the centre it is
	// steel with the band round a horizontal axis, band with a vertical one.
	upright: [PINBALL_SPRITE*PINBALL_SPRITE*4]u8
	pinball_ball_pixels(band, {1, 0, 0}, upright[:])
	above := pinball_test_pixel(pixels[:], 34, 14)
	crossed := pinball_test_pixel(upright[:], 34, 14)
	testing.expect(t, above != crossed)
	testing.expect(t, crossed.b > crossed.r)
}

// The card's words, its upgrade's preview, its inspector's rules, the HUD's
// chip and the hand's hints.
@(test)
test_pinball_card_reads_its_value_and_the_wall :: proc(t: ^testing.T) {
	first, second := gothic_card_lines({definition_id = .Pinball}, true)
	testing.expect_value(t, string(first), "COLPI 2, 3, 4...")
	testing.expect_value(t, string(second), "MURO: TORNA A 2 / 20s")
	first, second = gothic_card_lines({definition_id = .Pinball, upgrade_level = 3}, true)
	testing.expect_value(t, string(first), "COLPI 5, 6, 7...")
	testing.expect_value(t, string(second), "MURO: TORNA A 5 / 20s")
	first, second = gothic_card_lines({definition_id = .Pinball})
	testing.expect_value(t, string(first), "COLPI 2, 3, 4...")
	testing.expect_value(t, string(second), "SOLO TATTICA")
	short_first, short_second, short := gothic_card_narrow_lines({definition_id = .Pinball}, true)
	testing.expect(t, short && string(short_first) == "COLPI 2, 3..." && string(short_second) == "MURO: 2 / 20s")
	// Its name holds on a narrow card as it is.
	_, renamed := gothic_card_narrow_name(.Pinball)
	testing.expect(t, !renamed)
	detail_first, detail_second := card_detail_lines({definition_id = .Pinball, upgrade_level = 2})
	testing.expect(t, string(detail_first) == "COLPI 4, 5, 6..." && string(detail_second) == "SOLO TATTICA")
	testing.expect_value(t, string(card_short_name(.Pinball)), "PINBALL")
	// Its own icon (the atlas's cell 25), in the steel cards' accent.
	testing.expect_value(t, gothic_card_icon(.Pinball), 25)
	testing.expect_value(t, gothic_card_accent(.Pinball), gothic_card_accent(.Guard))
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Pinball}, true)), "VALORE 2 -> 3")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Pinball, upgrade_level = 4}, true)), "VALORE 6 -> 7")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Pinball, upgrade_level = game.PINBALL_MAX_UPGRADE_LEVEL}, true)), "MAX UPGRADE")
	definition, _ := game.card_definition_by_id(.Pinball, true)
	reaction, rule := tactical_card_inspector_rules({definition_id = .Pinball}, definition)
	testing.expect_value(t, string(reaction), "BOSS E MINIBOSS: TROPPO PESANTI")
	testing.expect_value(t, string(rule), "DOPO 20s SCOPPIA E CADE")
	testing.expect_value(t, string(pinball_chip_text(14, 5, false)), "PINBALL 14s x5")
	testing.expect_value(t, string(pinball_chip_text(13.2, 5, true)), "PIN 14s x5")
	testing.expect_value(t, string(pinball_chip_text(game.PINBALL_SECONDS, 2, false)), "PINBALL 20s x2")
	testing.expect_value(t, string(pinball_chip_text(0.4, 3, false)), "PINBALL 1s x3")
	data: level.Level
	player: game.Player
	room := pinball_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	_, shown := pinball_chip(&room, false)
	testing.expect(t, !shown)
	testing.expect_value(t, string(pinball_aim_hint(&room, .Target_Too_Heavy)), "TROPPO PESANTE PER IL PINBALL")
	testing.expect_value(t, string(pinball_aim_hint(&room, .Target_Blocked)), "")
	testing.expect_value(t, game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(room.enemies[0].id))).result,
		game.Card_Play_Result.Played)
	text, rolling := pinball_chip(&room, false)
	testing.expect(t, rolling && string(text) == "PINBALL 20s x2")
	testing.expect_value(t, string(pinball_aim_hint(&room, .Target_Blocked)), "UNA PALLA ALLA VOLTA")
	testing.expect_value(t, string(pinball_aim_hint(&room, .Target_Out_Of_Range)), "")
}

// The ball's wounds hurt the struck card, never swing the player's; a foe
// struck says COLPO n, the burst POP!, a solid thing touched nothing.
@(test)
test_pinball_wounds_swing_no_card_and_say_their_value :: proc(t: ^testing.T) {
	foe := game.enemy_entity(4)
	ball := game.enemy_entity(3)
	hit := Presentation_Cue{kind = .Damage, started = true, event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = foe,
		amount = 3, area_mask = game.EVENT_PINBALL_BIT}}
	action, hurt := living_cue_action(&hit, foe)
	testing.expect(t, hurt && action == .Hurt)
	_, swung := living_cue_action(&hit, game.PLAYER_ENTITY)
	testing.expect(t, !swung)
	renderer := new(Renderer)
	defer free(renderer)
	bumped := Presentation_Cue{kind = .Pinball_Bumped, started = true, event = {kind = .Pinball_Bumped, source = ball, target = foe, amount = 3,
		card_definition = .Pinball}}
	badges, count := tactical_feedback_badges(renderer, &bumped)
	testing.expect(t, count == 1 && string(badges[0].label) == "COLPO 3" && badges[0].over == foe)
	burst := Presentation_Cue{kind = .Pinball_Burst, started = true, event = {kind = .Pinball_Burst, source = game.PLAYER_ENTITY, target = ball,
		card_definition = .Pinball}}
	badges, count = tactical_feedback_badges(renderer, &burst)
	testing.expect(t, count == 1 && string(badges[0].label) == "POP!" && badges[0].over == ball)
	// Clear over the ball's top as it swells to burst (a quarter past its
	// size), so the flash and the paper under it show; the others over the
	// cards' middles.
	swollen := pinball_steel_radius()+(pinball_steel_radius()+PINBALL_SPRITE_PAPER*attack_texel(.Pilgrim))*(1+PINBALL_BURST_GROWTH)
	testing.expect(t, badges[0].height > swollen && badges[0].height < swollen+0.3)
	bumped_badges, _ := tactical_feedback_badges(renderer, &bumped)
	testing.expect_value(t, bumped_badges[0].height, f32(0))
	bounced := Presentation_Cue{kind = .Pinball_Bounced, started = true, event = {kind = .Pinball_Bounced, source = ball, target = game.SYSTEM_ENTITY,
		amount = 2, duration = 5, card_definition = .Pinball}}
	_, count = tactical_feedback_badges(renderer, &bounced)
	testing.expect_value(t, count, 0)
	// The strike is the ball's sound: the player's card swings silently.
	_, voiced := lab_actor_sfx(.Pilgrim, .Attack, .Pinball_Launched, 0)
	testing.expect(t, !voiced)
}

// The lab hears the ball with its own sounds: its card, the strike's thwack
// as the swing lands, a ding off a solid thing, a bong off a foe (higher the
// more it took) and the burst.
@(test)
test_pinball_lab_sounds_follow_the_ball :: proc(t: ^testing.T) {
	player: game.Player
	room := game.Room{player = &player, phase = .Combat}
	state: Living_State
	snapshot: Room_Presentation
	renderer: Renderer
	renderer.tactical.living_state = &state
	renderer.tactical.snapshot = &snapshot
	renderer.tactical.mechanics_lab = true
	defer destroy_lab_sounds(&renderer)
	card, carded := lab_card_sfx(.Pinball)
	testing.expect(t, carded && card == LAB_PINBALL_CARD)
	ball := game.enemy_entity(3)
	renderer.tactical.pinball.base = 2
	s: Lab_Sounds
	impacts := 0
	bounced := Presentation_Cue{kind = .Pinball_Bounced, started = true, event = {kind = .Pinball_Bounced, source = ball, target = game.SYSTEM_ENTITY,
		amount = 2, duration = 4, card_definition = .Pinball}}
	lab_cue_sounds(&renderer, &s, &bounced, 1, &impacts)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == LAB_PINBALL_DING)
	bumped := Presentation_Cue{kind = .Pinball_Bumped, started = true, event = {kind = .Pinball_Bumped, source = ball, target = game.enemy_entity(4),
		amount = 5, card_definition = .Pinball}}
	lab_cue_sounds(&renderer, &s, &bumped, 2, &impacts)
	testing.expect(t, s.count == 2 && s.queue[1].sfx == LAB_PINBALL_BONG && s.queue[1].pitch == lab_bong_pitch(5, 2))
	testing.expect(t, lab_bong_pitch(5, 2) > lab_bong_pitch(2, 2) && lab_bong_pitch(99, 2) == lab_bong_pitch(2+LAB_BONG_STEPS, 2))
	burst := Presentation_Cue{kind = .Pinball_Burst, started = true, event = {kind = .Pinball_Burst, source = game.PLAYER_ENTITY, target = ball,
		card_definition = .Pinball}}
	lab_cue_sounds(&renderer, &s, &burst, 3, &impacts)
	testing.expect(t, s.count == 3 && s.queue[2].sfx == LAB_PINBALL_BURST)
	// The strike's thwack waits for the swing's contact.
	update_lab_sounds(&renderer, &room, 1)
	heard := renderer.tactical.lab_sounds
	if !testing.expect(t, heard != nil) { return }
	testing.expect_value(t, heard.count, 0)
	renderer.tactical.pinball.strikes, renderer.tactical.pinball.contact = 1, 2.5
	update_lab_sounds(&renderer, &room, 2)
	testing.expect(t, heard.count == 1 && heard.queue[0].sfx == LAB_PINBALL_LAUNCH && heard.queue[0].at == 2.5)
	update_lab_sounds(&renderer, &room, 2.1)
	testing.expect_value(t, heard.count, 1)
	// None of them stands in for another of its own.
	sounds := [5]audio.Lab_Sfx{LAB_PINBALL_CARD, LAB_PINBALL_LAUNCH, LAB_PINBALL_DING, LAB_PINBALL_BONG, LAB_PINBALL_BURST}
	for a, i in sounds { for b in sounds[i+1:] { testing.expect(t, a != b) } }
}

// The launch the card's aim shows is the one the strike gives: the room's
// stream, untouched by the looking.
@(test)
test_pinball_aim_shows_the_launch_the_strike_gives :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := pinball_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	random := room.pinball_random
	heading, turn := game.pinball_next_launch(&room, {7, 6})
	testing.expect_value(t, room.pinball_random, random)
	testing.expect(t, abs(turn) >= game.PINBALL_MIN_TURN && abs(turn) <= game.PINBALL_MAX_TURN)
	testing.expect(t, abs(math.hypot(heading.x, heading.y)-1) < 1e-12)
	testing.expect_value(t, game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(room.enemies[0].id))).result,
		game.Card_Play_Result.Played)
	testing.expect_value(t, room.pinball.turn, turn)
	testing.expect(t, room.pinball.heading == heading)
	testing.expect_value(t, room.pinball.cell, grid.Position{7, 6})
}
