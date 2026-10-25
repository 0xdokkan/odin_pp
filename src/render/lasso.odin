package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// LAZZO on the board (game/lasso.odin), cut from paper like the cards and the
// props. The rope is a strip of paper pixel art drawn by code: two strands of
// hemp twisted together between two ink lines, inside a margin of white paper.
// During the card's throw (its Lasso_Caught cue, stretched over the cast) the
// open loop flies from the player's hand over the foe, drops round its waist
// and cinches with a twist; the foe's card is lifted off the board and pulled
// on a raised curve onto its ring. Then it flies round the player at
// LASSO_LIFT above the floor, where the room says it is (the spin records no
// event of its own: the board follows the room's angle every frame, as the
// shadow of Movimento Ombra), its rope trailing against the spin, while a
// faint dashed paper ring on the floor shows the radius (a smash's solid cells
// left out, red ticks where the swung foe will hit them). The player's card
// throws it in its cast (living_cue_action), then is the pivot: it channels
// and turns to follow the foe until the spin is too fast for it. Each hit
// flashes a paper star between the two cards (a smash, a star and paper puffs
// of stone dust at the wall), a full turn's 1 pops a small "-1" where it was.
// While a wide ring spins the camera stands back a little, so all of it shows
// between the HUD and the hand. When the rope goes it falls slack and the card
// drops to the floor: at once round a foe that died, and for one let go as the
// board shows what moved the player (his dodge, a push), MOLLATO over it as it
// falls. Nothing here gates gameplay or input.

// World units the swung card flies above the floor.
LASSO_LIFT :: f32(0.42)
// The card dropping to the floor once the rope is gone, and the MOLLATO over
// a foe let go, from the start of its fall.
LASSO_DROP_SECONDS :: f64(0.28)
LASSO_RELEASE_BADGE_SECONDS :: f64(0.6)
// The throw's moments, as shares of its cue: the loop flies to the foe, drops
// round it and cinches; the foe is lifted; it is pulled onto its ring.
LASSO_THROW_FLOWN :: f32(0.35)
LASSO_THROW_CINCHED :: f32(0.55)
LASSO_THROW_LIFTED :: f32(0.72)
// The rope strip's pixel art: its height (paper, ink, three rows of hemp,
// ink, paper) and the length of its repeat, in texels of the board's props.
LASSO_ROPE_TEXELS :: 7
LASSO_ROPE_TILE :: 12
LASSO_ROPE_POINTS :: 25
LASSO_ROPE_PIECES :: 6
LASSO_LOOP_POINTS :: 13
// The loop round the foe's waist: open as it flies, cinched once it is caught.
LASSO_LOOP_OPEN :: f32(0.42)
LASSO_LOOP_TIGHT :: f32(0.24)
LASSO_IMPACTS :: 8
LASSO_IMPACTS_SEEN :: 16
LASSO_IMPACT_SECONDS :: f64(0.42)
// The floor ring: texels a cell, its paper's opacity, its fades.
LASSO_RING_TEXELS :: GROUND_TEXELS
LASSO_RING_ALPHA :: f32(0.6)
LASSO_RING_FADE_SECONDS :: f64(0.3)
// Dashes along the floor ring, in its texels: a period and its paper.
LASSO_RING_DASH :: f32(18)
LASSO_RING_DASH_ON :: f32(12)
// The pivot turns to follow the foe at most this often, and holds his side
// once the foe goes round faster than this many turns a second.
LASSO_FACE_SECONDS :: f64(0.15)
LASSO_FACE_TURNS :: f32(3)
// While the widest ring spins the camera stands this share farther back and
// drops this share of its lead before the player (update_tactical_view), so
// the swung card shows whole between the HUD and the hand; it eases there
// and home at this pace (a second's rate).
LASSO_CAMERA_BACK :: f32(0.35)
LASSO_CAMERA_AIM :: f32(0.65)
LASSO_CAMERA_EASE :: f32(5)

LASSO_ROPE_LIGHT :: rl.Color{232, 208, 154, 255}
LASSO_ROPE_HEMP :: rl.Color{196, 158, 96, 255}
LASSO_ROPE_SHADE :: rl.Color{150, 112, 62, 255}
LASSO_ROPE_GROOVE :: rl.Color{104, 72, 38, 255}
LASSO_SMASH_RED :: rl.Color{196, 44, 44, 255}
LASSO_DUST :: rl.Color{158, 152, 144, 255}

// What makes a Lasso_Struck cue this one, whichever frame shows it.
Lasso_Cue_Key :: struct {
	batch: u32,
	source, target: game.Entity_Ref,
	amount: i32,
	cell: grid.Position,
}

Lasso_Impact :: struct {
	used, smash: bool,
	// Where it shows, and the ring cell it happened on (the fog asks that).
	at: rl.Vector3,
	cell: grid.Position,
	born: f64,
	seed: int,
}

