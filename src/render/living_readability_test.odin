package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

@(test)
test_living_heart_reads_the_health_over_the_maximum :: proc(t: ^testing.T) {
	testing.expect_value(t, living_heart_text(12, 18), "12/18")
	testing.expect_value(t, living_heart_text(-3, 18), " 0/18")
	width, height := living_heart_size("12/18")
	// The heart, a pixel, five figures, and a token's paper and edge.
	testing.expect(t, width == 7+1+5*6-1+7 && height == 14)
	// The intent stays in the same tag, beside the full health text, without
	// growing its height or changing size as the plan changes.
	compact_width, compact_height := living_heart_size("12/18", true)
	testing.expect(t, compact_width == width+INTENT_GLYPH_SIZE+4 && compact_height == height)
	testing.expect(t, width+INTENT_GLYPH_SIZE < compact_width-2)
	for icon in Intent_Icon {
		pixels := 0
		for row in INTENT_GLYPHS[icon] {
			testing.expect(t, row < 1<<INTENT_GLYPH_SIZE)
			pixels += int(row)
		}
		testing.expect(t, (pixels > 0) == (icon != .None))
	}
	slash, ok := living_token_glyph('/')
	testing.expect(t, ok && slash == 12)
	// Every figure of a tag is drawable.
	for r in living_heart_text(123, 456) {
		_, found := living_token_glyph(u8(r))
		testing.expect(t, found)
	}
}

// The old allocator moved a stationary enemy's tag whenever another actor,
// status, fuse or panel took its preferred spot. Such occupancy now changes
// only the placement of secondary labels, never this attachment.
@(test)
test_living_heart_stays_attached_when_surrounding_labels_change :: proc(t: ^testing.T) {
	head := view.Vec2{300, 200}
	size := view.Vec2{44, 14}
	expected := rl.Rectangle{278, 186, 44, 14}
	for occupied in ([4]rl.Rectangle{{}, {276, 130, 48, 75}, {270, 120, 60, 110}, {0, 0, 2000, 2000}}) {
		layout := Tactical_Label_Layout{count = 1}
		layout.bounds[0] = occupied
		first := place_living_heart(&layout, head, size)
		testing.expect_value(t, first, expected)
		testing.expect(t, layout.count == 2 && layout.bounds[1] == expected)
		// Changing enemy order or adding a nearby tag cannot move either.
		_ = place_living_heart(&layout, {310, 204}, size)
		testing.expect_value(t, place_living_heart(&layout, head, size), expected)
		testing.expect(t, !living_heart_is_clear(&layout, expected))
	}
	layout: Tactical_Label_Layout
	moved := place_living_heart(&layout, {head.x+21, head.y-8}, size)
	testing.expect_value(t, moved, rl.Rectangle{expected.x+21, expected.y-8, 44, 14})
	// No screen-edge clamp detaches the tag from an enemy behind the HUD.
	testing.expect_value(t, place_living_heart(&layout, {0, 4}, size), rl.Rectangle{-22, -10, 44, 14})
	// Full bookkeeping storage must not hide or relocate an attachment.
	layout.count = len(layout.bounds)
	testing.expect_value(t, place_living_heart(&layout, head, size), expected)
}

@(test)
test_living_heart_keeps_its_width_across_damage_and_healing :: proc(t: ^testing.T) {
	for maximum in ([4]i32{9, 18, 100, 456}) {
		width, height := living_heart_size(living_heart_text(maximum, maximum), true)
		layout: Tactical_Label_Layout
		full := place_living_heart(&layout, {300, 200}, {f32(width), f32(height)})
		for hp in ([7]i32{maximum, 9, 1, 0, -3, 8, maximum}) {
			w, h := living_heart_size(living_heart_text(hp, maximum), true)
			testing.expect(t, w == width && h == height)
			testing.expect_value(t, place_living_heart(&layout, {300, 200}, {f32(w), f32(h)}), full)
		}
	}
	testing.expect_value(t, living_heart_text(9, 18), " 9/18")
	// Defensive formatting still shows overheal rather than truncating it.
	testing.expect_value(t, living_heart_text(100, 18), "100/18")
}

