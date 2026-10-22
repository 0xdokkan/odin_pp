package game

import grid "../engine/grid"

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
	Shock_Floor,
	Tesla_Coil,
	Titan_Grip,
	Storm_Crown,
	Sei_Denari,
	Sette_Denari,
	Shadow_Step,
	Poison_Pool,
	Wildfire,
	Deflect,
	Coffin,
	Fate_Dice,
	Venom_Blade,
	Lasso,
	Fishing_Rod,
	Pinball,
	First_Person,
	Cannon, Flood, Black_Hole, Bomb_Marley, Dinosaur,
	Count,
}

// Static card traits live with the definition; rules, previews and menus query
// these through the existing predicates instead of maintaining card lists.
Card_Trait :: enum { Scopa, Room_Tool, Player_Charge, Board_Device, Ground }

@(private = "file")
card_has_trait :: proc(id: Card_Id, trait: Card_Trait) -> bool {
	return id >= .Strike && id < .Count && trait in CARD_DEFINITIONS[id].traits
}

card_is_scopa :: proc(id: Card_Id) -> bool { return card_has_trait(id, .Scopa) }
// A room tool waits in Exhaust during combat and uses its own slot after it.
card_is_room_tool :: proc(id: Card_Id) -> bool { return card_has_trait(id, .Room_Tool) }
@(private)
card_loads_player_charge :: proc(id: Card_Id) -> bool { return card_has_trait(id, .Player_Charge) }
card_is_board_device :: proc(id: Card_Id) -> bool { return card_has_trait(id, .Board_Device) }
card_places_ground :: proc(id: Card_Id) -> bool { return card_has_trait(id, .Ground) }

card_dice_count :: proc(id: Card_Id) -> int {
	return CARD_DEFINITIONS[id].dice_count if id >= .Strike && id < .Count else 0
}

// Dice upgrades climb the shared ladder; special tools keep their own caps.
card_max_upgrade_level :: proc(id: Card_Id) -> i32 {
	return CARD_DEFINITIONS[id].upgrade_limit if id >= .Strike && id < .Count else MAX_CARD_UPGRADE_LEVEL
}

// The cast's price, shared by gameplay, the hand and the inspector. A lasting
// effect's own seconds (shadow, lasso, pinball, FPS) belong to its mechanic.
tactical_card_time_cost :: proc(id: Card_Id) -> f32 {
	return CARD_DEFINITIONS[id].time_cost if id >= .Strike && id < .Count else 0
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
	// PINBALL: a boss or a miniboss is too heavy to become a ball.
	Target_Too_Heavy,
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
	object_kind:        Grid_Object_Kind,
}

