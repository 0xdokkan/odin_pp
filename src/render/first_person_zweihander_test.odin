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

// FIRST PERSON ARCHER's compound bow (first_person_compound.odin): its arrow
// points at the crosshair's place far ahead, its string comes back toward the
// eye as it is drawn (each level further), the arrow's head is its kind's colour.
@(test)
test_first_person_compound_aims_and_draws :: proc(t: ^testing.T) {
	m := first_person_compound_matrix(0)
	back := rl.Vector3{m[0, 2], m[1, 2], m[2, 2]}
	grip := rl.Vector3{m[0, 3], m[1, 3], m[2, 3]}
	want := rl.Vector3Normalize(rl.Vector3{0, 0, -FIRST_PERSON_COMPOUND_AIM}-grip)
	testing.expect(t, rl.Vector3DotProduct(rl.Vector3Normalize(-back), want) > 0.999)
	last := f32(-1)
	for level in 0..=4 {
		z := first_person_compound_nock(f32(level)/4).z
		testing.expect(t, z > last)
		last = z
	}
	testing.expect(t, first_person_compound_nock(2).z == first_person_compound_nock(1).z)
	for kind in game.Bow_Arrow_Kind {
		for other in game.Bow_Arrow_Kind {
			if kind != other { testing.expect(t, FIRST_PERSON_BOW_COLORS[kind] != FIRST_PERSON_BOW_COLORS[other]) }
		}
	}
}

// An arrow in flight keeps one size on screen from a metre to NEAR*FAR metres
// (its size grows as its distance), no smaller than a true arrow up close, no
// bigger past it; it grows an eighth a bounce up to half again, the same as
// its damage. It leaves from where the bow shows its nocked arrow's head.
@(test)
test_first_person_bow_arrow_size :: proc(t: ^testing.T) {
	eye := rl.Vector3{0, 1, 0}
	for d in ([?]f32{1, 2, 3, 5, 7.5}) {
		size := first_person_bow_arrow_size(eye, eye+{d, 0, 0}, 0)
		testing.expectf(t, abs(size/d-1/FIRST_PERSON_BOW_ARROW_NEAR) < 1e-5, "at %f m its size %f is not its distance's", d, size)
	}
	closest := first_person_bow_arrow_size(eye, eye+{0.5, 0, 0}, 0)
	testing.expect(t, abs(closest-1/FIRST_PERSON_BOW_ARROW_THICK) < 1e-5, "up close it is thinner than a true arrow")
	farthest := first_person_bow_arrow_size(eye, eye+{40, 0, 0}, 0)
	testing.expect(t, abs(farthest-FIRST_PERSON_BOW_ARROW_FAR) < 1e-5, "it grows without end")
	for bounced in i16(0)..=6 {
		size := first_person_bow_arrow_size(eye, eye+{3, 0, 0}, bounced)
		want := 1+min(0.125*f32(bounced), 0.5)
		testing.expectf(t, abs(size-want) < 1e-5, "%d bounces: %f, not %f", bounced, size, want)
	}
	// The launch point: ahead of the eye, low and on the bow's side (looking
	// east, the right is south: +z).
	camera := rl.Camera3D{position = eye, target = eye+{1, 0, 0}, up = {0, 1, 0}, fovy = FIRST_PERSON_FOV, projection = .PERSPECTIVE}
	start := first_person_bow_launch_point(camera, 16.0/9)
	side := (start.z > eye.z) if FIRST_PERSON_COMPOUND_RIGHT else (start.z < eye.z)
	testing.expectf(t, start.x > eye.x+0.2 && start.y < eye.y && side, "it leaves from %v", start)
	// Its pixel is the nocked arrow head's: the same place on screen in both cameras.
	head := first_person_compound_head(1)
	p := first_person_compound_matrix(0)*[4]f32{head.x, head.y, head.z, 1}
	glove := math.tan(FIRST_PERSON_GLOVE_FOV*math.RAD_PER_DEG*0.5)
	main := math.tan(FIRST_PERSON_FOV*math.RAD_PER_DEG*0.5)
	q := start-eye
	testing.expect(t, abs((q.z/q.x)/main-(p.x/-p.z)/glove) < 1e-4 && abs((q.y/q.x)/main-(p.y/-p.z)/glove) < 1e-4)
}
