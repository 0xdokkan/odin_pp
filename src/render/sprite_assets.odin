package render

import "core:c"
import "core:encoding/json"
import "core:math"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import game "../game"
import view "../view"

Sprite_Key :: enum {
	Player, Chaser, Archer, Brute, Bomber, Custodian, Demolitionist, Ice_Block, Fire, Barrel, Bomb,
	Player_Cast, Player_Hit, Firebomb_Cast, Firebomb_Projectile, Firebomb_Impact, Chain_Bolt, Fate_Cast, Fate_Impact,
	Count,
}
MAX_SPRITE_TEXTURES :: int(Sprite_Key.Count)
MAX_SPRITE_FILE_BYTES :: 16*1024*1024
MAX_SPRITE_PIXELS :: 8*1024*1024
MAX_SPRITE_TOTAL_PIXELS :: 32*1024*1024
MAX_SPRITE_FRAMES :: 128
MAX_SPRITE_TEXTURE_EDGE :: 4096

Sprite_Asset :: struct {
	configured: bool,
	texture_index, columns, frames: int,
	frame_width, frame_height: int,
	width, height: f32,
	anchor: view.Vec2,
	fps: f64,
}

Sprite_Texture :: struct {
	texture: rl.Texture2D,
	alpha: []u8,
	filename: string,
	is_gif: bool,
	columns, frames, frame_width, frame_height: int,
}

Sprite_Assets :: struct {
	sprites: [MAX_SPRITE_TEXTURES]Sprite_Asset,
	textures: [MAX_SPRITE_TEXTURES]Sprite_Texture,
	texture_count, total_pixels: int,
	elapsed: f64,
	allocator: mem.Allocator,
}

Sprite_Load_Report :: struct {
	manifest_found: bool,
	loaded, rejected: int,
	message: string,
}

Sprite_Manifest_Entry :: struct {
	key, file: string,
	width, height: f32,
	anchor: []f32,
	columns, rows, frames: int,
	fps: f64,
}

Sprite_Manifest :: struct {version: int, sprites: []Sprite_Manifest_Entry}
Sprite_Image_Metadata :: struct {width, height, frames: int, is_gif: bool}

sprite_key_from_name :: proc(name: string) -> (key: Sprite_Key, valid: bool) {
	switch name {
	case "player": return .Player, true
	case "chaser": return .Chaser, true
	case "archer": return .Archer, true
	case "brute": return .Brute, true
	case "bomber": return .Bomber, true
	case "custodian": return .Custodian, true
	case "demolitionist": return .Demolitionist, true
	case "ice_block": return .Ice_Block, true
	case "fire": return .Fire, true
	case "barrel": return .Barrel, true
	case "bomb": return .Bomb, true
	case "player_cast": return .Player_Cast, true
	case "player_hit": return .Player_Hit, true
	case "firebomb_cast": return .Firebomb_Cast, true
	case "firebomb_projectile": return .Firebomb_Projectile, true
	case "firebomb_impact": return .Firebomb_Impact, true
	case "chain_bolt": return .Chain_Bolt, true
	case "fate_cast": return .Fate_Cast, true
	case "fate_impact": return .Fate_Impact, true
	}
	return .Count, false
}

sprite_key_is_clip :: proc(key: Sprite_Key) -> bool {
	return key >= .Player_Cast && key < .Count
}

sprite_key_for_enemy :: proc(kind: game.Enemy_Archetype) -> Sprite_Key {
	switch kind {
	case .Chaser: return .Chaser
	case .Archer: return .Archer
	case .Brute: return .Brute
	case .Bomber: return .Bomber
	case .Custodian: return .Custodian
	case .Demolitionist: return .Demolitionist
	case .Count: return .Count
	}
	return .Count
}

sprite_key_for_object :: proc(kind: game.Grid_Object_Kind) -> Sprite_Key {
	switch kind {
	case .Ice_Block: return .Ice_Block
	case .Fire: return .Fire
	case .Barrel: return .Barrel
	case .Bomb: return .Bomb
	case .Shock_Floor, .Tesla_Coil: return .Count
	case .Count: return .Count
	}
	return .Count
}

sprite_read_u16 :: proc(data: []u8, offset: int) -> int {
	return int(data[offset]) | int(data[offset+1])<<8
}

sprite_read_be32 :: proc(data: []u8, offset: int) -> u32 {
	return u32(data[offset])<<24 | u32(data[offset+1])<<16 | u32(data[offset+2])<<8 | u32(data[offset+3])
}

