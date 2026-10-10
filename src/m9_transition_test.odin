package main

import "core:testing"
import engine "engine"
import fight "fight"
import game "game"
import level "level"
import render "render"
import view "view"

M9_Transition_Fixture :: struct {
	data: ^level.Level,
	player: ^game.Player,
	room: game.Room,
	renderer: ^render.Renderer,
	session: M8_Session,
	controller: Tactical_Controller,
	cards: Card_Interaction_State,
	buffer: Buffered_Gameplay_Command,
}

m9_transition_fixture :: proc(t: ^testing.T) -> ^M9_Transition_Fixture {
	f := new(M9_Transition_Fixture)
	f.data = new(level.Level)
	f.data^ = create_gameplay_command_test_level(t)
	f.player = new(game.Player)
	f.player^ = create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(f.player, game.DEFAULT_TACTICAL_CONFIG))
	ok: bool
	f.room, ok = game.create_room(f.data, f.player, {})
	testing.expect(t, ok)
	testing.expect_value(t, f.room.phase, game.Room_Phase.Loot)
	f.renderer = new(render.Renderer)
	f.renderer.canvas_width, f.renderer.canvas_height = 960, 540
	f.renderer.tactical.enabled = true
	f.controller.was_focused = true
	return f
}

destroy_m9_transition_fixture :: proc(f: ^M9_Transition_Fixture) {
	destroy_m9_session(&f.session.activity)
	render.destroy_renderer_world_playback(f.renderer)
	free(f.renderer)
	game.destroy_room(&f.room)
	level.destroy(f.data)
	free(f.data)
	free(f.player)
	free(f)
}

m9_transition_step :: proc(f: ^M9_Transition_Fixture, input: M8_Session_Input, dt: f32 = 0, available := true) -> bool {
	return step_m8_session(&f.session, &f.room, f.renderer, &f.controller,
		&f.cards, &f.buffer, available, dt, input)
}

m9_transition_enter :: proc(f: ^M9_Transition_Fixture, control: render.M8_Control) -> bool {
	return m9_transition_step(f, {focused = true, inside = true, pressed = true,
		mouse = m8_test_button_center(f.renderer, control)})
}

m9_transition_click :: proc(f: ^M9_Transition_Fixture, control: render.M9_Control) -> bool {
	bounds := render.m9_control_bounds(f.renderer, control)
	point := view.Vec2{bounds.x+bounds.width/2, bounds.y+bounds.height/2}
	selected := render.m9_control_at_point(f.renderer, m9_view(&f.session.activity), point)
	return m9_transition_step(f, {focused = true, inside = true, pressed = true,
		mouse = point, activity = {control = selected}})
}

@(test)
test_m9_ring_transition_suspends_board_and_resumes_only_its_input_owner :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	f.cards.selected_card_id = 42
	f.buffer = {occupied = true, command = {kind = .Move, origin_phase = .Loot, direction = .East}}
	before_player := f.player^
	before_pulse := f.room.pulse_count
	before_tactical := f.room.tactical_pulse
	before_dice := f.player.dice
	testing.expect(t, m9_transition_enter(f, .Ring))
	testing.expect_value(t, f.session.activity.mode, render.M9_Kind.Ring)
	testing.expect(t, !f.session.activity.practice && f.room.ring_challenge_attempted)
	testing.expect_value(t, f.cards.selected_card_id, u32(0))
	testing.expect(t, !f.buffer.occupied)
	position := f.session.activity.ring.fighters[0].position
	for _ in 0..<30 {
		testing.expect(t, m9_transition_step(f, {focused = true, activity = {ring = {move = {0,0,1}}}}, f32(engine.FIXED_DT)))
	}
	testing.expect(t, f.session.activity.ring.fighters[0].position.z > position.z+1)
	paused_ring := f.session.activity.ring
	testing.expect(t, m9_transition_step(f, {focused = false, activity = {ring = {jab = true}}}, 3))
	testing.expect(t, f.session.activity.paused)
	testing.expect_value(t, f.session.activity.ring, paused_ring)
	testing.expect_value(t, f.session.activity.pending, M9_Tick_Input{})
	// Becoming focused is not permission to spend the hidden elapsed time.
	testing.expect(t, m9_transition_step(f, {focused = true}, 3))
	testing.expect_value(t, f.session.activity.ring, paused_ring)
	testing.expect(t, m9_transition_click(f, .Pause))
	m9_transition_step(f, {focused = true, activity = {ring = {move = {0,0,1}}}}, f32(engine.FIXED_DT))
	testing.expect_value(t, f.session.activity.ring.ticks, paused_ring.ticks+1)
	paused_ring = f.session.activity.ring
	m9_transition_step(f, {focused = true, activity = {ring = {heavy = true}}}, 1, false)
	testing.expect(t, f.session.activity.paused)
	testing.expect_value(t, f.session.activity.ring, paused_ring)
	testing.expect_value(t, f.player^, before_player)
	testing.expect_value(t, f.player.dice, before_dice)
	testing.expect_value(t, f.room.pulse_count, before_pulse)
	testing.expect_value(t, f.room.tactical_pulse, before_tactical)
	testing.expect_value(t, f.room.phase, game.Room_Phase.Loot)
}

