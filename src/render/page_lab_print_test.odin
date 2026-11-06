package render

import "core:testing"
import "core:slice"
import rl "vendor:raylib"
import gfx "../engine/gfx"

@(test)
test_page_lab_print_clock_animates_idle_without_changing_fold_pose :: proc(t: ^testing.T) {
	pose := Page_Lab_Pose{act = .Still, time = 0}
	for surface in ([2]Page_Lab_Surface{.Hero, .Enemy}) {
		a := page_lab_print_sample(pose, surface, 0)
		b := page_lab_print_sample(pose, surface, 2.05)
		testing.expect(t, a.valid && b.valid && a.frame == 0 && b.frame == 10)
		testing.expect_value(t, a.origin, b.origin)
		testing.expect_value(t, a.scale, b.scale)
		art_a := page_lab_print_art(a.actor, a.clip, a.frame)
		art_b := page_lab_print_art(b.actor, b.clip, b.frame)
		pixels_a, pixels_b := cartoon_raster(&art_a), cartoon_raster(&art_b)
		testing.expect(t, !slice.equal(pixels_a[:], pixels_b[:]), "The actual printed actor blinks while its paper pose stays still")
	}
	loop := page_lab_print_sample(pose, .Hero, 2.4)
	testing.expect_value(t, loop.frame, 0)
}

@(test)
test_page_lab_print_calls_the_existing_actor_art_without_replacing_its_design :: proc(t: ^testing.T) {
	for actor in ([2]int{PAGE_LAB_PRINT_HERO, PAGE_LAB_PRINT_ENEMY}) {
		actual := page_lab_print_art(actor, .Idle, 0)
		expected := expedition_robot_art(0)
		if actor == PAGE_LAB_PRINT_ENEMY { expected = expedition_cyber_actor_art(.Brute, 0) }
		testing.expect_value(t, actual.count, expected.count)
		for part, i in actual.parts[:actual.count] {
			testing.expect_value(t, part, expected.parts[i])
		}
	}
}

@(test)
test_page_lab_death_print_keeps_upright_anatomy_and_only_changes_eyes :: proc(t: ^testing.T) {
	for actor in 0..<PAGE_LAB_PRINT_ACTORS {
		changed_expression := false
		for frame in 0..<PAGE_LAB_PRINT_FRAMES {
			progress := f32(frame)/f32(PAGE_LAB_PRINT_FRAMES)
			standing := expedition_robot_art(progress*2.4, .Idle, progress, actor == PAGE_LAB_PRINT_MOUNTED)
			if actor == PAGE_LAB_PRINT_ENEMY { standing = expedition_cyber_actor_art(.Brute, progress*2.4, .Idle, progress) }
			dying := page_lab_print_art(actor, .Death, frame)
			upright_pixels, dying_pixels := cartoon_raster(&standing), cartoon_raster(&dying)
			body_identical := true
			for pixel, i in upright_pixels {
				y := i/CARTOON_CELL
				// The source's eye band is y=.88..1.12 (including its ink rim).
				// Every other pixel, including head, torso and soles, must stay put.
				if y >= 32 && y <= 52 {
					changed_expression = changed_expression || pixel != dying_pixels[i]
				} else { body_identical = body_identical && pixel == dying_pixels[i] }
			}
			testing.expectf(t, body_identical, "actor %d frame %d: death ink must not squash or lower the body; the sheet supplies the fall", actor, frame)
		}
		testing.expect(t, changed_expression, "The death print changes expression without moving its anatomy")
	}
	// The last frame of the explorer uses the existing crossed-eye expression,
	// not the existing ground-collapsed death drawing.
	frame := PAGE_LAB_PRINT_FRAMES-1
	progress := f32(frame)/f32(PAGE_LAB_PRINT_FRAMES)
	expected := expedition_robot_art(progress*2.4, gfx.Living_Action.Hurt, progress)
	actual := page_lab_print_art(PAGE_LAB_PRINT_HERO, .Death, frame)
	testing.expect_value(t, actual.count, expected.count)
	for part, i in actual.parts[:actual.count] { testing.expect_value(t, part, expected.parts[i]) }
}

