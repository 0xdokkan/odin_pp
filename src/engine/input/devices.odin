package input

import rl "vendor:raylib"

MAX_GAMEPADS :: 4

Gamepad_Snapshot :: struct {
	available: bool,
	buttons, pressed, released: [rl.GamepadButton]bool,
	axes: [rl.GamepadAxis]f32,
}

// Immutable for one host frame. Edges come from the native frame, while
// action maps retain their own held/repeat history and focus resume gates.
Device_Snapshot :: struct {
	focused: bool,
	keys_down, keys_pressed, keys_released: #sparse[rl.KeyboardKey]bool,
	buttons_down, buttons_pressed, buttons_released: [rl.MouseButton]bool,
	mouse_position, mouse_motion: [2]f32,
	wheel: f32,
	gamepads: [MAX_GAMEPADS]Gamepad_Snapshot,
}

// Called once at the start of a native frame, before any scene owns input.
capture_devices :: proc() -> Device_Snapshot {
	s: Device_Snapshot
	s.focused = rl.IsWindowFocused()
	for key in rl.KeyboardKey {
		s.keys_down[key] = rl.IsKeyDown(key)
		s.keys_pressed[key] = rl.IsKeyPressed(key)
		s.keys_released[key] = rl.IsKeyReleased(key)
	}
	for button in rl.MouseButton {
		s.buttons_down[button] = rl.IsMouseButtonDown(button)
		s.buttons_pressed[button] = rl.IsMouseButtonPressed(button)
		s.buttons_released[button] = rl.IsMouseButtonReleased(button)
	}
	position, delta := rl.GetMousePosition(), rl.GetMouseDelta()
	s.mouse_position, s.mouse_motion = {position.x, position.y}, {delta.x, delta.y}
	s.wheel = rl.GetMouseWheelMove()
	for &pad, index in s.gamepads {
		pad.available = rl.IsGamepadAvailable(i32(index))
		if !pad.available { continue }
		for button in rl.GamepadButton {
			pad.buttons[button] = rl.IsGamepadButtonDown(i32(index), button)
			pad.pressed[button] = rl.IsGamepadButtonPressed(i32(index), button)
			pad.released[button] = rl.IsGamepadButtonReleased(i32(index), button)
		}
		for axis in rl.GamepadAxis { pad.axes[axis] = rl.GetGamepadAxisMovement(i32(index), axis) }
	}
	return s
}

key_down :: proc(s: ^Device_Snapshot, key: rl.KeyboardKey) -> bool {
	return s != nil && s.keys_down[key]
}
key_pressed :: proc(s: ^Device_Snapshot, key: rl.KeyboardKey) -> bool {
	return s != nil && s.keys_pressed[key]
}
key_released :: proc(s: ^Device_Snapshot, key: rl.KeyboardKey) -> bool {
	return s != nil && s.keys_released[key]
}
mouse_down :: proc(s: ^Device_Snapshot, button: rl.MouseButton) -> bool {
	return s != nil && s.buttons_down[button]
}
mouse_pressed :: proc(s: ^Device_Snapshot, button: rl.MouseButton) -> bool {
	return s != nil && s.buttons_pressed[button]
}
mouse_released :: proc(s: ^Device_Snapshot, button: rl.MouseButton) -> bool {
	return s != nil && s.buttons_released[button]
}
mouse_delta :: proc(s: ^Device_Snapshot) -> [2]f32 {
	return s.mouse_motion if s != nil else [2]f32{}
}
mouse_wheel :: proc(s: ^Device_Snapshot) -> f32 {
	return s.wheel if s != nil else 0
}
