package run

import "core:testing"
import input "../engine/input"
import game "../game"
import level "../level"

@(private)
expedition_input_fixture :: proc() -> ^Expedition_Session {
	e := new(Expedition_Session)
	e.rs = new(Roguelike_Session)
	e.site = -1
	e.rs.room = {phase = .Combat, player = &e.rs.run_state.player}
	e.rs.run_state.player.position = {x = 4, y = 4, layer = 1}
	e.rs.run_state.player.health = 19
	e.rs.run_state.player.tactical.cast_remaining = 0.4
	e.rs.run_state.player.tactical.clock_fraction = 0.25
	e.world.clock = 12.5
	return e
}

@(private)
expedition_input_fixture_destroy :: proc(e: ^Expedition_Session) {
	free(e.rs)
	free(e)
}

@(test)
test_expedition_panels_drop_buffered_command_from_keyboard_and_hud :: proc(t: ^testing.T) {
	for entry in 0..<6 {
		e := expedition_input_fixture()
		rs := e.rs
		rs.card_interaction = {selected_card_id = 2, dragged_card_id = 2}
		queued := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
		_, emitted := route_gameplay_command(&rs.gameplay_buffer, &rs.room, true, queued, true, 1.0/60)
		testing.expect(t, !emitted && rs.gameplay_buffer.has_pending)
		player_before, clock_before := rs.run_state.player, e.world.clock
		devices: input.Device_Snapshot
		if entry == 0 { devices.keys_pressed[.TAB] = true }
		if entry == 1 { devices.keys_pressed[.Z] = true }
		if entry == 2 { devices.keys_pressed[.U] = true }
		expedition_panel_input(e, &devices, entry == 3, entry == 4)
		if entry == 5 { expedition_set_inventory_open(e, true) } // The backpack HUD button.
		testing.expect(t, expedition_gameplay_input_blocked(e))
		testing.expect(t, rs.gameplay_buffer == {}, "panel opening kept a queued gameplay command")
		testing.expect(t, rs.card_interaction == {}, "panel opening kept selected/dragged gameplay cards")
		if e.map_open { expedition_set_map_open(e, false) }
		if e.inventory_open { expedition_set_inventory_open(e, false) }
		// The real lane must be empty even after the cast finishes. No fresh
		// physical press should be needed to cancel the pre-panel command.
		_, emitted = route_gameplay_command(&rs.gameplay_buffer, &rs.room, false, {}, false, 1.0/60)
		testing.expect(t, !emitted, "closing a panel replayed the pre-panel command")
		testing.expect(t, rs.run_state.player == player_before, "input ownership changed gameplay state or clocks")
		testing.expect_value(t, e.world.clock, clock_before)
		expedition_input_fixture_destroy(e)
	}
}

@(test)
test_expedition_map_open_and_close_in_one_frame_owns_gameplay_input :: proc(t: ^testing.T) {
	for from_hud in 0..<2 {
		e := expedition_input_fixture()
		devices: input.Device_Snapshot
		devices.keys_pressed[.ESCAPE] = true
		if from_hud == 0 { devices.keys_pressed[.TAB] = true }
		expedition_panel_input(e, &devices, from_hud == 1, false)
		testing.expect(t, !e.map_open)
		// Tab+Esc, or a HUD click+Esc, both belong to the map even though
		// its final open flag is false. A simultaneous walk/card cannot pass.
		testing.expect(t, expedition_gameplay_input_blocked(e), "same-frame map close released its input to gameplay")
		expedition_input_fixture_destroy(e)
	}
}

@(test)
test_expedition_panel_consumes_held_mouse_without_losing_focus :: proc(t: ^testing.T) {
	e := expedition_input_fixture()
	defer expedition_input_fixture_destroy(e)
	e.rs.frame_input = {focused = true, left_pressed = true, left_down = true,
		left_released = true, right_pressed = true, right_down = true,
		middle_pressed = true, middle_down = true, mouse_motion = {7, -3}, wheel = 1,
		actions = {pressed = {.East, .Hand_1}, down = {.East}, released = {.West}}}
	expedition_set_inventory_open(e, true)
	controls := expedition_gameplay_controls(e)
	testing.expect(t, controls == Run_Input{focused = true}, "overlay kept held fire, look, or other gameplay controls")
	testing.expect(t, controls.focused, "modal filtering must not suspend the world's controller clock")
}

@(test)
test_expedition_panel_close_consumes_only_its_frame :: proc(t: ^testing.T) {
	for modal in 0..<6 {
		e := expedition_input_fixture()
		rs := e.rs
		if modal == 0 { expedition_set_inventory_open(e, true) }
		if modal == 1 { expedition_set_map_open(e, true) }
		if modal == 2 { e.site = 0 }
		if modal == 3 { e.world.reward_count = 3 }
		if modal == 4 { e.placing = true }
		if modal == 5 { rs.effect_window.open = true }
		// The closing frame begins with the modal owning input.
		expedition_begin_input_frame(e)
		e.inventory_open, e.map_open, e.placing, rs.effect_window.open = false, false, false, false
		e.site, e.world.reward_count = -1, 0
		testing.expect(t, expedition_gameplay_input_blocked(e), "closing frame leaked into gameplay")
		expedition_begin_input_frame(e)
		testing.expect(t, !expedition_gameplay_input_blocked(e), "modal swallowed input beyond its closing frame")
		fresh := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .West}
		ready, accepted := route_gameplay_command(&rs.gameplay_buffer, &rs.room, false, fresh, true, 1.0/60)
		testing.expect(t, accepted && ready.kind == .Move && ready.direction == .West)
		expedition_input_fixture_destroy(e)
	}
}

