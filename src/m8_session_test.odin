package main

import "core:fmt"
import "core:os"
import "core:testing"
import game "game"
import level "level"
import render "render"
import view "view"

m8_test_button_center :: proc(renderer: ^render.Renderer, control: render.M8_Control) -> view.Vec2 {
	b := render.m8_control_bounds(renderer, control)
	return {b.x+b.width/2, b.y+b.height/2}
}

@(test)
test_m8_mouse_buttons_commit_equipment_and_activation_once :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	spawns := [?]game.Enemy_Spawn{{position = {5,3}, health = 30, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled = true
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	controller := Tactical_Controller{was_focused = true}
	testing.expect(t, game.collect_weapon(&player, .Iron_Cleaver, 4))
	equip := m8_test_button_center(renderer, .Equip)
	for flags in ([3][3]bool{{false,true,true},{true,false,true},{true,true,false}}) {
		_, accepted := m8_pointer_gameplay_command(&room, renderer, equip, flags[0], flags[1], flags[2])
		testing.expect(t, !accepted, "outside, held, or blocked input cannot dispatch")
	}
	command, accepted := m8_pointer_gameplay_command(&room, renderer, equip, true, true, true)
	testing.expect(t, accepted && command.kind == .Equip)
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, command))
	testing.expect_value(t, player.equipment.weapon.id, game.Weapon_Id.Iron_Cleaver)
	testing.expect_value(t, player.tactical.remaining, f32(19))
	step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true, {focused = true})
	testing.expect(t, game.deploy_board_device(&room, .Shock_Floor, {2,2}, 1, 3, &room.recent_events))
	activate := m8_test_button_center(renderer, .Activate)
	command, accepted = m8_pointer_gameplay_command(&room, renderer, activate, true, true, true)
	testing.expect(t, accepted && command.kind == .Activate)
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, command))
	testing.expect(t, room.objects[0].device_armed)
	testing.expect_value(t, player.tactical.remaining, f32(18))
	_, repeated := m8_pointer_gameplay_command(&room, renderer, activate, true, false, true)
	testing.expect(t, !repeated)
}

@(test)
test_m8_mouse_navigation_closes_modals_without_click_through :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	room, built := game.create_room(&data, &player, {})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled = true
	session: M8_Session
	controller: Tactical_Controller
	cards := Card_Interaction_State{selected_card_id = 42}
	buffer: Buffered_Gameplay_Command
	input := M8_Session_Input{focused = true, inside = true, pressed = true, mouse = m8_test_button_center(renderer, .Character)}
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
	testing.expect(t, session.character_open && cards.selected_card_id == 0)
	close := render.m8_modal_control_bounds(renderer, .Close_Character)
	input.mouse = {close.x+close.width/2, close.y+close.height/2}
	input.pressed = false
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
	testing.expect(t, session.character_open, "hovering or holding cannot close a modal")
	input.pressed = true
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
	testing.expect(t, !session.character_open, "closing still consumes this frame's click")
	input.mouse = m8_test_button_center(renderer, .Ring)
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
	testing.expect(t, session.ring_open)
	health := player.health
	leave := render.m8_modal_control_bounds(renderer, .Leave_Ring)
	input.mouse = {leave.x+leave.width/2, leave.y+leave.height/2}
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
	testing.expect(t, !session.ring_open && session.ring.phase == .Lost && session.ring.settled)
	testing.expect_value(t, player.health, health)
	testing.expect(t, room.ring_challenge_attempted)
	input.mouse = m8_test_button_center(renderer, .Ring)
	testing.expect(t, !step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, input))
}

@(test)
test_m8_profile_round_trip_rejects_corruption_and_preserves_file :: proc(t: ^testing.T) {
	temp_dir, temp_error := os.temp_directory(context.temp_allocator)
	testing.expect(t, temp_error == nil)
	path, join_error := os.join_path({temp_dir, "odin-pp-m8-profile-regression.json"}, context.temp_allocator)
	testing.expect(t, join_error == nil)
	defer os.remove(path)
	defer os.remove(fmt.tprintf("%s.tmp", path))
	testing.expect(t, save_m8_profile(path, {ring_wins = 3}))
	profile, loaded := load_m8_profile(path)
	testing.expect(t, loaded)
	testing.expect_value(t, profile.ring_wins, u32(3))
	testing.expect(t, game.m8_card_unlocked(.Storm_Crown, &profile))
	for malformed in ([3]string{`{"version":99,"progress":{"ring_wins":3}}`, `broken`, `{"version":1,"progress":{"ring_wins":1000001}}`}) {
		testing.expect(t, os.write_entire_file(path, malformed) == nil)
		_, accepted := load_m8_profile(path)
		testing.expect(t, !accepted)
		data, error := os.read_entire_file(path, context.allocator)
		testing.expect(t, error == nil && string(data) == malformed)
		delete(data)
	}
}
