package run

import game "../game"
import grid "../engine/grid"

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
	// FERETRO: an arrow loosed at `target` (Ctrl and a left click on a foe).
	Shoot,
	// LAZZO: the world's seconds waiting, spun out (a world command, as a beat).
	Lasso_Spin,
	// CANNA DA PESCA: the rod cast at the cell `target`, once the room is
	// cleared (its slot; game/fishing.odin).
	Fish,
	// PINBALL: the world's seconds waiting, rolled out (a world command, as a
	// beat; game/pinball.odin).
	Pinball_Roll,
	// FIRST PERSON SHOOTER: one shot of the AK along `aim`, its trigger held (a
	// world command, as a beat: never blocked by the player's own action;
	// game/first_person.odin).
	First_Person_Fire,
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
	// The view a First_Person_Fire shot is fired along.
	aim: game.First_Person_Aim,
	// The way the wheel gave a cannon (CANNONE) before it was played.
	aim_way: game.Move_Direction,
	has_aim_way: bool,
}

// Both the native hand and MOSTRA EFFETTO construct the same commands. Their
// callers own pointer bounds, hand lookup and selection/drag state; only the
// game decides whether an anchor provides a target.
targeted_card_command :: proc(room: ^game.Room, card: game.Card_Instance, anchor: grid.Position, way := game.Move_Direction.North,
                              forced := false) -> (Gameplay_Command, bool) {
	target, valid := game.card_drop_target(room, card, anchor)
	if !valid { return {}, false }
	// A cannon turned with the wheel keeps its way; without it the game takes the
	// way from the player to the cell.
	aimed := forced && game.card_emplacement_kind(card.definition_id) == .Field_Cannon
	return {kind = .Play_Card, origin_phase = .Combat, card_id = card.id, target = target, aim_way = way if aimed else .North, has_aim_way = aimed}, true
}

immediate_card_command :: proc(card: game.Card_Instance) -> (Gameplay_Command, bool) {
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found || game.card_requires_spatial_target(definition) { return {}, false }
	target: game.Target
	if definition.targeting.rule == .Self || definition.targeting.rule == .Player {
		target = game.entity_target(game.PLAYER_ENTITY)
	}
	return {kind = .Play_Card, origin_phase = .Combat, card_id = card.id, target = target}, true
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
	     .Shadow_Emerge, .Shoot, .Lasso_Spin, .Pinball_Roll:
		return command.origin_phase == .Combat
	// The rod fishes a room cleared, and nothing else.
	case .Fish:
		return command.origin_phase == .Loot && command.target.kind == .Cell
	case .First_Person_Fire:
		return command.origin_phase == .Combat
	}
	unreachable()
}

clear_gameplay_command_buffer :: proc(buffer: ^Buffered_Gameplay_Command) {
	if buffer != nil {
		buffer^ = {}
	}
}
