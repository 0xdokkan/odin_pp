package application

import campaign "../campaign"
import game "../game"
import run "../run"
import render "../render"
import app "../engine/app"
import host "../engine/host"
import input "../engine/input"

// The archive preview owns its entire lab session. No campaign, inventory,
// expedition state or save callbacks are borrowed by the film.
hub_card_preview_prepare :: proc(card: game.Card_Id, window: ^app.Window = nil) -> (^run.Roguelike_Session, bool) {
	if card < .Strike || card >= .Count { return nil, false }
	options := run.DEFAULT_OPTIONS
	options.mechanics_lab = true; options.persist_profile = false; options.procedural_rooms = false
	rs := run.roguelike_session_new(options)
	if run.roguelike_prepare(rs) != .Ready { run.roguelike_destroy(rs); return nil, false }
	rs.from_launcher = true
	if window != nil {
		if run.roguelike_attach(rs, window) != .Ready { run.roguelike_destroy(rs); return nil, false }
	} else { rs.iso_renderer = render.create(960, 540) }
	if !run.open_effect_window_in_run(rs, {id = 1, definition_id = card}, .Inspector) {
		run.roguelike_destroy(rs); return nil, false
	}
	return rs, true
}

hub_card_preview_scene :: proc(card: game.Card_Id, frame: ^host.Frame) -> (host.Scene, bool) {
	if frame == nil || frame.window == nil { return {}, false }
	rs, ok := hub_card_preview_prepare(card, frame.window)
	if !ok { return {}, false }
	return host.Scene{name = "archive-preview", data = rs, opaque = true, modal = true,
		clear_color = {8, 14, 23, 255}, update = hub_preview_update, draw = hub_preview_draw,
		draw_window = hub_preview_draw_window, destroy = run.roguelike_destroy}, true
}

// Kept separate from scene creation so a locked card can never be revealed
// accidentally by a stale menu selection. The lab remains unrestricted.
hub_open_archive_preview :: proc(progress: ^campaign.Campaign, card: game.Card_Id, frame: ^host.Frame) -> bool {
	if progress == nil || card < .Strike || card >= .Count || !progress.discovered[card] { return false }
	scene, ok := hub_card_preview_scene(card, frame)
	if ok { host.push(frame, scene) }
	return ok
}

@(private)
hub_preview_update :: proc(data: rawptr, frame: ^host.Frame) {
	rs := cast(^run.Roguelike_Session)data
	run.step_effect_window_in_run(rs, {
		focused = frame.focused && frame.window_focused,
		inside = frame.mouse_inside,
		mouse = {frame.mouse.x, frame.mouse.y},
		pressed = input.mouse_pressed(frame.devices, .LEFT),
		right_pressed = input.mouse_pressed(frame.devices, .RIGHT),
		escape = input.key_pressed(frame.devices, .ESCAPE),
		restart = input.key_pressed(frame.devices, .R),
	}, frame.dt, frame.audio)
	if !rs.effect_window.open { host.pop(frame) }
}
@(private)
hub_preview_draw :: proc(data: rawptr, frame: ^host.Frame) {
	rs := cast(^run.Roguelike_Session)data
	if rs.effect_window.backdrop_ready { run.draw_effect_window_backdrop(&rs.effect_window, frame.canvas.width, frame.canvas.height) }
	run.draw_effect_window(&rs.effect_window, &rs.iso_renderer, frame.canvas.width, frame.canvas.height)
}
@(private)
hub_preview_draw_window :: proc(data: rawptr, frame: ^host.Frame) {
	rs := cast(^run.Roguelike_Session)data
	run.draw_window_effect_stage(frame.window, &rs.effect_window)
}
