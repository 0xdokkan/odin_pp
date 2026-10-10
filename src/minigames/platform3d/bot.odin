package platform3d

import "core:math"
import physics "../../engine/physics"

MAX_ROUTE :: 192

Bot_Mode :: enum u8 {
	Approach, // walking to the run-up spot
	Run,      // running at the edge, jumps when it gets there
	Air,      // a planned jump is in flight
}

// Scripted player for tests and the preview autoplay. It follows the main
// path, detours through every branch for its shard and waits out shuttles,
// spikes and sentinels. It only reads the world, through the same
// Player_Input a human produces.
Bot :: struct {
	route: [MAX_ROUTE]int,
	count: int,
	index: int,
	mode:  Bot_Mode,
	from:  int, // last pad stood on
}

bot_init :: proc(b: ^Bot, w: ^World) {
	b^ = {}
	push :: proc(b: ^Bot, p: int) {
		if b.count < MAX_ROUTE {
			b.route[b.count] = p
			b.count += 1
		}
	}
	for i in 0..<w.path_count {
		root := w.path[i]
		push(b, root)
		for t in 0..<w.pad_count {
			tip := w.pads[t]
			if !tip.branch || tip.shard < 0 || branch_root(w, t) != root {
				continue
			}
			chain: [8]int
			n := 0
			for c := t; c != root && n < len(chain); c = w.pads[c].parent {
				chain[n] = c
				n += 1
			}
			for k := n - 1; k >= 0; k -= 1 {
				push(b, chain[k])
			}
			for k in 1..<n {
				push(b, chain[k])
			}
			push(b, root)
		}
	}
	b.from = w.path[0]
}

branch_root :: proc(w: ^World, pad: int) -> int {
	p := pad
	for p >= 0 && w.pads[p].branch {
		p = w.pads[p].parent
	}
	return p
}

bot_input :: proc(b: ^Bot, w: ^World) -> Player_Input {
	out: Player_Input
	if w.phase != .Alive || w.status != .Playing || b.count == 0 {
		b.mode = .Approach
		return out
	}
	p := w.player
	feet := physics.body3_feet(p.body)
	pos := Vec2{feet.x, feet.z}
	standing := standing_pad(w)
	if standing >= 0 {
		bot_resync(b, standing)
		b.from = standing
	}
	for b.index < b.count && standing == b.route[b.index] {
		s := w.pads[standing].shard
		if s >= 0 && !w.shards[s].taken {
			break
		}
		b.index += 1
		b.mode = .Approach
	}
	if b.index >= b.count {
		out.move = steer(pos, Vec2{w.portal_center.x, w.portal_center.z}, 0.3)
		return out
	}
	target := b.route[b.index]
	if standing == target {
		// Stand under the shard; jump for it when it floats high.
		shard := w.shards[w.pads[target].shard]
		goal := Vec2{shard.position.x, shard.position.z}
		out.move = steer(pos, goal, 0.3)
		if physics.length2(goal-pos) < 0.45 && shard.position.y-feet.y > 1.4 {
			out.jump_pressed = true
			out.jump_held = true
		}
		return out
	}
	if !p.grounded {
		bot_air(b, w, target, pos, feet, &out)
		return out
	}
	if br, ok := bot_bridge(w, b.from, target); ok {
		bot_walk_bridge(b, w, br, target, standing, pos, &out)
		return out
	}
	cur := standing if standing >= 0 else b.from
	clo, chi, _ := pad_area(w, cur)
	tlo, thi, _ := departure_area(w, cur, target)
	takeoff := takeoff_point(clo, chi, tlo, thi)
	landing := landing_point(tlo, thi, takeoff)
	dir := physics.normalize2(landing - takeoff)
	if b.mode == .Air {
		b.mode = .Approach
	}
	if b.mode == .Approach {
		spot := takeoff
		// A long jump wants a run-up; crumbling slabs leave no time for one.
		if physics.length2(landing-takeoff) > 2.6 && w.pads[cur].kind != .Crumble {
			// Shorten the run-up rather than wait inside a hazard band.
			for run := f32(1.4); run > 0.1; run -= 0.35 {
				spot = clamp_into(takeoff-dir*run, clo, chi, 0.3)
				if !in_hazard_band(w, cur, spot) {
					break
				}
				spot = takeoff
			}
		}
		if physics.length2(spot-pos) > 0.3 {
			if hazard_ahead(w, cur, pos, spot) {
				return out
			}
			out.move = steer(pos, spot, 0.2)
			return out
		}
		if !ready_to_leave(w, cur, target) {
			return out
		}
		b.mode = .Run
	}
	if hazard_ahead(w, cur, pos, landing) {
		b.mode = .Approach
		return out
	}
	out.move = physics.normalize2(landing - pos)
	if physics.length2(landing-takeoff) < 0.05 || (pos.x-takeoff.x)*dir.x+(pos.y-takeoff.y)*dir.y >= -0.05 {
		out.jump_pressed = true
		out.jump_held = true
		b.mode = .Air
	}
	return out
}