sprite_dimensions_valid :: proc(width, height, frames: int) -> bool {
	return width > 0 && width <= MAX_SPRITE_TEXTURE_EDGE && height > 0 &&
	       height <= MAX_SPRITE_TEXTURE_EDGE && frames > 0 && frames <= MAX_SPRITE_FRAMES &&
	       i64(width)*i64(height)*i64(frames) <= MAX_SPRITE_PIXELS
}

sprite_skip_gif_blocks :: proc(data: []u8, cursor: ^int) -> bool {
	for cursor^ < len(data) {
		length := int(data[cursor^])
		cursor^ += 1
		if length == 0 {return true}
		if length > len(data)-cursor^ {return false}
		cursor^ += length
	}
	return false
}

// Inspect dimensions and every GIF frame before handing compressed bytes to
// Raylib. Limits therefore apply before a decoder can allocate frame buffers.
sprite_image_metadata :: proc(data: []u8) -> (metadata: Sprite_Image_Metadata, valid: bool) {
	if len(data) >= 33 && string(data[:8]) == "\x89PNG\r\n\x1a\n" &&
	   string(data[12:16]) == "IHDR" && sprite_read_be32(data, 8) == 13 {
		metadata = {width = int(sprite_read_be32(data, 16)), height = int(sprite_read_be32(data, 20)), frames = 1}
		return metadata, sprite_dimensions_valid(metadata.width, metadata.height, 1)
	}
	if len(data) < 14 || (string(data[:6]) != "GIF87a" && string(data[:6]) != "GIF89a") {return}
	metadata = {width = sprite_read_u16(data, 6), height = sprite_read_u16(data, 8), is_gif = true}
	if !sprite_dimensions_valid(metadata.width, metadata.height, 1) {return metadata, false}
	cursor := 13
	if data[10]&0x80 != 0 {cursor += 3*(1<<uint((data[10]&7)+1))}
	for cursor < len(data) {
		label := data[cursor]
		cursor += 1
		switch label {
		case 0x3b:
			return metadata, sprite_dimensions_valid(metadata.width, metadata.height, metadata.frames)
		case 0x21:
			if cursor >= len(data) {return metadata, false}
			cursor += 1 // extension type, followed by size-prefixed sub-blocks
			if !sprite_skip_gif_blocks(data, &cursor) {return metadata, false}
		case 0x2c:
			if len(data)-cursor < 9 {return metadata, false}
			x, y := sprite_read_u16(data, cursor), sprite_read_u16(data, cursor+2)
			w, h := sprite_read_u16(data, cursor+4), sprite_read_u16(data, cursor+6)
			if w <= 0 || h <= 0 || x+w > metadata.width || y+h > metadata.height {return metadata, false}
			packed := data[cursor+8]
			cursor += 9
			if packed&0x80 != 0 {cursor += 3*(1<<uint((packed&7)+1))}
			if cursor >= len(data) || data[cursor] < 2 || data[cursor] > 8 {return metadata, false}
			cursor += 1 // LZW minimum code size
			if !sprite_skip_gif_blocks(data, &cursor) {return metadata, false}
			metadata.frames += 1
			if !sprite_dimensions_valid(metadata.width, metadata.height, metadata.frames) {return metadata, false}
		case: return metadata, false
		}
	}
	return metadata, false
}

sprite_entry_config :: proc(entry: Sprite_Manifest_Entry, texture: ^Sprite_Texture) -> (asset: Sprite_Asset, valid: bool) {
	if texture == nil || entry.width < 0 || entry.height < 0 || entry.width > 256 || entry.height > 256 ||
	   math.is_nan(entry.width) || math.is_nan(entry.height) || math.is_nan(entry.fps) ||
	   entry.fps < 0 || entry.fps > 60 || entry.columns < 0 || entry.rows < 0 || entry.frames < 0 {return}
	asset.anchor = {0.5, 1}
	if len(entry.anchor) != 0 {
		if len(entry.anchor) != 2 {return asset, false}
		for value in entry.anchor {
			if math.is_nan(value) || value < 0 || value > 1 {return asset, false}
		}
		asset.anchor = {entry.anchor[0], entry.anchor[1]}
	}
	if texture.is_gif {
		if entry.columns != 0 || entry.rows != 0 || entry.frames != 0 {return asset, false}
		asset.columns, asset.frames = texture.columns, texture.frames
		asset.frame_width, asset.frame_height = texture.frame_width, texture.frame_height
	} else {
		columns, rows := max(1, entry.columns), max(1, entry.rows)
		if columns > MAX_SPRITE_FRAMES || rows > MAX_SPRITE_FRAMES || columns*rows > MAX_SPRITE_FRAMES ||
		   int(texture.texture.width)%columns != 0 || int(texture.texture.height)%rows != 0 {return asset, false}
		asset.columns = columns
		asset.frames = entry.frames if entry.frames != 0 else columns*rows
		if asset.frames > columns*rows {return asset, false}
		asset.frame_width, asset.frame_height = int(texture.texture.width)/columns, int(texture.texture.height)/rows
	}
	if asset.frame_width <= 0 || asset.frame_height <= 0 || asset.frames <= 0 {return asset, false}
	asset.width = entry.width if entry.width > 0 else f32(asset.frame_width)
	asset.height = entry.height if entry.height > 0 else f32(asset.frame_height)
	if asset.width > 256 || asset.height > 256 {return asset, false}
	asset.fps = entry.fps if entry.fps > 0 else 8
	asset.configured = true
	return asset, true
}