@(test)
test_m9_ring_victory_receipt_grants_once_and_close_has_no_click_through :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	before := f.player^
	testing.expect(t, m9_transition_enter(f, .Ring))
	// The fight package separately verifies a win using real movement/attacks;
	// this test checks the run handoff for a completed fight.
	f.session.activity.ring.result = .Won
	testing.expect(t, m9_transition_step(f, {focused = true}, 1))
	testing.expect(t, f.session.ring.settled && f.session.reward.won && f.session.reward.has_unlock)
	testing.expect_value(t, f.session.reward.unlocked, game.Card_Id.Titan_Grip)
	testing.expect_value(t, f.player.m8_profile.ring_wins, u32(1))
	testing.expect_value(t, f.player.deck.owned_count, before.deck.owned_count+1)
	testing.expect_value(t, f.player.health, before.health)
	testing.expect_value(t, f.player.dice, before.dice)
	after_reward := f.player^
	for _ in 0..<8 { testing.expect(t, m9_transition_step(f, {focused = true}, 1)) }
	testing.expect_value(t, f.player^, after_reward)
	testing.expect(t, m9_transition_click(f, .Leave))
	testing.expect_value(t, f.session.activity.mode, render.M9_Kind.None)
	testing.expect_value(t, f.player^, after_reward)
	// A held/repeated close at this location does not reopen or dispatch any
	// gameplay button, and an attempted room ring cannot award another win.
	testing.expect(t, !m9_transition_click(f, .Leave))
	testing.expect(t, !m9_transition_enter(f, .Ring))
	testing.expect_value(t, f.player^, after_reward)
	testing.expect_value(t, f.room.phase, game.Room_Phase.Loot)
	testing.expect_value(t, f.room.pulse_count, u64(0))
}

@(test)
test_m9_aborting_ring_consumes_attempt_without_run_damage_or_reward :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	before := f.player^
	testing.expect(t, m9_transition_enter(f, .Ring))
	f.session.activity.ring.fighters[0].health = 1
	testing.expect(t, m9_transition_click(f, .Leave))
	testing.expect(t, f.session.ring.settled && f.session.ring.phase == .Lost)
	testing.expect(t, !f.session.reward.won && !f.session.reward.has_unlock)
	testing.expect(t, f.room.ring_challenge_attempted)
	testing.expect_value(t, f.player^, before)
	testing.expect(t, !m9_transition_enter(f, .Ring))
	testing.expect(t, m9_transition_enter(f, .FPS), "An aborted ring must not lock other activities")
	testing.expect(t, m9_transition_click(f, .Leave))
	testing.expect_value(t, f.player^, before)
}

