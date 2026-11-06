package expedition

import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Minimal legitimate checkpoint input avoids allocating AI work tables for
// every scale test. The 320-cell integration test below restores a real Room.
@(private)
snapshot_capacity_fixture :: proc(t: ^testing.T, side: int, w: ^World, data: ^level.Level, player: ^game.Player, room: ^game.Room, layers: bool) {
	created: bool
	data^, created = level.create(side, side, {.Floor})
	testing.expect(t, created)
	data.player_spawn = {x = 2, y = 2}; data.has_player_spawn = true
	testing.expect(t, level.set_tile(data, data.player_spawn, {.Player_Spawn}))
	testing.expect(t, level.set_tile(data, {x = side-3, y = side-3}, {.Exit}))
	if layers {
		cell := grid.Position{x = side-4, y = side-5, layer = grid.HIGHEST_LAYER}
		testing.expect(t, level.set_tile(data, cell, {.Floor}))
		testing.expect(t, level.set_height(data, cell, level.LAYER_SPACING))
	}
	player^, created = game.create_player({max_health = 32, attack = 2, defense = 1})
	testing.expect(t, created && game.configure_tactical(player, game.EXPEDITION_TACTICAL_CONFIG))
	player.position = data.player_spawn
	w^ = {biome = .Cyber, side_length = side, seed = 42, reward_site = -1}
	room^ = {player = player, level_data = data, phase = .Combat, exit_position = {x = side-3, y = side-3},
		next_enemy_id = 1, next_trap_id = 1, next_object_id = 1}
	room.ground.pool = make([]i32, game.room_table_cells(data))
}

@(test)
test_snapshot_dynamic_capacity_captures_2x_4x_8x_without_fixed_array_growth :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	context.allocator = mem.tracking_allocator(&tracker)
	snapshot := new(Snapshot)
	for scale in ([3]int{2, 4, 8}) {
		w: World; data: level.Level; player: game.Player; room: game.Room
		side := 224*scale
		snapshot_capacity_fixture(t, side, &w, &data, &player, &room, false)
		last := side*side-1
		data.tiles.cells[last].kind = .Wall; room.ground.pool[last] = i32(scale)
		testing.expect(t, capture(&w, &room, snapshot) && valid_snapshot(snapshot))
		testing.expect(t, len(snapshot.tiles) == side*side && snapshot.ground_pool[last] == i32(scale))
		testing.expect(t, snapshot_storage_bytes(snapshot) <= MAX_SNAPSHOT_BYTES)
		pointer := raw_data(snapshot.tiles)
		testing.expect(t, capture(&w, &room, snapshot) && pointer == raw_data(snapshot.tiles), "Unchanged capacity is reused")
		previous := snapshot.world.seed
		w.side_length = MAX_SNAPSHOT_SIDE+1; w.seed += 1
		testing.expect(t, !capture(&w, &room, snapshot) && snapshot.valid && snapshot.world.seed == previous,
			"Rejected dimensions preserve the previous complete checkpoint")
		delete(room.ground.pool); level.destroy(&data)
	}
	snapshot_destroy(snapshot); free(snapshot)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}

