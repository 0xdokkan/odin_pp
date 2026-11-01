package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import rl "vendor:raylib"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// THE JUICE (render/juice.odin, docs/piano-succo.md, Fase 1): the lab's F9
// tried in the real window. The board's camera shakes and comes back still;
// the hit-stop holds the drawings (their clock stands) for its frames.
// Stills odin_pp_mechanics_lab_juice_NN.png. Then (Fase 2, juice_blows.odin)
// a bump on a foe: its hit-stop, its kick and its paper bits, stills
// odin_pp_living_juice_blow_NN.png. Then (Fase 2, juice_blows.odin)
// a bump on a foe: its hit-stop, its kick and its paper bits, stills
// odin_pp_mechanics_lab_juice_blow_NN.png.
mechanics_lab_juice :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	if render.first_person_amount(renderer) > 0 { fmt.eprintln("mechanics lab: the juice's act began behind the player's eyes"); return false }
	steady := renderer.tactical.camera
	run_session.mechanics_lab_try_juice(renderer)
	held, still_drawings, shaken := 0, 0, f32(0)
	for index in 0..<40 {
		before := renderer.sprite_assets.elapsed
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if renderer.frame_had_hit_stop {
			held += 1
			if renderer.sprite_assets.elapsed == before { still_drawings += 1 }
		}
		shaken = max(shaken, rl.Vector3Distance(renderer.tactical.camera.position, steady.position))
		if index%4 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_mechanics_lab_juice_%02d.png", index/4)) }
	}
	back := rl.Vector3Distance(renderer.tactical.camera.position, steady.position)
	if held < 4 || still_drawings != held || shaken < 0.01 || back > 0.001 {
		fmt.eprintln("mechanics lab: the juice did not shake and hold:", held, "frames held,", still_drawings, "with still drawings, shaken", shaken, "back by", back)
		return false
	}
	fmt.eprintf("mechanics lab juice: %d frames held, the camera shaken up to %.3f cells and back\n", held, shaken)
	return mechanics_lab_juice_blow(window, renderer, room, controller, cards, buffer)
}

// A bump on a foe beside the player, in a fresh arena.
@(private = "file")
mechanics_lab_juice_blow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the juice's blow") { return false }
	foe_id := mechanics_lab_spawn_enemy(room, grid.offset(room.player.position, 1, 0), 60)
	if foe_id == 0 { fmt.eprintln("mechanics lab: no room for the juice's foe"); return false }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	before := renderer.tactical.juice_blows.blows
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .East}) {
		fmt.eprintln("mechanics lab: the juice's bump was not committed"); return false
	}
	held, kicked, frame := 0, f32(0), 0
	foe := game.enemy_entity(foe_id)
	for _ in 0..<60 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "juice_blow", 3, &frame)
		if renderer.frame_had_hit_stop { held += 1 }
		k := render.juice_kick_offset(renderer, foe)
		kicked = max(kicked, abs(k.x)+abs(k.y))
	}
	juiced := renderer.tactical.juice_blows.blows-before
	if juiced < 1 || held < 3 || kicked < 0.1 {
		fmt.eprintln("mechanics lab: the bump gave no juice:", juiced, "blows,", held, "frames held, kicked", kicked); return false
	}
	fmt.eprintf("mechanics lab juice: a bump juiced (%d), %d frames held, its foe kicked %.2f cells\n", juiced, held, kicked)
	return true
}
