// Collision and movement for real-time minigames: rectangles and circles in
// 2D, boxes and rays in 3D, swept against tile and voxel maps. Everything here
// is plain math with no raylib dependency, so simulations run headless.
package physics

import "core:math"

Vec2 :: [2]f32
Vec3 :: [3]f32

EPSILON :: f32(1e-4)

// Same field layout as rl.Rectangle, so it converts with a plain cast.
Rect :: struct {
	x, y, width, height: f32,
}

rect_from_center :: proc "contextless" (center, size: Vec2) -> Rect {
	return Rect{center.x - size.x*0.5, center.y - size.y*0.5, size.x, size.y}
}

rect_center :: proc "contextless" (r: Rect) -> Vec2 {
	return Vec2{r.x + r.width*0.5, r.y + r.height*0.5}
}

rect_overlaps :: proc "contextless" (a, b: Rect) -> bool {
	return a.x < b.x+b.width && b.x < a.x+a.width && a.y < b.y+b.height && b.y < a.y+a.height
}

rect_contains :: proc "contextless" (r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x+r.width && p.y < r.y+r.height
}

// Shrinks (positive amount) or grows (negative) every side.
rect_inset :: proc "contextless" (r: Rect, amount: f32) -> Rect {
	return Rect{r.x + amount, r.y + amount, max(r.width-2*amount, 0), max(r.height-2*amount, 0)}
}

closest_point_on_rect :: proc "contextless" (r: Rect, p: Vec2) -> Vec2 {
	return Vec2{clamp(p.x, r.x, r.x+r.width), clamp(p.y, r.y, r.y+r.height)}
}

circles_overlap :: proc "contextless" (a: Vec2, ra: f32, b: Vec2, rb: f32) -> bool {
	d := b - a
	r := ra + rb
	return d.x*d.x+d.y*d.y < r*r
}

circle_overlaps_rect :: proc "contextless" (center: Vec2, radius: f32, r: Rect) -> bool {
	d := center - closest_point_on_rect(r, center)
	return d.x*d.x+d.y*d.y < radius*radius
}

// Minimum translation that separates circle b from circle a; zero if apart.
circle_push :: proc "contextless" (a: Vec2, ra: f32, b: Vec2, rb: f32) -> Vec2 {
	d := b - a
	dist2 := d.x*d.x + d.y*d.y
	r := ra + rb
	if dist2 >= r*r {
		return {}
	}
	dist := math.sqrt(dist2)
	if dist < EPSILON {
		return Vec2{r, 0}
	}
	return d / dist * (r - dist)
}

length2 :: proc "contextless" (v: Vec2) -> f32 {
	return math.sqrt(v.x*v.x + v.y*v.y)
}

length3 :: proc "contextless" (v: Vec3) -> f32 {
	return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
}

normalize2 :: proc "contextless" (v: Vec2) -> Vec2 {
	l := length2(v)
	if l < EPSILON {
		return {}
	}
	return v / l
}

normalize3 :: proc "contextless" (v: Vec3) -> Vec3 {
	l := length3(v)
	if l < EPSILON {
		return {}
	}
	return v / l
}

// Caps the length of v without changing its direction.
clamp_length2 :: proc "contextless" (v: Vec2, max_length: f32) -> Vec2 {
	l := length2(v)
	if l <= max_length || l < EPSILON {
		return v
	}
	return v * (max_length / l)
}

rotate2 :: proc "contextless" (v: Vec2, radians: f32) -> Vec2 {
	c := math.cos(radians)
	s := math.sin(radians)
	return Vec2{v.x*c - v.y*s, v.x*s + v.y*c}
}

// Slab test. dir need not be normalised; t is in units of dir.
ray_aabb3 :: proc "contextless" (origin, dir, box_min, box_max: Vec3) -> (t: f32, hit: bool) {
	t_min := f32(0)
	t_max := max(f32)
	for axis in 0..<3 {
		if abs(dir[axis]) < EPSILON {
			if origin[axis] < box_min[axis] || origin[axis] > box_max[axis] {
				return 0, false
			}
			continue
		}
		inv := 1 / dir[axis]
		t1 := (box_min[axis] - origin[axis]) * inv
		t2 := (box_max[axis] - origin[axis]) * inv
		if t1 > t2 {
			t1, t2 = t2, t1
		}
		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
		if t_min > t_max {
			return 0, false
		}
	}
	return t_min, true
}

ray_sphere :: proc "contextless" (origin, dir, center: Vec3, radius: f32) -> (t: f32, hit: bool) {
	oc := origin - center
	a := dir.x*dir.x + dir.y*dir.y + dir.z*dir.z
	if a < EPSILON {
		return 0, false
	}
	b := oc.x*dir.x + oc.y*dir.y + oc.z*dir.z
	c := oc.x*oc.x + oc.y*oc.y + oc.z*oc.z - radius*radius
	disc := b*b - a*c
	if disc < 0 {
		return 0, false
	}
	root := math.sqrt(disc)
	near := (-b - root) / a
	if near >= 0 {
		return near, true
	}
	far := (-b + root) / a
	if far >= 0 {
		return 0, true // origin inside the sphere
	}
	return 0, false
}

boxes_overlap3 :: proc "contextless" (a_min, a_max, b_min, b_max: Vec3) -> bool {
	return a_min.x < b_max.x && b_min.x < a_max.x &&
		a_min.y < b_max.y && b_min.y < a_max.y &&
		a_min.z < b_max.z && b_min.z < a_max.z
}
