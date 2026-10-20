package game

// One slot for each kind: no status is ever refused for want of room (the
// player alone can carry every kind but Rallentamento at once).
MAX_STATUSES_PER_ENTITY :: len(Status_Kind)

Status_Kind :: enum {
	Poison,
	Shield,
	Thorns,
	Afterimage,
	Stagger,
	Survey,
	// Bruciatura: damage equal to its stacks at each new window; they never wear.
	Burn,
	// Rallentamento: each stack holds an enemy's next planned intent a second
	// longer; the action it held wears a stack. No effect on the player.
	Slow,
	// The player's charges (player_charges.odin): stacks only he carries,
	// spent one at a time by what they load, until they run out or the room
	// ends. Riflesso (Deflect): the next enemy blow on him comes back at its
	// attacker.
	Deflect,
	// Frecce (Feretro): arrows loosed with Ctrl and a click.
	Arrows,
	// Destino (Dado del Destino): bumps that roll the card's die at the hit.
	Fate,
	// Lama (Lama Velenosa): bumps that poison.
	Venom_Blade,
}

status_kind_is_valid :: proc(kind: Status_Kind) -> bool {
	switch kind {
	case .Poison, .Shield, .Thorns, .Afterimage, .Stagger, .Survey, .Burn, .Slow,
	     .Deflect, .Arrows, .Fate, .Venom_Blade:
		return true
	}
	return false
}

// Poison, Burn and Slow are stacks: applications add up and nothing counts
// them down by the pulse. Their bearer's actions (Poison, Slow) or the new
// windows (Burn) wear them instead (pulse.odin). The player's charges are
// stacks too, worn by their use.
status_kind_stacks :: proc(kind: Status_Kind) -> bool {
	switch kind {
	case .Poison, .Burn, .Slow, .Deflect, .Arrows, .Fate, .Venom_Blade:
		return true
	case .Shield, .Thorns, .Afterimage, .Stagger, .Survey:
	}
	return false
}

// The player's charges: only he carries them, and only his own blows (and
// the blows that reach him) spend them.
status_kind_is_player_charge :: proc(kind: Status_Kind) -> bool {
	switch kind {
	case .Deflect, .Arrows, .Fate, .Venom_Blade:
		return true
	case .Poison, .Shield, .Thorns, .Afterimage, .Stagger, .Survey, .Burn, .Slow:
	}
	return false
}

status_kind_name :: proc(kind: Status_Kind) -> string {
	switch kind {
	case .Poison:
		return "Poison"
	case .Shield:
		return "Shield"
	case .Thorns:
		return "Thorns"
	case .Afterimage:
		return "Afterimage"
	case .Stagger:
		return "Stagger"
	case .Survey:
		return "Survey"
	case .Burn:
		return "Burn"
	case .Slow:
		return "Slow"
	case .Deflect:
		return "Deflect"
	case .Arrows:
		return "Arrows"
	case .Fate:
		return "Fate"
	case .Venom_Blade:
		return "Venom Blade"
	}
	return "Unknown"
}

Status :: struct {
	kind:             Status_Kind,
	potency:          i32,
	remaining_pulses: i32,
}

Status_Set :: struct {
	items: [MAX_STATUSES_PER_ENTITY]Status,
	count: int,
}

status_index :: proc(statuses: ^Status_Set, kind: Status_Kind) -> (int, bool) {
	if statuses == nil || !status_kind_is_valid(kind) ||
	   statuses.count < 0 || statuses.count > MAX_STATUSES_PER_ENTITY {
		return 0, false
	}
	for index in 0..<statuses.count {
		if statuses.items[index].kind == kind {
			return index, true
		}
	}
	return 0, false
}

@(private = "file")
status_set_for_entity :: proc(room: ^Room, entity: Entity_Ref) -> (^Status_Set, bool) {
	if room == nil || room.player == nil {
		return nil, false
	}
	switch entity.kind {
	case .Player:
		if entity.id == 0 {
			return &room.player.statuses, true
		}
	case .Enemy:
		index, found := enemy_index_by_id(room, entity.id)
		if found {
			return &room.enemies[index].statuses, true
		}
	case .Trap, .Object, .System:
	}
	return nil, false
}

status_for_entity :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> (^Status, bool) {
	statuses, found := status_set_for_entity(room, entity)
	if !found {
		return nil, false
	}
	index, has_status := status_index(statuses, kind)
	if !has_status {
		return nil, false
	}
	return &statuses.items[index], true
}

can_apply_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> bool {
	statuses, found := status_set_for_entity(room, entity)
	if !found || !status_kind_is_valid(kind) ||
	   statuses.count < 0 || statuses.count > MAX_STATUSES_PER_ENTITY {
		return false
	}
	// Rallentamento holds an enemy's intents; the player has none to hold.
	if kind == .Slow && entity.kind == .Player {
		return false
	}
	// The player's charges load his own blows: no enemy carries one.
	if status_kind_is_player_charge(kind) && entity.kind != .Player {
		return false
	}
	// The Pinball's ball carries none (pinball.odin).
	if entity.kind == .Enemy && enemy_is_pinball(room, entity.id) {
		return false
	}
	_, already_present := status_index(statuses, kind)
	return already_present || statuses.count < MAX_STATUSES_PER_ENTITY
}

apply_status :: proc(
	room: ^Room,
	entity: Entity_Ref,
	kind: Status_Kind,
	potency, duration: i32,
) -> (applied, created: bool) {
	stacks := status_kind_stacks(kind)
	if potency <= 0 || (duration <= 0 && !stacks) || !can_apply_status(room, entity, kind) {
		return false, false
	}
	statuses, found := status_set_for_entity(room, entity)
	assert(found)
	if index, already_present := status_index(statuses, kind); already_present {
		status := &statuses.items[index]
		switch kind {
		// A new Dado del Destino loads its bumps back to its charges, never above.
		case .Thorns, .Afterimage, .Stagger, .Survey, .Fate:
			status.potency = max(status.potency, potency)
		case .Shield, .Poison, .Burn, .Slow, .Deflect, .Arrows, .Venom_Blade:
			available := max(i32)-status.potency
			status.potency += min(potency, available)
		}
		if !stacks { status.remaining_pulses = max(status.remaining_pulses, duration) }
		return true, false
	}

	statuses.items[statuses.count] = {
		kind = kind,
		potency = potency,
		remaining_pulses = 0 if stacks else duration,
	}
	statuses.count += 1
	return true, true
}

remove_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> (removed: Status, ok: bool) {
	statuses, found := status_set_for_entity(room, entity)
	if !found {
		return {}, false
	}
	index, has_status := status_index(statuses, kind)
	if !has_status {
		return {}, false
	}

	removed = statuses.items[index]
	for current in index..<statuses.count-1 {
		statuses.items[current] = statuses.items[current+1]
	}
	statuses.count -= 1
	statuses.items[statuses.count] = {}
	return removed, true
}

@(private)
clear_statuses :: proc(statuses: ^Status_Set) {
	if statuses != nil {
		statuses^ = {}
	}
}
