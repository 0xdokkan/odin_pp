package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"

GOTHIC_INK :: rl.Color{13, 13, 16, 255}
GOTHIC_PAPER :: rl.Color{218, 207, 184, 255}
GOTHIC_MUTED :: rl.Color{147, 133, 121, 255}
GOTHIC_RED :: rl.Color{174, 39, 51, 255}
GOTHIC_DARK_RED :: rl.Color{72, 17, 25, 255}
GOTHIC_STEEL :: rl.Color{43, 53, 69, 255}
GOTHIC_BLUE :: rl.Color{125, 170, 203, 255}
GOTHIC_RECESS :: rl.Color{19, 25, 34, 255}
GOTHIC_FONT_SIZES :: [?]int{10, 12, 14, 16, 18, 24, 32}

Gothic_Art :: struct {
	icons, figures, paper: rl.Texture2D,
	figure_sources, icon_sources: [16]rl.Rectangle,
	figure_alpha: []u8,
	fonts: [len(GOTHIC_FONT_SIZES)]rl.Font,
}

gothic_hash :: proc(x, y: int) -> u32 {
	n := u32(x)*0x45d9f3b+u32(y)*0x119de1f3+0x27d4eb2d
	n = (n~(n>>16))*0x45d9f3b
	return n~(n>>16)
}

// Embedded art works from any working directory. External sprite packs still
// override these defaults through the existing --sprites interface.
create_gothic_art :: proc(art: ^Gothic_Art) {
	icon_bytes := #load("../../assets/gothic/card-icons-pixel.png")
	figure_bytes := #load("../../assets/gothic/figures-v2.png")
	for bytes, index in ([?][]u8{icon_bytes, figure_bytes}) {
		img := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
		if img.data == nil { continue }
		colors := rl.LoadImageColors(img)
		texture := rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(texture, .POINT)
		sources := &art.icon_sources if index == 0 else &art.figure_sources
		if index == 0 { art.icons = texture }
		else {
			art.figures = texture
			art.figure_alpha = make([]u8, int(img.width)*int(img.height))
			for &alpha, at in art.figure_alpha { alpha = colors[at].a }
		}
		for cell in 0..<16 {
			left, right := cell%4*int(img.width)/4, (cell%4+1)*int(img.width)/4
			top, bottom := cell/4*int(img.height)/4, (cell/4+1)*int(img.height)/4
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
destroy_gothic_art :: proc(art: ^Gothic_Art) {
	for texture in ([?]rl.Texture2D{art.icons, art.figures, art.paper}) { if texture.id != 0 { rl.UnloadTexture(texture) } }
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
gothic_text_width :: proc(renderer: ^Renderer, text: cstring, size: int) -> f32 {
	font, actual := gothic_font(renderer, size)
	return rl.MeasureTextEx(font, text, actual, 1).x
}
gothic_text :: proc(renderer: ^Renderer, text: cstring, x, y: f32, size: int, color: rl.Color) {
	font, actual := gothic_font(renderer, size)
	rl.DrawTextEx(font, text, {math.round(x), math.round(y)}, actual, 1, color)
}
gothic_text_fit :: proc(renderer: ^Renderer, text: cstring, bounds: rl.Rectangle, size: int, color: rl.Color) {
	chosen := size
	for chosen > 10 && gothic_text_width(renderer, text, chosen) > bounds.width { chosen -= 2 }
	label := text
	if gothic_text_width(renderer, label, chosen) > bounds.width {
		value := string(text)
		end := len(value)
		for end > 0 && gothic_text_width(renderer, fmt.ctprintf("%s...", value[:end]), chosen) > bounds.width { end -= 1 }
		label = fmt.ctprintf("%s...", value[:end])
	}
	rl.BeginScissorMode(c.int(bounds.x), c.int(bounds.y), c.int(bounds.width), c.int(bounds.height))
	gothic_text(renderer, label, bounds.x, bounds.y, chosen, color)
	rl.EndScissorMode()
}
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
gothic_inlay :: proc(x, y, radius: f32, color: rl.Color) {
	rl.DrawPoly({x, y}, 4, radius+1, 0, GOTHIC_INK)
	rl.DrawPoly({x, y}, 4, radius, 0, color)
	rl.DrawRectangleRec({x-1, y-radius+2, 2, 2}, {235, 237, 224, 195})
	rl.DrawRectangleRec({x-1, y+radius-3, 2, 2}, {13, 20, 33, 110})
}
gothic_rule :: proc(x, y, width: f32, color: rl.Color = GOTHIC_MUTED) {
	rl.DrawRectangle(c.int(x), c.int(y), c.int(width), 1, color)
	rl.DrawRectangle(c.int(x), c.int(y-1), 3, 3, color)
	rl.DrawRectangle(c.int(x+width-3), c.int(y-1), 3, 3, color)
}
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
gothic_atlas_icon :: proc(texture: rl.Texture2D, source, bounds: rl.Rectangle, tint: rl.Color = rl.WHITE) {
	if texture.id == 0 || source.width <= 0 || source.height <= 0 { return }
	scale := min(bounds.width/source.width, bounds.height/source.height)
	w, h := math.floor(source.width*scale), math.floor(source.height*scale)
	rl.DrawTexturePro(texture, source, {math.floor(bounds.x+(bounds.width-w)*0.5), math.floor(bounds.y+(bounds.height-h)*0.5), w, h}, {}, 0, tint)
}

gothic_card_icon :: proc(id: game.Card_Id) -> int {
	switch id {
	case .Strike, .Cross_Slash: return 0
	case .Guard: return 1
	case .Toxic_Wave, .Venom_Needle, .Caustic_Bloom, .Twin_Venom: return 2
	case .Shove: return 3
	case .Arc_Bolt, .Piercing_Ray: return 4
	case .Dash, .Afterimage: return 5
	case .Firebomb: return 6
	case .Thorn_Coat: return 7
	case .Counter_Rune: return 8
	case .Battle_Focus, .Calculated_Risk, .Volatile_Study: return 9
	case .Spark_Forge, .Spark: return 10
	case .Grappling_Hook: return 11
	case .Heavy_Blow, .Sundering_Blow: return 12
	case .Fate_Strike, .Prismatic_Barrage: return 13
	case .Chain_Lightning: return 14
	case .Purifying_Guard: return 15
	case .Count: return 0
	}
	return 0
}
gothic_figure_index :: proc(key: Sprite_Key) -> int {
	if key == .Player_Cast { return 12 }
	if key == .Player_Hit { return 13 }
	if key <= .Demolitionist { return int(key) }
	if key >= .Ice_Block && key <= .Bomb { return int(key)+1 }
	return 0
}

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

draw_gothic_status :: proc(renderer: ^Renderer, room: ^game.Room) {
	draw_tactical_status(renderer, room)
}
