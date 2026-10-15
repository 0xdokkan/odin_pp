package main

import rl "vendor:raylib"
import app "app"
import game "game"
import grid "grid"
import render "render"

mechanics_lab_enemy :: proc(room: ^game.Room, id: u32) -> ^game.Enemy {
	index, found := game.enemy_index_by_id(room, id)
	return &room.enemies[index] if found else nil
}

mechanics_lab_spawn_enemy :: proc(room: ^game.Room, at: grid.Position, health: i32, archetype: game.Enemy_Archetype = .Chaser, free := false) -> u32 {
	id, placed := game.spawn_enemy(room, {position = at, health = health, attack = 1, archetype = archetype})
	if placed && !free { mechanics_lab_hold(room, id) }
	return id
}

mechanics_lab_capture_aim :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, card: u32, cell: grid.Position, name: cstring) {
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		renderer.has_hovered_cell, renderer.hovered_cell = true, cell
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, card)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, 0, card, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	rl.TakeScreenshot(name)
	renderer.has_hovered_cell = false
}
