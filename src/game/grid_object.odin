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
	Cannon, Flood, Black_Hole, Bomb_Marley,
	// What the player sets down for a while (emplacement.odin).
	Field_Cannon,
	Devouring_Hole,
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
	device_direction: Move_Direction,
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
	{kind = .Cannon, name = "Cannone", max_health = 8, blocks_movement = true, targetable = true, damageable = true},
	{kind = .Flood, name = "Inondazione"},
	{kind = .Black_Hole, name = "Buco Nero"},
	{kind = .Bomb_Marley, name = "Bomb Marley", max_health = 1, targetable = true, damageable = true},
	// Solid on its stand, nothing aims at it; the hole blocks nothing.
	{kind = .Field_Cannon, name = "Cannon", blocks_movement = true},
	{kind = .Devouring_Hole, name = "Black Hole"},
}

// How wide and high an object stands as it is drawn (render: voxel_object_bounds,
// its ray pick; the bow's arrows fly over it, first_person_bow.odin).
grid_object_size :: proc(kind: Grid_Object_Kind) -> (width, height: f32) {
	width, height = 0.68, 0.72
	switch kind {
	case .Ice_Block: width, height = 0.82, 0.94
	case .Barrel: width, height = 0.64, 0.76
	case .Bomb: width, height = 0.46, 0.46
	case .Fire: width, height = 0.64, 0.7
	case .Shock_Floor: width, height = 0.88, 0.12
	case .Tesla_Coil: width, height = 0.64, 1.18
	case .Cannon: width, height = 0.85, 0.85
	case .Flood: width, height = 0.85, 0.35
	case .Black_Hole: width, height = 0.85, 0.65
	case .Bomb_Marley: width, height = 0.75, 0.9
	// CANNONE on its stand; the hole is a dark disc with a sphere in it.
	case .Field_Cannon: width, height = 0.72, 0.86
	case .Devouring_Hole: width, height = 0.9, 0.5
	case .Count:
	}
	return
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
