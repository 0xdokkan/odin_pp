package game

import grid "../engine/grid"

// CANNONE and CANNONE LASER. The card sets a cannon on its raised stand on a
// free cell and aims it (the mouse wheel turns it, as the Inondazione's wave;
// else the way from the player to the cell). Each world beat, CANNON_SECONDS of
// them, it fires straight ahead from the cell in front of it:
//
//   - the ball (Cannone): the first foe on the line takes the damage and stops
//     it; a wall, a cover or a blocking thing stops it first; a barrel on its way
//     catches and stops it;
//   - the beam (Cannone laser, what the Cannone becomes at its second upgrade,
//     deck.odin): every foe on the line to the wall takes the damage, and a
//     barrel on it catches without stopping it.
//
// The cannon is solid (it blocks the way as a Tesla Coil does) and nothing
// aims at it. After its last beat it falls apart. Damage is the card's amount:
// Cannone 2 (+1 an upgrade), Laser 3 (+1 an upgrade); the tick adds to it.

CANNON_SECONDS :: i32(20)
CANNON_BASE_DAMAGE :: i32(2)
CANNON_MAX_UPGRADE_LEVEL :: i32(2)
// The Cannone's upgrade that makes it the Cannone laser.
CANNON_EVOLVE_LEVEL :: i32(2)
LASER_BASE_DAMAGE :: i32(3)
LASER_MAX_UPGRADE_LEVEL :: i32(3)

@(private)
place_cannon_effect :: proc(damage, seconds: i32, laser: bool) -> Effect {
	return {kind = .Place_Cannon, target = PLAYER_ENTITY, amount = damage, duration = seconds,
		card_definition = .Laser_Cannon if laser else .Cannon}
}

// What a cannon's fire reaches from its cell along its way: the foes it
// strikes (the first only, for the ball), the barrels it sets off, and the
// last cell it crosses.
Cannon_Line :: struct {
	foes: [MAX_ENEMIES_PER_ROOM]u32,
	foe_count: int,
	barrels: [MAX_GRID_OBJECTS_PER_ROOM]u32,
	barrel_count: int,
	last: grid.Position,
}

cannon_line :: proc(room: ^Room, origin: grid.Position, way: Move_Direction, laser: bool) -> (line: Cannon_Line) {
	step := direction_offset(way)
	line.last = origin
	cell := grid.Position{origin.x+step.x, origin.y+step.y}
	for grid.contains(&room.level_data.tiles, cell) {
		if !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) { break }
		if index, present := enemy_index_at(room, cell); present {
			line.foes[line.foe_count] = room.enemies[index].id
			line.foe_count += 1
			line.last = cell
			if !laser { break }
		} else if object, standing := grid_object_at(room, cell); standing {
			definition, _ := grid_object_definition(object.kind)
			if definition.explosive && line.barrel_count < len(line.barrels) {
				line.barrels[line.barrel_count] = object.id
				line.barrel_count += 1
				line.last = cell
				if !laser { break }
			} else if definition.blocks_movement { break }
		}
		line.last = cell
		cell = grid.Position{cell.x+step.x, cell.y+step.y}
	}
	return
}

// One beat of every cannon: it fires, then its time runs down; at the end it
// falls apart.
@(private)
cannon_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for object in room.objects { if object.kind == .Cannon && count < len(ids) { ids[count] = object.id; count += 1 } }
	for id in ids[:count] {
		if room.phase != .Combat { return }
		index, found := object_index_by_id(room, id)
		if !found { continue }
		cannon := room.objects[index]
		line := cannon_line(room, cannon.position, cannon.facing, cannon.laser)
		target := SYSTEM_ENTITY
		if line.foe_count > 0 { target = enemy_entity(line.foes[0]) }
		record_event(&pulse.events, {kind = .Cannon_Fired, source = object_entity(id), target = target, object_kind = .Cannon,
			from_position = cannon.position, to_position = line.last, amount = cannon.power, duration = 1 if cannon.laser else 0,
			card_definition = .Laser_Cannon if cannon.laser else .Cannon})
		action := make_action(.Trigger, object_entity(id))
		for foe in line.foes[:line.foe_count] {
			added := add_effect(&action, damage_effect(enemy_entity(foe), cannon.power))
			assert(added)
		}
		for barrel in line.barrels[:line.barrel_count] {
			effect := damage_effect(object_entity(barrel), cannon.power)
			if effect_is_valid(room, effect) && action.effect_count < MAX_ACTION_EFFECTS { add_effect(&action, effect) }
		}
		if action.effect_count > 0 {
			report := resolve_action(room, &action)
			merge_action_report(pulse, &report)
		}
		if room.phase != .Combat { return }
		index, found = object_index_by_id(room, id)
		if !found { continue }
		room.objects[index].life -= 1
		if room.objects[index].life <= 0 {
			record_event(&pulse.events, {kind = .Cannon_Broken, source = SYSTEM_ENTITY, target = object_entity(id), object_kind = .Cannon,
				from_position = cannon.position, to_position = cannon.position, card_definition = cannon_card(cannon)})
			remove_grid_object(room, index)
		}
	}
}

@(private = "file")
cannon_card :: proc(object: Grid_Object) -> Card_Id {
	return .Laser_Cannon if object.laser else .Cannon
}
