package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../grid"

// Blows on the 3D board, cut from paper like the living cards. The game marks
// every physical blow (game.mark_attack_events): a bump, an enemy's Attack or
// Charge. When one of its cues starts showing, the attacker's own weapon
// (gfx.ATTACK_PROPS) sweeps over every cell the blow covers, or its bolt,
// bomb or ember flies to the aim on a slight arc. The blow lands on the hit
// drawing of the attacker's attack clip (gfx.living_hit_seconds); the struck
// card's reaction, its token and the lab's sounds wait for a bolt to land
// (attack_fx_landing_in). A prop lives on its attacker's clock (living_clock:
// the world's stands still while the player is in his shadow), outlives its
// cues and never gates gameplay. The other phases play their own through
// play_attack_swing, play_attack_projectile and reflect_attack_projectile.

ATTACK_FX_MAX :: 24
ATTACK_FX_SEEN :: 48
// tools/art/living_actions.py: a struck card's reaction (hurt, block, dodge,
// death) lands STRIKE ms after it starts.
LIVING_REACT_STRIKE :: f64(0.115)
// The swing's last stretch before the contact, and its follow-through.
ATTACK_SWING_LEAD :: f64(0.08)
ATTACK_SWING_FOLLOW :: f64(0.13)
ATTACK_SWING_FOLLOW_PER_CELL :: f64(0.03)
ATTACK_SWING_OVERSHOOT :: f32(0.5)
ATTACK_FADE_SECONDS :: f64(0.16)
ATTACK_IMPACT_SECONDS :: f64(0.26)
ATTACK_STUCK_SECONDS :: f64(0.24)
ATTACK_GROUNDED_SECONDS :: f64(0.55)
ATTACK_SHARD_SECONDS :: f64(0.38)
// The ghoul's second rake, after the first (tools/art/living_actions.py:
// its slashes 128 ms apart).
ATTACK_RAKE_SECOND :: f64(0.128)
// Props are drawn a little larger than in their owners' hands, to read on the board.
ATTACK_PROP_SCALE :: f32(1.3)

Attack_Look :: enum u8 {None, Lantern, Iron_Cleaver, Storm_Pike, Claws, Cleaver, Crozier, Staff, Bolt, Bomb, Ember}
Attack_Fx_Kind :: enum u8 {Swing, Thrust, Rake, Projectile}
Attack_Outcome :: enum u8 {Missed, Absorbed, Hit}

Attack_Fx :: struct {
	used, critical, reflected: bool,
	// RIFLESSO: the blow an Attack_Deflected cue shows, and whether it has
	// been turned back yet (attack_fx_answer_deflection): a bolt flies home as
	// it reaches the player; a swing is answered by his riposte, a cue of its own.
	deflect, answered: bool,
	// RIFLESSO's place among the player's statuses as the blow began (-1:
	// none): the charge it spends keeps its chip there until the blow reaches
	// him (hold_unlanded_blows).
	slot: i32,
	// What the blow takes from its victim's health, shown as it lands
	// (hold_unlanded_blows).
	damage: i32,
	id: u32,
	kind: Attack_Fx_Kind,
	look: Attack_Look,
	outcome: Attack_Outcome,
	attacker, victim: game.Entity_Ref,
	character: gfx.Flipbook_Character,
	// The aimed cell, the cells swept (footprint bits around it) and the
	// attacker's cell when the blow began.
	aim, from: grid.Position,
	swept: u16,
	// On the attacker's clock: its clip started, the blow lands (a swing's
	// contact, a bolt's release) and the bolt arrives (a swing's: its contact).
	start, contact, landing: f64,
	// A bolt's flight, from the muzzle to where it lands.
	origin, target: rl.Vector3,
	arc: f32,
	batch: u32,
}

// What makes a blow this one, whichever of its cues shows it.
Attack_Fx_Key :: struct {
	batch: u32,
	attacker, victim: game.Entity_Ref,
	aim: grid.Position,
	swept: u16,
}

Attack_Fx_State :: struct {
	items: [ATTACK_FX_MAX]Attack_Fx,
	next_id: u32,
	// Blows already shown: a cue still showing after its prop is over never
	// brings it back.
	seen: [ATTACK_FX_SEEN]Attack_Fx_Key,
	seen_next: int,
	// What the board has shown so far (smoke and tests).
	spawned: [Attack_Look]int,
}

// --------------------------------------------------------------------------
// Who strikes with what.

attack_character :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (character: gfx.Flipbook_Character, archetype: game.Enemy_Archetype, ok: bool) {
	if entity == game.PLAYER_ENTITY { return .Pilgrim, .Count, true }
	if actor, found := presentation_actor_in_view(renderer.tactical.snapshot, entity); found {
		character, ok = flipbook_character(sprite_key_for_enemy(actor.archetype))
		return character, actor.archetype, ok
	}
	return
}

// The player's iron lantern, or the M8 weapon in his hand as the board shows
// him, and the arrow he looses (FERETRO); every enemy its own.
attack_look :: proc(renderer: ^Renderer, attacker: game.Entity_Ref, ranged: bool) -> Attack_Look {
	if attacker == game.PLAYER_ENTITY {
		if ranged { return .Bolt }
		return attack_player_look(renderer.tactical.snapshot.weapon if renderer.tactical.snapshot != nil else .None)
	}
	_, archetype, ok := attack_character(renderer, attacker)
	if !ok { return .Bolt if ranged else .Claws }
	return attack_enemy_look(archetype, ranged)
}

attack_player_look :: proc(weapon: game.Weapon_Id) -> Attack_Look {
	switch weapon {
	case .Iron_Cleaver: return .Iron_Cleaver
	case .Storm_Pike: return .Storm_Pike
	case .None:
	}
	return .Lantern
}

attack_enemy_look :: proc(archetype: game.Enemy_Archetype, ranged: bool) -> Attack_Look {
	switch archetype {
	case .Chaser: return .Claws
	case .Archer: return .Bolt
	case .Brute: return .Cleaver
	case .Bomber: return .Bomb
	case .Custodian: return .Crozier
	case .Demolitionist: return .Ember if ranged else .Staff
	case .Count:
	}
	return .Claws
}

attack_fx_kind :: proc(look: Attack_Look, ranged: bool) -> Attack_Fx_Kind {
	if ranged || look == .Bolt || look == .Bomb || look == .Ember { return .Projectile }
	if look == .Storm_Pike { return .Thrust }
	if look == .Claws { return .Rake }
	return .Swing
}

attack_look_prop :: proc(look: Attack_Look, t: f64) -> gfx.Attack_Prop {
	switch look {
	case .Lantern: return .Lantern
	case .Iron_Cleaver: return .Iron_Cleaver
	case .Storm_Pike: return .Storm_Pike
	case .Claws: return .Claw
	case .Cleaver: return .Cleaver
	case .Crozier: return .Crozier
	case .Staff: return .Staff
	case .Bolt: return .Bolt
	case .Bomb: return .Bomb
	// The ember flickers between its two drawings.
	case .Ember: return .Ember_A if int(math.floor(t*16))%2 == 0 else .Ember_B
	case .None:
	}
	return .Impact
}