sprite_read_file :: proc(filename: string, limit: int, allocator: mem.Allocator) -> (data: []u8, valid: bool) {
	file, open_error := os.open(filename)
	if open_error != nil {return}
	defer os.close(file)
	size, size_error := os.file_size(file)
	if size_error != nil || size <= 0 || size > i64(limit) {return}
	data = make([]u8, int(size), allocator)
	total := 0
	for total < len(data) {
		n, read_error := os.read(file, data[total:])
		total += n
		if read_error != nil || n == 0 {
			delete(data, allocator)
			return nil, false
		}
	}
	return data, true
}

// One RGBA atlas is uploaded per unique file. GIFs need no texture uploads
// during gameplay, and only a compact alpha mask remains in CPU memory.
sprite_decode_atlas :: proc(data: []u8, metadata: Sprite_Image_Metadata) -> (atlas: rl.Image, columns: int, valid: bool) {
	if !sprite_dimensions_valid(metadata.width, metadata.height, metadata.frames) || len(data) == 0 {return}
	if !metadata.is_gif {
		atlas = rl.LoadImageFromMemory(".png", raw_data(data), c.int(len(data)))
		if !rl.IsImageValid(atlas) {return atlas, 0, false}
		if int(atlas.width) != metadata.width || int(atlas.height) != metadata.height {
			rl.UnloadImage(atlas)
			return {}, 0, false
		}
		rl.ImageFormat(&atlas, .UNCOMPRESSED_R8G8B8A8)
		return atlas, 1, rl.IsImageValid(atlas)
	}
	frames: c.int
	decoded := rl.LoadImageAnimFromMemory(".gif", raw_data(data), c.int(len(data)), &frames)
	if !rl.IsImageValid(decoded) {return}
	defer rl.UnloadImage(decoded)
	if int(frames) != metadata.frames || int(decoded.width) != metadata.width ||
	   int(decoded.height) != metadata.height || decoded.format != .UNCOMPRESSED_R8G8B8A8 {return}
	columns = 1
	for columns*columns < metadata.frames {columns += 1}
	max_rows := MAX_SPRITE_TEXTURE_EDGE/metadata.height
	columns = max(columns, (metadata.frames+max_rows-1)/max_rows)
	columns = min(columns, MAX_SPRITE_TEXTURE_EDGE/metadata.width)
	rows := (metadata.frames+columns-1)/columns
	width, height := columns*metadata.width, rows*metadata.height
	if height > MAX_SPRITE_TEXTURE_EDGE || width*height > MAX_SPRITE_PIXELS {return {}, 0, false}
	atlas = rl.GenImageColor(c.int(width), c.int(height), rl.BLANK)
	if !rl.IsImageValid(atlas) {return atlas, 0, false}
	input := ([^]u8)(decoded.data)
	output := ([^]u8)(atlas.data)
	for frame in 0..<metadata.frames {
		for row in 0..<metadata.height {
			from := (frame*metadata.height+row)*metadata.width*4
			to := ((frame/columns*metadata.height+row)*width+frame%columns*metadata.width)*4
			copy(output[to:to+metadata.width*4], input[from:from+metadata.width*4])
		}
	}
	return atlas, columns, true
}

unload_sprite_assets :: proc(assets: ^Sprite_Assets) {
	if assets == nil {return}
	for index in 0..<assets.texture_count {
		texture := &assets.textures[index]
		if texture.texture.id != 0 {rl.UnloadTexture(texture.texture)}
		delete(texture.alpha, assets.allocator)
		delete(texture.filename, assets.allocator)
	}
	assets^ = {}
}

