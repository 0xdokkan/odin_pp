package platform2d

import rl "vendor:raylib"
import audio "../../engine/audio"
import fx "../../engine/fx"
import host "../../engine/host"
import input "../../engine/input"
import timing "../../engine/timing"

Action :: enum u8 {
	Left,
	Right,
	Down,
	Jump,
	Jump_Alt,
	Dash,
}

info :: proc() -> host.Minigame_Info {
	return host.Minigame_Info{
		id       = "platform2d",
		title    = "Torre di Cenere",
		genre    = "Platform 2D",
		tagline  = "Risali la torre in fiamme fino al portale. Raccogli le braci: il 60% vale due stelle, il 90% senza ferite tre.",
		controls = "A/D o frecce: muoviti.  Spazio, W o Z: salta (ripremi in aria per il doppio salto).\nShift o X: scatto.  S: scendi dalle sporgenze.  Pad: stick, A salta, X scatta.\nCadi sui nemici per schiacciarli. Contro un muro puoi scivolare e rimbalzare.",
		accent   = rl.Color{232, 122, 58, 255},
		create   = create,
	}
}

create :: proc(config: host.Minigame_Config) -> host.Scene {
	return create_game(config, false)
}

// Debug and preview only: the solver's bot plays the round by itself.
create_autoplay :: proc(config: host.Minigame_Config) -> host.Scene {
	return create_game(config, true)
}

Game :: struct {
	world:       World,
	fixed:       timing.Fixed_Step,
	actions:     input.Action_Map(Action),
	controls:    input.State(Action),
	// Presses latched until a simulation step consumes them, so none is lost
	// on frames that run zero steps (hit-stop, high refresh rates).
	pending:     Player_Input,
	input_gate: input.Resume_Gate(Action),
	autoplay:    bool,
	bot:         Bot,
	view:        View,
}

@(private)
create_game :: proc(config: host.Minigame_Config, autoplay: bool) -> host.Scene {
	g := new(Game)
	g.autoplay = autoplay
	g.actions = make_actions()
	g.view.sprites = sprites_create()
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

make_actions :: proc() -> input.Action_Map(Action) {
	m := input.make_map(Action)
	input.bind_all(&m, Action.Left, input.key(.A), input.key(.LEFT), input.pad(.LEFT_FACE_LEFT), input.pad_axis(.LEFT_X, false))
	input.bind_all(&m, Action.Right, input.key(.D), input.key(.RIGHT), input.pad(.LEFT_FACE_RIGHT), input.pad_axis(.LEFT_X, true))
	input.bind_all(&m, Action.Down, input.key(.S), input.key(.DOWN), input.pad(.LEFT_FACE_DOWN), input.pad_axis(.LEFT_Y, true))
	input.bind_all(&m, Action.Jump, input.key(.SPACE), input.key(.Z), input.key(.K), input.pad(.RIGHT_FACE_DOWN))
	input.bind_all(&m, Action.Jump_Alt, input.key(.W), input.key(.UP))
	input.bind_all(&m, Action.Dash, input.key(.LEFT_SHIFT), input.key(.X), input.pad(.RIGHT_FACE_LEFT), input.pad(.RIGHT_TRIGGER_1))
	return m
}

@(private)
game_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Game)data
	world_reset(&g.world, config)
	g.fixed = timing.fixed_step(STEP_HZ)
	suspend_player_input(g)
	view_reset(&g.view, &g.world)
	if g.autoplay {
		bot_destroy(&g.bot)
		g.bot = bot_create(&g.world)
	}
}

@(private)
suspend_player_input :: proc(g: ^Game) {
	input.suspend(&g.controls, &g.input_gate)
	g.pending = {}
}

@(private)
advance_player_controls :: proc(g: ^Game, sample: input.Sample(Action), dt: f32) {
	input.advance_resumable(&g.controls, &g.input_gate, sample, dt, bit_set[Action]{})
	c := &g.controls
	if .Jump in c.pressed || .Jump_Alt in c.pressed {
		g.pending.jump_pressed = true
	}
	if .Dash in c.pressed {
		g.pending.dash_pressed = true
	}
	if .Down in c.pressed {
		g.pending.down_pressed = true
	}
}

@(private)
game_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Game)data
	w := &g.world
	if !playing {
		suspend_player_input(g)
		timing.fixed_step_advance(&g.fixed, 0, true)
		view_update(&g.view, w, frame, false)
		return w.status
	}
	if frame.focused && !g.autoplay {
		advance_player_controls(g, input.sample(&g.actions, frame.devices), frame.dt)
	} else {
		suspend_player_input(g)
	}
	c := &g.controls
	move := input.axis(c, Action.Left, Action.Right)
	held := .Jump in c.down || .Jump_Alt in c.down

	sim_dt := fx.hit_stop_filter(&g.view.hit_stop, frame.dt)
	steps := timing.fixed_step_advance(&g.fixed, sim_dt)
	status := w.status
	for _ in 0..<steps {
		cmd: Player_Input
		if g.autoplay {
			cmd = bot_input(&g.bot, w)
		} else {
			cmd = g.pending
			cmd.move = move
			cmd.jump_held = held
			g.pending = {}
		}
		status = world_step(w, cmd, SIM_DT)
		view_consume_events(&g.view, w, frame)
		// A fresh impact freezes the rest of this frame's steps.
		if status != .Playing || g.view.hit_stop.remaining > 0 {
			break
		}
	}
	view_update(&g.view, w, frame, true)
	return status
}

@(private)
game_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Game)data
	draw_game(&g.view, &g.world, frame)
}

@(private)
game_score :: proc(data: rawptr) -> (i64, u8) {
	g := cast(^Game)data
	return world_score(&g.world)
}

@(private)
game_destroy :: proc(data: rawptr) {
	g := cast(^Game)data
	bot_destroy(&g.bot)
	world_destroy(&g.world)
	sprites_destroy(&g.view.sprites)
	free(g)
}

// Sounds stay quiet for events far outside the view.
@(private)
play_at :: proc(v: ^View, frame: ^host.Frame, sfx: audio.Sfx, at: Vec2, volume := f32(1), pitch := f32(1)) {
	d := at - v.cam.position
	if abs(d.x) > 320 || abs(d.y) > 220 {
		return
	}
	audio.play(frame.audio, sfx, volume, pitch)
}
