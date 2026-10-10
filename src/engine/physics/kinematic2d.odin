package physics

import "core:math"

// Axis-aligned box moved against a Tile_Map. position is the top-left corner.
Body2 :: struct {
	position: Vec2,
	size:     Vec2,
	velocity: Vec2,
}

body2_rect :: proc "contextless" (b: Body2) -> Rect {
	return Rect{b.position.x, b.position.y, b.size.x, b.size.y}
}

body2_center :: proc "contextless" (b: Body2) -> Vec2 {
	return b.position + b.size*0.5
}

Move_Result2 :: struct {
	on_ground, on_ceiling: bool,
	hit_left, hit_right:   bool,
	on_one_way:            bool,
}

// Moves `delta` resolving x then y, zeroing the blocked velocity component.
// Long moves are split so no step exceeds half a tile (no tunnelling).
move_body2 :: proc(m: ^Tile_Map, body: ^Body2, delta: Vec2, drop_through := false) -> Move_Result2 {
	result: Move_Result2
	limit := m.tile_size * 0.5
	steps := max(1, int(math.ceil(max(abs(delta.x), abs(delta.y)) / limit)))
	part := delta / f32(steps)
	for _ in 0..<steps {
		move_axis_x(m, body, part.x, &result)
		move_axis_y(m, body, part.y, drop_through, &result)
	}
	if delta.y == 0 {
		// Standing still vertically: probe one epsilon down for ground contact.
		feet := body.position.y + body.size.y
		below_y := int(math.floor((feet + EPSILON*4) / m.tile_size))
		x0, x1 := cell_span(m, body.position.x, body.size.x)
		on_boundary := abs(feet - f32(below_y)*m.tile_size) < EPSILON*8
		for x in x0..=x1 {
			shape := tile_at(m, x, below_y)
			if on_boundary && (shape == .Solid || (shape == .One_Way && !drop_through)) {
				result.on_ground = true
				result.on_one_way = result.on_one_way || shape == .One_Way
			}
		}
	}
	return result
}

@(private)
move_axis_x :: proc(m: ^Tile_Map, body: ^Body2, dx: f32, result: ^Move_Result2) {
	if dx == 0 {
		return
	}
	body.position.x += dx
	y0, y1 := cell_span(m, body.position.y, body.size.y)
	if dx > 0 {
		column := int(math.floor((body.position.x + body.size.x - EPSILON) / m.tile_size))
		for y in y0..=y1 {
			if tile_at(m, column, y) == .Solid {
				body.position.x = f32(column)*m.tile_size - body.size.x
				body.velocity.x = min(body.velocity.x, 0)
				result.hit_right = true
				return
			}
		}
	} else {
		column := int(math.floor(body.position.x / m.tile_size))
		for y in y0..=y1 {
			if tile_at(m, column, y) == .Solid {
				body.position.x = f32(column+1) * m.tile_size
				body.velocity.x = max(body.velocity.x, 0)
				result.hit_left = true
				return
			}
		}
	}
}

@(private)
move_axis_y :: proc(m: ^Tile_Map, body: ^Body2, dy: f32, drop_through: bool, result: ^Move_Result2) {
	if dy == 0 {
		return
	}
	previous_bottom := body.position.y + body.size.y
	body.position.y += dy
	x0, x1 := cell_span(m, body.position.x, body.size.x)
	if dy > 0 {
		row := int(math.floor((body.position.y + body.size.y - EPSILON) / m.tile_size))
		row_top := f32(row) * m.tile_size
		for x in x0..=x1 {
			shape := tile_at(m, x, row)
			one_way_lands := shape == .One_Way && !drop_through && previous_bottom <= row_top+EPSILON*8
			if shape == .Solid || one_way_lands {
				body.position.y = row_top - body.size.y
				body.velocity.y = min(body.velocity.y, 0)
				result.on_ground = true
				result.on_one_way = shape == .One_Way
				return
			}
		}
	} else {
		row := int(math.floor(body.position.y / m.tile_size))
		for x in x0..=x1 {
			if tile_at(m, x, row) == .Solid {
				body.position.y = f32(row+1) * m.tile_size
				body.velocity.y = max(body.velocity.y, 0)
				result.on_ceiling = true
				return
			}
		}
	}
}

// Pushes a circle out of every Solid cell it overlaps (top-down games).
// Returns true when it touched a wall.
resolve_circle_tiles :: proc(m: ^Tile_Map, center: ^Vec2, radius: f32) -> bool {
	touched := false
	for _ in 0..<3 {
		moved := false
		x0, x1 := cell_span(m, center.x-radius, radius*2)
		y0, y1 := cell_span(m, center.y-radius, radius*2)
		for y in y0..=y1 {
			for x in x0..=x1 {
				if tile_at(m, x, y) != .Solid {
					continue
				}
				r := cell_rect(m, x, y)
				closest := closest_point_on_rect(r, center^)
				d := center^ - closest
				dist2 := d.x*d.x + d.y*d.y
				if dist2 >= radius*radius {
					continue
				}
				if dist2 < EPSILON*EPSILON {
					// Centre inside the cell: leave through the nearest edge.
					c := rect_center(r)
					offset := center^ - c
					if abs(offset.x) > abs(offset.y) {
						center.x = r.x - radius if offset.x < 0 else r.x + r.width + radius
					} else {
						center.y = r.y - radius if offset.y < 0 else r.y + r.height + radius
					}
				} else {
					dist := math.sqrt(dist2)
					center^ += d / dist * (radius - dist)
				}
				moved = true
				touched = true
			}
		}
		if !moved {
			break
		}
	}
	return touched
}
