package advisor

import "core:mem"
import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The map exceeds both the old 224x224 save capacity and a 16-bit flat index.
// Coordinates stay within the supported world bounds: no new combat rules.
@(private = "file")
LARGE_MAP_TEST_SIDE :: 320
@(private = "file")
LARGE_MAP_TEST_PLAYER :: grid.Position{x = 270, y = 270}

@(private = "file")
Large_Map_Test_Fixture :: struct {
	data: level.Level,
	player: game.Player,
	room: game.Room,
}

@(private = "file")
large_map_test_destroy :: proc(f: ^Large_Map_Test_Fixture) {
	if f == nil { return }
	game.destroy_room(&f.room)
	level.destroy(&f.data)
	free(f)
}

@(private = "file")
large_map_test_create :: proc(raised := false) -> ^Large_Map_Test_Fixture {
	f := new(Large_Map_Test_Fixture)
	ready := false
	defer { if !ready { large_map_test_destroy(f) } }
	ok: bool
	f.data, ok = level.create(LARGE_MAP_TEST_SIDE, LARGE_MAP_TEST_SIDE, {kind = .Floor})
	if !ok { return nil }
	f.data.player_spawn, f.data.has_player_spawn = LARGE_MAP_TEST_PLAYER, true
	if !level.set_tile(&f.data, {x = 310, y = 310}, {kind = .Exit}) { return nil }
	if raised && !level.set_height(&f.data, LARGE_MAP_TEST_PLAYER, 3) { return nil }
	f.player, ok = game.create_player({max_health = 100, attack = 5, defense = 0})
	if !ok { return nil }
	if !game.configure_tactical(&f.player, game.EXPEDITION_TACTICAL_CONFIG) { return nil }
	foes := [1]game.Enemy_Spawn{{position = grid.offset(LARGE_MAP_TEST_PLAYER, 1, 0), health = 2, attack = 1}}
	f.room, ok = game.create_room(&f.data, &f.player, {enemies = foes[:], room_seed = 42})
	if !ok || !game.configure_expedition_combat(&f.room) { return nil }
	ready = true
	return f
}

@(private = "file")
large_map_test_pour :: proc(room: ^game.Room, cell: grid.Position, amount: i32) -> bool {
	action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
	if !game.add_effect(&action, game.place_ground_effect(cell, .Poison, amount)) { return false }
	return game.resolve_action(room, &action).accepted
}

@(private = "file")
large_map_test_copy :: proc(t: ^testing.T) {
	f := large_map_test_create(true)
	if !testing.expect(t, f != nil) { return }
	defer large_map_test_destroy(f)
	cell := grid.offset(LARGE_MAP_TEST_PLAYER, 0, 2)
	index, inside := game.room_table_index(&f.room, cell)
	if !testing.expect(t, inside && index > 65535 && len(f.room.ground.pool) == 102400) { return }
	wrapped := game.room_table_cell(&f.room, index%65536)
	testing.expect(t, wrapped != cell)
	if !testing.expect(t, large_map_test_pour(&f.room, cell, 3)) { return }
	testing.expect_value(t, game.ground_pool_at(&f.room, wrapped), i32(0))

	snapshot := new(Snapshot)
	defer free(snapshot)
	if !testing.expect(t, snapshot_init(snapshot)) { return }
	defer snapshot_destroy(snapshot)
	rehearsal := new(Rehearsal)
	defer free(rehearsal)
	if !testing.expect(t, rehearsal_init(rehearsal)) { return }
	defer rehearsal_destroy(rehearsal)
	if !testing.expect(t, snapshot_take(snapshot, &f.room) && rehearsal_begin(rehearsal, snapshot)) { return }
	copy := rehearsal_room(rehearsal)
	testing.expect(t, len(snapshot.level.tiles.cells) == 102400 && len(copy.level_data.tiles.cells) == 102400)
	testing.expect(t, &snapshot.level.tiles.cells[index] != &f.data.tiles.cells[index])
	testing.expect(t, &copy.level_data.tiles.cells[index] != &snapshot.level.tiles.cells[index])
	testing.expect(t, &copy.ground.pool[index] != &snapshot.room.ground.pool[index] && &snapshot.room.ground.pool[index] != &f.room.ground.pool[index])
	testing.expect(t, &copy.enemy_path_distances[index] != &snapshot.room.enemy_path_distances[index])
	testing.expect_value(t, snapshot.room.enemy_path_distances[index], f.room.enemy_path_distances[index])
	testing.expect_value(t, game.ground_pool_at(copy, cell), i32(3))
	testing.expect_value(t, level.height_at(copy.level_data, LARGE_MAP_TEST_PLAYER), i32(3))

	// The actual ground effect writes a high index; a geometry edit invalidates
	// the rehearsal. The next try must restore both, without touching the root.
	changed := grid.offset(LARGE_MAP_TEST_PLAYER, 0, 3)
	if !testing.expect(t, large_map_test_pour(copy, changed, 5)) { return }
	testing.expect(t, level.set_height(copy.level_data, LARGE_MAP_TEST_PLAYER, 4))
	testing.expect_value(t, game.ground_pool_at(copy, changed), i32(5))
	testing.expect_value(t, game.ground_pool_at(&snapshot.room, changed), i32(0))
	testing.expect_value(t, game.ground_pool_at(&f.room, changed), i32(0))
	testing.expect_value(t, level.height_at(&snapshot.level, LARGE_MAP_TEST_PLAYER), i32(3))
	testing.expect_value(t, level.height_at(&f.data, LARGE_MAP_TEST_PLAYER), i32(3))
	copy = rehearsal_room(rehearsal)
	testing.expect_value(t, rehearsal.level_copies, 1)
	testing.expect_value(t, rehearsal.pool_copies, 1)
	testing.expect_value(t, game.ground_pool_at(copy, changed), i32(0))
	testing.expect_value(t, game.ground_pool_at(copy, cell), i32(3))
	testing.expect_value(t, game.ground_pool_at(copy, wrapped), i32(0))
	testing.expect_value(t, level.height_at(copy.level_data, LARGE_MAP_TEST_PLAYER), i32(3))
	testing.expect_value(t, copy.level_data.geometry_revision, snapshot.level.geometry_revision)
}

