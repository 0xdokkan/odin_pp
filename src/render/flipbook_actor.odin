package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import view "../engine/view"

// Board characters are paper standees: a pixel-art print that plays
// flipbook drawings, on a paper card cut a little wider than the drawing.
// Each drawing carries a distance field to its silhouette, and when the print
// turns a page the card's cut morphs from the old drawing to the new one: it
// reaches out where an arm extends and draws back as it returns. The card is
// also what moves on the board (hop, shake, turn, topple). Clips are chosen
// from the presentation cues but never gate gameplay: a clip that outlives
// its cue finishes on its own clock while input is already live again.

FLIPBOOK_MAX_ACTORS :: game.MAX_ENEMIES_PER_ROOM+9
// A cue still active within this gap is the same trigger, not a new one.
FLIPBOOK_TRIGGER_GAP :: f64(0.12)
// Keeps a stride going across the short pause between two grid steps.
FLIPBOOK_WALK_GRACE :: f64(0.1)
FLIPBOOK_TURN_SECONDS :: f64(0.18)
FLIPBOOK_FALL_SECONDS :: f64(0.38)
FLIPBOOK_FORGET_SECONDS :: f64(1.0)
Flipbook_Actor :: struct {
	entity: game.Entity_Ref,
	character: gfx.Flipbook_Character,
	used, ghost, facing_left: bool,
	// `action` is the running one-shot (Idle: none); `base` the loop beneath.
	action, base, trigger: gfx.Flipbook_Action,
	first_frame: i32,
	started, base_started, trigger_seen, walk_until, turn_started, seen: f64,
	position: view.Vec2,
	// The drawing on the card now and the one it is morphing away from.
	shown, previous: [2]i32,
	shown_since: f64,
}

Flipbook_State :: struct {
	actors: [FLIPBOOK_MAX_ACTORS]Flipbook_Actor,
}

@(private)
flipbook_character :: proc(key: Sprite_Key) -> (gfx.Flipbook_Character, bool) {
	#partial switch key {
	case .Player, .Player_Cast, .Player_Hit: return .Pilgrim, true
	case .Chaser: return .Ghoul, true
	case .Archer: return .Archer, true
	case .Brute: return .Brute, true
	case .Bomber: return .Bomber, true
	case .Custodian: return .Bishop, true
	case .Demolitionist: return .Archmage, true
	}
	return .Pilgrim, false
}

@(private)
flipbook_key :: proc(character: gfx.Flipbook_Character) -> Sprite_Key {
	switch character {
	case .Pilgrim: return .Player
	case .Ghoul: return .Chaser
	case .Archer: return .Archer
	case .Brute: return .Brute
	case .Bomber: return .Bomber
	case .Bishop: return .Custodian
	case .Archmage: return .Demolitionist
	}
	return .Player
}

@(private = "file")
flipbook_one_shot_seconds :: proc(actor: ^Flipbook_Actor) -> f64 {
	return gfx.flipbook_clip_seconds(&gfx.FLIPBOOK_SHEETS[actor.character].clips[actor.action], actor.first_frame)
}

@(private = "file")
flipbook_one_shot_running :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	if actor.action == .Idle { return false }
	if actor.action == .Death { return true }
	return now-actor.started < flipbook_one_shot_seconds(actor)
}

// Past the impact drawing, a one-shot is only follow-through and may yield.
@(private = "file")
flipbook_past_hit :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	clip := &gfx.FLIPBOOK_SHEETS[actor.character].clips[actor.action]
	if clip.hit < 0 { return true }
	frame, _ := gfx.flipbook_frame(clip, now-actor.started, actor.first_frame)
	return frame > clip.hit
}

// 0..1 progress of the card toppling after the death drawings.
@(private = "file")
flipbook_fall :: proc(actor: ^Flipbook_Actor, now: f64) -> f32 {
	if actor == nil || actor.action != .Death { return 0 }
	t := (now-actor.started-flipbook_one_shot_seconds(actor))/FLIPBOOK_FALL_SECONDS
	return f32(clamp(t, 0, 1))
}

@(private = "file")
flipbook_death_done :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	return actor.action == .Death && now-actor.started >= flipbook_one_shot_seconds(actor)+FLIPBOOK_FALL_SECONDS
}

