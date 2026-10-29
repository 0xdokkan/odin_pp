package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
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
// A landed punch (the user's choices, Fase 3): the drawing stops FISTS_HITSTOP
// seconds (the gloves hold, the struck card white), then the gloves catch up
// with the rules in FISTS_HITSTOP_CATCH; the rules never stop. The look jolts
// FIRST_PERSON_PUNCH_JOLT radians at most, twice that on a critical, fading in
// FIRST_PERSON_PUNCH_JOLT_SECONDS; a miss does nothing. The struck card's
// print goes white for the stop and fades in FIRST_PERSON_STRUCK_FADE.
FIRST_PERSON_HITSTOP :: f32(0.08)
FIRST_PERSON_HITSTOP_CATCH :: f32(0.12)
FIRST_PERSON_PUNCH_JOLT :: f32(0.008)
FIRST_PERSON_PUNCH_JOLT_SECONDS :: f32(0.16)
FIRST_PERSON_STRUCK_FADE :: f32(0.06)
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
	now := renderer.sprite_assets.elapsed
	// A punch landed since the last frame (the view's counts start over with
	// each view, and the first frame of one only takes them).
	hits := room.first_person.hits
	if f.engaged && hits > f.fists_hits_seen && f.fists_hits_seen >= 0 {
		f.fists_hit_at, f.fists_hit_crit, f.fists_struck = now, fists.crits > f.fists_crits_seen, fists.struck
		// A critical: the gold star bursts where its mark was (the struck mark
		// keeps its zone until the next lights).
		if f.fists_hit_crit {
			f.fists_star_at, f.fists_star_enemy, f.fists_star_zone = now, fists.struck, 1
			for mark in fists.marks { if mark.enemy_id == fists.struck { f.fists_star_zone = mark.zone } }
		}
	}
	f.fists_hits_seen, f.fists_crits_seen = hits, fists.crits
	since := f32(now-f.fists_hit_at) if f.fists_hit_at > 0 else max(f32)
	f.fists_punch, f.fists_clock = fists.punch, first_person_glove_display_clock(fists.punch_clock, since)
	f.fists_run = clamp(math.sqrt(fists.velocity.x*fists.velocity.x+fists.velocity.y*fists.velocity.y)/game.FISTS_SPEED, 0, 1)
}

// The clock the gloves are drawn at, `since` seconds after the last landed
// punch: held for the stop, then catching up with the rules' `clock`.
first_person_glove_display_clock :: proc(clock, since: f32) -> f32 {
	if since < 0 || since >= FIRST_PERSON_HITSTOP+FIRST_PERSON_HITSTOP_CATCH { return clock }
	lag := since if since < FIRST_PERSON_HITSTOP else FIRST_PERSON_HITSTOP*(1-(since-FIRST_PERSON_HITSTOP)/FIRST_PERSON_HITSTOP_CATCH)
	return max(0, clock-lag)
}

// How far the look is jolted `since` seconds after a landed punch (radians at most).
first_person_punch_shake :: proc(since: f32, critical: bool) -> f32 {
	if since < 0 || since >= FIRST_PERSON_PUNCH_JOLT_SECONDS { return 0 }
	fade := 1-since/FIRST_PERSON_PUNCH_JOLT_SECONDS
	return FIRST_PERSON_PUNCH_JOLT*(2 if critical else 1)*fade*fade
}

// How white the struck foe's print is now (0..1).
first_person_struck_flash :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	f := &renderer.tactical.first_person
	if f.weapon != .Fists || f.amount <= 0 || f.fists_hit_at <= 0 || entity != game.enemy_entity(f.fists_struck) { return 0 }
	since := f32(renderer.sprite_assets.elapsed-f.fists_hit_at)
	if since < 0 { return 0 }
	if since < FIRST_PERSON_HITSTOP { return 1 }
	return clamp(1-(since-FIRST_PERSON_HITSTOP)/FIRST_PERSON_STRUCK_FADE, 0, 1)
}

// The struck print over itself, added three times: its colours go white, its
// ink stays dark.
@(private)
draw_first_person_struck_flash :: proc(quad: Tactical_Billboard, flash: f32) {
	if quad.texture.id == 0 || flash <= 0 { return }
	uv := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	if quad.mirror { uv = {{1, 0}, {1, 1}, {0, 1}, {0, 0}} }
	rl.BeginBlendMode(.ADDITIVE)
	for _ in 0..<3 {
		rlgl.SetTexture(quad.texture.id)
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255, 255, 255, u8(clamp(flash, 0, 1)*255))
		for point, index in quad.points {
			rlgl.TexCoord2f((quad.source.x+uv[index].x*quad.source.width)/f32(quad.texture.width),
				(quad.source.y+uv[index].y*quad.source.height)/f32(quad.texture.height))
			rlgl.Vertex3f(point.x, point.y, point.z)
		}
		rlgl.End()
	}
	rlgl.SetTexture(0)
	rl.EndBlendMode()
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

