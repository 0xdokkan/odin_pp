package mapeditor

import "core:fmt"
import "core:slice"
import artifacts "../devtools/artifacts"
import campaign "../campaign"
import grid "../engine/grid"
import host "../engine/host"
import level "../level"
import run "../run"

// THE EDITOR'S SMOKE (`--smoke-editor-mappe`): the editor driven step by step, a capture at each one
// (odin_pp_editor_*.png). The flat arena: a hill raised, smoothed, saved and opened again, the same; the brushes the
// user added (a ramp, the noise, a piece copied and pasted, a painted wall); a biome's caves on their layer; a start
// walled in, its errors in red and the save refused, the camera on the first error (G), then undone. It writes only
// under EDITOR_SMOKE_ROOT, which git leaves out, never in assets/mappe.

EDITOR_SMOKE_ROOT :: "build/editor_smoke/mappe"
EDITOR_SMOKE_NAMES :: [?]cstring{
	"odin_pp_editor_arena.png", "odin_pp_editor_collina.png", "odin_pp_editor_levigata.png", "odin_pp_editor_riaperta.png",
	"odin_pp_editor_pennelli.png", "odin_pp_editor_grotte.png", "odin_pp_editor_errori.png", "odin_pp_editor_errore.png",
}
// Frames a step shows before its capture.
EDITOR_SMOKE_FRAMES :: 20

Editor_Smoke :: struct {
	step, frames: int,
	ready:        bool,
}

@(private = "file")
smoke_check :: proc(ok: bool, what: string) {
	if !ok { fmt.eprintln("editor smoke:", what); panic("editor smoke failed") }
}

@(private = "file")
smoke_stroke :: proc(e: ^Editor, brush: level.Sculpt_Brush, radius: int, cells: []grid.Position) {
	e.brush, e.radius = brush, radius
	editor_begin(e, cells[0])
	for cell in cells { editor_apply(e, cell) }
	editor_end(e)
}

// The step's work: the map, the brushes and the camera before its capture.
@(private = "file")
smoke_step :: proc(e: ^Editor, step: int) {
	center := grid.Position{x = 11, y = 8}
	switch step {
	case 0:
		// A clean start: none of the last run's files.
		for i in 0..<target_count() {
			width, height := target_size(target_at(i))
			empty := level.Map_Edits{width = width, height = height}
			_ = save_edits(target_folder(e.root, target_at(i)), &empty)
		}
		smoke_check(editor_open(e, 0), "the flat arena does not open")
		e.focus, e.yaw, e.pitch, e.distance = {11.5, 0, 8.5}, 0.6, 0.85, 26
	case 1:
		smoke_stroke(e, .Raise, 3, []grid.Position{center, center, center, center, center})
		smoke_stroke(e, .Raise, 1, []grid.Position{center, center, center, center})
		smoke_check(level.height_at(&e.data, center) == 9, "the hill is not 9 steps tall")
	case 2:
		smoke_stroke(e, .Smooth, 4, []grid.Position{center, center, center})
		smoke_check(len(e.report.errors) == 0, "the smoothed hill has errors")
		smoke_check(editor_unsaved(e), "nothing to save")
	case 3:
		smoke_check(editor_save(e), "the arena is not saved")
		before := slice.clone(e.data.heights[:], context.temp_allocator)
		smoke_check(editor_open(e, 0), "the arena does not open again")
		smoke_check(slice.equal(before, e.data.heights[:]), "the arena opened again is not the one saved")
		smoke_check(!editor_unsaved(e), "the arena opened again has changes")
	case 4:
		smoke_stroke(e, .Raise, 0, []grid.Position{{x = 19, y = 14}, {x = 19, y = 14}, {x = 19, y = 14}, {x = 19, y = 14}, {x = 19, y = 14}, {x = 19, y = 14}})
		e.brush, e.radius = .Ramp, 0
		editor_ramp(e, {x = 3, y = 14})
		editor_ramp(e, {x = 19, y = 14})
		smoke_check(level.height_at(&e.data, {x = 11, y = 14}) == 3, "the ramp does not climb")
		smoke_stroke(e, .Noise, 2, []grid.Position{{x = 4, y = 4}})
		e.brush = .Copy
		level.sculpt_copy(&e.data, {x = 8, y = 5}, {x = 14, y = 11}, &e.clip)
		e.brush = .Paste
		editor_paste(e, {x = 15, y = 2})
		e.paint = 1
		smoke_stroke(e, .Paint, 0, []grid.Position{{x = 3, y = 9}, {x = 4, y = 9}, {x = 5, y = 9}})
		smoke_check(level.height_at(&e.data, {x = 18, y = 5}) == level.height_at(&e.data, {x = 11, y = 8}), "the pasted hill is not the hill")
		// The start pasted with the hill is a floor there: one start only.
		pasted, _ := level.tile_at(&e.data, {x = 18, y = 5})
		smoke_check(pasted.kind == .Floor, "the start pasted is a second start")
	case 5:
		smoke_check(editor_open(e, len(run.Mechanics_Lab_Arena)+int(campaign.Biome.Egypt)), "the Egypt does not open")
		smoke_check(len(e.report.errors) == 0, "the Egypt as the code makes it has errors")
		e.layer = -1
		arrival := e.world.caves[0].place.arrival
		e.focus, e.yaw, e.pitch, e.distance = {f32(arrival.x)+14, 0, f32(arrival.y)+6}, 0.5, 0.95, 46
	case 6:
		e.layer = grid.GROUND_LAYER
		spawn := e.data.player_spawn
		ring := make([dynamic]grid.Position, context.temp_allocator)
		for dy in -2..=2 { for dx in -2..=2 { if max(abs(dx), abs(dy)) == 2 { append(&ring, grid.offset(spawn, dx, dy)) } } }
		e.paint = 1
		smoke_stroke(e, .Paint, 0, ring[:])
		smoke_check(len(e.report.errors) > 0, "a walled start has no errors")
		smoke_check(!editor_save(e), "a map with errors is saved")
		e.focus, e.yaw, e.pitch, e.distance = {f32(spawn.x)+.5, 0, f32(spawn.y)+.5}, 0.6, 0.9, 30
	case 7:
		editor_next_error(e)
		first := e.report.errors[0].cell
		smoke_check(e.layer == first.layer && int(e.focus.x) == first.x && int(e.focus.z) == first.y, "G does not show the first error")
	}
}

@(private)
editor_smoke_update :: proc(e: ^Editor, frame: ^host.Frame) {
	s := e.smoke
	names := EDITOR_SMOKE_NAMES
	if s.step >= len(names) {
		// The last step undone: the walled start's errors go.
		editor_undo(e)
		smoke_check(len(e.report.errors) == 0, "the undone wall leaves errors")
		host.quit(frame)
		return
	}
	if !s.ready {
		smoke_step(e, s.step)
		s.ready, s.frames = true, 0
	}
}

@(private)
editor_smoke_present :: proc(data: rawptr, frame: ^host.Frame) {
	e := cast(^Editor)data
	s := e.smoke
	if s == nil || !s.ready { return }
	s.frames += 1
	if s.frames < EDITOR_SMOKE_FRAMES { return }
	names := EDITOR_SMOKE_NAMES
	artifacts.screenshot(names[s.step])
	s.step += 1
	s.ready = false
}
