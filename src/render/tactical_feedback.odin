package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../grid"
import view "../view"

// These effects are a read-only interpretation of the presentation snapshot.
// No particles survive a cue or require timers, RNG, allocations or input locks.
TACTICAL_FEEDBACK_BLUE :: rl.Color{108, 192, 250, 255}
TACTICAL_FEEDBACK_HIT :: rl.Color{237, 93, 105, 255}
TACTICAL_FEEDBACK_WHITE :: rl.Color{221, 241, 255, 255}
MAX_TACTICAL_FEEDBACK_CUES :: 32

Tactical_Feedback_Layer :: enum {Ground, Accent}

Tactical_Feedback_Pose :: struct {
	lift, lean: f32,
	scale_y: f32,
	tint: rl.Color,
}

tactical_feedback_pose :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2) -> Tactical_Feedback_Pose {
	result := Tactical_Feedback_Pose{scale_y = 1, tint = rl.WHITE}
	if renderer == nil || !renderer.tactical.enabled || !renderer.tactical.scene_3d { return result }
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		entity := cue.event.target
		if cue.kind == .Card_Played { entity = game.PLAYER_ENTITY }
		snapshot := renderer.tactical.snapshot
		if snapshot == nil { snapshot = &renderer.timeline.view }
		actor, exists := presentation_actor_in_view(snapshot, entity)
		if !exists || !actor.visible || actor.position != position { continue }
		actor_key := Sprite_Key.Player if entity == game.PLAYER_ENTITY else sprite_key_for_enemy(actor.archetype)
		if key != actor_key { continue }
		p := comic_clip_progress(presentation_cue_progress(cue))
		envelope := math.sin(p*math.PI)
		if cue.kind == .Move {
			result.lift = 0.095*envelope
			result.lean = 0.028*math.sin(p*2*math.PI)
			result.scale_y = 1+0.045*envelope
		} else if cue.kind == .Damage {
			result.lean = math.sin(p*3*math.PI)*(1-p)*0.07
			result.scale_y = 1-0.07*envelope
			result.tint = {255, u8(255-145*envelope), u8(255-115*envelope), 255}
		} else if cue.kind == .Damage_Absorbed {
			result.tint = {u8(255-80*envelope), u8(255-25*envelope), 255, 255}
		} else if cue.kind == .Card_Played {
			result.lift = envelope*0.04
		}
	}
	return result
}

tactical_feedback_position :: proc(renderer: ^Renderer, entity: game.Entity_Ref, fallback: grid.Position) -> rl.Vector3 {
	if actor, found := presentation_actor_in_view(renderer.tactical.snapshot, entity); found {
		return {actor.position.x+0.5, 0.055, actor.position.y+0.5}
	}
	for object in renderer.tactical.snapshot.objects[:renderer.tactical.snapshot.object_count] {
		if object.entity == entity { return {object.position.x+0.5, 0.055, object.position.y+0.5} }
	}
	return {f32(fallback.x)+0.5, 0.055, f32(fallback.y)+0.5}
}

tactical_feedback_alpha :: proc(p: f32) -> f32 {
	return clamp(p*12, f32(0), f32(1))*clamp((1-p)*3, f32(0), f32(1))
}

// Eight angular strokes leave the cell center and grid edges readable.
draw_tactical_rune :: proc(center: rl.Vector3, radius, phase: f32, color: rl.Color, broken: bool = true) {
	for index in 0..<8 {
		angle := f32(index)*math.PI/4+phase
		a := center+rl.Vector3{math.cos(angle)*radius, 0, math.sin(angle)*radius}
		end := angle+math.PI/4*(0.62 if broken else 1)
		b := center+rl.Vector3{math.cos(end)*radius, 0, math.sin(end)*radius}
		rl.DrawLine3D(a, b, color)
		if index%2 == 0 {
			c := center+rl.Vector3{math.cos(angle)*(radius-0.07), 0, math.sin(angle)*(radius-0.07)}
			rl.DrawLine3D(a, c, color)
		}
	}
}

