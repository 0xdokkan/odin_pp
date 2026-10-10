// Logical actions bound to keyboard, mouse and gamepad.
//
// Each game declares an enum of actions and an Action_Map that binds them.
// `sample` is the only procedure that reads raylib; `advance` turns samples
// into pressed/held/released edges and is pure, so gameplay input can be
// scripted in tests by feeding Samples directly.
//
// Query edges through the bit_sets (`.Jump in state.pressed`): implicit enum
// selectors resolve there, while the polymorphic helpers below need the
// action spelled out (`input.axis(&state, Action.Left, Action.Right)`).
package input

import rl "vendor:raylib"

MAX_BINDINGS :: 6

Binding_Kind :: enum u8 {
	None,
	Key,
	Mouse_Button,
	Gamepad_Button,
	Gamepad_Axis_Positive,
	Gamepad_Axis_Negative,
	Mouse_Wheel_Up,
	Mouse_Wheel_Down,
}

Binding :: struct {
	kind:   Binding_Kind,
	key:    rl.KeyboardKey,
	mouse:  rl.MouseButton,
	button: rl.GamepadButton,
	axis:   rl.GamepadAxis,
}

key :: proc "contextless" (k: rl.KeyboardKey) -> Binding {
	return Binding{kind = .Key, key = k}
}

mouse :: proc "contextless" (b: rl.MouseButton) -> Binding {
	return Binding{kind = .Mouse_Button, mouse = b}
}

pad :: proc "contextless" (b: rl.GamepadButton) -> Binding {
	return Binding{kind = .Gamepad_Button, button = b}
}

pad_axis :: proc "contextless" (a: rl.GamepadAxis, positive: bool) -> Binding {
	return Binding{kind = .Gamepad_Axis_Positive if positive else .Gamepad_Axis_Negative, axis = a}
}

wheel :: proc "contextless" (up: bool) -> Binding {
	return Binding{kind = .Mouse_Wheel_Up if up else .Mouse_Wheel_Down}
}

Action_Map :: struct($A: typeid) {
	bindings:      [A][MAX_BINDINGS]Binding,
	gamepad:       i32,
	axis_deadzone: f32,
	// Analog value above which an axis binding counts as "down".
	axis_press:    f32,
}

make_map :: proc($A: typeid) -> Action_Map(A) {
	return Action_Map(A){axis_deadzone = 0.2, axis_press = 0.5}
}

// Adds a binding in the first free slot; false when the action is full.
bind :: proc(m: ^Action_Map($A), action: A, binding: Binding) -> bool {
	for &slot in m.bindings[action] {
		if slot.kind == .None {
			slot = binding
			return true
		}
	}
	return false
}

bind_all :: proc(m: ^Action_Map($A), action: A, bindings: ..Binding) {
	for b in bindings {
		bind(m, action, b)
	}
}

unbind_all :: proc(m: ^Action_Map($A), action: A) {
	m.bindings[action] = {}
}

// Replaces the binding in one slot, used by rebinding menus.
rebind :: proc(m: ^Action_Map($A), action: A, slot: int, binding: Binding) -> bool {
	if slot < 0 || slot >= MAX_BINDINGS {
		return false
	}
	m.bindings[action][slot] = binding
	return true
}

// One frame of raw device state, already mapped to actions.
Sample :: struct($A: typeid) {
	down:  bit_set[A],
	value: [A]f32,
}

State :: struct($A: typeid) {
	down:      bit_set[A],
	pressed:   bit_set[A],
	released:  bit_set[A],
	value:     [A]f32,
	held_time: [A]f32,
}

