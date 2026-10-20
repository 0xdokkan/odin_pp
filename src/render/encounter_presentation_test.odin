package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

create_encounter_presentation_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{"##########", "#@.......#", "#........#", "#........#", "#.......>#", "##########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return data
}

encounter_presentation_test_modifier :: proc() -> game.Room_Modifier {
	modifier := game.Room_Modifier{
		kind = .Furnace, cell_count = 3, activation_pulse = 2, damage = game.ROOM_HAZARD_DAMAGE,
	}
	modifier.cells[0] = {2, 2}
	modifier.cells[1] = {3, 2}
	modifier.cells[2] = {4, 2}
	return modifier
}

// Advancing by precisely the current cue's remaining duration exposes the next
// cue before it starts. Assertions can distinguish announcement from resolution.
finish_encounter_test_cue :: proc(t: ^testing.T, timeline: ^Presentation_Timeline) {
	current, found := active_presentation_cue(timeline)
	testing.expect(t, found)
	if !found {
		return
	}
	old_count := timeline.count
	update_event_timeline(timeline, current.duration-current.elapsed)
	testing.expect_value(t, timeline.count, old_count-1)
}

// Collect the real clock's bounded batches for replay as one test sequence.
// Casts finish before world time advances; no player action manufactures a beat.
advance_presentation_test_clock :: proc(t: ^testing.T, room: ^game.Room, seconds: int) {
	if game.tactical_is_casting(room) { game.tactical_tick(room, room.player.tactical.cast_remaining, true, false) }
	events := room.recent_events^
	for _ in 0..<seconds {
		game.tactical_tick(room, 1, true, false)
		for step in 0..<400 {
			if room.qte.kind != .None { testing.expect(t, game.resolve_qte(room, false)) }
			if !room.tactical_pulse.pending { break }
			testing.expect(t, game.continue_tactical_pulse(room))
			game.append_event_log(&events, room.recent_events)
			testing.expect(t, step < 399)
		}
	}
	room.recent_events^ = events
	testing.expect_value(t, events.dropped_count, 0)
}