draw_tactical_sparks :: proc(center: rl.Vector3, p: f32, color: rl.Color, count: int = 7, radius: f32 = 0.52, scale: f32 = 1) {
	alpha := tactical_feedback_alpha(p)
	for index in 0..<count {
		angle := f32(index)*2*math.PI/f32(count)+0.35
		distance := 0.06+radius*p*(0.7+f32(index%3)*0.12)
		height := 0.12+math.sin(p*math.PI)*(0.22+f32(index%3)*0.075)
		point := center+rl.Vector3{math.cos(angle)*distance, height, math.sin(angle)*distance}
		size := (0.045+f32(index%2)*0.018)*(1-p*0.7)*scale
		spark_color := TACTICAL_FEEDBACK_WHITE if scale > 1 && index%3 == 0 else color
		rl.DrawCube(point, size, size*(1+f32(index%2)*0.4), size, color_with_opacity(spark_color, alpha))
	}
}

draw_tactical_shield :: proc(renderer: ^Renderer, origin: rl.Vector3, p: f32) {
	alpha := tactical_feedback_alpha(p)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, renderer.tactical.camera.position-renderer.tactical.camera.target))
	center := origin+rl.Vector3{0, 0.5, 0}
	radius := 0.32+0.10*p
	for index in 0..<6 {
		a := f32(index)*math.PI/3
		b := a+math.PI/3
		start := center+right*(math.cos(a)*radius)+rl.Vector3{0, math.sin(a)*radius*1.2, 0}
		end := center+right*(math.cos(b)*radius)+rl.Vector3{0, math.sin(b)*radius*1.2, 0}
		rl.DrawCylinderEx(start, end, 0.012*(1-p*0.6), 0.009, 4, color_with_opacity(TACTICAL_FEEDBACK_BLUE, alpha))
	}
	draw_tactical_sparks(center-rl.Vector3{0, 0.2, 0}, p, TACTICAL_FEEDBACK_BLUE, 4, 0.42)
}

draw_tactical_hit :: proc(renderer: ^Renderer, origin: rl.Vector3, p: f32, color: rl.Color) {
	alpha := tactical_feedback_alpha(p)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, renderer.tactical.camera.position-renderer.tactical.camera.target))
	center := origin+rl.Vector3{0, 0.53, 0}
	// Short angular cuts and four pixel fragments replace broad screen flashes.
	for index in 0..<2 {
		sign := f32(1) if index == 0 else f32(-1)
		length := 0.18+0.18*math.sin(p*math.PI)
		direction := right*length+rl.Vector3{0, length*sign*1.3, 0}
		a, b := center-direction, center+direction
		rl.DrawCylinderEx(a, b, 0.022*(1-p*0.7), 0.007, 4, color_with_opacity(color, alpha))
	}
	draw_tactical_sparks(center-rl.Vector3{0, 0.12, 0}, p, color, 4, 0.4)
}

tactical_feedback_spell_color :: proc(id: game.Card_Id) -> rl.Color {
	if id == .Firebomb { return {244, 157, 104, 255} }
	if id == .Sundering_Blow { return TACTICAL_FEEDBACK_HIT }
	if id == .Twin_Venom { return {126, 211, 174, 255} }
	if id == .Fate_Strike { return {172, 170, 241, 255} }
	return TACTICAL_FEEDBACK_BLUE
}

tactical_feedback_projectile :: proc(from, to: rl.Vector3, p: f32, arc: bool) -> rl.Vector3 {
	point := from+(to-from)*p
	if arc { point.y += math.sin(p*math.PI)*0.65 }
	return point
}

