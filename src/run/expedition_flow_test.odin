package run

import "core:os"
import _ "../engine/teststack"
import "core:testing"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import host "../engine/host"

// A scratch file in the system's temp directory: the tests must not depend on
// a macOS-only path such as /private/tmp (they failed on Windows).
scratch_path :: proc(name: string) -> string {
	dir, dir_error := os.temp_directory(context.temp_allocator)
	if dir_error != nil { return name }
	path, path_error := os.join_path({dir, name}, context.temp_allocator)
	return path if path_error == nil else name
}

@(test)
test_workshop_purchase_uses_cell_freed_by_payment_and_rolls_back_failure :: proc(t:^testing.T) {
	for credits in 10..=11 {
		c:campaign.Campaign;campaign.initialize(&c)
		testing.expect(t,campaign.grid_add(&c.backpack.grid,campaign.make_item(.Credits,i32(credits))))
		for _ in 1..<campaign.BACKPACK_WIDTH*campaign.BACKPACK_HEIGHT {
			testing.expect(t,campaign.grid_add(&c.backpack.grid,campaign.make_item(.Memory,1,0)))
		}
		before,revision:=c.backpack,c.revision
		purchased:=expedition_buy_consumable(&c,campaign.make_item(.Healing),10)
		testing.expect_value(t,purchased,credits==10)
		if purchased {
			testing.expect_value(t,campaign.backpack_credits(&c.backpack),i32(0))
			healing:=0;for entry in c.backpack.grid.entries[:c.backpack.grid.count] {if entry.item.kind==.Healing {healing+=int(entry.item.quantity)}}
			testing.expect_value(t,healing,1)
			testing.expect_value(t,c.revision,revision+1)
		} else {
			testing.expect_value(t,c.backpack,before)
			testing.expect_value(t,c.revision,revision)
		}
		campaign.destroy(&c)
	}
}

@(private)
flow_fixture :: proc(t: ^testing.T, biome: campaign.Biome = .Cyber) -> ^Expedition_Session {
	e := new(Expedition_Session)
	e.progress = new(campaign.Campaign)
	campaign.initialize(e.progress)
	e.progress.unlocked[biome] = true
	testing.expect(t, campaign.begin_run(e.progress, biome, 0xCAFE))
	e.checkpoint = new(world.Snapshot)
	e.site = -1
	e.rs = roguelike_session_new()
	rs := e.rs
	player, created := game.create_player({max_health = 32, attack = 2, defense = 1})
	testing.expect(t, created)
	rs.run_state.player = player
	testing.expect(t, world.generate(&e.world, &rs.level_data, biome, 0xCAFE))
	room, ready := game.create_room(&rs.level_data, &rs.run_state.player, {room_seed = 0xCAFE})
	testing.expect(t, ready)
	rs.room = room; rs.room_created = true
	testing.expect(t, game.configure_expedition_combat(&rs.room))
	game.end_expedition_encounter(&rs.room)
	return e
}
@(private)
flow_destroy :: proc(e: ^Expedition_Session) {
	roguelike_destroy(e.rs)
	campaign.destroy(e.progress)
	free(e.progress); free(e.checkpoint); delete(e.message); free(e)
}

@(test)
test_failed_extraction_arcade_still_wins_and_clears_checkpoint :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	campaign.grid_add(&e.progress.backpack.grid, campaign.make_item(.Credits, 37))
	campaign.grid_add(&e.progress.backpack.grid, campaign.make_item(.Memory, 1, 0))
	e.world.boss_defeated = true; e.world.extracting = true
	testing.expect(t, expedition_save(e))
	testing.expect(t, e.checkpoint.valid && e.checkpoint.world.extracting)
	e.extracting = true
	commands: host.Commands
	frame := host.Frame{commands = &commands}
	expedition_resume(e, &frame, "lightcycles", host.Result{minigame = "lightcycles", outcome = .Lost, stars = 0})
	testing.expect(t, e.finished && !e.progress.run.active && !e.checkpoint.valid)
	testing.expect_value(t, campaign.depot_credits(e.progress), i64(37))
	testing.expect_value(t, e.progress.memory_fragments, u64(1))
	testing.expect(t, e.progress.won[campaign.Biome.Cyber])
	testing.expect_value(t, commands.count, 1)
	result, present := commands.items[0].result.?
	testing.expect(t, present && result.outcome == .Won)
}

