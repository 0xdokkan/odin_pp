package devtools
import run_session "../run"

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import rl "vendor:raylib"
import advisor "../advisor"
import app "../engine/app"
import artifacts "artifacts"
import game "../game"
import level "../level"
import render "../render"

// IA (game/ia.odin, docs/piano-ia.md, Fase 0), in the real window, in the IA's arena (run.Mechanics_Lab_Arena.IA, F3)
// with its own deck: the arena, its low walls, covers and four foes (odin_pp_ia_arena.png), and the card in hand
// (odin_pp_mechanics_lab_card_IA.png). Played, IA_Begun says its 30 seconds and "IA 30s" shows over the player while
// the chip under VITA counts them down on the world's clock (odin_pp_ia_card_NN.png). Behind the eyes of a view (the
// AK, taken up by the rules for two seconds) they stand still and the chip says IA FERMA (odin_pp_ia_card_view.png);
// the view over, they run again. Its foes are held, so every run sees the same.
// Fase 2: then the foes go free and the player follows the IA's advice for twenty seconds of the world (Fase 2: ten; the
// cards of Fase 3 need longer to come in), every advised move
// sent as the game's own commands the moment he is free; the cyan square on the cell to step on
// (odin_pp_ia_step_NN.png), the cyan cross on the foe to strike (odin_pp_ia_bump_NN.png), the word over him.
// Fase 3: the cards too: the advised card framed in cyan in the hand and its target marked, then the card raised
// as the player takes it (odin_pp_ia_card_hint_NN.png, even and odd).
// Fase 4: the search runs on its own thread. ODIN_PP_LAB_TIMING=1 measures the frames instead of going on
// (mechanics_lab_ia_timing).
mechanics_lab_ia :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator); timing == "1" {
		return mechanics_lab_ia_timing(window, renderer, room, data, controller, cards, buffer)
	}
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	if !built { fmt.eprintln("mechanics lab: the IA's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if len(room.enemies) != 4 { fmt.eprintln("mechanics lab: the IA's arena has", len(room.enemies), "foes, not 4"); return false }
	id, held := mechanics_lab_hand_card(player, .IA)
	if !held || player.deck.hand_count != 8 { fmt.eprintln("mechanics lab: the IA's arena has not its eight cards in hand"); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_ia_arena.png")
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_IA.png")

	// Played: its seconds begin, said over the player.
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .IA, game.entity_target(game.PLAYER_ENTITY)) {
		fmt.eprintln("mechanics lab: the IA was not played"); return false
	}
	begun := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .IA_Begun && event.amount == game.IA_SECONDS { begun = true }
	}
	if !begun || player.tactical.ia_remaining != f32(game.IA_SECONDS) {
		fmt.eprintln("mechanics lab: the IA began with", player.tactical.ia_remaining, "seconds, not", game.IA_SECONDS); return false
	}
	text, shown := render.ia_chip(room, false)
	if !shown || string(text) != "IA 30s" { fmt.eprintln("mechanics lab: the IA's chip says", text); return false }
	before := player.tactical.ia_remaining
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 90, 6, "ia_card")
	spent := before-player.tactical.ia_remaining
	// Ninety frames of a sixtieth: a second and a half of the world, less the card's cast (the world stands still in it).
	if !(spent > 1.0 && spent <= 1.5+0.01) { fmt.eprintln("mechanics lab: the IA's seconds ran", spent, "in a second and a half"); return false }

	// Behind the eyes of a view they stand still; the view over, they run again.
	if !game.tactical_begin_first_person(room, 2, .AK) { fmt.eprintln("mechanics lab: the AK's view did not open for the IA"); return false }
	held_at, view_left := player.tactical.ia_remaining, room.first_person.remaining
	for _ in 0..<60 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	// The world's clock ran (the view's own seconds went down), the IA's did not.
	if !(room.first_person.remaining < view_left-0.5) { fmt.eprintln("mechanics lab: the world's clock did not run in the view"); return false }
	if player.tactical.ia_remaining != held_at { fmt.eprintln("mechanics lab: the IA's seconds ran behind the eyes"); return false }
	if text, shown = render.ia_chip(room, false); !shown || string(text) != "IA FERMA" { fmt.eprintln("mechanics lab: the IA's chip behind the eyes says", text); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_ia_card_view.png")
	for _ in 0..<240 {
		if !game.tactical_first_person_active(room) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if game.tactical_first_person_active(room) { fmt.eprintln("mechanics lab: the AK's view did not end"); return false }
	after_view := player.tactical.ia_remaining
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	if !(player.tactical.ia_remaining < after_view) { fmt.eprintln("mechanics lab: the IA's seconds did not run again after the view"); return false }
	artifacts.screenshot("odin_pp_ia_card_after.png")
	if !mechanics_lab_ia_follow(window, renderer, room, controller, cards, buffer) { return false }
	if !mechanics_lab_ia_defend(window, renderer, room, data, controller, cards, buffer) { return false }
	return mechanics_lab_ia_warning(window, renderer, room, data, controller, cards, buffer)
}

// The foes free, the player follows the IA's advice for twenty seconds of the world, or until its seconds are over.
@(private = "file")
mechanics_lab_ia_follow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	for &foe in room.enemies { foe.recovery_pulses = 0 }
	steps, bumps, played, waits, followed := 0, 0, 0, 0, 0
	health := room.player.health
	for frame := 0; frame < 1200 && room.phase == .Combat && game.ia_active(room); frame += 1 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		advice := run_session.advisor_current_advice()
		free := advisor.player_free(room) || room.qte.kind != .None
		if !advice.valid || !free || render.renderer_blocks_player_input(renderer) { continue }
		// The marks of the advice about to be followed, as the player sees them.
		if renderer.tactical.advice.mark == .None { fmt.eprintln("mechanics lab: the IA's advice has no mark"); return false }
		#partial switch advice.kind {
		case .Step, .Dodge, .Diagonal:
			if steps < 8 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_step_%02d.png", steps)) }
			steps += 1
		case .Bump:
			if bumps < 8 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_bump_%02d.png", bumps)) }
			bumps += 1
		case .Card:
			// The card framed in the hand; then held, its frame on the target's cell.
			if played < 4 {
				artifacts.screenshot(fmt.ctprintf("odin_pp_ia_card_hint_%02d.png", 2*played))
				mechanics_lab_ia_held_still(window, renderer, room, advice.move.card_id, fmt.ctprintf("odin_pp_ia_card_hint_%02d.png", 2*played+1))
			}
			played += 1
		case .Wait:
			if waits < 4 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_wait_%02d.png", waits)) }
			waits += 1
		}
		commands, count := run_session.advisor_move_commands(room, advice.move)
		for command in commands[:count] { run_session.commit_gameplay_command(room, renderer, cards, command) }
		followed += 1
	}
	fmt.eprintf("mechanics lab IA: %d moves followed (%d steps, %d bumps, %d cards, %d waits), life %d to %d, %d foes left\n",
		followed, steps, bumps, played, waits, health, room.player.health, len(room.enemies))
	if steps == 0 || bumps == 0 || played == 0 { fmt.eprintln("mechanics lab: the IA advised no step, no bump or no card in twenty seconds"); return false }
	return true
}

