package main

import "core:fmt"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import audio "engine/audio"
import gfx "engine/gfx"
import host "engine/host"
import rng "engine/rng"
import save "engine/save"
import ui "engine/ui"
import render "render"

// Options consumed before the roguelike parser sees the command line.
Launch_Options :: struct {
	run:        bool,   // --run: straight into the roguelike
	minigame:   string, // --minigame=<id>: open one minigame on top of the menu
	// --smoke-menu: capture odin_pp_menu.png after a few frames and quit.
	smoke_menu: bool,
	// --smoke-minigame=<id>: play <id> without the intro, capture
	// odin_pp_<id>.png after a few seconds and quit.
	smoke_minigame: string,
}

split_launch_arguments :: proc(args: []string) -> (Launch_Options, [dynamic]string) {
	launch := Launch_Options{}
	rest := make([dynamic]string, 0, len(args))
	for arg in args {
		switch {
		case arg == "--run":
			launch.run = true
		case strings.has_prefix(arg, "--minigame="):
			launch.minigame = arg[len("--minigame="):]
		case arg == "--smoke-menu":
			launch.smoke_menu = true
		case strings.has_prefix(arg, "--smoke-minigame="):
			launch.smoke_minigame = arg[len("--smoke-minigame="):]
			launch.minigame = launch.smoke_minigame
		case:
			append(&rest, arg)
		}
	}
	return launch, rest
}

profile_path :: proc() -> string {
	return save.user_file("odin_pp", "profilo.json", context.temp_allocator)
}

run_launcher :: proc(options: Runtime_Options, launch: Launch_Options) {
	rs_config := roguelike_session_new()
	rs_config.options = options
	window := roguelike_window_config(rs_config)
	roguelike_destroy(rs_config)
	window.title = "Odin PP"
	h, ok := host.create(host.Config{
		window          = window,
		profile_path    = profile_path() if launch.smoke_minigame == "" && !launch.smoke_menu else "",
		enable_audio    = launch.smoke_minigame == "" && !launch.smoke_menu,
		letterbox_color = render.LETTERBOX_COLOR,
		force_focus     = launch.smoke_minigame != "",
	})
	if !ok {
		fmt.eprintln("could not open the window")
		return
	}
	defer host.destroy(h)
	menu := launcher_create(options)
	menu.smoke = launch.smoke_menu
	host.push_scene(h, launcher_scene(menu))
	if launch.minigame != "" {
		index := minigame_index_by_id(launch.minigame)
		if info, found := minigame_info(index); found {
			config := launcher_cli_minigame_config(options)
			scene := minigame_capture_scene(index,config) if launch.smoke_minigame != "" else info.create(config)
			if launch.smoke_minigame != "" {
				if shell := host.shell_of(&scene); shell != nil {
					host.shell_skip_intro(shell)
				}
				scene.after_present = minigame_smoke_after_present
			}
			host.push_scene(h, scene)
		} else {
			fmt.eprintf("unknown minigame: %s\n", launch.minigame)
		}
	}
	host.run(h)
}

Launcher :: struct {
	options:    Runtime_Options,
	seeds:      rng.Rng,
	time:       f32,
	status:     string,
	status_ttl: f32,
	focus_set:  bool,
	smoke:      bool,
	frames:     int,
}

launcher_create :: proc(options: Runtime_Options) -> ^Launcher {
	l := new(Launcher)
	l.options = options
	l.seeds = rng.create(u64(time.now()._nsec) ~ options.seed)
	return l
}

launcher_scene :: proc(l: ^Launcher) -> host.Scene {
	return host.Scene{
		name        = "menu",
		data        = l,
		opaque      = true,
		modal       = true,
		clear_color = rl.Color{12, 13, 19, 255},
		update      = launcher_update,
		draw        = launcher_draw,
		resume      = launcher_resume,
		after_present = launcher_after_present,
		destroy     = proc(data: rawptr) {
			l := cast(^Launcher)data
			delete(l.status)
			free(l)
		},
	}
}

