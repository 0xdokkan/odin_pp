package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"

// FIRST PERSON FENCER's zweihänder (first_person_zweihander.odin): wherever
// the mouse puts the point, the model's point is drawn exactly there, its
// guard on the rules' line from the hilt, the blade going away into the view;
// its flat faces the eye and its frame is a true one.
@(test)
test_first_person_zweihander_follows_the_point :: proc(t: ^testing.T) {
	project :: proc(p: rl.Vector3) -> [2]f32 {
		k := 2*f32(math.tan(f64(FIRST_PERSON_GLOVE_FOV)*math.PI/360))
		return {p.x/(-p.z)/k, p.y/(-p.z)/k}
	}
	hilt := game.SWORD_HILT
	for tip in ([?][2]f32{{0, 0}, {-0.8, 0}, {0.8, 0.1}, {0.6, -0.4}, {0, 0.46}, {-0.5, -0.4}, {0.3, -0.55}}) {
		guard, axis := first_person_zweihander_place(tip, 0)
		shown := project(guard+axis*FIRST_PERSON_ZWEIHANDER_BLADE)
		testing.expectf(t, abs(shown.x-tip.x) < 1e-3 && abs(shown.y-tip.y) < 1e-3, "tip %v drawn at %v", tip, shown)
		g := project(guard)
		way := tip-hilt
		testing.expectf(t, abs(way.x*(g.y-hilt.y)-way.y*(g.x-hilt.x)) < 1e-3, "tip %v: guard %v off the line", tip, g)
		testing.expectf(t, axis.z < 0, "tip %v: the blade comes toward the eye", tip)
		m := first_person_zweihander_matrix(guard, axis)
		x, y, z := rl.Vector3{m[0, 0], m[1, 0], m[2, 0]}, rl.Vector3{m[0, 1], m[1, 1], m[2, 1]}, rl.Vector3{m[0, 2], m[1, 2], m[2, 2]}
		testing.expect(t, abs(rl.Vector3DotProduct(x, y)) < 1e-4 && abs(rl.Vector3DotProduct(y, z)) < 1e-4 && abs(rl.Vector3DotProduct(x, z)) < 1e-4)
		testing.expect(t, rl.Vector3DotProduct(rl.Vector3CrossProduct(x, y), z) > 0.999)
		testing.expect(t, rl.Vector3DotProduct(z, rl.Vector3Normalize(-guard)) > 0)
	}
	// Coming in from under the view it is lower on the screen, the same way along.
	low, _ := first_person_zweihander_place({0, 0}, 0.6)
	high, _ := first_person_zweihander_place({0, 0}, 0)
	testing.expect(t, project(low).y < project(high).y)
}