Lasso_View :: struct {
	// The room's rope as last seen: it holds `enemy` round the player's cell
	// `centre` at `radius` (a walled first ring: `smash`), turning `direction`.
	active: bool,
	enemy: game.Entity_Ref,
	centre: grid.Position,
	radius: i32,
	smash: bool,
	direction: i32,
	// Where the rope caught the foe and the cell under it now; when the rope
	// came out (sprite clock), and the throw's progress (1: thrown).
	caught_from: view.Vec2,
	under: grid.Position,
	began: f64,
	throw: f32,
	spinning: bool,
	// The swung card now: its place on the board (the snapshot shows it
	// there) and how high it flies (world units); the angle round the player,
	// the turns and hits so far and the turns a second.
	at: view.Vec2,
	lift: f32,
	angle: f64,
	turns, hits: i32,
	turns_per_second: f32,
	// The rope gone (sprite clock): the card drops from `drop_from` (at
	// `drop_lift`) to `drop_to`, slack; `died` when its foe fell. A living foe
	// let go says MOLLATO from `released` on (0: none).
	ending, died: bool,
	ended, released: f64,
	drop_from, drop_to: view.Vec2,
	drop_lift: f32,
	// When the pivot last turned to follow it.
	faced: f64,
	// The camera's pull back for the ring (0..1, eased) and the sprite clock
	// it last moved at.
	frame: f32,
	framed: f64,
	impacts: [LASSO_IMPACTS]Lasso_Impact,
	impact_next: int,
	seen: [LASSO_IMPACTS_SEEN]Lasso_Cue_Key,
	seen_next: int,
	// The rope this frame (lasso_rope_geometry): its points, their sideways
	// half widths and the strip's length coordinate; the loop's two halves
	// (the one behind the foe, the one in front) the same way.
	rope: [LASSO_ROPE_POINTS]rl.Vector3,
	rope_side: [LASSO_ROPE_POINTS]rl.Vector3,
	rope_u: [LASSO_ROPE_POINTS]f32,
	loop: [2][LASSO_LOOP_POINTS]rl.Vector3,
	loop_side: [2][LASSO_LOOP_POINTS]rl.Vector3,
	loop_u: [2][LASSO_LOOP_POINTS]f32,
	loop_centre: rl.Vector3,
	rope_alpha: f32,
	rope_ready: bool,
	// The strip's texture, and the floor ring's (baked for `ring_key` when
	// `ring_baked`).
	rope_texture: rl.Texture2D,
	ring_texture: rl.Texture2D,
	ring_key: Lasso_Ring_Key,
	ring_baked: bool,
	// What the board has shown so far (the lab's sounds, the smoke and tests).
	spawned_hits, spawned_smashes, whirrs, releases, drops, throws: int,
}

// A fresh rope (or board): what was shown of the last one goes, the textures
// and the counts stay.
@(private)
lasso_view_reset :: proc(l: ^Lasso_View) {
	l^ = {rope_texture = l.rope_texture, ring_texture = l.ring_texture, ring_key = l.ring_key, ring_baked = l.ring_baked,
		spawned_hits = l.spawned_hits, spawned_smashes = l.spawned_smashes, whirrs = l.whirrs, releases = l.releases,
		drops = l.drops, throws = l.throws, seen = l.seen, seen_next = l.seen_next, frame = l.frame, framed = l.framed}
}

@(private)
destroy_lasso_view :: proc(renderer: ^Renderer) {
	l := &renderer.tactical.lasso
	if l.rope_texture.id != 0 { rl.UnloadTexture(l.rope_texture) }
	if l.ring_texture.id != 0 { rl.UnloadTexture(l.ring_texture) }
	l^ = {}
}

// The swung foe's place on the board at `angle`: round the centre of the
// player's cell, `radius` cells out (actor positions are cells' corners).
@(private)
lasso_orbit_point :: proc(centre: grid.Position, radius: i32, angle: f64) -> view.Vec2 {
	r := f64(radius)
	return {f32(f64(centre.x)+r*math.cos(angle)), f32(f64(centre.y)+r*math.sin(angle))}
}

// The swung card during the throw at `u` (0..1): standing where it was
// caught, lifted, then pulled on a raised curve onto its ring at `orbit`.
@(private)
lasso_throw_pose :: proc(from, orbit: view.Vec2, u: f32) -> (at: view.Vec2, lift: f32) {
	switch {
	case u < LASSO_THROW_CINCHED:
		return from, 0
	case u < LASSO_THROW_LIFTED:
		// Up with a little spring past the height it keeps.
		p := (u-LASSO_THROW_CINCHED)/(LASSO_THROW_LIFTED-LASSO_THROW_CINCHED)
		k := f32(1.7)
		w := p-1
		return from, LASSO_LIFT*(1+w*w*((k+1)*w+k))
	case u < 1:
		p := (u-LASSO_THROW_LIFTED)/(1-LASSO_THROW_LIFTED)
		e := p*p*(3-2*p)
		return {from.x+(orbit.x-from.x)*e, from.y+(orbit.y-from.y)*e}, LASSO_LIFT+0.22*math.sin(p*math.PI)
	}
	return orbit, LASSO_LIFT
}

// The snapshot's `entity` shown at `at` (the airborne card, or its fall).
@(private = "file")
lasso_override :: proc(renderer: ^Renderer, entity: game.Entity_Ref, at: view.Vec2) {
	snapshot := renderer.tactical.snapshot
	if actor, found := presentation_actor_in_view(snapshot, entity); found { actor.position = at }
}

// Once per frame, right after the shadow's (update_tactical_view, which may
// run twice a frame): follows the room's rope and shows the swung card where
// it flies; then the cues of its hits.
@(private)
update_tactical_lasso :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	l := &v.lasso
	if room == nil || room.player == nil || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	s := &room.lasso
	held := game.tactical_lasso_active(room)
	foe := game.enemy_entity(s.enemy_id)
	if held && (!l.active || l.enemy != foe) {
		lasso_view_reset(l)
		l.active, l.enemy = true, foe
		l.centre, l.radius, l.smash = s.centre, s.radius, s.smash
		l.caught_from = presentation_position(s.caught_from)
		l.began = now
		l.turns, l.hits = s.turns, s.hits
		l.throws += 1
	}
	if held {
		l.under = game.lasso_arc_cell(s, s.arc)
		if s.turns > l.turns { l.whirrs += int(s.turns-l.turns) }
		l.turns, l.hits, l.direction = s.turns, s.hits, s.direction
		l.angle = game.lasso_angle(s)
		l.turns_per_second = f32(1/game.lasso_turn_seconds(s.turns))
		l.spinning = s.started
		progress, throwing := shadow_cue_progress(renderer, .Lasso_Caught)
		l.throw = progress if throwing else 1
		orbit := lasso_orbit_point(l.centre, l.radius, l.angle)
		l.at, l.lift = lasso_throw_pose(l.caught_from, orbit, l.throw)
		// A little bob as it flies round.
		if l.throw >= 1 { l.lift += 0.03*f32(math.sin(2*l.angle)) }
		lasso_override(renderer, l.enemy, l.at)
		lasso_face_pivot(renderer, l, now)
	} else if l.active {
		// The rope is gone: let go (the foe lands where the room put it) or
		// slack round a foe that fell (on the cell under it). Let go, the card
		// hangs on the taut rope until the board shows what moved the player
		// (a brute's push still to land): then it falls, MOLLATO over it and
		// the rope's slack heard, as his dodge or his push plays.
		index, alive := game.enemy_index_by_id(room, l.enemy.id)
		if alive && lasso_release_waits(renderer, l.enemy) {
			lasso_override(renderer, l.enemy, l.at)
		} else {
			l.active, l.ending, l.ended = false, true, now
			l.drop_from, l.drop_lift = l.at, l.lift
			l.drop_to = {math.round(l.at.x), math.round(l.at.y)}
			if alive {
				l.drop_to = presentation_position(room.enemies[index].position)
				l.releases += 1
				l.released = now
			} else {
				l.died = true
			}
			l.drops += 1
		}
	}
	if !held && l.ending {
		u := f32(clamp((now-l.ended)/LASSO_DROP_SECONDS, 0, 1))
		if u >= 1 {
			l.ending, l.lift = false, 0
		} else {
			e := u*u
			l.at = {l.drop_from.x+(l.drop_to.x-l.drop_from.x)*e, l.drop_from.y+(l.drop_to.y-l.drop_from.y)*e}
			l.lift = l.drop_lift*(1-e)
			lasso_override(renderer, l.enemy, l.at)
		}
	}
	// The camera: back for a wide ring while the rope holds, home after.
	goal := f32(0)
	if held { goal = clamp(f32(l.radius-1)/f32(game.LASSO_MAX_RADIUS-1), 0, 1) }
	dt := f32(clamp(now-l.framed, 0, 0.25))
	l.framed = now
	l.frame += (goal-l.frame)*(1-math.exp(-LASSO_CAMERA_EASE*dt))
	observe_lasso_cues(renderer, now)
}

