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

// NIDO DI RAGNI (game/spider_nest.odin, docs/piano-ia.md, Fase 9), in the real window, in the IA's arena: a low wall
// between the nest and a held foe, the card played by the rules (odin_pp_nido_00.png), the spiderlings around the wall and
// their bites (odin_pp_nido_NN.png, filmed), a chaser set free beside the nest, which strikes it and takes its 3 seconds
// (odin_pp_nido_struck.png) and a tear, the nest sagging at no seconds (odin_pp_nido_sag.png) and gone
// (odin_pp_nido_end.png). Fase 10: each of its six sounds has sounded.
mechanics_lab_nest :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	run_session.advisor_pilot_release()
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	if !built { fmt.eprintln("mechanics lab: the nest's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	player.tactical.ia_remaining = 0
	p := player.position
	chaser := -1
	for &foe, index in room.enemies {
		mechanics_lab_hold(room, foe.id)
		if foe.archetype == .Chaser { chaser = index }
	}
	if chaser < 0 { fmt.eprintln("mechanics lab: the nest's arena has no chaser"); return false }
	// The foe beyond a low wall, three cells long: the spiderlings go around it.
	foe := &room.enemies[chaser]
	foe.position, foe.health, foe.max_health = grid.offset(p, 4, 0), 60, 60
	foe.intent = {}
	mechanics_lab_hold(room, foe.id)
	for dy in -1..=1 {
		if !level.set_tile(data, grid.offset(p, 3, dy), {kind = .Fence}) { fmt.eprintln("mechanics lab: the nest's low wall was not built"); return false }
	}
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }

	cell := grid.offset(p, 1, 0)
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Spider_Nest, game.cell_target(cell)) {
		fmt.eprintln("mechanics lab: the nest was not played"); return false
	}
	if game.emplacement_count(room, .Spider_Nest) != 1 || player.tactical.spiders.count != 1 {
		fmt.eprintln("mechanics lab: nests", game.emplacement_count(room, .Spider_Nest), "spiderlings", player.tactical.spiders.count, "after the card"); return false
	}
	artifacts.screenshot("odin_pp_nido_00.png")

	// Around the wall and to the foe: 4 cells a second, the wall's way longer than the straight one.
	health := foe.health
	for frame in 0..<240 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if frame%40 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_nido_%02d.png", 1+frame/40)) }
	}
	foe = &room.enemies[chaser]
	bitten := health-foe.health
	if bitten < game.SPIDER_BITE_DAMAGE { fmt.eprintln("mechanics lab: the spiderlings bit for", bitten); return false }

	// A chaser set free beside the nest, far from the player: it strikes the nest, 3 seconds off it.
	index, found := game.object_index_at(room, cell)
	if !found { fmt.eprintln("mechanics lab: the nest is gone too soon"); return false }
	foe.position = grid.offset(cell, 0, 1)
	foe.intent, foe.tactical_cooldown, foe.recovery_pulses = {}, 0, 0
	game.plan_enemy_intents(room)
	player.position = grid.offset(cell, -3, -1)
	// Seen in its seconds: a spiderling's flight can follow a beat in the same frame, and the log is the last command's.
	life, beat := room.objects[index].life, room.pulse_count
	struck := false
	for _ in 0..<360 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		index, found = game.object_index_at(room, cell)
		if !found { break }
		struck = room.objects[index].life <= life-i32(room.pulse_count-beat)-game.SPIDER_NEST_BLOW_SECONDS
		if struck { break }
	}
	if !struck { fmt.eprintln("mechanics lab: the chaser did not strike the nest"); return false }
	artifacts.screenshot("odin_pp_nido_struck.png")

	// At no seconds it is gone. The foe aside: it would stand in front of it.
	foe = &room.enemies[chaser]
	foe.position = grid.offset(cell, 3, 2)
	foe.intent = {}
	mechanics_lab_hold(room, foe.id)
	if index, found = game.object_index_at(room, cell); found {
		if room.objects[index].radius < 1 { fmt.eprintln("mechanics lab: the blow left no tear"); return false }
		room.objects[index].life = 1
	}
	shown := false
	for _ in 0..<180 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if !shown {
			if render.nest_sagging(renderer) {
				shown = true
				for _ in 0..<5 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
				artifacts.screenshot("odin_pp_nido_sag.png")
			}
		}
	}
	if game.emplacement_count(room, .Spider_Nest) != 0 { fmt.eprintln("mechanics lab: the nest did not end"); return false }
	if !shown { fmt.eprintln("mechanics lab: the nest went without sagging"); return false }
	artifacts.screenshot("odin_pp_nido_end.png")
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds to count"); return false }
	for sfx in ([6]audio.Lab_Sfx{.Card_Spider_Nest, .World_Spider_Place, .World_Spider_Hatch, .World_Spider_Bite, .World_Spider_Tear, .World_Spider_Close}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: the nest's sound", sfx, "never sounded"); return false }
	}
	fmt.eprintf("mechanics lab nest: bites %d of life, struck, ended; sounds: place %d, hatch %d, bite %d, tear %d, close %d\n", bitten,
		sounds.played[.World_Spider_Place], sounds.played[.World_Spider_Hatch], sounds.played[.World_Spider_Bite], sounds.played[.World_Spider_Tear], sounds.played[.World_Spider_Close])
	return true
}
