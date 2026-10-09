package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_dodge_without_cards_cancels_a_melee_hit_and_starts_recovery :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, tactical_dodge_ready(&room))
	wait_player_turn(&room)
	continue_tactical_pulse(&room)
	continue_tactical_pulse(&room)
	testing.expect_value(t, room.qte.defenses, bit_set[Defense_Mode]{.Dodge})
	testing.expect(t, select_defense(&room, .Dodge))
	testing.expect(t, qte_key(&room, .South))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.position, grid.Position{1, 2})
	testing.expect_value(t, player.health, i32(1000))
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.dodge_recovery, TACTICAL_DODGE_RECOVERY)
	testing.expect(t, !tactical_dodge_ready(&room))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Afterimage, 1, 4)
	testing.expect(t, tactical_dodge_ready(&room), "Afterimage permits another dodge during recovery")
}

@(test)
test_active_dodge_traverses_two_cells_costs_one_pulse_and_recovers_on_forced_pulses :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 100, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {4, 5}}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, try_dodge_player(&room, .South))
	testing.expect_value(t, player.position, grid.Position{4, 6})
	testing.expect_value(t, player.health, i32(98)) // Rolling still traverses floor hazards.
	testing.expect(t, !try_dodge_player(&room, .North), "cannot dodge twice during one committed pulse")
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.budget, 19)
	testing.expect_value(t, player.tactical.dodge_recovery, 2)
	testing.expect(t, !try_dodge_player(&room, .North))
	player.tactical.phase, player.tactical.skipped_remaining = .Forced, 2
	for _ in 0..<2 {
		testing.expect(t, continue_tactical_pulse(&room))
		drain_tactical_test_pulse(t, &room)
	}
	testing.expect_value(t, player.tactical.dodge_recovery, 0)
	testing.expect(t, tactical_dodge_ready(&room))
	testing.expect_value(t, room.pulse_count, u64(3))
}

@(test)
test_active_dodge_does_not_cross_walls_actors_or_consume_a_blocked_attempt :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !try_dodge_player(&room, .East))
	testing.expect_value(t, player.position, grid.Position{4, 4})
	testing.expect_value(t, player.tactical.dodge_recovery, 0)
	testing.expect(t, !room.tactical_pulse.pending)
	append(&room.obstacles, Obstacle{position = {2, 4}})
	destination, ok := tactical_dodge_destination(&room, .West)
	testing.expect(t, ok)
	testing.expect_value(t, destination, grid.Position{3, 4})
	player.tactical.phase = .Preparation
	testing.expect(t, !try_dodge_player(&room, .West))
	player.tactical.phase = .Decision
	testing.expect(t, try_dodge_player(&room, .West))
	testing.expect_value(t, player.position, grid.Position{3, 4})
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, player.tactical.dodge_recovery, 0)
}

@(test)
test_failed_reactive_dodge_leaves_the_attack_live :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	wait_player_turn(&room)
	continue_tactical_pulse(&room)
	continue_tactical_pulse(&room)
	testing.expect(t, select_defense(&room, .Dodge))
	testing.expect(t, qte_key(&room, .North), "blocked landing resolves as a failed QTE")
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.position, grid.Position{1, 1})
	testing.expect(t, player.health < 1000)
	testing.expect_value(t, player.tactical.metrics.qte_failures, u64(1))
}