// Seconds from the start of a character's attack clip to its hit drawing.
attack_fx_impact_seconds :: proc(character: gfx.Flipbook_Character) -> f64 {
	return gfx.living_hit_seconds(&gfx.LIVING_SHEETS[character].clips[gfx.living_resolve(character, .Attack)])
}

attack_flight_seconds :: proc(look: Attack_Look, cells: f32) -> f64 {
	flight := clamp(0.11+0.04*f64(cells), 0.14, 0.34)
	return flight*1.35 if look == .Bomb else flight
}

attack_flight_arc :: proc(look: Attack_Look, cells: f32) -> f32 {
	#partial switch look {
	case .Bomb: return 0.42+0.08*cells
	case .Ember: return 0.14+0.03*cells
	}
	return 0.08+0.03*cells
}

// A swing's follow-through after its contact, longer the more cells it sweeps.
attack_swing_follow :: proc(cells: int) -> f64 {
	return ATTACK_SWING_FOLLOW+ATTACK_SWING_FOLLOW_PER_CELL*f64(max(cells, 1)-1)
}

// Seconds from the start of a marked blow until its attacker is done with it:
// the hit drawing of its attack clip, then a bolt's flight (from its cell to
// the aim) or a swing's follow-through and the ghoul's second rake.
attack_fx_done_seconds :: proc(character: gfx.Flipbook_Character, look: Attack_Look, blow: game.Game_Event) -> f64 {
	contact := attack_fx_impact_seconds(character)
	kind := attack_fx_kind(look, game.event_is_ranged_attack(blow))
	if kind == .Projectile {
		dx, dz := f32(blow.to_position.x-blow.from_position.x), f32(blow.to_position.y-blow.from_position.y)
		return contact+attack_flight_seconds(look, math.sqrt(dx*dx+dz*dz))
	}
	_, count := attack_swept_cells(blow.to_position, blow.area_mask&game.EVENT_FOOTPRINT_BITS)
	return contact+attack_swing_follow(count)+(ATTACK_RAKE_SECOND if kind == .Rake else 0)
}

// --------------------------------------------------------------------------
// Where the cards stand.

// A card's feet on the board as it shows now (sliding, or the player's body
// held where it sank in his shadow) and its drawing's height; an object's
// cell and a lower height. A card that has left the board but still falls
// (living_find_dying) stands where it fell: a blow it struck plays on.
attack_card :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (feet: rl.Vector3, height: f32, ok: bool) {
	position, found := tactical_cue_actor_position(renderer, entity)
	if !found {
		snapshot := renderer.tactical.snapshot
		if snapshot == nil { return }
		for object in snapshot.objects[:snapshot.object_count] {
			if object.entity == entity && object.visible { return {object.position.x+0.5, 0.02, object.position.y+0.5}, 0.7, true }
		}
		dying := living_find_dying(renderer, entity)
		if dying == nil { return }
		at, lift := living_card_position(renderer, entity, flipbook_key(dying.character), dying.position)
		return {at.x+0.5, 0.02+lift, at.y+0.5}, gfx.LIVING_SHEETS[dying.character].world_height, true
	}
	character, _, known := attack_character(renderer, entity)
	if !known { return {position.x+0.5, 0.02, position.y+0.5}, 1.2, true }
	at, lift := living_card_position(renderer, entity, flipbook_key(character), position)
	return {at.x+0.5, 0.02+lift, at.y+0.5}, gfx.LIVING_SHEETS[character].world_height, true
}

// Where a blow lands on `entity`: a card's middle (a bolt sticks a little in
// front of it), or the camera's side of an object's box, so that the box
// never hides the impact.
attack_struck_point :: proc(renderer: ^Renderer, entity: game.Entity_Ref, bolt := false) -> (point: rl.Vector3, ok: bool) {
	feet, height, found := attack_card(renderer, entity)
	if !found { return }
	toward := attack_toward_camera(renderer)
	if snapshot := renderer.tactical.snapshot; entity.kind == .Object && snapshot != nil {
		for object in snapshot.objects[:snapshot.object_count] {
			if object.entity != entity { continue }
			box := voxel_object_bounds(object.kind, object.position)
			centre := (box.min+box.max)*0.5
			// Out of the square along the camera's way, and a hair beyond.
			out := (box.max.x-box.min.x)*0.5/max(abs(toward.x), abs(toward.z), 0.0001)+0.05
			return {centre.x, box.min.y+(box.max.y-box.min.y)*0.55, centre.z}+toward*out, true
		}
	}
	if bolt { return feet+{0, height*0.48, 0}+toward*0.12, true }
	return feet+{0, height*0.5, 0}, true
}

// The size of one texel of a prop in the hand of `character`.
attack_texel :: proc(character: gfx.Flipbook_Character) -> f32 {
	sheet := &gfx.LIVING_SHEETS[character]
	return sheet.world_height/max(sheet.rest_height, 1)*ATTACK_PROP_SCALE
}

attack_cell_center :: proc(cell: grid.Position, height: f32 = 0) -> rl.Vector3 {
	return {f32(cell.x)+0.5, height, f32(cell.y)+0.5}
}

attack_board_cell :: proc(point: rl.Vector3) -> grid.Position {
	return {int(math.floor(point.x)), int(math.floor(point.z))}
}

// The cells a blow sweeps, decoded around its aim (game.event_footprint_bit).
attack_swept_cells :: proc(aim: grid.Position, swept: u16) -> (cells: [9]grid.Position, count: int) {
	for bit in 0..<9 {
		if swept&(u16(1)<<u32(bit)) == 0 { continue }
		cells[count] = {aim.x+bit%3-1, aim.y+bit/3-1}
		count += 1
	}
	if count == 0 { cells[0], count = aim, 1 }
	return
}

attack_prop_length :: proc(prop: gfx.Attack_Prop, texel: f32) -> f32 {
	sheet := gfx.ATTACK_PROPS[prop]
	dx, dy := sheet.tip.x-sheet.grip.x, sheet.tip.y-sheet.grip.y
	return math.sqrt(dx*dx+dy*dy)*texel
}

// --------------------------------------------------------------------------
// The swing's path.

attack_ease_in :: proc(u: f32) -> f32 { v := clamp(u, 0, 1); return v*v }
attack_ease_out :: proc(u: f32) -> f32 { v := clamp(u, 0, 1); return 1-(1-v)*(1-v) }

// When a swing starts to come down: the last stretch before its contact,
// never before its clip began.
attack_swing_begin :: proc(fx: ^Attack_Fx) -> f64 {
	return fx.contact-min(ATTACK_SWING_LEAD, max(fx.contact-fx.start, 0))
}

// The yaw at `t`: held at `start` until `begin`, speeding up to `aim` at
// `contact`, slowing down to `finish` over `follow`.
attack_swing_yaw :: proc(t, begin, contact, follow: f64, start, aim, finish: f32) -> f32 {
	if t <= begin { return start }
	if t <= contact {
		u := f32((t-begin)/max(contact-begin, 0.0001))
		return start+(aim-start)*attack_ease_in(u)
	}
	return aim+(finish-aim)*attack_ease_out(f32((t-contact)/max(follow, 0.0001)))
}

