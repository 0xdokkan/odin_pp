package game

import grid "../engine/grid"

// BENVENUTI A NAPOLI (docs/piano-napoli.md). Played, the card rolls a d4
// (whatever its upgrade: the die is fixed) and the face picks one of four
// effects:
//
//   1 Bastone: the player's own back seen from close behind, the ace of clubs
//     in hand, on the grid: NAPOLI_CLUB_SECONDS world seconds (+2 an upgrade;
//     the tick adds NAPOLI_CLUB_CRITICAL_SECONDS); blows from above of
//     NAPOLI_CLUB_DAMAGE (+1 an upgrade) that stagger for NAPOLI_CLUB_STAGGER_BEATS;
//   2 Tavolata: a grandpa sets a table down by the player; a step into it eats
//     and cures half his most health (+2 an upgrade);
//   3 Borsellino: the grandpa brings a purse, NAPOLI_PURSE_GOLD (+2 an upgrade);
//   4 Nonno: the player is the grandpa for NAPOLI_NONNO_SECONDS, free on the
//     board, the club on the left button, NAPOLI_NONNO_HEALTH of his own
//     (+5 an upgrade; the tick adds NAPOLI_NONNO_CRITICAL_HEALTH), Q to cure
//     both once, E for the gold once.
//
// Fase 0 of the plan: the card, its die and the four branches, each saying
// which it is (Napoli_Begun). The effect keeps the face in `charges` (1-4), the
// face's number in `amount` (the club's seconds, the cure, the gold, the
// grandpa's health) and the card's upgrade level in `duration`, for the numbers
// a face has besides (the club's damage).
//
// Fase 1, the grandpa's visit (the user's choices): the world stands still
// while he comes (the cue is a cinematic one, render/napoli.odin) and:
//   - 2 brings a table (Grid_Object_Kind.Napoli_Table) to the free cell next to
//     the player farthest from the nearest foe; nothing walks through it, nothing
//     sees or shoots through it, nothing strikes it. One table at a time: a new
//     one takes the old one's place. A step of the player's into it sits him down
//     (Napoli_Feast) for NAPOLI_FEAST_SECONDS world seconds, his body busy (no
//     step, card or dodge; no defence: he takes the blows), the cure coming in
//     two halves on the two world beats he sits through; a blow never stops the
//     meal. Then the table is cleared (Napoli_Table_Cleared). It lasts till it is
//     eaten or the combat ends. With no free cell round him the grandpa feeds him
//     where he stands: the whole cure at once.
//   - 3 brings a purse: the gold at once (Gold_Gained).
//
// Fase 2: 1 opens the view of the club (First_Person_Weapon.Club,
// first_person_club.odin), the board's camera behind his back.
// Fase 4: 4 turns him into the grandpa (First_Person_Weapon.Nonno, napoli_nonno.odin).

NAPOLI_DIE_SIDES :: i32(4)
NAPOLI_CLUB_SECONDS :: i32(30)
NAPOLI_CLUB_SECONDS_PER_UPGRADE :: i32(2)
NAPOLI_CLUB_CRITICAL_SECONDS :: i32(3)
NAPOLI_CLUB_DAMAGE :: i32(8)
NAPOLI_CLUB_DAMAGE_PER_UPGRADE :: i32(1)
NAPOLI_CLUB_STAGGER_BEATS :: i32(2)
NAPOLI_TABLE_HEAL_PER_UPGRADE :: i32(2)
NAPOLI_PURSE_GOLD :: i32(15)
NAPOLI_PURSE_GOLD_PER_UPGRADE :: i32(2)
NAPOLI_NONNO_SECONDS :: i32(60)
NAPOLI_NONNO_HEALTH :: i32(30)
NAPOLI_NONNO_HEALTH_PER_UPGRADE :: i32(5)
NAPOLI_NONNO_CRITICAL_HEALTH :: i32(10)

