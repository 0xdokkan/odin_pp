package host

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import app "../../app"
import view "../../view"
import audio "../audio"
import timing "../timing"
import save "../save"
import gui "../ui"

Config :: struct {
	window:       app.Window_Config,
	profile_path: string, // empty disables persistence
	enable_audio: bool,
	// Bars around the canvas when the window aspect differs; zero means black.
	letterbox_color: rl.Color,
	// Automation: report the window as focused even in the background, so
	// focus-loss pauses do not interfere with scripted captures.
	force_focus:     bool,
}

Host :: struct {
	window:        app.Window,
	stack:         Stack,
	commands:      Commands,
	theme:         gui.Theme,
	ui:            ^gui.Context,
	audio:         ^audio.Bank,
	profile:       Profile,
	profile_path:  string,
	profile_status: save.Load_Status,
	save_enabled: bool,
	time:          f64,
	frame_index:   u64,
	fade:          f32, // 1 = black, fades to 0 after scene changes
	debug:         bool,
	frame_ms:      [120]f32,
	frame_cursor:  int,
	last_settings: Settings,
	letterbox:     rl.Color,
	force_focus:   bool,
}

// Opens the window and the shared services. The host is heap-allocated
// because the UI command buffer and the scene stack are large.
create :: proc(config: Config) -> (^Host, bool) {
	h := new(Host)
	window, ok := app.open(config.window)
	if !ok {
		free(h)
		return nil, false
	}
	h.window = window
	h.theme = gui.default_theme()
	gui.load_fonts(&h.theme)
	h.ui = gui.create(&h.theme)
	// Owned copy: callers often build the path in the per-frame temp allocator.
	h.profile_path = strings.clone(config.profile_path)
	h.letterbox = config.letterbox_color if config.letterbox_color.a != 0 else rl.BLACK
	h.force_focus = config.force_focus
	load_persistent_profile(h)
	if config.enable_audio {
		h.audio = audio.bank_create()
	}
	apply_settings(h)
	return h, true
}

destroy :: proc(h: ^Host) {
	if h == nil {
		return
	}
	destroy_all(&h.stack)
	save_profile(h)
	profile_destroy(&h.profile)
	delete(h.profile_path)
	audio.bank_destroy(h.audio)
	gui.destroy(h.ui)
	gui.unload_fonts(&h.theme)
	app.close(&h.window)
	free(h)
}

save_profile :: proc(h: ^Host) -> bool {
	if h == nil || !h.save_enabled || h.profile_path == "" {
		return false
	}
	return profile_save(h.profile_path, &h.profile)
}

@(private)
load_persistent_profile :: proc(h: ^Host) {
	h.profile = profile_default()
	h.profile_status = .Missing
	h.save_enabled = false
	if h.profile_path == "" { return }
	h.profile, h.profile_status = profile_load(h.profile_path)
	// Future schemas and unreadable/corrupt files are preserved for recovery.
	h.save_enabled = h.profile_status == .Loaded || h.profile_status == .Missing
}

@(private)
apply_settings :: proc(h: ^Host) {
	s := h.profile.settings
	if h.audio != nil {
		audio.set_master_volume(h.audio, s.master_volume)
		h.audio.sfx_volume = s.sfx_volume
		h.audio.music_volume = s.music_volume
		audio.set_muted(h.audio, s.muted)
	}
	h.last_settings = s
}

// Saves the profile from inside a scene, e.g. after a round updates records.
persist_profile :: proc(frame: ^Frame) -> bool {
	if frame == nil || !frame.save_enabled || frame.profile == nil || frame.profile_path == "" {
		return false
	}
	return profile_save(frame.profile_path, frame.profile)
}

push_scene :: proc(h: ^Host, scene: Scene) -> bool {
	return stack_push(&h.stack, scene)
}

// Runs until the stack empties, a scene quits or the window closes.
run :: proc(h: ^Host) {
	for !app.should_close(&h.window) {
		if !step(h) {
			break
		}
	}
}

