package game

import grid "../engine/grid"

// Movimento Ombra. The player sinks into his shadow for TACTICAL_SHADOW_SECONDS
// of real time. Meanwhile the world is frozen: tactical_tick runs only the
// shadow's clock, so the window, the world beats (and with them the enemies,
// fuses, devices, statuses and energy), recovery and stun all keep their
// values. The player is intangible (apply_damage_effect) and can only move
// the shadow, one quick step at a time, under the player's own step rules from
// the shadow's cell. The shadow keeps its own beats, one at each whole second
// of its clock: two keys pressed on one of them step diagonally, as on the
// world's tick. When the time is up he rises at the shadow's cell (a
// teleport) and the world resumes exactly where it stopped.
TACTICAL_SHADOW_SECONDS :: f32(4)
TACTICAL_SHADOW_STEP_SECONDS :: f32(0.4)
// Beats at one, two and three seconds; the fourth second is the end.
TACTICAL_SHADOW_BEATS :: 3
// A beat stamped at the press stays claimable this long past its window, for
// the few frames a two-key diagonal waits for its second key.
TACTICAL_SHADOW_BEAT_GRACE :: f32(0.1)

tactical_shadow_active :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && room.player.tactical.phase == .Shadow
}

// No damage of any kind reaches the player while he is in his shadow.
tactical_player_intangible :: proc(room: ^Room) -> bool {
	return tactical_shadow_active(room)
}

// A shadow step's own short lockout: a press during it is dropped.
tactical_shadow_step_busy :: proc(room: ^Room) -> bool {
	return tactical_shadow_active(room) && room.player.tactical.shadow_step_remaining > 0
}

@(private)
tactical_reset_shadow :: proc(s: ^Tactical_State) {
	s.shadow_resume = .Decision
	s.shadow_remaining, s.shadow_duration, s.shadow_step_remaining = 0, 0, 0
	s.shadow_origin, s.shadow_position, s.shadow_from = {}, {}, {}
	s.shadow_beats_spent = {}
	s.shadow_steps = 0
}

@(private)
tactical_begin_shadow :: proc(room: ^Room, seconds: f32) -> bool {
	if !(seconds > 0) || !tactical_can_begin_shadow(room) { return false }
	s := &room.player.tactical
	resume := s.phase
	tactical_reset_shadow(s)
	s.shadow_resume = resume
	s.phase = .Shadow
	s.shadow_remaining, s.shadow_duration = seconds, seconds
	s.shadow_origin = room.player.position
	s.shadow_position, s.shadow_from = room.player.position, room.player.position
	return true
}

// Called by tactical_tick in place of the world clock.
@(private)
tactical_shadow_tick :: proc(room: ^Room, dt: f32) {
	if !tactical_shadow_active(room) || !(dt > 0) { return }
	s := &room.player.tactical
	s.shadow_remaining = max(f32(0), s.shadow_remaining-dt)
	if s.shadow_remaining < 0.00001 { s.shadow_remaining = 0 }
	s.shadow_step_remaining = max(f32(0), s.shadow_step_remaining-dt)
	if s.shadow_step_remaining < 0.00001 { s.shadow_step_remaining = 0 }
}

// Its time is up and its last step has landed: the caller commits the rise
// (tactical_end_shadow) as an explicit command, as it does a timeout.
tactical_shadow_due :: proc(room: ^Room) -> bool {
	return tactical_shadow_active(room) && room.player.tactical.shadow_remaining <= 0 &&
	       room.player.tactical.shadow_step_remaining <= 0
}

tactical_shadow_elapsed :: proc(s: ^Tactical_State) -> f32 {
	return max(f32(0), s.shadow_duration-s.shadow_remaining)
}

// The shadow beat a press made now lands on (1..3), or 0 off the beat.
tactical_shadow_beat_target :: proc(room: ^Room) -> u32 {
	if !tactical_shadow_active(room) { return 0 }
	s := &room.player.tactical
	elapsed := tactical_shadow_elapsed(s)
	nearest := int(elapsed+0.5)
	if nearest < 1 || nearest > TACTICAL_SHADOW_BEATS || nearest in s.shadow_beats_spent ||
	   abs(elapsed-f32(nearest)) > TACTICAL_BEAT_WINDOW { return 0 }
	return u32(nearest)
}