// After a respawn or a lucky landing, continue from where the bot stands.
@(private)
bot_resync :: proc(b: ^Bot, standing: int) {
	if b.index < b.count && standing == b.route[b.index] {
		return
	}
	if b.index > 0 && standing == b.route[b.index-1] {
		return
	}
	for k := min(b.index, b.count) - 1; k >= 0; k -= 1 {
		if b.route[k] == standing {
			b.index = k + 1
			b.mode = .Approach
			return
		}
	}
	for k in b.index..<b.count {
		if b.route[k] == standing {
			b.index = k
			b.mode = .Approach
			return
		}
	}
}

@(private)
bot_air :: proc(b: ^Bot, w: ^World, target: int, pos: Vec2, feet: Vec3, out: ^Player_Input) {
	p := w.player
	out.jump_held = true
	goal_pad := target
	if b.mode != .Air {
		// Not a planned jump (knocked or stepped off): head back where it was.
		goal_pad = b.from
		if b.mode == .Run {
			out.jump_pressed = true
			b.mode = .Air
			goal_pad = target
		}
	}
	tlo, thi, ttop := pad_area(w, goal_pad)
	landing := landing_point(tlo, thi, pos)
	out.move = steer(pos, landing, 0.6)
	over := pos.x > tlo.x+0.15 && pos.x < thi.x-0.15 && pos.y > tlo.y+0.15 && pos.y < thi.y-0.15
	if p.body.velocity.y < -0.5 && p.air_jumps_left > 0 && feet.y < ttop+0.9 && feet.y > ttop-2 && !over {
		out.jump_pressed = true
	}
}

@(private)
bot_bridge :: proc(w: ^World, from, to: int) -> (Bridge, bool) {
	for i in 0..<w.bridge_count {
		br := w.bridges[i]
		if br.from == from && br.to == to {
			return br, true
		}
	}
	return {}, false
}

// Walk the plank line, hopping wherever a plank is missing.
@(private)
bot_walk_bridge :: proc(b: ^Bot, w: ^World, br: Bridge, target, standing: int, pos: Vec2, out: ^Player_Input) {
	along := br.axis
	lat := 1 - along
	line := f32(br.lo[lat]+br.hi[lat]) * 0.5
	tc := pad_center(w.pads[target])
	sign := f32(1) if tc[along] > f32(br.lo[along]) else -1
	entry: Vec2
	entry[lat] = line
	entry[along] = f32(br.lo[along]) - 0.7 if sign > 0 else f32(br.hi[along]) + 0.7
	if b.mode == .Approach && standing >= 0 {
		if physics.length2(entry-pos) > 0.25 {
			out.move = steer(pos, entry, 0.15)
			return
		}
		b.mode = .Run
	}
	b.mode = .Run
	ahead := pos
	ahead[along] += sign * 1.5
	ahead[lat] = line
	out.move = physics.normalize2(ahead - pos)
	probe := pos
	probe[along] += sign * 0.55
	k := int(math.floor(probe[along])) - br.lo[along]
	inside := k >= 0 && k < br.hi[along]-br.lo[along]
	if inside && bridge_hole(br, k) {
		out.jump_pressed = true
		out.jump_held = true
		b.mode = .Air
	}
}

// Where to aim when leaving `cur` for `target`: shuttles are boarded at the
// end they wait at, not wherever they are right now.
@(private)
departure_area :: proc(w: ^World, cur, target: int) -> (lo, hi: Vec2, top: f32) {
	t := w.pads[target]
	if t.kind == .Shuttle && t.parent == cur {
		m := w.movers[t.mover]
		return Vec2{m.a.x, m.a.z}, Vec2{m.a.x + m.size.x, m.a.z + m.size.z}, m.a.y + m.size.y
	}
	return pad_area(w, target)
}

@(private)
ready_to_leave :: proc(w: ^World, cur, target: int) -> bool {
	t := w.pads[target]
	if t.kind == .Shuttle {
		end, remaining := shuttle_dwell(w.movers[t.mover], w.time)
		return end == 0 && remaining > 0.45
	}
	if t.kind == .Crumble && w.movers[t.mover].state != .Idle {
		return false
	}
	if c := w.pads[cur]; c.kind == .Shuttle {
		end, remaining := shuttle_dwell(w.movers[c.mover], w.time)
		return end == 1 && remaining > 0.35
	}
	return true
}

