package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import audio "../engine/audio"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// THE ARCHERS' REAL ARROWS (game/enemy_arrow.odin, docs/piano-succo.md,
// Fasi 3-4), as the board shows and the lab sounds them. The user's choices
// of 2026-11-01: the bolt is cut paper like the cards (gfx Attack_Prop
// .Quarrel); a pale streak of air behind it; its whistle sounds all the way,
// louder near the Viandante; where it misses it sticks, quivering, with a
// knock of wood or a crack of stone (as the land is made: enemy_bolt_in_wood),
// and is gone after a second and a half.
//
// The cells an aimed or flying bolt will cross are lit on the floor; ahead of
// a flying one they pulse, stronger as it comes, and go out as it passes.

ENEMY_ARROW_COURSE_COLOR :: rl.Color{255, 92, 72, 255}
ENEMY_ARROW_HEIGHT :: f32(0.62)
// The bolt from its nock to its head (cells), and its streak of air.
ENEMY_BOLT_LENGTH :: f32(0.6)
ENEMY_BOLT_TRAIL :: f32(1)
ENEMY_BOLT_TRAIL_WIDTH :: f32(0.08)
ENEMY_BOLT_AIR :: rl.Color{238, 242, 250, 255}
// Ahead of a flying bolt its cells pulse: how many are lit stronger, the
// wave's speed (radians a second) and its step from cell to cell.
ENEMY_BOLT_PULSE_CELLS :: f32(3)
ENEMY_BOLT_PULSE_SPEED :: f32(20)
ENEMY_BOLT_PULSE_STEP :: f32(1.6)
// A bolt stuck in a wall or the floor shows this long, its last stretch
// fading; one in a struck card stays a moment, then drops away.
ENEMY_BOLT_STUCK_SECONDS :: f64(1.5)
ENEMY_BOLT_FADE_SECONDS :: f64(0.3)
ENEMY_BOLT_PINNED_SECONDS :: f64(0.35)
ENEMY_BOLT_DROP_SECONDS :: f64(0.2)
// How deep its head goes in, how steeply it falls into the floor (radians).
ENEMY_BOLT_BITE :: f32(0.06)
ENEMY_BOLT_FALL :: f32(0.9)
// Its quiver: the tail's swing (cells), how fast (Hz), how soon it dies (s).
ENEMY_BOLT_QUIVER :: f32(0.05)
ENEMY_BOLT_QUIVER_HZ :: f32(11)
ENEMY_BOLT_QUIVER_TAU :: f32(0.25)
// Its whistle: as loud far away as this, rising to full near the Viandante
// (half way at ENEMY_BOLT_NEAR cells), its pitch bent this much as it comes
// toward him (up) and goes away (down).
ENEMY_BOLT_FAR :: f32(0.22)
ENEMY_BOLT_NEAR :: f32(1.5)
ENEMY_BOLT_DOPPLER :: f32(0.16)
// Frames a bolt must stand still before its whistle pauses.
ENEMY_BOLT_STILL_FRAMES :: u8(3)
ENEMY_BOLT_SEEN :: 24
ENEMY_BOLT_STUCK :: 12
// Its sounds: the whistle, and the bolt stuck in wood or stone.
LAB_BOLT_FLIGHT :: audio.LAB_FLIGHT_SFX
LAB_BOLT_WOOD :: audio.Lab_Sfx.Archer_Bolt_Wood
LAB_BOLT_STONE :: audio.Lab_Sfx.Archer_Bolt_Stone

Enemy_Bolt_Rest :: enum u8 {Wall, Floor, Card}

// A bolt landed: where its head is, the way it flew, what holds it.
Enemy_Bolt_Stuck :: struct {
	tip, way: rl.Vector3,
	rest: Enemy_Bolt_Rest,
	cell: grid.Position,
	at: f64,
}

// What the board keeps of the bolts that have landed.
Enemy_Bolts :: struct {
	seen: [ENEMY_BOLT_SEEN]Juice_Seen,
	seen_next: int,
	stuck: [ENEMY_BOLT_STUCK]Enemy_Bolt_Stuck,
	stuck_next: int,
	// Landings so far, by what holds the bolt (the lab's smoke and the tests).
	landed: [Enemy_Bolt_Rest]int,
}

