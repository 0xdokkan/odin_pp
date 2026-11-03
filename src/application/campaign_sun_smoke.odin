package application

import "core:fmt"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import host "../engine/host"
import input "../engine/input"
import game "../game"
import run "../run"

// A real expedition renderer in first person, including a continuous turn and
// a return to the approved board camera. No profile or gameplay defaults change.
@(private)
Sun_FPS_Capture :: struct { wrapped: host.Scene, frames: int }

@(private)
expedition_enable_sun_fps_smoke :: proc(scene: ^host.Scene) {
	s := new(Sun_FPS_Capture)
	s.wrapped = scene^
	e := cast(^run.Expedition_Session)scene.data
	expedition_smoke_cartoon(e)
	e.rs.room.player.health = 400
	begun := game.tactical_begin_first_person(&e.rs.room, 30)
	assert(begun, "The sun probe must enter first person in the expedition")
	rl.SetWindowSize(1024, 576)
	scene^ = host.Scene{name = "sun-fps-smoke", data = s, opaque = true, modal = true,
		update = sun_fps_update, draw = sun_fps_draw, after_present = sun_fps_present,
		destroy = proc(data: rawptr) { s := cast(^Sun_FPS_Capture)data; s.wrapped.destroy(s.wrapped.data); free(s) }}
}

@(private)
sun_fps_update :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Sun_FPS_Capture)data
	e := cast(^run.Expedition_Session)s.wrapped.data
	keys := input.Device_Snapshot{focused = true}
	actual := frame^
	actual.focused, actual.window_focused, actual.dt = true, true, 1.0/60
	actual.devices = &keys
	if s.frames >= 90 && s.frames < 210 { e.rs.iso_renderer.tactical.first_person.yaw += .012 }
	if s.frames == 210 { e.rs.room.first_person.active = false }
	s.wrapped.update(s.wrapped.data, &actual)
}

@(private)
sun_fps_draw :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Sun_FPS_Capture)data
	s.wrapped.draw(s.wrapped.data, frame)
}

@(private)
sun_fps_present :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Sun_FPS_Capture)data
	s.frames += 1
	if s.frames == 60 || s.frames == 150 || s.frames == 210 || s.frames == 270 {
		artifacts.screenshot(fmt.ctprintf("odin_pp_sun_fps_%03d.png", s.frames))
		e := cast(^run.Expedition_Session)s.wrapped.data
		if m := e.rs.iso_renderer.tactical.expedition_material; m != nil {
			fmt.printfln("SUN FPS frame=%d maps=%d active=%v", s.frames, m.sun.renders, m.sun.active)
		}
	}
	if s.frames >= 270 { host.quit(frame) }
}
