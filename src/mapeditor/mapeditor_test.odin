package mapeditor

import "core:fmt"
import "core:os"
import "core:slice"
import "core:testing"
import world "../expedition"
import grid "../engine/grid"
import game "../game"
import level "../level"
import run "../run"

// A folder of its own in the system's temp directory, emptied.
@(private = "file")
test_root :: proc(name: string) -> string {
	dir, dir_error := os.temp_directory(context.temp_allocator)
	if dir_error != nil { dir = "build" }
	path, path_error := os.join_path({dir, "odin_pp_mapeditor", name}, context.temp_allocator)
	if path_error != nil { path = name }
	_ = os.remove_all(path)
	return path
}

// The retouches written as images and read back are the same, layer by layer; a layer without retouches has no image,
// one whose retouches are gone loses it, and an image of another size is left out.
@(test)
test_retouch_files_go_and_come_back :: proc(t: ^testing.T) {
	folder := test_root("andata")
	edits := level.Map_Edits{width = 20, height = 14}
	defer level.map_edits_destroy(&edits)
	ground := level.map_edit_layer(&edits, grid.GROUND_LAYER)
	// A height of 0 is a retouch too: only a transparent pixel is none.
	ground.heights[3*20+5] = 0
	ground.heights[7*20+11], ground.kinds[7*20+11] = 37, u8(level.Tile_Kind.Wall)
	ground.kinds[2*20+2] = u8(level.Tile_Kind.Fence)
	under := level.map_edit_layer(&edits, -1)
	under.heights[9*20+4], under.kinds[9*20+4] = 3, u8(level.Tile_Kind.Floor)
	testing.expect(t, save_edits(folder, &edits))
	read := load_edits(folder, 20, 14)
	defer level.map_edits_destroy(&read)
	for slot in 0..<level.LAYER_COUNT {
		testing.expect(t, slice.equal(read.layers[slot].kinds, edits.layers[slot].kinds))
		testing.expect(t, slice.equal(read.layers[slot].heights, edits.layers[slot].heights))
	}
	names := LAYER_FILE_NAMES
	file :: proc(folder, layer, what: string) -> string { return fmt.tprintf("%s/%s_%s.png", folder, layer, what) }
	testing.expect(t, !os.exists(file(folder, names[level.layer_slot(1)], "altezze")), "no image for a layer without retouches")
	// The ground's kinds taken back: their image goes, the heights' stays.
	for &kind in ground.kinds { kind = level.MAP_EDIT_NO_KIND }
	testing.expect(t, save_edits(folder, &edits))
	testing.expect(t, !os.exists(file(folder, names[level.layer_slot(0)], "tipi")))
	testing.expect(t, os.exists(file(folder, names[level.layer_slot(0)], "altezze")))
	// For a map of another size the images are left out.
	other := load_edits(folder, 21, 14)
	defer level.map_edits_destroy(&other)
	testing.expect(t, !level.map_edits_any(&other))
}

