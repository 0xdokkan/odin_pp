package gfx

import rl "vendor:raylib"

// Keep a separate alpha silhouette: its paper edge can stay rigid while the
// sprite inside squashes. Created once, never read back during drawing.
sprite_silhouette_create :: proc(s: Sprite) -> Sprite {
	if s.texture.id == 0 { return {} }
	img := rl.LoadImageFromTexture(s.texture)
	if img.data == nil { return {} }
	defer rl.UnloadImage(img)
	pixels := rl.LoadImageColors(img)
	defer rl.UnloadImageColors(pixels)
	for y in 0..<int(img.height) { for x in 0..<int(img.width) {
		color := pixels[y*int(img.width)+x]
		rl.ImageDrawPixel(&img, i32(x), i32(y), {255, 255, 255, color.a})
	} }
	out := s
	out.texture = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(out.texture, .POINT)
	return out
}

// A bounded set of batched quads, with no per-frame texture or allocation.
// thickness is in destination pixels; the actor remains the same visual size.
draw_sprite_cutout_rect :: proc(s, silhouette: Sprite, frame: int, dest: rl.Rectangle,
	origin: Vec2 = {}, flip_x := false, tint := rl.WHITE, thickness: f32 = 2,
	rotation: f32 = 0) {
	if s.texture.id == 0 { return }
	if silhouette.texture.id != 0 && tint.a > 0 {
		// Dark keyline separates the warm paper from bright ice or magic.
		for offset in ([4]Vec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
			r := dest
			r.x += offset.x * (thickness+1)
			r.y += offset.y * (thickness+1)
			rl.DrawTexturePro(silhouette.texture, sprite_source(silhouette, frame, flip_x),
				r, origin, rotation, {8, 12, 20, tint.a})
		}
		for offset in ([8]Vec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-0.7, -0.7}, {0.7, -0.7}, {-0.7, 0.7}, {0.7, 0.7}}) {
			r := dest
			r.x += offset.x * thickness
			r.y += offset.y * thickness
			rl.DrawTexturePro(silhouette.texture, sprite_source(silhouette, frame, flip_x),
				r, origin, rotation, {219, 212, 195, tint.a})
		}
	}
	rl.DrawTexturePro(s.texture, sprite_source(s, frame, flip_x), dest, origin, rotation, tint)
}

draw_sprite_cutout_feet :: proc(s, silhouette: Sprite, frame: int, feet: Vec2,
	scale: f32 = 1, flip_x := false, tint := rl.WHITE, squash: Vec2 = {1, 1}) {
	w, h := f32(s.width)*scale*squash.x, f32(s.height)*scale*squash.y
	draw_sprite_cutout_rect(s, silhouette, frame, {feet.x, feet.y, w, h}, {w*0.5, h},
		flip_x, tint, max(scale*1.1, 1.4))
}

draw_sprite_cutout :: proc(s, silhouette: Sprite, frame: int, center: Vec2,
	scale: f32 = 1, flip_x := false, tint := rl.WHITE, rotation: f32 = 0) {
	w, h := f32(s.width)*scale, f32(s.height)*scale
	draw_sprite_cutout_rect(s, silhouette, frame, {center.x, center.y, w, h}, {w*0.5, h*0.5},
		flip_x, tint, max(scale*1.1, 1.4), rotation)
}
