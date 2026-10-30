package campaign

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"
import game "../game"

// The Prova meccaniche's own cards never reach a memory: not at the start, not
// as a discovery, not in a run's pool.
// A scratch file in the system's temp directory: the tests must not depend on
// a macOS-only path such as /private/tmp (they failed on Windows).
scratch_path :: proc(name: string) -> string {
	dir, dir_error := os.temp_directory(context.temp_allocator)
	if dir_error != nil { return name }
	path, path_error := os.join_path({dir, name}, context.temp_allocator)
	return path if path_error == nil else name
}

@(test)
test_lab_only_cards_never_enter_the_campaign :: proc(t: ^testing.T) {
	c: Campaign
	initialize(&c)
	defer destroy(&c)
	lab := 0
	for id in game.Card_Id.Strike..<game.Card_Id.Count {
		if !game.card_is_lab_only(id) { continue }
		lab += 1
		testing.expect(t, !c.discovered[id] && !discover(&c, id) && !c.discovered[id] && !card_in_pool(&c, id))
	}
	testing.expect_value(t, lab, 9)
	// Every card of the collection still comes to light one at a time; the lab's, the retired ones and those only an
	// upgrade makes never do (docs/registro-carte.md).
	for id in game.Card_Id.Strike..<game.Card_Id.Count {
		if !game.card_in_collection(id) { testing.expect(t, !c.discovered[id] && !discover(&c, id)) } else { discover(&c, id) }
	}
	testing.expect(t, begin_run(&c, .Cyber, 7))
	for id in game.Card_Id.Strike..<game.Card_Id.Count {
		testing.expect_value(t, card_in_pool(&c, id), game.card_in_collection(id))
	}
	for id in ([?]game.Card_Id{.Thorn_Coat, .Afterimage, .Titan_Grip, .Cross_Slash, .Purifying_Guard, .Twin_Venom}) {
		testing.expect(t, !card_in_pool(&c, id))
	}
}

@(test)
test_polyomino_rotations_and_collision :: proc(t: ^testing.T) {
	grid := make_grid(8, 5)
	relic := make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil))
	shape := item_shape(relic)
	testing.expect_value(t, shape.count, 5)
	testing.expect(t, grid_place(&grid, relic, 0, 0))
	// The top-left corner of a cross is empty, not its bounding rectangle.
	testing.expect(t, grid_place(&grid, make_item(.Healing), 0, 0))
	testing.expect(t, !grid_place(&grid, make_item(.Energy), 1, 0))
	long := make_item(.Weapon, 1, i32(game.Weapon_Id.Storm_Pike))
	long.rotation = 1
	testing.expect_value(t, item_shape(long).width, 1)
	testing.expect_value(t, item_shape(long).height, 3)
	testing.expect(t, grid_place(&grid, long, 7, 2))
	testing.expect(t, !grid_move(&grid, 2, 7, 2, 0))
	testing.expect(t, grid_valid(&grid))
	for id in game.Relic_Id.Iron_Knuckle..<game.Relic_Id.Count {
		for rotation in 0..<4 {
			item := make_item(.Relic, 1, i32(id)); item.rotation = u8(rotation)
			rotated := item_shape(item)
			testing.expect_value(t, rotated.count, int(id))
			for cell, i in rotated.cells[:rotated.count] {
				testing.expect(t, cell.x >= 0 && cell.y >= 0)
				for other in rotated.cells[:i] { testing.expect(t, cell != other) }
			}
		}
	}
}

@(test)
test_stacking_and_failed_pickup_are_transactional :: proc(t: ^testing.T) {
	grid := make_grid(1, 1)
	testing.expect(t, grid_add(&grid, make_item(.Healing, 4)))
	testing.expect(t, !grid_add(&grid, make_item(.Healing, 2)))
	testing.expect_value(t, grid.entries[0].item.quantity, i32(4))
	testing.expect(t, grid_add(&grid, make_item(.Healing)))
	testing.expect_value(t, grid.entries[0].item.quantity, i32(5))
	testing.expect(t, !grid_add(&grid, make_item(.Credits, 100)))
	bag := Backpack{grid = grid}
	testing.expect_value(t, pickup(&bag, make_item(.Energy)), Pickup_Result.Rejected)
	for _ in 0..<3 { testing.expect_value(t, pickup(&bag, make_item(.Energy), true), Pickup_Result.Pending) }
	testing.expect_value(t, pickup(&bag, make_item(.Energy), true), Pickup_Result.Rejected)
	_, count := drop_pending(&bag, false)
	testing.expect_value(t, count, 0); testing.expect_value(t, bag.pending_count, 3)
	dropped, accepted := drop_pending(&bag, true)
	testing.expect_value(t, accepted, 3); testing.expect_value(t, dropped[0].kind, Item_Kind.Energy)
	testing.expect_value(t, bag.pending_count, 0)
}

