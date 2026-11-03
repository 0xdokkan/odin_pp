package render

import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"

// THE IA'S ADVICE ON THE BOARD (docs/piano-ia.md, Fase 2: the provisional marks; the real ones are Fase 5's): a cyan
// square on the cell to step or land on, a cyan cross on the foe to strike, the word over the player. The pilot
// (run/advisor_driver.odin) sets it every frame; nothing while the IA is off or stands still.

Advice_Mark :: enum u8 { None, Step, Bump, Wait, Defend }

Advice_View :: struct {
	mark: Advice_Mark,
	cell: grid.Position,
	word: cstring,
}

@(private)
advice_shown :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return renderer.tactical.advice.mark != .None && game.ia_active(room)
}

// The floor's mark, in the world's pass.
draw_advice_floor :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !advice_shown(renderer, room) { return }
	advice := renderer.tactical.advice
	if !tactical_render_visible(renderer, advice.cell) { return }
	ground := 0.05+cell_overlay_ground(advice.cell)
	center := rl.Vector3{f32(advice.cell.x)+0.5, ground, f32(advice.cell.y)+0.5}
	#partial switch advice.mark {
	case .Step, .Defend:
		rl.DrawPlane(center, {0.8, 0.8}, {IA_COLOR.r, IA_COLOR.g, IA_COLOR.b, 60})
		rl.DrawCubeWires(center, 0.8, 0.01, 0.8, IA_COLOR)
		rl.DrawCubeWires(center, 0.7, 0.01, 0.7, IA_COLOR)
	case .Bump:
		// Two strokes of small cubes, corner to corner, a little over the foe's feet.
		for k in 0..<9 {
			t := -0.36+0.09*f32(k)
			rl.DrawCube({center.x+t, ground+0.02, center.z+t}, 0.1, 0.03, 0.1, IA_COLOR)
			rl.DrawCube({center.x+t, ground+0.02, center.z-t}, 0.1, 0.03, 0.1, IA_COLOR)
		}
	}
}

// The word over the player, with the labels.
draw_advice_word :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !advice_shown(renderer, room) || renderer.tactical.advice.word == nil { return }
	p := room.player.position
	draw_tactical_label(renderer, tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 1.75), renderer.tactical.advice.word, "", IA_COLOR)
}
