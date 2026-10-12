package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import view "../view"

// Living cards (the mechanics lab): each character is a drawing animated on a
// still paper card (gfx.LIVING_SHEETS). The card never bends or turns: the
// drawing acts inside it, turns round inside it and is cut by its edge. On a
// move the drawing shoves, runs, stomps or hops, and the card slides to the
// new cell as one block from the moment of that push, along the clip's own
// travel curve. The clips are chosen from the presentation cues like the
// classic flipbook's, and never gate gameplay.

LIVING_TURN_SECONDS :: f64(0.12)
LIVING_FALL_SECONDS :: f64(0.38)
LIVING_FORGET_SECONDS :: f64(1.0)
LIVING_TRIGGER_GAP :: f64(0.12)

Living_Actor :: struct {
	entity: game.Entity_Ref,
	character: gfx.Flipbook_Character,
	used, ghost, facing_left: bool,
	// `action` is the running one-shot (Idle: none); `base` the loop beneath.
	action, base, trigger: gfx.Living_Action,
	started, base_started, trigger_seen, turn_started, seen: f64,
	position: view.Vec2,
	// The card's slide of the move in progress, and that move's cells.
	slide_from, slide_to, move_from, move_to: view.Vec2,
	slide_start: f64,
	slide_ms: f32,
	slide_kind: gfx.Living_Travel,
	sliding, moved: bool,
}

Living_State :: struct {
	actors: [FLIPBOOK_MAX_ACTORS]Living_Actor,
	tokens: [LIVING_MAX_TOKENS]Living_Token,
}

// Turns living cards on or off for this renderer; the drawings load the
// first time they are needed.
set_living_cards :: proc(renderer: ^Renderer, on: bool) {
	if renderer == nil { return }
	renderer.tactical.living = on
}

living_cards_ready :: proc(renderer: ^Renderer) -> bool {
	v := &renderer.tactical
	if !v.living || v.living_assets.failed { return false }
	if !v.living_assets.loaded {
		gfx.create_living_assets(&v.living_assets)
		if v.living_assets.failed { return false }
	}
	if v.living_state == nil { v.living_state = new(Living_State) }
	return true
}

destroy_living_cards :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	living_tokens_free(v.living_state)
	gfx.destroy_living_assets(&v.living_assets)
	if v.living_state != nil { free(v.living_state); v.living_state = nil }
}

// A fresh board starts with fresh drawings.
forget_living_actors :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.living_state == nil { return }
	living_tokens_free(renderer.tactical.living_state)
	renderer.tactical.living_state^ = {}
}

living_slot :: proc(state: ^Living_State, entity: game.Entity_Ref, character: gfx.Flipbook_Character, now: f64) -> ^Living_Actor {
	free_slot: ^Living_Actor
	for &actor in state.actors {
		if actor.used && actor.entity == entity && actor.character == character { return &actor }
		if !actor.used && free_slot == nil { free_slot = &actor }
	}
	if free_slot == nil {
		free_slot = &state.actors[0]
		for &actor in state.actors { if actor.seen < free_slot.seen { free_slot = &actor } }
	}
	// Stagger idle loops so a pack never breathes in unison.
	offset := f64(entity.id%7)*0.37
	free_slot^ = {entity = entity, character = character, used = true, started = now, base_started = now-offset,
		trigger_seen = -1, turn_started = -1, seen = now}
	return free_slot
}

living_find :: proc(renderer: ^Renderer, entity: game.Entity_Ref, character: gfx.Flipbook_Character) -> ^Living_Actor {
	state := renderer.tactical.living_state
	if state == nil { return nil }
	for &actor in state.actors {
		if actor.used && actor.character == character && actor.entity == entity { return &actor }
	}
	return nil
}

living_death_done :: proc(actor: ^Living_Actor, now: f64) -> bool {
	if actor.action != .Death { return false }
	clip := &gfx.LIVING_SHEETS[actor.character].clips[.Death]
	return now-actor.started >= gfx.living_clip_seconds(clip)+LIVING_FALL_SECONDS
}