// The drawing to print right now.
@(private)
flipbook_drawing :: proc(actor: ^Flipbook_Actor, now: f64) -> (action: gfx.Flipbook_Action, frame: i32) {
	sheet := &gfx.FLIPBOOK_SHEETS[actor.character]
	if actor.action != .Idle {
		clip := &sheet.clips[actor.action]
		drawing, finished := gfx.flipbook_frame(clip, now-actor.started, actor.first_frame)
		if !finished || actor.action == .Death { return actor.action, drawing }
	}
	base := gfx.flipbook_resolve(actor.character, actor.base)
	drawing, _ := gfx.flipbook_frame(&sheet.clips[base], now-actor.base_started)
	return base, drawing
}

@(private)
flipbook_slot :: proc(state: ^Flipbook_State, entity: game.Entity_Ref, character: gfx.Flipbook_Character, now: f64) -> ^Flipbook_Actor {
	free_slot: ^Flipbook_Actor
	for &actor in state.actors {
		if actor.used && actor.entity == entity && actor.character == character { return &actor }
		if !actor.used && free_slot == nil { free_slot = &actor }
	}
	if free_slot == nil {
		free_slot = &state.actors[0]
		for &actor in state.actors { if actor.seen < free_slot.seen { free_slot = &actor } }
	}
	// Stagger idle breathing so a pack never inhales in unison.
	offset := f64(entity.id%7)*0.37
	free_slot^ = {entity = entity, character = character, used = true, started = now,
		base_started = now-offset, trigger_seen = -1, walk_until = -1, turn_started = -1, seen = now,
		shown = {-1, -1}, previous = {-1, -1}}
	return free_slot
}

@(private)
flipbook_find :: proc(renderer: ^Renderer, entity: game.Entity_Ref, character: gfx.Flipbook_Character, position: view.Vec2) -> ^Flipbook_Actor {
	state := renderer.tactical.flipbook_state
	if state == nil { return nil }
	for &actor in state.actors {
		if !actor.used || actor.character != character { continue }
		if entity != game.SYSTEM_ENTITY {
			if actor.entity == entity { return &actor }
		} else if actor.position == position { return &actor }
	}
	return nil
}

@(private)
flipbook_camera_right :: proc(renderer: ^Renderer) -> rl.Vector3 {
	camera := renderer.tactical.camera
	return rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, camera.position-camera.target))
}

// Screen-space facing: prints are drawn facing right and mirror to face left.
// A change of side turns the card over like a real standee.
@(private = "file")
flipbook_face :: proc(actor: ^Flipbook_Actor, sideways: f32, now: f64) {
	if abs(sideways) < 0.2 { return }
	left := sideways < 0
	if left == actor.facing_left { return }
	actor.facing_left = left
	actor.turn_started = now
}

// Which clip a cue asks of this actor. `from_hit` starts at the impact
// drawing: the cue *is* the impact, its anticipation is already past.
@(private = "file")
flipbook_cue_action :: proc(cue: ^Presentation_Cue, entity: game.Entity_Ref) -> (action: gfx.Flipbook_Action, matched, from_hit: bool) {
	event := &cue.event
	#partial switch cue.kind {
	case .Move:
		// A teleport is no walk: the card is simply on its landing.
		if event.target == entity && !game.event_is_teleport(event^) { return .Walk, true, false }
	case .Damage:
		if event.target == entity { return .Hurt, true, false }
		if event.source == entity { return .Attack, true, true }
	case .Damage_Absorbed, .Move_Blocked:
		if event.target == entity { return .Block, true, false }
	case .Attack_Missed:
		if event.target == entity { return .Dodge, true, false }
		if event.source == entity { return .Attack, true, true }
	case .Defeat:
		if event.target == entity { return .Death, true, false }
	case .Card_Played:
		if entity == game.PLAYER_ENTITY { return .Cast, true, false }
	case .Spell_Launched:
		if event.source == entity { return .Cast, true, true }
	case .Object_Spawned:
		if event.source == entity && entity != game.PLAYER_ENTITY { return .Cast, true, true }
	case .Status_Applied:
		if event.source == entity && event.target != entity && entity != game.PLAYER_ENTITY { return .Cast, true, true }
	case .Loot:
		if entity == game.PLAYER_ENTITY { return .Interact, true, false }
	}
	return .Idle, false, false
}

