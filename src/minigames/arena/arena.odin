// "Arena delle Braci": a twin-stick survival arena. This file wires the
// simulation (world.odin, enemies.odin, level.odin) and the renderer
// (draw.odin) into the minigame shell.
package arena

import rl "vendor:raylib"
import camera "../../engine/camera"
import fx "../../engine/fx"
import host "../../engine/host"
import input "../../engine/input"
import physics "../../engine/physics"
import timing "../../engine/timing"

Action :: enum u8 {
	Left,
	Right,
	Up,
	Down,
	Aim_Left,
	Aim_Right,
	Aim_Up,
	Aim_Down,
	Fire,
	Dash,
	Dash_Alt,
}

// Debug hooks for the screenshot preview harness, set before `create`:
// `demo_autoplay` lets the test bot play instead of the devices, and
// `demo_skip_seconds` fast-forwards each round headlessly (bot play, or idle
// without autoplay) to reach later waves. The game itself never sets these.
demo_autoplay: bool
demo_skip_seconds: f32

Game :: struct {
	config:      host.Minigame_Config,
	world:       World,
	clock:       timing.Fixed_Step,
	actions:     input.Action_Map(Action),
	controls:    input.State(Action),
	was_playing: bool,
	// A dash press is delivered to exactly one fixed step, even on frames
	// that run none.
	dash_latch:  bool,
	demo:        bool,
	playing:     bool,
	view:        Render,
}

info :: proc() -> host.Minigame_Info {
	return host.Minigame_Info{
		id       = "arena",
		title    = "Arena delle Braci",
		genre    = "Arena top-down",
		tagline  = "Resisti alle ondate di creature di brace. Uccisioni rapide alzano la combo. Stelle: vittoria, mezza vita salva, combo alta.",
		controls = "WASD / stick sinistro: muovi    Mouse / stick destro: mira\nClic sinistro / RT: spara (tieni premuto)\nSpazio, Shift, clic destro / A: scatto invulnerabile\nEsc: pausa",
		accent   = rl.Color{232, 120, 48, 255},
		create   = create,
	}
}

create :: proc(config: host.Minigame_Config) -> host.Scene {
	g := new(Game)
	g.config = config
	g.demo = demo_autoplay
	g.clock = timing.fixed_step(SIM_HZ)
	g.actions = make_actions()
	render_init(&g.view)
	hooks := host.Minigame_Hooks{
		data          = g,
		reset         = game_reset,
		step          = game_step,
		draw          = game_draw,
		score         = game_score,
		destroy       = game_destroy,
		music         = .Action,
		capture_mouse = false,
	}
	return host.minigame_scene(info(), hooks, config)
}

make_actions :: proc() -> input.Action_Map(Action) {
	m := input.make_map(Action)
	input.bind_all(&m, Action.Left, input.key(.A), input.key(.LEFT), input.pad_axis(.LEFT_X, false), input.pad(.LEFT_FACE_LEFT))
	input.bind_all(&m, Action.Right, input.key(.D), input.key(.RIGHT), input.pad_axis(.LEFT_X, true), input.pad(.LEFT_FACE_RIGHT))
	input.bind_all(&m, Action.Up, input.key(.W), input.key(.UP), input.pad_axis(.LEFT_Y, false), input.pad(.LEFT_FACE_UP))
	input.bind_all(&m, Action.Down, input.key(.S), input.key(.DOWN), input.pad_axis(.LEFT_Y, true), input.pad(.LEFT_FACE_DOWN))
	input.bind_all(&m, Action.Aim_Left, input.pad_axis(.RIGHT_X, false))
	input.bind_all(&m, Action.Aim_Right, input.pad_axis(.RIGHT_X, true))
	input.bind_all(&m, Action.Aim_Up, input.pad_axis(.RIGHT_Y, false))
	input.bind_all(&m, Action.Aim_Down, input.pad_axis(.RIGHT_Y, true))
	input.bind_all(&m, Action.Fire, input.mouse(.LEFT), input.pad_axis(.RIGHT_TRIGGER, true), input.pad(.RIGHT_TRIGGER_2))
	input.bind_all(&m, Action.Dash, input.key(.SPACE), input.key(.LEFT_SHIFT), input.mouse(.RIGHT), input.pad(.RIGHT_FACE_DOWN))
	input.bind_all(&m, Action.Dash_Alt, input.key(.RIGHT_SHIFT), input.pad(.LEFT_TRIGGER_1), input.pad(.RIGHT_TRIGGER_1),
		input.pad_axis(.LEFT_TRIGGER, true))
	return m
}

