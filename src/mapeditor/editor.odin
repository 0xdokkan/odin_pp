package mapeditor

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import world "../expedition"
import grid "../engine/grid"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"
import level "../level"

// THE EDITOR'S SCENE: the map open (Target), the brush, the camera and what is shown. The mouse sculpts with the left
// button and turns the camera with the right one; the keys are in EDITOR_HELP.

BRUSH_NAMES :: [level.Sculpt_Brush]string{
	.Raise = "Alza", .Lower = "Abbassa", .Smooth = "Leviga", .Flatten = "Appiattisci", .Paint = "Dipingi",
	.Ramp = "Rampa", .Copy = "Copia", .Paste = "Incolla", .Noise = "Rumore",
}
PAINT_KINDS :: [4]level.Tile_Kind{.Floor, .Wall, .Void, .Fence}
PAINT_NAMES :: [4]string{"pavimento", "roccia", "vuoto", "recinto"}
LAYER_NAMES :: [level.LAYER_COUNT]string{"sotto profondo", "sotto", "terra", "sopra"}
EDITOR_HELP :: [?]string{
	"1-9 pennello   T tipo   [ ] grandezza   PagSu PagGiu piano   G errore seguente",
	"Ctrl+Z annulla   Ctrl+Y ripeti   Ctrl+S salva   F5 ricarica i file",
	"Tasto destro o Q E ruota   rotella zoom   WASD sposta   Tab mappa   Esc esci",
}

// How often a brush held down acts again on the same cell, in seconds.
BRUSH_REPEAT :: f32(0.12)

Editor :: struct {
	// Where the retouches are read and written (MAPS_ROOT; the smoke's own folder).
	root:           string,
	target_index:   int,
	target:         Target,
	// The map as the code makes it, and the one sculpted; a biome's world (its sites and caves).
	base, data:     level.Level,
	world:          ^world.World,
	opened:         bool,
	history:        level.Sculpt_History,
	// The stroke of the brush held down (nil: none), and when and where it last acted.
	stroke:         ^level.Sculpt_Stroke,
	stroke_timer:   f32,
	last_cell:      grid.Position,
	layer:          i8,
	brush:          level.Sculpt_Brush,
	paint:          int,
	radius:         int,
	flatten_height: u8,
	ramp_from:      grid.Position,
	ramp_set:       bool,
	copy_from:      grid.Position,
	copying:        bool,
	clip:           level.Sculpt_Clip,
	noise_seed:     u32,
	// The camera: the point it looks at, its turn and tilt, its distance.
	focus:          rl.Vector3,
	yaw, pitch:     f32,
	distance:       f32,
	hovered:        grid.Position,
	has_hovered:    bool,
	view:           Editor_View,
	report:         Check_Report,
	// The error of the report G shows next.
	error_next:     int,
	// The map's geometry at the last save or opening: another one has changes not saved.
	saved_revision: u64,
	message:        string,
	message_timer:  f32,
	// A second press of Tab, F5 or Esc throws the changes away.
	discard_armed:  bool,
	smoke:          ^Editor_Smoke,
}

editor_message :: proc(e: ^Editor, text: string) {
	delete(e.message)
	e.message = strings.clone(text)
	e.message_timer = 6
}

editor_unsaved :: proc(e: ^Editor) -> bool {
	return e.opened && e.data.geometry_revision != e.saved_revision
}

@(private = "file")
editor_close_map :: proc(e: ^Editor) {
	if e.stroke != nil { level.sculpt_end(&e.history); e.stroke = nil }
	level.sculpt_history_destroy(&e.history)
	if e.opened {
		level.destroy(&e.base)
		level.destroy(&e.data)
	}
	view_release(&e.view)
	check_report_clear(&e.report)
	e.opened, e.ramp_set, e.copying = false, false, false
}

// Opens map `index` (target_at): as the code makes it, with the retouches the root has for it.
editor_open :: proc(e: ^Editor, index: int) -> bool {
	editor_close_map(e)
	e.target_index = index
	e.target = target_at(index)
	base, made := target_base(e.target, e.world)
	if !made { editor_message(e, "La mappa non si apre"); return false }
	scratch := new(world.World)
	defer free(scratch)
	data, copied := target_base(e.target, scratch)
	if !copied { level.destroy(&base); editor_message(e, "La mappa non si apre"); return false }
	e.base, e.data, e.opened = base, data, true
	width, height := target_size(e.target)
	edits := load_edits(target_folder(e.root, e.target), width, height)
	defer level.map_edits_destroy(&edits)
	if level.map_edits_any(&edits) && !level.map_edits_apply(&e.data, &edits) { editor_message(e, "I file dei ritocchi non vanno su questa mappa") }
	e.saved_revision = e.data.geometry_revision
	e.layer = grid.GROUND_LAYER
	view_open(&e.view, &e.data)
	editor_check(e)
	// The camera over the start, the whole map in view.
	center := e.data.player_spawn if e.data.has_player_spawn else grid.Position{x = width/2, y = height/2}
	e.focus = {f32(center.x)+.5, cell_top(&e.data, center), f32(center.y)+.5}
	e.yaw, e.pitch, e.distance = 0.6, 0.9, f32(max(width, height))*0.9
	if e.target.is_biome { e.distance = 60 }
	return true
}

