package game

import grid "../grid"

MAX_TARGETING_RANGE       :: 12
MAX_TARGETING_RADIUS      :: 4
MAX_TARGETING_PATH_CELLS  :: MAX_TARGETING_RANGE
MAX_TARGETING_SHAPE_CELLS :: (MAX_TARGETING_RADIUS*2+1)*(MAX_TARGETING_RADIUS*2+1)

Target_Shape :: enum {
	None,
	Single,
	Line,
	Cross,
	Square,
	Count,
}

Targeting_Range_Metric :: enum {
	None,
	Manhattan,
	Chebyshev,
}

Targeting_Range :: struct {
	metric:  Targeting_Range_Metric,
	minimum: int,
	maximum: int,
}

Targeting_Spec :: struct {
	rule:                   Target_Rule,
	cast_range:             Targeting_Range,
	shape:                  Target_Shape,
	radius:                 int,
	requires_line_of_sight: bool,
	stops_on_wall:          bool,
	stops_on_actor:         bool,
}

Target_Request :: struct {
	anchor:     grid.Position,
	has_anchor: bool,
}

Target_Query_Error :: enum {
	None,
	Invalid_Room,
	Invalid_Spec,
	Invalid_Source,
	Missing_Anchor,
	Anchor_Out_Of_Bounds,
	Anchor_Out_Of_Range,
	Shape_Not_Aligned,
	Line_Of_Sight_Blocked,
	Invalid_Primary_Target,
	Capacity_Exceeded,
}

Target_Cell_Set :: struct {
	cells: [MAX_TARGETING_SHAPE_CELLS]grid.Position,
	count: int,
}

Target_Query_Result :: struct {
	error:             Target_Query_Error,
	origin:            grid.Position,
	anchor:            grid.Position,
	anchor_reachable:  bool,
	primary_target:    Target,
	has_primary_target: bool,
	affected:          Target_Cell_Set,
	path:              [MAX_TARGETING_PATH_CELLS]grid.Position,
	path_count:        int,
	blocker:           grid.Position,
	has_blocker:       bool,
	enemy_ids:         [MAX_ENEMIES_PER_ROOM]u32,
	enemy_count:       int,
}

targeting_range_is_valid :: proc(target_range: Targeting_Range) -> bool {
	switch target_range.metric {
	case .None:
		return target_range.minimum == 0 && target_range.maximum == 0
	case .Manhattan, .Chebyshev:
		return target_range.minimum >= 0 && target_range.maximum >= target_range.minimum &&
		       target_range.maximum > 0 && target_range.maximum <= MAX_TARGETING_RANGE
	}
	return false
}

targeting_range_distance :: proc(
	metric: Targeting_Range_Metric,
	origin, target: grid.Position,
) -> (distance: int, ok: bool) {
	delta_x := abs(origin.x-target.x)
	delta_y := abs(origin.y-target.y)
	switch metric {
	case .Manhattan:
		return delta_x+delta_y, true
	case .Chebyshev:
		return max(delta_x, delta_y), true
	case .None:
		return 0, false
	}
	return 0, false
}

targeting_range_contains :: proc(
	target_range: Targeting_Range,
	origin, target: grid.Position,
) -> bool {
	if !targeting_range_is_valid(target_range) || target_range.metric == .None {
		return false
	}
	distance, ok := targeting_range_distance(target_range.metric, origin, target)
	return ok && distance >= target_range.minimum && distance <= target_range.maximum
}

targeting_rule_uses_anchor :: proc(rule: Target_Rule) -> bool {
	switch rule {
	case .Entity, .Opponent, .Opponent_Or_Object, .Adjacent_Opponent, .Cell, .Walkable_Cell:
		return true
	case .Any, .None, .Self, .Player:
		return false
	}
	return false
}

