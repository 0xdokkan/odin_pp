package main

import "core:c"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import render "render"
import view "view"

// Original diagnostic shapes, created only by --smoke-sprites. They are not
// game artwork and all temporary files are removed after the textures load.
prepare_sprite_smoke :: proc(renderer: ^render.Renderer) -> bool {
	if renderer == nil || !rl.IsWindowReady() {return false}
	directory, directory_error := os.make_directory_temp("", "odin_pp_sprites.*", context.allocator)
	if directory_error != nil {return false}
	defer delete(directory)
	defer os.remove(directory)
	sheet_path := fmt.aprintf("%s/shared.png", directory)
	static_path := fmt.aprintf("%s/ice.png", directory)
	gif_path := fmt.aprintf("%s/barrel.gif", directory)
	manifest_path := fmt.aprintf("%s/sprites.json", directory)
	defer delete(sheet_path)
	defer delete(static_path)
	defer delete(gif_path)
	defer delete(manifest_path)
	defer os.remove(sheet_path)
	defer os.remove(static_path)
	defer os.remove(gif_path)
	defer os.remove(manifest_path)

	sheet := rl.GenImageColor(64, 48, rl.BLANK)
	if !rl.IsImageValid(sheet) {return false}
	defer rl.UnloadImage(sheet)
	for frame in 0..<2 {
		x := c.int(frame*32)
		color := rl.Color{63, 218, 197, 255} if frame == 0 else rl.Color{255, 197, 72, 255}
		rl.ImageDrawCircle(&sheet, x+16, 10, 7, color)
		rl.ImageDrawRectangle(&sheet, x+8, 16, 16, 24, color)
		rl.ImageDrawRectangle(&sheet, x+8, 39, 6, 9, color)
		rl.ImageDrawRectangle(&sheet, x+18, 39, 6, 9, color)
		rl.ImageDrawRectangle(&sheet, x+12, 8, 8, 3, rl.Color{20, 29, 39, 255})
	}
	if !rl.ExportImage(sheet, fmt.ctprintf("%s", sheet_path)) {return false}
	ice := rl.GenImageColor(32, 32, rl.BLANK)
	if !rl.IsImageValid(ice) {return false}
	defer rl.UnloadImage(ice)
	rl.ImageDrawRectangle(&ice, 4, 4, 24, 28, rl.Color{70, 160, 220, 230})
	rl.ImageDrawRectangle(&ice, 6, 6, 8, 22, rl.Color{169, 237, 248, 255})
	if !rl.ExportImage(ice, fmt.ctprintf("%s", static_path)) {return false}
	// Two white/transparent diagnostic frames with no external fixture files.
	gif := [?]u8{
		'G','I','F','8','9','a', 1,0,1,0, 0x80,0,0, 0,0,0, 255,255,255,
		0x21,0xf9,4,1,10,0,0,0, 0x2c,0,0,0,0,1,0,1,0,0, 2,2,0x44,1,0,
		0x21,0xf9,4,1,10,0,0,0, 0x2c,0,0,0,0,1,0,1,0,0, 2,2,0x4c,1,0,0x3b,
	}
	if os.write_entire_file(gif_path, gif[:]) != nil {return false}
	manifest :: `{"version":1,"sprites":[
		{"key":"player","file":"shared.png","columns":2,"frames":2,"width":32,"height":48,"fps":2},
		{"key":"chaser","file":"shared.png","columns":2,"frames":2,"width":28,"height":42,"fps":2},
		{"key":"player_cast","file":"shared.png","columns":2,"frames":2,"width":32,"height":48},
		{"key":"ice_block","file":"ice.png","width":32,"height":32},
		{"key":"barrel","file":"barrel.gif","width":20,"height":28,"fps":2},
		{"key":"bomber","file":"missing.png"}
	]}`
	if os.write_entire_file(manifest_path, manifest) != nil {return false}
	assets := &renderer.sprite_assets
	report := render.load_sprite_assets(assets, manifest_path)
	if !report.manifest_found || report.loaded != 5 || report.rejected != 1 || assets.texture_count != 3 {return false}
	if assets.sprites[int(render.Sprite_Key.Player)].texture_index != assets.sprites[int(render.Sprite_Key.Chaser)].texture_index {return false}
	if assets.sprites[int(render.Sprite_Key.Player)].texture_index != assets.sprites[int(render.Sprite_Key.Player_Cast)].texture_index {return false}
	if assets.sprites[int(render.Sprite_Key.Bomber)].configured {return false}
	center := view.Vec2{100, 100}
	hit, configured := render.sprite_asset_contains_point(assets, .Player, center, {100, 70}, 1)
	if !hit || !configured {return false}
	hit, configured = render.sprite_asset_contains_point(assets, .Player, center, {85, 70}, 1)
	if hit || !configured {return false}
	hit, configured = render.sprite_asset_contains_point(assets, .Barrel, center, {100, 80}, 1)
	if hit || !configured {return false}
	render.advance_sprite_assets(assets, 0.5)
	hit, configured = render.sprite_asset_contains_point(assets, .Barrel, center, {100, 80}, 1)
	if !hit || !configured {return false}
	source, _ := render.sprite_asset_rectangles(&assets.sprites[int(render.Sprite_Key.Player)], assets.elapsed, center, 1)
	if source.x != 32 || source.y != 0 || source.width != 32 || source.height != 48 {return false}
	if !verify_sprite_clip_smoke(assets) {return false}
	// Exercise GPU ownership and reload; the final load stays alive for capture.
	render.unload_sprite_assets(assets)
	if assets.texture_count != 0 || assets.total_pixels != 0 || assets.sprites[int(render.Sprite_Key.Player)].configured {return false}
	report = render.load_sprite_assets(assets, manifest_path)
	if report.loaded != 5 || report.rejected != 1 || assets.texture_count != 3 {return false}
	render.advance_sprite_assets(assets, 0.5)
	fmt.println("Sprite smoke passed: PNG sheet, static PNG, animated GIF, shared idle/clip texture, clip endpoints, alpha picking, fallback, unload/reload.")
	return true
}

verify_sprite_clip_smoke :: proc(assets: ^render.Sprite_Assets) -> bool {
	// Render both endpoints to a small private target and read their actual GPU
	// pixels. The idle clock is deliberately on the other frame at the start.
	target := rl.LoadRenderTexture(80, 80)
	if !rl.IsRenderTextureValid(target) {return false}
	defer rl.UnloadRenderTexture(target)
	clock_before := assets.elapsed
	for endpoint in 0..<2 {
		rl.BeginTextureMode(target)
		rl.ClearBackground(rl.BLANK)
		drawn := render.draw_sprite_clip(assets, .Player_Cast, {40, 68}, 1, f32(endpoint))
		rl.EndTextureMode()
		if !drawn {return false}
		pixels := rl.LoadImageFromTexture(target.texture)
		if !rl.IsImageValid(pixels) {return false}
		colors := rl.LoadImageColors(pixels)
		if colors == nil {rl.UnloadImage(pixels); return false}
		actual := colors[40*80+40]
		expected := rl.Color{63, 218, 197, 255} if endpoint == 0 else rl.Color{255, 197, 72, 255}
		rl.UnloadImageColors(colors)
		rl.UnloadImage(pixels)
		if actual != expected {return false}
	}
	return assets.elapsed == clock_before && assets.texture_count == 3
}