// Checks the map (checks.odin) into the report.
editor_check :: proc(e: ^Editor) {
	check_map(&e.data, e.world if e.target.is_biome else nil, &e.report)
	e.error_next = 0
}

// The camera on the report's next error (G), one after the other, on the error's layer.
editor_next_error :: proc(e: ^Editor) {
	if len(e.report.errors) == 0 { editor_message(e, "Nessun errore"); return }
	i := e.error_next%len(e.report.errors)
	e.error_next = i+1
	err := e.report.errors[i]
	e.layer = err.cell.layer
	e.focus = {f32(err.cell.x)+.5, cell_top(&e.data, err.cell), f32(err.cell.y)+.5}
	e.distance = min(e.distance, 30)
	editor_message(e, fmt.tprintf("Errore %d di %d: %s", i+1, len(e.report.errors), err.text))
}

// Saves what changed, unless the checks find errors.
editor_save :: proc(e: ^Editor) -> bool {
	editor_check(e)
	if len(e.report.errors) > 0 {
		editor_message(e, fmt.tprintf("Non salvata: %d errori, in rosso", len(e.report.errors)))
		return false
	}
	edits, ok := level.map_edits_diff(&e.base, &e.data)
	defer level.map_edits_destroy(&edits)
	folder := target_folder(e.root, e.target)
	if !ok || !save_edits(folder, &edits) {
		editor_message(e, "Non salvata: i file non si scrivono")
		return false
	}
	e.saved_revision = e.data.geometry_revision
	editor_message(e, fmt.tprintf("Salvata in %s", folder))
	return true
}

editor_camera :: proc(e: ^Editor) -> rl.Camera3D {
	cp := math.cos(e.pitch)
	eye := e.focus+rl.Vector3{math.sin(e.yaw)*cp, math.sin(e.pitch), math.cos(e.yaw)*cp}*e.distance
	return {position = eye, target = e.focus, up = {0, 1, 0}, fovy = 45, projection = .PERSPECTIVE}
}

// The cells round `low`..`high` on the editor's layer are to be drawn again, and the map checked again.
@(private = "file")
editor_changed :: proc(e: ^Editor, layer: i8, low, high: grid.Position) {
	mark_dirty(&e.view, layer, low, high)
}

// The changes of a stroke undone or done again are to be drawn again.
@(private = "file")
editor_changed_stroke :: proc(e: ^Editor, stroke: ^level.Sculpt_Stroke) {
	for change in stroke.changes { mark_dirty(&e.view, change.cell.layer, change.cell, change.cell) }
	editor_check(e)
}

// The brush acts once on `cell` (inside a stroke).
editor_apply :: proc(e: ^Editor, cell: grid.Position) {
	if e.stroke == nil { return }
	r := e.radius
	kinds := PAINT_KINDS
	switch e.brush {
	case .Raise: level.sculpt_raise(&e.data, e.stroke, cell, r, 1)
	case .Lower: level.sculpt_raise(&e.data, e.stroke, cell, r, -1)
	case .Smooth: level.sculpt_smooth(&e.data, e.stroke, cell, r)
	case .Flatten: level.sculpt_flatten(&e.data, e.stroke, cell, r, e.flatten_height)
	case .Paint: level.sculpt_paint(&e.data, e.stroke, cell, r, kinds[e.paint])
	case .Noise:
		e.noise_seed += 1
		level.sculpt_noise(&e.data, e.stroke, cell, r, e.noise_seed)
	case .Ramp, .Copy, .Paste:
	}
	editor_changed(e, cell.layer, grid.offset(cell, -r, -r), grid.offset(cell, r, r))
}

// A stroke begins on `cell`.
editor_begin :: proc(e: ^Editor, cell: grid.Position) {
	e.discard_armed = false
	e.stroke = level.sculpt_begin(&e.history)
	e.flatten_height = u8(clamp(level.height_at(&e.data, cell), 0, level.MAX_CELL_HEIGHT))
	e.stroke_timer = 0
	e.last_cell = cell
}

