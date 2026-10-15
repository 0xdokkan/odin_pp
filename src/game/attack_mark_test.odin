package game

import "core:testing"
import grid "../grid"
import level "../level"

// Every physical blow marks its own events for the board (mark_attack_events):
// where it comes from, the cell it aims at and the cells it sweeps.

attack_mark_find :: proc(log: ^Event_Log, kind: Game_Event_Kind, source: Entity_Ref, target := PLAYER_ENTITY) -> (Game_Event, bool) {
	for event in log.events[:log.count] {
		if event.kind == kind && event.source == source && event.target == target { return event, true }
	}
	return {}, false
}

@(test)
test_attack_marks_only_its_own_blow_up_to_the_first_wound :: proc(t: ^testing.T) {
	brute, thorned := enemy_entity(1), enemy_entity(2)
	log: Event_Log
	record_event(&log, {kind = .Damage_Absorbed, source = brute, target = PLAYER_ENTITY, amount = 1})
	record_event(&log, {kind = .Status_Removed, source = brute, target = PLAYER_ENTITY, status = .Shield})
	record_event(&log, {kind = .Damaged, source = brute, target = PLAYER_ENTITY, amount = 2})
	// What follows the wound is not the blow: a second one, a reaction, a bite.
	record_event(&log, {kind = .Damaged, source = brute, target = PLAYER_ENTITY, amount = 3})
	record_event(&log, {kind = .Damaged, source = PLAYER_ENTITY, target = brute, amount = 1})
	record_event(&log, {kind = .Damaged, source = thorned, target = PLAYER_ENTITY, amount = 1})
	cells := [3]grid.Position{{4, 3}, {4, 5}, {9, 9}}
	mark_attack_events(&log, 0, brute, PLAYER_ENTITY, {5, 4}, {4, 4}, cells[:], false)
	marked := [6]bool{true, false, true, false, false, false}
	for event, index in log.events[:log.count] {
		testing.expectf(t, event_is_attack(event) == marked[index], "event %d (%v)", index, event.kind)
		if !marked[index] { continue }
		testing.expect(t, !event_is_ranged_attack(event))
		testing.expect_value(t, event.from_position, grid.Position{5, 4})
		testing.expect_value(t, event.to_position, grid.Position{4, 4})
		// A cell beyond the 3x3 around the aim cannot be told apart: it is left out.
		testing.expect_value(t, event.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<1|u16(1)<<4|u16(1)<<7)
	}
	// Damage with a status cause is never a blow, and a ranged one says so.
	bite: Event_Log
	record_event(&bite, {kind = .Damaged, source = brute, target = PLAYER_ENTITY, amount = 1, has_status_cause = true, status_cause = .Poison})
	record_event(&bite, {kind = .Attack_Missed, source = brute, target = PLAYER_ENTITY})
	mark_attack_events(&bite, 0, brute, PLAYER_ENTITY, {8, 4}, {4, 4}, nil, true)
	testing.expect(t, !event_is_attack(bite.events[0]))
	testing.expect(t, event_is_ranged_attack(bite.events[1]))
	testing.expect_value(t, bite.events[1].area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4)
	_, beyond := event_footprint_bit({4, 4}, {6, 4})
	testing.expect(t, !beyond)
}

@(test)
test_attack_marks_a_bump_with_its_two_cells :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 3}, health = 100, attack = 1, archetype = .Chaser}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
	hit, found := attack_mark_find(&room.recent_events, .Damaged, PLAYER_ENTITY, enemy_entity(room.enemies[0].id))
	testing.expect(t, found && event_is_attack(hit) && !event_is_ranged_attack(hit) && !event_is_critical(hit))
	testing.expect_value(t, hit.from_position, grid.Position{4, 4})
	testing.expect_value(t, hit.to_position, grid.Position{4, 3})
	testing.expect_value(t, hit.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4)
}

