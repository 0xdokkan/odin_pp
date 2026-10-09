package game

import grid "../grid"

MAX_TESLA_COILS :: 4
MAX_SHOCK_FLOORS :: 4
TESLA_RECHARGE_BEATS :: i32(3)

Board_Device_Network :: struct {
	ids: [MAX_TESLA_COILS]u32,
	positions: [MAX_TESLA_COILS]grid.Position,
	count: int,
	hull: [MAX_TESLA_COILS]grid.Position,
	hull_count: int,
	field: bool,
	ready: bool,
	damage: i32,
	base_damage: i32,
	active_links: u8,
}

board_device_kind :: proc(kind: Grid_Object_Kind) -> bool {
	return kind == .Shock_Floor || kind == .Tesla_Coil
}

card_is_board_device :: proc(id: Card_Id) -> bool {
	return id == .Shock_Floor || id == .Tesla_Coil
}

board_device_count :: proc(room: ^Room, kind: Grid_Object_Kind) -> (count: int) {
	if room == nil { return }
	for object in room.objects {
		if object.kind == kind { count += 1 }
	}
	return
}

board_tesla_count :: proc(room: ^Room) -> int {
	return board_device_count(room, .Tesla_Coil)
}

board_device_can_deploy :: proc(room: ^Room, kind: Grid_Object_Kind, position: grid.Position) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || !board_device_kind(kind) ||
	   len(room.objects) >= MAX_GRID_OBJECTS_PER_ROOM || room.next_object_id == 0 || room.next_object_id == max(u32) ||
	   !base_cell_is_walkable(room, position) || obstacle_at(room, position) || position == room.exit_position {
		return false
	}
	if _, occupied := object_index_at(room, position); occupied { return false }
	if _, trapped := trap_index_at(room, position); trapped { return false }
	if kind == .Tesla_Coil {
		if room.player.position == position { return false }
		if _, occupied := enemy_index_at(room, position); occupied { return false }
		return board_tesla_count(room) < MAX_TESLA_COILS
	}
	return board_device_count(room, .Shock_Floor) < MAX_SHOCK_FLOORS
}

deploy_device_effect :: proc(kind: Grid_Object_Kind, position: grid.Position, damage: i32) -> Effect {
	return {kind = .Deploy_Device, target = PLAYER_ENTITY, object_kind = kind, destination = position, amount = damage, charges = 1 if kind == .Shock_Floor else 0}
}

deploy_board_device :: proc(room: ^Room, kind: Grid_Object_Kind, position: grid.Position, damage, charges: i32, events: ^Event_Log) -> bool {
	if events == nil || events.count < 0 || events.count >= MAX_GAME_EVENTS ||
	   !board_device_can_deploy(room, kind, position) || damage <= 0 ||
	   (kind == .Shock_Floor && (charges < 1 || charges > 4)) { return false }
	definition, _ := grid_object_definition(kind)
	object := Grid_Object{
		id = room.next_object_id, kind = kind, position = position,
		health = definition.max_health, max_health = definition.max_health,
		device_damage = damage, device_charges = charges, device_target_limit = charges,
	}
	room.next_object_id += 1
	append(&room.objects, object)
	record_event(events, {kind = .Object_Spawned, source = PLAYER_ENTITY, target = object_entity(object.id),
		object_kind = kind, from_position = position, to_position = position, amount = damage, duration = charges})
	return true
}

resolve_board_device_card :: proc(room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action) -> (report: Action_Report) {
	if compiled == nil || !card_is_board_device(instance.definition_id) || compiled.kind != .Card ||
	   compiled.source != PLAYER_ENTITY || compiled.target != target || compiled.effect_count != 1 ||
	   compiled.effects[0].kind != .Deploy_Device || !effect_is_valid(room, compiled.effects[0]) { return }
	action := compiled^
	staged_dice := room.player.dice
	roll: Dice_Roll
	if instance.definition_id == .Shock_Floor {
		rolled: bool
		roll, rolled = roll_d4(&staged_dice)
		if !rolled { return }
		action.effects[0].charges = roll.total
	}
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	if instance.definition_id == .Shock_Floor {
		room.player.dice = staged_dice
		record_report_event(&report, spell_dice_event(instance, origin, target.cell, PLAYER_ENTITY, roll))
	}
	record_report_event(&report, spell_card_event(.Spell_Launched, instance, origin, target.cell))
	record_report_event(&report, spell_card_event(.Spell_Impact, instance, origin, target.cell))
	merge_spell_hit_report(&report, &hit)
	return
}

board_device_cross :: proc(a, b, c: grid.Position) -> int {
	return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
}

