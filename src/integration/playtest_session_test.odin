package integration
import run_session "../run"
import devtools "../devtools"


import "core:testing"
import combatdebug "../combatdebug"
import game "../game"
import level "../level"

@(test)
test_headless_playtest_finishes_forty_timed_decisions_and_observes_the_world :: proc(t: ^testing.T) {
	// The normal window covers recovery; the one-second window also reaches
	// shrinking-window stuns. Neither may truncate the run at Action_Busy.
	for seconds in ([2]int{20, 1}) {
		run, created := game.create_run({max_health = 1000, attack = 2, defense = 1}, run_session.DEMO_RUN_CONFIG, 0xC0FFEE)
		testing.expect(t, created)
		defer game.destroy_run(&run)
		config := game.GAME_TACTICAL_CONFIG
		config.timer_seconds = seconds
		testing.expect(t, game.configure_tactical(&run.player, config))
		data := create_gameplay_command_test_level(t)
		defer level.destroy(&data)
		enemies := [?]game.Enemy_Spawn{{position = {x = 2, y = 1}, health = 1000, attack = 2}}
		room, built := game.create_room(&data, &run.player, {enemies = enemies[:]})
		testing.expect(t, built)
		defer game.destroy_room(&room)
		session: combatdebug.Playtest_Session
		defer combatdebug.destroy_playtest_session(&session)
		testing.expect(t, run_session.begin_playtest_run(&session, run.seed, &run, &room))
		// Start on an enemy deadline so the driver must answer a real defense
		// QTE before its evasive policy can move away from the announced hit.
		room.enemies[0].tactical_cooldown = 1
		game.tactical_tick(&room, 1, true, false)
		testing.expect(t, devtools.run_headless_playtest_decisions(&room, &session))
		// Forty at the player's pace: the world seconds twenty took at the first prices.
		testing.expect_value(t, run.player.tactical.metrics.decisions, u64(devtools.PLAYTEST_DECISIONS))
		testing.expect(t, room.pulse_count >= 20 && game.tactical_allows_action(&room))
		testing.expect(t, run.player.tactical.metrics.timeouts > 0)
		if seconds == 1 {
			testing.expect(t, run.player.tactical.stuns > 0)
		}
		testing.expect(t, run.player.tactical.metrics.qte_failures > 0)
		testing.expect(t, combatdebug.finish_playtest_session(&session, .Abandoned, &room))
		testing.expect(t, combatdebug.combat_metrics_integrity_complete(&session.aggregate))
		testing.expect_value(t, session.aggregate.pulses, room.pulse_count)
		testing.expect(t, session.aggregate.player_moves > 0 && session.aggregate.enemy_moves > 0)
		for record in session.commands {
			testing.expect(t, record.sample.committed && record.sample.complete)
		}
	}
}