// 0..1 progress of the card toppling after the death drawings.
living_fall :: proc(actor: ^Living_Actor, now: f64) -> f32 {
	if actor == nil || actor.action != .Death { return 0 }
	clip := &gfx.LIVING_SHEETS[actor.character].clips[.Death]
	t := (now-actor.started-gfx.living_clip_seconds(clip))/LIVING_FALL_SECONDS
	return f32(clamp(t, 0, 1))
}

// The same curves as tools/art/living.py: how the card follows the push.
living_travel_progress :: proc(kind: gfx.Living_Travel, progress: f32) -> f32 {
	u := clamp(progress, 0, 1)
	switch kind {
	case .Shove:
		c := f32(1.2)
		v := u-1
		return 1+v*v*((c+1)*v+c)
	case .Run, .Glide, .Float:
		return 0.5-0.5*math.cos(math.PI*u)
	case .Stomp:
		a := clamp(u*2, 0, 1)
		b := clamp(u*2-1, 0, 1)
		return 0.5*(1-(1-a)*(1-a)*(1-a))+0.5*(1-(1-b)*(1-b)*(1-b))
	case .Hop:
		return u*u*(3-2*u)
	case .Dash:
		c := f32(0.9)
		v := u-1
		return 1+v*v*((c+1)*v+c)
	case .None:
		return 1
	}
	return 1
}

// A hopping or floating card leaves the board for a moment; the others slide.
living_travel_lift :: proc(kind: gfx.Living_Travel, u: f32) -> f32 {
	#partial switch kind {
	case .Hop: return abs(math.sin(u*2*math.PI))*0.1
	case .Float: return math.sin(u*math.PI)*0.06
	case .Glide: return math.sin(u*math.PI)*0.03
	}
	return 0
}

// Where the card stands now: on its cell, or partway through its slide.
living_card_position :: proc(renderer: ^Renderer, entity: game.Entity_Ref, key: Sprite_Key, position: view.Vec2) -> (at: view.Vec2, lift: f32) {
	at = position
	if !renderer.tactical.living || renderer.tactical.living_state == nil { return }
	character, ok := flipbook_character(key)
	if !ok { return }
	actor := living_find(renderer, entity, character)
	if actor == nil || !actor.sliding { return }
	now := renderer.sprite_assets.elapsed
	u := f32((now-actor.slide_start)*1000/f64(max(actor.slide_ms, 1)))
	if u >= 1 { return }
	p := living_travel_progress(actor.slide_kind, u) if u > 0 else 0
	at = {actor.slide_from.x+(actor.slide_to.x-actor.slide_from.x)*p, actor.slide_from.y+(actor.slide_to.y-actor.slide_from.y)*p}
	if u > 0 { lift = living_travel_lift(actor.slide_kind, u) }
	return
}

living_cue_action :: proc(cue: ^Presentation_Cue, entity: game.Entity_Ref) -> (action: gfx.Living_Action, matched: bool) {
	event := &cue.event
	#partial switch cue.kind {
	case .Damage:
		if event.target == entity { return .Hurt, true }
		if event.source == entity { return .Attack, true }
	case .Damage_Absorbed, .Move_Blocked:
		if event.target == entity { return .Block, true }
	case .Attack_Missed:
		if event.target == entity { return .Dodge, true }
		if event.source == entity { return .Attack, true }
	case .Defeat:
		if event.target == entity { return .Death, true }
	case .Card_Played:
		if entity == game.PLAYER_ENTITY { return .Cast, true }
	case .Spell_Launched:
		if event.source == entity { return .Cast, true }
	case .Object_Spawned:
		if event.source == entity && entity != game.PLAYER_ENTITY { return .Cast, true }
	case .Status_Applied:
		if event.source == entity && event.target != entity && entity != game.PLAYER_ENTITY { return .Cast, true }
	case .Loot:
		if entity == game.PLAYER_ENTITY { return .Interact, true }
	}
	return .Idle, false
}

living_face :: proc(actor: ^Living_Actor, sideways: f32, now: f64) {
	if abs(sideways) < 0.2 { return }
	left := sideways < 0
	if left == actor.facing_left { return }
	actor.facing_left = left
	actor.turn_started = now
}

living_camera_forward :: proc(renderer: ^Renderer) -> rl.Vector3 {
	camera := renderer.tactical.camera
	return rl.Vector3Normalize(rl.Vector3{camera.target.x-camera.position.x, 0, camera.target.z-camera.position.z})
}

