package render

import game "../game"
import grid "../engine/grid"

// A refusal explains the same query that colours the board. Empty means the
// ordinary play/cancel instructions still apply; it never predicts a new rule.
@(private)
tactical_card_aim_hint :: proc(room: ^game.Room, card: game.Card_Instance, has_hover: bool, cell: grid.Position, aim: Flood_Aim = {}) -> cstring {
	if room == nil || room.player == nil || room.phase != .Combat { return "" }
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found || game.card_is_room_tool(card.definition_id) { return "" }
	if room.player.deck.energy < game.card_energy_cost(room, card.definition_id) { return "ENERGIA INSUFFICIENTE" }
	if game.card_requires_spatial_target(definition) && !has_hover { return "" }
	anchor := game.flood_card_anchor(room, card, cell, aim.active && aim.forced, aim.way)
	evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, anchor))
	if card.definition_id == .Pinball {
		if hint := pinball_aim_hint(room, evaluation.error); hint != "" { return hint }
	}
	switch evaluation.error {
	case .None: return ""
	case .Target_Out_Of_Range: return "FUORI PORTATA"
	case .Target_Blocked:
		if evaluation.query.error == .Line_Of_Sight_Blocked { return "LINEA DI TIRO BLOCCATA" }
		if evaluation.has_movement { return "PERCORSO BLOCCATO" }
		return "CASELLA NON DISPONIBILE"
	case .Invalid_Target:
		if evaluation.query.error == .Shape_Not_Aligned { return "BERSAGLIO NON ALLINEATO" }
		return "NESSUN BERSAGLIO VALIDO"
	case .Target_Too_Heavy: return "BERSAGLIO TROPPO PESANTE"
	case .No_Effects: return "NESSUN EFFETTO QUI"
	case .Invalid_Room, .Invalid_Phase, .Invalid_Instance, .Unknown_Definition, .Invalid_Definition, .Too_Many_Effects:
		return "CARTA NON DISPONIBILE"
	}
	return ""
}