@(test)
test_active_relics_are_exclusive_and_cannot_swap_in_combat :: proc(t: ^testing.T) {
	bag := make_backpack()
	testing.expect(t, grid_add(&bag.grid, make_item(.Relic, 1, i32(game.Relic_Id.Iron_Knuckle))))
	testing.expect(t, grid_add(&bag.grid, make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil))))
	testing.expect(t, !equip(&bag, 0, 0, true))
	testing.expect(t, equip(&bag, 0, 0, false))
	player: game.Player
	apply_equipment(&bag, &player)
	testing.expect(t, game.player_has_relic(&player, .Iron_Knuckle))
	testing.expect(t, !game.player_has_relic(&player, .Guard_Sigil))
	testing.expect(t, !unequip(&bag, 0, false, true))
	testing.expect(t, unequip(&bag, 0, false, false))
	apply_equipment(&bag, &player)
	testing.expect_value(t, player.relics.count, 0)
}

@(test)
test_consume_reduces_stack_and_charges_world_action :: proc(t: ^testing.T) {
	bag := make_backpack()
	grid_add(&bag.grid, make_item(.Healing, 2))
	effect, used := consume(&bag, 0, true)
	testing.expect(t, used); testing.expect_value(t, effect.heal, i32(12))
	testing.expect_value(t, effect.action_seconds, f32(1))
	testing.expect_value(t, bag.grid.entries[0].item.quantity, i32(1))
	consume(&bag, 0, false)
	testing.expect_value(t, bag.grid.count, 0)
}

@(test)
test_fished_food_potency_survives_storage_and_validates_its_range :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	for potency in i32(1)..=i32(4) {
		food := make_item(.Healing, 1, potency)
		testing.expect(t, item_valid(food) && depot_add(&c, food))
	}
	testing.expect(t, !item_valid(make_item(.Healing, 1, -1)))
	testing.expect(t, !item_valid(make_item(.Healing, 1, 5)))
	for potency in i32(1)..=i32(4) {
		testing.expect(t, depot_take(&c, 0, 0))
		effect, used := consume(&c.backpack, 0, true)
		testing.expect(t, used)
		testing.expect_value(t, effect.heal, potency)
		testing.expect_value(t, effect.action_seconds, f32(1))
	}
}

@(test)
test_death_loses_carried_stakes_but_keeps_memory :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_add(&c, make_item(.Energy))
	depot_add(&c, make_item(.Credits, 42))
	testing.expect(t, depot_take(&c, 0, 0))
	testing.expect(t, begin_run(&c, .Cyber, 100))
	grid_add(&c.backpack.grid, make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil)))
	equip(&c.backpack, 1, 0, false)
	discover(&c, .Storm_Crown); discover_secret(&c, .Cyber, 4)
	add_xp(&c, 50)
	testing.expect(t, finish_run(&c, false))
	testing.expect_value(t, c.backpack.grid.count, 0)
	testing.expect_value(t, c.backpack.relics[0].kind, Item_Kind.None)
	testing.expect_value(t, c.run.level, i32(0)); testing.expect_value(t, c.deaths, u32(1))
	testing.expect(t, c.discovered[game.Card_Id.Storm_Crown]); testing.expect(t, secret_known(&c, .Cyber, 4))
	testing.expect_value(t, depot_credits(&c), i64(42))
	testing.expect(t, campaign_valid(&c))
}

