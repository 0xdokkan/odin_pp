package mapeditor

import "core:fmt"
import "core:strings"
import world "../expedition"
import grid "../engine/grid"
import level "../level"

// THE CHECKS BEFORE A SAVE: what a map needs to be played. Every map: its columns keep the rule of the layers
// (level.check_layers) and it has its start. A biome's map, besides: the start's square is level, every site is level
// in its bounds (a cave's mouth aside), and from the start a walker gets to every site, every cave's inside and the
// exit (level.layer_reach). Each error has its cell, which the editor shows in red; a map with errors is not saved.

Check_Error :: struct {
	cell: grid.Position,
	text: string,
}

Check_Report :: struct {
	errors: [dynamic]Check_Error,
}

check_report_clear :: proc(report: ^Check_Report) {
	for e in report.errors { delete(e.text) }
	clear(&report.errors)
}

check_report_destroy :: proc(report: ^Check_Report) {
	check_report_clear(report)
	delete(report.errors)
}

@(private = "file")
check_add :: proc(report: ^Check_Report, cell: grid.Position, text: string) {
	append(&report.errors, Check_Error{cell = cell, text = strings.clone(text)})
}

// Checks `data` (with `w`, its world, for a biome's map; nil for an arena) into `report`.
check_map :: proc(data: ^level.Level, w: ^world.World, report: ^Check_Report) {
	check_report_clear(report)
	if error, bad := level.check_layers(data); error != .None {
		text := "Due pavimenti della colonna distano meno di 12 gradini" if error == .Column_Too_Close else "Una scala non unisce due pavimenti vicini"
		check_add(report, bad, text)
	}
	if !data.has_player_spawn {
		check_add(report, {}, "La mappa non ha la partenza")
		return
	}
	if spawn, _ := level.tile_at(data, data.player_spawn); !level.is_walkable(spawn.kind) {
		check_add(report, data.player_spawn, "La partenza non è calpestabile")
	}
	if w == nil { return }
	// The start's square, and every site in its bounds, level.
	level_square :: proc(data: ^level.Level, low, high, at: grid.Position) -> (cell: grid.Position, uneven: bool) {
		base := level.height_at(data, at)
		for y in low.y..=high.y {
			for x in low.x..=high.x {
				cell = {x = x, y = y}
				if tile, ok := level.tile_at(data, cell); ok && tile.kind != .Void && level.height_at(data, cell) != base { return cell, true }
			}
		}
		return
	}
	if cell, uneven := level_square(data, grid.offset(data.player_spawn, -8, -8), grid.offset(data.player_spawn, 8, 8), data.player_spawn); uneven {
		check_add(report, cell, "La partenza non è in piano")
	}
	for &site in w.sites[:w.site_count] {
		if site.kind == .Cave { continue }
		low, high := world.site_bounds(&site)
		if cell, uneven := level_square(data, low, high, site.position); uneven {
			check_add(report, cell, fmt.tprintf("%s: il luogo non è in piano", world.site_name(site.kind)))
		}
	}
	// Where a walker gets from the start.
	seen := level.layer_reach(data, data.player_spawn, context.temp_allocator)
	reached :: proc(data: ^level.Level, seen: []bool, p: grid.Position) -> bool {
		return level.layer_contains(data, p) && seen[level.layer_reach_index(data, p)]
	}
	for &site in w.sites[:w.site_count] {
		near := false
		for dy in -3..=3 { for dx in -3..=3 { near = near || reached(data, seen, grid.offset(site.position, dx, dy)) } }
		if !near { check_add(report, site.position, fmt.tprintf("%s: non si raggiunge dalla partenza", world.site_name(site.kind))) }
	}
	for cave, i in w.caves[:w.cave_count] {
		if !reached(data, seen, cave.place.arrival) { check_add(report, cave.place.arrival, fmt.tprintf("Grotta %d: l'interno non si raggiunge", i+1)) }
	}
	for tile, i in data.tiles.cells {
		cell := grid.Position{x = i%data.tiles.width, y = i/data.tiles.width}
		if tile.kind == .Exit && !reached(data, seen, cell) { check_add(report, cell, "L'uscita non si raggiunge dalla partenza") }
	}
}
