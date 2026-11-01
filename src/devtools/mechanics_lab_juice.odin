package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import rl "vendor:raylib"
import app "../engine/app"
import game "../game"
import render "../render"

// THE JUICE (render/juice.odin, docs/piano-succo.md, Fase 1): the lab's F9
// tried in the real window. The board's camera shakes and comes back still;
// the hit-stop holds the drawings (their clock stands) for its frames.
// Stills odin_pp_mechanics_lab_juice_NN.png.
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
	return true
}
