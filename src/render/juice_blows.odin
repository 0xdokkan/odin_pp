package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import view "../engine/view"

// THE JUICE ON THE BLOWS (docs/piano-succo.md, Fase 2): what the board shows
// when a blow lands, on top of juice.odin's shake and hit-stop.
//
// The user's choices of 2026-11-01: the plan's numbers to start from; the
// hit-stop only for the player's bumps and arrows (EVENT_ATTACK_BIT), his
// cards only shake; a short red edge when a foe strikes him; a critical's
// thump of its own. A blow shown with its props juices as it lands
// (attack_fx_landing_in), any other as its cue starts; each cue once.

Juice_Hit :: struct {
	hold, trauma, kick, flash: f32,
}

// The player's blow, his critical and his kill (the kill's card flies back
// and stays there as it falls).
JUICE_BLOW :: Juice_Hit{hold = 0.06, trauma = 0.25, kick = 0.15, flash = 0.06}
JUICE_CRITICAL :: Juice_Hit{hold = 0.09, trauma = 0.45, kick = 0.2, flash = 0.1}
JUICE_KILL :: Juice_Hit{hold = 0.10, trauma = 0.55, kick = 0.3, flash = 0.1}
// A foe's blow on the player, one his guard took, an explosion (weaker away
// from him: trauma/(1+cells/JUICE_BLAST_FALLOFF)).
JUICE_HURT_TRAUMA :: f32(0.30)
JUICE_GUARD_TRAUMA :: f32(0.15)
JUICE_BLAST_TRAUMA :: f32(0.40)
JUICE_BLAST_FALLOFF :: f32(4)
// How long a kick comes back, the sparks fly, the red edge shows.
JUICE_KICK_SECONDS :: f64(0.18)
JUICE_SPARK_SECONDS :: f64(0.35)
JUICE_HURT_SECONDS :: f64(0.25)
// The red edge's depth (canvas share) and strength, more for a bigger blow.
JUICE_HURT_EDGE :: f32(0.09)
JUICE_SEEN :: 48
JUICE_KICKS :: 16
JUICE_BURSTS :: 16
// A cue's event is juiced once (on the world's clock: one the shadow holds is
// never juiced again).
JUICE_SEEN_SECONDS :: f64(4)
JUICE_PAPER :: rl.Color{240, 234, 220, 255}
JUICE_GOLD :: rl.Color{255, 206, 84, 255}
JUICE_GUARD :: rl.Color{120, 196, 255, 255}
// Every other bit is ink, so the burst reads on the cream card and on the floor.
JUICE_INK :: rl.Color{34, 28, 30, 255}

Juice_Seen :: struct {
	kind: Presentation_Cue_Kind,
	event: game.Game_Event,
	batch: u32,
	at: f64,
}

// A struck card thrown back along `way` and flashing white.
Juice_Kick :: struct {
	entity: game.Entity_Ref,
	way: view.Vec2,
	distance, flash: f32,
	stays: bool,
	at: f64,
}

// Paper bits thrown off a struck point.
Juice_Burst :: struct {
	at: rl.Vector3,
	color: rl.Color,
	count: int,
	seed: u32,
	start: f64,
}

// What the board keeps of the blows' juice.
Juice_Blows :: struct {
	seen: [JUICE_SEEN]Juice_Seen,
	seen_next: int,
	kicks: [JUICE_KICKS]Juice_Kick,
	kick_next: int,
	bursts: [JUICE_BURSTS]Juice_Burst,
	burst_next: int,
	hurt_at: f64,
	hurt: f32,
	// What the board has juiced so far (the lab's smoke and the tests).
	blows, criticals, kills, hurts, guards, blasts: int,
}

@(private = "file")
juice_seen :: proc(b: ^Juice_Blows, cue: ^Presentation_Cue, now: f64) -> bool {
	for seen in b.seen {
		if seen.at > 0 && now-seen.at < JUICE_SEEN_SECONDS && seen.kind == cue.kind && seen.batch == cue.batch && seen.event == cue.event { return true }
	}
	b.seen[b.seen_next] = {kind = cue.kind, event = cue.event, batch = cue.batch, at = max(now, 0.000001)}
	b.seen_next = (b.seen_next+1)%JUICE_SEEN
	return false
}

// Whether the batch of `cue` fells its target: its Defeat cue, shown yet or not.
@(private = "file")
juice_fells :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	fells :: proc(other: ^Presentation_Cue, cue: ^Presentation_Cue) -> bool {
		return other.kind == .Defeat && other.event.target == cue.event.target && other.batch == cue.batch
	}
	for offset in 0..<renderer.timeline.count {
		if other, found := presentation_cue_at(&renderer.timeline, offset); found && fells(other, cue) { return true }
	}
	if w := renderer.world_playback; w != nil {
		for &entry in w.cues[:w.count] { if fells(&entry.cue, cue) { return true } }
	}
	return false
}

