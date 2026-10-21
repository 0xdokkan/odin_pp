package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"

// INONDAZIONE on the board (game/flood.odin): a wall of water sweeps the room
// from one wall to the other as the cue plays, every foe it reaches pushed as
// the front arrives, every fire it passes over sent up in steam. The front's
// place is the cue's progress: it crosses the room in FLOOD_FRONT_SHARE of the
// cue, and the pushes (Move cues carrying the card) and the steam are timed to
// its arrival.

// The share of the cue the front takes to cross the board; the rest lets the
// last pushes settle.
FLOOD_FRONT_SHARE :: f32(0.78)

FLOOD_WATER :: rl.Color{58, 138, 222, 140}
FLOOD_WATER_LIGHT :: rl.Color{140, 200, 244, 170}
FLOOD_FOAM :: rl.Color{236, 248, 255, 220}
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
				// Foam along the top, and a drop or two thrown up at the crest.
				rl.DrawCube({x, body+0.02, z}, 1.0, 0.05, 1.0, FLOOD_FOAM)
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
