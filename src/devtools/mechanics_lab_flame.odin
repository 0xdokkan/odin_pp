package devtools
import run_session "../run"

import "core:fmt"
import "core:os"
import "core:slice"
import rl "vendor:raylib"
import audio "../engine/audio"
import app "../engine/app"
import artifacts "artifacts"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// LANCIAFIAMME (game/first_person_flame.odin, docs/piano-ia.md, Fase 13), in the real window, in the first person arena: the
// card from the hand, the camera staying on the board and the mouse free; the flame turned from one foe to the other, its
// trail filmed (odin_pp_lanciafiamme_NN.png); a foe touched twice two seconds apart, his Bruciatura rising; a wall that stops
// it and a low wall that does not (odin_pp_lanciafiamme_wall.png); a barrel, a block of ice, a fire on the floor
// (odin_pp_lanciafiamme_things.png); and a step taken while it fires. Fase 14: the paper model in his hands, the flame and
// its smoke filmed closely as he turns, each of its six sounds heard. ODIN_PP_LAB_TIMING=1 measures its frames instead.

// A frame with the world running, the mouse over the board's point `at`, the button as `fire` says.
@(private = "file")
flame_lab_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, at: grid.Position, fire: bool) {
	input := run_session.Tactical_Controller_Input{focused = true, fire = fire}
	mouse := render.tactical_project(renderer, {f32(at.x)+0.5, f32(at.y)+0.5})
	input.map_input.mouse, input.map_input.inside = mouse, true
	mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, nil, input)
}

@(private = "file")
flame_lab_burn :: proc(room: ^game.Room, id: u32) -> i32 {
	status, found := game.status_for_entity(room, game.enemy_entity(id), .Burn)
	return status.potency if found else 0
}

