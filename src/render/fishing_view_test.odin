package render

import "core:testing"
import rl "vendor:raylib"
import audio "../engine/audio"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The Canna da Pesca on the board (fishing.odin): its card's texts, its slot
// clear of the cleared room's footer, its three cues (the water from the
// bobber's plop, the d4 of its food accepted), what they say, and its water
// baked blue with ripples.

fishing_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{"###########", "#.........#", "#.........#", "#....@....#", "#.........#", "#........>#", "###########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return data
}

// A cleared tactical room, the rod in the deck, the player hurt.
fishing_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> game.Room {
	data^ = fishing_test_level(t)
	created: bool
	player^, created = game.create_player({max_health = 30, attack = 2, defense = 1})
	testing.expect(t, created)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	_, added := game.add_owned_card(&player.deck, .Fishing_Rod)
	testing.expect(t, added)
	player.health = 20
	room, built := game.create_room(data, player, {})
	testing.expect(t, built)
	testing.expect(t, game.fishing_room_open(&room))
	return room
}

fishing_test_stream :: proc(card: bool) -> u64 {
	for seed in u64(1)..<u64(100_000) {
		random := seed
		if game.fishing_catch_is_card(&random) == card { return seed }
	}
	return 0
}

@(test)
test_fishing_rod_card_says_its_fishings_and_its_catch :: proc(t: ^testing.T) {
	rod := game.Card_Instance{id = 1, definition_id = .Fishing_Rod}
	first, second := gothic_card_lines(rod)
	testing.expect_value(t, string(first), "1 PESCA A STANZA")
	testing.expect_value(t, string(second), "CIBO d4 / 5% CARTA")
	upgraded := rod
	upgraded.upgrade_level = 2
	first, second = gothic_card_lines(upgraded)
	testing.expect_value(t, string(first), "3 PESCHE A STANZA")
	testing.expect_value(t, string(second), "CIBO d4 / 5% CARTA")
	narrow_first, narrow_second, short := gothic_card_narrow_lines(upgraded)
	testing.expect(t, short)
	testing.expect_value(t, string(narrow_first), "3 PESCHE")
	testing.expect_value(t, string(narrow_second), "CIBO d4 O CARTA")
	// Its upgrades raise the fishings alone.
	testing.expect_value(t, string(card_upgrade_preview(rod)), "PESCHE 1 -> 2")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Fishing_Rod, upgrade_level = 5})), "MAX UPGRADE")
	definition, _ := game.card_definition_by_id(.Fishing_Rod)
	testing.expect_value(t, string(tactical_card_target_label(definition)), "RAGGIO 1-3")
	testing.expect_value(t, string(tactical_card_time_badge(.Fishing_Rod)), "0s")
	testing.expect_value(t, string(card_short_name(.Fishing_Rod)), "CANNA")
	testing.expect_value(t, gothic_card_icon(.Fishing_Rod), 24)
	sfx, sounds := lab_card_sfx(.Fishing_Rod)
	testing.expect(t, sounds && sfx == .Card_Fishing_Rod)
}

// The slot stands where a one-card hand's card would, on the right: inside the
// canvas, under the board (its drop area) and clear of every footer control
// of a cleared room, at every width.
@(test)
test_fishing_slot_stands_clear_of_the_footer_and_the_board :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	player: game.Player
	player.equipment.reserve = {.Iron_Cleaver, 4}
	player.equipment.weapon = {.Storm_Pike, 3}
	room := game.Room{player = &player, phase = .Loot}
	for width in ([3]f32{640, 960, 1280}) {
		renderer.canvas_width, renderer.canvas_height = width, 540
		slot := fishing_slot_bounds(renderer)
		testing.expect(t, slot.x >= 0 && slot.y >= 0 && slot.x+slot.width <= width && slot.y+slot.height <= 540)
		testing.expect(t, slot.width >= 120 && slot.height == 154)
		// Its hint and its ribbon stand above it, still under the board.
		board := tactical_world_bounds(renderer)
		testing.expect(t, slot.y-27 >= board.y+board.height)
		for bounds in ([4]rl.Rectangle{m8_control_bounds(renderer, .Activate, &room), m8_control_bounds(renderer, .Equip, &room),
			m8_weapon_bounds(renderer, &room), m8_trap_status_bounds(renderer, &room)}) {
			testing.expectf(t, !rl.CheckCollisionRecs(slot, bounds), "%v: the slot %v meets %v", width, slot, bounds)
		}
		testing.expect(t, !rl.CheckCollisionRecs(slot, m8_control_bounds(renderer, .Character, &room)))
	}
}