// Whether the board has yet to show what moved the player before the rope let
// `foe` go: his walk in the command of the release (its Lasso_Released cue)
// not begun, none of its steps started yet. His dodge is the foreground's
// first cue and starts with the next frame; a brute's push in the world's
// beat waits for its blow to land.
@(private)
lasso_release_waits :: proc(renderer: ^Renderer, foe: game.Entity_Ref) -> bool {
	batch, found := u32(0), false
	for offset in 0..<renderer_queued_cue_count(renderer) {
		cue, ok := renderer_queued_cue_at(renderer, offset)
		if ok && cue.kind == .Lasso_Released && cue.event.target == foe { batch, found = cue.batch, true }
	}
	if !found { return false }
	walks, begun := false, false
	note :: proc(cue: ^Presentation_Cue, batch: u32, walks, begun: ^bool) {
		if cue.batch != batch || cue.kind != .Move || cue.event.target != game.PLAYER_ENTITY { return }
		walks^ = true
		if cue.started { begun^ = true }
	}
	for offset in 0..<renderer_queued_cue_count(renderer) {
		if cue, ok := renderer_queued_cue_at(renderer, offset); ok { note(cue, batch, &walks, &begun) }
	}
	return walks && !begun
}

// MOLLATO over a foe the rope let go, from the start of its fall, on either
// board (its labels keep clear of what was placed before it). The release's
// own cue says nothing (draw_tactical_feedback_overlay, draw_presentation_cue).
@(private)
draw_lasso_release_badge :: proc(renderer: ^Renderer) {
	l := &renderer.tactical.lasso
	if l.released <= 0 || l.died || renderer.tactical.snapshot == nil { return }
	u := f32((renderer.sprite_assets.elapsed-l.released)/LASSO_RELEASE_BADGE_SECONDS)
	if u < 0 || u >= 1 { return }
	actor, found := presentation_actor_in_view(renderer.tactical.snapshot, l.enemy)
	if !found || !actor.visible { return }
	cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
	if !tactical_render_visible(renderer, cell) { return }
	draw_tactical_feedback_badge(renderer, {label = "MOLLATO", color = LASSO_ROPE_LIGHT, over = l.enemy, fallback = cell}, tactical_feedback_alpha(u))
}

// How far back the camera stands for the ring now (0: where it always is).
@(private)
lasso_camera_pull :: proc(renderer: ^Renderer) -> f32 {
	if renderer == nil { return 0 }
	return clamp(renderer.tactical.lasso.frame, 0, 1)
}

// The pivot turns to follow the foe round him, as fast as his card can turn.
@(private = "file")
lasso_face_pivot :: proc(renderer: ^Renderer, l: ^Lasso_View, now: f64) {
	if !l.spinning || l.turns_per_second > LASSO_FACE_TURNS || now-l.faced < LASSO_FACE_SECONDS { return }
	pivot := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	if pivot == nil { return }
	d := rl.Vector3{l.at.x-f32(l.centre.x), 0, l.at.y-f32(l.centre.y)}
	living_face(pivot, rl.Vector3DotProduct(d, flipbook_camera_right(renderer)), now)
	l.faced = now
}

// How high `entity`'s card flies on the rope now (world units; 0 for any
// other card): living_card_position lifts the card, its stand and all it
// carries (its heart, its tokens, the blows that reach it).
@(private)
tactical_lasso_lift :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	if renderer == nil { return 0 }
	// DINOSAURO: the player's card sits up on the saddle (arsenal.odin).
	if entity == game.PLAYER_ENTITY { return tactical_ride_lift(renderer) }
	l := &renderer.tactical.lasso
	if entity.kind != .Enemy || entity != l.enemy || !(l.active || l.ending) { return 0 }
	return max(f32(0), l.lift)
}

// The card the rope holds (or lets fall): no floor of its own under it.
@(private)
tactical_lasso_holds :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> bool {
	if renderer == nil { return false }
	l := &renderer.tactical.lasso
	return entity.kind == .Enemy && entity == l.enemy && (l.active || l.ending)
}

// While the rope holds, the player sees round him as far as it reaches: the
// ring's cells, where his foe flies, join the board's view (by the radius
// rule the ring holds no solid cell, but for a smash's ring beside him, whose
// walls are in sight anyway).
@(private)
lasso_extend_vision :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !game.tactical_lasso_active(room) { return }
	s := &room.lasso
	for arc in s.arcs[:s.arc_count] {
		cell := game.add_position(s.centre, arc.cell)
		if !grid.contains(&room.level_data.tiles, cell) { continue }
		known := false
		for seen in v.visible[:v.visible_count] { if seen == cell { known = true; break } }
		if known || v.visible_count >= len(v.visible) { continue }
		v.visible[v.visible_count] = cell
		v.visible_count += 1
	}
}

