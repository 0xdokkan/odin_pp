package platform3d

import "core:math"
import rl "vendor:raylib"
import fx "../../engine/fx"
import host "../../engine/host"
import input "../../engine/input"
import timing "../../engine/timing"

Action :: enum u8 {
	Left,
	Right,
	Forward,
	Back,
	Jump,
	Dash,
	Cam_Left,
	Cam_Right,
	Cam_Up,
	Cam_Down,
	Orbit,
	Zoom_In,
	Zoom_Out,
}

Game :: struct {
	config:       host.Minigame_Config,
	world:        World,
	view:         View,
	actions:      input.Action_Map(Action),
	controls:     input.State(Action),
	clock:        timing.Fixed_Step,
	hit_stop:     fx.Hit_Stop,
	// Edges caught on frames that run no simulation step are kept for the next.
	pending_jump: bool,
	pending_dash: bool,
	input_gate: input.Resume_Gate(Action),
	demo:         bool,
	bot:          Bot,
}

info :: proc() -> host.Minigame_Info {
	return host.Minigame_Info{
		id       = "platform3d",
		title    = "Guglie Sospese",
		genre    = "Platform 3D",
		tagline  = "Isole di pietra sospese sull'abisso. Raccogli i frammenti d'anima, risveglia il portale del santuario e non guardare giù.",
		controls = "WASD: muovi   Spazio: salta, anche in aria   Shift: scatto   Q/E o tasto destro: visuale   Rotella: zoom   Pad: stick sinistro, A salta, X/RB scatto, stick destro visuale",
		accent   = rl.Color{120, 200, 240, 255},
		create   = create,
	}
}

create :: proc(config: host.Minigame_Config) -> host.Scene {
	return create_game(config, false)
}

// Debug and attract mode: the bot plays the round (preview screenshots, demos).
create_autoplay :: proc(config: host.Minigame_Config) -> host.Scene {
	return create_game(config, true)
}

@(private)
create_game :: proc(config: host.Minigame_Config, demo: bool) -> host.Scene {
	g := new(Game)
	g.config = config
	g.demo = demo
	g.actions = make_actions()
	view_init(&g.view)
	hooks := host.Minigame_Hooks{
		data    = g,
		reset   = game_reset,
		step    = game_step,
		draw    = game_draw,
		score   = game_score,
		destroy = game_destroy,
		music   = .Action,
	}
	return host.minigame_scene(info(), hooks, config)
}

@(private)
make_actions :: proc() -> input.Action_Map(Action) {
	m := input.make_map(Action)
	input.bind_all(&m, Action.Left, input.key(.A), input.key(.LEFT), input.pad(.LEFT_FACE_LEFT), input.pad_axis(.LEFT_X, false))
	input.bind_all(&m, Action.Right, input.key(.D), input.key(.RIGHT), input.pad(.LEFT_FACE_RIGHT), input.pad_axis(.LEFT_X, true))
	input.bind_all(&m, Action.Forward, input.key(.W), input.key(.UP), input.pad(.LEFT_FACE_UP), input.pad_axis(.LEFT_Y, false))
	input.bind_all(&m, Action.Back, input.key(.S), input.key(.DOWN), input.pad(.LEFT_FACE_DOWN), input.pad_axis(.LEFT_Y, true))
	input.bind_all(&m, Action.Jump, input.key(.SPACE), input.pad(.RIGHT_FACE_DOWN))
	input.bind_all(&m, Action.Dash, input.key(.LEFT_SHIFT), input.key(.RIGHT_SHIFT), input.pad(.RIGHT_FACE_LEFT), input.pad(.RIGHT_TRIGGER_1))
	input.bind_all(&m, Action.Cam_Left, input.key(.Q), input.pad_axis(.RIGHT_X, false), input.pad(.LEFT_TRIGGER_1))
	input.bind_all(&m, Action.Cam_Right, input.key(.E), input.pad_axis(.RIGHT_X, true))
	input.bind_all(&m, Action.Cam_Up, input.pad_axis(.RIGHT_Y, false))
	input.bind_all(&m, Action.Cam_Down, input.pad_axis(.RIGHT_Y, true))
	input.bind_all(&m, Action.Orbit, input.mouse(.RIGHT))
	input.bind_all(&m, Action.Zoom_In, input.wheel(true))
	input.bind_all(&m, Action.Zoom_Out, input.wheel(false))
	return m
}

