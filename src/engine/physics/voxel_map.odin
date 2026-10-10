package physics

import "core:math"

// Solid/empty volume for 3D minigames. y is up; a cell value of 0 is empty and
// any other value is a solid material id the renderer may colour.
Voxel_Map :: struct {
	width, height, depth: int,
	voxel_size:           f32,
	cells:                []u8,
	// Value reported outside the volume: 0 lets bodies fall out of the world,
	// non-zero turns the bounds into walls.
	outside:              u8,
}

voxel_map_create :: proc(width, height, depth: int, voxel_size: f32, outside := u8(0),
	allocator := context.allocator) -> (Voxel_Map, bool) {
	if width <= 0 || height <= 0 || depth <= 0 || voxel_size <= 0 {
		return {}, false
	}
	cells := make([]u8, width*height*depth, allocator)
	return Voxel_Map{width = width, height = height, depth = depth, voxel_size = voxel_size,
		cells = cells, outside = outside}, true
}

voxel_map_destroy :: proc(m: ^Voxel_Map, allocator := context.allocator) {
	delete(m.cells, allocator)
	m^ = {}
}

// Edge length used by every query; a zero-value map behaves as size 1 instead
// of dividing by zero.
voxel_size_of :: proc "contextless" (m: ^Voxel_Map) -> f32 {
	return m.voxel_size if m.voxel_size > 0 else 1
}

voxel_in_bounds :: proc "contextless" (m: ^Voxel_Map, x, y, z: int) -> bool {
	return x >= 0 && y >= 0 && z >= 0 && x < m.width && y < m.height && z < m.depth
}

voxel_get :: proc "contextless" (m: ^Voxel_Map, x, y, z: int) -> u8 {
	if !voxel_in_bounds(m, x, y, z) {
		return m.outside
	}
	return m.cells[(y*m.depth+z)*m.width+x]
}

voxel_set :: proc "contextless" (m: ^Voxel_Map, x, y, z: int, value: u8) -> bool {
	if !voxel_in_bounds(m, x, y, z) {
		return false
	}
	m.cells[(y*m.depth+z)*m.width+x] = value
	return true
}

voxel_fill_box :: proc "contextless" (m: ^Voxel_Map, from, to: [3]int, value: u8) {
	for y in min(from.y, to.y)..=max(from.y, to.y) {
		for z in min(from.z, to.z)..=max(from.z, to.z) {
			for x in min(from.x, to.x)..=max(from.x, to.x) {
				voxel_set(m, x, y, z, value)
			}
		}
	}
}

voxel_of :: proc "contextless" (m: ^Voxel_Map, p: Vec3) -> [3]int {
	s := voxel_size_of(m)
	return [3]int{int(math.floor(p.x / s)), int(math.floor(p.y / s)), int(math.floor(p.z / s))}
}

voxel_world_size :: proc "contextless" (m: ^Voxel_Map) -> Vec3 {
	return Vec3{f32(m.width), f32(m.height), f32(m.depth)} * voxel_size_of(m)
}

box_hits_voxels :: proc "contextless" (m: ^Voxel_Map, box_min, box_max: Vec3) -> bool {
	s := voxel_size_of(m)
	lo := voxel_of(m, box_min)
	hi := [3]int{
		int(math.floor((box_max.x - EPSILON) / s)),
		int(math.floor((box_max.y - EPSILON) / s)),
		int(math.floor((box_max.z - EPSILON) / s)),
	}
	for y in lo.y..=hi.y {
		for z in lo.z..=hi.z {
			for x in lo.x..=hi.x {
				if voxel_get(m, x, y, z) != 0 {
					return true
				}
			}
		}
	}
	return false
}

// Axis-aligned box in 3D. position is the minimum corner (feet at position.y).
Body3 :: struct {
	position: Vec3,
	size:     Vec3,
	velocity: Vec3,
}

body3_center :: proc "contextless" (b: Body3) -> Vec3 {
	return b.position + b.size*0.5
}

body3_feet :: proc "contextless" (b: Body3) -> Vec3 {
	return Vec3{b.position.x + b.size.x*0.5, b.position.y, b.position.z + b.size.z*0.5}
}

Move_Result3 :: struct {
	on_ground, on_ceiling: bool,
	hit_wall:              bool,
	wall_normal:           Vec3,
}