// When the swing's yaw passes `yaw` (-1: never).
attack_swing_passes :: proc(begin, contact, follow: f64, start, aim, finish, yaw: f32) -> f64 {
	previous := attack_swing_yaw(begin, begin, contact, follow, start, aim, finish)
	for step in 1..=96 {
		t := begin+(contact+follow-begin)*f64(step)/96
		current := attack_swing_yaw(t, begin, contact, follow, start, aim, finish)
		if (previous-yaw)*(current-yaw) <= 0 && previous != current { return t }
		previous = current
	}
	return -1
}

attack_wrap :: proc(angle: f32) -> f32 {
	a := angle
	for a > math.PI { a -= math.TAU }
	for a < -math.PI { a += math.TAU }
	return a
}

Attack_Swing :: struct {
	hand: rl.Vector3,
	start, aim, finish: f32,
	follow: f64,
	reach, grip: f32,
	yaws: [9]f32,
	cells: [9]grid.Position,
	count: int,
}

// A swing's plan from where the attacker's card stands now: it sweeps from
// its cell farthest from the camera to its nearest, so the blow comes toward
// the eye, and its weapon's tip crosses the aim's centre at the contact.
attack_swing_plan :: proc(renderer: ^Renderer, fx: ^Attack_Fx) -> (plan: Attack_Swing, ok: bool) {
	feet, height, found := attack_card(renderer, fx.attacker)
	if !found { return }
	plan.hand = feet+{0, height*0.5, 0}
	plan.cells, plan.count = attack_swept_cells(fx.aim, fx.swept)
	aim := attack_cell_center(fx.aim)
	plan.aim = math.atan2(aim.z-plan.hand.z, aim.x-plan.hand.x)
	low, high := f32(0), f32(0)
	for index in 0..<plan.count {
		c := attack_cell_center(plan.cells[index])
		plan.yaws[index] = plan.aim+attack_wrap(math.atan2(c.z-plan.hand.z, c.x-plan.hand.x)-plan.aim)
		low, high = min(low, plan.yaws[index]-plan.aim), max(high, plan.yaws[index]-plan.aim)
	}
	plan.start, plan.finish = plan.aim+low-ATTACK_SWING_OVERSHOOT, plan.aim+high+ATTACK_SWING_OVERSHOOT
	camera := renderer.tactical.camera.position
	far := rl.Vector3{plan.hand.x+math.cos(plan.start), 0, plan.hand.z+math.sin(plan.start)}
	near := rl.Vector3{plan.hand.x+math.cos(plan.finish), 0, plan.hand.z+math.sin(plan.finish)}
	if rl.Vector3Distance(far, camera) < rl.Vector3Distance(near, camera) { plan.start, plan.finish = plan.finish, plan.start }
	plan.follow = attack_swing_follow(plan.count)
	plan.reach = attack_prop_length(attack_look_prop(fx.look, 0), attack_texel(fx.character))
	distance := math.sqrt((aim.x-plan.hand.x)*(aim.x-plan.hand.x)+(aim.z-plan.hand.z)*(aim.z-plan.hand.z))
	plan.grip = clamp(distance-plan.reach*math.cos(f32(0.35))-0.05, 0.12, 1.1)
	return plan, true
}

// The weapon's grip and tip at `t`: raised behind before the blow, coming
// down over the cells as it sweeps, low after it.
attack_swing_pose :: proc(fx: ^Attack_Fx, plan: ^Attack_Swing, t: f64) -> (grip, tip: rl.Vector3) {
	begin := attack_swing_begin(fx)
	yaw := attack_swing_yaw(t, begin, fx.contact, plan.follow, plan.start, plan.aim, plan.finish)
	pitch: f32
	if t <= begin { pitch = 1.15 }
	else if t <= fx.contact { pitch = 1.15+(-0.35-1.15)*attack_ease_in(f32((t-begin)/max(fx.contact-begin, 0.0001))) }
	else { pitch = -0.35+(-0.7+0.35)*attack_ease_out(f32((t-fx.contact)/plan.follow)) }
	out := rl.Vector3{math.cos(yaw), 0, math.sin(yaw)}
	grip = plan.hand+out*plan.grip+rl.Vector3{0, 0.12*math.sin(pitch), 0}
	tip = grip+(out*math.cos(pitch)+rl.Vector3{0, math.sin(pitch), 0})*plan.reach
	return
}

// The pike's lunge at `t`: straight at its cell and back.
attack_thrust_pose :: proc(fx: ^Attack_Fx, plan: ^Attack_Swing, t: f64) -> (grip, tip: rl.Vector3) {
	begin := attack_swing_begin(fx)
	out := rl.Vector3{math.cos(plan.aim), 0, math.sin(plan.aim)}
	lunge := f32(0)
	if t > begin && t <= fx.contact { lunge = attack_ease_in(f32((t-begin)/max(fx.contact-begin, 0.0001))) }
	else if t > fx.contact { lunge = 1-attack_ease_out(f32((t-fx.contact)/plan.follow))*0.7 }
	grip = plan.hand+out*(0.05+(plan.grip-0.05)*lunge)+rl.Vector3{0, -0.05, 0}
	tip = grip+(out*math.cos(f32(-0.15))+rl.Vector3{0, math.sin(f32(-0.15)), 0})*plan.reach
	return
}

// --------------------------------------------------------------------------
// The bolt's path.

attack_flight_point :: proc(origin, target: rl.Vector3, arc, u: f32) -> (point, heading: rl.Vector3) {
	v := clamp(u, 0, 1)
	point = origin+(target-origin)*v+rl.Vector3{0, arc*4*v*(1-v), 0}
	heading = rl.Vector3Normalize((target-origin)+rl.Vector3{0, arc*4*(1-2*v), 0})
	return
}

// The camera's side of a card, on the board's plane.
attack_toward_camera :: proc(renderer: ^Renderer) -> rl.Vector3 {
	camera := renderer.tactical.camera
	return rl.Vector3Normalize(rl.Vector3{camera.position.x-camera.target.x, 0, camera.position.z-camera.target.z})
}

// Fixes a bolt's flight: from the attacker's card at chest height to the
// victim's (a hit or a guard), or into the floor beyond the aim (a miss).
attack_aim_flight :: proc(renderer: ^Renderer, fx: ^Attack_Fx) {
	feet, height, found := attack_card(renderer, fx.attacker)
	if !found { feet, height = attack_cell_center(fx.from, 0.02), 1.2 }
	target := attack_cell_center(fx.aim, 0.04)
	if fx.outcome != .Missed {
		if struck, ok := attack_struck_point(renderer, fx.victim, true); ok { target = struck }
	}
	origin := feet+{0, height*0.52, 0}
	toward := rl.Vector3{target.x-origin.x, 0, target.z-origin.z}
	cells := rl.Vector3Length(toward)
	if cells > 0.001 {
		toward = toward/cells
		origin += toward*0.28
		if fx.outcome == .Missed { target += toward*0.18 }
	}
	fx.origin, fx.target = origin, target
	fx.arc = attack_flight_arc(fx.look, cells)
	fx.landing = fx.contact+attack_flight_seconds(fx.look, cells)
}

