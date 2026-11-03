package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// BENVENUTI A NAPOLI's blow on the board (docs/piano-napoli.md, Fase 3, the
// user's choices of 2026-11-03). The club's blow lands as a cartoon's does:
//   - the struck foe's card squashes (JUICE_SQUASH_LOW of its height in
//     JUICE_SQUASH_DOWN, as wide as 1/sqrt of its height: the same volume),
//     stays flat JUICE_SQUASH_HOLD, then springs back up past its height
//     (JUICE_SQUASH_OVERSHOOT) and settles, all in JUICE_SQUASH_SECONDS; its
//     feet never leave the floor; only the picture: its cell and the rules
//     stay as they are;
//   - a killing blow flattens it like a pancake (JUICE_PANCAKE) and it stays so
//     as it falls;
//   - the pictures hold JUICE_CLUB's hold and the camera shakes its trauma,
//     paper bits off the foe, dust off the floor; a blow on the floor only a
//     little shake and its dust;
//   - a foe the club staggered has three paper stars going round over its head
//     while the Stagger lasts.

JUICE_CLUB :: Juice_Hit{hold = 0.09, trauma = 0.45, kick = 0, flash = 0.08}
// The club on the floor (and on a barrel, an ice block: a little more).
JUICE_CLUB_FLOOR_TRAUMA :: f32(0.15)
JUICE_CLUB_THING_TRAUMA :: f32(0.25)
JUICE_SQUASH_LOW :: f32(0.3)
JUICE_SQUASH_DOWN :: f32(0.06)
JUICE_SQUASH_HOLD :: f32(0.08)
JUICE_SQUASH_SECONDS :: f32(0.6)
JUICE_SQUASH_OVERSHOOT :: f32(1.12)
// The spring back: its first peak (the overshoot) this long after the hold.
JUICE_SQUASH_PEAK :: f32(0.14)
JUICE_PANCAKE :: f32(0.18)
// No card is drawn wider than this (a pancake's 1/sqrt would be 2.36).
JUICE_SQUASH_WIDEST :: f32(2)
JUICE_SQUASHES :: 8
JUICE_DAZED :: 8
// The stars: how many, how far round the head, how fast (turns a second), their size.
JUICE_STARS :: 3
JUICE_STAR_RING :: f32(0.3)
JUICE_STAR_TURNS :: f32(0.9)
JUICE_STAR_SIZE :: f32(0.085)
JUICE_STAR_COLOR :: rl.Color{255, 214, 64, 255}
JUICE_DUST :: rl.Color{176, 168, 152, 255}

// A struck card squashing since `at` (a pancake when it `stays`).
Juice_Squash :: struct {
	entity: game.Entity_Ref,
	at: f64,
	stays: bool,
}

// A foe the club staggered: its stars show while its Stagger lasts.
Juice_Dazed :: struct {
	entity: game.Entity_Ref,
	at: f64,
}

// The card's height and width (parts of its own) `t` seconds after the blow.
juice_squash_shape :: proc(t: f32, stays: bool) -> (height, width: f32) {
	if !(t >= 0) { return 1, 1 }
	ease := proc(u: f32) -> f32 { v := clamp(u, 0, 1); return 1-(1-v)*(1-v) }
	if stays {
		height = 1+(JUICE_PANCAKE-1)*ease(t/JUICE_SQUASH_DOWN)
	} else if t < JUICE_SQUASH_DOWN {
		height = 1+(JUICE_SQUASH_LOW-1)*ease(t/JUICE_SQUASH_DOWN)
	} else if t < JUICE_SQUASH_DOWN+JUICE_SQUASH_HOLD {
		height = JUICE_SQUASH_LOW
	} else if t < JUICE_SQUASH_SECONDS {
		// A damped spring from rest at the low: its first peak the overshoot.
		s := t-JUICE_SQUASH_DOWN-JUICE_SQUASH_HOLD
		wd := math.PI/JUICE_SQUASH_PEAK
		decay := -math.ln((JUICE_SQUASH_OVERSHOOT-1)/(1-JUICE_SQUASH_LOW))/JUICE_SQUASH_PEAK
		height = 1-(1-JUICE_SQUASH_LOW)*math.exp(-decay*s)*(math.cos(wd*s)+decay/wd*math.sin(wd*s))
	} else {
		return 1, 1
	}
	return height, min(1/math.sqrt(height), JUICE_SQUASH_WIDEST)
}

