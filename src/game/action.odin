package game

import grid "../engine/grid"

// One simultaneous area discharge can hit every enemy plus the player.
// Multi-template area cards still validate their expansion against this bound.
MAX_ACTION_EFFECTS :: MAX_ENEMIES_PER_ROOM+1

Entity_Kind :: enum {
	Player,
	Enemy,
	Trap,
	Object,
	System,
}

Entity_Ref :: struct {
	kind: Entity_Kind,
	id:   u32,
}

PLAYER_ENTITY :: Entity_Ref{kind = .Player}
SYSTEM_ENTITY :: Entity_Ref{kind = .System}

enemy_entity :: proc(id: u32) -> Entity_Ref {
	return {kind = .Enemy, id = id}
}

trap_entity :: proc(id: u32) -> Entity_Ref {
	return {kind = .Trap, id = id}
}

object_entity :: proc(id: u32) -> Entity_Ref {
	return {kind = .Object, id = id}
}

Target_Kind :: enum {
	None,
	Entity,
	Cell,
}

Target :: struct {
	kind:   Target_Kind,
	entity: Entity_Ref,
	cell:   grid.Position,
}

Target_Rule :: enum {
	Any,
	None,
	Self,
	Entity,
	Player,
	Opponent,
	Opponent_Or_Object,
	Adjacent_Opponent,
	Cell,
	Walkable_Cell,
}

entity_target :: proc(entity: Entity_Ref) -> Target {
	return {kind = .Entity, entity = entity}
}

cell_target :: proc(position: grid.Position) -> Target {
	return {kind = .Cell, cell = position}
}

Action_Kind :: enum {
	Move,
	Attack,
	Wait,
	Trigger,
	Collect,
	Ability,
	Card,
	Reaction,
}

Effect_Kind :: enum {
	Damage,
	Heal,
	Gain_Gold,
	Move,
	Apply_Status,
	Remove_Status,
	Add_Reaction_Binding,
	Draw_Cards,
	Discard_Cards,
	Create_Card,
	Gain_Energy,
	Deploy_Device,
	// Movimento Ombra: `amount` seconds inside the player's shadow.
	Enter_Shadow,
	// Pozza di Veleno (`status` Poison) or Incendio (Burn) on `destination`:
	// `amount` stacks to an enemy for each cell of it entered (ground.odin).
	Place_Ground,
	// LAZZO: `target` caught and swung round the player, its first hit
	// numbered `amount` (lasso.odin).
	Lasso,
	// CANNA DA PESCA: the room's fishings (`amount`), the rod's template only;
	// its slot fishes through fish_with_rod, never through an action (fishing.odin).
	Fish,
	// PINBALL: `target` turned into a steel ball and struck away, its value
	// `amount` (pinball.odin).
	Pinball,
	// FIRST PERSON SHOOTER: `amount` world seconds behind the player's eyes,
	// his AK in hand (first_person.odin).
	First_Person,
}

Effect :: struct {
	kind:        Effect_Kind,
	target:      Entity_Ref,
	amount:      i32,
	has_status_cause: bool,
	status_cause:     Status_Kind,
	destination: grid.Position,
	movement_mode: Movement_Mode,
	status:      Status_Kind,
	duration:    i32,
	reaction:    Reaction_Id,
	charges:     i32,
	priority_modifier: i32,
	binding_source: Reaction_Binding_Source,
	card_definition: Card_Id,
	object_kind: Grid_Object_Kind,
}

damage_effect :: proc(target: Entity_Ref, amount: i32) -> Effect {
	return {kind = .Damage, target = target, amount = amount}
}

@(private)
status_damage_effect :: proc(
	target: Entity_Ref,
	amount: i32,
	status_cause: Status_Kind,
) -> Effect {
	return {
		kind = .Damage,
		target = target,
		amount = amount,
		has_status_cause = true,
		status_cause = status_cause,
	}
}

