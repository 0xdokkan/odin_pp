package main

import "core:testing"
import game "game"
import host "engine/host"

@(test)
test_host_cli_minigame_and_capture_preserve_explicit_seed :: proc(t: ^testing.T) {
	for argument in ([2]string{"--minigame=fps", "--smoke-minigame=fps"}) {
		_, rest := split_launch_arguments([]string{argument, "--seed=7"})
		rs := roguelike_session_new()
		roguelike_parse_arguments(rs, rest[:])
		delete(rest)
		first := launcher_cli_minigame_config(rs.options)
		// Time/randomness in the interactive menu must not alter a CLI fixture.
		menu := launcher_create(rs.options)
		for _ in 0..<3 { launcher_minigame_config(menu) }
		second := launcher_cli_minigame_config(rs.options)
		testing.expect_value(t, first, host.Minigame_Config{seed = 7})
		testing.expect_value(t, second, first)
		free(menu)
		roguelike_destroy(rs)
	}
}

host_run_fixture :: proc(t: ^testing.T) -> ^Roguelike_Session {
	rs := roguelike_session_new()
	ok: bool
	rs.run_state, ok = game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, 0xC0FFEE)
	testing.expect(t, ok)
	rs.run_created = true
	rs.level_data = create_gameplay_command_test_level(t)
	rs.room, ok = game.create_room(&rs.level_data, &rs.run_state.player, {})
	testing.expect(t, ok)
	rs.room_created = true
	rs.run_state.phase = .In_Room
	node, found := game.current_run_node(&rs.run_state)
	testing.expect(t, found)
	node.kind = .Combat
	rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height = 960, 540
	rs.iso_renderer.tactical.enabled = true
	return rs
}

@(test)
test_host_preserves_direct_m9_and_dice_lab_commands_without_profile_writes :: proc(t: ^testing.T) {
	for argument in ([?]string{"--engine-lab", "--ring-lab", "--fps-lab", "--smoke-m9-view", "--dice-set-lab", "--smoke-dice-set"}) {
		rs := roguelike_session_new()
		roguelike_parse_arguments(rs, []string{argument})
		testing.expect(t, roguelike_requires_direct_start(rs), argument)
		testing.expect(t, !roguelike_profile_enabled(rs), argument)
		roguelike_destroy(rs)
	}
	launch, rest := split_launch_arguments([]string{"--minigame=fps", "--seed=7"})
	defer delete(rest)
	testing.expect_value(t, launch.minigame, "fps")
	testing.expect_value(t, len(rest), 1)
	testing.expect_value(t, rest[0], "--seed=7")
}

@(test)
test_host_suspension_clears_run_input_without_advancing_gameplay :: proc(t: ^testing.T) {
    rs := host_run_fixture(t)
    defer roguelike_destroy(rs)
    before := rs.run_state.player
    pulse := rs.room.pulse_count
    rs.card_interaction.selected_card_id=42
    rs.gameplay_buffer.occupied=true
    rs.iso_renderer.frame_clock_valid=true
    rs.iso_renderer.tactical.world_orbit.dragging=true
    rs.iso_renderer.tactical.hologram_orbit.dragging=true
    roguelike_suspend_input(rs)
    testing.expect(t,rs.card_interaction.selected_card_id==0 && !rs.gameplay_buffer.occupied)
    testing.expect(t,!rs.iso_renderer.frame_clock_valid && !rs.tactical_controller.was_focused)
    testing.expect(t,!rs.iso_renderer.tactical.world_orbit.dragging && !rs.iso_renderer.tactical.hologram_orbit.dragging)
    testing.expect_value(t,rs.run_state.player,before)
    testing.expect_value(t,rs.room.pulse_count,pulse)
}