// A mark (or the star) where the board shows it this frame: the world point on
// its zone of the foe's card at its chest, its zone, how long it stays lit.
First_Person_Mark_Point :: struct {
	point: rl.Vector3,
	zone: i8,
	lit: f32,
	shown: bool,
}

// The world point of `zone` across `enemy_id`'s card at its chest (as the rules
// cut the card), where this frame's camera sees it.
@(private = "file")
first_person_mark_world :: proc(renderer: ^Renderer, room: ^game.Room, enemy_id: u32, zone: i8) -> (point: rl.Vector3, ok: bool) {
	f := &renderer.tactical.first_person
	index, found := game.enemy_index_by_id(room, enemy_id)
	if !found { return }
	enemy := room.enemies[index]
	at := [2]f32{f32(enemy.position.x)+0.5, f32(enemy.position.y)+0.5}
	lift := f32(0)
	for card in f.cards[:f.card_count] {
		if card.enemy_id == enemy.id { at, lift = card.at, card.lift; break }
	}
	right := rl.Vector3{-math.sin(f.yaw), 0, math.cos(f.yaw)}
	across := [4]f32{-0.75, -0.25, 0.25, 0.75}
	top := game.first_person_outline_top(enemy.archetype)
	height := top*FIRST_PERSON_MARK_HEIGHT
	half := game.first_person_outline_half_width(enemy.archetype, height)
	offset := across[clamp(int(zone), 0, 3)]*half
	ground := entity_point_ground(game.enemy_entity(enemy.id), {at.x-0.5, at.y-0.5})
	point = {at.x+right.x*offset, ground+lift+height, at.y+right.z*offset}
	camera := renderer.tactical.camera
	look := rl.Vector3Normalize(camera.target-camera.position)
	return point, rl.Vector3DotProduct(point-camera.position, look) > 0.05
}

// After this frame's camera (frame_first_person_camera): where the lit marks
// and the star are.
@(private)
frame_first_person_marks :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	f.fists_marks, f.fists_star = {}, {}
	if !game.first_person_fists_active(room) { return }
	for mark, slot in room.first_person.fists.marks {
		if mark.enemy_id == 0 || mark.lit <= 0 { continue }
		point, ok := first_person_mark_world(renderer, room, mark.enemy_id, mark.zone)
		f.fists_marks[slot] = {point = point, zone = mark.zone, lit = mark.lit, shown = ok}
	}
	if since := f32(renderer.sprite_assets.elapsed-f.fists_star_at); f.fists_star_at > 0 && since >= 0 && since < FIRST_PERSON_STAR_SECONDS {
		point, ok := first_person_mark_world(renderer, room, f.fists_star_enemy, f.fists_star_zone)
		f.fists_star = {point = point, zone = f.fists_star_zone, shown = ok}
	}
}

// The gold star of a critical, `since` seconds after it (FIRST_PERSON_STAR_SECONDS
// in all): its size as a part of its full one (it bursts, holds, shrinks away),
// its turn, how far its sparks have flown (0..1, gone at 1).
FIRST_PERSON_STAR_SECONDS :: f32(0.5)
first_person_star :: proc(since: f32) -> (scale, turn, sparks: f32) {
	if since < 0 || since >= FIRST_PERSON_STAR_SECONDS { return 0, 0, 1 }
	if since < 0.12 {
		u := since/0.12
		scale = 1.25*(1-(1-u)*(1-u))
	} else if since < 0.18 {
		scale = 1.25-0.25*(since-0.12)/0.06
	} else if since < 0.34 {
		scale = 1
	} else {
		scale = 1-(since-0.34)/(FIRST_PERSON_STAR_SECONDS-0.34)
	}
	return scale, since*1.4, clamp(since/0.4, 0, 1)
}

// The lit marks on the small canvas of the gloves (`w` by `h`, the board's
// camera), before the gloves: neon rings of the punch's colour with a bright
// core and the punch's path inside (an arrow up for the jab and the cross, an
// arc for the hooks), blinking in their last third of a second; or (`star`,
// after the gloves, so the impact shows over the fist) the critical's star.
// The canvas' cut gives them the ink and the paper's band.
@(private)
draw_first_person_marks_pixel :: proc(renderer: ^Renderer, w, h: i32, star := false) {
	f := &renderer.tactical.first_person
	now := renderer.sprite_assets.elapsed
	camera := renderer.tactical.camera
	for mark in f.fists_marks {
		if star || !mark.shown { continue }
		if mark.lit < 0.33 && math.mod(now*8, 2) < 1 { continue }
		screen := rl.GetWorldToScreenEx(mark.point, camera, w, h)
		distance := max(f32(0.4), rl.Vector3Distance(mark.point, camera.position))
		radius := math.round(clamp(f32(h)*0.035/distance, 5, 11))
		draw_first_person_mark_pixel({math.round(screen.x), math.round(screen.y)}, radius, mark.zone)
	}
	if star && f.fists_star.shown {
		scale, turn, _ := first_person_star(f32(now-f.fists_star_at))
		screen := rl.GetWorldToScreenEx(f.fists_star.point, camera, w, h)
		distance := max(f32(0.4), rl.Vector3Distance(f.fists_star.point, camera.position))
		radius := clamp(f32(h)*0.06/distance, 8, 18)*scale
		if radius >= 2 { draw_first_person_star_pixel({math.round(screen.x), math.round(screen.y)}, radius, turn) }
	}
}

