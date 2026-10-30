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

// A save from before the caves were a layer of the map (Fase 5 of docs/piano-profondita.md) is refused without harm: the
// campaign's own progress loads, the expedition's checkpoint does not (the user deletes the old saves; none is converted).
@(test)
test_a_save_from_before_the_layers_is_refused_without_harm :: proc(t: ^testing.T) {
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
		testing.expect(t, loaded.discovered[game.Card_Id.Storm_Crown]); testing.expect_value(t, campaign.depot_credits(&loaded), i64(31))
		testing.expect(t, !valid_snapshot(snapshot))
		w: World; data: level.Level; player: game.Player; room: game.Room
		testing.expect(t, !restore(snapshot, &w, &data, &player, &room))
		testing.expect(t, len(data.tiles.cells) == 0, "nothing is made of it")
	}
}
