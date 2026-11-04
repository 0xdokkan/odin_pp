package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"

// LANCIAFIAMME on the board (game/first_person_flame.odin, docs/piano-ia.md, Fase 13), provisional until its Fase 14: the
// pieces of flame as dots that go straight where they left, so the trail shows when he turns; a chip under VITA for its
// seconds. The board's point under the mouse is the aim (tactical_board_point).

FLAME_CHIP_COLOR :: rl.Color{255, 140, 40, 255}

// The chip under VITA: LANCIAFIAMME 14s.
flame_chip :: proc(room: ^game.Room, short: bool) -> (text: cstring, shown: bool) {
	if !game.first_person_flame_active(room) { return }
	left := int(math.ceil(room.first_person.remaining-0.0001))
	return fmt.ctprintf("%s %ds", "LNF" if short else "FIAMMA", left), true
}

// The point of the board under `mouse` (a canvas point), on the floor he stands on, in cells.
tactical_board_point :: proc(renderer: ^Renderer, room: ^game.Room, mouse: [2]f32) -> (point: [2]f32, ok: bool) {
	if renderer == nil || room == nil || room.player == nil || renderer.canvas_width <= 0 { return }
	ray := rl.GetScreenToWorldRayEx({mouse.x, mouse.y}, renderer.tactical.camera, i32(renderer.canvas_width), i32(renderer.canvas_height))
	if abs(ray.direction.y) < 0.0001 { return }
	ground := cell_overlay_ground(room.player.position)
	t := (ground-ray.position.y)/ray.direction.y
	if t < 0 { return }
	return {ray.position.x+ray.direction.x*t, ray.position.z+ray.direction.z*t}, true
}

draw_flame :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !game.first_person_flame_active(room) { return }
	f := &room.first_person.flame
	ground := cell_overlay_ground(room.player.position)+0.45
	rl.BeginBlendMode(.ADDITIVE)
	for age in 0..<game.FLAME_PIECES {
		piece := game.flame_piece_at(f, age)
		if !piece.alive { continue }
		distance := game.flame_piece_distance(age)
		point := game.flame_piece_point(piece^, distance)
		k := distance/game.FLAME_LENGTH
		size := 0.1+0.26*game.flame_width(distance)
		color := rl.Color{255, u8(220-170*k), u8(90-80*k), 200}
		rl.DrawCube({point.x, ground, point.y}, size, size, size, color)
	}
	rl.EndBlendMode()
}
