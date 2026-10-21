package render

import "core:math"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"
import level "../level"

@(test)
test_environment_theme_names_round_trip_and_default_is_neon :: proc(t: ^testing.T) {
	for theme in Environment_Theme {
		parsed, ok := parse_environment_theme(environment_theme_name(theme))
		testing.expect(t, ok)
		testing.expect_value(t, parsed, theme)
	}
	for name in ([?]string{"", "Neon", "GOTHIC", "gothic ", "sepia", "--theme=neon"}) {
		_, ok := parse_environment_theme(name)
		testing.expectf(t, !ok, "%q must not parse", name)
	}
	// A view nobody configured is neon; a renderer made before the command
	// line spoke starts with the default look.
	view: Tactical_View
	testing.expect_value(t, view.theme, Environment_Theme.Neon)
	testing.expect_value(t, startup_environment_theme, Environment_Theme.Neon)
}

@(test)
test_neon_theme_is_a_branch_of_one_shared_material :: proc(t: ^testing.T) {
	// One program serves the board, the hologram, the dice and the neon world:
	// the neon branch is in it once, after the hologram's early exit, and the
	// uniforms it reads are declared.
	source := TACTICAL_LIGHT_FRAGMENT
	testing.expect_value(t, strings.count(source, "hologram == 3"), 1)
	testing.expect(t, strings.count(source, "uniform float neonTime;") == 1)
	testing.expect(t, strings.count(source, "uniform vec3 neonColor;") == 1)
	testing.expect(t, strings.index(source, "hologram == 1") < strings.index(source, "hologram == 3"))
	testing.expect_value(t, int(Resin_Light_Mode.Board), 0)
	testing.expect_value(t, int(Resin_Light_Mode.Hologram), 1)
	testing.expect_value(t, int(Resin_Light_Mode.Model), 2)
	testing.expect_value(t, int(Resin_Light_Mode.Neon), 3)
}

@(test)
test_neon_family_glows_stay_red_and_stay_apart :: proc(t: ^testing.T) {
	glows: [len(level.Room_Family)][3]f32
	for family in level.Room_Family {
		glow := neon_family_glow(family)
		glows[int(family)] = glow
		// Neon that tends to red: red always leads.
		testing.expectf(t, glow.x >= 0.75 && glow.x > glow.y*2 && glow.x > glow.z, "%v is not red enough: %v", family, glow)
	}
	for a in 0..<len(glows) { for b in a+1..<len(glows) {
		distance := abs(glows[a].x-glows[b].x)+abs(glows[a].y-glows[b].y)+abs(glows[a].z-glows[b].z)
		testing.expectf(t, distance >= 0.07, "families %d and %d are too alike: %v %v", a, b, glows[a], glows[b])
	} }
}

// The rectangle's distance to a hill's centre.
neon_test_gap :: proc(hill: Neon_Hill, width, height: int) -> f32 {
	nearest := rl.Vector2{clamp(hill.center.x, 0, f32(width)), clamp(hill.center.y, 0, f32(height))}
	return rl.Vector2Length(hill.center-nearest)
}

@(test)
test_neon_hills_are_deterministic_few_and_never_over_cells :: proc(t: ^testing.T) {
	sizes := [?][2]int{{9, 7}, {17, 11}, {23, 17}, {25, 17}, {33, 23}, {41, 29}, {45, 31}, {7, 31}, {31, 7}}
	for size in sizes {
		for family in level.Room_Family {
			seed := neon_hill_seed(size.x, size.y, family, {size.x-2, size.y-2}, .Standard)
			again := neon_hill_seed(size.x, size.y, family, {size.x-2, size.y-2}, .Standard)
			testing.expect_value(t, seed, again)
			count := neon_hill_count(size.x, size.y)
			// A small fixed number of meshes: far below the per-frame budget.
			testing.expectf(t, count >= 14 && count <= NEON_HILL_MAX && NEON_HILL_MAX <= 40, "%v: %d hills", size, count)
			for index in 0..<count {
				hill := neon_hill(seed, index, count, size.x, size.y)
				same := neon_hill(seed, index, count, size.x, size.y)
				testing.expect_value(t, hill, same)
				// The whole footprint (a jittered ring of up to 1.16 radii) stays
				// beyond the walls, so it never covers a cell.
				gap := neon_test_gap(hill, size.x, size.y)
				testing.expectf(t, gap >= hill.radius*1.2+NEON_HILL_MIN_GAP-0.001,
					"%v %v hill %d: gap %.2f for radius %.2f", size, family, index, gap, hill.radius)
				testing.expect(t, hill.height > 0.5 && hill.height < hill.radius)
				testing.expect(t, hill.sides >= 6 && hill.sides <= 8)
			}
		}
	}
	// Another room is another range; the same room is the same range.
	a := neon_hill_seed(25, 17, .Ring, {3, 4}, .Standard)
	testing.expect(t, a != neon_hill_seed(25, 17, .Pillars, {3, 4}, .Standard))
	testing.expect(t, a != neon_hill_seed(23, 17, .Ring, {3, 4}, .Standard))
	testing.expect(t, a != neon_hill_seed(25, 17, .Ring, {4, 3}, .Standard))
}

