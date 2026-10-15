package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import view "../view"

// How a living board shows what each enemy is about to do. The game uses
// SIGILLI + TERRENO; the mechanics lab cycles the four displays with F6 to
// compare them. The rules they follow come from how vision works away from
// where one looks:
// the edge of the eye misses colour and detail but catches luminance changes
// (flicker around 5-10 Hz) and motion. So an intent says what it is with a
// large pictogram and a consistent colour (red blow, orange shot or area,
// green move, violet protection), how soon with a gauge that fills toward the
// action, and that it is now with a flicker and a tremble in its last moments
// and a flash outward when it lands. Only actions about to happen are loud:
// the others stay quiet, so six enemies do not shout at once.
//
//   SIGILLI   a wax seal pinned to the enemy's card: the pictogram on paper,
//             a gauge around it; the figure trembles inside the card.
//   TERRENO   the consequence drawn where it lands (Into the Breach): the
//             cells about to be struck fill from their edges inward, the
//             player's own cell outlined when it is one of them; a move is an
//             arrow to its cell, a protection a thread to the ally.
//   SIGILLI + TERRENO  both (the game's).
//   ADESIVI   the board as it was: the small sticker, now beside the heart
//             over the enemy's head (living_heart.odin).
//
// Under fog nothing gives a hidden enemy away: its seal, arrow and thread
// show only while it is in sight, and a threatened cell only while that cell
// is.

Intent_Display :: enum u8 {Both, Seals, Ground, Labels}

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
	flash_at: view.Vec2,
}

intent_display_name :: proc(mode: Intent_Display) -> cstring {
	switch mode {
	case .Both: return "SIGILLI + TERRENO"
	case .Seals: return "SIGILLI"
	case .Ground: return "TERRENO"
	case .Labels: return "ADESIVI"
	}
	return ""
}

cycle_intent_display :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	v.intent_display = Intent_Display((int(v.intent_display)+1)%len(Intent_Display))
}

intent_seals_on :: proc(renderer: ^Renderer) -> bool {
	v := &renderer.tactical
	return v.living && (v.intent_display == .Both || v.intent_display == .Seals)
}

intent_ground_on :: proc(renderer: ^Renderer) -> bool {
	v := &renderer.tactical
	return v.living && (v.intent_display == .Both || v.intent_display == .Ground)
}

// Seconds to the action and its whole countdown; `progress` runs 0..1 to it.
intent_timing :: proc(room: ^game.Room, enemy: ^game.Enemy) -> (left, total, progress: f32) {
	total = game.tactical_enemy_intent_seconds(enemy)
	left = game.tactical_enemy_seconds(room, enemy)
	progress = clamp(1-left/max(total, 0.001), 0, 1)
	return
}

// 0 while the action is far, 1 as it lands.
intent_loudness :: proc(left: f32) -> f32 { return clamp(1-left/INTENT_LOUD_SECONDS, 0, 1) }

// A luminance flicker in the last moments: 1 lit, low dark.
intent_flicker :: proc(left: f32, now: f64, low: f32 = 0.35) -> f32 {
	if left > INTENT_FLICKER_SECONDS { return 1 }
	phase := math.sin(f32(now)*math.TAU*INTENT_FLICKER_HZ)
	return 1 if phase >= 0 else low
}

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
				trace.flash_at = {f32(enemy.position.x), f32(enemy.position.y)}
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

// The tremble of a figure about to act (the seals): 0..1.
intent_tremble :: proc(renderer: ^Renderer, room: ^game.Room, entity: game.Entity_Ref) -> f32 {
	if !intent_seals_on(renderer) || room == nil || entity.kind != .Enemy { return 0 }
	index, found := game.enemy_index_by_id(room, entity.id)
	if !found { return 0 }
	enemy := &room.enemies[index]
	if living_ring_kind(enemy) == .None || game.enemy_is_staggered(room, enemy) { return 0 }
	left, _, _ := intent_timing(room, enemy)
	return clamp(1-left/INTENT_TREMBLE_SECONDS, 0, 1)
}

// Where an enemy's seal is pinned: by the top right corner of its card. The
// hearts over the heads (living_heart.odin) keep clear of it.
intent_seal_center :: proc(renderer: ^Renderer, actor: Presentation_Actor) -> (center: rl.Vector2, ok: bool) {
	key := sprite_key_for_enemy(actor.archetype)
	character, found := flipbook_character(key)
	if !found { return }
	corner := living_billboard_geometry(renderer, character, key, actor.position, true, actor.entity).card_points[3]
	at := tactical_project(renderer, {corner.x, corner.z}, corner.y)
	return {at.x-4, at.y+8}, true
}