// IDs retain deployment order even when destruction reorders room.objects.
query_board_device_network :: proc(room: ^Room) -> (network: Board_Device_Network) {
	if room == nil { return }
	network.ready = true
	for object in room.objects {
		if object.kind != .Tesla_Coil || network.count == MAX_TESLA_COILS { continue }
		at := network.count
		for at > 0 && network.ids[at-1] > object.id {
			network.ids[at] = network.ids[at-1]
			network.positions[at] = network.positions[at-1]
			at -= 1
		}
		network.ids[at], network.positions[at] = object.id, object.position
		network.count += 1
		network.ready = network.ready && object.device_cooldown <= 0
		network.base_damage = max(network.base_damage, object.device_damage)
	}
	network.ready = network.ready && network.count >= 2
	network.damage = network.base_damage
	if network.count != MAX_TESLA_COILS {
		finalize_board_device_network(room, &network)
		return
	}
	// Monotone hull gives the same field for crossed placement orders; collinear
	// arrangements remain lightning walls rather than inventing an area.
	points := network.positions
	for i in 1..<network.count {
		point, at := points[i], i
		for at > 0 && (points[at-1].x > point.x || (points[at-1].x == point.x && points[at-1].y > point.y)) {
			points[at] = points[at-1]
			at -= 1
		}
		points[at] = point
	}
	hull: [MAX_TESLA_COILS*2]grid.Position
	count := 0
	for point in points {
		for count >= 2 && board_device_cross(hull[count-2], hull[count-1], point) <= 0 { count -= 1 }
		hull[count] = point
		count += 1
	}
	lower := count
	for i := network.count-2; i >= 0; i -= 1 {
		point := points[i]
		for count > lower && board_device_cross(hull[count-2], hull[count-1], point) <= 0 { count -= 1 }
		hull[count] = point
		count += 1
	}
	network.hull_count = min(MAX_TESLA_COILS, max(0, count-1))
	copy(network.hull[:], hull[:network.hull_count])
	network.field = network.hull_count >= 3
	if network.field {
		for i in 0..<network.hull_count {
			network.damage = min(network.damage, board_device_link_damage(network.base_damage, network.hull[i], network.hull[(i+1)%network.hull_count]))
		}
	}
	finalize_board_device_network(room, &network)
	return
}


// Coils cannot conduct through opaque walls or cover. The same trace handles
// diagonal sealed corners as card targeting, so preview and damage agree.
board_device_link_is_clear :: proc(room: ^Room, a, b: grid.Position) -> bool {
	return a != b && board_device_clear_path(room, a, b)
}

// Device networks span a room, so they do not inherit the twelve-cell bound of
// card targeting's fixed path buffer. This uses the same corner occlusion rule.
board_device_clear_path :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	return room != nil && base_cell_is_walkable(room, origin) && base_cell_is_walkable(room, target) &&
	       !cell_blocks_line_of_sight(room, target) &&
	       tactical_line_visible(origin, target, tactical_room_opaque, room)
}

finalize_board_device_network :: proc(room: ^Room, network: ^Board_Device_Network) {
	if network.count < 2 { network.ready = false; return }
	links := network.count if network.count > 2 else 1
	for i in 0..<links {
		if board_device_link_is_clear(room, network.positions[i], network.positions[(i+1)%network.count]) {
			network.active_links |= u8(1)<<u32(i)
		}
	}
	if network.field {
		for i in 0..<network.hull_count {
			if !board_device_link_is_clear(room, network.hull[i], network.hull[(i+1)%network.hull_count]) {
				network.field = false
				break
			}
		}
	}
	network.ready = network.ready && (network.active_links != 0 || network.field)
}

// Each doubling of separation halves damage; rounding up keeps a distant
// connection meaningful. The shared helper also supplies the inspection HUD.
board_device_link_damage :: proc(base_damage: i32, a, b: grid.Position) -> i32 {
	distance := max(1, max(abs(a.x-b.x), abs(a.y-b.y)))
	return max(i32(1), (base_damage+i32(distance)-1)/i32(distance))
}

board_device_network_damage_at :: proc(room: ^Room, network: ^Board_Device_Network, cell: grid.Position) -> i32 {
	if !board_device_network_contains_cell(room, network, cell) { return 0 }
	if network.field { return network.damage }
	damage: i32
	links := network.count if network.count > 2 else 1
	for i in 0..<links {
		a, b := network.positions[i], network.positions[(i+1)%network.count]
		if (network.active_links&(u8(1)<<u32(i))) != 0 && board_device_segment_contains(a, b, cell) {
			damage = max(damage, board_device_link_damage(network.base_damage, a, b))
		}
	}
	return damage
}

