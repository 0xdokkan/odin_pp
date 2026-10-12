package render

import "core:fmt"
import rl "vendor:raylib"
import game "../game"

// The sandbox's sign under the top HUD: its name, the crowd and the keys.
draw_mechanics_lab_banner :: proc(renderer: ^Renderer, room: ^game.Room, from_menu: bool) {
	if renderer == nil || room == nil { return }
	title: cstring = "PROVA MECCANICHE"
	detail := fmt.ctprintf("NEMICI %d/%d  /  F5 RICOMINCIA%s", len(room.enemies), game.SANDBOX_MAX_ENEMIES,
		"  /  F10 MENU" if from_menu else "")
	width := max(gothic_text_width(renderer, title, 16), gothic_text_width(renderer, detail, 10))+28
	bounds := rl.Rectangle{(renderer.canvas_width-width)*0.5, TACTICAL_HUD_HEIGHT+4, width, 38}
	hud_frame(bounds, HUD_AMBER)
	rl.DrawRectangleRec({bounds.x, bounds.y, 3, bounds.height}, HUD_AMBER)
	gothic_text(renderer, title, bounds.x+(bounds.width-gothic_text_width(renderer, title, 16))*0.5, bounds.y+3, 16, GOTHIC_PAPER)
	gothic_text(renderer, detail, bounds.x+(bounds.width-gothic_text_width(renderer, detail, 10))*0.5, bounds.y+22, 10, GOTHIC_MUTED)
}
