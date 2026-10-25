package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// These effects are a read-only interpretation of the presentation snapshot.
// No particles survive a cue or require timers, RNG, allocations or input locks.
TACTICAL_FEEDBACK_BLUE :: rl.Color{108, 192, 250, 255}
TACTICAL_FEEDBACK_HIT :: rl.Color{237, 93, 105, 255}
TACTICAL_FEEDBACK_WHITE :: rl.Color{221, 241, 255, 255}
TACTICAL_FEEDBACK_CRITICAL :: rl.Color{240, 198, 92, 255}
MAX_TACTICAL_FEEDBACK_CUES :: 32

Tactical_Feedback_Layer :: enum {Ground, Accent}

Tactical_Feedback_Pose :: struct {
	lift, lean: f32,
	scale_y: f32,
	tint: rl.Color,
}

@(private)
tactical_feedback_pose :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2) -> Tactical_Feedback_Pose {
	result := Tactical_Feedback_Pose{scale_y = 1, tint = rl.WHITE}
	if renderer == nil { return result }
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
		} else if cue.kind == .Damage && !attack_fx_shows(renderer, cue) && !game.event_is_lasso_turn(cue.event) {
			// A blow shown with its props has its own impact (attack_fx.odin);
			// the Lazzo's full turn shakes nothing (lasso.odin).
			result.lean = math.sin(p*3*math.PI)*(1-p)*0.07
			result.scale_y = 1-0.07*envelope
			result.tint = {255, u8(255-145*envelope), u8(255-115*envelope), 255}
		} else if (cue.kind == .Damage_Absorbed || cue.kind == .Attack_Deflected) && !attack_fx_shows(renderer, cue) {
			result.tint = {u8(255-80*envelope), u8(255-25*envelope), 255, 255}
		} else if cue.kind == .Card_Played {
			result.lift = envelope*0.04
		}
	}
	return result
}

// Where the cues aimed at an actor show: on the actor as the board shows it,
// except the player sunk in his shadow. The pool takes his place in the
// snapshot, but his body stays where it sank, and so does what the held world
// shows of him (a miss, a block, a shield, their sparks).
@(private)
tactical_cue_actor_position :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (position: view.Vec2, found: bool) {
	if entity == game.PLAYER_ENTITY && renderer.tactical.shadow.active { return renderer.tactical.shadow.body, true }
	actor, ok := presentation_actor_in_view(renderer.tactical.snapshot, entity)
	if !ok { return }
	return actor.position, true
}

@(private)
tactical_feedback_position :: proc(renderer: ^Renderer, entity: game.Entity_Ref, fallback: grid.Position) -> rl.Vector3 {
	if position, found := tactical_cue_actor_position(renderer, entity); found {
		return {position.x+0.5, 0.055, position.y+0.5}
	}
	for object in renderer.tactical.snapshot.objects[:renderer.tactical.snapshot.object_count] {
		if object.entity == entity { return {object.position.x+0.5, 0.055, object.position.y+0.5} }
	}
	return {f32(fallback.x)+0.5, 0.055, f32(fallback.y)+0.5}
}

@(private)
tactical_feedback_alpha :: proc(p: f32) -> f32 {
	return clamp(p*12, f32(0), f32(1))*clamp((1-p)*3, f32(0), f32(1))
}

// A played card's rune and sparks: blue, or the shadow's violet.
@(private = "file")
tactical_card_played_color :: proc(cue: ^Presentation_Cue) -> rl.Color {
	return SHADOW_RIM if cue.kind == .Card_Played && cue.event.card_definition == .Shadow_Step else TACTICAL_FEEDBACK_BLUE
}

// Eight angular strokes leave the cell center and grid edges readable.
@(private)
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

@(private = "file")
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

@(private)
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

@(private = "file")
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

@(private = "file")
tactical_feedback_spell_color :: proc(id: game.Card_Id) -> rl.Color {
	if id == .Firebomb { return {244, 157, 104, 255} }
	if id == .Sundering_Blow { return TACTICAL_FEEDBACK_HIT }
	if id == .Twin_Venom { return {126, 211, 174, 255} }
	if id == .Fate_Strike { return {172, 170, 241, 255} }
	if id == .Poison_Pool { return GROUND_VENOM_BUBBLE }
	if id == .Wildfire { return GROUND_CHAR_HOT }
	return TACTICAL_FEEDBACK_BLUE
}

