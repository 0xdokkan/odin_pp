package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// A trench between two plateaus, a bridge over it. The plateaus stand 12 steps high (x 1..4 and 8..11), the
// trench's floor is at 0 (x 5..7, a road along y), and the bridge (layer +1, 12 steps) crosses it along
// y = 3, from one plateau's edge to the other's. A ladder climbs the west wall, from (5,1) up to (4,1).
@(private = "file")
trench_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = {}) -> (room: Room) {
	rows := [?]string{
		"#############",
		"#@..........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#..........>#",
		"#############",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	for y in 1..=5 {
		for x in 1..=11 {
			if x <= 4 || x >= 8 { testing.expect(t, level.set_height(data, {x = x, y = y}, level.LAYER_SPACING)) }
		}
	}
	for x in 5..=7 {
		bridge := grid.Position{x = x, y = 3, layer = 1}
		testing.expect(t, level.set_tile(data, bridge, {kind = .Floor}))
		testing.expect(t, level.set_height(data, bridge, level.LAYER_SPACING))
	}
	testing.expect(t, level.add_ladder(data, {x = 5, y = 1}, {x = 4, y = 1}))
	error, _ := level.check_layers(data)
	testing.expect_value(t, error, level.Layer_Error.None)
	player^ = create_test_player(t)
	made: bool
	room, made = create_room(data, player, {enemies = spawns})
	testing.expect(t, made)
	return
}

// A hill 14 steps high (x 4..6) with a tunnel through it on layer -1, at 0, along y = 3: its mouths open on
// the flat ground at (3,3) and (7,3).
@(private = "file")
tunnel_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = {}) -> (room: Room) {
	rows := [?]string{
		"###########",
		"#@........#",
		"#.........#",
		"#.........#",
		"#.........#",
		"#........>#",
		"###########",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	for y in 1..=5 { for x in 4..=6 { testing.expect(t, level.set_height(data, {x = x, y = y}, 14)) } }
	for x in 4..=6 { testing.expect(t, level.set_tile(data, {x = x, y = 3, layer = -1}, {kind = .Floor})) }
	player^ = create_test_player(t)
	made: bool
	room, made = create_room(data, player, {enemies = spawns})
	testing.expect(t, made)
	return
}

// The player walks from a plateau onto the bridge, across it and off onto the other plateau, a layer at a
// time; off the bridge's side, a drop of twelve, he does not walk.
@(test)
test_the_player_walks_across_a_bridge :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := trench_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	room.player.position = {x = 4, y = 3}
	path := [?]grid.Position{{x = 5, y = 3, layer = 1}, {x = 6, y = 3, layer = 1}, {x = 7, y = 3, layer = 1}, {x = 8, y = 3}}
	for cell in path {
		testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
		testing.expect_value(t, room.player.position, cell)
	}
	room.player.position = {x = 6, y = 3, layer = 1}
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Blocked)
	testing.expect_value(t, room.player.position, grid.Position{x = 6, y = 3, layer = 1})
	// Under the bridge the road goes on along the trench, on the ground.
	room.player.position = {x = 6, y = 2}
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 6, y = 3})
}

// A ladder takes the walker up the trench's wall and down again, a cliff of twelve steps.
@(test)
test_a_ladder_climbs_a_cliff_both_ways :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := trench_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	room.player.position = {x = 5, y = 1}
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 4, y = 1})
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 5, y = 1})
	// Next to the ladder the wall is a cliff.
	room.player.position = {x = 5, y = 2}
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Blocked)
}