// A fishing's cues play with nothing refused: the cast, then the bite (the
// water shows as it starts), then the catch; food's d4 and cure after it.
// Some three seconds of fishing, the die's own besides.
@(test)
test_fishing_cues_show_the_water_from_the_plop :: proc(t: ^testing.T) {
	for card in ([2]bool{false, true}) {
		data: level.Level
		player: game.Player
		room := fishing_test_room(t, &data, &player)
		room.fishing.random = fishing_test_stream(card)
		cell := grid.Position{7, 3}
		before := capture_room_presentation(&room)
		report := game.fish_with_rod(&room, cell)
		testing.expect(t, report.result == .Fished && report.card == card)
		after := capture_room_presentation(&room)
		testing.expect(t, before.ground.water_count == 0 && after.ground.water_count == 1 && presentation_ground_water(&after.ground, cell))
		renderer := new(Renderer)
		testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
		timeline := &renderer.timeline
		kinds: [dynamic]Presentation_Cue_Kind
		fishing_seconds: f32
		for offset in 0..<timeline.count {
			cue, _ := presentation_cue_at(timeline, offset)
			if fishing_cue_kind(cue.kind) { fishing_seconds += cue.duration }
		}
		testing.expectf(t, fishing_seconds >= 2.5 && fishing_seconds <= 3.5, "%.2f s of fishing", fishing_seconds)
		watered := false
		for _ in 0..<4000 {
			if !event_timeline_is_busy(timeline) { break }
			update_event_timeline(timeline, 1.0/60.0)
			cue, found := active_presentation_cue(timeline)
			if !found || !cue.started { continue }
			if len(kinds) == 0 || kinds[len(kinds)-1] != cue.kind { append(&kinds, cue.kind) }
			shown := presentation_ground_water(&timeline.view.ground, cell)
			if cue.kind == .Fish_Cast { testing.expect(t, !shown) }
			if cue.kind == .Fish_Bite { testing.expect(t, shown); watered = true }
		}
		testing.expect(t, watered)
		testing.expect_value(t, timeline.update_failures, 0)
		testing.expect(t, len(kinds) >= 3 && kinds[0] == .Fish_Cast && kinds[1] == .Fish_Bite && kinds[2] == .Fish_Caught)
		if !card { testing.expect(t, len(kinds) >= 4 && kinds[3] == .Dice_Rolled) }
		delete(kinds)
		destroy_renderer_world_playback(renderer)
		free(renderer)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}

// The rod's d4 is accepted at every level; any other die is not its.
@(test)
test_fishing_dice_cue_accepts_the_rods_d4_only :: proc(t: ^testing.T) {
	for sides in ([2]i32{4, 6}) {
		timeline: Presentation_Timeline
		roll := game.Dice_Roll{faces = {3, 0, 0}, total = 3, sides = sides, count = 1}
		cue := Presentation_Cue{kind = .Dice_Rolled, duration = 1, event = {kind = .Dice_Rolled, source = game.PLAYER_ENTITY,
			target = game.PLAYER_ENTITY, amount = 3, dice_roll = roll, card_definition = .Fishing_Rod, card_upgrade_level = 5}}
		start_presentation_cue(&timeline, &cue)
		testing.expect_value(t, timeline.update_failures, 0 if sides == 4 else 1)
	}
}

// What the cues say: the rod's name as it is cast and a caught card's under
// the board and the food's name over the player.
@(test)
test_fishing_cues_say_their_catch :: proc(t: ^testing.T) {
	names := [game.Fishing_Food]string{.Fish = "PESCE", .Apple = "MELA", .Bread = "PANE", .Cheese = "FORMAGGIO", .Meat = "CARNE"}
	for food in game.Fishing_Food {
		event := game.Game_Event{kind = .Fish_Caught, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
			card_definition = .Fishing_Rod, duration = i32(food)}
		testing.expect_value(t, string(fishing_catch_label(event)), names[food])
		cue := Presentation_Cue{kind = .Fish_Caught, event = event}
		_, _, banner := fishing_cue_banner(&cue)
		testing.expect(t, !banner)
		renderer := new(Renderer)
		badges, count := tactical_feedback_badges(renderer, &cue)
		free(renderer)
		testing.expect(t, count == 1 && string(badges[0].label) == names[food] && badges[0].over == game.PLAYER_ENTITY)
	}
	caught := Presentation_Cue{kind = .Fish_Caught, event = {kind = .Fish_Caught, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
		card_definition = .Strike, card_id = 40}}
	label, _, shown := fishing_cue_banner(&caught)
	testing.expect(t, shown && string(label) == "CARTA PESCATA / Strike")
	testing.expect_value(t, string(fishing_catch_label(caught.event)), "CARTA PESCATA")
	thrown := Presentation_Cue{kind = .Fish_Cast, event = {kind = .Fish_Cast, source = game.PLAYER_ENTITY, card_definition = .Fishing_Rod}}
	label, _, shown = fishing_cue_banner(&thrown)
	testing.expect(t, shown && string(label) == "Canna da Pesca")
	for kind in ([3]game.Game_Event_Kind{.Fish_Cast, .Fish_Bite, .Fish_Caught}) {
		testing.expect(t, fishing_cue_kind(presentation_cue_kind({kind = kind})))
	}
	testing.expect_value(t, presentation_cue_duration(.Fish_Caught, caught.event), PRESENTATION_FISH_CARD_DURATION)
	testing.expect_value(t, presentation_cue_duration(.Fish_Caught, {card_definition = .Fishing_Rod}), PRESENTATION_FISH_CATCH_DURATION)
}

// The water is the ground's decal in blue: its texels water and ripples, paper
// and ink round them, nothing of the poison's green.
@(test)
test_fishing_water_bakes_blue_with_ripples :: proc(t: ^testing.T) {
	fx: Ground_Fx
	defer ground_test_free(&fx)
	ground_fx_resize(&fx, 9, 7)
	tx := fx.texels
	fx.cells[3*fx.width+4].layers += {.Water}
	for y in 0..<fx.height { for x in 0..<fx.width {
		fx.cells[y*fx.width+x].content = bake_ground_cell(&fx, {x, y})
	} }
	water, ripples, paper, venom := 0, 0, 0, 0
	for gy in 2*tx..<5*tx { for gx in 3*tx..<6*tx {
		c := ground_test_pixel(&fx, gx, gy)
		colour := rl.Color{c[0], c[1], c[2], c[3]}
		if colour == GROUND_WATER || colour == GROUND_WATER_DEEP || colour == GROUND_WATER_LIGHT { water += 1 }
		if colour == GROUND_WATER_RIPPLE || colour == GROUND_WATER_GLINT { ripples += 1 }
		if colour == LIVING_TOKEN_PAPER { paper += 1 }
		if ground_test_is_venom(&fx, gx, gy) { venom += 1 }
	} }
	testing.expect(t, water > tx*tx/3 && ripples > tx && paper > tx && venom == 0)
	testing.expect(t, fx.cells[3*fx.width+4].content && !fx.cells[0].content)
	// The middle of the cell is water, its liquid as the texel-by-texel cut says.
	testing.expect(t, ground_texel_liquid(&fx, .Water, 4*tx+tx/2, 3*tx+tx/2) && !ground_texel_liquid(&fx, .Pool, 4*tx+tx/2, 3*tx+tx/2))
}

// The lab hears the rod with its own sounds, each as its drawing shows: the
// card as the rod is cast, the plop as the bobber lands and the bite as it
// dips; the reel with its splash where the catch breaks the water, then the
// catch reaching his hand, or a caught card reaching him.
@(test)
test_fishing_lab_sounds_follow_the_rod :: proc(t: ^testing.T) {
	snapshot: Room_Presentation
	renderer: Renderer
	renderer.tactical.snapshot = &snapshot
	s: Lab_Sounds
	impacts := 0
	casting := Presentation_Cue{kind = .Fish_Cast, started = true, duration = PRESENTATION_FISH_CAST_DURATION,
		event = {kind = .Fish_Cast, source = game.PLAYER_ENTITY, card_definition = .Fishing_Rod}}
	lab_cue_sounds(&renderer, &s, &casting, 1, &impacts)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Card_Fishing_Rod && s.queue[0].at == 1)
	bite := Presentation_Cue{kind = .Fish_Bite, started = true, duration = PRESENTATION_FISH_BITE_DURATION,
		event = {kind = .Fish_Bite, source = game.PLAYER_ENTITY, card_definition = .Fishing_Rod}}
	lab_cue_sounds(&renderer, &s, &bite, 2, &impacts)
	testing.expect(t, s.count == 3 && s.queue[1].sfx == .World_Bobber_Plop && s.queue[1].at == 2)
	testing.expect(t, s.queue[2].sfx == .World_Fish_Bite && abs(s.queue[2].at-(2+f64(PRESENTATION_FISH_BITE_DURATION*FISHING_BITE_AT))) < 1e-6)
	food := Presentation_Cue{kind = .Fish_Caught, started = true, duration = PRESENTATION_FISH_CATCH_DURATION,
		event = {kind = .Fish_Caught, source = game.PLAYER_ENTITY, card_definition = .Fishing_Rod}}
	lab_cue_sounds(&renderer, &s, &food, 4, &impacts)
	breaks := 4+f64(PRESENTATION_FISH_CATCH_DURATION*FISHING_REEL*FISHING_REEL_BREAKS)
	testing.expect(t, s.count == 5 && s.queue[3].sfx == .Pilgrim_Reel && abs(s.queue[3].at+LAB_REEL_SPLASH_SECONDS-breaks) < 1e-6)
	testing.expect(t, s.queue[4].sfx == .Pilgrim_Catch && abs(s.queue[4].at-(4+f64(PRESENTATION_FISH_CATCH_DURATION*fishing_food_taken()))) < 1e-6)
	card := Presentation_Cue{kind = .Fish_Caught, started = true, duration = PRESENTATION_FISH_CARD_DURATION,
		event = {kind = .Fish_Caught, source = game.PLAYER_ENTITY, card_definition = .Poison_Pool}}
	lab_cue_sounds(&renderer, &s, &card, 8, &impacts)
	testing.expect(t, s.count == 7 && s.queue[5].sfx == .Pilgrim_Reel && s.queue[6].sfx == .Ui_Fish_Card)
	testing.expect(t, abs(s.queue[6].at-(8+f64(PRESENTATION_FISH_CARD_DURATION*FISHING_CARD_LANDS))) < 1e-6)
	// Food is taken late in its flight, after the reeling.
	testing.expect(t, fishing_food_taken() > FISHING_REEL && fishing_food_taken() < 1)
}

