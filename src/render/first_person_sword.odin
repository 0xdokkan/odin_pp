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
// gold), flaring the colour of the cut it made. A cut shows at once (the
// user's ask after trying it): a streak of blood across the chest it cut, the
// way the blade went, longer the harder it was, drops flying off it; what made
// it stronger in words beside it (a spinning cut, a lunge, a perfect cut:
// first_person_sword_words), the trail magenta from the moment a turn spins
// the swing; the
// struck foe's print white a moment, the blade held still FIRST_PERSON_SWORD_STOP
// at the cut, the look jolted as a punch's (twice for a perfect cut).

FIRST_PERSON_SWORD_TURN :: f64(0.15)
FIRST_PERSON_SWORD_TRAIL :: 8
// Seconds the trail stays after a swing, and a cut's colour flares.
FIRST_PERSON_SWORD_TRAIL_FADE :: f64(0.18)
// A cut's stop of the blade on the board, its blood's life, the struck print's flash.
FIRST_PERSON_SWORD_STOP :: f64(0.06)
FIRST_PERSON_SWORD_BLOOD :: f64(0.5)
FIRST_PERSON_SWORD_BLOOD_DROPS :: 7
// The cut's words: how long they show and how far they rise (screen heights).
FIRST_PERSON_SWORD_WORDS :: f64(0.8)
FIRST_PERSON_SWORD_WORDS_RISE :: f32(0.08)
// The trail of a spinning swing (Q or E turned the way it sweeps).
FIRST_PERSON_SWORD_SPIN_COLOR :: rl.Color{255, 64, 206, 255}

