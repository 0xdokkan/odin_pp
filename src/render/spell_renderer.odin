package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

@(private = "file")
spell_has_visuals :: proc(id: game.Card_Id) -> bool {
	return id == .Firebomb || id == .Fate_Strike || id == .Chain_Lightning || id == .Sundering_Blow ||
	       id == .Prismatic_Barrage || id == .Twin_Venom
}

@(private = "file")
spell_color :: proc(id: game.Card_Id) -> rl.Color {
	if id == .Firebomb { return {255, 149, 55, 255} }
	if id == .Fate_Strike { return {225, 173, 255, 255} }
	if id == .Sundering_Blow { return {245, 94, 100, 255} }
	if id == .Prismatic_Barrage { return {247, 198, 112, 255} }
	if id == .Twin_Venom { return {179, 237, 111, 255} }
	return {112, 226, 255, 255}
}

@(private = "file")
prismatic_ray_color :: proc(index: int) -> rl.Color {
	switch index%3 {
	case 0: return {255, 170, 105, 255}
	case 1: return {164, 190, 255, 255}
	case 2: return {241, 143, 229, 255}
	}
	return {247, 198, 112, 255}
}

@(private = "file")
draw_player_event_clip :: proc(renderer: ^Renderer, center: view.Vec2, opacity: f32) -> bool {
	for offset in 0..<presentation_group_size(&renderer.timeline) {
		cue, found := presentation_cue_at(&renderer.timeline, offset)
		if !found || !cue.started { continue }
		key: Sprite_Key
		if cue.kind == .Card_Played {
			key = .Player_Cast
		} else if cue.kind == .Damage && cue.event.target == game.PLAYER_ENTITY {
			key = .Player_Hit
		} else { continue }
		return draw_sprite_clip(&renderer.sprite_assets, key, center, renderer.overlay_scale,
			presentation_cue_progress(cue), opacity)
	}
	return false
}

@(private)
draw_spell_cast :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	id := cue.event.card_definition
	if !spell_has_visuals(id) { return }
	center := presentation_actor_center(renderer, &renderer.timeline.view.player)
	p := presentation_cue_progress(cue)
	zoom := renderer.overlay_scale
	key := Sprite_Key.Fate_Cast
	if id == .Firebomb { key = .Firebomb_Cast }
	if (id == .Firebomb || id == .Fate_Strike) &&
	   draw_sprite_clip(&renderer.sprite_assets, key, center, zoom, p) { return }
	color := spell_color(id)
	rl.DrawEllipseLines(c.int(center.x), c.int(center.y+6*zoom), (15+12*p)*zoom, (7+5*p)*zoom, color)
	orb_count := 3 if id == .Prismatic_Barrage else 2 if id == .Twin_Venom else 6
	for index in 0..<orb_count {
		angle := f32(index)*2*math.PI/f32(orb_count)+p*2
		orb := rl.Vector2{center.x+math.cos(angle)*(20-10*p)*zoom,
			center.y-8*zoom+math.sin(angle)*10*zoom-15*p*zoom}
		orb_color := prismatic_ray_color(index) if id == .Prismatic_Barrage else color
		if id == .Prismatic_Barrage {
			radius := (3+2*p)*zoom
			rl.DrawTriangle(orb+rl.Vector2{0, -radius}, orb+rl.Vector2{-radius, radius},
				orb+rl.Vector2{radius, radius}, color_with_opacity(orb_color, 0.4+0.6*p))
		} else {
			rl.DrawCircleV(orb, (2+2*p)*zoom, color_with_opacity(orb_color, 0.4+0.6*p))
		}
	}
}

@(private = "file")
spell_projectile_position :: proc(from, to: view.Vec2, progress, zoom: f32) -> view.Vec2 {
	p := clamp(progress, f32(0), f32(1))
	return {from.x+(to.x-from.x)*p, from.y+(to.y-from.y)*p-math.sin(p*math.PI)*42*zoom}
}