@(test)
test_advisor_large_map_copy_restores_cells_beyond_65535 :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	tracking.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	{
		context.allocator = mem.tracking_allocator(&tracking)
		large_map_test_copy(t)
	}
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}

@(private = "file")
large_map_test_puzzle :: proc(t: ^testing.T) {
	f := large_map_test_create()
	if !testing.expect(t, f != nil) { return }
	defer large_map_test_destroy(f)
	// Keep every card in its real zone, but leave the hand empty: this puzzle
	// isolates the board's moves rather than inventing a special IA action.
	deck := &f.player.deck
	for card in deck.hand[:deck.hand_count] {
		deck.discard_pile[deck.discard_count] = card
		deck.discard_count += 1
	}
	deck.hand, deck.hand_count = {}, 0
	if !testing.expect(t, game.validate_deck_state(deck)) { return }
	target := f.room.enemies[0].position
	foe_id := f.room.enemies[0].id
	index, inside := game.room_table_index(&f.room, target)
	if !testing.expect(t, inside && index == 86671 && index > 65535) { return }
	before := discrete_fingerprint(&f.room)
	search := new(Search)
	defer free(search)
	if !testing.expect(t, search_init(search)) { return }
	defer search_destroy(search)
	advice := search_whole(search, &f.room, 128)
	testing.expectf(t, advice.valid && advice.kind == .Bump && advice.move.direction == .East && advice.cell == target,
		"the IA must finish the adjacent weak foe beyond index 65535: %v %v at %v", advice.kind, advice.move.direction, advice.cell)
	testing.expect(t, advice.nodes > 0 && search.work <= 128)
	testing.expect_value(t, discrete_fingerprint(&f.room), before)
	testing.expect_value(t, f.player.position, LARGE_MAP_TEST_PLAYER)
	testing.expect_value(t, f.room.enemies[0].health, i32(2))
	if !advice.valid || advice.kind != .Bump || advice.move.direction != .East || advice.cell != target { return }
	// Execute the suggested move through the real game rule, on the original.
	testing.expect_value(t, game.try_move_player(&f.room, advice.move.direction), game.Action_Result.Combat_Ended)
	_, alive := game.enemy_index_by_id(&f.room, foe_id)
	testing.expect(t, !alive)
	testing.expect_value(t, len(f.room.enemies), 0)
	testing.expect_value(t, f.room.phase, game.Room_Phase.Loot)
}

@(test)
test_advisor_large_map_puzzle_strikes_the_weak_foe_beyond_65535 :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	tracking.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	{
		context.allocator = mem.tracking_allocator(&tracking)
		large_map_test_puzzle(t)
	}
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}
