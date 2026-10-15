package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../view"

// MOSTRA EFFETTO's film (main/card_demo.odin): its pointer, a leather glove of
// pixel art cut from paper as the board's props are (the print, its ink line,
// white paper round it, the ink cut and the cut edge one texel down and right:
// first_person_paint's layers), the ring a click leaves under its finger, and
// the plate that says in words what the glove does. All drawn in place, piece
// by piece: nothing to load, nothing to free.

// The glove's two drawings: the finger pointing (reaching, clicking), the
// hand closed on the card it carries.
Card_Demo_Glove :: enum u8 {Point, Grab}

// Palette letters: the leather's shine, light, mid and dark, the cuff red
// and its light ('.' clear). The right hand from its back: the index up, the
// thumb low at its left, the other fingers folded, stepping down to the right.
@(rodata)
CARD_DEMO_GLOVE_POINT := [?]string{
	"...BB........",
	"..BLBn.......",
	"..BLBn.......",
	"..BLBn.......",
	"..BBBn.......",
	"..BBBNBBn....",
	"..BBBNBBNBn..",
	"..BBBNBBNBBn.",
	"..BBBNBBNBBNn",
	"B.BBBBBBBBBBn",
	"BBnBBBBBBBBBn",
	".BBnBBBBBBBBn",
	"..BBBBBBBBBn.",
	"...nBBBBBBBn.",
	"...RrrrrrrrR.",
	"...RRRRRRRRR.",
}
// The hand closed on the card: the knuckles on top, the fingertips folded
// under them, the thumb across.
@(rodata)
CARD_DEMO_GLOVE_GRAB := [?]string{
	".............",
	".............",
	".............",
	".............",
	"...BBnBBnBn..",
	"..BBBNBBNBBn.",
	"..BLBNBLNBBNn",
	"..BBBNBBNBBNn",
	".BnnnnnnnnBBn",
	"BBBBBBBnBBBBn",
	"BLBBBBBnBBBBn",
	".BBBBBBBBBBBn",
	"..BBBBBBBBBn.",
	"...nBBBBBBBn.",
	"...RrrrrrrrR.",
	"...RRRRRRRRR.",
}
CARD_DEMO_GLOVE_COLUMNS :: 13
CARD_DEMO_GLOVE_ROWS :: 16
// Texels of room round the print for its paper's layers.
CARD_DEMO_GLOVE_MARGIN :: 4
CARD_DEMO_GLOVE_PAPER :: 1
// Stage pixels to a texel of the glove.
CARD_DEMO_GLOVE_PIXEL :: f32(2)
// The texel of the print that touches what the glove points at: the
// fingertip, and the closed hand's knuckles.
CARD_DEMO_GLOVE_POINT_TIP :: [2]f32{3.5, 0}
CARD_DEMO_GLOVE_GRAB_TIP :: [2]f32{6.5, 4}
CARD_DEMO_GLOVE_WIDTH :: CARD_DEMO_GLOVE_COLUMNS+CARD_DEMO_GLOVE_MARGIN*2
CARD_DEMO_GLOVE_HEIGHT :: CARD_DEMO_GLOVE_ROWS+CARD_DEMO_GLOVE_MARGIN*2

card_demo_glove_color :: proc(letter: u8) -> (color: rl.Color, ok: bool) {
	switch letter {
	case 'L': return {238, 196, 136, 255}, true
	case 'B': return {214, 160, 98, 255}, true
	case 'n': return {160, 104, 56, 255}, true
	case 'N': return {98, 58, 32, 255}, true
	case 'R': return {132, 30, 38, 255}, true
	case 'r': return {196, 64, 62, 255}, true
	}
	return
}

// A drawing of the glove with its paper, texel by texel (0: clear).
Card_Demo_Glove_Print :: [CARD_DEMO_GLOVE_HEIGHT][CARD_DEMO_GLOVE_WIDTH]rl.Color

