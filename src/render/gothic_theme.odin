package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import ui "../engine/ui"

// Semantic colors belong to the engine UI; the world/card art keeps its own materials.
GOTHIC_INK :: ui.GOTHIC_PALETTE.background
GOTHIC_PAPER :: ui.GOTHIC_PALETTE.text
GOTHIC_MUTED :: ui.GOTHIC_PALETTE.text_dim
GOTHIC_RED :: ui.GOTHIC_PALETTE.danger
GOTHIC_DARK_RED :: rl.Color{72, 17, 25, 255}
GOTHIC_STEEL :: ui.GOTHIC_PALETTE.border
GOTHIC_BLUE :: ui.GOTHIC_PALETTE.focus
GOTHIC_RECESS :: ui.GOTHIC_PALETTE.panel
GOTHIC_FONT_SIZES :: [?]int{10, 12, 14, 16, 18, 24, 32}

// The card icon atlas: the 16 painted icons in four rows of four, then the
// rows added by tools/art/build_card_icons.py (cell 16: Movimento Ombra, 17:
// Pozza di Veleno, 18: Incendio, 19: Deflect, 20: Feretro, 21: Dado del
// Destino, 22: Lama Velenosa, 23: Lazzo, 24: Canna da Pesca, 25: Pinball,
// 26: First Person Shooter, 27: Bomb Marley, 28: Inondazione, 29: Cannone, 30:
// Cannone laser, 31: Buco nero, 32: Dinosauro; 33-35 are free).
CARD_ICON_COLUMNS :: 4
CARD_ICON_ROWS :: 9
CARD_ICON_CELLS :: CARD_ICON_COLUMNS*CARD_ICON_ROWS
// The figure atlas: four rows of four.
GOTHIC_FIGURE_CELLS :: 16

Gothic_Art :: struct {
	icons, figures, paper: rl.Texture2D,
	// The Scopa 6 and 7 of coins (tools/art/build_scopa.py), side by side.
	scopa: rl.Texture2D,
	figure_sources: [GOTHIC_FIGURE_CELLS]rl.Rectangle,
	icon_sources: [CARD_ICON_CELLS]rl.Rectangle,
	figure_alpha: []u8,
	fonts: [len(GOTHIC_FONT_SIZES)]rl.Font,
}

// A cell of a four-column atlas `rows` cells high, in pixels (right and
// bottom excluded). The icons' added rows leave the painted four where they
// were: 2195/7, 1881/6 and 1254/4 rows start on the same pixels.
@(private)
gothic_atlas_cell :: proc(cell, rows, width, height: int) -> (left, top, right, bottom: int) {
	return cell%CARD_ICON_COLUMNS*width/CARD_ICON_COLUMNS, cell/CARD_ICON_COLUMNS*height/rows,
		(cell%CARD_ICON_COLUMNS+1)*width/CARD_ICON_COLUMNS, (cell/CARD_ICON_COLUMNS+1)*height/rows
}

@(private)
gothic_hash :: proc(x, y: int) -> u32 {
	n := u32(x)*0x45d9f3b+u32(y)*0x119de1f3+0x27d4eb2d
	n = (n~(n>>16))*0x45d9f3b
	return n~(n>>16)
}

