// "Cripta delle Rune": a first-person crawl through a crypt generated from
// the seed. Collect every rune, survive ghouls, wraiths and cultists, and
// escape through the portal that the last rune unseals.
//
// world.odin, player.odin, enemies.odin, maze.odin and bot.odin are the pure
// simulation; draw.odin, hud.odin and sprites.odin render it.
package fps

import fx "../../engine/fx"
import host "../../engine/host"
import input "../../engine/input"
import timing "../../engine/timing"

Action :: enum u8 {
	Forward,
	Back,
	Left,
	Right,
	Sprint,
	Jump,
	Fire,
	Map,
	Look_Left,
	Look_Right,
	Look_Up,
	Look_Down,
}

// Radians per mouse pixel before the profile's sensitivity multiplier.
MOUSE_SENSITIVITY :: f32(0.0022)
// Radians per second at full right-stick deflection.
PAD_LOOK_SPEED :: f32(2.8)

Game :: struct {
	world:        World,
	view:         View,
	config:       host.Minigame_Config,
	clock:        timing.Fixed_Step,
	actions:      input.Action_Map(Action),
	controls:     input.State(Action),
	was_playing:  bool,
	jump_queued:  bool,
	fire_queued:  bool,
	fire_blocked: bool,
	demo:         bool,
}

info :: proc() -> host.Minigame_Info {
	return host.Minigame_Info{
		id       = "fps",
		title    = "Cripta delle Rune",
		genre    = "FPS 3D",
		tagline  = "Scendi nella cripta, strappa le rune ai suoi guardiani e fuggi dal portale prima che i morti ti reclamino.",
		controls = "Mouse: guarda   WASD / stick: muoviti   Shift: corri   Spazio: salta\nClick SX / RT: bastone runico   Tab: mappa",
		accent   = {226, 128, 58, 255},
		create   = create,
	}
}

create :: proc(config: host.Minigame_Config) -> host.Scene {
	return create_game(config, false)
}

// Debug and attract mode: the built-in bot plays the round and player input is
// ignored (preview screenshots, demos).
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
		data          = g,
		reset         = hook_reset,
		step          = hook_step,
		draw          = hook_draw,
		score         = hook_score,
		destroy       = hook_destroy,
		music         = .Tense,
		capture_mouse = true,
	}
	return host.minigame_scene(info(), hooks, config)
}

make_actions :: proc() -> input.Action_Map(Action) {
	m := input.make_map(Action)
	input.bind_all(&m, Action.Forward, input.key(.W), input.key(.UP), input.pad_axis(.LEFT_Y, false))
	input.bind_all(&m, Action.Back, input.key(.S), input.key(.DOWN), input.pad_axis(.LEFT_Y, true))
	input.bind_all(&m, Action.Left, input.key(.A), input.key(.LEFT), input.pad_axis(.LEFT_X, false))
	input.bind_all(&m, Action.Right, input.key(.D), input.key(.RIGHT), input.pad_axis(.LEFT_X, true))
	input.bind_all(&m, Action.Sprint, input.key(.LEFT_SHIFT), input.key(.RIGHT_SHIFT), input.pad(.LEFT_THUMB),
		input.pad(.LEFT_TRIGGER_1))
	input.bind_all(&m, Action.Jump, input.key(.SPACE), input.pad(.RIGHT_FACE_DOWN))
	input.bind_all(&m, Action.Fire, input.mouse(.LEFT), input.pad(.RIGHT_TRIGGER_2), input.pad_axis(.RIGHT_TRIGGER, true),
		input.pad(.RIGHT_TRIGGER_1))
	input.bind_all(&m, Action.Map, input.key(.TAB), input.pad(.MIDDLE_LEFT), input.pad(.RIGHT_FACE_UP))
	input.bind_all(&m, Action.Look_Left, input.pad_axis(.RIGHT_X, false))
	input.bind_all(&m, Action.Look_Right, input.pad_axis(.RIGHT_X, true))
	input.bind_all(&m, Action.Look_Up, input.pad_axis(.RIGHT_Y, false))
	input.bind_all(&m, Action.Look_Down, input.pad_axis(.RIGHT_Y, true))
	return m
}

@(private)
hook_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Game)data
	g.config = config
	world_reset(&g.world, config)
	g.clock = timing.fixed_step(SIM_HZ)
	suspend_player_input(g)
	view_reset(&g.view, &g.world)
}