@(test)
test_running_slot_snapshot_restores_owned_room_pointers :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-expedition-flow-slot.json")
	defer os.remove(path)
	e := flow_fixture(t); defer flow_destroy(e)
	campaign.discover(e.progress, .Storm_Crown)
	campaign.grid_add(&e.progress.backpack.grid, campaign.make_item(.Healing, 3))
	e.rs.room.player.health = 19
	e.world.mounted = true; e.world.clock = 17.25
	testing.expect(t, world.capture(&e.world, &e.rs.room, e.checkpoint))
	testing.expect(t, campaign.save_slot_from(path, e.progress, e.checkpoint))
	loaded: campaign.Campaign
	checkpoint := new(world.Snapshot); defer free(checkpoint)
	status := campaign.load_slot_into(path, &loaded, checkpoint)
	defer campaign.destroy(&loaded)
	testing.expect_value(t, status, campaign.Load_Status.Loaded)
	testing.expect(t, loaded.run.active && loaded.discovered[game.Card_Id.Storm_Crown])
	resumed := roguelike_session_new(); defer roguelike_destroy(resumed)
	restored_world: world.World
	testing.expect(t, world.restore(checkpoint, &restored_world, &resumed.level_data, &resumed.run_state.player, &resumed.room))
	resumed.room_created = true
	testing.expect(t, resumed.room.player == &resumed.run_state.player)
	testing.expect(t, resumed.room.level_data == &resumed.level_data)
	testing.expect(t, resumed.room.player != e.rs.room.player)
	testing.expect_value(t, resumed.room.player.health, i32(19))
	testing.expect(t, restored_world.mounted); testing.expect_value(t, restored_world.clock, f32(17.25))
	testing.expect_value(t, loaded.backpack.grid.entries[0].item.quantity, i32(3))
}

@(test)
test_gold_over_99_and_full_ground_never_disappear :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	position := e.rs.room.player.position
	e.world.drop_count = world.MAX_DROPS
	for &drop in e.world.drops { drop = {position = {0, 0}, item = campaign.make_item(.Healing)} }
	append(&e.rs.room.loot, game.Loot{position = position, kind = .Gold, amount = 250})
	expedition_collect(e)
	testing.expect_value(t, len(e.rs.room.loot), 1)
	testing.expect_value(t, e.rs.room.loot[0].amount, i32(250))
	e.world.drop_count = 0
	expedition_collect(e)
	testing.expect_value(t, campaign.backpack_credits(&e.progress.backpack), i32(250))
	testing.expect_value(t, len(e.rs.room.loot), 0)
	testing.expect_value(t, e.world.drop_count, 0)
	append(&e.rs.room.loot, game.Loot{position = position, kind = .Weapon, weapon_id = .Iron_Cleaver, amount = 2})
	expedition_collect(e)
	index := e.progress.backpack.grid.count-1
	testing.expect_value(t, e.progress.backpack.grid.entries[index].item.uses, i32(2))
}

@(test)
test_deliberately_dropped_item_waits_for_manual_pickup :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	position := e.rs.room.player.position
	testing.expect(t, world.add_drop(&e.world, position, campaign.make_item(.Healing), manual_only = true))
	expedition_collect(e)
	testing.expect_value(t, e.progress.backpack.grid.count, 0)
	testing.expect_value(t, e.world.drop_count, 1)
	expedition_collect(e, true)
	testing.expect_value(t, e.progress.backpack.grid.count, 1)
	testing.expect_value(t, e.world.drop_count, 0)
}