living_start :: proc(actor: ^Living_Actor, action: gfx.Living_Action, now: f64) {
	resolved := gfx.living_resolve(actor.character, action)
	actor.action, actor.started = resolved, now
}

living_busy :: proc(actor: ^Living_Actor, now: f64) -> bool {
	if actor.action == .Idle { return false }
	if actor.action == .Death { return true }
	clip := &gfx.LIVING_SHEETS[actor.character].clips[actor.action]
	return now-actor.started < gfx.living_clip_seconds(clip)
}

living_past_hit :: proc(actor: ^Living_Actor, now: f64) -> bool {
	clip := &gfx.LIVING_SHEETS[actor.character].clips[actor.action]
	if clip.hit < 0 { return true }
	frame, _ := gfx.living_frame(clip, now-actor.started)
	return frame > clip.hit
}

living_observe :: proc(renderer: ^Renderer, state: ^Living_State, room: ^game.Room, actor: Presentation_Actor,
	character: gfx.Flipbook_Character, now: f64) {
	slot := living_slot(state, actor.entity, character, now)
	// Back on the board alive after its fall: a restart reuses the player's
	// id, and that is a fresh card.
	if slot.action == .Death && actor.health > 0 && living_death_done(slot, now) {
		slot^ = {}
		slot = living_slot(state, actor.entity, character, now)
	}
	slot.seen, slot.ghost, slot.position = now, false, actor.position
	right := flipbook_camera_right(renderer)
	forward := living_camera_forward(renderer)
	snapshot := renderer.tactical.snapshot
	sheet := &gfx.LIVING_SHEETS[character]
	wanted := gfx.Living_Action.Idle
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		event := &cue.event
		if cue.kind == .Move && event.target == actor.entity {
			from, to := presentation_position(event.from_position), presentation_position(event.to_position)
			if slot.moved && slot.move_from == from && slot.move_to == to { continue }
			slot.moved, slot.move_from, slot.move_to = true, from, to
			d := rl.Vector3{to.x-from.x, 0, to.y-from.y}
			h := rl.Vector3DotProduct(d, right)
			f := rl.Vector3DotProduct(d, forward)
			length := math.sqrt(h*h+f*f)
			move := gfx.Living_Action.Move_Side
			pushed := event.source != event.target && event.source != game.SYSTEM_ENTITY
			if pushed { move = .Hurt_Back }
			else if actor.entity == game.PLAYER_ENTITY && abs(event.to_position.x-event.from_position.x)+abs(event.to_position.y-event.from_position.y) >= 2 { move = .Dodge }
			else if length > 0.001 && abs(f) >= 0.38*length { move = .Move_Up if f > 0 else .Move_Down }
			if !pushed { living_face(slot, h, now) }
			if slot.action != .Death {
				living_start(slot, move, now)
				clip := &sheet.clips[slot.action]
				// The card goes from wherever it stands now, at the push.
				here, _ := living_card_position(renderer, actor.entity, flipbook_key(character), from)
				slot.slide_from, slot.slide_to = here, to
				slot.slide_kind = clip.travel if clip.travel != .None && !pushed else .Dash
				slot.slide_start = now+(f64(clip.travel_start)/1000 if clip.travel != .None && !pushed else 0)
				slot.slide_ms = f32(clip.travel_ms) if clip.travel != .None && !pushed else 220
				slot.sliding = true
			}
			continue
		}
		action, matched := living_cue_action(cue, actor.entity)
		if !matched { continue }
		if action == .Attack || action == .Cast {
			if target, ok := presentation_actor_in_view(snapshot, event.target); ok && event.target != actor.entity {
				delta := rl.Vector3{target.position.x-actor.position.x, 0, target.position.y-actor.position.y}
				living_face(slot, rl.Vector3DotProduct(delta, right), now)
			}
		}
		if action == .Hurt {
			// Struck from the side it faces: thrown back; from behind: forward.
			if source, ok := presentation_actor_in_view(snapshot, event.source); ok && event.source != actor.entity {
				delta := rl.Vector3{source.position.x-actor.position.x, 0, source.position.y-actor.position.y}
				side := rl.Vector3DotProduct(delta, right)
				if abs(side) > 0.2 && (side < 0) != slot.facing_left { action = .Hurt_Back }
			}
		}
		if gfx.living_priority(action) > gfx.living_priority(wanted) { wanted = action }
	}
	if wanted != .Idle {
		fresh := wanted != slot.trigger || now-slot.trigger_seen > LIVING_TRIGGER_GAP
		slot.trigger, slot.trigger_seen = wanted, now
		if fresh && slot.action != .Death {
			if !living_busy(slot, now) || gfx.living_priority(wanted) >= gfx.living_priority(slot.action) || living_past_hit(slot, now) {
				living_start(slot, wanted, now)
			}
		}
	}
	// The loop beneath the one-shots: breath, telegraph, daze or a cast held.
	base := gfx.Living_Action.Idle
	statuses := actor.statuses
	if _, staggered := game.status_index(&statuses, .Stagger); staggered { base = .Stunned }
	if room != nil && actor.entity.kind == .Enemy {
		for &enemy in room.enemies {
			if game.enemy_entity(enemy.id) != actor.entity { continue }
			if enemy.intent.kind == .Recover { base = .Stunned }
			else if enemy.intent.windup { base = .Windup }
			break
		}
	}
	if room != nil && actor.entity == game.PLAYER_ENTITY && game.tactical_is_casting(room) { base = .Channel }
	base = gfx.living_resolve(character, base)
	if base != slot.base {
		slot.base = base
		slot.base_started = now
	}
}