// Spends a shadow beat stamped at the press; true when the step is critical.
@(private = "file")
tactical_claim_shadow_beat :: proc(room: ^Room, beat: u32) -> bool {
	if !tactical_shadow_active(room) || beat == 0 || beat > TACTICAL_SHADOW_BEATS { return false }
	s := &room.player.tactical
	elapsed := tactical_shadow_elapsed(s)
	if int(beat) in s.shadow_beats_spent || elapsed < f32(beat)-TACTICAL_BEAT_WINDOW ||
	   elapsed > f32(beat)+TACTICAL_BEAT_WINDOW+TACTICAL_SHADOW_BEAT_GRACE { return false }
	s.shadow_beats_spent += {int(beat)}
	return true
}

// Where the player's eyes are: the shadow's cell while it walks.
tactical_view_origin :: proc(room: ^Room) -> grid.Position {
	if tactical_shadow_active(room) { return room.player.tactical.shadow_position }
	return room.player.position
}

// One step of the shadow: the player's own step rules from the shadow's cell
// (walls, solid objects and enemies block; an enemy is never bumped), no
// world, window or action time, then TACTICAL_SHADOW_STEP_SECONDS before the
// next. Two keys on a shadow beat step diagonally; otherwise the first key
// steps straight. A diagonal that cannot be taken gives its beat back. It
// records no event: the renderer draws the shadow from this state.
try_shadow_step :: proc(room: ^Room, direction: Move_Direction, diagonal: grid.Position = {}, beat: u32 = 0) -> Action_Result {
	if !tactical_shadow_active(room) { return .Invalid_Phase }
	s := &room.player.tactical
	if s.shadow_remaining <= 0 || s.shadow_step_remaining > 0 { return .Invalid_Phase }
	critical := abs(diagonal.x) == 1 && abs(diagonal.y) == 1 && tactical_claim_shadow_beat(room, beat)
	offset := diagonal if critical else direction_offset(direction)
	destination := add_position(s.shadow_position, offset)
	query := query_movement_from(room, PLAYER_ENTITY, s.shadow_position, destination)
	if !movement_query_is_clear(&query) {
		if critical { s.shadow_beats_spent -= {int(beat)} }
		return .Blocked
	}
	clear_event_log(room.recent_events)
	s.shadow_from, s.shadow_position = s.shadow_position, destination
	s.shadow_step_remaining = TACTICAL_SHADOW_STEP_SECONDS
	s.shadow_steps += 1
	s.facing = direction
	if critical { s.facing = .North if offset.y < 0 else .South }
	return .Moved
}

// The rise: the player comes out at the shadow's cell and the world resumes
// exactly where it stopped. Intangibility ends first, so the landing is an
// ordinary teleport through the shared movement resolver (a trap or a fire
// under it bites, as on any landing); loot in the magnet's reach is taken.
tactical_end_shadow :: proc(room: ^Room) -> bool {
	if !tactical_shadow_due(room) { return false }
	s := &room.player.tactical
	clear_event_log(room.recent_events)
	origin, landing := room.player.position, s.shadow_position
	s.phase = s.shadow_resume
	tactical_reset_shadow(s)
	if landing != origin {
		action := make_action(.Move, PLAYER_ENTITY, cell_target(landing), .Walkable_Cell)
		added := add_effect(&action, move_effect(PLAYER_ENTITY, landing, .Teleport))
		assert(added)
		report := resolve_action(room, &action)
		if report.accepted { append_event_log(room.recent_events, &report.events) }
	}
	record_event(room.recent_events, {
		kind = .Shadow_Emerged, source = PLAYER_ENTITY, target = PLAYER_ENTITY,
		from_position = origin, to_position = room.player.position,
	})
	finish_player_combat_command(room, 0, acted = false)
	return true
}