// The heart's pixel rows are runs of lit pixels: the glyph is the classic
// heart, seven wide, widest in its middle rows and a single pixel at its tip.
@(test)
test_living_heart_glyph_is_a_heart :: proc(t: ^testing.T) {
	widths: [7]int
	for row, index in LIVING_HEART_GLYPH {
		for column in 0..<LIVING_HEART_WIDTH { if row&(u8(1)<<u8(column)) != 0 { widths[index] += 1 } }
	}
	testing.expect(t, widths == {4, 7, 7, 7, 5, 3, 1})
	// Two lobes: the top row is split in the middle.
	testing.expect(t, LIVING_HEART_GLYPH[0]&0b0001000 == 0)
}

// A living board's inspector keeps the enemy it showed while the camera glides
// under a still mouse; the flipbook fallback follows the hovered cell.
@(test)
test_living_inspector_keeps_its_enemy_while_the_board_moves :: proc(t: ^testing.T) {
	enemies := [?]game.Enemy{{id = 5, position = {x = 3, y = 2}, health = 7, max_health = 10}}
	room := make_intent_presentation_test_room(enemies[:])
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.living, renderer.tactical.no_fog = true, true
	renderer.hovered_cell, renderer.has_hovered_cell = {x = 3, y = 2}, true
	enemy, found := tactical_inspected_enemy(renderer, &room)
	testing.expect(t, found && enemy.id == 5)
	renderer.hovered_cell = {x = 6, y = 6}
	enemy, found = tactical_inspected_enemy(renderer, &room)
	testing.expect(t, found && enemy.id == 5)
	renderer.has_hovered_cell = false
	enemy, found = tactical_inspected_enemy(renderer, &room)
	testing.expect(t, found && enemy.id == 5)
	// Gone from the room: nothing left to show.
	clear(&room.enemies)
	_, found = tactical_inspected_enemy(renderer, &room)
	testing.expect(t, !found && renderer.tactical.inspected == 0)
	renderer.tactical.living = false
	append(&room.enemies, enemies[0])
	renderer.hovered_cell, renderer.has_hovered_cell = {x = 3, y = 2}, true
	_, found = tactical_inspected_enemy(renderer, &room)
	testing.expect(t, found)
	renderer.hovered_cell = {x = 6, y = 6}
	_, found = tactical_inspected_enemy(renderer, &room)
	testing.expect(t, !found)
}

@(test)
test_living_tokens_one_per_blow_and_side_by_side :: proc(t: ^testing.T) {
	testing.expect_value(t, living_token_text(4, false), "-4")
	testing.expect_value(t, living_token_text(3, true), "+3")
	width, height := living_token_size("-12")
	testing.expect(t, width == 3*6-1+7 && height == 14)
	for r in "0123456789+-" {
		_, ok := living_token_glyph(u8(r))
		testing.expect(t, ok)
	}
	_, ok := living_token_glyph('x')
	testing.expect(t, !ok)
	state := new(Living_State)
	defer free(state)
	blow := game.Game_Event{target = game.enemy_entity(3), source = game.PLAYER_ENTITY, amount = 4, pulse_count = 7}
	testing.expect(t, living_token_spawn(state, blow, false, 1))
	// The same blow seen again on a later frame of its cue: still one token.
	testing.expect(t, !living_token_spawn(state, blow, false, 1.05))
	second := blow
	second.pulse_count = 8
	testing.expect(t, living_token_spawn(state, second, false, 1.3))
	cure := blow
	testing.expect(t, living_token_spawn(state, cure, true, 1.4))
	stacks: [3]int
	count := 0
	for token in state.tokens {
		if !token.used { continue }
		stacks[count] = token.stack
		count += 1
	}
	testing.expect(t, count == 3 && stacks == {0, 1, 2})
	testing.expect(t, state.tokens[0].born > 1)
	living_tokens_free(state)
	for token in state.tokens { testing.expect(t, !token.used) }
}