Card_Definition :: struct {
	traits:          bit_set[Card_Trait],
	dice_count:      int,
	upgrade_limit:   i32,
	time_cost:       f32,
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

// An exhaustive enum array: adding a Card_Id without its definition is a
// compile error. Count is explicitly invalid and never enters an offer pool.
// Read-only storage avoids copying the full catalog for a dynamic lookup.
@(private, rodata)
CARD_DEFINITIONS := [Card_Id]Card_Definition{
	.Strike = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
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
	.Arc_Bolt = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		id = .Arc_Bolt,
		name = "Arc Bolt",
		rarity = .Common,
		reward_weight = 90,
		shop_base_price = 3,
		cost = 1,
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
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Piercing_Ray = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 3,
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
				base_amount = 3,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Cross_Slash = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 3,
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
				base_amount = 3,
				amount_per_upgrade = 1,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Firebomb = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 4,
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
	.Guard = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 4,
				amount_per_upgrade = 1,
				status = .Shield,
				duration = 2,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Toxic_Wave = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 4,
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
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Thorn_Coat = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 2,
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
	.Afterimage = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
	.Counter_Rune = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 3,
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
	.Battle_Focus = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
			{kind = .Apply_Status, target = .Player, status = .Survey, base_amount = 1, duration = 3},
			{},
			{},
		},
		effect_count = 2,
	},
	.Calculated_Risk = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
	.Spark_Forge = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 2,
				card_definition = .Spark,
				has_card_definition = true,
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Spark = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
	.Shove = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
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
				kind = .Move,
				target = .Chosen_Entity,
				movement = .Away_From_Player,
				movement_distance = 1,
			},
			{
				kind = .Damage,
				target = .Chosen_Entity,
				base_amount = 1,
				amount_per_upgrade = 1,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	.Dash = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		id = .Dash,
		name = "Dash",
		rarity = .Uncommon,
		reward_weight = 75,
		shop_base_price = 5,
		cost = 1,
		targeting = {
			rule = .Walkable_Cell,
			cast_range = {.Chebyshev, 1, 4},
			shape = .Line,
			requires_line_of_sight = true,
			stops_on_wall = true,
		},
		effects = {
			{kind = .Apply_Status, target = .Player, status = .Shield, base_amount = 2, duration = 2},
			{
				kind = .Move,
				target = .Player,
				movement = .Player_To_Anchor,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	.Grappling_Hook = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		id = .Grappling_Hook,
		name = "Grappling Hook",
		rarity = .Rare,
		reward_weight = 60,
		shop_base_price = 8,
		cost = 1,
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
	.Heavy_Blow = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 3,
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
				base_amount = 4,
				amount_per_upgrade = 1,
			},
			{kind = .Apply_Status, target = .Chosen_Entity, status = .Stagger, base_amount = 1, duration = 1},
			{},
			{},
		},
		effect_count = 2,
	},
	.Venom_Needle = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
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
				base_amount = 2,
				status = .Poison,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	.Caustic_Bloom = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 4,
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
			},
			{},
			{},
			{},
		},
		effect_count = 1,
	},
	.Purifying_Guard = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 3,
				amount_per_upgrade = 1,
				status = .Shield,
				duration = 2,
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
	.Volatile_Study = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
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
				base_amount = 2,
				amount_per_upgrade = 1,
			},
			{},
			{},
		},
		effect_count = 2,
	},
	.Fate_Strike = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 2,
		dice_count = 1,
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
		effects = {{kind = .Damage, target = .Chosen_Entity, base_amount = 2}, {}, {}, {}},
		effect_count = 1,
	},
	.Chain_Lightning = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 4,
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
	.Sundering_Blow = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 3,
		dice_count = 2,
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
			{kind = .Damage, target = .Chosen_Entity, base_amount = 2},
			{kind = .Move, target = .Chosen_Entity, movement = .Away_From_Player, movement_distance = 1},
			{}, {},
		},
		effect_count = 2,
	},
	.Prismatic_Barrage = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 4,
		dice_count = 3,
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
			{kind = .Damage, target = .Chosen_Entity, base_amount = 3},
			{}, {},
		},
		effect_count = 2,
	},
	.Twin_Venom = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 3,
		dice_count = 2,
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
			{kind = .Damage, target = .Chosen_Entity, base_amount = 2},
			{kind = .Apply_Status, target = .Chosen_Entity, base_amount = 2, status = .Poison},
			{}, {},
		},
		effect_count = 2,
	},
	.Shock_Floor = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 3,
		traits = {.Board_Device}, dice_count = 1,
		id = .Shock_Floor, name = "Shock Floor", rarity = .Uncommon,
		reward_weight = 85, shop_base_price = 6, cost = 2,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 3}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 1, object_kind = .Shock_Floor}, {}, {}, {}},
		effect_count = 1,
	},
	.Tesla_Coil = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		traits = {.Board_Device},
		id = .Tesla_Coil, name = "Tesla Coil", rarity = .Uncommon,
		reward_weight = 90, shop_base_price = 5, cost = 1,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 3}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 8, amount_per_upgrade = 1, object_kind = .Tesla_Coil}, {}, {}, {}},
		effect_count = 1,
	},
	.Titan_Grip = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 3,
		id = .Titan_Grip, name = "Titan Grip", rarity = .Rare,
		reward_weight = 65, shop_base_price = 9, cost = 2,
		targeting = {rule = .Opponent, cast_range = {.Manhattan, 1, 1}, shape = .Single},
		effects = {
			{kind = .Damage, target = .Chosen_Entity, base_amount = 3, amount_per_upgrade = 1},
			{kind = .Move, target = .Chosen_Entity, movement = .Away_From_Player, movement_distance = 2},
			{kind = .Apply_Status, target = .Chosen_Entity, base_amount = 1, status = .Stagger, duration = 1}, {},
		}, effect_count = 3,
	},
	.Storm_Crown = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 4,
		id = .Storm_Crown, name = "Storm Crown", rarity = .Rare,
		reward_weight = 35, shop_base_price = 12, cost = 3,
		targeting = {rule = .Opponent, cast_range = {.Manhattan, 1, 4}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Damage, target = .Chosen_Entity, base_amount = 5, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	.Sei_Denari = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Scopa},
		id = .Sei_Denari, name = "6 di denari", rarity = .Common,
		reward_weight = 1, shop_base_price = 6, cost = 1, exhaust_on_play = true,
		targeting = {rule = .Self},
		effects = {{kind = .Gain_Gold, target = .Player, base_amount = 6}, {}, {}, {}},
		effect_count = 1,
	},
	.Sette_Denari = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Scopa},
		id = .Sette_Denari, name = "7 di denari", rarity = .Common,
		reward_weight = 1, shop_base_price = 7, cost = 1, exhaust_on_play = true,
		targeting = {rule = .Self},
		effects = {{kind = .Gain_Gold, target = .Player, base_amount = 7}, {}, {}, {}},
		effect_count = 1,
	},
	.Shadow_Step = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 0,
		// Four real seconds inside the player's shadow (tactical_shadow.odin).
		// Its length never scales: there is no upgrade.
		id = .Shadow_Step, name = "Movimento Ombra", rarity = .Rare,
		reward_weight = 60, shop_base_price = 8, cost = 3,
		targeting = {rule = .Self},
		effects = {{kind = .Enter_Shadow, target = .Player, base_amount = 4}, {}, {}, {}},
		effect_count = 1,
	},
	.Poison_Pool = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Ground},
		// A pool of poison on a free cell for the rest of the room: Veleno 2 (+1
		// per upgrade) to an enemy for each of its cells it enters; the areas
		// pools close fill by themselves (ground.odin).
		id = .Poison_Pool, name = "Pozza di Veleno", rarity = .Common,
		reward_weight = 85, shop_base_price = 4, cost = 1,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 3}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Place_Ground, target = .Player, base_amount = 2, amount_per_upgrade = 1, status = .Poison}, {}, {}, {}},
		effect_count = 1,
	},
	.Wildfire = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		traits = {.Ground},
		// A fire on a free cell that grows as a plus at each new window and goes
		// out at the fifth: Bruciatura 1 (+1 per upgrade) to an enemy entering a
		// burning cell, or standing where it catches (ground.odin).
		id = .Wildfire, name = "Incendio", rarity = .Uncommon,
		reward_weight = 75, shop_base_price = 6, cost = 2,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 3}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Place_Ground, target = .Player, base_amount = 1, amount_per_upgrade = 1, status = .Burn}, {}, {}, {}},
		effect_count = 1,
	},
	.Deflect = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Player_Charge},
		// RIFLESSO: the next enemy blow that would hit the player goes back to
		// its attacker (player_charges.odin). Each play adds a charge; no upgrade.
		id = .Deflect, name = "Deflect", rarity = .Uncommon,
		reward_weight = 80, shop_base_price = 5, cost = 1,
		targeting = {rule = .Self},
		effects = {{kind = .Apply_Status, target = .Player, base_amount = 1, status = .Deflect}, {}, {}, {}},
		effect_count = 1,
	},
	.Coffin = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Player_Charge},
		// FRECCE: three arrows (+1 per upgrade), loosed with Ctrl and a click on
		// a foe in the line of fire (shoot_player_arrow). Plays add up.
		id = .Coffin, name = "Feretro", rarity = .Uncommon,
		reward_weight = 75, shop_base_price = 6, cost = 2,
		targeting = {rule = .Self},
		effects = {{kind = .Apply_Status, target = .Player, base_amount = 3, amount_per_upgrade = 1, status = .Arrows}, {}, {}, {}},
		effect_count = 1,
	},
	.Fate_Dice = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Player_Charge}, dice_count = 1,
		// DESTINO: the next three bumps each roll the card's die at the hit
		// (player_bump); a new play loads them back to three. A dice card: its
		// upgrades climb the die.
		id = .Fate_Dice, name = "Dado del Destino", rarity = .Rare,
		reward_weight = 60, shop_base_price = 8, cost = 2,
		targeting = {rule = .Self},
		effects = {{kind = .Apply_Status, target = .Player, base_amount = FATE_DICE_CHARGES, status = .Fate}, {}, {}, {}},
		effect_count = 1,
	},
	.Venom_Blade = {
		upgrade_limit = MAX_DICE_UPGRADE_LEVEL, time_cost = 1,
		traits = {.Player_Charge}, dice_count = 1,
		// LAMA: its die, rolled as it is played, is how many bumps it poisons
		// (resolve_loading_card); the template's one stands for that roll.
		id = .Venom_Blade, name = "Lama Velenosa", rarity = .Common,
		reward_weight = 85, shop_base_price = 4, cost = 1,
		targeting = {rule = .Self},
		effects = {{kind = .Apply_Status, target = .Player, base_amount = 1, status = .Venom_Blade}, {}, {}, {}},
		effect_count = 1,
	},
	.Lasso = {
		upgrade_limit = LASSO_MAX_UPGRADE_LEVEL, time_cost = 2,
		// LAZZO: one foe in reach is caught, lifted and swung round the player
		// (lasso.odin). Its amount is the first hit's number: 1 (+1 per upgrade,
		// +1 on the tick); every next hit strikes one harder.
		id = .Lasso, name = "Lazzo", rarity = .Rare,
		reward_weight = 60, shop_base_price = 8, cost = 2,
		targeting = {rule = .Opponent, cast_range = {.Chebyshev, 1, LASSO_RANGE}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Lasso, target = .Chosen_Entity, base_amount = 1, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	.Fishing_Rod = {
		upgrade_limit = FISHING_ROD_MAX_UPGRADE_LEVEL, time_cost = 0,
		traits = {.Room_Tool},
		// CANNA DA PESCA: never in the hand; once the room is cleared it fishes a
		// free cell in reach, turned to water, from its own slot (fishing.odin).
		// Its amount is the room's fishings: 1 (+1 per upgrade). At most one a run.
		id = .Fishing_Rod, name = "Canna da Pesca", rarity = .Uncommon,
		reward_weight = 70, shop_base_price = 5, cost = 0,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, FISHING_RANGE}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Fish, target = .Player, base_amount = 1, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	.Pinball = {
		upgrade_limit = PINBALL_MAX_UPGRADE_LEVEL, time_cost = 2,
		// PINBALL: one foe beside the player turned into a steel ball and struck
		// away; for twenty seconds it bounces round the room (pinball.odin). Its
		// amount is the ball's value: 2 (+1 per upgrade, +1 on the tick), one
		// more after each foe it strikes, back to it at every wall.
		id = .Pinball, name = "Pinball", rarity = .Rare,
		reward_weight = 60, shop_base_price = 8, cost = 3,
		targeting = {rule = .Opponent, cast_range = {.Chebyshev, 1, PINBALL_RANGE}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Pinball, target = .Chosen_Entity, base_amount = 2, amount_per_upgrade = 1}, {}, {}, {}},
		effect_count = 1,
	},
	.First_Person = {
		upgrade_limit = FIRST_PERSON_MAX_UPGRADE_LEVEL, time_cost = 0,
		// FIRST PERSON SHOOTER: the player's own eyes and a paper AK for twenty
		// seconds of the world's (first_person.odin): +2 per upgrade, +2 on the
		// tick. It takes no window time, and no card is played meanwhile.
		id = .First_Person, name = "First Person Shooter", rarity = .Rare,
		reward_weight = 60, shop_base_price = 8, cost = 3,
		targeting = {rule = .Self},
		effects = {{kind = .First_Person, target = .Player, base_amount = FIRST_PERSON_SECONDS,
			amount_per_upgrade = FIRST_PERSON_SECONDS_PER_UPGRADE}, {}, {}, {}},
		effect_count = 1,
	},
	.Cannon = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2, traits = {.Board_Device},
		id = .Cannon, name = "Cannone", rarity = .Uncommon, reward_weight = 45, shop_base_price = 7, cost = 2,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 5}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 5, amount_per_upgrade = 1, object_kind = .Cannon}, {}, {}, {}},
		effect_count = 1,
	},
	.Flood = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2, traits = {.Board_Device},
		id = .Flood, name = "Inondazione", rarity = .Uncommon, reward_weight = 45, shop_base_price = 7, cost = 2,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 5}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 2, amount_per_upgrade = 1, object_kind = .Flood}, {}, {}, {}},
		effect_count = 1,
	},
	.Black_Hole = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2, traits = {.Board_Device},
		id = .Black_Hole, name = "Buco Nero", rarity = .Rare, reward_weight = 45, shop_base_price = 7, cost = 3,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 5}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 2, amount_per_upgrade = 1, object_kind = .Black_Hole}, {}, {}, {}},
		effect_count = 1,
	},
	.Bomb_Marley = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2, traits = {.Board_Device},
		id = .Bomb_Marley, name = "Bomb Marley", rarity = .Rare, reward_weight = 45, shop_base_price = 7, cost = 3,
		targeting = {rule = .Walkable_Cell, cast_range = {.Chebyshev, 1, 5}, shape = .Single, requires_line_of_sight = true, stops_on_wall = true},
		effects = {{kind = .Deploy_Device, target = .Player, base_amount = 12, amount_per_upgrade = 1, object_kind = .Bomb_Marley}, {}, {}, {}},
		effect_count = 1,
	},
	.Dinosaur = {
		upgrade_limit = MAX_CARD_UPGRADE_LEVEL, time_cost = 2,
		id = .Dinosaur, name = "Dinosauro", rarity = .Rare, reward_weight = 45, shop_base_price = 7, cost = 2,
		targeting = {rule = .Self},
		effects = {{kind = .Apply_Status, target = .Player, base_amount = 5, amount_per_upgrade = 1, status = .Shield, duration = 12}, {}, {}, {}},
		effect_count = 1,
	},
	.Count = {id = .Count},
}

