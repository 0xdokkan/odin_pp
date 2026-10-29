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

// The sword's trail (first_person_sword.odin) is its seconds long whatever the
// frame rate: a fast swing round a circle at 30, 60, 144 and 240 frames a
// second leaves a line from exactly its seconds ago to the point, as long at
// each, with no step between its points longer than the finest one.
@(test)
test_first_person_sword_trail_at_every_frame_rate :: proc(t: ^testing.T) {
	rates := [4]f64{30, 60, 144, 240}
	spans: [4]f32
	for fps, index in rates {
		v: First_Person_Sword_View
		v.swinging = true
		now := f64(1)
		for _ in 0..<int(0.3*fps) {
			now += 1/fps
			// A turn in 0.6 s.
			a := now*math.TAU/0.6
			v.tip = {0.45*f32(math.cos(a)), 0.4*f32(math.sin(a))}
			first_person_sword_keep_trail(&v, now)
		}
		points: [FIRST_PERSON_SWORD_TRAIL*FIRST_PERSON_SWORD_TRAIL_CUTS]First_Person_Sword_Trail_Point
		count := first_person_sword_trail_points(&v, now, v.tip, points[:])
		if !testing.expectf(t, count >= 2, "%v fps: no trail", fps) { continue }
		testing.expectf(t, abs(points[0].age-1) < 1e-3, "%v fps: the tail is %v of the seconds old", fps, points[0].age)
		testing.expect(t, points[count-1].age == 0 && points[count-1].tip == v.tip)
		longest := f32(0)
		for k in 0..<count-1 {
			d := points[k+1].tip-points[k].tip
			gap := math.sqrt(d.x*d.x+d.y*d.y)
			longest = max(longest, gap)
			spans[index] += gap
		}
		testing.expectf(t, longest <= FIRST_PERSON_SWORD_TRAIL_STEP*1.3, "%v fps: a gap of %v", fps, longest)
	}
	for span, index in spans {
		testing.expectf(t, abs(span-spans[3]) < spans[3]*0.05, "%v fps: the trail %v long, %v at 240", rates[index], span, spans[3])
	}
	// Once the swing is over its places age away.
	v: First_Person_Sword_View
	v.swinging = true
	first_person_sword_keep_trail(&v, 1)
	first_person_sword_keep_trail(&v, 1.01)
	v.swinging = false
	first_person_sword_keep_trail(&v, 1.5)
	points: [8]First_Person_Sword_Trail_Point
	testing.expect(t, first_person_sword_trail_points(&v, 1.5, v.tip, points[:]) == 0)
}

// The grapple's hook (first_person_sword.odin): it leaves the guard, reaches
// the foe's chest as its flight ends, the chain slack; then it holds his chest
// where his card is drawn, the chain drawn taut, and is gone at the end.
@(test)
test_first_person_sword_hook_flies_then_holds :: proc(t: ^testing.T) {
	guard, from, at := [2]f32{0.3, -0.4}, [2]f32{-0.2, 0.1}, [2]f32{-0.05, 0.0}
	hook, sag, shown := first_person_sword_hook(0, guard, from, at)
	testing.expect(t, shown && hook == guard && sag > 0)
	hook, _, _ = first_person_sword_hook(FIRST_PERSON_SWORD_HOOK_FLIGHT*0.5, guard, from, at)
	testing.expect(t, hook != guard && hook != from)
	hook, _, _ = first_person_sword_hook(FIRST_PERSON_SWORD_HOOK_FLIGHT, guard, from, at)
	testing.expect(t, hook == at)
	hook, sag, shown = first_person_sword_hook(FIRST_PERSON_SWORD_GRAPPLE*0.9, guard, from, at)
	testing.expect(t, shown && hook == at && sag == 0)
	_, _, shown = first_person_sword_hook(FIRST_PERSON_SWORD_GRAPPLE, guard, from, at)
	testing.expect(t, !shown)
	_, _, shown = first_person_sword_hook(-0.01, guard, from, at)
	testing.expect(t, !shown)
}
