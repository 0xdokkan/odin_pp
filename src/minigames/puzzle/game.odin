// "Sigilli della Cripta": push stone relics onto rune sigils.
//
// game.odin wires the pure rules (puzzle.odin, solver.odin, session.odin) to
// the minigame shell: input, phases between levels, sounds and drawing.
package puzzle

import rl "vendor:raylib"
import audio "../../engine/audio"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import host "../../engine/host"
import input "../../engine/input"

Action :: enum u8 {
	Up,
	Down,
	Left,
	Right,
	Undo,
	Redo,
	Restart,
	Hint,
}

Phase :: enum u8 {
	Enter, // the level assembles
	Play,
	Clear, // solved: celebration
	Leave, // fade toward the next level
	Won,
	Snuffed, // challenge torch ran out
}

ENTER_TIME :: 1.1
CLEAR_TIME :: 1.7
LEAVE_TIME :: 0.45
SNUFF_TIME :: 1.1
HINT_BUDGET :: 400_000
DEMO_STEP :: 0.17

// Held directions (and undo/redo) repeat after a short delay.
REPEAT_DELAY :: 0.18
REPEAT_RATE :: 0.09

Repeat :: struct {
	action: Action,
	active: bool,
	timer:  f32,
}

Hint_Cache :: struct {
	path:  [dynamic]Dir,
	index: int,
	state: State, // the state path[index] applies to
	valid: bool,
}

// Debug autoplay: replays the solver's line at a fixed pace. Used by the
// preview harness for screenshots and as an attract-mode demo.
Demo :: struct {
	enabled: bool,
	limit:   int, // moves per level before pausing, < 0 = until solved
	done:    int,
	timer:   f32,
	path:    [dynamic]Dir,
	index:   int,
}

Game :: struct {
	config:      host.Minigame_Config,
	session:     Session,
	view:        View,
	actions:     input.Action_Map(Action),
	controls:    input.State(Action),
	repeat:      Repeat,
	queued:      Action,
	has_queued:  bool,
	input_gate: input.Resume_Gate(Action),
	phase:       Phase,
	phase_time:  f32,
	result:      Level_Result, // of the level just cleared
	hint:        Hint_Cache,
	demo:        Demo,
	time:        f32,
	canvas:      rl.Rectangle,
	// Holding a direction into a wall repeats the bump; only the first one
	// of a run makes a sound.
	blocked_dir: Dir,
	blocked_at:  f32,
}

info :: proc() -> host.Minigame_Info {
	return host.Minigame_Info{
		id       = "puzzle",
		title    = "Sigilli della Cripta",
		genre    = "Puzzle a turni",
		tagline  = "Spingi le reliquie sui sigilli runici: quando brillano tutti, la cripta si apre. Sul ghiaccio si scivola fino al primo ostacolo; le grate restano aperte solo finché ogni piastra è premuta.",
		controls = "Frecce/WASD o croce: muovi e spingi (non si tira). Z annulla, Y ripete, R ricomincia, H suggerimento. Tre stelle entro il par di mosse. Nella sfida ogni mossa consuma la torcia e non ci sono suggerimenti.",
		accent   = rl.Color{120, 150, 255, 255},
		create   = create,
	}
}

create :: proc(config: host.Minigame_Config) -> host.Scene {
	g := new(Game)
	g.config = config
	g.canvas = {0, 0, 960, 540}
	view_create(&g.view)
	g.actions = input.make_map(Action)
	m := &g.actions
	input.bind_all(m, Action.Up, input.key(.UP), input.key(.W), input.pad(.LEFT_FACE_UP), input.pad_axis(.LEFT_Y, false))
	input.bind_all(m, Action.Down, input.key(.DOWN), input.key(.S), input.pad(.LEFT_FACE_DOWN), input.pad_axis(.LEFT_Y, true))
	input.bind_all(m, Action.Left, input.key(.LEFT), input.key(.A), input.pad(.LEFT_FACE_LEFT), input.pad_axis(.LEFT_X, false))
	input.bind_all(m, Action.Right, input.key(.RIGHT), input.key(.D), input.pad(.LEFT_FACE_RIGHT), input.pad_axis(.LEFT_X, true))
	// Backspace belongs to the shell (it pauses), so undo lives on Z and U.
	input.bind_all(m, Action.Undo, input.key(.Z), input.key(.U), input.pad(.RIGHT_FACE_LEFT), input.pad(.LEFT_TRIGGER_1))
	input.bind_all(m, Action.Redo, input.key(.Y), input.pad(.RIGHT_TRIGGER_1))
	input.bind_all(m, Action.Restart, input.key(.R), input.pad(.RIGHT_FACE_UP))
	input.bind_all(m, Action.Hint, input.key(.H), input.pad(.MIDDLE_LEFT))
	// The shell calls `reset` (game_reset) while building the scene.
	hooks := host.Minigame_Hooks{
		data          = g,
		reset         = game_reset,
		step          = game_step,
		draw          = game_draw,
		score         = game_score,
		destroy       = game_destroy,
		music         = .Calm,
		capture_mouse = false,
	}
	return host.minigame_scene(info(), hooks, config)
}