// Where a body stands as the board shows it, and its struck point's height.
@(private = "file")
juice_body :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (at: view.Vec2, ok: bool) {
	return tactical_cue_actor_position(renderer, entity)
}

@(private = "file")
juice_burst :: proc(renderer: ^Renderer, b: ^Juice_Blows, entity: game.Entity_Ref, color: rl.Color, count: int, now: f64) {
	at, ok := juice_body(renderer, entity)
	if !ok { return }
	point := rl.Vector3{at.x+0.5, 0.7, at.y+0.5}
	if struck, found := attack_struck_point(renderer, entity); found { point = struck }
	b.bursts[b.burst_next] = {at = point, color = color, count = count, seed = u32(b.burst_next*7919+int(entity.id)*31), start = now}
	b.burst_next = (b.burst_next+1)%JUICE_BURSTS
}

@(private = "file")
juice_kick :: proc(renderer: ^Renderer, b: ^Juice_Blows, entity, from: game.Entity_Ref, hit: Juice_Hit, stays: bool, now: f64) {
	at, ok := juice_body(renderer, entity)
	if !ok { return }
	way := view.Vec2{0, 0}
	if origin, found := juice_body(renderer, from); found {
		d := view.Vec2{at.x-origin.x, at.y-origin.y}
		length := math.sqrt(d.x*d.x+d.y*d.y)
		if length > 0.001 { way = {d.x/length, d.y/length} }
	}
	b.kicks[b.kick_next] = {entity = entity, way = way, distance = hit.kick, flash = hit.flash, stays = stays, at = now}
	b.kick_next = (b.kick_next+1)%JUICE_KICKS
}

// Once a frame, after the blows' props (observe_attack_cues): every blow cue
// that has landed gives its juice, once.
@(private)
observe_juice_blows :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.snapshot == nil { return }
	b := &renderer.tactical.juice_blows
	now := renderer.sprite_assets.elapsed
	world := tactical_world_time_at(renderer, now)
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		event := cue.event
		#partial switch cue.kind {
		case .Damage:
			if event.has_status_cause { continue }
			if event.source == game.PLAYER_ENTITY && event.target.kind == .Enemy {
				// A blow with its props juices as it lands.
				if _, pending := attack_fx_landing_in(renderer, event.target, now, game.PLAYER_ENTITY); pending { continue }
				if juice_seen(b, cue, world) { continue }
				blow := game.event_is_attack(event)
				critical := game.event_is_critical(event)
				fells := juice_fells(renderer, cue)
				hit := JUICE_KILL if fells else (JUICE_CRITICAL if critical else JUICE_BLOW)
				juice_shake(renderer, hit.trauma)
				b.blows += 1
				if critical { b.criticals += 1 }
				if fells { b.kills += 1 }
				// His cards only shake (the user's choice).
				if !blow { continue }
				_ = juice_hit_stop(renderer, hit.hold)
				juice_kick(renderer, b, event.target, game.PLAYER_ENTITY, hit, fells, now)
				juice_burst(renderer, b, event.target, JUICE_GOLD if critical else JUICE_PAPER, 16 if critical || fells else 11, now)
				if critical && renderer.tactical.lab_sounds != nil { lab_sound_queue(renderer.tactical.lab_sounds, .World_Hit_Critical, now) }
			} else if event.target == game.PLAYER_ENTITY && event.source.kind == .Enemy {
				if _, pending := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, now, event.source); pending { continue }
				if juice_seen(b, cue, world) { continue }
				juice_shake(renderer, JUICE_HURT_TRAUMA)
				b.hurt_at, b.hurt = now, clamp(0.55+f32(event.amount)/10, 0.55, 1)
				b.hurts += 1
			}
		case .Damage_Absorbed, .Attack_Deflected:
			if event.target != game.PLAYER_ENTITY || event.source.kind != .Enemy { continue }
			if _, pending := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, now, event.source); pending { continue }
			if juice_seen(b, cue, world) { continue }
			juice_shake(renderer, JUICE_GUARD_TRAUMA)
			juice_burst(renderer, b, game.PLAYER_ENTITY, JUICE_GUARD, 8, now)
			b.guards += 1
		case .Explosion:
			if juice_seen(b, cue, world) { continue }
			cells := f32(0)
			if player, ok := juice_body(renderer, game.PLAYER_ENTITY); ok {
				dx, dy := f32(event.to_position.x)-player.x, f32(event.to_position.y)-player.y
				cells = math.sqrt(dx*dx+dy*dy)
			}
			juice_shake(renderer, JUICE_BLAST_TRAUMA/(1+cells/JUICE_BLAST_FALLOFF))
			b.blasts += 1
		}
	}
}

