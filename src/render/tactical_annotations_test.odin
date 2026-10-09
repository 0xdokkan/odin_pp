package render

import "core:testing"
import rl "vendor:raylib"
import view "../view"

@(test)
test_tactical_labels_pack_shared_anchor_without_overlap_or_leaving_viewport :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{20, 80, 600, 240}
	for anchor in ([3]view.Vec2{{320, 260}, {20, 320}, {620, 320}}) {
		layout: Tactical_Label_Layout
		for _ in 0..<6 {
			bounds, placed := place_tactical_label(&layout, anchor, {90, 30}, viewport)
			testing.expect(t, placed, "six clustered health/intent/fuse labels must fit")
			if !placed { continue }
			testing.expect(t, bounds.x >= viewport.x && bounds.y >= viewport.y)
			testing.expect(t, bounds.x+bounds.width <= viewport.x+viewport.width)
			testing.expect(t, bounds.y+bounds.height <= viewport.y+viewport.height)
			for previous in layout.bounds[:layout.count-1] {
				testing.expect(t, !rl.CheckCollisionRecs(bounds, previous))
			}
		}
		testing.expect_value(t, layout.count, 6)
	}
}

@(test)
test_tactical_label_capacity_and_full_viewport_fail_without_overwriting :: proc(t: ^testing.T) {
	layout: Tactical_Label_Layout
	viewport := rl.Rectangle{0, 0, 120, 80}
	_, placed := place_tactical_label(&layout, {60, 80}, {120, 80}, viewport)
	testing.expect(t, placed)
	before := layout
	_, placed = place_tactical_label(&layout, {60, 80}, {20, 15}, viewport)
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
	_, placed = place_tactical_label(&layout, {60, 80}, {121, 15}, viewport)
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
	// Occupancy storage also has a hard cap independent of free screen space.
	layout.count = len(layout.bounds)
	before = layout
	_, placed = place_tactical_label(&layout, {2000, 2000}, {20, 15}, {0, 0, 4000, 4000})
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
}

@(test)
test_tactical_label_clamped_at_top_avoids_its_actor_and_adjacent_actor :: proc(t: ^testing.T) {
	// A tall archer reaches above the world viewport. Its intended label is
	// clamped down onto its head unless bodies participate in label placement.
	viewport := rl.Rectangle{12, 116, 600, 300}
	layout := Tactical_Label_Layout{actor_count = 2}
	layout.actor_bounds[0] = {278, 105, 64, 94}
	layout.actor_bounds[1] = {205, 119, 66, 102}
	bounds, placed := place_tactical_label(&layout, {310, 103}, {70, 34}, viewport)
	testing.expect(t, placed, "an adjacent free lane exists for the clamped health/intent label")
	testing.expect(t, bounds.y >= viewport.y)
	for actor in layout.actor_bounds[:layout.actor_count] {
		testing.expect(t, !rl.CheckCollisionRecs(bounds, actor), "clamping must never place health text over a character")
	}
	testing.expect_value(t, layout.actor_count, 2)
	testing.expect(t, layout.count == 1, "actor reservations must not consume the 96 label slots")
}

@(test)
test_tactical_crowded_front_actor_retains_label_using_a_free_lower_lane :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{12, 116, 600, 240}
	layout := Tactical_Label_Layout{actor_count = 6}
	// A projected group behind the front actor occupies every old +/-2
	// column above its anchor, while free space remains below and beside it.
	for index in 0..<5 { layout.actor_bounds[index] = {120+f32(index)*76, 116, 74, 180} }
	layout.actor_bounds[5] = {278, 288, 64, 60}
	bounds, placed := place_tactical_label(&layout, {310, 280}, {70, 34}, viewport)
	testing.expect(t, placed, "a crowded front actor must retain health/intent when a nearby lower lane is free")
	if !placed { return }
	for actor in layout.actor_bounds[:layout.actor_count] { testing.expect(t, !rl.CheckCollisionRecs(bounds, actor)) }
	testing.expect(t, bounds.y > 296, "prefer the nearby lower lane to a far lateral label")
	testing.expect(t, bounds.x >= viewport.x && bounds.x+bounds.width <= viewport.x+viewport.width)
	testing.expect(t, bounds.y >= viewport.y && bounds.y+bounds.height <= viewport.y+viewport.height)
	testing.expect_value(t, layout.count, 1)
}
