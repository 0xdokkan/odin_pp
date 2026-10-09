package render

import "core:c"
import rl "vendor:raylib"
import game "../game"

// Explicit per-screen theme: layout, hitboxes and classic rendering keep the
// same contracts. Menus share the battle font and palette without global state.
menu_themed :: proc(theme: ^Renderer) -> bool { return theme != nil && theme.tactical.enabled }

menu_color :: proc(theme: ^Renderer, input: rl.Color) -> rl.Color {
	color := input
	if !menu_themed(theme) { return color }
	alpha := color.a
	if max(color.r, max(color.g, color.b)) < 85 {
		color = GOTHIC_INK if max(color.r, max(color.g, color.b)) < 45 else rl.Color{37, 25, 31, 255}
	} else if int(color.r) > int(color.g)+30 && int(color.r) > int(color.b)+30 && color.g < 140 {
		color = GOTHIC_RED
	} else if max(color.r, max(color.g, color.b)) < 195 { color = GOTHIC_MUTED }
	else { color = GOTHIC_PAPER }
	color.a = alpha
	return color
}
menu_label :: proc(text: cstring) -> cstring {
	switch string(text) {
	case "ROUTE": return "ASCESA ALLA TORRE"
	case "CARD REWARD": return "SCEGLI UNA CARTA"
	case "CHOOSE A RELIC": return "SCEGLI UNA RELIQUIA"
	case "SHOP": return "MERCANTE"
	case "REST": return "RIPOSO"
	case "REST SITE": return "RIPOSO"
	case "A QUIET MOMENT BETWEEN ROOMS": return "UNA TREGUA DURANTE L'ASCESA"
	case "ROUTE EVENT": return "INCONTRO"
	case "TREASURE": return "TESORO"
	case "DEFEAT": return "LA TORRE TI HA VINTO"
	case "RESTART": return "RIPROVA"
	case "CONTINUE": return "CONTINUA"
	case "SKIP": return "PASSA"
	case "CHOOSE ONE": return "SCEGLINE UNA"
	case "S  SKIP": return "S  PASSA"
	case "START YOUR RUN WITH A DIFFERENT TACTIC": return "UN DONO PRIMA DELL'ASCESA"
	case "PASSIVE EFFECTS / NO ENERGY COST": return "EFFETTI PASSIVI / NESSUN COSTO IN ENERGIA"
	case "KEPT UNTIL THE END OF THE RUN": return "CON TE FINO ALLA FINE DELLA RUN"
	case "1-3 OR CLICK TO CHOOSE": return "1-3 O CLIC PER SCEGLIERE"
	case "SELECTED CARD": return "CARTA SELEZIONATA"
	case "KEEP MOVING": return "RIPRENDI L'ASCESA"
	case "AN UNGUARDED CACHE": return "UN TESORO INCUSTODITO"
	case "NO ENERGY COST": return "NESSUN COSTO IN ENERGIA"
	case "OPEN": return "APRI"
	case "CLAIM": return "RACCOGLI"
	case "MAKE OFFER": return "OFFRI"
	case "REFUSE": return "RIFIUTA"
	case "TAKE NOTHING": return "NON PRENDERE NULLA"
	case "WALK AWAY": return "RIPRENDI L'ASCESA"
	case "DO NOT OPEN": return "LASCIA IL TESORO"
	case "CARD OFFERS": return "CARTE IN VENDITA"
	case "RECOVER": return "RECUPERA"
	case "UPGRADE": return "POTENZIA"
	case "REMOVE": return "RIMUOVI"
	case "LEAVE": return "PROSEGUI"
	case "RESULT": return "ESITO"
	}
	return text
}
menu_text :: proc(theme: ^Renderer, text: cstring, x, y, size: c.int, color: rl.Color) {
	if menu_themed(theme) { gothic_text(theme, menu_label(text), f32(x), f32(y), int(size), menu_color(theme, color)) }
	else { rl.DrawText(text, x, y, size, color) }
}
menu_measure_text :: proc(theme: ^Renderer, text: cstring, size: c.int) -> c.int {
	if menu_themed(theme) { return c.int(gothic_text_width(theme, menu_label(text), int(size))) }
	return rl.MeasureText(text, size)
}
menu_rectangle :: proc(theme: ^Renderer, x, y, w, h: c.int, color: rl.Color) {
	rl.DrawRectangle(x, y, w, h, menu_color(theme, color))
	if menu_themed(theme) && x == 0 && y == 0 && h < 100 && w > 500 { gothic_rule(18, f32(h), f32(w)-36) }
}
menu_rectangle_rec :: proc(theme: ^Renderer, bounds: rl.Rectangle, color: rl.Color) {
	rl.DrawRectangleRec(bounds, menu_color(theme, color))
}
menu_outline :: proc(theme: ^Renderer, bounds: rl.Rectangle, thickness: f32, color: rl.Color) {
	if menu_themed(theme) && bounds.height > 28 && bounds.width > 48 {
		gothic_frame(bounds, GOTHIC_INK, menu_color(theme, color))
	} else { rl.DrawRectangleLinesEx(bounds, thickness, menu_color(theme, color)) }
}
menu_rectangle_lines :: proc(theme: ^Renderer, x, y, w, h: c.int, color: rl.Color) {
	menu_outline(theme, {f32(x), f32(y), f32(w), f32(h)}, 1, color)
}
menu_circle :: proc(theme: ^Renderer, center: rl.Vector2, radius: f32, color: rl.Color) {
	if menu_themed(theme) { rl.DrawPoly(center, 8, radius, 22.5, menu_color(theme, color)) }
	else { rl.DrawCircleV(center, radius, color) }
}
menu_circle_lines :: proc(theme: ^Renderer, center: rl.Vector2, radius: f32, color: rl.Color) {
	if menu_themed(theme) { rl.DrawPolyLinesEx(center, 8, radius, 22.5, 1, menu_color(theme, color)) }
	else { rl.DrawCircleLinesV(center, radius, color) }
}
menu_poly :: proc(theme: ^Renderer, center: rl.Vector2, sides: c.int, radius, rotation: f32, color: rl.Color) {
	rl.DrawPoly(center, sides, radius, rotation, menu_color(theme, color))
}
menu_poly_lines :: proc(theme: ^Renderer, center: rl.Vector2, sides: c.int, radius, rotation, thickness: f32, color: rl.Color) {
	rl.DrawPolyLinesEx(center, sides, radius, rotation, thickness, menu_color(theme, color))
}
menu_line :: proc(theme: ^Renderer, a, b: rl.Vector2, thickness: f32, color: rl.Color) {
	rl.DrawLineEx(a, b, thickness, menu_color(theme, color))
}
menu_triangle :: proc(theme: ^Renderer, a, b, c: rl.Vector2, color: rl.Color) {
	rl.DrawTriangle(a, b, c, menu_color(theme, color))
}
menu_card_face :: proc(theme: ^Renderer, bounds: rl.Rectangle, card: game.Card_Instance,
	definition: game.Card_Definition, slot: int, affordable, expanded, highlighted, selected: bool) {
	if menu_themed(theme) {
		draw_tactical_card(theme, bounds, card, definition, slot, affordable, selected, highlighted, true)
	} else { draw_card_face(bounds, card, definition, slot, affordable, expanded, highlighted, selected) }
}
