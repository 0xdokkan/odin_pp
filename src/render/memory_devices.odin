package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"

@(private)
memory_device_tint :: proc(kind: game.Grid_Object_Kind) -> rl.Color {
	#partial switch kind {
	case .Cannon: return {106, 220, 255, 255}
	case .Flood: return {65, 157, 255, 255}
	case .Black_Hole: return {196, 113, 255, 255}
	case .Bomb_Marley: return {255, 158, 70, 255}
	}
	return GOTHIC_BLUE
}

@(private)
draw_memory_card_icon :: proc(id: game.Card_Id, bounds: rl.Rectangle, tint: rl.Color) {
	p := rl.Vector2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
	s := min(bounds.width/52, bounds.height/44)
	#partial switch id {
	case .Cannon:
		rl.DrawRectangleRec({p.x-19*s, p.y-7*s, 31*s, 12*s}, tint)
		rl.DrawRectangleRec({p.x+11*s, p.y-10*s, 9*s, 18*s}, tint)
		for x in ([2]f32{-10, 10}) { rl.DrawCircleV({p.x+x*s, p.y+10*s}, 7*s, GOTHIC_INK) }
	case .Flood:
		for row in 0..<3 {
			for i in 0..<5 {
				x := p.x-23*s+f32(i)*10*s
				y := p.y-12*s+f32(row)*12*s
				rl.DrawLineEx({x, y+4*s}, {x+5*s, y-2*s}, 3*s, tint)
				rl.DrawLineEx({x+5*s, y-2*s}, {x+10*s, y+4*s}, 3*s, tint)
			}
		}
	case .Black_Hole:
		rl.DrawRing(p, 11*s, 18*s, 20, 330, 18, tint)
		rl.DrawRing(p, 5*s, 9*s, 190, 510, 14, GOTHIC_INK)
		rl.DrawCircleV(p, 4*s, GOTHIC_INK)
	case .Bomb_Marley:
		rl.DrawCircleV({p.x, p.y+4*s}, 15*s, tint)
		rl.DrawLineEx({p.x, p.y-11*s}, {p.x+7*s, p.y-19*s}, 3*s, GOTHIC_INK)
		rl.DrawCircleV({p.x+8*s, p.y-19*s}, 4*s, GOTHIC_RED)
		for x in ([2]f32{-6, 6}) { rl.DrawCircleV({p.x+x*s, p.y+1*s}, 3*s, GOTHIC_INK) }
	}
}

@(private)
draw_memory_device :: proc(renderer: ^Renderer, object: Presentation_Grid_Object) {
	p := rl.Vector3{object.position.x+0.5, 0.10, object.position.y+0.5}
	tint := memory_device_tint(object.kind)
	time := f32(tactical_world_time(renderer))
	step := game.direction_offset(object.device_direction)
	direction := rl.Vector3{f32(step.x), 0, f32(step.y)}
	if object.kind == .Cannon {
		draw_resin_cube_v(renderer, p, {0.82, 0.16, 0.70}, RESIN_DARK)
		draw_resin_cube_v(renderer, p+rl.Vector3{0, 0.22, 0}, {0.46, 0.35, 0.46}, RESIN_CAP)
		origin := p+rl.Vector3{0, 0.40, 0}
		rl.DrawCylinderEx(origin-direction*0.15, origin+direction*0.58, 0.13, 0.17, 6, tint)
		rl.DrawCylinderEx(origin+direction*0.60, origin+direction*0.63, 0.11, 0.11, 6, GOTHIC_INK)
		if object.device_target_limit > 1 {
			rl.DrawCylinderEx(origin+direction*0.62, origin+direction*0.65, 0.065, 0.065, 6, rl.WHITE)
		}
	} else if object.kind == .Flood {
		draw_resin_cube_v(renderer, p, {0.78, 0.14, 0.78}, RESIN_DARK)
		for i in 0..<3 {
			q := p+direction*(f32(i-1)*0.21)+rl.Vector3{0, 0.12+0.04*math.sin(time*4+f32(i)), 0}
			rl.DrawCubeV(q, {0.65 if step.x == 0 else 0.08, 0.06, 0.65 if step.y == 0 else 0.08}, tint)
		}
	} else if object.kind == .Black_Hole {
		center := p+rl.Vector3{0, 0.32, 0}
		rl.DrawSphereEx(center, 0.22, 5, 7, {7, 4, 14, 255})
		for ring in 0..<2 {
			last: rl.Vector3
			for i in 0..=24 {
				a := f32(i)*math.PI*2/24+time*(0.6 if ring == 0 else -0.8)
				point := center+rl.Vector3{math.cos(a)*(0.40+f32(ring)*0.08), math.sin(a*2)*0.09, math.sin(a)*0.40}
				if i > 0 { rl.DrawLine3D(last, point, tint) }
				last = point
			}
		}
	} else {
		rl.DrawSphereEx(p+rl.Vector3{0, 0.28, 0}, 0.33, 5, 8, {35, 37, 29, 255})
		for i in 0..<3 { draw_resin_cube_v(renderer, p+rl.Vector3{0, 0.19+f32(i)*0.11, 0}, {0.66, 0.065, 0.66}, tint) }
		rl.DrawCylinderEx(p+rl.Vector3{0, 0.60, 0}, p+rl.Vector3{0.1, 0.8, 0}, 0.025, 0.025, 5, GOTHIC_PAPER)
		rl.DrawSphereEx(p+rl.Vector3{0.1, 0.8, 0}, 0.04+0.015*math.sin(time*12), 3, 4, tint)
	}
}

@(private)
draw_memory_device_ranges :: proc(renderer: ^Renderer, room: ^game.Room, active_card: u32) {
	if room == nil || room.player == nil { return }
	if !renderer.tactical.expedition_placement || !renderer.has_hovered_cell { return }
	index, found := game.hand_card_index_by_id(&room.player.deck, active_card)
	if !found { return }
	card := room.player.deck.hand[index]
	if !game.card_requires_orientation(card.definition_id) { return }
	definition, _ := game.card_definition_by_id(card.definition_id)
	_, valid := game.card_drop_target(room, card, renderer.hovered_cell)
	kind := definition.effects[0].object_kind
	color := memory_device_tint(kind) if valid else GOTHIC_RED
	object := game.Grid_Object{kind = kind, position = renderer.hovered_cell, device_direction = renderer.tactical.expedition_direction}
	for y in -7..=7 {
		for x in -7..=7 {
			cell := grid.offset(object.position, x, y)
			if !game.memory_device_contains(room, object, cell) || !tactical_cell_on_screen(renderer, cell) { continue }
			rl.DrawCubeV({f32(cell.x)+0.5, 0.08, f32(cell.y)+0.5}, {0.86, 0.025, 0.86}, color_with_opacity(color, 0.25))
		}
	}
	draw_memory_device(renderer, {kind = kind, position = {f32(object.position.x), f32(object.position.y)}, device_direction = object.device_direction})
}