// --------------------------------------------------------------------------
// Playing blows: from the cues, and for the other phases.

// The board is new: no blow of the old one stays on it.
forget_attack_fx :: proc(renderer: ^Renderer) {
	if renderer == nil { return }
	spawned := renderer.tactical.attack_fx.spawned
	renderer.tactical.attack_fx = {spawned = spawned}
}

attack_fx_end :: proc(fx: ^Attack_Fx) -> f64 {
	if fx.kind == .Projectile {
		tail := ATTACK_STUCK_SECONDS+0.2 if fx.outcome == .Hit else (0.3 if fx.outcome == .Absorbed else ATTACK_GROUNDED_SECONDS+0.2)
		return fx.landing+max(tail, ATTACK_SHARD_SECONDS)
	}
	follow := ATTACK_SWING_FOLLOW+ATTACK_SWING_FOLLOW_PER_CELL*8
	second := ATTACK_RAKE_SECOND if fx.kind == .Rake else 0
	return fx.contact+second+max(follow+ATTACK_FADE_SECONDS, ATTACK_SHARD_SECONDS)
}

// A free slot, or the oldest blow's.
attack_fx_slot :: proc(state: ^Attack_Fx_State) -> ^Attack_Fx {
	for &fx in state.items { if !fx.used { return &fx } }
	oldest := &state.items[0]
	for &fx in state.items { if fx.start < oldest.start { oldest = &fx } }
	return oldest
}

attack_fx_begin :: proc(renderer: ^Renderer, attacker, victim: game.Entity_Ref, look: Attack_Look, kind: Attack_Fx_Kind,
	outcome: Attack_Outcome, aim: grid.Position, swept: u16, fallback: gfx.Flipbook_Character) -> ^Attack_Fx {
	character, _, known := attack_character(renderer, attacker)
	if !known { character = fallback }
	state := &renderer.tactical.attack_fx
	fx := attack_fx_slot(state)
	now := living_clock(renderer, attacker)
	state.next_id += 1
	fx^ = {used = true, id = state.next_id, kind = kind, look = look, outcome = outcome, attacker = attacker, victim = victim,
		character = character, aim = aim, swept = swept, start = now}
	if feet, _, found := attack_card(renderer, attacker); found { fx.from = attack_board_cell(feet) }
	state.spawned[look] += 1
	return fx
}

// A weapon swung by `attacker` over `swept` (footprint bits around `aim`),
// the blow landing `contact` seconds from now on its clock (-1: on its attack
// clip's hit drawing). A swing nobody's cue asked for: Phase 2's riposte.
play_attack_swing :: proc(renderer: ^Renderer, attacker, victim: game.Entity_Ref, look: Attack_Look, aim: grid.Position,
	swept: u16 = 1<<4, outcome := Attack_Outcome.Hit, contact := f64(-1)) -> (id: u32, ok: bool) {
	if renderer == nil || look == .None { return }
	fx := attack_fx_begin(renderer, attacker, victim, look, attack_fx_kind(look, false), outcome, aim, swept, .Pilgrim)
	fx.contact = fx.start+(attack_fx_impact_seconds(fx.character) if contact < 0 else contact)
	fx.landing = fx.contact
	return fx.id, true
}

// A bolt (or bomb, or ember) from `shooter` at `aim`, loosed `release`
// seconds from now (-1: on the attack clip's hit drawing). Returns the
// seconds until it lands.
play_attack_projectile :: proc(renderer: ^Renderer, shooter, victim: game.Entity_Ref, look: Attack_Look, aim: grid.Position,
	outcome := Attack_Outcome.Hit, release := f64(-1)) -> (id: u32, landing: f64, ok: bool) {
	if renderer == nil || look == .None { return }
	fx := attack_fx_begin(renderer, shooter, victim, look, .Projectile, outcome, aim, 1<<4, .Archer)
	fx.contact = fx.start+(attack_fx_impact_seconds(fx.character) if release < 0 else release)
	attack_aim_flight(renderer, fx)
	return fx.id, fx.landing-fx.start, true
}

attack_fx_by_id :: proc(renderer: ^Renderer, id: u32) -> ^Attack_Fx {
	if id == 0 { return nil }
	for &fx in renderer.tactical.attack_fx.items { if fx.used && fx.id == id { return &fx } }
	return nil
}

// Phase 2 (Deflect): a bolt in flight, or just landed, flies back from where
// it is to its shooter, now the struck one. Returns the seconds until it lands.
reflect_attack_projectile :: proc(renderer: ^Renderer, id: u32, outcome := Attack_Outcome.Hit) -> (landing: f64, ok: bool) {
	fx := attack_fx_by_id(renderer, id)
	if fx == nil || fx.kind != .Projectile { return }
	now := living_clock(renderer, fx.attacker)
	u := f32(clamp((now-fx.contact)/max(fx.landing-fx.contact, 0.0001), 0, 1))
	from, _ := attack_flight_point(fx.origin, fx.target, fx.arc, u)
	shooter := fx.attacker
	fx.attacker, fx.victim, fx.reflected, fx.outcome = fx.victim, shooter, true, outcome
	if character, _, known := attack_character(renderer, fx.attacker); known { fx.character = character }
	now = living_clock(renderer, fx.attacker)
	target := fx.origin
	if feet, height, found := attack_card(renderer, shooter); found { target = feet+{0, height*0.48, 0} }
	fx.origin, fx.target = from, target
	cells := rl.Vector3Length(rl.Vector3{target.x-from.x, 0, target.z-from.z})
	fx.arc = attack_flight_arc(fx.look, cells)
	fx.start, fx.contact = now, now
	fx.landing = now+attack_flight_seconds(fx.look, cells)
	return fx.landing-now, true
}

// RIFLESSO: a deflected blow turned back once it reaches the player. A bolt
// flies home from where it is, now the player's, aimed at its shooter's cell
// (where the reflected cues aim: attack_fx_of_cue finds it for them), and
// lands as its answer does: a wound, or a guard when the shooter's Shield takes
// all of it; a swing waits for the riposte its own cue brings.
attack_fx_answer_deflection :: proc(renderer: ^Renderer, fx: ^Attack_Fx) {
	if fx == nil || fx.answered { return }
	fx.answered = true
	if fx.kind != .Projectile { return }
	home := fx.from
	if _, ok := reflect_attack_projectile(renderer, fx.id, attack_fx_returned_outcome(renderer, fx)); ok { fx.aim, fx.swept = home, 1<<4 }
}

// How a deflected bolt (`fx`, not yet turned) lands back on its shooter: as
// the answer RIFLESSO's command gives it (game.deflect_enemy_blow), its wound
// or, with none, its guard. A hit when the board holds no answer.
attack_fx_returned_outcome :: proc(renderer: ^Renderer, fx: ^Attack_Fx) -> Attack_Outcome {
	outcome := Attack_Outcome.Missed
	if renderer.world_playback != nil {
		for &entry in renderer.world_playback.cues[:renderer.world_playback.count] {
			cue := &entry.cue
			if cue.batch != fx.batch || !game.event_is_reflected(cue.event) || cue.event.source != fx.victim || cue.event.target != fx.attacker { continue }
			if cue.kind == .Damage || cue.kind == .Damage_Absorbed { outcome = max(outcome, attack_cue_outcome(cue.kind)) }
		}
	}
	return outcome if outcome != .Missed else .Hit
}