// The star's sparks, on the card already cut (`paper`, stored upside down):
// gold and white specks flying out of it.
@(private)
draw_first_person_star_sparks :: proc(renderer: ^Renderer, w, h: i32) {
	f := &renderer.tactical.first_person
	if !f.fists_star.shown { return }
	_, turn, flown := first_person_star(f32(renderer.sprite_assets.elapsed-f.fists_star_at))
	if flown >= 1 { return }
	camera := renderer.tactical.camera
	screen := rl.GetWorldToScreenEx(f.fists_star.point, camera, w, h)
	distance := max(f32(0.4), rl.Vector3Distance(f.fists_star.point, camera.position))
	reach := clamp(f32(h)*0.06/distance, 8, 18)*(0.8+2.0*flown)
	for k in 0..<7 {
		angle := turn*0.5+f32(k)*(2*math.PI/7)
		at := rl.Vector2{screen.x+math.cos(angle)*reach, f32(h)-(screen.y+math.sin(angle)*reach)}
		size := f32(2) if flown < 0.6 else 1
		rl.DrawRectangleV({math.round(at.x), math.round(at.y)}, {size, size}, (rl.Color{255, 246, 196, 255} if k%2 == 0 else rl.Color{255, 196, 48, 255}))
	}
}

@(private = "file")
draw_first_person_mark_pixel :: proc(at: rl.Vector2, radius: f32, zone: i8) {
	color := FIRST_PERSON_MARK_COLORS[clamp(int(zone), 0, 3)]
	core := rl.Color{u8((int(color.r)+255)/2), u8((int(color.g)+255)/2), u8((int(color.b)+255)/2), 255}
	rl.DrawRing(at, radius-2, radius, 0, 360, 28, color)
	rl.DrawRing(at, radius-1.5, radius-0.5, 0, 360, 28, core)
	inner := radius-3
	switch zone {
	case 1, 2:
		tail, tip := rl.Vector2{at.x, at.y+inner*0.75}, rl.Vector2{at.x, at.y-inner*0.6}
		rl.DrawLineEx(tail, tip, 1, core)
		rl.DrawTriangle(tip+{0, -2}, tip+{-2, 1}, tip+{2, 1}, color)
	case 0, 3:
		from := f32(200) if zone == 0 else -20
		to := f32(300) if zone == 0 else -120
		rl.DrawRing(at, inner*0.55-0.5, inner*0.55+0.5, min(from, to), max(from, to), 12, core)
		end := to*math.PI/180
		tip := at+rl.Vector2{math.cos(end), math.sin(end)}*(inner*0.55)
		rl.DrawRectangleV({math.round(tip.x)-1, math.round(tip.y)-1}, {2, 2}, color)
	}
}

// A five-pointed gold star of `radius` pixels turned `turn` radians, its
// light core a smaller star.
@(private = "file")
draw_first_person_star_pixel :: proc(at: rl.Vector2, radius, turn: f32) {
	star :: proc(at: rl.Vector2, radius, turn: f32, color: rl.Color) {
		points: [10]rl.Vector2
		for &point, k in points {
			r := radius if k%2 == 0 else radius*0.45
			angle := turn-math.PI/2+f32(k)*math.PI/5
			point = at+rl.Vector2{math.cos(angle), math.sin(angle)}*r
		}
		for k in 0..<10 { rl.DrawTriangle(at, points[(k+1)%10], points[k], color) }
	}
	star(at, radius, turn, {255, 196, 48, 255})
	star(at, radius*0.55, turn, {255, 240, 170, 255})
}

// Without the gloves' small canvas (no board surface): the marks straight on
// the view, as cached by frame_first_person_marks.
@(private)
draw_first_person_marks :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	f := &renderer.tactical.first_person
	if f.gloves.ready || !game.first_person_fists_active(room) { return }
	camera := renderer.tactical.camera
	for mark in f.fists_marks {
		if !mark.shown { continue }
		if mark.lit < 0.33 && math.mod(now*8, 2) < 1 { continue }
		screen := rl.GetWorldToScreenEx(mark.point, camera, i32(renderer.canvas_width), i32(renderer.canvas_height))
		distance := max(f32(0.4), rl.Vector3Distance(mark.point, camera.position))
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