@(test)
test_expedition_end_encounter_drops_command_before_next_encounter :: proc(t: ^testing.T) {
	e := expedition_input_fixture()
	defer expedition_input_fixture_destroy(e)
	rs := e.rs
	player, created := game.create_player({max_health = 32, attack = 2, defense = 1})
	testing.expect(t, created)
	rs.run_state.player = player
	data, allocated := level.create(8, 8, {kind = .Floor})
	if !testing.expect(t, allocated) { return }
	rs.level_data = data
	defer level.destroy(&rs.level_data)
	rs.level_data.player_spawn, rs.level_data.has_player_spawn = {x = 4, y = 4}, true
	exit_set := level.set_tile(&rs.level_data, {x = 6, y = 6}, {kind = .Exit})
	if !testing.expect(t, exit_set) { return }
	room, built := game.create_room(&rs.level_data, &rs.run_state.player, {room_seed = 42})
	if !testing.expect(t, built) { return }
	rs.room = room
	defer game.destroy_room(&rs.room)
	configured := game.configure_expedition_combat(&rs.room)
	testing.expect(t, configured)
	began := game.begin_expedition_encounter(&rs.room)
	testing.expect(t, began)
	queued := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	_, emitted := route_gameplay_command(&rs.gameplay_buffer, &rs.room, true, queued, true, 1.0/60)
	testing.expect(t, !emitted && rs.gameplay_buffer.has_pending)
	// This is the real ending used when the last enemy dies, including
	// during a timed effect. Loot has no route_gameplay_command call.
	game.end_expedition_encounter(&rs.room)
	testing.expect_value(t, rs.room.phase, game.Room_Phase.Loot)
	expedition_drop_stale_gameplay_input(e)
	testing.expect(t, rs.gameplay_buffer == {}, "the cleared encounter kept its pending move")
	began = game.begin_expedition_encounter(&rs.room)
	testing.expect(t, began)
	_, emitted = route_gameplay_command(&rs.gameplay_buffer, &rs.room, false, {}, false, 1.0/60)
	testing.expect(t, !emitted, "the next encounter replayed the previous encounter's move")
}

@(test)
test_expedition_map_and_backpack_filter_keep_cast_clock_running :: proc(t: ^testing.T) {
	for map_panel in 0..<2 {
		e := expedition_input_fixture()
		rs := e.rs
		rs.room.player.tactical.config = game.EXPEDITION_TACTICAL_CONFIG
		rs.tactical_controller.was_focused = true
		rs.frame_input = {focused = true, left_down = true, actions = {pressed = {.East}, down = {.East}}}
		if map_panel == 0 { expedition_set_inventory_open(e, true) }
		else { expedition_set_map_open(e, true) }
		controls := expedition_gameplay_controls(e)
		controller_input := tactical_controller_input(&rs.tactical_controller, &rs.room, controls, {}, false)
		blocked := step_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer,
			&rs.card_interaction, &rs.gameplay_buffer, 0.1, true, controller_input)
		testing.expect(t, blocked && rs.tactical_controller.lane_busy)
		testing.expect(t, rs.room.player.tactical.cast_remaining > 0.29 && rs.room.player.tactical.cast_remaining < 0.31,
			"map/backpack input filtering stopped the existing cast clock")
		testing.expect(t, !controller_input.fire && controller_input.walk == [4]bool{})
		expedition_input_fixture_destroy(e)
	}
}

@(test)
test_expedition_panel_releases_first_person_pointer_and_latches_resume_click :: proc(t: ^testing.T) {
	e := expedition_input_fixture()
	defer expedition_input_fixture_destroy(e)
	rs := e.rs
	rs.room.first_person.active = true
	rs.room.first_person.weapon = .AK
	rs.room.first_person.trigger = true
	rs.tactical_controller = {was_focused = true, look_captured = true}
	rs.frame_input = {focused = true, left_down = true}
	before := rs.room.player^
	expedition_set_inventory_open(e,true)
	testing.expect(t,!rs.tactical_controller.look_captured && !rs.room.first_person.trigger)
	// The controller still runs beneath the backpack, but cannot take the
	// cursor back from the panel on its deferred capture pass.
	first_person_follow_capture(&rs.tactical_controller,&rs.room,true,{focused=true})
	testing.expect(t,!rs.tactical_controller.look_captured)
	expedition_set_inventory_open(e,false)
	first_person_follow_capture(&rs.tactical_controller,&rs.room,true,{focused=true})
	testing.expect(t,!rs.tactical_controller.look_captured,"closing click still belongs to the panel")
	expedition_begin_input_frame(e)
	first_person_follow_capture(&rs.tactical_controller,&rs.room,true,{focused=true})
	testing.expect(t,rs.tactical_controller.look_captured && rs.tactical_controller.fire_latched)
	buttons := first_person_buttons(&rs.tactical_controller,&rs.iso_renderer,&rs.room,{focused=true,fire=true})
	testing.expect(t,!buttons.left,"held closing click must not become a shot")
	first_person_buttons(&rs.tactical_controller,&rs.iso_renderer,&rs.room,{focused=true})
	buttons = first_person_buttons(&rs.tactical_controller,&rs.iso_renderer,&rs.room,{focused=true,fire=true})
	testing.expect(t,buttons.left,"a new click after release must still fire")
	testing.expect_value(t,rs.room.player^,before)
}