// How far a struck card stands thrown back now: at once at its full kick, then
// back home over JUICE_KICK_SECONDS (a kill's card stays out as it falls).
juice_kick_offset :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> view.Vec2 {
	if renderer == nil { return {} }
	now := renderer.sprite_assets.elapsed
	for &kick in renderer.tactical.juice_blows.kicks {
		if kick.at <= 0 || kick.entity != entity { continue }
		u := f32((now-kick.at)/JUICE_KICK_SECONDS)
		if u < 0 || (!kick.stays && u >= 1) || u > 30 { continue }
		s := f32(1) if kick.stays else (1-u)*(1-u)
		return {kick.way.x*kick.distance*s, kick.way.y*kick.distance*s}
	}
	return {}
}

// How white a struck card's print flashes now (0..1).
juice_struck_flash :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	if renderer == nil { return 0 }
	now := renderer.sprite_assets.elapsed
	best := f32(0)
	for &kick in renderer.tactical.juice_blows.kicks {
		if kick.at <= 0 || kick.entity != entity || kick.flash <= 0 { continue }
		u := f32(now-kick.at)/kick.flash
		if u >= 0 && u < 1 { best = max(best, 1-u) }
	}
	return best
}

// The paper bits, in the board's 3D pass: each a small two-sided triangle
// thrown out of the struck point, turning, falling and fading; drawn over the
// cards, as the impact star is, every other one in ink.
@(private)
draw_juice_bursts :: proc(renderer: ^Renderer) {
	now := renderer.sprite_assets.elapsed
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthTest() }
	camera := renderer.tactical.camera
	forward := rl.Vector3Normalize(camera.target-camera.position)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, {0, 1, 0}))
	up := rl.Vector3CrossProduct(right, forward)
	for &burst in renderer.tactical.juice_blows.bursts {
		if burst.start <= 0 { continue }
		t := f32(now-burst.start)
		if t < 0 || f64(t) >= JUICE_SPARK_SECONDS { continue }
		p := t/f32(JUICE_SPARK_SECONDS)
		alpha := u8(255*clamp((1-p)*2, 0, 1))
		for index in 0..<burst.count {
			h := burst.seed*2654435761+u32(index)*40503
			angle := f32(index)/f32(burst.count)*math.TAU+f32(h%100)*0.01
			speed := 2.8+f32((h>>8)%100)*0.018
			out := right*math.cos(angle)+up*math.sin(angle)*0.8
			point := burst.at+out*(speed*t)+rl.Vector3{0, -4.5*t*t, 0}
			spin := f32((h>>16)%628)*0.01+t*14
			size := f32(0.1)+f32((h>>4)%10)*0.007
			a := right*math.cos(spin)+up*math.sin(spin)
			c := right*math.cos(spin+2.3)+up*math.sin(spin+2.3)
			d := right*math.cos(spin+4.1)+up*math.sin(spin+4.1)
			tone := JUICE_INK if index%2 == 1 else burst.color
			color := rl.Color{tone.r, tone.g, tone.b, alpha}
			rl.DrawTriangle3D(point+a*size, point+c*size, point+d*size, color)
			rl.DrawTriangle3D(point+a*size, point+d*size, point+c*size, color)
		}
	}
}

// A foe's blow on the player: a red shade along the canvas's edges.
@(private)
draw_juice_hurt_edge :: proc(renderer: ^Renderer) {
	b := &renderer.tactical.juice_blows
	if b.hurt_at <= 0 { return }
	u := f32((renderer.sprite_assets.elapsed-b.hurt_at)/JUICE_HURT_SECONDS)
	if u < 0 || u >= 1 { return }
	strength := b.hurt*(1-u)*juice_strength(renderer)
	if strength <= 0 { return }
	w, h := renderer.canvas_width, renderer.canvas_height
	depth := min(w, h)*JUICE_HURT_EDGE
	edge := rl.Color{210, 24, 32, u8(170*clamp(strength, 0, 1))}
	clear := rl.Color{210, 24, 32, 0}
	rl.DrawRectangleGradientV(0, 0, i32(w), i32(depth), edge, clear)
	rl.DrawRectangleGradientV(0, i32(h-depth), i32(w), i32(depth), clear, edge)
	rl.DrawRectangleGradientH(0, 0, i32(depth), i32(h), edge, clear)
	rl.DrawRectangleGradientH(i32(w-depth), 0, i32(depth), i32(h), clear, edge)
}
