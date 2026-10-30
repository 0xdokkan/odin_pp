package game

import grid "../engine/grid"
import level "../level"

// HEIGHTS. Every cell has a height in steps (level.height_at, 0 on a flat map). The
// rules count in steps; a step is drawn HEIGHT_STEP_DRAWN of a cell tall.
//
// - A walker (the player's step, a foe's step) goes between neighbours at most
//   HEIGHT_MAX_STEP steps apart, up or down; more is a cliff, a wall to walkers.
// - Force (a push, a pull, a dash) cannot climb a cliff: a rise of more than a step is
//   a wall to it. It can go down one: the one pushed falls, and a fall of two steps or
//   more costs `fall_damage` (a walker never falls by choice).
// - Sight and cast lines rise and fall with the ground: a cell whose top is above the
//   line from the eye to the target hides what is behind it.
// - A ranged card reaches one cell further from HEIGHT_RANGE_BONUS_STEPS steps above.

HEIGHT_MAX_STEP :: i32(1)
HEIGHT_FALL_FREE :: i32(1)
HEIGHT_FALL_MAX_DAMAGE :: i32(10)
HEIGHT_RANGE_BONUS_STEPS :: i32(4)
// The eye stands this many steps over its floor, a target's middle this many.
HEIGHT_EYE_STEPS :: i32(6)
HEIGHT_TARGET_STEPS :: i32(4)
// How much of a cell's side a step is drawn (the renderer's unit; the rules do not use it).
HEIGHT_STEP_DRAWN :: f32(0.12)

cell_height :: proc(room: ^Room, position: grid.Position) -> i32 {
	if room == nil { return 0 }
	return level.height_at(room.level_data, position)
}

// A walker's step between two cells: a cliff (more than HEIGHT_MAX_STEP apart) stops it.
step_height_blocked :: proc(room: ^Room, from, to: grid.Position) -> bool {
	return abs(cell_height(room, to)-cell_height(room, from)) > HEIGHT_MAX_STEP
}

// A displacement's step: only a rise of more than HEIGHT_MAX_STEP stops it.
rise_height_blocked :: proc(room: ^Room, from, to: grid.Position) -> bool {
	return cell_height(room, to)-cell_height(room, from) > HEIGHT_MAX_STEP
}

// What a drop of `steps` steps costs whoever falls it.
fall_damage :: proc(steps: i32) -> i32 {
	if steps <= HEIGHT_FALL_FREE { return 0 }
	return min(steps-1, HEIGHT_FALL_MAX_DAMAGE)
}

// Whether the ground hides the cell at step `index` (1-based) of an `count`-step line
// from `origin` to `destination`: its top is above the line from the eye to the
// target. The cells at the two ends are never the ground in the way; flat ground
// never hides anything.
height_hides :: proc(room: ^Room, origin, destination, cell: grid.Position, index, count: int) -> bool {
	if room == nil || count <= 1 || index <= 0 || index >= count || !level.has_heights(room.level_data) { return false }
	eye := cell_height(room, origin)+HEIGHT_EYE_STEPS
	aim := cell_height(room, destination)+HEIGHT_TARGET_STEPS
	// The line's height at `index`, scaled by `count`, against the cell's top.
	return int(cell_height(room, cell))*count > int(eye)*count+int(aim-eye)*index
}

// How far a cast from `origin` reaches `anchor`, given how far its card reaches: one
// cell more from HEIGHT_RANGE_BONUS_STEPS steps above, for a ranged card (reach over 1).
height_range_maximum :: proc(room: ^Room, maximum: int, origin, anchor: grid.Position) -> int {
	if maximum <= 1 { return maximum }
	if cell_height(room, origin)-cell_height(room, anchor) >= HEIGHT_RANGE_BONUS_STEPS { return maximum+1 }
	return maximum
}

// What falling does to `target` (a player or a foe) that went down `steps` steps and
// stands on its new cell: the damage, with the report that carries it.
@(private)
trigger_fall :: proc(room: ^Room, target: Entity_Ref, steps: i32, report: ^Action_Report) {
	damage := fall_damage(steps)
	if room == nil || report == nil || damage <= 0 || (target.kind != .Player && target.kind != .Enemy) || !entity_exists(room, target) { return }
	position, found := entity_position(room, target)
	if !found { return }
	record_report_event(report, {
		kind = .Hazard_Triggered,
		source = SYSTEM_ENTITY,
		target = target,
		amount = damage,
		from_position = position,
		to_position = position,
	})
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(target), .Entity)
	add_effect(&action, damage_effect(target, damage))
	hit := resolve_action(room, &action)
	merge_spell_hit_report(report, &hit)
}