// A diagonal bump on the tick is a blow too, and stays a critical one.
@(test)
test_attack_marks_a_critical_diagonal_bump_and_keeps_it_critical :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 100, attack = 1, archetype = .Chaser}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, try_move_player_diagonal(&room, {1, -1}), Action_Result.Attacked)
	hit, found := attack_mark_find(&room.recent_events, .Damaged, PLAYER_ENTITY, enemy_entity(room.enemies[0].id))
	testing.expect(t, found && event_is_attack(hit) && event_is_critical(hit))
	testing.expect_value(t, hit.from_position, grid.Position{4, 4})
	testing.expect_value(t, hit.to_position, grid.Position{5, 3})
	testing.expect_value(t, hit.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4)
}

@(test)
test_attack_marks_the_brute_cleave_hit_miss_parry_and_charge :: proc(t: ^testing.T) {
	for case_index in 0..<4 {
		data: level.Level
		player: Player
		charge := case_index == 3
		spawns := [?]Enemy_Spawn{{position = ({7, 4} if charge else {5, 4}), health = 100, attack = 2, archetype = .Brute}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		brute := enemy_entity(room.enemies[0].id)
		// 1: he has stepped off the cleave; 2: his parry cancelled the blow.
		if case_index == 1 { room.player.position = {4, 6} }
		if case_index == 2 { room.tactical_pulse.cancel_attack = room.enemies[0].id }
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
		cleave := u16(1)<<1|u16(1)<<4|u16(1)<<7
		if case_index == 1 || case_index == 2 {
			miss, found := attack_mark_find(&pulse.events, .Attack_Missed, brute)
			testing.expectf(t, found && event_is_attack(miss), "case %d", case_index)
			testing.expect_value(t, miss.from_position, grid.Position{5, 4})
			testing.expect_value(t, miss.to_position, grid.Position{4, 4})
			testing.expect_value(t, miss.area_mask&EVENT_FOOTPRINT_BITS, cleave)
		} else {
			hit, found := attack_mark_find(&pulse.events, .Damaged, brute)
			testing.expectf(t, found && event_is_attack(hit) && !event_is_ranged_attack(hit), "case %d", case_index)
			// The charge strikes from where it arrived, at the one cell it threatens.
			testing.expect_value(t, hit.from_position, grid.Position{5, 4})
			testing.expect_value(t, hit.to_position, grid.Position{4, 4})
			testing.expect_value(t, hit.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4 if charge else cleave)
			// The push that follows the blow keeps its own, unmarked event.
			push, pushed := attack_mark_find(&pulse.events, .Moved, brute)
			testing.expect(t, pushed && !event_is_attack(push))
			if charge {
				walk, walked := attack_mark_find(&pulse.events, .Moved, brute, brute)
				testing.expect(t, walked && !event_is_attack(walk))
			}
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_attack_marks_the_archer_shot_as_ranged_and_not_its_aim :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3, archetype = .Archer}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	archer := enemy_entity(room.enemies[0].id)
	aim: Pulse_Report
	resolve_enemy_intents(&room, &aim, room.enemies[0].id)
	for event in aim.events.events[:aim.events.count] { testing.expect(t, !event_is_attack(event)) }
	plan_enemy_intents(&room)
	shot: Pulse_Report
	resolve_enemy_intents(&room, &shot, room.enemies[0].id)
	hit, found := attack_mark_find(&shot.events, .Damaged, archer)
	testing.expect(t, found && event_is_ranged_attack(hit))
	testing.expect_value(t, hit.from_position, grid.Position{7, 4})
	testing.expect_value(t, hit.to_position, grid.Position{4, 4})
}

// Thorns answer a blow with damage of their own: never marked as one.
@(test)
test_attack_marks_the_ghoul_blow_and_not_the_thorns_it_meets :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 100, attack = 2, archetype = .Chaser}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	ghoul := enemy_entity(room.enemies[0].id)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
	hit, found := attack_mark_find(&pulse.events, .Damaged, ghoul)
	testing.expect(t, found && event_is_attack(hit) && !event_is_ranged_attack(hit))
	thorns, answered := attack_mark_find(&pulse.events, .Damaged, PLAYER_ENTITY, ghoul)
	testing.expect(t, answered && !event_is_attack(thorns))
}