targeting_spec_is_valid :: proc(spec: Targeting_Spec) -> bool {
	if int(spec.shape) < 0 || spec.shape >= .Count || !targeting_range_is_valid(spec.cast_range) ||
	   spec.radius < 0 || spec.radius > MAX_TARGETING_RADIUS || spec.rule == .Any {
		return false
	}
	if spec.shape == .None {
		return spec.cast_range.metric == .None && spec.radius == 0 &&
		       !spec.requires_line_of_sight && !spec.stops_on_wall && !spec.stops_on_actor &&
		       (spec.rule == .None || spec.rule == .Self || spec.rule == .Player)
	}
	if !targeting_rule_uses_anchor(spec.rule) || spec.cast_range.metric == .None {
		return false
	}
	switch spec.shape {
	case .None, .Count:
		return false
	case .Single:
		return spec.radius == 0 && !spec.stops_on_actor
	case .Line:
		return spec.cast_range.metric == .Chebyshev && spec.radius == 0
	case .Cross, .Square:
		return spec.radius > 0 && !spec.stops_on_actor &&
		       (spec.rule == .Cell || spec.rule == .Walkable_Cell)
	}
	return false
}

target_cell_set_contains :: proc(set: ^Target_Cell_Set, position: grid.Position) -> bool {
	if set == nil || set.count < 0 || set.count > MAX_TARGETING_SHAPE_CELLS {
		return false
	}
	for index in 0..<set.count {
		if set.cells[index] == position {
			return true
		}
	}
	return false
}

add_target_cell :: proc(set: ^Target_Cell_Set, position: grid.Position) -> bool {
	if set == nil || set.count < 0 || set.count > MAX_TARGETING_SHAPE_CELLS {
		return false
	}
	if target_cell_set_contains(set, position) {
		return true
	}
	if set.count >= MAX_TARGETING_SHAPE_CELLS {
		return false
	}
	set.cells[set.count] = position
	set.count += 1
	return true
}

targeting_static_blocker_at :: proc(room: ^Room, position: grid.Position) -> bool {
	return room == nil || cell_blocks_line_of_sight(room, position)
}

targeting_actor_at :: proc(room: ^Room, position: grid.Position) -> bool {
	if room == nil || room.player == nil {
		return false
	}
	if room.player.position == position {
		return true
	}
	_, found := enemy_index_at(room, position)
	return found
}

trace_targeting_line :: proc(
	origin, target: grid.Position,
	path: ^[MAX_TARGETING_PATH_CELLS]grid.Position,
) -> (count: int, ok: bool) {
	if path == nil || origin == target {
		return
	}
	x, y := origin.x, origin.y
	delta_x := abs(target.x-origin.x)
	delta_y := abs(target.y-origin.y)
	step_x := sign(target.x-origin.x)
	step_y := sign(target.y-origin.y)
	error_value := delta_x-delta_y

	for x != target.x || y != target.y {
		double_error := error_value*2
		if double_error > -delta_y {
			error_value -= delta_y
			x += step_x
		}
		if double_error < delta_x {
			error_value += delta_x
			y += step_y
		}
		if count >= MAX_TARGETING_PATH_CELLS {
			return count, false
		}
		path[count] = {x = x, y = y}
		count += 1
	}
	return count, true
}

targeting_path_blocker :: proc(
	room: ^Room,
	origin: grid.Position,
	path: ^[MAX_TARGETING_PATH_CELLS]grid.Position,
	path_count: int,
	allow_blocked_destination: bool = false,
) -> (blocker: grid.Position, found: bool) {
	if room == nil || path == nil || path_count < 0 || path_count > MAX_TARGETING_PATH_CELLS {
		return {}, true
	}
	previous := origin
	for index in 0..<path_count {
		position := path[index]
		is_destination := index == path_count-1
		if targeting_static_blocker_at(room, position) &&
		   !(allow_blocked_destination && is_destination) {
			return position, true
		}
		step_x := position.x-previous.x
		step_y := position.y-previous.y
		if step_x != 0 && step_y != 0 {
			side_x := grid.Position{x = previous.x+step_x, y = previous.y}
			side_y := grid.Position{x = previous.x, y = previous.y+step_y}
			if targeting_static_blocker_at(room, side_x) && targeting_static_blocker_at(room, side_y) {
				return side_x, true
			}
		}
		previous = position
	}
	return
}

