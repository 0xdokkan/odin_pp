package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"

@(test)
test_lab_health_label_counts_the_health_and_stays_on_the_board :: proc(t: ^testing.T) {
	testing.expect_value(t, string(lab_health_text(12, 18, 0)), "HP 12/18")
	testing.expect_value(t, string(lab_health_text(12, 18, 3)), "HP 12/18 / SC 3")
	testing.expect_value(t, lab_health_step(18), i32(1))
	testing.expect_value(t, lab_health_step(40), i32(5))
	viewport := rl.Rectangle{12, 110, 1256, 400}
	// Behind the top panel: just below it, straight under the enemy.
	at := lab_label_anchor(viewport, {400, 12}, {120, 44})
	testing.expect(t, at.x == 400 && at.y == 110+44+2)
	// Off the side: pulled in whole.
	at = lab_label_anchor(viewport, {5, 300}, {120, 44})
	testing.expect(t, at.x == 12+60 && at.y == 300)
	at = lab_label_anchor(viewport, {640, 300}, {120, 44})
	testing.expect(t, at.x == 640 && at.y == 300)
}

// The lab's inspector keeps the enemy it showed while the camera glides under
// a still mouse; the classic one follows the cell under the mouse only.
@(test)
test_lab_inspector_keeps_its_enemy_while_the_board_moves :: proc(t: ^testing.T) {
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
