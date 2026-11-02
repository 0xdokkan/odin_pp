package game

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
// Fase 0 of the plan: the card, its die and the four branches, each of which
// only says which it is (Napoli_Begun); the branches' own rules come with Fasi
// 1-4. The effect keeps the face in `charges` (1-4), the face's number in
// `amount` (the club's seconds, the cure, the gold, the grandpa's health) and
// the card's upgrade level in `duration`, for the numbers a face has besides
// (the club's damage).

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
	return room != nil && room.player != nil && room.phase == .Combat && !room.first_person.active && !room.ride.active
}

// The face picked, said (Fase 0: what each branch does comes with Fasi 1-4).
@(private)
begin_napoli :: proc(room: ^Room, effect: Effect, report: ^Action_Report) -> bool {
	if report == nil || effect.amount <= 0 || effect.charges < 1 || effect.charges > 4 || !napoli_can_begin(room) { return false }
	at := room.player.position
	record_report_event(report, {kind = .Napoli_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = effect.amount, duration = effect.charges, card_definition = .Napoli})
	return true
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
