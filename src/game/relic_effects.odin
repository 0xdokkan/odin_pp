package game

relic_combat_is_active :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat &&
	       room.player.health > 0 && room.player.relics.combat.started
}

begin_room_relics :: proc(room: ^Room) {
	if room == nil || room.player == nil {
		return
	}
	room.player.relics.combat = {started = room.phase == .Combat}
	apply_entry_relic(room)
}

// Also used for the starting relic picked after the first room was constructed.
apply_entry_relic :: proc(room: ^Room) {
	if !relic_combat_is_active(room) || room.pulse_count != 0 ||
	   room.player.relics.combat.entry_used || !player_has_relic(room.player, .Guard_Sigil) {
		return
	}
	room.player.relics.combat.entry_used = true
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Player)
	added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, 2, 3))
	assert(added)
	report := resolve_action(room, &action)
	append_event_log(&room.recent_events, &report.events)
}

// Called only after a validated status effect is about to be committed.
relic_poison_potency :: proc(room: ^Room, source: Entity_Ref, effect: Effect) -> i32 {
	if !relic_combat_is_active(room) || source != PLAYER_ENTITY ||
	   effect.target.kind != .Enemy || effect.status != .Poison ||
	   !player_has_relic(room.player, .Venom_Vial) || room.player.relics.combat.poison_used {
		return effect.amount
	}
	room.player.relics.combat.poison_used = true
	return effect.amount+1 if effect.amount < max(i32) else effect.amount
}

// Runs before the normal reaction dispatcher. The bonus is an ordinary System
// action; its events join this chain once, and cannot trigger another push.
apply_action_relics :: proc(room: ^Room, action: ^Action, report: ^Action_Report) {
	if !relic_combat_is_active(room) || action == nil || report == nil ||
	   !report.accepted || action.source != PLAYER_ENTITY ||
	   !player_has_relic(room.player, .Iron_Knuckle) {
		return
	}
	state := &room.player.relics.combat
	if state.push_used && state.push_pulse == room.pulse_count {
		return
	}
	pushed := false
	for event in report.events.events[:report.events.count] {
		if event.kind == .Moved && event.source == PLAYER_ENTITY &&
		   (event.target.kind == .Enemy || event.target.kind == .Object) &&
		   event.from_position != event.to_position {
			pushed = true
			break
		}
	}
	if !pushed {
		return
	}
	state.push_used = true
	state.push_pulse = room.pulse_count
	bonus := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Player)
	added := add_effect(&bonus, apply_status_effect(PLAYER_ENTITY, .Shield, 1, 2))
	assert(added)
	bonus_report := resolve_action_once(room, &bonus)
	if bonus_report.accepted {
		merge_reaction_action_report(report, &bonus_report)
		append_event_log(&report.events, &bonus_report.events)
	}
}

apply_card_relics :: proc(room: ^Room, destination: Card_Zone, played_report: ^Action_Report) {
	if !relic_combat_is_active(room) {
		return
	}
	state := &room.player.relics.combat
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Player)
	if destination == .Exhaust && player_has_relic(room.player, .Ash_Bookmark) &&
	   !state.exhaust_used {
		state.exhaust_used = true
		added := add_effect(&action, draw_cards_effect(1))
		assert(added)
	}
	if played_report != nil && player_has_relic(room.player, .Swift_Soles) &&
	   !state.movement_used {
		for event in played_report.events.events[:played_report.events.count] {
			if event.kind == .Moved && event.source == PLAYER_ENTITY &&
			   event.target == PLAYER_ENTITY && event.from_position != event.to_position {
				state.movement_used = true
				added := add_effect(&action, gain_energy_effect(1))
				assert(added)
				break
			}
		}
	}
	if action.effect_count > 0 {
		report := resolve_action(room, &action)
		append_event_log(&room.recent_events, &report.events)
	}
}

// A room which started without enemies never pays this reward. The once-only
// flag is consumed even at full HP, so acquiring or damaging later cannot farm it.
apply_room_clear_relics :: proc(room: ^Room) -> (report: Action_Report) {
	if room == nil || room.player == nil || room.phase != .Loot ||
	   room.player.health <= 0 || !room.player.relics.combat.started ||
	   room.player.relics.combat.clear_used {
		return
	}
	room.player.relics.combat.clear_used = true
	if !player_has_relic(room.player, .Mending_Thread) {
		return
	}
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Player)
	added := add_effect(&action, heal_effect(PLAYER_ENTITY, 2))
	assert(added)
	return resolve_action(room, &action)
}

append_room_clear_relic :: proc(room: ^Room, report: ^Action_Report) {
	bonus := apply_room_clear_relics(room)
	if bonus.accepted {
		merge_reaction_action_report(report, &bonus)
		append_event_log(&report.events, &bonus.events)
		report.reactions_triggered += bonus.reactions_triggered
		report.reactions_dropped += bonus.reactions_dropped
		report.reaction_events_processed += bonus.reaction_events_processed
		report.reaction_events_dropped += bonus.reaction_events_dropped
		report.reaction_limit_reached = report.reaction_limit_reached || bonus.reaction_limit_reached
	}
}
