package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"

// Enemy intents live in the small health tag (living_heart.odin). The main
// game also shows the threatened cells, movement arrows and protection links
// on the floor; F6 in the mechanics lab compares that with tags alone.
// Hidden enemies and cells remain hidden under the combat fog.
Intent_Display :: enum u8 {Both, Labels}

// The last seconds before an action, which are loud; the last of them flicker.
INTENT_LOUD_SECONDS :: f32(1.5)
INTENT_FLICKER_SECONDS :: f32(0.6)
INTENT_FLICKER_HZ :: f32(6)
INTENT_FLASH_SECONDS :: f64(0.32)
INTENT_TREMBLE_SECONDS :: f32(0.4)

// What an enemy is doing, remembered across frames to see the moment it acts.
Intent_Trace :: struct {
	id: u32,
	used: bool,
	planned: u64,
	kind: Living_Ring_Kind,
	left: f32,
	cells: [game.MAX_ENEMY_INTENT_THREAT_CELLS]grid.Position,
	count: int,
	// The flash of the last action, where it landed.
	flash: f64,
	flash_kind: Living_Ring_Kind,
	flash_cells: [game.MAX_ENEMY_INTENT_THREAT_CELLS]grid.Position,
	flash_count: int,
}

@(private)
intent_display_name :: proc(mode: Intent_Display) -> cstring {
	switch mode {
	case .Both: return "HUD + TERRENO"
	case .Labels: return "SOLO HUD"
	}
	return ""
}

cycle_intent_display :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	v.intent_display = Intent_Display((int(v.intent_display)+1)%len(Intent_Display))
}

@(private)
intent_ground_on :: proc(renderer: ^Renderer) -> bool {
	v := &renderer.tactical
	return v.living && v.intent_display == .Both
}

// Seconds to the action and its whole countdown; `progress` runs 0..1 to it.
@(private)
intent_timing :: proc(room: ^game.Room, enemy: ^game.Enemy) -> (left, total, progress: f32) {
	total = game.tactical_enemy_intent_seconds(enemy)
	left = game.tactical_enemy_seconds(room, enemy)
	progress = clamp(1-left/max(total, 0.001), 0, 1)
	return
}

// 0 while the action is far, 1 as it lands.
@(private)
intent_loudness :: proc(left: f32) -> f32 { return clamp(1-left/INTENT_LOUD_SECONDS, 0, 1) }

// A luminance flicker in the last moments: 1 lit, low dark.
@(private)
intent_flicker :: proc(left: f32, now: f64, low: f32 = 0.35) -> f32 {
	if left > INTENT_FLICKER_SECONDS { return 1 }
	phase := math.sin(f32(now)*math.TAU*INTENT_FLICKER_HZ)
	return 1 if phase >= 0 else low
}

@(private)
intent_trace :: proc(renderer: ^Renderer, id: u32) -> ^Intent_Trace {
	traces := &renderer.tactical.intent_traces
	free_slot: ^Intent_Trace
	for &trace in traces {
		if trace.used && trace.id == id { return &trace }
		if !trace.used && free_slot == nil { free_slot = &trace }
	}
	if free_slot == nil { free_slot = &traces[int(id)%len(traces)] }
	free_slot^ = {id = id, used = true, left = 99}
	return free_slot
}

// Once per frame in the board pass: notes each enemy's intent, and flashes
// the one that has just been carried out (its countdown ran out and a new
// plan took its place).
@(private)
update_intent_traces :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	if room == nil || !renderer.tactical.living { return }
	for &trace in renderer.tactical.intent_traces {
		if !trace.used { continue }
		found := false
		for &enemy in room.enemies { if enemy.id == trace.id { found = true; break } }
		if !found && now-trace.flash > INTENT_FLASH_SECONDS { trace = {} }
	}
	for &enemy in room.enemies {
		trace := intent_trace(renderer, enemy.id)
		left, _, _ := intent_timing(room, &enemy)
		kind := living_ring_kind(&enemy)
		if trace.planned != enemy.intent.planned_pulse || left > trace.left+0.5 {
			if trace.kind != .None && trace.left < 0.5 {
				trace.flash, trace.flash_kind = now, trace.kind
				trace.flash_cells, trace.flash_count = trace.cells, trace.count
			}
		}
		trace.planned, trace.kind, trace.left = enemy.intent.planned_pulse, kind, left
		trace.count = enemy.intent.threatened_cell_count
		trace.cells = enemy.intent.threatened_cells
		if enemy.intent.kind == .Move || enemy.intent.kind == .Charge {
			trace.count = min(enemy.intent.path_count, len(trace.cells))
			for index in 0..<trace.count { trace.cells[index] = enemy.intent.path[index] }
		}
	}
}

