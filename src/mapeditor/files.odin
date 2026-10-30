package mapeditor

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import grid "../engine/grid"
import level "../level"
import run "../run"

// THE RETOUCHES' FILES: under the root (MAPS_ROOT in the game), a folder for each map (target_folder) with two PNG for
// each layer retouched: `<layer>_altezze.png`, the heights in grey (a level a step), and `<layer>_tipi.png`, the kinds
// in colour (KIND_COLORS). A transparent pixel is a cell left as the code makes it: the files can be painted with any
// program, and the editor reads them back (F5).

MAPS_ROOT :: "assets/mappe"

LAYER_FILE_NAMES :: [level.LAYER_COUNT]string{"sotto_profondo", "sotto", "terra", "sopra"}

// The colour of each kind; a pixel of a file is read as the kind of the nearest colour.
KIND_COLORS :: [level.Tile_Kind]rl.Color{
	.Void = {0, 0, 0, 255}, .Floor = {200, 200, 200, 255}, .Wall = {120, 72, 40, 255}, .Door = {80, 150, 220, 255},
	.Player_Spawn = {60, 110, 255, 255}, .Exit = {200, 60, 220, 255}, .Fence = {230, 190, 40, 255},
}

@(private = "file")
layer_paths :: proc(folder: string, slot: int) -> (heights, kinds: cstring) {
	names := LAYER_FILE_NAMES
	return fmt.ctprintf("%s/%s_altezze.png", folder, names[slot]), fmt.ctprintf("%s/%s_tipi.png", folder, names[slot])
}

@(private = "file")
remove_if_there :: proc(path: cstring) {
	if os.exists(string(path)) { _ = os.remove(string(path)) }
}

// Writes `edits` into `folder` (made if missing): the images of every layer with a retouch, and no image left of what
// has none now. False if a file could not be written.
save_edits :: proc(folder: string, edits: ^level.Map_Edits) -> bool {
	if err := os.make_directory_all(folder); err != nil && !(err == .Exist && os.is_directory(folder)) { return false }
	ok := true
	count := edits.width*edits.height
	for tables, slot in edits.layers {
		heights_path, kinds_path := layer_paths(folder, slot)
		touched_heights, touched_kinds := false, false
		for h in tables.heights { if h != level.MAP_EDIT_NO_HEIGHT { touched_heights = true; break } }
		for k in tables.kinds { if k != level.MAP_EDIT_NO_KIND { touched_kinds = true; break } }
		if touched_heights {
			pixels := make([]u8, count*2, context.temp_allocator)
			for h, i in tables.heights {
				if h == level.MAP_EDIT_NO_HEIGHT { continue }
				pixels[i*2], pixels[i*2+1] = u8(h), 255
			}
			image := rl.Image{data = raw_data(pixels), width = i32(edits.width), height = i32(edits.height), mipmaps = 1, format = .UNCOMPRESSED_GRAY_ALPHA}
			ok = rl.ExportImage(image, heights_path) && ok
		} else { remove_if_there(heights_path) }
		if touched_kinds {
			colors := KIND_COLORS
			pixels := make([]rl.Color, count, context.temp_allocator)
			for k, i in tables.kinds {
				if k == level.MAP_EDIT_NO_KIND || k > u8(max(level.Tile_Kind)) { continue }
				pixels[i] = colors[level.Tile_Kind(k)]
			}
			image := rl.Image{data = raw_data(pixels), width = i32(edits.width), height = i32(edits.height), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
			ok = rl.ExportImage(image, kinds_path) && ok
		} else { remove_if_there(kinds_path) }
	}
	return ok
}

// The kind whose colour is nearest to `color`.
@(private = "file")
nearest_kind :: proc(color: rl.Color) -> level.Tile_Kind {
	colors := KIND_COLORS
	best, best_distance := level.Tile_Kind.Floor, max(int)
	for kind in level.Tile_Kind {
		c := colors[kind]
		dr, dg, db := int(c.r)-int(color.r), int(c.g)-int(color.g), int(c.b)-int(color.b)
		if distance := dr*dr+dg*dg+db*db; distance < best_distance { best, best_distance = kind, distance }
	}
	return best
}

// Reads an image of `width` by `height` as colours (nil: no file, or not of that size).
@(private = "file")
load_colors :: proc(path: cstring, width, height: int) -> (pixels: []rl.Color, image: rl.Image, ok: bool) {
	if !os.exists(string(path)) { return }
	image = rl.LoadImage(path)
	if !rl.IsImageValid(image) { return }
	if int(image.width) != width || int(image.height) != height {
		fmt.eprintfln("mappe: %s is %dx%d, not %dx%d: left out", path, image.width, image.height, width, height)
		rl.UnloadImage(image)
		return nil, {}, false
	}
	rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8A8)
	return ([^]rl.Color)(image.data)[:width*height], image, true
}

// Reads the retouches of a map of `width` by `height` from `folder` (none if it has no image).
load_edits :: proc(folder: string, width, height: int) -> (edits: level.Map_Edits) {
	edits.width, edits.height = width, height
	for slot in 0..<level.LAYER_COUNT {
		heights_path, kinds_path := layer_paths(folder, slot)
		layer := i8(slot+grid.LOWEST_LAYER)
		if pixels, image, ok := load_colors(heights_path, width, height); ok {
			tables := level.map_edit_layer(&edits, layer)
			for p, i in pixels { if p.a >= 128 { tables.heights[i] = i16(p.r) } }
			rl.UnloadImage(image)
		}
		if pixels, image, ok := load_colors(kinds_path, width, height); ok {
			tables := level.map_edit_layer(&edits, layer)
			for p, i in pixels { if p.a >= 128 { tables.kinds[i] = u8(nearest_kind(p)) } }
			rl.UnloadImage(image)
		}
	}
	return
}

// Loads the retouches of every map from `root`, for the game to put over its maps: the arenas' and the biomes'. A
// map with no folder keeps none.
load_all :: proc(root: string = MAPS_ROOT) {
	unload_all()
	for arena in run.Mechanics_Lab_Arena {
		width, height := run.mechanics_lab_size(arena)
		edits := load_edits(target_folder(root, {arena = arena}), width, height)
		if level.map_edits_any(&edits) { run.mechanics_lab_edits[arena] = edits } else { level.map_edits_destroy(&edits) }
	}
	for biome in campaign.Biome {
		if biome == .Count { continue }
		side := world.map_size(biome)
		edits := load_edits(target_folder(root, {biome = biome, is_biome = true}), side, side)
		if level.map_edits_any(&edits) { world.biome_map_edits[biome] = edits } else { level.map_edits_destroy(&edits) }
	}
}

// Forgets every retouch loaded: the maps as the code makes them.
unload_all :: proc() {
	for &edits in run.mechanics_lab_edits { level.map_edits_destroy(&edits) }
	for &edits in world.biome_map_edits { level.map_edits_destroy(&edits) }
}
