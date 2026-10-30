package render

import "core:fmt"
import rl "vendor:raylib"
import game "../game"

MECHANICS_LAB_TITLE :: cstring("PROVA MECCANICHE")

// The sandbox's sign under the top HUD: its name, the crowd and the keys.
// Its second line as the banner writes it now: in a fight the crowd and the
// keys, once F7 cleared the arena for the Canna da Pesca
// (game.sandbox_clear_for_fishing) its fishings; F10 when it was opened from
// the menu (set_mechanics_lab).
mechanics_lab_banner_detail :: proc(renderer: ^Renderer, room: ^game.Room) -> cstring {
	menu: cstring = "  /  F10 MENU" if renderer.tactical.mechanics_lab_menu else ""
	if room.phase == .Loot {
		return fmt.ctprintf("ARENA LIBERA  /  PESCA %d/%d  /  F7 DA CAPO  /  F5 RICOMINCIA%s", game.fishing_casts_left(room),
			game.fishing_casts_allowed(room), menu)
	}
	return fmt.ctprintf("NEMICI %d/%d  /  F5 RICOMINCIA  /  F6 INTENTI: %s  /  F7 PESCA  /  F3 ARENA%s", len(room.enemies), game.SANDBOX_MAX_ENEMIES,
		intent_display_name(renderer.tactical.intent_display), menu)
}

// The banner's frame, around the words it writes now: the board's labels keep
// clear of it while the lab runs (draw_tactical_annotations).
@(private)
mechanics_lab_banner_bounds :: proc(renderer: ^Renderer, room: ^game.Room) -> rl.Rectangle {
	width := max(gothic_text_width(renderer, MECHANICS_LAB_TITLE, 16), gothic_text_width(renderer, mechanics_lab_banner_detail(renderer, room), 10))+28
	return {(renderer.canvas_width-width)*0.5, TACTICAL_HUD_HEIGHT+4, width, 38}
}

set_mechanics_lab :: proc(renderer: ^Renderer, on: bool, from_menu := false) {
	if renderer != nil { renderer.tactical.mechanics_lab, renderer.tactical.mechanics_lab_menu = on, on && from_menu }
}

draw_mechanics_lab_banner :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer == nil || room == nil { return }
	detail := mechanics_lab_banner_detail(renderer, room)
	bounds := mechanics_lab_banner_bounds(renderer, room)
	hud_frame(bounds, HUD_AMBER)
	rl.DrawRectangleRec({bounds.x, bounds.y, 3, bounds.height}, HUD_AMBER)
	gothic_text(renderer, MECHANICS_LAB_TITLE, bounds.x+(bounds.width-gothic_text_width(renderer, MECHANICS_LAB_TITLE, 16))*0.5, bounds.y+3, 16, GOTHIC_PAPER)
	gothic_text(renderer, detail, bounds.x+(bounds.width-gothic_text_width(renderer, detail, 10))*0.5, bounds.y+22, 10, GOTHIC_MUTED)
}