@(private)
game_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Game)data
	g.config = config
	suspend_player_input(g)
	session_start(&g.session, config.seed, config.challenge)
	begin_level(g)
}

@(private)
suspend_player_input :: proc(g: ^Game) {
	input.suspend(&g.controls, &g.input_gate)
	g.repeat = {}
	g.has_queued = false
}

@(private)
begin_level :: proc(g: ^Game) {
	view_reset(&g.view, &g.session.puzzle, g.canvas, g.config.seed + u64(g.session.current)*977)
	g.phase = .Enter
	g.phase_time = 0
	g.has_queued = false
	g.repeat = {}
	g.hint.valid = false
	g.demo.done = 0
	clear(&g.demo.path)
	g.demo.index = 0
}

@(private)
game_destroy :: proc(data: rawptr) {
	g := cast(^Game)data
	view_destroy(&g.view)
	delete(g.hint.path)
	delete(g.demo.path)
	free(g)
}

@(private)
game_score :: proc(data: rawptr) -> (i64, u8) {
	g := cast(^Game)data
	return session_score(&g.session)
}

// Turns this frame's edges and held time into at most one command.
repeat_update :: proc(r: ^Repeat, st: ^input.State(Action), dt: f32) -> (Action, bool) {
	repeatable := bit_set[Action]{.Up, .Down, .Left, .Right, .Undo, .Redo}
	// Newly pressed actions win; directions first so a quick tap is not lost.
	order := [?]Action{.Up, .Down, .Left, .Right, .Undo, .Redo, .Restart, .Hint}
	for a in order {
		if a in st.pressed {
			if a in repeatable {
				r^ = Repeat{action = a, active = true, timer = REPEAT_DELAY}
			}
			return a, true
		}
	}
	if !r.active {
		return .Up, false
	}
	if r.action not_in st.down {
		r.active = false
		return .Up, false
	}
	r.timer -= dt
	if r.timer <= 0 {
		r.timer += REPEAT_RATE
		return r.action, true
	}
	return .Up, false
}

@(private)
action_dir :: proc(a: Action) -> (Dir, bool) {
	#partial switch a {
	case .Up:
		return .Up, true
	case .Down:
		return .Down, true
	case .Left:
		return .Left, true
	case .Right:
		return .Right, true
	}
	return .Up, false
}

@(private)
game_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Game)data
	g.time += frame.dt
	g.canvas = frame.canvas
	view_ambient(&g.view, &g.session.puzzle, frame.dt)
	if !playing {
		suspend_player_input(g)
		return .Playing
	}
	dt := frame.dt
	g.phase_time += dt
	view_update(&g.view, &g.session.puzzle, dt)

	command: Action
	has_command := false
	if frame.focused {
		if input.advance_resumable(&g.controls, &g.input_gate, input.sample(&g.actions), dt, bit_set[Action]{}) {
			g.repeat = {}
		}
		command, has_command = repeat_update(&g.repeat, &g.controls, dt)
	} else {
		// The shell owns focus pauses. Without device focus, scripted/demo
		// commands may still finish; only device state and repeats are reset.
		input.suspend(&g.controls, &g.input_gate)
		g.repeat = {}
	}

	switch g.phase {
	case .Enter:
		if has_command {
			queue_command(g, command)
		}
		if g.phase_time >= ENTER_TIME {
			set_phase(g, .Play)
		}
	case .Play:
		if has_command {
			queue_command(g, command)
		}
		if g.demo.enabled && !g.has_queued {
			demo_step(g, frame, dt)
		}
		if g.has_queued && !view_busy(&g.view, int(g.session.puzzle.state.crate_count)) {
			g.has_queued = false
			execute(g, frame, g.queued)
		}
	case .Clear:
		if g.phase_time >= CLEAR_TIME {
			if session_is_last(&g.session) {
				set_phase(g, .Won)
				return .Won
			}
			set_phase(g, .Leave)
		}
	case .Leave:
		if g.phase_time >= LEAVE_TIME {
			session_load(&g.session, g.session.current+1)
			begin_level(g)
		}
	case .Won:
		return .Won
	case .Snuffed:
		if g.phase_time >= SNUFF_TIME {
			return .Lost
		}
	}
	return .Playing
}