board_device_segment_contains :: proc(a, b, cell: grid.Position) -> bool {
	if cell.x < min(a.x,b.x) || cell.x > max(a.x,b.x) || cell.y < min(a.y,b.y) || cell.y > max(a.y,b.y) { return false }
	return abs(board_device_cross(a, b, cell))*2 <= max(abs(b.x-a.x), abs(b.y-a.y))
}

// Shared by targeting preview and resolution; walls exclude their own cells.
board_device_network_contains_cell :: proc(room: ^Room, network: ^Board_Device_Network, cell: grid.Position) -> bool {
	if room == nil || network == nil || network.count < 2 || !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) { return false }
	if network.field {
		for i in 0..<network.hull_count {
			if board_device_cross(network.hull[i], network.hull[(i+1)%network.hull_count], cell) < 0 { return false }
		}
		// An opaque pocket wholly hidden from all coils receives no energy.
		for coil in network.positions[:network.count] {
			if coil == cell || board_device_clear_path(room, coil, cell) { return true }
		}
		return false
	}
	links := network.count if network.count > 2 else 1
	for i in 0..<links {
		if (network.active_links&(u8(1)<<u32(i))) != 0 &&
		   board_device_segment_contains(network.positions[i], network.positions[(i+1)%network.count], cell) { return true }
	}
	return false
}

shock_floor_contains_cell :: proc(room: ^Room, center, cell: grid.Position) -> bool {
	return room != nil && max(abs(center.x-cell.x), abs(center.y-cell.y)) <= 1 &&
	       base_cell_is_walkable(room, cell) && !obstacle_at(room, cell)
}

arm_shock_floor :: proc(object: ^Grid_Object, enemy: Entity_Ref, events: ^Event_Log) {
	assert(object != nil && object.kind == .Shock_Floor && enemy.kind == .Enemy)
	object.device_armed = true
	record_event(events, {kind = .Hazard_Triggered, source = enemy,
		target = object_entity(object.id), object_kind = .Shock_Floor,
		from_position = object.position, to_position = object.position})
}

// All movement, including pushes, charges and teleport landings, enters here
// through the shared movement resolver. Crossing an entire area still trips
// its trap; discharges retain the world's one-second cadence.
trigger_shock_floors_on_entry :: proc(room: ^Room, entity: Entity_Ref, events: ^Event_Log) {
	if room == nil || room.phase != .Combat || entity.kind != .Enemy { return }
	position, present := entity_position(room, entity)
	if !present { return }
	for &object in room.objects {
		if object.kind == .Shock_Floor && !object.device_armed && object.device_charges > 0 &&
		   shock_floor_contains_cell(room, object.position, position) {
			arm_shock_floor(&object, entity, events)
		}
	}
}

board_devices_can_activate :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || !tactical_allows_action(room) { return false }
	return query_board_device_network(room).ready
}

// Only Tesla networks use the active command. Shock floors are passive traps;
// neither their presence nor their state can enable or consume this action.
activate_board_devices :: proc(room: ^Room) -> bool {
	if !board_devices_can_activate(room) { return false }
	clear_event_log(&room.recent_events)
	network := query_board_device_network(room)
	for &object in room.objects {
		if object.kind == .Tesla_Coil { object.device_cooldown = TESLA_RECHARGE_BEATS }
	}
	links := network.hull_count if network.field else (network.count if network.count > 2 else 1)
	for i in 0..<links {
		if !network.field && (network.active_links&(u8(1)<<u32(i))) == 0 { continue }
		a := network.hull[i] if network.field else network.positions[i]
		b := network.hull[(i+1)%network.hull_count] if network.field else network.positions[(i+1)%network.count]
		damage := network.damage if network.field else board_device_link_damage(network.base_damage, a, b)
		record_event(&room.recent_events, {kind = .Spell_Impact, source = PLAYER_ENTITY,
			target = SYSTEM_ENTITY, card_definition = .Tesla_Coil,
			from_position = a, to_position = b, amount = damage})
	}
	// All targets belong to one discharge. The system source remains valid if
	// friendly fire is lethal, and the normal resolver defers reactions and
	// terminal cleanup until every captured target has received its one hit.
	action := make_action(.Trigger, SYSTEM_ENTITY)
	action.visual_group = 1
	if network.field && board_device_network_contains_cell(room, &network, room.player.position) {
		added := add_effect(&action, damage_effect(PLAYER_ENTITY, board_device_network_damage_at(room, &network, room.player.position)))
		assert(added)
	}
	ids, count := enemy_ids_in_planning_order(room)
	for id in ids[:count] {
		index, found := enemy_index_by_id(room, id)
		if found && board_device_network_contains_cell(room, &network, room.enemies[index].position) {
			added := add_effect(&action, damage_effect(enemy_entity(id), board_device_network_damage_at(room, &network, room.enemies[index].position)))
			assert(added)
		}
	}
	if action.effect_count > 0 {
		report := resolve_action(room, &action)
		assert(report.accepted)
		append_event_log(&room.recent_events, &report.events)
	}
	// Lightning walls leave their coils anchored for later combinations. Only
	// a complete electromagnetic field spends its four participating coils,
	// after the entire discharge resolves. Terminal cleanup may already have
	// removed them; stable IDs prevent duplicate removals or unrelated objects.
	if network.field {
		for id in network.ids[:network.count] {
			index, found := object_index_by_id(room, id)
			if !found { continue }
			position := room.objects[index].position
			remove_grid_object(room, index)
			record_event(&room.recent_events, {kind = .Entity_Defeated, source = SYSTEM_ENTITY,
				target = object_entity(id), object_kind = .Tesla_Coil,
				from_position = position, to_position = position})
		}
	}
	return true
}

