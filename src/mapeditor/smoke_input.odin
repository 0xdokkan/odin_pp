package mapeditor

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import grid "../engine/grid"
import host "../engine/host"
import input "../engine/input"
import level "../level"

// THE SMOKE'S SECOND PART: the editor used through its keys and its mouse, as a user would, one frame of input at a
// time given to editor_input (the code the window's own frames go through). On the flat arena opened again: a brush
// picked with its key, a click, the button held and a drag; undo and redo; the kinds gone round with T and a wall
// painted; a piece copied by dragging and pasted; a ramp, the noise, smoothing and flattening; the camera turned,
// zoomed and moved; the layers; a save; a change of map with changes not saved, back again, a reload, G; the way out.

// A frame of input: the devices' snapshot and the host's frame that carries it.
@(private = "file")
Fake_Input :: struct {
	devices: input.Device_Snapshot,
	frame:   host.Frame,
}

// A frame at 60 a second, the window focused, nothing pressed, and the mouse out of the window until `point` puts it
// on a cell (never where the real mouse is: the smoke is the same whoever is at the computer).
@(private = "file")
fake_frame :: proc(fake: ^Fake_Input, frame: ^host.Frame) {
	fake.devices = {focused = true}
	fake.frame = frame^
	fake.frame.devices = &fake.devices
	fake.frame.dt = 1.0/60
	fake.frame.focused = true
	fake.frame.mouse, fake.frame.mouse_inside = {-1000, -1000}, false
}

@(private = "file")
press :: proc(fake: ^Fake_Input, keys: ..rl.KeyboardKey) {
	for key in keys { fake.devices.keys_pressed[key], fake.devices.keys_down[key] = true, true }
}

@(private = "file")
hold :: proc(fake: ^Fake_Input, keys: ..rl.KeyboardKey) {
	for key in keys { fake.devices.keys_down[key] = true }
}

@(private = "file")
Button_State :: enum { Press, Hold, Release }

@(private = "file")
button :: proc(fake: ^Fake_Input, which: rl.MouseButton, state: Button_State) {
	switch state {
	case .Press: fake.devices.buttons_pressed[which], fake.devices.buttons_down[which] = true, true
	case .Hold: fake.devices.buttons_down[which] = true
	case .Release: fake.devices.buttons_released[which] = true
	}
}

// The mouse over `cell` of the active layer: where the camera shows the top of what is drawn there.
@(private = "file")
point :: proc(e: ^Editor, fake: ^Fake_Input, cell: grid.Position) {
	p := grid.Position{x = cell.x, y = cell.y, layer = e.layer}
	top := rl.Vector3{f32(p.x)+.5, cell_top(&e.data, p), f32(p.y)+.5}
	fake.frame.mouse = rl.GetWorldToScreenEx(top, editor_camera(e), i32(fake.frame.canvas.width), i32(fake.frame.canvas.height))
	fake.frame.mouse_inside = true
}

// A click of the left button on `cell`: pressed in one frame (`release` false) and let go in the next one.
@(private = "file")
click :: proc(e: ^Editor, fake: ^Fake_Input, cell: grid.Position, release: bool) {
	point(e, fake, cell)
	button(fake, .LEFT, .Release if release else .Press)
}

@(private = "file")
height :: proc(e: ^Editor, x, y: int) -> i32 {
	return level.height_at(&e.data, {x = x, y = y})
}

@(private = "file")
kind :: proc(e: ^Editor, cell: grid.Position) -> level.Tile_Kind {
	tile, _ := level.tile_at(&e.data, cell)
	return tile.kind
}

@(private = "file")
near :: proc(a, b: f32) -> bool {
	return abs(a-b) < 0.001
}

// The arena's camera of the first part.
@(private = "file")
arena_camera :: proc(e: ^Editor) {
	e.focus, e.yaw, e.pitch, e.distance = {11.5, 0, 8.5}, 0.6, 0.85, 26
}