@(private = "file")
draw_spell_bolt :: proc(from, to: view.Vec2, progress, zoom: f32, color: rl.Color, dashed: bool = false) {
	delta := view.Vec2{to.x-from.x, to.y-from.y}
	length := max(f32(1), math.sqrt(delta.x*delta.x+delta.y*delta.y))
	previous := from
	for index in 1..=9 {
		part := f32(index)/9
		jitter := math.sin(f32(index)*13.1+progress*15)*5*zoom
		if index == 9 || dashed { jitter = 0 }
		point := view.Vec2{from.x+delta.x*part-delta.y/length*jitter,
			from.y+delta.y*part+delta.x/length*jitter}
		if !dashed || index%2 == 1 {
			rl.DrawLineEx(to_raylib(previous), to_raylib(point), max(f32(1), 5*zoom), color_with_opacity(color, 0.25))
			rl.DrawLineEx(to_raylib(previous), to_raylib(point), max(f32(1), 2*zoom), color)
		}
		previous = point
	}
}

@(private)
draw_spell_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	id := cue.event.card_definition
	if !spell_has_visuals(id) { return }
	p := presentation_cue_progress(cue)
	zoom := renderer.overlay_scale
	from := cell_center(renderer, cue.event.from_position)
	to := cell_center(renderer, cue.event.to_position)
	from.y -= 12*zoom
	to.y -= 8*zoom
	color := spell_color(id)
	if cue.kind == .Spell_Launched {
		if id == .Prismatic_Barrage {
			point := to_raylib(spell_projectile_position(from, to, p, zoom))
			for index in 0..<3 {
				trail := spell_projectile_position(from, to, max(f32(0), p-0.08-f32(index)*0.02), zoom)
				rl.DrawLineEx(to_raylib(trail)+rl.Vector2{f32(index-1)*3*zoom, 0}, point,
					(4-f32(index)*0.7)*zoom, prismatic_ray_color(index))
			}
			rl.DrawTriangle(point+rl.Vector2{0, -8*zoom}, point+rl.Vector2{-7*zoom, 6*zoom},
				point+rl.Vector2{7*zoom, 6*zoom}, {255, 240, 217, 255})
		} else if id == .Twin_Venom {
			for sign in ([2]f32{-1, 1}) {
				previous := to_raylib(from)
				for segment in 1..=18 {
					part := p*f32(segment)/18
					point := to_raylib(spell_projectile_position(from, to, part, zoom))
					point.x += math.sin(part*math.PI*3)*sign*7*zoom
					point.y += math.sin(part*math.PI)*sign*4*zoom
					rl.DrawLineEx(previous, point, (2+part)*zoom, color_with_opacity(color, 0.3+0.7*part))
					previous = point
				}
				rl.DrawCircleV(previous, 3*zoom, {231, 255, 182, 255})
			}
		} else if id == .Firebomb {
			for index in 0..<7 {
				trail_p := max(f32(0), p-f32(index)*0.035)
				point := spell_projectile_position(from, to, trail_p, zoom)
				rl.DrawCircleV(to_raylib(point), (8-f32(index)*0.9)*zoom,
					color_with_opacity(color, (1-f32(index)/7)*0.7))
			}
			point := spell_projectile_position(from, to, p, zoom)
			if !draw_sprite_clip(&renderer.sprite_assets, .Firebomb_Projectile, point, zoom, p) {
				rl.DrawCircleV(to_raylib(point), 6*zoom, {255, 239, 171, 255})
			}
		} else {
			end := view.Vec2{from.x+(to.x-from.x)*p, from.y+(to.y-from.y)*p}
			draw_spell_bolt(from, end, p, zoom, color)
		}
		return
	}
	opacity := clamp((1-p)*2, f32(0), f32(1))
	if id == .Prismatic_Barrage {
		hits := clamp(cue.event.amount/game.PRISMATIC_HIT_DAMAGE, i32(1), i32(3))
		for index in 0..<int(hits)*4 {
			angle := f32(index)*2*math.PI/f32(hits*4)
			ray_color := color_with_opacity(prismatic_ray_color(index%int(hits)), opacity)
			inner := to_raylib(to)+rl.Vector2{math.cos(angle)*(5+12*p)*zoom, math.sin(angle)*(3+7*p)*zoom}
			outer := to_raylib(to)+rl.Vector2{math.cos(angle)*(14+28*p)*zoom, math.sin(angle)*(8+18*p)*zoom}
			rl.DrawLineEx(inner, outer, (4-3*p)*zoom, ray_color)
		}
		rl.DrawCircleV(to_raylib(to), (7+f32(hits)*2)*(1-p)*zoom, color_with_opacity({255, 244, 224, 255}, opacity))
		return
	}
	if id == .Twin_Venom {
		for sign in ([2]f32{-1, 1}) {
			origin := to_raylib(to)+rl.Vector2{sign*(7+12*p)*zoom, -12*zoom}
			tip := to_raylib(to)+rl.Vector2{sign*(2+4*p)*zoom, (12+8*p)*zoom}
			rl.DrawLineEx(origin, tip, max(f32(1), (5-4*p)*zoom), color_with_opacity(color, opacity))
			for index in 0..<3 {
				point := tip+rl.Vector2{sign*f32(index+1)*8*p*zoom, f32(index-1)*9*p*zoom}
				rl.DrawCircleV(point, (3-2*p)*zoom, color_with_opacity({223, 255, 171, 255}, opacity))
			}
		}
		return
	}
	if id == .Sundering_Blow {
		rl.DrawEllipseLines(c.int(to.x), c.int(to.y), (10+32*p)*zoom, (5+17*p)*zoom,
			color_with_opacity(color, opacity))
		for index in 0..<8 {
			angle := f32(index)*math.PI/4
			near := rl.Vector2{to.x+math.cos(angle)*(5+12*p)*zoom, to.y+math.sin(angle)*(3+6*p)*zoom}
			far := rl.Vector2{to.x+math.cos(angle)*(12+31*p)*zoom, to.y+math.sin(angle)*(7+16*p)*zoom}
			rl.DrawLineEx(near, far, max(f32(1), (4-3*p)*zoom), color_with_opacity(color, opacity))
		}
		rl.DrawCircleV(to_raylib(to), (7-5*p)*zoom, color_with_opacity({255, 218, 205, 255}, opacity))
		return
	}
	if id == .Firebomb {
		if draw_sprite_clip(&renderer.sprite_assets, .Firebomb_Impact, to, zoom, p, opacity) { return }
		// One visible blast for the complete 3x3 footprint, independent of target count.
		for dy in -1..=1 {
			for dx in -1..=1 {
				if cue.event.area_mask&(u16(1)<<u32((dy+1)*3+dx+1)) == 0 { continue }
				cell := cue.event.to_position
				cell.x += dx
				cell.y += dy
				draw_card_range_cell(renderer, cell, color_with_opacity(color, opacity*0.20),
					color_with_opacity(color, opacity*0.7))
			}
		}
		rl.DrawEllipse(c.int(to.x), c.int(to.y), (20+52*p)*zoom, (13+27*p)*zoom,
			color_with_opacity(color, opacity*0.32))
		rl.DrawEllipseLines(c.int(to.x), c.int(to.y), (18+60*p)*zoom, (12+30*p)*zoom,
			color_with_opacity({255, 226, 137, 255}, opacity))
		for index in 0..<14 {
			angle := f32(index)*2*math.PI/14
			point := rl.Vector2{to.x+math.cos(angle)*(12+50*p)*zoom,
				to.y+math.sin(angle)*(8+24*p)*zoom-18*math.sin(p*math.PI)*zoom}
			rl.DrawCircleV(point, (5-3*p)*zoom, color_with_opacity(color, opacity))
		}
	} else {
		draw_spell_bolt(from, to, p, zoom, color_with_opacity(color, opacity))
		key := Sprite_Key.Chain_Bolt if id == .Chain_Lightning else Sprite_Key.Fate_Impact
		if !draw_sprite_clip(&renderer.sprite_assets, key, to, zoom, p, opacity) {
			rl.DrawCircleLinesV(to_raylib(to), (7+22*p)*zoom, color_with_opacity(color, opacity))
			rl.DrawCircleV(to_raylib(to), (9-6*p)*zoom, color_with_opacity({246, 247, 255, 255}, opacity))
		}
	}
}

