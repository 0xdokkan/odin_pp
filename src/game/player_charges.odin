package game

import grid "../engine/grid"

// The player's charges (status.odin): four cards load stacks on him that are
// spent one at a time, until they run out or the room ends (create_room clears
// them with the rest of his statuses). RIFLESSO (Deflect) turns the next enemy
// blow that would hit him back at its attacker; FRECCE (Feretro) are arrows
// loosed with Ctrl and a click; DESTINO (Dado del Destino) and LAMA (Lama
// Velenosa) load his next bumps.

// Lama Velenosa: the Veleno each loaded bump leaves.
VENOM_BLADE_POISON :: i32(2)
// Dado del Destino: the bumps one play loads; a new play loads them back to
// this, never above.
FATE_DICE_CHARGES :: i32(3)
// Feretro: an arrow's damage, then one status of these at random (the
// player's dice): Veleno 2, Bruciatura 1 or Rallentamento 1.
COFFIN_ARROW_DAMAGE :: i32(1)
COFFIN_ARROW_STATUSES :: [3]Status_Kind{.Poison, .Burn, .Slow}
COFFIN_ARROW_STACKS :: [3]i32{2, 1, 1}

// What a loaded bump's face does (Dado del Destino): 1, 2 and 3 leave Veleno,
// Bruciatura and Rallentamento of as many stacks; 4 steals the life the bump
// takes; 5 makes the bump critical; 6 and over kill outright, but a boss or a
// miniboss only takes a critical.
Fate_Outcome :: enum u8 {Poison, Burn, Slow, Lifesteal, Critical, Lethal}

@(private)
fate_outcome :: proc(face: i32, boss: bool) -> Fate_Outcome {
	switch {
	case face <= 1: return .Poison
	case face == 2: return .Burn
	case face == 3: return .Slow
	case face == 4: return .Lifesteal
	case face == 5 || boss: return .Critical
	}
	return .Lethal
}

// The boss (the Demolitionist) and the miniboss (the Custodian): no die kills
// them outright.
@(private)
enemy_is_boss :: proc(archetype: Enemy_Archetype) -> bool {
	return archetype == .Demolitionist || archetype == .Custodian
}

// The player's charges of `kind` left (0 without any).
player_charges :: proc(room: ^Room, kind: Status_Kind) -> i32 {
	status, found := status_for_entity(room, PLAYER_ENTITY, kind)
	return status.potency if found else 0
}

// One charge of the player's `kind` spent; the last one ends it, with a
// Status_Expired in `events` so the board drops its chip. False without one.
@(private)
spend_player_charge :: proc(room: ^Room, kind: Status_Kind, events: ^Event_Log) -> bool {
	status, found := status_for_entity(room, PLAYER_ENTITY, kind)
	if !found { return false }
	status.potency -= 1
	if status.potency > 0 { return true }
	removed, ok := remove_status(room, PLAYER_ENTITY, kind)
	assert(ok)
	record_event(events, {kind = .Status_Expired, source = SYSTEM_ENTITY, target = PLAYER_ENTITY,
		amount = removed.potency, status = removed.kind})
	return true
}

// The die the Dado del Destino's bumps roll: the one of the last card played
// (Tactical_State.fate_sides), a d4 when none was.
player_fate_sides :: proc(room: ^Room) -> i32 {
	sides := room.player.tactical.fate_sides
	return sides if dice_sides_are_valid(sides) else DICE_LADDER[0]
}