mechanics_lab_flame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	run_session.advisor_pilot_release()
	timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator)
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	if !built { fmt.eprintln("mechanics lab: the flame's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	if len(room.enemies) < 2 { fmt.eprintln("mechanics lab: the flame's arena has", len(room.enemies), "foes"); return false }
	player.position = {x = 11, y = 6}
	p := player.position
	for &foe in room.enemies {
		foe.health, foe.max_health = 90, 90
		mechanics_lab_hold(room, foe.id)
	}
	first, second := &room.enemies[0], &room.enemies[1]
	first.position, second.position = grid.offset(p, 2, 0), grid.offset(p, 0, 2)
	mechanics_lab_hold(room, first.id)
	mechanics_lab_hold(room, second.id)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }

	// The card, from the hand: the camera stays where it is, the mouse stays free.
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Flamethrower, game.entity_target(game.PLAYER_ENTITY)) {
		fmt.eprintln("mechanics lab: the Lanciafiamme was not played"); return false
	}
	for _ in 0..<60 { flame_lab_frame(window, renderer, room, controller, cards, buffer, first.position, false) }
	if !game.first_person_flame_active(room) || !game.first_person_on_board(room) { fmt.eprintln("mechanics lab: no Lanciafiamme in hand"); return false }
	if render.first_person_amount(renderer) > 0 || controller.look_captured { fmt.eprintln("mechanics lab: the Lanciafiamme left the board's camera"); return false }

	// ODIN_PP_LAB_TIMING=1: frames in crossed order, the flame off, on, on, off, turning all the time: it must not slow the game.
	if timing == "1" {
		rl.SetTargetFPS(0)
		rl.ClearWindowState({.VSYNC_HINT})
		for firing, run in ([4]bool{false, true, true, false}) {
			samples: [600]f64
			last := rl.GetTime()
			for index in 0..<30+len(samples) {
				room.first_person.remaining = 20
				flame_lab_frame(window, renderer, room, controller, cards, buffer, first.position if index%60 < 30 else second.position, firing)
				now := rl.GetTime()
				if index >= 30 { samples[index-30] = (now-last)*1000 }
				last = now
			}
			slice.sort(samples[:])
			total: f64
			for ms in samples { total += ms }
			fmt.printf("FLAME TIMING run=%d firing=%v mean_ms=%.3f median_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f\n", run, firing,
				total/f64(len(samples)), samples[len(samples)/2], samples[len(samples)*95/100], samples[len(samples)*99/100], samples[len(samples)-1])
		}
		return true
	}

	// On the first foe, then turned to the second: the trail, filmed.
	id_first, id_second := first.id, second.id
	first_cell, second_cell := first.position, second.position
	for _ in 0..<30 { flame_lab_frame(window, renderer, room, controller, cards, buffer, first_cell, true) }
	if first.health != 90-game.FLAME_DAMAGE { fmt.eprintln("mechanics lab: the first foe has", first.health); return false }
	artifacts.screenshot("odin_pp_lanciafiamme_00.png")
	for frame in 0..<24 {
		flame_lab_frame(window, renderer, room, controller, cards, buffer, second_cell, true)
		if frame%2 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_lanciafiamme_%02d.png", 1+frame/2)) }
	}
	if second.health != 90-game.FLAME_DAMAGE { fmt.eprintln("mechanics lab: the second foe has", second.health); return false }

	// Two seconds on, touched again: his Bruciatura rises. Only the seconds of a touch count: the Bruciatura bites too.
	for _ in 0..<130 { flame_lab_frame(window, renderer, room, controller, cards, buffer, second_cell, true) }
	if flame_lab_burn(room, id_second) < 2*game.FLAME_BURN { fmt.eprintln("mechanics lab: the Bruciatura stayed at", flame_lab_burn(room, id_second)); return false }

	// A wall stops it, a low wall does not.
	first, second = &room.enemies[0], &room.enemies[1]
	first.position = grid.offset(p, -2, 0)
	if !level.set_tile(data, grid.offset(p, -1, 0), {kind = .Fence}) { fmt.eprintln("mechanics lab: no low wall"); return false }
	second.position = grid.offset(p, 0, -2)
	if !level.set_tile(data, grid.offset(p, 0, -1), {kind = .Wall}) { fmt.eprintln("mechanics lab: no wall"); return false }
	mechanics_lab_hold(room, id_first)
	mechanics_lab_hold(room, id_second)
	room.first_person.flame.memory = {}
	behind_low, behind_wall := first.health, second.health
	for _ in 0..<40 { flame_lab_frame(window, renderer, room, controller, cards, buffer, first.position, true) }
	artifacts.screenshot("odin_pp_lanciafiamme_wall.png")
	for _ in 0..<40 { flame_lab_frame(window, renderer, room, controller, cards, buffer, second.position, true) }
	if room.enemies[0].health >= behind_low { fmt.eprintln("mechanics lab: a low wall stopped the flame"); return false }
	if !(room.enemies[1].health >= behind_wall-3) { fmt.eprintln("mechanics lab: the flame went through a wall"); return false }
	if !level.set_tile(data, grid.offset(p, 0, -1), {kind = .Floor}) || !level.set_tile(data, grid.offset(p, -1, 0), {kind = .Floor}) { return false }

	// A barrel, a block of ice, a fire where the tip stays.
	far := grid.offset(p, 8, -4)
	for index in 0..<2 {
		foe := &room.enemies[index]
		foe.position = grid.offset(far, index, 0)
		mechanics_lab_hold(room, foe.id)
	}
	barrel := game.Grid_Object{id = room.next_object_id, kind = .Barrel, position = grid.offset(p, 2, 0), health = 1, max_health = 1}
	room.next_object_id += 1
	append(&room.objects, barrel)
	ice := game.Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = grid.offset(p, 0, 2), health = 4, max_health = 4}
	room.next_object_id += 1
	append(&room.objects, ice)
	for _ in 0..<40 { flame_lab_frame(window, renderer, room, controller, cards, buffer, ice.position, true) }
	if _, standing := game.object_index_by_id(room, ice.id); standing { fmt.eprintln("mechanics lab: the ice did not melt"); return false }
	for _ in 0..<30 { flame_lab_frame(window, renderer, room, controller, cards, buffer, barrel.position, true) }
	lit := false
	if index, standing := game.object_index_by_id(room, barrel.id); standing { lit = room.objects[index].detonation_pulse != 0 } else { lit = true }
	if !lit { fmt.eprintln("mechanics lab: the barrel did not catch"); return false }
	artifacts.screenshot("odin_pp_lanciafiamme_things.png")
	for _ in 0..<100 { flame_lab_frame(window, renderer, room, controller, cards, buffer, grid.offset(p, -4, 0), true) }
	if room.ground.fire_count == 0 { fmt.eprintln("mechanics lab: no fire where the tip stayed"); return false }

	// A step while it fires.
	from := room.player.position
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = .West}) {
		fmt.eprintln("mechanics lab: no step with the Lanciafiamme"); return false
	}
	for _ in 0..<40 { flame_lab_frame(window, renderer, room, controller, cards, buffer, grid.offset(p, -4, 0), true) }
	if room.player.position == from { fmt.eprintln("mechanics lab: he did not walk while firing"); return false }
	artifacts.screenshot("odin_pp_lanciafiamme_walk.png")
	// Let go: the breath.
	for _ in 0..<30 { flame_lab_frame(window, renderer, room, controller, cards, buffer, grid.offset(p, -4, 0), false) }
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds to count"); return false }
	for sfx in ([6]audio.Lab_Sfx{.Card_Flamethrower, .World_Flame_On, .World_Flame_Roar, .World_Flame_Off, .World_Flame_Crackle, .World_Flame_Catch}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: the flame's sound", sfx, "never sounded"); return false }
	}
	fmt.eprintf("mechanics lab Lanciafiamme: %d touches, %d fires, %d barrels, Bruciatura up to %d, on the board's camera; sounds: on %d, roar %d, off %d, crackle %d, catch %d\n",
		room.first_person.flame.hits, room.first_person.flame.fires, room.first_person.flame.barrels, flame_lab_burn(room, id_first),
		sounds.played[.World_Flame_On], sounds.played[.World_Flame_Roar], sounds.played[.World_Flame_Off], sounds.played[.World_Flame_Crackle], sounds.played[.World_Flame_Catch])
	return true
}
