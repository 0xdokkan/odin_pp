package main

import "core:testing"
import game "game"
import level "level"

@(test)
test_mechanics_lab_is_an_open_endless_arena_with_only_shadow_steps :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, room.endless && game.tactical_enabled(&room))
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect_value(t, player.tactical.config.vision_size, 0)
	// Each action lasts its cost in real time here.
	testing.expect(t, player.tactical.config.timed_actions)
	testing.expect_value(t, data.tiles.width, MECHANICS_LAB_WIDTH)
	testing.expect_value(t, data.tiles.height, MECHANICS_LAB_HEIGHT)
	// No cover: every cell inside the border is walkable floor.
	for y in 1..<MECHANICS_LAB_HEIGHT-1 {
		for x in 1..<MECHANICS_LAB_WIDTH-1 {
			tile, inside := level.tile_at(&data, {x, y})
			testing.expect(t, inside && level.is_walkable(tile.kind))
		}
	}
	testing.expect(t, len(room.objects) == 0 && len(room.traps) == 0)
	// The deck holds Movimento Ombra and nothing else.
	testing.expect_value(t, player.deck.owned_count, len(MECHANICS_LAB_DECK))
	for card in player.deck.owned[:player.deck.owned_count] { testing.expect_value(t, card.definition_id, game.Card_Id.Shadow_Step) }
	testing.expect(t, player.deck.hand_count > 0)
}

@(test)
test_mechanics_lab_never_touches_the_profile_and_starts_directly :: proc(t: ^testing.T) {
	rs := roguelike_session_new()
	defer roguelike_destroy(rs)
	roguelike_parse_arguments(rs, []string{"--mechanics-lab"})
	testing.expect(t, rs.options.mechanics_lab)
	testing.expect(t, roguelike_requires_direct_start(rs))
	testing.expect(t, !roguelike_profile_enabled(rs))
}
