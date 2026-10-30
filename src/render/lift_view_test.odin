package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

// A road with a bridge over it on layer +1, 12 steps up (x 3..5, y 2), and the player standing on the deck: the board
// draws him on the deck, not on the road under it, as it draws a foe there.
@(test)
test_the_player_on_a_bridge_is_drawn_on_its_deck :: proc(t: ^testing.T) {
	rows := [?]string{
		"#########",
		"#@......#",
		"#.......#",
		"#......>#",
		"#########",
	}
	data, parsed, _ := level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	defer level.destroy(&data)
	for x in 3..=5 {
		deck := grid.Position{x = x, y = 2, layer = 1}
		testing.expect(t, level.set_tile(&data, deck, {kind = .Floor}))
		testing.expect(t, level.set_height(&data, deck, level.LAYER_SPACING))
	}
	player, created := game.create_player(game.Player_Stats{max_health = 20, attack = 2, defense = 0})
	testing.expect(t, created)
	spawns := [?]game.Enemy_Spawn{{position = {x = 5, y = 2, layer = 1}, health = 10, attack = 1, archetype = .Chaser}}
	room, made := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, made)
	defer game.destroy_room(&room)
	room.player.position = {x = 3, y = 2, layer = 1}
	set_board_level(&data)
	set_board_actors(&room)
	defer set_board_level(nil)
	deck := f32(level.LAYER_SPACING)*game.HEIGHT_STEP_DRAWN
	testing.expect_value(t, entity_point_ground(game.enemy_entity(room.enemies[0].id), {5, 2}), deck)
	testing.expect_value(t, entity_point_ground(game.PLAYER_ENTITY, {3, 2}), deck)
	// A point no figure stands on keeps the ground's floor, the road under the deck.
	testing.expect_value(t, entity_point_ground(NO_FIGURE, {3, 2}), f32(0))
}

// A shaft from a deck on layer +1, 14 steps up, down to the ground at (3,2): the player riding the platform down is
// drawn on it, halfway at half the height, and on the ground once it stops.
@(test)
test_the_player_riding_a_lift_is_drawn_on_its_platform :: proc(t: ^testing.T) {
	rows := [?]string{
		"#########",
		"#@......#",
		"#.......#",
		"#......>#",
		"#########",
	}
	data, parsed, _ := level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	defer level.destroy(&data)
	top, foot := grid.Position{x = 3, y = 2, layer = 1}, grid.Position{x = 3, y = 2}
	testing.expect(t, level.set_tile(&data, top, {kind = .Floor}))
	testing.expect(t, level.set_height(&data, top, 14))
	testing.expect(t, level.add_lift(&data, foot, top, 1))
	player, created := game.create_player(game.Player_Stats{max_health = 20, attack = 2, defense = 0})
	testing.expect(t, created)
	room, made := game.create_room(&data, &player, {})
	testing.expect(t, made)
	defer game.destroy_room(&room)
	room.phase = .Loot
	room.player.position = top
	testing.expect(t, game.lift_board(&room, game.PLAYER_ENTITY, top))
	game.lift_tick(&room, game.lift_journey_seconds(&room, 0)*0.5)
	set_board_level(&data)
	set_board_actors(&room)
	defer set_board_level(nil)
	high := f32(14)*game.HEIGHT_STEP_DRAWN
	halfway := entity_point_ground(game.PLAYER_ENTITY, {3, 2})
	testing.expectf(t, abs(halfway-high*0.5) < 0.01, "halfway down the player is drawn at %v, not %v", halfway, high*0.5)
	game.lift_tick(&room, game.lift_journey_seconds(&room, 0))
	set_board_actors(&room)
	testing.expect_value(t, entity_point_ground(game.PLAYER_ENTITY, {3, 2}), f32(0))
}