@(test)
test_zero_star_extraction_stores_every_inventory_location :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	begin_run(&c, .Cyber, 22)
	grid_add(&c.backpack.grid, make_item(.Memory, 1, 2))
	c.backpack.relics[0] = make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil))
	c.backpack.weapon = make_item(.Weapon, 1, i32(game.Weapon_Id.Storm_Pike))
	c.backpack.pending[0] = make_item(.Backpack, 1, 2); c.backpack.pending_count = 1
	testing.expect(t, finish_run(&c, true, 0))
	testing.expect_value(t, c.depot[0].count, 4)
	testing.expect_value(t, c.memory_fragments, u64(4))
	testing.expect_value(t, c.backpack.grid.width, 10)
	testing.expect(t, c.won[Biome.Cyber] && c.unlocked[Biome.West] && c.unlocked[Biome.City] && c.unlocked[Biome.Jungle])
	testing.expect(t, !c.unlocked[Biome.Space]); testing.expect(t, campaign_valid(&c))
}

@(test)
test_routes_streak_and_both_endings :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	order := [?]Biome{.Cyber, .West, .Egypt, .Inferno, .City, .Snow, .Sky, .Jungle, .Vietnam, .Gothic, .Space}
	for biome, i in order {
		testing.expect(t, begin_run(&c, biome, u64(i+1)))
		testing.expect(t, finish_run(&c, true))
		if i < 9 { testing.expect(t, !c.unlocked[Biome.Space]) }
		if i < 10 { testing.expect(t, !c.normal_ending && !c.unlocked[Biome.Secret]) }
	}
	testing.expect(t, c.normal_ending && c.unlocked[Biome.Secret])
	testing.expect_value(t, c.streak, u32(11))
	testing.expect(t, begin_run(&c, .Secret, 12)); testing.expect(t, finish_run(&c, true))
	testing.expect(t, c.true_ending)
	begin_run(&c, .Cyber, 13); finish_run(&c, false)
	testing.expect_value(t, c.streak, u32(0)); testing.expect(t, c.true_ending && c.normal_ending)
	for visited in c.streak_biomes { testing.expect(t, !visited) }
	// A completed unlock remains permanent even after a later death.
	testing.expect(t, c.unlocked[Biome.Secret])
}

@(test)
test_repeating_same_biome_does_not_unlock_secret :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	for _ in 0..<12 { begin_run(&c, .Cyber, 1); finish_run(&c, true) }
	testing.expect_value(t, c.streak, u32(12)); testing.expect(t, !c.unlocked[Biome.Secret])
}

// TEMPORARY test mode: every biome is playable, the real progress stays as it was.
@(test)
test_test_mode_opens_every_biome_without_touching_progress :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	testing.expect(t, begin_run(&c, .Cyber, 1)); testing.expect(t, finish_run(&c, true))
	real_unlocked := c.unlocked
	testing.expect(t, !biome_open(&c, .Egypt) && !begin_run(&c, .Egypt, 2))
	testing.expect(t, set_test_all_biomes(&c, true))
	for b in Biome.Cyber..<Biome.Count { testing.expect(t, biome_open(&c, b)) }
	testing.expect_value(t, c.unlocked, real_unlocked)
	// A win in a test biome brings the backpack and the star bonus home, nothing else.
	testing.expect(t, begin_run(&c, .Egypt, 2))
	testing.expect(t, c.run.test && !c.visited[Biome.Egypt])
	testing.expect(t, !set_test_all_biomes(&c, false) && c.test_all_biomes)
	testing.expect(t, campaign_valid(&c))
	grid_add(&c.backpack.grid, make_item(.Memory, 1, 4))
	testing.expect(t, finish_run(&c, true, 1))
	testing.expect_value(t, c.memory_fragments, u64(1) << 4)
	testing.expect_value(t, depot_credits(&c), i64(20))
	testing.expect(t, !c.won[Biome.Egypt] && !c.streak_biomes[Biome.Egypt] && !c.unlocked[Biome.Inferno])
	testing.expect_value(t, c.streak, u32(1)); testing.expect_value(t, c.total_wins, u32(1))
	// A death in a test biome loses the backpack but neither the streak nor a death.
	testing.expect(t, begin_run(&c, .Secret, 3))
	grid_add(&c.backpack.grid, make_item(.Healing, 2))
	testing.expect(t, finish_run(&c, false))
	testing.expect_value(t, c.backpack.grid.count, 0)
	testing.expect_value(t, c.streak, u32(1)); testing.expect_value(t, c.deaths, u32(0))
	testing.expect(t, !c.true_ending && !c.normal_ending)
	// A biome the slot really opened still counts while the test is on.
	testing.expect(t, begin_run(&c, .West, 4)); testing.expect(t, !c.run.test)
	testing.expect(t, finish_run(&c, true))
	testing.expect(t, c.won[Biome.West] && c.unlocked[Biome.Egypt]); testing.expect_value(t, c.streak, u32(2))
	testing.expect(t, set_test_all_biomes(&c, false))
	testing.expect(t, !biome_open(&c, .Inferno) && !begin_run(&c, .Inferno, 5))
	testing.expect(t, campaign_valid(&c))
}

