package integration
import run_session "../run"

import "core:testing"
import advisor "../advisor"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE IA'S GAME STATE (docs/piano-ia.md, Fase 6): a point of life weighs less near the end of the run and with a real
// heal near; the run and the expedition tell the advisor how far along they are, which heals are near (the Cibo
// pescato never) and which foes sleep on the map; a branch ending where a sleeper wakes costs.

@(private = "file")
context_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	testing.expect(t, built)
	for &enemy in room.enemies { enemy.recovery_pulses, enemy.intent, enemy.tactical_cooldown = 99, {}, 0 }
	game.plan_enemy_intents(&room)
	return room
}

// What a branch ending with `lost` life lost and `dealt` damage done is worth more than one ending as the root, with
// `game_context` (the same cells: only the weights speak).
@(private = "file")
context_test_trade :: proc(room: ^game.Room, game_context: advisor.Game_Context, lost, dealt: i32) -> f32 {
	facts := advisor.root_facts(room, game_context)
	before := advisor.evaluate(room, &facts, 0)
	room.player.health -= lost
	room.enemies[0].health -= dealt
	after := advisor.evaluate(room, &facts, 0)
	room.player.health += lost
	room.enemies[0].health += dealt
	return after-before
}

// The plan's puzzles: at the start of the run the IA does not give 2 of life for 5 of damage (-6 + 5); at its end it
// does (-4 + 5); half way, with a FONTE not yet used near, it does too.
@(test)
test_advisor_life_weighs_less_near_the_end :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := context_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	testing.expect_value(t, advisor.life_weight({known = true, progress = 0}, false), f32(3))
	testing.expect_value(t, advisor.life_weight({known = true, progress = 1}, false), f32(2))
	testing.expect_value(t, advisor.life_weight({known = true, progress = 0.5}, true), f32(2))
	testing.expect_value(t, advisor.life_weight({known = true, progress = 1}, true), f32(1.5))
	start := context_test_trade(&room, {known = true, progress = 0}, 2, 5)
	end := context_test_trade(&room, {known = true, progress = 1}, 2, 5)
	spring := context_test_trade(&room, {known = true, progress = 0.5, heal_outside = 16}, 2, 5)
	testing.expectf(t, start < 0, "at the start of the run 2 of life for 5 of damage is worth %.2f", start)
	testing.expectf(t, end > 0, "at the end of the run 2 of life for 5 of damage is worth %.2f", end)
	testing.expectf(t, spring > 0, "half way with a FONTE near, 2 of life for 5 of damage is worth %.2f", spring)
	// Death stays the worst, whatever the progress.
	facts := advisor.root_facts(&room, {known = true, progress = 1, heal_outside = 16})
	health := room.player.health
	room.player.health = 0
	testing.expect(t, advisor.evaluate(&room, &facts, 0) <= advisor.DEATH_VALUE+10)
	room.player.health = health
}

// A branch ending where a sleeping foe wakes costs SLEEPER_VALUE; one out of its reach costs nothing.
@(test)
test_advisor_keeps_away_from_the_sleepers :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := context_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	p := room.player.position
	near := advisor.Game_Context{known = true, sleeper_count = 1}
	near.sleepers[0] = {position = game.add_position(p, {x = 2, y = 0}), archetype = .Brute, health = 18, wake = 3}
	far := near
	far.sleepers[0].position = game.add_position(p, {x = 9, y = 0})
	quiet := advisor.root_facts(&room, far)
	woken := advisor.root_facts(&room, near)
	difference := advisor.evaluate(&room, &woken, 0)-advisor.evaluate(&room, &quiet, 0)
	testing.expectf(t, abs(difference-advisor.SLEEPER_VALUE) < 0.001, "a sleeper woken costs %.2f", difference)
}