Napoli_Face :: enum {
	Club,
	Table,
	Purse,
	Nonno,
}

// The face a d4 shows (1-4) as the effect it picks.
napoli_for_face :: proc(face: i32) -> Napoli_Face {
	return Napoli_Face(clamp(face, 1, 4)-1)
}

// What the HUD and the dice panel call it.
napoli_face_name :: proc(face: Napoli_Face) -> string {
	switch face {
	case .Club: return "BASTONE"
	case .Table: return "TAVOLATA"
	case .Purse: return "BORSELLINO"
	case .Nonno: return "NONNO"
	}
	return ""
}

// The face's number at an upgrade level, before the tick: the club's seconds,
// the table's cure (half of `most_health`, rounded up), the purse's gold, the
// grandpa's health. The grandpa's minute never grows.
napoli_face_amount :: proc(face: Napoli_Face, upgrade_level, most_health: i32) -> i32 {
	level := max(upgrade_level, 0)
	switch face {
	case .Club: return NAPOLI_CLUB_SECONDS+NAPOLI_CLUB_SECONDS_PER_UPGRADE*level
	case .Table: return max((most_health+1)/2, 1)+NAPOLI_TABLE_HEAL_PER_UPGRADE*level
	case .Purse: return NAPOLI_PURSE_GOLD+NAPOLI_PURSE_GOLD_PER_UPGRADE*level
	case .Nonno: return NAPOLI_NONNO_HEALTH+NAPOLI_NONNO_HEALTH_PER_UPGRADE*level
	}
	return 0
}

// The club's blow at the card's upgrade level (Fasi 2 and 4).
napoli_club_damage :: proc(level: i32) -> i32 {
	return NAPOLI_CLUB_DAMAGE+NAPOLI_CLUB_DAMAGE_PER_UPGRADE*max(level, 0)
}


@(private)
napoli_effect :: proc(face: Napoli_Face, amount, level: i32) -> Effect {
	return {kind = .Napoli, target = PLAYER_ENTITY, amount = amount, charges = i32(face)+1, duration = level, card_definition = .Napoli}
}

// Never behind the player's eyes (cards are shut there anyway) nor on a
// dinosaur's back: two of its faces open a view of their own.
napoli_can_begin :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && !room.first_person.active && !room.ride.active &&
	       tactical_can_begin_first_person(room, .Club)
}

// The face picked, said, then done: the club's view behind his back (Fase 2),
// the grandpa's table or purse (Fase 1), the grandpa himself (Fase 4).
@(private)
begin_napoli :: proc(room: ^Room, effect: Effect, report: ^Action_Report) -> bool {
	if report == nil || effect.amount <= 0 || effect.charges < 1 || effect.charges > 4 || !napoli_can_begin(room) { return false }
	at := room.player.position
	record_report_event(report, {kind = .Napoli_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = effect.amount, duration = effect.charges, card_definition = .Napoli})
	#partial switch napoli_for_face(effect.charges) {
	case .Club:
		// The view's own cue paces the camera's flight behind his back.
		began := tactical_begin_first_person(room, f32(effect.amount), .Club)
		assert(began)
		first_person_club_begin(room, napoli_club_damage(effect.duration))
		record_report_event(report, {kind = .First_Person_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY,
			from_position = at, to_position = at, duration = effect.amount, card_definition = .Napoli})
	case .Nonno:
		// A minute as the grandpa, his health the face's number (napoli_nonno.odin).
		began := tactical_begin_first_person(room, f32(NAPOLI_NONNO_SECONDS), .Nonno)
		assert(began)
		napoli_nonno_begin(room, effect.amount, napoli_face_amount(.Purse, effect.duration, 0), napoli_club_damage(effect.duration))
		record_report_event(report, {kind = .First_Person_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY,
			from_position = at, to_position = at, duration = NAPOLI_NONNO_SECONDS, card_definition = .Napoli})
	case .Table: napoli_set_table(room, effect.amount, report)
	case .Purse:
		room.player.gold += effect.amount
		report.gold_gained += effect.amount
		record_report_event(report, {kind = .Gold_Gained, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
			amount = effect.amount, card_definition = .Napoli})
	}
	return true
}