// RIFLESSO: an enemy blow that would hit the player (an Attack or the blow of a
// Charge, a shot or a swing; `origin` the attacker's cell as it strikes) goes
// back at its attacker. The player takes nothing and his Shield is not touched;
// the attacker takes what the player would have taken (player_blow_damage) and
// a charge is spent. Bombs, explosions, traps, hazards and the statuses' bites
// are no blow and never come here; a player sunk in his shadow is out of
// reach and spends nothing. False when the blow goes on to hit him.
deflect_enemy_blow :: proc(room: ^Room, source: Entity_Ref, origin: grid.Position, blow: ^Enemy_Intent, ranged: bool,
	pulse: ^Pulse_Report) -> bool {
	if room == nil || room.player == nil || pulse == nil || blow == nil || source.kind != .Enemy ||
	   blow.threatened_cell_count <= 0 || tactical_player_intangible(room) || (player_charges(room, .Deflect) <= 0 && !ride_deflects(room)) { return false }
	damage := player_blow_damage(room, blow.damage)
	first := pulse.events.count
	// The blow itself, struck as it was aimed: the board shows it reach him.
	record_event(&pulse.events, {kind = .Attack_Deflected, source = source, target = PLAYER_ENTITY, amount = damage, status = .Deflect})
	mark_attack_events(&pulse.events, first, source, PLAYER_ENTITY, origin, blow.threatened_cells[0],
		blow.threatened_cells[:blow.threatened_cell_count], ranged)
	// The Stegosauro keeps no charge to spend.
	if player_charges(room, .Deflect) > 0 { wear_status_stack(room, PLAYER_ENTITY, .Deflect, pulse) }
	// And back (EVENT_REFLECTED_BIT): the attacker's own bolt flying home, or a
	// swing of the player's at the attacker.
	answer := make_action(.Trigger, PLAYER_ENTITY, entity_target(source), .Opponent)
	added := add_effect(&answer, damage_effect(source, damage))
	assert(added)
	report := resolve_action(room, &answer)
	if report.accepted {
		mark_attack_events(&report.events, 0, PLAYER_ENTITY, source, room.player.position, origin, {}, ranged, true)
		merge_action_report(pulse, &report)
	}
	return true
}

// The damage the player's own blows dealt `target` in `report` (no status's bite).
@(private)
player_damage_dealt :: proc(report: ^Action_Report, target: Entity_Ref) -> (dealt: i32) {
	for event in report.events.events[:report.events.count] {
		if event.kind == .Damaged && event.source == PLAYER_ENTITY && event.target == target && !event.has_status_cause {
			dealt += event.amount
		}
	}
	return
}

// Where a blow's own events end in `log`: after its last marked event on
// `target` (game.mark_attack_events) and the Shield that blow broke. The
// count when the blow has none.
@(private = "file")
player_blow_events_end :: proc(log: ^Event_Log, target: Entity_Ref) -> int {
	end := -1
	for event, index in log.events[:log.count] {
		if event.source == PLAYER_ENTITY && event.target == target && event_is_attack(event) { end = index+1 }
	}
	if end < 0 { return log.count }
	if end < log.count && log.events[end].kind == .Status_Removed && log.events[end].status == .Shield &&
	   log.events[end].target == target { end += 1 }
	return end
}

