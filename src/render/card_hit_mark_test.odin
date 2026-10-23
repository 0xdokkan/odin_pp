package render

import "core:fmt"
import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The foes marked as "can be hit" are the ones the game says a valid cast would
// affect, no more: the room has a foe beside the player to the east (7,6), one
// to the south (6,7) and one far away (9,9).
@(test)
test_the_hit_marks_follow_the_foes_a_cast_would_really_hit :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	update_tactical_view(renderer, &room, {}, false)
	preview: Card_Range_Preview
	player.deck.hand_count = 1
	// A Strike reaches one step: the two foes beside the player, not the far one.
	player.deck.hand[0] = {id = 11, definition_id = .Strike, lifetime = .Permanent}
	renderer.has_hovered_cell = false
	prepare_card_range_preview(renderer, &room, 11, &preview)
	testing.expect_value(t, preview.hit_count, 2)
	for mark in preview.hits[:preview.hit_count] {
		testing.expect(t, mark.cell == {7, 6} || mark.cell == {6, 7}, fmt.tprintf("marked %v", mark.cell))
		testing.expect(t, !mark.locked)
	}
	// With the mouse on one of them the cast closes on it: only it locks.
	renderer.has_hovered_cell, renderer.hovered_cell = true, {7, 6}
	prepare_card_range_preview(renderer, &room, 11, &preview)
	locked := 0
	for mark in preview.hits[:preview.hit_count] {
		if mark.locked { locked += 1; testing.expect_value(t, mark.cell, grid.Position{7, 6}) }
	}
	testing.expect_value(t, locked, 1)
	// The mouse on an empty cell locks no one.
	renderer.hovered_cell = {3, 3}
	prepare_card_range_preview(renderer, &room, 11, &preview)
	for mark in preview.hits[:preview.hit_count] { testing.expect(t, !mark.locked) }
	// A Dash lists the foes on its line and hits none: nothing is marked.
	player.deck.hand[0] = {id = 12, definition_id = .Dash, lifetime = .Permanent}
	prepare_card_range_preview(renderer, &room, 12, &preview)
	testing.expect_value(t, preview.hit_count, 0)
}

@(test)
test_a_card_only_under_the_mouse_shows_faintly_without_evaluating_the_pointer :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	update_tactical_view(renderer, &room, {}, false)
	preview: Card_Range_Preview
	player.deck.hand_count = 1
	player.deck.hand[0] = {id = 13, definition_id = .Strike, lifetime = .Permanent}
	renderer.has_hovered_cell, renderer.hovered_cell = true, {7, 6}
	prepare_card_range_preview(renderer, &room, 13, &preview, true)
	testing.expect(t, preview.active && preview.faint)
	testing.expect(t, !preview.has_hover)
	testing.expect_value(t, preview.hit_count, 2)
	for mark in preview.hits[:preview.hit_count] { testing.expect(t, !mark.locked) }
	testing.expect(t, card_range_contains(&preview, {7, 6}))
	// A chosen card is never faint, and no card at all is no preview.
	prepare_card_range_preview(renderer, &room, 13, &preview)
	testing.expect(t, preview.active && !preview.faint && preview.has_hover)
	prepare_card_range_preview(renderer, &room, 0, &preview, true)
	testing.expect(t, !preview.active)
	testing.expect_value(t, preview.hit_count, 0)
}

@(test)
test_a_foe_in_the_fog_is_not_marked :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	// Only the cell the player stands on and its neighbours are seen.
	player.tactical.config.vision_size = 1
	player.deck.hand_count = 1
	player.deck.hand[0] = {id = 14, definition_id = .Firebomb, lifetime = .Permanent}
	update_tactical_view(renderer, &room, {}, false)
	preview: Card_Range_Preview
	prepare_card_range_preview(renderer, &room, 14, &preview)
	for mark in preview.hits[:preview.hit_count] {
		testing.expect(t, tactical_render_visible(renderer, mark.cell), fmt.tprintf("marked %v in the fog", mark.cell))
	}
}

// The halo is kept at least 40 degrees of hue away from the four colours of the
// range and from the biome's own tint, in every biome and in the lab.
@(test)
test_the_hit_halo_keeps_its_distance_from_every_colour_it_sits_with :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, halo: rl.Color, tint: [3]u8, has_tint: bool, label: string) {
		hue := card_hit_hue(halo)
		testing.expect(t, card_hit_hue_gap(hue, card_hit_hue(CARD_LIGHT_REACH)) >= CARD_HIT_MIN_HUE_GAP, label)
		testing.expect(t, card_hit_hue_gap(hue, card_hit_hue(CARD_LIGHT_EFFECT)) >= CARD_HIT_MIN_HUE_GAP, label)
		testing.expect(t, card_hit_hue_gap(hue, card_hit_hue(CARD_LIGHT_TARGET)) >= CARD_HIT_MIN_HUE_GAP, label)
		testing.expect(t, card_hit_hue_gap(hue, card_hit_hue(CARD_LIGHT_INVALID)) >= CARD_HIT_MIN_HUE_GAP, label)
		if has_tint { testing.expect(t, card_hit_hue_gap(hue, card_hit_hue({tint.x, tint.y, tint.z, 255})) >= CARD_HIT_MIN_HUE_GAP, label) }
	}
	check(t, card_hit_halo_color({}, false), {}, false, "lab")
	for biome in campaign.Biome {
		if biome == .Count { continue }
		tint := world.metadata(biome).color
		check(t, card_hit_halo_color(tint, true), tint, true, fmt.tprintf("%v", biome))
	}
	// Violet everywhere but where the biome is itself violet.
	testing.expect_value(t, card_hit_halo_color({}, false), CARD_HIT_VIOLET)
	testing.expect_value(t, card_hit_halo_color(world.metadata(.Cyber).color, true), CARD_HIT_VIOLET)
	testing.expect_value(t, card_hit_halo_color(world.metadata(.Space).color, true), CARD_HIT_ACID)
}