// A fresh board: no bolt stuck; the counts go on.
@(private)
enemy_bolts_reset :: proc(b: ^Enemy_Bolts) {
	b^ = {landed = b.landed}
}

// The texel the Quarrel is drawn at, ENEMY_BOLT_LENGTH long.
@(private = "file")
enemy_bolt_texel :: proc() -> f32 {
	return ENEMY_BOLT_LENGTH/max(attack_prop_length(.Quarrel, 1), 1)
}

// --------------------------------------------------------------------------
// The floor

// The cells from the `from`th of a line to its end (a wall, a cover, its
// range), lit at `alpha`; ahead of a bolt flying `at` along it, pulsing.
@(private = "file")
draw_enemy_arrow_course :: proc(renderer: ^Renderer, room: ^game.Room, origin, step: grid.Position, from: int, progress, alpha: f32,
	flying := false, at: f32 = 0, now: f32 = 0) {
	_, cells := game.enemy_arrow_course_end(room, origin, step)
	line := game.enemy_arrow_line(origin, step)
	for k in max(from, 1)..=cells {
		cell := game.enemy_arrow_cell(line, k)
		if !tactical_render_visible(renderer, cell) { continue }
		draw_intent_cell(cell, progress, ENEMY_ARROW_COURSE_COLOR, enemy_bolt_course_alpha(k, at, now) if flying else alpha)
	}
}

// A cell `k` of a flying bolt's line, the bolt `at` along it: lit, more and
// pulsing as the bolt comes, the pulse running ahead of it.
enemy_bolt_course_alpha :: proc(k: int, at, now: f32) -> f32 {
	near := clamp(1-(f32(k)-at-0.5)/ENEMY_BOLT_PULSE_CELLS, 0, 1)
	wave := 0.5+0.5*math.sin(now*ENEMY_BOLT_PULSE_SPEED-f32(k)*ENEMY_BOLT_PULSE_STEP)
	return 0.35+0.45*near*(0.6+0.4*wave)
}

// In the ground pass: the aimed archers' lines, and the flying bolts' rest.
@(private)
draw_enemy_arrow_courses :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.phase != .Combat { return }
	now := tactical_world_time(renderer)
	for &enemy in room.enemies {
		if !game.enemy_attack_is_arrow(&enemy, &enemy.intent) || game.enemy_is_out_of_play(room, enemy.id) || game.enemy_is_staggered(room, &enemy) { continue }
		step, ok := game.enemy_arrow_aim_step(&enemy)
		if !ok { continue }
		left, _, progress := intent_timing(room, &enemy)
		lit := intent_flicker(left, now, 0.25)
		draw_enemy_arrow_course(renderer, room, enemy.position, step, 1, progress*0.6, (0.22+0.25*intent_loudness(left))*lit)
	}
	for arrow in room.arrows.items[:room.arrows.count] {
		at := game.enemy_arrow_distance(room, arrow)
		draw_enemy_arrow_course(renderer, room, game.enemy_arrow_origin(arrow), game.enemy_arrow_step(arrow), int(math.floor(at+0.5))+1, 1, 0,
			true, at, f32(now))
	}
}

// --------------------------------------------------------------------------
// In flight

// Where a flying bolt's head is (on the floor's plane), the way it flies.
@(private = "file")
enemy_bolt_place :: proc(room: ^game.Room, arrow: game.Enemy_Arrow) -> (centre, way: view.Vec2) {
	at := game.enemy_arrow_distance(room, arrow)
	way = {f32(arrow.step.x), f32(arrow.step.y)}
	centre = {f32(arrow.origin.x)+way.x*at, f32(arrow.origin.y)+way.y*at}
	return
}

