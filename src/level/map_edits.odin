package level

import grid "../engine/grid"

// THE RETOUCHES OF A MAP (Fase 6 of docs/piano-profondita.md): what the map editor (src/mapeditor) changed in a map
// the code makes, a lab's arena or a biome's map, cell by cell and layer by layer: a cell's kind, its height, or both.
// Put over the map the code makes, they are part of it, as fixed as the rest of its geography; a cell they do not touch
// stays as the code makes it. As for the brushes (sculpt.odin), a building's cells stay the building's, and the start,
// the exit and the doors the code's: a retouch never changes, takes away or makes one, even if the code moved them.

// No retouch of a cell's kind, or of its height.
MAP_EDIT_NO_KIND :: u8(255)
MAP_EDIT_NO_HEIGHT :: i16(-1)

// The retouches of one layer: every cell's kind and height, or none (both empty: no retouch on the layer).
Map_Edit_Layer :: struct {
	kinds:   []u8,
	heights: []i16,
}

Map_Edits :: struct {
	width, height: int,
	layers:        [LAYER_COUNT]Map_Edit_Layer,
}

map_edits_destroy :: proc(edits: ^Map_Edits) {
	if edits == nil { return }
	for &layer in edits.layers {
		delete(layer.kinds)
		delete(layer.heights)
	}
	edits^ = {}
}

// Whether there is any retouch at all.
map_edits_any :: proc(edits: ^Map_Edits) -> bool {
	if edits == nil { return false }
	for layer in edits.layers { if len(layer.kinds) > 0 { return true } }
	return false
}

// The tables of `layer`, made on their first use with every cell untouched.
map_edit_layer :: proc(edits: ^Map_Edits, layer: i8) -> ^Map_Edit_Layer {
	tables := &edits.layers[layer_slot(layer)]
	if len(tables.kinds) == 0 {
		count := edits.width*edits.height
		tables.kinds = make([]u8, count)
		tables.heights = make([]i16, count)
		for i in 0..<count { tables.kinds[i], tables.heights[i] = MAP_EDIT_NO_KIND, MAP_EDIT_NO_HEIGHT }
	}
	return tables
}

// What `edited` changed of `base` (the two of one size): every cell of every layer whose kind or height differs.
map_edits_diff :: proc(base, edited: ^Level) -> (edits: Map_Edits, ok: bool) {
	if base == nil || edited == nil || base.tiles.width != edited.tiles.width || base.tiles.height != edited.tiles.height { return }
	edits.width, edits.height = base.tiles.width, base.tiles.height
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		for y in 0..<edits.height {
			for x in 0..<edits.width {
				p := grid.Position{x = x, y = y, layer = i8(layer)}
				before, _ := tile_at(base, p)
				after, _ := tile_at(edited, p)
				before_height, after_height := height_at(base, p), height_at(edited, p)
				if before.kind == after.kind && before_height == after_height { continue }
				tables := map_edit_layer(&edits, i8(layer))
				index := y*edits.width+x
				if before.kind != after.kind { tables.kinds[index] = u8(after.kind) }
				if before_height != after_height { tables.heights[index] = i16(after_height) }
			}
		}
	}
	return edits, true
}

// Puts `edits` on `data` as the game does: false when they do not go on it (map_edits_apply), or when the map they make
// breaks the layers' rule (check_layers: a file painted by hand skips the editor's checks). Then `data` is to be made
// again without them. The editor opens such a file anyway, with the map_edits_apply below, to show its errors.
map_edits_apply_checked :: proc(data: ^Level, edits: ^Map_Edits) -> bool {
	if !map_edits_apply(data, edits) { return false }
	error, _ := check_layers(data)
	return error == .None
}

// Puts `edits` on `data`: false, with nothing changed, when they are not of its size or hold a kind that is none.
map_edits_apply :: proc(data: ^Level, edits: ^Map_Edits) -> bool {
	if data == nil || edits == nil || edits.width != data.tiles.width || edits.height != data.tiles.height { return false }
	for tables in edits.layers {
		for kind in tables.kinds { if kind != MAP_EDIT_NO_KIND && kind > u8(max(Tile_Kind)) { return false } }
		for height in tables.heights { if height != MAP_EDIT_NO_HEIGHT && (height < 0 || height > MAX_CELL_HEIGHT) { return false } }
	}
	for tables, slot in edits.layers {
		if len(tables.kinds) == 0 { continue }
		layer := i8(slot+grid.LOWEST_LAYER)
		for i in 0..<len(tables.kinds) {
			p := grid.Position{x = i%edits.width, y = i/edits.width, layer = layer}
			if layer == grid.GROUND_LAYER {
				if _, owned := structure_index_at(data, p); owned { continue }
			}
			if kind := tables.kinds[i]; kind != MAP_EDIT_NO_KIND {
				tile, _ := tile_at(data, p)
				if !sculpt_marker(tile.kind) && !sculpt_marker(Tile_Kind(kind)) { _ = set_tile(data, p, {kind = Tile_Kind(kind)}) }
			}
			if tables.heights[i] != MAP_EDIT_NO_HEIGHT { _ = set_height(data, p, i32(tables.heights[i])) }
		}
	}
	return true
}
