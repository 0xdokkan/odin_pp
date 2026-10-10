package host

import "core:testing"
import "core:os"
import save "../save"
import input "../input"
import ui "../ui"

@(test)
test_invalid_profile_cannot_be_overwritten_by_host_or_scene :: proc(t: ^testing.T) {
	dir, dir_error := os.temp_directory(context.temp_allocator)
	testing.expect(t, dir_error == nil)
	path, path_error := os.join_path({dir, "odin-pp-host-protected-profile.json"}, context.temp_allocator)
	testing.expect(t, path_error == nil)
	defer os.remove(path)
	sources := [?]string{
		`{"version":99,"data":{"records":{"ring":{"best_score":81}}}}`,
		`{"version":1,"data":{"records":{"ring":{"best_score":"bad"}}}}`,
	}
	for source, index in sources {
		testing.expect(t, os.write_entire_file(path, source) == nil)
		h := new(Host)
		h.profile_path = path
		load_persistent_profile(h)
		testing.expect_value(t, h.profile_status, save.Load_Status.Wrong_Version if index == 0 else save.Load_Status.Malformed)
		testing.expect(t, !h.save_enabled)
		record_result(&h.profile, Result{minigame = "arena", outcome = .Won, score = 100})
		testing.expect(t, !save_profile(h))
		frame := Frame{profile = &h.profile, profile_path = path, profile_status = h.profile_status, save_enabled = h.save_enabled}
		testing.expect(t, !persist_profile(&frame))
		bytes, err := os.read_entire_file(path, context.temp_allocator)
		testing.expect(t, err == nil)
		testing.expect_value(t, string(bytes), source)
		profile_destroy(&h.profile)
		free(h)
	}
	os.remove(path)
	h := new(Host)
	defer free(h)
	h.profile_path = path
	load_persistent_profile(h)
	defer profile_destroy(&h.profile)
	testing.expect(t, h.save_enabled && h.profile_status == .Missing)
	testing.expect(t, save_profile(h))
}

@(private = "file")
Probe :: struct {
	updates:   int,
	destroyed: ^int,
	resumed:   int,
	last:      Maybe(Result),
	from:      string,
}

@(private = "file")
probe_scene :: proc(name: string, p: ^Probe, opaque := false, modal := false) -> Scene {
	return Scene{
		name = name,
		data = p,
		opaque = opaque,
		modal = modal,
		update = proc(data: rawptr, f: ^Frame) {
			(cast(^Probe)data).updates += 1
		},
		resume = proc(data: rawptr, f: ^Frame, from: string, result: Maybe(Result)) {
			p := cast(^Probe)data
			p.resumed += 1
			p.last = result
			p.from = from
		},
		destroy = proc(data: rawptr) {
			p := cast(^Probe)data
			if p.destroyed != nil {
				p.destroyed^ += 1
			}
		},
	}
}

@(test)
test_modal_and_opaque_ranges :: proc(t: ^testing.T) {
	s: Stack
	a, b, c: Probe
	stack_push(&s, probe_scene("menu", &a, opaque = true))
	stack_push(&s, probe_scene("game", &b, opaque = true, modal = true))
	stack_push(&s, probe_scene("hud", &c))
	testing.expect_value(t, update_start(&s), 1)
	testing.expect_value(t, draw_start(&s), 1)
}

@(test)
test_pop_delivers_result_and_destroys_child :: proc(t: ^testing.T) {
	s: Stack
	destroyed := 0
	parent := Probe{destroyed = &destroyed}
	child := Probe{destroyed = &destroyed}
	stack_push(&s, probe_scene("launcher", &parent))
	stack_push(&s, probe_scene("platform", &child))
	cmds: Commands
	f := Frame{commands = &cmds}
	pop(&f, Result{minigame = "platform", outcome = .Won, score = 42, stars = 2})
	testing.expect(t, apply(&s, &cmds, &f))
	testing.expect_value(t, s.count, 1)
	testing.expect_value(t, destroyed, 1)
	testing.expect_value(t, parent.resumed, 1)
	testing.expect_value(t, parent.from, "platform")
	r, has := parent.last.?
	testing.expect(t, has && r.score == 42 && r.stars == 2)
}

@(test)
test_replace_and_quit :: proc(t: ^testing.T) {
	s: Stack
	destroyed := 0
	a := Probe{destroyed = &destroyed}
	b := Probe{destroyed = &destroyed}
	stack_push(&s, probe_scene("a", &a))
	cmds: Commands
	f := Frame{commands = &cmds}
	replace(&f, probe_scene("b", &b))
	testing.expect(t, apply(&s, &cmds, &f))
	testing.expect_value(t, stack_top(&s).name, "b")
	testing.expect_value(t, destroyed, 1)
	testing.expect_value(t, a.resumed, 0)
	quit(&f)
	testing.expect(t, !apply(&s, &cmds, &f))
	destroy_all(&s)
	testing.expect_value(t, destroyed, 2)
}

