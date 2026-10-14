package main

import game "game"
import grid "grid"

Gameplay_Command_Kind :: enum {
	None,
	Move,
	Dodge,
	Wait,
	Ability,
	Play_Card,
	Refocus,
	Activate, Equip,
	Timeout, Continue_Pulse, Begin_Diagonal, QTE_Key, QTE_Fail, Defense,
	// Movimento Ombra's time is up: the player rises at the shadow's cell.
	Shadow_Emerge,
}

Gameplay_Command :: struct {
	kind:         Gameplay_Command_Kind,
	origin_phase: game.Room_Phase,
	direction:    game.Move_Direction,
	ability:      game.Player_Ability,
	card_id:      u32,
	target:       game.Target,
	offset: grid.Position,
	defense: game.Defense_Mode,
	// The tick this action was pressed on (0: off the tick), and for a move
	// made with two direction keys, its diagonal step.
	beat: u32,
	diagonal: grid.Position,
}

// No command is ever kept for later. While the player's own action runs (its
// animation or its timed seconds) a press is dropped; only a press made after
// the action ends acts. The one input held across frames is a move pressed on
// the tick, waiting BEAT_CHORD_SECONDS for its diagonal partner key
// (beat_input.odin): every boundary that clears this struct drops it too.
Buffered_Gameplay_Command :: struct {
	chord: Beat_Chord,
}

gameplay_command_is_valid :: proc(command: Gameplay_Command) -> bool {
	switch command.kind {
	case .None:
		return false
	case .Move:
		return command.origin_phase == .Combat || command.origin_phase == .Loot
	case .Equip:
		return command.origin_phase == .Combat || command.origin_phase == .Loot
	case .Activate:
		return command.origin_phase == .Combat
	case .Dodge, .Wait, .Ability, .Play_Card, .Refocus, .Timeout, .Continue_Pulse, .Begin_Diagonal, .QTE_Key, .QTE_Fail, .Defense,
	     .Shadow_Emerge:
		return command.origin_phase == .Combat
	}
	unreachable()
}

clear_gameplay_command_buffer :: proc(buffer: ^Buffered_Gameplay_Command) {
	if buffer != nil {
		buffer^ = {}
	}
}