// The newest prop of `attacker` of a kind still on the board.
attack_fx_find :: proc(renderer: ^Renderer, attacker: game.Entity_Ref, kind: Attack_Fx_Kind) -> (id: u32, ok: bool) {
	newest := f64(-1)
	for fx in renderer.tactical.attack_fx.items {
		if fx.used && fx.attacker == attacker && fx.kind == kind && fx.start > newest { id, ok, newest = fx.id, true, fx.start }
	}
	return
}

attack_fx_key :: proc(cue: ^Presentation_Cue) -> Attack_Fx_Key {
	return {batch = cue.batch, attacker = cue.event.source, victim = cue.event.target, aim = cue.event.to_position,
		swept = cue.event.area_mask&game.EVENT_FOOTPRINT_BITS}
}

// A deflected blow reaches the player's guard: it is stopped there, as one a
// Shield takes.
attack_cue_outcome :: proc(kind: Presentation_Cue_Kind) -> Attack_Outcome {
	#partial switch kind {
	case .Damage, .Explosive_Armed: return .Hit
	case .Damage_Absorbed, .Attack_Deflected: return .Absorbed
	}
	return .Missed
}

attack_cue_is_blow :: proc(cue: ^Presentation_Cue) -> bool {
	if cue == nil || !cue.started || !game.event_is_attack(cue.event) { return false }
	#partial switch cue.kind {
	case .Damage, .Damage_Absorbed, .Attack_Missed, .Explosive_Armed, .Attack_Deflected: return true
	}
	return false
}

// RIFLESSO's answer to a shot: the shooter's own bolt coming home, not an
// arrow of the player's.
attack_cue_returns_bolt :: proc(cue: ^Presentation_Cue) -> bool {
	return cue != nil && game.event_is_reflected(cue.event) && game.event_is_ranged_attack(cue.event)
}

// The deflected bolt a returned shot's cue answers: the shooter's, aimed at the
// player, in the same batch.
attack_fx_deflected_bolt :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> ^Attack_Fx {
	for &fx in renderer.tactical.attack_fx.items {
		if fx.used && fx.deflect && fx.kind == .Projectile && fx.batch == cue.batch &&
		   ((!fx.answered && fx.attacker == cue.event.target && fx.victim == cue.event.source) ||
		    (fx.answered && fx.attacker == cue.event.source && fx.victim == cue.event.target)) { return &fx }
	}
	return nil
}

// The prop showing the blow of `cue`, if any. A returned shot is shown by the
// bolt it turned round.
attack_fx_of_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> ^Attack_Fx {
	if !attack_cue_is_blow(cue) { return nil }
	if attack_cue_returns_bolt(cue) {
		fx := attack_fx_deflected_bolt(renderer, cue)
		return fx if fx != nil && fx.answered else nil
	}
	key := attack_fx_key(cue)
	for &fx in renderer.tactical.attack_fx.items {
		if fx.used && fx.batch == key.batch && fx.attacker == key.attacker && fx.victim == key.victim && fx.aim == key.aim && fx.swept == key.swept { return &fx }
	}
	return nil
}

// Once per frame, before the cards read their cues: a prop for every blow
// that has started showing, one per blow however many of its cues show.
observe_attack_cues :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if !v.enabled || !v.scene_3d || !v.living || v.snapshot == nil { return }
	state := &v.attack_fx
	now := renderer.sprite_assets.elapsed
	for &fx in state.items {
		if fx.used && living_clock_at(renderer, fx.attacker, now) > attack_fx_end(&fx) { fx = {} }
	}
	// RIFLESSO: a deflected bolt turns round as it reaches the player.
	for &fx in state.items {
		if fx.used && fx.deflect && !fx.answered && living_clock_at(renderer, fx.attacker, now) >= fx.landing {
			attack_fx_answer_deflection(renderer, &fx)
		}
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !attack_cue_is_blow(cue) { continue }
		outcome := attack_cue_outcome(cue.kind)
		// The shot given back is the shooter's own bolt, turned now if it has
		// not been yet: the player looses none of his.
		if attack_cue_returns_bolt(cue) {
			attack_fx_answer_deflection(renderer, attack_fx_deflected_bolt(renderer, cue))
			if fx := attack_fx_of_cue(renderer, cue); fx != nil {
				fx.critical = fx.critical || game.event_is_critical(cue.event)
				if cue.kind == .Damage { fx.damage = cue.event.amount }
			}
			continue
		}
		if fx := attack_fx_of_cue(renderer, cue); fx != nil {
			// A guard, then a wound: the same blow, and it got through (only
			// the wound says it was critical).
			fx.outcome = max(fx.outcome, outcome)
			fx.critical = fx.critical || game.event_is_critical(cue.event)
			if cue.kind == .Damage { fx.damage = cue.event.amount }
			continue
		}
		key := attack_fx_key(cue)
		seen := false
		for previous in state.seen { if previous == key && key.batch != 0 { seen = true; break } }
		if seen { continue }
		state.seen[state.seen_next] = key
		state.seen_next = (state.seen_next+1)%len(state.seen)
		ranged := game.event_is_ranged_attack(cue.event)
		look := attack_look(renderer, key.attacker, ranged)
		id: u32
		if attack_fx_kind(look, ranged) == .Projectile {
			id, _, _ = play_attack_projectile(renderer, key.attacker, key.victim, look, key.aim, outcome)
		} else {
			id, _ = play_attack_swing(renderer, key.attacker, key.victim, look, key.aim, key.swept, outcome)
		}
		if fx := attack_fx_by_id(renderer, id); fx != nil {
			fx.batch, fx.swept, fx.critical = key.batch, key.swept, game.event_is_critical(cue.event)
			fx.deflect = cue.kind == .Attack_Deflected
			if cue.kind == .Damage { fx.damage = cue.event.amount }
			// The board shows the charge this blow spends still in its place.
			fx.slot = -1
			if index, carried := game.status_index(&v.snapshot.player.statuses, .Deflect); carried && fx.deflect { fx.slot = i32(index) }
		}
	}
}

// Whether the board has put this blow's prop on it already (it keeps the blows
// it has shown): a returned shot once its bolt has turned carrying the wound,
// or when that bolt is gone.
attack_fx_shown :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	if attack_cue_returns_bolt(cue) {
		fx := attack_fx_deflected_bolt(renderer, cue)
		return fx == nil || (fx.answered && (cue.kind != .Damage || fx.damage > 0))
	}
	key := attack_fx_key(cue)
	if key.batch == 0 { return true }
	for previous in renderer.tactical.attack_fx.seen { if previous == key { return true } }
	return false
}