// The stroke ends: kept if it changed something, and the map checked again.
editor_end :: proc(e: ^Editor) {
	if e.stroke == nil { return }
	level.sculpt_end(&e.history)
	e.stroke = nil
	editor_check(e)
}

// A ramp from the first end chosen to `cell`.
editor_ramp :: proc(e: ^Editor, cell: grid.Position) {
	if !e.ramp_set {
		e.ramp_from, e.ramp_set = cell, true
		editor_message(e, "Rampa: scegli l'altro capo")
		return
	}
	editor_begin(e, cell)
	level.sculpt_ramp(&e.data, e.stroke, e.ramp_from, cell, e.radius)
	low := grid.Position{x = min(e.ramp_from.x, cell.x)-e.radius, y = min(e.ramp_from.y, cell.y)-e.radius}
	high := grid.Position{x = max(e.ramp_from.x, cell.x)+e.radius, y = max(e.ramp_from.y, cell.y)+e.radius}
	editor_changed(e, cell.layer, low, high)
	editor_end(e)
	e.ramp_set = false
}

// Pastes what was copied with its north-west corner on `cell`.
editor_paste :: proc(e: ^Editor, cell: grid.Position) {
	if e.clip.width == 0 { editor_message(e, "Incolla: prima copia un pezzo"); return }
	editor_begin(e, cell)
	level.sculpt_paste(&e.data, e.stroke, &e.clip, cell)
	editor_changed(e, cell.layer, cell, grid.offset(cell, e.clip.width-1, e.clip.height-1))
	editor_end(e)
}

editor_undo :: proc(e: ^Editor) {
	if e.stroke != nil { return }
	if !level.sculpt_undo(&e.data, &e.history) { editor_message(e, "Niente da annullare"); return }
	editor_changed_stroke(e, &e.history.strokes[e.history.done])
}

editor_redo :: proc(e: ^Editor) {
	if e.stroke != nil { return }
	if !level.sculpt_redo(&e.data, &e.history) { editor_message(e, "Niente da ripetere"); return }
	editor_changed_stroke(e, &e.history.strokes[e.history.done-1])
}

// A change of map, a reload or the way out: with changes not saved, the first press warns and the second goes.
@(private = "file")
editor_may_discard :: proc(e: ^Editor) -> bool {
	if !editor_unsaved(e) || e.discard_armed { e.discard_armed = false; return true }
	e.discard_armed = true
	editor_message(e, "Modifiche non salvate: Ctrl+S per salvarle, o premi di nuovo per perderle")
	return false
}

