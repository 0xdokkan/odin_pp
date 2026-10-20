package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// MOVIMENTO OMBRA on the board. The player's card sinks into its own shadow,
// a pool of ink that glides from cell to cell at each of the shadow's steps
// while the world stands still: its colours drain, its figures, tokens and
// seals hold their pose and its cues wait. When the four seconds end the card
// climbs back out of the pool where it stopped, and the world goes on from
// the moment it stopped. The room says where the shadow is and how far its
// step has gone (game/tactical_shadow.odin: the steps record no event), the
// board only follows; the sinking and the rise are paced by the card's own
// cues, Shadow_Entered and Shadow_Emerged. Nothing here holds the player's
// input: the shadow's own 0.4 s step does that in the game.

// Without the card's cue (a board that missed it), its own length.
SHADOW_SINK_SECONDS :: f64(PRESENTATION_SHADOW_SINK_DURATION)
SHADOW_RISE_SECONDS :: f64(PRESENTATION_SHADOW_RISE_DURATION)
// The world's colours drain, and come back, this fast.
SHADOW_FREEZE_SECONDS :: f64(0.25)
// The share of the figure under the floor while sunk.
SHADOW_DEPTH :: f32(0.72)
SHADOW_TRAIL :: 6
SHADOW_TRAIL_SECONDS :: f64(0.55)
SHADOW_CRITICAL_SECONDS :: f64(0.45)
SHADOW_INK :: rl.Color{14, 8, 26, 255}
SHADOW_RIM :: rl.Color{150, 116, 214, 255}
SHADOW_FIGURE :: rl.Color{78, 58, 120, 255}

Shadow_Drop :: struct {
	at: view.Vec2,
	born: f64,
}

Shadow_View :: struct {
	// The room is in the shadow (as seen this frame); the card is still
	// climbing out of it.
	active, rising: bool,
	// 0..1: how far the card has gone down, and back up; whether the card's
	// cue paces each (otherwise the sprite clock from `sunk` and `risen`).
	sink, rise: f32,
	sink_paced, rise_paced: bool,
	sunk, risen: f64,
	// The world stopped at `frozen_at` (sprite clock); `held` is all the time
	// it has spent stopped, so its own clock (tactical_world_time) goes on
	// from where it stopped. `frozen` is the drain of its colours, 0..1.
	frozen_at, held: f64,
	frozen: f32,
	// The room's shadow as last seen: its steps, where the pool is shown now
	// (easing between cells), the drops it leaves behind. `body` is where the
	// player's body stays meanwhile, the snapshot's player before the pool
	// takes its place: what the held world shows of him stays there.
	seen_steps: int,
	at, body: view.Vec2,
	trail: [SHADOW_TRAIL]Shadow_Drop,
	trail_next: int,
	critical_at: f64,
	// Running counts for the lab's sounds: steps, diagonals on a beat, and
	// the shadow's beats struck.
	steps, criticals, beats: u32,
	// The shadow's clock, read once a frame for the passes without a room:
	// the seconds left of how many, how open its next beat is (1 just after
	// one, 0 on it), whether a press now lands on one, and whether one is
	// still to come.
	left, duration, beat_open: f32,
	on_beat, beat_ahead: bool,
	beat: int,
}

// The world's clock for its drawings: the sprite clock less every moment the
// world spent stopped. It stands still while the player is in his shadow,
// then goes on from there.
@(private)
tactical_world_time :: proc(renderer: ^Renderer) -> f64 {
	return tactical_world_time_at(renderer, renderer.sprite_assets.elapsed)
}

// The same at sprite time `now`.
@(private)
tactical_world_time_at :: proc(renderer: ^Renderer, now: f64) -> f64 {
	s := &renderer.tactical.shadow
	if s.active { return s.frozen_at-s.held }
	return now-s.held
}

// The time an actor's drawings see: the player keeps the sprite clock, the
// world (every other card) its own (tactical_world_time).
@(private)
living_clock :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f64 {
	return living_clock_at(renderer, entity, renderer.sprite_assets.elapsed)
}

