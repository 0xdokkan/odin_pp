package render

import "core:fmt"
import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private = "file")
card_range_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> (room: game.Room) {
	rows := [?]string{
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#.....#.....#",
		"#...........#",
		"#.....@.....#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#..........>#",
		"#############",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	made: bool
	player^, made = game.create_player({max_health = 40, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 43))
	_, added := game.add_owned_card(&player.deck, .Guard)
	testing.expect(t, added)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{
		{position = {7, 6}, health = 30, attack = 1},
		{position = {6, 7}, health = 30, attack = 1, archetype = .Custodian},
		{position = {9, 9}, health = 30, attack = 1},
	}
	obstacles := [?]grid.Position{{8, 6}}
	built: bool
	room, built = game.create_room(data, player, {enemies = enemies[:], obstacles = obstacles[:]})
	testing.expect(t, built)
	return
}

// Lighting must retain the gameplay query's complete reachability contract:
// empty anchors, optional blocked knockback, static .Cell anchors, the Lazzo's
// ring and Pinball's weight checks. A target can be in range but unplayable.
@(test)
test_card_range_light_matches_shared_targeting_for_the_catalog :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	preview: Card_Range_Preview
	player.deck.hand_count = 1
	for vision in ([2]int{0, 5}) {
		player.tactical.config.vision_size = vision
		update_tactical_view(renderer, &room, {}, false)
		for id in game.Card_Id.Strike..<game.Card_Id.Count {
			definition, found := game.card_definition_by_id(id)
			testing.expect(t, found)
			card := game.Card_Instance{id = 91, definition_id = id,
				lifetime = .Combat if definition.temporary_only else .Permanent}
			player.deck.hand[0] = card
			// A blocked shove, a heavy Pinball target and a normal enemy share
			// the same stored hover result used to draw path and impact cells.
			renderer.hovered_cell = {6, 7} if id == .Pinball else {7, 6}
			renderer.has_hovered_cell = true
			prepare_card_range_preview(renderer, &room, card.id, &preview)
			for y in 0..<data.tiles.height { for x in 0..<data.tiles.width {
				cell := grid.Position{x, y}
				expected := false
				if definition.targeting.shape != .None || cell == player.position {
					query := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, cell))
					expected = query.query.anchor_reachable || query.error == .None
				}
				if id == .Toxic_Wave {
					for enemy in room.enemies {
						if enemy.position == cell && game.tactical_card_enemy_in_area(&room, id, cell) { expected = true }
					}
				}
				expected = expected && tactical_render_visible(renderer, cell)
				testing.expect(t, card_range_contains(&preview, cell) == expected,
					fmt.tprintf("%v vision=%d cell=%v: lighting disagrees with targeting", id, vision, cell))
			} }
			if game.card_is_room_tool(id) { continue }
			hover := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, renderer.hovered_cell))
			testing.expect(t, preview.has_hover)
			testing.expect_value(t, preview.hover.error, hover.error)
			testing.expect_value(t, preview.hover.query.anchor, hover.query.anchor)
			testing.expect_value(t, preview.hover.query.path_count, hover.query.path_count)
			testing.expect_value(t, preview.hover.query.affected.count, hover.query.affected.count)
			testing.expect_value(t, preview.hover.has_movement, hover.has_movement)
			testing.expect_value(t, preview.hover.movement.destination, hover.movement.destination)
			testing.expect_value(t, preview.hover.movement.error, hover.movement.error)
		}
	}
}

// A per-frame preview carries no explored-cell memory or stale selection.
// Insufficient energy dims range without deleting it; Self stays on the player.
@(test)
test_card_range_light_resets_with_visibility_selection_and_control :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	preview: Card_Range_Preview
	player.tactical.config.vision_size = 3
	player.deck.hand_count = 1
	player.deck.hand[0] = {id = 92, definition_id = .Dash}
	update_tactical_view(renderer, &room, {}, false)
	renderer.has_hovered_cell, renderer.hovered_cell = true, {5, 6}
	prepare_card_range_preview(renderer, &room, 92, &preview)
	testing.expect(t, preview.active && preview.has_hover)
	testing.expect(t, card_range_contains(&preview, {5, 6}))
	testing.expect(t, !card_range_contains(&preview, {-1, 6}))

	player.position = {3, 6}
	update_tactical_view(renderer, &room, {}, false)
	// A stale pointer into fog must not reveal a new target or retain the old
	// room's illumination after the player moves.
	renderer.has_hovered_cell, renderer.hovered_cell = true, {5, 6}
	prepare_card_range_preview(renderer, &room, 92, &preview)
	testing.expect(t, card_range_contains(&preview, {2, 6}))
	testing.expect(t, !card_range_contains(&preview, {5, 6}) && !preview.has_hover)

	player.deck.hand[0] = {id = 93, definition_id = .Guard}
	renderer.hovered_cell = {2, 6}
	prepare_card_range_preview(renderer, &room, 93, &preview)
	testing.expect(t, preview.active && preview.has_hover)
	testing.expect_value(t, preview.hover.query.anchor, player.position)
	testing.expect(t, card_range_contains(&preview, player.position))
	testing.expect(t, !card_range_contains(&preview, {2, 6}))
	player.deck.energy = 0
	prepare_card_range_preview(renderer, &room, 93, &preview)
	testing.expect(t, !preview.affordable && card_range_contains(&preview, player.position))

	for disabled in 0..<4 {
		// Start each branch with a populated preview, so reset is exercised.
		room.phase, renderer.timeline.count = .Combat, 0
		prepare_card_range_preview(renderer, &room, 93, &preview)
		testing.expect(t, preview.active)
		selected := u32(93)
		switch disabled {
		case 0: selected = 0
		case 1: selected = 92 // A card no longer in the hand.
		case 2: room.phase = .Loot
		case 3: renderer.timeline.count = 1
		}
		prepare_card_range_preview(renderer, &room, selected, &preview)
		testing.expect(t, !preview.active && !preview.has_hover)
		for lit in preview.cells { testing.expect(t, !lit) }
	}
}
