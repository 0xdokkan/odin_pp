package game

import grid "../grid"

MAX_GRID_OBJECTS_PER_ROOM :: 32

Grid_Object_Kind :: enum {
	Ice_Block,
	Fire,
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
}

Grid_Object :: struct {
	id:         u32,
	kind:       Grid_Object_Kind,
	position:   grid.Position,
	max_health: i32,
	health:     i32,
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
}

grid_object_definition :: proc(kind: Grid_Object_Kind) -> (Grid_Object_Definition, bool) {
	definitions := GRID_OBJECT_DEFINITIONS
	index := int(kind)
	if index < 0 || index >= len(definitions) {
		return {}, false
	}
	return definitions[index], true
}

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