// Two fighters share a column on two layers: the one on the bridge passes over the one on the road, and
// neither strikes the other in melee; the bump goes to whoever stands on one's own layer.
@(test)
test_two_fighters_share_a_column_on_two_layers :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 4}, health = 20, attack = 1}}
	room := trench_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	room.player.position = {x = 6, y = 3, layer = 1}
	_, under := enemy_index_at(&room, {x = 6, y = 4})
	_, over := enemy_index_at(&room, {x = 6, y = 4, layer = 1})
	testing.expect(t, under && !over)
	// The foe in the trench beside the bridge does not reach the player on it, nor the player him.
	testing.expect(t, !melee_layers_meet(&room, room.enemies[0].position, room.player.position))
	positions: [MAX_ENEMIES_PER_ROOM]grid.Position
	positions[0] = room.enemies[0].position
	intent := plan_chaser_intent(&room, &room.enemies[0], room.enemies[0].position, &positions, 1, 0)
	testing.expect(t, intent.kind != .Attack)
	testing.expect_value(t, bump_cell(&room, room.player.position, {y = 1}), grid.Position{x = 6, y = 4, layer = 1})
	// Under the bridge, the foe and the player share the column (6,3).
	room.player.position = {x = 6, y = 3}
	room.enemies[0].position = {x = 6, y = 3, layer = 1}
	_, found := enemy_index_at(&room, room.player.position)
	testing.expect(t, !found)
}

// A push off the bridge's open edge falls onto the trench's floor, twelve steps down: the fall's damage is
// eleven, ten at most.
@(test)
test_a_push_off_the_bridge_falls_onto_the_road :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 3, layer = 1}, health = 20, attack = 1}}
	room := trench_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	foe := enemy_entity(room.enemies[0].id)
	query := query_entity_movement(&room, foe, {x = 6, y = 2})
	testing.expect(t, movement_query_is_clear(&query))
	testing.expect_value(t, query.destination, grid.Position{x = 6, y = 2})
	action := make_action(.Move, PLAYER_ENTITY, entity_target(foe), .Entity)
	testing.expect(t, add_effect(&action, move_effect(foe, {x = 6, y = 2})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 6, y = 2})
	testing.expect_value(t, room.enemies[0].health, i32(20-HEIGHT_FALL_MAX_DAMAGE))
	// Along the bridge a push stays on it.
	room.enemies[0].position = {x = 6, y = 3, layer = 1}
	along := query_entity_movement(&room, foe, {x = 7, y = 3})
	testing.expect(t, movement_query_is_clear(&along))
	testing.expect_value(t, along.destination, grid.Position{x = 7, y = 3, layer = 1})
}

// From the bridge one sees the trench and the trench sees the bridge; straight under the deck one does not
// see the deck's top.
@(test)
test_lines_of_sight_go_between_the_bridge_and_the_road :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := trench_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, blocked := room_line_blocker(&room, {x = 6, y = 3, layer = 1}, {x = 6, y = 5})
	testing.expect(t, !blocked)
	_, blocked = room_line_blocker(&room, {x = 6, y = 1}, {x = 6, y = 3, layer = 1})
	testing.expect(t, !blocked)
	_, blocked = room_line_blocker(&room, {x = 6, y = 3}, {x = 6, y = 3, layer = 1})
	testing.expect(t, blocked)
	// The player's sight with a footprint: from the road, the deck over his head is out of sight.
	room.player.position = {x = 6, y = 3}
	room.player.tactical.config.vision_size = 9
	testing.expect(t, tactical_cell_visible(&room, {x = 6, y = 5}))
	testing.expect(t, !tactical_cell_visible(&room, {x = 6, y = 3, layer = 1}))
}

// An area on the bridge takes the bridge's cells and not the road's under it or beside it; an area in the
// tunnel spills out of its mouth onto the ground, and not through the hill.
@(test)
test_an_area_takes_one_cell_a_column :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := trench_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	anchor := grid.Position{x = 6, y = 3, layer = 1}
	taken := 0
	for y in 2..=4 {
		for x in 5..=7 {
			if cell, ok := area_cell(&room, anchor, x, y); ok {
				testing.expect_value(t, cell.layer, i8(1))
				taken += 1
			}
		}
	}
	testing.expect_value(t, taken, 3)
	hill: level.Level
	hill_player: Player
	tunnel := tunnel_room(t, &hill, &hill_player)
	defer level.destroy(&hill)
	defer destroy_room(&tunnel)
	inside := grid.Position{x = 4, y = 3, layer = -1}
	cell, ok := area_cell(&tunnel, inside, 3, 3)
	testing.expect(t, ok && cell == grid.Position{x = 3, y = 3})
	cell, ok = area_cell(&tunnel, inside, 5, 3)
	testing.expect(t, ok && cell == grid.Position{x = 5, y = 3, layer = -1})
	_, ok = area_cell(&tunnel, inside, 5, 2)
	testing.expect(t, !ok)
	// A blast in the tunnel's mouth strikes the ground outside and not the hill's top over it.
	testing.expect(t, explosion_contains_cell(&tunnel, inside, {x = 3, y = 3}))
	testing.expect(t, !explosion_contains_cell(&tunnel, inside, {x = 4, y = 2}))
}