@(private = "file")
draw_spell_path_preview :: proc(renderer: ^Renderer, room: ^game.Room, card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || !renderer.has_hovered_cell ||
	   renderer_blocks_player_input(renderer) { return }
	index, found := game.hand_card_index_by_id(&room.player.deck, card_id)
	if !found { return }
	card := room.player.deck.hand[index]
	if card.definition_id != .Chain_Lightning && card.definition_id != .Fate_Strike &&
	   card.definition_id != .Sundering_Blow && card.definition_id != .Prismatic_Barrage &&
	   card.definition_id != .Twin_Venom { return }
	target, valid := game.card_drop_target(room, card, renderer.hovered_cell)
	if !valid { return }
	path := game.query_spell_path(room, card, target)
	if path.error != .None { return }
	previous := cell_center(renderer, room.player.position)
	for hit in 0..<path.count {
		center := cell_center(renderer, path.positions[hit])
		conditional := card.definition_id == .Fate_Strike && hit > 0
		color := spell_color(card.definition_id)
		draw_card_range_cell(renderer, path.positions[hit], color_with_opacity(color, 0.25), color)
		draw_spell_bolt(previous, center, 0, renderer.overlay_scale, color, conditional)
		if card.definition_id == .Sundering_Blow || card.definition_id == .Prismatic_Barrage || card.definition_id == .Twin_Venom {
			previous = center
			continue // A single primary target; conditional effects are described below.
		}
		label := fmt.ctprintf("%d", hit+1)
		if conditional { label = fmt.ctprintf("SOLO %d", game.card_die_sides(card.definition_id, card.upgrade_level)) }
		label_x := c.int(center.x)+13
		label_y := c.int(center.y)+7
		rl.DrawRectangle(label_x-3, label_y-2, rl.MeasureText(label, 11)+6, 15, {12, 19, 26, 240})
		rl.DrawText(label, label_x, label_y, 11, color)
		previous = center
	}
	lines, count := dice_spell_preview_lines(card)
	for line, line_index in lines[:count] {
		rl.DrawText(line, 265, 121+c.int(line_index)*14, 10, spell_color(card.definition_id))
	}
}

