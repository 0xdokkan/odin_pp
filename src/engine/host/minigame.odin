package host

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import audio "../audio"
import input "../input"
import ui "../ui"

// How a minigame is started: from the launcher (free play, retries allowed)
// or as a one-shot challenge inside a roguelike run.
Minigame_Config :: struct {
	seed:       u64,
	difficulty: int, // 0 easy, 1 normal, 2 hard
	challenge:  bool,
}

Minigame_Info :: struct {
	id:       string,
	title:    string,
	genre:    string,
	tagline:  string,
	controls: string,
	accent:   rl.Color,
	create:   proc(config: Minigame_Config) -> Scene,
}

Round_Status :: enum u8 {
	Playing,
	Won,
	Lost,
}

// The part each minigame implements; the shell provides intro, pause,
// results, records and music around it.
Minigame_Hooks :: struct {
	data:          rawptr,
	// (Re)starts a round from the config; called before the intro and on retry.
	reset:         proc(data: rawptr, config: Minigame_Config),
	// Called every frame. `playing` is false during intro, pause and results,
	// when the simulation must hold still (ambient animation may continue).
	step:          proc(data: rawptr, frame: ^Frame, playing: bool) -> Round_Status,
	draw:          proc(data: rawptr, frame: ^Frame),
	score:         proc(data: rawptr) -> (score: i64, stars: u8),
	destroy:       proc(data: rawptr),
	music:         audio.Music_Mood,
	capture_mouse: bool,
}

Shell_Phase :: enum u8 {
	Intro,
	Playing,
	Paused,
	Finished,
}

Minigame_Shell :: struct {
	info:      Minigame_Info,
	hooks:     Minigame_Hooks,
	config:    Minigame_Config,
	phase:     Shell_Phase,
	elapsed:   f32,
	status:    Round_Status,
	result:    Result,
	new_best:  bool,
	attempts:  int,
	phase_time: f32,
}

// Wraps hooks into an opaque, modal scene.
minigame_scene :: proc(info: Minigame_Info, hooks: Minigame_Hooks, config: Minigame_Config) -> Scene {
	shell := new(Minigame_Shell)
	shell.info = info
	shell.hooks = hooks
	shell.config = config
	shell_restart(shell)
	return Scene{
		name        = info.id,
		data        = shell,
		opaque      = true,
		modal       = true,
		clear_color = rl.Color{10, 10, 16, 255},
		update      = shell_update,
		draw        = shell_draw,
		destroy     = shell_destroy,
	}
}

@(private)
shell_restart :: proc(s: ^Minigame_Shell) {
	if s.hooks.reset != nil {
		s.hooks.reset(s.hooks.data, s.config)
	}
	s.phase = .Intro
	s.elapsed = 0
	s.status = .Playing
	s.new_best = false
	s.phase_time = 0
	s.attempts += 1
}

@(private)
shell_destroy :: proc(data: rawptr) {
	s := cast(^Minigame_Shell)data
	if s.hooks.capture_mouse {
		input.capture_mouse(false)
	}
	if s.hooks.destroy != nil {
		s.hooks.destroy(s.hooks.data)
	}
	free(s)
}

@(private)
set_phase :: proc(s: ^Minigame_Shell, phase: Shell_Phase) {
	s.phase = phase
	s.phase_time = 0
	if s.hooks.capture_mouse {
		input.capture_mouse(phase == .Playing)
	}
}

@(private)
finish :: proc(s: ^Minigame_Shell, frame: ^Frame, outcome: Outcome) {
	score, stars := i64(0), u8(0)
	if s.hooks.score != nil {
		score, stars = s.hooks.score(s.hooks.data)
	}
	if outcome != .Won {
		stars = 0
	}
	s.result = Result{minigame = s.info.id, outcome = outcome, score = score, stars = min(stars, 3), elapsed = s.elapsed}
	if frame.profile != nil && outcome != .Abandoned {
		s.new_best = record_result(frame.profile, s.result)
	}
	audio.play(frame.audio, .Win if outcome == .Won else .Lose)
	set_phase(s, .Finished)
}

@(private)
leave :: proc(s: ^Minigame_Shell, frame: ^Frame) {
	if s.phase != .Finished {
		finish(s, frame, .Abandoned)
	}
	pop(frame, s.result)
}

@(private)
shell_update :: proc(data: rawptr, frame: ^Frame) {
	s := cast(^Minigame_Shell)data
	s.phase_time += frame.dt
	audio.play_music(frame.audio, s.hooks.music, 7)
	ctx := frame.ui
	playing := s.phase == .Playing

	// Losing focus pauses the round, so alt-tab never costs a life.
	if playing && !frame.window_focused {
		set_phase(s, .Paused)
		playing = false
	}
	if frame.focused && ui.back_pressed(ctx) && s.phase_time > 0.05 {
		#partial switch s.phase {
		case .Playing:
			set_phase(s, .Paused)
			playing = false
		case .Paused:
			set_phase(s, .Playing)
			playing = true
		}
	}

	status := Round_Status.Playing
	if s.hooks.step != nil {
		status = s.hooks.step(s.hooks.data, frame, playing)
	}
	if playing {
		s.elapsed += frame.dt
		switch status {
		case .Playing:
		case .Won:
			finish(s, frame, .Won)
		case .Lost:
			finish(s, frame, .Lost)
		}
	}
	if !frame.visible {
		return
	}
	switch s.phase {
	case .Intro:
		shell_intro(s, frame)
	case .Paused:
		shell_pause(s, frame)
	case .Finished:
		shell_results(s, frame)
	case .Playing:
	}
}

