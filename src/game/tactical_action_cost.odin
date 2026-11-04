package game

// Valid actions charge time using the same prices shown by the hand and inspector.
// These are the first prices: the player's pace divides them in the game as
// it is played (tactical_player_pace).
TACTICAL_MOVE_SECONDS :: f32(0.8)
TACTICAL_ATTACK_SECONDS :: f32(1)
TACTICAL_DODGE_SECONDS :: f32(1)
TACTICAL_REFOCUS_SECONDS :: f32(2)
// One arrow of Feretro (shoot_player_arrow), like a bump.
TACTICAL_ARROW_SECONDS :: f32(1)

// The player's pace: his prices (a step, a blow, a dodge, a refocus, an arrow,
// a card's cast) are the first ones divided by it. Two since 2026-10-30 (the
// user's choice: twice as quick). The foes keep their own seconds.
TACTICAL_PLAYER_PACE :: f32(2)

// The divisor of the player's prices in this room. The game as it is played
// (timed actions: the run, the expedition, the lab) goes at his pace; the bare
// rules the regression probes are written against keep the first prices.
// Behind the eyes only the sword's and the bow's steps go at it (the user's
// choice): the AK's and the fists' keep theirs.
tactical_player_pace :: proc(room: ^Room, step := false) -> f32 {
	if room == nil || room.player == nil || !room.player.tactical.config.timed_actions { return 1 }
	if tactical_first_person_active(room) && !first_person_on_board(room) && !(step && (first_person_sword_active(room) || first_person_bow_active(room))) { return 1 }
	return TACTICAL_PLAYER_PACE
}

// A price as this room charges it.
tactical_paced_seconds :: proc(room: ^Room, seconds: f32, step := false) -> f32 {
	return seconds/tactical_player_pace(room, step)
}

// A card's cast at the player's pace (the user's choice, 2026-10-30: quick,
// a heavier card a little longer, never past CARD_CAST_MAX): from
// CARD_CAST_BASE, CARD_CAST_SLOPE more for each of its first seconds (one
// second 0.26, two 0.375, three 0.49, four 0.6). At the bare rules' pace its
// first seconds; a card of none, none.
CARD_CAST_BASE :: f32(0.15)
CARD_CAST_SLOPE :: f32(0.1125)
CARD_CAST_MAX :: f32(0.6)

tactical_card_cast_seconds :: proc(seconds, pace: f32) -> f32 {
	if seconds <= 0 { return 0 }
	if pace <= 1 { return seconds }
	return min(CARD_CAST_MAX, CARD_CAST_BASE+CARD_CAST_SLOPE*seconds)
}