// How `entity`'s card is squashed now.
juice_squash :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (height, width: f32) {
	height, width = 1, 1
	if renderer == nil || entity == game.SYSTEM_ENTITY { return }
	now := renderer.sprite_assets.elapsed
	for squash in renderer.tactical.juice_blows.squashes {
		if squash.at <= 0 || squash.entity != entity { continue }
		t := f32(now-squash.at)
		if t < 0 || (!squash.stays && t >= JUICE_SQUASH_SECONDS) || t > 30 { continue }
		return juice_squash_shape(t, squash.stays)
	}
	return
}

// A card's corners squashed about `anchor` (its feet on the floor): `height`
// of their rise over it, `width` of their reach along `right`.
juice_squash_points :: proc(points: ^[4]rl.Vector3, anchor, right: rl.Vector3, height, width: f32) {
	for &point in points {
		d := point-anchor
		along := d.x*right.x+d.y*right.y+d.z*right.z
		flat := d-right*along
		point = anchor+right*(along*width)+rl.Vector3{flat.x, flat.y*height, flat.z}
	}
}

@(private)
juice_club_squash :: proc(b: ^Juice_Blows, entity: game.Entity_Ref, stays: bool, now: f64) {
	b.squashes[b.squash_next] = {entity = entity, at = now, stays = stays}
	b.squash_next = (b.squash_next+1)%JUICE_SQUASHES
}

// The club's blow on a foe, as its wound's cue lands (observe_juice_blows).
@(private)
juice_club_blow :: proc(renderer: ^Renderer, b: ^Juice_Blows, target: game.Entity_Ref, fells: bool, now: f64) {
	juice_shake(renderer, JUICE_CLUB.trauma)
	_ = juice_hit_stop(renderer, JUICE_CLUB.hold)
	b.kicks[b.kick_next] = {entity = target, flash = JUICE_CLUB.flash, at = now}
	b.kick_next = (b.kick_next+1)%JUICE_KICKS
	juice_club_squash(b, target, fells, now)
	if struck, found := attack_struck_point(renderer, target); found { juice_burst_at(b, struck, JUICE_PAPER, 14, u32(target.id)*31, now) }
	if at, found := tactical_cue_actor_position(renderer, target); found {
		juice_burst_at(b, {at.x+0.5, entity_point_ground(target, at)+0.08, at.y+0.5}, JUICE_DUST, 10, u32(target.id)*17+5, now)
	}
	b.clubs += 1
}

// The club's blow on the floor or on a thing (the rules' impact, which has no
// wound of a foe: follow_first_person_club).
@(private)
juice_club_floor :: proc(renderer: ^Renderer, impact: game.Club_Impact) {
	b := &renderer.tactical.juice_blows
	now := renderer.sprite_assets.elapsed
	juice_shake(renderer, JUICE_CLUB_THING_TRAUMA if impact.hit == .Object else JUICE_CLUB_FLOOR_TRAUMA)
	cell := impact.cell
	floor := cell_overlay_ground(cell)
	juice_burst_at(b, {f32(cell.x)+0.5, floor+0.06, f32(cell.y)+0.5}, JUICE_DUST, 9, u32(impact.number)*7919, now)
	if impact.hit == .Object { juice_burst_at(b, {f32(cell.x)+0.5, floor+0.45, f32(cell.y)+0.5}, JUICE_PAPER, 10, u32(impact.number)*131, now) }
}