NAPOLI_FEAST_SECONDS :: f32(2)
NAPOLI_FEAST_BEATS :: i32(2)

// The cell the grandpa sets the table on: of the eight round the player, one
// he can step into from where he stands (same floor, no wall, cover, foe,
// object, trap or exit, no height between), the farthest from the nearest foe;
// in a tie, north, east, south, west, then the corners.
napoli_table_cell :: proc(room: ^Room) -> (cell: grid.Position, ok: bool) {
	if room == nil || room.player == nil { return }
	ways := [8]grid.Position{{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
		{x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}}
	from := room.player.position
	best := -1
	for way in ways {
		at := grid.offset(from, way.x, way.y)
		if !napoli_table_fits(room, from, at) { continue }
		// Squared distance to the nearest foe in play (none: every cell ties).
		nearest := max(int)
		for enemy in room.enemies {
			if enemy_is_out_of_play(room, enemy.id) || enemy.position.layer != at.layer { continue }
			dx, dy := enemy.position.x-at.x, enemy.position.y-at.y
			nearest = min(nearest, dx*dx+dy*dy)
		}
		if nearest > best { best, cell, ok = nearest, at, true }
	}
	return
}

@(private = "file")
napoli_table_fits :: proc(room: ^Room, from, at: grid.Position) -> bool {
	if len(room.objects) >= MAX_GRID_OBJECTS_PER_ROOM || room.next_object_id == 0 || room.next_object_id == max(u32) ||
	   at.layer != from.layer || !base_cell_is_walkable(room, at) || cell_blocks_movement(room, at) || at == room.exit_position ||
	   step_height_blocked(room, from, at) { return false }
	if _, occupied := object_index_at(room, at); occupied { return false }
	if _, trapped := trap_index_at(room, at); trapped { return false }
	if _, occupied := enemy_index_at(room, at); occupied { return false }
	return !pinball_covers_cell(room, at)
}

// The table in the room, if one stands.
napoli_table_index :: proc(room: ^Room) -> (index: int, found: bool) {
	if room == nil { return }
	for object, i in room.objects { if object.kind == .Napoli_Table { return i, true } }
	return
}

// Whether the player sits at the table, eating: its `life` is the beats of the
// meal left.
napoli_seated :: proc(room: ^Room) -> bool {
	index, found := napoli_table_index(room)
	return found && room.objects[index].life > 0 && room.phase == .Combat
}

// The cure the player gets on the world beat that leaves `left` beats of the
// meal: the first half (rounded up), then the rest.
napoli_feast_bite :: proc(cure, left: i32) -> i32 {
	first := (cure+1)/2
	return first if left > 0 else cure-first
}

@(private = "file")
napoli_heal :: proc(room: ^Room, amount: i32, log: ^Event_Log) {
	before := room.player.health
	room.player.health = min(room.player.stats.max_health, before+max(amount, 0))
	at := room.player.position
	record_event(log, {kind = .Healed, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = room.player.health-before, card_definition = .Napoli})
}

// Face 2: the table set down (the old one cleared first), its cure kept in
// `power`; with no cell for it, the whole cure at once.
@(private = "file")
napoli_set_table :: proc(room: ^Room, cure: i32, report: ^Action_Report) {
	if old, found := napoli_table_index(room); found {
		object := room.objects[old]
		record_report_event(report, {kind = .Napoli_Table_Cleared, source = PLAYER_ENTITY, target = object_entity(object.id),
			object_kind = .Napoli_Table, from_position = object.position, to_position = object.position, card_definition = .Napoli})
		remove_grid_object(room, old)
	}
	cell, placed := napoli_table_cell(room)
	if !placed {
		napoli_heal(room, cure, &report.events)
		return
	}
	object := Grid_Object{id = room.next_object_id, kind = .Napoli_Table, position = cell, power = cure}
	room.next_object_id += 1
	append(&room.objects, object)
	record_report_event(report, {kind = .Object_Spawned, source = PLAYER_ENTITY, target = object_entity(object.id),
		object_kind = .Napoli_Table, from_position = cell, to_position = cell, amount = cure, card_definition = .Napoli})
}

// A step of the player's into the table at `cell` sits him down: his body is
// busy NAPOLI_FEAST_SECONDS world seconds and the meal lasts NAPOLI_FEAST_BEATS
// beats (napoli_beat). Not the table there: not handled.
napoli_try_feast :: proc(room: ^Room, cell: grid.Position) -> (result: Action_Result, handled: bool) {
	if room == nil || room.player == nil || room.phase != .Combat { return }
	index, found := napoli_table_index(room)
	if !found || room.objects[index].position != cell || room.objects[index].life > 0 { return }
	if !tactical_allows_action(room) { return .Invalid_Phase, true }
	clear_event_log(room.recent_events)
	table := &room.objects[index]
	table.life = NAPOLI_FEAST_BEATS
	record_event(room.recent_events, {kind = .Napoli_Feast, source = PLAYER_ENTITY, target = object_entity(table.id), object_kind = .Napoli_Table,
		from_position = room.player.position, to_position = cell, amount = table.power, duration = NAPOLI_FEAST_BEATS, card_definition = .Napoli})
	switch finish_player_combat_command(room, 0) {
	case .Player_Defeated: return .Player_Defeated, true
	case .Combat_Ended: return .Combat_Ended, true
	case .Combat_Continues:
	}
	tactical_spend_action_time(room, NAPOLI_FEAST_SECONDS)
	return .Used_Ability, true
}

// One world beat of the meal: a half of the cure; with the last one the table
// is cleared.
napoli_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || room.phase != .Combat { return }
	index, found := napoli_table_index(room)
	if !found || room.objects[index].life <= 0 { return }
	table := &room.objects[index]
	table.life -= 1
	napoli_heal(room, napoli_feast_bite(table.power, table.life), &pulse.events)
	if table.life > 0 { return }
	record_event(&pulse.events, {kind = .Napoli_Table_Cleared, source = PLAYER_ENTITY, target = object_entity(table.id),
		object_kind = .Napoli_Table, from_position = table.position, to_position = table.position, card_definition = .Napoli})
	remove_grid_object(room, index)
}