@(test)
test_neon_hills_never_stand_between_the_camera_and_a_cell :: proc(t: ^testing.T) {
	sizes := [?][2]int{{17, 11}, {33, 23}, {45, 31}}
	for size in sizes {
		seed := neon_hill_seed(size.x, size.y, .Scattered, {1, 1}, .Standard)
		count := neon_hill_count(size.x, size.y)
		w, h := f32(size.x), f32(size.y)
		for yaw_step in 0..<24 { for pitch in ([?]f32{0.3, 0.5, 0.68, 1.0, 1.45}) { for distance in ([?]f32{7, 12.5, 24}) {
			yaw := f32(yaw_step)*(2*math.PI/24)
			// The target roams the room; the eye sits on the orbit around it.
			for target in ([?]rl.Vector3{{w*0.5, 0, h*0.5}, {2, 0, 2}, {w-2, 0, h-2}}) {
				eye := target+rl.Vector3{math.cos(yaw)*math.cos(pitch), math.sin(pitch), math.sin(yaw)*math.cos(pitch)}*distance
				for index in 0..<count {
					hill := neon_hill(seed, index, count, size.x, size.y)
					rise := neon_hill_rise(eye, hill, w, h)
					testing.expect(t, rise >= 0.12-0.0001 && rise <= 1)
					apex := rl.Vector3{hill.center.x, hill.height*rise, hill.center.y}
					if apex.y >= eye.y { continue }
					// Where the sight line over the apex comes down to the floor.
					scale := eye.y/(eye.y-apex.y)
					ground := eye+(apex-eye)*scale
					if rise > 0.12+0.0001 {
						inside := ground.x > 0 && ground.x < w && ground.z > 0 && ground.z < h
						// Only a ground point past the hill can be covered by it.
						testing.expectf(t, !inside, "%v hill %d at yaw %d pitch %.2f distance %.1f hides the floor at %v",
							size, index, yaw_step, pitch, distance, ground)
					}
				}
			}
		} } }
	}
}

@(test)
test_neon_hills_do_not_depend_on_the_clock :: proc(t: ^testing.T) {
	// The ring is a pure function of the room: the clock and the global RNG
	// are never inputs (the whole generator is the three procedures above).
	first, second: [NEON_HILL_MAX]Neon_Hill
	seed := neon_hill_seed(41, 29, .Twin_Courts, {39, 27}, .Assault)
	for index in 0..<NEON_HILL_MAX { first[index] = neon_hill(seed, index, NEON_HILL_MAX, 41, 29) }
	for index in 0..<NEON_HILL_MAX { second[index] = neon_hill(seed, index, NEON_HILL_MAX, 41, 29) }
	testing.expect(t, first == second)
}

@(test)
test_neon_pulse_is_slow_and_bounded :: proc(t: ^testing.T) {
	low, high := f32(10), f32(-10)
	for step in 0..<2000 {
		value := neon_pulse(f32(step)*0.01, 3, 4)
		low, high = min(low, value), max(high, value)
	}
	testing.expect(t, low >= 0.59 && high <= 1.01)
	// Held world: the same clock reading gives the same line.
	testing.expect_value(t, neon_pulse(12.5, 4, 9), neon_pulse(12.5, 4, 9))
	// "Very slowly": a quarter second moves the pulse by well under a tenth.
	testing.expect(t, abs(neon_pulse(5.25, 1, 1)-neon_pulse(5, 1, 1)) < 0.06)
}

@(test)
test_neon_wall_footprint_stays_inside_its_tile :: proc(t: ^testing.T) {
	// The wall's rings are 0.465 and 0.36 around the centre, wandering by at
	// most 0.05: always inside the 0.5 half tile, so no wall ever grows over a
	// neighbouring cell.
	for cell_x in 0..<32 { for cell_y in 0..<32 {
		for ring in 1..<3 { for index in 0..<4 {
			n := neon_hash(u32(cell_x), u32(cell_y), u32(ring*4+index))
			wander := f32(0.012) if ring == 1 else f32(0.05)
			offset := (neon_unit(n)-0.5)*2*wander
			width := f32(0.465) if ring == 1 else f32(0.36)
			testing.expect(t, width+abs(offset) < 0.5)
			testing.expect(t, neon_unit(n) >= 0 && neon_unit(n) < 1)
		} }
	} }
}
