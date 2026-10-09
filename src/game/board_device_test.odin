package game

import "core:testing"
import grid "../grid"
import level "../level"

board_device_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	data^ = spell_test_level(t)
	player^ = spell_test_player(t, .Shock_Floor)
	spawns := [?]Enemy_Spawn{
		{position = {3, 2}, health = 30, attack = 1},
		{position = {4, 2}, health = 30, attack = 1},
		{position = {4, 3}, health = 30, attack = 1},
		{position = {9, 3}, health = 30, attack = 1},
	}
	room, ok := create_room(data, player, {enemies = spawns[:]})
	testing.expect(t, ok)
	return room
}

@(test)
test_m8_d4_is_reproducible_bounded_and_rejects_without_mutation :: proc(t: ^testing.T) {
	a, b := make_dice_state(9981), make_dice_state(9981)
	seen: [4]bool
	for _ in 0..<128 {
		first, ok := roll_d4(&a)
		second, other_ok := roll_d4(&b)
		testing.expect(t, ok && other_ok && validate_dice_roll(&first))
		testing.expect(t, first.total >= 1 && first.total <= 4)
		testing.expect_value(t, first, second)
		testing.expect_value(t, a, b)
		seen[first.total-1] = true
	}
	for found in seen { testing.expect(t, found) }
	a.roll_count = max(u64)
	before := a
	_, ok := roll_d4(&a)
	testing.expect(t, !ok)
	testing.expect_value(t, a, before)
}

@(test)
test_m8_floor_targeting_never_rolls_and_committed_deploy_uses_one_d4 :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := player.deck.hand[0]
	before := player.dice
	for _ in 0..<5 {
		action, err := compile_card_action(&room, card, cell_target({3, 2}))
		testing.expect_value(t, err, Card_Compile_Error.None)
		testing.expect_value(t, action.effects[0].kind, Effect_Kind.Deploy_Device)
		testing.expect_value(t, player.dice, before)
	}
	action, err := compile_card_action(&room, card, cell_target({3, 2}))
	testing.expect_value(t, err, Card_Compile_Error.None)
	report := resolve_played_card_action(&room, card, cell_target({3, 2}), &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, player.dice.roll_count, before.roll_count+1)
	testing.expect_value(t, len(room.objects), 1)
	floor := room.objects[0]
	testing.expect(t, floor.device_charges >= 1 && floor.device_charges <= 4)
	testing.expect_value(t, floor.device_target_limit, floor.device_charges)
	testing.expect_value(t, floor.device_damage, i32(1))
	testing.expect(t, !floor.device_armed && !cell_blocks_movement(&room, floor.position))
	for event in report.events.events[:report.events.count] {
		if event.kind == .Dice_Rolled { testing.expect_value(t, event.dice_roll.total, floor.device_charges) }
	}
}

@(test)
test_m8_floor_d4_limits_targets_and_repeated_beats_then_expires :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {3, 2}, 1, 2, &log))
	pulse: Pulse_Report
	tick_board_devices(&room, &pulse)
	testing.expect_value(t, room.objects[0].device_charges, i32(2))
	testing.expect_value(t, room.enemies[0].health, i32(30))
	testing.expect(t, activate_board_devices(&room))
	testing.expect(t, !activate_board_devices(&room))
	player.position = {3, 2}
	for tick in 1..=2 {
		pulse = {}
		tick_board_devices(&room, &pulse)
		testing.expect_value(t, room.enemies[0].health, i32(30-tick))
		testing.expect_value(t, room.enemies[1].health, i32(30-tick))
		testing.expect_value(t, room.enemies[2].health, i32(30))
		testing.expect_value(t, room.enemies[3].health, i32(30))
		testing.expect_value(t, player.health, player.stats.max_health)
		testing.expect_value(t, pulse.damage_dealt, i32(2))
		testing.expect_value(t, pulse.events.dropped_count, 0)
	}
	testing.expect_value(t, len(room.objects), 0)
}

@(test)
test_m8_floor_target_ties_use_id_after_object_and_enemy_reordering :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	object := Grid_Object{kind = .Shock_Floor, position = {3, 3}, device_target_limit = 2}
	first, count := shock_floor_targets(&room, object)
	room.enemies[0], room.enemies[2] = room.enemies[2], room.enemies[0]
	second, next_count := shock_floor_targets(&room, object)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, next_count, count)
	testing.expect_value(t, first, second)
}

