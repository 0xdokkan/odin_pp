package run

import app "../engine/app"
import game "../game"
import render "../render"
import rl "vendor:raylib"

Dice_Window_Overlay :: struct {
	renderer: ^render.Dice_Renderer,
	roll: game.Dice_Roll,
	progress: f32,
	seed: u64,
	card: game.Card_Id,
	outcome: render.Dice_Outcome,
}

// Cosmetic only: identical committed events replay the same physical throw.
// No gameplay random stream is read or advanced by presentation.
dice_event_visual_seed :: proc(event: game.Game_Event) -> u64 {
	seed := (u64(event.card_id)<<32)~event.pulse_count~0xAE6D79B30C521F47
	roll := event.dice_roll
	if !game.validate_dice_roll(&roll) { return seed }
	for face, index in roll.faces[:roll.count] {
		seed = (seed~u64(face+1+i32(index)*7))*0x100000001B3
	}
	return seed
}

update_window_dice_overlay :: proc(window: ^app.Window, state: ^Dice_Window_Overlay) {
	area := window.viewport.destination
	render.update_dice_pool_texture(state.renderer, state.roll, state.progress,
		f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()),
		{area.x, area.y, area.width, area.height}, state.seed)
}

draw_window_dice_overlay :: proc(window: ^app.Window, data: rawptr) {
	if window == nil || data == nil { return }
	state := cast(^Dice_Window_Overlay)data
	area := window.viewport.destination
	render.draw_dice_pool_overlay(state.renderer, state.roll, state.progress,
		f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()),
		{area.x, area.y, area.width, area.height}, state.seed, state.card, state.outcome)
}