// A ribbon facing the eye along `from`→`to`, `w0` wide at `from` narrowing
// to `w1`, its colour fading from `a0` to `a1`.
@(private = "file")
draw_enemy_bolt_ribbon :: proc(renderer: ^Renderer, from, to: rl.Vector3, w0, w1, a0, a1: f32, color: rl.Color) {
	camera := renderer.tactical.camera
	along := to-from
	if rl.Vector3Length(along) < 0.0001 { return }
	side := rl.Vector3CrossProduct(along, camera.position-from)
	if rl.Vector3Length(side) < 0.0001 { return }
	side = rl.Vector3Normalize(side)
	SEGMENTS :: 6
	rlgl.Begin(rlgl.QUADS)
	for index in 0..<SEGMENTS {
		u0, u1 := f32(index)/SEGMENTS, f32(index+1)/SEGMENTS
		p0, p1 := from+along*u0, from+along*u1
		h0, h1 := (w0+(w1-w0)*u0)*0.5, (w0+(w1-w0)*u1)*0.5
		c0 := u8(clamp(a0+(a1-a0)*u0, 0, 1)*f32(color.a))
		c1 := u8(clamp(a0+(a1-a0)*u1, 0, 1)*f32(color.a))
		rlgl.Color4ub(color.r, color.g, color.b, c0); rlgl.Vertex3f(p0.x-side.x*h0, p0.y-side.y*h0, p0.z-side.z*h0)
		rlgl.Color4ub(color.r, color.g, color.b, c1); rlgl.Vertex3f(p1.x-side.x*h1, p1.y-side.y*h1, p1.z-side.z*h1)
		rlgl.Color4ub(color.r, color.g, color.b, c1); rlgl.Vertex3f(p1.x+side.x*h1, p1.y+side.y*h1, p1.z+side.z*h1)
		rlgl.Color4ub(color.r, color.g, color.b, c0); rlgl.Vertex3f(p0.x+side.x*h0, p0.y+side.y*h0, p0.z+side.z*h0)
	}
	rlgl.End()
}

// A long soft shadow on the floor under a bolt from `tail` to `tip`.
@(private = "file")
draw_enemy_bolt_shadow :: proc(tail, tip: rl.Vector3, ground: f32) {
	a, b := rl.Vector3{tail.x, ground+0.03, tail.z}, rl.Vector3{tip.x, ground+0.03, tip.z}
	along := b-a
	if rl.Vector3Length(along) < 0.0001 { return }
	side := rl.Vector3Normalize(rl.Vector3{-along.z, 0, along.x})
	for layer in 0..<2 {
		half := f32(0.045) if layer == 0 else f32(0.022)
		tone := u8(40) if layer == 0 else u8(70)
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(0, 0, 0, tone)
		rlgl.Vertex3f(a.x-side.x*half, a.y, a.z-side.z*half)
		rlgl.Vertex3f(a.x+side.x*half, a.y, a.z+side.z*half)
		rlgl.Vertex3f(b.x+side.x*half, b.y, b.z+side.z*half)
		rlgl.Vertex3f(b.x-side.x*half, b.y, b.z-side.z*half)
		rlgl.End()
	}
}

// In the paper pass: each bolt in flight with its streak of air and its
// shadow, and the bolts stuck where they landed.
@(private)
draw_enemy_arrows :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil { return }
	// Nothing to draw, nothing to flush: the batch goes on unbroken.
	now := renderer.sprite_assets.elapsed
	busy := room.arrows.count > 0
	for bolt in renderer.tactical.enemy_bolts.stuck { busy = busy || (bolt.at > 0 && now-bolt.at < ENEMY_BOLT_STUCK_SECONDS) }
	if !busy { return }
	texel := enemy_bolt_texel()
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	for arrow in room.arrows.items[:room.arrows.count] {
		centre, way := enemy_bolt_place(room, arrow)
		cell := grid.Position{x = int(math.round(centre.x)), y = int(math.round(centre.y)), layer = i8(arrow.origin.z)}
		if !tactical_render_visible(renderer, cell) { continue }
		ground := point_ground(centre)
		heading := rl.Vector3{way.x, 0, way.y}
		tip := rl.Vector3{centre.x+0.5, ground+ENEMY_ARROW_HEIGHT, centre.y+0.5}+heading*(ENEMY_BOLT_LENGTH*0.5)
		tail := tip-heading*ENEMY_BOLT_LENGTH
		draw_enemy_bolt_shadow(tail, tip, ground)
		// The streak never reaches back past the bow it left.
		flown := game.enemy_arrow_distance(room, arrow)+ENEMY_BOLT_LENGTH*0.5
		streak := clamp(flown-ENEMY_BOLT_LENGTH, 0, ENEMY_BOLT_TRAIL)
		if streak > 0.01 {
			draw_enemy_bolt_ribbon(renderer, tail+heading*0.08, tail-heading*streak, ENEMY_BOLT_TRAIL_WIDTH, 0, 0.75, 0, ENEMY_BOLT_AIR)
			lift := rl.Vector3{0, 0.06, 0}
			draw_enemy_bolt_ribbon(renderer, tail+lift, tail+lift-heading*streak*0.6, 0.022, 0, 0.45, 0, ENEMY_BOLT_AIR)
			draw_enemy_bolt_ribbon(renderer, tail-lift, tail-lift-heading*streak*0.6, 0.022, 0, 0.45, 0, ENEMY_BOLT_AIR)
		}
		rlgl.DrawRenderBatchActive()
		draw_attack_prop(renderer, .Quarrel, tail, tip, texel, 1)
	}
	for bolt in renderer.tactical.enemy_bolts.stuck {
		if bolt.at <= 0 || !tactical_render_visible(renderer, bolt.cell) { continue }
		tail, tip, opacity, shown := enemy_bolt_stuck_pose(bolt, now)
		if shown { draw_attack_prop(renderer, .Quarrel, tail, tip, texel, opacity) }
	}
}

