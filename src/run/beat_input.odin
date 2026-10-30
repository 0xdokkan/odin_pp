package run

import game "../game"
import grid "../engine/grid"

// Input side of the on-beat criticals (game/tactical_beat.odin): every move
// and card is stamped with the tick it is done on. A move done on the tick with
// a perpendicular key held steps diagonally (W+D, S+A and the other pairs).
// Nothing waits for the partner key any more (2026-10-30: it held back a step
// in three by 60 ms): held together, they are both down when the step goes.

// The diagonal formed by `primary` and a perpendicular direction key held now
// (W, D, S and A stepping the ways of `keys`: poll_walk_command).
beat_chord_offset :: proc(primary: game.Move_Direction, keys := game.MOVEMENT_KEY_DIRECTIONS, controls: Run_Input = {}) -> (offset: grid.Position, found: bool) {
	vertical := primary == .North || primary == .South
	for action, index in RUN_WALK_ACTIONS {
		direction := keys[index]
		if (direction == .North || direction == .South) == vertical || !run_down(controls, action) { continue }
		a, b := game.direction_offset(primary), game.direction_offset(direction)
		return grid.offset(a, b.x, b.y), true
	}
	return
}

beat_stamp :: proc(room: ^game.Room, command: ^Gameplay_Command) {
	if (command.kind == .Move || command.kind == .Play_Card) && command.beat == 0 {
		command.beat = game.tactical_beat_target(room)
	}
}

// A command as it is done now: stamped with the tick, and a move on the tick
// with a perpendicular key held turned diagonal.
beat_input_command :: proc(room: ^game.Room, command: Gameplay_Command, keys := game.MOVEMENT_KEY_DIRECTIONS,
	controls: Run_Input = {}) -> Gameplay_Command {
	result := command
	beat_stamp(room, &result)
	if result.kind == .Move && result.beat != 0 && result.origin_phase == .Combat && result.diagonal == {} {
		if offset, found := beat_chord_offset(result.direction, keys, controls); found { result.diagonal = offset }
	}
	return result
}

// The commands a press made during the player's own action keeps for its end.
gameplay_command_keeps :: proc(command: Gameplay_Command) -> bool {
	#partial switch command.kind {
	case .Move, .Wait, .Play_Card, .Refocus, .Ability, .Equip: return true
	}
	return false
}

// The walk key held now, the one pressed last first: the move it makes.
held_walk_command :: proc(held: ^Buffered_Gameplay_Command, room: ^game.Room, keys := game.MOVEMENT_KEY_DIRECTIONS,
	controls: Run_Input = {}) -> (command: Gameplay_Command, ok: bool) {
	if room.phase != .Combat && room.phase != .Loot { return }
	// Shift held is the dodge's; the fists walk free (first_person_fists.odin).
	if run_down(controls, .Dodge_Modifier) || game.first_person_fists_active(room) { return }
	actions := RUN_WALK_ACTIONS
	if held.walk > 0 && run_down(controls, actions[held.walk-1]) {
		return {kind = .Move, origin_phase = room.phase, direction = keys[held.walk-1]}, true
	}
	for action, index in actions {
		if run_down(controls, action) {
			held.walk = index+1
			return {kind = .Move, origin_phase = room.phase, direction = keys[index]}, true
		}
	}
	return
}

// The scene's input lane for one frame. While the player's own action runs
// (`busy`: its animation, its timed seconds or a card's cast) the newest press
// is kept, to be done the frame the action ends; then a walk key still held
// walks on.
route_gameplay_command :: proc(held: ^Buffered_Gameplay_Command, room: ^game.Room, busy: bool,
	command: Gameplay_Command, has_command: bool, dt: f32, keys := game.MOVEMENT_KEY_DIRECTIONS, controls: Run_Input = {}) -> (result: Gameplay_Command, ok: bool) {
	if room.phase == .Complete || room.phase == .Defeat {
		clear_gameplay_command_buffer(held)
		return
	}
	// The walk key pressed last is the one a held walk follows.
	if has_command && command.kind == .Move {
		for direction, index in keys {
			if direction == command.direction { held.walk = index+1; break }
		}
	}
	if busy {
		if has_command && gameplay_command_keeps(command) { held.pending, held.has_pending = command, true }
		return
	}
	if has_command {
		held.has_pending = false
		return beat_input_command(room, command, keys, controls), true
	}
	if held.has_pending {
		held.has_pending = false
		return beat_input_command(room, held.pending, keys, controls), true
	}
	if walk, walking := held_walk_command(held, room, keys, controls); walking {
		return beat_input_command(room, walk, keys, controls), true
	}
	return
}