@(test)
test_page_lab_print_cache_covers_every_stored_frame_with_stable_paper :: proc(t: ^testing.T) {
	cache := page_lab_print_cpu()
	testing.expect(t, cache == page_lab_print_cpu(), "The immutable CPU atlas is prepared only once")
	testing.expect_value(t, PAGE_LAB_PRINT_BYTES, 4672512)
	for actor in 0..<PAGE_LAB_PRINT_ACTORS {
		for clip in Page_Lab_Print_Clip { for frame in 0..<PAGE_LAB_PRINT_FRAMES {
			tile := page_lab_print_tile(actor, clip, frame)
			ink_count := 0
			for y in 0..<CARTOON_CELL { for x in 0..<CARTOON_CELL {
				pixel := cache.pixels[(tile.y+y)*PAGE_LAB_PRINT_WIDTH+tile.x+x]
				if pixel.a == 0 { continue }
				ink_count += 1
				testing.expect(t, cache.masks[actor][y*CARTOON_CELL+x] != 0)
			} }
			testing.expect(t, ink_count > 100)
		} }
	}
	// The protection at the soles must not reconnect their gap into a plinth.
	for actor in ([2]int{PAGE_LAB_PRINT_HERO, PAGE_LAB_PRINT_ENEMY}) {
		for y in int(CARTOON_FEET)-5..<int(CARTOON_FEET) {
			testing.expect_value(t, cache.masks[actor][y*CARTOON_CELL+CARTOON_CELL/2], u8(0))
		}
	}
}

@(test)
test_page_lab_print_material_coordinates_follow_the_fold_and_death :: proc(t: ^testing.T) {
	for act in Page_Lab_Act {
		pose := Page_Lab_Pose{act = act, time = 1.5}
		sample := page_lab_print_sample(pose, .Hero, 2.05)
		// Recover a source-art point through its uniform sheet mapping.
		source := rl.Vector2{.125, 1.0}
		sheet := rl.Vector2{sample.origin.x+source.x*sample.scale, sample.origin.y-sample.lift-source.y*sample.scale}
		pixel := page_lab_print_source_pixel(sample, sheet)
		testing.expect(t, abs(pixel.x-(CARTOON_CELL*.5+source.x*CARTOON_PIXELS)) < .0001)
		testing.expect(t, abs(pixel.y-(CARTOON_FEET-source.y*CARTOON_PIXELS)) < .0001)
	}
	death := page_lab_print_sample({act = .Death, time = 3}, .Hero, 0)
	testing.expect(t, death.clip == .Death && death.frame == PAGE_LAB_PRINT_FRAMES-1)
	still_later := page_lab_print_sample({act = .Death, time = 3}, .Hero, 200)
	testing.expect_value(t, death.frame, still_later.frame)
}

@(test)
test_page_lab_actor_paper_geometry_is_independent_of_print_clock :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model); defer free(model)
	page_lab_build(model, {})
	testing.expect(t, page_lab_validate(model))
	count := model.vertex_count
	first := model.vertices[0]
	for clock in ([4]f32{0, .6, 1.4, 2.05}) {
		_ = page_lab_print_sample(model.pose, .Hero, clock)
		_ = page_lab_print_sample(model.pose, .Enemy, clock)
		testing.expect_value(t, model.vertex_count, count)
		testing.expect_value(t, model.vertices[0], first)
	}
}

@(private)
page_lab_print_test_axis_cell :: proc(axis: []f32, point: f32) -> int {
	lo, hi := 0, len(axis)-1
	for lo+1 < hi {
		mid := (lo+hi)/2
		if axis[mid] <= point { lo = mid } else { hi = mid }
	}
	return lo
}

@(test)
test_page_lab_animated_heads_and_hands_fit_actual_folded_mesh :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model); defer free(model)
	cache := page_lab_print_cpu()
	for actor in 0..<PAGE_LAB_PRINT_ACTORS {
		pose := Page_Lab_Pose{}
		surface := Page_Lab_Surface.Hero
		if actor == PAGE_LAB_PRINT_ENEMY { surface = .Enemy }
		if actor == PAGE_LAB_PRINT_MOUNTED { pose.act = .Mount }
		page_lab_build(model, pose)
		sample := page_lab_print_sample(pose, surface, 0)
		covered, missed := 0, 0
		for clip in Page_Lab_Print_Clip { for frame in 0..<PAGE_LAB_PRINT_FRAMES {
			tile := page_lab_print_tile(actor, clip, frame)
			for y in 0..<int(CARTOON_FEET)-5 { for x in 0..<CARTOON_CELL {
				if cache.pixels[(tile.y+y)*PAGE_LAB_PRINT_WIDTH+tile.x+x].a == 0 { continue }
				point := rl.Vector2{sample.origin.x+(f32(x)+.5-CARTOON_CELL*.5)/CARTOON_PIXELS*sample.scale,
					sample.origin.y-sample.lift-(CARTOON_FEET-f32(y)-.5)/CARTOON_PIXELS*sample.scale}
				column := page_lab_print_test_axis_cell(model.xs[:model.x_count], point.x)
				row := page_lab_print_test_axis_cell(model.ys[:model.y_count], point.y)
				if page_lab_cell(model, column, row) == surface { covered += 1 } else { missed += 1 }
			} }
		} }
		testing.expectf(t, covered > 100 && missed == 0, "actor %d: %d ink pixels outside the physical sheet", actor, missed)
	}
}
