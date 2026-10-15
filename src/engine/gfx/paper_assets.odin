package gfx

import "core:c"
import rl "vendor:raylib"

// A pixel-art print and its smoothly sampled paper distance field. Keep a CPU
// copy of the field for picking. Living cards use a grayscale GPU field;
// flipbooks retain their original image format and shader contract.
@(private)
load_paper_textures :: proc(frame_png, paper_png: []u8, grayscale: bool) -> (frame, paper: rl.Texture2D, field: []u8) {
	for bytes, kind in ([2][]u8{frame_png, paper_png}) {
		img := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
		if img.data == nil { continue }
		defer rl.UnloadImage(img)
		if kind == 0 {
			frame = rl.LoadTextureFromImage(img)
			rl.SetTextureFilter(frame, .POINT)
		} else {
			colors := rl.LoadImageColors(img)
			field = make([]u8, int(img.width)*int(img.height))
			for &value, index in field { value = colors[index].r }
			rl.UnloadImageColors(colors)
			if grayscale { rl.ImageFormat(&img, .UNCOMPRESSED_GRAYSCALE) }
			paper = rl.LoadTextureFromImage(img)
			// No mipmaps: adjacent atlas cells must not bleed into each other.
			rl.SetTextureFilter(paper, .BILINEAR)
			rl.SetTextureWrap(paper, .CLAMP)
		}
	}
	return
}

@(private)
unload_paper_textures :: proc(frame, paper: rl.Texture2D, field: []u8) {
	if frame.id != 0 { rl.UnloadTexture(frame) }
	if paper.id != 0 { rl.UnloadTexture(paper) }
	delete(field)
}