card_drop_target :: proc(
	room: ^Room,
	instance: Card_Instance,
	position: grid.Position,
) -> (Target, bool) {
	if room == nil || room.player == nil || room.level_data == nil {
		return {}, false
	}
	definition, found := card_definition_by_id(instance.definition_id)
	if !found {
		return {}, false
	}
	request := card_target_request_at(definition, position)
	evaluation := evaluate_card_targeting(room, instance, request)
	return evaluation.query.primary_target,
	       evaluation.error == .None && evaluation.query.has_primary_target
}

@(private = "file")
card_target_rule_selects_effect_entity :: proc(rule: Target_Rule) -> bool {
	switch rule {
	case .Self, .Player, .Opponent, .Opponent_Or_Object, .Adjacent_Opponent:
		return true
	case .Any, .None, .Entity, .Cell, .Walkable_Cell:
		return false
	}
	return false
}

@(private = "file")
card_amount_template_is_valid :: proc(template: Card_Effect_Template) -> bool {
	if template.base_amount <= 0 || template.amount_per_upgrade < 0 {
		return false
	}
	maximum := i64(template.base_amount)+i64(template.amount_per_upgrade)*i64(MAX_CARD_UPGRADE_LEVEL)
	return maximum <= i64(max(i32))
}

@(private = "file")
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