@(private)
suspend_player_input :: proc(g: ^Game) {
	input.reset(&g.controls)
	g.was_playing = false
	g.jump_queued = false
	g.fire_queued = false
	g.fire_blocked = false
}

// A click that starts/resumes the round belongs to the shell until released.
// Movement remains held input; jump is delivered once, fire also supports hold.
@(private)
advance_player_controls :: proc(g: ^Game, sample: input.Sample(Action), dt: f32) -> Player_Input {
	input.advance(&g.controls, sample, dt)
	if !g.was_playing {
		g.was_playing = true
		g.controls.pressed = {}
		g.fire_blocked = .Fire in g.controls.down
		return {}
	}
	g.fire_blocked = g.fire_blocked && .Fire in g.controls.down
	move := input.vector(&g.controls, Action.Left, Action.Right, Action.Forward, Action.Back)
	if .Jump in g.controls.pressed {
		g.jump_queued = true
	}
	if .Map in g.controls.pressed {
		g.view.show_map = !g.view.show_map
	}
	return Player_Input{
		move = {move.x, -move.y},
		sprint = .Sprint in g.controls.down,
		fire = .Fire in g.controls.down && !g.fire_blocked,
	}
}

@(private)
hook_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Game)data
	w := &g.world
	v := &g.view
	v.shake_scale = frame.profile.settings.screen_shake if frame.profile != nil else 1
	if !playing {
		suspend_player_input(g)
		timing.fixed_step_advance(&g.clock, 0, true)
		// Intro and pause hold everything; after the round the death fall and
		// the particles keep playing under the results panel.
		view_update(g, frame, w.status != .Playing)
		return w.status
	}

	base: Player_Input
	look: Vec2
	if !frame.focused {
		suspend_player_input(g)
	}
	if frame.focused && !g.demo {
		resuming := !g.was_playing
		base = advance_player_controls(g, input.sample(&g.actions), frame.dt)
		if resuming {
			// Keys still held from the menu (Space, Enter) must not fire edges.
			_ = input.mouse_delta()
		} else {
			sensitivity := MOUSE_SENSITIVITY
			if frame.profile != nil {
				sensitivity *= frame.profile.settings.mouse_sensitivity
			}
			mouse := input.mouse_delta()
			mouse.x = clamp(mouse.x, -300, 300)
			mouse.y = clamp(mouse.y, -300, 300)
			look = Vec2{-mouse.x, -mouse.y} * sensitivity
			stick := Vec2{input.axis(&g.controls, Action.Look_Left, Action.Look_Right),
				input.axis(&g.controls, Action.Look_Up, Action.Look_Down)}
			// Squared response keeps small stick movements precise.
			stick = Vec2{stick.x * abs(stick.x), stick.y * abs(stick.y)}
			pad_scale := PAD_LOOK_SPEED * frame.dt
			if frame.profile != nil {
				pad_scale *= frame.profile.settings.mouse_sensitivity
			}
			look -= stick * pad_scale
		}
	}
	return advance_simulation(g, frame, base, look)
}

// Keep frame input separate from device polling so fixed-step delivery can be
// exercised headlessly with the same path used by the window.
@(private)
advance_simulation :: proc(g: ^Game, frame: ^host.Frame, base: Player_Input, look: Vec2) -> host.Round_Status {
	w := &g.world
	v := &g.view
	if !g.demo {
		g.fire_queued = g.fire_queued || base.fire
	}
	dt := fx.hit_stop_filter(&v.hit_stop, frame.dt)
	steps := timing.fixed_step_advance(&g.clock, dt)
	if steps == 0 {
		// No step this frame (hit-stop): keep the view responsive anyway.
		world_look(w, look)
	}
	for i in 0..<steps {
		step_input := base
		if g.demo {
			step_input = bot_input(w, g.clock.step)
		} else if i == 0 {
			step_input.look = look
			step_input.jump = g.jump_queued
			step_input.fire = base.fire || g.fire_queued
			g.jump_queued = false
			g.fire_queued = false
		}
		world_step(w, step_input, g.clock.step)
		view_consume_events(g, frame)
		if w.status != .Playing {
			break
		}
	}
	view_update(g, frame, true)
	return w.status
}

@(private)
hook_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Game)data
	view_draw(g, frame)
}

@(private)
hook_score :: proc(data: rawptr) -> (i64, u8) {
	g := cast(^Game)data
	return world_score(&g.world)
}

@(private)
hook_destroy :: proc(data: rawptr) {
	g := cast(^Game)data
	view_destroy(&g.view)
	world_destroy(&g.world)
	free(g)
}