@(private)
game_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Game)data
	g.config = config
	world_reset(&g.world, config)
	g.clock = timing.fixed_step(SIM_HZ)
	suspend_player_input(g)
	g.hit_stop = {}
	if g.demo {
		bot_init(&g.bot, &g.world)
	}
	view_reset(&g.view, &g.world)
}

@(private)
suspend_player_input :: proc(g: ^Game) {
	input.suspend(&g.controls, &g.input_gate)
	g.pending_jump = false
	g.pending_dash = false
}

@(private)
advance_player_controls :: proc(g: ^Game, sample: input.Sample(Action), dt: f32) {
	input.advance_resumable(&g.controls, &g.input_gate, sample, dt, bit_set[Action]{})
	if .Jump in g.controls.pressed {
		g.pending_jump = true
	}
	if .Dash in g.controls.pressed {
		g.pending_dash = true
	}
}

// Camera-relative movement. camera.orbit_ground_basis returns a mirrored
// right vector (screen right is -x when looking down +z), so the basis is
// derived here from the yaw instead.
camera_basis :: proc "contextless" (yaw: f32) -> (forward, right: Vec2) {
	forward = Vec2{math.sin(yaw), math.cos(yaw)}
	right = Vec2{-forward.y, forward.x}
	return
}

@(private)
game_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Game)data
	w := &g.world
	if !playing {
		suspend_player_input(g)
		timing.fixed_step_advance(&g.clock, 0, true)
		view_update(&g.view, w, frame, frame.dt)
		return w.status
	}
	if !frame.focused {
		suspend_player_input(g)
	} else if !g.demo {
		advance_player_controls(g, input.sample(&g.actions), frame.dt)
	}
	c := &g.controls
	sensitivity := frame.profile.settings.mouse_sensitivity if frame.profile != nil else 1
	look := Vec2{input.axis(c, Action.Cam_Right, Action.Cam_Left), input.axis(c, Action.Cam_Up, Action.Cam_Down)}
	mouse: Vec2
	if .Orbit in c.down {
		mouse = input.mouse_delta() * sensitivity
	}
	zoom := c.value[.Zoom_Out] - c.value[.Zoom_In]
	view_camera_input(&g.view, look, mouse, zoom, frame.dt)

	stick := input.vector(c, Action.Left, Action.Right, Action.Forward, Action.Back)
	forward, right := camera_basis(g.view.cam.yaw)
	cmd := Player_Input{move = forward*(-stick.y) + right*stick.x, jump_held = .Jump in c.down}
	dt := fx.hit_stop_filter(&g.hit_stop, frame.dt)
	steps := timing.fixed_step_advance(&g.clock, dt)
	for _ in 0..<steps {
		step_input := cmd
		if g.demo {
			step_input = bot_input(&g.bot, w)
		} else {
			step_input.jump_pressed = g.pending_jump
			step_input.dash_pressed = g.pending_dash
			g.pending_jump = false
			g.pending_dash = false
		}
		world_step(w, step_input, g.clock.step)
		view_events(&g.view, w, frame, &g.hit_stop)
	}
	view_update(&g.view, w, frame, frame.dt)
	return w.status
}

@(private)
game_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Game)data
	view_draw(&g.view, &g.world, frame)
}

@(private)
game_score :: proc(data: rawptr) -> (i64, u8) {
	g := cast(^Game)data
	return world_score(&g.world)
}

@(private)
game_destroy :: proc(data: rawptr) {
	g := cast(^Game)data
	view_destroy(&g.view)
	world_destroy(&g.world)
	free(g)
}