// Reads the devices. Gamepad bindings are ignored when no pad is present.
sample :: proc(m: ^Action_Map($A)) -> Sample(A) {
	s: Sample(A)
	pad_ok := rl.IsGamepadAvailable(m.gamepad)
	wheel_move := rl.GetMouseWheelMove()
	for action in A {
		best: f32
		for b in m.bindings[action] {
			v: f32
			switch b.kind {
			case .None:
			case .Key:
				v = 1 if rl.IsKeyDown(b.key) else 0
			case .Mouse_Button:
				v = 1 if rl.IsMouseButtonDown(b.mouse) else 0
			case .Gamepad_Button:
				if pad_ok {
					v = 1 if rl.IsGamepadButtonDown(m.gamepad, b.button) else 0
				}
			case .Gamepad_Axis_Positive, .Gamepad_Axis_Negative:
				if pad_ok {
					raw := rl.GetGamepadAxisMovement(m.gamepad, b.axis)
					if b.kind == .Gamepad_Axis_Negative {
						raw = -raw
					}
					v = apply_deadzone(raw, m.axis_deadzone)
				}
			case .Mouse_Wheel_Up:
				v = 1 if wheel_move > 0 else 0
			case .Mouse_Wheel_Down:
				v = 1 if wheel_move < 0 else 0
			}
			best = max(best, v)
		}
		s.value[action] = best
		if best >= m.axis_press {
			s.down += {action}
		}
	}
	return s
}

apply_deadzone :: proc "contextless" (raw, deadzone: f32) -> f32 {
	if raw <= deadzone {
		return 0
	}
	return min((raw - deadzone) / (1 - deadzone), 1)
}

// Pure edge detection: pressed/released are relative to the previous state.
advance :: proc(s: ^State($A), sample: Sample(A), dt: f32) {
	s.pressed = sample.down - s.down
	s.released = s.down - sample.down
	s.down = sample.down
	s.value = sample.value
	for action in A {
		if action in s.down {
			s.held_time[action] += dt
		} else {
			s.held_time[action] = 0
		}
	}
}

poll :: proc(m: ^Action_Map($A), s: ^State(A), dt: f32) {
	advance(s, sample(m), dt)
}

// Forgets all device history. Use suspend/advance_resumable at menu or focus
// boundaries: resetting alone turns a still-held key into a fresh press.
reset :: proc(s: ^State($A)) {
	s^ = {}
}

// Shared menu/focus boundary for gameplay controls. The first active sample
// establishes a baseline without edges. Selected held actions (typically fire)
// remain suppressed until released; movement can resume immediately.
Resume_Gate :: struct($A: typeid) {
	active:  bool,
	blocked: bit_set[A],
}

suspend :: proc(s: ^State($A), gate: ^Resume_Gate(A)) {
	reset(s)
	gate^ = {}
}

// Returns true on the first sample after suspension, so mouse-look can also
// discard its capture delta. Fixed-step action queues remain the caller's job.
advance_resumable :: proc(s: ^State($A), gate: ^Resume_Gate(A), sample: Sample(A), dt: f32,
	block_held: bit_set[A]) -> bool {
	resumed := !gate.active
	if resumed {
		gate.active = true
		gate.blocked = sample.down & block_held
		s^ = State(A){down = sample.down, value = sample.value}
	} else {
		gate.blocked &= sample.down
		advance(s, sample, dt)
	}
	for action in gate.blocked {
		s.down -= {action}
		s.pressed -= {action}
		s.released -= {action}
		s.value[action] = 0
		s.held_time[action] = 0
	}
	return resumed
}

down :: proc(s: ^State($A), action: A) -> bool {
	return action in s.down
}

pressed :: proc(s: ^State($A), action: A) -> bool {
	return action in s.pressed
}

released :: proc(s: ^State($A), action: A) -> bool {
	return action in s.released
}

// -1..1 from a pair of opposing actions, honouring analog values.
axis :: proc(s: ^State($A), negative, positive: A) -> f32 {
	return clamp(s.value[positive]-s.value[negative], -1, 1)
}

// 2D direction from four actions; diagonal length is clamped to 1. y grows
// downward (screen convention), so `up` gives negative y.
vector :: proc(s: ^State($A), left, right, up, down: A) -> [2]f32 {
	v := [2]f32{axis(s, left, right), axis(s, up, down)}
	l2 := v.x*v.x + v.y*v.y
	if l2 > 1 {
		inv := 1 / sqrt_f32(l2)
		v *= inv
	}
	return v
}