@(private)
living_clock_at :: proc(renderer: ^Renderer, entity: game.Entity_Ref, now: f64) -> f64 {
	if entity == game.PLAYER_ENTITY { return now }
	return tactical_world_time_at(renderer, now)
}

// The progress of the card's own cue of `kind` in the player's lane (0 until
// it starts); not found once it is over.
@(private)
shadow_cue_progress :: proc(renderer: ^Renderer, kind: Presentation_Cue_Kind) -> (progress: f32, found: bool) {
	for offset in 0..<renderer.timeline.count {
		cue, ok := presentation_cue_at(&renderer.timeline, offset)
		if ok && cue.kind == kind { return presentation_cue_progress(cue), true }
	}
	return
}

// Where the pool is now: easing out of the cell the shadow left toward its
// cell (fast at first) over the step's own lockout, so it arrives when the
// next press is taken.
@(private = "file")
tactical_shadow_glide :: proc(t: ^game.Tactical_State) -> view.Vec2 {
	u := clamp(1-t.shadow_step_remaining/game.TACTICAL_SHADOW_STEP_SECONDS, 0, 1)
	p := 1-(1-u)*(1-u)*(1-u)
	from, to := presentation_position(t.shadow_from), presentation_position(t.shadow_position)
	return {from.x+(to.x-from.x)*p, from.y+(to.y-from.y)*p}
}

// Once per frame, right after the snapshot (update_tactical_view, which may
// run twice a frame): follows the room's shadow and moves the shown player
// onto the pool, so the camera, the vision, the lantern and the player's
// glyphs follow it.
@(private)
update_tactical_shadow :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	s := &v.shadow
	if room == nil || room.player == nil || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	t := &room.player.tactical
	inside := game.tactical_shadow_active(room)
	if inside && !s.active {
		_, paced := shadow_cue_progress(renderer, .Shadow_Entered)
		s^ = {active = true, sink_paced = paced, sunk = now, frozen_at = now, held = s.held,
			seen_steps = t.shadow_steps, at = presentation_position(t.shadow_position),
			steps = s.steps, criticals = s.criticals, beats = s.beats}
		// The card goes down where it stands: no push left over from a step.
		if player := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); player != nil { player.sliding = false }
	} else if !inside && s.active {
		_, paced := shadow_cue_progress(renderer, .Shadow_Emerged)
		s.active, s.rising, s.rise_paced, s.risen, s.rise = false, true, paced, now, 0
		s.held += now-s.frozen_at
		s.on_beat, s.beat_ahead = false, false
	}
	if s.active {
		if t.shadow_steps != s.seen_steps {
			s.trail[s.trail_next] = {at = presentation_position(t.shadow_from), born = now}
			s.trail_next = (s.trail_next+1)%len(s.trail)
			if abs(t.shadow_position.x-t.shadow_from.x) == 1 && abs(t.shadow_position.y-t.shadow_from.y) == 1 {
				s.critical_at = now
				s.criticals += 1
			}
			s.steps += u32(max(1, t.shadow_steps-s.seen_steps))
			s.seen_steps = t.shadow_steps
			// The figure faces where it goes.
			if player := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); player != nil {
				d := rl.Vector3{f32(t.shadow_position.x-t.shadow_from.x), 0, f32(t.shadow_position.y-t.shadow_from.y)}
				living_face(player, rl.Vector3DotProduct(d, flipbook_camera_right(renderer)), now)
			}
		}
		if s.sink_paced {
			progress, found := shadow_cue_progress(renderer, .Shadow_Entered)
			s.sink = progress if found else 1
		} else { s.sink = f32(clamp((now-s.sunk)/SHADOW_SINK_SECONDS, 0, 1)) }
		s.left, s.duration = t.shadow_remaining, t.shadow_duration
		elapsed := game.tactical_shadow_elapsed(t)
		approach, on := game.tactical_beat_glow(room)
		s.beat_open, s.on_beat = 1-approach, on
		s.beat_ahead = on || elapsed < f32(game.TACTICAL_SHADOW_BEATS)
		if beat := int(elapsed); beat > s.beat && beat <= game.TACTICAL_SHADOW_BEATS { s.beats += 1 }
		s.beat = int(elapsed)
		u := f32(clamp((now-s.frozen_at)/SHADOW_FREEZE_SECONDS, 0, 1))
		s.frozen = u*u*(3-2*u)
		s.at = tactical_shadow_glide(t)
		s.body = v.snapshot.player.position
		v.snapshot.player.position = s.at
		return
	}
	if s.rising {
		if s.rise_paced {
			progress, found := shadow_cue_progress(renderer, .Shadow_Emerged)
			s.rise = progress if found else 1
		} else { s.rise = f32(clamp((now-s.risen)/SHADOW_RISE_SECONDS, 0, 1)) }
		if s.rise >= 1 { s.rising = false }
		// The card comes out where the body now stands, never where the
		// cue's first frame still had it.
		s.at = presentation_position(room.player.position)
		if s.rising { v.snapshot.player.position = s.at }
	}
	if s.risen > 0 {
		u := f32(clamp((now-s.risen)/SHADOW_FREEZE_SECONDS, 0, 1))
		s.frozen = 1-u*u*(3-2*u)
	}
}

