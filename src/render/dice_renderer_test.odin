package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"

@(test)
test_dice_bevel_mesh_is_closed_outward_and_removes_the_sharp_cube_corners :: proc(t: ^testing.T) {
	mesh := build_dice_bevel_mesh()
	testing.expect_value(t, mesh.count, DICE_BODY_TRIANGLES)
	volume: f32
	for triangle in mesh.triangles[:mesh.count] {
		cross := rl.Vector3CrossProduct(triangle.points[1]-triangle.points[0], triangle.points[2]-triangle.points[0])
		testing.expect(t, rl.Vector3DotProduct(cross, triangle.normal) > 0)
		testing.expect(t, rl.Vector3DotProduct(triangle.points[0], triangle.normal) > 0)
		volume += rl.Vector3DotProduct(triangle.points[0], rl.Vector3CrossProduct(triangle.points[1], triangle.points[2]))/6
		for point in triangle.points {
			testing.expect(t, abs(point.x) <= 0.5 && abs(point.y) <= 0.5 && abs(point.z) <= 0.5)
			testing.expect(t, abs(point.x)+abs(point.y)+abs(point.z) < 1.5,
				"real corner geometry must be chamfered, not only a rounded texture")
		}
		for edge in 0..<3 {
			a, b := triangle.points[edge], triangle.points[(edge+1)%3]
			matches := 0
			for other in mesh.triangles[:mesh.count] {
				for oe in 0..<3 {
					c, d := other.points[oe], other.points[(oe+1)%3]
					if (a == c && b == d) || (a == d && b == c) {matches += 1}
				}
			}
			testing.expect_value(t, matches, 2)
		}
	}
	testing.expect(t, volume > 0.8 && volume < 1)
}

@(test)
test_dice_pips_fit_flat_faces_and_never_overlap_the_bevels :: proc(t: ^testing.T) {
	for value in i32(1)..=6 {
		positions, count := dice_pip_positions(value)
		testing.expect_value(t, count, int(value))
		for point, index in positions[:count] {
			testing.expect(t, abs(point.x)+0.068 < 0.5-DICE_BEVEL && abs(point.y)+0.068 < 0.5-DICE_BEVEL)
			for previous in positions[:index] {testing.expect(t, rl.Vector2Distance(point, previous) > 0.136)}
		}
	}
}

@(test)
test_dice_pool_window_layout_keeps_initial_physical_mesh_above_real_letterbox :: proc(t: ^testing.T) {
	areas := [4]rl.Rectangle{{0, 0, 960, 540}, {0, 243, 948, 533.25}, {60, 240, 960, 540}, {0, 900, 640, 360}}
	windows := [4]rl.Vector2{{960, 540}, {948, 1020}, {1080, 1080}, {640, 2160}}
	mesh := build_dice_bevel_mesh()
	for area, index in areas {
		layout := dice_pool_layout(windows[index].x, windows[index].y, area)
		testing.expect(t, layout.valid)
		testing.expect(t, layout.release_height <= 24)
		if index < 3 {testing.expect_value(t, layout.pixels_per_world, 88*layout.scale)}
		throw: Dice_Throw
		build_dice_throw(&throw, 3, 101, layout.release_height)
		initial := sample_dice_throw(&throw, 0)
		for die in 0..<3 {
			for triangle in mesh.triangles[:mesh.count] {
				for point in triangle.points {
					world := initial.positions[die]+rl.Vector3RotateByQuaternion(point, initial.orientations[die])
					testing.expect(t, dice_world_to_window(layout, world).y < 0,
						"the entire physical die must start above the actual window, including letterbox")
				}
			}
		}
		for frame in throw.frames {
			for die in 0..<3 {
				for corner in 0..<8 {
					point := rl.Vector3{0.5 if corner&1 != 0 else -0.5,
						0.5 if corner&2 != 0 else -0.5, 0.5 if corner&4 != 0 else -0.5}
					world := frame.positions[die]+rl.Vector3RotateByQuaternion(point, frame.orientations[die])
					x := dice_world_to_window(layout, world).x
					testing.expect(t, x > 0 && x < windows[index].x,
						"enlarging a tall-window throw must not push any rotating die outside the horizontal viewport")
				}
			}
		}
		testing.expect_value(t, dice_world_to_window(layout, {}), layout.ground)
		final := sample_dice_throw(&throw, 1)
		for die in 0..<3 {
			center := dice_world_to_window(layout, final.positions[die])
			testing.expect(t, center.x > 0 && center.x < windows[index].x && center.y > 0 && center.y < windows[index].y)
		}
	}
}

