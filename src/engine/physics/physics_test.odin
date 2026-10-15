package physics

import "core:testing"

@(test)
test_platformer_dash_refill_and_cooldown_order :: proc(t: ^testing.T) {
	m2, _ := tile_map_create(12, 12, 16, .Empty)
	defer tile_map_destroy(&m2)
	m3, _ := voxel_map_create(12, 12, 12, 1)
	defer voxel_map_destroy(&m3)
	p2 := platformer_create({50, 50}, {10, 14})
	p3 := platformer3_create({5, 5, 5}, {0.6, 1.6, 0.6})
	p2.air_dashes_used, p3.air_dashes_used = 1, 1
	p2.dash_cooldown, p3.dash_cooldown = 0.01, 0.01
	p2.wall_side = -1
	_, wall := platformer_step(&p2, DEFAULT_PLATFORMER, {dash_pressed = true}, &m2, 0.01)
	_, air := platformer3_step(&p3, DEFAULT_PLATFORMER3, {dash_pressed = true}, &m3, 0.01)
	// Expiring cooldown permits a dash on the same step. A wall replenishes
	// the 2D controller's allowance; the airborne 3D controller stays spent.
	testing.expect(t, wall.dashed && !air.dashed)
	testing.expect_value(t, p2.air_dashes_used, 1)
	testing.expect_value(t, p3.air_dashes_used, 1)

	// Landing refreshes jump/dash allowances before processing input. A
	// zero-duration dash still emits its event, then normal jumping runs.
	p2.grounded, p3.grounded = true, true
	p2.wall_side = 0
	p2.dash_remaining, p3.dash_remaining = 0, 0
	p2.dash_cooldown, p3.dash_cooldown = 0, 0
	p2.air_jumps_left, p3.air_jumps_left = 0, 0
	params2, params3 := DEFAULT_PLATFORMER, DEFAULT_PLATFORMER3
	params2.dash_time, params3.dash_time = 0, 0
	_, ground2 := platformer_step(&p2, params2, {dash_pressed = true, jump_pressed = true, jump_held = true}, &m2, 0)
	_, ground3 := platformer3_step(&p3, params3, {dash_pressed = true, jump_pressed = true, jump_held = true}, &m3, 0)
	testing.expect(t, ground2.dashed && ground2.jumped && ground3.dashed && ground3.jumped)
	testing.expect_value(t, p2.air_dashes_used, 0)
	testing.expect_value(t, p3.air_dashes_used, 0)
	testing.expect_value(t, p2.air_jumps_left, params2.air_jumps)
	testing.expect_value(t, p3.air_jumps_left, params3.air_jumps)
}

@(test)
test_tile_ray_enters_open_map_from_outside :: proc(t: ^testing.T) {
	m, ok := tile_map_create(6, 3, 1, .Empty)
	testing.expect(t, ok)
	defer tile_map_destroy(&m)
	set_tile(&m, 3, 1, .Solid)
	hit := raycast_tiles(&m, {-3.5, 1.5}, {1, 0}, 12)
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.cell.x, 3)
	testing.expect(t, abs(hit.distance-6.5) < 0.0001)
	testing.expect(t, !raycast_tiles(&m, {-3.5, 1.5}, {-1, 0}, 12).hit)
	// The parallel, outside axis must not trigger an endless traversal.
	testing.expect(t, !raycast_tiles(&m, {-3.5, -1.5}, {1, 0}, 12).hit)
}

@(private = "file")
shape_of_char :: proc(ch: u8) -> Tile_Shape {
	switch ch {
	case '#':
		return .Solid
	case '-':
		return .One_Way
	}
	return .Empty
}

@(private = "file")
test_map :: proc(rows: []string) -> Tile_Map {
	m, ok := tile_map_from_rows(rows, 16, shape_of_char)
	assert(ok)
	return m
}

@(test)
test_body_lands_on_floor_and_stops :: proc(t: ^testing.T) {
	m := test_map({
		"........",
		"........",
		"........",
		"########",
	})
	defer tile_map_destroy(&m)
	body := Body2{position = {20, 0}, size = {10, 14}, velocity = {0, 200}}
	landed := false
	for _ in 0..<60 {
		r := move_body2(&m, &body, body.velocity*(1.0/60))
		landed = landed || r.on_ground
	}
	testing.expect(t, landed)
	testing.expect_value(t, body.position.y+body.size.y, f32(48))
	testing.expect_value(t, body.velocity.y, f32(0))
}

