package expedition

import grid "../engine/grid"
import game "../game"
import level "../level"

// THE STRUCTURES THE PLAYER SETS DOWN (Fase 7 of docs/piano-griglia.md). A kit from the backpack (campaign.Item_Kind.Structure_Kit)
// puts a structure of the catalog on the open map, out of a fight: the footprint follows the mouse, the wheel turns it. It
// stands for the rest of the expedition (it is saved with it) and cannot be taken up again; at most MAX_PLAYER_STRUCTURES in
// an expedition. The objects and the low walls take the blows of the enemies and fall apart (game/structure_damage.odin), the
// buildings do not. The rules of where it can go are level.place_check's (floor, flat, not touching another, no pocket) with the
// biome's own keep-clear ground, and no actor or thing lying on it.

MAX_PLAYER_STRUCTURES :: 3
// How far from the player, in cells, the nearest cell of the footprint may be.
PLAYER_STRUCTURE_REACH :: 9

Player_Placement :: enum u8 { Ok, Not_Exploring, In_Cave, No_More, Too_Far, On_The_Player, Occupied, Not_Allowed }

player_placement_text :: proc(result: Player_Placement, err: level.Placement_Error) -> string {
	switch result {
	case .Ok: return ""
	case .Not_Exploring: return "Puoi posare una struttura solo fuori dagli scontri."
	case .In_Cave: return "Non puoi costruire in una grotta."
	case .No_More: return "Hai gia posato tutte le strutture di questa spedizione."
	case .Too_Far: return "Troppo lontano: avvicinati."
	case .On_The_Player: return "Non puoi posarla addosso a te."
	case .Occupied: return "Qualcosa e in mezzo: un nemico, un oggetto o una trappola."
	case .Not_Allowed: return level.placement_error_text(err)
	}
	return ""
}

// The top left cell of a structure's plan when its middle is on `at`.
structure_origin_for :: proc(id: level.Structure_Id, rotation: u8, mirror: bool, at: grid.Position) -> grid.Position {
	plan := level.placed_plan({id = id, rotation = rotation%4, mirror = mirror})
	return {at.x-plan.width/2, at.y-plan.height/2}
}

// Whether `cell` is inside the plan of the structure at `origin` (the footprint's cells, with its walls and doors).
@(private = "file")
footprint_has :: proc(plan: ^level.Plan, origin, cell: grid.Position) -> bool {
	x, y := cell.x-origin.x, cell.y-origin.y
	return x >= 0 && y >= 0 && x < plan.width && y < plan.height && level.plan_at(plan, x, y) != .Outside
}

// Whether the player can set `id` down at `origin` now, and if not why not.
check_player_structure :: proc(w: ^World, data: ^level.Level, room: ^game.Room, id: level.Structure_Id, origin: grid.Position,
	rotation: u8, mirror: bool) -> (result: Player_Placement, err: level.Placement_Error) {
	if w == nil || data == nil || room == nil || room.player == nil || id >= .Count { return .Not_Allowed, .Bad_Structure }
	if room.phase != .Loot { return .Not_Exploring, .None }
	if w.in_cave > 0 { return .In_Cave, .None }
	if w.placed_by_player >= MAX_PLAYER_STRUCTURES { return .No_More, .None }
	plan := level.placed_plan({id = id, origin = origin, rotation = rotation%4, mirror = mirror})
	if plan.width == 0 { return .Not_Allowed, .Bad_Structure }
	nearest := 1<<20
	for y in 0..<plan.height { for x in 0..<plan.width {
		if level.plan_at(&plan, x, y) == .Outside { continue }
		nearest = min(nearest, distance({origin.x+x, origin.y+y}, room.player.position))
	} }
	if nearest > PLAYER_STRUCTURE_REACH { return .Too_Far, .None }
	if footprint_has(&plan, origin, room.player.position) { return .On_The_Player, .None }
	for enemy in room.enemies { if footprint_has(&plan, origin, enemy.position) { return .Occupied, .None } }
	for trap in room.traps { if footprint_has(&plan, origin, trap.position) { return .Occupied, .None } }
	for object in room.objects { if footprint_has(&plan, origin, object.position) { return .Occupied, .None } }
	for &group in w.groups[:w.group_count] {
		if !in_scope(w, group.cave) { continue }
		for member in group.members[:group.count] { if member.alive && footprint_has(&plan, origin, member.enemy.position) { return .Occupied, .None } }
	}
	for drop in w.drops[:w.drop_count] { if in_scope(w, drop.cave) && footprint_has(&plan, origin, drop.position) { return .Occupied, .None } }
	if error := level.place_check(data, id, origin, rotation, mirror, structure_keep_clear, w); error != .None { return .Not_Allowed, error }
	return .Ok, .None
}

// Sets it down if check_player_structure allows it. The new structure has the health its kind has.
place_player_structure :: proc(w: ^World, data: ^level.Level, room: ^game.Room, id: level.Structure_Id, origin: grid.Position,
	rotation: u8, mirror: bool) -> (result: Player_Placement, err: level.Placement_Error) {
	result, err = check_player_structure(w, data, room, id, origin, rotation, mirror)
	if result != .Ok { return }
	if w.structure_count >= MAX_WORLD_STRUCTURES { return .No_More, .None }
	index, placed := level.place_structure(data, id, origin, rotation, mirror, structure_keep_clear, w)
	if placed != .None { return .Not_Allowed, placed }
	data.structures[index].health = level.structure_max_health(id)
	w.placed_by_player += 1
	sync_structures(w, data)
	return .Ok, .None
}

// The world's list of structures is the level's: after one is set down, and before a checkpoint (the enemies break some).
sync_structures :: proc(w: ^World, data: ^level.Level) {
	if w == nil || data == nil || w.in_cave > 0 { return }
	w.structure_count = min(len(data.structures), MAX_WORLD_STRUCTURES)
	for i in 0..<w.structure_count { w.structures[i] = data.structures[i] }
}