@(test)
test_records_keep_best_score_and_stars :: proc(t: ^testing.T) {
	p := profile_default()
	defer profile_destroy(&p)
	testing.expect(t, record_result(&p, Result{minigame = "arena", outcome = .Won, score = 100, stars = 2}))
	testing.expect(t, !record_result(&p, Result{minigame = "arena", outcome = .Lost, score = 50}))
	testing.expect(t, record_result(&p, Result{minigame = "arena", outcome = .Won, score = 140, stars = 1}))
	r := record_get(&p, "arena")
	testing.expect_value(t, r.best_score, i64(140))
	testing.expect_value(t, r.best_stars, u8(2))
	testing.expect_value(t, r.plays, 3)
	testing.expect_value(t, r.wins, 2)
	testing.expect_value(t, record_get(&p, "missing").plays, 0)
}

@(private = "file")
Fake_Game :: struct {
	resets: int,
	steps:  int,
	finish: Round_Status,
}

@(private = "file")
fake_hooks :: proc(g: ^Fake_Game) -> Minigame_Hooks {
	return Minigame_Hooks{
		data = g,
		reset = proc(data: rawptr, c: Minigame_Config) {
			(cast(^Fake_Game)data).resets += 1
		},
		step = proc(data: rawptr, f: ^Frame, playing: bool) -> Round_Status {
			g := cast(^Fake_Game)data
			if !playing {
				return .Playing
			}
			g.steps += 1
			return g.finish if g.steps >= 3 else .Playing
		},
		score = proc(data: rawptr) -> (i64, u8) {
			return 77, 3
		},
	}
}

@(test)
test_shell_runs_intro_play_and_reports_result :: proc(t: ^testing.T) {
	theme := ui.default_theme()
	ctx := ui.create(&theme)
	defer ui.destroy(ctx)
	profile := profile_default()
	defer profile_destroy(&profile)
	game := Fake_Game{finish = .Won}
	scene := minigame_scene(Minigame_Info{id = "fake", title = "Fake"}, fake_hooks(&game), {})
	shell := shell_of(&scene)
	testing.expect(t, shell != nil)
	testing.expect_value(t, game.resets, 1)
	testing.expect_value(t, shell.phase, Shell_Phase.Intro)

	cmds: Commands
	frame := Frame{dt = 0.1, ui = ctx, profile = &profile, commands = &cmds, focused = true,
		visible = true, window_focused = true, canvas = {0, 0, 960, 540}}
	run_frame :: proc(scene: ^Scene, frame: ^Frame, ctx: ^ui.Context, nav: bit_set[ui.Nav]) {
		sample := input.Sample(ui.Nav){down = nav}
		for a in nav {
			sample.value[a] = 1
		}
		ui.begin(ctx, ui.Pointer{}, sample, frame.dt)
		scene.update(scene.data, frame)
		ui.end(ctx)
	}
	// Intro holds the simulation still.
	run_frame(&scene, &frame, ctx, {})
	testing.expect_value(t, game.steps, 0)
	shell_skip_intro(shell)
	for _ in 0..<3 {
		run_frame(&scene, &frame, ctx, {})
	}
	testing.expect_value(t, shell.phase, Shell_Phase.Finished)
	testing.expect_value(t, shell.result.score, i64(77))
	testing.expect_value(t, shell.result.stars, u8(3))
	testing.expect_value(t, record_get(&profile, "fake").wins, 1)
	scene.destroy(scene.data)
}

@(test)
test_shell_pauses_on_focus_loss_and_back :: proc(t: ^testing.T) {
	theme := ui.default_theme()
	ctx := ui.create(&theme)
	defer ui.destroy(ctx)
	game := Fake_Game{finish = .Lost}
	scene := minigame_scene(Minigame_Info{id = "fake"}, fake_hooks(&game), {challenge = true})
	shell := shell_of(&scene)
	shell_skip_intro(shell)
	cmds: Commands
	frame := Frame{dt = 0.1, ui = ctx, commands = &cmds, focused = true, visible = true, canvas = {0, 0, 960, 540}}
	ui.begin(ctx, ui.Pointer{}, {}, 0.1)
	scene.update(scene.data, &frame) // window_focused = false
	ui.end(ctx)
	testing.expect_value(t, shell.phase, Shell_Phase.Paused)
	testing.expect_value(t, game.steps, 0)
	frame.window_focused = true
	back := input.Sample(ui.Nav){down = {.Back}}
	back.value[.Back] = 1
	ui.begin(ctx, ui.Pointer{}, back, 0.1)
	scene.update(scene.data, &frame)
	ui.end(ctx)
	testing.expect_value(t, shell.phase, Shell_Phase.Playing)
	scene.destroy(scene.data)
}

@(test)
test_format_time :: proc(t: ^testing.T) {
	testing.expect_value(t, format_time(83.47), "1:23.4")
	testing.expect_value(t, format_time(-1), "0:00.0")
}

