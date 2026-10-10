package render

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import view "../view"

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
// How long the paper takes to follow the print to a new drawing.
FLIPBOOK_MORPH_SECONDS :: f64(0.09)

// Samples two drawings' fields and blends them, then cuts paper, the
// visible card edge (offset down-right) and the ink line from the result.
FLIPBOOK_PAPER_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 frameA;
uniform vec4 frameB;
uniform float morph;
uniform vec2 cell;
uniform vec2 edgeDir;
out vec4 finalColor;
float field(vec4 r, vec2 uv) {
    vec2 p = r.xy + clamp(uv, vec2(0.002), vec2(0.998))*r.zw;
    return texture(texture0, p).r*255.0/PAPER_SCALE;
}
float dist(vec2 uv) { return mix(field(frameA, uv), field(frameB, uv), morph); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)))*43758.5453); }
void main() {
    vec2 uv = fragTexCoord;
    float d = dist(uv);
    float de = dist(uv - edgeDir*EDGE_PX/cell);
    float aa = max(fwidth(d), 0.03)*0.8;
    float paper = 1.0 - smoothstep(PAPER_PX - aa, PAPER_PX + aa, d);
    float body = max(paper, 1.0 - smoothstep(PAPER_PX - aa, PAPER_PX + aa, de));
    float ink = 1.0 - smoothstep(INK_PX - aa, INK_PX + aa, min(d, de));
    if (ink < 0.01) discard;
    vec2 px = floor(uv*cell*4.0);
    float grain = (hash(px) - 0.5)*0.026 + (hash(floor(uv*cell*0.6)) - 0.5)*0.022;
    vec3 sheet = vec3(0.894, 0.867, 0.788) + grain;
    vec3 col = mix(vec3(0.051, 0.078, 0.118), vec3(0.643, 0.596, 0.514), body);
    col = mix(col, sheet, paper);
    finalColor = vec4(col*fragColor.rgb, ink*fragColor.a);
}`

Flipbook_Assets :: struct {
	frames, papers: [Flipbook_Character]rl.Texture2D,
	// CPU copies of the fields, for picking on the paper itself.
	fields: [Flipbook_Character][]u8,
	paper_shader: rl.Shader,
	frame_a_location, frame_b_location, morph_location, cell_location, edge_location: c.int,
	loaded: bool,
}

Flipbook_Actor :: struct {
	entity: game.Entity_Ref,
	character: Flipbook_Character,
	used, ghost, facing_left: bool,
	// `action` is the running one-shot (Idle: none); `base` the loop beneath.
	action, base, trigger: Flipbook_Action,
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

create_flipbook_assets :: proc(assets: ^Flipbook_Assets) {
	for character in Flipbook_Character {
		for bytes, kind in ([2][]u8{FLIPBOOK_FRAMES_PNG[character], FLIPBOOK_PAPER_PNG[character]}) {
			img := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
			if img.data == nil { continue }
			texture := rl.LoadTextureFromImage(img)
			if kind == 0 {
				// The print is pixel art: never filtered.
				rl.SetTextureFilter(texture, .POINT)
				assets.frames[character] = texture
			} else {
				// Distance fields interpolate: bilinear, no mipmaps (cells abut).
				rl.SetTextureFilter(texture, .BILINEAR)
				rl.SetTextureWrap(texture, .CLAMP)
				assets.papers[character] = texture
				colors := rl.LoadImageColors(img)
				field := make([]u8, int(img.width)*int(img.height))
				for &value, index in field { value = colors[index].r }
				rl.UnloadImageColors(colors)
				assets.fields[character] = field
			}
			rl.UnloadImage(img)
		}
	}
	source := flipbook_paper_source()
	assets.paper_shader = rl.LoadShaderFromMemory(nil, source)
	if assets.paper_shader.id != 0 {
		assets.frame_a_location = rl.GetShaderLocation(assets.paper_shader, "frameA")
		assets.frame_b_location = rl.GetShaderLocation(assets.paper_shader, "frameB")
		assets.morph_location = rl.GetShaderLocation(assets.paper_shader, "morph")
		assets.cell_location = rl.GetShaderLocation(assets.paper_shader, "cell")
		assets.edge_location = rl.GetShaderLocation(assets.paper_shader, "edgeDir")
	}
	assets.loaded = assets.paper_shader.id != 0
	for character in Flipbook_Character {
		if assets.frames[character].id == 0 || assets.papers[character].id == 0 { assets.loaded = false }
	}
}

destroy_flipbook_assets :: proc(assets: ^Flipbook_Assets) {
	for character in Flipbook_Character {
		if assets.frames[character].id != 0 { rl.UnloadTexture(assets.frames[character]) }
		if assets.papers[character].id != 0 { rl.UnloadTexture(assets.papers[character]) }
		delete(assets.fields[character])
	}
	if assets.paper_shader.id != 0 { rl.UnloadShader(assets.paper_shader) }
	assets^ = {}
}

flipbook_character :: proc(key: Sprite_Key) -> (Flipbook_Character, bool) {
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

flipbook_key :: proc(character: Flipbook_Character) -> Sprite_Key {
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

// A character without a dedicated clip borrows the closest one it has.
flipbook_resolve :: proc(character: Flipbook_Character, action: Flipbook_Action) -> Flipbook_Action {
	clips := &FLIPBOOK_SHEETS[character].clips
	current := action
	for _ in 0..<4 {
		if clips[current].count > 0 { return current }
		switch current {
		case .Cast: current = .Attack
		case .Dodge: current = .Walk
		case .Block: current = .Hurt
		case .Idle, .Walk, .Attack, .Windup, .Hurt, .Stunned, .Interact, .Death: current = .Idle
		}
	}
	return .Idle
}

flipbook_priority :: proc(action: Flipbook_Action) -> int {
	switch action {
	case .Death: return 6
	case .Hurt: return 5
	case .Cast, .Attack: return 4
	case .Block, .Dodge: return 3
	case .Interact: return 2
	case .Walk, .Windup, .Stunned: return 1
	case .Idle: return 0
	}
	return 0
}

flipbook_clip_seconds :: proc(clip: ^Flipbook_Clip, first: i32 = 0) -> f64 {
	total: f64
	for index in max(first, 0)..<clip.count { total += f64(clip.durations[index]) }
	return total/1000
}

// The drawing shown `elapsed` seconds into a clip that began at drawing
// `first`. A finished one-shot holds its last drawing.
flipbook_frame :: proc(clip: ^Flipbook_Clip, elapsed: f64, first: i32 = 0) -> (frame: i32, finished: bool) {
	if clip.count <= 0 { return 0, true }
	t := max(elapsed, 0)*1000
	if clip.loop {
		cycle := flipbook_clip_seconds(clip)*1000
		if cycle <= 0 { return 0, false }
		t = math.mod(t, cycle)
		for index in 0..<clip.count {
			duration := f64(clip.durations[index])
			if t < duration { return index, false }
			t -= duration
		}
		return clip.count-1, false
	}
	for index in clamp(first, 0, clip.count-1)..<clip.count {
		duration := f64(clip.durations[index])
		if t < duration { return index, false }
		t -= duration
	}
	return clip.count-1, true
}

flipbook_one_shot_seconds :: proc(actor: ^Flipbook_Actor) -> f64 {
	return flipbook_clip_seconds(&FLIPBOOK_SHEETS[actor.character].clips[actor.action], actor.first_frame)
}

flipbook_one_shot_running :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	if actor.action == .Idle { return false }
	if actor.action == .Death { return true }
	return now-actor.started < flipbook_one_shot_seconds(actor)
}

// Past the impact drawing, a one-shot is only follow-through and may yield.
flipbook_past_hit :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	clip := &FLIPBOOK_SHEETS[actor.character].clips[actor.action]
	if clip.hit < 0 { return true }
	frame, _ := flipbook_frame(clip, now-actor.started, actor.first_frame)
	return frame > clip.hit
}

// 0..1 progress of the card toppling after the death drawings.
flipbook_fall :: proc(actor: ^Flipbook_Actor, now: f64) -> f32 {
	if actor == nil || actor.action != .Death { return 0 }
	t := (now-actor.started-flipbook_one_shot_seconds(actor))/FLIPBOOK_FALL_SECONDS
	return f32(clamp(t, 0, 1))
}

flipbook_death_done :: proc(actor: ^Flipbook_Actor, now: f64) -> bool {
	return actor.action == .Death && now-actor.started >= flipbook_one_shot_seconds(actor)+FLIPBOOK_FALL_SECONDS
}

// The drawing to print right now.
flipbook_drawing :: proc(actor: ^Flipbook_Actor, now: f64) -> (action: Flipbook_Action, frame: i32) {
	sheet := &FLIPBOOK_SHEETS[actor.character]
	if actor.action != .Idle {
		clip := &sheet.clips[actor.action]
		drawing, finished := flipbook_frame(clip, now-actor.started, actor.first_frame)
		if !finished || actor.action == .Death { return actor.action, drawing }
	}
	base := flipbook_resolve(actor.character, actor.base)
	drawing, _ := flipbook_frame(&sheet.clips[base], now-actor.base_started)
	return base, drawing
}

flipbook_slot :: proc(state: ^Flipbook_State, entity: game.Entity_Ref, character: Flipbook_Character, now: f64) -> ^Flipbook_Actor {
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

flipbook_find :: proc(renderer: ^Renderer, entity: game.Entity_Ref, character: Flipbook_Character, position: view.Vec2) -> ^Flipbook_Actor {
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

flipbook_camera_right :: proc(renderer: ^Renderer) -> rl.Vector3 {
	camera := renderer.tactical.camera
	return rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, camera.position-camera.target))
}

// Screen-space facing: prints are drawn facing right and mirror to face left.
// A change of side turns the card over like a real standee.
flipbook_face :: proc(actor: ^Flipbook_Actor, sideways: f32, now: f64) {
	if abs(sideways) < 0.2 { return }
	left := sideways < 0
	if left == actor.facing_left { return }
	actor.facing_left = left
	actor.turn_started = now
}

// Which clip a cue asks of this actor. `from_hit` starts at the impact
// drawing: the cue *is* the impact, its anticipation is already past.
flipbook_cue_action :: proc(cue: ^Presentation_Cue, entity: game.Entity_Ref) -> (action: Flipbook_Action, matched, from_hit: bool) {
	event := &cue.event
	#partial switch cue.kind {
	case .Move:
		if event.target == entity { return .Walk, true, false }
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

flipbook_observe :: proc(renderer: ^Renderer, state: ^Flipbook_State, room: ^game.Room, actor: Presentation_Actor,
	character: Flipbook_Character, now: f64, right: rl.Vector3) {
	slot := flipbook_slot(state, actor.entity, character, now)
	slot.seen, slot.ghost, slot.position = now, false, actor.position
	wanted, from_hit := Flipbook_Action.Idle, false
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
		if flipbook_priority(action) > flipbook_priority(wanted) { wanted, from_hit = action, at_hit }
	}
	if walking {
		if now > slot.walk_until && slot.base != .Walk { slot.base_started = now }
		slot.walk_until = now+FLIPBOOK_WALK_GRACE
	}
	if wanted != .Idle {
		fresh := wanted != slot.trigger || now-slot.trigger_seen > FLIPBOOK_TRIGGER_GAP
		slot.trigger, slot.trigger_seen = wanted, now
		resolved := flipbook_resolve(character, wanted)
		clip := &FLIPBOOK_SHEETS[character].clips[resolved]
		if fresh && !clip.loop && slot.action != .Death {
			if !flipbook_one_shot_running(slot, now) || flipbook_priority(resolved) >= flipbook_priority(slot.action) ||
			   flipbook_past_hit(slot, now) {
				slot.action, slot.started = resolved, now
				slot.first_frame = max(clip.hit, 0) if from_hit else 0
			}
		}
	}
	// The loop beneath the one-shots: stride, telegraph, daze or breath.
	base := Flipbook_Action.Idle
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

// Once per frame, before the board is drawn: read the cues and states. Map
// and ring views only read the result.
update_flipbook_actors :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	state := v.flipbook_state
	if state == nil || !v.flipbook.loaded || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	right := flipbook_camera_right(renderer)
	snapshot := v.snapshot
	if snapshot.player.visible { flipbook_observe(renderer, state, room, snapshot.player, .Pilgrim, now, right) }
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		if !actor.visible { continue }
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
flipbook_opacity :: proc(renderer: ^Renderer, entity: game.Entity_Ref, key: Sprite_Key, position: view.Vec2, opacity: f32) -> f32 {
	character, ok := flipbook_character(key)
	if !ok || !renderer.tactical.flipbook.loaded { return opacity }
	actor := flipbook_find(renderer, entity, character, position)
	if actor == nil || actor.action != .Death { return opacity }
	fall := flipbook_fall(actor, renderer.sprite_assets.elapsed)
	return clamp(1-(fall-0.55)/0.45, 0, 1)
}

flipbook_billboard_geometry :: proc(renderer: ^Renderer, character: Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	feedback: bool, entity: game.Entity_Ref) -> Tactical_Billboard {
	v := &renderer.tactical
	sheet := &FLIPBOOK_SHEETS[character]
	now := renderer.sprite_assets.elapsed
	actor := flipbook_find(renderer, entity, character, position) if feedback else nil
	action, frame := Flipbook_Action.Idle, i32(0)
	if actor != nil { action, frame = flipbook_drawing(actor, now) }
	else {
		phase := f64(position.x*0.31+position.y*0.17)
		frame, _ = flipbook_frame(&sheet.clips[.Idle], now+phase)
	}
	clip := &sheet.clips[action]
	cell := rl.Vector2{f32(sheet.cell.x), f32(sheet.cell.y)}
	// The paper follows the print to each new drawing over a short morph.
	shown := [2]i32{clip.row, frame}
	previous, morph := shown, f32(1)
	if actor != nil {
		if actor.shown.x < 0 { actor.previous, actor.shown, actor.shown_since = shown, shown, now-FLIPBOOK_MORPH_SECONDS }
		else if actor.shown != shown { actor.previous, actor.shown, actor.shown_since = actor.shown, shown, now }
		previous = actor.previous
		morph = f32(clamp((now-actor.shown_since)/FLIPBOOK_MORPH_SECONDS, 0, 1))
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
	lift := (FLIPBOOK_PAPER+FLIPBOOK_INK)*scale+0.03
	if v.outline_mode == .Hologram { lift = 0; result.card = {} }
	base := rl.Vector3{position.x+0.5, 0.02+lift+pose.lift, position.y+0.5}
	sy := scale*pose.scale_y
	bl := base-right*(feet_x*scale*width)-up*(below*sy)
	span := right*(cell.x*scale*width)
	top := up*(cell.y*sy)
	lean := right*pose.lean
	result.points = {bl+top+lean, bl, bl+span, bl+span+top+lean}
	if fall := flipbook_fall(actor, now); fall > 0 {
		// Topple backwards around the card's bottom edge.
		angle := fall*fall*1.4
		away := rl.Vector3Normalize(rl.Vector3{v.camera.target.x-v.camera.position.x, 0, v.camera.target.z-v.camera.position.z})
		floor := f32(0.02)
		for &point in result.points {
			h := point.y-floor
			point = {point.x, floor+h*math.cos(angle), point.z}+away*(h*math.sin(angle))
		}
	}
	return result
}

// The card quad grows the print quad by the paper margin on every side, in
// the quad's own axes, so ring and lean transforms of the print carry it.
flipbook_card_points :: proc(quad: Tactical_Billboard) -> [4]rl.Vector3 {
	right := (quad.points[2]-quad.points[1])/max(quad.source.width, 1)
	up := (quad.points[0]-quad.points[1])/max(quad.source.height, 1)
	m := quad.card_margin
	return {quad.points[0]+(-right+up)*m, quad.points[1]+(-right-up)*m,
		quad.points[2]+(right-up)*m, quad.points[3]+(right+up)*m}
}

flipbook_card_hit :: proc(renderer: ^Renderer, quad: Tactical_Billboard, ray: rl.Ray) -> (distance: f32, hit: bool) {
	points := flipbook_card_points(quad)
	collision := rl.GetRayCollisionQuad(ray, points[0], points[1], points[2], points[3])
	if !collision.hit { return }
	character, ok := flipbook_character(quad.key)
	if !ok { return }
	field := renderer.tactical.flipbook.fields[character]
	width, height := int(quad.card.width), int(quad.card.height)
	if len(field) < width*height || width <= 0 { return collision.distance, true }
	u := points[3]-points[0]
	w := points[1]-points[0]
	delta := collision.point-points[0]
	fx := clamp(rl.Vector3DotProduct(delta, u)/rl.Vector3DotProduct(u, u), 0, 0.9999)
	fy := clamp(rl.Vector3DotProduct(delta, w)/rl.Vector3DotProduct(w, w), 0, 0.9999)
	if quad.mirror { fx = 0.9999-fx }
	// Picking follows the paper of the drawing on the card now.
	x := clamp(int((quad.card_b.x+fx*quad.card_b.width)*f32(width)), 0, width-1)
	y := clamp(int((quad.card_b.y+fy*quad.card_b.height)*f32(height)), 0, height-1)
	if f32(field[y*width+x]) > (FLIPBOOK_PAPER+FLIPBOOK_INK)*FLIPBOOK_PAPER_SCALE { return }
	return collision.distance, true
}

draw_flipbook_card :: proc(renderer: ^Renderer, quad: Tactical_Billboard, uv: [4]rl.Vector2, opacity: f32) {
	assets := &renderer.tactical.flipbook
	if assets.paper_shader.id == 0 { return }
	points := flipbook_card_points(quad)
	a := rl.Vector4{quad.card_a.x, quad.card_a.y, quad.card_a.width, quad.card_a.height}
	b := rl.Vector4{quad.card_b.x, quad.card_b.y, quad.card_b.width, quad.card_b.height}
	morph := quad.card_morph
	cell := rl.Vector2{quad.source.width+quad.card_margin*2, quad.source.height+quad.card_margin*2}
	edge := rl.Vector2{-1 if quad.mirror else 1, 1}
	rl.SetShaderValue(assets.paper_shader, assets.frame_a_location, &a, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.frame_b_location, &b, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.morph_location, &morph, .FLOAT)
	rl.SetShaderValue(assets.paper_shader, assets.cell_location, &cell, .VEC2)
	rl.SetShaderValue(assets.paper_shader, assets.edge_location, &edge, .VEC2)
	rl.BeginShaderMode(assets.paper_shader)
	rlgl.SetTexture(quad.card.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, u8(clamp(opacity, f32(0), f32(1))*255))
	for point, index in points {
		rlgl.TexCoord2f(uv[index].x, uv[index].y)
		rlgl.Vertex3f(point.x, point.y, point.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndShaderMode()
}

// The standee's base: a low iron plinth with a slot that grips the card,
// turned with the card toward the camera and hopping with it. A thin strip
// of the side's colour (ivory pilgrim, crimson foe) runs along its front.
draw_flipbook_stand :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, accent: rl.Color) {
	character, ok := flipbook_character(key)
	if !ok { return }
	sheet := &FLIPBOOK_SHEETS[character]
	pose := tactical_feedback_pose(renderer, key, position)
	right := flipbook_camera_right(renderer)
	angle := math.atan2(-right.z, right.x)*math.DEG_PER_RAD
	size := clamp(sheet.world_height/1.35, 0.85, 1.2)
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.Translatef(position.x+0.5, pose.lift, position.y+0.5)
	rlgl.Rotatef(angle, 0, 1, 0)
	rlgl.Scalef(size, 1, size)
	rl.DrawCube({0, 0.03, 0}, 0.58, 0.05, 0.24, {20, 24, 34, 255})
	rl.DrawCubeWires({0, 0.03, 0}, 0.58, 0.05, 0.24, {58, 66, 86, 255})
	rl.DrawCube({0, 0.062, 0}, 0.5, 0.016, 0.18, {44, 50, 66, 255})
	rl.DrawCube({0, 0.082, 0}, 0.24, 0.03, 0.075, {30, 35, 48, 255})
	rl.DrawCube({0, 0.03, 0.121}, 0.5, 0.014, 0.004, accent)
}

// The card shader with the generator's paper constants baked in. GLSL braces
// rule out fmt templates, so named tokens are replaced instead.
flipbook_paper_source :: proc() -> cstring {
	source := string(FLIPBOOK_PAPER_FRAGMENT)
	tokens := [4]string{"PAPER_SCALE", "EDGE_PX", "PAPER_PX", "INK_PX"}
	values := [4]f32{FLIPBOOK_PAPER_SCALE, FLIPBOOK_EDGE, FLIPBOOK_PAPER, FLIPBOOK_PAPER+FLIPBOOK_INK}
	for token, index in tokens {
		source, _ = strings.replace_all(source, token, fmt.tprintf("%.4f", values[index]), context.temp_allocator)
	}
	return strings.clone_to_cstring(source, context.temp_allocator)
}