// A star for each perimeter hit on the struck card; an interior push has
// movement cues only. A smash is by the wall with stone dust.
@(private = "file")
observe_lasso_cues :: proc(renderer: ^Renderer, now: f64) {
	l := &renderer.tactical.lasso
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Lasso_Struck { continue }
		key := Lasso_Cue_Key{batch = cue.batch, source = cue.event.source, target = cue.event.target, amount = cue.event.amount, cell = cue.event.to_position}
		seen := false
		for previous in l.seen { if previous == key && key.batch != 0 { seen = true; break } }
		if seen { continue }
		l.seen[l.seen_next] = key
		l.seen_next = (l.seen_next+1)%len(l.seen)
		smash := cue.event.target == game.SYSTEM_ENTITY
		at := attack_cell_center(cue.event.to_position, 0.5)
		if swung, ok := attack_struck_point(renderer, cue.event.source); ok {
			at = swung
			if smash {
				wall := attack_cell_center(cue.event.to_position, swung.y)
				at = swung+(wall-swung)*0.42
			} else if struck, hit := attack_struck_point(renderer, cue.event.target); hit {
				at = struck
			}
			// In front of the cards (a wall on the camera's side: no further
			// than its face), or their paper would hide it.
			toward := attack_toward_camera(renderer)
			way := rl.Vector3{at.x-swung.x, 0, at.z-swung.z}
			facing := f32(0)
			if rl.Vector3Length(way) > 0.001 { facing = max(f32(0), rl.Vector3DotProduct(rl.Vector3Normalize(way), toward)) }
			at += toward*(0.38*(1-facing) if smash else 0.3)
		}
		l.impacts[l.impact_next] = {used = true, smash = smash, at = at, cell = cue.event.from_position, born = now, seed = int(cue.event.amount)*7+cue.event.to_position.x*3+cue.event.to_position.y}
		l.impact_next = (l.impact_next+1)%len(l.impacts)
		if smash { l.spawned_smashes += 1 } else { l.spawned_hits += 1 }
	}
}

// --------------------------------------------------------------------------
// The rope.

// A texel of the rope strip at column `x`, row `y`: white paper at the edges,
// an ink line inside them, and two strands of hemp twisting between, their
// grooves running across.
@(private = "file")
lasso_rope_texel :: proc(x, y: int) -> rl.Color {
	switch y {
	case 0, LASSO_ROPE_TEXELS-1: return LIVING_TOKEN_PAPER
	case 1, LASSO_ROPE_TEXELS-2: return LIVING_TOKEN_INK
	}
	row := y-2
	t := ((x+row)%6+6)%6
	underside := row == 2
	switch {
	case t == 0: return LASSO_ROPE_GROOVE
	case t <= 2: return LASSO_ROPE_HEMP if underside else LASSO_ROPE_LIGHT
	}
	return LASSO_ROPE_SHADE if underside else LASSO_ROPE_HEMP
}

@(private = "file")
lasso_rope_texture :: proc(l: ^Lasso_View) -> rl.Texture2D {
	if l.rope_texture.id != 0 { return l.rope_texture }
	image := rl.GenImageColor(LASSO_ROPE_TILE, LASSO_ROPE_TEXELS, rl.BLANK)
	defer rl.UnloadImage(image)
	for y in 0..<LASSO_ROPE_TEXELS {
		for x in 0..<LASSO_ROPE_TILE { rl.ImageDrawPixel(&image, c.int(x), c.int(y), lasso_rope_texel(x, y)) }
	}
	l.rope_texture = rl.LoadTextureFromImage(image)
	if l.rope_texture.id != 0 {
		rl.SetTextureFilter(l.rope_texture, .POINT)
		rl.SetTextureWrap(l.rope_texture, .REPEAT)
	}
	return l.rope_texture
}

// The size of one texel of the rope, the props' own.
@(private = "file")
lasso_texel :: proc() -> f32 {
	return attack_texel(.Pilgrim)
}

// The sideways half widths of a strip through `points` (camera-facing, across
// the strip on screen) and its length coordinate (in repeats).
@(private = "file")
lasso_strip_sides :: proc(renderer: ^Renderer, points: []rl.Vector3, sides: []rl.Vector3, us: []f32, closed: bool, start_u: f32 = 0) {
	camera := renderer.tactical.camera
	view_dir := rl.Vector3Normalize(camera.target-camera.position)
	half := f32(LASSO_ROPE_TEXELS)*lasso_texel()*0.5
	tile := f32(LASSO_ROPE_TILE)*lasso_texel()
	n := len(points)
	u := start_u
	for index in 0..<n {
		before := points[max(index-1, 0)]
		after := points[min(index+1, n-1)]
		if closed && index == 0 { before = points[n-2] if n > 2 else points[0] }
		tangent := after-before
		side := rl.Vector3CrossProduct(tangent, view_dir)
		if rl.Vector3Length(side) < 0.00001 { side = flipbook_camera_right(renderer) }
		sides[index] = rl.Vector3Normalize(side)*half
		if index > 0 { u += rl.Vector3Distance(points[index], points[index-1])/tile }
		us[index] = u
	}
}