// What the board keeps of the sword each frame its view is on.
First_Person_Sword_View :: struct {
	// The blade's point (screen heights), its speed, and the swing: whether
	// on, where it started, how far it has gone.
	tip: [2]f32,
	speed: f32,
	swinging: bool,
	start: [2]f32,
	length: f32,
	// A spinning swing (its trail magenta), a lunging one.
	spin, lunge: bool,
	// The last cut and the counts of cuts, parries and grapples seen.
	last: game.Sword_Strike,
	strikes, parries, perfect_parries, grapples: i32,
	// The point's last positions while swinging (newest last), when the
	// swing ended and when the last cut landed (sprite clock).
	trail: [FIRST_PERSON_SWORD_TRAIL][2]f32,
	trail_count: int,
	ended_at, cut_at: f64,
	// Where the point was as the last cut landed (the blade is held there a moment).
	cut_tip: [2]f32,
	// The sprite clock at the last frame followed (the turn's pace).
	seen_at: f64,
	// When the last parry was, and whether it was perfect.
	parry_at: f64,
	parry_perfect: bool,
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
	if s.strikes != v.strikes { v.cut_at, v.cut_tip = now, s.tip }
	if s.parries != v.parries { v.parry_at, v.parry_perfect = now, s.perfect_parries != v.perfect_parries }
	if v.swinging && !s.swing.active { v.ended_at = now }
	if !v.swinging && s.swing.active { v.trail_count = 0 }
	v.tip, v.speed, v.swinging, v.start, v.length, v.last = s.tip, s.speed, s.swing.active, s.swing.start, s.swing.length, s.last
	v.spin, v.lunge = s.swing.spin, s.swing.lunge
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

// The point as the board draws it: held at the last cut for FIRST_PERSON_SWORD_STOP,
// then back to where the mouse has it.
first_person_sword_shown_tip :: proc(v: ^First_Person_Sword_View, now: f64) -> [2]f32 {
	since := now-v.cut_at
	if v.cut_at <= 0 || since < 0 || since >= FIRST_PERSON_SWORD_STOP*2 { return v.tip }
	if since < FIRST_PERSON_SWORD_STOP { return v.cut_tip }
	u := f32((since-FIRST_PERSON_SWORD_STOP)/FIRST_PERSON_SWORD_STOP)
	return v.cut_tip+(v.tip-v.cut_tip)*u
}

// A perfect parry flashes the blade white for FIRST_PERSON_SWORD_PARRY_FLASH.
FIRST_PERSON_SWORD_PARRY_FLASH :: f64(0.08)
first_person_sword_parry_flash :: proc(v: ^First_Person_Sword_View, now: f64) -> bool {
	return v.parry_perfect && v.parry_at > 0 && now >= v.parry_at && now-v.parry_at < FIRST_PERSON_SWORD_PARRY_FLASH
}

// The blood of the last cut, `since` seconds on: how long its streak is (a
// part of its full length: it opens in 0.05 s, then thins away), how far its
// drops have flown (0..1).
first_person_sword_blood :: proc(since: f64) -> (streak, flown: f32) {
	if since < 0 || since >= FIRST_PERSON_SWORD_BLOOD { return 0, 1 }
	t := f32(since/FIRST_PERSON_SWORD_BLOOD)
	streak = clamp(f32(since/0.05), 0, 1)*(1-t*t)
	return streak, t
}

// The words of what made `strike` stronger (nil: nothing did).
first_person_sword_words :: proc(strike: game.Sword_Strike) -> cstring {
	switch {
	case strike.spin && strike.lunge: return "ROTEANTE x1,5 + AFFONDO"
	case strike.spin: return "COLPO ROTEANTE x1,5"
	case strike.lunge: return "AFFONDO x1,25"
	case strike.perfect: return "TAGLIO PERFETTO"
	}
	return nil
}

// The last cut's words over the view, by the chest it cut, rising and fading
// in FIRST_PERSON_SWORD_WORDS (the HUD, over the gloves' canvas).
@(private)
draw_first_person_sword_words :: proc(renderer: ^Renderer) {
	v := &renderer.tactical.first_person.sword
	since := renderer.sprite_assets.elapsed-v.cut_at
	words := first_person_sword_words(v.last)
	if words == nil || v.cut_at <= 0 || since < 0 || since >= FIRST_PERSON_SWORD_WORDS { return }
	u := f32(since/FIRST_PERSON_SWORD_WORDS)
	w, h := renderer.canvas_width, renderer.canvas_height
	at := [2]f32{w*0.5+v.last.chest.x*h, h*0.5-(v.last.chest.y+0.12+FIRST_PERSON_SWORD_WORDS_RISE*u)*h}
	size := 20
	width := gothic_text_width(renderer, words, size)
	x := clamp(at.x-width*0.5, 8, w-width-8)
	alpha := 1-max(0, u-0.6)/0.4
	color := (rl.Color{255, 214, 80, 255} if !v.last.spin else rl.Color{255, 96, 214, 255})
	gothic_text(renderer, words, x+2, at.y+2, size, color_with_opacity(LIVING_TOKEN_INK, alpha))
	gothic_text(renderer, words, x, at.y, size, color_with_opacity(color, alpha))
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
	// The last cut's blood across the chest it cut, under the blade.
	if v.cut_at > 0 && v.last.enemy_id != 0 {
		streak, flown := first_person_sword_blood(now-v.cut_at)
		if streak > 0 {
			way := v.last.along
			length := math.sqrt(way.x*way.x+way.y*way.y)
			if length > 0 { way /= length } else { way = {1, 0} }
			half := clamp(f32(v.last.damage)*0.025, 0.08, 0.3)*streak
			centre := v.last.chest
			a, b := at(centre-way*half, w, h, lift), at(centre+way*half, w, h, lift)
			rl.DrawLineEx(a, b, max(f32(2), f32(h)*0.02*streak), {150, 12, 24, 255})
			rl.DrawLineEx(a, b, max(f32(1), f32(h)*0.009*streak), {230, 48, 52, 255})
		}
		if flown < 1 {
			way := v.last.along
			length := math.sqrt(way.x*way.x+way.y*way.y)
			if length > 0 { way /= length } else { way = {1, 0} }
			side := [2]f32{-way.y, way.x}
			for k in 0..<FIRST_PERSON_SWORD_BLOOD_DROPS {
				spread := f32(k)/f32(FIRST_PERSON_SWORD_BLOOD_DROPS-1)-0.5
				out := way*(0.06+0.22*flown*(0.6+0.4*f32((k*5)%3)/2))+side*spread*0.12*flown
				// They fall as they fly.
				out.y -= 0.25*flown*flown
				drop := at(v.last.chest+out, w, h, lift)
				size := f32(2) if flown < 0.6 else 1
				rl.DrawRectangleV({math.round(drop.x), math.round(drop.y)}, {size, size}, {200, 24, 32, 255})
			}
		}
	}
	// The trail: a ribbon along the point's last places, thinning to the oldest.
	trail := v.swinging || now-v.ended_at < FIRST_PERSON_SWORD_TRAIL_FADE
	if trail && v.trail_count >= 2 {
		color := first_person_sword_trail_color(first_person_sword_quality(v))
		// A spinning swing shows it from the turn on.
		if v.spin && v.swinging { color = FIRST_PERSON_SWORD_SPIN_COLOR }
		if now-v.cut_at < FIRST_PERSON_SWORD_TRAIL_FADE {
			color = first_person_sword_trail_color(1 if v.last.perfect else (0.5 if v.last.damage >= 3 else 0))
		}
		for k in 0..<v.trail_count-1 {
			thick := max(f32(1), f32(h)*0.022*f32(k+1)/f32(v.trail_count))
			rl.DrawLineEx(at(v.trail[k], w, h, lift), at(v.trail[k+1], w, h, lift), thick, color)
		}
	}
	// The blade itself is the zweihänder's model, over all this (first_person_zweihander.odin).
}
