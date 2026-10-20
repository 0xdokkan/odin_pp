package integration
import application "../application"
import devtools "../devtools"
import run_session "../run"
import "core:testing"
import host "../engine/host"
import game "../game"

@(test)
test_host_cli_minigame_and_capture_preserve_explicit_seed :: proc(t: ^testing.T) {
	for argument in ([2]string{"--minigame=fps", "--smoke-minigame=fps"}) {
		_, rest := application.split_launch_arguments([]string{argument, "--seed=7"})
		options := application.DEFAULT_RUNTIME_OPTIONS
		application.roguelike_parse_arguments(&options, rest[:])
		delete(rest)
		first := application.launcher_cli_minigame_config(options)
		// Time/randomness in the interactive menu must not alter a CLI fixture.
		menu := application.launcher_create(options)
		for _ in 0..<3 { application.launcher_minigame_config(menu) }
		second := application.launcher_cli_minigame_config(options)
		testing.expect_value(t, first, host.Minigame_Config{seed = 7})
		testing.expect_value(t, second, first)
		free(menu)
	}
}

@(test)
test_host_preserves_direct_m9_and_dice_lab_commands_without_profile_writes :: proc(t: ^testing.T) {
	for argument in ([?]string{"--engine-lab", "--ring-lab", "--fps-lab", "--smoke-m9-view", "--dice-set-lab", "--smoke-dice-set"}) {
		options := application.DEFAULT_RUNTIME_OPTIONS
		application.roguelike_parse_arguments(&options, []string{argument})
		testing.expect(t, application.roguelike_requires_direct_start(&options), argument)
		rs := run_session.roguelike_session_new(options.gameplay)
		testing.expect(t, devtools.configure(rs, options.tools), argument)
		testing.expect(t, !run_session.roguelike_profile_enabled(rs), argument)
		run_session.roguelike_destroy(rs)
	}
	// Composition can restrict a caller's settings, never re-enable them.
	settings := run_session.DEFAULT_OPTIONS
	settings.persist_profile, settings.procedural_rooms = false, false
	rs := run_session.roguelike_session_new(settings)
	testing.expect(t, devtools.configure(rs, {}))
	testing.expect(t, !run_session.roguelike_profile_enabled(rs) && !rs.options.procedural_rooms)
	run_session.roguelike_destroy(rs)
	launch, rest := application.split_launch_arguments([]string{"--minigame=fps", "--seed=7"})
	defer delete(rest)
	testing.expect_value(t, launch.minigame, "fps")
	testing.expect_value(t, len(rest), 1)
	testing.expect_value(t, rest[0], "--seed=7")
}

@(test)
test_headless_startup_preserves_fresh_room_clock_and_static_fixture :: proc(t: ^testing.T) {
	options := application.DEFAULT_RUNTIME_OPTIONS
	application.roguelike_parse_arguments(&options, []string{"--smoke-playtest"})
	rs := run_session.roguelike_session_new(options.gameplay)
	defer run_session.roguelike_destroy(rs)
	testing.expect(t, devtools.configure(rs, options.tools))
	testing.expect(t, !run_session.roguelike_profile_enabled(rs))
	// The original headless path starts its decisions immediately after room
	// creation, before the interactive clock/telegraph reconfiguration.
	testing.expect_value(t, run_session.roguelike_prepare(rs, false), run_session.Session_Start.Ready)
	testing.expect(t, !rs.procedural_rooms && !rs.run_state.relic_rewards_enabled)
	testing.expect(t, !rs.attached && !rs.player_activities.save_enabled)
	testing.expect_value(t, rs.run_state.player.tactical.beat_age, f32(99))
	testing.expect_value(t, rs.run_state.player.tactical.remaining, f32(options.tactical.timer_seconds))
	testing.expect(t, game.validate_enemy_intents(&rs.room))
}
