package game

import grid "../grid"

MAX_SPELL_TARGETS :: 3
SPELL_BOUNCE_RANGE :: 3

Spell_Path :: struct {
	targets: [MAX_SPELL_TARGETS]Entity_Ref,
	positions: [MAX_SPELL_TARGETS]grid.Position,
	count: int,
	error: Card_Compile_Error,
}

// Both paths are certain spatial queries. Fate's second target is conditional on
// a later committed six; querying or compiling never rolls the die.
query_spell_path :: proc(room: ^Room, instance: Card_Instance, target: Target) -> (path: Spell_Path) {
	path.error = .Invalid_Target
	if instance.definition_id != .Fate_Strike && instance.definition_id != .Chain_Lightning &&
	   instance.definition_id != .Sundering_Blow && instance.definition_id != .Prismatic_Barrage &&
	   instance.definition_id != .Twin_Venom {
		return
	}
	if room == nil || room.player == nil {
		path.error = .Invalid_Room
		return
	}
	definition, found := card_definition_by_id(instance.definition_id, tactical_enabled(room))
	if !found { return }
	request, has_request := card_target_request_from_target(room, definition, target)
	if !has_request { return }
	evaluation := evaluate_card_targeting(room, instance, request)
	path.error = evaluation.error
	if path.error != .None { return }
	if !evaluation.query.has_primary_target || evaluation.query.primary_target != target ||
	   target.kind != .Entity || target.entity.kind != .Enemy {
		path.error = .Invalid_Target
		return
	}
	path.targets[0] = target.entity
	path.positions[0] = evaluation.query.anchor
	path.count = 1
	if instance.definition_id != .Fate_Strike && instance.definition_id != .Chain_Lightning { return }
	maximum := 2 if instance.definition_id == .Fate_Strike else MAX_SPELL_TARGETS
	for path.count < maximum {
		origin := path.positions[path.count-1]
		best_id: u32
		best_distance := SPELL_BOUNCE_RANGE+1
		best_position: grid.Position
		for enemy in room.enemies {
			visited := false
			for entity in path.targets[:path.count] {
				visited = visited || entity.id == enemy.id
			}
			if visited || enemy.health <= 0 || !tactical_card_enemy_in_area(room, instance.definition_id, enemy.position) { continue }
			distance := int(abs(origin.x-enemy.position.x)+abs(origin.y-enemy.position.y))
			if distance <= 0 || distance > SPELL_BOUNCE_RANGE ||
			   !shape_cell_has_clear_path(room, origin, enemy.position) { continue }
			if distance < best_distance || (distance == best_distance && enemy.id < best_id) {
				best_id = enemy.id
				best_distance = distance
				best_position = enemy.position
			}
		}
		if best_id == 0 { break }
		path.targets[path.count] = enemy_entity(best_id)
		path.positions[path.count] = best_position
		path.count += 1
	}
	return
}

spell_card_event :: proc(
	kind: Game_Event_Kind,
	instance: Card_Instance,
	from, to: grid.Position,
	target: Entity_Ref = SYSTEM_ENTITY,
	amount: i32 = 0,
) -> Game_Event {
	return {
		kind = kind, source = PLAYER_ENTITY, target = target, amount = amount,
		from_position = from, to_position = to,
		card_id = instance.id, card_definition = instance.definition_id,
		card_upgrade_level = instance.upgrade_level, card_lifetime = instance.lifetime,
	}
}

spell_dice_event :: proc(instance: Card_Instance, from, to: grid.Position, target: Entity_Ref, roll: Dice_Roll) -> Game_Event {
	event := spell_card_event(.Dice_Rolled, instance, from, to, target, roll.total)
	event.dice_roll = roll
	return event
}

resolve_sundering_blow :: proc(
	room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action,
) -> (report: Action_Report) {
	if compiled == nil || instance.definition_id != .Sundering_Blow ||
	   compiled.kind != .Card || compiled.source != PLAYER_ENTITY || compiled.target != target ||
	   compiled.effect_count != 2 || compiled.effects[0].kind != .Damage || compiled.effects[1].kind != .Move {
		return
	}
	path := query_spell_path(room, instance, target)
	if path.error != .None || path.count != 1 { return }
	staged_dice := room.player.dice
	roll, rolled := roll_d6_pool(&staged_dice, 2)
	if !rolled { return }
	action := compiled^
	action.effects[0].amount = roll.total+instance.upgrade_level
	if roll.total < 8 {
		action.effects[1] = {}
		action.effect_count = 1
	}
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	room.player.dice = staged_dice
	record_report_event(&report, spell_dice_event(instance, origin, path.positions[0], target.entity, roll))
	record_report_event(&report, spell_card_event(.Spell_Launched, instance, origin, path.positions[0], target.entity))
	record_report_event(&report, spell_card_event(.Spell_Impact, instance, origin, path.positions[0], target.entity))
	merge_spell_hit_report(&report, &hit)
	return
}