@(test)
test_test_expedition_survives_a_save_and_needs_the_test_mode :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-campaign-test-mode.json")
	defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	testing.expect(t, set_test_all_biomes(&c, true)); testing.expect(t, begin_run(&c, .Space, 9))
	testing.expect(t, save_slot(path, &c, Test_Snapshot{label = "prova"}))
	loaded, world, status := load_slot(path, Test_Snapshot)
	defer destroy(&loaded); defer delete(world.label)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect(t, loaded.test_all_biomes && loaded.run.test && loaded.run.biome == .Space)
	// The run's test mark must agree with the slot's real routes.
	loaded.test_all_biomes = false; testing.expect(t, !campaign_valid(&loaded))
	loaded.test_all_biomes = true; loaded.unlocked[Biome.Space] = true; testing.expect(t, !campaign_valid(&loaded))
	loaded.run.test = false; testing.expect(t, campaign_valid(&loaded))
}

@(test)
test_discovery_pool_next_run_and_xp_upgrades :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	begin_run(&c, .Cyber, 1)
	testing.expect(t, !card_in_pool(&c, .Storm_Crown))
	testing.expect(t, discover(&c, .Storm_Crown))
	testing.expect(t, !card_in_pool(&c, .Storm_Crown))
	testing.expect_value(t, add_xp(&c, 15), i32(2))
	testing.expect_value(t, c.run.level, i32(3)); testing.expect_value(t, c.run.xp, i32(1))
	testing.expect_value(t, c.run.points, i32(2))
	deck: game.Deck_State; game.initialize_starter_deck(&deck)
	testing.expect(t, !upgrade_card(&c, &deck, deck.owned[0].id, true))
	testing.expect_value(t, c.run.points, i32(2))
	testing.expect(t, upgrade_card(&c, &deck, deck.owned[0].id, false))
	testing.expect_value(t, c.run.points, i32(1))
	finish_run(&c, false); begin_run(&c, .Cyber, 2)
	testing.expect(t, card_in_pool(&c, .Storm_Crown))
	testing.expect_value(t, c.run.level, i32(1)); testing.expect_value(t, c.run.points, i32(0))
}

@(test)
test_depot_expands_and_currency_never_goes_negative :: proc(t: ^testing.T) {
	c: Campaign; initialize(&c); defer destroy(&c)
	for _ in 0..<100 { testing.expect(t, depot_add(&c, make_item(.Memory, 1, 0))) }
	testing.expect_value(t, len(c.depot), 2)
	testing.expect(t, depot_credit(&c, 250))
	testing.expect_value(t, depot_credits(&c), i64(250))
	testing.expect(t, !depot_pay(&c, 251))
	testing.expect_value(t, depot_credits(&c), i64(250))
	testing.expect(t, depot_pay(&c, 150)); testing.expect_value(t, depot_credits(&c), i64(100))
	testing.expect(t, campaign_valid(&c))
}

Test_Snapshot :: struct { position: [2]int, random_state: u64, enemy_hp: [3]i32, label: string }

@(test)
test_version_one_checksum_survives_new_fields_and_expanded_arrays :: proc(t: ^testing.T) {
	Legacy :: struct { cells: [2]i32, seed: u64, label: string }
	Expanded :: struct { width: int, cells: [4]i32, seed: u64, label: string }
	path := scratch_path("odin-pp-version-one-migration.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_credit(&c, 71)
	old := Saved_State(Legacy){campaign = c, snapshot = {{4, 8}, 0xFEDCBA9876543210, "braces { } and \\\"quotes\\\""}}
	payload, payload_err := json.marshal(old, allocator = context.temp_allocator)
	testing.expect(t, payload_err == nil)
	envelope := Slot_Envelope(Legacy){version = 1, checksum = checksum(payload), state = old}
	bytes, encoded := json.marshal(envelope, allocator = context.temp_allocator)
	testing.expect(t, encoded == nil && os.write_entire_file(path, bytes) == nil)
	loaded, snapshot, status := load_slot(path, Expanded)
	defer destroy(&loaded); defer delete(snapshot.label)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, snapshot.cells, [4]i32{4, 8, 0, 0})
	testing.expect_value(t, snapshot.width, 0)
	testing.expect_value(t, snapshot.seed, old.snapshot.seed)
	testing.expect_value(t, snapshot.label, old.snapshot.label)
	testing.expect_value(t, depot_credits(&loaded), i64(71))
}

