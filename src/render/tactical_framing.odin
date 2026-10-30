package render

import "core:math"
import rl "vendor:raylib"
import grid "../engine/grid"

// A camera-space sphere test discards geometry that cannot reach the canvas.
// This is deliberately independent of gameplay sight: it never reveals cells,
// records exploration, or changes the targets accepted by the picker.
Tactical_Draw_Frustum :: struct {
	valid, perspective: bool,
	eye, right, up, forward: rl.Vector3,
	horizontal, vertical, horizontal_margin, vertical_margin: f32,
}

@(private)
tactical_draw_frustum :: proc(camera: rl.Camera3D, width, height: f32) -> (result: Tactical_Draw_Frustum) {
	if width <= 0 || height <= 0 || camera.fovy <= 0 || rl.Vector3LengthSqr(camera.target-camera.position) < 0.0001 { return }
	result.valid, result.perspective = true, camera.projection == .PERSPECTIVE
	result.eye = camera.position
	result.forward = rl.Vector3Normalize(camera.target-camera.position)
	result.right = rl.Vector3Normalize(rl.Vector3CrossProduct(result.forward, camera.up))
	result.up = rl.Vector3CrossProduct(result.right, result.forward)
	result.vertical = math.tan(camera.fovy*math.PI/360) if result.perspective else camera.fovy*0.5
	result.horizontal = result.vertical*width/height
	result.horizontal_margin = math.sqrt(1+result.horizontal*result.horizontal)
	result.vertical_margin = math.sqrt(1+result.vertical*result.vertical)
	return
}

@(private)
tactical_cell_on_screen :: proc(renderer: ^Renderer, cell: grid.Position) -> bool {
	f := &renderer.tactical.draw_frustum
	if !f.valid { return true }
	// Covers a complete wall, cap, lamp, floor bevel, shadow and drifting mote.
	// The generous sphere also avoids geometry popping at the edge of the view.
	// It stands on the cell's own ground (its layer's, the map's base taken off):
	// at a fixed height a mountain's flank was culled while on screen (section 12
	// of docs/piano-profondita.md).
	radius :: f32(1.8)
	delta := rl.Vector3{f32(cell.x)+0.5, cell_ground(cell)+0.65, f32(cell.y)+0.5}-f.eye
	z := rl.Vector3DotProduct(delta, f.forward)
	if z+radius <= 0 { return false }
	x, y := abs(rl.Vector3DotProduct(delta, f.right)), abs(rl.Vector3DotProduct(delta, f.up))
	if !f.perspective { return x <= f.horizontal+radius && y <= f.vertical+radius }
	return x <= z*f.horizontal+radius*f.horizontal_margin && y <= z*f.vertical+radius*f.vertical_margin
}

// Fit the full board and standing actors into the map's actual scissored area.
// The orbit distance remains a relative zoom, so the wheel still intentionally
// permits a closer inspection and reset restores an unclipped overview.
@(private)
tactical_hologram_camera :: proc(renderer: ^Renderer, width, height: int, orbit: Tactical_Orbit) -> rl.Camera3D {
	target := rl.Vector3{f32(width)*0.5, 0, f32(height)*0.5}
	view_orbit := orbit
	view_orbit.distance = 1
	unit_camera := tactical_orbit_camera(view_orbit, target, true)
	back := unit_camera.position-target
	right := rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, back))
	up := rl.Vector3CrossProduct(back, right)
	viewport := tactical_map_drag_bounds(renderer)
	padding :: f32(12)
	vertical := math.tan(unit_camera.fovy*math.PI/360)
	horizontal := vertical*renderer.canvas_width/renderer.canvas_height
	left := (2*(viewport.x+padding)/renderer.canvas_width-1)*horizontal
	right_limit := (2*(viewport.x+viewport.width-padding)/renderer.canvas_width-1)*horizontal
	bottom := (1-2*(viewport.y+viewport.height-padding)/renderer.canvas_height)*vertical
	top := (1-2*(viewport.y+padding)/renderer.canvas_height)*vertical
	max_right, max_top := f32(-1e30), f32(-1e30)
	min_left, min_bottom := f32(1e30), f32(1e30)
	nearest := f32(0)
	for x in ([2]f32{-0.3, f32(width)+0.3}) {
		for y in ([2]f32{-0.3, 2.0}) {
			for z in ([2]f32{-0.3, f32(height)+0.3}) {
				delta := rl.Vector3{x, y, z}-target
				near := rl.Vector3DotProduct(delta, back)
				x_view, y_view := rl.Vector3DotProduct(delta, right), rl.Vector3DotProduct(delta, up)
				max_right = max(max_right, x_view+right_limit*near)
				min_left = min(min_left, x_view+left*near)
				max_top = max(max_top, y_view+top*near)
				min_bottom = min(min_bottom, y_view+bottom*near)
				nearest = max(nearest, near)
			}
		}
	}
	// Perspective makes the near corner larger than the far one. Fixing the
	// aim at the board's geometric center wastes much of the upper viewport.
	// These linear frustum constraints jointly solve distance and the camera's
	// lateral aim, fitting both sides rather than applying a symmetric margin.
	distance := max(nearest+1, (max_right-min_left)/(right_limit-left), (max_top-min_bottom)/(top-bottom))
	horizontal_offset := (max_right+min_left-(right_limit+left)*distance)*0.5
	vertical_offset := (max_top+min_bottom-(top+bottom)*distance)*0.5
	target += right*horizontal_offset+up*vertical_offset
	view_orbit.distance = distance*orbit.distance/12.5
	return tactical_orbit_camera(view_orbit, target, true)
}