heal_effect :: proc(target: Entity_Ref, amount: i32) -> Effect {
	return {kind = .Heal, target = target, amount = amount}
}

@(private)
gain_gold_effect :: proc(amount: i32) -> Effect {
	return {kind = .Gain_Gold, target = PLAYER_ENTITY, amount = amount}
}

@(private)
gain_energy_effect :: proc(amount: i32) -> Effect {
	return {kind = .Gain_Energy, target = PLAYER_ENTITY, amount = amount}
}

@(private)
enter_shadow_effect :: proc(seconds: i32) -> Effect {
	return {kind = .Enter_Shadow, target = PLAYER_ENTITY, amount = seconds}
}

@(private)
draw_cards_effect :: proc(amount: i32) -> Effect {
	return {kind = .Draw_Cards, target = PLAYER_ENTITY, amount = amount}
}

@(private)
discard_cards_effect :: proc(amount: i32) -> Effect {
	return {kind = .Discard_Cards, target = PLAYER_ENTITY, amount = amount}
}

@(private)
create_card_effect :: proc(definition_id: Card_Id, amount: i32) -> Effect {
	return {
		kind = .Create_Card,
		target = PLAYER_ENTITY,
		amount = amount,
		card_definition = definition_id,
	}
}

move_effect :: proc(
	target: Entity_Ref,
	destination: grid.Position,
	mode: Movement_Mode = .Traverse,
) -> Effect {
	return {
		kind = .Move,
		target = target,
		destination = destination,
		movement_mode = mode,
	}
}

apply_status_effect :: proc(target: Entity_Ref, status: Status_Kind, potency, duration: i32) -> Effect {
	return {
		kind = .Apply_Status,
		target = target,
		amount = potency,
		status = status,
		duration = duration,
	}
}

@(private)
remove_status_effect :: proc(target: Entity_Ref, status: Status_Kind) -> Effect {
	return {kind = .Remove_Status, target = target, status = status}
}

@(private)
add_reaction_binding_effect :: proc(
	target: Entity_Ref,
	reaction: Reaction_Id,
	potency, charges, duration: i32,
	priority_modifier: i32 = 0,
	source: Reaction_Binding_Source = {},
) -> Effect {
	return {
		kind = .Add_Reaction_Binding,
		target = target,
		amount = potency,
		duration = duration,
		reaction = reaction,
		charges = charges,
		priority_modifier = priority_modifier,
		binding_source = source,
	}
}

Action :: struct {
	kind:         Action_Kind,
	visual_group: u32,
	source:       Entity_Ref,
	target:       Target,
	target_rule:  Target_Rule,
	effects:      [MAX_ACTION_EFFECTS]Effect,
	effect_count: int,
}

make_action :: proc(
	kind: Action_Kind,
	source: Entity_Ref,
	target: Target = {},
	target_rule: Target_Rule = .Any,
) -> Action {
	return {
		kind = kind,
		source = source,
		target = target,
		target_rule = target_rule,
	}
}

add_effect :: proc(action: ^Action, effect: Effect) -> bool {
	if action == nil || action.effect_count < 0 || action.effect_count >= MAX_ACTION_EFFECTS {
		return false
	}
	action.effects[action.effect_count] = effect
	action.effect_count += 1
	return true
}

Action_Report :: struct {
	accepted:          bool,
	applied_effects:   int,
	skipped_effects:   int,
	damage_dealt:      i32,
	damage_absorbed:   i32,
	healing_done:      i32,
	gold_gained:       i32,
	enemies_defeated:  int,
	objects_destroyed: int,
	statuses_applied:  int,
	statuses_removed:  int,
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
	events:            Event_Log,
}

entity_exists :: proc(room: ^Room, entity: Entity_Ref) -> bool {
	if room == nil || room.player == nil {
		return false
	}
	switch entity.kind {
	case .Player:
		return entity.id == 0 && room.player.health > 0
	case .Enemy:
		_, found := enemy_index_by_id(room, entity.id)
		return found
	case .Trap:
		_, found := trap_index_by_id(room, entity.id)
		return found
	case .Object:
		_, found := object_index_by_id(room, entity.id)
		return found
	case .System:
		return entity.id == 0
	}
	return false
}