@(private)
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
	case .Enter_Shadow:
		return template.target == .Player && definition.targeting.rule == .Self &&
		       template.amount_per_upgrade == 0 && card_amount_template_is_valid(template)
	// One foe chosen on its cell; the amount is the first hit's number.
	case .Lasso:
		return template.target == .Chosen_Entity && definition.targeting.rule == .Opponent &&
		       definition.targeting.shape == .Single && card_amount_template_is_valid(template)
	// One foe beside the player; the amount is the ball's value.
	case .Pinball:
		return template.target == .Chosen_Entity && definition.targeting.rule == .Opponent &&
		       definition.targeting.shape == .Single && definition.targeting.cast_range.maximum == PINBALL_RANGE &&
		       card_amount_template_is_valid(template)
	// A cell to fish; the amount is the room's fishings.
	case .Fish:
		return template.target == .Player && definition.targeting.rule == .Walkable_Cell &&
		       definition.targeting.shape == .Single && card_amount_template_is_valid(template)
	case .Place_Ground:
		// Its stacks are given on entry: no duration.
		return template.target == .Player && definition.targeting.rule == .Walkable_Cell &&
		       definition.targeting.shape == .Single && ground_kind_is_valid(template.status) &&
		       template.duration == 0 && card_amount_template_is_valid(template)
	case .Deploy_Device:
		return template.target == .Player && definition.targeting.rule == .Walkable_Cell &&
		       board_device_kind(template.object_kind) && card_amount_template_is_valid(template)
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
		// Stacks carry no duration; every other status needs one. The player's
		// charges go to the player alone.
		return status_kind_is_valid(template.status) &&
		       (template.duration == 0 if status_kind_stacks(template.status) else template.duration > 0) &&
		       (!status_kind_is_player_charge(template.status) || template.target == .Player) &&
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
	// The player's own seconds behind his eyes.
	case .First_Person:
		return template.target == .Player && definition.targeting.rule == .Self && card_amount_template_is_valid(template)
	}
	return false
}