// THE FRAMES WITH THE IA AND WITHOUT (docs/piano-ia.md, Fase 4): four runs in crossed order, without, with, with,
// without (ABBA: the machine's own drift weighs on both alike). Each the IA's arena built afresh, its foes free, the
// player standing; with the IA its seconds never run out and its worker searches on its own thread. The whole smoke
// frame (controller, view, board, HUD), no frame limit and no vsync, as the first person timing measures.
@(private = "file")
mechanics_lab_ia_timing :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	rl.SetTargetFPS(0)
	rl.ClearWindowState({.VSYNC_HINT})
	player := room.player
	for with_ia, run in ([4]bool{false, true, true, false}) {
		game.destroy_room(room)
		player.health = player.stats.max_health
		rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
		if !built { fmt.eprintln("mechanics lab timing: the IA's arena was not built"); return false }
		room^ = rebuilt
		render.clear_event_animations(renderer)
		controller^ = {was_focused = true}
		player.tactical.ia_remaining = 999 if with_ia else 0
		samples: [MECHANICS_LAB_TIMING_SAMPLES]f64
		roots := 0
		last := rl.GetTime()
		root: u64
		for index in 0..<MECHANICS_LAB_TIMING_WARMUP+MECHANICS_LAB_TIMING_SAMPLES {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
			now := rl.GetTime()
			if index >= MECHANICS_LAB_TIMING_WARMUP { samples[index-MECHANICS_LAB_TIMING_WARMUP] = (now-last)*1000 }
			last = now
			if packet := run_session.advisor_pilot_packet(); packet.root != root { root = packet.root; roots += 1 }
			if room.phase != .Combat { fmt.eprintln("mechanics lab timing: the fight ended at frame", index); return false }
		}
		if with_ia && !game.ia_active(room) { fmt.eprintln("mechanics lab timing: the IA stopped"); return false }
		values := samples[:]
		slice.sort(values)
		total: f64
		for ms in values { total += ms }
		count := len(values)
		packet := run_session.advisor_pilot_packet()
		fmt.printf("IA TIMING run=%d ia=%v samples=%d mean_ms=%.3f median_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f roots=%d last_round=%d last_nodes=%d\n",
			run, with_ia, count, total/f64(count), (values[(count-1)/2]+values[count/2])*0.5, values[(count*95+99)/100-1],
			values[(count*99+99)/100-1], values[count-1], roots, packet.round, packet.nodes)
	}
	run_session.advisor_pilot_release()
	return true
}

// The board with `card_id` held, as when the player takes the card up: the advice's frame on its target.
@(private = "file")
mechanics_lab_ia_held_still :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, card_id: u32, name: cstring) {
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, card_id)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, 0, card_id, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot(name)
}