// The pool shows: while sunk, and while the card climbs out of it.
tactical_shadow_showing :: proc(renderer: ^Renderer) -> bool {
	s := &renderer.tactical.shadow
	return s.active || s.rising
}

// How far under the floor the player's card is: 0 on the board, SHADOW_DEPTH
// sunk (a share of the figure's height).
@(private)
tactical_shadow_depth :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	s := &renderer.tactical.shadow
	if entity != game.PLAYER_ENTITY { return 0 }
	if s.active {
		u := clamp(s.sink, 0, 1)
		return SHADOW_DEPTH*u*u*(3-2*u)
	}
	if s.rising {
		// Out of the pool with a small spring past the floor.
		u := clamp(s.rise, 0, 1)
		if u <= 0 { return SHADOW_DEPTH }
		c := f32(1.6)
		w := u-1
		return SHADOW_DEPTH*(1-(1+w*w*((c+1)*w+c)))
	}
	return 0
}

// The sunk figure is dark and half seen; it clears as it rises.
@(private)
tactical_shadow_tint :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (tint: rl.Color, opacity: f32) {
	d := clamp(tactical_shadow_depth(renderer, entity)/SHADOW_DEPTH, 0, 1)
	if d <= 0 { return rl.WHITE, 1 }
	mix :: proc(a, b: u8, t: f32) -> u8 { return u8(f32(a)+(f32(b)-f32(a))*t) }
	return {mix(255, SHADOW_FIGURE.r, d), mix(255, SHADOW_FIGURE.g, d), mix(255, SHADOW_FIGURE.b, d), 255}, 1-0.4*d
}