launcher_minigame_config :: proc(l: ^Launcher) -> host.Minigame_Config {
	return host.Minigame_Config{seed = rng.next_u64(&l.seeds)}
}

// Command-line launches and captures must reproduce the requested seed. The
// interactive menu keeps its independent stream for subsequent new rounds.
launcher_cli_minigame_config :: proc(options: Runtime_Options) -> host.Minigame_Config {
	return {seed = options.seed}
}

@(private = "file")
launcher_resume :: proc(data: rawptr, frame: ^host.Frame, from: string, result: Maybe(host.Result)) {
	l := cast(^Launcher)data
	l.focus_set = false
	// The minigame shell already folded the result into the records.
	host.persist_profile(frame)
	if r, has := result.?; has && r.outcome == .Won {
		delete(l.status)
		l.status = fmt.aprintf("%s completato: %d punti", from, r.score)
		l.status_ttl = 4
	}
}

@(private = "file")
launcher_after_present :: proc(data: rawptr, frame: ^host.Frame) {
	l := cast(^Launcher)data
	if !l.smoke {
		return
	}
	l.frames += 1
	if l.frames == 30 {
		rl.TakeScreenshot("odin_pp_menu.png")
		host.quit(frame)
	}
}

// Three seconds of play, then a capture named after the minigame.
@(private = "file")
minigame_smoke_after_present :: proc(data: rawptr, frame: ^host.Frame) {
	if frame.index == 180 {
		shell := cast(^host.Minigame_Shell)data
		rl.TakeScreenshot(fmt.ctprintf("odin_pp_%s.png", shell.info.id))
		host.quit(frame)
	}
}

@(private = "file")
launcher_start_run :: proc(l: ^Launcher, frame: ^host.Frame, mechanics_lab := false) {
	rs := roguelike_session_new()
	rs.options = l.options
	rs.options.seed = rng.next_u64(&l.seeds)
	rs.options.mechanics_lab = mechanics_lab
	if mechanics_lab { rs.options.tactical.enabled = true }
	rs.from_launcher = true
	if roguelike_prepare(rs) != .Ready || roguelike_attach(rs, frame.window) != .Ready {
		roguelike_destroy(rs)
		delete(l.status)
		l.status = fmt.aprintf("Impossibile preparare la run.")
		l.status_ttl = 3
		return
	}
	audio.stop_music(frame.audio)
	host.push(frame, roguelike_scene(rs))
}