// --------------------------------------------------------------------------
// Landed

// A stuck bolt at `now`: its tail and head, how opaque, whether it shows.
enemy_bolt_stuck_pose :: proc(bolt: Enemy_Bolt_Stuck, now: f64) -> (tail, tip: rl.Vector3, opacity: f32, shown: bool) {
	t := now-bolt.at
	if bolt.at <= 0 || t < 0 { return }
	tip, opacity = bolt.tip, 1
	switch bolt.rest {
	case .Wall, .Floor:
		if t >= ENEMY_BOLT_STUCK_SECONDS { return }
		opacity = clamp(f32((ENEMY_BOLT_STUCK_SECONDS-t)/ENEMY_BOLT_FADE_SECONDS), 0, 1)
		way := bolt.way
		if bolt.rest == .Floor { way = rl.Vector3Normalize(way*math.cos(ENEMY_BOLT_FALL)+rl.Vector3{0, -math.sin(ENEMY_BOLT_FALL), 0}) }
		tail = tip-way*ENEMY_BOLT_LENGTH
		// The tail quivers across its flight, dying away.
		swing := ENEMY_BOLT_QUIVER*math.exp(-f32(t)/ENEMY_BOLT_QUIVER_TAU)*math.sin(f32(t)*math.TAU*ENEMY_BOLT_QUIVER_HZ)
		across := rl.Vector3{0, 1, 0} if bolt.rest == .Wall else rl.Vector3{-bolt.way.z, 0, bolt.way.x}
		tail += across*swing
	case .Card:
		if t >= ENEMY_BOLT_PINNED_SECONDS+ENEMY_BOLT_DROP_SECONDS { return }
		fall := f32(max(0, t-ENEMY_BOLT_PINNED_SECONDS)/ENEMY_BOLT_DROP_SECONDS)
		tip += rl.Vector3{0, -0.35*fall*fall, 0}
		tail = tip-bolt.way*ENEMY_BOLT_LENGTH*0.7+rl.Vector3{0, 0.3*fall, 0}
		opacity = 1-fall
	}
	return tail, tip, opacity, opacity > 0.01
}

@(private = "file")
enemy_bolt_seen :: proc(b: ^Enemy_Bolts, cue: ^Presentation_Cue, now: f64) -> bool {
	for seen in b.seen {
		if seen.at > 0 && now-seen.at < JUICE_SEEN_SECONDS && seen.kind == cue.kind && seen.batch == cue.batch && seen.event == cue.event { return true }
	}
	b.seen[b.seen_next] = {kind = cue.kind, event = cue.event, batch = cue.batch, at = max(now, 0.000001)}
	b.seen_next = (b.seen_next+1)%ENEMY_BOLT_SEEN
	return false
}