@(test)
test_dice_pool_reuses_throw_and_keeps_texture_budget_bounded :: proc(t: ^testing.T) {
	layout := dice_pool_layout(948, 1020, {0, 243, 948, 533.25})
	renderer: Dice_Renderer
	roll := game.Dice_Roll{faces = {1, 4, 6}, sides = 6, count = 3, total = 11}
	prepare_dice_pool(&renderer, roll, 113, layout)
	initial := renderer.throw_state.frames[0]
	steps := renderer.throw_state.physics_steps
	prepare_dice_pool(&renderer, roll, 113, dice_pool_layout(1920, 1080))
	testing.expect_value(t, renderer.throw_state.frames[0], initial)
	testing.expect_value(t, renderer.throw_state.physics_steps, steps)
	for size in ([4]rl.Vector2{{960, 540}, {948, 1020}, {8192, 8192}, {16384, 1080}}) {
		w, h := dice_texture_dimensions(size.x, size.y)
		testing.expect(t, w > 0 && h > 0 && w <= DICE_MAX_TEXTURE_EDGE && h <= DICE_MAX_TEXTURE_EDGE)
		testing.expect(t, w*h <= DICE_MAX_TEXTURE_PIXELS)
	}
	testing.expect(t, !dice_pool_layout(0, 100).valid)
	testing.expect(t, !dice_pool_layout(100, math.nan_f32()).valid)
	testing.expect(t, !dice_pool_layout(100, 100, {500, 0, 100, 100}).valid)
	testing.expect(t, !dice_pool_roll_valid({count = 4}))
	testing.expect(t, !dice_pool_roll_valid({faces = {3, 5, 6}, sides = 6, count = 2, total = 8}))
	// A roll must name a die of the ladder, and its faces must fit it.
	testing.expect(t, !dice_pool_roll_valid({faces = {3, 5, 0}, count = 2, total = 8}))
	testing.expect(t, !dice_pool_roll_valid({faces = {3, 5, 0}, sides = 4, count = 2, total = 8}))
	testing.expect(t, dice_pool_roll_valid({faces = {3, 5, 0}, sides = 8, count = 2, total = 8}))
}

@(test)
test_dice_pool_total_keeps_clear_of_final_meshes_and_the_hand :: proc(t: ^testing.T) {
	for seed in u64(1)..=12 {
		for count in 2..=3 {
			renderer: Dice_Renderer
			roll := game.Dice_Roll{faces = {2, 5, 0}, sides = 6, count = i32(count), total = 7}
			if count == 3 {roll.faces[2], roll.total = 6, 13}
			layout := dice_pool_layout(948, 1020, {0, 243, 948, 533.25})
			prepare_dice_pool(&renderer, roll, seed, layout)
			target := dice_total_target(&renderer, layout)
			label := dice_total_bounds(target, layout.scale)
			testing.expect(t, label.y+label.height <= layout.game_area.y+layout.game_area.height*0.865-13*layout.scale)
			for index in 0..<count {
				die := dice_final_projected_bounds(&renderer, layout, index)
				testing.expect(t, !rl.CheckCollisionRecs(label, die), "the total must remain legible beside every settled die")
			}
			renderer.frame = sample_dice_throw(&renderer.throw_state, DICE_PHYSICS_REVEAL_PROGRESS)
			testing.expect_value(t, dice_total_target(&renderer, layout), target)
		}
	}
}