@(test)
test_save_roundtrip_keeps_campaign_and_live_snapshot :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-campaign-roundtrip.json")
	defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_credit(&c, 184); begin_run(&c, .Cyber, 0x1234); add_xp(&c, 20)
	snapshot := Test_Snapshot{{15, 42}, 0xFEDCBA9876543210, {1, 4, 9}, "run in corso"}
	testing.expect(t, save_slot(path, &c, snapshot))
	loaded, world, status := load_slot(path, Test_Snapshot)
	defer destroy(&loaded); defer delete(world.label)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, world.position, snapshot.position)
	testing.expect_value(t, world.random_state, snapshot.random_state)
	testing.expect_value(t, world.enemy_hp, snapshot.enemy_hp)
	testing.expect_value(t, world.label, snapshot.label)
	testing.expect_value(t, depot_credits(&loaded), i64(184))
	testing.expect_value(t, loaded.run.xp, c.run.xp)
	testing.expect(t, loaded.run.active && loaded.saved_unix_seconds > 0)
	testing.expect(t, !os.exists(fmt.tprintf("%s.tmp", path)))
	testing.expect(t, !delete_slot(path, true, false)); testing.expect(t, os.exists(path))
	testing.expect(t, delete_slot(path, true, true))
}

@(test)
test_corrupt_save_is_preserved_and_rejection_leaks_nothing :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-campaign-corrupt.json")
	defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	testing.expect(t, save_slot(path, &c, Test_Snapshot{label = "owned data"}))
	bytes, _ := os.read_entire_file(path, context.temp_allocator)
	envelope: Slot_Envelope(Test_Snapshot)
	testing.expect(t, json.unmarshal(bytes, &envelope, allocator = context.temp_allocator) == nil)
	envelope.state.campaign.total_wins = 999
	corrupt, _ := json.marshal(envelope, allocator = context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, corrupt) == nil)
	tracker: mem.Tracking_Allocator; mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	_, _, status := load_slot(path, Test_Snapshot, allocator = mem.tracking_allocator(&tracker))
	testing.expect_value(t, status, Load_Status.Checksum_Mismatch)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
	testing.expect(t, os.exists(path))
	testing.expect(t, os.write_entire_file(path, "{\"version\":1,\"state\":{") == nil)
	_, _, malformed := load_slot(path, Test_Snapshot, allocator = mem.tracking_allocator(&tracker))
	testing.expect_value(t, malformed, Load_Status.Malformed)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}

@(test)
test_three_slots_keep_independent_stakes_and_discoveries :: proc(t: ^testing.T) {
	paths := [3]string{scratch_path("odin-pp-independent-slot1.json"), scratch_path("odin-pp-independent-slot2.json"), scratch_path("odin-pp-independent-slot3.json")}
	for path, index in paths {
		c: Campaign; initialize(&c)
		depot_credit(&c, i64((index+1)*10))
		if index == 1 { discover(&c, .Storm_Crown) }
		if index == 2 { begin_run(&c, .Cyber, 300) }
		testing.expect(t, save_slot(path, &c, Test_Snapshot{position = {index, 7}}))
		destroy(&c)
	}
	for path, index in paths {
		c, snapshot, status := load_slot(path, Test_Snapshot)
		testing.expect_value(t, status, Load_Status.Loaded)
		testing.expect_value(t, depot_credits(&c), i64((index+1)*10))
		testing.expect_value(t, c.discovered[game.Card_Id.Storm_Crown], index == 1)
		testing.expect_value(t, c.run.active, index == 2)
		testing.expect_value(t, snapshot.position[0], index)
		destroy(&c); delete(snapshot.label); os.remove(path)
	}
}