@(private)
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

@(private)
validate_card_definitions :: proc() -> bool {
	for definition, id in CARD_DEFINITIONS {
		if id == .Count { continue }
		checked := definition
		if definition.id != id || !validate_card_definition(&checked) ||
		   definition.dice_count < 0 || definition.dice_count > MAX_ROLL_DICE ||
		   definition.upgrade_limit < 0 || definition.upgrade_limit > MAX_CARD_UPGRADE_LEVEL ||
		   definition.time_cost < 0 ||
		   (definition.dice_count > 0 && definition.upgrade_limit != MAX_DICE_UPGRADE_LEVEL) { return false }
	}
	return true
}

card_definition_by_id :: proc(id: Card_Id) -> (Card_Definition, bool) {
	if id < .Strike || id >= .Count { return {}, false }
	return CARD_DEFINITIONS[id], true
}

validate_card_instance :: proc(instance: Card_Instance) -> bool {
	if instance.id == 0 || instance.upgrade_level < 0 || instance.upgrade_level > card_max_upgrade_level(instance.definition_id) ||
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
	   instance.upgrade_level >= card_max_upgrade_level(instance.definition_id) {
		return false
	}
	// A dice card's benefit is the next die of its ladder.
	if card_dice_count(instance.definition_id) > 0 { return true }
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

@(private)
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

@(private)
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
	case .Deploy_Device:
		return deploy_device_effect(template.object_kind, {}, card_effect_amount(template, instance.upgrade_level)), true
	case .Enter_Shadow:
		return enter_shadow_effect(card_effect_amount(template, instance.upgrade_level)), true
	case .Place_Ground:
		return place_ground_effect({}, template.status, card_effect_amount(template, instance.upgrade_level)), true
	case .Lasso:
		return lasso_effect(target, card_effect_amount(template, instance.upgrade_level)), true
	case .Pinball:
		return pinball_effect(target, card_effect_amount(template, instance.upgrade_level)), true
	// The rod's fishings, as its amount says; no action ever applies it.
	case .Fish:
		return {kind = .Fish, target = target, amount = card_effect_amount(template, instance.upgrade_level)}, true
	case .Move, .Gain_Energy:
			return {}, false
	case .First_Person:
		return first_person_effect(card_effect_amount(template, instance.upgrade_level)), true
	}
	return {}, false
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