@(test)
test_custodian_shield_replays_before_ally_moves_then_absorbs_a_real_card :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{
		{position = {3, 2}, health = 8, attack = 1},
		{position = {4, 2}, health = 8, attack = 1, archetype = .Custodian},
	}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:], encounter_kind = .Escort})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	ally := game.enemy_entity(room.enemies[0].id)
	custodian := game.enemy_entity(room.enemies[1].id)
	testing.expect_value(t, room.enemies[1].intent.kind, game.Enemy_Intent_Kind.Protect)
	// Align the ally with the custodian's fourth beat: protection must replay first.
	room.enemies[0].tactical_cooldown = 4
	advance_presentation_test_clock(t, &room, 3)
	before := capture_room_presentation(&room)
	game.wait_player_turn(&room)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	testing.expect_value(t, timeline.view.encounter_kind, game.Encounter_Kind.Escort)
	visual, found := presentation_actor(&timeline, ally)
	testing.expect(t, found)
	_, shielded := game.status_index(&visual.statuses, .Shield)
	testing.expect(t, !shielded)
	shield_seen, movement_seen, pulse_seen := false, false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		if cue.kind == .Move && cue.event.target == ally {
			testing.expect(t, shield_seen)
			movement_seen = true
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Status_Applied && cue.event.target == ally {
			shield_seen = true
			testing.expect_value(t, cue.event.source, custodian)
			index, has_shield := game.status_index(&visual.statuses, .Shield)
			testing.expect(t, has_shield)
			testing.expect_value(t, visual.statuses.items[index].potency, i32(2))
			// The application is visible before this pulse's status tick.
			testing.expect_value(t, visual.statuses.items[index].remaining_pulses, i32(3))
			testing.expect_value(t, visual.position, presentation_position({3, 2}))
		}
		if cue.kind == .Pulse_Advanced {
			pulse_seen = true
			index, has_shield := game.status_index(&visual.statuses, .Shield)
			testing.expect(t, has_shield)
			testing.expect_value(t, visual.statuses.items[index].remaining_pulses, i32(2))
		}
	}
	testing.expect(t, shield_seen && movement_seen && pulse_seen)
	testing.expect_value(t, visual.position, presentation_position(room.enemies[0].position))
	testing.expect_value(t, visual.statuses, room.enemies[0].statuses)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)

	bolt, card_created := game.create_temporary_card(&player.deck, .Arc_Bolt)
	testing.expect(t, card_created)
	before = capture_room_presentation(&room)
	play := game.play_card(&room, bolt.id, game.entity_target(ally))
	testing.expect(t, game.card_play_was_committed(play.result))
	testing.expect_value(t, play.action_report.damage_absorbed, i32(2))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	absorption_seen := false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		if cue.kind == .Damage_Absorbed && cue.event.target == ally {
			absorption_seen = true
			testing.expect_value(t, cue.event.amount, i32(2))
		}
		finish_encounter_test_cue(t, &timeline)
	}
	visual, found = presentation_actor(&timeline, ally)
	testing.expect(t, found && absorption_seen)
	testing.expect_value(t, visual.health, i32(8))
	_, shielded = game.status_index(&visual.statuses, .Shield)
	testing.expect(t, !shielded)
	testing.expect_value(t, visual.statuses, room.enemies[0].statuses)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_boss_snapshot_changes_phase_only_at_pulse_boundary_after_announced_charge :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{{position = {3, 1}, health = 20, attack = 2, archetype = .Demolitionist}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:], encounter_kind = .Demolitionist})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	room.enemies[0].health = 12
	room.enemies[0].boss_cycle = 1
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	game.plan_enemy_intents(&room)
	advance_presentation_test_clock(t, &room, 4)
	testing.expect_value(t, room.enemies[0].intent.kind, game.Enemy_Intent_Kind.Charge)
	bolt, card_created := game.create_temporary_card(&player.deck, .Arc_Bolt)
	testing.expect(t, card_created)
	boss := game.enemy_entity(room.enemies[0].id)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, bolt.id, game.entity_target(boss))
	testing.expect(t, game.card_play_was_committed(play.result))
	advance_presentation_test_clock(t, &room, 1)
	testing.expect_value(t, room.enemies[0].health, i32(10))
	testing.expect_value(t, room.enemies[0].boss_phase, i32(2))
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	visual, found := presentation_actor(&timeline, boss)
	testing.expect(t, found)
	testing.expect_value(t, visual.boss_phase, i32(1))
	testing.expect_value(t, visual.health, i32(12))
	damage_seen, charge_seen, phase_changed := false, false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		testing.expect_value(t, visual.boss_phase, i32(2) if phase_changed else i32(1))
		if cue.kind == .Pulse_Advanced {
			testing.expect(t, damage_seen && charge_seen)
			// The phase label updates when the boundary cue starts, not when
			// the earlier damage cue first shows health below half.
			update_event_timeline(&timeline, cue.duration*0.5)
			testing.expect_value(t, visual.boss_phase, i32(2))
			phase_changed = true
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Damage && cue.event.target == boss {
			damage_seen = true
			testing.expect_value(t, visual.health, i32(10))
			testing.expect_value(t, visual.boss_phase, i32(1))
		}
		if cue.kind == .Move && cue.event.target == boss {
			charge_seen = true
			testing.expect_value(t, visual.position, presentation_position({2, 1}))
			testing.expect_value(t, visual.boss_phase, i32(1))
		}
	}
	testing.expect(t, phase_changed)
	testing.expect_value(t, visual.boss_phase, room.enemies[0].boss_phase)
	testing.expect_value(t, visual.health, room.enemies[0].health)
	testing.expect_value(t, timeline.view.player.health, player.health)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_furnace_warning_snapshot_and_trigger_precede_damage_and_restart_countdown :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{{position = {7, 4}, health = 20, attack = 1}}
	modifier := encounter_presentation_test_modifier()
	room, ok := game.create_room(&data, &player, {enemies = enemies[:], encounter_kind = .Assault, modifier = modifier})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	room.enemies[0].recovery_pulses = 100
	game.plan_enemy_intents(&room)
	before := capture_room_presentation(&room)
	testing.expect_value(t, before.modifier, modifier)
	testing.expect_value(t, before.encounter_kind, game.Encounter_Kind.Assault)
	testing.expect_value(t, game.room_modifier_pulses_remaining(&before.modifier, before.pulse_count), 2)
	testing.expect(t, game.room_modifier_warning_active(&before.modifier, before.pulse_count))
	game.try_move_player(&room, .East)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	testing.expect_value(t, game.room_modifier_pulses_remaining(&timeline.view.modifier, timeline.view.pulse_count), 2)
	testing.expect(t, update_event_timeline(&timeline, 1000))
	testing.expect_value(t, game.room_modifier_pulses_remaining(&timeline.view.modifier, timeline.view.pulse_count), 1)
	testing.expect_value(t, timeline.view.player.health, i32(20))
	testing.expect_value(t, timeline.update_failures, 0)

	before = capture_room_presentation(&room)
	game.try_move_player(&room, .South)
	advance_presentation_test_clock(t, &room, 1)
	testing.expect_value(t, player.position, grid.Position{2, 2})
	testing.expect_value(t, player.health, i32(17))
	testing.expect_value(t, room.modifier.activation_pulse, u64(6))
	after = capture_room_presentation(&room)
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	testing.expect_value(t, timeline.view.modifier.activation_pulse, u64(2))
	testing.expect_value(t, timeline.view.player.health, i32(20))
	hazard_seen, damage_seen := false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		if cue.kind == .Room_Hazard_Triggered {
			testing.expect(t, !damage_seen)
			testing.expect_value(t, cue.event.amount, game.ROOM_HAZARD_DAMAGE)
			testing.expect_value(t, cue.event.from_position, modifier.cells[0])
			testing.expect_value(t, cue.event.to_position, modifier.cells[modifier.cell_count-1])
			update_event_timeline(&timeline, cue.duration*0.5)
			testing.expect_value(t, timeline.view.player.health, i32(20))
			testing.expect_value(t, timeline.view.modifier.activation_pulse, u64(6))
			testing.expect_value(t, timeline.view.modifier.cells, modifier.cells)
			hazard_seen = true
		}
		if cue.kind == .Damage && cue.event.target == game.PLAYER_ENTITY {
			testing.expect(t, hazard_seen)
			damage_seen = true
		}
		finish_encounter_test_cue(t, &timeline)
	}
	testing.expect(t, hazard_seen && damage_seen)
	testing.expect_value(t, timeline.view.player.health, player.health)
	testing.expect_value(t, timeline.view.modifier, room.modifier)
	testing.expect_value(t, timeline.view.pulse_count, room.pulse_count)
	testing.expect_value(t, game.room_modifier_pulses_remaining(&timeline.view.modifier, timeline.view.pulse_count), 4)
	testing.expect(t, !game.room_modifier_warning_active(&timeline.view.modifier, timeline.view.pulse_count))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
	// Two further real commands advance through cooldown into the next warning.
	for step in 0..<2 {
		before = capture_room_presentation(&room)
		game.wait_player_turn(&room)
		advance_presentation_test_clock(t, &room, 1)
		after = capture_room_presentation(&room)
		testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
		testing.expect(t, update_event_timeline(&timeline, 1000))
		testing.expect_value(t, game.room_modifier_warning_active(&timeline.view.modifier, timeline.view.pulse_count), step == 1)
		testing.expect_value(t, timeline.view.modifier, room.modifier)
		testing.expect_value(t, timeline.update_failures, 0)
	}
}