@(private = "file")
target_is_valid :: proc(room: ^Room, target: Target) -> bool {
	if room == nil {
		return false
	}
	switch target.kind {
	case .None:
		return true
	case .Entity:
		return entity_exists(room, target.entity)
	case .Cell:
		return room.level_data != nil && grid.contains(&room.level_data.tiles, target.cell)
	}
	return false
}

@(private)
entity_position :: proc(room: ^Room, entity: Entity_Ref) -> (grid.Position, bool) {
	if room == nil || !entity_exists(room, entity) {
		return {}, false
	}
	switch entity.kind {
	case .Player:
		return room.player.position, true
	case .Enemy:
		index, found := enemy_index_by_id(room, entity.id)
		assert(found)
		return room.enemies[index].position, true
	case .Trap:
		index, found := trap_index_by_id(room, entity.id)
		assert(found)
		return room.traps[index].position, true
	case .Object:
		index, found := object_index_by_id(room, entity.id)
		assert(found)
		return room.objects[index].position, true
	case .System:
		return {}, false
	}
	return {}, false
}

@(private)
entities_are_opponents :: proc(source, target: Entity_Ref) -> bool {
	return (source.kind == .Player && target.kind == .Enemy) ||
	       (source.kind == .Enemy && target.kind == .Player)
}

@(private)
entity_is_targetable_object :: proc(room: ^Room, entity: Entity_Ref) -> bool {
	if room == nil || entity.kind != .Object {
		return false
	}
	index, found := object_index_by_id(room, entity.id)
	if !found {
		return false
	}
	definition, definition_found := grid_object_definition(room.objects[index].kind)
	return definition_found && definition.targetable
}

@(private)
target_matches_rule :: proc(room: ^Room, source: Entity_Ref, target: Target, rule: Target_Rule) -> bool {
	if !target_is_valid(room, target) {
		return false
	}
	switch rule {
	case .Any:
		return true
	case .None:
		return target.kind == .None
	case .Self:
		return target.kind == .Entity && target.entity == source
	case .Entity:
		return target.kind == .Entity
	case .Player:
		return target.kind == .Entity && target.entity == PLAYER_ENTITY
	case .Opponent:
		return target.kind == .Entity && entities_are_opponents(source, target.entity)
	case .Opponent_Or_Object:
		return target.kind == .Entity &&
		       (entities_are_opponents(source, target.entity) ||
		        entity_is_targetable_object(room, target.entity))
	case .Adjacent_Opponent:
		if target.kind != .Entity || !entities_are_opponents(source, target.entity) {
			return false
		}
		source_position, source_found := entity_position(room, source)
		target_position, target_found := entity_position(room, target.entity)
		return source_found && target_found &&
		       abs(source_position.x-target_position.x)+abs(source_position.y-target_position.y) == 1
	case .Cell:
		return target.kind == .Cell
	case .Walkable_Cell:
		return target.kind == .Cell && !cell_blocks_movement(room, target.cell)
	}
	return false
}

