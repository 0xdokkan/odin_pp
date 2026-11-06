package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:time"
import campaign "../../../src/campaign"
import expedition "../../../src/expedition"
import game "../../../src/game"
import grid "../../../src/engine/grid"
import level "../../../src/level"

@(private)
Record :: struct {
	side, cells, high_index, layer_pool_index, snapshot_bytes, file_bytes: int,
	captured, valid, saved, loaded, restored, equal: bool,
	capture_ms, save_ms, load_ms, restore_ms: f64,
	error: string,
}

// A controlled real level/room and a real campaign JSON file. This isolates
// persistence capacity; it does not measure world generation or rendering.
main :: proc() {
	if len(os.args) != 3 { fmt.eprintln("Uso: snapshot-capacity LATO FILE-NUOVO.json"); os.exit(2) }
	side, parsed := strconv.parse_int(os.args[1])
	if !parsed || side < 16 || side > expedition.MAX_SNAPSHOT_SIDE || os.exists(os.args[2]) {
		fmt.eprintln("Lato non supportato o file di destinazione gia esistente"); os.exit(2)
	}
	record := measure(side, os.args[2])
	encoded, err := json.marshal(record, allocator = context.temp_allocator)
	if err != nil { os.exit(2) }
	fmt.println(string(encoded))
	if !record.equal { os.exit(2) }
}

@(private)
measure :: proc(side: int, path: string) -> (r: Record) {
	r.side, r.cells = side, side*side
	r.error = "create_level"
	data, ok := level.create(side, side, {kind = .Floor})
	if !ok { return }
	defer level.destroy(&data)
	spawn := grid.Position{x = side-8, y = side-8}
	exit := grid.Position{x = side-2, y = side-2}
	high := grid.Position{x = side-4, y = side-4}
	upper := grid.Position{x = high.x, y = high.y, layer = 1}
	data.player_spawn, data.has_player_spawn = spawn, true
	if !level.set_tile(&data, spawn, {kind = .Player_Spawn}) || !level.set_tile(&data, exit, {kind = .Exit}) ||
		!level.set_tile(&data, upper, {kind = .Floor}) || !level.set_height(&data, upper, level.LAYER_SPACING+2) || !level.set_height(&data, high, 2) { return }
	player, made := game.create_player({max_health = 100, attack = 5, defense = 0})
	if !made || !game.configure_tactical(&player, game.EXPEDITION_TACTICAL_CONFIG) { return }
	r.error = "create_room"
	room, room_ok := game.create_room(&data, &player, {room_seed = 42})
	if !room_ok { return }
	defer game.destroy_room(&room)
	if !game.configure_expedition_combat(&room) { return }
	w := new(expedition.World)
	defer free(w)
	w^ = {biome = .Cyber, side_length = side, seed = 42, reward_site = -1, last_position = spawn, last_health = 100}
	r.high_index = high.y*side+high.x
	pool_index, pool_ok := game.room_table_index(&room, upper)
	if !pool_ok { r.error = "layer_pool_index"; return }
	r.layer_pool_index = pool_index
	// The fixture writes distinguishable values, including a cell that would
	// collide with the old 16-bit encoding, without measuring flood-fill work.
	room.ground.pool[r.high_index] = 7
	room.ground.pool[pool_index] = 11
	snapshot := new(expedition.Snapshot)
	defer { expedition.snapshot_destroy(snapshot); free(snapshot) }
	stamp := time.tick_now()
	r.captured = expedition.capture(w, &room, snapshot)
	r.capture_ms = time.duration_milliseconds(time.tick_since(stamp))
	r.valid = r.captured && expedition.valid_snapshot(snapshot)
	r.snapshot_bytes = expedition.snapshot_storage_bytes(snapshot)
	if !r.valid { r.error = "capture_or_validation"; return }
	c := new(campaign.Campaign)
	defer { campaign.destroy(c); free(c) }
	campaign.initialize(c)
	if !campaign.begin_run(c, .Cyber, 42) { r.error = "campaign"; return }
	stamp = time.tick_now()
	r.saved = campaign.save_slot_from(path, c, snapshot)
	r.save_ms = time.duration_milliseconds(time.tick_since(stamp))
	if !r.saved { r.error = "save"; return }
	info, stat_err := os.stat(path, context.temp_allocator)
	if stat_err == nil { r.file_bytes = int(info.size) }
	loaded := new(expedition.Snapshot)
	defer { expedition.snapshot_destroy(loaded); free(loaded) }
	loaded_campaign := new(campaign.Campaign)
	defer { campaign.destroy(loaded_campaign); free(loaded_campaign) }
	stamp = time.tick_now()
	status := campaign.load_slot_into(path, loaded_campaign, loaded)
	r.load_ms = time.duration_milliseconds(time.tick_since(stamp))
	r.loaded = status == .Loaded && expedition.valid_snapshot(loaded)
	if !r.loaded { r.error = "load"; return }
	other_world := new(expedition.World)
	defer free(other_world)
	other_data: level.Level
	other_player: game.Player
	other_room: game.Room
	stamp = time.tick_now()
	r.restored = expedition.restore(loaded, other_world, &other_data, &other_player, &other_room)
	r.restore_ms = time.duration_milliseconds(time.tick_since(stamp))
	if !r.restored { r.error = "restore"; return }
	defer { game.destroy_room(&other_room); level.destroy(&other_data) }
	r.equal = slice.equal(data.tiles.cells[:], other_data.tiles.cells[:]) && slice.equal(data.heights[:], other_data.heights[:]) &&
		slice.equal(room.ground.pool, other_room.ground.pool) && player.position == other_player.position &&
		game.ground_pool_at(&other_room, high) == 7 && game.ground_pool_at(&other_room, upper) == 11 &&
		level.height_at(&other_data, high) == 2
	for plane, index in data.planes {
		r.equal = r.equal && slice.equal(plane.tiles[:], other_data.planes[index].tiles[:]) && slice.equal(plane.heights[:], other_data.planes[index].heights[:])
	}
	r.error = "" if r.equal else "roundtrip_mismatch"
	return
}