// Both preview and compilation validate the card before resolving a target.
// Keep request conversion outside this helper: the compiler rejects a missing
// entity before applying the card's mode restrictions, as it always has.
@(private="file")
validated_card_definition_for_action :: proc(
	room: ^Room,
	instance: Card_Instance,
) -> (definition: Card_Definition, err: Card_Compile_Error) {
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
	found: bool
	definition, found = card_definition_by_id(instance.definition_id)
	if !found {
		return {}, .Unknown_Definition
	}
	if !validate_card_definition(&definition) {
		return {}, .Invalid_Definition
	}
	// Instance validity includes temporary lifetimes and per-card upgrade limits.
	if !validate_card_instance(instance) {
		return {}, .Invalid_Instance
	}
	return definition, .None
}

evaluate_card_targeting :: proc(
	room: ^Room,
	instance: Card_Instance,
	request: Target_Request,
) -> Card_Target_Evaluation {
	definition, err := validated_card_definition_for_action(room, instance)
	if err != .None {
		return {error = err}
	}
	return evaluate_validated_card_targeting(room, instance, definition, request)
}

@(private="file")
evaluate_validated_card_targeting :: proc(
	room: ^Room,
	instance: Card_Instance,
	definition: Card_Definition,
	request: Target_Request,
	plan: ^Card_Target_Plan = nil,
) -> (evaluation: Card_Target_Evaluation) {
	// The Canna da Pesca is no card to play: its slot fishes (fishing.odin).
	if card_is_room_tool(instance.definition_id) {
		evaluation.error = .Invalid_Phase
		return
	}
	if request.has_anchor && !tactical_cell_visible(room, request.anchor) {
		evaluation.error = .Invalid_Target
		return
	}
	evaluation.query = evaluate_target_query(room, PLAYER_ENTITY, definition.targeting, request)
	evaluation.error = card_compile_error_from_query(evaluation.query.error)
	if evaluation.error != .None {
		return
	}

	if card_is_board_device(instance.definition_id) && !board_device_can_deploy(room, definition.effects[0].object_kind, evaluation.query.anchor) {
		evaluation.error = .Target_Blocked
		return
	}
	// A pool or a fire needs a free cell: no enemy, object or player on it.
	if card_places_ground(instance.definition_id) && !ground_can_place(room, definition.effects[0].status, evaluation.query.anchor) {
		evaluation.error = .Target_Blocked
		return
	}
	// LAZZO: never a boss's weight, and a ring with room to swing the foe.
	if instance.definition_id == .Lasso {
		if refusal := lasso_target_error(room, evaluation.query.primary_target); refusal != .None {
			evaluation.error = refusal
			return
		}
	}
	// PINBALL: never a boss's weight, and one ball at a time.
	if instance.definition_id == .Pinball {
		if refusal := pinball_target_error(room, evaluation.query.primary_target); refusal != .None {
			evaluation.error = refusal
			return
		}
	}

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
		evaluation.movement = low_gravity_movement(room, PLAYER_ENTITY, evaluation.movement)
		if evaluation.movement_required && evaluation.movement.error != .None {
			evaluation.error = card_compile_error_from_movement(evaluation.movement.error)
			return
		}
	}

	targets := build_card_target_plan(room, instance.definition_id, definition, &evaluation.query, plan != nil)
	evaluation.required_effect_count = targets.count
	if plan != nil { plan^ = targets }
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