@(test)
test_snapshot_large_layer_index_roundtrips_json_and_real_room :: proc(t: ^testing.T) {
	w: World; data: level.Level; player: game.Player; room: game.Room
	snapshot_capacity_fixture(t, 320, &w, &data, &player, &room, true)
	defer level.destroy(&data); defer delete(room.ground.pool)
	cell := grid.Position{x = 316, y = 315, layer = grid.HIGHEST_LAYER}
	pool_index, found := game.room_table_index(&room, cell)
	testing.expect(t, found && cell.y*320+cell.x > 65535)
	room.ground.pool[pool_index] = 7
	snapshot := new(Snapshot); defer { snapshot_destroy(snapshot); free(snapshot) }
	testing.expect(t, capture(&w, &room, snapshot) && valid_snapshot(snapshot))
	index, slot, kind, height := layer_cell_unpack(snapshot.layer_cells[0])
	testing.expect(t, index == cell.y*320+cell.x && slot == level.layer_slot(cell.layer) && kind == .Floor && height == u8(level.LAYER_SPACING))
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	testing.expect(t, campaign.begin_run(&c, .Cyber, w.seed))
	path := scratch_path("odin-pp-snapshot-large-v2.json"); defer os.remove(path)
	testing.expect(t, campaign.save_slot_from(path, &c, snapshot))
	loaded: campaign.Campaign; defer campaign.destroy(&loaded)
	read_back := new(Snapshot); defer { snapshot_destroy(read_back); free(read_back) }
	testing.expect_value(t, campaign.load_slot_into(path, &loaded, read_back), campaign.Load_Status.Loaded)
	testing.expect(t, valid_snapshot(read_back))
	w2: World; data2: level.Level; player2: game.Player; room2: game.Room
	if !testing.expect(t, restore(read_back, &w2, &data2, &player2, &room2)) { return }
	defer level.destroy(&data2); defer game.destroy_room(&room2)
	tile, present := level.tile_at(&data2, cell)
	testing.expect(t, present && tile.kind == .Floor && w2.side_length == 320)
	testing.expect(t, room2.ground.pool[pool_index] == 7 && level.height_at(&data2, cell) == level.LAYER_SPACING)
	// Reloading replaces owned buffers only after successful validation.
	testing.expect_value(t, campaign.load_slot_into(path, &loaded, read_back), campaign.Load_Status.Loaded)
	testing.expect(t, valid_snapshot(read_back) && room2.ground.pool[pool_index] == 7)
}

@(test)
test_snapshot_v1_padded_arrays_and_16_bit_layers_still_load :: proc(t: ^testing.T) {
	w: World; data: level.Level; player: game.Player; room: game.Room
	snapshot_capacity_fixture(t, 80, &w, &data, &player, &room, true)
	defer level.destroy(&data); defer delete(room.ground.pool)
	snapshot := new(Snapshot); defer { snapshot_destroy(snapshot); free(snapshot) }
	testing.expect(t, capture(&w, &room, snapshot))
	index, slot, kind, height := layer_cell_unpack(snapshot.layer_cells[0])
	snapshot.layer_cells[0] = u64(u32(index)|u32(slot)<<16|u32(kind)<<18|u32(height)<<21)
	snapshot.layers_version = SNAPSHOT_LAYERS_V1; snapshot.width = 0; snapshot.height = 0; snapshot.world.side_length = 0
	resize(&snapshot.tiles, MAX_CELLS); resize(&snapshot.heights, MAX_CELLS); resize(&snapshot.ground_pool, MAX_CELLS)
	resize(&snapshot.obstacles, MAX_CELLS); resize(&snapshot.layer_cells, 4096); resize(&snapshot.layer_pools, 1024)
	testing.expect(t, valid_snapshot(snapshot))
	append(&snapshot.tiles, level.Tile{.Floor})
	testing.expect(t, !valid_snapshot(snapshot), "Legacy padding is bounded by the actual v1 capacities")
	resize(&snapshot.tiles, MAX_CELLS)
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	path := scratch_path("odin-pp-snapshot-compatible-v1.json"); defer os.remove(path)
	testing.expect(t, campaign.save_slot_from(path, &c, snapshot))
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	old, _ := strings.replace(string(bytes), "\"version\":2", "\"version\":1", 1, context.temp_allocator)
	testing.expect(t, err == nil && os.write_entire_file(path, old) == nil)
	loaded: campaign.Campaign; defer campaign.destroy(&loaded)
	read_back := new(Snapshot); defer { snapshot_destroy(read_back); free(read_back) }
	testing.expect_value(t, campaign.load_slot_into(path, &loaded, read_back), campaign.Load_Status.Loaded)
	testing.expect(t, valid_snapshot(read_back))
	w2: World; data2: level.Level; player2: game.Player; room2: game.Room
	if !testing.expect(t, restore(read_back, &w2, &data2, &player2, &room2)) { return }
	defer level.destroy(&data2); defer game.destroy_room(&room2)
	tile, found := level.tile_at(&data2, {x = index%80, y = index/80, layer = i8(slot+grid.LOWEST_LAYER)})
	testing.expect(t, found && tile.kind == .Floor)
}

