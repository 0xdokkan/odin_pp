package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// Drive real elapsed time through the same clock as the controller. A role's
// telegraph must survive unrelated one-second beats until its own deadline.
advance_enemy_rework_seconds :: proc(t: ^testing.T, room: ^Room, seconds: int) {
	for _ in 0..<seconds {
		testing.expect(t, !tactical_tick(room, 1, true, false))
		drain_tactical_test_pulse(t, room)
	}
}

@(test)
test_tactical_archer_aims_without_qte_then_fires_at_frozen_cell_and_recovers :: proc(t: ^testing.T) {
	for evade in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3, archetype = .Archer}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		testing.expect(t, room.enemies[0].intent.windup)
		testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]))
		initial := room.enemies[0].intent
		for _ in 0..<3 {
			advance_enemy_rework_seconds(t, &room, 1)
			testing.expect_value(t, room.enemies[0].intent, initial)
			testing.expect(t, !room.enemies[0].aim_ready)
			testing.expect_value(t, player.health, i32(100))
		}
		advance_enemy_rework_seconds(t, &room, 1)
		testing.expect_value(t, player.health, i32(100))
		testing.expect(t, room.enemies[0].aim_ready)
		testing.expect(t, !room.enemies[0].intent.windup)
		testing.expect_value(t, room.enemies[0].intent.threatened_cells[0], grid.Position{4, 4})
		if evade { try_move_player(&room, .North) } else { wait_player_turn(&room) }
		// Evading now finishes before the prepared shot's one-second deadline.
		if evade { tactical_tick(&room, 1-TACTICAL_MOVE_SECONDS, true, false) }
		drain_tactical_test_pulse(t, &room)
		testing.expect_value(t, player.health, i32(100) if evade else i32(97))
		testing.expect(t, !room.enemies[0].aim_ready)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1))
		testing.expect_value(t, room.pulse_count, u64(5))
		testing.expect(t, abs(player.tactical.remaining-15) < 0.001)
		testing.expect_value(t, player.tactical.cycle, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_stagger_interrupts_prepared_shots_bombs_charges_and_support :: proc(t: ^testing.T) {
	for archetype in ([?]Enemy_Archetype{.Archer, .Bomber, .Brute, .Custodian, .Demolitionist}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3, archetype = archetype},
			{position = {7, 5}, health = 100, attack = 1}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		if archetype == .Archer || archetype == .Bomber {
			pulse: Pulse_Report
			resolve_enemy_intents(&room, &pulse, 1)
			plan_enemy_intents(&room)
			testing.expect(t, room.enemies[0].aim_ready || room.enemies[0].bomb_ready)
		}
		if archetype == .Custodian { testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Protect) }
		if archetype == .Brute { testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge) }
		position := room.enemies[0].position
		applied, _ := apply_status(&room, enemy_entity(1), .Stagger, 1, 1)
		testing.expect(t, applied)
		testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]))
		advance_enemy_rework_seconds(t, &room, 1)
		testing.expect_value(t, player.health, i32(100))
		testing.expect_value(t, room.enemies[0].position, position)
		testing.expect_value(t, active_bomb_count(&room), 0)
		testing.expect(t, !room.enemies[0].aim_ready && !room.enemies[0].bomb_ready)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		_, shielded := status_for_entity(&room, enemy_entity(2), .Shield)
		testing.expect(t, !shielded)
		testing.expect(t, validate_enemy_intents(&room))
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_brute_cleave_has_three_fixed_cells_and_charge_recovers_two :: proc(t: ^testing.T) {
	for charge in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = ({7, 4} if charge else {5, 4}), health = 100, attack = 2, archetype = .Brute}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		intent := room.enemies[0].intent
		if !charge {
			testing.expect_value(t, intent.threatened_cell_count, 3)
			for cell in ([?]grid.Position{{4, 3}, {4, 4}, {4, 5}}) { testing.expect(t, enemy_intent_cell_is_threatened(&intent, cell)) }
			testing.expect(t, !enemy_intent_cell_is_threatened(&intent, {3, 4}))
		}
		advance_enemy_rework_seconds(t, &room, 4)
		testing.expect_value(t, room.enemies[0].intent, intent)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(0))
		advance_enemy_rework_seconds(t, &room, 1)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2) if charge else i32(1))
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_custodian_cannot_shield_loop_and_exposes_two_pulse_window :: proc(t: ^testing.T) {
	for both_custodians in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 1, archetype = .Custodian},
			{position = {7, 5}, health = 100, attack = 1, archetype = (.Custodian if both_custodians else .Archer)}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		if both_custodians {
			for enemy in room.enemies { testing.expect(t, enemy.intent.kind != .Protect) }
		} else {
			testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Protect)
			advance_enemy_rework_seconds(t, &room, 3)
			_, early_shield := status_for_entity(&room, enemy_entity(2), .Shield)
			testing.expect(t, !early_shield)
			advance_enemy_rework_seconds(t, &room, 1)
			shield, found := status_for_entity(&room, enemy_entity(2), .Shield)
			testing.expect(t, found)
			if found { testing.expect_value(t, shield.potency, i32(2)) }
			testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}