// THE RUN: the node's depth on the way to the boss; a Rest one step on is a heal near (30% of the life).
@(test)
test_advisor_context_of_the_run :: proc(t: ^testing.T) {
	run: game.Run_State
	defer delete(run.route_map.nodes)
	run.player.stats.max_health = 20
	append(&run.route_map.nodes, game.Run_Node{id = 0, kind = .Combat, depth = 2, outgoing_count = 1})
	run.route_map.nodes[0].outgoing[0] = 1
	append(&run.route_map.nodes, game.Run_Node{id = 1, kind = .Rest, depth = 3})
	append(&run.route_map.nodes, game.Run_Node{id = 2, kind = .Boss, depth = 8})
	run.current_node = 0
	game_context := run_session.advisor_context_run(&run)
	testing.expect(t, game_context.known)
	testing.expect_value(t, game_context.progress, f32(0.25))
	testing.expect_value(t, game_context.heal_outside, i32(6))
	// Every node, place and biome has its line (the switches have no default).
	for kind in game.Node_Kind { if kind != .Count { testing.expectf(t, run_session.advisor_node(kind).why != "", "%v", kind) } }
	for kind in world.Site_Kind { testing.expectf(t, run_session.advisor_site(kind).why != "", "%v", kind) }
	for biome in campaign.Biome { if biome != .Count { testing.expectf(t, run_session.advisor_biome(biome) != "", "%v", biome) } }
	testing.expect_value(t, run_session.advisor_item_heal({kind = .Healing, variant = 0}), i32(12))
	testing.expect_value(t, run_session.advisor_item_heal({kind = .Healing, variant = 3}), i32(0))
}

// THE EXPEDITION: a FONTE not yet used within 20 cells is a heal near (16), one used or far is not; the Kit in the
// backpack is (12), the Cibo pescato is not; the foes asleep near the player are sleepers; the groups beaten, the
// places done and the boss make the progress.
@(test)
test_advisor_context_of_the_expedition :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := context_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	w := new(world.World)
	defer free(w)
	p := room.player.position
	w.site_count = 2
	w.sites[0] = {kind = .Spring, state = .Discovered, position = grid.offset(p, 10, 0)}
	w.sites[1] = {kind = .Nest, state = .Resolved, position = grid.offset(p, 40, 0)}
	w.group_count = 2
	w.groups[0].count = 2
	w.groups[0].members[0] = {enemy = {archetype = .Chaser, health = 12, position = grid.offset(p, 5, 0)}, alive = true}
	w.groups[0].members[1] = {enemy = {archetype = .Brute, health = 18, position = grid.offset(p, 6, 1)}, alive = true}
	w.groups[1].count = 1
	w.groups[1].members[0] = {alive = false}
	bag := new(campaign.Backpack)
	defer free(bag)
	game_context := run_session.advisor_context_expedition(w, bag, &room)
	testing.expect_value(t, game_context.heal_outside, i32(16))
	testing.expect_value(t, game_context.sleeper_count, 2)
	testing.expect_value(t, game_context.progress, f32(0.5))
	for sleeper in game_context.sleepers[:game_context.sleeper_count] { testing.expect(t, sleeper.wake == 3 || sleeper.wake == 6) }
	// The FONTE used: the Kit is the heal near; the Cibo pescato alone is none.
	w.sites[0].state = .Resolved
	bag.grid.count = 1
	bag.grid.entries[0].item = {kind = .Healing, variant = 0, quantity = 1}
	testing.expect_value(t, run_session.advisor_context_expedition(w, bag, &room).heal_outside, i32(12))
	bag.grid.entries[0].item = {kind = .Healing, variant = 2, quantity = 1}
	testing.expect_value(t, run_session.advisor_context_expedition(w, bag, &room).heal_outside, i32(0))
	w.boss_defeated = true
	testing.expect_value(t, run_session.advisor_context_expedition(w, bag, &room).progress, f32(1))
}

// The food the foes drop is a heal in the room; the fish of the rod is not.
@(test)
test_advisor_room_heals :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := context_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	testing.expect_value(t, advisor.room_heal(&room), i32(0))
	append(&room.loot, game.Loot{position = room.player.position, kind = .Healing, amount = 3, healing_amount = 3})
	testing.expect_value(t, advisor.room_heal(&room), i32(0))
	append(&room.loot, game.Loot{position = room.player.position, kind = .Healing, amount = 2})
	testing.expect_value(t, advisor.room_heal(&room), i32(2))
}