targeting_line_is_aligned :: proc(origin, anchor: grid.Position) -> bool {
	delta_x := abs(anchor.x-origin.x)
	delta_y := abs(anchor.y-origin.y)
	return (delta_x == 0 && delta_y > 0) || (delta_y == 0 && delta_x > 0) ||
	       (delta_x > 0 && delta_x == delta_y)
}

targeting_target_at_anchor :: proc(
	room: ^Room,
	source: Entity_Ref,
	rule: Target_Rule,
	anchor: grid.Position,
) -> (Target, bool) {
	switch rule {
	case .None:
		return {}, true
	case .Self:
		return entity_target(source), true
	case .Player:
		return entity_target(PLAYER_ENTITY), true
	case .Opponent, .Adjacent_Opponent:
		if source.kind == .Player {
			if index, found := enemy_index_at(room, anchor); found {
				return entity_target(enemy_entity(room.enemies[index].id)), true
			}
		} else if source.kind == .Enemy && room.player != nil && room.player.position == anchor {
			return entity_target(PLAYER_ENTITY), true
		}
	case .Opponent_Or_Object:
		if source.kind == .Player {
			if index, found := enemy_index_at(room, anchor); found {
				return entity_target(enemy_entity(room.enemies[index].id)), true
			}
		} else if source.kind == .Enemy && room.player != nil && room.player.position == anchor {
			return entity_target(PLAYER_ENTITY), true
		}
		if index, found := object_index_at(room, anchor); found {
			entity := object_entity(room.objects[index].id)
			if entity_is_targetable_object(room, entity) {
				return entity_target(entity), true
			}
		}
	case .Entity:
		if room.player != nil && room.player.position == anchor {
			return entity_target(PLAYER_ENTITY), true
		}
		if index, found := enemy_index_at(room, anchor); found {
			return entity_target(enemy_entity(room.enemies[index].id)), true
		}
		if index, found := trap_index_at(room, anchor); found {
			return entity_target(trap_entity(room.traps[index].id)), true
		}
		if index, found := object_index_at(room, anchor); found {
			return entity_target(object_entity(room.objects[index].id)), true
		}
	case .Cell, .Walkable_Cell, .Any:
		return cell_target(anchor), true
	}
	return {}, false
}

append_shape_cell :: proc(room: ^Room, set: ^Target_Cell_Set, position: grid.Position) -> bool {
	if room == nil || room.level_data == nil || !grid.contains(&room.level_data.tiles, position) ||
	   targeting_static_blocker_at(room, position) {
		return true
	}
	return add_target_cell(set, position)
}

shape_cell_has_clear_path :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	if origin == target {
		return true
	}
	path: [MAX_TARGETING_PATH_CELLS]grid.Position
	path_count, traced := trace_targeting_line(origin, target, &path)
	if !traced {
		return false
	}
	_, blocked := targeting_path_blocker(room, origin, &path, path_count)
	return !blocked
}

build_target_shape :: proc(
	room: ^Room,
	spec: Targeting_Spec,
	result: ^Target_Query_Result,
) -> bool {
	assert(room != nil && result != nil)
	switch spec.shape {
	case .None:
		return true
	case .Single:
		if spec.rule == .Opponent_Or_Object {
			if object, found := grid_object_at(room, result.anchor); found {
				entity := object_entity(object.id)
				if entity_is_targetable_object(room, entity) {
					return add_target_cell(&result.affected, result.anchor)
				}
			}
		}
		return append_shape_cell(room, &result.affected, result.anchor)
	case .Line:
		for index in 0..<result.path_count {
			position := result.path[index]
			if !append_shape_cell(room, &result.affected, position) {
				return false
			}
			if spec.stops_on_actor && targeting_actor_at(room, position) {
				break
			}
		}
		return true
	case .Cross:
		for offset_y in -spec.radius..=spec.radius {
			for offset_x in -spec.radius..=spec.radius {
				if offset_x != 0 && offset_y != 0 {
					continue
			}
				position := grid.Position{x = result.anchor.x+offset_x, y = result.anchor.y+offset_y}
				if spec.stops_on_wall && !shape_cell_has_clear_path(room, result.anchor, position) {
					continue
				}
				if !append_shape_cell(room, &result.affected, position) {
					return false
				}
			}
		}
		return true
	case .Square:
		for offset_y in -spec.radius..=spec.radius {
			for offset_x in -spec.radius..=spec.radius {
				position := grid.Position{x = result.anchor.x+offset_x, y = result.anchor.y+offset_y}
				if !append_shape_cell(room, &result.affected, position) {
					return false
				}
			}
		}
		return true
	case .Count:
	}
	return false
}