// The subtle tremble of a figure about to act: 0..1.
@(private)
intent_tremble :: proc(renderer: ^Renderer, room: ^game.Room, entity: game.Entity_Ref) -> f32 {
	if !renderer.tactical.living || room == nil || entity.kind != .Enemy { return 0 }
	index, found := game.enemy_index_by_id(room, entity.id)
	if !found { return 0 }
	enemy := &room.enemies[index]
	if living_ring_kind(enemy) == .None || game.enemy_is_staggered(room, enemy) { return 0 }
	left, _, _ := intent_timing(room, enemy)
	return clamp(1-left/INTENT_TREMBLE_SECONDS, 0, 1)
}

// TERRENO: on the floor, inside the 3D pass.
@(private)
draw_intent_ground :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !intent_ground_on(renderer) || room == nil { return }
	now := tactical_world_time(renderer)
	player := room.player.position
	// Sunk in his shadow the player is out of reach: no threat outlines him.
	intangible := game.tactical_player_intangible(room)
	for &enemy in room.enemies {
		kind := living_ring_kind(&enemy)
		if kind == .None || game.enemy_is_staggered(room, &enemy) { continue }
		left, _, progress := intent_timing(room, &enemy)
		loud := intent_loudness(left)
		lit := intent_flicker(left, now, 0.25)
		color := living_ring_color(kind)
		switch kind {
		case .Strike, .Ranged:
			cells := enemy.intent.threatened_cells[:enemy.intent.threatened_cell_count]
			for cell in cells {
				if !tactical_render_visible(renderer, cell) { continue }
				draw_intent_cell(cell, progress, color, (0.5+0.45*loud)*lit)
				if cell == player && !intangible {
					draw_intent_cell_outline(cell, 0.06+0.05*loud, color_with_opacity({255, 240, 225, 255}, (0.6+0.4*loud)*lit))
				}
			}
			if enemy.intent.kind == .Charge {
				for cell in enemy.intent.path[:enemy.intent.path_count] {
					if tactical_render_visible(renderer, cell) { draw_intent_cell(cell, progress*0.5, color, 0.3*lit) }
				}
			}
		case .Move:
			if enemy.intent.path_count == 0 { continue }
			from := enemy.position
			to := enemy.intent.destination
			if !tactical_render_visible(renderer, from) || !tactical_render_visible(renderer, to) { continue }
			// The cell it steps onto fills like a struck one; the arrow says from where.
			draw_intent_cell(to, progress, color, (0.45+0.45*loud)*lit)
			draw_intent_arrow(from, to, progress, color_with_opacity(color, (0.45+0.5*loud)*lit))
		case .Protect:
			ally_index, found := game.enemy_index_by_id(room, enemy.intent.protected_ally.id)
			if !found { continue }
			ally := room.enemies[ally_index].position
			if !tactical_render_visible(renderer, enemy.position) || !tactical_render_visible(renderer, ally) { continue }
			a := rl.Vector3{f32(enemy.position.x)+0.5, 0.7, f32(enemy.position.y)+0.5}
			b := rl.Vector3{f32(ally.x)+0.5, 0.7, f32(ally.y)+0.5}
			tether := color_with_opacity(color, (0.5+0.5*loud)*lit)
			rl.DrawLine3D(a, b, tether)
			rl.DrawLine3D(a+{0, 0.02, 0}, b+{0, 0.02, 0}, tether)
			draw_intent_cell_outline(ally, 0.04+0.05*progress, tether)
		case .Beat, .None:
		}
	}
	// The flash of an action just carried out, on the cells it struck.
	for &trace in v.intent_traces {
		if !trace.used || trace.flash_kind == .None { continue }
		t := f32((now-trace.flash)/INTENT_FLASH_SECONDS)
		if t < 0 || t >= 1 { continue }
		for cell in trace.flash_cells[:trace.flash_count] {
			if tactical_render_visible(renderer, cell) { draw_intent_cell(cell, 1, {255, 250, 235, 255}, 0.75*(1-t)) }
		}
	}
}