// Embedded art works from any working directory. External sprite packs still
// override these defaults through the existing --sprites interface.
@(private)
create_gothic_art :: proc(art: ^Gothic_Art) {
	icon_bytes := #load("../../assets/gothic/card-icons-pixel.png")
	figure_bytes := #load("../../assets/gothic/figures-v2.png")
	for bytes, index in ([?][]u8{icon_bytes, figure_bytes}) {
		img := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
		if img.data == nil { continue }
		colors := rl.LoadImageColors(img)
		texture := rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(texture, .POINT)
		sources := art.icon_sources[:] if index == 0 else art.figure_sources[:]
		atlas_rows := len(sources)/CARD_ICON_COLUMNS
		if index == 0 { art.icons = texture }
		else {
			art.figures = texture
			art.figure_alpha = make([]u8, int(img.width)*int(img.height))
			for &alpha, at in art.figure_alpha { alpha = colors[at].a }
		}
		for cell in 0..<len(sources) {
			left, top, right, bottom := gothic_atlas_cell(cell, atlas_rows, int(img.width), int(img.height))
			if index == 1 {
				// The generated 1254px sheet has uneven transparent gutters.
				// Explicit regions keep every figure whole and isolated; crop
				// only inside its region, retaining the original PNG unchanged.
				columns := [5]int{0, 320, 640, 940, 1254}
				rows := [5]int{0, 350, 675, 923, 1254}
				left, right = columns[cell%4]*int(img.width)/1254, columns[cell%4+1]*int(img.width)/1254
				top, bottom = rows[cell/4]*int(img.height)/1254, rows[cell/4+1]*int(img.height)/1254
			}
			x0, y0, x1, y1 := right, bottom, left, top
			for y in top..<bottom { for x in left..<right {
				if colors[y*int(img.width)+x].a > 32 {
					x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
				}
			} }
			sources[cell] = {f32(x0), f32(y0), f32(max(1, x1-x0+1)), f32(max(1, y1-y0+1))}
		}
		rl.UnloadImageColors(colors)
		rl.UnloadImage(img)
	}
	paper := rl.GenImageColor(96, 128, GOTHIC_PAPER)
	for y in 0..<128 { for x in 0..<96 {
		n := gothic_hash(x/2, y/2)
		shade := i32(n%13)-6
		if min(min(x, 95-x), min(y, 127-y)) < 5 { shade -= 8 }
		rl.ImageDrawPixel(&paper, c.int(x), c.int(y), {u8(218+shade), u8(207+shade), u8(184+shade), 255})
	} }
	art.paper = rl.LoadTextureFromImage(paper)
	scopa_bytes := #load("../../assets/gothic/scopa-denari.png")
	if scopa := rl.LoadImageFromMemory(".png", raw_data(scopa_bytes), c.int(len(scopa_bytes))); scopa.data != nil {
		art.scopa = rl.LoadTextureFromImage(scopa)
		rl.SetTextureFilter(art.scopa, .POINT)
		rl.UnloadImage(scopa)
	}
	rl.SetTextureFilter(art.paper, .POINT)
	rl.UnloadImage(paper)
	body_bytes := #load("../../assets/fonts/Jersey10-Regular.ttf")
	for size, index in GOTHIC_FONT_SIZES {
		bytes := body_bytes
		raster_size := size+4 if size < 24 else size+8
		font := rl.LoadFontFromMemory(".ttf", raw_data(bytes), c.int(len(bytes)), c.int(raster_size), nil, 0)
		if font.texture.id == 0 { continue }
		// Quantize the glyph coverage once; no grayscale fringe when scaled.
		img := rl.LoadImageFromTexture(font.texture)
		pixels := rl.LoadImageColors(img)
		for i in 0..<int(img.width*img.height) { pixels[i].a = 255 if pixels[i].a >= 100 else 0 }
		rl.UnloadTexture(font.texture)
		font.texture = rl.LoadTextureFromImage({data = pixels, width = img.width, height = img.height, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8})
		rl.UnloadImageColors(pixels)
		rl.UnloadImage(img)
		rl.SetTextureFilter(font.texture, .POINT)
		art.fonts[index] = font
	}
}
@(private)
destroy_gothic_art :: proc(art: ^Gothic_Art) {
	for texture in ([?]rl.Texture2D{art.icons, art.figures, art.paper, art.scopa}) { if texture.id != 0 { rl.UnloadTexture(texture) } }
	for font in art.fonts { if font.texture.id != 0 { rl.UnloadFont(font) } }
	delete(art.figure_alpha)
	art^ = {}
}
gothic_font :: proc(renderer: ^Renderer, size: int) -> (rl.Font, f32) {
	sizes := GOTHIC_FONT_SIZES
	index := 0
	for value, i in sizes { if abs(value-size) < abs(sizes[index]-size) { index = i } }
	font := renderer.tactical.art.fonts[index]
	if font.texture.id == 0 { return rl.GetFontDefault(), f32(size) }
	return font, f32(sizes[index]+4 if sizes[index] < 24 else sizes[index]+8)
}
gothic_text_width :: proc(renderer: ^Renderer, text: cstring, size: int, spacing: f32 = 1) -> f32 {
	font, actual := gothic_font(renderer, size)
	return rl.MeasureTextEx(font, text, actual, spacing).x
}
gothic_text :: proc(renderer: ^Renderer, text: cstring, x, y: f32, size: int, color: rl.Color, spacing: f32 = 1) {
	font, actual := gothic_font(renderer, size)
	rl.DrawTextEx(font, text, {math.round(x), math.round(y)}, actual, spacing, color)
}
// How gothic_text_fit sets a text in a width: as it is, its letters closed up,
// a size smaller, or cut short ("...").
Gothic_Fit :: enum {Fits, Closed, Smaller, Cut}
GOTHIC_CPU_TEXT_CLIP :: #config(GOTHIC_CPU_TEXT_CLIP,true)

