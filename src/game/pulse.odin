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

@(private)
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

@(private = "file")
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

// A status that deals its stacks as damage: a System hit with the status as
// its cause. A Shield absorbs it and the presentation shows it as any blow;
// the player's defense never takes from it (apply_damage_effect).
@(private = "file")
status_damage_tick :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, pulse: ^Pulse_Report) {
	status, found := status_for_entity(room, entity, kind)
	if !found {
		return
	}
	pulse.status_ticks += 1
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(entity), .Entity)
	added := add_effect(&action, status_damage_effect(entity, status.potency, kind))
	assert(added)
	report := resolve_action(room, &action)
	assert(report.accepted)
	merge_action_report(pulse, &report)
}

// One stack less; the last one ends the status.
@(private)
wear_status_stack :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, pulse: ^Pulse_Report) {
	status, found := status_for_entity(room, entity, kind)
	if !found {
		return
	}
	status.potency -= 1
	if status.potency <= 0 {
		expire_status(room, entity, kind, pulse)
	}
}

// Poison bites its bearer's own actions: damage equal to its stacks, then a
// stack less. Nothing reaches the player sunk in his shadow, and the shadow's
// own steps are no action: there it neither bites nor wears.
@(private)
tick_poison_on_action :: proc(room: ^Room, entity: Entity_Ref, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	if room.phase != .Combat || !entity_exists(room, entity) ||
	   (entity == PLAYER_ENTITY && tactical_player_intangible(room)) {
		return
	}
	if _, poisoned := status_for_entity(room, entity, .Poison); !poisoned {
		return
	}
	status_damage_tick(room, entity, .Poison, pulse)
	if room.phase == .Combat && entity_exists(room, entity) {
		wear_status_stack(room, entity, .Poison, pulse)
	}
}

// After an enemy carries out an intent (any kind, hit, miss or blocked): its
// poison bites, and the slow that held this intent wears a stack.
@(private)
finish_enemy_action :: proc(room: ^Room, enemy: Entity_Ref, slowed: bool, pulse: ^Pulse_Report) {
	tick_poison_on_action(room, enemy, pulse)
	if slowed && room.phase == .Combat && entity_exists(room, enemy) {
		wear_status_stack(room, enemy, .Slow, pulse)
	}
}

// Bruciatura: its stacks as damage; they never wear.
@(private)
burn_status :: proc(room: ^Room, entity: Entity_Ref, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	if room.phase != .Combat || !entity_exists(room, entity) {
		return
	}
	status_damage_tick(room, entity, .Burn, pulse)
}

@(private = "file")
tick_status_kind :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, pulse: ^Pulse_Report) {
	status, found := status_for_entity(room, entity, kind)
	if !found {
		return
	}
	switch kind {
	case .Poison, .Slow, .Deflect, .Arrows, .Fate, .Venom_Blade, .Bleed:
		// Worn by their bearer's actions (a charge: by its use), never by the clock.
		return
	case .Burn:
		// Burn bites at each new window (tactical_expire_window).
		return
	case .Shield, .Thorns, .Afterimage, .Stagger, .Survey:
	}
	pulse.status_ticks += 1
	status.remaining_pulses -= 1
	if status.remaining_pulses <= 0 {
		expire_status(room, entity, kind, pulse)
	}
}

@(private)
tick_entity_statuses :: proc(room: ^Room, entity: Entity_Ref, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	// Only timed statuses expire on world beats. Burn ticks at window expiry.
	status_order := [?]Status_Kind{.Shield, .Thorns, .Afterimage, .Stagger, .Survey}
	for kind in status_order {
		if room.phase != .Combat || !entity_exists(room, entity) {
			return
		}
		tick_status_kind(room, entity, kind, pulse)
	}
}

// The player, then every enemy in turn; an enemy that dies on its own tick
// leaves the next one in its place.
@(private)
tick_combatants :: proc(room: ^Room, pulse: ^Pulse_Report, tick: proc(room: ^Room, entity: Entity_Ref, pulse: ^Pulse_Report)) {
	assert(room != nil && pulse != nil)
	if room.phase != .Combat {
		return
	}

	tick(room, PLAYER_ENTITY, pulse)
	enemy_index := 0
	for enemy_index < len(room.enemies) && room.phase == .Combat {
		enemy_id := room.enemies[enemy_index].id
		tick(room, enemy_entity(enemy_id), pulse)
		_, still_present := enemy_index_by_id(room, enemy_id)
		if still_present {
			enemy_index += 1
		}
	}
}

@(private = "file")
tick_all_statuses :: proc(room: ^Room, pulse: ^Pulse_Report) {
	tick_combatants(room, pulse, tick_entity_statuses)
}

@(private)
finish_combat_pulse :: proc(room: ^Room, pulse: ^Pulse_Report) {
	pulse.advanced = true
	if room.phase == .Combat { tick_board_devices(room, pulse) }
	statuses_advanced := false
	if room.phase == .Combat {
		tick_all_statuses(room, pulse)
		statuses_advanced = true
	}
	if room.phase == .Combat {
		tick_reaction_bindings(room, pulse)
	}
	if room.phase == .Combat { expedition_finish_beat(room, pulse) }
	pulse.combat_ended = pulse.combat_ended || room.phase == .Loot
	pulse.player_defeated = pulse.player_defeated || room.phase == .Defeat
	// M7's world beat is one second. Energy needs its own cadence so a costly
	// spell does not automatically refund all the energy it just spent.
	if room.phase == .Combat && !room.player.tactical.config.expedition && (room.pulse_count+1)%3 == 0 {
		regen := room.player.deck.rules.energy_regen_per_pulse
		pulse.energy_restored = restore_deck_energy_after_pulse(&room.player.deck)
		pulse.energy_wasted = max(0, regen-pulse.energy_restored)
	}
	room.pulse_count += 1
	disarm_explosives_after_combat(room, &pulse.events)
	disarm_room_modifier_after_combat(room)
	disarm_board_devices_after_combat(room, &pulse.events)
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