@(private)
effect_is_valid :: proc(room: ^Room, effect: Effect) -> bool {
	if room == nil || !entity_exists(room, effect.target) {
		return false
	}
	// PINBALL: nothing reaches the ball while it rolls, its burst aside
	// (pinball_burst ends the roll first).
	if effect.target.kind == .Enemy && enemy_is_pinball(room, effect.target.id) {
		return false
	}
	switch effect.kind {
	case .Enter_Shadow:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && tactical_can_begin_shadow(room)
	case .Place_Ground:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && ground_can_place(room, effect.status, effect.destination)
	case .Lasso:
		return effect.target.kind == .Enemy && effect.amount > 0 && lasso_target_error(room, entity_target(effect.target)) == .None
	case .Pinball:
		return effect.target.kind == .Enemy && effect.amount > 0 && pinball_target_error(room, entity_target(effect.target)) == .None
	// Never resolved: the rod fishes from its slot (fishing.odin).
	case .Fish:
		return false
	case .Deploy_Device:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 &&
		       (effect.object_kind != .Shock_Floor || (effect.charges >= 1 && effect.charges <= TACTICAL_SHOCK_FLOOR_MAX_CHARGES)) &&
		       board_device_can_deploy(room, effect.object_kind, effect.destination)
	case .Damage:
		if effect.amount <= 0 {
			return false
		}
		if effect.target.kind == .Player || effect.target.kind == .Enemy {
			return true
		}
		if effect.target.kind != .Object {
			return false
		}
		index, found := object_index_by_id(room, effect.target.id)
		if !found {
			return false
		}
		definition, definition_found := grid_object_definition(room.objects[index].kind)
		return definition_found && definition.damageable &&
		       (!definition.explosive || room.objects[index].detonation_pulse == 0)
	case .Heal:
		return effect.amount > 0 && (effect.target.kind == .Player || effect.target.kind == .Enemy)
	case .Gain_Gold:
		return effect.amount > 0 && effect.target == PLAYER_ENTITY
	case .Gain_Energy:
		return effect.amount > 0 && effect.target == PLAYER_ENTITY && room.phase == .Combat &&
		       room.player.deck.combat_active && room.player.deck.energy < room.player.deck.rules.max_energy
	case .Move:
		query := query_entity_movement(
			room,
			effect.target,
			effect.destination,
			effect.movement_mode,
		)
		return movement_query_is_clear(&query)
	case .Apply_Status:
		// Stacks carry no duration; every other status needs one.
		return effect.amount > 0 && (effect.duration > 0 || status_kind_stacks(effect.status)) &&
		       (effect.target.kind == .Player || effect.target.kind == .Enemy) &&
		       can_apply_status(room, effect.target, effect.status)
	case .Remove_Status:
		if effect.target.kind != .Player && effect.target.kind != .Enemy {
			return false
		}
		_, found := status_for_entity(room, effect.target, effect.status)
		return found
	case .Add_Reaction_Binding:
		return can_add_reaction_binding(room, {
			definition_id = effect.reaction,
			owner = effect.target,
			potency = effect.amount,
			charges = effect.charges,
			duration = effect.duration,
			priority_modifier = effect.priority_modifier,
			source = effect.binding_source,
		})
	case .Draw_Cards:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && room.phase == .Combat &&
		       can_draw_card(&room.player.deck)
	case .Discard_Cards:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && room.phase == .Combat &&
		       can_discard_hand_card(&room.player.deck, 0)
	case .Create_Card:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && room.phase == .Combat &&
		       can_create_temporary_card(&room.player.deck, effect.card_definition)
	case .First_Person:
		return effect.target == PLAYER_ENTITY && effect.amount > 0 && tactical_can_begin_first_person(room)
	}
	return false
}

@(private)
record_report_event :: proc(report: ^Action_Report, event: Game_Event) {
	assert(report != nil)
	if !record_event(&report.events, event) {
		// Action events drive reactions as well as presentation; dropping one
		// would change authoritative gameplay instead of degrading visuals only.
		panic("Action_Report event capacity exhausted")
	}
}

@(private = "file")
absorb_damage_with_shield :: proc(
	room: ^Room,
	source, target: Entity_Ref,
	damage: i32,
	has_status_cause: bool,
	status_cause: Status_Kind,
	report: ^Action_Report,
) -> i32 {
	shield, found := status_for_entity(room, target, .Shield)
	if !found || damage <= 0 {
		return damage
	}
	absorbed := min(damage, shield.potency)
	shield.potency -= absorbed
	report.damage_absorbed += absorbed
	record_report_event(report, {
		kind = .Damage_Absorbed,
		source = source,
		target = target,
		amount = absorbed,
		status = .Shield,
		has_status_cause = has_status_cause,
		status_cause = status_cause,
	})
	if shield.potency == 0 {
		removed, ok := remove_status(room, target, .Shield)
		assert(ok)
		report.statuses_removed += 1
		record_report_event(report, {
			kind = .Status_Removed,
			source = source,
			target = target,
			amount = removed.potency,
			status = .Shield,
			duration = removed.remaining_pulses,
		})
	}
	return damage-absorbed
}