// The size, letter spacing and words gothic_text_fit draws `text` with in
// `width`, and how it had to fit them.
gothic_text_fit_plan :: proc(renderer: ^Renderer, text: cstring, width: f32, size: int) -> (chosen: int, spacing: f32, label: cstring, fit: Gothic_Fit) {
	if gothic_text_width(renderer, text, size) <= width { return size, 1, text, .Fits }
	// The pixel font is crisp only at some sizes; a smaller one bends its
	// figures (an "o" reads as an "a"). Close the letters up first.
	if gothic_text_width(renderer, text, size, 0) <= width { return size, 0, text, .Closed }
	chosen = size
	for chosen > 10 && gothic_text_width(renderer, text, chosen) > width { chosen -= 2 }
	if gothic_text_width(renderer, text, chosen) <= width { return chosen, 1, text, .Smaller }
	value := string(text)
	end := len(value)
	for end > 0 && gothic_text_width(renderer, fmt.ctprintf("%s...", value[:end]), chosen) > width { end -= 1 }
	return chosen, 1, fmt.ctprintf("%s...", value[:end]), .Cut
}

gothic_text_fit :: proc(renderer: ^Renderer, text: cstring, bounds: rl.Rectangle, size: int, color: rl.Color) {
	chosen, spacing, label, _ := gothic_text_fit_plan(renderer, text, bounds.width, size)
	font,actual:=gothic_font(renderer,chosen)
	when GOTHIC_CPU_TEXT_CLIP {
		draw_gothic_text_clipped(font,label,bounds,actual,spacing,color)
	} else {
		draw_gothic_text_scissored(font,label,bounds,actual,spacing,color)
	}
}
@(private)
gothic_wrapped_text :: proc(renderer: ^Renderer, value: string, x, y, width: f32, color: rl.Color) {
	start, last_space := 0, -1
	line_y := y
	for index in 0..<len(value) {
		if value[index] == ' ' { last_space = index }
		if gothic_text_width(renderer, fmt.ctprintf("%s", value[start:index+1]), 14) <= width || last_space < start { continue }
		gothic_text(renderer, fmt.ctprintf("%s", value[start:last_space]), x, line_y, 14, color)
		line_y += 18
		start, last_space = last_space+1, -1
	}
	if start < len(value) { gothic_text(renderer, fmt.ctprintf("%s", value[start:]), x, line_y, 14, color) }
}
gothic_frame :: proc(bounds: rl.Rectangle, fill, edge: rl.Color, parchment: bool = false, art: ^Gothic_Art = nil) {
	x, y, w, h := bounds.x, bounds.y, bounds.width, bounds.height
	rl.DrawRectangleRec({x+5, y, w-10, h}, edge)
	rl.DrawRectangleRec({x+2, y+3, w-4, h-6}, edge)
	rl.DrawRectangleRec({x, y+7, w, h-14}, edge)
	rl.DrawRectangleRec({x+5, y+4, w-10, h-8}, fill)
	rl.DrawRectangleRec({x+3, y+8, w-6, h-16}, fill)
	if parchment && art != nil && art.paper.id != 0 {
		rl.DrawTexturePro(art.paper, {0, 0, f32(art.paper.width), f32(art.paper.height)}, {x+6, y+7, w-12, h-14}, {}, 0, rl.WHITE)
	}
	// A restrained bevel keeps panels looking like inset metal, even at the
	// native pixel resolution. All ornament stays inside the original bounds.
	rl.DrawRectangleLinesEx({x+5, y+6, w-10, h-12}, 1, GOTHIC_MUTED if parchment else GOTHIC_STEEL)
	rl.DrawRectangleRec({x+8, y+2, w-16, 1}, GOTHIC_PAPER if parchment else GOTHIC_STEEL)
	rl.DrawRectangleRec({x+8, y+h-3, w-16, 1}, GOTHIC_INK)
	if parchment {
		rl.DrawRectangleRec({x+8, y+8, 1, h-17}, {247, 238, 214, 135})
		rl.DrawRectangleRec({x+w-9, y+9, 1, h-18}, {76, 67, 56, 85})
	}
	for corner in 0..<4 {
		cx := x+7 if corner%2 == 0 else x+w-10
		cy := y+8 if corner/2 == 0 else y+h-11
		rl.DrawRectangle(c.int(cx), c.int(cy), 3, 3, edge)
		rl.DrawPixel(c.int(cx), c.int(cy), GOTHIC_PAPER)
	}
}
// Pixel-cut inlay shared by resource gems and rarity marks. No smooth shapes
// or per-frame textures are needed for the small decorative details.
@(private)
gothic_inlay :: proc(x, y, radius: f32, color: rl.Color) {
	rl.DrawPoly({x, y}, 4, radius+1, 0, GOTHIC_INK)
	rl.DrawPoly({x, y}, 4, radius, 0, color)
	rl.DrawRectangleRec({x-1, y-radius+2, 2, 2}, {235, 237, 224, 195})
	rl.DrawRectangleRec({x-1, y+radius-3, 2, 2}, {13, 20, 33, 110})
}
@(private)
gothic_rule :: proc(x, y, width: f32, color: rl.Color = GOTHIC_MUTED) {
	rl.DrawRectangle(c.int(x), c.int(y), c.int(width), 1, color)
	rl.DrawRectangle(c.int(x), c.int(y-1), 3, 3, color)
	rl.DrawRectangle(c.int(x+width-3), c.int(y-1), 3, 3, color)
}
@(private)
gothic_button :: proc(renderer: ^Renderer, bounds: rl.Rectangle, key, label: cstring, enabled: bool = true) {
	color := GOTHIC_PAPER if enabled else GOTHIC_MUTED
	rl.DrawRectangleRec(bounds, GOTHIC_RECESS)
	rl.DrawRectangleLinesEx(bounds, 1, GOTHIC_STEEL)
	rl.DrawRectangleRec({bounds.x+2, bounds.y+1, bounds.width-4, 1}, color)
	rl.DrawRectangleRec({bounds.x+2, bounds.y+bounds.height-2, bounds.width-4, 1}, GOTHIC_INK)
	key_width := max(f32(20), gothic_text_width(renderer, key, 16)+8)
	rl.DrawRectangleRec({bounds.x+4, bounds.y+4, key_width, bounds.height-8}, color)
	rl.DrawRectangleRec({bounds.x+5, bounds.y+5, key_width-2, 1}, rl.WHITE if enabled else GOTHIC_PAPER)
	gothic_text(renderer, key, bounds.x+8, bounds.y+3, 16, GOTHIC_INK)
	gothic_text_fit(renderer, label, {bounds.x+key_width+10, bounds.y+4, bounds.width-key_width-15, bounds.height-6}, 14, color)
}
@(private)
gothic_atlas_icon :: proc(texture: rl.Texture2D, source, bounds: rl.Rectangle, tint: rl.Color = rl.WHITE) {
	if texture.id == 0 || source.width <= 0 || source.height <= 0 { return }
	scale := min(bounds.width/source.width, bounds.height/source.height)
	w, h := math.floor(source.width*scale), math.floor(source.height*scale)
	rl.DrawTexturePro(texture, source, {math.floor(bounds.x+(bounds.width-w)*0.5), math.floor(bounds.y+(bounds.height-h)*0.5), w, h}, {}, 0, tint)
}

