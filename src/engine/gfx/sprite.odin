// Rendering helpers shared by minigames: pixel-art sprites authored as rows of
// characters, a lit/fogged 3D material, greedy-free voxel meshing and a few
// procedural backdrops. Content stays in code, so no asset files are needed.
package gfx

import "core:math"
import rl "vendor:raylib"

Vec2 :: [2]f32
Vec3 :: [3]f32

// Character -> colour. Unset entries (alpha 0) are transparent, so '.' or ' '
// work as empty pixels without being declared.
Pixel_Palette :: [128]rl.Color

palette_set :: proc(p: ^Pixel_Palette, ch: u8, color: rl.Color) {
	if ch < 128 {
		p[ch] = color
	}
}

// One frame is a list of equal-length rows.
Frame_Rows :: []string

Sprite :: struct {
	texture:       rl.Texture2D,
	width, height: int, // one frame, in pixels
	frames:        int,
}

// Packs the frames side by side into one texture with nearest filtering.
sprite_create :: proc(frames: []Frame_Rows, palette: ^Pixel_Palette) -> (Sprite, bool) {
	if len(frames) == 0 || len(frames[0]) == 0 {
		return {}, false
	}
	h := len(frames[0])
	w := len(frames[0][0])
	for f in frames {
		if len(f) != h {
			return {}, false
		}
		for r in f {
			if len(r) != w {
				return {}, false
			}
		}
	}
	img := rl.GenImageColor(i32(w*len(frames)), i32(h), rl.BLANK)
	for f, fi in frames {
		for r, y in f {
			for x in 0..<w {
				ch := r[x]
				if ch >= 128 {
					continue
				}
				c := palette[ch]
				if c.a == 0 {
					continue
				}
				rl.ImageDrawPixel(&img, i32(fi*w+x), i32(y), c)
			}
		}
	}
	texture := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	if texture.id == 0 {
		return {}, false
	}
	rl.SetTextureFilter(texture, .POINT)
	return Sprite{texture = texture, width = w, height = h, frames = len(frames)}, true
}

sprite_destroy :: proc(s: ^Sprite) {
	if s.texture.id != 0 {
		rl.UnloadTexture(s.texture)
	}
	s^ = {}
}

sprite_source :: proc(s: Sprite, frame: int, flip_x := false, flip_y := false) -> rl.Rectangle {
	f := clamp(frame, 0, max(s.frames-1, 0))
	r := rl.Rectangle{f32(f * s.width), 0, f32(s.width), f32(s.height)}
	if flip_x {
		r.width = -r.width
	}
	if flip_y {
		r.height = -r.height
	}
	return r
}

// Draws a frame centred at `center`, scaled by `scale` pixels per sprite pixel.
draw_sprite :: proc(s: Sprite, frame: int, center: Vec2, scale: f32 = 1, flip_x := false,
	tint := rl.WHITE, rotation: f32 = 0, flip_y := false) {
	if s.texture.id == 0 {
		return
	}
	w := f32(s.width) * scale
	h := f32(s.height) * scale
	dest := rl.Rectangle{math.round(center.x), math.round(center.y), w, h}
	rl.DrawTexturePro(s.texture, sprite_source(s, frame, flip_x, flip_y), dest, {w * 0.5, h * 0.5}, rotation, tint)
}

// Same, anchored at the bottom centre (feet), the natural pivot for characters.
draw_sprite_feet :: proc(s: Sprite, frame: int, feet: Vec2, scale: f32 = 1, flip_x := false,
	tint := rl.WHITE, squash: Vec2 = {1, 1}) {
	if s.texture.id == 0 {
		return
	}
	w := f32(s.width) * scale * squash.x
	h := f32(s.height) * scale * squash.y
	dest := rl.Rectangle{math.round(feet.x), math.round(feet.y), w, h}
	rl.DrawTexturePro(s.texture, sprite_source(s, frame, flip_x), dest, {w * 0.5, h}, 0, tint)
}

// Camera-facing sprite standing on `feet`, `height` world units tall.
draw_billboard :: proc(camera: rl.Camera3D, s: Sprite, frame: int, feet: Vec3, height: f32,
	tint := rl.WHITE, flip_x := false) {
	if s.texture.id == 0 {
		return
	}
	width := height * f32(s.width) / f32(s.height)
	center := feet + Vec3{0, height * 0.5, 0}
	rl.DrawBillboardRec(camera, s.texture, sprite_source(s, frame, flip_x), center, {width, height}, tint)
}

// Frame index for a looping or one-shot animation of `count` frames.
anim_frame :: proc "contextless" (time, fps: f32, first, count: int, loop := true) -> int {
	if count <= 1 || fps <= 0 {
		return first
	}
	f := int(time * fps)
	if loop {
		return first + f%count
	}
	return first + min(f, count-1)
}
