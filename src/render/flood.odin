package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// INONDAZIONE on the board (game/flood.odin): a wall of water sweeps the room
// from one wall to the other as the cue plays, every foe it reaches pushed as
// the front arrives, every fire it passes over sent up in steam. The front's
// place is the cue's progress: it crosses the room in FLOOD_FRONT_SHARE of the
// cue, and the pushes (Move cues carrying the card) and the steam are timed to
// its arrival.

// The share of the cue the front takes to cross the board; the rest lets the
// last pushes settle.
FLOOD_FRONT_SHARE :: f32(0.78)

FLOOD_WATER :: rl.Color{30, 100, 196, 150}
FLOOD_WATER_LIGHT :: rl.Color{90, 170, 232, 150}
FLOOD_FOAM :: rl.Color{214, 238, 252, 200}
FLOOD_STEAM :: rl.Color{226, 232, 238, 150}

// The place along its way a wave has at a cell: 0 at the wall it starts from.
@(private)
flood_progress_index :: proc(direction: game.Move_Direction, cell: grid.Position, length: int) -> int {
	switch direction {
	case .East: return cell.x
	case .West: return length-1-cell.x
	case .South: return cell.y
	case .North: return length-1-cell.y
	}
	return 0
}

// The cue progress at which the front reaches the cells `index` along.
@(private)
flood_arrival :: proc(index, length: int) -> f32 {
	return FLOOD_FRONT_SHARE*(f32(index)+0.5)/f32(length+1)
}

// The share of a cue a push of one cell takes: as long as the front takes to
// cross a cell, so that a push of several keeps up with it.
@(private)
flood_push_share :: proc(length: int) -> f32 {
	return FLOOD_FRONT_SHARE/f32(length+1)
}

// The length of the board along the way of a wave, from its sweep's event.
@(private)
flood_length :: proc(event: game.Game_Event) -> int {
	direction := game.Move_Direction(event.duration)
	if direction == .East || direction == .West { return abs(event.to_position.x-event.from_position.x)+1 }
	return abs(event.to_position.y-event.from_position.y)+1
}

// The sweep that leads the group a cue is in, if it is a wave's.
@(private)
flood_group_head :: proc(timeline: ^Presentation_Timeline) -> (head: ^Presentation_Cue, found: bool) {
	head, found = presentation_cue_at(timeline, 0)
	if !found || head.kind != .Flood_Swept { return nil, false }
	return head, true
}

// The cell of the board at `index` along the way of a wave and `across` it.
@(private = "file")
flood_cell :: proc(direction: game.Move_Direction, index, across, length, width, height: int) -> grid.Position {
	switch direction {
	case .East: return {index, across}
	case .West: return {width-1-index, across}
	case .South: return {across, index}
	case .North: return {across, height-1-index}
	}
	return {}
}

// The wave itself, after the board's actors: for every cell the front has
// reached, a swell that rises as it arrives and sinks behind it, with foam on
// its top and a wet sheen on the floor it has left.
@(private)
draw_flood_wave :: proc(renderer: ^Renderer, room: ^game.Room) {
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Flood_Swept { continue }
		draw_flood_sweep(renderer, room, cue)
	}
}

