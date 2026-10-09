package game

import grid "../grid"

plan_bomber_intent :: proc(
	room: ^Room, enemy: ^Enemy, origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int, reserved_bombs: []grid.Position,
) -> Enemy_Intent {
	if tactical_enabled(room) { return plan_tactical_bomber(room, enemy, origin, predicted_positions, enemy_count, ordered_index, reserved_bombs) }
	distance := abs(origin.x-room.player.position.x)+abs(origin.y-room.player.position.y)
	if distance >= 2 && distance <= 5 &&
	   active_bomb_count(room)+len(reserved_bombs) < MAX_ACTIVE_BOMBS &&
	   len(room.objects)+len(reserved_bombs) < MAX_GRID_OBJECTS_PER_ROOM {
		offsets := [?]grid.Position{{0, 0}, {0, -1}, {1, 0}, {0, 1}, {-1, 0},
			{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
		for offset in offsets {
			anchor := add_position(room.player.position, offset)
			if !bomb_cell_is_available(room, anchor) || position_in_list(reserved_bombs, anchor) {
				continue
			}
			intent := make_wait_intent(room, origin)
			intent.kind = .Bombard
			intent.destination = anchor
			intent.damage = EXPLOSIVE_DAMAGE
			for y in anchor.y-1..=anchor.y+1 {
				for x in anchor.x-1..=anchor.x+1 {
					cell := grid.Position{x, y}
					if explosion_contains_cell(room, anchor, cell) {
						intent.threatened_cells[intent.threatened_cell_count] = cell
						intent.threatened_cell_count += 1
					}
				}
			}
			return intent
		}
	}
	// Reuse the archer's close-range retreat; otherwise approach without shooting.
	if distance == 1 {
		return plan_archer_intent(room, enemy, origin, predicted_positions, enemy_count, ordered_index)
	}
	return plan_chaser_intent(room, enemy, origin, predicted_positions, enemy_count, ordered_index)
}