@(private = "file")
launcher_update :: proc(data: rawptr, frame: ^host.Frame) {
	l := cast(^Launcher)data
	l.time += frame.dt
	l.status_ttl = max(l.status_ttl-frame.dt, 0)
	if !frame.visible {
		return
	}
	audio.play_music(frame.audio, .Menu, 3)
	ctx := frame.ui
	p := ctx.theme.palette
	canvas := frame.canvas
	if !l.focus_set && frame.focused {
		ui.set_focus(ctx, 0)
		ctx.keyboard_mode = false
		l.focus_set = true
	}

	area := ui.shrink_xy(canvas, 32, 24)
	ui.cut_top(&area, 80) // title, drawn in launcher_draw
	ui.cut_bottom(&area, 26) // navigation legend
	status := ui.cut_bottom(&area, 20)
	bottom := ui.cut_bottom(&area, 38)
	ui.cut_bottom(&area, 12)

	// Give the main game one clear action. The catalogue remains a compact
	// list, with complete short descriptions instead of clipped card copy.
	left := ui.cut_left(&area, 304)
	ui.cut_left(&area, 24)
	run := ui.panel(ctx, left)
	ui.label(ctx, ui.cut_top(&run, 22), "L'ASCESA", .Small, p.focus)
	ui.label(ctx, ui.cut_top(&run, 48), "La Rotta", .Title, p.text)
	ui.cut_top(&run, 8)
	ui.paragraph(ctx, ui.cut_top(&run, 76), "Carte, dadi e reliquie.\nSette livelli per raggiungere\nil cuore della torre.", .Body, p.text_dim)
	start := ui.cut_bottom(&run, 42)
	ui.cut_bottom(&run, 8)
	lab := ui.cut_bottom(&run, 32)
	ui.cut_bottom(&run, 8)
	ui.paragraph(ctx, run, "Leggi gli intenti. Colpisci sul\nsecondo: la torre nasconde\nsegreti per chi osa.", .Small, p.text_dim)
	if ui.button(ctx, start, "Inizia l'ascesa", primary = true) {
		audio.play(frame.audio, .Confirm)
		launcher_start_run(l, frame)
	}
	// A sandbox for trying new mechanics: an open arena, endless enemies.
	if ui.button(ctx, lab, "Prova meccaniche") {
		audio.play(frame.audio, .Confirm)
		launcher_start_run(l, frame, true)
	}

	count := MINIGAME_COUNT
	heading := ui.cut_top(&area, 28)
	ui.label(ctx, heading, "LE PROVE DELLA TORRE", .Body, p.text)
	ui.label(ctx, heading, "Pratica libera", .Small, p.text_dim, .Right)
	ui.cut_top(&area, 4)
	if count == 0 {
		ui.panel(ctx, area)
		ui.label(ctx, ui.shrink(area, 40), "Nessun minigioco registrato.", .Body, p.text_dim, .Center)
	}
	for i in 0..<count {
		info, ok := minigame_info(i)
		if !ok {
			continue
		}
		cell := ui.row(area, count, i, 4)
		rec := host.record_get(frame.profile, info.id)
		if launcher_trial_row(ctx, cell, info, rec) {
			audio.play(frame.audio, .Confirm)
			host.push(frame, info.create(launcher_minigame_config(l)))
		}
	}

	// Bottom bar: settings and quit.
	quit_rect := ui.cut_right(&bottom, 92)
	ui.cut_right(&bottom, 12)
	settings_rect := ui.cut_right(&bottom, 144)
	if ui.button(ctx, settings_rect, "Impostazioni") {
		audio.play(frame.audio, .Confirm)
		host.push(frame, settings_scene())
	}
	if ui.button(ctx, quit_rect, "Esci") {
		host.quit(frame)
	}
	if l.status_ttl > 0 {
		ui.label(ctx, status, l.status, .Small, p.warning, .Left)
	}
}

@(private = "file")
launcher_trial_blurb :: proc(id: string) -> string {
	switch id {
	case "platform2d": return "Platform 2D  /  Salti e braci"
	case "platform3d": return "Platform 3D  /  Isole sospese"
	case "arena": return "Arena  /  Resisti alle ondate"
	case "fps": return "Prima persona  /  Rune e ombre"
	case "puzzle": return "Enigmi  /  Pietre e sigilli"
	case "ring": return "Duello 3D  /  Parate e prese"
	}
	return "Una prova nella torre"
}

@(private = "file")
launcher_trial_row :: proc(ctx: ^ui.Context, bounds: ui.Rect, info: host.Minigame_Info,
	record: host.Record) -> bool {
	s := ui.interact(ctx, bounds)
	p := ctx.theme.palette
	active := s.hovered || s.focused
	ui.fill(ctx, bounds, p.panel_alt if active else p.panel)
	ui.fill(ctx, {bounds.x, bounds.y+bounds.height-1, bounds.width, 1}, p.border)
	ui.fill(ctx, {bounds.x, bounds.y+8, 2, bounds.height-16}, p.focus if active else p.border)
	if s.focused && ctx.keyboard_mode {
		ui.outline(ctx, bounds, p.focus, 1)
	}
	inner := ui.shrink_xy(bounds, 12, 3)
	result := ui.cut_right(&inner, 96)
	ui.label(ctx, ui.cut_top(&inner, 20), info.title, .Body, p.text)
	ui.label(ctx, inner, launcher_trial_blurb(info.id), .Small, p.text_dim)
	if record.plays > 0 {
		ui.label(ctx, ui.cut_top(&result, 20), fmt.tprintf("%d", record.best_score), .Body, p.text, .Right)
		ui.label(ctx, result, fmt.tprintf("%d / 3 sigilli", record.best_stars), .Small, p.warning, .Right)
	} else {
		ui.label(ctx, result, "Entra  >", .Small, p.focus if active else p.text_dim, .Right)
	}
	return s.clicked
}