// One frame. Exposed so tools (smoke tests) can drive the loop themselves.
step :: proc(h: ^Host) -> bool {
	free_all(context.temp_allocator)
	app.update_window_controls(&h.window)
	if rl.IsKeyPressed(.F9) {
		h.debug = !h.debug
	}
	if h.profile.settings != h.last_settings {
		apply_settings(h)
	}
	audio.bank_update(h.audio)

	dt := min(rl.GetFrameTime(), timing.MAX_FRAME_DELTA)
	h.time += f64(dt)
	h.frame_index += 1
	h.frame_ms[h.frame_cursor] = rl.GetFrameTime() * 1000
	h.frame_cursor = (h.frame_cursor + 1) % len(h.frame_ms)

	mouse, inside := app.mouse_canvas_position(&h.window)
	canvas := rl.Rectangle{0, 0, f32(h.window.config.canvas_width), f32(h.window.config.canvas_height)}
	window_focused := h.force_focus || rl.IsWindowFocused()
	frame := Frame{
		dt             = dt,
		time           = h.time,
		index          = h.frame_index,
		canvas         = canvas,
		mouse          = {mouse.x, mouse.y},
		mouse_inside   = inside,
		window_focused = window_focused,
		ui             = h.ui,
		theme          = &h.theme,
		audio          = h.audio,
		window         = &h.window,
		profile        = &h.profile,
		profile_path   = h.profile_path,
		profile_status = h.profile_status,
		save_enabled   = h.save_enabled,
		commands       = &h.commands,
	}

	gui.begin_frame(h.ui, frame.mouse, inside, dt)
	first_update := update_start(&h.stack)
	first_draw := draw_start(&h.stack)
	count := h.stack.count
	for i in first_update..<count {
		s := &h.stack.items[i]
		frame.focused = i == count-1 && window_focused
		frame.visible = i >= first_draw
		if s.update != nil {
			s.update(s.data, &frame)
		}
	}
	gui.end(h.ui)

	clear := rl.BLACK
	if first_draw < count {
		clear = h.stack.items[first_draw].clear_color
	}
	app.begin_canvas(&h.window, clear)
	for i in first_draw..<count {
		s := &h.stack.items[i]
		frame.focused = i == count-1 && window_focused
		frame.visible = true
		if s.draw != nil {
			s.draw(s.data, &frame)
		}
	}
	gui.render(h.ui)
	if h.fade > 0 {
		rl.DrawRectangleRec(canvas, rl.Color{0, 0, 0, u8(255 * min(h.fade, 1))})
		h.fade = max(h.fade-dt*4, 0)
	}
	if h.debug || h.profile.settings.show_fps {
		draw_debug(h, canvas, h.debug)
	}
	present_data := Present_Data{host = h, frame = &frame, first = first_draw, count = count}
	app.present(&h.window, h.letterbox, present_window_overlays, &present_data)
	for i in first_draw..<count {
		s := &h.stack.items[i]
		if s.after_present != nil {
			s.after_present(s.data, &frame)
		}
	}

	changed := h.commands.count > 0
	running := apply(&h.stack, &h.commands, &frame)
	if changed {
		h.fade = 0.6
	}
	return running
}

@(private)
Present_Data :: struct {
	host:  ^Host,
	frame: ^Frame,
	first: int,
	count: int,
}

@(private)
present_window_overlays :: proc(window: ^app.Window, data: rawptr) {
	p := cast(^Present_Data)data
	for i in p.first..<p.count {
		s := &p.host.stack.items[i]
		if s.draw_window != nil {
			s.draw_window(s.data, p.frame)
		}
	}
}

@(private)
draw_debug :: proc(h: ^Host, canvas: rl.Rectangle, full: bool) {
	fps := rl.GetFPS()
	gui.draw_text(&h.theme, fmt.tprintf("%d FPS", fps), {canvas.width - 90, 6}, .Small, rl.Color{160, 255, 160, 255})
	if !full {
		return
	}
	panel := rl.Rectangle{8, canvas.height - 150, 260, 142}
	rl.DrawRectangleRec(panel, rl.Color{0, 0, 0, 180})
	y := panel.y + 6
	gui.draw_text(&h.theme, fmt.tprintf("frame %d  scale %s", h.frame_index, view.scale_mode_name(h.window.scale_mode)),
		{panel.x + 6, y}, .Small, rl.WHITE, false)
	y += 16
	for i in 0..<h.stack.count {
		s := h.stack.items[i]
		flags := fmt.tprintf("%s%s", "O" if s.opaque else "-", "M" if s.modal else "-")
		gui.draw_text(&h.theme, fmt.tprintf("[%d] %s %s", i, flags, s.name), {panel.x + 6, y}, .Small, rl.WHITE, false)
		y += 14
	}
	// Frame-time graph; the line marks 16.7 ms.
	graph := rl.Rectangle{panel.x + 6, panel.y + panel.height - 40, 240, 34}
	rl.DrawRectangleLinesEx(graph, 1, rl.Color{120, 120, 120, 200})
	limit := graph.y + graph.height - 16.7/33.4*graph.height
	rl.DrawLineV({graph.x, limit}, {graph.x + graph.width, limit}, rl.Color{255, 200, 80, 160})
	for i in 0..<len(h.frame_ms) {
		ms := h.frame_ms[(h.frame_cursor+i) % len(h.frame_ms)]
		bar := min(ms/33.4, 1) * graph.height
		color := rl.Color{120, 220, 120, 220} if ms < 17.5 else rl.Color{240, 100, 90, 220}
		rl.DrawRectangleRec({graph.x + f32(i)*2, graph.y + graph.height - bar, 2, bar}, color)
	}
}
