package devtools
import activities "../activities"

import app "../engine/app"
import devices_input "../engine/input"
import render "../render"
import rl "vendor:raylib"

draw_m9_session :: proc(renderer: ^render.Renderer, session: ^activities.Free_Mode_Session) {
	if session.mode == .FPS {render.draw_m9_fps(renderer,&session.fps,&session.previous_fps,activities.free_mode_view(session))}
	else if session.mode != .None {render.draw_m9_fight(renderer,&session.ring,activities.free_mode_view(session))}
}

run_m9_lab :: proc(window: ^app.Window, renderer: ^render.Renderer, mode: render.M9_Kind) {
	session := new(activities.Free_Mode_Session)
	defer free(session)
	defer activities.destroy_free_mode_session(session)
	defer rl.EnableCursor()
	activities.begin_free_mode_session(session,mode,true,true)
	for !app.should_close(window) && session.mode != .None {
		defer free_all(context.temp_allocator)
		devices := devices_input.capture_devices()
		app.refresh_viewport(window)
		mouse,inside := app.mouse_canvas_position(window, &devices)
		input := activities.sample_free_mode_input(session,renderer,mouse,inside,&devices)
		dt := rl.GetFrameTime()
		activities.step_free_mode_session(session,dt,input)
		activities.update_free_mode_cursor(session, devices.focused)
		render.advance_sprite_assets(&renderer.sprite_assets,dt)
		app.begin_canvas(window,render.RESIN_BACKGROUND)
		draw_m9_session(renderer,session)
		app.present(window,render.LETTERBOX_COLOR)
	}
}
