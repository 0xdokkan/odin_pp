package render

import rl "vendor:raylib"

// Pure shadow preparation. Each receiver's plane and edge half-spaces are
// computed once per model frame, with the same operations as the reference
// page_lab_project_shadow. Clipping, projection and final depth bias are unchanged.
@(private)
Page_Lab_Shadow_Receiver :: struct {
	points: [3]rl.Vector3,
	normal: rl.Vector3,
	inside: [3]rl.Vector3,
	denominator: f32,
	valid: bool,
}

@(private)
page_lab_shadow_receiver :: proc(points: [3]rl.Vector3) -> (receiver: Page_Lab_Shadow_Receiver) {
	receiver.points = points
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(points[1]-points[0], points[2]-points[0]))
	if n.y < 0 { n = -n }
	denominator := rl.Vector3DotProduct(n, PAGE_LAB_LIGHT)
	if n.y < .05 || denominator < .05 { return }
	receiver.normal, receiver.denominator = n, denominator
	for i in 0..<3 {
		a, b, other := points[i], points[(i+1)%3], points[(i+2)%3]
		inside := rl.Vector3CrossProduct(n, b-a)
		if rl.Vector3DotProduct(other-a, inside) < 0 { inside = -inside }
		receiver.inside[i] = inside
	}
	receiver.valid = true
	return
}

@(private)
page_lab_project_shadow_prepared :: proc(caster: [3]rl.Vector3, receiver: ^Page_Lab_Shadow_Receiver) -> (polygon: [12]rl.Vector3, count: int) {
	if !receiver.valid { return }
	initial := caster
	n := receiver.normal
	polygon, count = page_lab_clip_polygon(initial[:], receiver.points[0], n, .0005)
	if count < 3 { count = 0; return }
	for &p in polygon[:count] {
		p -= PAGE_LAB_LIGHT*(rl.Vector3DotProduct(p-receiver.points[0], n)/receiver.denominator)
	}
	for i in 0..<3 {
		polygon, count = page_lab_clip_polygon(polygon[:count], receiver.points[i], receiver.inside[i])
		if count < 3 { count = 0; return }
	}
	for &p in polygon[:count] { p += n*.003 }
	return
}

// q is invariant along p-t*LIGHT, for every receiver height. Both caster and
// receiver AABBs therefore live in the same light plane without expanding each
// caster over the whole terrain's min/max height range.
@(private)
page_lab_shadow_light_point :: proc(p: rl.Vector3) -> rl.Vector2 {
	return {p.x-PAGE_LAB_LIGHT.x*(p.y/PAGE_LAB_LIGHT.y), p.z-PAGE_LAB_LIGHT.z*(p.y/PAGE_LAB_LIGHT.y)}
}

// 64 f32 epsilons per coordinate magnitude protect boundary cancellation in
// projection/dot products. At the 16-unit page extent this is about 0.00012:
// only the conservative broadphase grows, never the clipped polygon or bias.
@(private)
PAGE_LAB_SHADOW_BOUND_EPSILON :: f32(64)*1.1920928955078125e-7

@(private)
page_lab_shadow_light_bounds :: proc(points: [3]rl.Vector3) -> (bounds: Page_Lab_Shadow_Bounds) {
	bounds.lo = {max(f32), max(f32)}; bounds.hi = {-max(f32), -max(f32)}
	magnitude := f32(1)
	for p in points {
		q := page_lab_shadow_light_point(p)
		bounds.lo.x = min(bounds.lo.x, q.x); bounds.lo.y = min(bounds.lo.y, q.y)
		bounds.hi.x = max(bounds.hi.x, q.x); bounds.hi.y = max(bounds.hi.y, q.y)
		magnitude = max(magnitude, abs(p.x)+abs(PAGE_LAB_LIGHT.x*p.y/PAGE_LAB_LIGHT.y),
			abs(p.z)+abs(PAGE_LAB_LIGHT.z*p.y/PAGE_LAB_LIGHT.y))
	}
	padding := magnitude*PAGE_LAB_SHADOW_BOUND_EPSILON
	bounds.lo -= {padding, padding}; bounds.hi += {padding, padding}
	return
}