// The player's bump on room.enemies[enemy_index], aimed at `aim` (`rule` its
// target rule: a straight bump's, a diagonal's): his basic blow, twice as hard
// when critical, with whatever his charges load it with. Lama Velenosa adds its
// Veleno; the Dado del Destino rolls its die at the hit (fate_outcome) and
// shows it there (Fate_Rolled, right after the blow). Its events go to
// room.recent_events; only a bump that strikes spends its charges, its die and
// a use of his weapon. Straight and diagonal bumps both come here.
player_bump :: proc(room: ^Room, enemy_index: int, aim: grid.Position, rule: Target_Rule, critical: bool) -> bool {
	enemy := room.enemies[enemy_index]
	ref := enemy_entity(enemy.id)
	critical := critical
	venom := player_charges(room, .Venom_Blade) > 0
	fated := player_charges(room, .Fate) > 0
	staged_dice := room.player.dice
	roll: Dice_Roll
	outcome: Fate_Outcome
	if fated {
		rolled: bool
		roll, rolled = roll_dice_pool(&staged_dice, 1, player_fate_sides(room))
		fated = rolled
		// A critical face doubles the bump once: one already struck on the
		// tick is no more critical for it.
		if fated {
			outcome = fate_outcome(roll.total, enemy_is_boss(enemy.archetype))
			critical = critical || outcome == .Critical
		}
	}
	damage := player_basic_attack_damage(room.player)
	if critical { damage = critical_bump_damage(damage) }
	// The Giganotosauro's bite: a small foe falls, the rest take the great blow.
	if bite := giga_bite_damage(room, enemy); bite > 0 { damage = max(damage, bite) }
	if fated && outcome == .Lethal {
		// Whatever guards it, it falls.
		guard: i32
		if shield, shielded := status_for_entity(room, ref, .Shield); shielded { guard = shield.potency }
		damage = max(damage, i32(min(i64(max(i32)), i64(enemy.health)+i64(guard))))
	}
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(ref), rule)
	added := add_effect(&action, damage_effect(ref, damage))
	assert(added)
	if venom {
		added = add_effect(&action, apply_status_effect(ref, .Poison, VENOM_BLADE_POISON, 0))
		assert(added)
	}
	// The Velociraptor's claws leave a stack of Sanguinamento.
	if ride_is(room, .Raptor) {
		added = add_effect(&action, apply_status_effect(ref, .Bleed, 1, 0))
		assert(added)
	}
	if fated && outcome <= .Slow {
		kinds := [3]Status_Kind{.Poison, .Burn, .Slow}
		added = add_effect(&action, apply_status_effect(ref, kinds[int(outcome)], roll.total, 0))
		assert(added)
	}
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	consume_equipped_weapon_use(room.player)
	mark_attack_events(&report.events, 0, PLAYER_ENTITY, ref, room.player.position, aim, {}, false)
	if critical { mark_critical_events(&report.events) }
	// The life a 4 steals: the blow's own damage to the foe, back to him.
	cure: Action_Report
	if fated && outcome == .Lifesteal {
		if stolen := player_damage_dealt(&report, ref); stolen > 0 {
			heal := make_action(.Trigger, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
			added = add_effect(&heal, heal_effect(PLAYER_ENTITY, stolen))
			assert(added)
			cure = resolve_action(room, &heal)
		}
	}
	// The die shows as the blow lands: its event follows the blow's own.
	shown := player_blow_events_end(&report.events, ref) if fated else -1
	for event, index in report.events.events[:report.events.count] {
		if index == shown { record_event(room.recent_events, player_fate_event(roll, outcome, ref, aim, room, &cure)) }
		record_event(room.recent_events, event)
	}
	if shown == report.events.count { record_event(room.recent_events, player_fate_event(roll, outcome, ref, aim, room, &cure)) }
	room.recent_events.dropped_count += report.events.dropped_count
	if cure.accepted { append_event_log(room.recent_events, &cure.events) }
	if fated {
		room.player.dice = staged_dice
		spend_player_charge(room, .Fate, room.recent_events)
	}
	if venom { spend_player_charge(room, .Venom_Blade, room.recent_events) }
	if room.player.tactical.dinosaur_remaining > 0 && room.phase == .Combat && entity_exists(room, ref) {
		step := grid.Position{sign(enemy.position.x-room.player.position.x), sign(enemy.position.y-room.player.position.y)}
		charge := make_action(.Trigger, PLAYER_ENTITY, entity_target(ref), .Opponent)
		add_effect(&charge, move_effect(ref, add_position(enemy.position, step)))
		pushed := resolve_action(room, &charge)
		if pushed.accepted { append_event_log(room.recent_events, &pushed.events) }
	}
	return true
}

// The Dado del Destino's event for a bump on `target`: the roll, what it did
// (in `duration`) and its stacks or the life it gave back.
@(private = "file")
player_fate_event :: proc(roll: Dice_Roll, outcome: Fate_Outcome, target: Entity_Ref, aim: grid.Position, room: ^Room,
	cure: ^Action_Report) -> Game_Event {
	amount: i32
	#partial switch outcome {
	case .Poison, .Burn, .Slow: amount = roll.total
	case .Lifesteal: amount = cure.healing_done if cure.accepted else 0
	}
	return {kind = .Fate_Rolled, source = PLAYER_ENTITY, target = target, dice_roll = roll, amount = amount,
		duration = i32(outcome), from_position = room.player.position, to_position = aim, card_definition = .Fate_Dice}
}