@(private = "file")
tactical_feedback_projectile :: proc(from, to: rl.Vector3, p: f32, arc: bool) -> rl.Vector3 {
	point := from+(to-from)*p
	if arc { point.y += math.sin(p*math.PI)*0.65 }
	return point
}

@(private = "file")
draw_tactical_spell_flight :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	// A pool's flask and a fire's ember fly as paper.
	if game.card_places_ground(cue.event.card_definition) && renderer.tactical.attack_props.loaded {
		draw_ground_throw(renderer, cue)
		return
	}
	p := presentation_cue_progress(cue)
	from := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.65, f32(cue.event.from_position.y)+0.5}
	to := rl.Vector3{f32(cue.event.to_position.x)+0.5, 0.6, f32(cue.event.to_position.y)+0.5}
	color := tactical_feedback_spell_color(cue.event.card_definition)
	arc := cue.event.card_definition == .Firebomb || cue.event.card_definition == .Prismatic_Barrage
	for index in 0..<7 {
		part := max(f32(0), p-f32(index)*0.028)
		point := tactical_feedback_projectile(from, to, part, arc)
		cell := grid.Position{x = int(math.floor(point.x)), y = int(math.floor(point.z))}
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
			cell := grid.Position{x = int(math.floor(point.x)), y = int(math.floor(point.z))}
			previous_cell := grid.Position{x = int(math.floor(previous.x)), y = int(math.floor(previous.z))}
			if tactical_render_visible(renderer, cell) && tactical_render_visible(renderer, previous_cell) {
				rl.DrawLine3D(previous, point, color_with_opacity(color, 0.7))
			}
			previous = point
		}
	}
}

@(private)
draw_tactical_feedback :: proc(renderer: ^Renderer, layer: Tactical_Feedback_Layer) {
	if renderer == nil || renderer.tactical.snapshot == nil { return }
	// Read depth, but never leave translucent fragments in the terrain buffer.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	if layer == .Ground {
		for &actor in renderer.tactical.snapshot.enemies[:renderer.tactical.snapshot.enemy_count] {
			draw_tactical_status_rune(renderer, &actor)
		}
		// Behind his eyes his own rune is under the eye.
		if !first_person_hides_player(renderer) { draw_tactical_status_rune(renderer, &renderer.tactical.snapshot.player) }
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || !tactical_cue_visible(renderer, cue) { continue }
		p := presentation_cue_progress(cue)
		alpha := tactical_feedback_alpha(p)
		center := tactical_feedback_position(renderer, cue.event.target, cue.event.to_position)
		if layer == .Ground {
			// A teleport leaves no trail of steps behind it.
			if cue.kind == .Move && !game.event_is_teleport(cue.event) {
				from := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.056, f32(cue.event.from_position.y)+0.5}
				color := TACTICAL_FEEDBACK_BLUE if cue.event.target == game.PLAYER_ENTITY else TACTICAL_FEEDBACK_HIT
				for index in 0..<3 {
					point := from+(center-from)*(f32(index)+1)/4
					cell := grid.Position{x = int(math.floor(point.x)), y = int(math.floor(point.z))}
					if !tactical_render_visible(renderer, cell) { continue }
					rl.DrawCube(point, 0.09, 0.01, 0.09, color_with_opacity(color, alpha*0.4))
				}
			} else if cue.kind == .Card_Played || cue.kind == .Refocus {
				center = tactical_feedback_position(renderer, game.PLAYER_ENTITY, cue.event.from_position)
				draw_tactical_rune(center, 0.24+0.19*p, p*0.3, color_with_opacity(tactical_card_played_color(cue), alpha))
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
						cell := grid.offset(cue.event.to_position, dx, dy)
						if !tactical_render_visible(renderer, cell) { continue }
						point := rl.Vector3{f32(cell.x)+0.5, 0.057, f32(cell.y)+0.5}
						draw_tactical_rune(point, 0.34, 0, color_with_opacity(color, alpha*0.7))
					} }
				}
			}
			continue
		}
		// Behind his eyes what befalls him shows on the HUD, not under the eye.
		if cue.event.target == game.PLAYER_ENTITY && first_person_hides_player(renderer) { continue }
		#partial switch cue.kind {
		case .Damage:
			color := TACTICAL_FEEDBACK_HIT
			if cue.event.has_status_cause && cue.event.status_cause == .Poison { color = {126, 211, 174, 255} }
			if cue.event.has_status_cause && cue.event.status_cause == .Burn { color = {244, 157, 104, 255} }
			// The Lazzo's hits have their paper star (lasso.odin); a turn's 1 its
			// token; and so have the Pinball's (pinball.odin). The AK's have their
			// spark (first_person.odin).
			if !attack_fx_shows(renderer, cue) && !game.event_is_lasso(cue.event) && !game.event_is_pinball(cue.event) &&
			   !game.event_is_first_person_shot(cue.event) {
				draw_tactical_hit(renderer, center, p, color)
			}
		case .Damage_Absorbed, .Attack_Deflected:
			if !attack_fx_shows(renderer, cue) { draw_tactical_shield(renderer, center, p) }
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
			draw_tactical_sparks(center+rl.Vector3{0, 0.12, 0}, p, tactical_card_played_color(cue), 5, 0.25)
		case .Spell_Launched:
			draw_tactical_spell_flight(renderer, cue)
		case .Spell_Impact:
			draw_tactical_sparks(center+rl.Vector3{0, 0.18, 0}, p, tactical_feedback_spell_color(cue.event.card_definition), 8, 0.63, 1.8)
		case .Explosion, .Room_Hazard_Triggered:
			draw_tactical_sparks(center+rl.Vector3{0, 0.1, 0}, p, {244, 157, 104, 255}, 12, 0.78, 2.2)
		case .Heal:
			draw_tactical_sparks(center, p, {128, 220, 190, 255}, 5, 0.27)
		case .Defeat:
			// The Pinball's foe falls in its ball's burst (pinball.odin).
			if !tactical_pinball_holds(renderer, cue.event.target) { draw_tactical_sparks(center, p, {149, 165, 189, 255}, 6, 0.34) }
		case .Explosive_Armed, .Trap_Triggered:
			draw_tactical_sparks(center, p, {227, 174, 105, 255}, 4, 0.26)
		case:
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