@(private)
shell_intro :: proc(s: ^Minigame_Shell, frame: ^Frame) {
	ctx := frame.ui
	ui.dim(ctx, frame.canvas, 0.55)
	box := ui.center(frame.canvas, 520, 330)
	inner := ui.panel(ctx, box, s.info.title)
	ui.label(ctx, ui.cut_top(&inner, 24), s.info.genre, .Body, ctx.theme.palette.focus)
	ui.cut_top(&inner, 4)
	ui.paragraph(ctx, ui.cut_top(&inner, 70), s.info.tagline, .Body)
	ui.label(ctx, ui.cut_top(&inner, 22), "Comandi", .Body, ctx.theme.palette.text_dim)
	ui.paragraph(ctx, ui.cut_top(&inner, 80), s.info.controls, .Small)
	if s.config.challenge {
		ui.label(ctx, ui.cut_top(&inner, 22), "Sfida della run: un solo tentativo.", .Small, ctx.theme.palette.warning)
	}
	buttons := ui.cut_bottom(&inner, 40)
	if ui.button(ctx, ui.column(buttons, 2, 0, 12), "Inizia", primary = true) ||
	   (frame.focused && ui.confirm_pressed(ctx) && ctx.focus < 0) {
		audio.play(frame.audio, .Confirm)
		set_phase(s, .Playing)
	}
	if ui.button(ctx, ui.column(buttons, 2, 1, 12), "Esci") {
		audio.play(frame.audio, .Back)
		leave(s, frame)
	}
}

@(private)
shell_pause :: proc(s: ^Minigame_Shell, frame: ^Frame) {
	ctx := frame.ui
	ui.dim(ctx, frame.canvas, 0.6)
	box := ui.center(frame.canvas, 360, 260)
	inner := ui.panel(ctx, box, "Pausa")
	rows := 3 if !s.config.challenge else 2
	area := ui.cut_top(&inner, f32(rows)*48)
	index := 0
	if ui.button(ctx, ui.row(area, rows, index, 8), "Riprendi", primary = true) {
		audio.play(frame.audio, .Confirm)
		set_phase(s, .Playing)
	}
	index += 1
	if !s.config.challenge {
		if ui.button(ctx, ui.row(area, rows, index, 8), "Ricomincia") {
			audio.play(frame.audio, .Confirm)
			shell_restart(s)
			set_phase(s, .Playing)
		}
		index += 1
	}
	if ui.button(ctx, ui.row(area, rows, index, 8), "Abbandona") {
		audio.play(frame.audio, .Back)
		leave(s, frame)
	}
	ui.label(ctx, ui.cut_top(&inner, 30), fmt.tprintf("Tempo %s", format_time(s.elapsed)), .Small,
		ctx.theme.palette.text_dim, .Center)
}

@(private)
shell_results :: proc(s: ^Minigame_Shell, frame: ^Frame) {
	ctx := frame.ui
	p := ctx.theme.palette
	ui.dim(ctx, frame.canvas, min(s.phase_time*2, 0.65))
	box := ui.center(frame.canvas, 440, 300)
	title := "Vittoria!" if s.result.outcome == .Won else ("Sconfitta" if s.result.outcome == .Lost else "Abbandonata")
	inner := ui.panel(ctx, box, title)
	stars_row := ui.cut_top(&inner, 56)
	shown := s.result.stars
	for i in 0..<3 {
		filled := u8(i) < shown && s.phase_time > 0.25 + f32(i)*0.2
		cell := ui.centered_item(stars_row, 3, i, 50, 16)
		ui.star(ctx, cell, p.focus if filled else p.button)
	}
	ui.label(ctx, ui.cut_top(&inner, 30), fmt.tprintf("Punteggio  %d", s.result.score), .Large, p.text, .Center)
	rec := record_get(frame.profile, s.info.id) if frame.profile != nil else Record{}
	best_text := "Nuovo record!" if s.new_best else fmt.tprintf("Record  %d", rec.best_score)
	ui.label(ctx, ui.cut_top(&inner, 24), best_text, .Body, p.success if s.new_best else p.text_dim, .Center)
	ui.label(ctx, ui.cut_top(&inner, 22), fmt.tprintf("Tempo  %s", format_time(s.result.elapsed)), .Small, p.text_dim, .Center)
	buttons := ui.cut_bottom(&inner, 40)
	if s.config.challenge {
		if ui.button(ctx, buttons, "Continua la run", primary = true) || (ui.confirm_pressed(ctx) && ctx.focus < 0 && s.phase_time > 0.4) {
			audio.play(frame.audio, .Confirm)
			leave(s, frame)
		}
		return
	}
	if ui.button(ctx, ui.column(buttons, 2, 0, 12), "Riprova", primary = true) {
		audio.play(frame.audio, .Confirm)
		shell_restart(s)
		set_phase(s, .Playing)
	}
	if ui.button(ctx, ui.column(buttons, 2, 1, 12), "Esci") {
		audio.play(frame.audio, .Back)
		leave(s, frame)
	}
}

@(private)
shell_draw :: proc(data: rawptr, frame: ^Frame) {
	s := cast(^Minigame_Shell)data
	if s.hooks.draw != nil {
		s.hooks.draw(s.hooks.data, frame)
	}
}

format_time :: proc(seconds: f32) -> string {
	total := int(math.floor(max(seconds, 0)))
	tenths := int(math.floor(max(seconds, 0)*10)) % 10
	return fmt.tprintf("%d:%02d.%d", total/60, total%60, tenths)
}

// Shell state for tests and for hosts embedding minigames (challenges).
shell_of :: proc(scene: ^Scene) -> ^Minigame_Shell {
	if scene == nil || scene.update != shell_update {
		return nil
	}
	return cast(^Minigame_Shell)scene.data
}

// Starts play immediately (skips the intro), used by smoke tests.
shell_skip_intro :: proc(s: ^Minigame_Shell) {
	set_phase(s, .Playing)
}