// The preview counts the same expansion that compilation consumes. Capture is
// local to a compilation: previews need no sorting, target lookup or stored plan.
@(private="file")
Card_Effect_Target :: struct { template_index: int, entity: Entity_Ref }

@(private="file")
Card_Target_Plan :: struct {
	targets: [MAX_ACTION_EFFECTS]Card_Effect_Target,
	count: int,
	capture: bool,
}

@(private="file")
append_card_target :: proc(plan: ^Card_Target_Plan, template_index: int, entity: Entity_Ref) {
	if plan.capture && plan.count < len(plan.targets) { plan.targets[plan.count] = {template_index, entity} }
	// Keep the full count on overflow; evaluation reports it before compiling.
	plan.count += 1
}

@(private="file")
build_card_target_plan :: proc(room: ^Room, card: Card_Id, definition: Card_Definition,
	query: ^Target_Query_Result, capture: bool) -> (plan: Card_Target_Plan) {
	plan.capture = capture
	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		switch template.target {
		case .Each_Enemy:
			start := plan.count
			for enemy in room.enemies {
				if enemy_is_out_of_play(room, enemy.id) || !tactical_card_enemy_in_area(room, card, enemy.position) { continue }
				append_card_target(&plan, index, enemy_entity(enemy.id))
			}
			// Stable IDs, as enemy planning; storage order may change after a kill.
			if capture && plan.count <= len(plan.targets) {
				for i in start+1..<plan.count {
					target, at := plan.targets[i], i
					for at > start && plan.targets[at-1].entity.id > target.entity.id {
						plan.targets[at] = plan.targets[at-1]
						at -= 1
					}
					plan.targets[at] = target
				}
			}
		case .Each_Affected_Enemy:
			if template.affects_objects {
				ids, count := affected_damageable_object_ids(room, &query.affected)
				for id in ids[:count] { append_card_target(&plan, index, object_entity(id)) }
			}
			for id in query.enemy_ids[:query.enemy_count] { append_card_target(&plan, index, enemy_entity(id)) }
		case .Chosen_Entity, .Player:
			entity, _ := card_effect_target(template.target, query.primary_target)
			append_card_target(&plan, index, entity)
		case .Count:
		}
	}
	return
}