// True when walking from `pos` toward `goal` would enter a spike strip or a
// sentinel's patrol band of pad `pad` at a dangerous moment, and the bot is
// close enough that it has to wait now.
@(private)
hazard_ahead :: proc(w: ^World, pad: int, pos, goal: Vec2) -> bool {
	for i in 0..<w.spike_count {
		s := w.spikes[i]
		if s.pad != pad {
			continue
		}
		lo := s.lo - 0.45
		hi := s.hi + 0.45
		if !crosses(pos, goal, lo, hi) || rect_distance(pos, lo, hi) > 0.9 {
			continue
		}
		for k in 0..=6 {
			if spike_extension(s, w.time+0.65*f32(k)/6) > 0 {
				return true
			}
		}
	}
	for i in 0..<w.sentinel_count {
		s := w.sentinels[i]
		if s.pad != pad {
			continue
		}
		lo := Vec2{min(s.a.x, s.b.x), min(s.a.z, s.b.z)} - 0.85
		hi := Vec2{max(s.a.x, s.b.x), max(s.a.z, s.b.z)} + 0.85
		if !crosses(pos, goal, lo, hi) || rect_distance(pos, lo, hi) > 0.9 {
			continue
		}
		// Contact needs the wraith within 0.72 sideways; crossing the band
		// takes under half a second.
		across := 0 if abs(s.b.x-s.a.x) > abs(s.b.z-s.a.z) else 1
		for k in 0..=6 {
			sp := sentinel_position(s, w.time+0.55*f32(k)/6)
			flat := Vec2{sp.x, sp.z}
			if abs(flat[across]-pos[across]) < 1.25 {
				return true
			}
		}
	}
	return false
}

@(private)
in_hazard_band :: proc(w: ^World, pad: int, p: Vec2) -> bool {
	for i in 0..<w.spike_count {
		s := w.spikes[i]
		if s.pad == pad && inside_rect(p, s.lo-0.45, s.hi+0.45) {
			return true
		}
	}
	for i in 0..<w.sentinel_count {
		s := w.sentinels[i]
		lo := Vec2{min(s.a.x, s.b.x), min(s.a.z, s.b.z)} - 0.85
		hi := Vec2{max(s.a.x, s.b.x), max(s.a.z, s.b.z)} + 0.85
		if s.pad == pad && inside_rect(p, lo, hi) {
			return true
		}
	}
	return false
}

@(private)
crosses :: proc(a, b, lo, hi: Vec2) -> bool {
	if inside_rect(a, lo, hi) {
		return false // already in it: keep going
	}
	for k in 1..=16 {
		p := a + (b-a)*(f32(k)/16)
		if inside_rect(p, lo, hi) {
			return true
		}
	}
	return false
}

@(private)
inside_rect :: proc "contextless" (p, lo, hi: Vec2) -> bool {
	return p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y
}

@(private)
rect_distance :: proc "contextless" (p, lo, hi: Vec2) -> f32 {
	d := Vec2{max(lo.x-p.x, 0, p.x-hi.x), max(lo.y-p.y, 0, p.y-hi.y)}
	return physics.length2(d)
}

@(private)
clamp_into :: proc "contextless" (p, lo, hi: Vec2, inset: f32) -> Vec2 {
	r: Vec2
	for i in 0..<2 {
		a := lo[i] + inset
		b := hi[i] - inset
		r[i] = clamp(p[i], a, b) if a <= b else (lo[i]+hi[i])*0.5
	}
	return r
}

// Point on the current pad (kept inside) closest to the target pad.
@(private)
takeoff_point :: proc "contextless" (clo, chi, tlo, thi: Vec2) -> Vec2 {
	r: Vec2
	for i in 0..<2 {
		a := clo[i] + 0.35
		b := chi[i] - 0.35
		if a > b {
			r[i] = (clo[i] + chi[i]) * 0.5
			continue
		}
		switch {
		case tlo[i] >= chi[i]:
			r[i] = b
		case thi[i] <= clo[i]:
			r[i] = a
		case:
			// Overlapping range: aim at the middle of the shared part.
			r[i] = clamp((max(clo[i], tlo[i])+min(chi[i], thi[i]))*0.5, a, b)
		}
	}
	return r
}

// Point well inside the target pad nearest to `from`.
@(private)
landing_point :: proc "contextless" (tlo, thi, from: Vec2) -> Vec2 {
	r: Vec2
	for i in 0..<2 {
		inset := min(0.85, (thi[i]-tlo[i])*0.4)
		r[i] = clamp(from[i], tlo[i]+inset, thi[i]-inset)
	}
	return r
}

// Full speed toward a point, easing off inside `slow` of it.
@(private)
steer :: proc "contextless" (pos, goal: Vec2, slow: f32) -> Vec2 {
	d := goal - pos
	l := physics.length2(d)
	if l < 0.02 {
		return {}
	}
	return d / l * min(1, l/max(slow, 0.01))
}