// What a blow of `amount` takes from the player before any Shield: his
// defense counted, never below 1. RIFLESSO sends back the same.
@(private)
player_blow_damage :: proc(room: ^Room, amount: i32) -> i32 {
	return max(i32(1), amount-room.player.stats.defense)
}

@(private)
apply_damage_effect :: proc(
	room: ^Room,
	source: Entity_Ref,
	effect: Effect,
	report: ^Action_Report,
) {
	// Every hit on the player passes here, hazards included: nothing reaches
	// a player sunk in his shadow (no shield spent, no Damaged, no reactions).
	if effect.target.kind == .Player && tactical_player_intangible(room) { return }
	damage := effect.amount
	// A status's bite (Veleno, Bruciatura) is its stacks: no defense takes
	// from it, only a Shield.
	if effect.target.kind == .Player && !effect.has_status_cause {
		damage = player_blow_damage(room, damage)
	}
	if effect.target.kind == .Player || effect.target.kind == .Enemy {
		damage = absorb_damage_with_shield(
			room,
			source,
			effect.target,
			damage,
			effect.has_status_cause,
			effect.status_cause,
			report,
		)
	}
	if damage <= 0 {
		return
	}

	actual_damage: i32
	switch effect.target.kind {
	case .Player:
		actual_damage = min(damage, room.player.health)
		room.player.health -= actual_damage
		if room.player.health == 0 {
			room.phase = .Defeat
			clear_enemy_intents(room)
		}
	case .Enemy:
		index, found := enemy_index_by_id(room, effect.target.id)
		assert(found)
		actual_damage = min(damage, room.enemies[index].health)
		room.enemies[index].health -= actual_damage
	case .Object:
		index, found := object_index_by_id(room, effect.target.id)
		assert(found)
		definition, _ := grid_object_definition(room.objects[index].kind)
		if definition.explosive && room.phase == .Combat {
			arm_explosive(room, effect.target.id, source, &report.events)
			return
		}
		actual_damage = min(damage, room.objects[index].health)
		room.objects[index].health -= actual_damage
	case .Trap, .System:
		unreachable()
	}
	report.damage_dealt += actual_damage
	record_report_event(report, {
		kind = .Damaged,
		source = source,
		target = effect.target,
		amount = actual_damage,
		has_status_cause = effect.has_status_cause,
		status_cause = effect.status_cause,
	})

	defeated := false
	drops: [3]Loot
	drop_count := 0
	if effect.target.kind == .Player {
		defeated = room.player.health == 0
	} else if effect.target.kind == .Enemy {
		index, found := enemy_index_by_id(room, effect.target.id)
		assert(found)
		if room.enemies[index].health == 0 {
			drops, drop_count = kill_enemy(room, index)
			report.enemies_defeated += 1
			defeated = true
		}
	} else if effect.target.kind == .Object {
		index, found := object_index_by_id(room, effect.target.id)
		assert(found)
		if room.objects[index].health == 0 {
			removed := remove_grid_object(room, index)
			assert(removed)
			report.objects_destroyed += 1
			defeated = true
		}
	}
	if defeated {
		record_report_event(report, {
			kind = .Entity_Defeated,
			source = source,
			target = effect.target,
		})
		for index in 0..<drop_count {
			drop := drops[index]
			record_report_event(report, {
				kind = .Loot_Dropped,
				source = effect.target,
				target = SYSTEM_ENTITY,
				amount = drop.amount,
				from_position = drop.position,
				to_position = drop.position,
				loot_kind = drop.kind,
			})
		}
	}
}

