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
	difficulty: int,
	// --smoke-menu: capture odin_pp_menu.png after a few frames and quit.
	smoke_menu: bool,
	// --smoke-minigame=<id>: play <id> without the intro, capture
	// odin_pp_<id>.png after a few seconds and quit.
	smoke_minigame: string,
}

split_launch_arguments :: proc(args: []string) -> (Launch_Options, [dynamic]string) {
	launch := Launch_Options{difficulty = 1}
	rest := make([dynamic]string, 0, len(args))
	for arg in args {
		switch {
		case arg == "--run":
			launch.run = true
		case strings.has_prefix(arg, "--minigame="):
			launch.minigame = arg[len("--minigame="):]
		case arg == "--easy":
			launch.difficulty = 0
		case arg == "--hard":
			launch.difficulty = 2
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
		profile_path    = profile_path(),
		enable_audio    = launch.smoke_minigame == "" && !launch.smoke_menu,
		letterbox_color = render.LETTERBOX_COLOR,
		force_focus     = launch.smoke_minigame != "",
	})
	if !ok {
		fmt.eprintln("could not open the window")
		return
	}
	defer host.destroy(h)
	menu := launcher_create(options, launch.difficulty)
	menu.smoke = launch.smoke_menu
	host.push_scene(h, launcher_scene(menu))
	if launch.minigame != "" {
		index := minigame_index_by_id(launch.minigame)
		if info, found := minigame_info(index); found {
			scene := info.create(launcher_minigame_config(menu))
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
	difficulty: int,
	seeds:      rng.Rng,
	time:       f32,
	status:     string,
	status_ttl: f32,
	focus_set:  bool,
	smoke:      bool,
	frames:     int,
}

launcher_create :: proc(options: Runtime_Options, difficulty: int) -> ^Launcher {
	l := new(Launcher)
	l.options = options
	l.difficulty = clamp(difficulty, 0, 2)
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
			free(data)
		},
	}
}

launcher_minigame_config :: proc(l: ^Launcher) -> host.Minigame_Config {
	return host.Minigame_Config{seed = rng.next_u64(&l.seeds), difficulty = l.difficulty}
}

@(private = "file")
DIFFICULTY_NAMES :: [3]string{"Facile", "Normale", "Difficile"}