// Resolves x, then z, then y; blocked velocity components are zeroed.
move_body3 :: proc(m: ^Voxel_Map, body: ^Body3, delta: Vec3) -> Move_Result3 {
	result: Move_Result3
	limit := voxel_size_of(m) * 0.45
	steps := max(1, int(math.ceil(max(abs(delta.x), abs(delta.y), abs(delta.z)) / limit)))
	part := delta / f32(steps)
	for _ in 0..<steps {
		for axis in ([3]int{0, 2, 1}) {
			move_axis3(m, body, axis, part[axis], &result)
		}
	}
	if delta.y == 0 {
		lo := body.position + Vec3{0, -EPSILON * 8, 0}
		hi := body.position + Vec3{body.size.x, 0, body.size.z}
		result.on_ground = result.on_ground || box_hits_voxels(m, lo, hi)
	}
	return result
}

@(private)
move_axis3 :: proc(m: ^Voxel_Map, body: ^Body3, axis: int, d: f32, result: ^Move_Result3) {
	if d == 0 {
		return
	}
	body.position[axis] += d
	if !box_hits_voxels(m, body.position, body.position+body.size) {
		return
	}
	s := voxel_size_of(m)
	if d > 0 {
		edge := math.floor((body.position[axis] + body.size[axis] - EPSILON) / s) * s
		body.position[axis] = edge - body.size[axis]
	} else {
		edge := (math.floor(body.position[axis] / s) + 1) * s
		body.position[axis] = edge
	}
	body.velocity[axis] = 0
	switch axis {
	case 1:
		if d > 0 {
			result.on_ceiling = true
		} else {
			result.on_ground = true
		}
	case:
		result.hit_wall = true
		result.wall_normal[axis] = -math.sign(d)
	}
}

Ray_Hit3 :: struct {
	hit:      bool,
	point:    Vec3,
	normal:   Vec3,
	cell:     [3]int,
	value:    u8,
	distance: f32,
}

// 3D grid traversal (Amanatides-Woo) through non-zero voxels.
raycast_voxels :: proc(m: ^Voxel_Map, origin, direction: Vec3, max_distance: f32) -> Ray_Hit3 {
	dir := normalize3(direction)
	if dir == {} || max_distance <= 0 {
		return {}
	}
	cell := voxel_of(m, origin)
	if v := voxel_get(m, cell.x, cell.y, cell.z); v != 0 {
		return Ray_Hit3{hit = true, point = origin, cell = cell, value = v}
	}
	s := voxel_size_of(m)
	step: [3]int
	t_max, t_delta: Vec3
	for axis in 0..<3 {
		step[axis] = 1 if dir[axis] > 0 else -1
		if abs(dir[axis]) < EPSILON {
			t_max[axis] = max(f32)
			t_delta[axis] = max(f32)
			continue
		}
		boundary := f32(cell[axis]+1)*s if step[axis] > 0 else f32(cell[axis])*s
		t_max[axis] = (boundary - origin[axis]) / dir[axis]
		t_delta[axis] = s / abs(dir[axis])
	}
	for {
		axis := 0
		if t_max.y < t_max[axis] {
			axis = 1
		}
		if t_max.z < t_max[axis] {
			axis = 2
		}
		t := t_max[axis]
		if t > max_distance {
			return {}
		}
		t_max[axis] += t_delta[axis]
		cell[axis] += step[axis]
		if v := voxel_get(m, cell.x, cell.y, cell.z); v != 0 {
			normal: Vec3
			normal[axis] = f32(-step[axis])
			return Ray_Hit3{hit = true, point = origin + dir*t, normal = normal, cell = cell,
				value = v, distance = t}
		}
		if !voxel_in_bounds(m, cell.x, cell.y, cell.z) && m.outside == 0 {
			// Outside an open volume nothing can be hit any more once moving away.
			moving_away := false
			for a in 0..<3 {
				size := [3]int{m.width, m.height, m.depth}[a]
				if (cell[a] < 0 && step[a] < 0) || (cell[a] >= size && step[a] > 0) {
					moving_away = true
				}
			}
			if moving_away {
				return {}
			}
		}
	}
}

voxel_line_of_sight :: proc(m: ^Voxel_Map, from, to: Vec3) -> bool {
	d := to - from
	dist := length3(d)
	if dist < EPSILON {
		return true
	}
	return !raycast_voxels(m, from, d, dist).hit
}