draw_tactical_spell_flight :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	from := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.65, f32(cue.event.from_position.y)+0.5}
	to := rl.Vector3{f32(cue.event.to_position.x)+0.5, 0.6, f32(cue.event.to_position.y)+0.5}
	color := tactical_feedback_spell_color(cue.event.card_definition)
	arc := cue.event.card_definition == .Firebomb || cue.event.card_definition == .Prismatic_Barrage
	for index in 0..<7 {
		part := max(f32(0), p-f32(index)*0.028)
		point := tactical_feedback_projectile(from, to, part, arc)
		cell := grid.Position{int(math.floor(point.x)), int(math.floor(point.z))}
		if !tactical_render_visible(renderer, cell) { continue }
		size := 0.14*(1-f32(index)*0.095)
		if index == 0 {
			rl.DrawCube(point, size, size, size, TACTICAL_FEEDBACK_WHITE)
		} else { rl.DrawCube(point, size, size, size, color_with_opacity(color, 1-f32(index)*0.12)) }
	}
	if !arc {
		previous := from
		for index in 1..=10 {
			part := p*f32(index)/10
			point := tactical_feedback_projectile(from, to, part, false)
			point.y += math.sin(f32(index)*12.7+p*10)*0.06
			cell := grid.Position{int(math.floor(point.x)), int(math.floor(point.z))}
			previous_cell := grid.Position{int(math.floor(previous.x)), int(math.floor(previous.z))}
			if tactical_render_visible(renderer, cell) && tactical_render_visible(renderer, previous_cell) {
				rl.DrawLine3D(previous, point, color_with_opacity(color, 0.7))
			}
			previous = point
		}
	}
}

