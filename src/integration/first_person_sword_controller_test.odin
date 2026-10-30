package integration

import run_session "../run"
import "core:math"
import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// FIRST PERSON FENCER through the controller (run/first_person_input.odin, Fase
// 4 passo 3): the mouse moves the blade, not the view; Q and E turn the view a
// quarter; the right button held is the guard, Ctrl pressed the grapple (once
// a press); W steps the way the view looks (the lane's, as with the AK).
@(test)
test_first_person_sword_through_the_controller :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_first_person_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	room.player.tactical.facing = .East
	testing.expect(t, game.tactical_begin_first_person(&room, 30, .Sword))
	view := &renderer.tactical.first_person
	view.engaged, view.amount, view.yaw = true, 1, 0
	s := &room.first_person.sword
	for _ in 0..<3 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	testing.expect(t, controller.look_captured)
	// The mouse to the right: the point moves right, the view stays.
	tip := s.tip
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {look = {60, 0}})
	testing.expectf(t, s.tip.x > tip.x+0.05 && abs(s.tip.y-tip.y) < 1e-4, "the point at %v from %v", s.tip, tip)
	testing.expect_value(t, view.yaw, f32(0))
	// Q: a quarter to the left (north); E back; Q again.
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {diagonals = {true, false, false, false}})
	testing.expect_value(t, s.facing, game.Move_Direction.North)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {diagonals = {false, true, false, false}})
	testing.expect_value(t, s.facing, game.Move_Direction.East)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {diagonals = {true, false, false, false}})
	testing.expect_value(t, s.facing, game.Move_Direction.North)
	// The right button held: the guard up.
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {fire_right = true})
	testing.expect(t, s.guard)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	testing.expect(t, !s.guard)
	// Ctrl held two frames: one grapple, the foe three cells north pulled in front.
	foe := &room.enemies[0]
	testing.expect(t, foe.position == {x = 5, y = 1})
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {ctrl = true})
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, {ctrl = true})
	testing.expect(t, s.grapples == 1 && foe.position == {x = 5, y = 3}, "the grapple did not pull, or pulled twice")
	// The steps are the lane's, as with the AK: W, D, S, A turned with the view.
	cmd, stepped := run_session.first_person_lane_command({true, false, false, false}, false, false, game.first_person_key_directions(math.PI/2))
	testing.expect(t, stepped && cmd.kind == .Move && cmd.direction == .South)
}