// The rope's points this frame, from the player's hand to the knot on the
// loop, and the loop round the foe (or flying open to it): its shape follows
// the throw, the spin (it trails against it, sagging when slow) and its end
// (slack, fading).
@(private = "file")
lasso_rope_geometry :: proc(renderer: ^Renderer) -> bool {
	l := &renderer.tactical.lasso
	l.rope_ready = false
	if !(l.active || l.ending) { return false }
	pfeet, pheight, pfound := attack_card(renderer, game.PLAYER_ENTITY)
	ffeet, fheight, ffound := attack_card(renderer, l.enemy)
	if !pfound || !ffound { return false }
	right := flipbook_camera_right(renderer)
	up := rl.Vector3{0, 1, 0}
	side := f32(1)
	if pivot := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); pivot != nil && pivot.facing_left { side = -1 }
	hand := pfeet+up*(pheight*0.55)+right*(0.16*side)
	waist := ffeet+up*(fheight*0.42)
	// The loop: flying open over the foe, dropping round its waist, cinched.
	u := l.throw if l.active else 1
	centre, radius := waist, LASSO_LOOP_TIGHT
	twist := f32(0)
	if u < LASSO_THROW_FLOWN {
		p := u/LASSO_THROW_FLOWN
		head := ffeet+up*(fheight*1.08)
		centre = hand+(head-hand)*(p*(2-p))+up*(0.5*math.sin(p*math.PI))
		radius = LASSO_LOOP_OPEN*(0.6+0.4*p)
	} else if u < LASSO_THROW_CINCHED {
		p := (u-LASSO_THROW_FLOWN)/(LASSO_THROW_CINCHED-LASSO_THROW_FLOWN)
		head := ffeet+up*(fheight*1.08)
		centre = head+(waist-head)*(p*p)
		radius = LASSO_LOOP_OPEN+(LASSO_LOOP_TIGHT-LASSO_LOOP_OPEN)*(p*p*(3-2*p))
		twist = p*math.PI*0.9
	}
	l.loop_centre = centre
	// The knot faces the hand, give or take the cinch's twist.
	toward := math.atan2(hand.z-centre.z, hand.x-centre.x)+twist
	knot := centre+rl.Vector3{math.cos(toward), 0, math.sin(toward)}*radius
	// The rope from the hand to the knot: a quadratic curve, its middle
	// pulled up while it flies, trailing the spin, sagging when slack.
	length := rl.Vector3Distance(hand, knot)
	middle := (hand+knot)*0.5
	l.rope_alpha = 1
	if l.active {
		if u < LASSO_THROW_FLOWN {
			middle += up*(length*0.18)
		} else if l.spinning {
			// Against the spin: the foe's way round is direction*(-sin, cos).
			a := f32(l.angle)
			motion := rl.Vector3{-math.sin(a), 0, math.cos(a)}*f32(l.direction)
			lag := clamp(0.06+0.025*l.turns_per_second, 0, 0.3)
			middle += -motion*(length*lag)-up*(length*0.1/(1+l.turns_per_second))
		} else {
			middle -= up*(length*0.04)
		}
	} else {
		// Slack: it droops to the floor and fades as the card falls.
		p := f32(clamp((renderer.sprite_assets.elapsed-l.ended)/LASSO_DROP_SECONDS, 0, 1))
		middle -= up*(length*(0.12+0.45*p))
		middle.y = max(middle.y, 0.04)
		l.rope_alpha = 1-p
	}
	for index in 0..<LASSO_ROPE_POINTS {
		t := f32(index)/f32(LASSO_ROPE_POINTS-1)
		a, b, w := (1-t)*(1-t), 2*t*(1-t), t*t
		l.rope[index] = hand*a+middle*b+knot*w
	}
	lasso_strip_sides(renderer, l.rope[:], l.rope_side[:], l.rope_u[:], false)
	// The loop's halves, behind the foe's card and in front of it, from the
	// knot round.
	camera := renderer.tactical.camera
	face := math.atan2(camera.position.z-centre.z, camera.position.x-centre.x)
	for half in 0..<2 {
		start := face+math.PI*0.5 if half == 0 else face-math.PI*0.5
		for index in 0..<LASSO_LOOP_POINTS {
			angle := start+f32(index)/f32(LASSO_LOOP_POINTS-1)*math.PI
			// Behind it the loop rides a little higher: it is seen from above.
			l.loop[half][index] = centre+rl.Vector3{math.cos(angle)*radius, 0, math.sin(angle)*radius}
		}
		lasso_strip_sides(renderer, l.loop[half][:], l.loop_side[half][:], l.loop_u[half][:], false, f32(half)*7)
	}
	l.rope_ready = true
	return true
}

// The rope's pieces, the loop's two halves and the hits' stars, sorted with
// the cards and walls (one entry each): the rope passes behind a card or in
// front of it as it really does.
@(private)
collect_lasso_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	l := &renderer.tactical.lasso
	if lasso_rope_geometry(renderer) {
		per := (LASSO_ROPE_POINTS-1)/LASSO_ROPE_PIECES
		for piece in 0..<LASSO_ROPE_PIECES {
			mid := l.rope[piece*per+per/2]
			append(entries, Tactical_Alpha_Entry{kind = .Lasso, lasso = i32(piece), position = {mid.x-0.5, mid.z-0.5}})
		}
		toward := attack_toward_camera(renderer)
		for half in 0..<2 {
			at := l.loop_centre+toward*(0.22 if half == 1 else -0.22)
			append(entries, Tactical_Alpha_Entry{kind = .Lasso, lasso = i32(LASSO_ROPE_PIECES+half), position = {at.x-0.5, at.z-0.5}})
		}
	}
	now := renderer.sprite_assets.elapsed
	for impact, index in l.impacts {
		if !impact.used || now-impact.born > LASSO_IMPACT_SECONDS { continue }
		append(entries, Tactical_Alpha_Entry{kind = .Lasso, lasso = i32(LASSO_ROPE_PIECES+2+index),
			position = {impact.at.x-0.5+attack_toward_camera(renderer).x*0.4, impact.at.z-0.5+attack_toward_camera(renderer).z*0.4}})
	}
}

@(private)
draw_lasso_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	l := &renderer.tactical.lasso
	piece := int(entry.lasso)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	if piece < LASSO_ROPE_PIECES {
		if !l.rope_ready { return }
		per := (LASSO_ROPE_POINTS-1)/LASSO_ROPE_PIECES
		first := piece*per
		last := LASSO_ROPE_POINTS-1 if piece == LASSO_ROPE_PIECES-1 else first+per
		draw_lasso_strip(renderer, l.rope[first:last+1], l.rope_side[first:last+1], l.rope_u[first:last+1], l.rope_alpha)
		return
	}
	if piece < LASSO_ROPE_PIECES+2 {
		if !l.rope_ready { return }
		half := piece-LASSO_ROPE_PIECES
		draw_lasso_strip(renderer, l.loop[half][:], l.loop_side[half][:], l.loop_u[half][:], l.rope_alpha)
		return
	}
	index := piece-LASSO_ROPE_PIECES-2
	if index >= 0 && index < len(l.impacts) { draw_lasso_impact(renderer, &l.impacts[index]) }
}