@(test)
test_m8_tesla_limit_capacity_and_invalid_positions_are_atomic :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	for cell in ([?]grid.Position{{1, 1}, {3, 2}, {0, 0}, room.exit_position}) {
		id := room.next_object_id
		testing.expect(t, !deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
		testing.expect_value(t, room.next_object_id, id)
		testing.expect_value(t, len(room.objects), 0)
	}
	log.count = MAX_GAME_EVENTS
	testing.expect(t, !deploy_board_device(&room, .Tesla_Coil, {2, 1}, 8, 0, &log))
	testing.expect_value(t, len(room.objects), 0)
	clear_event_log(&log)
	for cell in ([?]grid.Position{{2, 1}, {6, 1}, {6, 4}, {2, 4}}) {
		testing.expect(t, deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
	}
	id := room.next_object_id
	testing.expect(t, !deploy_board_device(&room, .Tesla_Coil, {8, 1}, 8, 0, &log))
	testing.expect_value(t, room.next_object_id, id)
	testing.expect_value(t, board_tesla_count(&room), MAX_TESLA_COILS)
	testing.expect(t, cell_blocks_movement(&room, {2, 1}))
	room.next_object_id = max(u32)
	testing.expect(t, !deploy_board_device(&room, .Shock_Floor, {8, 1}, 1, 3, &log))
}

@(test)
test_m8_tesla_geometry_damage_recharge_and_friendly_fire_share_query :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.stats.defense = 0
	log: Event_Log
	for cell in ([?]grid.Position{{2, 1}, {6, 1}, {6, 4}, {2, 4}}) {
		testing.expect(t, deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
	}
	network := query_board_device_network(&room)
	testing.expect(t, network.field && network.ready)
	testing.expect_value(t, network.damage, i32(2))
	for x in 2..=6 { for y in 1..=4 {
		testing.expect(t, board_device_network_contains_cell(&room, &network, {x, y}))
	} }
	testing.expect(t, !board_device_network_contains_cell(&room, &network, {7, 2}))
	player.position = {3, 3}
	testing.expect(t, activate_board_devices(&room))
	testing.expect_value(t, player.health, i32(8))
	for i in 0..<3 { testing.expect_value(t, room.enemies[i].health, i32(28)) }
	testing.expect_value(t, room.enemies[3].health, i32(30))
	testing.expect(t, !board_devices_can_activate(&room))
	for beat in 1..=3 {
		pulse: Pulse_Report
		tick_board_devices(&room, &pulse)
		testing.expect_value(t, board_devices_can_activate(&room), beat == 3)
	}
}

@(test)
test_m8_tesla_distance_halving_crossed_hull_and_degenerate_lines :: proc(t: ^testing.T) {
	for distance in ([?]int{1, 2, 4, 8}) {
		testing.expect_value(t, board_device_link_damage(8, {0, 0}, {distance, 0}), i32(8/distance))
	}
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	for cell in ([?]grid.Position{{2, 1}, {6, 4}, {6, 1}, {2, 4}}) {
		testing.expect(t, deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
	}
	network := query_board_device_network(&room)
	testing.expect(t, network.field)
	testing.expect(t, board_device_network_contains_cell(&room, &network, {3, 3}))
	for &object, i in room.objects { object.position = {2+i*2, 1} }
	network = query_board_device_network(&room)
	testing.expect(t, !network.field)
	testing.expect(t, board_device_network_contains_cell(&room, &network, {3, 1}))
	testing.expect(t, !board_device_network_contains_cell(&room, &network, {3, 2}))
}

@(test)
test_m8_failed_device_card_preserves_payment_dice_and_board :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {3, 2}, 1, 2, &log))
	before, dice, next_id := player.deck, player.dice, room.next_object_id
	play := play_card(&room, player.deck.hand[0].id, cell_target({3, 2}))
	testing.expect(t, !card_play_was_committed(play.result))
	testing.expect_value(t, player.deck, before)
	testing.expect_value(t, player.dice, dice)
	testing.expect_value(t, room.next_object_id, next_id)
	testing.expect_value(t, len(room.objects), 1)
}

@(test)
test_m8_tesla_links_spare_player_and_damage_every_enemy_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {2, 2}, 8, 0, &log))
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {6, 2}, 8, 0, &log))
	player.position = {5, 2}
	network := query_board_device_network(&room)
	testing.expect(t, !network.field && network.ready)
	testing.expect_value(t, board_device_network_damage_at(&room, &network, {3, 2}), i32(2))
	testing.expect(t, activate_board_devices(&room))
	testing.expect_value(t, player.health, player.stats.max_health)
	testing.expect_value(t, room.enemies[0].health, i32(28))
	testing.expect_value(t, room.enemies[1].health, i32(28))
	testing.expect_value(t, room.enemies[2].health, i32(30))
}

@(test)
test_m8_endfight_removes_devices_preserves_room_objects_and_opens_loot_path :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {2, 1}, 8, 0, &log))
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {3, 1}, 1, 4, &log))
	append(&room.objects, Grid_Object{id = room.next_object_id, kind = .Barrel, position = {5, 1}, health = 1, max_health = 1})
	room.next_object_id += 1
	room.phase = .Loot
	disarm_board_devices_after_combat(&room, &log)
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, room.objects[0].kind, Grid_Object_Kind.Barrel)
	testing.expect(t, !cell_blocks_movement(&room, {2, 1}))
	testing.expect_value(t, spell_test_event_count(&log, .Entity_Defeated), 2)
	disarm_board_devices_after_combat(&room, &log)
	testing.expect_value(t, spell_test_event_count(&log, .Entity_Defeated), 2)
}

