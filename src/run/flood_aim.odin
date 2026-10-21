package run

import game "../game"
import grid "../engine/grid"
import render "../render"

// INONDAZIONE's aim (and CANNONE's, which turns its barrel the same way). While the card is held (dragged or chosen) the wave's way
// is one of the four directions: the mouse's cell gives it (the main axis from
// the player to the cell, game.flood_direction) until the mouse wheel turns it,
// a quarter turn a notch (up clockwise: north, east, south, west); the way the
// wheel chose then stays until the card is let go or put away. The board draws
// the arrow of the chosen way (render.draw_flood_preview) and the camera's zoom
// leaves the wheel alone. The card is played on a cell the chosen way names.

// Turns a way a quarter turn: `notches` > 0 clockwise.
flood_turn :: proc(way: game.Move_Direction, notches: int) -> game.Move_Direction {
	return game.Move_Direction(((int(way)+notches)%4+4)%4)
}

// Once a frame (poll_gameplay_command): whether the held card is aimed with the
// wheel, the way now, and the renderer told.
update_flood_aim :: proc(room: ^game.Room, renderer: ^render.Renderer, cards: ^Card_Interaction_State, deck: ^game.Deck_State, wheel: f32) {
	held := false
	if id := active_targeting_card_id(cards^); id != 0 {
		if index, found := game.hand_card_index_by_id(deck, id); found { held = game.card_is_wheel_aimed(deck.hand[index].definition_id) }
	}
	if !held {
		cards.flood_way_set = false
		render.set_flood_aim(renderer, false, false, .East)
		return
	}
	way := cards.flood_way
	if !cards.flood_way_set {
		way = room.player.tactical.facing
		if renderer.has_hovered_cell {
			if derived, ok := game.flood_direction(room.player.position, renderer.hovered_cell); ok { way = derived }
		}
	}
	if wheel != 0 {
		way = flood_turn(way, 1 if wheel > 0 else -1)
		cards.flood_way, cards.flood_way_set = way, true
	}
	render.set_flood_aim(renderer, true, cards.flood_way_set, way)
}

// The cell the Inondazione is played on: the one the mouse names, or, once the
// wheel has chosen the way, a cell the chosen way names (the first of the
// three cells that way the game takes as a drop).
flood_anchor :: proc(room: ^game.Room, card: game.Card_Instance, hovered: grid.Position, cards: Card_Interaction_State) -> grid.Position {
	if card.definition_id != .Flood || !cards.flood_way_set { return hovered }
	step := game.direction_offset(cards.flood_way)
	for distance in 1..=3 {
		cell := grid.Position{room.player.position.x+step.x*distance, room.player.position.y+step.y*distance}
		if _, valid := game.card_drop_target(room, card, cell); valid { return cell }
	}
	return {room.player.position.x+step.x, room.player.position.y+step.y}
}