@(private)
set_phase :: proc(g: ^Game, phase: Phase) {
	g.phase = phase
	g.phase_time = 0
}

// One slot: a newer command replaces an older one still waiting.
@(private)
queue_command :: proc(g: ^Game, a: Action) {
	g.queued = a
	g.has_queued = true
}

@(private)
execute :: proc(g: ^Game, frame: ^host.Frame, a: Action) {
	s := &g.session
	p := &s.puzzle
	v := &g.view
	if d, ok := action_dir(a); ok {
		do_move(g, frame, d)
		return
	}
	#partial switch a {
	case .Undo:
		if undo(p) {
			view_follow(v, p, .Undo)
			v.hint_time = 0
			audio.play(frame.audio, .Back, 0.6)
		}
	case .Redo:
		if redo(p) {
			view_follow(v, p, .Undo)
			audio.play(frame.audio, .Blip, 0.5)
		}
	case .Restart:
		if restart(p) {
			view_follow(v, p, .Rewind)
			v.hint_time = 0
			audio.play(frame.audio, .Back, 0.8, 0.7)
		}
	case .Hint:
		show_hint(g, frame)
	}
}

@(private)
do_move :: proc(g: ^Game, frame: ^host.Frame, d: Dir) {
	s := &g.session
	p := &s.puzzle
	v := &g.view
	before := p.state
	r := apply_move(p, d)
	if !r.moved {
		repeated := g.blocked_dir == d && g.time-g.blocked_at < 0.3
		g.blocked_dir = d
		g.blocked_at = g.time
		if !repeated {
			view_bump(v, d)
			audio.play(frame.audio, .Blip, 0.25, 0.55)
		}
		return
	}
	g.blocked_at = -1
	track_hint(&g.hint, before, d, p.state)
	view_follow(v, p, .Move)
	view_on_move(v, p, r)
	if r.pushed {
		audio.play(frame.audio, .Push, 0.9, 0.9 + 0.1*f32(p.moves%3))
	} else {
		audio.play(frame.audio, .Step, 0.7)
	}
	if r.crate_slid || r.player_slid {
		audio.play(frame.audio, .Dash, 0.45, 1.3)
	}
	if r.sigil_filled {
		audio.play(frame.audio, .Coin, 0.6)
	}
	if r.gates_opened {
		audio.play(frame.audio, .Power_Up, 0.35, 1.4)
	} else if r.gates_closed {
		audio.play(frame.audio, .Land, 0.7, 0.7)
	}
	if r.solved {
		g.result = session_complete_level(s)
		view_celebrate(v, p)
		if !session_is_last(s) {
			audio.play(frame.audio, .Power_Up, 0.6)
		}
		set_phase(g, .Clear)
		return
	}
	if session_spend_torch(s) {
		audio.play(frame.audio, .Hurt, 0.6)
		set_phase(g, .Snuffed)
		return
	}
	if s.torch_max > 0 && s.torch == 10 {
		view_message(v, "La torcia si sta spegnendo...")
		audio.play(frame.audio, .Blip, 0.5, 0.7)
	}
}

// Keeps a hint line valid while the player follows it.
@(private)
track_hint :: proc(h: ^Hint_Cache, before: State, d: Dir, after: State) {
	if !h.valid {
		return
	}
	if h.state == before && h.index < len(h.path) && h.path[h.index] == d {
		h.index += 1
		h.state = after
		return
	}
	h.valid = false
}

