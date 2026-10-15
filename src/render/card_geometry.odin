package render

import "core:math"
import rl "vendor:raylib"

// Both standee styles fall around the same floor edge; only their animation
// clocks and the set of quads being transformed differ.
topple_card_points :: proc(points: ^[4]rl.Vector3, camera: rl.Camera3D, fall: f32) {
	angle := fall*fall*1.4
	away := rl.Vector3Normalize(rl.Vector3{camera.target.x-camera.position.x, 0, camera.target.z-camera.position.z})
	floor := f32(0.02)
	for &point in points {
		h := point.y-floor
		point = {point.x, floor+h*math.cos(angle), point.z}+away*(h*math.sin(angle))
	}
}

// Local coordinates of a confirmed quad hit, clamped inside the last texel.
// Callers retain their own mirroring and atlas-frame selection.
card_hit_uv :: proc(points: [4]rl.Vector3, hit: rl.Vector3) -> rl.Vector2 {
	u := points[3]-points[0]
	v := points[1]-points[0]
	delta := hit-points[0]
	return {
		clamp(rl.Vector3DotProduct(delta, u)/rl.Vector3DotProduct(u, u), 0, 0.9999),
		clamp(rl.Vector3DotProduct(delta, v)/rl.Vector3DotProduct(v, v), 0, 0.9999),
	}
}
