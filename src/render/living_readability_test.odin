package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

@(test)
test_living_heart_reads_the_health_over_the_maximum :: proc(t: ^testing.T) {
	testing.expect_value(t, living_heart_text(12, 18), "12/18")
	testing.expect_value(t, living_heart_text(-3, 18), "0/18")
	width, height := living_heart_size("12/18")
	// The heart, a pixel, five figures, and a token's paper and edge.
	testing.expect(t, width == 7+1+5*6-1+7 && height == 14)
	slash, ok := living_token_glyph('/')
	testing.expect(t, ok && slash == 12)
	// Every figure of a tag is drawable.
	for r in living_heart_text(123, 456) {
		_, found := living_token_glyph(u8(r))
		testing.expect(t, found)
	}
}

// Centred over the head, left of the enemy's own seal, lifted past another
// tag, never out of the board, and always shown.
@(test)
test_living_heart_keeps_clear_of_seals_and_other_tags :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{12, 84, 936, 260}
	size := view.Vec2{44, 14}
	layout: Tactical_Label_Layout
	alone := place_living_heart(&layout, {300, 200}, size, {}, false, viewport)
	testing.expect(t, alone == rl.Rectangle{278, 186, 44, 14})
	testing.expect(t, layout.count == 1 && layout.bounds[0] == alone)
	// A seal close to the head pushes the tag left of the square it keeps.
	layout = {}
	seal := rl.Vector2{330, 190}
	layout.bounds[0] = living_heart_seal_bounds(seal)
	layout.count = 1
	beside := place_living_heart(&layout, {300, 200}, size, seal, true, viewport)
	testing.expect(t, beside.x+beside.width < seal.x-LIVING_HEART_SEAL_KEEP-2 && beside.y == 186)
	testing.expect(t, !rl.CheckCollisionRecs(beside, layout.bounds[0]))
	// A seal far to the right leaves it centred.
	layout = {}
	far := place_living_heart(&layout, {300, 200}, size, {400, 190}, true, viewport)
	testing.expect(t, far.x == 278)
	// Two heads together: the second tag goes up a row.
	layout = {}
	first := place_living_heart(&layout, {300, 200}, size, {}, false, viewport)
	second := place_living_heart(&layout, {310, 204}, size, {}, false, viewport)
	testing.expect(t, !rl.CheckCollisionRecs(first, second) && second.y < first.y)
	// Behind the top panel: just under it; off the side: pulled in whole.
	layout = {}
	top := place_living_heart(&layout, {300, 60}, size, {}, false, viewport)
	testing.expect(t, top.y == viewport.y)
	side := place_living_heart(&layout, {0, 300}, size, {}, false, viewport)
	testing.expect(t, side.x == viewport.x)
	// A crowd that fills every row still shows it, in its first place.
	layout = {}
	layout.bounds[0], layout.count = {0, 0, 2000, 2000}, 1
	crowd := place_living_heart(&layout, {300, 200}, size, {}, false, viewport)
	testing.expect(t, crowd == rl.Rectangle{278, 186, 44, 14} && layout.count == 2)
	// The player's figure behind the enemy: the tag steps aside, never over it.
	layout = {}
	figure := rl.Rectangle{270, 120, 60, 110}
	aside := place_living_heart(&layout, {300, 200}, size, {}, false, viewport, figure)
	testing.expect(t, !rl.CheckCollisionRecs(aside, figure) && aside.y == 186 && aside.x+aside.width <= figure.x)
	// Blocked by another label instead, with the figure far off: one step
	// aside, never across the board past the figure.
	layout = {}
	layout.bounds[0], layout.count = {276, 130, 48, 75}, 1
	near := place_living_heart(&layout, {300, 200}, size, {}, false, viewport, {600, 100, 60, 110})
	testing.expect(t, near.x == 230 && near.y == 186)
	// A head behind the top panel, with the lab's banner there too: the tag
	// waits under the banner, over its enemy.
	layout = {}
	layout.bounds[0], layout.count = {200, 84, 400, 60}, 1
	under := place_living_heart(&layout, {300, 40}, size, {}, false, viewport)
	testing.expect(t, under.y > 84+60 && under.x == 278)
	// Never past its enemy's feet: a tag that cannot sit over its own enemy
	// stays in its first place rather than wander off below another figure.
	layout.count = 1
	kept := place_living_heart(&layout, {300, 40}, size, {}, false, viewport, {}, 120)
	testing.expect(t, kept.y == viewport.y)
}

// A crowd that takes every row over the head, both sides and the cells down
// to the feet: the tag takes the nearest free place around its first. With
// none free, it lies over other tags where it hides the least of them, never
// under a seal (drawn over it).
@(test)
test_living_heart_finds_its_place_in_a_crowd :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{12, 84, 936, 400}
	size := view.Vec2{44, 14}
	layout: Tactical_Label_Layout
	layout.bounds[0], layout.count = {226, 230, 150, 120}, 1
	near := place_living_heart(&layout, {300, 300}, size, {}, false, viewport, {}, 330)
	testing.expect_value(t, near, rl.Rectangle{278, 206, 44, 14})
	// Everything taken: a seal (another enemy's), and the other tags.
	layout = {}
	seal := living_heart_seal_bounds({300, 293})
	layout.bounds[0], layout.bounds[1], layout.count = seal, {0, 0, 2000, 2000}, 2
	over := place_living_heart(&layout, {300, 300}, size, {}, false, viewport, {}, 1e9, 1)
	testing.expect_value(t, over, rl.Rectangle{278, 238, 44, 14})
	testing.expect(t, !rl.CheckCollisionRecs(over, seal))
	// Not told which places are tags: its first place.
	layout.count = 2
	first := place_living_heart(&layout, {300, 300}, size, {}, false, viewport)
	testing.expect_value(t, first, rl.Rectangle{278, 286, 44, 14})
	// Over other tags, where it hides the least of them: in a strip one tag
	// high, its first place under a seal, the place over a sliver of a tag
	// rather than the nearer one wholly over another.
	layout = {}
	strip := rl.Rectangle{152, 216, 240, 14}
	layout.bounds[0] = {250, 216, 40, 14}
	layout.bounds[1], layout.bounds[2] = {196, 216, 52, 14}, {300, 216, 8, 14}
	layout.bounds[3], layout.bounds[4] = {150, 216, 50, 14}, {340, 216, 60, 14}
	layout.count = 5
	least := place_living_heart(&layout, {270, 230}, size, {}, false, strip, {}, 1e9, 1)
	testing.expect_value(t, least, rl.Rectangle{296, 216, 44, 14})
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
// under a still mouse; the classic one follows the cell under the mouse only.
@(test)
test_living_inspector_keeps_its_enemy_while_the_board_moves :: proc(t: ^testing.T) {
	enemies := [?]game.Enemy{{id = 5, position = {x = 3, y = 2}, health = 7, max_health = 10}}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.living = true
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
