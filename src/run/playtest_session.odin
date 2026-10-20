package run

import "core:fmt"
import combatdebug "../combatdebug"
import game "../game"

begin_current_playtest_room :: proc(
	session: ^combatdebug.Playtest_Session,
	run: ^game.Run_State,
	room: ^game.Room,
) -> bool {
	if session == nil || run == nil || room == nil || room.phase != .Combat {
		return false
	}
	node, node_ok := game.current_run_node(run)
	if !node_ok {
		return false
	}
	metadata, metadata_ok := combatdebug.playtest_room_metadata(node)
	return metadata_ok && combatdebug.begin_playtest_room(session, metadata, room)
}

begin_playtest_run :: proc(
	session: ^combatdebug.Playtest_Session,
	run_seed: u64,
	run: ^game.Run_State,
	room: ^game.Room,
) -> bool {
	if !combatdebug.begin_playtest_session(session, run_seed) {
		return false
	}
	if begin_current_playtest_room(session, run, room) {
		return true
	}
	combatdebug.destroy_playtest_session(session)
	return false
}

playtest_outcome_for_state :: proc(
	run: ^game.Run_State,
	room: ^game.Room,
) -> combatdebug.Playtest_Run_Outcome {
	if run != nil && run.phase == .Victory {
		return .Victory
	}
	if (run != nil && run.phase == .Defeat) || (room != nil && room.phase == .Defeat) {
		return .Defeat
	}
	return .Abandoned
}

write_seed_playtest_report :: proc(
	session: ^combatdebug.Playtest_Session,
	run_seed: u64,
	output_path: string,
) -> bool {
	path_buffer: [96]u8
	base_path := output_path
	if len(base_path) == 0 {
		base_path = fmt.bprintf(path_buffer[:], "odin_pp_playtest_%d.json", run_seed)
	}
	path, written := combatdebug.write_unique_playtest_report(session, base_path)
	if written {
		fmt.printf("wrote %s\n", path)
		delete(path)
	}
	return written
}

finish_seed_playtest_report :: proc(
	session: ^combatdebug.Playtest_Session,
	run_seed: u64,
	output_path: string,
	outcome: combatdebug.Playtest_Run_Outcome,
	room: ^game.Room,
) -> bool {
	if session == nil {
		return false
	}
	if !session.finalized && !combatdebug.finish_playtest_session(session, outcome, room) {
		return false
	}
	return write_seed_playtest_report(session, run_seed, output_path)
}

