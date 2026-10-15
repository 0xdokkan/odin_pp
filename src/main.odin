package main

import "core:os"
import "core:fmt"
import host "engine/host"
import render "render"

// Entry-point routing and native host ownership. Run setup and teardown live
// in roguelike_startup.odin and roguelike_lifecycle.odin.

// Without arguments the menu opens; smoke, lab and report modes start the
// roguelike directly, so automation keeps its command lines.
main :: proc() {
	launch, rest := split_launch_arguments(os.args[1:])
	defer delete(rest)
	rs := roguelike_session_new()
	roguelike_parse_arguments(rs, rest[:])
	if (launch.minigame != "" || launch.smoke_menu) && (launch.run || roguelike_requires_direct_start(rs)) {
		fmt.eprintln("choose a run/lab/smoke or a launcher minigame, not both")
		roguelike_destroy(rs)
		os.exit(2)
	}
	if launch.minigame == "" && !launch.smoke_menu && (launch.run || roguelike_requires_direct_start(rs)) {
		run_roguelike_directly(rs)
		return
	}
	options := rs.options
	roguelike_destroy(rs)
	run_launcher(options, launch)
}

run_roguelike_directly :: proc(rs: ^Roguelike_Session) {
	if roguelike_prepare(rs) != .Ready {
		roguelike_destroy(rs)
		return
	}
	h, ok := host.create(host.Config{
		window          = roguelike_window_config(rs),
		profile_path    = profile_path() if roguelike_profile_enabled(rs) else "",
		enable_audio    = rs.smoke_mode_count == 0,
		letterbox_color = render.LETTERBOX_COLOR,
	})
	if !ok {
		roguelike_destroy(rs)
		return
	}
	defer host.destroy(h)
	if roguelike_attach(rs, &h.window) != .Ready {
		roguelike_destroy(rs)
		return
	}
	host.push_scene(h, roguelike_scene(rs))
	host.run(h)
}
