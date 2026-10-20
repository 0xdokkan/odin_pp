package run

import game "../game"

resolve_demo_relic_choice :: proc(run: ^game.Run_State, room: ^game.Room, choice: int, skip: bool) -> bool {
	if run == nil || room == nil || !game.run_has_relic_choice(run) { return false }
	starter := run.relic_reward.origin == .Starter
	if starter && (room.player != &run.player || room.phase != .Combat || room.pulse_count != 0) { return false }
	resolved := false
	if choice >= 0 {
		resolved = game.choose_run_relic(run, choice)
	} else if skip {
		resolved = game.skip_run_relic(run)
	}
	if resolved && starter { game.apply_entry_relic(room) }
	return resolved
}
