package expedition

import "core:fmt"
import "core:os"
import _ "../engine/teststack"
import "core:strings"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

// A v1-shaped fixture intentionally lacks dimensions and all later World
// fields, and has the old 112² array capacity. The production v1 writer used
// the same canonical JSON envelope/checksum.
@(private)
Legacy_Test_World :: struct { biome: campaign.Biome, seed: u64, reward_site: int, last_health: i32, last_position: grid.Position }
@(private)
Legacy_Test_Snapshot :: struct {
	valid: bool, world: Legacy_Test_World, player: game.Player, phase: game.Room_Phase,
	tiles: [112*112]level.Tile, obstacles: [112*112]game.Obstacle, obstacle_count: int,
	exit_position: grid.Position, ground_pool: [112*112]i32,
	next_enemy_id, next_trap_id, next_object_id: u32,
}

// A scratch file in the system's temp directory: the tests must not depend on
// a macOS-only path such as /private/tmp (they failed on Windows).
scratch_path :: proc(name: string) -> string {
	dir, dir_error := os.temp_directory(context.temp_allocator)
	if dir_error != nil { return name }
	path, path_error := os.join_path({dir, name}, context.temp_allocator)
	return path if path_error == nil else name
}

@(test)
test_legacy_80_96_112_slots_resume_exact_tiles_and_keep_original_size :: proc(t: ^testing.T) {
	for biome in ([3]campaign.Biome{.Cyber, .Egypt, .Space}) {
		path := scratch_path(fmt.tprintf("odin-pp-legacy-world-%d.json", int(biome))); defer os.remove(path)
		old := new(Legacy_Test_Snapshot); defer free(old)
		side := legacy_map_size(biome)
		old.valid = true; old.world = {biome, 42, -1, 32, {x = 9, y = side/2}}
		old.phase = .Loot; old.exit_position = {x = side-8, y = side/2}
		old.next_enemy_id = 1; old.next_trap_id = 1; old.next_object_id = 1
		created: bool
		old.player, created = game.create_player({max_health = 32, attack = 2, defense = 1})
		testing.expect(t, created && game.configure_tactical(&old.player, game.EXPEDITION_TACTICAL_CONFIG))
		old.player.position = {x = 9, y = side/2}
		for &tile in old.tiles[:side*side] { tile.kind = .Floor }
		old.tiles[(side/2)*side+7].kind = .Player_Spawn
		old.tiles[(side/2)*side+side-8].kind = .Exit
		old.tiles[8*side+8].kind = .Wall
		old.obstacles[0] = {{x = 8, y = 8}}; old.obstacle_count = 1
		old.ground_pool[(side-3)*side+side-4] = 3
		c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
		c.unlocked[biome] = true; testing.expect(t, campaign.begin_run(&c, biome, 42))
		campaign.discover(&c, .Storm_Crown); campaign.depot_credit(&c, 31)
		testing.expect(t, campaign.save_slot_from(path, &c, old))
		bytes, read_err := os.read_entire_file(path, context.temp_allocator)
		legacy, _ := strings.replace(string(bytes), "\"version\":2", "\"version\":1", 1, context.temp_allocator)
		testing.expect(t, read_err == nil && os.write_entire_file(path, legacy) == nil)
		loaded: campaign.Campaign; defer campaign.destroy(&loaded)
		snapshot := new(Snapshot); defer free(snapshot)
		testing.expect_value(t, campaign.load_slot_into(path, &loaded, snapshot), campaign.Load_Status.Loaded)
		testing.expect(t, valid_snapshot(snapshot))
		w: World; data: level.Level; player: game.Player; room: game.Room
		if !testing.expect(t, restore(snapshot, &w, &data, &player, &room)) { continue }
		defer level.destroy(&data); defer game.destroy_room(&room)
		testing.expect_value(t, data.tiles.width, side); testing.expect_value(t, size(&w), side)
		testing.expect_value(t, map_size(biome), side*2)
		testing.expect_value(t, data.tiles.cells[8*side+8].kind, level.Tile_Kind.Wall)
		testing.expect_value(t, room.ground.pool[(side-3)*side+side-4], i32(3))
		testing.expect_value(t, player.position, old.player.position)
		testing.expect(t, room.player == &player && room.level_data == &data)
		testing.expect(t, loaded.discovered[game.Card_Id.Storm_Crown]); testing.expect_value(t, campaign.depot_credits(&loaded), i64(31))
		// Migrated v2 checkpoints retain this run's old size. Only a new run
		// uses the larger geography, even after several subsequent saves.
		testing.expect(t, capture(&w, &room, snapshot))
		testing.expect_value(t, snapshot.width, side); testing.expect_value(t, snapshot.height, side)
		testing.expect(t, campaign.save_slot_from(path, &loaded, snapshot))
		reloaded: campaign.Campaign; defer campaign.destroy(&reloaded)
		testing.expect_value(t, campaign.load_slot_into(path, &reloaded, snapshot), campaign.Load_Status.Loaded)
		testing.expect_value(t, snapshot.width, side); testing.expect_value(t, snapshot.world.side_length, side)
		testing.expect(t, valid_snapshot(snapshot))
		snapshot.width += 1; testing.expect(t, !valid_snapshot(snapshot)); snapshot.width -= 1
		snapshot.world.side_length = 225; testing.expect(t, !valid_snapshot(snapshot))
	}
}