// A foe the club has just staggered: its stars.
@(private)
juice_club_daze :: proc(renderer: ^Renderer, entity: game.Entity_Ref) {
	b := &renderer.tactical.juice_blows
	for &dazed in b.dazed {
		if dazed.entity == entity && dazed.at > 0 { dazed.at = renderer.sprite_assets.elapsed; return }
	}
	b.dazed[b.dazed_next] = {entity = entity, at = renderer.sprite_assets.elapsed}
	b.dazed_next = (b.dazed_next+1)%JUICE_DAZED
}

// Whether `actor` shows its stars now: one the club staggered, staggered still.
@(private)
juice_club_dazed :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> bool {
	if !actor.visible || actor.opacity <= 0 { return false }
	if _, staggered := game.status_index(&actor.statuses, .Stagger); !staggered { return false }
	for dazed in renderer.tactical.juice_blows.dazed { if dazed.at > 0 && dazed.entity == actor.entity { return true } }
	return false
}

// Whether the board shows `entity`'s stars now (the lab's smoke).
juice_club_shows_stars :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> bool {
	if renderer == nil || renderer.tactical.snapshot == nil { return false }
	v := &renderer.tactical
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] { if actor.entity == entity { return juice_club_dazed(renderer, &actor) } }
	return false
}

// The stars, in the board's 3D pass after the cards: each a five-pointed
// paper star, in ink, facing the camera, going round over the dazed head.
@(private)
draw_juice_dazed :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if v.snapshot == nil { return }
	shown := false
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] { shown = shown || juice_club_dazed(renderer, &actor) }
	if !shown { return }
	now := renderer.sprite_assets.elapsed
	camera := v.camera
	forward := rl.Vector3Normalize(camera.target-camera.position)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, {0, 1, 0}))
	up := rl.Vector3CrossProduct(right, forward)
	// As the paper bits are drawn (draw_juice_bursts): over the cards, no depth
	// written, so the board's resolve leaves their colours as they are.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthTest()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthTest() }
	star :: proc(at, right, up: rl.Vector3, outer, inner, turn: f32, color: rl.Color) {
		for k in 0..<5 {
			a := turn+f32(k)*math.TAU/5
			tip := at+(right*math.cos(a)+up*math.sin(a))*outer
			l := a-math.TAU/10
			r := a+math.TAU/10
			left := at+(right*math.cos(l)+up*math.sin(l))*inner
			rightp := at+(right*math.cos(r)+up*math.sin(r))*inner
			rl.DrawTriangle3D(at, left, tip, color)
			rl.DrawTriangle3D(at, tip, rightp, color)
		}
	}
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if !juice_club_dazed(renderer, &actor) { continue }
		cell_at, _ := living_card_position(renderer, actor.entity, sprite_key_for_enemy(actor.archetype), actor.position)
		height, _ := juice_squash(renderer, actor.entity)
		top := entity_point_ground(actor.entity, actor.position)+game.first_person_outline_top(actor.archetype)*height+0.16
		centre := rl.Vector3{cell_at.x+0.5, top, cell_at.y+0.5}
		for k in 0..<JUICE_STARS {
			a := f32(now)*JUICE_STAR_TURNS*math.TAU+f32(k)*math.TAU/JUICE_STARS
			at := centre+rl.Vector3{math.cos(a)*JUICE_STAR_RING, 0.04*math.sin(a*2), math.sin(a)*JUICE_STAR_RING}
			spin := f32(now)*3+f32(k)
			alpha := u8(255*clamp(actor.opacity, 0, 1))
			// The ink a little behind, then the paper star.
			star(at-forward*0.01, right, up, JUICE_STAR_SIZE*1.35, JUICE_STAR_SIZE*0.65, spin, {JUICE_INK.r, JUICE_INK.g, JUICE_INK.b, alpha})
			star(at, right, up, JUICE_STAR_SIZE, JUICE_STAR_SIZE*0.45, spin, {JUICE_STAR_COLOR.r, JUICE_STAR_COLOR.g, JUICE_STAR_COLOR.b, alpha})
		}
	}
}