// A cell striking: a frame that closes in from the edges to the middle.
@(private = "file")
draw_intent_cell :: proc(cell: grid.Position, progress: f32, color: rl.Color, alpha: f32) {
	x, z := f32(cell.x), f32(cell.y)
	y := f32(0.045)+cell_ground(cell)
	band := 0.08+0.42*progress
	c := color_with_opacity(color, clamp(alpha, 0, 1))
	rl.DrawCubeV({x+0.5, y, z+band*0.5}, {1, 0.01, band}, c)
	rl.DrawCubeV({x+0.5, y, z+1-band*0.5}, {1, 0.01, band}, c)
	if band < 0.5 {
		rl.DrawCubeV({x+band*0.5, y, z+0.5}, {band, 0.01, 1-band*2}, c)
		rl.DrawCubeV({x+1-band*0.5, y, z+0.5}, {band, 0.01, 1-band*2}, c)
	}
	draw_intent_cell_outline(cell, 0.03, color_with_opacity(color, clamp(alpha+0.3, 0, 1)))
}

@(private = "file")
draw_intent_cell_outline :: proc(cell: grid.Position, width: f32, color: rl.Color) {
	x, z := f32(cell.x), f32(cell.y)
	y := f32(0.05)+cell_ground(cell)
	rl.DrawCubeV({x+0.5, y, z+width*0.5}, {1, 0.012, width}, color)
	rl.DrawCubeV({x+0.5, y, z+1-width*0.5}, {1, 0.012, width}, color)
	rl.DrawCubeV({x+width*0.5, y, z+0.5}, {width, 0.012, 1}, color)
	rl.DrawCubeV({x+1-width*0.5, y, z+0.5}, {width, 0.012, 1}, color)
}

// A move: a shaft from the enemy's cell and a head on the cell it goes to,
// the head filling as the step comes.
@(private = "file")
draw_intent_arrow :: proc(from, to: grid.Position, progress: f32, color: rl.Color) {
	a := rl.Vector3{f32(from.x)+0.5, 0.05+cell_ground(from), f32(from.y)+0.5}
	b := rl.Vector3{f32(to.x)+0.5, 0.05+cell_ground(to), f32(to.y)+0.5}
	d := b-a
	length := rl.Vector3Length(d)
	if length < 0.01 { return }
	d /= length
	side := rl.Vector3{-d.z, 0, d.x}
	start, tip := a+d*0.45, b+d*0.3
	neck := tip-d*0.42
	for offset in ([3]f32{-0.03, 0, 0.03}) { rl.DrawLine3D(start+side*offset, neck+side*offset, color) }
	head := [3]rl.Vector3{tip, neck+side*0.28, neck-side*0.28}
	rl.DrawTriangle3D(head[0], head[1], head[2], color)
	rl.DrawTriangle3D(head[0], head[2], head[1], color)
	// The head fills toward the step.
	filled := neck+(tip-neck)*(1-progress)
	inner := [3]rl.Vector3{tip, filled+side*0.28*progress, filled-side*0.28*progress}
	bright := color_with_opacity({255, 250, 235, 255}, f32(color.a)/255)
	rl.DrawTriangle3D(inner[0], inner[1], inner[2], bright)
	rl.DrawTriangle3D(inner[0], inner[2], inner[1], bright)
}