@(private = "file")
launcher_draw :: proc(data: rawptr, frame: ^host.Frame) {
	l := cast(^Launcher)data
	w := frame.canvas.width
	h := frame.canvas.height
	p := frame.theme.palette
	gfx.draw_vertical_gradient(frame.canvas, rl.Color{12, 18, 29, 255}, p.background)
	// Recessed pillars echo the arena's block geometry without covering the
	// controls with moving particles or another layer of decorative cards.
	for i in 0..<7 {
		x := f32(i)*w/6 - 34
		rl.DrawRectangleRec({x, 0, 68, h}, rl.Color{16, 23, 34, 255})
		rl.DrawRectangleRec({x+6, 0, 2, h}, rl.Color{30, 43, 58, 255})
		for j in 0..<8 {
			rl.DrawRectangleRec({x, f32(j)*76 + f32(i%2)*38, 68, 2}, p.background)
		}
	}
	gfx.draw_stars(w, h*0.6, 24, l.time*0.4)
	gfx.draw_vignette(w, h, 0.35)
	ui.draw_text(frame.theme, "ODIN PP", {32, 24}, .Title, p.text)
	ui.draw_text(frame.theme, "Ogni stanza, una scelta. Ogni prova, una nuova strada.", {34, 72}, .Body, p.text_dim)
	rl.DrawRectangleRec({32, 99, w-64, 1}, p.border)
	ui.draw_text(frame.theme, "Mouse / frecce / pad: scegli    Invio: conferma", {32, h-24}, .Small, p.text_dim, false)
	ui.draw_text_fit(frame.theme, "F11  Schermo intero", {w-230, h-27, 198, 20}, .Small, p.text_dim, .Right)
}

// Settings: a modal panel over the menu, saved when closed.
@(private = "file")
Settings_Panel :: struct {
	opened: f32,
}

settings_scene :: proc() -> host.Scene {
	return host.Scene{
		name    = "settings",
		data    = new(Settings_Panel),
		modal   = true,
		update  = settings_update,
		destroy = proc(data: rawptr) {
			free(data)
		},
	}
}

@(private = "file")
settings_update :: proc(data: rawptr, frame: ^host.Frame) {
	panel := cast(^Settings_Panel)data
	panel.opened += frame.dt
	ctx := frame.ui
	s := &frame.profile.settings
	ui.dim(ctx, frame.canvas, 0.6)
	box := ui.center(frame.canvas, 460, 400)
	inner := ui.panel(ctx, box, "Impostazioni")
	rows := ui.cut_top(&inner, 7*40)
	ui.slider(ctx, ui.row(rows, 7, 0, 6), "Volume generale", &s.master_volume, 0, 1)
	ui.slider(ctx, ui.row(rows, 7, 1, 6), "Musica", &s.music_volume, 0, 1)
	if ui.slider(ctx, ui.row(rows, 7, 2, 6), "Effetti", &s.sfx_volume, 0, 1) {
		audio.play(frame.audio, .Blip)
	}
	ui.toggle(ctx, ui.row(rows, 7, 3, 6), "Audio disattivato", &s.muted)
	ui.slider(ctx, ui.row(rows, 7, 4, 6), "Scuotimento", &s.screen_shake, 0, 1)
	ui.slider(ctx, ui.row(rows, 7, 5, 6), "Sensibilità mouse", &s.mouse_sensitivity, 0.25, 3)
	ui.toggle(ctx, ui.row(rows, 7, 6, 6), "Mostra FPS", &s.show_fps)
	close := ui.cut_bottom(&inner, 40)
	if ui.button(ctx, close, "Chiudi", primary = true) || (panel.opened > 0.1 && ui.back_pressed(ctx)) {
		audio.play(frame.audio, .Back)
		host.persist_profile(frame)
		host.pop(frame)
	}
}