@(private = "file")
draw_tactical_status_rune :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) {
	if !actor.visible || actor.opacity <= 0 { return }
	cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
	if !tactical_render_visible(renderer, cell) { return }
	if index, shielded := game.status_index(&actor.statuses, .Shield); shielded && actor.statuses.items[index].potency > 0 {
		draw_tactical_rune({actor.position.x+0.5, 0.057, actor.position.y+0.5}, 0.34, 0,
			color_with_opacity(TACTICAL_FEEDBACK_BLUE, 0.42*actor.opacity))
	}
}

// Called after actor annotations: compact feedback shares their collision
// allocator and viewport instead of painting floating text across the hearts.
@(private)
draw_tactical_feedback_overlay :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	if cue.kind == .Loot || cue.kind == .Loot_Dropped { return false }
	if cue.kind == .Card_Played || cue.kind == .Refocus {
		label: cstring = "RICONCENTRAZIONE"
		if cue.kind == .Card_Played {
			definition, found := game.card_definition_by_id(cue.event.card_definition)
			if !found { return true }
			label = fmt.ctprintf("%s", definition.name)
			if game.event_is_critical(cue.event) { label = fmt.ctprintf("CRITICO / %s", definition.name) }
		}
		draw_tactical_cue_banner(renderer, cue, label, TACTICAL_FEEDBACK_CRITICAL if game.event_is_critical(cue.event) else TACTICAL_FEEDBACK_BLUE)
		return true
	}
	// CANNA DA PESCA (fishing.odin): its name as it is cast and a caught
	// card's as it comes out, where a played card's shows.
	if label, accent, shown := fishing_cue_banner(cue); shown {
		draw_tactical_cue_banner(renderer, cue, label, accent)
		return true
	}
	badges, count := tactical_feedback_badges(renderer, cue)
	alpha := tactical_feedback_alpha(presentation_cue_progress(cue))
	for badge in badges[:count] { draw_tactical_feedback_badge(renderer, badge, alpha) }
	return true
}