@(test)
test_furnace_snapshot_disarms_after_final_player_kill_without_a_pulse_event :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{{position = {2, 1}, health = 1, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:], modifier = encounter_presentation_test_modifier()})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	game.try_move_player(&room, .East)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect_value(t, room.modifier.activation_pulse, u64(0))
	testing.expect_value(t, room.pulse_count, u64(0))
	for event in room.recent_events.events[:room.recent_events.count] {
		testing.expect(t, event.kind != .Pulse_Advanced)
	}
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	testing.expect_value(t, timeline.view.modifier.activation_pulse, u64(2))
	testing.expect(t, update_event_timeline(&timeline, 1000))
	testing.expect_value(t, timeline.view.phase, game.Room_Phase.Loot)
	testing.expect_value(t, timeline.view.modifier.activation_pulse, u64(0))
	testing.expect(t, !game.room_modifier_warning_active(&timeline.view.modifier, timeline.view.pulse_count))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_furnace_death_cues_preserve_defeat_and_disarm_when_last_enemy_dies_too :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{{position = {3, 2}, health = 1, attack = 1}}
	modifier := encounter_presentation_test_modifier()
	modifier.activation_pulse = 1
	room, ok := game.create_room(&data, &player, {enemies = enemies[:], modifier = modifier})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	player.position = {2, 2}
	player.health = 1
	game.plan_enemy_intents(&room)
	before := capture_room_presentation(&room)
	game.wait_player_turn(&room)
		advance_presentation_test_clock(t, &room, 1)
	testing.expect_value(t, room.phase, game.Room_Phase.Defeat)
	testing.expect_value(t, len(room.enemies), 0)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	player_defeated := false
	enemy_defeated := false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Defeat && cue.event.target == game.PLAYER_ENTITY {
			player_defeated = true
		}
		if cue.kind == .Defeat && cue.event.target.kind == .Enemy {
			enemy_defeated = true
		}
		if player_defeated {
			testing.expect_value(t, timeline.view.phase, game.Room_Phase.Defeat)
			testing.expect_value(t, timeline.view.modifier.activation_pulse, u64(0))
		}
	}
	testing.expect(t, player_defeated && enemy_defeated)
	testing.expect_value(t, timeline.view.player.health, i32(0))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}