// Once per frame, before the board is drawn: read the cues and states.
update_living_actors :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !living_cards_ready(renderer) || v.snapshot == nil { return }
	state := v.living_state
	now := renderer.sprite_assets.elapsed
	snapshot := v.snapshot
	if snapshot.player.visible { living_observe(renderer, state, room, snapshot.player, .Pilgrim, now) }
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		if !actor.visible { continue }
		if character, ok := flipbook_character(sprite_key_for_enemy(actor.archetype)); ok {
			living_observe(renderer, state, room, actor, character, now)
		}
	}
	for &actor in state.actors {
		if !actor.used || actor.seen == now { continue }
		// Gone from the board mid-death: finish the fall as a ghost.
		if actor.action == .Death && !living_death_done(&actor, now) { actor.ghost = true; continue }
		if actor.ghost || now-actor.seen > LIVING_FORGET_SECONDS { actor = {} }
	}
	update_living_tokens(renderer, now)
}

// The drawing to print right now.
living_drawing :: proc(actor: ^Living_Actor, now: f64) -> (action: gfx.Living_Action, frame: i32) {
	sheet := &gfx.LIVING_SHEETS[actor.character]
	if actor.action != .Idle {
		clip := &sheet.clips[actor.action]
		drawing, finished := gfx.living_frame(clip, now-actor.started)
		if !finished || actor.action == .Death { return actor.action, drawing }
	}
	base := gfx.living_resolve(actor.character, actor.base)
	drawing, _ := gfx.living_frame(&sheet.clips[base], now-actor.base_started)
	return base, drawing
}

// Dying drawings keep full opacity, then fade as the card topples.
living_opacity :: proc(renderer: ^Renderer, entity: game.Entity_Ref, key: Sprite_Key, opacity: f32) -> f32 {
	character, ok := flipbook_character(key)
	if !ok { return opacity }
	actor := living_find(renderer, entity, character)
	if actor == nil || actor.action != .Death { return opacity }
	fall := living_fall(actor, renderer.sprite_assets.elapsed)
	return clamp(1-(fall-0.55)/0.45, 0, 1)
}