@(private = "file")
draw_flood_sweep :: proc(renderer: ^Renderer, room: ^game.Room, cue: ^Presentation_Cue) {
	tiles := &room.level_data.tiles
	direction := game.Move_Direction(cue.event.duration)
	length := flood_length(cue.event)
	across_count := tiles.height if direction == .East || direction == .West else tiles.width
	p := presentation_cue_progress(cue)
	// The front, in cells along its way: the cell centre `index` is at `index`.
	front := p/FLOOD_FRONT_SHARE*f32(length+1)-0.5
	t := tactical_world_time(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	for index in 0..<length {
		age := front-f32(index)
		// Behind the front for ten cells' time, and nothing ahead of it.
		if age < 0 || age > 9 { continue }
		for across in 0..<across_count {
			cell := flood_cell(direction, index, across, length, tiles.width, tiles.height)
			if !grid.contains(tiles, cell) || !tactical_cell_on_screen(renderer, cell) || game.cell_blocks_movement(room, cell) { continue }
			// The swell: up in a third of a cell's time, then down.
			rise := min(age/0.45, 1)
			fall := max(0, 1-max(age-0.45, 0)/2.4)
			height := 0.78*rise*fall*fall
			x, z := f32(cell.x)+0.5, f32(cell.y)+0.5
			// The sheen it leaves on the floor, fading.
			sheen := max(0, 1-age/9)
			rl.BeginBlendMode(.ALPHA)
			marley_flood_square(x, 0.034, z, 0.5, rl.Color{70, 150, 230, u8(90*sheen)})
			if height > 0.02 {
				wobble := 0.06*math.sin(f32(t)*7+f32(cell.x)*1.3+f32(cell.y)*0.9)
				body := height+wobble
				rl.DrawCube({x, body*0.5, z}, 1.0, body, 1.0, FLOOD_WATER)
				// A crest of foam along the leading edge, thinning behind the front,
				// and a drop or two thrown up at it.
				if age < 2.2 {
					lead := game.direction_offset(direction)
					crest := 0.22*max(0, 1-age/2.2)+0.04
					across_axis := direction == .East || direction == .West
					rl.DrawCube({x+f32(lead.x)*(0.5-crest*0.5), body+0.015, z+f32(lead.y)*(0.5-crest*0.5)},
						crest if across_axis else 1.0, 0.04, 1.0 if across_axis else crest, FLOOD_FOAM)
				}
				if age < 1.2 {
					seed := gothic_hash(cell.x*5+index, cell.y*3+across)
					rise_t := age/1.2
					rl.DrawCube({x+(f32(seed%7)-3)*0.07, body+0.1+0.55*math.sin(rise_t*math.PI), z+(f32(seed/7%7)-3)*0.07}, 0.07, 0.07, 0.07, FLOOD_FOAM)
				}
			}
		}
	}
	// The steam of the fires it passes: puffs that rise after the front.
	for offset in 0..<renderer_active_cue_count(renderer) {
		other, found := renderer_active_cue_at(renderer, offset)
		if !found || !other.started || other.kind != .Fire_Extinguished { continue }
		cell := other.event.from_position
		arrival := flood_arrival(flood_progress_index(direction, cell, length), length)
		age := (p-arrival)*cue.duration
		if age < 0 || age > 0.9 || !tactical_cell_on_screen(renderer, cell) { continue }
		rise := age/0.9
		for puff in 0..<3 {
			spread := f32(puff-1)*0.18
			rl.DrawSphereEx({f32(cell.x)+0.5+spread, 0.25+rise*0.9+f32(puff)*0.12, f32(cell.y)+0.5+spread*0.5}, 0.2+0.18*rise, 6, 8,
				{FLOOD_STEAM.r, FLOOD_STEAM.g, FLOOD_STEAM.b, u8(f32(FLOOD_STEAM.a)*(1-rise))})
		}
	}
	rl.EndBlendMode()
}

// A flat square on the floor.
@(private = "file")
marley_flood_square :: proc(cx, y, cz, half: f32, color: rl.Color) {
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.Vertex3f(cx-half, y, cz-half)
	rlgl.Vertex3f(cx-half, y, cz+half)
	rlgl.Vertex3f(cx+half, y, cz+half)
	rlgl.Vertex3f(cx+half, y, cz-half)
	rlgl.End()
}

// INONDAZIONE's aim, as the board shows it while the card is held over the
// board: whether it is, whether the wheel has turned the way (`forced`; else
// the mouse's cell gives it) and the way itself. The run's input sets it every
// frame (set_flood_aim); while it is active the mouse wheel turns the way and
// no longer the camera's zoom.
Flood_Aim :: struct {
	active, forced: bool,
	way: game.Move_Direction,
}

set_flood_aim :: proc(renderer: ^Renderer, active, forced: bool, way: game.Move_Direction) {
	if renderer != nil { renderer.tactical.flood_aim = {active = active, forced = forced, way = way} }
}

// Whether the wheel is the wave's way now (the camera must not zoom).
flood_aim_active :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.tactical.flood_aim.active
}

@(private = "file")
flood_label :: proc(renderer: ^Renderer, text: cstring, at: rl.Vector2, color: rl.Color) {
	size := c.int(14)
	width := rl.MeasureText(text, size)
	x := clamp(at.x, f32(width)*0.5+10, renderer.canvas_width-f32(width)*0.5-10)
	y := clamp(at.y, 132, renderer.canvas_height-190)
	rl.DrawRectangle(c.int(x)-width/2-6, c.int(y)-4, width+12, size+8, {8, 14, 24, 226})
	rl.DrawRectangleLines(c.int(x)-width/2-6, c.int(y)-4, width+12, size+8, color)
	rl.DrawText(text, c.int(x)-width/2, c.int(y), size, color)
}

// A thick line on the canvas.
@(private = "file")
flood_line :: proc(a, b: rl.Vector2, width: f32, color: rl.Color) {
	rl.DrawLineEx(a, b, width, color)
}

