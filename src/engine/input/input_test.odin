package input

import "core:testing"
import rl "vendor:raylib"

@(private = "file")
Test_Action :: enum {
	Left,
	Right,
	Up,
	Down,
	Jump,
}

@(private = "file")
held :: proc(actions: bit_set[Test_Action]) -> Sample(Test_Action) {
	s := Sample(Test_Action){down = actions}
	for a in actions {
		s.value[a] = 1
	}
	return s
}

@(test)
test_advance_reports_edges_once :: proc(t: ^testing.T) {
	s: State(Test_Action)
	advance(&s, held({.Jump}), 0.016)
	testing.expect(t, .Jump in s.pressed && .Jump in s.down && .Jump not_in s.released)
	advance(&s, held({.Jump}), 0.016)
	testing.expect(t, .Jump not_in s.pressed && .Jump in s.down)
	testing.expect(t, s.held_time[.Jump] > 0.03)
	advance(&s, held({}), 0.016)
	testing.expect(t, .Jump in s.released && .Jump not_in s.down)
	testing.expect_value(t, s.held_time[.Jump], f32(0))
	testing.expect(t, released(&s, Test_Action.Jump))
}

@(test)
test_vector_clamps_diagonals :: proc(t: ^testing.T) {
	s: State(Test_Action)
	advance(&s, held({.Right, .Down}), 0)
	v := vector(&s, Test_Action.Left, Test_Action.Right, Test_Action.Up, Test_Action.Down)
	testing.expect(t, abs(v.x*v.x+v.y*v.y-1) < 1e-3)
	testing.expect(t, v.x > 0 && v.y > 0)
	advance(&s, held({.Left, .Right}), 0)
	testing.expect_value(t, axis(&s, Test_Action.Left, Test_Action.Right), f32(0))
}

@(test)
test_bind_fills_slots_and_rebind_replaces :: proc(t: ^testing.T) {
	m := make_map(Test_Action)
	for _ in 0..<MAX_BINDINGS {
		testing.expect(t, bind(&m, Test_Action.Jump, key(.SPACE)))
	}
	testing.expect(t, !bind(&m, Test_Action.Jump, key(.W)))
	testing.expect(t, rebind(&m, Test_Action.Jump, 1, pad(.RIGHT_FACE_DOWN)))
	testing.expect_value(t, m.bindings[.Jump][1].kind, Binding_Kind.Gamepad_Button)
	testing.expect(t, !rebind(&m, Test_Action.Jump, MAX_BINDINGS, key(.W)))
	unbind_all(&m, Test_Action.Jump)
	testing.expect_value(t, m.bindings[.Jump][0].kind, Binding_Kind.None)
}

@(test)
test_deadzone_rescales_to_full_range :: proc(t: ^testing.T) {
	testing.expect_value(t, apply_deadzone(0.1, 0.2), f32(0))
	testing.expect_value(t, apply_deadzone(1, 0.2), f32(1))
	testing.expect(t, abs(apply_deadzone(0.6, 0.2)-0.5) < 1e-5)
}

@(test)
test_names_are_readable :: proc(t: ^testing.T) {
	testing.expect_value(t, binding_name(key(.SPACE)), "Spazio")
	testing.expect_value(t, binding_name(mouse(rl.MouseButton.LEFT)), "Mouse SX")
	testing.expect_value(t, binding_name(Binding{}), "-")
}

@(test)
test_resume_gate_keeps_movement_but_never_replays_menu_edges :: proc(t: ^testing.T) {
	s: State(Test_Action)
	gate: Resume_Gate(Test_Action)
	testing.expect(t, advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{}))
	testing.expect(t, s.pressed == {} && s.released == {})
	testing.expect(t, .Jump in s.down && .Right in s.down)
	testing.expect_value(t, axis(&s, Test_Action.Left, Test_Action.Right), f32(1))
	testing.expect(t, !advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{}))
	testing.expect(t, s.pressed == {})
	advance_resumable(&s, &gate, held({.Right}), 0.016, bit_set[Test_Action]{})
	advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{})
	testing.expect(t, .Jump in s.pressed)
	suspend(&s, &gate)
	testing.expect_value(t, s, State(Test_Action){})
	testing.expect(t, !gate.active && gate.blocked == {})
	testing.expect(t, advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{}))
	testing.expect(t, s.pressed == {})
}

@(test)
test_resume_gate_suppresses_held_fire_until_release :: proc(t: ^testing.T) {
	s: State(Test_Action)
	gate: Resume_Gate(Test_Action)
	for _ in 0..<4 {
		advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{.Jump})
		testing.expect(t, .Jump not_in s.down && .Jump not_in s.pressed)
		testing.expect_value(t, s.value[.Jump], f32(0))
		testing.expect_value(t, s.held_time[.Jump], f32(0))
		testing.expect(t, .Right in s.down)
	}
	advance_resumable(&s, &gate, held({.Right}), 0.016, bit_set[Test_Action]{.Jump})
	testing.expect(t, s.released == {} && gate.blocked == {})
	advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{.Jump})
	testing.expect(t, .Jump in s.pressed && .Jump in s.down)
	advance_resumable(&s, &gate, held({.Right, .Jump}), 0.016, bit_set[Test_Action]{.Jump})
	testing.expect(t, .Jump not_in s.pressed && .Jump in s.down)
}