// SIGILLI: over the board, after the hearts.
draw_intent_seals :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !intent_seals_on(renderer) || v.snapshot == nil || !living_cards_ready(renderer) { return }
	// The world's clock: still while the player is in his shadow.
	now := tactical_world_time(renderer)
	for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		// The Pinball's ball intends nothing, and has no card to seal.
		if !actor.visible || actor.health <= 0 || !tactical_overlay_visible(renderer, cell) || tactical_pinball_holds(renderer, actor.entity) { continue }
		index, found := game.enemy_index_by_id(room, actor.entity.id)
		if !found { continue }
		enemy := &room.enemies[index]
		center, ok := intent_seal_center(renderer, actor)
		if !ok { continue }
		icon := tactical_intent_icon(room, enemy)
		kind := living_ring_kind(enemy)
		if kind == .None || game.enemy_is_staggered(room, enemy) {
			// Waiting, recovering or interrupted: a small quiet seal.
			draw_intent_sticker(center, icon, false, now, int(enemy.id), 11)
			continue
		}
		left, total, progress := intent_timing(room, enemy)
		loud := intent_loudness(left)
		lit := intent_flicker(left, now)
		color := living_ring_color(kind)
		radius := 13+4*loud
		if left < INTENT_FLICKER_SECONDS && lit == 1 { radius += 1.5 }
		// A glow of the action's colour behind it as the action nears: a patch
		// of colour survives the blur of the eye's edge, a thin line does not.
		inner, outer := radius+3, radius+3+4+4*loud
		if loud > 0 { rl.DrawCircleV(center, outer+5*loud, color_with_opacity(color, 0.3*loud*lit)) }
		// The gauge: a thin dark track, the colour filling it clockwise to the
		// action, a notch per second of the countdown.
		rl.DrawRing(center, outer-1, outer+1, 0, 360, 40, {13, 20, 30, 220})
		rl.DrawRing(center, inner-1, inner+1, 0, 360, 40, {13, 20, 30, 220})
		rl.DrawRing(center, inner, outer, -90, -90+360*progress, 40, color_with_opacity(color, (0.55+0.45*loud)*lit))
		seconds := int(math.round(total))
		for notch in 1..<max(seconds, 1) {
			a := (-90+360*f32(notch)/f32(seconds))*math.RAD_PER_DEG
			d := rl.Vector2{math.cos(a), math.sin(a)}
			rl.DrawLineEx(center+d*(inner-1), center+d*(outer+1), 2, {13, 20, 30, 255})
		}
		if left < INTENT_FLICKER_SECONDS && lit == 1 {
			rl.DrawRing(center, outer+1, outer+3, 0, 360, 40, color_with_opacity({255, 250, 235, 255}, 0.9))
		}
		draw_intent_sticker(center, icon, false, now, int(enemy.id), radius)
	}
	// The flash of an action just carried out: a ring bursting outward.
	for &trace in v.intent_traces {
		if !trace.used || trace.flash_kind == .None { continue }
		t := f32((now-trace.flash)/INTENT_FLASH_SECONDS)
		if t < 0 || t >= 1 || !tactical_render_visible(renderer, {int(trace.flash_at.x), int(trace.flash_at.y)}) { continue }
		p := tactical_project(renderer, {trace.flash_at.x+0.5, trace.flash_at.y+0.5}, 1.1)
		r := 18+46*t
		rl.DrawRing({p.x, p.y}, r, r+5*(1-t)+1, 0, 360, 48, color_with_opacity(living_ring_color(trace.flash_kind), 1-t))
	}
}

// TERRENO: on the floor, inside the 3D pass.
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
draw_intent_cell :: proc(cell: grid.Position, progress: f32, color: rl.Color, alpha: f32) {
	x, z := f32(cell.x), f32(cell.y)
	y := f32(0.045)
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

draw_intent_cell_outline :: proc(cell: grid.Position, width: f32, color: rl.Color) {
	x, z := f32(cell.x), f32(cell.y)
	y := f32(0.05)
	rl.DrawCubeV({x+0.5, y, z+width*0.5}, {1, 0.012, width}, color)
	rl.DrawCubeV({x+0.5, y, z+1-width*0.5}, {1, 0.012, width}, color)
	rl.DrawCubeV({x+width*0.5, y, z+0.5}, {width, 0.012, 1}, color)
	rl.DrawCubeV({x+1-width*0.5, y, z+0.5}, {width, 0.012, 1}, color)
}

// A move: a shaft from the enemy's cell and a head on the cell it goes to,
// the head filling as the step comes.
draw_intent_arrow :: proc(from, to: grid.Position, progress: f32, color: rl.Color) {
	a := rl.Vector3{f32(from.x)+0.5, 0.05, f32(from.y)+0.5}
	b := rl.Vector3{f32(to.x)+0.5, 0.05, f32(to.y)+0.5}
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
