package main

import "core:testing"
import game "game"
import render "render"

@(test)
test_terminal_room_transition_waits_for_the_presentation_timeline :: proc(t: ^testing.T) {
	// Exercise the actual scene boundaries in both modes, without a window:
	// pending action -> reward -> special node -> room -> restart.
	for tactical in ([2]bool{false, true}) {
		rs := roguelike_session_new()
		defer roguelike_destroy(rs)
		rest_node: game.Node_Id
		rs.run_state, rest_node = create_procedural_run_with_first_special(t, 0xC0FFEE, .Rest)
		rs.run_created = true
		rs.run_seed = rs.run_state.seed
		rs.procedural_rooms = true
		rs.options.tactical.enabled = tactical
		if tactical { testing.expect(t, configure_demo_tactical_player(&rs.run_state.player, rs.options.tactical)) }
		testing.expect(t, replace_current_demo_room(&rs.level_data, &rs.run_state, &rs.room, true))
		rs.room_created = true
		rs.iso_renderer = render.create(960, 540, &rs.level_data)
		rs.room.phase = .Complete
		rs.card_interaction.selected_card_id = 42
		rs.gameplay_buffer.chord.active = true
		testing.expect(t, room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer))
		events: game.Event_Log
		game.record_event(&events, {
			kind = .Moved, target = game.PLAYER_ENTITY,
			from_position = {x = 1, y = 1}, to_position = {x = 2, y = 1},
		})
		testing.expect(t, render.begin_renderer_event_timeline(
			&rs.iso_renderer, render.capture_room_presentation(&rs.room), &events,
		))
		testing.expect(t, !room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer))
		roguelike_finish_room(rs)
		testing.expect_value(t, rs.run_state.phase, game.Run_Phase.In_Room)
		testing.expect(t, rs.card_interaction.selected_card_id == 42 && rs.gameplay_buffer.chord.active)
		render.update_renderer_event_timeline(&rs.iso_renderer, render.PRESENTATION_PLAYER_MOVE_DURATION)
		testing.expect(t, room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer))
		roguelike_finish_room(rs)
		testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Reward)
		testing.expect(t, rs.reward_visible && !rs.route_visible && !rs.show_route_map)
		testing.expect(t, rs.card_interaction == {} && !rs.gameplay_buffer.chord.active)
		testing.expect(t, !room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer))

		testing.expect_value(t, game.skip_card_reward(&rs.run_state), game.Card_Reward_Result.Skipped)
		rs.show_route_map, rs.route_visible = true, true
		rs.card_interaction.selected_card_id = 42
		rs.gameplay_buffer.chord.active = true
		camera_before := rs.iso_renderer.camera
		room_seed := rs.room.pinball_random
		testing.expect(t, !roguelike_enter_node(rs, game.INVALID_NODE_ID))
		testing.expect(t, rs.show_route_map && rs.route_visible && rs.card_interaction.selected_card_id == 42)
		testing.expect(t, roguelike_enter_node(rs, rest_node))
		testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Rest)
		testing.expect(t, rs.special_visible && !rs.shop_visible && !rs.show_route_map && !rs.route_visible)
		testing.expect_value(t, rs.iso_renderer.camera, camera_before)
		testing.expect_value(t, rs.room.pinball_random, room_seed)
		testing.expect(t, rs.card_interaction == {} && !rs.gameplay_buffer.chord.active)
		testing.expect_value(t, game.leave_special_node(&rs.run_state), game.Special_Node_Result.Left)
		testing.expect_value(t, game.continue_special_node(&rs.run_state), game.Special_Node_Result.Continued)
		next := first_available_room_node(&rs.run_state)
		testing.expect(t, next != game.INVALID_NODE_ID && roguelike_enter_node(rs, next))
		testing.expect_value(t, rs.run_state.phase, game.Run_Phase.In_Room)
		testing.expect(t, !rs.special_visible && !rs.shop_visible)
		testing.expect(t, rs.room.player == &rs.run_state.player && rs.room.level_data == &rs.level_data)
		testing.expect_value(t, rs.run_state.player.position, rs.level_data.player_spawn)

		rs.run_state.player.m8_profile.ring_wins = 5
		rs.m8_session.character_open = true
		rs.card_interaction.selected_card_id = 42
		rs.gameplay_buffer.chord.active = true
		rs.tactical_controller.paused = true
		seed := rs.run_seed
		testing.expect(t, roguelike_restart(rs, nil))
		testing.expect_value(t, rs.run_seed, seed+1)
		testing.expect_value(t, rs.run_state.player.m8_profile.ring_wins, u32(5))
		testing.expect(t, !rs.m8_session.character_open && rs.card_interaction == {} && !rs.gameplay_buffer.chord.active)
		testing.expect(t, !tactical || !rs.tactical_controller.paused)
		testing.expect_value(t, rs.shop_render_state.hovered_offer_index, -1)
		testing.expect(t, rs.room.player == &rs.run_state.player && rs.room.level_data == &rs.level_data)
		testing.expect_value(t, rs.run_state.player.tactical.config.enabled, tactical)
		testing.expect(t, game.validate_run_state(&rs.run_state) && game.validate_enemy_intents(&rs.room))
	}
}

@(test)
test_route_map_toggle_rejects_terminal_rooms_and_busy_timelines :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := game.Room{player = &player, phase = .Combat}
	run := game.Run_State{phase = .In_Room}
	renderer: render.Renderer

	testing.expect(t, route_map_toggle_is_allowed(&run, &room, &renderer))
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	render.begin_renderer_event_timeline(
		&renderer,
		render.capture_room_presentation(&room),
		&events,
	)
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
	render.clear_event_animations(&renderer)

	room.phase = .Complete
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
	room.phase = .Defeat
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
}
