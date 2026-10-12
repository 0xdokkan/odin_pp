package main

import rl "vendor:raylib"
import game "game"
import grid "grid"

// Input side of the on-beat criticals (game/tactical_beat.odin): every move
// and card is stamped with the tick it was pressed on. A move pressed on the
// tick waits a few frames for a perpendicular key; W+D, S+A and the other
// pairs then step diagonally. Off the tick nothing waits.
BEAT_CHORD_SECONDS :: f32(0.06)

Beat_Chord :: struct {
	command: Gameplay_Command,
	timer: f32,
	active: bool,
}

// The diagonal formed by `primary` and a perpendicular direction key held now.
beat_chord_offset :: proc(primary: game.Move_Direction) -> (offset: grid.Position, found: bool) {
	keys := [4]rl.KeyboardKey{.W, .D, .S, .A}
	vertical := primary == .North || primary == .South
	for key, index in keys {
		direction := game.Move_Direction(index)
		if (direction == .North || direction == .South) == vertical || !rl.IsKeyDown(key) { continue }
		a, b := game.direction_offset(primary), game.direction_offset(direction)
		return {a.x+b.x, a.y+b.y}, true
	}
	return
}

beat_stamp :: proc(room: ^game.Room, command: ^Gameplay_Command) {
	if (command.kind == .Move || command.kind == .Play_Card) && command.beat == 0 {
		command.beat = game.tactical_beat_target(room)
	}
}

// Returns the command to commit this frame; ok is false while a tick move
// waits for its diagonal partner.
beat_input_command :: proc(chord: ^Beat_Chord, room: ^game.Room, command: Gameplay_Command, has_command: bool,
	dt: f32) -> (result: Gameplay_Command, ok: bool) {
	if chord.active {
		chord.timer -= dt
		if offset, found := beat_chord_offset(chord.command.direction); found {
			result = chord.command
			result.diagonal = offset
			chord.active = false
			return result, true
		}
		if chord.timer > 0 { return }
		chord.active = false
		return chord.command, true
	}
	if !has_command { return }
	result = command
	beat_stamp(room, &result)
	if result.kind == .Move && result.beat != 0 && result.origin_phase == .Combat {
		if offset, found := beat_chord_offset(result.direction); found {
			result.diagonal = offset
			return result, true
		}
		chord^ = {command = result, timer = BEAT_CHORD_SECONDS, active = true}
		return {}, false
	}
	return result, true
}