// Seconds until the earliest blow still to land on `victim` (a bolt in
// flight, a swing not yet down), sprite time `now`; only the blows of
// `attacker` when one is given.
attack_fx_landing_in :: proc(renderer: ^Renderer, victim: game.Entity_Ref, now: f64,
	attacker: Maybe(game.Entity_Ref) = nil) -> (seconds: f64, pending: bool) {
	best := max(f64)
	wanted, filtered := attacker.?
	for &fx in renderer.tactical.attack_fx.items {
		if !fx.used || fx.victim != victim || (filtered && fx.attacker != wanted) { continue }
		left := fx.landing-living_clock_at(renderer, fx.attacker, now)
		if left > 0 && left < best { best, pending = left, true }
	}
	if pending { seconds = best }
	return
}

// How long a struck card waits so that its reaction lands with the blow.
attack_fx_reaction_delay :: proc(renderer: ^Renderer, victim: game.Entity_Ref, now: f64,
	attacker: Maybe(game.Entity_Ref) = nil) -> f64 {
	left, pending := attack_fx_landing_in(renderer, victim, now, attacker)
	return max(0, left-LIVING_REACT_STRIKE) if pending else 0
}

// Whether a blow of the player's own command (the foreground timeline's: a
// bump, an arrow) is still on its way, on a board that shows it with its
// props: its cue started before its prop is on the board, or its prop has not
// landed yet (on the player's clock, which always runs). What follows the blow
// waits for it (update_renderer_frame_timeline), and the charges it spent stay
// on show until it lands (hold_unlanded_blows).
attack_fx_foreground_pending :: proc(renderer: ^Renderer) -> bool {
	v := &renderer.tactical
	head, busy := active_presentation_cue(&renderer.timeline)
	if !busy || head.batch == 0 || !(v.enabled && v.scene_3d && v.living) { return false }
	for offset in 0..<presentation_group_size(&renderer.timeline) {
		cue, _ := presentation_cue_at(&renderer.timeline, offset)
		if attack_cue_is_blow(cue) && cue.event.source == game.PLAYER_ENTITY && !attack_fx_shown(renderer, cue) { return true }
	}
	now := renderer.sprite_assets.elapsed
	for &fx in v.attack_fx.items {
		if fx.used && fx.batch == head.batch && fx.attacker == game.PLAYER_ENTITY && fx.landing-living_clock_at(renderer, fx.attacker, now) > 0 { return true }
	}
	return false
}

// The board shows this blow with its props: the cue's generic hit stays away.
attack_fx_shows :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	return renderer.tactical.attack_props.loaded && attack_fx_of_cue(renderer, cue) != nil
}

// --------------------------------------------------------------------------
// Drawing.

// A prop's texel axes in the world. It faces the viewer like a cut-out held
// up to the eye: its grip-to-tip axis is `long` as the screen shows it, so a
// blow struck toward the camera is never foreshortened; never mirrored.
attack_prop_axes :: proc(long, view: rl.Vector3, axis: [2]f32, texel: f32) -> (u, v: rl.Vector3) {
	along := long-view*rl.Vector3DotProduct(long, view)
	if rl.Vector3Length(along) < 0.0001 {
		// Straight at the eye: up the screen.
		along = rl.Vector3{0, 1, 0}-view*view.y
		if rl.Vector3Length(along) < 0.0001 { along = {1, 0, 0} }
	}
	l := rl.Vector3Normalize(along)
	c := rl.Vector3Normalize(rl.Vector3CrossProduct(view, l))
	length := max(math.sqrt(axis.x*axis.x+axis.y*axis.y), 0.0001)
	a := [2]f32{axis.x/length, axis.y/length}
	u = (l*a.x-c*a.y)*texel
	v = (l*a.y+c*a.x)*texel
	return
}

// The cut edge, in texels, that shows down and to the right on screen.
attack_edge_dir :: proc(renderer: ^Renderer, at, u, v: rl.Vector3) -> rl.Vector2 {
	o := tactical_project(renderer, {at.x, at.z}, at.y)
	pu := tactical_project(renderer, {at.x+u.x, at.z+u.z}, at.y+u.y)
	pv := tactical_project(renderer, {at.x+v.x, at.z+v.z}, at.y+v.y)
	su, sv := [2]f32{pu.x-o.x, pu.y-o.y}, [2]f32{pv.x-o.x, pv.y-o.y}
	det := su.x*sv.y-su.y*sv.x
	if abs(det) < 0.000001 { return {1, 1} }
	ex, ey := (sv.y-sv.x)/det, (su.x-su.y)/det
	length := max(math.sqrt(ex*ex+ey*ey), 0.0001)
	return {ex/length*math.SQRT_TWO, ey/length*math.SQRT_TWO}
}

// The cards' paper shader set for one prop's field.
attack_paper_begin :: proc(renderer: ^Renderer, prop: gfx.Attack_Prop, edge: rl.Vector2) -> bool {
	assets := &renderer.tactical.flipbook
	props := &renderer.tactical.attack_props
	sheet := gfx.ATTACK_PROPS[prop]
	if assets.paper_shader.id == 0 || sheet.paper <= 0 || renderer.tactical.outline_mode == .Hologram { return false }
	m := f32(gfx.ATTACK_PROP_MARGIN)
	w, h := f32(props.paper.width), f32(props.paper.height)
	frame := rl.Vector4{(f32(sheet.rect.x)-m)/w, (f32(sheet.rect.y)-m)/h, (f32(sheet.rect.z)+m*2)/w, (f32(sheet.rect.w)+m*2)/h}
	cell := rl.Vector2{f32(sheet.rect.z)+m*2, f32(sheet.rect.w)+m*2}
	morph := f32(1)
	paper := gfx.LIVING_SHEET_COLOR
	edge := edge
	rl.SetShaderValue(assets.paper_shader, assets.sheet_location, &paper, .VEC3)
	rl.SetShaderValue(assets.paper_shader, assets.frame_a_location, &frame, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.frame_b_location, &frame, .VEC4)
	rl.SetShaderValue(assets.paper_shader, assets.morph_location, &morph, .FLOAT)
	rl.SetShaderValue(assets.paper_shader, assets.cell_location, &cell, .VEC2)
	rl.SetShaderValue(assets.paper_shader, assets.edge_location, &edge, .VEC2)
	rl.BeginShaderMode(assets.paper_shader)
	rlgl.SetTexture(props.paper.id)
	return true
}

attack_paper_end :: proc() {
	rlgl.SetTexture(0)
	rl.EndShaderMode()
}