@(private)
show_hint :: proc(g: ^Game, frame: ^host.Frame) {
	s := &g.session
	p := &s.puzzle
	v := &g.view
	if s.challenge {
		view_message(v, "Nessun suggerimento durante la sfida")
		audio.play(frame.audio, .Blip, 0.4, 0.6)
		return
	}
	h := &g.hint
	if !(h.valid && h.state == p.state && h.index < len(h.path)) {
		sol := solve(&p.board, p.state, HINT_BUDGET)
		if !sol.solved || len(sol.path) == 0 {
			solution_destroy(&sol)
			h.valid = false
			view_message(v, "Troppo intricato da qui: prova ad annullare")
			audio.play(frame.audio, .Blip, 0.4, 0.6)
			return
		}
		delete(h.path)
		h.path = sol.path
		h.index = 0
		h.state = p.state
		h.valid = true
	}
	v.hint_dir = h.path[h.index]
	v.hint_time = 3
	s.hints += 1
	audio.play(frame.audio, .Confirm, 0.5)
}

@(private)
demo_step :: proc(g: ^Game, frame: ^host.Frame, dt: f32) {
	d := &g.demo
	if d.limit >= 0 && d.done >= d.limit {
		return
	}
	d.timer -= dt
	if d.timer > 0 || view_busy(&g.view, int(g.session.puzzle.state.crate_count)) {
		return
	}
	d.timer = DEMO_STEP
	p := &g.session.puzzle
	if d.index >= len(d.path) {
		sol := solve(&p.board, p.state, 4_000_000)
		delete(d.path)
		d.path = sol.path
		d.index = 0
		if !sol.solved {
			d.enabled = false
			return
		}
	}
	dir := d.path[d.index]
	d.index += 1
	d.done += 1
	do_move(g, frame, dir)
}

// Enables the solver autoplay on a scene made by `create`. `moves_per_level`
// stops it after that many moves on each level (< 0 plays to the end).
autoplay :: proc(scene: ^host.Scene, moves_per_level := -1) {
	shell := host.shell_of(scene)
	if shell == nil {
		return
	}
	g := cast(^Game)shell.hooks.data
	g.demo.enabled = true
	g.demo.limit = moves_per_level
	g.demo.done = 0
}

// Debug: replaces the planned sequence with one library level.
force_level :: proc(scene: ^host.Scene, level: int, transform := Transform.Identity) {
	shell := host.shell_of(scene)
	if shell == nil {
		return
	}
	g := cast(^Game)shell.hooks.data
	session_force_level(&g.session, level, transform)
	begin_level(g)
}

@(private)
game_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Game)data
	s := &g.session
	p := &s.puzzle
	v := &g.view
	canvas := frame.canvas
	draw_backdrop(canvas, g.time)

	params := Draw_Params{time = g.time, reveal = 1, celebrate = -1, shake_scale = 1}
	if frame.profile != nil {
		params.shake_scale = frame.profile.settings.screen_shake
	}
	switch g.phase {
	case .Enter:
		params.reveal = clamp(g.phase_time/(ENTER_TIME*0.8), 0, 1)
	case .Clear, .Won:
		params.celebrate = g.phase_time
	case .Leave:
		params.celebrate = CLEAR_TIME + g.phase_time
	case .Play, .Snuffed:
	}
	draw_world(v, p, params)
	if g.phase == .Play {
		draw_hint(v, g.time)
	}
	fx.flash_draw(v.flash, canvas.width, canvas.height)
	gfx.draw_vignette(canvas.width, canvas.height, vignette_strength(s.torch, s.torch_max))

	level := session_level(s)
	draw_hud(v, frame.theme, canvas, Hud_Info{
		level_index = s.current,
		level_count = s.count,
		level_name  = level.name,
		moves       = p.moves,
		par         = s.par,
		torch       = s.torch,
		torch_max   = s.torch_max,
		plates      = p.board.plate_count,
		plates_down = pressed_plates(&p.board, &p.state),
		hints       = s.hints,
		challenge   = s.challenge,
	}, g.time)

	switch g.phase {
	case .Enter:
		k := 1 - clamp((g.phase_time-ENTER_TIME*0.55)/(ENTER_TIME*0.45), 0, 1)
		draw_title_card(frame.theme, canvas, s.current, s.count, level.name, k)
	case .Clear, .Won:
		draw_clear_card(frame.theme, canvas, g.result, g.phase_time, session_is_last(s))
	case .Leave:
		draw_clear_card(frame.theme, canvas, g.result, CLEAR_TIME, false)
		a := clamp(g.phase_time/LEAVE_TIME, 0, 1)
		rl.DrawRectangleRec(canvas, {0, 0, 0, u8(255*a)})
	case .Snuffed:
		a := clamp(g.phase_time/SNUFF_TIME, 0, 1)
		rl.DrawRectangleRec(canvas, {0, 0, 0, u8(200*a)})
	case .Play:
	}
}