// The aim of the card as the board shows it: the way the wave goes drawn as a
// big arrow from the wall it starts at to the wall it ends at, with a bar on
// each of those two walls, fainter arrows across the rest of the board, the
// visible floor tinted, the line through the player stronger and the foes the
// wave will push marked.
@(private)
draw_flood_preview :: proc(renderer: ^Renderer, room: ^game.Room) {
	aim := renderer.tactical.flood_aim
	if !aim.active || room == nil || room.player == nil { return }
	direction := aim.way
	step := game.direction_offset(direction)
	tiles := &room.level_data.tiles
	width, height := f32(tiles.width), f32(tiles.height)
	for cell in renderer.tactical.visible[:renderer.tactical.visible_count] {
		if game.cell_blocks_movement(room, cell) { continue }
		draw_card_range_cell(renderer, cell, {64, 140, 226, 24}, {120, 190, 240, 40})
	}
	// The line through the player, from the wall behind him to the wall in front.
	start := room.player.position
	for grid.contains(tiles, {start.x-step.x, start.y-step.y}) { start = {start.x-step.x, start.y-step.y} }
	for cell := start; grid.contains(tiles, cell); cell = {cell.x+step.x, cell.y+step.y} {
		if game.cell_blocks_movement(room, cell) { continue }
		draw_card_range_cell(renderer, cell, {64, 140, 226, 70}, {160, 214, 250, 150})
	}
	for enemy in room.enemies {
		if game.enemy_is_out_of_play(room, enemy.id) { continue }
		draw_card_range_cell(renderer, enemy.position, {236, 248, 255, 70}, {236, 248, 255, 255})
	}
	// The two walls: where the wave starts (the bar, in cyan) and where it ends
	// (white), as board-edge segments.
	start_a, start_b, end_a, end_b: view.Vec2
	switch direction {
	case .East: start_a, start_b, end_a, end_b = {0, 0}, {0, height}, {width, 0}, {width, height}
	case .West: start_a, start_b, end_a, end_b = {width, 0}, {width, height}, {0, 0}, {0, height}
	case .South: start_a, start_b, end_a, end_b = {0, 0}, {width, 0}, {0, height}, {width, height}
	case .North: start_a, start_b, end_a, end_b = {0, height}, {width, height}, {0, 0}, {width, 0}
	}
	cyan, white := rl.Color{92, 226, 255, 255}, rl.Color{245, 250, 255, 255}
	sa, sb := to_raylib(tactical_project(renderer, start_a)), to_raylib(tactical_project(renderer, start_b))
	ea, eb := to_raylib(tactical_project(renderer, end_a)), to_raylib(tactical_project(renderer, end_b))
	flood_line(sa, sb, 6, cyan)
	flood_line(ea, eb, 6, white)
	// The arrows: the player's lane thick and bright, the others every third
	// cell fainter, each from its start wall to its end wall with a head and
	// chevrons along it.
	across_count := tiles.height if direction == .East || direction == .West else tiles.width
	player_lane := room.player.position.y if direction == .East || direction == .West else room.player.position.x
	for lane in 0..<across_count {
		main := lane == player_lane
		if !main && (lane-player_lane)%3 != 0 { continue }
		a, b: view.Vec2
		switch direction {
		case .East: a, b = {0, f32(lane)+0.5}, {width, f32(lane)+0.5}
		case .West: a, b = {width, f32(lane)+0.5}, {0, f32(lane)+0.5}
		case .South: a, b = {f32(lane)+0.5, 0}, {f32(lane)+0.5, height}
		case .North: a, b = {f32(lane)+0.5, height}, {f32(lane)+0.5, 0}
		}
		from, to := to_raylib(tactical_project(renderer, a)), to_raylib(tactical_project(renderer, b))
		along := to-from
		length := math.sqrt(along.x*along.x+along.y*along.y)
		if length < 1 { continue }
		along /= length
		side := rl.Vector2{-along.y, along.x}
		color := cyan if main else rl.Color{150, 214, 244, 120}
		thick := f32(8) if main else f32(2)
		flood_line(from, to, thick, color)
		head := f32(42) if main else f32(14)
		tip := to
		base := to-along*head
		rl.DrawTriangle(tip, base-side*head*0.55, base+side*head*0.55, white if main else color)
		// Chevrons marching along the lane.
		spacing := f32(64) if main else f32(96)
		run := math.mod(f32(tactical_world_time(renderer))*60, spacing)
		for offset := run; offset < length-head; offset += spacing {
			at := from+along*offset
			rl.DrawLineEx(at-along*8+side*10, at+along*4, 3 if main else 2, color)
			rl.DrawLineEx(at-along*8-side*10, at+along*4, 3 if main else 2, color)
		}
	}
	// Words: the wall it starts at, the wall it ends at, and the wheel.
	flood_label(renderer, "PARTE", (sa+sb)*0.5, cyan)
	flood_label(renderer, "FINE", (ea+eb)*0.5, white)
	player := to_raylib(tactical_project(renderer, {f32(room.player.position.x)+0.5, f32(room.player.position.y)+0.5}))
	flood_label(renderer, "ROTELLA: DIREZIONE", {player.x, player.y+46}, rl.Color{236, 248, 255, 255})
}
