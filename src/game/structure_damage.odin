package game

import grid "../engine/grid"
import level "../level"

// WHAT THE ENEMIES BREAK (Fase 7 of docs/piano-griglia.md). The objects and the low walls the player has set down (a cart, a
// fountain, a statue, a machine, a ruin, a pen: level.structure_max_health) take the damage of an enemy's blow when they stand
// in its threatened cells or beside the one who strikes it; a building never does. A structure takes a blow once, however many
// of its cells are in reach; when its health is gone it leaves the map (level.damage_structure).

// Returns how many fell.
strike_structures :: proc(room: ^Room, attacker: grid.Position, cells: []grid.Position, damage: i32) -> (fell: int) {
	if room == nil || room.level_data == nil || damage <= 0 || len(room.level_data.structures) == 0 { return }
	data := room.level_data
	hit: [level.MAX_STRUCTURES_PER_LEVEL]bool
	any_hit := false
	reach :: proc(data: ^level.Level, cell: grid.Position, hit: ^[level.MAX_STRUCTURES_PER_LEVEL]bool) -> bool {
		index, found := level.structure_index_at(data, cell)
		if !found || index >= len(hit) || data.structures[index].health <= 0 { return false }
		hit[index] = true
		return true
	}
	for cell in cells { if reach(data, cell, &hit) { any_hit = true } }
	for dy in -1..=1 { for dx in -1..=1 {
		if reach(data, {attacker.x+dx, attacker.y+dy}, &hit) { any_hit = true }
	} }
	if !any_hit { return }
	// From the last to the first: a structure that falls moves the later ones up.
	for index := len(data.structures)-1; index >= 0; index -= 1 {
		if index < len(hit) && hit[index] && level.damage_structure(data, index, damage) { fell += 1 }
	}
	return
}