// The pool, its trail of drops and the shadow's own metronome: in the 3D
// pass, in place of the player's stand while the card is under the floor
// (draw_tactical_actor_bases).
@(private)
draw_tactical_shadow_pool :: proc(renderer: ^Renderer) {
	s := &renderer.tactical.shadow
	now := renderer.sprite_assets.elapsed
	for drop in s.trail {
		age := now-drop.born
		if drop.born <= 0 || age >= SHADOW_TRAIL_SECONDS || !tactical_render_visible(renderer, shadow_drop_cell(drop.at)) { continue }
		k := f32(1-age/SHADOW_TRAIL_SECONDS)
		rl.DrawCylinder({drop.at.x+0.5, 0.024, drop.at.y+0.5}, 0.26*k, 0.26*k, 0.001, 20, color_with_opacity(SHADOW_INK, 0.6*k))
	}
	open := clamp(tactical_shadow_depth(renderer, game.PLAYER_ENTITY)/SHADOW_DEPTH, 0, 1)
	p := rl.Vector3{s.at.x+0.5, 0.026, s.at.y+0.5}
	if open > 0 {
		ripple := 0.015*math.sin(f32(math.mod(now, 1000))*math.TAU*1.4)
		for layer in 0..<3 {
			r := (0.46-f32(layer)*0.1+ripple)*open
			rl.DrawCylinder(p+{0, f32(layer)*0.001, 0}, r, r, 0.001, 28, color_with_opacity(SHADOW_INK, (0.5+0.18*f32(layer))*open))
		}
		rl.DrawCircle3D(p+{0, 0.004, 0}, (0.47+ripple)*open, {1, 0, 0}, 90, color_with_opacity(SHADOW_RIM, 0.85*open))
	}
	if !s.active {
		// The rise: a last ring of the rim spreading out of the pool, to its
		// end, also once the card has sprung past the floor and the pool has
		// closed.
		u := clamp(s.rise, 0, 1)
		draw_tactical_rune(p+{0, 0.003, 0}, 0.24+0.3*u, u*0.3, color_with_opacity(SHADOW_RIM, 1-u))
		return
	}
	if open <= 0 { return }
	// The seconds left: an arc of the rim that drains clockwise.
	segments := 40
	shown := int(f32(segments)*clamp(s.left/max(s.duration, 0.001), 0, 1)+0.999)
	for index in 0..<shown {
		a0 := -math.PI*0.5+f32(index)/f32(segments)*math.TAU
		a1 := -math.PI*0.5+f32(index+1)/f32(segments)*math.TAU
		r := f32(0.56)
		rl.DrawCylinderEx(p+{math.cos(a0)*r, 0.006, math.sin(a0)*r}, p+{math.cos(a1)*r, 0.006, math.sin(a1)*r}, 0.014, 0.014, 4,
			color_with_opacity(SHADOW_RIM, open))
	}
	// The shadow's tick: a gold ring closing on the pool toward each of its
	// beats, bright while a two-key press would step diagonally.
	if !s.beat_ahead { return }
	gold := TACTICAL_FEEDBACK_CRITICAL
	if s.on_beat {
		// On the beat: a bright band of gold and a glow on the floor.
		rl.DrawCylinder(p+{0, 0.002, 0}, 0.66, 0.66, 0.001, 32, color_with_opacity(gold, 0.16*open))
		for ring in 0..<3 { rl.DrawCircle3D(p+{0, 0.008+f32(ring)*0.001, 0}, 0.6+f32(ring)*0.014, {1, 0, 0}, 90, color_with_opacity(gold, open)) }
		return
	}
	r := 0.6+0.45*clamp(s.beat_open, 0, 1)
	rl.DrawCircle3D(p+{0, 0.008, 0}, r, {1, 0, 0}, 90, color_with_opacity(gold, (0.25+0.45*(1-s.beat_open))*open))
}

@(private)
draw_tactical_shadow_overlay :: proc(renderer: ^Renderer) {
	s := &renderer.tactical.shadow
	now := renderer.sprite_assets.elapsed
	if s.critical_at <= 0 || now-s.critical_at >= SHADOW_CRITICAL_SECONDS { return }
	anchor := tactical_project(renderer, {s.at.x+0.5, s.at.y+0.5}, 0.9)
	label: cstring = "CRITICO!"
	width := gothic_text_width(renderer, label, 12)+12
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, 19}, tactical_world_bounds(renderer))
	if !placed { return }
	alpha := tactical_feedback_alpha(f32((now-s.critical_at)/SHADOW_CRITICAL_SECONDS))
	rl.DrawRectangleRec(bounds, color_with_opacity({8, 15, 26, 235}, alpha))
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, color_with_opacity(TACTICAL_FEEDBACK_CRITICAL, alpha))
	gothic_text(renderer, label, bounds.x+6, bounds.y+3, 12, color_with_opacity(TACTICAL_FEEDBACK_CRITICAL, alpha))
}

@(private="file")
shadow_drop_cell :: proc(at: view.Vec2) -> grid.Position {
	return {int(math.round(at.x)), int(math.round(at.y))}
}
