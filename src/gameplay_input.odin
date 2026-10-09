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
	Timeout, Continue_Pulse, Begin_Diagonal, QTE_Key, QTE_Fail, Defense,
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
}

Buffered_Gameplay_Command :: struct {
	command:       Gameplay_Command,
	occupied:      bool,
	offered_count: int,
	dropped_count: int,
	consumed_count: int,
}

gameplay_command_is_valid :: proc(command: Gameplay_Command) -> bool {
	switch command.kind {
	case .None:
		return false
	case .Move:
		return command.origin_phase == .Combat || command.origin_phase == .Loot
	case .Dodge, .Wait, .Ability, .Play_Card, .Refocus, .Timeout, .Continue_Pulse, .Begin_Diagonal, .QTE_Key, .QTE_Fail, .Defense:
		return command.origin_phase == .Combat
	}
	unreachable()
}

offer_gameplay_command :: proc(
	buffer: ^Buffered_Gameplay_Command,
	command: Gameplay_Command,
) -> bool {
	if buffer == nil || !gameplay_command_is_valid(command) {
		return false
	}
	buffer.offered_count += 1
	if buffer.occupied {
		buffer.dropped_count += 1
		return false
	}
	buffer.command = command
	buffer.occupied = true
	return true
}

take_gameplay_command :: proc(
	buffer: ^Buffered_Gameplay_Command,
) -> (command: Gameplay_Command, ok: bool) {
	if buffer == nil || !buffer.occupied {
		return
	}
	command = buffer.command
	buffer.command = {}
	buffer.occupied = false
	buffer.consumed_count += 1
	ok = true
	return
}

clear_gameplay_command_buffer :: proc(buffer: ^Buffered_Gameplay_Command) {
	if buffer != nil {
		buffer^ = {}
	}
}