// Only the card definition and upgrade influence preview text, never a dice
// stream. The odds follow the die of the card's level.
@(private)
dice_spell_preview_lines :: proc(card: game.Card_Instance) -> (lines: [3]cstring, count: int) {
	sides := game.card_die_sides(card.definition_id, card.upgrade_level)
	if sides == 0 { return }
	dice := card_dice_label(card)
	#partial switch card.definition_id {
	case .Fate_Strike:
		return {fmt.ctprintf("%s: 1-%d ALLA PARI / RIMBALZO SU %d (1/%d)", dice, sides, sides, sides), "", ""}, 1
	case .Sundering_Blow:
		// Pairs of faces that reach the push, out of every pair.
		pushes := 0
		for a in 1..=int(sides) {
			for b in 1..=int(sides) { if i32(a+b) >= game.SUNDERING_PUSH_TOTAL { pushes += 1 } }
		}
		return {fmt.ctprintf("%s: 2-%d / %d+: SPINTA 1 (%d/%d) / RAGGIO 1-2", dice, sides*2, game.SUNDERING_PUSH_TOTAL,
			pushes, sides*sides), "", ""}, 1
	case .Prismatic_Barrage:
		hits := sides-game.DICE_SUCCESS_THRESHOLD+1
		return {fmt.ctprintf("%s: OGNI %d+ COLPISCE (%d%%) / RAGGIO 1-3 / VISTA", dice, game.DICE_SUCCESS_THRESHOLD, hits*100/sides),
			fmt.ctprintf("COLPO: %d DANNI / ALTRO DADO: SCUDO 1 PER 2 PULSE", game.PRISMATIC_HIT_DAMAGE),
			"SCUDO PRIMA / UN SOLO COLPO / ZERO COLPI: SCUDO 3"}, 3
	case .Twin_Venom:
		return {fmt.ctprintf("%s: DADO MAGGIORE +1 DANNI / RAGGIO 1-3 / VISTA", dice),
			fmt.ctprintf("COPPIA (1/%d): 2 VELENO", sides),
			"VELENO SOLO SE IL BERSAGLIO SOPRAVVIVE"}, 3
	}
	return
}
