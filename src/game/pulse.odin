package game

Pulse_Report :: struct {
	advanced:          bool,
	enemy_actions:     int,
	status_ticks:      int,
	damage_dealt:      i32,
	damage_absorbed:   i32,
	enemies_defeated:  int,
	objects_destroyed: int,
	cards_drawn:       int,
	cards_discarded:   int,
	cards_created:     int,
	reactions_triggered:       int,
	reactions_dropped:         int,
	reaction_events_processed: int,
	reaction_events_dropped:   int,
	reaction_limit_reached:    bool,
	reaction_bindings_removed: int,
	reaction_bindings_added:   int,
	combat_ended:      bool,
	player_defeated:   bool,
	energy_restored:   i32,
	energy_wasted:     i32,
	events:            Event_Log,
}

merge_action_report :: proc(pulse: ^Pulse_Report, action: ^Action_Report) {
	if pulse == nil || action == nil || !action.accepted {
		return
	}
	pulse.damage_dealt += action.damage_dealt
	pulse.damage_absorbed += action.damage_absorbed
	pulse.enemies_defeated += action.enemies_defeated
	pulse.objects_destroyed += action.objects_destroyed
	pulse.cards_drawn += action.cards_drawn
	pulse.cards_discarded += action.cards_discarded
	pulse.cards_created += action.cards_created
	pulse.reactions_triggered += action.reactions_triggered
	pulse.reactions_dropped += action.reactions_dropped
	pulse.reaction_events_processed += action.reaction_events_processed
	pulse.reaction_events_dropped += action.reaction_events_dropped
	pulse.reaction_limit_reached = pulse.reaction_limit_reached || action.reaction_limit_reached
	pulse.reaction_bindings_removed += action.reaction_bindings_removed
	pulse.reaction_bindings_added += action.reaction_bindings_added
	pulse.combat_ended = pulse.combat_ended || action.combat_ended
	pulse.player_defeated = pulse.player_defeated || action.player_defeated
	append_event_log(&pulse.events, &action.events)
}

expire_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	removed, ok := remove_status(room, entity, kind)
	assert(ok)
	record_event(&pulse.events, {
		kind = .Status_Expired,
		source = SYSTEM_ENTITY,
		target = entity,
		amount = removed.potency,
		status = removed.kind,
	})
}

tick_status_kind :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, pulse: ^Pulse_Report) {
	status, found := status_for_entity(room, entity, kind)
	if !found {
		return
	}
	pulse.status_ticks += 1

	if kind == .Poison {
		potency := status.potency
		action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(entity), .Entity)
		added := add_effect(&action, status_damage_effect(entity, potency, .Poison))
		assert(added)
		report := resolve_action(room, &action)
		assert(report.accepted)
		merge_action_report(pulse, &report)
		if !entity_exists(room, entity) {
			return
		}
	}

	status, found = status_for_entity(room, entity, kind)
	if !found {
		return
	}
	status.remaining_pulses -= 1
	if status.remaining_pulses <= 0 {
		expire_status(room, entity, kind, pulse)
	}
}

tick_entity_statuses :: proc(room: ^Room, entity: Entity_Ref, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	status_order := [?]Status_Kind{.Poison, .Shield, .Thorns, .Afterimage}
	for kind in status_order {
		if room.phase != .Combat || !entity_exists(room, entity) {
			return
		}
		tick_status_kind(room, entity, kind, pulse)
	}
}

tick_all_statuses :: proc(room: ^Room, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	if room.phase != .Combat {
		return
	}

	tick_entity_statuses(room, PLAYER_ENTITY, pulse)
	enemy_index := 0
	for enemy_index < len(room.enemies) && room.phase == .Combat {
		enemy_id := room.enemies[enemy_index].id
		tick_entity_statuses(room, enemy_entity(enemy_id), pulse)
		_, still_present := enemy_index_by_id(room, enemy_id)
		if still_present {
			enemy_index += 1
		}
	}
}

advance_combat_pulse :: proc(room: ^Room) -> (pulse: Pulse_Report) {
	if room == nil || room.phase != .Combat {
		return
	}
	pulse.advanced = true
	statuses_advanced := false
	resolve_due_explosives(room, &pulse)
	resolve_due_room_modifier(room, &pulse)
	resolve_enemy_intents(room, &pulse)
	if room.phase == .Combat {
		tick_all_statuses(room, &pulse)
		statuses_advanced = true
	}
	if room.phase == .Combat {
		tick_reaction_bindings(room, &pulse)
	}
	pulse.combat_ended = pulse.combat_ended || room.phase == .Loot
	pulse.player_defeated = pulse.player_defeated || room.phase == .Defeat
	if room.phase == .Combat {
		regen := room.player.deck.rules.energy_regen_per_pulse
		pulse.energy_restored = restore_deck_energy_after_pulse(&room.player.deck)
		pulse.energy_wasted = max(0, regen-pulse.energy_restored)
	}
	room.pulse_count += 1
	disarm_explosives_after_combat(room, &pulse.events)
	disarm_room_modifier_after_combat(room)
	if room.phase == .Combat {
		plan_enemy_intents(room)
	} else {
		clear_enemy_intents(room)
	}
	record_event(&pulse.events, {
		kind = .Pulse_Advanced,
		source = SYSTEM_ENTITY,
		target = PLAYER_ENTITY,
		pulse_count = room.pulse_count,
		energy = room.player.deck.energy,
		energy_restored = pulse.energy_restored,
		energy_wasted = pulse.energy_wasted,
		statuses_advanced = statuses_advanced,
	})
	return
}