@(private)
game_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Game)data
	g.config = config
	world_reset(&g.world, config)
	if demo_skip_seconds > 0 {
		// Without autoplay the skipped stretch is idle, which previews defeat.
		for _ in 0..<int(demo_skip_seconds*SIM_HZ) {
			step_input := bot_input(&g.world) if g.demo else Player_Input{}
			if world_step(&g.world, step_input, SIM_DT) != .Playing {
				break
			}
			events_clear(&g.world)
		}
		events_clear(&g.world)
		g.world.player.prev = g.world.player.pos
	}
	timing.fixed_step_reset(&g.clock)
	input.reset(&g.controls)
	g.was_playing = false
	g.dash_latch = false
	render_reset(&g.view, &g.world)
}

@(private)
read_input :: proc(g: ^Game, frame: ^host.Frame) -> Player_Input {
	s := &g.controls
	if frame.focused {
		input.poll(&g.actions, s, frame.dt)
		if !g.was_playing {
			// Keys still held from the intro or pause menu must not dash.
			s.pressed = {}
		}
	} else {
		input.reset(s)
	}
	g.was_playing = true
	if .Dash in s.pressed || .Dash_Alt in s.pressed {
		g.dash_latch = true
	}
	result := Player_Input{
		move = input.vector(s, Action.Left, Action.Right, Action.Up, Action.Down),
		fire = .Fire in s.down,
	}
	v := &g.view
	stick := input.vector(s, Action.Aim_Left, Action.Aim_Right, Action.Aim_Up, Action.Aim_Down)
	strength := physics.length2(stick)
	if strength > 0.3 {
		v.pad_aim = true
		result.aim = stick
		// Twin-stick habit: a fully deflected aim stick fires on its own.
		if strength > 0.85 {
			result.fire = true
		}
	} else if physics.length2(frame.mouse-v.last_mouse) > 1.5 {
		v.pad_aim = false
	}
	v.last_mouse = frame.mouse
	if !v.pad_aim {
		view := Vec2{frame.canvas.width, frame.canvas.height}
		target := camera.screen_to_world2(v.cam, view, frame.mouse)
		result.aim = target - g.world.player.pos
	}
	return result
}

@(private)
game_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Game)data
	v := &g.view
	w := &g.world
	g.playing = playing
	set_cursor_hidden(v, playing && frame.focused && frame.mouse_inside && !g.demo)
	if !playing {
		g.was_playing = false
		g.dash_latch = false
		input.reset(&g.controls)
		v.time += frame.dt
		ambient_update(v, frame.dt)
		return w.status
	}
	controls := Player_Input{}
	if g.demo {
		v.pad_aim = true
	} else {
		controls = read_input(g, frame)
	}
	dt := fx.hit_stop_filter(&v.hit_stop, frame.dt)
	steps := timing.fixed_step_advance(&g.clock, dt)
	status := w.status
	for _ in 0..<steps {
		step_input := controls
		if g.demo {
			step_input = bot_input(w)
		} else {
			step_input.dash = g.dash_latch
			g.dash_latch = false
		}
		status = world_step(w, step_input, g.clock.step)
	}
	render_events(v, w, frame)
	events_clear(w)
	render_update(v, w, frame, dt, g.clock.alpha)
	return status
}

@(private)
game_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Game)data
	render_draw(&g.view, &g.world, frame, g.clock.alpha, g.playing)
}

@(private)
game_score :: proc(data: rawptr) -> (i64, u8) {
	g := cast(^Game)data
	return world_score(&g.world)
}

@(private)
game_destroy :: proc(data: rawptr) {
	g := cast(^Game)data
	render_destroy(&g.view)
	world_destroy(&g.world)
	free(g)
}