@(test)
test_direct_card_credits_are_physical_and_spending_does_not_duplicate :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	e.rs.room.player.gold += 7
	expedition_collect(e)
	testing.expect_value(t, campaign.backpack_credits(&e.progress.backpack), i32(7))
	testing.expect(t, campaign.backpack_pay(&e.progress.backpack, 4))
	// A purchase edits the bag while the displayed player counter is stale.
	expedition_collect(e)
	testing.expect_value(t, campaign.backpack_credits(&e.progress.backpack), i32(3))
	testing.expect_value(t, e.rs.room.player.gold, i32(3))
	// A blocked floor retains the award in the serialized pending room loot.
	e.world.drop_count = world.MAX_DROPS
	for &drop in e.world.drops { drop = {position = {0, 0}, item = campaign.make_item(.Healing)} }
	e.rs.room.player.gold += 6
	expedition_collect(e)
	testing.expect_value(t, len(e.rs.room.loot), 1)
	testing.expect_value(t, e.rs.room.loot[0].amount, i32(6))
	expedition_collect(e)
	testing.expect_value(t, len(e.rs.room.loot), 1)
	e.world.drop_count = 0
	expedition_collect(e)
	testing.expect_value(t, campaign.backpack_credits(&e.progress.backpack), i32(9))
}

@(test)
test_full_ground_restores_equipment_when_backpack_and_pending_are_full :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	bag := &e.progress.backpack
	for y in 0..<bag.grid.height { for x in 0..<bag.grid.width {
		testing.expect(t, campaign.grid_place(&bag.grid, campaign.make_item(.Credits, 99), x, y))
	} }
	bag.pending_count = campaign.PENDING_ITEMS
	for &item in bag.pending { item = campaign.make_item(.Healing, 5) }
	e.world.drop_count = world.MAX_DROPS
	bag.relics[0] = campaign.make_item(.Relic, 1, i32(game.Relic_Id.Iron_Knuckle))
	bag.relics[1] = campaign.make_item(.Relic, 1, i32(game.Relic_Id.Ash_Bookmark))
	bag.relics[2] = campaign.make_item(.Relic, 1, i32(game.Relic_Id.Swift_Soles))
	bag.weapon = campaign.make_item(.Weapon, 1, i32(game.Weapon_Id.Iron_Cleaver))
	bag.weapon.uses = 2
	before := bag^
	// The UI removes an item and reapplies passives before returning its drop.
	relic := bag.relics[1]; bag.relics[1] = {}
	campaign.apply_equipment(bag, e.rs.room.player)
	testing.expect(t, !expedition_drop_inventory_item(e, relic))
	testing.expect_value(t, bag^, before)
	testing.expect(t, game.player_has_relic(e.rs.room.player, .Ash_Bookmark))
	weapon := bag.weapon; bag.weapon = {}
	campaign.apply_equipment(bag, e.rs.room.player)
	testing.expect(t, !expedition_drop_inventory_item(e, weapon))
	testing.expect_value(t, bag^, before)
	testing.expect_value(t, e.rs.room.player.equipment.weapon.uses_remaining, i32(2))
	testing.expect_value(t, e.world.drop_count, world.MAX_DROPS)
	testing.expect(t, e.inventory_open)
}

@(test)
test_focus_loss_flushes_once_and_preserves_previous_checkpoint_during_cast :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	testing.expect(t, expedition_save(e))
	Probe :: struct { writes, flushes: int, reject_write: bool }
	probe: Probe
	e.save_data = &probe
	e.save = proc(data: rawptr) -> bool { p := cast(^Probe)data; p.writes += 1; return !p.reject_write }
	e.flush = proc(data: rawptr) -> bool { p := cast(^Probe)data; p.flushes += 1; return true }
	e.window_active = true
	before_health := e.checkpoint.player.health
	e.rs.room.player.health -= 3
	e.rs.room.tactical_pulse.pending = true
	frame := host.Frame{focused = false, window_focused = false}
	expedition_update(e, &frame)
	expedition_update(e, &frame)
	testing.expect_value(t, probe.writes, 0)
	testing.expect_value(t, probe.flushes, 1)
	testing.expect_value(t, e.checkpoint.player.health, before_health)
	// Regaining OS focus while covered does not mutate or save the scene.
	frame.window_focused = true
	expedition_update(e, &frame)
	e.rs.room.tactical_pulse.pending = false
	frame.window_focused = false
	expedition_update(e, &frame)
	testing.expect_value(t, probe.writes, 1)
	testing.expect_value(t, probe.flushes, 2)
	testing.expect_value(t, e.checkpoint.player.health, before_health-3)
	// Flushing an older success cannot mask rejection of this new checkpoint.
	probe.reject_write = true
	testing.expect(t, !expedition_save(e, true) && e.save_failed)
}

