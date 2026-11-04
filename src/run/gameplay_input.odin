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
	// THE ARCHERS' ARROWS AND THE BOMBERS' BOMBS IN FLIGHT: the world's seconds
	// waiting, flown out (a world command, as a beat; game/enemy_arrow.odin,
	// game/enemy_bomb.odin).
	Enemy_Flight,
	// FIRST PERSON SHOOTER: one shot of the AK along `aim`, its trigger held (a
	// world command, as a beat: never blocked by the player's own action;
	// game/first_person.odin).
	First_Person_Fire,
	// FIRST PERSON BRAWLER: the frame's `seconds` of the fists' body and punches
	// along `fists` (a world command too; game/first_person_fists.odin).
	First_Person_Fists,
	First_Person_Sword,
	// FIRST PERSON ARCHER: the frame's draw and arrows along `bow` (a world
	// command too; game/first_person_bow.odin).
	First_Person_Bow,
	// BENVENUTI A NAPOLI's club: the frame's blow along `club` (a world command
	// too; game/first_person_club.odin).
	First_Person_Club,
	// LANCIAFIAMME's frame: the button and the aim (game/first_person_flame.odin).
	First_Person_Flame,
	// BENVENUTI A NAPOLI's grandpa: the frame's `seconds` of his body, blow and
	// keys along `nonno` (a world command too; game/napoli_nonno.odin).
	Napoli_Nonno,
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
	// What a First_Person_Fists frame asks of the body, and its seconds.
	fists: game.First_Person_Fists_Input,
	// What a First_Person_Sword frame asks of the blade.
	sword: game.First_Person_Sword_Input,
	// What a First_Person_Bow frame asks of the bow.
	bow: game.First_Person_Bow_Input,
	// What a First_Person_Club frame asks of the club.
	club: game.First_Person_Club_Input,
	// What a First_Person_Flame frame asks of the flame.
	flame: game.First_Person_Flame_Input,
	// What a Napoli_Nonno frame asks of the grandpa.
	nonno: game.First_Person_Nonno_Input,
	seconds: f32,
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

// The player's lane across frames (beat_input.odin; the user's choice of
// 2026-10-30, for a quicker, smoother game). While his own action runs (its
// animation, its timed seconds, a card's cast) the newest press is kept, one
// only, and done as soon as the action ends: before, it was dropped. A walk
// key held walks on, step after step: `walk` is the one pressed last
// (RUN_WALK_ACTIONS' index plus one; 0, none). Every boundary that clears this
// struct (a defence prompt, the window's end, a pause, a modal) drops both.
Buffered_Gameplay_Command :: struct {
	pending: Gameplay_Command,
	has_pending: bool,
	walk: int,
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
	     .Shadow_Emerge, .Shoot, .Lasso_Spin, .Pinball_Roll, .Enemy_Flight:
		return command.origin_phase == .Combat
	// The rod fishes a room cleared, and nothing else.
	case .Fish:
		return command.origin_phase == .Loot && command.target.kind == .Cell
	case .First_Person_Fire, .First_Person_Fists, .First_Person_Sword, .First_Person_Bow, .First_Person_Club, .First_Person_Flame, .Napoli_Nonno:
		return command.origin_phase == .Combat
	}
	unreachable()
}

clear_gameplay_command_buffer :: proc(buffer: ^Buffered_Gameplay_Command) {
	if buffer != nil {
		buffer^ = {}
	}
}