@(test)
test_m8_tesla_blocked_link_rejects_activation_without_mutation :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {2, 2}, 8, 0, &log))
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {6, 2}, 8, 0, &log))
	append(&room.obstacles, Obstacle{position = {5, 2}})
	network := query_board_device_network(&room)
	testing.expect(t, !network.ready && network.active_links == 0)
	testing.expect_value(t, board_device_network_damage_at(&room, &network, {3, 2}), i32(0))
	before_log := room.recent_events
	testing.expect(t, !activate_board_devices(&room))
	testing.expect_value(t, room.recent_events, before_log)
	for object in room.objects { testing.expect_value(t, object.device_cooldown, i32(0)) }
	for enemy in room.enemies { testing.expect_value(t, enemy.health, i32(30)) }
	clear(&room.obstacles)
	testing.expect(t, board_devices_can_activate(&room))
}

@(test)
test_m8_tesla_field_requires_a_closed_unblocked_perimeter :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	log: Event_Log
	for cell in ([?]grid.Position{{2, 1}, {6, 1}, {6, 4}, {2, 4}}) {
		testing.expect(t, deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
	}
	append(&room.obstacles, Obstacle{position = {4, 1}})
	network := query_board_device_network(&room)
	testing.expect(t, !network.field && network.ready)
	testing.expect(t, !board_device_network_contains_cell(&room, &network, {3, 2}))
	testing.expect(t, board_device_network_contains_cell(&room, &network, {6, 2}))
	clear(&room.obstacles)
	network = query_board_device_network(&room)
	testing.expect(t, network.field)
}

@(test)
test_m8_last_floor_discharge_can_end_fight_while_cleanup_removes_other_devices :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := board_device_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	kill_enemy(&room, 3)
	for &enemy in room.enemies { enemy.health = 1 }
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {3, 2}, 1, 3, &log))
	room.objects[0].device_charges = 1
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {8, 2}, 1, 1, &log))
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {2, 1}, 8, 0, &log))
	testing.expect(t, activate_board_devices(&room))
	pulse: Pulse_Report
	tick_board_devices(&room, &pulse)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, len(room.objects), 0)
	testing.expect_value(t, pulse.enemies_defeated, 3)
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect(t, !cell_blocks_movement(&room, {2, 1}))
}

@(test)
test_m8_network_trace_spans_full_room_and_respects_sealed_diagonal_corners :: proc(t: ^testing.T) {
	rows := [?]string{
		"########################",
		"#@.....................#",
		"#......................#",
		"#.....................>#",
		"########################",
	}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {21, 3}, health = 10, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect(t, board_device_link_is_clear(&room, {2, 2}, {21, 2}))
	append(&room.obstacles, Obstacle{position = {13, 2}})
	testing.expect(t, !board_device_link_is_clear(&room, {2, 2}, {21, 2}))
	clear(&room.obstacles)
	append(&room.obstacles, Obstacle{position = {3, 1}})
	append(&room.obstacles, Obstacle{position = {2, 2}})
	testing.expect(t, !board_device_link_is_clear(&room, {2, 1}, {4, 3}))
}

@(test)
test_m8_field_lethal_friendly_fire_still_hits_all_32_enemies_once :: proc(t: ^testing.T) {
	rows := [?]string{
		"#########", "#.......#", "#.......#", "#.......#", "#...@...#",
		"#.......#", "#.......#", "#...>...#", "#########",
	}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	for lethal_enemies in ([2]bool{false, true}) {
		player := create_test_player(t)
		player.stats.defense = 0
		player.health = 1
		spawns: [MAX_ENEMIES_PER_ROOM]Enemy_Spawn
		count := 0
		for y in 1..=5 { for x in 1..=7 {
			if (y == 1 && (x == 1 || x == 7)) || (x == 4 && y == 4) { continue }
			spawns[count] = {position = {x, y}, health = 1 if lethal_enemies else 5, attack = 1}
			count += 1
		} }
		testing.expect_value(t, count, MAX_ENEMIES_PER_ROOM)
		room, ok := create_room(&data, &player, {enemies = spawns[:]})
		testing.expect(t, ok)
		defer destroy_room(&room)
		log: Event_Log
		for cell in ([4]grid.Position{{1, 1}, {7, 1}, {7, 7}, {1, 7}}) {
			testing.expect(t, deploy_board_device(&room, .Tesla_Coil, cell, 8, 0, &log))
		}
		network := query_board_device_network(&room)
		testing.expect(t, network.field && network.ready)
		testing.expect_value(t, network.damage, i32(2))
		testing.expect(t, activate_board_devices(&room))
		testing.expect_value(t, room.phase, Room_Phase.Defeat)
		testing.expect_value(t, player.health, i32(0))
		testing.expect_value(t, len(room.enemies), 0 if lethal_enemies else MAX_ENEMIES_PER_ROOM)
		for enemy in room.enemies { testing.expect_value(t, enemy.health, i32(3)) }
		hits: [MAX_ENEMIES_PER_ROOM+1]int
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind != .Damaged { continue }
			if event.target == PLAYER_ENTITY { hits[0] += 1 }
			else if event.target.kind == .Enemy { hits[event.target.id] += 1 }
		}
		for hit in hits { testing.expect_value(t, hit, 1) }
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		testing.expect_value(t, len(room.objects), 0)
	}
}