// The archmage ignites a barrel from afar: its ember flies to the barrel.
@(test)
test_attack_marks_the_barrel_shot_as_ranged :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 2}, health = 20, attack = 2, archetype = .Demolitionist}}
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {4, 3}}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.target_object, room.objects[0].id)
	barrel := object_entity(room.objects[0].id)
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
	armed, found := attack_mark_find(&pulse.events, .Explosive_Armed, enemy_entity(room.enemies[0].id), barrel)
	testing.expect(t, found && event_is_ranged_attack(armed))
	testing.expect_value(t, armed.from_position, grid.Position{6, 2})
	testing.expect_value(t, armed.to_position, grid.Position{4, 3})
	testing.expect_value(t, armed.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4)
}

// An ember at a barrel that has moved is still thrown: a ranged blow on that
// barrel that lands on the cell it stood on, never a miss on the player.
@(test)
test_attack_marks_the_missed_barrel_shot_on_its_barrel :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 2}, health = 20, attack = 2, archetype = .Demolitionist}}
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {4, 3}}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	archmage, barrel := enemy_entity(room.enemies[0].id), object_entity(room.objects[0].id)
	testing.expect_value(t, room.enemies[0].intent.target_object, barrel.id)
	room.objects[0].position = {3, 3}
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
	miss, found := attack_mark_find(&pulse.events, .Attack_Missed, archmage, barrel)
	testing.expect(t, found && event_is_ranged_attack(miss))
	testing.expect_value(t, miss.from_position, grid.Position{6, 2})
	testing.expect_value(t, miss.to_position, grid.Position{4, 3})
	testing.expect_value(t, miss.area_mask&EVENT_FOOTPRINT_BITS, u16(1)<<4)
	_, on_player := attack_mark_find(&pulse.events, .Attack_Missed, archmage)
	testing.expect(t, !on_player)
}

// A charge parried before it ran is no blow: the brute never left his cell.
// A broken aim is none either.
@(test)
test_attack_marks_no_parried_charge_and_no_broken_aim :: proc(t: ^testing.T) {
	{
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 2, archetype = .Brute}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		defer level.destroy(&data)
		defer destroy_room(&room)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
		brute := enemy_entity(room.enemies[0].id)
		room.tactical_pulse.cancel_attack = brute.id
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, brute.id)
		miss, found := attack_mark_find(&pulse.events, .Attack_Missed, brute)
		testing.expect(t, found && !event_is_attack(miss))
		testing.expect_value(t, room.enemies[0].position, grid.Position{7, 4})
		_, walked := attack_mark_find(&pulse.events, .Moved, brute, brute)
		testing.expect(t, !walked)
	}
	{
		// The archer takes aim, then is shoved off the cell it aims from.
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3, archetype = .Archer}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		defer level.destroy(&data)
		defer destroy_room(&room)
		archer := enemy_entity(room.enemies[0].id)
		testing.expect(t, room.enemies[0].intent.kind == .Attack && room.enemies[0].intent.windup)
		room.enemies[0].position = {7, 3}
		aim: Pulse_Report
		resolve_enemy_intents(&room, &aim, archer.id)
		broken, missed := attack_mark_find(&aim.events, .Attack_Missed, archer)
		testing.expect(t, missed && !event_is_attack(broken))
	}
}

@(test)
test_attack_marks_no_bomb_and_no_protection :: proc(t: ^testing.T) {
	for archetype in ([?]Enemy_Archetype{.Bomber, .Custodian}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 2, archetype = archetype},
			{position = {7, 5}, health = 100, attack = 1}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		for _ in 0..<3 {
			pulse: Pulse_Report
			resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
			for event in pulse.events.events[:pulse.events.count] { testing.expect(t, !event_is_attack(event)) }
			plan_enemy_intents(&room)
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}