load_sprite_assets :: proc(assets: ^Sprite_Assets, manifest_path: string) -> (report: Sprite_Load_Report) {
	if assets == nil || len(manifest_path) == 0 {return}
	unload_sprite_assets(assets)
	assets.allocator = context.allocator
	file, open_error := os.open(manifest_path)
	if open_error != nil {report.message = "Sprite manifest could not be opened."; return}
	os.close(file)
	report.manifest_found = true
	data, readable := sprite_read_file(manifest_path, 64*1024, context.allocator)
	if !readable {report.message = "Sprite manifest is empty, unreadable, or exceeds 64 KiB."; return}
	defer delete(data)
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	manifest: Sprite_Manifest
	if json.unmarshal(data, &manifest, allocator = allocator) != nil || manifest.version != 1 ||
	   len(manifest.sprites) > MAX_SPRITE_TEXTURES {
		report.message = "Invalid sprite manifest: require version 1 and at most 19 sprites."
		return
	}
	if !rl.IsWindowReady() {report.message = "Sprite textures require an initialized graphics window."; return}
	directory := filepath.dir(manifest_path)
	seen: [MAX_SPRITE_TEXTURES]bool
	for entry in manifest.sprites {
		key, key_valid := sprite_key_from_name(entry.key)
		if !key_valid || seen[int(key)] || len(entry.file) == 0 || strings.contains(entry.file, "\x00") {
			report.rejected += 1
			continue
		}
		seen[int(key)] = true
		filename := entry.file
		if !filepath.is_abs(filename) {
			filename, _ = filepath.join({directory, filename}, allocator)
		}
		texture_index := -1
		for index in 0..<assets.texture_count {
			if assets.textures[index].filename == filename {texture_index = index; break}
		}
		if texture_index < 0 {
			bytes, file_valid := sprite_read_file(filename, MAX_SPRITE_FILE_BYTES, assets.allocator)
			metadata, metadata_valid := sprite_image_metadata(bytes)
			if !file_valid || !metadata_valid || assets.total_pixels+metadata.width*metadata.height*metadata.frames > MAX_SPRITE_TOTAL_PIXELS {
				delete(bytes, assets.allocator)
				report.rejected += 1
				continue
			}
			atlas, columns, decoded := sprite_decode_atlas(bytes, metadata)
			delete(bytes, assets.allocator)
			if !decoded {report.rejected += 1; continue}
			pixel_count := int(atlas.width)*int(atlas.height)
			if assets.total_pixels+pixel_count > MAX_SPRITE_TOTAL_PIXELS {
				rl.UnloadImage(atlas)
				report.rejected += 1
				continue
			}
			texture := rl.LoadTextureFromImage(atlas)
			if !rl.IsTextureValid(texture) {
				rl.UnloadImage(atlas)
				report.rejected += 1
				continue
			}
			rl.SetTextureFilter(texture, .POINT)
			alpha := make([]u8, pixel_count, assets.allocator)
			pixels := ([^]u8)(atlas.data)
			for index in 0..<pixel_count {alpha[index] = pixels[index*4+3]}
			rl.UnloadImage(atlas)
			texture_index = assets.texture_count
			assets.textures[texture_index] = {
				texture = texture, alpha = alpha, filename = strings.clone(filename, assets.allocator),
				is_gif = metadata.is_gif, columns = columns, frames = metadata.frames,
				frame_width = metadata.width, frame_height = metadata.height,
			}
			assets.texture_count += 1
			assets.total_pixels += pixel_count
		}
		asset, config_valid := sprite_entry_config(entry, &assets.textures[texture_index])
		if !config_valid {report.rejected += 1; continue}
		asset.texture_index = texture_index
		assets.sprites[int(key)] = asset
		report.loaded += 1
	}
	if report.rejected > 0 {report.message = "Some sprites were rejected; their procedural graphics remain active."}
	return
}

advance_sprite_assets :: proc(assets: ^Sprite_Assets, dt: f32) {
	if assets != nil && dt > 0 && !math.is_nan(dt) && !math.is_inf(dt) {
		assets.elapsed += f64(dt)
	}
}

sprite_frame_index :: proc(asset: ^Sprite_Asset, elapsed: f64) -> int {
	if asset == nil || asset.frames <= 1 || asset.fps <= 0 || math.is_nan(asset.fps) || math.is_inf(asset.fps) ||
	   elapsed <= 0 || math.is_nan(elapsed) || math.is_inf(elapsed) {return 0}
	period := f64(asset.frames)/asset.fps
	return min(asset.frames-1, int(math.floor(math.mod(elapsed, period)*asset.fps)))
}