@(test)
test_m9_practice_modes_return_to_same_run_without_unlocking_cards :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	before := f.player^
	for entry in ([2]render.M8_Control{.FPS, .Workshop}) {
		testing.expect(t, m9_transition_enter(f, entry))
		testing.expect(t, f.session.activity.practice)
		if f.session.activity.paused { testing.expect(t, m9_transition_click(f, .Pause)) }
		for _ in 0..<90 {
			m9_transition_step(f, {focused = true, activity = {ring = {move = {0,0,1}}, fps = {move_right = 1}}}, f32(engine.FIXED_DT))
		}
		testing.expect(t, m9_transition_click(f, .Ring))
		testing.expect(t, f.session.activity.practice)
		f.session.activity.ring.result = .Won
		m9_transition_step(f, {focused = true}, 1)
		testing.expect(t, !f.session.reward.won && !f.session.ring.settled)
		testing.expect(t, m9_transition_click(f, .Leave))
		testing.expect_value(t, f.player^, before)
		testing.expect(t, !f.room.ring_challenge_attempted)
		testing.expect_value(t, f.room.phase, game.Room_Phase.Loot)
		testing.expect_value(t, f.room.pulse_count, u64(0))
	}
	testing.expect(t, m9_transition_enter(f, .Ring), "Practice must leave the real room challenge available")
}

@(test)
test_m9_workshop_level_change_preserves_character_collisions :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	testing.expect(t, m9_transition_enter(f, .Workshop))
	testing.expect(t, m9_transition_click(f, .Level))
	testing.expect_value(t, f.session.activity.level_index, 1)
	testing.expect_value(t, f.session.activity.ring.world.actor_count, 2)
	// Both selectable arena layouts have a clear lane here; the gallery's
	// authored spawns intentionally do not face each other along the X axis.
	f.session.activity.ring.fighters[0].position = {-1,0,1}
	f.session.activity.ring.fighters[1].position = {1,0,1}
	for &fighter in f.session.activity.ring.fighters { fighter.previous = fighter.position }
	fight.sync_fighters(&f.session.activity.ring)
	for _ in 0..<180 {
		m9_transition_step(f, {focused = true, activity = {ring = {move = {1,0,0}}}}, f32(engine.FIXED_DT))
	}
	player, opponent := f.session.activity.ring.fighters[0], f.session.activity.ring.fighters[1]
	testing.expect(t, player.position.x < opponent.position.x)
	testing.expect(t, engine.vec_length(engine.vec_sub(player.position, opponent.position)) >= 2*fight.BODY_RADIUS-0.001)
}

@(test)
test_m9_only_drawn_controls_are_clickable_in_run_practice_modes :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	testing.expect(t, m9_transition_enter(f, .FPS))
	for control in ([2]render.M9_Control{.Reset, .Level}) {
		testing.expect(t, !render.m9_control_enabled(m9_view(&f.session.activity), control))
		bounds := render.m9_control_bounds(f.renderer, control)
		center := view.Vec2{bounds.x+bounds.width/2, bounds.y+bounds.height/2}
		testing.expect_value(t, render.m9_control_at_point(f.renderer, m9_view(&f.session.activity), center), render.M9_Control.None)
	}
	for control in ([3]render.M9_Control{.Arena, .Ring, .FPS}) {
		testing.expect(t, render.m9_control_enabled(m9_view(&f.session.activity), control))
	}
}

@(test)
test_m9_activity_entry_obeys_the_existing_tactical_input_owner :: proc(t: ^testing.T) {
	f := m9_transition_fixture(t)
	defer destroy_m9_transition_fixture(f)
	for control in ([3]render.M8_Control{.Ring, .FPS, .Workshop}) {
		f.controller.hologram = true
		testing.expect(t, !m9_transition_enter(f, control))
		f.controller.hologram = false
		f.controller.paused = true
		testing.expect(t, !m9_transition_enter(f, control))
		f.controller.paused = false
		f.room.phase = .Combat
		testing.expect(t, !m9_transition_enter(f, control))
		f.room.phase = .Loot
		testing.expect_value(t, f.session.activity.mode, render.M9_Kind.None)
		testing.expect(t, !f.room.ring_challenge_attempted)
	}
}