// Whether the bolt of `cue` wounded the one it reached: a Damage of its
// command on them (a guard, RIFLESSO or the Stegosauro sent it back).
@(private = "file")
enemy_bolt_wounds :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	wounds :: proc(other: ^Presentation_Cue, cue: ^Presentation_Cue) -> bool {
		return other.kind == .Damage && other.event.target == cue.event.target && other.batch == cue.batch
	}
	for offset in 0..<renderer.timeline.count {
		if other, found := presentation_cue_at(&renderer.timeline, offset); found && wounds(other, cue) { return true }
	}
	if w := renderer.world_playback; w != nil {
		for &entry in w.cues[:w.count] { if wounds(&entry.cue, cue) { return true } }
	}
	return false
}

// Whether a missed bolt sticks in wood, else stone: the stockades, trees and
// bamboo of the Far West, the Giungla and the Vietnam (campaign.Biome 1, 2
// and 5); the crypt, the cover, the ice and every other land are hard.
enemy_bolt_in_wood :: proc(room: ^game.Room) -> bool {
	if room == nil || room.player == nil || !room.player.tactical.config.expedition { return false }
	biome := room.player.tactical.config.expedition_biome
	return biome == 1 || biome == 2 || biome == 5
}

// Where a landed bolt stays: stuck in the face of the wall it struck, in the
// floor where it fell, or in the card it wounded.
enemy_bolt_landing :: proc(room: ^game.Room, event: game.Game_Event) -> (bolt: Enemy_Bolt_Stuck, ok: bool) {
	origin, cell := event.from_position, event.to_position
	dx, dy := cell.x-origin.x, cell.y-origin.y
	if (dx == 0) == (dy == 0) { return }
	way := rl.Vector3{f32(math.sign(f32(dx))), 0, f32(math.sign(f32(dy)))}
	before := grid.Position{x = cell.x-int(way.x), y = cell.y-int(way.z), layer = cell.layer}
	bolt.way, bolt.cell = way, cell
	if event.target != game.SYSTEM_ENTITY {
		ground := point_ground({f32(cell.x), f32(cell.y)})
		bolt.rest, bolt.tip = .Card, rl.Vector3{f32(cell.x)+0.5, ground+ENEMY_ARROW_HEIGHT*0.9, f32(cell.y)+0.5}-way*0.15
	} else if game.enemy_arrow_struck_wall(room, origin, cell) {
		// Its head in the wall's face, at the height it flew.
		ground := point_ground({f32(before.x), f32(before.y)})
		bolt.rest, bolt.cell = .Wall, before
		bolt.tip = rl.Vector3{f32(cell.x)+0.5, ground+ENEMY_ARROW_HEIGHT, f32(cell.y)+0.5}-way*(0.5-ENEMY_BOLT_BITE)
	} else {
		ground := point_ground({f32(cell.x), f32(cell.y)})
		bolt.rest, bolt.tip = .Floor, rl.Vector3{f32(cell.x)+0.5, ground-0.08, f32(cell.y)+0.5}+way*0.1
	}
	return bolt, true
}

// Once a frame with the cues: each bolt landed stays where it landed, and in
// the lab knocks into wood or cracks on stone where it missed.
@(private)
observe_enemy_bolts :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer == nil || room == nil { return }
	b := &renderer.tactical.enemy_bolts
	now := renderer.sprite_assets.elapsed
	world := tactical_world_time_at(renderer, now)
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Arrow_Landed { continue }
		if enemy_bolt_seen(b, cue, world) { continue }
		bolt, ok := enemy_bolt_landing(room, cue.event)
		if !ok || (bolt.rest == .Card && !enemy_bolt_wounds(renderer, cue)) { continue }
		bolt.at = max(now, 0.000001)
		b.stuck[b.stuck_next] = bolt
		b.stuck_next = (b.stuck_next+1)%ENEMY_BOLT_STUCK
		b.landed[bolt.rest] += 1
		if s := renderer.tactical.lab_sounds; s != nil && renderer.tactical.mechanics_lab && bolt.rest != .Card {
			at := view.Vec2{bolt.tip.x-0.5, bolt.tip.z-0.5}
			ear := renderer.tactical.snapshot.player.position
			volume := clamp(1/(1+rl.Vector2Length(at-ear)/6), 0.45, 1)
			lab_sound_queue(s, LAB_BOLT_WOOD if enemy_bolt_in_wood(room) else LAB_BOLT_STONE, now, volume, enemy_bolt_pan(renderer, at))
		}
	}
}

