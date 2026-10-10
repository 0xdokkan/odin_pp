package ui

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Text_Size :: enum u8 {
	Small,
	Body,
	Large,
	Title,
	Huge,
}

TEXT_PIXELS :: [Text_Size]f32{
	.Small = 16,
	.Body  = 20,
	.Large = 28,
	.Title = 40,
	.Huge  = 64,
}

text_pixels :: proc "contextless" (size: Text_Size) -> f32 {
	switch size {
	case .Small:
		return 16
	case .Body:
		return 20
	case .Large:
		return 28
	case .Title:
		return 40
	case .Huge:
		return 64
	}
	return 20
}

Palette :: struct {
	background:    rl.Color,
	panel:         rl.Color,
	panel_alt:     rl.Color,
	border:        rl.Color,
	text:          rl.Color,
	text_dim:      rl.Color,
	accent:        rl.Color,
	accent_text:   rl.Color,
	button:        rl.Color,
	button_hover:  rl.Color,
	button_down:   rl.Color,
	disabled:      rl.Color,
	focus:         rl.Color,
	danger:        rl.Color,
	success:       rl.Color,
	warning:       rl.Color,
	shadow:        rl.Color,
}

// Ivory and crimson on slate, matching the roguelike HUD.
GOTHIC_PALETTE :: Palette{
	background   = {14, 16, 22, 255},
	panel        = {26, 29, 38, 238},
	panel_alt    = {36, 40, 52, 240},
	border       = {92, 84, 72, 255},
	text         = {236, 226, 204, 255},
	text_dim     = {160, 152, 136, 255},
	accent       = {178, 38, 52, 255},
	accent_text  = {255, 240, 228, 255},
	button       = {48, 52, 66, 255},
	button_hover = {66, 70, 88, 255},
	button_down  = {34, 36, 46, 255},
	disabled     = {40, 42, 50, 200},
	focus        = {232, 196, 112, 255},
	danger       = {214, 64, 64, 255},
	success      = {96, 184, 112, 255},
	warning      = {226, 168, 72, 255},
	shadow       = {0, 0, 0, 120},
}

Theme :: struct {
	palette:   Palette,
	fonts:     [Text_Size]rl.Font,
	has_fonts: bool,
	roundness: f32,
	border:    f32,
	padding:   f32,
	spacing:   f32,
}

default_theme :: proc() -> Theme {
	return Theme{palette = GOTHIC_PALETTE, roundness = 0.18, border = 2, padding = 10, spacing = 1}
}

// Printable ASCII plus Latin-1 letters, so Italian accents (àèéìòù) render.
// raylib's default set stops at 126.
FONT_CODEPOINTS :: 95 + 96

// Rasterises the embedded pixel font once per size. Coverage is quantised so
// glyphs stay crisp when the canvas is scaled.
load_fonts :: proc(theme: ^Theme) {
	bytes := #load("../../../assets/fonts/Jersey10-Regular.ttf")
	sizes := TEXT_PIXELS
	codepoints: [FONT_CODEPOINTS]rune
	for i in 0..<95 {
		codepoints[i] = rune(32 + i)
	}
	for i in 0..<96 {
		codepoints[95+i] = rune(160 + i)
	}
	loaded := 0
	for size in Text_Size {
		font := rl.LoadFontFromMemory(".ttf", raw_data(bytes), c.int(len(bytes)), c.int(sizes[size]),
			raw_data(codepoints[:]), FONT_CODEPOINTS)
		if font.texture.id == 0 {
			theme.fonts[size] = rl.GetFontDefault()
			continue
		}
		img := rl.LoadImageFromTexture(font.texture)
		pixels := rl.LoadImageColors(img)
		for i in 0..<int(img.width*img.height) {
			pixels[i].a = 255 if pixels[i].a >= 100 else 0
		}
		rl.UnloadTexture(font.texture)
		font.texture = rl.LoadTextureFromImage(rl.Image{data = pixels, width = img.width, height = img.height,
			mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8})
		rl.UnloadImageColors(pixels)
		rl.UnloadImage(img)
		rl.SetTextureFilter(font.texture, .POINT)
		theme.fonts[size] = font
		loaded += 1
	}
	theme.has_fonts = loaded > 0
}

unload_fonts :: proc(theme: ^Theme) {
	if !theme.has_fonts {
		return
	}
	default_font := rl.GetFontDefault()
	for font in theme.fonts {
		if font.texture.id != 0 && font.texture.id != default_font.texture.id {
			rl.UnloadFont(font)
		}
	}
	theme.fonts = {}
	theme.has_fonts = false
}

// Width/height of a single line. Without loaded fonts (tests, headless) a
// fixed advance is assumed so layout stays deterministic.
measure :: proc(theme: ^Theme, text: string, size: Text_Size) -> [2]f32 {
	pixels := text_pixels(size)
	if theme == nil || !theme.has_fonts {
		return {f32(len(text)) * pixels * 0.5, pixels}
	}
	ctext := cstring_temp(text)
	m := rl.MeasureTextEx(theme.fonts[size], ctext, pixels, theme.spacing)
	return {m.x, m.y}
}

// Shortens text to fit max_width, ending in "...", cutting only at UTF-8
// character boundaries. Returns the text unchanged when it already fits.
ellipsize :: proc(theme: ^Theme, text: string, max_width: f32, size: Text_Size) -> string {
	if measure(theme, text, size).x <= max_width {
		return text
	}
	end := len(text)
	for end > 0 {
		end -= 1
		for end > 0 && text[end] & 0xC0 == 0x80 {
			end -= 1
		}
		candidate := fmt.tprintf("%s...", strings.trim_right_space(text[:end]))
		if measure(theme, candidate, size).x <= max_width {
			return candidate
		}
	}
	return "..."
}

@(private)
cstring_temp :: proc(text: string) -> cstring {
	buffer := make([]u8, len(text)+1, context.temp_allocator)
	copy(buffer, text)
	return cstring(raw_data(buffer))
}

with_alpha :: proc(color: rl.Color, alpha: f32) -> rl.Color {
	return rl.Color{color.r, color.g, color.b, u8(clamp(f32(color.a)*alpha, 0, 255))}
}

mix_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	k := clamp(t, 0, 1)
	return rl.Color{
		u8(f32(a.r) + (f32(b.r)-f32(a.r))*k),
		u8(f32(a.g) + (f32(b.g)-f32(a.g))*k),
		u8(f32(a.b) + (f32(b.b)-f32(a.b))*k),
		u8(f32(a.a) + (f32(b.a)-f32(a.a))*k),
	}
}