draw_tactical_feedback :: proc(renderer: ^Renderer, layer: Tactical_Feedback_Layer) {
	if renderer == nil || !renderer.tactical.enabled || !renderer.tactical.scene_3d || renderer.tactical.snapshot == nil { return }
	// Read depth, but never leave translucent fragments in the terrain buffer.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	if layer == .Ground {
		for &actor in renderer.tactical.snapshot.enemies[:renderer.tactical.snapshot.enemy_count] {
			draw_tactical_status_rune(renderer, &actor)
		}
		draw_tactical_status_rune(renderer, &renderer.tactical.snapshot.player)
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || !tactical_cue_visible(renderer, cue) { continue }
		p := presentation_cue_progress(cue)
		alpha := tactical_feedback_alpha(p)
		center := tactical_feedback_position(renderer, cue.event.target, cue.event.to_position)
		if layer == .Ground {
			if cue.kind == .Move {
				from := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.056, f32(cue.event.from_position.y)+0.5}
				color := TACTICAL_FEEDBACK_BLUE if cue.event.target == game.PLAYER_ENTITY else TACTICAL_FEEDBACK_HIT
				for index in 0..<3 {
					point := from+(center-from)*(f32(index)+1)/4
					cell := grid.Position{int(math.floor(point.x)), int(math.floor(point.z))}
					if !tactical_render_visible(renderer, cell) { continue }
					rl.DrawCube(point, 0.09, 0.01, 0.09, color_with_opacity(color, alpha*0.4))
				}
			} else if cue.kind == .Card_Played || cue.kind == .Refocus {
				center = tactical_feedback_position(renderer, game.PLAYER_ENTITY, cue.event.from_position)
				draw_tactical_rune(center, 0.24+0.19*p, p*0.3, color_with_opacity(TACTICAL_FEEDBACK_BLUE, alpha))
				draw_tactical_rune(center+rl.Vector3{0, 0.002, 0}, 0.17+0.14*p, -p*0.3, color_with_opacity(TACTICAL_FEEDBACK_WHITE, alpha*0.6))
			} else if cue.kind == .Explosion || cue.kind == .Spell_Impact || cue.kind == .Room_Hazard_Triggered {
				color := tactical_feedback_spell_color(cue.event.card_definition)
				if cue.kind != .Spell_Impact { color = {244, 157, 104, 255} }
				draw_tactical_rune(center, 0.14+p*0.49, 0, color_with_opacity(color, alpha), false)
				// Firebomb's captured footprint is shown tile by tile; no expanding
				// screen disc can hide unrelated threats or reveal fogged cells.
				if cue.event.card_definition == .Firebomb {
					for dy in -1..=1 { for dx in -1..=1 {
						if cue.event.area_mask&(u16(1)<<u32((dy+1)*3+dx+1)) == 0 { continue }
						cell := grid.Position{cue.event.to_position.x+dx, cue.event.to_position.y+dy}
						if !tactical_render_visible(renderer, cell) { continue }
						point := rl.Vector3{f32(cell.x)+0.5, 0.057, f32(cell.y)+0.5}
						draw_tactical_rune(point, 0.34, 0, color_with_opacity(color, alpha*0.7))
					} }
				}
			}
			continue
		}
		#partial switch cue.kind {
		case .Damage:
			color := TACTICAL_FEEDBACK_HIT
			if cue.event.has_status_cause && cue.event.status_cause == .Poison { color = {126, 211, 174, 255} }
			draw_tactical_hit(renderer, center, p, color)
		case .Damage_Absorbed:
			draw_tactical_shield(renderer, center, p)
		case .Status_Applied:
			if cue.event.status == .Shield { draw_tactical_shield(renderer, center, p) }
			else if cue.event.status == .Stagger {
				// A broken crown makes interruption distinct from ordinary damage.
				for index in 0..<3 {
					x := f32(index-1)*(0.15+0.12*p)
					point := center+rl.Vector3{x, 0.85+p*0.15, 0}
					rl.DrawCube(point, 0.065, 0.12*(1-p*0.6), 0.065, color_with_opacity({218, 187, 123, 255}, alpha))
				}
			} else { draw_tactical_sparks(center, p, TACTICAL_FEEDBACK_BLUE, 4, 0.28) }
		case .Card_Played:
			center = tactical_feedback_position(renderer, game.PLAYER_ENTITY, cue.event.from_position)
			draw_tactical_sparks(center+rl.Vector3{0, 0.12, 0}, p, TACTICAL_FEEDBACK_BLUE, 5, 0.25)
		case .Spell_Launched:
			draw_tactical_spell_flight(renderer, cue)
		case .Spell_Impact:
			draw_tactical_sparks(center+rl.Vector3{0, 0.18, 0}, p, tactical_feedback_spell_color(cue.event.card_definition), 8, 0.63, 1.8)
		case .Explosion, .Room_Hazard_Triggered:
			draw_tactical_sparks(center+rl.Vector3{0, 0.1, 0}, p, {244, 157, 104, 255}, 12, 0.78, 2.2)
		case .Heal:
			draw_tactical_sparks(center, p, {128, 220, 190, 255}, 5, 0.27)
		case .Defeat:
			draw_tactical_sparks(center, p, {149, 165, 189, 255}, 6, 0.34)
		case .Explosive_Armed, .Trap_Triggered:
			draw_tactical_sparks(center, p, {227, 174, 105, 255}, 4, 0.26)
		case:
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

draw_tactical_status_rune :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) {
	if !actor.visible || actor.opacity <= 0 { return }
	cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
	if !tactical_render_visible(renderer, cell) { return }
	if index, shielded := game.status_index(&actor.statuses, .Shield); shielded && actor.statuses.items[index].potency > 0 {
		draw_tactical_rune({actor.position.x+0.5, 0.057, actor.position.y+0.5}, 0.34, 0,
			color_with_opacity(TACTICAL_FEEDBACK_BLUE, 0.42*actor.opacity))
	}
}