// --------------------------------------------------------------------------
// The whistle (lab only)

// Left and right of a point of the board, as lab_sound_pan hears an actor.
@(private = "file")
enemy_bolt_pan :: proc(renderer: ^Renderer, at: view.Vec2) -> f32 {
	if renderer.canvas_width <= 0 { return 0 }
	if renderer.tactical.first_person.amount > 0 {
		camera := renderer.tactical.camera
		toward := rl.Vector3{at.x+0.5, camera.position.y, at.y+0.5}-camera.position
		if rl.Vector3Length(toward) < 0.001 { return 0 }
		return clamp(rl.Vector3DotProduct(rl.Vector3Normalize(toward), flipbook_camera_right(renderer)), -1, 1)*0.55
	}
	p := tactical_project(renderer, at)
	return clamp((p.x/f32(renderer.canvas_width))*2-1, -1, 1)*0.55
}

// A flying bolt's whistle at `at` going `way`, heard by the Viandante at
// `ear`: louder as it nears him, higher as it comes, lower as it goes.
enemy_bolt_whistle :: proc(at, way, ear: view.Vec2) -> (volume, pitch: f32) {
	d := at-ear
	distance := rl.Vector2Length(d)
	q := distance/ENEMY_BOLT_NEAR
	volume = ENEMY_BOLT_FAR+(1-ENEMY_BOLT_FAR)/(1+q*q)
	going := f32(0)
	if distance > 0.001 { going = clamp(rl.Vector2DotProduct(way, d/distance), -1, 1) }
	pitch = 1-ENEMY_BOLT_DOPPLER*going
	return
}

// Which bolt an arrow is, from its archer, its bow and its way (never 0).
@(private = "file")
enemy_bolt_key :: proc(arrow: game.Enemy_Arrow) -> u32 {
	h := arrow.shooter*2654435761 ~ u32(u16(arrow.origin.x))*40503 ~ u32(u16(arrow.origin.y))*69069 ~
	     u32(u8(arrow.origin.z))*7919 ~ u32(u8(arrow.step.x))*131 ~ u32(u8(arrow.step.y))*137
	return h | 1
}

// Every frame in the lab: each flying bolt keeps its voice, a new one takes a
// free voice (and is heard: played), a landed one lets its voice go; each
// whistles as it flies and holds when the world stands still.
@(private)
lab_bolt_flights :: proc(renderer: ^Renderer, room: ^game.Room, s: ^Lab_Sounds) {
	keys: [audio.LAB_FLIGHTS]u32
	count := min(room.arrows.count, audio.LAB_FLIGHTS)
	for index in 0..<count { keys[index] = enemy_bolt_key(room.arrows.items[index]) }
	// The voices of bolts gone.
	for &flight, slot in s.flights {
		if flight.key == 0 { continue }
		kept := false
		for key in keys[:count] { kept = kept || key == flight.key }
		if !kept { flight, s.flight_flown[slot], s.flight_still[slot] = {}, 0, 0 }
	}
	ear := renderer.tactical.snapshot.player.position
	for index in 0..<count {
		arrow := room.arrows.items[index]
		slot := -1
		for flight, at in s.flights { if flight.key == keys[index] { slot = at; break } }
		if slot < 0 {
			for flight, at in s.flights { if flight.key == 0 { slot = at; break } }
			if slot < 0 { continue }
			s.flights[slot].key = keys[index]
			s.flight_flown[slot], s.flight_still[slot] = -1, 0
			s.played[LAB_BOLT_FLIGHT] += 1
		}
		flown := game.enemy_arrow_distance(room, arrow)
		if flown > s.flight_flown[slot]+0.00001 { s.flight_still[slot] = 0 } else if s.flight_still[slot] < 255 { s.flight_still[slot] += 1 }
		s.flight_flown[slot] = flown
		centre, way := enemy_bolt_place(room, arrow)
		volume, pitch := enemy_bolt_whistle(centre, way, ear)
		f := &s.flights[slot]
		f.volume, f.pitch, f.pan = volume, pitch, enemy_bolt_pan(renderer, centre)
		f.running = s.flight_still[slot] < ENEMY_BOLT_STILL_FRAMES
	}
}