compile_card_action :: proc(
	room: ^Room,
	instance: Card_Instance,
	target: Target,
) -> (action: Action, err: Card_Compile_Error) {
	definition: Card_Definition
	definition, err = validated_card_definition_for_action(room, instance)
	if err != .None {
		return {}, err
	}
	request, has_request := card_target_request_from_target(room, definition, target)
	if !has_request {
		return {}, .Invalid_Target
	}
	plan: Card_Target_Plan
	evaluation := evaluate_validated_card_targeting(room, instance, definition, request, &plan)
	if evaluation.error != .None {
		return {}, evaluation.error
	}
	if !evaluation.query.has_primary_target || evaluation.query.primary_target != target {
		return {}, .Invalid_Target
	}

	action = make_action(.Card, PLAYER_ENTITY, target, definition.targeting.rule)
	if instance.definition_id == .Chain_Lightning || instance.definition_id == .Storm_Crown {
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
	for entry in plan.targets[:plan.count] {
		template := definition.effects[entry.template_index]
		if template.kind == .Move {
			assert(evaluation.has_movement)
			destination, has_destination := card_movement_destination(room, template, entry.entity, &evaluation.query)
			assert(has_destination)
			if !add_effect(&action, move_effect(entry.entity, destination)) { return {}, .Too_Many_Effects }
			continue
		}
		effect, instantiated := instantiate_card_effect(template, entry.entity, instance)
		if effect.kind == .Deploy_Device || effect.kind == .Place_Ground { effect.destination = evaluation.query.anchor }
		if instance.definition_id == .Strike && effect.kind == .Damage { effect.amount += tactical_strike_bonus(room, entry.entity) }
		if !instantiated {
			return {}, .Too_Many_Effects if template.target == .Each_Affected_Enemy && entry.entity.kind == .Object else .Invalid_Definition
		}
		if !add_effect(&action, effect) { return {}, .Too_Many_Effects }
	}
	return action, .None
}

card_requires_spatial_target :: proc(definition: Card_Definition) -> bool {
	return definition.targeting.shape != .None
}
