package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// THE ARCHERS' REAL ARROWS (game/enemy_arrow.odin, docs/piano-succo.md,
// Fase 3), as the board shows them for now (their look is Fase 4's): the
// cells an aimed or flying arrow will cross lit on the floor, going out as it
// passes them, and the arrow itself, a dart over the board with its shadow.

ENEMY_ARROW_COURSE_COLOR :: rl.Color{255, 92, 72, 255}
ENEMY_ARROW_HEIGHT :: f32(0.62)
ENEMY_ARROW_LENGTH :: f32(0.5)

// The cells from the `from`th of a line to its end (a wall, a cover, its
// range), lit at `alpha`.
@(private = "file")
draw_enemy_arrow_course :: proc(renderer: ^Renderer, room: ^game.Room, origin, step: grid.Position, from: int, progress, alpha: f32) {
	_, cells := game.enemy_arrow_course_end(room, origin, step)
	line := game.enemy_arrow_line(origin, step)
	for k in max(from, 1)..=cells {
		cell := game.enemy_arrow_cell(line, k)
		if !tactical_render_visible(renderer, cell) { continue }
		draw_intent_cell(cell, progress, ENEMY_ARROW_COURSE_COLOR, alpha)
	}
}

// In the ground pass: the aimed archers' lines, and the flying arrows' rest.
@(private)
draw_enemy_arrow_courses :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.phase != .Combat { return }
	now := tactical_world_time(renderer)
	for &enemy in room.enemies {
		if !game.enemy_attack_is_arrow(&enemy, &enemy.intent) || game.enemy_is_out_of_play(room, enemy.id) || game.enemy_is_staggered(room, &enemy) { continue }
		step, ok := game.enemy_arrow_aim_step(&enemy)
		if !ok { continue }
		left, _, progress := intent_timing(room, &enemy)
		lit := intent_flicker(left, now, 0.25)
		draw_enemy_arrow_course(renderer, room, enemy.position, step, 1, progress*0.6, (0.22+0.25*intent_loudness(left))*lit)
	}
	for arrow in room.arrows.items[:room.arrows.count] {
		at := game.enemy_arrow_distance(room, arrow)
		draw_enemy_arrow_course(renderer, room, game.enemy_arrow_origin(arrow), game.enemy_arrow_step(arrow), int(math.floor(at+0.5))+1, 1, 0.6)
	}
}

// In the paper pass: each arrow in flight, a dart with its shadow.
@(private)
draw_enemy_arrows :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil { return }
	for arrow in room.arrows.items[:room.arrows.count] {
		at := game.enemy_arrow_distance(room, arrow)
		way := view.Vec2{f32(arrow.step.x), f32(arrow.step.y)}
		centre := view.Vec2{f32(arrow.origin.x)+way.x*at, f32(arrow.origin.y)+way.y*at}
		cell := grid.Position{x = int(math.round(centre.x)), y = int(math.round(centre.y)), layer = i8(arrow.origin.z)}
		if !tactical_render_visible(renderer, cell) { continue }
		ground := point_ground(centre)
		tip := rl.Vector3{centre.x+0.5+way.x*ENEMY_ARROW_LENGTH*0.5, ground+ENEMY_ARROW_HEIGHT, centre.y+0.5+way.y*ENEMY_ARROW_LENGTH*0.5}
		tail := tip-rl.Vector3{way.x, 0, way.y}*ENEMY_ARROW_LENGTH
		rl.DrawCylinderEx(tail, tip, 0.025, 0.025, 6, {92, 64, 40, 255})
		rl.DrawCylinderEx(tip, tip+rl.Vector3{way.x, 0, way.y}*0.12, 0.05, 0, 6, {200, 210, 220, 255})
		rl.DrawCylinderEx(tail, tail+rl.Vector3{way.x, 0, way.y}*0.1, 0.07, 0.02, 4, {236, 72, 64, 255})
		rl.DrawCircle3D({centre.x+0.5, ground+0.03, centre.y+0.5}, 0.12, {1, 0, 0}, 90, {0, 0, 0, 90})
	}
}
