package render

import "core:fmt"
import rl "vendor:raylib"
import game "../game"

// The sandbox's sign under the top HUD: its name, the crowd and the keys.
// The banner's frame; the board's labels keep clear of it while the lab runs
// (set_mechanics_lab).
mechanics_lab_banner_bounds :: proc(renderer: ^Renderer, title, detail: cstring) -> rl.Rectangle {
	width := max(gothic_text_width(renderer, title, 16), gothic_text_width(renderer, detail, 10))+28
	return {(renderer.canvas_width-width)*0.5, TACTICAL_HUD_HEIGHT+4, width, 38}
}

set_mechanics_lab :: proc(renderer: ^Renderer, on: bool) {
	if renderer != nil { renderer.tactical.mechanics_lab = on }
}

draw_mechanics_lab_banner :: proc(renderer: ^Renderer, room: ^game.Room, from_menu: bool) {
	if renderer == nil || room == nil { return }
	title: cstring = "PROVA MECCANICHE"
	detail := fmt.ctprintf("NEMICI %d/%d  /  F5 RICOMINCIA  /  F6 INTENTI: %s%s", len(room.enemies), game.SANDBOX_MAX_ENEMIES,
		intent_display_name(renderer.tactical.intent_display), "  /  F10 MENU" if from_menu else "")
	bounds := mechanics_lab_banner_bounds(renderer, title, detail)
	hud_frame(bounds, HUD_AMBER)
	rl.DrawRectangleRec({bounds.x, bounds.y, 3, bounds.height}, HUD_AMBER)
	gothic_text(renderer, title, bounds.x+(bounds.width-gothic_text_width(renderer, title, 16))*0.5, bounds.y+3, 16, GOTHIC_PAPER)
	gothic_text(renderer, detail, bounds.x+(bounds.width-gothic_text_width(renderer, detail, 10))*0.5, bounds.y+22, 10, GOTHIC_MUTED)
}