sprite_asset_rectangles :: proc(asset: ^Sprite_Asset, elapsed: f64, center: view.Vec2, zoom: f32) -> (source, destination: rl.Rectangle) {
	return sprite_frame_rectangles(asset, sprite_frame_index(asset, elapsed), center, zoom)
}

sprite_frame_rectangles :: proc(asset: ^Sprite_Asset, requested_frame: int, center: view.Vec2, zoom: f32) -> (source, destination: rl.Rectangle) {
	if asset == nil || !asset.configured || asset.columns <= 0 || asset.frames <= 0 ||
	   zoom <= 0 || math.is_nan(zoom) || math.is_inf(zoom) {return}
	frame := clamp(requested_frame, 0, asset.frames-1)
	source = {f32(frame%asset.columns*asset.frame_width), f32(frame/asset.columns*asset.frame_height), f32(asset.frame_width), f32(asset.frame_height)}
	destination = {center.x-asset.width*zoom*asset.anchor.x, center.y-asset.height*zoom*asset.anchor.y, asset.width*zoom, asset.height*zoom}
	return
}

// A clip belongs to a presentation cue. Its caller supplies progress rather
// than mutating the shared asset: simultaneous effects can use distinct frames.
sprite_clip_frame_index :: proc(asset: ^Sprite_Asset, progress: f32) -> int {
	if asset == nil || asset.frames <= 1 || math.is_nan(progress) || progress <= 0 {return 0}
	if progress >= 1 {return asset.frames-1}
	return min(asset.frames-1, int(math.floor(progress*f32(asset.frames))))
}

sprite_clip_rectangles :: proc(asset: ^Sprite_Asset, progress: f32, center: view.Vec2, zoom: f32) -> (source, destination: rl.Rectangle) {
	return sprite_frame_rectangles(asset, sprite_clip_frame_index(asset, progress), center, zoom)
}

draw_sprite_asset :: proc(assets: ^Sprite_Assets, key: Sprite_Key, center: view.Vec2, zoom: f32, opacity: f32 = 1) -> bool {
	if assets == nil || int(key) < 0 || key >= .Count || sprite_key_is_clip(key) {return false}
	asset := &assets.sprites[int(key)]
	if !asset.configured || asset.texture_index < 0 || asset.texture_index >= assets.texture_count {return false}
	source, destination := sprite_asset_rectangles(asset, assets.elapsed, center, zoom)
	rl.DrawTexturePro(assets.textures[asset.texture_index].texture, source, destination, {}, 0, color_with_opacity(rl.WHITE, opacity))
	return true
}

draw_sprite_clip :: proc(assets: ^Sprite_Assets, key: Sprite_Key, center: view.Vec2, zoom: f32, progress: f32, opacity: f32 = 1) -> bool {
	if assets == nil || !sprite_key_is_clip(key) {return false}
	asset := &assets.sprites[int(key)]
	if !asset.configured || asset.texture_index < 0 || asset.texture_index >= assets.texture_count {return false}
	source, destination := sprite_clip_rectangles(asset, progress, center, zoom)
	if destination.width <= 0 || destination.height <= 0 {return false}
	rl.DrawTexturePro(assets.textures[asset.texture_index].texture, source, destination, {}, 0, color_with_opacity(rl.WHITE, opacity))
	return true
}

sprite_asset_contains_point :: proc(assets: ^Sprite_Assets, key: Sprite_Key, center, point: view.Vec2, zoom: f32) -> (hit, configured: bool) {
	if assets == nil || int(key) < 0 || key >= .Count || sprite_key_is_clip(key) {return}
	asset := &assets.sprites[int(key)]
	if !asset.configured || asset.texture_index < 0 || asset.texture_index >= assets.texture_count {return}
	configured = true
	source, destination := sprite_asset_rectangles(asset, assets.elapsed, center, zoom)
	if destination.width <= 0 || destination.height <= 0 || point.x < destination.x || point.y < destination.y ||
	   point.x >= destination.x+destination.width || point.y >= destination.y+destination.height {return}
	x := int(source.x+(point.x-destination.x)*source.width/destination.width)
	y := int(source.y+(point.y-destination.y)*source.height/destination.height)
	texture := &assets.textures[asset.texture_index]
	index := y*int(texture.texture.width)+x
	if index >= 0 && index < len(texture.alpha) {hit = texture.alpha[index] > 16}
	return
}
