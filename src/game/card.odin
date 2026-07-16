package game

import grid "../grid"

MAX_CARD_DEFINITION_EFFECTS :: 4
MAX_CARD_UPGRADE_LEVEL :: 10

Card_Rarity :: enum {
	Common,
	Uncommon,
	Rare,
	Count,
}

card_rarity_name :: proc(rarity: Card_Rarity) -> string {
	switch rarity {
	case .Common:
		return "Common"
	case .Uncommon:
		return "Uncommon"
	case .Rare:
		return "Rare"
	case .Count:
	}
	return "Unknown"
}

Card_Id :: enum {
	Strike,
	Arc_Bolt,
	Piercing_Ray,
	Cross_Slash,
	Firebomb,
	Guard,
	Toxic_Wave,
	Thorn_Coat,
	Afterimage,
	Counter_Rune,
	Battle_Focus,
	Calculated_Risk,
	Spark_Forge,
	Spark,
	Count,
}

Card_Target_Selector :: enum {
	Chosen_Entity,
	Player,
	Each_Enemy,
	Each_Affected_Enemy,
	Count,
}

Card_Compile_Error :: enum {
	None,
	Invalid_Room,
	Invalid_Phase,
	Invalid_Instance,
	Unknown_Definition,
	Invalid_Definition,
	Invalid_Target,
	Target_Out_Of_Range,
	Target_Blocked,
	No_Effects,
	Too_Many_Effects,
}

Card_Effect_Template :: struct {
	kind:               Effect_Kind,
	target:             Card_Target_Selector,
	base_amount:        i32,
	amount_per_upgrade: i32,
	status:             Status_Kind,
	duration:           i32,
	reaction:           Reaction_Id,
	charges:            i32,
	priority_modifier:  i32,
	card_definition:    Card_Id,
	has_card_definition: bool,
}

Card_Definition :: struct {
	id:              Card_Id,
	name:            string,
	rarity:          Card_Rarity,
	reward_weight:   u32,
	shop_base_price: i32,
	cost:            i32,
	temporary_only:  bool,
	exhaust_on_play: bool,
	retain_on_refocus: bool,
	ethereal:          bool,
	targeting:       Targeting_Spec,
	effects:         [MAX_CARD_DEFINITION_EFFECTS]Card_Effect_Template,
	effect_count:    int,
}

Card_Instance :: struct {
	id:             u32,
	definition_id:  Card_Id,
	upgrade_level:  i32,
	lifetime:       Card_Lifetime,
}

