package game

import grid "../engine/grid"

// A wheel-aimed Flood Wave uses the first legal drop along its chosen way.
// Input, previews and hints share this anchor; targeting legality remains
// card_drop_target's. Other cards keep the cell beneath the pointer.
flood_card_anchor :: proc(room: ^Room, card: Card_Instance, hovered: grid.Position, forced: bool, way: Move_Direction) -> grid.Position {
	if card.definition_id != .Flood_Wave || !forced { return hovered }
	step := direction_offset(way)
	for distance in 1..=3 {
		cell := grid.offset(room.player.position, step.x*distance, step.y*distance)
		if _, valid := card_drop_target(room, card, cell); valid { return cell }
	}
	return grid.offset(room.player.position, step.x, step.y)
}
