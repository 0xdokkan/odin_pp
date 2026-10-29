package render

import "core:math"
import rl "vendor:raylib"
import tween "../engine/tween"
import game "../game"

// FIRST PERSON BRAWLER behind his eyes (game/first_person_fists.odin), the
// prototype's simple look until its art in Fase 3 (docs/piano-prima-persona.md):
// the eye rides the free body, not his cell's glide, and slides back to his
// cell's centre in FIRST_PERSON_FISTS_SETTLE seconds as the view ends; the
// gloves are first_person_gloves.odin's; a lit critical mark is a ring of its
// punch's colour on its side of the foe's card at its chest, with the punch's
// own path in it (straight for the jab and the cross, an arc for the hooks):
// colour and shape both, read without telling colours apart.

FIRST_PERSON_FISTS_SETTLE :: f64(0.15)
// The eye a little behind the body (a foe at a punch's reach stays whole in
// view, its body's marks within the pitch's limit), never into a solid cell;
// and a wider view than the AK's.
FIRST_PERSON_FISTS_EYE_BACK :: f32(0.35)
FIRST_PERSON_FISTS_FOV :: f32(80)
// The marks' colours by zone: the left hook, the jab, the cross, the right hook.
@(rodata)
FIRST_PERSON_MARK_COLORS := [4]rl.Color{{255, 150, 40, 255}, {80, 220, 255, 255}, {255, 222, 70, 255}, {238, 92, 222, 255}}

// The eye on the board behind his eyes with the fists: over the body, its feet's
// height above his cell's floor; as the view ends it slides to the centre of his
// cell (`cell`: the snapshot's position, a cell's corner).
@(private)
first_person_fists_eye :: proc(renderer: ^Renderer, room: ^game.Room, cell: [2]f32) -> (eye: rl.Vector3, ok: bool) {
	f := &renderer.tactical.first_person
	if f.weapon != .Fists || room == nil { return }
	now := renderer.sprite_assets.elapsed
	centre := [2]f32{cell.x+0.5, cell.y+0.5}
	body, lift, behind := f.fists_body, f.fists_lift, FIRST_PERSON_FISTS_EYE_BACK
	if !f.engaged {
		// Settling, the step behind the body goes too.
		u := tween.smoothstep(f32(clamp((now-f.changed)/FIRST_PERSON_FISTS_SETTLE, 0, 1)))
		body, lift, behind = body+(centre-body)*u, lift*(1-u), behind*(1-u)
	}
	ground := entity_point_ground(game.PLAYER_ENTITY, {body.x-0.5, body.y-0.5})
	back := [2]f32{-math.cos(f.yaw), -math.sin(f.yaw)}
	for k := 0; k < 4; k += 1 {
		step := behind*(1-f32(k)/3)
		at := body+back*step
		cell := room.player.position
		cell.x, cell.y = int(math.floor(at.x)), int(math.floor(at.y))
		if step <= 0 || !game.lasso_cell_is_solid(room, cell) {
			body = at
			break
		}
	}
	return {body.x, game.FIRST_PERSON_EYE_HEIGHT+ground+lift, body.y}, true
}

// What the board keeps of the body each frame the fists' view is on.
@(private)
follow_first_person_fists :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	if !game.first_person_fists_active(room) { return }
	fists := &room.first_person.fists
	f.fists_body = fists.body
	f.fists_lift = (fists.feet-f32(game.cell_height(room, room.player.position)))*game.HEIGHT_STEP_DRAWN
	f.fists_punch, f.fists_clock = fists.punch, fists.punch_clock
	f.fists_run = clamp(math.sqrt(fists.velocity.x*fists.velocity.x+fists.velocity.y*fists.velocity.y)/game.FISTS_SPEED, 0, 1)
}

// How far out a glove is, 0 at rest .. 1 landed: out over the punch's `land`
// seconds, back over most of what is left of its `recover`.
first_person_glove_reach :: proc(punch: game.First_Person_Punch, clock: f32) -> f32 {
	rules := game.FISTS_PUNCHES[punch]
	if punch == .None || rules.land <= 0 { return 0 }
	if clock <= rules.land { return tween.smoothstep(clamp(clock/rules.land, 0, 1)) }
	back := max(rules.recover-rules.land, 0.01)*0.7
	return 1-tween.smoothstep(clamp((clock-rules.land)/back, 0, 1))
}

