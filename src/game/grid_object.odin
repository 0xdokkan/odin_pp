package game

import grid "../engine/grid"

MAX_GRID_OBJECTS_PER_ROOM :: 32

Grid_Object_Kind :: enum {
	Ice_Block,
	Fire,
	Barrel,
	Bomb,
	Shock_Floor,
	Tesla_Coil,
	// What the player sets down for a while (emplacement.odin).
	Cannon,
	Black_Hole,
	Count,
}

Grid_Object_Definition :: struct {
	kind:                 Grid_Object_Kind,
	name:                 string,
	max_health:           i32,
	blocks_movement:      bool,
	blocks_line_of_sight: bool,
	targetable:           bool,
	damageable:           bool,
	movable:              bool,
	hazardous:            bool,
	hazard_damage:        i32,
	explosive:            bool,
}

Grid_Object :: struct {
	id:         u32,
	kind:       Grid_Object_Kind,
	position:   grid.Position,
	max_health: i32,
	health:     i32,
	detonation_pulse: u64,
	fuse_pulses: int,
	explosion_damage: i32,
	device_charges: i32,
	device_target_limit: i32,
	device_armed: bool,
	device_cooldown: i32,
	device_damage: i32,
	// An emplacement's (emplacement.odin): the beats left, its damage a beat,
	// a hole's damage radius, a cannon's way and whether it fires a beam.
	life: i32,
	power: i32,
	radius: i32,
	facing: Move_Direction,
	laser: bool,
}

Grid_Object_Spawn :: struct {
	kind:     Grid_Object_Kind,
	position: grid.Position,
}

GRID_OBJECT_DEFINITIONS :: [int(Grid_Object_Kind.Count)]Grid_Object_Definition{
	{
		kind = .Ice_Block,
		name = "Ice Block",
		max_health = 4,
		blocks_movement = true,
		blocks_line_of_sight = true,
		targetable = true,
		damageable = true,
		movable = true,
	},
	{
		kind = .Fire,
		name = "Fire",
		max_health = 0,
		blocks_movement = false,
		blocks_line_of_sight = false,
		targetable = false,
		damageable = false,
		movable = false,
		hazardous = true,
		hazard_damage = 2,
	},
	{
		kind = .Barrel,
		name = "Barrel",
		max_health = 1,
		blocks_movement = true,
		targetable = true,
		damageable = true,
		movable = true,
		explosive = true,
	},
	{
		kind = .Bomb,
		name = "Bomb",
		max_health = 1,
		targetable = true,
		damageable = true,
		movable = true,
		explosive = true,
	},
	{kind = .Shock_Floor, name = "Shock Floor"},
	{kind = .Tesla_Coil, name = "Tesla Coil", max_health = 4, blocks_movement = true, targetable = true, damageable = true},
	// Solid on its stand, nothing aims at it; the hole blocks nothing.
	{kind = .Cannon, name = "Cannon", blocks_movement = true},
	{kind = .Black_Hole, name = "Black Hole"},
}

grid_object_definition :: proc(kind: Grid_Object_Kind) -> (Grid_Object_Definition, bool) {
	definitions := GRID_OBJECT_DEFINITIONS
	index := int(kind)
	if index < 0 || index >= len(definitions) {
		return {}, false
	}
	return definitions[index], true
}

@(private)
validate_grid_object_definition :: proc(definition: Grid_Object_Definition) -> bool {
	if definition.kind >= .Count || len(definition.name) == 0 ||
	   definition.max_health < 0 || definition.hazard_damage < 0 {
		return false
	}
	if definition.damageable != (definition.max_health > 0) {
		return false
	}
	if definition.hazardous != (definition.hazard_damage > 0) {
		return false
	}
	return true
}

@(private)
validate_grid_object_definitions :: proc() -> bool {
	definitions := GRID_OBJECT_DEFINITIONS
	for definition, index in definitions {
		if int(definition.kind) != index ||
		   !validate_grid_object_definition(definition) {
			return false
		}
	}
	return true
}