collect_targeted_enemy_ids :: proc(room: ^Room, result: ^Target_Query_Result) {
	assert(room != nil && result != nil)
	ids, count := enemy_ids_in_planning_order(room)
	for index in 0..<count {
		enemy_index, found := enemy_index_by_id(room, ids[index])
		assert(found)
		// A foe out of play is on none of them.
		if enemy_is_out_of_play(room, ids[index]) { continue }
		if target_cell_set_contains(&result.affected, room.enemies[enemy_index].position) {
			result.enemy_ids[result.enemy_count] = ids[index]
			result.enemy_count += 1
		}
	}
}

evaluate_target_query :: proc(
	room: ^Room,
	source: Entity_Ref,
	spec: Targeting_Spec,
	request: Target_Request,
) -> (result: Target_Query_Result) {
	result.error = .Invalid_Room
	if room == nil || room.player == nil || room.level_data == nil {
		return
	}
	result.error = .Invalid_Spec
	if !targeting_spec_is_valid(spec) {
		return
	}
	result.error = .Invalid_Source
	if !entity_exists(room, source) {
		return
	}
	result.origin, _ = entity_position(room, source)

	if spec.shape == .None {
		result.anchor = result.origin
		result.anchor_reachable = true
		result.primary_target, result.has_primary_target =
			targeting_target_at_anchor(room, source, spec.rule, result.origin)
		if !result.has_primary_target ||
		   !target_matches_rule(room, source, result.primary_target, spec.rule) {
			result.error = .Invalid_Primary_Target
			return
		}
		result.error = .None
		return
	}

	result.error = .Missing_Anchor
	if !request.has_anchor {
		return
	}
	result.anchor = request.anchor
	result.error = .Anchor_Out_Of_Bounds
	if !grid.contains(&room.level_data.tiles, result.anchor) {
		return
	}
	result.error = .Anchor_Out_Of_Range
	if !targeting_range_contains(spec.cast_range, result.origin, result.anchor) {
		return
	}
	if spec.shape == .Line && !targeting_line_is_aligned(result.origin, result.anchor) {
		result.error = .Shape_Not_Aligned
		return
	}
	if result.origin != result.anchor {
		traced := false
		result.path_count, traced = trace_targeting_line(result.origin, result.anchor, &result.path)
		if !traced || result.path_count <= 0 {
			result.error = .Capacity_Exceeded
			return
		}
	}
	if spec.requires_line_of_sight || spec.stops_on_wall {
		allow_blocked_destination := false
		if spec.rule == .Opponent_Or_Object {
			if object, found := grid_object_at(room, result.anchor); found {
				allow_blocked_destination = entity_is_targetable_object(
					room,
					object_entity(object.id),
				)
			}
		}
		if blocker, blocked := targeting_path_blocker(
			room,
			result.origin,
			&result.path,
			result.path_count,
			allow_blocked_destination,
		); blocked {
			result.error = .Line_Of_Sight_Blocked
			result.blocker = blocker
			result.has_blocker = true
			return
		}
	}
	if !build_target_shape(room, spec, &result) {
		result.error = .Capacity_Exceeded
		return
	}
	result.anchor_reachable = !targeting_static_blocker_at(room, result.anchor)
	result.primary_target, result.has_primary_target =
		targeting_target_at_anchor(room, source, spec.rule, result.anchor)
	if !result.has_primary_target ||
	   !target_matches_rule(room, source, result.primary_target, spec.rule) {
		result.error = .Invalid_Primary_Target
		return
	}
	collect_targeted_enemy_ids(room, &result)
	result.error = .None
	return
}
