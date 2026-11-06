package run

import "core:mem"
import "core:testing"
import advisor "../advisor"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Translate the ordinary heal/sleeper rules beyond both the old map boundary
// and index 65535. All actors stay on the same layer; no new spatial rule.
@(private = "file")
advisor_large_map_context_checks :: proc(t: ^testing.T) {
	data, created := level.create(320, 320, {kind = .Floor})
	if !testing.expect(t, created) { return }
	defer level.destroy(&data)
	p := grid.Position{x = 270, y = 270}
	data.player_spawn, data.has_player_spawn = p, true
	if !testing.expect(t, level.set_tile(&data, {x = 310, y = 310}, {kind = .Exit})) { return }
	player, valid := game.create_player({max_health = 100, attack = 5, defense = 0})
	if !testing.expect(t, valid) { return }
	if !testing.expect(t, game.configure_tactical(&player, game.EXPEDITION_TACTICAL_CONFIG)) { return }
	foes := [1]game.Enemy_Spawn{{position = grid.offset(p, 1, 0), health = 12, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = foes[:], room_seed = 42})
	if !testing.expect(t, built) { return }
	defer game.destroy_room(&room)
	if !testing.expect(t, game.configure_expedition_combat(&room)) { return }
	index, inside := game.room_table_index(&room, p)
	testing.expect(t, inside && index == 86670 && index > 65535)
	w := new(world.World)
	defer free(w)
	w.side_length, w.biome = 320, .City
	w.site_count = 2
	w.sites[0] = {kind = .Spring, state = .Discovered, position = grid.offset(p, ADVISOR_HEAL_REACH, 0)}
	w.sites[1] = {kind = .Spring, state = .Discovered, position = grid.offset(p, ADVISOR_HEAL_REACH+1, 0)}
	w.group_count, w.groups[0].count = 1, 3
	w.groups[0].members[0] = {enemy = {archetype = .Chaser, health = 12, position = grid.offset(p, ADVISOR_SLEEPER_REACH, 0)}, alive = true}
	w.groups[0].members[1] = {enemy = {archetype = .Brute, health = 18, position = grid.offset(p, ADVISOR_SLEEPER_REACH+1, 0)}, alive = true}
	w.groups[0].members[2] = {enemy = room.enemies[0], alive = true, deployed = true}
	bag := new(campaign.Backpack)
	defer free(bag)
	game_context := advisor_context_expedition(w, bag, &room)
	testing.expect(t, game_context.known)
	testing.expect_value(t, game_context.heal_outside, i32(16))
	testing.expect_value(t, game_context.sleeper_count, 1)
	testing.expect_value(t, game_context.sleepers[0].position, grid.offset(p, 24, 0))
	testing.expect_value(t, game_context.remaining_foes, 3)
	testing.expect_value(t, advisor.root_facts(&room, game_context).life_weight, f32(2.5))
	// A consumed spring no longer heals; the one 21 cells away is too far.
	w.sites[0].state = .Resolved
	testing.expect_value(t, advisor_context_expedition(w, bag, &room).heal_outside, i32(0))
	bag.grid.count = 1
	bag.grid.entries[0].item = {kind = .Healing, variant = 0, quantity = 1}
	testing.expect_value(t, advisor_context_expedition(w, bag, &room).heal_outside, i32(12))
	bag.grid.entries[0].item = {kind = .Healing, variant = 2, quantity = 1}
	testing.expect_value(t, advisor_context_expedition(w, bag, &room).heal_outside, i32(0))
	// Bring the existing sleeper into its ordinary wake radius. Its high
	// coordinate must survive the snapshot and affect the branch's value.
	w.groups[0].members[0].enemy.position = grid.offset(p, 3, 0)
	game_context = advisor_context_expedition(w, bag, &room)
	snapshot := new(advisor.Snapshot)
	defer free(snapshot)
	if !testing.expect(t, advisor.snapshot_init(snapshot)) { return }
	defer advisor.snapshot_destroy(snapshot)
	if !testing.expect(t, advisor.snapshot_take(snapshot, &room, game_context)) { return }
	testing.expect_value(t, snapshot.game_context.sleepers[0].position, grid.offset(p, 3, 0))
	testing.expect_value(t, snapshot.level.tiles.width, 320)
	w.groups[0].members[0].enemy.position = grid.offset(p, 25, 0)
	testing.expect_value(t, snapshot.game_context.sleepers[0].position, grid.offset(p, 3, 0))
	quiet := snapshot.game_context
	quiet.sleeper_count = 0
	quiet_facts := advisor.root_facts(&snapshot.room, quiet)
	woken_facts := advisor.root_facts(&snapshot.room, snapshot.game_context)
	difference := advisor.evaluate(&snapshot.room, &woken_facts, 0)-advisor.evaluate(&snapshot.room, &quiet_facts, 0)
	testing.expectf(t, abs(difference-advisor.SLEEPER_VALUE) < .001, "high-coordinate sleeper changes value by %.3f", difference)
}

@(test)
test_advisor_large_map_context_preserves_heals_sleepers_and_their_value :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	tracking.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	{
		context.allocator = mem.tracking_allocator(&tracking)
		advisor_large_map_context_checks(t)
	}
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}