@(test)
test_fished_food_is_carried_extracted_and_retained_when_ground_is_full :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	_, added := game.add_owned_card(&e.rs.room.player.deck, .Fishing_Rod)
	testing.expect(t, added)
	for seed in u64(1)..<u64(1000) { stream := seed; if !game.fishing_catch_is_card(&stream) { e.rs.room.fishing.random = seed; break } }
	e.rs.room.player.health = 20
	position := e.rs.room.player.position
	report := game.fish_with_rod(&e.rs.room, {position.x+1, position.y})
	testing.expect(t, report.result == .Fished && !report.card)
	e.world.drop_count = world.MAX_DROPS
	for &drop in e.world.drops { drop = {position = {0, 0}, item = campaign.make_item(.Healing)} }
	expedition_collect(e)
	testing.expect_value(t, e.rs.room.player.health, i32(20))
	testing.expect_value(t, len(e.rs.room.loot), 1)
	testing.expect_value(t, e.rs.room.loot[0].healing_amount, report.roll.total)
	e.world.drop_count = 0
	expedition_collect(e)
	testing.expect_value(t, len(e.rs.room.loot), 0)
	testing.expect_value(t, e.progress.backpack.grid.entries[0].item.variant, report.roll.total)
	testing.expect(t, campaign.finish_run(e.progress, true))
	testing.expect_value(t, e.progress.depot[0].entries[0].item.variant, report.roll.total)
}

@(test)
test_fished_card_discovery_survives_a_later_death :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	_, added := game.add_owned_card(&e.rs.room.player.deck, .Fishing_Rod)
	testing.expect(t, added)
	for seed in u64(1)..<u64(1000) { stream := seed; if game.fishing_catch_is_card(&stream) { e.rs.room.fishing.random = seed; break } }
	position := e.rs.room.player.position
	report := game.fish_with_rod(&e.rs.room, {position.x+1, position.y})
	if !testing.expect(t, report.result == .Fished && report.card) { return }
	e.progress.discovered[report.added.definition_id] = false
	expedition_collect(e)
	testing.expect(t, e.progress.discovered[report.added.definition_id])
	testing.expect(t, campaign.finish_run(e.progress, false))
	testing.expect(t, e.progress.discovered[report.added.definition_id])
}

@(test)
test_death_checkpoint_cannot_restore_lost_stakes :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	campaign.grid_add(&e.progress.backpack.grid, campaign.make_item(.Credits, 71))
	campaign.discover(e.progress, .Storm_Crown)
	testing.expect(t, expedition_save(e)); testing.expect(t, e.checkpoint.valid)
	testing.expect(t, campaign.finish_run(e.progress, false))
	testing.expect(t, expedition_save(e))
	testing.expect(t, !e.checkpoint.valid && !e.progress.run.active)
	testing.expect_value(t, campaign.backpack_credits(&e.progress.backpack), i32(0))
	testing.expect(t, e.progress.discovered[game.Card_Id.Storm_Crown])
}

@(test)
test_expedition_reward_never_offers_temporary_only_card :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	for seed in 1..<40 {
		e.world.sites[0].kind = .Nest; e.world.sites[0].seed = u64(seed)
		e.world.reward_count = 0
		expedition_reward(e, 0)
		testing.expect_value(t, e.world.reward_count, 3)
		for card in e.world.reward_cards[:e.world.reward_count] {
			definition, ok := game.card_definition_by_id(card)
			testing.expect(t, ok && !definition.temporary_only && definition.reward_weight > 0)
			testing.expect(t, campaign.card_in_pool(e.progress, card))
		}
	}
}

@(test)
test_workshop_offer_is_deterministic_varied_and_current_pool_only :: proc(t: ^testing.T) {
	e := flow_fixture(t); defer flow_destroy(e)
	e.site = 0
	seen_other := false
	for seed in 1..<24 {
		e.world.sites[0].seed = u64(seed)
		first, ok := expedition_workshop_card(e)
		second, again := expedition_workshop_card(e)
		testing.expect(t, ok && again && first == second)
		testing.expect(t, campaign.card_in_pool(e.progress, first))
		definition, _ := game.card_definition_by_id(first)
		testing.expect(t, !definition.temporary_only)
		seen_other = seen_other || first != .Strike
	}
	testing.expect(t, seen_other)
}