// The retouches under a root reach the game: an arena of the lab and a biome's map are made with them, the biome's the
// same at every seed; with `retouched` false, or once forgotten, as the code makes them.
@(test)
test_retouches_reach_the_lab_and_the_biomes :: proc(t: ^testing.T) {
	root := test_root("gioco")
	defer unload_all()
	// The flat arena: a cell raised, one walled.
	width, height := run.mechanics_lab_size(.Flat)
	lab := level.Map_Edits{width = width, height = height}
	defer level.map_edits_destroy(&lab)
	tables := level.map_edit_layer(&lab, grid.GROUND_LAYER)
	tables.heights[5*width+5], tables.kinds[5*width+6] = 7, u8(level.Tile_Kind.Wall)
	testing.expect(t, save_edits(target_folder(root, {arena = .Flat}), &lab))
	// The Egypt: a free cell of its ground raised and fenced.
	w := new(world.World)
	defer free(w)
	base: level.Level
	testing.expect(t, world.generate(w, &base, .Egypt, 1, retouched = false))
	defer level.destroy(&base)
	side := world.map_size(.Egypt)
	cell, found := grid.Position{}, false
	for x in 10..<side-10 {
		p := grid.Position{x = x, y = 5}
		tile, _ := level.tile_at(&base, p)
		if _, owned := level.structure_index_at(&base, p); tile.kind == .Floor && !owned { cell, found = p, true; break }
	}
	testing.expect(t, found)
	ground := level.height_at(&base, cell)
	biome := level.Map_Edits{width = side, height = side}
	defer level.map_edits_destroy(&biome)
	retouch := level.map_edit_layer(&biome, grid.GROUND_LAYER)
	retouch.heights[cell.y*side+cell.x], retouch.kinds[cell.y*side+cell.x] = i16(ground+5), u8(level.Tile_Kind.Fence)
	testing.expect(t, save_edits(target_folder(root, {biome = .Egypt, is_biome = true}), &biome))
	load_all(root)
	arena, made := run.mechanics_lab_level(.Flat)
	testing.expect(t, made)
	defer level.destroy(&arena)
	testing.expect_value(t, level.height_at(&arena, {x = 5, y = 5}), 7)
	wall, _ := level.tile_at(&arena, {x = 6, y = 5})
	testing.expect_value(t, wall.kind, level.Tile_Kind.Wall)
	plain_arena, _ := run.mechanics_lab_level(.Flat, retouched = false)
	defer level.destroy(&plain_arena)
	testing.expect_value(t, level.height_at(&plain_arena, {x = 5, y = 5}), 0)
	first, second, plain: level.Level
	testing.expect(t, world.generate(w, &first, .Egypt, 1))
	defer level.destroy(&first)
	testing.expect(t, world.generate(w, &second, .Egypt, 99))
	defer level.destroy(&second)
	testing.expect(t, world.generate(w, &plain, .Egypt, 1, retouched = false))
	defer level.destroy(&plain)
	testing.expect_value(t, level.height_at(&first, cell), ground+5)
	fence, _ := level.tile_at(&first, cell)
	testing.expect_value(t, fence.kind, level.Tile_Kind.Fence)
	testing.expect(t, slice.equal(first.heights[:], second.heights[:]), "the same map at every seed")
	testing.expect_value(t, level.height_at(&plain, cell), ground)
	// A floor under the raised cell, too close to it: the retouches break the layers' rule and are left out whole.
	cellar := level.map_edit_layer(&lab, -1)
	cellar.heights[5*width+5], cellar.kinds[5*width+5] = 0, u8(level.Tile_Kind.Floor)
	testing.expect(t, save_edits(target_folder(root, {arena = .Flat}), &lab))
	load_all(root)
	broken, _ := run.mechanics_lab_level(.Flat)
	defer level.destroy(&broken)
	testing.expect_value(t, level.height_at(&broken, {x = 5, y = 5}), 0)
	under, _ := level.tile_at(&broken, {x = 5, y = 5, layer = -1})
	testing.expect(t, under.kind != .Floor)
	// Forgotten, the arena is as the code makes it again.
	unload_all()
	again, _ := run.mechanics_lab_level(.Flat)
	defer level.destroy(&again)
	testing.expect_value(t, level.height_at(&again, {x = 5, y = 5}), 0)
}

