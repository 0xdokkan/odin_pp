package render

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

// Original 1x1 GIF fixture: transparent first frame, opaque white second.
SPRITE_TEST_GIF :: [?]u8{
	'G','I','F','8','9','a', 1,0,1,0, 0x80,0,0, 0,0,0, 255,255,255,
	0x21,0xf9,4,1,10,0,0,0, 0x2c,0,0,0,0,1,0,1,0,0, 2,2,0x44,1,0,
	0x21,0xf9,4,1,10,0,0,0, 0x2c,0,0,0,0,1,0,1,0,0, 2,2,0x4c,1,0,0x3b,
}

@(test)
test_sprite_png_and_gif_metadata_reject_truncation_and_oversized_decodes :: proc(t: ^testing.T) {
	fixture := SPRITE_TEST_GIF
	metadata, valid := sprite_image_metadata(fixture[:])
	testing.expect(t, valid && metadata.is_gif)
	testing.expect_value(t, metadata.frames, 2)
	for length in 0..<len(SPRITE_TEST_GIF) {
		_, truncated_valid := sprite_image_metadata(fixture[:length])
		testing.expect(t, !truncated_valid)
	}
	oversized := SPRITE_TEST_GIF
	oversized[6], oversized[7] = 0xff, 0x7f
	_, valid = sprite_image_metadata(oversized[:])
	testing.expect(t, !valid)
	testing.expect(t, !sprite_dimensions_valid(1024, 1024, 128))
	testing.expect(t, !sprite_dimensions_valid(1, 1, MAX_SPRITE_FRAMES+1))
	outside := SPRITE_TEST_GIF
	outside[28] = 2 // first image extends beyond logical canvas
	_, valid = sprite_image_metadata(outside[:])
	testing.expect(t, !valid)

	png := [?]u8{137,80,78,71,13,10,26,10, 0,0,0,13, 'I','H','D','R', 0,0,0,32, 0,0,0,48, 8,6,0,0,0, 0,0,0,0}
	metadata, valid = sprite_image_metadata(png[:])
	testing.expect(t, valid && !metadata.is_gif)
	testing.expect_value(t, metadata.width, 32)
	testing.expect_value(t, metadata.height, 48)
	png[16] = 127
	_, valid = sprite_image_metadata(png[:])
	testing.expect(t, !valid)
}

@(test)
test_sprite_manifest_sheet_and_gif_configuration_enforce_frame_boundaries :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	manifest: Sprite_Manifest
	err := json.unmarshal_string(`{"version":1,"sprites":[{"key":"player","file":"hero.png","columns":4,"rows":2,"frames":7,"width":32,"height":48,"fps":12,"anchor":[0.5,0.9]}]}`, &manifest, allocator = mem.dynamic_arena_allocator(&arena))
	testing.expect(t, err == nil)
	texture := Sprite_Texture{texture = {width = 128, height = 96}}
	entry := manifest.sprites[0]
	asset, valid := sprite_entry_config(entry, &texture)
	testing.expect(t, valid)
	testing.expect_value(t, asset.frame_width, 32)
	testing.expect_value(t, asset.frame_height, 48)
	testing.expect_value(t, asset.frames, 7)
	testing.expect_value(t, asset.anchor.y, f32(0.9))
	entry.frames = 9
	_, valid = sprite_entry_config(entry, &texture)
	testing.expect(t, !valid)
	entry.frames, entry.columns = 6, 3
	_, valid = sprite_entry_config(entry, &texture)
	testing.expect(t, !valid)
	entry.columns, entry.frames, entry.width = 4, 7, -1
	_, valid = sprite_entry_config(entry, &texture)
	testing.expect(t, !valid)
	texture.is_gif = true
	texture.columns, texture.frames, texture.frame_width, texture.frame_height = 2, 3, 16, 24
	_, valid = sprite_entry_config(manifest.sprites[0], &texture)
	testing.expect(t, !valid, "GIF frames must come from its decoded image, not sheet settings")
	asset, valid = sprite_entry_config({key = "player", file = "hero.gif"}, &texture)
	testing.expect(t, valid)
	testing.expect_value(t, asset.frames, 3)
	testing.expect_value(t, asset.anchor, view.Vec2{0.5, 1})
	testing.expect_value(t, asset.fps, f64(8))
}