CARD_DEFINITIONS :: [int(Card_Id.Count)]Card_Definition{
	{
		id = .Strike,
		name = "Strike",
		rarity = .Common,
		reward_weight = 100,
		shop_base_price = 3,
		cost = 1,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 1},
			shape = .Single,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Arc_Bolt,
		name = "Arc Bolt",
		rarity = .Common,
		reward_weight = 90,
		shop_base_price = 3,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 3},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 3,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Piercing_Ray,
		name = "Piercing Ray",
		rarity = .Uncommon,
		reward_weight = 80,
		shop_base_price = 5,
		cost = 2,
		targeting = {
			rule = .Walkable_Cell,
			cast_range = {.Chebyshev, 1, 5},
			shape = .Line,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Each_Affected_Enemy,
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Cross_Slash,
		name = "Cross Slash",
		rarity = .Uncommon,
		reward_weight = 90,
		shop_base_price = 5,
		cost = 2,
		targeting = {
			rule = .Walkable_Cell,
			cast_range = {.Manhattan, 1, 3},
			shape = .Cross,
			radius = 1,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Each_Affected_Enemy,
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Firebomb,
		name = "Firebomb",
		rarity = .Rare,
		reward_weight = 75,
		shop_base_price = 8,
		cost = 2,
		targeting = {
			rule = .Walkable_Cell,
			cast_range = {.Chebyshev, 1, 3},
			shape = .Square,
			radius = 1,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Each_Affected_Enemy,
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Guard,
		name = "Guard",
		rarity = .Common,
		reward_weight = 100,
		shop_base_price = 3,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Apply_Status,
				target = .Player,
				base_amount = 3,
				amount_per_upgrade = 1,
				status = .Shield,
				duration = 3,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Toxic_Wave,
		name = "Toxic Wave",
		rarity = .Rare,
		reward_weight = 70,
		shop_base_price = 8,
		cost = 2,
		targeting = {rule = .None},
		effects = {
			{
				kind = .Apply_Status,
				target = .Each_Enemy,
				base_amount = 1,
				amount_per_upgrade = 1,
				status = .Poison,
				duration = 3,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Thorn_Coat,
		name = "Thorn Coat",
		rarity = .Uncommon,
		reward_weight = 85,
		shop_base_price = 5,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Apply_Status,
				target = .Player,
				base_amount = 1,
				amount_per_upgrade = 1,
				status = .Thorns,
				duration = 3,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Afterimage,
		name = "Afterimage",
		rarity = .Uncommon,
		reward_weight = 85,
		shop_base_price = 5,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Apply_Status,
				target = .Player,
				base_amount = 1,
				amount_per_upgrade = 1,
				status = .Afterimage,
				duration = 4,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Counter_Rune,
		name = "Counter Rune",
		rarity = .Rare,
		reward_weight = 65,
		shop_base_price = 8,
		cost = 1,
		retain_on_refocus = true,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Add_Reaction_Binding,
				target = .Player,
				base_amount = 2,
				amount_per_upgrade = 1,
				duration = 4,
				reaction = .Thorns_Counter,
				charges = 2,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Battle_Focus,
		name = "Battle Focus",
		rarity = .Rare,
		reward_weight = 65,
		shop_base_price = 8,
		cost = 1,
		exhaust_on_play = true,
		ethereal = true,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Draw_Cards,
				target = .Player,
				base_amount = 2,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Calculated_Risk,
		name = "Calculated Risk",
		rarity = .Uncommon,
		reward_weight = 80,
		shop_base_price = 5,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Draw_Cards,
				target = .Player,
				base_amount = 2,
			},
			{
				kind = .Discard_Cards,
				target = .Player,
				base_amount = 1,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Spark_Forge,
		name = "Spark Forge",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 5,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Create_Card,
				target = .Player,
				base_amount = 1,
				card_definition = .Spark,
				has_card_definition = true,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Spark,
		name = "Spark",
		rarity = .Common,
		cost = 0,
		temporary_only = true,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 2},
			shape = .Single,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
}

card_drop_target :: proc(
	room: ^Room,
	definition: Card_Definition,
	position: grid.Position,
) -> (Target, bool) {
	validated_definition := definition
	if room == nil || room.player == nil || room.level_data == nil ||
	   !validate_card_definition(&validated_definition) {
		return {}, false
	}
	request := Target_Request{}
	if definition.targeting.shape != .None {
		request = {anchor = position, has_anchor = true}
	}
	query := evaluate_target_query(room, PLAYER_ENTITY, definition.targeting, request)
	return query.primary_target, query.error == .None && query.has_primary_target
}

card_target_rule_selects_effect_entity :: proc(rule: Target_Rule) -> bool {
	switch rule {
	case .Self, .Player, .Opponent, .Adjacent_Opponent:
		return true
	case .Any, .None, .Entity, .Cell, .Walkable_Cell:
		return false
	}
	return false
}

card_amount_template_is_valid :: proc(template: Card_Effect_Template) -> bool {
	if template.base_amount <= 0 || template.amount_per_upgrade < 0 {
		return false
	}
	maximum := i64(template.base_amount)+i64(template.amount_per_upgrade)*i64(MAX_CARD_UPGRADE_LEVEL)
	return maximum <= i64(max(i32))
}

card_effect_template_is_valid :: proc(
	definition: ^Card_Definition,
	template: Card_Effect_Template,
) -> bool {
	if definition == nil || int(template.target) < 0 || int(template.target) >= int(Card_Target_Selector.Count) ||
	   (template.target == .Chosen_Entity && !card_target_rule_selects_effect_entity(definition.targeting.rule)) ||
	   (template.target == .Each_Affected_Enemy && definition.targeting.shape == .None) {
		return false
	}

	switch template.kind {
	case .Move:
		return false
	case .Remove_Status:
		return status_kind_is_valid(template.status)
	case .Damage, .Heal:
		return card_amount_template_is_valid(template)
	case .Gain_Gold:
		return template.target == .Player && card_amount_template_is_valid(template)
	case .Draw_Cards, .Discard_Cards:
		return template.target == .Player && card_amount_template_is_valid(template)
	case .Create_Card:
		_, found := card_definition_by_id(template.card_definition)
		return template.target == .Player && template.has_card_definition && found &&
		       card_amount_template_is_valid(template)
	case .Apply_Status:
		return status_kind_is_valid(template.status) && template.duration > 0 &&
		       card_amount_template_is_valid(template)
	case .Add_Reaction_Binding:
		if template.charges != REACTION_BINDING_UNLIMITED && template.charges <= 0 {
			return false
		}
		if template.duration != REACTION_BINDING_UNLIMITED && template.duration <= 0 {
			return false
		}
		reaction, found := reaction_definition_by_id(template.reaction)
		return found && validate_reaction_definition(&reaction) && card_amount_template_is_valid(template)
	}
	return false
}

validate_card_definition :: proc(definition: ^Card_Definition) -> bool {
	if definition == nil || int(definition.id) < 0 || int(definition.id) >= int(Card_Id.Count) ||
	   len(definition.name) == 0 || int(definition.rarity) < 0 ||
	   int(definition.rarity) >= int(Card_Rarity.Count) || definition.cost < 0 ||
	   (definition.retain_on_refocus && definition.ethereal) ||
	   !targeting_spec_is_valid(definition.targeting) ||
	   definition.effect_count <= 0 || definition.effect_count > MAX_CARD_DEFINITION_EFFECTS {
		return false
	}
	if (!definition.temporary_only &&
	    (definition.reward_weight == 0 || definition.shop_base_price <= 0)) ||
	   (definition.temporary_only &&
	    (definition.reward_weight != 0 || definition.shop_base_price != 0 || definition.exhaust_on_play)) {
		return false
	}
	for index in 0..<definition.effect_count {
		if !card_effect_template_is_valid(definition, definition.effects[index]) {
			return false
		}
	}
	return true
}

validate_card_definitions :: proc() -> bool {
	definitions := CARD_DEFINITIONS
	for &definition, index in definitions {
		if int(definition.id) != index || !validate_card_definition(&definition) {
			return false
		}
	}
	return true
}

card_definition_by_id :: proc(id: Card_Id) -> (Card_Definition, bool) {
	definitions := CARD_DEFINITIONS
	index := int(id)
	if index < 0 || index >= len(definitions) {
		return {}, false
	}
	return definitions[index], true
}

validate_card_instance :: proc(instance: Card_Instance) -> bool {
	if instance.id == 0 || instance.upgrade_level < 0 || instance.upgrade_level > MAX_CARD_UPGRADE_LEVEL ||
	   int(instance.lifetime) < 0 || int(instance.lifetime) >= int(Card_Lifetime.Count) {
		return false
	}
	definition, found := card_definition_by_id(instance.definition_id)
	return found && validate_card_definition(&definition) &&
	       (!definition.temporary_only || instance.lifetime == .Combat)
}

card_destination_after_play :: proc(instance: Card_Instance) -> (Card_Zone, bool) {
	if !validate_card_instance(instance) {
		return .Count, false
	}
	definition, found := card_definition_by_id(instance.definition_id)
	assert(found)
	if instance.lifetime == .Combat || definition.exhaust_on_play {
		return .Exhaust, true
	}
	return .Discard, true
}

card_definition_destination_after_refocus :: proc(definition: Card_Definition) -> (Card_Zone, bool) {
	validated_definition := definition
	if !validate_card_definition(&validated_definition) {
		return .Count, false
	}
	if definition.retain_on_refocus {
		return .Hand, true
	}
	if definition.ethereal {
		return .Exhaust, true
	}
	return .Discard, true
}

card_destination_after_refocus :: proc(instance: Card_Instance) -> (Card_Zone, bool) {
	if !validate_card_instance(instance) {
		return .Count, false
	}
	definition, found := card_definition_by_id(instance.definition_id)
	assert(found)
	return card_definition_destination_after_refocus(definition)
}

card_effect_amount :: proc(template: Card_Effect_Template, upgrade_level: i32) -> i32 {
	assert(upgrade_level >= 0 && upgrade_level <= MAX_CARD_UPGRADE_LEVEL)
	amount := i64(template.base_amount)+i64(template.amount_per_upgrade)*i64(upgrade_level)
	assert(amount > 0 && amount <= i64(max(i32)))
	return i32(amount)
}

instantiate_card_effect :: proc(
	template: Card_Effect_Template,
	target: Entity_Ref,
	instance: Card_Instance,
) -> (Effect, bool) {
	switch template.kind {
	case .Damage:
		amount := card_effect_amount(template, instance.upgrade_level)
		return damage_effect(target, amount), true
	case .Heal:
		amount := card_effect_amount(template, instance.upgrade_level)
		return heal_effect(target, amount), true
	case .Gain_Gold:
		amount := card_effect_amount(template, instance.upgrade_level)
		return gain_gold_effect(amount), true
	case .Draw_Cards:
		amount := card_effect_amount(template, instance.upgrade_level)
		return draw_cards_effect(amount), true
	case .Discard_Cards:
		amount := card_effect_amount(template, instance.upgrade_level)
		return discard_cards_effect(amount), true
	case .Create_Card:
		amount := card_effect_amount(template, instance.upgrade_level)
		return create_card_effect(template.card_definition, amount), true
	case .Apply_Status:
		amount := card_effect_amount(template, instance.upgrade_level)
		return apply_status_effect(target, template.status, amount, template.duration), true
	case .Remove_Status:
		return remove_status_effect(target, template.status), true
	case .Add_Reaction_Binding:
		amount := card_effect_amount(template, instance.upgrade_level)
		return add_reaction_binding_effect(
			target,
			template.reaction,
			amount,
			template.charges,
			template.duration,
			template.priority_modifier,
			{kind = .Card, id = instance.id},
		), true
	case .Move:
		return {}, false
	}
	return {}, false
}

card_effect_target :: proc(selector: Card_Target_Selector, chosen: Target) -> (Entity_Ref, bool) {
	switch selector {
	case .Chosen_Entity:
		return chosen.entity, chosen.kind == .Entity
	case .Player:
		return PLAYER_ENTITY, true
	case .Each_Enemy, .Each_Affected_Enemy, .Count:
		return {}, false
	}
	return {}, false
}

Card_Target_Evaluation :: struct {
	query:                 Target_Query_Result,
	error:                 Card_Compile_Error,
	required_effect_count: int,
}

card_target_request_at :: proc(
	definition: Card_Definition,
	position: grid.Position,
) -> Target_Request {
	if definition.targeting.shape == .None {
		return {}
	}
	return {anchor = position, has_anchor = true}
}

card_target_request_from_target :: proc(
	room: ^Room,
	definition: Card_Definition,
	target: Target,
) -> (Target_Request, bool) {
	if definition.targeting.shape == .None {
		return {}, true
	}
	switch target.kind {
	case .Entity:
		position, found := entity_position(room, target.entity)
		return Target_Request{anchor = position, has_anchor = found}, found
	case .Cell:
		return Target_Request{anchor = target.cell, has_anchor = true}, true
	case .None:
	}
	return {}, false
}

card_compile_error_from_query :: proc(err: Target_Query_Error) -> Card_Compile_Error {
	switch err {
	case .None:
		return .None
	case .Invalid_Room:
		return .Invalid_Room
	case .Invalid_Spec:
		return .Invalid_Definition
	case .Anchor_Out_Of_Range:
		return .Target_Out_Of_Range
	case .Line_Of_Sight_Blocked:
		return .Target_Blocked
	case .Invalid_Source, .Missing_Anchor, .Anchor_Out_Of_Bounds,
	     .Shape_Not_Aligned, .Invalid_Primary_Target, .Capacity_Exceeded:
		return .Invalid_Target
	}
	return .Invalid_Target
}

evaluate_card_targeting :: proc(
	room: ^Room,
	instance: Card_Instance,
	request: Target_Request,
) -> (evaluation: Card_Target_Evaluation) {
	evaluation.error = .Invalid_Room
	if room == nil || room.player == nil {
		return
	}
	evaluation.error = .Invalid_Phase
	if room.phase != .Combat {
		return
	}
	evaluation.error = .Invalid_Instance
	if instance.id == 0 || instance.upgrade_level < 0 || instance.upgrade_level > MAX_CARD_UPGRADE_LEVEL ||
	   int(instance.lifetime) < 0 || int(instance.lifetime) >= int(Card_Lifetime.Count) {
		return
	}
	definition, found := card_definition_by_id(instance.definition_id)
	if !found {
		evaluation.error = .Unknown_Definition
		return
	}
	evaluation.error = .Invalid_Definition
	if !validate_card_definition(&definition) {
		return
	}
	evaluation.error = .Invalid_Instance
	if !validate_card_instance(instance) {
		return
	}
	evaluation.query = evaluate_target_query(room, PLAYER_ENTITY, definition.targeting, request)
	evaluation.error = card_compile_error_from_query(evaluation.query.error)
	if evaluation.error != .None {
		return
	}

	for index in 0..<definition.effect_count {
		switch definition.effects[index].target {
		case .Each_Enemy:
			evaluation.required_effect_count += len(room.enemies)
		case .Each_Affected_Enemy:
			evaluation.required_effect_count += evaluation.query.enemy_count
		case .Chosen_Entity, .Player:
			evaluation.required_effect_count += 1
		case .Count:
		}
	}
	if evaluation.required_effect_count == 0 {
		evaluation.error = .No_Effects
		return
	}
	if evaluation.required_effect_count > MAX_ACTION_EFFECTS {
		evaluation.error = .Too_Many_Effects
		return
	}
	return
}

compile_card_action :: proc(
	room: ^Room,
	instance: Card_Instance,
	target: Target,
) -> (action: Action, err: Card_Compile_Error) {
	if room == nil || room.player == nil {
		return {}, .Invalid_Room
	}
	if room.phase != .Combat {
		return {}, .Invalid_Phase
	}
	if instance.id == 0 || instance.upgrade_level < 0 || instance.upgrade_level > MAX_CARD_UPGRADE_LEVEL ||
	   int(instance.lifetime) < 0 || int(instance.lifetime) >= int(Card_Lifetime.Count) {
		return {}, .Invalid_Instance
	}
	definition, found := card_definition_by_id(instance.definition_id)
	if !found {
		return {}, .Unknown_Definition
	}
	if !validate_card_definition(&definition) {
		return {}, .Invalid_Definition
	}
	if !validate_card_instance(instance) {
		return {}, .Invalid_Instance
	}
	request, has_request := card_target_request_from_target(room, definition, target)
	if !has_request {
		return {}, .Invalid_Target
	}
	evaluation := evaluate_card_targeting(room, instance, request)
	if evaluation.error != .None {
		return {}, evaluation.error
	}
	if !evaluation.query.has_primary_target || evaluation.query.primary_target != target {
		return {}, .Invalid_Target
	}

	action = make_action(.Card, PLAYER_ENTITY, target, definition.targeting.rule)
	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		if template.target == .Each_Enemy {
			ids, count := enemy_ids_in_planning_order(room)
			for enemy_index in 0..<count {
				effect, instantiated := instantiate_card_effect(
					template,
					enemy_entity(ids[enemy_index]),
					instance,
				)
				assert(instantiated && add_effect(&action, effect))
			}
			continue
		}
		if template.target == .Each_Affected_Enemy {
			for enemy_index in 0..<evaluation.query.enemy_count {
				effect, instantiated := instantiate_card_effect(
					template,
					enemy_entity(evaluation.query.enemy_ids[enemy_index]),
					instance,
				)
				assert(instantiated && add_effect(&action, effect))
			}
			continue
		}

		effect_target, has_target := card_effect_target(template.target, target)
		assert(has_target)
		effect, instantiated := instantiate_card_effect(template, effect_target, instance)
		assert(instantiated && add_effect(&action, effect))
	}
	return action, .None
}