card_demo_glove_paint :: proc(glove: Card_Demo_Glove) -> (print: Card_Demo_Glove_Print) {
	rows := CARD_DEMO_GLOVE_POINT if glove == .Point else CARD_DEMO_GLOVE_GRAB
	w, h := CARD_DEMO_GLOVE_WIDTH, CARD_DEMO_GLOVE_HEIGHT
	layers, staged: [CARD_DEMO_GLOVE_WIDTH*CARD_DEMO_GLOVE_HEIGHT]Paper_Outline_Layer
	m := CARD_DEMO_GLOVE_MARGIN
	for row, y in rows {
		for x in 0..<min(len(row), CARD_DEMO_GLOVE_COLUMNS) {
			if color, ok := card_demo_glove_color(row[x]); ok {
				print[y+m][x+m] = color
				layers[(y+m)*w+x+m] = .Print
			}
		}
	}
	paper_outline_grow(layers[:], staged[:], w, h, .Ink, true)
	for ring in 0..<CARD_DEMO_GLOVE_PAPER { paper_outline_grow(layers[:], staged[:], w, h, .Paper, ring%2 == 1) }
	paper_outline_grow(layers[:], staged[:], w, h, .Cut, true)
	for y in 0..<CARD_DEMO_GLOVE_HEIGHT {
		for x in 0..<CARD_DEMO_GLOVE_WIDTH {
			#partial switch layers[y*w+x] {
			case .Ink, .Cut: print[y][x] = LIVING_TOKEN_INK
			case .Paper: print[y][x] = LIVING_TOKEN_PAPER
			}
		}
	}
	// The cut edge shows the paper's thickness, down and right.
	for y := CARD_DEMO_GLOVE_HEIGHT-1; y > 0; y -= 1 {
		for x := CARD_DEMO_GLOVE_WIDTH-1; x > 0; x -= 1 {
			if layers[y*w+x] == .Clear && layers[(y-1)*w+x-1] != .Clear { print[y][x] = LIVING_TOKEN_EDGE }
		}
	}
	return
}

// The glove's top left on the stage for its tip at `at`, on whole pixels.
card_demo_glove_origin :: proc(at: view.Vec2, glove: Card_Demo_Glove) -> rl.Vector2 {
	tip := CARD_DEMO_GLOVE_POINT_TIP if glove == .Point else CARD_DEMO_GLOVE_GRAB_TIP
	p := CARD_DEMO_GLOVE_PIXEL
	m := f32(CARD_DEMO_GLOVE_MARGIN)
	return {math.round(at.x-(tip.x+m)*p), math.round(at.y-(tip.y+m)*p)}
}

card_demo_glove_bounds :: proc(at: view.Vec2, glove: Card_Demo_Glove) -> rl.Rectangle {
	origin := card_demo_glove_origin(at, glove)
	return {origin.x, origin.y, f32(CARD_DEMO_GLOVE_WIDTH)*CARD_DEMO_GLOVE_PIXEL, f32(CARD_DEMO_GLOVE_HEIGHT)*CARD_DEMO_GLOVE_PIXEL}
}

// The glove with its tip at `at`: each row's runs of one colour, so a fading
// glove stays even.
draw_card_demo_glove :: proc(at: view.Vec2, glove: Card_Demo_Glove, alpha: f32 = 1) {
	if alpha <= 0 { return }
	print := card_demo_glove_paint(glove)
	origin := card_demo_glove_origin(at, glove)
	p := CARD_DEMO_GLOVE_PIXEL
	for y in 0..<CARD_DEMO_GLOVE_HEIGHT {
		x := 0
		for x < CARD_DEMO_GLOVE_WIDTH {
			color := print[y][x]
			start := x
			for x < CARD_DEMO_GLOVE_WIDTH && print[y][x] == color { x += 1 }
			if color.a == 0 { continue }
			rl.DrawRectangleRec({origin.x+f32(start)*p, origin.y+f32(y)*p, f32(x-start)*p, p}, color_with_opacity(color, alpha))
		}
	}
}

// A click under the glove's finger: a ring of paper with its ink, spreading
// as it fades (`t` from 0 to 1).
draw_card_demo_click :: proc(at: view.Vec2, t: f32) {
	if t < 0 || t >= 1 { return }
	alpha := 1-t
	radius := 6+t*10
	center := rl.Vector2{math.round(at.x), math.round(at.y)}
	rl.DrawRing(center, radius-1, radius+3, 0, 360, 24, color_with_opacity(LIVING_TOKEN_INK, alpha*0.9))
	rl.DrawRing(center, radius, radius+2, 0, 360, 24, color_with_opacity(LIVING_TOKEN_PAPER, alpha))
}

// The plate of the film's caption: at the stage's bottom left, beside a hand
// of one card, clear of the board, the hand, its energy and the card
// inspector. `high` (a film whose hand grows past one card, which would reach
// under the plate) stands it over the hand's left end instead, above its
// ENERGIA line, unless the board's bar shows something there (ATTIVA, the
// traps' line, the weapon): then it stays low.
card_demo_caption_bounds :: proc(renderer: ^Renderer, room: ^game.Room, high: bool) -> rl.Rectangle {
	low := rl.Rectangle{16, renderer.canvas_height-66, 364, 46}
	if !high || card_demo_bar_shown(room) { return low }
	return {low.x, renderer.canvas_height-TACTICAL_HAND_HEIGHT-14-low.height-6, low.width, low.height}
}