@(private = "file")
launcher_resume :: proc(data: rawptr, frame: ^host.Frame, from: string, result: Maybe(host.Result)) {
	l := cast(^Launcher)data
	l.focus_set = false
	// The minigame shell already folded the result into the records.
	host.persist_profile(frame)
	if r, has := result.?; has && r.outcome == .Won {
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
launcher_start_run :: proc(l: ^Launcher, frame: ^host.Frame) {
	rs := roguelike_session_new()
	rs.options = l.options
	rs.options.seed = rng.next_u64(&l.seeds)
	rs.from_launcher = true
	if roguelike_prepare(rs) != .Ready || roguelike_attach(rs, frame.window) != .Ready {
		roguelike_destroy(rs)
		l.status = "Impossibile preparare la run."
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
	if !l.focus_set {
		ui.set_focus(ctx, 0)
		ctx.keyboard_mode = false
		l.focus_set = true
	}

	area := ui.shrink_xy(canvas, 36, 24)
	ui.cut_top(&area, 96) // title, drawn in launcher_draw
	bottom := ui.cut_bottom(&area, 44)
	ui.cut_bottom(&area, 14)

	// The run: a large tile on the left.
	left := ui.cut_left(&area, 330)
	ui.cut_left(&area, 20)
	run_text := "Sette livelli di stanze procedurali fino al Demolitore.\n\n- Mazzo di carte, dadi e reliquie\n- Nemici con intenti dichiarati\n- Negozi, riposi, eventi e tesori\n- Sfide dei minigiochi nelle stanze ripulite: vinci oro extra\n\nF10 durante la run torna a questo menu."
	if ui.tile(ctx, left, "La Rotta", run_text, p.accent) {
		audio.play(frame.audio, .Confirm)
		launcher_start_run(l, frame)
	}

	// Minigames: a grid on the right.
	count := MINIGAME_COUNT
	if count == 0 {
		ui.panel(ctx, area, "Minigiochi")
		ui.label(ctx, ui.shrink(area, 40), "Nessun minigioco registrato.", .Body, p.text_dim, .Center)
	}
	columns := 2
	rows := max((count+columns-1)/columns, 1)
	for i in 0..<count {
		info, ok := minigame_info(i)
		if !ok {
			continue
		}
		cell := ui.cell(area, columns, rows, i, 14)
		rec := host.record_get(frame.profile, info.id)
		stars := ""
		switch rec.best_stars {
		case 1:
			stars = "*"
		case 2:
			stars = "**"
		case 3:
			stars = "***"
		}
		// One line of description: the tile also carries title, genre and record.
		blurb := ui.ellipsize(ctx.theme, first_sentence(info.tagline), cell.width - 24, .Small)
		subtitle := fmt.tprintf("%s\n%s", info.genre, blurb)
		if rec.plays > 0 {
			subtitle = fmt.tprintf("%s  -  record %d %s\n%s", info.genre, rec.best_score, stars, blurb)
		}
		if ui.tile(ctx, cell, info.title, subtitle, info.accent) {
			audio.play(frame.audio, .Confirm)
			host.push(frame, info.create(launcher_minigame_config(l)))
		}
	}

	// Bottom bar: difficulty, settings, quit.
	diff_area := ui.cut_left(&bottom, 420)
	ui.label(ctx, ui.cut_left(&diff_area, 110), "Difficoltà", .Body, p.text_dim)
	names := DIFFICULTY_NAMES
	for i in 0..<3 {
		r := ui.column(diff_area, 3, i, 8)
		if ui.button(ctx, r, names[i], primary = l.difficulty == i) {
			l.difficulty = i
			audio.play(frame.audio, .Blip)
		}
	}
	quit_rect := ui.cut_right(&bottom, 120)
	ui.cut_right(&bottom, 12)
	settings_rect := ui.cut_right(&bottom, 160)
	if ui.button(ctx, settings_rect, "Impostazioni") {
		audio.play(frame.audio, .Confirm)
		host.push(frame, settings_scene())
	}
	if ui.button(ctx, quit_rect, "Esci") {
		host.quit(frame)
	}
	if l.status_ttl > 0 {
		ui.label(ctx, bottom, l.status, .Small, p.warning, .Center)
	}
}

// The menu tile shows the opening sentence; the intro card shows the rest.
@(private = "file")
first_sentence :: proc(text: string) -> string {
	for i in 0..<len(text) {
		if (text[i] == '.' || text[i] == '!' || text[i] == '?') && (i+1 == len(text) || text[i+1] == ' ') {
			return text[:i+1]
		}
	}
	return text
}

@(private = "file")
launcher_draw :: proc(data: rawptr, frame: ^host.Frame) {
	l := cast(^Launcher)data
	w := frame.canvas.width
	h := frame.canvas.height
	gfx.draw_vertical_gradient(frame.canvas, rl.Color{18, 16, 30, 255}, rl.Color{44, 20, 28, 255})
	gfx.draw_stars(w, h*0.6, 70, l.time)
	gfx.draw_hills(w, h, h*0.78, 90, l.time*14, rl.Color{30, 24, 40, 255}, 1.3)
	gfx.draw_hills(w, h, h*0.88, 60, l.time*30, rl.Color{20, 16, 26, 255}, 4.1)
	ui.draw_text(frame.theme, "ODIN PP", {36, 22}, .Huge, rl.Color{236, 226, 204, 255})
	ui.draw_text(frame.theme, "Roguelike e minigiochi su un unico engine", {40, 88}, .Body, rl.Color{232, 196, 112, 255})
	ui.draw_text(frame.theme, "Frecce/WASD o pad per scegliere, Invio per confermare  -  F9 diagnostica  -  F11 schermo intero",
		{40, h - 20}, .Small, rl.Color{150, 140, 128, 255}, false)
	gfx.draw_vignette(w, h, 0.45)
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
