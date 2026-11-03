package devtools
import run_session "../run"

import "core:fmt"
import audio "../engine/audio"
import app "../engine/app"
import artifacts "artifacts"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// REGINA (game/queen.odin, docs/piano-ia.md, Fase 11), in the real window, in the IA's arena: the card played by the rules
// with no foe on her lines (odin_pp_regina_00.png); a foe set on a diagonal, her run and her blow
// (odin_pp_regina_run_NN.png, odin_pp_regina_02.png); of two foes the nearest (odin_pp_regina_03.png); a low wall that stops
// a line (odin_pp_regina_wall.png); at no seconds she topples (odin_pp_regina_fall.png). Fase 12: each of her five sounds has
// sounded.
mechanics_lab_queen :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	run_session.advisor_pilot_release()
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	if !built { fmt.eprintln("mechanics lab: the Queen's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	player.tactical.ia_remaining = 0
	p := player.position
	chaser, brute := -1, -1
	for &foe, index in room.enemies {
		mechanics_lab_hold(room, foe.id)
		#partial switch foe.archetype {
		case .Chaser: chaser = index
		case .Brute: brute = index
		}
	}
	if chaser < 0 || brute < 0 { fmt.eprintln("mechanics lab: the Queen's arena has no chaser or no brute"); return false }
	// Foes out of her lines at first: she is set down and waits.
	cell := grid.offset(p, 2, 0)
	far := grid.offset(cell, 3, 4)
	for &foe, index in room.enemies {
		foe.health, foe.max_health = 60, 60
		foe.position = grid.offset(far, index, 2*index)
		foe.intent = {}
		mechanics_lab_hold(room, foe.id)
	}
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Queen, game.cell_target(cell)) {
		fmt.eprintln("mechanics lab: the Queen was not played"); return false
	}
	for _ in 0..<80 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	index, found := game.object_index_at(room, cell)
	if !found || room.objects[index].kind != .Queen { fmt.eprintln("mechanics lab: no Queen where she was set"); return false }
	id := room.objects[index].id
	artifacts.screenshot("odin_pp_regina_00.png")

	// A foe on a diagonal: she runs to the cell next to him and strikes.
	foe := &room.enemies[chaser]
	health := foe.health
	foe.position = grid.offset(cell, 4, -4)
	mechanics_lab_hold(room, foe.id)
	// The run and the blow, close together.
	for frame in 0..<60 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if frame < 18 && frame%6 == 2 { artifacts.screenshot(fmt.ctprintf("odin_pp_regina_run_%02d.png", frame/6)) }
		if frame == 59 { artifacts.screenshot("odin_pp_regina_02.png") }
	}
	foe = &room.enemies[chaser]
	if health-foe.health != game.QUEEN_BASE_DAMAGE { fmt.eprintln("mechanics lab: the Queen struck for", health-foe.health); return false }
	index, found = game.object_index_by_id(room, id)
	if !found || room.objects[index].position != grid.offset(cell, 3, -3) { fmt.eprintln("mechanics lab: the Queen did not stop next to her foe"); return false }

	// Of two foes on her lines, the nearest; the chaser out of them.
	at := room.objects[index].position
	foe.position = grid.offset(far, 6, 0)
	mechanics_lab_hold(room, foe.id)
	near, other := &room.enemies[brute], &room.enemies[chaser]
	near.position = grid.offset(at, -3, 0)
	mechanics_lab_hold(room, near.id)
	other.position = grid.offset(at, 0, -5)
	mechanics_lab_hold(room, other.id)
	near_health, other_health := near.health, other.health
	room.player.tactical.queen_wait = 0
	for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	if room.enemies[brute].health != near_health-game.QUEEN_BASE_DAMAGE || room.enemies[chaser].health != other_health {
		fmt.eprintln("mechanics lab: of two foes the Queen did not strike the nearest"); return false
	}
	artifacts.screenshot("odin_pp_regina_03.png")

	// A low wall stops a line: the foe beyond it is safe.
	index, found = game.object_index_by_id(room, id)
	if !found { fmt.eprintln("mechanics lab: the Queen is gone too soon"); return false }
	at = room.objects[index].position
	near = &room.enemies[brute]
	near.position = grid.offset(far, 6, 4)
	mechanics_lab_hold(room, near.id)
	other = &room.enemies[chaser]
	other.position = grid.offset(at, 0, -3)
	mechanics_lab_hold(room, other.id)
	if !level.set_tile(data, grid.offset(at, 0, -1), {kind = .Fence}) { fmt.eprintln("mechanics lab: the Queen's low wall was not built"); return false }
	other_health = other.health
	room.player.tactical.queen_wait = 0
	for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	if room.enemies[chaser].health != other_health { fmt.eprintln("mechanics lab: the Queen struck through a low wall"); return false }
	artifacts.screenshot("odin_pp_regina_wall.png")

	// At no seconds she topples.
	index, found = game.object_index_by_id(room, id)
	if !found { fmt.eprintln("mechanics lab: the Queen is gone too soon"); return false }
	room.objects[index].life = 1
	toppled := false
	for _ in 0..<180 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if !toppled && render.queen_toppling(renderer) {
			toppled = true
			for _ in 0..<10 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
			artifacts.screenshot("odin_pp_regina_fall.png")
		}
	}
	if game.emplacement_count(room, .Queen) != 0 || !toppled { fmt.eprintln("mechanics lab: the Queen did not topple and go"); return false }
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds to count"); return false }
	for sfx in ([5]audio.Lab_Sfx{.Card_Queen, .World_Queen_Place, .World_Queen_Run, .World_Queen_Strike, .World_Queen_Fall}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: the Queen's sound", sfx, "never sounded"); return false }
	}
	fmt.eprintf("mechanics lab Queen: ran down a diagonal, the nearest of two struck, a low wall held; sounds: place %d, run %d, strike %d, fall %d\n",
		sounds.played[.World_Queen_Place], sounds.played[.World_Queen_Run], sounds.played[.World_Queen_Strike], sounds.played[.World_Queen_Fall])
	return true
}
