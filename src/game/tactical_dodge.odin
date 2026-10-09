package game

import grid "../grid"

tactical_dodge_ready :: proc(room: ^Room) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat { return false }
	_, afterimage := status_for_entity(room, PLAYER_ENTITY, .Afterimage)
	return room.player.tactical.dodge_recovery == 0 || afterimage
}

tactical_dodge_has_landing :: proc(room: ^Room) -> bool {
	for direction in Move_Direction {
		query := query_entity_movement(room, PLAYER_ENTITY, add_position(room.player.position, direction_offset(direction)))
		if movement_query_is_clear(&query) { return true }
	}
	return false
}

start_tactical_dodge_recovery :: proc(room: ^Room) {
	// The pulse containing the dodge finishes next; then two whole pulses
	// must pass. Forced pulses count, opening/closing UI does not.
	room.player.tactical.dodge_recovery = TACTICAL_DODGE_RECOVERY+1
}

tactical_dodge_destination :: proc(room: ^Room, direction: Move_Direction) -> (destination: grid.Position, ok: bool) {
	if !tactical_dodge_ready(room) { return }
	step := direction_offset(direction)
	origin := room.player.position
	// A short roll is still possible when only the first cell is free.
	for distance in 1..=2 {
		next := grid.Position{origin.x+step.x*distance, origin.y+step.y*distance}
		query := query_entity_movement(room, PLAYER_ENTITY, next)
		if !movement_query_is_clear(&query) { break }
		destination, ok = next, true
	}
	return
}

try_dodge_player :: proc(room: ^Room, direction: Move_Direction) -> bool {
	if !tactical_dodge_ready(room) || !tactical_allows_action(room) { return false }
	destination, clear := tactical_dodge_destination(room, direction)
	if !clear { return false }
	action := make_action(.Move, PLAYER_ENTITY, cell_target(destination), .Walkable_Cell)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, destination))
	assert(added)
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	clear_event_log(&room.recent_events)
	append_event_log(&room.recent_events, &report.events)
	start_tactical_dodge_recovery(room)
	room.player.tactical.facing = direction
	collect_loot_in_magnet_range(room)
	_, _ = finish_player_combat_command(room)
	return true
}
