package application
import devtools "../devtools"
import run_session "../run"

import "core:os"
import "core:fmt"
import host "../engine/host"
import render "../render"

// Entry-point routing and native host ownership. Run setup and teardown live
// in roguelike_startup.odin and roguelike_lifecycle.odin.

// Without arguments the menu opens; smoke, lab and report modes start the
// roguelike directly, so automation keeps its command lines.
start :: proc(args: []string) {
	launch, rest := split_launch_arguments(args)
	defer delete(rest)
	options := DEFAULT_RUNTIME_OPTIONS
	roguelike_parse_arguments(&options, rest[:])
	// Every renderer made from here on starts with this look.
	render.set_startup_environment_theme(options.environment_theme)
	rs := run_session.roguelike_session_new(options.gameplay)
	if (launch.minigame != "" || launch.smoke_menu) && (launch.run || roguelike_requires_direct_start(&options)) {
		fmt.eprintln("choose a run/lab/smoke or a launcher minigame, not both")
		run_session.roguelike_destroy(rs)
		os.exit(2)
	}
	if launch.minigame == "" && !launch.smoke_menu && (launch.run || roguelike_requires_direct_start(&options)) {
		run_roguelike_directly(rs, options.tools)
		return
	}
	run_session.roguelike_destroy(rs)
	run_launcher(options, launch)
}

run_roguelike_directly :: proc(rs: ^run_session.Roguelike_Session, options: devtools.Tool_Options) {
	if !devtools.configure(rs, options) || run_session.roguelike_prepare(rs, !options.smoke_playtest && !options.m7_smoke) != .Ready {
		run_session.roguelike_destroy(rs)
		return
	}
	if result := devtools.run_headless(rs, options); result != .Ready {
		run_session.roguelike_destroy(rs)
		if result == .Failed { os.exit(2) }
		return
	}
	h, ok := host.create(host.Config{
		window          = run_session.roguelike_window_config(rs),
		profile_path    = profile_path() if run_session.roguelike_profile_enabled(rs) else "",
		enable_audio    = options.smoke_mode_count == 0,
		letterbox_color = render.LETTERBOX_COLOR,
	})
	if !ok {
		run_session.roguelike_destroy(rs)
		return
	}
	defer host.destroy(h)
	if run_session.roguelike_attach(rs, &h.window) != .Ready {
		run_session.roguelike_destroy(rs)
		return
	}
	if result := devtools.run_attached(rs, options); result != .Ready {
		run_session.roguelike_destroy(rs)
		if result == .Failed { os.exit(2) }
		return
	}
	host.push_scene(h, run_session.roguelike_scene(rs))
	host.run(h)
}