@(test)
test_shell_pauses_when_an_overlay_owns_scene_input :: proc(t: ^testing.T) {
	theme := ui.default_theme()
	ctx := ui.create(&theme)
	defer ui.destroy(ctx)
	game := Fake_Game{}
	scene := minigame_scene(Minigame_Info{id = "fake"}, fake_hooks(&game), {})
	defer scene.destroy(scene.data)
	shell := shell_of(&scene)
	shell_skip_intro(shell)
	cmds: Commands
	frame := Frame{dt = 0.1, ui = ctx, commands = &cmds, visible = true,
		focused = false, window_focused = true, canvas = {0, 0, 960, 540}}
	ui.begin(ctx, {}, {}, frame.dt)
	scene.update(scene.data, &frame)
	ui.end(ctx)
	testing.expect_value(t, shell.phase, Shell_Phase.Paused)
	testing.expect_value(t, game.steps, 0)
	testing.expect_value(t, shell.elapsed, f32(0))
	// Removing the overlay grants input, but cannot silently resume the round.
	frame.focused = true
	ui.begin(ctx, {}, {}, frame.dt)
	scene.update(scene.data, &frame)
	ui.end(ctx)
	testing.expect_value(t, shell.phase, Shell_Phase.Paused)
	testing.expect_value(t, game.steps, 0)
}

@(test)
test_pop_keeps_owned_names_valid_during_resume :: proc(t: ^testing.T) {
	s: Stack
	parent: Probe
	name := [5]u8{'c', 'h', 'i', 'l', 'd'}
	stack_push(&s, probe_scene("parent", &parent))
	stack_push(&s, Scene{
		name = string(name[:]), data = &name,
		destroy = proc(data: rawptr) {
			// A child's name may be owned by its data and disappear on destroy.
			(cast(^[5]u8)data)^ = {'x', 'x', 'x', 'x', 'x'}
		},
	})
	cmds: Commands
	frame := Frame{commands = &cmds}
	pop(&frame, Result{minigame = string(name[:]), outcome = .Won})
	testing.expect(t, apply(&s, &cmds, &frame))
	testing.expect_value(t, parent.from, "child")
	testing.expect_value(t, parent.last.?.minigame, "child")
	destroy_all(&s)
}

@(test)
test_visible_lower_scene_cannot_consume_overlay_click :: proc(t: ^testing.T) {
	theme := ui.default_theme()
	ctx := ui.create(&theme)
	defer ui.destroy(ctx)
	s: Stack
	parent, overlay: Probe
	probes := [?]^Probe{&parent, &overlay}
	for probe in probes {
		scene := probe_scene("button", probe)
		scene.update = proc(data: rawptr, frame: ^Frame) {
			p := cast(^Probe)data
			p.updates += 1
			if ui.button(frame.ui, {0, 0, 80, 40}, "Open") {
				p.resumed += 1
			}
		}
		stack_push(&s, scene)
	}
	frame := Frame{ui = ctx, window_focused = true, canvas = {0, 0, 960, 540}}
	ui.begin(ctx, {position = {20, 20}, inside = true, pressed = true, down = true}, {}, 0.016)
	update_scenes(&s, &frame, 0, 0)
	ui.end(ctx)
	ui.begin(ctx, {position = {20, 20}, inside = true, released = true}, {}, 0.016)
	update_scenes(&s, &frame, 0, 0)
	ui.end(ctx)
	testing.expect_value(t, parent.updates, 2)
	testing.expect_value(t, overlay.updates, 2)
	testing.expect_value(t, parent.resumed, 0)
	testing.expect_value(t, overlay.resumed, 1)
	testing.expect_value(t, ctx.focus_count, 1)
	testing.expect(t, !ctx.noninteractive, "the host must restore the surrounding UI state")
	destroy_all(&s)
}

@(test)
test_modal_push_suspends_round_until_explicit_resume :: proc(t: ^testing.T) {
	s: Stack
	game: Fake_Game
	scene := minigame_scene(Minigame_Info{id = "fake"}, fake_hooks(&game), {})
	shell := shell_of(&scene)
	shell_skip_intro(shell)
	stack_push(&s, scene)
	child: Probe
	stack_push(&s, probe_scene("overlay", &child, modal = true))
	testing.expect_value(t, shell.phase, Shell_Phase.Paused)
	testing.expect_value(t, update_start(&s), 1)
	cmds: Commands
	frame := Frame{commands = &cmds}
	pop(&frame)
	testing.expect(t, apply(&s, &cmds, &frame))
	testing.expect_value(t, shell.phase, Shell_Phase.Paused)
	testing.expect_value(t, shell.elapsed, f32(0))
	shell_skip_intro(shell)
	testing.expect_value(t, shell.phase, Shell_Phase.Playing)
	destroy_all(&s)
}

@(test)
test_failed_push_does_not_suspend_current_scene :: proc(t: ^testing.T) {
	s: Stack
	for _ in 0..<MAX_SCENES-1 {
		stack_push(&s, Scene{})
	}
	game: Fake_Game
	scene := minigame_scene(Minigame_Info{id = "fake"}, fake_hooks(&game), {})
	shell := shell_of(&scene)
	shell_skip_intro(shell)
	stack_push(&s, scene)
	testing.expect(t, !stack_push(&s, Scene{}))
	testing.expect_value(t, shell.phase, Shell_Phase.Playing)
	destroy_all(&s)
}
