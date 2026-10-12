package game

import grid "../grid"

// Four coils on the corners of a square whose inside, coils excluded, spans at
// least 2x2 cells form a ring. Activating it while enemies stand in the field
// starts a duel instead of a discharge: one enemy fights alone, several fight
// a tag match. The ring opens once per floor; afterwards the square is an
// ordinary electromagnetic field again.
TESLA_RING_MIN_SIDE :: 3
MAX_TESLA_RING_ROSTER :: 4
// A lost duel costs a quarter of the maximum health, never the last point.
TESLA_RING_LOSS_DIVISOR :: i32(4)

// Easter eggs open once per floor. A floor is the whole run until floors
// exist; begin_floor clears them for the next one.
Floor_Secret :: enum u8 {
	Tesla_Ring,
	Western_Ranch,
}

begin_floor :: proc(player: ^Player) {
	if player != nil { player.floor_secrets = {} }
}

// Set when the coils are spent; the host opens the duel and settles it.
Tesla_Ring :: struct {
	enemy_ids: [MAX_TESLA_RING_ROSTER]u32,
	count: int,
	pending: bool,
}

// What the duel left of each opponent, parallel to Tesla_Ring.enemy_ids, in
// thousandths of the health it entered the ring with.
Tesla_Ring_Outcome :: struct {
	won: bool,
	remaining: [MAX_TESLA_RING_ROSTER]i32,
}

Tesla_Ring_Report :: struct {
	settled, won: bool,
	defeated: int,
	player_damage: i32,
	reward: Ring_Reward,
}

// The four coils sit exactly on the corners of one axis-aligned square.
tesla_network_is_square :: proc(network: ^Board_Device_Network) -> bool {
	if network == nil || network.count != MAX_TESLA_COILS || !network.field { return false }
	lo, hi := network.positions[0], network.positions[0]
	for p in network.positions[:network.count] {
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
	}
	side := hi.x-lo.x
	if side < TESLA_RING_MIN_SIDE || hi.y-lo.y != side { return false }
	corners := [MAX_TESLA_COILS]grid.Position{lo, {hi.x, lo.y}, hi, {lo.x, hi.y}}
	for corner in corners {
		found := false
		for p in network.positions[:network.count] { found = found || p == corner }
		if !found { return false }
	}
	return true
}

// The enemies the next activation would pull into the ring, in planning order.
query_tesla_ring :: proc(room: ^Room) -> (ring: Tesla_Ring, ok: bool) {
	if room == nil || room.player == nil || room.phase != .Combat || .Tesla_Ring in room.player.floor_secrets { return }
	network := query_board_device_network(room)
	if !network.ready || !tesla_network_is_square(&network) { return }
	ids, count := enemy_ids_in_planning_order(room)
	for id in ids[:count] {
		index, found := enemy_index_by_id(room, id)
		if found && ring.count < MAX_TESLA_RING_ROSTER &&
		   board_device_network_contains_cell(room, &network, room.enemies[index].position) {
			ring.enemy_ids[ring.count] = id
			ring.count += 1
		}
	}
	return ring, ring.count > 0
}

// Spends the square's coils without a discharge and opens the floor's ring.
begin_tesla_ring :: proc(room: ^Room) -> bool {
	if !board_devices_can_activate(room) || room.tesla_ring.pending { return false }
	ring, ok := query_tesla_ring(room)
	if !ok { return false }
	clear_event_log(&room.recent_events)
	network := query_board_device_network(room)
	for id in network.ids[:network.count] {
		index, found := object_index_by_id(room, id)
		if !found { continue }
		position := room.objects[index].position
		remove_grid_object(room, index)
		record_event(&room.recent_events, {kind = .Entity_Defeated, source = SYSTEM_ENTITY,
			target = object_entity(id), object_kind = .Tesla_Coil,
			from_position = position, to_position = position})
	}
	ring.pending = true
	room.tesla_ring = ring
	room.player.floor_secrets += {.Tesla_Ring}
	return true
}

// A win defeats every opponent, loot included. A loss costs the player a
// quarter of the maximum health; opponents keep what the duel took from them
// and those knocked out in a tag match stay down.
settle_tesla_ring :: proc(room: ^Room, outcome: Tesla_Ring_Outcome) -> (report: Tesla_Ring_Report) {
	if room == nil || room.player == nil || !room.tesla_ring.pending { return }
	ring := room.tesla_ring
	room.tesla_ring = {}
	report.settled, report.won = true, outcome.won
	clear_event_log(&room.recent_events)
	action := make_action(.Trigger, SYSTEM_ENTITY)
	for slot in 0..<ring.count {
		index, found := enemy_index_by_id(room, ring.enemy_ids[slot])
		if !found { continue }
		enemy := &room.enemies[index]
		left: i32
		if !outcome.won {
			permille := clamp(outcome.remaining[slot], 0, 1000)
			left = (enemy.health*permille+999)/1000
		}
		if left <= 0 {
			// Shields cannot save an opponent the ring already put down.
			added := add_effect(&action, damage_effect(enemy_entity(enemy.id), enemy.health+999))
			assert(added)
			report.defeated += 1
		} else if left < enemy.health {
			enemy.health = left
		}
	}
	if action.effect_count > 0 {
		resolved := resolve_action(room, &action)
		assert(resolved.accepted)
		append_event_log(&room.recent_events, &resolved.events)
	}
	collect_loot_in_magnet_range(room)
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	if outcome.won {
		report.reward = record_ring_win(room)
	} else {
		player := room.player
		loss := max(i32(1), player.stats.max_health/TESLA_RING_LOSS_DIVISOR)
		report.player_damage = min(loss, max(i32(0), player.health-1))
		player.health -= report.player_damage
	}
	return
}
