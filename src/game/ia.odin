package game

// IA (docs/piano-ia.md). Played, the card gives the player IA_SECONDS world
// seconds (+IA_SECONDS_PER_UPGRADE an upgrade; the tick adds
// IA_CRITICAL_SECONDS) in which the advisor shows him the best move. The
// seconds are the player's (Tactical_State.ia_remaining), never the room's:
// they run with the world (tactical_advance_clock), stand still while the
// world does (dice, scenes, the defence keys) and behind the eyes of a view
// (the user's choice), and the combat's end clears them. Played again while
// they run, they start again from the full (never added up).
//
// Fase 0 of the plan: the card and its seconds. The advisor that fills them
// comes from Fase 1 on (src/advisor/).

IA_SECONDS :: i32(30)
IA_SECONDS_PER_UPGRADE :: i32(3)
IA_CRITICAL_SECONDS :: i32(5)
IA_MAX_UPGRADE_LEVEL :: i32(5)

ia_effect :: proc(seconds: i32) -> Effect {
	return {kind = .IA, target = PLAYER_ENTITY, amount = seconds, card_definition = .IA}
}

ia_can_begin :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat
}

// The seconds start again from `seconds`; IA_Begun says how many.
begin_ia :: proc(room: ^Room, seconds: i32, report: ^Action_Report) -> bool {
	if report == nil || seconds <= 0 || !ia_can_begin(room) { return false }
	room.player.tactical.ia_remaining = f32(seconds)
	at := room.player.position
	record_report_event(report, {kind = .IA_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = seconds, card_definition = .IA})
	return true
}

// Whether the advisor is on now: its seconds run and no view is open.
ia_active :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && room.player.tactical.ia_remaining > 0 &&
	       !tactical_first_person_active(room)
}

// The world's `seconds` (tactical_advance_clock): the IA's own run with them,
// except behind the eyes of a view.
@(private)
tactical_ia_tick :: proc(room: ^Room, seconds: f32) {
	s := &room.player.tactical
	if s.ia_remaining <= 0 || tactical_first_person_active(room) { return }
	s.ia_remaining = max(f32(0), s.ia_remaining-seconds)
	if s.ia_remaining < 0.00001 { s.ia_remaining = 0 }
}