// One word over the board, over its figure (draw_tactical_feedback_overlay,
// and the Lazzo's MOLLATO with its foe's fall: lasso.odin).
@(private)
draw_tactical_feedback_badge :: proc(renderer: ^Renderer, badge: Tactical_Feedback_Badge, alpha: f32) {
	center := tactical_feedback_position(renderer, badge.over, badge.fallback)
	anchor := tactical_project(renderer, {center.x, center.z}, badge.height if badge.height > 0 else TACTICAL_FEEDBACK_BADGE_HEIGHT)
	// Behind the player's eyes nothing is said of what the eye does not face.
	if first_person_amount(renderer) > 0 && !first_person_on_canvas(renderer, anchor) { return }
	width := gothic_text_width(renderer, badge.label, 12)+12
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, 19}, tactical_world_bounds(renderer))
	if !placed { return }
	color := badge.color
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
	gothic_text(renderer, badge.label, bounds.x+6, bounds.y+3, 12, color_with_opacity(color, alpha))
}

// A cue's name under the board, where a played card's shows: its `label`
// after a "+" in `accent`, fading with the cue.
@(private = "file")
draw_tactical_cue_banner :: proc(renderer: ^Renderer, cue: ^Presentation_Cue, label: cstring, accent: rl.Color) {
	viewport := tactical_world_bounds(renderer)
	width := min(f32(280), gothic_text_width(renderer, label, 13)+35)
	anchor := view.Vec2{viewport.x+viewport.width/2, viewport.y+viewport.height-5}
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, 23}, viewport)
	if !placed { return }
	alpha := tactical_feedback_alpha(presentation_cue_progress(cue))
	rl.DrawRectangleRec(bounds, color_with_opacity({10, 19, 33, 244}, alpha))
	rl.DrawRectangleRec({bounds.x, bounds.y+bounds.height-1, bounds.width, 1}, color_with_opacity(accent, alpha*0.7))
	gothic_text(renderer, "+", bounds.x+7, bounds.y+4, 13, color_with_opacity(accent, alpha))
	gothic_text_fit(renderer, label, {bounds.x+23, bounds.y+4, bounds.width-28, 15}, 13, color_with_opacity(TACTICAL_FEEDBACK_WHITE, alpha))
}

// A word a cue says over the board: over `over`'s figure (or the cell
// `fallback` when it is not on the board), its foot `height` over the floor
// (0: TACTICAL_FEEDBACK_BADGE_HEIGHT, over a card's middle).
Tactical_Feedback_Badge :: struct {
	label: cstring,
	color: rl.Color,
	over: game.Entity_Ref,
	fallback: grid.Position,
	height: f32,
}

TACTICAL_FEEDBACK_BADGE_HEIGHT :: f32(0.9)