// A scene of the IA's arena: built afresh, its seconds endless, a brute of 40 next to the player (south), its cleave
// about to fall on his cell and the two beside it, the other foes held far away; `dodge` whether his dodge is ready.
@(private = "file")
mechanics_lab_ia_scene :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, dodge: bool) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	if !built { fmt.eprintln("mechanics lab: the IA's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	player.tactical.ia_remaining = 999
	p := player.position
	brute := -1
	for &foe, index in room.enemies {
		mechanics_lab_hold(room, foe.id)
		if foe.archetype == .Brute { brute = index }
	}
	if brute < 0 { fmt.eprintln("mechanics lab: the IA's arena has no brute"); return false }
	foe := &room.enemies[brute]
	foe.position, foe.health, foe.max_health, foe.recovery_pulses = game.add_position(p, {x = 0, y = 1}), 40, 40, 0
	foe.intent = {kind = .Attack, origin = foe.position, destination = foe.position, damage = 3, planned_pulse = room.pulse_count+1}
	for dx in -1..=1 {
		foe.intent.threatened_cells[foe.intent.threatened_cell_count] = game.add_position(p, {x = dx, y = 0})
		foe.intent.threatened_cell_count += 1
	}
	foe.tactical_cooldown = 1
	if !dodge { player.tactical.dodge_recovery = game.TACTICAL_DODGE_RECOVERY+1 }
	return true
}

// THE DEFENCE: the player waits under the cleave (against the advice), his dodge ready: the defence keys come up and
// the IA frames the right one in the panel, the dodge's landing on the floor (odin_pp_ia_defend_00.png); followed, the
// blow misses (odin_pp_ia_defend_01.png).
@(private = "file")
mechanics_lab_ia_defend :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if !mechanics_lab_ia_scene(window, renderer, room, data, controller, cards, buffer, true) { return false }
	health := room.player.health
	shown := false
	for _ in 0..<600 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if room.qte.kind != .Defense || room.qte.selected { continue }
		advice := run_session.advisor_current_advice()
		if !advice.valid || advice.kind != .Defend { continue }
		if !render.advice_frames_defense(renderer, room, advice.move.defense) { fmt.eprintln("mechanics lab: the IA's defence is not framed"); return false }
		artifacts.screenshot("odin_pp_ia_defend_00.png")
		commands, count := run_session.advisor_move_commands(room, advice.move)
		for command in commands[:count] { run_session.commit_gameplay_command(room, renderer, cards, command) }
		for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
		artifacts.screenshot("odin_pp_ia_defend_01.png")
		shown = true
		break
	}
	if !shown { fmt.eprintln("mechanics lab: no defence advised under the cleave"); return false }
	fmt.eprintf("mechanics lab IA defence: advised and followed, life %d to %d\n", health, room.player.health)
	return true
}

// THE WARNING: under the cleave, his dodge recovering, no card in hand but the IA's own (none to escape with later),
// the IA advises a way out; the player refocuses his hand instead, standing under the blow while the cards turn (a
// move it tried, much worse: 2 of life lost where the advice loses none). The red «!» with the life it risks shows over him for half a second
// (odin_pp_ia_warning_NN.png).
@(private = "file")
mechanics_lab_ia_warning :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if !mechanics_lab_ia_scene(window, renderer, room, data, controller, cards, buffer, false) { return false }
	deck := &room.player.deck
	hand := deck.hand
	count := deck.hand_count
	deck.hand_count = 0
	for card in hand[:count] {
		if card.definition_id == .IA { deck.hand[deck.hand_count] = card; deck.hand_count += 1; continue }
		deck.discard_pile[deck.discard_count] = card
		deck.discard_count += 1
	}
	for &card in deck.hand[deck.hand_count:] { card = {} }
	// The search of this root over (frames of no time: the world waits), then the player's own move.
	for _ in 0..<300 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 0)
		if packet := run_session.advisor_pilot_packet(); packet.done && packet.root == advisor.discrete_fingerprint(room) { break }
		time.sleep(2*time.Millisecond)
	}
	advice := run_session.advisor_current_advice()
	if !advice.valid || advice.kind == .Refocus || advice.kind == .Wait { fmt.eprintln("mechanics lab: the IA advises", advice.kind, "under the cleave"); return false }
	artifacts.screenshot("odin_pp_ia_warning_advice.png")
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Refocus, origin_phase = .Combat}) {
		fmt.eprintln("mechanics lab: the refocus was not taken"); return false
	}
	warned := 0
	for frame in 0..<40 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if renderer.tactical.advice.warning_left > 0 {
			if warned < 3 && frame%4 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_warning_%02d.png", warned)); warned += 1 }
		}
	}
	if warned == 0 { fmt.eprintln("mechanics lab: no warning after the player's own move under the cleave"); return false }
	fmt.eprintf("mechanics lab IA warning: %s\n", renderer.tactical.advice.warning)
	return true
}