// One frame of the second part: the input of action `s.action`, what it must have done, and the next action (an action
// held over several frames counts them in `s.held`).
@(private)
smoke_input :: proc(e: ^Editor, frame: ^host.Frame) {
	s := e.smoke
	fake: Fake_Input
	fake_frame(&fake, frame)
	// The cells it uses on the flat arena (23 by 17, with the first part's hill round (11, 8)).
	block := grid.Position{x = 4, y = 5}
	wall := grid.Position{x = 3, y = 12}
	paste := grid.Position{x = 17, y = 4}
	ramp_from, ramp_to := grid.Position{x = 18, y = 6}, grid.Position{x = 18, y = 14}
	noise := grid.Position{x = 3, y = 2}
	lost := grid.Position{x = 2, y = 14}
	advance := true
	switch s.action {
	case 0:
		// The flat arena opened again, as its files have it (the hill saved in the first part).
		smoke_check(editor_open(e, 0), "the flat arena does not open again")
		arena_camera(e)
		e.radius = 0
		editor_input(e, &fake.frame)
	case 1:
		press(&fake, .RIGHT_BRACKET, .ONE)
		editor_input(e, &fake.frame)
		smoke_check(e.radius == 1 && e.brush == .Raise, "] and 1 do not pick a brush of radius 1")
	case 2:
		point(e, &fake, block)
		editor_input(e, &fake.frame)
		smoke_check(e.has_hovered && e.hovered == block, "the mouse is not over the cell it points at")
		s.base = height(e, block.x, block.y)
	case 3:
		click(e, &fake, block, false)
		editor_input(e, &fake.frame)
		smoke_check(e.stroke != nil && height(e, block.x, block.y) == s.base+1, "a click does not raise")
	case 4:
		// The button held for half a second: the brush acts again every BRUSH_REPEAT, three times more.
		point(e, &fake, block)
		button(&fake, .LEFT, .Hold)
		editor_input(e, &fake.frame)
		s.held += 1
		advance = s.held >= 30
		if advance { smoke_check(height(e, block.x, block.y) == s.base+4 && height(e, block.x+1, block.y+1) == s.base+4, "the held brush does not act again") }
	case 5:
		done := e.history.done
		click(e, &fake, block, true)
		editor_input(e, &fake.frame)
		smoke_check(e.stroke == nil && e.history.done == done+1 && editor_unsaved(e), "the stroke let go is not kept")
		s.capture = "odin_pp_editor_mouse.png"
	case 6:
		press(&fake, .LEFT_BRACKET)
		editor_input(e, &fake.frame)
		smoke_check(e.radius == 0, "[ does not make the brush smaller")
	case 7, 8, 9:
		// A drag along a row: every cell the mouse goes over, once.
		cell := grid.Position{x = 8+s.action-7, y = 15}
		before := height(e, cell.x, cell.y)
		point(e, &fake, cell)
		button(&fake, .LEFT, .Press if s.action == 7 else .Hold)
		editor_input(e, &fake.frame)
		smoke_check(height(e, cell.x, cell.y) == before+1, "the drag misses a cell")
	case 10:
		click(e, &fake, {x = 10, y = 15}, true)
		editor_input(e, &fake.frame)
		smoke_check(e.stroke == nil, "the drag does not end")
	case 11:
		press(&fake, .TWO)
		editor_input(e, &fake.frame)
	case 12:
		click(e, &fake, block, false)
		editor_input(e, &fake.frame)
		smoke_check(height(e, block.x, block.y) == s.base+3, "Abbassa does not lower")
	case 13:
		click(e, &fake, block, true)
		editor_input(e, &fake.frame)
	case 14:
		hold(&fake, .LEFT_CONTROL)
		press(&fake, .Z)
		editor_input(e, &fake.frame)
		smoke_check(height(e, block.x, block.y) == s.base+4, "Ctrl+Z does not undo")
	case 15:
		hold(&fake, .LEFT_CONTROL)
		press(&fake, .Y)
		editor_input(e, &fake.frame)
		smoke_check(height(e, block.x, block.y) == s.base+3, "Ctrl+Y does not do again")
	case 16:
		press(&fake, .FIVE)
		editor_input(e, &fake.frame)
		s.paint = e.paint
	case 17, 18, 19, 20:
		// T four times: round the four kinds, back to the rock.
		press(&fake, .T)
		editor_input(e, &fake.frame)
		kinds := PAINT_KINDS
		if s.action == 20 { smoke_check(e.paint == s.paint && kinds[e.paint] == .Wall, "T does not go round the kinds") }
	case 21:
		click(e, &fake, wall, false)
		editor_input(e, &fake.frame)
		smoke_check(kind(e, wall) == .Wall, "Dipingi does not paint the rock")
	case 22:
		// Over the block of rock now: the mouse is on its top.
		click(e, &fake, wall, true)
		editor_input(e, &fake.frame)
		smoke_check(e.hovered == wall, "the mouse does not stop on the rock's top")
	case 23:
		press(&fake, .SEVEN)
		editor_input(e, &fake.frame)
	case 24:
		click(e, &fake, {x = 3, y = 4}, false)
		editor_input(e, &fake.frame)
		smoke_check(e.copying, "Copia does not begin")
	case 25:
		point(e, &fake, {x = 5, y = 6})
		button(&fake, .LEFT, .Hold)
		editor_input(e, &fake.frame)
		s.capture = "odin_pp_editor_mouse_copia.png"
	case 26:
		click(e, &fake, {x = 5, y = 6}, true)
		editor_input(e, &fake.frame)
		smoke_check(e.clip.width == 3 && e.clip.height == 3 && !e.copying, "Copia does not copy the rectangle dragged")
	case 27:
		press(&fake, .EIGHT)
		point(e, &fake, paste)
		editor_input(e, &fake.frame)
		s.capture = "odin_pp_editor_mouse_incolla.png"
	case 28:
		click(e, &fake, paste, false)
		editor_input(e, &fake.frame)
		for dy in 0..<3 { for dx in 0..<3 { smoke_check(height(e, paste.x+dx, paste.y+dy) == height(e, 3+dx, 4+dy), "the piece pasted is not the one copied") } }
	case 29:
		click(e, &fake, paste, true)
		editor_input(e, &fake.frame)
	case 30:
		press(&fake, .SIX)
		editor_input(e, &fake.frame)
		s.ramp_high, s.ramp_low = height(e, ramp_from.x, ramp_from.y), height(e, ramp_to.x, ramp_to.y)
	case 31:
		click(e, &fake, ramp_from, false)
		editor_input(e, &fake.frame)
		smoke_check(e.ramp_set, "the ramp's first end is not taken")
	case 32:
		click(e, &fake, ramp_from, true)
		editor_input(e, &fake.frame)
	case 33:
		click(e, &fake, ramp_to, false)
		editor_input(e, &fake.frame)
		middle := i32(math.round(f32(s.ramp_high)+f32(s.ramp_low-s.ramp_high)*0.5))
		smoke_check(!e.ramp_set && s.ramp_high > s.ramp_low && height(e, 18, 10) == middle, "the ramp does not go down between its ends")
	case 34:
		click(e, &fake, ramp_to, true)
		editor_input(e, &fake.frame)
	case 35:
		press(&fake, .NINE, .RIGHT_BRACKET)
		editor_input(e, &fake.frame)
		smoke_check(e.brush == .Noise && e.radius == 1, "9 and ] do not pick the noise")
	case 36:
		click(e, &fake, noise, false)
		editor_input(e, &fake.frame)
	case 37:
		click(e, &fake, noise, true)
		editor_input(e, &fake.frame)
		smoke_check(e.stroke == nil, "the noise's stroke does not end")
	case 38:
		press(&fake, .THREE, .RIGHT_BRACKET)
		editor_input(e, &fake.frame)
		smoke_check(e.brush == .Smooth && e.radius == 2, "3 and ] do not pick the smoothing")
	case 39:
		// Smoothing held on the block: its rim comes down.
		point(e, &fake, block)
		button(&fake, .LEFT, .Press if s.held == 0 else .Hold)
		editor_input(e, &fake.frame)
		s.held += 1
		advance = s.held >= 10
		if advance {
			top := i32(0)
			for dy in -1..=1 { for dx in -1..=1 { top = max(top, height(e, block.x+dx, block.y+dy)) } }
			smoke_check(top < s.base+4, "Leviga does not smooth the block")
		}
	case 40:
		click(e, &fake, block, true)
		editor_input(e, &fake.frame)
	case 41:
		press(&fake, .FOUR, .LEFT_BRACKET)
		editor_input(e, &fake.frame)
		smoke_check(e.brush == .Flatten && e.radius == 1, "4 and [ do not pick the flattening")
	case 42:
		// Flattening from the pasted piece's corner, dragged one cell on.
		click(e, &fake, paste, false)
		editor_input(e, &fake.frame)
	case 43:
		point(e, &fake, {x = 18, y = 5})
		button(&fake, .LEFT, .Hold)
		editor_input(e, &fake.frame)
	case 44:
		click(e, &fake, {x = 18, y = 5}, true)
		editor_input(e, &fake.frame)
		smoke_check(height(e, 19, 6) == height(e, paste.x, paste.y) && height(e, 18, 10) != height(e, paste.x, paste.y), "Appiattisci does not level to where it began")
	case 45:
		// The camera: dragged with the right button, zoomed, moved and turned with the keys.
		s.yaw, s.distance, s.focus = e.yaw, e.distance, e.focus
		button(&fake, .RIGHT, .Press if s.held == 0 else .Hold)
		fake.devices.mouse_motion = {40, 0}
		editor_input(e, &fake.frame)
		s.held += 1
		advance = s.held >= 5
		if advance { smoke_check(near(e.yaw, s.yaw-0.24), "the right button does not turn the camera") }
	case 46:
		s.yaw = e.yaw
		fake.devices.wheel = 2
		editor_input(e, &fake.frame)
		smoke_check(near(e.distance, s.distance*0.88*0.88) && near(e.yaw, s.yaw), "the wheel does not zoom")
	case 47:
		if s.held == 0 { s.focus, s.distance = e.focus, e.distance }
		hold(&fake, .W)
		editor_input(e, &fake.frame)
		s.held += 1
		advance = s.held >= 10
		if advance {
			forward := rl.Vector3{-math.sin(e.yaw), 0, -math.cos(e.yaw)}
			goal := s.focus+forward*(s.distance*0.15)
			smoke_check(near(e.focus.x, goal.x) && near(e.focus.z, goal.z), "W does not move the camera ahead")
		}
	case 48:
		if s.held == 0 { s.yaw = e.yaw }
		hold(&fake, .Q)
		editor_input(e, &fake.frame)
		s.held += 1
		advance = s.held >= 10
		if advance { smoke_check(near(e.yaw, s.yaw+1.6*10.0/60), "Q does not turn the camera") }
	case 49:
		arena_camera(e)
		press(&fake, .PAGE_DOWN)
		editor_input(e, &fake.frame)
		smoke_check(e.layer == -1, "PagGiù does not go to the layer under")
	case 50:
		press(&fake, .PAGE_UP)
		editor_input(e, &fake.frame)
		smoke_check(e.layer == grid.GROUND_LAYER, "PagSu does not come back to the ground")
	case 51:
		// Ctrl+S: saved, and the S held with Ctrl does not move the camera.
		focus := e.focus
		hold(&fake, .LEFT_CONTROL, .S)
		press(&fake, .S)
		editor_input(e, &fake.frame)
		folder := target_folder(e.root, e.target)
		smoke_check(!editor_unsaved(e) && os.exists(fmt.tprintf("%s/terra_altezze.png", folder)) && os.exists(fmt.tprintf("%s/terra_tipi.png", folder)), "Ctrl+S does not save")
		smoke_check(e.focus == focus, "Ctrl+S moves the camera")
		s.saved_block, s.saved_ramp = height(e, block.x, block.y), height(e, 18, 10)
		s.capture = "odin_pp_editor_mouse_salvata.png"
	case 52:
		// A change not saved, then Tab: the first press warns, the second one goes.
		press(&fake, .ONE, .LEFT_BRACKET)
		editor_input(e, &fake.frame)
		s.lost = height(e, lost.x, lost.y)
	case 53:
		click(e, &fake, lost, false)
		editor_input(e, &fake.frame)
	case 54:
		click(e, &fake, lost, true)
		editor_input(e, &fake.frame)
		smoke_check(editor_unsaved(e) && height(e, lost.x, lost.y) == s.lost+1, "the change to lose is not made")
	case 55:
		press(&fake, .TAB)
		editor_input(e, &fake.frame)
		smoke_check(e.target_index == 0 && e.discard_armed, "Tab with changes not saved does not warn")
	case 56:
		press(&fake, .TAB)
		editor_input(e, &fake.frame)
		smoke_check(e.target_index == 1 && e.opened && !e.discard_armed, "the second Tab does not go to the next map")
	case 57:
		hold(&fake, .LEFT_SHIFT)
		press(&fake, .TAB)
		editor_input(e, &fake.frame)
		smoke_check(e.target_index == 0 && e.opened, "Maiusc+Tab does not go back")
		smoke_check(height(e, block.x, block.y) == s.saved_block && height(e, 18, 10) == s.saved_ramp && kind(e, wall) == .Wall, "the arena opened again is not the one saved")
		smoke_check(height(e, lost.x, lost.y) == s.lost, "the change not saved is still there")
	case 58:
		press(&fake, .F5)
		editor_input(e, &fake.frame)
		smoke_check(e.opened && !editor_unsaved(e) && e.message == "Ricaricata dai file", "F5 does not reload")
	case 59:
		press(&fake, .G)
		editor_input(e, &fake.frame)
		smoke_check(e.message == "Nessun errore", "G on a map without errors")
	case 60:
		click(e, &fake, lost, false)
		editor_input(e, &fake.frame)
	case 61:
		click(e, &fake, lost, true)
		editor_input(e, &fake.frame)
	case 62:
		// Esc with changes not saved: the first press warns and the editor stays.
		press(&fake, .ESCAPE)
		editor_input(e, &fake.frame)
		smoke_check(e.discard_armed && e.opened, "Esc with changes not saved does not warn")
	case 63:
		fmt.println("editor smoke: ok")
		press(&fake, .ESCAPE)
		editor_input(e, &fake.frame)
	case:
		// The second Esc asked the host to quit: nothing more.
		advance = false
	}
	if advance {
		s.action += 1
		s.held = 0
	}
}