@(private = "file")
apply_effect :: proc(room: ^Room, source: Entity_Ref, effect: Effect, report: ^Action_Report) {
	assert(room != nil && report != nil && effect_is_valid(room, effect))

	switch effect.kind {
	case .Enter_Shadow:
		origin := room.player.position
		began := tactical_begin_shadow(room, f32(effect.amount))
		assert(began)
		record_report_event(report, {
			kind = .Shadow_Entered, source = source, target = PLAYER_ENTITY,
			from_position = origin, to_position = origin, duration = effect.amount,
		})
	case .Deploy_Device:
		deployed := deploy_board_device(room, effect.object_kind, effect.destination, effect.amount, effect.charges, &report.events)
		assert(deployed)
	case .Place_Ground:
		placed := place_ground(room, effect.status, effect.destination, effect.amount, report)
		assert(placed)
	case .Lasso:
		caught := begin_lasso(room, effect.target, effect.amount, report)
		assert(caught)
	case .Pinball:
		struck := begin_pinball(room, effect.target, effect.amount, report)
		assert(struck)
	// effect_is_valid refuses it.
	case .Fish:
		unreachable()
	case .Damage:
		apply_damage_effect(room, source, effect, report)
	case .Heal:
		healed: i32
		switch effect.target.kind {
		case .Player:
			before := room.player.health
			room.player.health = min(room.player.stats.max_health, before+effect.amount)
			healed = room.player.health-before
		case .Enemy:
			index, enemy_found := enemy_index_by_id(room, effect.target.id)
			assert(enemy_found)
			before := room.enemies[index].health
			room.enemies[index].health = min(room.enemies[index].max_health, before+effect.amount)
			healed = room.enemies[index].health-before
		case .Trap, .Object, .System:
			unreachable()
		}
		report.healing_done += healed
		if healed > 0 {
			record_report_event(report, {
				kind = .Healed,
				source = source,
				target = effect.target,
				amount = healed,
			})
		}
	case .Gain_Gold:
		room.player.gold += effect.amount
		report.gold_gained += effect.amount
		record_report_event(report, {
			kind = .Gold_Gained,
			source = source,
			target = PLAYER_ENTITY,
			amount = effect.amount,
		})
	case .Gain_Energy:
		deck := &room.player.deck
		restored := min(effect.amount, deck.rules.max_energy-deck.energy)
		deck.energy += restored
		record_report_event(report, {
			kind = .Energy_Gained,
			source = source,
			target = PLAYER_ENTITY,
			amount = restored,
			energy = deck.energy,
		})
	case .Move:
		apply_movement_effect(room, source, effect, report)
	case .Apply_Status:
		potency := relic_poison_potency(room, source, effect)
		applied, _ := apply_status(room, effect.target, effect.status, potency, effect.duration)
		assert(applied)
		status, found := status_for_entity(room, effect.target, effect.status)
		assert(found)
		report.statuses_applied += 1
		record_report_event(report, {
			kind = .Status_Applied,
			source = source,
			target = effect.target,
			amount = status.potency,
			status = effect.status,
			duration = status.remaining_pulses,
		})
	case .Remove_Status:
		removed, ok := remove_status(room, effect.target, effect.status)
		assert(ok)
		report.statuses_removed += 1
		record_report_event(report, {
			kind = .Status_Removed,
			source = source,
			target = effect.target,
			amount = removed.potency,
			status = removed.kind,
			duration = removed.remaining_pulses,
		})
	case .Add_Reaction_Binding:
		binding_id, added := add_reaction_binding(room, {
			definition_id = effect.reaction,
			owner = effect.target,
			potency = effect.amount,
			charges = effect.charges,
			duration = effect.duration,
			priority_modifier = effect.priority_modifier,
			source = effect.binding_source,
		})
		assert(added)
		report.reaction_bindings_added += 1
		record_report_event(report, {
			kind = .Reaction_Binding_Added,
			source = source,
			target = effect.target,
			amount = effect.amount,
			duration = effect.duration,
			reaction = effect.reaction,
			binding_id = binding_id,
			binding_source = effect.binding_source,
		})
	case .Draw_Cards:
		for _ in 0..<effect.amount {
			if !can_draw_card(&room.player.deck) {
				break
			}
			card, drawn := draw_card(&room.player.deck)
			assert(drawn)
			report.cards_drawn += 1
			record_report_event(report, make_card_zone_event(
				.Card_Drawn, source, PLAYER_ENTITY, card, .Draw, .Hand,
			))
		}
	case .Discard_Cards:
		for _ in 0..<effect.amount {
			if !can_discard_hand_card(&room.player.deck, 0) {
				break
			}
			card, discarded := discard_hand_card(&room.player.deck, 0)
			assert(discarded)
			report.cards_discarded += 1
			record_report_event(report, make_card_zone_event(
				.Card_Moved, source, PLAYER_ENTITY, card, .Hand, .Discard,
			))
		}
	case .Create_Card:
		for _ in 0..<effect.amount {
			if !can_create_temporary_card(&room.player.deck, effect.card_definition) {
				break
			}
			card, created := create_temporary_card(&room.player.deck, effect.card_definition)
			assert(created)
			report.cards_created += 1
			record_report_event(report, make_card_zone_event(
				.Card_Created, source, PLAYER_ENTITY, card, .Count, .Hand,
			))
		}
	case .First_Person:
		began := tactical_begin_first_person(room, f32(effect.amount))
		assert(began)
		at := room.player.position
		record_report_event(report, {
			kind = .First_Person_Begun, source = source, target = PLAYER_ENTITY,
			from_position = at, to_position = at, duration = effect.amount, card_definition = .First_Person,
		})
	}
	report.applied_effects += 1
}

