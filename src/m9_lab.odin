package main

import app "app"
import render "render"
import rl "vendor:raylib"

draw_m9_session :: proc(renderer: ^render.Renderer, session: ^M9_Session) {
	if session.mode == .FPS {render.draw_m9_fps(renderer,&session.fps,&session.previous_fps,m9_view(session))}
	else if session.mode != .None {render.draw_m9_fight(renderer,&session.ring,m9_view(session))}
}

run_m9_lab :: proc(window: ^app.Window, renderer: ^render.Renderer, mode: render.M9_Kind) {
	session := new(M9_Session)
	defer free(session)
	defer destroy_m9_session(session)
	defer rl.EnableCursor()
	begin_m9_session(session,mode,true,true)
	for !app.should_close(window) && session.mode != .None {
		defer free_all(context.temp_allocator)
		app.refresh_viewport(window)
		mouse,inside := app.mouse_canvas_position(window)
		input := sample_m9_input(session,renderer,mouse,inside)
		dt := rl.GetFrameTime()
		step_m9_session(session,dt,input)
		update_m9_cursor(session)
		render.advance_sprite_assets(&renderer.sprite_assets,dt)
		app.begin_canvas(window,render.RESIN_BACKGROUND)
		draw_m9_session(renderer,session)
		app.present(window,render.LETTERBOX_COLOR)
	}
}