// The checks: a biome's map as the code makes it has no error; a start walled in reaches no site, and the errors go
// with the wall undone; a floor under the ground at the ground's own height breaks the column's rule.
@(test)
test_the_checks_find_what_breaks_a_map :: proc(t: ^testing.T) {
	w := new(world.World)
	defer free(w)
	data: level.Level
	testing.expect(t, world.generate(w, &data, .Egypt, 1, retouched = false))
	defer level.destroy(&data)
	report: Check_Report
	defer check_report_destroy(&report)
	check_map(&data, w, &report)
	testing.expect_value(t, len(report.errors), 0)
	history: level.Sculpt_History
	defer level.sculpt_history_destroy(&history)
	stroke := level.sculpt_begin(&history)
	spawn := data.player_spawn
	for dy in -2..=2 { for dx in -2..=2 { if max(abs(dx), abs(dy)) == 2 { level.sculpt_paint(&data, stroke, grid.offset(spawn, dx, dy), 0, .Wall) } } }
	level.sculpt_end(&history)
	check_map(&data, w, &report)
	testing.expect(t, len(report.errors) >= w.site_count, "every site out of reach")
	testing.expect(t, level.sculpt_undo(&data, &history))
	check_map(&data, w, &report)
	testing.expect_value(t, len(report.errors), 0)
	arena, made := run.mechanics_lab_level(.Flat, retouched = false)
	testing.expect(t, made)
	defer level.destroy(&arena)
	cellar: level.Sculpt_History
	defer level.sculpt_history_destroy(&cellar)
	stroke = level.sculpt_begin(&cellar)
	level.sculpt_paint(&arena, stroke, {x = 5, y = 5, layer = -1}, 0, .Floor)
	level.sculpt_end(&cellar)
	check_map(&arena, nil, &report)
	testing.expect_value(t, len(report.errors), 1)
	if len(report.errors) == 1 { testing.expect(t, report.errors[0].cell.x == 5 && report.errors[0].cell.y == 5) }
}

// The maps the editor opens, in their order and with their folders.
@(test)
test_the_editor_opens_every_arena_and_biome :: proc(t: ^testing.T) {
	testing.expect_value(t, target_at(0), Target{arena = .Flat})
	last := target_at(-1)
	testing.expect(t, last.is_biome && int(last.biome) == target_count()-len(run.Mechanics_Lab_Arena)-1)
	testing.expect_value(t, target_folder("radice", {biome = .Egypt, is_biome = true}), "radice/biomi/egypt")
	testing.expect_value(t, target_folder("radice", {arena = .Layers}), "radice/laboratorio/piani")
	for i in 0..<target_count() {
		width, height := target_size(target_at(i))
		testing.expect(t, width > 0 && height > 0)
	}
}

// The cell under the mouse: at the middle of the screen, the one the camera looks at, on flat ground and on a hill's
// top; on a layer with no floor yet, the one at its plane's height.
@(test)
test_the_mouse_picks_the_cell_the_camera_looks_at :: proc(t: ^testing.T) {
	data, made := run.mechanics_lab_level(.Flat, retouched = false)
	testing.expect(t, made)
	defer level.destroy(&data)
	e: Editor
	e.yaw, e.pitch, e.distance = 0.6, 0.9, 20
	center := grid.Position{x = 6, y = 5}
	e.focus = {f32(center.x)+.5, cell_top(&data, center), f32(center.y)+.5}
	middle := [2]f32{480, 270}
	cell, ok := view_pick(&data, grid.GROUND_LAYER, editor_camera(&e), middle, 960, 540)
	testing.expect(t, ok && cell == center)
	history: level.Sculpt_History
	defer level.sculpt_history_destroy(&history)
	stroke := level.sculpt_begin(&history)
	for _ in 0..<8 { level.sculpt_raise(&data, stroke, center, 2, 1) }
	level.sculpt_end(&history)
	e.focus.y = cell_top(&data, center)
	cell, ok = view_pick(&data, grid.GROUND_LAYER, editor_camera(&e), middle, 960, 540)
	testing.expect(t, ok && cell == center)
	e.focus.y = f32(level.LAYER_SPACING)*game.HEIGHT_STEP_DRAWN
	cell, ok = view_pick(&data, 1, editor_camera(&e), middle, 960, 540)
	testing.expect(t, ok && cell == grid.Position{x = center.x, y = center.y, layer = 1})
}

// Every map the editor opens passes the checks as the code makes it: the checks find only what a hand changed.
@(test)
test_every_map_the_code_makes_passes_the_checks :: proc(t: ^testing.T) {
	w := new(world.World)
	defer free(w)
	report: Check_Report
	defer check_report_destroy(&report)
	for i in 0..<target_count() {
		target := target_at(i)
		data, made := target_base(target, w)
		testing.expectf(t, made, "%s does not open", target_title(target))
		if !made { continue }
		check_map(&data, w if target.is_biome else nil, &report)
		for err in report.errors { testing.expectf(t, false, "%s: %s at %v", target_title(target), err.text, err.cell) }
		level.destroy(&data)
	}
}