// The lit marks on the foes' cards: a ring of the punch's colour on its zone
// across the card, the punch's path inside; blinking in its last third of a
// second. Only a help: the punch it asks is a critical anywhere on the foe.
@(private)
draw_first_person_marks :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	if !game.first_person_fists_active(room) { return }
	f := &renderer.tactical.first_person
	camera := renderer.tactical.camera
	right := rl.Vector3{-math.sin(f.yaw), 0, math.cos(f.yaw)}
	look := rl.Vector3Normalize(camera.target-camera.position)
	across := [4]f32{-0.75, -0.25, 0.25, 0.75}
	for mark in room.first_person.fists.marks {
		if mark.enemy_id == 0 || mark.lit <= 0 { continue }
		if mark.lit < 0.33 && math.mod(now*8, 2) < 1 { continue }
		index, found := game.enemy_index_by_id(room, mark.enemy_id)
		if !found { continue }
		enemy := room.enemies[index]
		at := [2]f32{f32(enemy.position.x)+0.5, f32(enemy.position.y)+0.5}
		lift := f32(0)
		for card in f.cards[:f.card_count] {
			if card.enemy_id == enemy.id { at, lift = card.at, card.lift; break }
		}
		top := game.first_person_outline_top(enemy.archetype)
		height := top*FIRST_PERSON_MARK_HEIGHT
		half := game.first_person_outline_half_width(enemy.archetype, height)
		offset := across[clamp(int(mark.zone), 0, 3)]*half
		ground := entity_point_ground(game.enemy_entity(enemy.id), {at.x-0.5, at.y-0.5})
		point := rl.Vector3{at.x+right.x*offset, ground+lift+height, at.y+right.z*offset}
		if rl.Vector3DotProduct(point-camera.position, look) <= 0.05 { continue }
		screen := rl.GetWorldToScreenEx(point, camera, i32(renderer.canvas_width), i32(renderer.canvas_height))
		distance := max(f32(0.4), rl.Vector3Distance(point, camera.position))
		radius := clamp(renderer.canvas_height*0.035/distance, 7, 30)
		draw_first_person_mark(screen, radius, mark.zone)
	}
}

// One mark: an ink ring round its colour's ring, and the punch's path: an
// arrow straight up for the jab and the cross, an arc into the middle for the
// hooks (from the left for the left hook, from the right for the right).
@(private = "file")
draw_first_person_mark :: proc(at: rl.Vector2, radius: f32, zone: i8) {
	color := FIRST_PERSON_MARK_COLORS[clamp(int(zone), 0, 3)]
	ink := LIVING_TOKEN_INK
	thick := max(f32(2), radius*0.22)
	rl.DrawRing(at, radius-thick-1, radius+1, 0, 360, 32, ink)
	rl.DrawRing(at, radius-thick, radius, 0, 360, 32, color)
	inner := radius-thick*1.6
	switch zone {
	case 1, 2:
		tail, tip := rl.Vector2{at.x, at.y+inner*0.7}, rl.Vector2{at.x, at.y-inner*0.7}
		rl.DrawLineEx(tail, tip, thick+2, ink)
		rl.DrawLineEx(tail, tip, thick, color)
		rl.DrawTriangle(tip+{0, -thick}, tip+{-thick*1.2, thick}, tip+{thick*1.2, thick}, color)
	case 0, 3:
		from := f32(200) if zone == 0 else -20
		to := f32(300) if zone == 0 else -120
		rl.DrawRing(at, inner*0.55-1, inner*0.55+thick*0.6+1, min(from, to), max(from, to), 16, ink)
		rl.DrawRing(at, inner*0.55, inner*0.55+thick*0.6, min(from, to), max(from, to), 16, color)
		end := to*math.PI/180
		tip := at+rl.Vector2{math.cos(end), math.sin(end)}*(inner*0.55+thick*0.3)
		rl.DrawCircleV(tip, thick*0.8, color)
	}
}