@(private)
gothic_figure_index :: proc(key: Sprite_Key) -> int {
	if key == .Player_Cast { return 12 }
	if key == .Player_Hit { return 13 }
	if key <= .Demolitionist { return int(key) }
	if key >= .Ice_Block && key <= .Bomb { return int(key)+1 }
	return 0
}

@(private = "file")
draw_gothic_backdrop :: proc(renderer: ^Renderer) {
	rl.ClearBackground(GOTHIC_INK)
	p := renderer.tactical.snapshot.player.position
	for layer in 0..<3 {
		for column in -2..<9 {
			x := f32(column*180+layer*71)-p.x*f32(3+layer*4)-p.y*f32(layer*2)
			height := f32(130+gothic_hash(column+20, layer)%180)
			base := f32(325+layer*12)
			fill := rl.Color{u8(15+layer*3), u8(14+layer*2), u8(18+layer*3), 255}
			rl.DrawRectangle(c.int(x), c.int(base-height), 61, c.int(height), fill)
			for step in 0..<5 { rl.DrawRectangle(c.int(x+f32(step*5)), c.int(base-height-5-f32(step*6)), c.int(61-step*10), 10, fill) }
			rl.DrawRectangle(c.int(x+18), c.int(base-height+22), 18, c.int(height-22), rl.Color{u8(27+layer*5), 13, 20, 255})
			rl.DrawRectangle(c.int(x+24), c.int(base-height+50), 6, 37, GOTHIC_INK)
			if layer == 2 {
				for link in 0..<16 { rl.DrawRectangle(c.int(x+4+f32(link*6)), c.int(base-height+f32(link*9)), 6, 9, GOTHIC_INK) }
			}
		}
	}
}

@(private)
draw_gothic_status :: proc(renderer: ^Renderer, room: ^game.Room) {
	draw_tactical_status(renderer, room)
}
