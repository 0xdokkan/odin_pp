package main

import "core:testing"
import game "game"
import host "engine/host"
import render "render"

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
test_host_challenge_cannot_overlap_input_owners_or_m9_buttons :: proc(t: ^testing.T) {
	rs := host_run_fixture(t)
	defer roguelike_destroy(rs)
	frame := host.Frame{focused = true, window_focused = true, visible = true}
	testing.expect(t, roguelike_challenge_available(rs, &frame))
	for gate in 0..<8 {
		switch gate {
		case 0: rs.tactical_controller.paused = true
		case 1: rs.tactical_controller.hologram = true
		case 2: frame.focused = false
		case 3: frame.window_focused = false
		case 4: rs.m8_modal = true
		case 5: rs.m8_session.character_open = true
		case 6: rs.m8_session.requested = .FPS
		case 7: rs.show_route_map = true
		}
		testing.expect(t, !roguelike_challenge_available(rs, &frame))
		rs.tactical_controller = {}
		frame.focused, frame.window_focused = true, true
		rs.m8_modal, rs.m8_session.character_open, rs.show_route_map = false, false, false
		rs.m8_session.requested = .None
	}
	challenge := roguelike_challenge_bounds(960)
	for control in ([?]render.M8_Control{.Character, .Ring, .FPS}) {
		button := render.m8_control_bounds(&rs.iso_renderer, control, &rs.room)
		testing.expect(t, challenge.y >= button.y+button.height || challenge.y+challenge.height <= button.y ||
			challenge.x >= button.x+button.width || challenge.x+challenge.width <= button.x)
	}
}

@(test)
test_host_challenge_accepts_only_its_result_once_and_preserves_run :: proc(t: ^testing.T) {
	rs := host_run_fixture(t)
	defer roguelike_destroy(rs)
	challenge, begun := game.begin_minigame_challenge(&rs.run_state, &rs.room, EXTRA_CHALLENGE_COUNT)
	testing.expect(t, begun)
	info, found := minigame_info(challenge.minigame)
	testing.expect(t, found)
	before := rs.run_state.player
	frame: host.Frame
	result := host.Result{minigame = info.id, outcome = .Won, stars = 3}
	roguelike_resume(rs, &frame, "unrelated-scene", result)
	testing.expect(t, rs.room.minigame_challenge_pending)
	testing.expect_value(t, rs.run_state.player, before)
	result.minigame = "wrong-result"
	roguelike_resume(rs, &frame, info.id, result)
	testing.expect(t, rs.room.minigame_challenge_pending)
	testing.expect_value(t, rs.run_state.player, before)
	result.minigame = info.id
	roguelike_resume(rs, &frame, info.id, result)
	before.gold += 18
	testing.expect(t, !rs.room.minigame_challenge_pending)
	testing.expect_value(t, rs.run_state.player, before)
	roguelike_resume(rs, &frame, info.id, result)
	testing.expect_value(t, rs.run_state.player, before)
}

@(test)
test_host_challenge_missing_result_abandons_without_reward :: proc(t: ^testing.T) {
	rs := host_run_fixture(t)
	defer roguelike_destroy(rs)
	challenge, begun := game.begin_minigame_challenge(&rs.run_state, &rs.room, EXTRA_CHALLENGE_COUNT)
	testing.expect(t, begun)
	info, _ := minigame_info(challenge.minigame)
	before := rs.run_state.player
	frame: host.Frame
	roguelike_resume(rs, &frame, info.id, nil)
	testing.expect(t, !rs.room.minigame_challenge_pending)
	testing.expect_value(t, rs.run_state.player, before)
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