// Dormant floors never spend charges. The first occupied beat also handles a
// floor placed underneath an enemy. Once tripped, the committed d4 sequence
// runs to completion even if the area becomes empty again.
tick_board_devices :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || room.phase != .Combat { return }
	ids: [MAX_SHOCK_FLOORS]u32
	count := 0
	for &object in room.objects {
		if object.kind == .Tesla_Coil { object.device_cooldown = max(0, object.device_cooldown-1) }
		if object.kind == .Shock_Floor && object.device_charges > 0 && count < len(ids) {
			ids[count] = object.id
			count += 1
		}
	}
	for id in ids[:count] {
		if room.phase != .Combat { break }
		index, found := object_index_by_id(room, id)
		if !found { continue }
		object := room.objects[index]
		enemy_ids, enemy_count := shock_floor_targets(room, object)
		if !object.device_armed {
			if enemy_count == 0 { continue }
			arm_shock_floor(&room.objects[index], enemy_entity(enemy_ids[0]), &pulse.events)
		}
		room.objects[index].device_charges -= 1
		record_event(&pulse.events, {kind = .Spell_Impact, source = object_entity(id), target = SYSTEM_ENTITY,
			card_definition = .Shock_Floor, object_kind = .Shock_Floor, from_position = object.position,
			to_position = object.position, amount = object.device_damage, area_mask = 0x1ff})
		for enemy_id in enemy_ids[:enemy_count] {
			if room.phase != .Combat { break }
			ei, present := enemy_index_by_id(room, enemy_id)
			if !present || !shock_floor_contains_cell(room, object.position, room.enemies[ei].position) { continue }
			action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(enemy_id)), .Entity)
			add_effect(&action, damage_effect(enemy_entity(enemy_id), object.device_damage))
			report := resolve_action(room, &action)
			merge_action_report(pulse, &report)
		}
		index, found = object_index_by_id(room, id)
		if found && room.objects[index].device_charges <= 0 {
			remove_grid_object(room, index)
			record_event(&pulse.events, {kind = .Entity_Defeated, source = SYSTEM_ENTITY, target = object_entity(id)})
		}
	}
}


// The committed d4 controls both repetition and target count. Equal distances
// always use entity ID, independent of removals or physical array ordering.
shock_floor_targets :: proc(room: ^Room, object: Grid_Object) -> (ids: [MAX_ENEMIES_PER_ROOM]u32, count: int) {
	distances: [MAX_ENEMIES_PER_ROOM]int
	for enemy in room.enemies {
		if !shock_floor_contains_cell(room, object.position, enemy.position) { continue }
		distance := max(abs(object.position.x-enemy.position.x), abs(object.position.y-enemy.position.y))
		at := count
		for at > 0 && (distances[at-1] > distance || (distances[at-1] == distance && ids[at-1] > enemy.id)) {
			distances[at], ids[at] = distances[at-1], ids[at-1]
			at -= 1
		}
		distances[at], ids[at] = distance, enemy.id
		count += 1
	}
	count = min(count, int(object.device_target_limit))
	return
}


// Deployed devices belong to one fight. Clearing them also restores every loot
// corridor the player could have sealed with a solid coil during combat.
disarm_board_devices_after_combat :: proc(room: ^Room, events: ^Event_Log) {
	if room == nil || room.phase == .Combat { return }
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for object in room.objects {
		if !board_device_kind(object.kind) { continue }
		at := count
		for at > 0 && ids[at-1] > object.id { ids[at] = ids[at-1]; at -= 1 }
		ids[at] = object.id
		count += 1
	}
	for id in ids[:count] {
		index, found := object_index_by_id(room, id)
		if !found { continue }
		position := room.objects[index].position
		remove_grid_object(room, index)
		record_event(events, {kind = .Entity_Defeated, source = SYSTEM_ENTITY, target = object_entity(id), from_position = position, to_position = position})
	}
}
