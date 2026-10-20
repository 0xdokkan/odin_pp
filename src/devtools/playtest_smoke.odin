package devtools
import run_session "../run"

import combatdebug "../combatdebug"
import game "../game"

// Count policy decisions separately from the world's observed continuations.
// Finish the final action's elapsed time too: a report must not call a timed
// action complete while its enemies and timer have never advanced.
run_headless_playtest_decisions :: proc(room: ^game.Room, session: ^combatdebug.Playtest_Session) -> bool {
	policy: combatdebug.Max_Distance_Policy_State
	decisions := 0
	for _ in 0..<10000 {
		if room.phase != .Combat { return decisions > 0 }
		command := run_session.Gameplay_Command{origin_phase = .Combat}
		if room.qte.kind != .None { command.kind = .QTE_Fail }
		else if room.tactical_pulse.pending { command.kind = .Continue_Pulse }
		else if room.player.tactical.phase == .Decision && room.player.tactical.remaining <= 0 { command.kind = .Timeout }
		else if !game.tactical_allows_action(room) {
			// The current game charges ordinary actions in real time. Recovery
			// and stun use that same clock; QTE and each beat above stay explicit.
			game.tactical_tick(room, 0.25, true, false)
			continue
		}
		if command.kind != .None {
			if !run_session.execute_observed_gameplay_command(room, command, session).committed { return false }
			continue
		}
		if decisions == 20 { return true }
		decision := combatdebug.choose_max_distance_command(room, &policy)
		if !decision.valid { return false }
		command.kind = .Wait
		if decision.kind == .Move {
			command.kind = .Move
			command.direction = decision.direction
		}
		position_before := room.player.position
		if !run_session.execute_observed_gameplay_command(room, command, session).committed { return false }
		decisions += 1
		if command.kind == .Move && room.player.position != position_before {
			policy.has_last_direction = true
			policy.last_direction = command.direction
		}
	}
	return false
}

run_headless_playtest_smoke :: proc(
	run: ^game.Run_State,
	room: ^game.Room,
	run_seed: u64,
	output_path: string = "",
) -> bool {
	if run == nil || room == nil || room.player == nil {
		return false
	}
	session: combatdebug.Playtest_Session
	defer combatdebug.destroy_playtest_session(&session)
	if !run_session.begin_playtest_run(&session, run_seed, run, room) || !run_headless_playtest_decisions(room, &session) {
		return false
	}

	if session.room_active && !combatdebug.finish_playtest_room(&session, room) {
		return false
	}
	outcome := run_session.playtest_outcome_for_state(run, room)
	if !combatdebug.finish_playtest_session(&session, outcome) {
		return false
	}
	path := output_path if len(output_path) > 0 else "odin_pp_playtest_smoke.json"
	return combatdebug.write_playtest_report(&session, path)
}
