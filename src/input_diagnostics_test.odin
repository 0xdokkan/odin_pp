package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import game "game"
import level "level"
import render "render"

@(test)
test_input_snapshots_preserve_blocked_state_and_previous_capture :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odin_pp_input.*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil { return }
	defer delete(directory)
	defer os.remove(directory)
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	run := game.Run_State{seed = 98765, phase = .In_Room, player = create_gameplay_command_test_player(t)}
	testing.expect(t, game.configure_tactical(&run.player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {2, 1}, health = 8, attack = 1}}
	objects := [?]game.Grid_Object_Spawn{{kind = .Ice_Block, position = {1, 2}}}
	room, created := game.create_room(&data, &run.player, {enemies = enemies[:], objects = objects[:]})
	testing.expect(t, created)
	defer game.destroy_room(&room)
	run.player.tactical.phase = .Resolving
	room.tactical_pulse = {pending = true, started = true, count = 1}
	room.qte = {kind = .Defense, remaining = 0.7, enemy_id = room.enemies[0].id}
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Move, duration = 0.16, elapsed = 0.1}
	controller := Tactical_Controller{was_focused = true}
	cards := Card_Interaction_State{dragged_card_id = 32}
	buffer: Buffered_Gameplay_Command
	buffer.chord = {command = {kind = .Move, origin_phase = .Combat, direction = .East, beat = 1}, timer = BEAT_CHORD_SECONDS, active = true}
	frame := Input_Diagnostic_Frame{dt = 1.0/60.0, focused = true, wasd_down = {false, true, false, false}}
	before_player, before_qte, before_pulse := run.player, room.qte, room.tactical_pulse
	first, first_ok := write_input_diagnostic(&run, &room, renderer, &controller, &cards, &buffer, frame, directory)
	testing.expect(t, first_ok)
	if !first_ok { return }
	defer delete(first)
	defer os.remove(first)
	frame.dt = 0.25
	second, second_ok := write_input_diagnostic(&run, &room, renderer, &controller, &cards, &buffer, frame, directory)
	testing.expect(t, second_ok)
	if !second_ok { return }
	defer delete(second)
	defer os.remove(second)
	testing.expect_value(t, first, fmt.tprintf("%s/odin_pp_input_0.txt", directory))
	testing.expect_value(t, second, fmt.tprintf("%s/odin_pp_input_1.txt", directory))
	first_bytes, read_error := os.read_entire_file(first, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(first_bytes)
	report := string(first_bytes)
	testing.expect(t, len(report) < INPUT_DIAGNOSTIC_MAX_BYTES)
	for expected in ([?]string{"seed=98765", "phase=Resolving", "pulse_pending=true", "qte=Defense",
		"timeline_busy=true", "dragged=32", "chord_active=true", "object=Ice_Block", "movement_query=Actor_Blocker", "movement_query=Static_Blocker"}) {
		testing.expect(t, strings.contains(report, expected), expected)
	}
	testing.expect(t, !strings.contains(report, "frame_dt=0.250000000"), "the second capture must not overwrite the first")
	second_bytes, second_read_error := os.read_entire_file(second, context.allocator)
	testing.expect(t, second_read_error == nil)
	defer delete(second_bytes)
	testing.expect(t, strings.contains(string(second_bytes), "frame_dt=0.250000000"))
	testing.expect_value(t, run.player, before_player)
	testing.expect_value(t, room.qte, before_qte)
	testing.expect_value(t, room.tactical_pulse, before_pulse)
	testing.expect_value(t, cards.dragged_card_id, u32(32))
	testing.expect(t, buffer.chord.active)
}