@(private)
editor_update :: proc(data: rawptr, frame: ^host.Frame) {
	e := cast(^Editor)data
	e.message_timer = max(0, e.message_timer-frame.dt)
	// The second press that throws the changes away counts while its warning is on screen.
	if e.message_timer <= 0 { e.discard_armed = false }
	if e.smoke != nil { editor_smoke_update(e, frame); return }
	if !frame.focused { return }
	devices := frame.devices
	ctrl := input.key_down(devices, .LEFT_CONTROL) || input.key_down(devices, .RIGHT_CONTROL)
	shift := input.key_down(devices, .LEFT_SHIFT) || input.key_down(devices, .RIGHT_SHIFT)
	// The camera.
	if input.mouse_down(devices, .RIGHT) {
		delta := input.mouse_delta(devices)
		e.yaw -= delta.x*0.006
		e.pitch = clamp(e.pitch+delta.y*0.006, 0.15, 1.5)
	}
	if input.key_down(devices, .Q) { e.yaw += 1.6*frame.dt }
	if input.key_down(devices, .E) { e.yaw -= 1.6*frame.dt }
	if wheel := input.mouse_wheel(devices); wheel != 0 { e.distance = clamp(e.distance*math.pow(f32(0.88), wheel), 4, 420) }
	if !ctrl {
		ahead := f32(int(input.key_down(devices, .W))-int(input.key_down(devices, .S)))
		side := f32(int(input.key_down(devices, .D))-int(input.key_down(devices, .A)))
		forward := rl.Vector3{-math.sin(e.yaw), 0, -math.cos(e.yaw)}
		right := rl.Vector3{-forward.z, 0, forward.x}
		e.focus += (forward*ahead+right*side)*(e.distance*0.9*frame.dt)
	}
	// The keys.
	for key, i in ([9]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}) {
		if input.key_pressed(devices, key) && e.stroke == nil { e.brush, e.ramp_set, e.copying = level.Sculpt_Brush(i), false, false }
	}
	if input.key_pressed(devices, .T) { e.paint = (e.paint+1)%len(PAINT_KINDS) }
	if input.key_pressed(devices, .LEFT_BRACKET) || input.key_pressed(devices, .MINUS) { e.radius = max(e.radius-1, 0) }
	if input.key_pressed(devices, .RIGHT_BRACKET) || input.key_pressed(devices, .EQUAL) { e.radius = min(e.radius+1, level.SCULPT_MAX_RADIUS) }
	if input.key_pressed(devices, .PAGE_UP) && e.stroke == nil { e.layer = min(e.layer+1, grid.HIGHEST_LAYER) }
	if input.key_pressed(devices, .PAGE_DOWN) && e.stroke == nil { e.layer = max(e.layer-1, grid.LOWEST_LAYER) }
	if ctrl && input.key_pressed(devices, .Z) { if shift { editor_redo(e) } else { editor_undo(e) } }
	if ctrl && input.key_pressed(devices, .Y) { editor_redo(e) }
	if ctrl && input.key_pressed(devices, .S) && e.stroke == nil { _ = editor_save(e) }
	if input.key_pressed(devices, .G) && e.stroke == nil { editor_next_error(e) }
	if input.key_pressed(devices, .F5) && e.stroke == nil && editor_may_discard(e) {
		if editor_open(e, e.target_index) { editor_message(e, "Ricaricata dai file") }
	}
	if input.key_pressed(devices, .TAB) && e.stroke == nil && editor_may_discard(e) {
		_ = editor_open(e, e.target_index+(-1 if shift else 1))
	}
	if input.key_pressed(devices, .ESCAPE) && editor_may_discard(e) { host.quit(frame); return }
	// The brush.
	if !e.opened { return }
	camera := editor_camera(e)
	e.hovered, e.has_hovered = view_pick(&e.data, e.layer, camera, frame.mouse, frame.canvas.width, frame.canvas.height)
	if !frame.mouse_inside { e.has_hovered = false }
	cell := e.hovered
	if input.mouse_pressed(devices, .LEFT) && e.has_hovered {
		switch e.brush {
		case .Ramp: editor_ramp(e, cell)
		case .Paste: editor_paste(e, cell)
		case .Copy: e.copy_from, e.copying = cell, true
		case .Raise, .Lower, .Smooth, .Flatten, .Paint, .Noise:
			editor_begin(e, cell)
			editor_apply(e, cell)
		}
	} else if input.mouse_down(devices, .LEFT) && e.stroke != nil && e.has_hovered {
		e.stroke_timer += frame.dt
		if cell != e.last_cell || e.stroke_timer >= BRUSH_REPEAT {
			editor_apply(e, cell)
			e.stroke_timer, e.last_cell = 0, cell
		}
	}
	if input.mouse_released(devices, .LEFT) {
		editor_end(e)
		if e.copying && e.has_hovered {
			level.sculpt_copy(&e.data, e.copy_from, cell, &e.clip)
			editor_message(e, fmt.tprintf("Copiate %d per %d caselle: Incolla (8) le mette giù", e.clip.width, e.clip.height))
		}
		e.copying = false
	}
}

// A cell's square at its surface's top, a little over it.
@(private = "file")
draw_cell_mark :: proc(data: ^level.Level, cell: grid.Position, color: rl.Color, filled: bool) {
	center := rl.Vector3{f32(cell.x)+.5, cell_top(data, cell)+0.03, f32(cell.y)+.5}
	if filled { rl.DrawCube(center, 0.96, 0.05, 0.96, color) }
	rl.DrawCubeWires(center, 0.98, 0.06, 0.98, {color.r, color.g, color.b, 255})
}