// What a cue says over the board (draw_tactical_feedback_overlay), at most
// two words. Over its target, as a rule. A critical the Dado del Destino's
// die made is said by the die as it shows (fate_made_critical), never first by
// the blow it doubles. RIFLESSO's answer says RIFLESSO over the player who gave
// the blow back, as the bolt turns or his riposte starts, once a blow: by its
// wound, or by its guard when the attacker's Shield takes all of it; that
// guard still says PARATA over the attacker.
@(private)
tactical_feedback_badges :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> (badges: [2]Tactical_Feedback_Badge, count: int) {
	event := cue.event
	label: cstring
	color := TACTICAL_FEEDBACK_BLUE
	#partial switch cue.kind {
	case .Damage:
		critical := game.event_is_critical(event) && !fate_made_critical(renderer, cue)
		label = fmt.ctprintf("-%d", event.amount); color = TACTICAL_FEEDBACK_HIT
		if critical { label = fmt.ctprintf("CRITICO -%d", event.amount); color = TACTICAL_FEEDBACK_CRITICAL }
		// A living board shows the amount on a paper token; a critical blow
		// still says so.
		if renderer.tactical.living { label = "CRITICO" if critical else nil }
	case .Move:
		if game.event_is_critical(event) && event.target == game.PLAYER_ENTITY { label = "CRITICO!"; color = TACTICAL_FEEDBACK_CRITICAL }
	case .Damage_Absorbed: label = fmt.ctprintf("PARATA %d", event.amount)
	// The die of a loaded bump and what it did; a living board shows the die
	// itself on its paper token (player_charges.odin).
	case .Fate_Rolled: label, color = fate_outcome_label(event, !renderer.tactical.living)
	case .Heal:
		if renderer.tactical.living { return }
		label = fmt.ctprintf("+%d", event.amount); color = {128, 220, 190, 255}
	case .Status_Applied:
		if event.status == .Stagger { label = "INTERROTTO"; color = {218, 187, 123, 255} }
		else if event.status == .Shield { label = fmt.ctprintf("SCUDO +%d", event.amount) }
	case .Attack_Missed: label = "MANCATO"
	// LAZZO (lasso.odin): a hit over the foe struck, a smash over the swung one.
	// The rope let go says MOLLATO with its foe's fall, which the board starts
	// as it shows what moved the player (draw_lasso_release_badge), never after.
	case .Lasso_Struck:
		color = TACTICAL_FEEDBACK_HIT
		if event.target == game.SYSTEM_ENTITY {
			badges[count] = {label = fmt.ctprintf("SCHIANTO %d", event.amount), color = color, over = event.source, fallback = event.from_position}
			count += 1
			return
		}
		label = fmt.ctprintf("COLPO %d", event.amount)
	// CANNA DA PESCA: the food it caught, over him (a card says so below).
	case .Fish_Caught:
		if event.card_definition == .Fishing_Rod { label = fishing_catch_label(event); color = FISHING_WATER_LIGHT }
	// PINBALL (pinball.odin): the value a foe took, over it; the burst over the
	// ball, clear of its top as it swells, so its flash and its paper show. A
	// solid thing touched says nothing: the ball rings off it.
	case .Pinball_Bumped: label = fmt.ctprintf("COLPO %d", event.amount); color = TACTICAL_FEEDBACK_HIT
	case .Pinball_Burst:
		badges[count] = {label = "POP!", color = PINBALL_STEEL_LIGHT, over = event.target, fallback = event.to_position,
			height = pinball_burst_badge_height()}
		count += 1
		return
	case .Move_Blocked: label = "BLOCCATO"; color = {218, 187, 123, 255}
	case .Explosive_Disarmed: label = "DISINNESCATA"
	case .Gold_Gained: label = fmt.ctprintf("+%d ORO", event.amount); color = {218, 187, 123, 255}
	case .Energy_Gained: label = fmt.ctprintf("+%d ENERGIA", event.amount)
	case:
	}
	if label != nil {
		badges[count] = {label = label, color = color, over = event.target, fallback = event.to_position}
		count += 1
	}
	reflected := game.event_is_reflected(event) &&
		(cue.kind == .Damage || (cue.kind == .Damage_Absorbed && !reflected_blow_wounds(renderer, cue)))
	if reflected {
		badges[count] = {label = "RIFLESSO", color = TACTICAL_FEEDBACK_BLUE, over = event.source, fallback = event.from_position}
		count += 1
	}
	return
}

// Whether the Dado del Destino's die made this blow critical: a Fate_Rolled of
// its command on its target whose face was a critical (game.player_bump).
@(private = "file")
fate_made_critical :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	if cue.batch == 0 || cue.event.source != game.PLAYER_ENTITY { return false }
	matches :: proc(other: ^Presentation_Cue, cue: ^Presentation_Cue) -> bool {
		return other.kind == .Fate_Rolled && other.batch == cue.batch && other.event.target == cue.event.target &&
		       game.Fate_Outcome(other.event.duration) == .Critical
	}
	for offset in 0..<renderer_queued_cue_count(renderer) {
		if other, found := renderer_queued_cue_at(renderer, offset); found && matches(other, cue) { return true }
	}
	return false
}

// Whether the blow RIFLESSO gives back, met by a guard (`cue`, its
// Damage_Absorbed), also wounds: its Damaged in the same command. The wound's
// cue starts with the guard's and lasts at least as long.
@(private = "file")
reflected_blow_wounds :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	matches :: proc(other: ^Presentation_Cue, cue: ^Presentation_Cue) -> bool {
		return other.kind == .Damage && other.batch == cue.batch && game.event_is_reflected(other.event) &&
		       other.event.source == cue.event.source && other.event.target == cue.event.target
	}
	for offset in 0..<renderer_queued_cue_count(renderer) {
		if other, found := renderer_queued_cue_at(renderer, offset); found && matches(other, cue) { return true }
	}
	return false
}