@(test)
test_sprite_sheet_clock_and_alpha_picking_follow_the_visible_frame :: proc(t: ^testing.T) {
	alpha := [?]u8{0,255,255,0, 0,255,255,0}
	assets := Sprite_Assets{texture_count = 1}
	assets.textures[0] = {texture = {width = 4, height = 2}, alpha = alpha[:]}
	asset := &assets.sprites[int(Sprite_Key.Barrel)]
	asset^ = {configured = true, columns = 2, frames = 2, frame_width = 2, frame_height = 2, width = 20, height = 20, anchor = {0.5, 1}, fps = 2}
	center := view.Vec2{100, 100}
	source, destination := sprite_asset_rectangles(asset, 0, center, 2)
	testing.expect_value(t, destination, rl.Rectangle{80, 60, 40, 40})
	testing.expect_value(t, source, rl.Rectangle{0, 0, 2, 2})
	hit, configured := sprite_asset_contains_point(&assets, .Barrel, center, {85, 70}, 2)
	testing.expect(t, configured && !hit, "transparent sprite pixels must not steal clicks")
	hit, _ = sprite_asset_contains_point(&assets, .Barrel, center, {105, 70}, 2)
	testing.expect(t, hit)
	advance_sprite_assets(&assets, 0.5)
	hit, _ = sprite_asset_contains_point(&assets, .Barrel, center, {85, 70}, 2)
	testing.expect(t, hit, "the second frame swaps the opaque column")
	hit, _ = sprite_asset_contains_point(&assets, .Barrel, center, {105, 70}, 2)
	testing.expect(t, !hit)
	advance_sprite_assets(&assets, 0.5)
	testing.expect_value(t, sprite_frame_index(asset, assets.elapsed), 0)
	testing.expect_value(t, sprite_frame_index(asset, 1000000.5), 1)
	hit, configured = sprite_asset_contains_point(&assets, .Player, center, center, 1)
	testing.expect(t, !hit && !configured, "missing assets preserve procedural fallback")
	hit, configured = sprite_asset_contains_point(&assets, .Barrel, center, {120, 100}, 2)
	testing.expect(t, !hit && configured, "right and bottom sprite bounds are exclusive")
}

@(test)
test_sprite_gif_decode_packs_real_frames_and_preserves_transparency_without_a_window :: proc(t: ^testing.T) {
	fixture := SPRITE_TEST_GIF
	metadata, valid := sprite_image_metadata(fixture[:])
	testing.expect(t, valid)
	atlas, columns, decoded := sprite_decode_atlas(fixture[:], metadata)
	testing.expect(t, decoded)
	if !decoded {return}
	defer rl.UnloadImage(atlas)
	testing.expect_value(t, columns, 2)
	testing.expect_value(t, atlas.width, c.int(2))
	testing.expect_value(t, atlas.height, c.int(1))
	pixels := ([^]u8)(atlas.data)
	testing.expect_value(t, pixels[3], u8(0))
	testing.expect_value(t, pixels[7], u8(255))
}

@(test)
test_sprite_actor_picking_uses_image_alpha_instead_of_the_previous_circle :: proc(t: ^testing.T) {
	alpha := [?]u8{0,255,0,255}
	renderer := Renderer{camera = view.make_camera(), projection = {tile_width = 64, tile_height = 32}}
	renderer.camera.zoom = 1
	renderer.sprite_assets.texture_count = 1
	renderer.sprite_assets.textures[0] = {texture = {width = 2, height = 2}, alpha = alpha[:]}
	renderer.sprite_assets.sprites[int(Sprite_Key.Chaser)] = {
		configured = true, columns = 1, frames = 1, frame_width = 2, frame_height = 2,
		width = 32, height = 48, anchor = {0.5, 1}, fps = 8,
	}
	enemy := game.Enemy{archetype = .Chaser}
	center := view.Vec2{100, 100}
	testing.expect(t, enemy_body_contains_point(&renderer, enemy, center, {108, 56}), "raised sprite head remains clickable")
	testing.expect(t, !enemy_body_contains_point(&renderer, enemy, center, {95, 95}), "transparent pixels inside the former circle pass through")
}

@(test)
test_sprite_manifest_failure_and_file_limits_leave_a_usable_fallback :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odin_pp_sprite_validation.*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {return}
	defer delete(directory)
	defer os.remove(directory)
	filename := fmt.aprintf("%s/sprites.json", directory)
	defer delete(filename)
	defer os.remove(filename)
	assets: Sprite_Assets
	defer unload_sprite_assets(&assets)
	report := load_sprite_assets(&assets, filename)
	testing.expect(t, !report.manifest_found)
	testing.expect_value(t, assets.texture_count, 0)
	testing.expect(t, os.write_entire_file(filename, `{"version":2,"sprites":[]}`) == nil)
	report = load_sprite_assets(&assets, filename)
	testing.expect(t, report.manifest_found && len(report.message) > 0)
	testing.expect_value(t, report.loaded, 0)
	testing.expect_value(t, assets.texture_count, 0)
	data, valid := sprite_read_file(filename, 4, context.allocator)
	testing.expect(t, !valid && len(data) == 0, "oversized compressed input is rejected before allocating its contents")
	testing.expect(t, os.write_entire_file(filename, `{"version":1,"sprites":`) == nil)
	report = load_sprite_assets(&assets, filename)
	testing.expect(t, report.manifest_found && len(report.message) > 0)
	testing.expect_value(t, assets.texture_count, 0)
}