@(private)
flipbook_observe :: proc(renderer: ^Renderer, state: ^Flipbook_State, room: ^game.Room, actor: Presentation_Actor,
	character: gfx.Flipbook_Character, now: f64, right: rl.Vector3) {
	slot := flipbook_slot(state, actor.entity, character, now)
	// Back on the board alive after its fall: a restart reuses the player's
	// id, and that is a fresh card, not the fallen one.
	if slot.action == .Death && actor.health > 0 && flipbook_death_done(slot, now) {
		slot^ = {}
		slot = flipbook_slot(state, actor.entity, character, now)
	}
	slot.seen, slot.ghost, slot.position = now, false, actor.position
	wanted, from_hit := gfx.Flipbook_Action.Idle, false
	walking := false
	snapshot := renderer.tactical.snapshot
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		action, matched, at_hit := flipbook_cue_action(cue, actor.entity)
		if !matched { continue }
		if action == .Walk {
			from, to := cue.event.from_position, cue.event.to_position
			flipbook_face(slot, rl.Vector3DotProduct({f32(to.x-from.x), 0, f32(to.y-from.y)}, right), now)
			// The player's dash covers two cells in one step: a dodge, not a stride.
			if actor.entity == game.PLAYER_ENTITY && abs(to.x-from.x)+abs(to.y-from.y) >= 2 { action = .Dodge }
			else { walking = true; continue }
		}
		if action == .Attack || action == .Cast {
			if target, ok := presentation_actor_in_view(snapshot, cue.event.target); ok && cue.event.target != actor.entity {
				delta := view.Vec2{target.position.x-actor.position.x, target.position.y-actor.position.y}
				flipbook_face(slot, rl.Vector3DotProduct({delta.x, 0, delta.y}, right), now)
			}
		}
		if gfx.flipbook_priority(action) > gfx.flipbook_priority(wanted) { wanted, from_hit = action, at_hit }
	}
	if walking {
		if now > slot.walk_until && slot.base != .Walk { slot.base_started = now }
		slot.walk_until = now+FLIPBOOK_WALK_GRACE
	}
	if wanted != .Idle {
		fresh := wanted != slot.trigger || now-slot.trigger_seen > FLIPBOOK_TRIGGER_GAP
		slot.trigger, slot.trigger_seen = wanted, now
		resolved := gfx.flipbook_resolve(character, wanted)
		clip := &gfx.FLIPBOOK_SHEETS[character].clips[resolved]
		if fresh && !clip.loop && slot.action != .Death {
			if !flipbook_one_shot_running(slot, now) || gfx.flipbook_priority(resolved) >= gfx.flipbook_priority(slot.action) ||
			   flipbook_past_hit(slot, now) {
				slot.action, slot.started = resolved, now
				slot.first_frame = max(clip.hit, 0) if from_hit else 0
			}
		}
	}
	// The loop beneath the one-shots: stride, telegraph, daze or breath.
	base := gfx.Flipbook_Action.Idle
	if now < slot.walk_until { base = .Walk }
	else {
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
	}
	if base != slot.base {
		if base != .Walk { slot.base_started = now }
		slot.base = base
	}
}

// A fresh board starts with fresh standees.
@(private)
forget_flipbook_actors :: proc(renderer: ^Renderer) {
	if renderer != nil && renderer.tactical.flipbook_state != nil { renderer.tactical.flipbook_state^ = {} }
	forget_living_actors(renderer)
}

// Once per frame, before the board is drawn: read the cues and states. Map
// and ring views only read the result.
@(private)
update_flipbook_actors :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	state := v.flipbook_state
	if state == nil || !v.flipbook.loaded || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	right := flipbook_camera_right(renderer)
	snapshot := v.snapshot
	if snapshot.player.visible { flipbook_observe(renderer, state, room, snapshot.player, .Pilgrim, now, right) }
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		// The Pinball's ball is no standee (pinball.odin).
		if !actor.visible || tactical_pinball_holds(renderer, actor.entity) { continue }
		if character, ok := flipbook_character(sprite_key_for_enemy(actor.archetype)); ok {
			flipbook_observe(renderer, state, room, actor, character, now, right)
		}
	}
	for &actor in state.actors {
		if !actor.used || actor.seen == now { continue }
		// Gone from the board mid-death: finish the fall as a ghost.
		if actor.action == .Death && !flipbook_death_done(&actor, now) { actor.ghost = true; continue }
		if actor.ghost || now-actor.seen > FLIPBOOK_FORGET_SECONDS { actor = {} }
	}
}

// Dying standees keep full opacity through their drawings, then fade as the
// card topples, instead of following the short defeat cue's fade.
@(private)
flipbook_opacity :: proc(renderer: ^Renderer, entity: game.Entity_Ref, key: Sprite_Key, position: view.Vec2, opacity: f32) -> f32 {
	character, ok := flipbook_character(key)
	if !ok || !renderer.tactical.flipbook.loaded { return opacity }
	actor := flipbook_find(renderer, entity, character, position)
	if actor == nil || actor.action != .Death { return opacity }
	fall := flipbook_fall(actor, renderer.sprite_assets.elapsed)
	return clamp(1-(fall-0.55)/0.45, 0, 1)
}

