package game

import grid "../engine/grid"

MAX_ROOM_HAZARD_CELLS :: 16
ROOM_HAZARD_WARNING_PULSES :: u64(2)
ROOM_HAZARD_INTERVAL_PULSES :: u64(4)
ROOM_HAZARD_DAMAGE :: i32(3)
ROOM_MODIFIER_SEED_SALT :: u64(0x1D8E4E27C47D124F)

Room_Modifier_Kind :: enum { None, Furnace }

Room_Modifier :: struct {
	kind: Room_Modifier_Kind,
	cells: [MAX_ROOM_HAZARD_CELLS]grid.Position,
	cell_count: int,
	activation_pulse: u64,
	damage: i32,
}

@(private = "file")
room_modifier_kind_name :: proc(kind: Room_Modifier_Kind) -> string {
	switch kind {
	case .None: return "Calm"
	case .Furnace: return "Furnace"
	}
	return "Calm"
}

room_modifier_contains_cell :: proc(modifier: ^Room_Modifier, cell: grid.Position) -> bool {
	if modifier == nil || modifier.kind == .None || modifier.cell_count < 0 ||
	   modifier.cell_count > MAX_ROOM_HAZARD_CELLS { return false }
	return position_in_list(modifier.cells[:modifier.cell_count], cell)
}

room_modifier_pulses_remaining :: proc(modifier: ^Room_Modifier, pulse: u64) -> int {
	if modifier == nil || modifier.kind == .None || modifier.activation_pulse <= pulse { return 0 }
	return int(min(modifier.activation_pulse-pulse, u64(max(int))))
}

room_modifier_warning_active :: proc(modifier: ^Room_Modifier, pulse: u64) -> bool {
	remaining := room_modifier_pulses_remaining(modifier, pulse)
	return remaining > 0 && remaining <= int(ROOM_HAZARD_WARNING_PULSES)
}

@(private)
valid_room_modifier :: proc(room: ^Room, modifier: ^Room_Modifier) -> bool {
	if modifier.kind == .None {
		return modifier.cell_count == 0 && modifier.activation_pulse == 0 && modifier.damage == 0
	}
	if modifier.kind != .Furnace || modifier.cell_count <= 0 ||
	   modifier.cell_count > MAX_ROOM_HAZARD_CELLS || modifier.damage <= 0 ||
	   modifier.activation_pulse == 0 { return false }
	first := modifier.cells[0]
	row, column := true, true
	for cell, index in modifier.cells[:modifier.cell_count] {
		if !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) ||
		   position_in_list(modifier.cells[:index], cell) ||
		   cell == room.level_data.player_spawn || cell == room.exit_position { return false }
		row = row && cell.y == first.y
		column = column && cell.x == first.x
	}
	return row || column
}

@(private)
disarm_room_modifier_after_combat :: proc(room: ^Room) {
	if room != nil && room.phase != .Combat { room.modifier.activation_pulse = 0 }
}

@(private)
resolve_due_room_modifier :: proc(room: ^Room, pulse: ^Pulse_Report) {
	modifier := &room.modifier
	if room.phase != .Combat || modifier.kind == .None || modifier.activation_pulse == 0 ||
	   modifier.activation_pulse > room.pulse_count+1 { return }
	modifier.activation_pulse = room.pulse_count+1+ROOM_HAZARD_INTERVAL_PULSES
	record_event(&pulse.events, {
		kind = .Room_Hazard_Triggered, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
		from_position = modifier.cells[0], to_position = modifier.cells[modifier.cell_count-1],
		amount = modifier.damage, pulse_count = modifier.activation_pulse,
	})
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(SYSTEM_ENTITY), .Entity)
	// At most one actor and one object per cell fit in the fixed Action buffer.
	for cell in modifier.cells[:modifier.cell_count] {
		if room.player.position == cell {
			added := add_effect(&action, damage_effect(PLAYER_ENTITY, modifier.damage))
			assert(added)
		}
		if index, found := enemy_index_at(room, cell); found {
			added := add_effect(&action, damage_effect(enemy_entity(room.enemies[index].id), modifier.damage))
			assert(added)
		}
		if object, found := grid_object_at(room, cell); found {
			effect := damage_effect(object_entity(object.id), modifier.damage)
			if effect_is_valid(room, effect) {
				added := add_effect(&action, effect)
				assert(added)
			}
		}
	}
	report := resolve_action(room, &action)
	assert(report.accepted)
	merge_action_report(pulse, &report)
	disarm_room_modifier_after_combat(room)
}

@(private = "file")
blueprint_hazard_escape_cell_is_safe :: proc(blueprint: ^Room_Blueprint, cell: grid.Position) -> bool {
	if !cell_is_walkable(&blueprint.level_data, cell) ||
	   position_in_list(blueprint.obstacles[:], cell) { return false }
	for object in blueprint.objects {
		if object.position == cell { return false }
	}
	return true
}

// Every marked cell has a route off the lane within its two-decision warning.
@(private)
blueprint_hazard_cell_has_escape :: proc(blueprint: ^Room_Blueprint, cell: grid.Position, rows: bool) -> bool {
	for direction in Move_Direction {
		step := add_position(cell, direction_offset(direction))
		if !blueprint_hazard_escape_cell_is_safe(blueprint, step) { continue }
		if (rows && step.y != cell.y) || (!rows && step.x != cell.x) { return true }
		for second_direction in Move_Direction {
			second := add_position(step, direction_offset(second_direction))
			if blueprint_hazard_escape_cell_is_safe(blueprint, second) &&
			   ((rows && second.y != cell.y) || (!rows && second.x != cell.x)) { return true }
		}
	}
	return false
}

@(private)
generate_blueprint_modifier :: proc(blueprint: ^Room_Blueprint) -> Room_Modifier {
	if blueprint.node_depth <= 1 || blueprint.node_kind == .Boss { return {} }
	seed := derive_room_stream_seed(blueprint.seed, ROOM_MODIFIER_SEED_SALT)
	if seed%3 == 0 { return {} }
	rows := seed%2 == 0
	width, height := blueprint.level_data.tiles.width, blueprint.level_data.tiles.height
	line_count := height-2 if rows else width-2
	span := width-2 if rows else height-2
	for attempt in 0..<line_count {
		line := 1+(int((seed>>8)%u64(line_count))+attempt)%line_count
		modifier := Room_Modifier{kind = .Furnace,
			activation_pulse = ROOM_HAZARD_WARNING_PULSES, damage = ROOM_HAZARD_DAMAGE}
		for offset in 1..=span {
			cell := grid.Position{offset, line} if rows else grid.Position{line, offset}
			if !cell_is_walkable(&blueprint.level_data, cell) ||
			   position_in_list(blueprint.obstacles[:], cell) ||
			   cell == blueprint.level_data.player_spawn || cell == blueprint.exit_position ||
			   !blueprint_hazard_cell_has_escape(blueprint, cell, rows) { continue }
			modifier.cells[modifier.cell_count] = cell
			modifier.cell_count += 1
			if modifier.cell_count == MAX_ROOM_HAZARD_CELLS { break }
		}
		if modifier.cell_count >= 3 { return modifier }
	}
	return {}
}