living_billboard_geometry :: proc(renderer: ^Renderer, character: gfx.Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	feedback: bool, entity: game.Entity_Ref) -> Tactical_Billboard {
	v := &renderer.tactical
	sheet := &gfx.LIVING_SHEETS[character]
	now := renderer.sprite_assets.elapsed
	actor := living_find(renderer, entity, character) if feedback else nil
	action, frame := gfx.Living_Action.Idle, i32(0)
	if actor != nil { action, frame = living_drawing(actor, now) }
	else {
		phase := f64(position.x*0.31+position.y*0.17)
		frame, _ = gfx.living_frame(&sheet.clips[.Idle], now+phase)
	}
	clip := &sheet.clips[action]
	cell := rl.Vector2{f32(sheet.cell.x), f32(sheet.cell.y)}
	result := Tactical_Billboard{
		texture = v.living_assets.frames[character],
		source = gfx.living_source(sheet, clip, frame),
		key = key,
		flipbook = true,
		living = true,
		card = v.living_assets.papers[character],
		card_margin = f32(sheet.card_margin),
		card_a = {0, 0, 1, 1},
		card_b = {0, 0, 1, 1},
		card_morph = 1,
	}
	scale := sheet.world_height/max(sheet.rest_height, 1)
	// The drawing turns round inside the card: the print narrows, flips and
	// widens again while the paper stays as it is.
	width := f32(1)
	if actor != nil {
		result.mirror = actor.facing_left
		turn := (now-actor.turn_started)/LIVING_TURN_SECONDS
		if actor.turn_started >= 0 && turn < 1 {
			width = max(f32(0.04), abs(f32(math.cos(turn*math.PI))))
			if turn < 0.5 { result.mirror = !result.mirror }
		}
	}
	at, travel_lift := living_card_position(renderer, entity, key, position)
	up := rl.Vector3{0, 1, 0}
	right := flipbook_camera_right(renderer)
	below := cell.y-sheet.feet.y
	lift := (sheet.ground+gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*scale+0.03
	if v.outline_mode == .Hologram { lift = 0; result.card = {} }
	base := rl.Vector3{at.x+0.5, 0.02+lift+travel_lift, at.y+0.5}
	bl := base-right*(sheet.feet.x*scale)-up*(below*scale)
	span := right*(cell.x*scale)
	top := up*(cell.y*scale)
	m := f32(sheet.card_margin)*scale
	result.card_points = {bl+top+(-right+up)*m, bl+(-right-up)*m, bl+span+(right-up)*m, bl+span+top+(right+up)*m}
	// The print: the same quad, narrowed about the feet while turning.
	center := base-right*((sheet.feet.x-cell.x*0.5)*scale)
	half := right*(cell.x*0.5*scale*width)
	pbl := center-half-up*(below*scale)
	result.points = {pbl+top, pbl, pbl+half*2, pbl+half*2+top}
	if fall := living_fall(actor, now); fall > 0 {
		// The whole card topples backwards around its bottom edge.
		angle := fall*fall*1.4
		away := rl.Vector3Normalize(rl.Vector3{v.camera.target.x-v.camera.position.x, 0, v.camera.target.z-v.camera.position.z})
		floor := f32(0.02)
		for &point in result.points {
			h := point.y-floor
			point = {point.x, floor+h*math.cos(angle), point.z}+away*(h*math.sin(angle))
		}
		for &point in result.card_points {
			h := point.y-floor
			point = {point.x, floor+h*math.cos(angle), point.z}+away*(h*math.sin(angle))
		}
	}
	return result
}

living_card_hit :: proc(renderer: ^Renderer, quad: Tactical_Billboard, ray: rl.Ray) -> (distance: f32, hit: bool) {
	points := quad.card_points
	collision := rl.GetRayCollisionQuad(ray, points[0], points[1], points[2], points[3])
	if !collision.hit { return }
	character, ok := flipbook_character(quad.key)
	if !ok { return }
	field := renderer.tactical.living_assets.fields[character]
	width, height := int(quad.card.width), int(quad.card.height)
	if len(field) < width*height || width <= 0 { return collision.distance, true }
	u := points[3]-points[0]
	w := points[1]-points[0]
	delta := collision.point-points[0]
	fx := clamp(rl.Vector3DotProduct(delta, u)/rl.Vector3DotProduct(u, u), 0, 0.9999)
	fy := clamp(rl.Vector3DotProduct(delta, w)/rl.Vector3DotProduct(w, w), 0, 0.9999)
	x := clamp(int(fx*f32(width)), 0, width-1)
	y := clamp(int(fy*f32(height)), 0, height-1)
	if f32(field[y*width+x]) > (gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*gfx.FLIPBOOK_PAPER_SCALE { return }
	return collision.distance, true
}