@(test)
test_walls_block_horizontal_motion :: proc(t: ^testing.T) {
	m := test_map({
		"#......#",
		"#......#",
		"########",
	})
	defer tile_map_destroy(&m)
	body := Body2{position = {20, 18}, size = {10, 14}}
	r := move_body2(&m, &body, {500, 0})
	testing.expect(t, r.hit_right)
	testing.expect_value(t, body.position.x+body.size.x, f32(7*16))
	r = move_body2(&m, &body, {-500, 0})
	testing.expect(t, r.hit_left)
	testing.expect_value(t, body.position.x, f32(16))
}

@(test)
test_one_way_platform_supports_from_above_only :: proc(t: ^testing.T) {
	m := test_map({
		"........",
		"..----..",
		"........",
		"########",
	})
	defer tile_map_destroy(&m)
	// Falling onto it from above lands on top.
	body := Body2{position = {40, 0}, size = {10, 12}}
	r := move_body2(&m, &body, {0, 10})
	testing.expect(t, r.on_ground && r.on_one_way)
	testing.expect_value(t, body.position.y+body.size.y, f32(16))
	// Dropping through ignores it.
	r = move_body2(&m, &body, {0, 10}, drop_through = true)
	testing.expect(t, !r.on_ground)
	// Jumping up from below passes through.
	below := Body2{position = {40, 34}, size = {10, 12}}
	r = move_body2(&m, &below, {0, -30})
	testing.expect(t, !r.on_ceiling)
	testing.expect_value(t, below.position.y, f32(4))
}

@(test)
test_fast_bodies_do_not_tunnel_through_thin_floors :: proc(t: ^testing.T) {
	m := test_map({
		"....",
		"....",
		"####",
		"....",
	}, )
	defer tile_map_destroy(&m)
	body := Body2{position = {10, 0}, size = {8, 8}}
	r := move_body2(&m, &body, {0, 200})
	testing.expect(t, r.on_ground)
	testing.expect_value(t, body.position.y+body.size.y, f32(32))
}

@(test)
test_coyote_time_allows_late_jump :: proc(t: ^testing.T) {
	m := test_map({
		"..........",
		"..........",
		"..........",
		"###.......",
	})
	defer tile_map_destroy(&m)
	p := platformer_create({30, 34}, {10, 14})
	params := DEFAULT_PLATFORMER
	dt := f32(1.0 / 120)
	// Settle on the ledge.
	for _ in 0..<10 {
		platformer_step(&p, params, {}, &m, dt)
	}
	testing.expect(t, p.grounded)
	// Run off the ledge, then press jump a few steps after leaving it.
	left_ground := -1
	jumped := false
	for i in 0..<120 {
		input := Platformer_Input{move = 1}
		if left_ground >= 0 && i == left_ground+4 {
			input.jump_pressed = true
			input.jump_held = true
		}
		_, ev := platformer_step(&p, params, input, &m, dt)
		if !p.grounded && left_ground < 0 {
			left_ground = i
		}
		if ev.jumped {
			jumped = true
			break
		}
	}
	testing.expect(t, jumped)
}

@(test)
test_releasing_jump_early_lowers_apex :: proc(t: ^testing.T) {
	apex :: proc(hold_steps: int) -> f32 {
		m := test_map({
			"....",
			"....",
			"....",
			"....",
			"....",
			"....",
			"....",
			"####",
		})
		defer tile_map_destroy(&m)
		p := platformer_create({20, 98}, {10, 14})
		params := DEFAULT_PLATFORMER
		params.air_jumps = 0
		dt := f32(1.0 / 120)
		for _ in 0..<5 {
			platformer_step(&p, params, {}, &m, dt)
		}
		highest := p.body.position.y
		for i in 0..<120 {
			input := Platformer_Input{jump_pressed = i == 0, jump_held = i < hold_steps}
			platformer_step(&p, params, input, &m, dt)
			highest = min(highest, p.body.position.y)
		}
		return highest
	}
	short_hop := apex(3)
	full_jump := apex(120)
	testing.expect(t, full_jump < short_hop-8)
}

@(test)
test_raycast_reports_first_solid_cell_and_normal :: proc(t: ^testing.T) {
	m := test_map({
		"........",
		"........",
		".....#..",
		"........",
	})
	defer tile_map_destroy(&m)
	hit := raycast_tiles(&m, {8, 40}, {1, 0}, 500)
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.cell.x, 5)
	testing.expect_value(t, hit.normal, Vec2{-1, 0})
	testing.expect(t, abs(hit.point.x-80) < 0.01)
	testing.expect(t, !line_of_sight(&m, {8, 40}, {120, 40}))
	testing.expect(t, line_of_sight(&m, {8, 8}, {120, 8}))
}

