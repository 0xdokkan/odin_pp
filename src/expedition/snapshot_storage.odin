package expedition

import game "../game"
import level "../level"

@(private)
snapshot_has_layer_cell :: proc(s: ^Snapshot, index, slot, cells: int) -> bool {
	wanted := slot*cells+index
	lo, hi := 0, s.layer_cell_count
	for lo < hi {
		mid := lo+(hi-lo)/2
		i, layer, _, _ := layer_cell_unpack(s.layer_cells[mid], s.layers_version)
		key := layer*cells+i
		if key < wanted { lo = mid+1 } else { hi = mid }
	}
	if lo == s.layer_cell_count { return false }
	i, layer, _, _ := layer_cell_unpack(s.layer_cells[lo], s.layers_version)
	return layer*cells+i == wanted
}

@(private)
Snapshot_Restore_State :: struct { world: World, data: level.Level, player: game.Player, room: game.Room }

// Build against temporary owners. A rejected layer map, failed allocation or
// invalid room cannot alter the caller's current world/player/level/room.
restore :: proc(s: ^Snapshot, w: ^World, data: ^level.Level, player: ^game.Player, room: ^game.Room) -> bool {
	if s == nil || w == nil || data == nil || player == nil || room == nil || !valid_snapshot(s) { return false }
	state, allocation_err := new(Snapshot_Restore_State)
	if allocation_err != nil || state == nil { return false }
	defer { game.destroy_room(&state.room); level.destroy(&state.data); free(state) }
	if !snapshot_restore_into_empty(s, &state.world, &state.data, &state.player, &state.room) { return false }
	game.destroy_room(room); level.destroy(data)
	w^ = state.world; player^ = state.player; data^ = state.data; room^ = state.room
	room.player = player; room.level_data = data
	state.data = {}; state.room = {}
	return true
}

@(private)
snapshot_capacity_allowed :: proc(cells, obstacles, layers, pools: int) -> bool {
	if cells <= 0 || cells > MAX_SNAPSHOT_CELLS || obstacles < 0 || obstacles > MAX_SNAPSHOT_CELLS ||
		layers < 0 || layers > cells*(level.LAYER_COUNT-1) || pools < 0 || pools > cells*(level.LAYER_COUNT-1) { return false }
	bytes := size_of(Snapshot)+cells*(size_of(level.Tile)+size_of(u8)+size_of(i32))+
		obstacles*size_of(game.Obstacle)+layers*size_of(u64)+pools*size_of([2]i32)
	return bytes <= MAX_SNAPSHOT_BYTES
}

snapshot_destroy :: proc(snapshot: ^Snapshot) {
	if snapshot == nil { return }
	delete(snapshot.tiles); delete(snapshot.heights); delete(snapshot.obstacles)
	delete(snapshot.ground_pool); delete(snapshot.layer_cells); delete(snapshot.layer_pools)
	snapshot^ = {}
}

// Struct plus actual reserved storage; does not include allocator bookkeeping.
snapshot_storage_bytes :: proc(snapshot: ^Snapshot) -> int {
	if snapshot == nil { return 0 }
	return size_of(Snapshot)+cap(snapshot.tiles)*size_of(level.Tile)+cap(snapshot.heights)*size_of(u8)+
		cap(snapshot.obstacles)*size_of(game.Obstacle)+cap(snapshot.ground_pool)*size_of(i32)+
		cap(snapshot.layer_cells)*size_of(u64)+cap(snapshot.layer_pools)*size_of([2]i32)
}

// A detached copy, reusing the destination's owned buffers. Reservation failure
// preserves all prior values; unlike assignment, the result never aliases src.
snapshot_clone :: proc(dst, src: ^Snapshot) -> bool {
	if dst == nil || src == nil { return false }
	if dst == src { return true }
	if src.valid && !valid_snapshot(src) { return false }
	if reserve(&dst.tiles, len(src.tiles)) != nil || reserve(&dst.heights, len(src.heights)) != nil ||
		reserve(&dst.obstacles, len(src.obstacles)) != nil || reserve(&dst.ground_pool, len(src.ground_pool)) != nil ||
		reserve(&dst.layer_cells, len(src.layer_cells)) != nil || reserve(&dst.layer_pools, len(src.layer_pools)) != nil { return false }
	tiles, heights, obstacles := dst.tiles, dst.heights, dst.obstacles
	ground_pool, layers, pools := dst.ground_pool, dst.layer_cells, dst.layer_pools
	dst^ = src^
	dst.tiles, dst.heights, dst.obstacles = tiles, heights, obstacles
	dst.ground_pool, dst.layer_cells, dst.layer_pools = ground_pool, layers, pools
	resize(&dst.tiles, len(src.tiles)); resize(&dst.heights, len(src.heights)); resize(&dst.obstacles, len(src.obstacles))
	resize(&dst.ground_pool, len(src.ground_pool)); resize(&dst.layer_cells, len(src.layer_cells)); resize(&dst.layer_pools, len(src.layer_pools))
	copy(dst.tiles[:], src.tiles[:]); copy(dst.heights[:], src.heights[:]); copy(dst.obstacles[:], src.obstacles[:])
	copy(dst.ground_pool[:], src.ground_pool[:]); copy(dst.layer_cells[:], src.layer_cells[:]); copy(dst.layer_pools[:], src.layer_pools[:])
	return true
}