// The player walks into the tunnel through its mouth and out of the other; from the hill's top the tunnel
// is out of sight.
@(test)
test_the_player_walks_through_a_tunnel :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tunnel_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	room.player.position = {x = 3, y = 3}
	path := [?]grid.Position{{x = 4, y = 3, layer = -1}, {x = 5, y = 3, layer = -1}, {x = 6, y = 3, layer = -1}, {x = 7, y = 3}}
	for cell in path {
		testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
		testing.expect_value(t, room.player.position, cell)
	}
	// Beside the mouth the hill is a cliff.
	room.player.position = {x = 3, y = 2}
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Blocked)
	_, blocked := room_line_blocker(&room, {x = 5, y = 1}, {x = 5, y = 3, layer = -1})
	testing.expect(t, blocked)
	_, blocked = room_line_blocker(&room, {x = 1, y = 3}, {x = 5, y = 3, layer = -1})
	testing.expect(t, !blocked)
}

// The foes' distances go across the layers: over the bridge from one plateau to the other, up the ladder
// from the trench, into the tunnel through its mouth.
@(test)
test_the_foes_find_their_way_across_the_layers :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := trench_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	room.player.position = {x = 10, y = 3}
	distances := make([]int, room_table_cells(&data))
	defer delete(distances)
	rebuild_tactical_enemy_distances(&room, distances, .Melee)
	at :: proc(room: ^Room, distances: []int, cell: grid.Position) -> int {
		index, ok := room_table_index(room, cell)
		return distances[index] if ok else -2
	}
	// From the west plateau across the bridge: (1,3) to (10,3) is nine steps.
	testing.expect_value(t, at(&room, distances, {x = 1, y = 3}), 9)
	testing.expect_value(t, at(&room, distances, {x = 6, y = 3, layer = 1}), 4)
	// From the trench: up the ladder, then over the bridge.
	testing.expect(t, at(&room, distances, {x = 6, y = 5}) > 0)
	testing.expect_value(t, at(&room, distances, {x = 5, y = 1}), at(&room, distances, {x = 4, y = 1})+1)
	// A foe in the trench next to the ladder climbs it.
	spawns := [?]Enemy_Spawn{{position = {x = 5, y = 1}, health = 20, attack = 1}}
	walker: level.Level
	walker_player: Player
	climb := trench_room(t, &walker, &walker_player, spawns[:])
	defer level.destroy(&walker)
	defer destroy_room(&climb)
	climb.phase = .Combat
	climb.player.position = {x = 1, y = 1}
	rebuild_tactical_enemy_distances(&climb, climb.enemy_path_distances, .Melee)
	positions: [MAX_ENEMIES_PER_ROOM]grid.Position
	positions[0] = climb.enemies[0].position
	intent := plan_chaser_intent(&climb, &climb.enemies[0], climb.enemies[0].position, &positions, 1, 0)
	testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, intent.destination, grid.Position{x = 4, y = 1})
	hill: level.Level
	hill_player: Player
	tunnel := tunnel_room(t, &hill, &hill_player)
	defer level.destroy(&hill)
	defer destroy_room(&tunnel)
	tunnel.phase = .Combat
	tunnel.player.position = {x = 5, y = 3, layer = -1}
	cave := make([]int, room_table_cells(&hill))
	defer delete(cave)
	rebuild_tactical_enemy_distances(&tunnel, cave, .Melee)
	testing.expect_value(t, at(&tunnel, cave, {x = 1, y = 3}), 4)
	testing.expect_value(t, at(&tunnel, cave, {x = 5, y = 1}), -1)
}