// A foe the player's arrows reach now: on the board, in his sight and in his
// line of fire, the line the game's shots and cards trace (walls, obstacles,
// opaque objects and closed corners stop it; other fighters do not).
player_arrow_target_is_valid :: proc(room: ^Room, target: Entity_Ref) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || target.kind != .Enemy || enemy_is_out_of_play(room, target.id) { return false }
	position, found := entity_position(room, target)
	return found && position != room.player.position && tactical_cell_visible(room, position) &&
	       shape_cell_has_clear_path(room, room.player.position, position)
}

// FERETRO: one arrow loosed at `target`, a foe the arrows reach. It is the
// player's action, as a bump is: a second of the window, his poison bites,
// he turns to face it. One damage and, by the player's dice, Veleno 2,
// Bruciatura 1 or Rallentamento 1.
shoot_player_arrow :: proc(room: ^Room, target: Entity_Ref) -> Action_Result {
	// Behind his eyes he shoots the AK, never an arrow (first_person.odin).
	if room == nil || room.player == nil || room.phase != .Combat || !tactical_allows_action(room) ||
	   tactical_first_person_active(room) {
		return .Invalid_Phase
	}
	if player_charges(room, .Arrows) <= 0 || !player_arrow_target_is_valid(room, target) { return .Blocked }
	aim, _ := entity_position(room, target)
	staged_dice := room.player.dice
	pick, rolled := roll_die(&staged_dice, i32(len(COFFIN_ARROW_STATUSES)))
	if !rolled { return .Blocked }
	statuses, stacks := COFFIN_ARROW_STATUSES, COFFIN_ARROW_STACKS
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
	added := add_effect(&action, damage_effect(target, COFFIN_ARROW_DAMAGE))
	assert(added)
	added = add_effect(&action, apply_status_effect(target, statuses[pick-1], stacks[pick-1], 0))
	assert(added)
	clear_event_log(room.recent_events)
	report := resolve_action(room, &action)
	if !report.accepted { return .Blocked }
	room.player.dice = staged_dice
	from := room.player.position
	mark_attack_events(&report.events, 0, PLAYER_ENTITY, target, from, aim, {}, true)
	append_event_log(room.recent_events, &report.events)
	spend_player_charge(room, .Arrows, room.recent_events)
	dx, dy := aim.x-from.x, aim.y-from.y
	if abs(dx) > abs(dy) { room.player.tactical.facing = .East if dx > 0 else .West }
	else { room.player.tactical.facing = .South if dy > 0 else .North }
	outcome := finish_player_combat_command(room, TACTICAL_ARROW_SECONDS)
	switch outcome {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Attacked
}

// Lama Velenosa rolls its die as it is played, shown as any dice card's roll
// (Dice_Rolled, before the charges it loads): the face is the bumps it
// poisons. The Dado del Destino rolls nothing yet: its bumps will roll the die
// of its level.
@(private)
resolve_loading_card :: proc(room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action) -> (report: Action_Report) {
	if compiled == nil || (instance.definition_id != .Venom_Blade && instance.definition_id != .Fate_Dice) ||
	   compiled.kind != .Card || compiled.source != PLAYER_ENTITY || compiled.target != target ||
	   compiled.effect_count != 1 || compiled.effects[0].kind != .Apply_Status { return }
	action := compiled^
	staged_dice := room.player.dice
	roll: Dice_Roll
	venom := instance.definition_id == .Venom_Blade
	if venom {
		rolled: bool
		roll, rolled = roll_card_dice(&staged_dice, instance)
		if !rolled { return }
		action.effects[0].amount = roll.total
	}
	tactical_critical_scale(room, &action)
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	if venom {
		room.player.dice = staged_dice
		record_report_event(&report, spell_dice_event(instance, origin, origin, PLAYER_ENTITY, roll))
	} else {
		room.player.tactical.fate_sides = card_die_sides(instance.definition_id, instance.upgrade_level)
	}
	merge_spell_hit_report(&report, &hit)
	return
}