// Each resolution writes into its caller's distinct storage. Nested reactions
// and relic actions must never reuse their parent's report while it is live.
@(private)
resolve_action_once :: proc(room: ^Room, action: ^Action, report: ^Action_Report) {
	if report == nil { return }
	report^ = {}
	if room == nil || room.player == nil || action == nil ||
	   room.phase == .Complete || room.phase == .Defeat ||
	   action.effect_count < 0 || action.effect_count > MAX_ACTION_EFFECTS ||
	   !entity_exists(room, action.source) ||
	   !target_matches_rule(room, action.source, action.target, action.target_rule) {
		return
	}

	valid_effect_count := 0
	for index in 0..<action.effect_count {
		if effect_is_valid(room, action.effects[index]) {
			valid_effect_count += 1
		}
	}
	if action.effect_count > 0 && valid_effect_count == 0 {
		return
	}

	initial_phase := room.phase
	report.accepted = true
	for index in 0..<action.effect_count {
		if !entity_exists(room, action.source) {
			report.skipped_effects += action.effect_count-index
			break
		}
		effect := action.effects[index]
		if !effect_is_valid(room, effect) {
			report.skipped_effects += 1
			continue
		}
		apply_effect(room, action.source, effect, report)
	}
	if action.visual_group != 0 {
		for &event in report.events.events[:report.events.count] {
			event.visual_group = action.visual_group
		}
	}
	apply_action_relics(room, action, report)
	report.combat_ended = initial_phase == .Combat && room.phase == .Loot
	report.player_defeated = room.phase == .Defeat
	return
}

resolve_action :: proc(room: ^Room, action: ^Action) -> (report: Action_Report) {
	resolve_action_once(room, action, &report)
	if report.accepted {
		dispatch_reactions(room, &report)
		append_room_clear_relic(room, &report)
		disarm_explosives_after_combat(room, &report.events)
		disarm_room_modifier_after_combat(room)
		disarm_board_devices_after_combat(room, &report.events)
	}
	return
}