// Whether the board's bar over the hand shows anything (draw_m8_active_bar).
card_demo_bar_shown :: proc(room: ^game.Room) -> bool {
	if room == nil || room.player == nil { return false }
	equipment := &room.player.equipment
	return m8_control_visible(room, .Activate) || m8_control_visible(room, .Equip) || game.board_device_count(room, .Shock_Floor) > 0 ||
	       equipment.weapon.id != .None || equipment.reserve.id != .None
}

// Room for the caption's words on its plate `b`, after its key's cap.
card_demo_caption_text_bounds :: proc(renderer: ^Renderer, b: rl.Rectangle, key: cstring) -> rl.Rectangle {
	left := b.x+14
	if key != nil && key != "" { left += card_demo_caption_key_width(renderer, key)+10 }
	return {left, b.y+(b.height-20)*0.5, b.x+b.width-12-left, 22}
}

CARD_DEMO_CAPTION_SIZE :: 16

card_demo_caption_key_width :: proc(renderer: ^Renderer, key: cstring) -> f32 {
	return max(f32(24), gothic_text_width(renderer, key, 14)+12)
}

// What the glove does, in words, on its plate `b` (card_demo_caption_bounds):
// the key it presses on its cap (none for the mouse alone), then the words.
draw_card_demo_caption :: proc(renderer: ^Renderer, b: rl.Rectangle, key, text: cstring) {
	if text == nil || text == "" { return }
	hud_frame(b, GOTHIC_BLUE)
	if key != nil && key != "" {
		width := card_demo_caption_key_width(renderer, key)
		cap_bounds := rl.Rectangle{b.x+12, b.y+(b.height-26)*0.5, width, 26}
		rl.DrawRectangleRec(cap_bounds, GOTHIC_PAPER)
		rl.DrawRectangleRec({cap_bounds.x+1, cap_bounds.y+1, cap_bounds.width-2, 1}, rl.WHITE)
		rl.DrawRectangleRec({cap_bounds.x, cap_bounds.y+cap_bounds.height-2, cap_bounds.width, 2}, GOTHIC_MUTED)
		gothic_text(renderer, key, math.round(cap_bounds.x+(cap_bounds.width-gothic_text_width(renderer, key, 14))*0.5), cap_bounds.y+3, 14, GOTHIC_INK)
	}
	gothic_text_fit(renderer, text, card_demo_caption_text_bounds(renderer, b, key), CARD_DEMO_CAPTION_SIZE, GOTHIC_PAPER)
}

// A plate of the HUD lit up (what the card did shows there): a frame of paper
// cut round it, its ink lines in and out, beating CARD_DEMO_HIGHLIGHT_BEATS
// times as it fades (`left` from 1 to 0).
draw_card_demo_highlight :: proc(bounds: rl.Rectangle, left: f32) {
	if left <= 0 { return }
	beat := 0.65+0.35*math.cos(f32(1-left)*CARD_DEMO_HIGHLIGHT_BEATS*2*math.PI)
	alpha := clamp(left*3, 0, 1)*beat
	b := rl.Rectangle{math.round(bounds.x)-5, math.round(bounds.y)-5, math.round(bounds.width)+10, math.round(bounds.height)+10}
	rl.DrawRectangleLinesEx(b, 1, color_with_opacity(LIVING_TOKEN_INK, alpha))
	rl.DrawRectangleLinesEx({b.x+1, b.y+1, b.width-2, b.height-2}, 2, color_with_opacity(LIVING_TOKEN_PAPER, alpha))
	rl.DrawRectangleLinesEx({b.x+3, b.y+3, b.width-6, b.height-6}, 1, color_with_opacity(LIVING_TOKEN_INK, alpha))
}

// How many times the lit plate beats over its whole light (CARD_DEMO_VITALS_FLASH).
CARD_DEMO_HIGHLIGHT_BEATS :: f32(3)

// Between two takes the stage goes dark a moment (`dark` from 0 to 1).
draw_card_demo_fade :: proc(renderer: ^Renderer, dark: f32) {
	if dark <= 0 { return }
	rl.DrawRectangleRec({0, 0, renderer.canvas_width, renderer.canvas_height}, color_with_opacity(RESIN_BACKGROUND, clamp(dark, 0, 1)))
}
