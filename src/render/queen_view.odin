package render

import rl "vendor:raylib"

// REGINA on the board (game/queen.odin, docs/piano-ia.md, Fase 11), provisional until its Fase 12: a simple ivory chess
// queen that slides along her line to her foe, the line lit on the floor while she runs.

QUEEN_IVORY :: rl.Color{226, 214, 186, 255}
QUEEN_IVORY_SHADE :: rl.Color{176, 160, 128, 255}

@(private)
draw_queen_object :: proc(renderer: ^Renderer, object: Presentation_Grid_Object, bounds: rl.BoundingBox) {
	cx, cz := (bounds.min.x+bounds.max.x)*0.5, (bounds.min.z+bounds.max.z)*0.5
	ground := bounds.min.y
	// The run: from the cell she left, quickly.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Queen_Ran || cue.event.target != object.entity { continue }
		left := 1-presentation_cue_progress(cue)
		cx += (f32(cue.event.from_position.x)-f32(cue.event.to_position.x))*left
		cz += (f32(cue.event.from_position.y)-f32(cue.event.to_position.y))*left
	}
	draw_resin_cube_v(renderer, {cx, ground+0.05, cz}, {0.56, 0.1, 0.56}, QUEEN_IVORY_SHADE)
	draw_resin_cube_v(renderer, {cx, ground+0.16, cz}, {0.42, 0.12, 0.42}, QUEEN_IVORY)
	draw_resin_cube_v(renderer, {cx, ground+0.42, cz}, {0.22, 0.4, 0.22}, QUEEN_IVORY)
	draw_resin_cube_v(renderer, {cx, ground+0.66, cz}, {0.36, 0.08, 0.36}, QUEEN_IVORY_SHADE)
	draw_resin_cube_v(renderer, {cx, ground+0.78, cz}, {0.26, 0.16, 0.26}, QUEEN_IVORY)
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
		draw_resin_cube_v(renderer, {cx+corner.x*0.12, ground+0.92, cz+corner.y*0.12}, {0.07, 0.1, 0.07}, QUEEN_IVORY_SHADE)
	}
	rl.DrawSphereEx({cx, ground+0.99, cz}, 0.05, 6, 8, {214, 60, 66, 255})
}

// The line she runs along, lit for the run.
@(private)
draw_queen_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	if cue.kind != .Queen_Ran { return }
	from, to := cue.event.from_position, cue.event.to_position
	ground := cell_overlay_ground(from)+0.03
	color := color_with_opacity(QUEEN_IVORY, 1-presentation_cue_progress(cue))
	for side in ([3]f32{-0.03, 0, 0.03}) {
		rl.DrawLine3D({f32(from.x)+0.5+side, ground, f32(from.y)+0.5-side}, {f32(to.x)+0.5+side, ground, f32(to.y)+0.5-side}, color)
	}
}