resolve_pattern_dice_spell :: proc(
	room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action,
) -> (report: Action_Report) {
	barrage := instance.definition_id == .Prismatic_Barrage
	if !barrage && instance.definition_id != .Twin_Venom { return }
	if compiled == nil || compiled.kind != .Card || compiled.source != PLAYER_ENTITY ||
	   compiled.target != target || compiled.effect_count != 2 { return }
	if barrage {
		if compiled.effects[0].kind != .Apply_Status || compiled.effects[0].target != PLAYER_ENTITY ||
		   compiled.effects[0].status != .Shield || compiled.effects[1].kind != .Damage ||
		   compiled.effects[1].target != target.entity { return }
	} else {
		if compiled.effects[0].kind != .Damage || compiled.effects[0].target != target.entity ||
		   compiled.effects[1].kind != .Apply_Status || compiled.effects[1].status != .Poison ||
		   compiled.effects[1].target != target.entity { return }
	}
	path := query_spell_path(room, instance, target)
	if path.error != .None || path.count != 1 { return }
	staged_dice := room.player.dice
	roll, rolled := roll_d6_pool(&staged_dice, card_dice_count(instance.definition_id))
	if !rolled { return }
	action := compiled^
	action.effects = {}
	action.effect_count = 0
	damage: i32
	if barrage {
		successes := dice_success_count(&roll)
		failures := i32(roll.count-successes)
		if failures > 0 {
			added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, failures, 2))
			assert(added)
		}
		damage = i32(successes)*(3+instance.upgrade_level)
		if damage > 0 {
			added := add_effect(&action, damage_effect(target.entity, damage))
			assert(added)
		}
	} else {
		damage = 1+max(roll.faces[0], roll.faces[1])+instance.upgrade_level
		added := add_effect(&action, damage_effect(target.entity, damage))
		assert(added)
		if dice_has_pair(&roll) {
			added = add_effect(&action, apply_status_effect(target.entity, .Poison, 2, 2))
			assert(added)
		}
	}
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	room.player.dice = staged_dice
	record_report_event(&report, spell_dice_event(instance, origin, path.positions[0], target.entity, roll))
	// A failed barrage becomes a guard: it launches no attack at the enemy.
	if damage > 0 {
		record_report_event(&report, spell_card_event(.Spell_Launched, instance, origin, path.positions[0], target.entity))
		record_report_event(&report, spell_card_event(.Spell_Impact, instance, origin, path.positions[0], target.entity, damage))
	}
	merge_spell_hit_report(&report, &hit)
	return
}

merge_spell_hit_report :: proc(destination, hit: ^Action_Report) {
	if !hit.accepted { return }
	destination.accepted = true
	merge_reaction_action_report(destination, hit)
	destination.reactions_triggered += hit.reactions_triggered
	destination.reactions_dropped += hit.reactions_dropped
	destination.reaction_events_processed += hit.reaction_events_processed
	destination.reaction_events_dropped += hit.reaction_events_dropped
	destination.reaction_limit_reached = destination.reaction_limit_reached || hit.reaction_limit_reached
	append_event_log(&destination.events, &hit.events)
}

// The card stays in Resolving throughout the spell. Each hit settles its normal
// reactions before the next hit, but only play_card pays, pulses and draws.
resolve_played_card_action :: proc(
	room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action,
) -> (report: Action_Report) {
	if room == nil || room.player == nil || compiled == nil || room.phase != .Combat {
		return
	}
	if instance.definition_id == .Sundering_Blow {
		return resolve_sundering_blow(room, instance, target, compiled)
	}
	if instance.definition_id == .Prismatic_Barrage || instance.definition_id == .Twin_Venom {
		return resolve_pattern_dice_spell(room, instance, target, compiled)
	}
	if instance.definition_id == .Firebomb {
		action := compiled^
		action.visual_group = 1
		origin := room.player.position
		definition, _ := card_definition_by_id(instance.definition_id, tactical_enabled(room))
		query := evaluate_card_targeting(room, instance, card_target_request_at(definition, target.cell))
		impact := spell_card_event(.Spell_Impact, instance, origin, target.cell)
		for cell in query.query.affected.cells[:query.query.affected.count] {
			dx, dy := cell.x-target.cell.x+1, cell.y-target.cell.y+1
			if dx >= 0 && dx < 3 && dy >= 0 && dy < 3 { impact.area_mask |= u16(1)<<u32(dy*3+dx) }
		}
		hit := resolve_action(room, &action)
		if !hit.accepted { return }
		record_report_event(&report, spell_card_event(.Spell_Launched, instance, origin, target.cell))
		record_report_event(&report, impact)
		merge_spell_hit_report(&report, &hit)
		return
	}
	if instance.definition_id != .Fate_Strike && instance.definition_id != .Chain_Lightning {
		return resolve_action(room, compiled)
	}
	path := query_spell_path(room, instance, target)
	if path.error != .None || path.count == 0 { return }
	staged_dice := room.player.dice
	roll: Dice_Roll
	if instance.definition_id == .Fate_Strike {
		rolled: bool
		roll, rolled = roll_d6_pool(&staged_dice, 1)
		if !rolled { return }
		if roll.total != 6 { path.count = 1 }
	}
	origin := room.player.position
	for index in 0..<path.count {
		if room.phase != .Combat || !entity_exists(room, PLAYER_ENTITY) ||
		   !entity_exists(room, path.targets[index]) {
			report.skipped_effects += path.count-index
			break
		}
		damage := i32(3)+instance.upgrade_level
		if instance.definition_id == .Fate_Strike && index == 0 {
			damage = 2+instance.upgrade_level+roll.total
		}
		action := make_action(.Card, PLAYER_ENTITY, entity_target(path.targets[index]), .Opponent)
		added := add_effect(&action, damage_effect(path.targets[index], damage))
		assert(added)
		hit := resolve_action(room, &action)
		if !hit.accepted {
			report.skipped_effects += path.count-index
			break
		}
		if index == 0 {
			if instance.definition_id == .Fate_Strike {
				room.player.dice = staged_dice
				record_report_event(&report, spell_dice_event(instance, origin, path.positions[0], path.targets[0], roll))
			}
			record_report_event(&report, spell_card_event(.Spell_Launched, instance, origin, path.positions[0], path.targets[0]))
		}
		record_report_event(&report, spell_card_event(.Spell_Impact, instance, origin, path.positions[index], path.targets[index]))
		merge_spell_hit_report(&report, &hit)
		origin = path.positions[index]
	}
	return
}