// The combat over: no table outlives it.
napoli_end_combat :: proc(room: ^Room) {
	if room == nil { return }
	for i := len(room.objects)-1; i >= 0; i -= 1 {
		if room.objects[i].kind == .Napoli_Table { remove_grid_object(room, i) }
	}
}

// The card played: its d4 rolls (shown as any dice card's roll, before the
// face's effect) and the face picks the effect, its number from the card's
// level and the player's most health.
@(private)
resolve_napoli_card :: proc(room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action) -> (report: Action_Report) {
	if compiled == nil || instance.definition_id != .Napoli || compiled.kind != .Card || compiled.source != PLAYER_ENTITY ||
	   compiled.target != target || compiled.effect_count != 1 || compiled.effects[0].kind != .Napoli { return }
	action := compiled^
	staged_dice := room.player.dice
	roll, rolled := roll_card_dice(&staged_dice, instance)
	if !rolled { return }
	face := napoli_for_face(roll.total)
	action.effects[0] = napoli_effect(face, napoli_face_amount(face, instance.upgrade_level, room.player.stats.max_health), instance.upgrade_level)
	tactical_critical_scale(room, &action)
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	room.player.dice = staged_dice
	record_report_event(&report, spell_dice_event(instance, origin, origin, PLAYER_ENTITY, roll))
	merge_spell_hit_report(&report, &hit)
	return
}
