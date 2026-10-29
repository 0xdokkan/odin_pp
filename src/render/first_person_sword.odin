package render

import "core:math"
import rl "vendor:raylib"
import game "../game"

// FIRST PERSON FENCER behind his eyes (game/first_person_sword.odin): the view
// looks the way the rules face, turning a quarter in FIRST_PERSON_SWORD_TURN
// seconds when Q or E turns them, level (the mouse is the blade's). The
// prototype's look until its art in Fase 5 (the user's choice: simple, in the
// gloves' paper pixels): the blade a Neon strip from the hilt low on the
// right to its point, a magenta guard across it, drawn on the gloves' small
// canvas so it gets their ink and paper; behind a swing a ribbon along the
// point's last positions, coloured by how good the cut would be (grey, white,
// gold), flaring the colour of the cut it made.

FIRST_PERSON_SWORD_TURN :: f64(0.15)
FIRST_PERSON_SWORD_TRAIL :: 8
// Seconds the trail stays after a swing, and a cut's colour flares.
FIRST_PERSON_SWORD_TRAIL_FADE :: f64(0.18)

// What the board keeps of the sword each frame its view is on.
First_Person_Sword_View :: struct {
	// The blade's point (screen heights), its speed, and the swing: whether
	// on, where it started, how far it has gone.
	tip: [2]f32,
	speed: f32,
	swinging: bool,
	start: [2]f32,
	length: f32,
	// The last cut and the counts of cuts, parries and grapples seen.
	last: game.Sword_Strike,
	strikes, parries, perfect_parries, grapples: i32,
	// The point's last positions while swinging (newest last), when the
	// swing ended and when the last cut landed (sprite clock).
	trail: [FIRST_PERSON_SWORD_TRAIL][2]f32,
	trail_count: int,
	ended_at, cut_at: f64,
	// The sprite clock at the last frame followed (the turn's pace).
	seen_at: f64,
}

@(private)
follow_first_person_sword :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	v := &f.sword
	now := renderer.sprite_assets.elapsed
	dt := clamp(now-v.seen_at, 0, 0.1)
	v.seen_at = now
	if !game.first_person_sword_active(room) { return }
	s := &room.first_person.sword
	if s.strikes != v.strikes { v.cut_at = now }
	if v.swinging && !s.swing.active { v.ended_at = now }
	if !v.swinging && s.swing.active { v.trail_count = 0 }
	v.tip, v.speed, v.swinging, v.start, v.length, v.last = s.tip, s.speed, s.swing.active, s.swing.start, s.swing.length, s.last
	v.strikes, v.parries, v.perfect_parries, v.grapples = s.strikes, s.parries, s.perfect_parries, s.grapples
	if v.swinging {
		if v.trail_count == FIRST_PERSON_SWORD_TRAIL {
			copy(v.trail[:], v.trail[1:])
			v.trail_count -= 1
		}
		v.trail[v.trail_count] = v.tip
		v.trail_count += 1
	}
	// The view turns toward the rules' facing, a quarter in FIRST_PERSON_SWORD_TURN, level.
	if !f.engaged { return }
	target := game.first_person_yaw(s.facing)
	gap := first_person_wrap(target-f.yaw)
	step := f32(math.PI/2*dt/FIRST_PERSON_SWORD_TURN)
	f.yaw = target if abs(gap) <= step else first_person_wrap(f.yaw+(step if gap > 0 else -step))
	f.pitch = 0
}

// How good the swing on now would cut (0..1): the formula's speed, breadth
// and line, as far as they are known before the cut.
first_person_sword_quality :: proc(v: ^First_Person_Sword_View) -> f32 {
	strike := game.sword_strike_damage(v.speed, v.length, v.start, v.tip, 0.75)
	return strike.speed*strike.breadth*strike.line
}

// The trail's colour for a quality: grey, white, gold.
@(private = "file")
first_person_sword_trail_color :: proc(quality: f32) -> rl.Color {
	if quality >= 0.75 { return {255, 206, 72, 255} }
	if quality >= 0.35 { return {236, 240, 250, 255} }
	return {128, 132, 150, 255}
}

// The blade and its trail on the gloves' small canvas (`w` by `h`), the guard
// `ready` 0..1 rising from under the view as it comes in.
@(private)
draw_first_person_sword_pixel :: proc(renderer: ^Renderer, w, h: i32, ready: f32) {
	v := &renderer.tactical.first_person.sword
	now := renderer.sprite_assets.elapsed
	lift := (1-ready)*0.6
	at :: proc(p: [2]f32, w, h: i32, lift: f32) -> rl.Vector2 {
		return {f32(w)*0.5+p.x*f32(h), f32(h)*0.5-(p.y-lift)*f32(h)}
	}
	hilt := game.SWORD_HILT
	// The trail: a ribbon along the point's last places, thinning to the oldest.
	trail := v.swinging || now-v.ended_at < FIRST_PERSON_SWORD_TRAIL_FADE
	if trail && v.trail_count >= 2 {
		color := first_person_sword_trail_color(first_person_sword_quality(v))
		if now-v.cut_at < FIRST_PERSON_SWORD_TRAIL_FADE {
			color = first_person_sword_trail_color(1 if v.last.perfect else (0.5 if v.last.damage >= 3 else 0))
		}
		for k in 0..<v.trail_count-1 {
			thick := max(f32(1), f32(h)*0.022*f32(k+1)/f32(v.trail_count))
			rl.DrawLineEx(at(v.trail[k], w, h, lift), at(v.trail[k+1], w, h, lift), thick, color)
		}
	}
	// The blade: a cyan Neon strip with a white core, narrowing to the point.
	base, point := at(hilt, w, h, lift), at(v.tip, w, h, lift)
	way := point-base
	length := math.sqrt(way.x*way.x+way.y*way.y)
	if length < 1 { return }
	side := rl.Vector2{-way.y, way.x}/length
	width := f32(h)*0.018
	rl.DrawTriangle(base+side*width, point, base-side*width, {60, 240, 255, 255})
	rl.DrawTriangle(base-side*width, point, base+side*width, {60, 240, 255, 255})
	rl.DrawTriangle(base+side*width*0.4, point, base-side*width*0.4, {214, 252, 255, 255})
	rl.DrawTriangle(base-side*width*0.4, point, base+side*width*0.4, {214, 252, 255, 255})
	// The guard across it near the hilt, magenta, and the grip below.
	guard := base+way*0.12
	rl.DrawLineEx(guard+side*width*3, guard-side*width*3, width*1.2, {255, 64, 206, 255})
	rl.DrawLineEx(base, base-way/length*width*4, width*1.6, {44, 34, 84, 255})
}
