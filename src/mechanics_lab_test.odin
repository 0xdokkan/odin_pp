package main

import "core:testing"
import game "game"
import level "level"

@(test)
test_mechanics_lab_is_an_open_endless_arena_with_the_cards_under_test :: proc(t: ^testing.T) {
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
	// The deck: one Movimento Ombra and one of each card of Phase 2, all in hand.
	testing.expect_value(t, player.deck.owned_count, len(MECHANICS_LAB_DECK))
	for id in ([?]game.Card_Id{.Shadow_Step, .Poison_Pool, .Wildfire, .Deflect, .Coffin, .Fate_Dice, .Venom_Blade}) {
		copies := 0
		for card in player.deck.owned[:player.deck.owned_count] { if card.definition_id == id { copies += 1 } }
		testing.expectf(t, copies == 1, "%v: %d copies", id, copies)
	}
	testing.expect_value(t, player.deck.hand_count, len(MECHANICS_LAB_DECK))
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
