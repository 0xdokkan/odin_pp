package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_room_creation_and_reconfiguration_prepare_first_bomb_intent :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {x = 5, y = 1}, health = 20, attack = 2, archetype = .Bomber}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.damage, TACTICAL_BOMB_DAMAGE)
	testing.expect(t, configure_tactical_room(&room, DEFAULT_TACTICAL_CONFIG))
	testing.expect(t, room.enemies[0].intent.windup)
	testing.expect_value(t, room.enemies[0].intent.damage, TACTICAL_BOMB_DAMAGE)
	testing.expect(t, validate_enemy_intents(&room))
	wait_player_turn(&room)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, active_bomb_count(&room), 0)
}

create_enemy_rework_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn,
	objects: []Grid_Object_Spawn = nil) -> Room {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
	err: level.Parse_Error
	data^, err, _ = level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	testing.expect(t, configure_tactical(player, DEFAULT_TACTICAL_CONFIG))
	room, ok := create_room(data, player, {enemies = spawns, objects = objects})
	testing.expect(t, ok)
	return room
}

@(test)
test_m7_bombers_prepare_one_frozen_throw_with_three_pulses_to_escape :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 20, attack = 2, archetype = .Bomber},
		{position = {x = 2, y = 2}, health = 20, attack = 2, archetype = .Bomber}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	count := 0
	for enemy in room.enemies { if enemy.intent.windup { count += 1 } }
	testing.expect_value(t, count, 1)
	anchor := player.position
	initial := room.enemies[0].intent
	testing.expect(t, !tactical_tick(&room, 4, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].intent, initial)
	testing.expect(t, !room.enemies[0].bomb_ready)
	wait_player_turn(&room)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, active_bomb_count(&room), 0)
	testing.expect(t, room.enemies[0].bomb_ready)
	testing.expect_value(t, room.enemies[0].intent.destination, anchor)
	testing.expect(t, !room.enemies[0].intent.windup)
	try_move_player(&room, .West)
	tactical_tick(&room, 1-TACTICAL_MOVE_SECONDS, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, active_bomb_count(&room), 1)
	testing.expect_value(t, room.objects[0].position, anchor)
	testing.expect_value(t, room.objects[0].detonation_pulse-room.pulse_count, u64(3))
	testing.expect_value(t, room.objects[0].explosion_damage, i32(3))
	testing.expect_value(t, room.enemies[0].recovery_pulses, TACTICAL_BOMBER_RECOVERY)
	testing.expect(t, validate_enemy_intents(&room))
}

@(test)
test_m7_shoving_a_prepared_bomber_cancels_throw_and_still_grants_recovery :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 20, attack = 2, archetype = .Bomber}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !tactical_tick(&room, 5, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, room.enemies[0].bomb_ready)
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(enemy_entity(1)), .Opponent)
	testing.expect(t, add_effect(&action, move_effect(enemy_entity(1), {x = 6, y = 1})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	wait_player_turn(&room)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, active_bomb_count(&room), 0)
	testing.expect(t, !room.enemies[0].bomb_ready)
	testing.expect_value(t, room.enemies[0].recovery_pulses, TACTICAL_BOMBER_RECOVERY)
}

@(test)
test_m7_enemy_bomb_damage_is_reduced_without_nerfing_player_explosives :: proc(t: ^testing.T) {
	for hostile in ([?]bool{true, false}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 7, y = 1}, health = 100, attack = 1}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		source := enemy_entity(1) if hostile else PLAYER_ENTITY
		testing.expect(t, spawn_bomb(&room, source, player.position, room.recent_events))
		object := room.objects[0]
		testing.expect_value(t, object.fuse_pulses, 3 if hostile else 2)
		room.pulse_count = object.detonation_pulse-1
		pulse: Pulse_Report
		resolve_due_explosives(&room, &pulse)
		testing.expect_value(t, player.health, i32(97) if hostile else i32(96))
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_m7_chaser_routes_around_fire_and_archer_seeks_a_firing_lane :: proc(t: ^testing.T) {
	for archer in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = ({x = 6, y = 3} if archer else {x = 4, y = 1}), health = 20, attack = 2,
			archetype = (.Archer if archer else .Chaser)}}
		objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 4, y = 2}}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
		intent := room.enemies[0].intent
		testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Move)
		if archer { testing.expect_value(t, intent.destination, grid.Position{x = 6, y = 4}) }
		else { testing.expect(t, intent.destination == (grid.Position{x = 3, y = 1}) || intent.destination == (grid.Position{x = 5, y = 1})) }
		testing.expect_value(t, enemy_terrain_danger(&room, intent.destination), 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_m7_brute_push_uses_hazards_and_a_full_block_prevents_displacement :: proc(t: ^testing.T) {
	for shielded in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 5, y = 4}, health = 20, attack = 2, archetype = .Brute}}
		objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 3, y = 4}}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
		if shielded {
			_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 2, 3)
			_, _ = apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)
		}
		testing.expect(t, room.enemies[0].intent.push)
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse)
		testing.expect_value(t, player.position, grid.Position{x = 4, y = 4} if shielded else grid.Position{x = 3, y = 4})
		testing.expect_value(t, player.health, i32(100) if shielded else i32(96))
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_m7_charge_can_be_parried_once_and_retains_recovery :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 4}, health = 20, attack = 2, archetype = .Brute}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	// Wait through the brute's first four seconds, then defend its deadline.
	testing.expect(t, !tactical_tick(&room, 4, true, false))
	drain_tactical_test_pulse(t, &room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 3, 3)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
	wait_player_turn(&room)
	for _ in 0..<4 { if room.qte.kind != .None { break }; continue_tactical_pulse(&room) }
	testing.expect_value(t, room.qte.kind, QTE_Kind.Defense)
	testing.expect(t, select_defense(&room, .Parry))
	testing.expect(t, qte_key(&room, room.qte.keys[0]))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 7, y = 4})
	testing.expect_value(t, room.enemies[0].health, i32(18))
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect_value(t, room.pulse_count, u64(5))
}

@(test)
test_m7_demolitionist_ignites_a_barrel_but_does_not_retarget_a_moved_barrel :: proc(t: ^testing.T) {
	for displaced in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 20, attack = 2, archetype = .Demolitionist}}
		objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {x = 4, y = 3}}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
		testing.expect_value(t, room.enemies[0].intent.target_object, room.objects[0].id)
		if displaced { room.objects[0].position = {x = 3, y = 3} }
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse)
		testing.expect_value(t, room.objects[0].detonation_pulse != 0, !displaced)
		testing.expect(t, room.enemies[0].recovery_pulses > 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}
