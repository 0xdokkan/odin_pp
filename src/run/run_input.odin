package run

import input "../engine/input"
import rl "vendor:raylib"
import view "../engine/view"

// Contextual run actions: the controller, menus and overlays decide which
// owner may use them. Other games retain their own action maps.
Run_Action :: enum {
	North, East, South, West,
	North_West, North_East, South_West, South_East,
	Dodge_Modifier, Arrow_Aim,
	Wait, Refocus, Pause, Map, Route_Map, Recenter, Cancel, Confirm, Inspect,
	Block, Parry, Deflect, Reactive_Dodge,
	Hand_1, Hand_2, Hand_3, Hand_4, Hand_5, Hand_6, Hand_7, Hand_8, Hand_9, Hand_10,
	Route_1, Route_2, Route_3,
	Skip, Previous_Page, Next_Page, Upgrade, Remove, Leave,
	Restart, Main_Menu, Animation_Speed, Diagnostics, Intent_Display, Clear_Lab, Lab_Arena,
	Debug_Thorns, Debug_Afterimage,
}

RUN_WALK_ACTIONS :: [4]Run_Action{.North, .East, .South, .West}
RUN_DIAGONAL_ACTIONS :: [4]Run_Action{.North_West, .North_East, .South_West, .South_East}
RUN_DEFENSE_ACTIONS :: [4]Run_Action{.Block, .Parry, .Deflect, .Reactive_Dodge}
RUN_HAND_ACTIONS :: [10]Run_Action{.Hand_1, .Hand_2, .Hand_3, .Hand_4, .Hand_5, .Hand_6, .Hand_7, .Hand_8, .Hand_9, .Hand_10}

default_run_actions :: proc() -> input.Action_Map(Run_Action) {
	m := input.make_map(Run_Action)
	bindings := [?]struct {action: Run_Action, key: rl.KeyboardKey}{
		{.North, .W}, {.East, .D}, {.South, .S}, {.West, .A},
		{.North_West, .Q}, {.North_East, .E}, {.South_West, .Z}, {.South_East, .C},
		{.Dodge_Modifier, .LEFT_SHIFT}, {.Dodge_Modifier, .RIGHT_SHIFT},
		{.Arrow_Aim, .LEFT_CONTROL}, {.Arrow_Aim, .RIGHT_CONTROL},
		{.Wait, .SPACE}, {.Refocus, .F}, {.Pause, .P}, {.Map, .TAB}, {.Route_Map, .M}, {.Recenter, .R},
		{.Cancel, .ESCAPE}, {.Confirm, .ENTER}, {.Inspect, .I},
		{.Block, .J}, {.Parry, .K}, {.Deflect, .L}, {.Reactive_Dodge, .E},
		{.Hand_1, .ONE}, {.Hand_2, .TWO}, {.Hand_3, .THREE}, {.Hand_4, .FOUR}, {.Hand_5, .FIVE},
		{.Hand_6, .SIX}, {.Hand_7, .SEVEN}, {.Hand_8, .EIGHT}, {.Hand_9, .NINE}, {.Hand_10, .ZERO},
		{.Route_1, .ONE}, {.Route_1, .KP_1}, {.Route_2, .TWO}, {.Route_2, .KP_2}, {.Route_3, .THREE}, {.Route_3, .KP_3},
		{.Skip, .S}, {.Previous_Page, .LEFT}, {.Next_Page, .RIGHT}, {.Upgrade, .U}, {.Remove, .R}, {.Leave, .L},
		{.Restart, .F5}, {.Main_Menu, .F10}, {.Animation_Speed, .F4}, {.Diagnostics, .F8},
		{.Intent_Display, .F6}, {.Clear_Lab, .F7}, {.Lab_Arena, .F3}, {.Debug_Thorns, .C}, {.Debug_Afterimage, .V},
	}
	for b in bindings { input.bind(&m, b.action, input.key(b.key)) }
	return m
}

// Values, not a borrowed pointer to the host frame: a suspended run may still
// be drawn underneath an activity on subsequent frames.
Run_Input :: struct {
	actions: input.Sample(Run_Action),
	focused: bool,
	left_pressed, left_down, left_released, right_pressed: bool,
	middle_pressed, middle_down: bool,
	mouse_window, mouse_motion: view.Vec2,
	wheel: f32,
}

// Native buttons already carry edges. Axes need history owned by the run;
// a held stick must never become a fresh press when a modal returns control.
Run_Input_History :: struct {
	active: bool,
	axes_down: bit_set[Run_Action],
}

map_run_input :: proc(actions: ^input.Action_Map(Run_Action), devices: ^input.Device_Snapshot, focused: bool,
	history: ^Run_Input_History = nil) -> Run_Input {
	r := Run_Input{focused = focused}
	if devices == nil {
		if history != nil { history^ = {} }
		return r
	}
	r.actions = input.sample(actions, devices)
	axes_down: bit_set[Run_Action]
	pad_available := actions.gamepad >= 0 && actions.gamepad < input.MAX_GAMEPADS && devices.gamepads[actions.gamepad].available
	for action in Run_Action {
		for binding in actions.bindings[action] {
			switch binding.kind {
			case .Gamepad_Axis_Positive, .Gamepad_Axis_Negative:
				if !pad_available { continue }
				value := devices.gamepads[actions.gamepad].axes[binding.axis]
				if binding.kind == .Gamepad_Axis_Negative { value = -value }
				if input.apply_deadzone(value, actions.axis_deadzone) >= actions.axis_press { axes_down += {action} }
			case .Mouse_Wheel_Up, .Mouse_Wheel_Down:
				// Every scrolling frame is an impulse, including consecutive
				// frames in the same direction; there is no held wheel state.
				if (binding.kind == .Mouse_Wheel_Up && devices.wheel > 0) ||
				   (binding.kind == .Mouse_Wheel_Down && devices.wheel < 0) { r.actions.pressed += {action} }
			case .None, .Key, .Mouse_Button, .Gamepad_Button:
			}
		}
	}
	if history != nil {
		if focused && history.active {
			r.actions.pressed += axes_down-history.axes_down
			r.actions.released += history.axes_down-axes_down
		}
		history^ = {active = focused, axes_down = axes_down}
	}
	r.left_pressed, r.left_down, r.left_released = input.mouse_pressed(devices, .LEFT), input.mouse_down(devices, .LEFT), input.mouse_released(devices, .LEFT)
	r.right_pressed = input.mouse_pressed(devices, .RIGHT)
	r.middle_pressed, r.middle_down = input.mouse_pressed(devices, .MIDDLE), input.mouse_down(devices, .MIDDLE)
	r.mouse_window = {devices.mouse_position.x, devices.mouse_position.y}
	r.mouse_motion = {devices.mouse_motion.x, devices.mouse_motion.y}
	r.wheel = devices.wheel
	return r
}

run_pressed :: proc(controls: Run_Input, action: Run_Action) -> bool { return action in controls.actions.pressed }
run_down :: proc(controls: Run_Input, action: Run_Action) -> bool { return action in controls.actions.down }

pressed_hand_slot :: proc(controls: Run_Input, limit: int = 8) -> int {
	for action, index in RUN_HAND_ACTIONS {
		if index >= limit { break }
		if run_pressed(controls, action) { return index }
	}
	return -1
}