// One stretch of the rope strip: its texels on the camera-facing quads
// between the points.
@(private = "file")
draw_lasso_strip :: proc(renderer: ^Renderer, points, sides: []rl.Vector3, us: []f32, alpha: f32) {
	if len(points) < 2 || alpha <= 0.01 { return }
	l := &renderer.tactical.lasso
	texture := lasso_rope_texture(l)
	if texture.id == 0 { return }
	rlgl.SetTexture(texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, u8(clamp(alpha, 0, 1)*255))
	for index in 0..<len(points)-1 {
		a, b := points[index], points[index+1]
		sa, sb := sides[index], sides[index+1]
		ua, ub := us[index], us[index+1]
		corners := [4]rl.Vector3{a+sa, a-sa, b-sb, b+sb}
		uv := [4][2]f32{{ua, 0}, {ua, 1}, {ub, 1}, {ub, 0}}
		for corner, k in corners {
			rlgl.TexCoord2f(uv[k].x, uv[k].y)
			rlgl.Vertex3f(corner.x, corner.y, corner.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// A hit's paper star between the two cards (red), or a smash's at the wall
// (stone grey) with dust; paper bits thrown off either.
@(private = "file")
draw_lasso_impact :: proc(renderer: ^Renderer, impact: ^Lasso_Impact) {
	t := renderer.sprite_assets.elapsed-impact.born
	if !impact.used || t < 0 || t > LASSO_IMPACT_SECONDS || !tactical_render_visible(renderer, impact.cell) { return }
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	if t < ATTACK_IMPACT_SECONDS {
		grip, tip, size, opacity := attack_impact_star(renderer, impact.at, t, impact.seed)
		draw_attack_prop(renderer, .Impact, grip, tip, size*(1.25 if impact.smash else 1.1), opacity, LASSO_DUST if impact.smash else LASSO_SMASH_RED)
	}
	p := f32(t/LASSO_IMPACT_SECONDS)
	shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
	for index in 0..<3 {
		angle := f32(impact.seed*5+index*3)*1.9
		out := right*math.cos(angle)+rl.Vector3CrossProduct(right, up)*math.sin(angle)*0.4
		point := impact.at+out*(0.5*p)+rl.Vector3{0, 0.32*p-0.9*p*p, 0}
		turn := p*9+f32(index)
		draw_attack_prop(renderer, shards[index], point, point+up*math.cos(turn)+right*math.sin(turn), texel, clamp((1-p)*2.5, 0, 1))
	}
	if !impact.smash { return }
	// Stone dust off the wall: paper puffs of grey that rise, spread, swell,
	// turn a little and thin out.
	for index in 0..<7 {
		angle := f32(index)*math.TAU/7+f32(impact.seed%5)*0.5
		out := right*math.cos(angle)+up*(0.35*math.sin(angle))
		point := impact.at+out*(0.12+0.38*p)+up*(0.18*p)
		puff := gfx.Attack_Prop.Dust_A if index%2 == 0 else gfx.Attack_Prop.Dust_B
		turn := (f32(index%3)-1)*0.35+p*0.5*(1 if index%2 == 0 else -1)
		swell := texel*(0.9+0.25*f32(index%3))*(1+0.8*p)
		draw_attack_prop(renderer, puff, point, point+up*math.cos(turn)+right*math.sin(turn), swell, clamp((1-p)*1.6, 0, 1)*0.9)
	}
}

// --------------------------------------------------------------------------
// The floor ring.

// The ring's arcs over solid cells (a smash's walls), as the bake needs them.
@(private = "file")
lasso_ring_solids :: proc(room: ^game.Room, centre: grid.Position, radius: i32) -> (solid: [game.LASSO_MAX_RING_CELLS]bool, arcs: [game.LASSO_MAX_RING_CELLS]game.Lasso_Arc, count: int) {
	arcs, count = game.lasso_ring(radius)
	for arc, index in arcs[:count] { solid[index] = game.lasso_cell_is_solid(room, game.add_position(centre, arc.cell)) }
	return
}

// The floor ring's pixels (RGBA rows, (2r+1) cells of LASSO_RING_TEXELS a
// side, centred on the player's cell): a dashed pixel circle at the ring's
// radius, two texels of paper between an ink texel on each side; the arcs over
// solid cells left out, with red ticks where a free arc meets a solid one.
@(private)
lasso_ring_pixels :: proc(radius: i32, arcs: []game.Lasso_Arc, solid: []bool, allocator := context.allocator) -> (pixels: []u8, size: int) {
	if radius < 1 || len(arcs) == 0 || len(solid) < len(arcs) { return }
	T := f32(LASSO_RING_TEXELS)
	size = (2*int(radius)+1)*LASSO_RING_TEXELS
	pixels = make([]u8, size*size*4, allocator)
	half := f32(size)*0.5
	r := f32(radius)
	put :: proc(pixels: []u8, size, x, y: int, colour: rl.Color) {
		if x < 0 || y < 0 || x >= size || y >= size { return }
		at := (y*size+x)*4
		pixels[at], pixels[at+1], pixels[at+2], pixels[at+3] = colour.r, colour.g, colour.b, colour.a
	}
	for y in 0..<size {
		for x in 0..<size {
			u, w := (f32(x)+0.5-half)/T, (f32(y)+0.5-half)/T
			e := abs(math.sqrt(u*u+w*w)-r)*T
			if e > 2 { continue }
			theta := game.lasso_wrap(f64(math.atan2(w, u)))
			if index, _ := game.lasso_locate(arcs, theta); solid[index] { continue }
			if math.mod(f32(theta)*r*T, LASSO_RING_DASH) >= LASSO_RING_DASH_ON { continue }
			put(pixels, size, x, y, LIVING_TOKEN_PAPER if e <= 1 else LIVING_TOKEN_INK)
		}
	}
	for arc, index in arcs {
		next := (index+1)%len(arcs)
		if solid[index] == solid[next] { continue }
		edge := arc.to
		for k in -4..=4 {
			reach := r*T+f32(k)
			px := half+reach*f32(math.cos(edge))
			py := half+reach*f32(math.sin(edge))
			for dy in 0..<2 { for dx in 0..<2 { put(pixels, size, int(px)+dx, int(py)+dy, LASSO_SMASH_RED) } }
		}
	}
	return
}

// What a floor ring's bake is of: its centre and radius and which of its arcs
// lie over solid cells (one bit an arc: the widest ring has 32).
Lasso_Ring_Key :: struct {
	centre: grid.Position,
	radius: i32,
	solid: u64,
}

@(private)
lasso_ring_key :: proc(centre: grid.Position, radius: i32, solid: []bool) -> (key: Lasso_Ring_Key) {
	#assert(game.LASSO_MAX_RING_CELLS <= 64)
	key.centre, key.radius = centre, radius
	for value, index in solid[:min(len(solid), game.LASSO_MAX_RING_CELLS)] { if value { key.solid |= u64(1)<<u64(index) } }
	return
}

// The ring under the spin, in the 3D pass after the ground's decal: one quad
// on the floor, depth kept and never written. It fades in as the foe reaches
// its ring and out once the rope is gone.
@(private)
draw_lasso_ring :: proc(renderer: ^Renderer, room: ^game.Room) {
	l := &renderer.tactical.lasso
	if room == nil || !(l.active || l.ending) || l.radius < 1 { return }
	now := renderer.sprite_assets.elapsed
	alpha := LASSO_RING_ALPHA
	if l.active {
		alpha *= clamp((l.throw-LASSO_THROW_LIFTED)/(1-LASSO_THROW_LIFTED), 0, 1)
	} else {
		alpha *= 1-f32(clamp((now-l.ended)/LASSO_RING_FADE_SECONDS, 0, 1))
	}
	if alpha <= 0.01 { return }
	solid, arcs, count := lasso_ring_solids(room, l.centre, l.radius)
	key := lasso_ring_key(l.centre, l.radius, solid[:count])
	if !l.ring_baked || l.ring_texture.id == 0 || l.ring_key != key {
		l.ring_baked = false
		pixels, size := lasso_ring_pixels(l.radius, arcs[:count], solid[:count], context.temp_allocator)
		if size == 0 { return }
		if l.ring_texture.id != 0 { rl.UnloadTexture(l.ring_texture); l.ring_texture = {} }
		image := rl.Image{data = raw_data(pixels), width = c.int(size), height = c.int(size), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		l.ring_texture = rl.LoadTextureFromImage(image)
		if l.ring_texture.id == 0 { return }
		rl.SetTextureFilter(l.ring_texture, .POINT)
		rl.SetTextureWrap(l.ring_texture, .CLAMP)
		l.ring_key, l.ring_baked = key, true
	}
	r := f32(l.radius)
	x0, z0 := f32(l.centre.x)-r, f32(l.centre.y)-r
	x1, z1 := f32(l.centre.x)+r+1, f32(l.centre.y)+r+1
	height := GROUND_DECAL_HEIGHT+0.002
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	rlgl.SetTexture(l.ring_texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, u8(alpha*255))
	rlgl.TexCoord2f(0, 0); rlgl.Vertex3f(x0, height, z0)
	rlgl.TexCoord2f(0, 1); rlgl.Vertex3f(x0, height, z1)
	rlgl.TexCoord2f(1, 1); rlgl.Vertex3f(x1, height, z1)
	rlgl.TexCoord2f(1, 0); rlgl.Vertex3f(x1, height, z0)
	rlgl.End()
	rlgl.SetTexture(0)
}

// The card's aim: paper and ink dashes projected `radius` cells around
// `centre`, with arcs over solid cells left out.
@(private = "file")
draw_lasso_projected_ring :: proc(renderer: ^Renderer, room: ^game.Room, centre: grid.Position, radius: i32, alpha: f32) {
	if room == nil || radius < 1 || alpha <= 0.01 { return }
	solid, arcs, count := lasso_ring_solids(room, centre, radius)
	if count == 0 { return }
	c := rl.Vector2{f32(centre.x)+0.5, f32(centre.y)+0.5}
	r := f32(radius)
	segments := 12*int(radius)
	for index in 0..<segments {
		if index%3 == 2 { continue }
		a, b := f32(index)*math.TAU/f32(segments), f32(index+1)*math.TAU/f32(segments)
		if arc, _ := game.lasso_locate(arcs[:count], f64(a+b)*0.5); solid[arc] { continue }
		p := tactical_project(renderer, {c.x+r*math.cos(a), c.y+r*math.sin(a)}, 0.03)
		q := tactical_project(renderer, {c.x+r*math.cos(b), c.y+r*math.sin(b)}, 0.03)
		rl.DrawLineEx(to_raylib(p), to_raylib(q), 4, color_with_opacity(LIVING_TOKEN_INK, 0.75*alpha))
		rl.DrawLineEx(to_raylib(p), to_raylib(q), 2, color_with_opacity(LIVING_TOKEN_PAPER, 0.9*alpha))
	}
}

// --------------------------------------------------------------------------
// The card's aim (draw_card_target_details).

LASSO_AIM_LINE :: rl.Color{232, 196, 128, 235}
LASSO_AIM_HOT :: rl.Color{255, 232, 168, 255}

// While the Lazzo is aimed: the ring it would spin on (its cells, red with a cross
// where the foe would smash, orange where it would strike a foe) and, for
// the foe under the mouse, the cell the
// spin starts on and its way round.
@(private)
draw_lasso_preview :: proc(renderer: ^Renderer, room: ^game.Room, card: game.Card_Instance) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil { return }
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found { return }
	centre := room.player.position
	radius, smash := game.lasso_radius(room, centre)
	arcs, count := game.lasso_ring(radius)
	for arc in arcs[:count] {
		cell := game.add_position(centre, arc.cell)
		if !grid.contains(&room.level_data.tiles, cell) { continue }
		if game.lasso_cell_is_solid(room, cell) {
			draw_card_range_cell(renderer, cell, {190, 68, 70, 70}, {255, 112, 102, 255})
			if tactical_render_visible(renderer, cell) {
				p := cell_center(renderer, cell)
				k := max(f32(3), 5*renderer.overlay_scale)
				rl.DrawLineEx({p.x-k, p.y-k*0.5}, {p.x+k, p.y+k*0.5}, 2, {255, 112, 102, 255})
				rl.DrawLineEx({p.x-k, p.y+k*0.5}, {p.x+k, p.y-k*0.5}, 2, {255, 112, 102, 255})
			}
		} else if _, other := game.enemy_index_at(room, cell); other {
			draw_card_range_cell(renderer, cell, {238, 150, 60, 80}, {250, 176, 92, 255})
		} else {
			draw_card_range_cell(renderer, cell, {196, 158, 96, 72}, LASSO_AIM_LINE)
		}
	}
	draw_lasso_projected_ring(renderer, room, centre, radius, 1)
	hovered_cell := renderer.hovered_cell
	for enemy in room.enemies {
		if game.enemy_is_lassoed(room, enemy.id) || !tactical_render_visible(renderer, enemy.position) { continue }
		evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, enemy.position))
		if evaluation.error != .None { continue }
		hot := renderer.has_hovered_cell && hovered_cell == enemy.position
		// The foe itself is marked by the general "can be hit" mark (card_hit_mark.odin).
		if !hot { continue }
		// Where the spin starts, and its way round (counter-clockwise).
		state: game.Lasso_State
		state.centre = centre
		state.radius, state.smash = radius, smash
		state.arcs, state.arc_count = arcs, count
		angle := math.atan2(f64(enemy.position.y-centre.y), f64(enemy.position.x-centre.x))
		start, _ := game.lasso_locate(arcs[:count], angle)
		if game.lasso_cell_is_solid(room, game.lasso_arc_cell(&state, start)) {
			start, _ = game.lasso_nearest_free_arc(room, &state, start, -1)
		}
		start_cell := game.lasso_arc_cell(&state, start)
		draw_card_range_cell(renderer, start_cell, {74, 196, 133, 90}, {123, 235, 169, 255})
		draw_lasso_spin_arrow(renderer, centre, radius, arcs[start])
	}
}

// A chevron on the ring past the start, pointing the spin's way.
@(private = "file")
draw_lasso_spin_arrow :: proc(renderer: ^Renderer, centre: grid.Position, radius: i32, arc: game.Lasso_Arc) {
	r := f32(radius)
	c := rl.Vector2{f32(centre.x)+0.5, f32(centre.y)+0.5}
	at := f32((arc.from+arc.to)*0.5)-0.35/r
	point :: proc(renderer: ^Renderer, c: rl.Vector2, r, angle: f32) -> rl.Vector2 {
		p := tactical_project(renderer, {c.x+r*math.cos(angle), c.y+r*math.sin(angle)}, 0.03)
		return {p.x, p.y}
	}
	tip := point(renderer, c, r, at)
	back := point(renderer, c, r, at+0.3/r)
	inner := point(renderer, c, r-0.18, at+0.3/r)
	outer := point(renderer, c, r+0.18, at+0.3/r)
	rl.DrawLineEx(back, tip, 3, {123, 235, 169, 255})
	rl.DrawLineEx(inner, tip, 3, {123, 235, 169, 255})
	rl.DrawLineEx(outer, tip, 3, {123, 235, 169, 255})
}

// What would let the rope go now: a dodge (the controller takes Shift only in
// the window, the dodge ready), the defence prompt's dodge while one is
// offered, or why none can be made yet: a prompt without one, the window's
// end, a stun, the dodge recharging (`wait`: its beats, as the dodge's chip
// counts them).
Lasso_Let_Go :: enum {Dodge, Prompt_Dodge, Prompt, Recovery, Stunned, Recharging}

@(private)
lasso_let_go :: proc(room: ^game.Room) -> (way: Lasso_Let_Go, wait: int) {
	if room.qte.kind != .None { return .Prompt_Dodge if room.qte.kind == .Defense && .Dodge in room.qte.defenses else .Prompt, 0 }
	if game.tactical_is_stunned(room) { return .Stunned, 0 }
	if game.tactical_is_recovering(room) { return .Recovery, 0 }
	if !game.tactical_dodge_ready(room) {
		return .Recharging, max(0, room.player.tactical.dodge_recovery-(1 if room.tactical_pulse.pending else 0))
	}
	return .Dodge, 0
}

// The HUD's line while the rope holds (draw_tactical_hud): its hits, the next
// one's number and what lets it go. It holds whole beside the plate's short
// objective (the rope's NEMICI n, tactical_hud_objective) with two figures
// each and a full room.
lasso_hud_status :: proc(room: ^game.Room) -> cstring {
	s := &room.lasso
	way, wait := lasso_let_go(room)
	return lasso_hud_line(s.hits, game.lasso_next_hit(s), way, wait)
}

lasso_hud_line :: proc(hits, next: i32, way: Lasso_Let_Go, wait: int) -> cstring {
	switch way {
	case .Dodge, .Prompt_Dodge: return fmt.ctprintf("LAZZO: COLPI %d / PROSSIMO %d / SCHIVA: LO MOLLI", hits, next)
	case .Prompt: return fmt.ctprintf("LAZZO: COLPI %d / PROSSIMO %d / DIFESA", hits, next)
	case .Recovery: return fmt.ctprintf("LAZZO: COLPI %d / PROSSIMO %d / IN RECUPERO", hits, next)
	case .Stunned: return fmt.ctprintf("LAZZO: COLPI %d / PROSSIMO %d / STORDITO", hits, next)
	case .Recharging: return fmt.ctprintf("LAZZO: COLPI %d / PROSSIMO %d / SCHIVA FRA %d", hits, next, wait)
	}
	return ""
}

// The hand's hint while the rope holds (draw_tactical_hand): the dodge that
// lets it go, only while one can be made.
@(private)
lasso_hand_hint :: proc(room: ^game.Room) -> cstring {
	way, wait := lasso_let_go(room)
	switch way {
	case .Dodge: return "LAZZO / SHIFT+WASD: LO MOLLI"
	case .Prompt_Dodge: return "LAZZO / E, POI WASD: LO MOLLI"
	case .Prompt: return "LAZZO / DIFESA"
	case .Recovery: return "LAZZO / IN RECUPERO"
	case .Stunned: return "LAZZO / STORDITO"
	case .Recharging: return fmt.ctprintf("LAZZO / SCHIVA FRA %d", wait)
	}
	return ""
}