@(private)
flipbook_billboard_geometry :: proc(renderer: ^Renderer, character: gfx.Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	feedback: bool, entity: game.Entity_Ref) -> Tactical_Billboard {
	v := &renderer.tactical
	sheet := &gfx.FLIPBOOK_SHEETS[character]
	now := renderer.sprite_assets.elapsed
	actor := flipbook_find(renderer, entity, character, position) if feedback else nil
	action, frame := gfx.Flipbook_Action.Idle, i32(0)
	if actor != nil { action, frame = flipbook_drawing(actor, now) }
	else {
		phase := f64(position.x*0.31+position.y*0.17)
		frame, _ = gfx.flipbook_frame(&sheet.clips[.Idle], now+phase)
	}
	clip := &sheet.clips[action]
	cell := rl.Vector2{f32(sheet.cell.x), f32(sheet.cell.y)}
	// The paper follows the print to each new drawing over a short morph.
	shown := [2]i32{clip.row, frame}
	previous, morph := shown, f32(1)
	if actor != nil {
		if actor.shown.x < 0 { actor.previous, actor.shown, actor.shown_since = shown, shown, now-gfx.FLIPBOOK_MORPH_SECONDS }
		else if actor.shown != shown { actor.previous, actor.shown, actor.shown_since = actor.shown, shown, now }
		previous = actor.previous
		morph = f32(clamp((now-actor.shown_since)/gfx.FLIPBOOK_MORPH_SECONDS, 0, 1))
	}
	papers := v.flipbook.papers[character]
	paper := rl.Vector2{f32(sheet.paper_cell.x)/f32(max(papers.width, 1)), f32(sheet.paper_cell.y)/f32(max(papers.height, 1))}
	result := Tactical_Billboard{
		texture = v.flipbook.frames[character],
		source = {f32(frame)*cell.x, f32(clip.row)*cell.y, cell.x, cell.y},
		key = key,
		flipbook = true,
		card = papers,
		card_margin = f32(sheet.card_margin),
		card_a = {f32(previous.y)*paper.x, f32(previous.x)*paper.y, paper.x, paper.y},
		card_b = {f32(shown.y)*paper.x, f32(shown.x)*paper.y, paper.x, paper.y},
		card_morph = morph,
	}
	pose := Tactical_Feedback_Pose{scale_y = 1, tint = rl.WHITE}
	if feedback { pose = tactical_feedback_pose(renderer, key, position) }
	scale := sheet.world_height/max(sheet.rest_height, 1)
	width := f32(1)
	if actor != nil {
		result.mirror = actor.facing_left
		turn := (now-actor.turn_started)/FLIPBOOK_TURN_SECONDS
		if actor.turn_started >= 0 && turn < 1 {
			// Edge-on at the midpoint; the old side shows until then.
			width = max(f32(0.04), abs(f32(math.cos(turn*math.PI))))
			if turn < 0.5 { result.mirror = !result.mirror }
		}
	}
	up := rl.Vector3{0, 1, 0}
	right := flipbook_camera_right(renderer)
	feet_x := cell.x-sheet.feet.x if result.mirror else sheet.feet.x
	below := cell.y-sheet.feet.y
	// The paper under the feet stands in the base's slot; map markers drop
	// the card and stand on their feet.
	lift := (gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*scale+0.03
	if v.outline_mode == .Hologram { lift = 0; result.card = {} }
	base := rl.Vector3{position.x+0.5, 0.02+lift+pose.lift, position.y+0.5}
	// The player's card in its shadow, as on the living board (shadow_step.odin);
	// the Lazzo's foe up on its rope (lasso.odin).
	base.y -= tactical_shadow_depth(renderer, entity)*sheet.world_height
	base.y += tactical_lasso_lift(renderer, entity)
	sy := scale*pose.scale_y
	bl := base-right*(feet_x*scale*width)-up*(below*sy)
	span := right*(cell.x*scale*width)
	top := up*(cell.y*sy)
	lean := right*pose.lean
	result.points = {bl+top+lean, bl, bl+span, bl+span+top+lean}
	if fall := flipbook_fall(actor, now); fall > 0 {
		topple_card_points(&result.points, v.camera, fall)
	}
	return result
}

// The card quad grows the print quad by the paper margin on every side, in
// the quad's own axes, so ring and lean transforms of the print carry it.
@(private = "file")
flipbook_card_points :: proc(quad: Tactical_Billboard) -> [4]rl.Vector3 {
	return gfx.paper_quad_points(quad.points, {quad.source.width, quad.source.height}, quad.card_margin)
}

@(private)
flipbook_card_hit :: proc(renderer: ^Renderer, quad: Tactical_Billboard, ray: rl.Ray) -> (distance: f32, hit: bool) {
	points := flipbook_card_points(quad)
	collision := rl.GetRayCollisionQuad(ray, points[0], points[1], points[2], points[3])
	if !collision.hit { return }
	character, ok := flipbook_character(quad.key)
	if !ok { return }
	field := renderer.tactical.flipbook.fields[character]
	width, height := int(quad.card.width), int(quad.card.height)
	if len(field) < width*height || width <= 0 { return collision.distance, true }
	uv := card_hit_uv(points, collision.point)
	if quad.mirror { uv.x = 0.9999-uv.x }
	// Picking follows the paper of the drawing on the card now.
	x := clamp(int((quad.card_b.x+uv.x*quad.card_b.width)*f32(width)), 0, width-1)
	y := clamp(int((quad.card_b.y+uv.y*quad.card_b.height)*f32(height)), 0, height-1)
	if f32(field[y*width+x]) > (gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*gfx.FLIPBOOK_PAPER_SCALE { return }
	return collision.distance, true
}

@(private)
draw_flipbook_card :: proc(renderer: ^Renderer, quad: Tactical_Billboard, uv: [4]rl.Vector2, opacity: f32, tint: rl.Color = rl.WHITE) {
	assets := &renderer.tactical.flipbook
	if assets.paper_shader.id == 0 { return }
	points := flipbook_card_points(quad)
	cell := rl.Vector2{quad.source.width+quad.card_margin*2, quad.source.height+quad.card_margin*2}
	edge := rl.Vector2{-1 if quad.mirror else 1, 1}
	sheet := gfx.FLIPBOOK_SHEET_COLOR
	uv := uv
	if quad.living {
		// The still card: never mirrored, on its whiter drawing paper, its cut
		// edge as thick on the board as the classic card's.
		points = quad.card_points
		uv = {{0, 0}, {0, 1}, {1, 1}, {1, 0}}
		edge = {1, 1}
		sheet = gfx.LIVING_SHEET_COLOR
		cell *= gfx.LIVING_PRINT_SCALE
	}
	gfx.begin_paper_material(assets, {frames = {quad.card_a, quad.card_b, quad.card_morph}, cell = cell, edge = edge, sheet = sheet})
	gfx.draw_texture_quad(quad.card.id, points, uv, {tint.r, tint.g, tint.b, u8(clamp(opacity, f32(0), f32(1))*255)})
	rl.EndShaderMode()
}

// The standee's base: a low iron plinth with a slot that grips the card,
// turned with the card toward the camera and hopping with it. A thin strip
// of the side's colour (ivory pilgrim, crimson foe) runs along its front.
@(private)
draw_flipbook_stand :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, accent: rl.Color,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) {
	character, ok := flipbook_character(key)
	if !ok { return }
	sheet := &gfx.FLIPBOOK_SHEETS[character]
	lift := tactical_feedback_pose(renderer, key, position).lift
	at := position
	if renderer.tactical.living && renderer.tactical.living_assets.loaded {
		// A living card is a rigid block: the base slides and hops with it.
		at, lift = living_card_position(renderer, entity, key, position)
	}
	right := flipbook_camera_right(renderer)
	angle := math.atan2(-right.z, right.x)*math.DEG_PER_RAD
	size := clamp(sheet.world_height/1.35, 0.85, 1.2)
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.Translatef(at.x+0.5, lift, at.y+0.5)
	rlgl.Rotatef(angle, 0, 1, 0)
	rlgl.Scalef(size, 1, size)
	rl.DrawCube({0, 0.03, 0}, 0.58, 0.05, 0.24, {20, 24, 34, 255})
	rl.DrawCubeWires({0, 0.03, 0}, 0.58, 0.05, 0.24, {58, 66, 86, 255})
	rl.DrawCube({0, 0.062, 0}, 0.5, 0.016, 0.18, {44, 50, 66, 255})
	rl.DrawCube({0, 0.082, 0}, 0.24, 0.03, 0.075, {30, 35, 48, 255})
	rl.DrawCube({0, 0.03, 0.121}, 0.5, 0.014, 0.004, accent)
}