// One prop laid from `grip` toward `tip` (only the direction counts: it keeps
// its own length), facing the viewer, its paper cut by the cards' shader.
draw_attack_prop :: proc(renderer: ^Renderer, prop: gfx.Attack_Prop, grip, tip: rl.Vector3, texel, opacity: f32, tint := rl.WHITE) {
	props := &renderer.tactical.attack_props
	if !props.loaded || opacity <= 0.01 { return }
	sheet := gfx.ATTACK_PROPS[prop]
	axis := [2]f32{sheet.tip.x-sheet.grip.x, sheet.tip.y-sheet.grip.y}
	long := tip-grip
	if rl.Vector3Length(long) < 0.0001 { long = flipbook_camera_right(renderer) }
	camera := renderer.tactical.camera
	u, v := attack_prop_axes(long, rl.Vector3Normalize(camera.target-camera.position), axis, texel)
	at :: proc(grip, u, v: rl.Vector3, sheet: gfx.Attack_Prop_Sheet, x, y: f32) -> rl.Vector3 {
		return grip+u*(x-sheet.grip.x)+v*(y-sheet.grip.y)
	}
	w, h := f32(sheet.rect.z), f32(sheet.rect.w)
	m := f32(gfx.ATTACK_PROP_MARGIN)
	alpha := u8(clamp(opacity, 0, 1)*255)
	if attack_paper_begin(renderer, prop, attack_edge_dir(renderer, grip, u, v)) {
		corners := [4][2]f32{{-m, -m}, {-m, h+m}, {w+m, h+m}, {w+m, -m}}
		uv := [4][2]f32{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255, 255, 255, alpha)
		for corner, index in corners {
			p := at(grip, u, v, sheet, corner.x, corner.y)
			rlgl.TexCoord2f(uv[index].x, uv[index].y)
			rlgl.Vertex3f(p.x, p.y, p.z)
		}
		rlgl.End()
		attack_paper_end()
	}
	pw, ph := f32(props.print.width), f32(props.print.height)
	corners := [4][2]f32{{0, 0}, {0, h}, {w, h}, {w, 0}}
	rlgl.SetTexture(props.print.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(tint.r, tint.g, tint.b, alpha)
	for corner in corners {
		p := at(grip, u, v, sheet, corner.x, corner.y)
		rlgl.TexCoord2f((f32(sheet.rect.x)+corner.x)/pw, (f32(sheet.rect.y)+corner.y)/ph)
		rlgl.Vertex3f(p.x, p.y, p.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// The swing's smear: a strip of paper bent along the tip's path, its tail
// thin and its head as wide as the weapon (gfx Attack_Prop.Swoosh).
draw_attack_strip :: proc(renderer: ^Renderer, outer, inner: []rl.Vector3, opacity: f32) {
	if len(outer) < 2 || len(inner) != len(outer) || opacity <= 0.01 { return }
	mid := len(outer)/2
	u := (outer[mid]-outer[mid-1])*0.02
	v := (inner[mid]-outer[mid])*0.1
	if !attack_paper_begin(renderer, .Swoosh, attack_edge_dir(renderer, outer[mid], u, v)) { return }
	alpha := u8(clamp(opacity, 0, 1)*255)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, alpha)
	last := f32(len(outer)-1)
	for index in 0..<len(outer)-1 {
		a, b := f32(index)/last, f32(index+1)/last
		quad := [4]rl.Vector3{outer[index], inner[index], inner[index+1], outer[index+1]}
		uv := [4][2]f32{{a, 0}, {a, 1}, {b, 1}, {b, 0}}
		for point, k in quad {
			rlgl.TexCoord2f(uv[k].x, uv[k].y)
			rlgl.Vertex3f(point.x, point.y, point.z)
		}
	}
	rlgl.End()
	attack_paper_end()
}

attack_point_visible :: proc(renderer: ^Renderer, point: rl.Vector3) -> bool {
	return tactical_render_visible(renderer, attack_board_cell(point))
}

attack_impact_tint :: proc(fx: ^Attack_Fx) -> rl.Color {
	if fx.critical { return TACTICAL_FEEDBACK_CRITICAL }
	if fx.outcome == .Absorbed { return TACTICAL_FEEDBACK_BLUE }
	return {196, 44, 44, 255}
}

// The screen's right and up, in the world.
attack_screen_axes :: proc(renderer: ^Renderer) -> (right, up: rl.Vector3) {
	camera := renderer.tactical.camera
	right = flipbook_camera_right(renderer)
	up = rl.Vector3Normalize(rl.Vector3CrossProduct(right, camera.target-camera.position))
	return
}

// The star of a blow `t` seconds after it lands on `at`, laid as
// draw_attack_prop lays it: its grip, the Impact sheet's centre, on the
// struck point; it swells at once, then shrinks, turns and fades.
attack_impact_star :: proc(renderer: ^Renderer, at: rl.Vector3, t: f64, seed: int) -> (grip, tip: rl.Vector3, texel, opacity: f32) {
	right, up := attack_screen_axes(renderer)
	p := f32(t/ATTACK_IMPACT_SECONDS)
	grow := f32(1.25) if p < 0.15 else 1-0.3*p
	spin := f32(seed%5)*0.4+p*0.6
	return at, at+up*math.cos(spin)+right*math.sin(spin), attack_texel(.Pilgrim)*grow, clamp((1-p)*3, 0, 1)
}

// A star of paper over the struck point, and paper bits thrown off it.
draw_attack_impact :: proc(renderer: ^Renderer, fx: ^Attack_Fx, at: rl.Vector3, t: f64, seed: int, star := true) {
	if t < 0 || t > ATTACK_SHARD_SECONDS || !attack_point_visible(renderer, at) { return }
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	if star && fx.outcome != .Missed && t < ATTACK_IMPACT_SECONDS {
		grip, tip, size, opacity := attack_impact_star(renderer, at, t, seed)
		draw_attack_prop(renderer, .Impact, grip, tip, size, opacity, attack_impact_tint(fx))
		// A guard takes it: the shield shows where the blow lands.
		if fx.outcome == .Absorbed { draw_tactical_shield(renderer, at-rl.Vector3{0, 0.5, 0}, f32(t/ATTACK_IMPACT_SECONDS)) }
	}
	p := f32(t/ATTACK_SHARD_SECONDS)
	shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
	for index in 0..<3 {
		angle := f32(seed*7+index*3)*1.9
		out := right*math.cos(angle)+rl.Vector3CrossProduct(right, up)*math.sin(angle)*0.4
		point := at+out*(0.45*p)+rl.Vector3{0, 0.35*p-0.9*p*p, 0}
		turn := p*9+f32(index)
		draw_attack_prop(renderer, shards[index], point, point+up*math.cos(turn)+right*math.sin(turn), texel, clamp((1-p)*2.5, 0, 1))
	}
}

draw_attack_swing :: proc(renderer: ^Renderer, fx: ^Attack_Fx, now: f64) {
	plan, ok := attack_swing_plan(renderer, fx)
	if !ok { return }
	texel := attack_texel(fx.character)
	passes := 2 if fx.kind == .Rake else 1
	for pass in 0..<passes {
		// The ghoul's second rake comes a moment later, with the other hand:
		// back the other way.
		shifted := fx^
		shifted.contact += ATTACK_RAKE_SECOND*f64(pass)
		shifted.start += ATTACK_RAKE_SECOND*f64(pass)
		swing := plan
		if pass == 1 { swing.start, swing.finish = plan.finish, plan.start }
		begin := attack_swing_begin(&shifted)
		end := shifted.contact+swing.follow
		if now < shifted.start || now > end+ATTACK_FADE_SECONDS { continue }
		fade := clamp(f32((end+ATTACK_FADE_SECONDS-now)/ATTACK_FADE_SECONDS), 0, 1)
		fade *= clamp(f32((now-(begin-0.04))/0.04), 0, 1)
		grip, tip: rl.Vector3
		if fx.kind == .Thrust { grip, tip = attack_thrust_pose(&shifted, &swing, now) }
		else { grip, tip = attack_swing_pose(&shifted, &swing, now) }
		if !attack_point_visible(renderer, tip) && !attack_point_visible(renderer, grip) { continue }
		// The smear: the tip's last tenth of a second, from the start of the blow.
		if now > begin {
			outer, inner: [10]rl.Vector3
			from := max(begin, now-0.11)
			for index in 0..<10 {
				at := from+(now-from)*f64(index)/9
				g, w: rl.Vector3
				if fx.kind == .Thrust { g, w = grip, grip+(tip-grip)*f32(0.4+0.6*f64(index)/9) }
				else { g, w = attack_swing_pose(&shifted, &swing, at) }
				outer[index] = w
				inner[index] = g+(w-g)*0.3
			}
			draw_attack_strip(renderer, outer[:], inner[:], fade*0.95)
			if fx.kind == .Rake {
				// Three talons, three smears.
				for offset in ([2]f32{-0.06, 0.06}) {
					o, i := outer, inner
					for index in 0..<10 { o[index].y += offset; i[index].y += offset }
					draw_attack_strip(renderer, o[:], i[:], fade*0.8)
				}
			}
		}
		draw_attack_prop(renderer, attack_look_prop(fx.look, now), grip, tip, texel, fade)
		// Each swept cell as the weapon passes it: a star on the struck card
		// (or before the struck object), paper bits off an empty cell.
		victim, _, standing := attack_card(renderer, fx.victim)
		struck_at, _ := attack_struck_point(renderer, fx.victim)
		for index in 0..<swing.count {
			passed := shifted.contact
			if fx.kind == .Swing {
				passed = attack_swing_passes(begin, shifted.contact, swing.follow, swing.start, swing.aim, swing.finish, swing.yaws[index])
				if passed < 0 { passed = shifted.contact }
			}
			cell := swing.cells[index]
			at := attack_cell_center(cell, 0.2)
			struck := standing && attack_board_cell(victim) == cell
			if struck { at = struck_at }
			draw_attack_impact(renderer, fx, at, now-passed, int(fx.id)+index+pass, struck && (pass == 0 || fx.kind == .Rake))
			if fx.kind == .Rake && fx.outcome == .Hit && struck && now >= passed && now-passed < 0.3 {
				right := flipbook_camera_right(renderer)
				draw_attack_prop(renderer, .Scratch, at-right*0.12+rl.Vector3{0, 0.1, 0}, at+right*0.12-rl.Vector3{0, 0.02, 0},
					texel*1.4, clamp(f32(1-(now-passed)/0.3)*2, 0, 1))
			}
		}
	}
}

draw_attack_projectile :: proc(renderer: ^Renderer, fx: ^Attack_Fx, now: f64) {
	if now < fx.contact { return }
	texel := attack_texel(fx.character)
	prop := attack_look_prop(fx.look, now)
	length := attack_prop_length(prop, texel)
	if now < fx.landing {
		u := f32((now-fx.contact)/max(fx.landing-fx.contact, 0.0001))
		point, heading := attack_flight_point(fx.origin, fx.target, fx.arc, u)
		if !attack_point_visible(renderer, point) { return }
		if fx.look == .Bomb {
			// A bomb tumbles as it flies.
			spin := f32(now*14)
			right := flipbook_camera_right(renderer)
			axis := rl.Vector3{0, 1, 0}*math.cos(spin)+right*math.sin(spin)
			draw_attack_prop(renderer, prop, point-axis*length*0.5, point+axis, texel, 1)
		} else {
			draw_attack_prop(renderer, prop, point-heading*length, point, texel, 1)
		}
		return
	}
	t := now-fx.landing
	_, heading := attack_flight_point(fx.origin, fx.target, fx.arc, 1)
	// A bomb and an ember burst where they land; a bolt stays there a moment,
	// under the star of its impact.
	if fx.look != .Bomb && fx.look != .Ember {
		switch fx.outcome {
		case .Hit:
			// Pinned in the struck card, then it drops away.
			if t < ATTACK_STUCK_SECONDS+0.2 {
				fall := f32(max(0, t-ATTACK_STUCK_SECONDS)/0.2)
				tip := fx.target+rl.Vector3{0, -0.35*fall*fall, 0}
				tail := tip-heading*length*0.7+rl.Vector3{0, 0.3*fall, 0}
				draw_attack_prop(renderer, prop, tail, tip, texel, 1-fall)
			}
		case .Absorbed:
			// It glances off the guard and spins away.
			if t < 0.3 {
				p := f32(t/0.3)
				point := fx.target-heading*(0.35*p)+rl.Vector3{0, 0.3*p-0.25*p*p, 0}
				spin := p*8
				axis := -heading*math.cos(spin)+rl.Vector3{0, math.sin(spin), 0}
				draw_attack_prop(renderer, prop, point-axis*length, point, texel, 1-p)
			}
		case .Missed:
			// Stuck in the floor where the target stood.
			if t < ATTACK_GROUNDED_SECONDS+0.2 && attack_point_visible(renderer, fx.target) {
				fade := clamp(f32((ATTACK_GROUNDED_SECONDS+0.2-t)/0.2), 0, 1)
				draw_attack_prop(renderer, prop, fx.target-heading*length, fx.target, texel, fade)
			}
		}
	}
	draw_attack_impact(renderer, fx, fx.target, t, int(fx.id))
}

// The board pass: one sorted entry per blow. A swung weapon shows over the
// cards it comes from and lands on; a bolt sorts where it is, in flight and
// once landed (stuck in the front of the struck card, or in the floor of a
// cell behind another card, which hides it).
collect_attack_fx_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	if !renderer.tactical.attack_props.loaded { return }
	camera := renderer.tactical.camera.position
	toward := attack_toward_camera(renderer)
	for &fx, index in renderer.tactical.attack_fx.items {
		if !fx.used { continue }
		at := attack_cell_center(fx.aim)
		if fx.kind == .Projectile {
			now := living_clock(renderer, fx.attacker)
			u := f32(clamp((now-fx.contact)/max(fx.landing-fx.contact, 0.0001), 0, 1))
			at, _ = attack_flight_point(fx.origin, fx.target, fx.arc, u)
		} else {
			nearest := false
			for entity in ([2]game.Entity_Ref{fx.attacker, fx.victim}) {
				position, ok := tactical_cue_actor_position(renderer, entity)
				if !ok { continue }
				card := rl.Vector3{position.x+0.5, 0, position.y+0.5}
				if !nearest || rl.Vector3Distance(card, camera) < rl.Vector3Distance(at, camera) { at, nearest = card, true }
			}
		}
		at += toward*0.3
		append(entries, Tactical_Alpha_Entry{kind = .Attack, position = {at.x-0.5, at.z-0.5}, attack = i32(index)})
	}
}

draw_attack_fx_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	state := &renderer.tactical.attack_fx
	if entry.attack < 0 || int(entry.attack) >= len(state.items) { return }
	fx := &state.items[entry.attack]
	if !fx.used { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	now := living_clock(renderer, fx.attacker)
	if fx.kind == .Projectile { draw_attack_projectile(renderer, fx, now) }
	else { draw_attack_swing(renderer, fx, now) }
}