// Called after actor annotations: compact feedback shares their collision
// allocator and viewport instead of painting floating text across health bars.
draw_tactical_feedback_overlay :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	if !renderer.tactical.enabled || !renderer.tactical.scene_3d { return false }
	if cue.kind == .Loot || cue.kind == .Loot_Dropped { return false }
	if cue.kind == .Card_Played || cue.kind == .Refocus {
		label: cstring = "RICONCENTRAZIONE"
		if cue.kind == .Card_Played {
			definition, found := game.card_definition_by_id(cue.event.card_definition, true)
			if !found { return true }
			label = fmt.ctprintf("%s", definition.name)
		}
		viewport := tactical_world_bounds(renderer)
		width := min(f32(280), gothic_text_width(renderer, label, 13)+35)
		anchor := view.Vec2{viewport.x+viewport.width/2, viewport.y+viewport.height-5}
		bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, 23}, viewport)
		if placed {
			alpha := tactical_feedback_alpha(presentation_cue_progress(cue))
			rl.DrawRectangleRec(bounds, color_with_opacity({10, 19, 33, 244}, alpha))
			rl.DrawRectangleRec({bounds.x, bounds.y+bounds.height-1, bounds.width, 1}, color_with_opacity(TACTICAL_FEEDBACK_BLUE, alpha*0.7))
			gothic_text(renderer, "+", bounds.x+7, bounds.y+4, 13, color_with_opacity(TACTICAL_FEEDBACK_BLUE, alpha))
			gothic_text_fit(renderer, label, {bounds.x+23, bounds.y+4, bounds.width-28, 15}, 13, color_with_opacity(TACTICAL_FEEDBACK_WHITE, alpha))
		}
		return true
	}
	label: cstring
	color := TACTICAL_FEEDBACK_BLUE
	#partial switch cue.kind {
	case .Damage: label = fmt.ctprintf("-%d", cue.event.amount); color = TACTICAL_FEEDBACK_HIT
	case .Damage_Absorbed: label = fmt.ctprintf("PARATA %d", cue.event.amount)
	case .Heal: label = fmt.ctprintf("+%d", cue.event.amount); color = {128, 220, 190, 255}
	case .Status_Applied:
		if cue.event.status == .Stagger { label = "INTERROTTO"; color = {218, 187, 123, 255} }
		else if cue.event.status == .Shield { label = fmt.ctprintf("SCUDO +%d", cue.event.amount) }
	case .Attack_Missed: label = "MANCATO"
	case .Move_Blocked: label = "BLOCCATO"; color = {218, 187, 123, 255}
	case .Explosive_Disarmed: label = "DISINNESCATA"
	case .Gold_Gained: label = fmt.ctprintf("+%d ORO", cue.event.amount); color = {218, 187, 123, 255}
	case .Energy_Gained: label = fmt.ctprintf("+%d ENERGIA", cue.event.amount)
	case:
	}
	if label == nil { return true }
	center := tactical_feedback_position(renderer, cue.event.target, cue.event.to_position)
	anchor := tactical_project(renderer, {center.x, center.z}, 0.9)
	width := gothic_text_width(renderer, label, 12)+12
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, 19}, tactical_world_bounds(renderer))
	if placed {
		alpha := tactical_feedback_alpha(presentation_cue_progress(cue))
		// Collision avoidance can place a badge beside another actor. A fine
		// leader and pixel dot preserve ownership without adding another label.
		badge_center := rl.Vector2{bounds.x+bounds.width/2, bounds.y+bounds.height/2}
		if abs(badge_center.x-anchor.x) > 12 || abs(badge_center.y-anchor.y) > 18 {
			edge := rl.Vector2{clamp(anchor.x, bounds.x, bounds.x+bounds.width), clamp(anchor.y, bounds.y, bounds.y+bounds.height)}
			rl.DrawLineEx(edge, to_raylib(anchor), 1, color_with_opacity(color, alpha*0.7))
			rl.DrawRectangleRec({anchor.x-1, anchor.y-1, 2, 2}, color_with_opacity(color, alpha))
		}
		rl.DrawRectangleRec(bounds, color_with_opacity({8, 15, 26, 235}, alpha))
		rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, color_with_opacity(color, alpha))
		gothic_text(renderer, label, bounds.x+6, bounds.y+3, 12, color_with_opacity(color, alpha))
	}
	return true
}