@(test)
test_snapshot_clone_owns_buffers_and_rejects_invalid_v2_indices :: proc(t: ^testing.T) {
	w: World; data: level.Level; player: game.Player; room: game.Room
	snapshot_capacity_fixture(t, 320, &w, &data, &player, &room, true)
	defer level.destroy(&data); defer delete(room.ground.pool)
	source, clone := new(Snapshot), new(Snapshot)
	defer { snapshot_destroy(source); free(source); snapshot_destroy(clone); free(clone) }
	testing.expect(t, capture(&w, &room, source) && snapshot_clone(clone, source))
	testing.expect(t, raw_data(source.tiles) != raw_data(clone.tiles) && raw_data(source.layer_cells) != raw_data(clone.layer_cells))
	snapshot_destroy(source)
	testing.expect(t, valid_snapshot(clone))
	packed := clone.layer_cells[0]
	clone.layer_cells[0] = layer_cell_pack(320*320, 0, .Floor, 0)
	testing.expect(t, !valid_snapshot(clone))
	clone.layer_cells[0] = packed | u64(1)<<63
	testing.expect(t, !valid_snapshot(clone))
	clone.layer_cells[0] = packed
	clone.layer_pool_count = 1
	testing.expect(t, !valid_snapshot(clone), "A prefix cannot exceed its owned allocation")
	clone.layer_pool_count = 0
	index, _, _, _ := layer_cell_unpack(packed)
	append(&clone.layer_pools, [2]i32{i32(game.room_layer_slot(grid.HIGHEST_LAYER)*320*320+index+1), 3})
	clone.layer_pool_count = 1
	testing.expect(t, !valid_snapshot(clone), "A pool cannot refer to a nonmaterialized layer cell")
	clear(&clone.layer_pools); clone.layer_pool_count = 0
	spawn := clone.player.position.y*320+clone.player.position.x
	clone.tiles[spawn].kind = .Floor
	testing.expect(t, !valid_snapshot(clone), "A saved room needs a player spawn before allocation")
	clone.tiles[spawn].kind = .Player_Spawn
	exit := clone.exit_position.y*320+clone.exit_position.x
	clone.tiles[exit].kind = .Floor
	testing.expect(t, !valid_snapshot(clone), "A saved room needs its unique exit before allocation")
	clone.tiles[exit].kind = .Exit
	testing.expect(t, valid_snapshot(clone))
	clone.width = MAX_SNAPSHOT_SIDE+1
	testing.expect(t, !valid_snapshot(clone))
}

@(test)
test_snapshot_failed_restore_preserves_existing_owners_and_releases_staging :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	context.allocator = mem.tracking_allocator(&tracker)
	w: World; data: level.Level; player: game.Player; room: game.Room
	snapshot_capacity_fixture(t, 80, &w, &data, &player, &room, true)
	snapshot := new(Snapshot)
	testing.expect(t, capture(&w, &room, snapshot))
	index, slot, kind, _ := layer_cell_unpack(snapshot.layer_cells[0])
	// Structurally valid, but its two walkable floors violate physical clearance.
	// The restore must discover this after allocation without touching old owners.
	snapshot.layer_cells[0] = layer_cell_pack(index, slot, kind, 0)
	testing.expect(t, valid_snapshot(snapshot))
	w.seed = 99; player.gold = 73; room.ground.pool[0] = 19
	tiles, pools := raw_data(data.tiles.cells), raw_data(room.ground.pool)
	before := tracker.current_memory_allocated
	testing.expect(t, !restore(snapshot, &w, &data, &player, &room))
	testing.expect(t, w.seed == 99 && player.gold == 73 && room.ground.pool[0] == 19)
	testing.expect(t, raw_data(data.tiles.cells) == tiles && raw_data(room.ground.pool) == pools)
	testing.expect(t, room.player == &player && room.level_data == &data)
	testing.expect_value(t, tracker.current_memory_allocated, before)
	snapshot_destroy(snapshot); free(snapshot); delete(room.ground.pool); level.destroy(&data)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}