@(private)
editor_draw :: proc(data: rawptr, frame: ^host.Frame) {
	e := cast(^Editor)data
	rl.ClearBackground({14, 16, 24, 255})
	if e.opened {
		camera := editor_camera(e)
		rl.BeginMode3D(camera)
		view_draw(&e.view, &e.data, e.layer, camera)
		// The errors, in red: the cell, and a pin over it to be seen from afar.
		for err in e.report.errors {
			draw_cell_mark(&e.data, err.cell, {255, 40, 40, 150}, true)
			top := rl.Vector3{f32(err.cell.x)+.5, cell_top(&e.data, err.cell), f32(err.cell.y)+.5}
			rl.DrawCube(top+{0, 1.2, 0}, 0.14, 2.4, 0.14, {255, 60, 60, 255})
			rl.DrawSphere(top+{0, 2.6, 0}, 0.4, {255, 60, 60, 255})
		}
		// The brush.
		if e.has_hovered {
			color := rl.Color{255, 230, 120, 90}
			switch e.brush {
			case .Ramp, .Copy:
				from := e.ramp_from if e.brush == .Ramp else e.copy_from
				if e.ramp_set || e.copying {
					if e.brush == .Copy {
						low := grid.Position{x = min(from.x, e.hovered.x), y = min(from.y, e.hovered.y), layer = e.layer}
						high := grid.Position{x = max(from.x, e.hovered.x), y = max(from.y, e.hovered.y), layer = e.layer}
						for y in low.y..=high.y { for x in low.x..=high.x { draw_cell_mark(&e.data, {x = x, y = y, layer = e.layer}, color, false) } }
					} else {
						a := rl.Vector3{f32(from.x)+.5, cell_top(&e.data, from)+.1, f32(from.y)+.5}
						b := rl.Vector3{f32(e.hovered.x)+.5, cell_top(&e.data, e.hovered)+.1, f32(e.hovered.y)+.5}
						rl.DrawLine3D(a, b, {255, 230, 120, 255})
					}
				}
				draw_cell_mark(&e.data, e.hovered, color, true)
			case .Paste:
				for y in 0..<max(e.clip.height, 1) { for x in 0..<max(e.clip.width, 1) { draw_cell_mark(&e.data, grid.offset(e.hovered, x, y), color, false) } }
			case .Raise, .Lower, .Smooth, .Flatten, .Paint, .Noise:
				cells := make([dynamic]grid.Position, context.temp_allocator)
				level.sculpt_footprint(e.hovered, e.radius, &cells)
				for c in cells { if level.layer_contains(&e.data, c) { draw_cell_mark(&e.data, c, color, false) } }
			}
		}
		rl.EndMode3D()
	}
	// The panel.
	theme := frame.theme
	rl.DrawRectangleRec({10, 10, 430, 128}, {8, 12, 22, 225})
	ui.draw_text(theme, target_title(e.target), {20, 16}, .Body, {226, 236, 246, 255})
	brushes, layers, kinds := BRUSH_NAMES, LAYER_NAMES, PAINT_NAMES
	brush := brushes[e.brush]
	if e.brush == .Paint { brush = fmt.tprintf("%s %s", brush, kinds[e.paint]) }
	ui.draw_text(theme, fmt.tprintf("Piano: %s   Pennello: %s   Grandezza: %d", layers[level.layer_slot(e.layer)], brush, e.radius), {20, 44}, .Small, {180, 214, 236, 255})
	state := "modifiche non salvate" if editor_unsaved(e) else "salvata"
	if e.has_hovered { state = fmt.tprintf("%s   casella %d, %d: %d gradini", state, e.hovered.x, e.hovered.y, level.height_at(&e.data, e.hovered)) }
	ui.draw_text(theme, state, {20, 66}, .Small, {150, 170, 190, 255})
	if len(e.report.errors) > 0 {
		ui.draw_text(theme, fmt.tprintf("%d errori: %s", len(e.report.errors), e.report.errors[0].text), {20, 90}, .Small, {255, 110, 100, 255})
	} else {
		ui.draw_text(theme, "Nessun errore", {20, 90}, .Small, {120, 220, 150, 255})
	}
	if e.message_timer > 0 { ui.draw_text(theme, e.message, {20, 112}, .Small, {246, 220, 150, 255}) }
	help := EDITOR_HELP
	for line, i in help { ui.draw_text(theme, line, {20, frame.canvas.height-70+f32(i)*20}, .Small, {170, 186, 204, 230}) }
}

@(private)
editor_destroy :: proc(data: rawptr) {
	e := cast(^Editor)data
	editor_close_map(e)
	view_destroy(&e.view)
	check_report_destroy(&e.report)
	delete(e.clip.cells)
	delete(e.message)
	delete(e.root)
	free(e.world)
	if e.smoke != nil { free(e.smoke) }
	free(e)
}

// The editor as a scene of its own, on the first map (the flat arena). With `smoke`, the smoke act drives it instead of
// the user (smoke.odin), with its own root under build/.
editor_scene :: proc(smoke := false) -> host.Scene {
	e := new(Editor)
	e.root = strings.clone(EDITOR_SMOKE_ROOT if smoke else MAPS_ROOT)
	e.world = new(world.World)
	e.radius = 2
	if smoke { e.smoke = new(Editor_Smoke) }
	_ = editor_open(e, 0)
	return host.Scene{name = "editor-mappe", data = e, opaque = true, modal = true, clear_color = {14, 16, 24, 255},
		update = editor_update, draw = editor_draw, after_present = editor_smoke_present if smoke else nil, destroy = editor_destroy}
}