// A real fishing on the lab's board, the player's card living and its clips
// heard as the lab hears them: he rises into his cast as the rod is cast (the
// lantern's blow and back flip never play, nor the pickup's stoop) and holds
// still while the catch is reeled in; and only the rod's own sounds play, food
// or a card, never the lantern's whoosh and clank, the pickup's coins or the
// chime of a card's cast.
@(test)
test_fishing_lab_board_plays_the_rod_alone :: proc(t: ^testing.T) {
	for card in ([2]bool{false, true}) {
		data: level.Level
		player: game.Player
		room := fishing_test_room(t, &data, &player)
		room.fishing.random = fishing_test_stream(card)
		snapshot: Room_Presentation
		renderer := shadow_view_test_renderer(&data, &snapshot)
		renderer.tactical.mechanics_lab = true
		renderer.tactical.living_state = new(Living_State)
		update_tactical_view(renderer, &room, {}, false)
		lab_shadow_test_frame(renderer, &room, 1.0/60.0)
		before := capture_room_presentation(&room)
		report := game.fish_with_rod(&room, {7, 3})
		testing.expect(t, report.result == .Fished && report.card == card)
		after := capture_room_presentation(&room)
		testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
		risen, swung, stooped := false, false, false
		for _ in 0..<600 {
			lab_shadow_test_frame(renderer, &room, 1.0/60.0)
			pilgrim := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
			if pilgrim == nil { continue }
			if pilgrim.action == .Cast && living_busy(pilgrim, living_clock(renderer, game.PLAYER_ENTITY)) { risen = true }
			if pilgrim.action == .Attack { swung = true }
			if pilgrim.action == .Interact { stooped = true }
		}
		testing.expect(t, !renderer_blocks_player_input(renderer))
		testing.expect(t, risen && !swung && !stooped, "he casts the rod, never swings his lantern or stoops")
		heard := renderer.tactical.lab_sounds
		caught, missed := audio.Lab_Sfx.Pilgrim_Catch, audio.Lab_Sfx.Ui_Fish_Card
		if card { caught, missed = missed, caught }
		if testing.expect(t, heard != nil) {
			for sfx in ([5]audio.Lab_Sfx{.Card_Fishing_Rod, .World_Bobber_Plop, .World_Fish_Bite, .Pilgrim_Reel, caught}) {
				testing.expectf(t, heard.played[sfx] == 1, "%v played %d times", sfx, heard.played[sfx])
			}
			for sfx in ([4]audio.Lab_Sfx{.Pilgrim_Attack, .Pilgrim_Interact, .Pilgrim_Cast, missed}) {
				testing.expectf(t, heard.played[sfx] == 0, "%v played %d times", sfx, heard.played[sfx])
			}
		}
		destroy_lab_sounds(renderer)
		living_tokens_free(renderer.tactical.living_state)
		free(renderer.tactical.living_state)
		destroy_renderer_world_playback(renderer)
		free(renderer)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}
