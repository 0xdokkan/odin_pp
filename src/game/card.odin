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
	Shove,
	Dash,
	Grappling_Hook,
	Heavy_Blow,
	Venom_Needle,
	Caustic_Bloom,
	Purifying_Guard,
	Volatile_Study,
	Fate_Strike,
	Chain_Lightning,
	Sundering_Blow,
	Prismatic_Barrage,
	Twin_Venom,
	Count,
}

card_dice_count :: proc(id: Card_Id) -> int {
	if id == .Fate_Strike { return 1 }
	if id == .Sundering_Blow || id == .Twin_Venom { return 2 }
	if id == .Prismatic_Barrage { return 3 }
	return 0
}

Card_Target_Selector :: enum {
	Chosen_Entity,
	Player,
	Each_Enemy,
	Each_Affected_Enemy,
	Count,
}

Card_Movement_Kind :: enum {
	None,
	Player_To_Anchor,
	Away_From_Player,
	Adjacent_To_Player,
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
	movement:           Card_Movement_Kind,
	movement_distance:  int,
	affects_objects:    bool,
}

Card_Definition :: struct {
	tactical: bool,
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
			rule = .Opponent_Or_Object,
			cast_range = {.Manhattan, 1, 1},
			shape = .Single,
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
		id = .Arc_Bolt,
		name = "Arc Bolt",
		rarity = .Common,
		reward_weight = 90,
		shop_base_price = 3,
		cost = 2,
		targeting = {
			rule = .Opponent_Or_Object,
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
				affects_objects = true,
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
	{
		id = .Shove,
		name = "Shove",
		rarity = .Common,
		reward_weight = 90,
		shop_base_price = 4,
		cost = 1,
		targeting = {
			rule = .Opponent_Or_Object,
			cast_range = {.Manhattan, 1, 1},
			shape = .Single,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 1,
				amount_per_upgrade = 1,
			},
			{
				kind = .Move,
				target = .Chosen_Entity,
				movement = .Away_From_Player,
				movement_distance = 1,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Dash,
		name = "Dash",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 5,
		cost = 2,
		targeting = {
			rule = .Walkable_Cell,
			cast_range = {.Chebyshev, 1, 3},
			shape = .Line,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Move,
				target = .Player,
				movement = .Player_To_Anchor,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Grappling_Hook,
		name = "Grappling Hook",
		rarity = .Rare,
		reward_weight = 60,
		shop_base_price = 8,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Chebyshev, 2, 4},
			shape = .Line,
			requires_line_of_sight = true,
			stops_on_wall = true,
			stops_on_actor = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 1,
				amount_per_upgrade = 1,
			},
			{
				kind = .Move,
				target = .Chosen_Entity,
				movement = .Adjacent_To_Player,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Heavy_Blow,
		name = "Heavy Blow",
		rarity = .Common,
		reward_weight = 85,
		shop_base_price = 4,
		cost = 2,
		targeting = {
			rule = .Adjacent_Opponent,
			cast_range = {.Manhattan, 1, 1},
			shape = .Single,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 5,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Venom_Needle,
		name = "Venom Needle",
		rarity = .Common,
		reward_weight = 85,
		shop_base_price = 4,
		cost = 1,
		targeting = {
			rule = .Opponent,
			cast_range = {.Chebyshev, 1, 3},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 1,
				amount_per_upgrade = 1,
			},
			{
				kind = .Apply_Status,
				target = .Chosen_Entity,
				base_amount = 1,
				status = .Poison,
				duration = 3,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Caustic_Bloom,
		name = "Caustic Bloom",
		rarity = .Uncommon,
		reward_weight = 70,
		shop_base_price = 6,
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
				kind = .Apply_Status,
				target = .Each_Affected_Enemy,
				base_amount = 2,
				amount_per_upgrade = 1,
				status = .Poison,
				duration = 2,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	{
		id = .Purifying_Guard,
		name = "Purifying Guard",
		rarity = .Uncommon,
		reward_weight = 80,
		shop_base_price = 5,
		cost = 1,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Apply_Status,
				target = .Player,
				base_amount = 2,
				amount_per_upgrade = 1,
				status = .Shield,
				duration = 3,
			},
			{
				kind = .Remove_Status,
				target = .Player,
				status = .Poison,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Volatile_Study,
		name = "Volatile Study",
		rarity = .Rare,
		reward_weight = 60,
		shop_base_price = 8,
		cost = 2,
		exhaust_on_play = true,
		ethereal = true,
		targeting = {rule = .Self},
		effects = {
			{
				kind = .Create_Card,
				target = .Player,
				base_amount = 1,
				card_definition = .Spark,
				has_card_definition = true,
			},
			{
				kind = .Draw_Cards,
				target = .Player,
				base_amount = 1,
				amount_per_upgrade = 1,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	{
		id = .Fate_Strike,
		name = "Fate Strike",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 6,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 4},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {{kind = .Damage, target = .Chosen_Entity, base_amount = 2, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	{
		id = .Chain_Lightning,
		name = "Chain Lightning",
		rarity = .Rare,
		reward_weight = 65,
		shop_base_price = 8,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 4},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {{kind = .Damage, target = .Chosen_Entity, base_amount = 3, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	{
		id = .Sundering_Blow,
		name = "Sundering Blow",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 6,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 2},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{kind = .Damage, target = .Chosen_Entity, base_amount = 2, amount_per_upgrade = 1},
			{kind = .Move, target = .Chosen_Entity, movement = .Away_From_Player, movement_distance = 1},
			{}, {},
		},
		effect_count = 2,
	},
	{
		id = .Prismatic_Barrage,
		name = "Prismatic Barrage",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 6,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 3},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{kind = .Apply_Status, target = .Player, base_amount = 1, status = .Shield, duration = 2},
			{kind = .Damage, target = .Chosen_Entity, base_amount = 3, amount_per_upgrade = 1},
			{}, {},
		},
		effect_count = 2,
	},
	{
		id = .Twin_Venom,
		name = "Twin Venom",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 6,
		cost = 2,
		targeting = {
			rule = .Opponent,
			cast_range = {.Manhattan, 1, 3},
			shape = .Single,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{kind = .Damage, target = .Chosen_Entity, base_amount = 2, amount_per_upgrade = 1},
			{kind = .Apply_Status, target = .Chosen_Entity, base_amount = 2, status = .Poison, duration = 2},
			{}, {},
		},
		effect_count = 2,
	},
}

card_drop_target :: proc(
	room: ^Room,
	instance: Card_Instance,
	position: grid.Position,
) -> (Target, bool) {
	if room == nil || room.player == nil || room.level_data == nil {
		return {}, false
	}
	definition, found := card_definition_by_id(instance.definition_id, tactical_enabled(room))
	if !found {
		return {}, false
	}
	request := card_target_request_at(definition, position)
	evaluation := evaluate_card_targeting(room, instance, request)
	return evaluation.query.primary_target,
	       evaluation.error == .None && evaluation.query.has_primary_target
}

card_target_rule_selects_effect_entity :: proc(rule: Target_Rule) -> bool {
	switch rule {
	case .Self, .Player, .Opponent, .Opponent_Or_Object, .Adjacent_Opponent:
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

card_movement_template_is_valid :: proc(
	definition: ^Card_Definition,
	template: Card_Effect_Template,
) -> bool {
	if definition == nil || template.kind != .Move ||
	   template.base_amount != 0 || template.amount_per_upgrade != 0 {
		return false
	}
	switch template.movement {
	case .None:
		return false
	case .Player_To_Anchor:
		return template.target == .Player && template.movement_distance == 0 &&
		       definition.targeting.rule == .Walkable_Cell &&
		       definition.targeting.shape == .Line
	case .Away_From_Player:
		return template.target == .Chosen_Entity && template.movement_distance > 0 &&
		       template.movement_distance <= MAX_MOVEMENT_PATH_CELLS &&
		       card_target_rule_selects_effect_entity(definition.targeting.rule)
	case .Adjacent_To_Player:
		return template.target == .Chosen_Entity && template.movement_distance == 0 &&
		       card_target_rule_selects_effect_entity(definition.targeting.rule) &&
		       definition.targeting.shape == .Line
	}
	return false
}

card_effect_template_is_valid :: proc(
	definition: ^Card_Definition,
	template: Card_Effect_Template,
) -> bool {
	if definition == nil || int(template.target) < 0 || int(template.target) >= int(Card_Target_Selector.Count) ||
	   (template.target == .Chosen_Entity && !card_target_rule_selects_effect_entity(definition.targeting.rule)) ||
	   (template.target == .Each_Affected_Enemy && definition.targeting.shape == .None) ||
	   (template.affects_objects && (template.kind != .Damage || template.target != .Each_Affected_Enemy)) ||
	   (template.kind != .Move &&
	    (template.movement != .None || template.movement_distance != 0)) {
		return false
	}

	switch template.kind {
	case .Gain_Energy:
		return false
	case .Move:
		return card_movement_template_is_valid(definition, template)
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
	movement_count := 0
	for index in 0..<definition.effect_count {
		if definition.effects[index].kind == .Move {
			movement_count += 1
		}
	}
	if movement_count > 1 {
		return false
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

card_definition_by_id :: proc(id: Card_Id, tactical: bool = false) -> (Card_Definition, bool) {
	definitions := CARD_DEFINITIONS
	index := int(id)
	if index < 0 || index >= len(definitions) {
		return {}, false
	}
	definition := definitions[index]
	if tactical { rework_tactical_card(&definition) }
	return definition, true
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

// Gli upgrade correnti scalano soltanto gli importi degli effetti. Non vendere
// livelli privi di benefici, anche quando l'istanza e formalmente valida.
card_can_upgrade :: proc(instance: Card_Instance) -> bool {
	if !validate_card_instance(instance) || instance.lifetime != .Permanent ||
	   instance.upgrade_level >= MAX_CARD_UPGRADE_LEVEL {
		return false
	}
	definition, _ := card_definition_by_id(instance.definition_id)
	for index in 0..<definition.effect_count {
		if definition.effects[index].amount_per_upgrade > 0 {
			return true
		}
	}
	return false
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
	case .Move, .Gain_Energy:
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
	movement:              Movement_Query,
	has_movement:          bool,
	movement_required:     bool,
	error:                 Card_Compile_Error,
	required_effect_count: int,
}

card_movement_destination :: proc(
	room: ^Room,
	template: Card_Effect_Template,
	target: Entity_Ref,
	query: ^Target_Query_Result,
) -> (destination: grid.Position, ok: bool) {
	if room == nil || room.player == nil || query == nil || template.kind != .Move {
		return
	}
	switch template.movement {
	case .None:
		return
	case .Player_To_Anchor:
		return query.anchor, target == PLAYER_ENTITY
	case .Away_From_Player:
		target_position, found := entity_position(room, target)
		if !found || !targeting_line_is_aligned(room.player.position, target_position) {
			return
		}
		step := grid.Position{
			x = sign(target_position.x-room.player.position.x),
			y = sign(target_position.y-room.player.position.y),
		}
		return grid.Position{
			x = target_position.x+step.x*template.movement_distance,
			y = target_position.y+step.y*template.movement_distance,
		}, true
	case .Adjacent_To_Player:
		target_position, found := entity_position(room, target)
		if !found || !targeting_line_is_aligned(target_position, room.player.position) {
			return
		}
		distance := max(
			abs(target_position.x-room.player.position.x),
			abs(target_position.y-room.player.position.y),
		)
		if distance <= 1 {
			return
		}
		step := grid.Position{
			x = sign(room.player.position.x-target_position.x),
			y = sign(room.player.position.y-target_position.y),
		}
		return grid.Position{
			x = room.player.position.x-step.x,
			y = room.player.position.y-step.y,
		}, true
	}
	return
}

card_compile_error_from_movement :: proc(err: Movement_Error) -> Card_Compile_Error {
	switch err {
	case .None:
		return .None
	case .Static_Blocker, .Actor_Blocker, .Object_Blocker:
		return .Target_Blocked
	case .Invalid_Room:
		return .Invalid_Room
	case .Invalid_Mover, .Same_Position, .Destination_Out_Of_Bounds,
	     .Path_Not_Aligned, .Path_Too_Long:
		return .Invalid_Target
	}
	return .Invalid_Target
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
	definition, found := card_definition_by_id(instance.definition_id, tactical_enabled(room))
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
	if tactical_enabled(room) && request.has_anchor && !tactical_cell_visible(room, request.anchor) {
		evaluation.error = .Invalid_Target
		return
	}
	evaluation.query = evaluate_target_query(room, PLAYER_ENTITY, definition.targeting, request)
	evaluation.error = card_compile_error_from_query(evaluation.query.error)
	if evaluation.error != .None {
		return
	}

	if tactical_enabled(room) {
		visible_cells := 0
		for cell in evaluation.query.affected.cells[:evaluation.query.affected.count] {
			if !tactical_cell_visible(room, cell) { continue }
			evaluation.query.affected.cells[visible_cells] = cell
			visible_cells += 1
		}
		evaluation.query.affected.count = visible_cells
		visible_enemies := 0
		for id in evaluation.query.enemy_ids[:evaluation.query.enemy_count] {
			i, present := enemy_index_by_id(room, id)
			if !present || !tactical_card_enemy_in_area(room, instance.definition_id, room.enemies[i].position) { continue }
			evaluation.query.enemy_ids[visible_enemies] = id
			visible_enemies += 1
		}
		evaluation.query.enemy_count = visible_enemies
	}

	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		if template.kind != .Move {
			continue
		}
		evaluation.has_movement = true
		evaluation.movement_required = definition.effect_count == 1 || template.movement == .Player_To_Anchor
		if definition.targeting.stops_on_actor &&
		   !target_cell_set_contains(&evaluation.query.affected, evaluation.query.anchor) {
			evaluation.error = .Target_Blocked
			return
		}
		effect_target, has_target := card_effect_target(
			template.target,
			evaluation.query.primary_target,
		)
		if !has_target {
			evaluation.error = .Invalid_Target
			return
		}
		destination, has_destination := card_movement_destination(
			room,
			template,
			effect_target,
			&evaluation.query,
		)
		if !has_destination {
			evaluation.error = .Invalid_Target
			return
		}
		evaluation.movement = query_entity_movement(room, effect_target, destination)
		if evaluation.movement_required && evaluation.movement.error != .None {
			evaluation.error = card_compile_error_from_movement(evaluation.movement.error)
			return
		}
	}

	for index in 0..<definition.effect_count {
		switch definition.effects[index].target {
		case .Each_Enemy:
			for enemy in room.enemies {
				if tactical_card_enemy_in_area(room, instance.definition_id, enemy.position) { evaluation.required_effect_count += 1 }
			}
		case .Each_Affected_Enemy:
			evaluation.required_effect_count += evaluation.query.enemy_count
			if definition.effects[index].affects_objects {
				_, object_count := affected_damageable_object_ids(room, &evaluation.query.affected)
				evaluation.required_effect_count += object_count
			}
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
	definition, found := card_definition_by_id(instance.definition_id, tactical_enabled(room))
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
	if instance.definition_id == .Chain_Lightning {
		path := query_spell_path(room, instance, target)
		if path.error != .None { return {}, path.error }
		for entity in path.targets[:path.count] {
			effect, valid := instantiate_card_effect(definition.effects[0], entity, instance)
			if !valid || !add_effect(&action, effect) { return {}, .Too_Many_Effects }
		}
		return action, .None
	}
	// Fate's template is its deterministic base. The die is materialized only by
	// resolve_played_card_action after all play validation and payment checks.
	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		if template.kind == .Move {
			effect_target, has_target := card_effect_target(template.target, target)
			assert(has_target && evaluation.has_movement)
			destination, has_destination := card_movement_destination(
				room,
				template,
				effect_target,
				&evaluation.query,
			)
			assert(has_destination)
			if !add_effect(&action, move_effect(effect_target, destination)) {
				return {}, .Too_Many_Effects
			}
			continue
		}
		if template.target == .Each_Enemy {
			ids, count := enemy_ids_in_planning_order(room)
			for enemy_index in 0..<count {
				entity_index, _ := enemy_index_by_id(room, ids[enemy_index])
				if !tactical_card_enemy_in_area(room, instance.definition_id, room.enemies[entity_index].position) { continue }
				effect, instantiated := instantiate_card_effect(
					template,
					enemy_entity(ids[enemy_index]),
					instance,
				)
				if !instantiated {
					return {}, .Invalid_Definition
				}
				if !add_effect(&action, effect) {
					return {}, .Too_Many_Effects
				}
			}
			continue
		}
		if template.target == .Each_Affected_Enemy {
			if template.affects_objects {
				ids, count := affected_damageable_object_ids(room, &evaluation.query.affected)
				for id in ids[:count] {
					effect, valid := instantiate_card_effect(template, object_entity(id), instance)
					if !valid || !add_effect(&action, effect) {
						return {}, .Too_Many_Effects
					}
				}
			}
			for enemy_index in 0..<evaluation.query.enemy_count {
				effect, instantiated := instantiate_card_effect(
					template,
					enemy_entity(evaluation.query.enemy_ids[enemy_index]),
					instance,
				)
				if !instantiated {
					return {}, .Invalid_Definition
				}
				if !add_effect(&action, effect) {
					return {}, .Too_Many_Effects
				}
			}
			continue
		}

		effect_target, has_target := card_effect_target(template.target, target)
		assert(has_target)
		effect, instantiated := instantiate_card_effect(template, effect_target, instance)
		if instance.definition_id == .Strike && effect.kind == .Damage { effect.amount += tactical_strike_bonus(room, effect_target) }
		if !instantiated {
			return {}, .Invalid_Definition
		}
		if !add_effect(&action, effect) {
			return {}, .Too_Many_Effects
		}
	}
	return action, .None
}

card_requires_spatial_target :: proc(definition: Card_Definition) -> bool {
	return definition.targeting.shape != .None
}