@(test)
test_circle_is_pushed_out_of_walls :: proc(t: ^testing.T) {
	m := test_map({
		"....",
		".#..",
		"....",
	})
	defer tile_map_destroy(&m)
	c := Vec2{14, 24}
	testing.expect(t, resolve_circle_tiles(&m, &c, 4))
	testing.expect(t, !circle_overlaps_rect(c, 4-0.01, cell_rect(&m, 1, 1)))
}

@(test)
test_voxel_body_slides_along_walls_and_lands :: proc(t: ^testing.T) {
	m, ok := voxel_map_create(8, 4, 8, 1)
	testing.expect(t, ok)
	defer voxel_map_destroy(&m)
	voxel_fill_box(&m, {0, 0, 0}, {7, 0, 7}, 1) // floor
	voxel_fill_box(&m, {5, 1, 0}, {5, 3, 7}, 2) // wall at x = 5
	body := Body3{position = {2, 2, 2}, size = {0.6, 1.8, 0.6}}
	r := move_body3(&m, &body, {0, -5, 0})
	testing.expect(t, r.on_ground)
	testing.expect_value(t, body.position.y, f32(1))
	r = move_body3(&m, &body, {10, 0, 1})
	testing.expect(t, r.hit_wall)
	testing.expect_value(t, r.wall_normal, Vec3{-1, 0, 0})
	testing.expect(t, abs(body.position.x+body.size.x-5) < 0.001)
	testing.expect(t, abs(body.position.z-3) < 0.001) // slid along z
}

@(test)
test_voxel_raycast_hits_wall_face :: proc(t: ^testing.T) {
	m, _ := voxel_map_create(8, 3, 8, 1, outside = 1)
	defer voxel_map_destroy(&m)
	voxel_set(&m, 6, 1, 4, 3)
	hit := raycast_voxels(&m, {1.5, 1.5, 4.5}, {1, 0, 0}, 20)
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.cell, [3]int{6, 1, 4})
	testing.expect_value(t, hit.value, u8(3))
	testing.expect_value(t, hit.normal, Vec3{-1, 0, 0})
	testing.expect(t, abs(hit.distance-4.5) < 0.001)
}

@(test)
test_platformer3_jumps_and_lands :: proc(t: ^testing.T) {
	m, _ := voxel_map_create(10, 6, 10, 1)
	defer voxel_map_destroy(&m)
	voxel_fill_box(&m, {0, 0, 0}, {9, 0, 9}, 1)
	p := platformer3_create({5, 1, 5}, {0.6, 1.6, 0.6})
	dt := f32(1.0 / 120)
	for _ in 0..<5 {
		platformer3_step(&p, DEFAULT_PLATFORMER3, {}, &m, dt)
	}
	testing.expect(t, p.grounded)
	peak := p.body.position.y
	landed := false
	for i in 0..<240 {
		_, ev := platformer3_step(&p, DEFAULT_PLATFORMER3, {jump_pressed = i == 0, jump_held = true}, &m, dt)
		peak = max(peak, p.body.position.y)
		if i > 0 && ev.landed {
			landed = true
		}
	}
	testing.expect(t, peak > 2.5)
	testing.expect(t, landed)
}

@(test)
test_ray_primitives :: proc(t: ^testing.T) {
	tb, hb := ray_aabb3({0, 0, 0}, {1, 0, 0}, {2, -1, -1}, {3, 1, 1})
	testing.expect(t, hb && abs(tb-2) < 1e-4)
	_, miss := ray_aabb3({0, 5, 0}, {1, 0, 0}, {2, -1, -1}, {3, 1, 1})
	testing.expect(t, !miss)
	ts, hs := ray_sphere({0, 0, 0}, {0, 0, 1}, {0, 0, 10}, 2)
	testing.expect(t, hs && abs(ts-8) < 1e-4)
}

@(test)
test_air_dashes_are_limited_per_airtime :: proc(t: ^testing.T) {
	m := test_map({
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"##########",
	})
	defer tile_map_destroy(&m)
	p := platformer_create({60, 20}, {10, 14})
	params := DEFAULT_PLATFORMER
	params.dash_cooldown = 0
	dt := f32(1.0 / 120)
	dashes := 0
	for i in 0..<40 {
		_, ev := platformer_step(&p, params, {dash_pressed = i == 0 || i == 30}, &m, dt)
		if ev.dashed {
			dashes += 1
		}
	}
	testing.expect_value(t, dashes, 1)
	params.air_dashes = 0
	for i in 0..<40 {
		_, ev := platformer_step(&p, params, {dash_pressed = i == 0}, &m, dt)
		if ev.dashed {
			dashes += 1
		}
	}
	testing.expect_value(t, dashes, 2)
}