@(private)
sqrt_f32 :: proc "contextless" (x: f32) -> f32 {
	// Newton iterations are enough for a unit-length clamp.
	if x <= 0 {
		return 0
	}
	r := x
	for _ in 0..<6 {
		r = 0.5 * (r + x/r)
	}
	return r
}

// Raw mouse motion in window pixels, for first-person look.
mouse_delta :: proc() -> [2]f32 {
	d := rl.GetMouseDelta()
	return {d.x, d.y}
}

// Hides and locks the cursor for mouse-look; false restores it.
capture_mouse :: proc(capture: bool) {
	if capture {
		rl.DisableCursor()
	} else {
		rl.EnableCursor()
	}
}

mouse_captured :: proc() -> bool {
	return rl.IsCursorHidden()
}

binding_name :: proc(b: Binding) -> string {
	switch b.kind {
	case .None:
		return "-"
	case .Key:
		return key_name(b.key)
	case .Mouse_Button:
		#partial switch b.mouse {
		case .LEFT:
			return "Mouse SX"
		case .RIGHT:
			return "Mouse DX"
		case .MIDDLE:
			return "Mouse centrale"
		}
		return "Mouse"
	case .Gamepad_Button:
		#partial switch b.button {
		case .RIGHT_FACE_DOWN:
			return "Pad A"
		case .RIGHT_FACE_RIGHT:
			return "Pad B"
		case .RIGHT_FACE_LEFT:
			return "Pad X"
		case .RIGHT_FACE_UP:
			return "Pad Y"
		case .MIDDLE_RIGHT:
			return "Pad Start"
		case .LEFT_TRIGGER_1:
			return "Pad LB"
		case .RIGHT_TRIGGER_1:
			return "Pad RB"
		case .LEFT_FACE_UP:
			return "Pad su"
		case .LEFT_FACE_DOWN:
			return "Pad giu"
		case .LEFT_FACE_LEFT:
			return "Pad sinistra"
		case .LEFT_FACE_RIGHT:
			return "Pad destra"
		}
		return "Pad"
	case .Gamepad_Axis_Positive, .Gamepad_Axis_Negative:
		return "Stick"
	case .Mouse_Wheel_Up:
		return "Rotella su"
	case .Mouse_Wheel_Down:
		return "Rotella giu"
	}
	return "?"
}

key_name :: proc(k: rl.KeyboardKey) -> string {
	#partial switch k {
	case .SPACE:
		return "Spazio"
	case .ENTER:
		return "Invio"
	case .ESCAPE:
		return "Esc"
	case .BACKSPACE:
		return "Backspace"
	case .TAB:
		return "Tab"
	case .LEFT_SHIFT, .RIGHT_SHIFT:
		return "Shift"
	case .LEFT_CONTROL, .RIGHT_CONTROL:
		return "Ctrl"
	case .LEFT_ALT, .RIGHT_ALT:
		return "Alt"
	case .UP:
		return "Su"
	case .DOWN:
		return "Giu"
	case .LEFT:
		return "Sinistra"
	case .RIGHT:
		return "Destra"
	case .A:
		return "A"
	case .B:
		return "B"
	case .C:
		return "C"
	case .D:
		return "D"
	case .E:
		return "E"
	case .F:
		return "F"
	case .G:
		return "G"
	case .H:
		return "H"
	case .I:
		return "I"
	case .J:
		return "J"
	case .K:
		return "K"
	case .L:
		return "L"
	case .M:
		return "M"
	case .N:
		return "N"
	case .O:
		return "O"
	case .P:
		return "P"
	case .Q:
		return "Q"
	case .R:
		return "R"
	case .S:
		return "S"
	case .T:
		return "T"
	case .U:
		return "U"
	case .V:
		return "V"
	case .W:
		return "W"
	case .X:
		return "X"
	case .Y:
		return "Y"
	case .Z:
		return "Z"
	case .ZERO:
		return "0"
	case .ONE:
		return "1"
	case .TWO:
		return "2"
	case .THREE:
		return "3"
	case .FOUR:
		return "4"
	case .FIVE:
		return "5"
	}
	return "Tasto"
}
