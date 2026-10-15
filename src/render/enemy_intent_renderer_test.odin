package render

import "core:testing"
import game "../game"
import grid "../grid"

make_enemy_intent_renderer_test_room :: proc(enemies: []game.Enemy) -> game.Room {
	result := game.Room{phase = .Combat}
	result.enemies = make([dynamic]game.Enemy, len(enemies))
	for enemy, index in enemies {
		result.enemies[index] = enemy
	}
	return result
}

@(test)
test_focused_enemy_intent_uses_hovered_combat_enemy_with_an_intent :: proc(t: ^testing.T) {
	enemies := [?]game.Enemy{
		{id = 11, position = {x = 2, y = 3}, intent = {kind = .Move}},
		{id = 22, position = {x = 4, y = 3}, intent = {kind = .Attack}},
	}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)
	renderer := Renderer{hovered_cell = {x = 4, y = 3}, has_hovered_cell = true}

	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(22))
	renderer.hovered_cell = {x = 2, y = 3}
	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(11))

	renderer.has_hovered_cell = false
	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(0))
	renderer.has_hovered_cell = true
	renderer.hovered_cell = {x = 8, y = 8}
	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(0))
	testing.expect_value(t, focused_enemy_intent_id(nil, &room), u32(0))
	testing.expect_value(t, focused_enemy_intent_id(&renderer, nil), u32(0))
}

@(test)
test_focused_enemy_intent_ignores_non_combat_and_missing_intents :: proc(t: ^testing.T) {
	enemies := [?]game.Enemy{
		{id = 7, position = {x = 3, y = 2}, intent = {kind = .Move}},
	}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)
	renderer := Renderer{hovered_cell = {x = 3, y = 2}, has_hovered_cell = true}

	room.phase = .Loot
	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(0))
	room.phase = .Combat
	room.enemies[0].intent = {}
	testing.expect_value(t, focused_enemy_intent_id(&renderer, &room), u32(0))
}

@(test)
test_enemy_intent_cell_counts_aggregate_paths_threats_and_focus :: proc(t: ^testing.T) {
	enemies := [?]game.Enemy{
		{id = 11, intent = {kind = .Move}},
		{id = 22, intent = {kind = .Move}},
		{id = 33, intent = {kind = .Attack}},
		{id = 44, intent = {kind = .Attack}},
	}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)
	overlap := grid.Position{x = 3, y = 2}

	room.enemies[0].intent.path[0] = {x = 2, y = 2}
	room.enemies[0].intent.path[1] = overlap
	room.enemies[0].intent.path_count = 2
	room.enemies[1].intent.path[0] = overlap
	room.enemies[1].intent.path[1] = {x = 4, y = 2}
	room.enemies[1].intent.path_count = 2
	room.enemies[2].intent.threatened_cells[0] = overlap
	room.enemies[2].intent.threatened_cells[1] = {x = 3, y = 3}
	room.enemies[2].intent.threatened_cell_count = 2
	room.enemies[3].intent.threatened_cells[0] = overlap
	room.enemies[3].intent.threatened_cell_count = 1

	move_count, threat_count, move_focused, threat_focused :=
		enemy_intent_cell_counts(&room, overlap, 22)
	testing.expect_value(t, move_count, 2)
	testing.expect_value(t, threat_count, 2)
	testing.expect(t, move_focused)
	testing.expect(t, !threat_focused)

	move_count, threat_count, move_focused, threat_focused =
		enemy_intent_cell_counts(&room, overlap, 33)
	testing.expect_value(t, move_count, 2)
	testing.expect_value(t, threat_count, 2)
	testing.expect(t, !move_focused)
	testing.expect(t, threat_focused)

	move_count, threat_count, move_focused, threat_focused =
		enemy_intent_cell_counts(&room, {x = 9, y = 9}, 22)
	testing.expect_value(t, move_count, 0)
	testing.expect_value(t, threat_count, 0)
	testing.expect(t, !move_focused)
	testing.expect(t, !threat_focused)

	move_count, threat_count, move_focused, threat_focused =
		enemy_intent_cell_counts(nil, overlap, 22)
	testing.expect_value(t, move_count, 0)
	testing.expect_value(t, threat_count, 0)
	testing.expect(t, !move_focused)
	testing.expect(t, !threat_focused)
}

@(test)
test_charge_intent_aggregates_path_and_threat_cells :: proc(t: ^testing.T) {
	charge := game.Enemy{
		id = 71,
		archetype = .Brute,
		intent = {kind = .Charge},
	}
	path_only := grid.Position{x = 2, y = 2}
	overlap := grid.Position{x = 3, y = 2}
	threat_only := grid.Position{x = 4, y = 2}
	charge.intent.path[0] = path_only
	charge.intent.path[1] = overlap
	charge.intent.path_count = 2
	charge.intent.threatened_cells[0] = overlap
	charge.intent.threatened_cells[1] = threat_only
	charge.intent.threatened_cell_count = 2
	enemies := [?]game.Enemy{charge}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)

	move_count, threat_count, move_focused, threat_focused :=
		enemy_intent_cell_counts(&room, path_only, charge.id)
	testing.expect_value(t, move_count, 1)
	testing.expect_value(t, threat_count, 0)
	testing.expect(t, move_focused)
	testing.expect(t, !threat_focused)

	move_count, threat_count, move_focused, threat_focused =
		enemy_intent_cell_counts(&room, overlap, charge.id)
	testing.expect_value(t, move_count, 1)
	testing.expect_value(t, threat_count, 1)
	testing.expect(t, move_focused)
	testing.expect(t, threat_focused)

	move_count, threat_count, move_focused, threat_focused =
		enemy_intent_cell_counts(&room, threat_only, charge.id)
	testing.expect_value(t, move_count, 0)
	testing.expect_value(t, threat_count, 1)
	testing.expect(t, !move_focused)
	testing.expect(t, threat_focused)
}

@(test)
test_enemy_intent_path_contains_handles_present_absent_and_nil_intents :: proc(t: ^testing.T) {
	intent := game.Enemy_Intent{kind = .Move}
	intent.path[0] = {x = 2, y = 1}
	intent.path[1] = {x = 3, y = 1}
	intent.path_count = 2

	testing.expect(t, enemy_intent_path_contains(&intent, {x = 2, y = 1}))
	testing.expect(t, enemy_intent_path_contains(&intent, {x = 3, y = 1}))
	testing.expect(t, !enemy_intent_path_contains(&intent, {x = 4, y = 1}))
	testing.expect(t, !enemy_intent_path_contains(nil, {x = 2, y = 1}))

	intent.path_count = 0
	testing.expect(t, !enemy_intent_path_contains(&intent, {x = 2, y = 1}))
}
