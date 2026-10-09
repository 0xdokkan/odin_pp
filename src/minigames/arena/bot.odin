// A simple deterministic autopilot. Tests use it to prove a round is
// winnable; the preview harness enables it (demo_autoplay) to capture action.
package arena

import "core:math"
import physics "../../engine/physics"
import pool "../../engine/pool"

// `skill` below 1 makes it sloppy (it notices only some orbs and never
// dashes), which approximates a human player when tuning difficulty.
bot_input :: proc(w: ^World, skill: f32 = 1) -> Player_Input {
	result: Player_Input
	p := &w.player
	if !p.alive {
		return result
	}
	steer: Vec2
	target: Vec2
	target_vel: Vec2
	target_score := max(f32)
	threat := false
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		d := p.pos - e.pos
		dist := physics.length2(d)
		// Prefer close enemies in sight; the boss is always worth shooting.
		score := dist
		if !physics.line_of_sight(&w.tiles, p.pos, e.pos) {
			score += 600
		}
		if e.kind == .Boss {
			score -= 150
		}
		if score < target_score {
			target_score = score
			target = e.pos
			target_vel = e.vel
		}
		danger := 120 + e.radius
		dangerous := (e.kind == .Charger || e.kind == .Boss) && (e.state == .Windup || e.state == .Attack)
		if dangerous {
			danger = 260
			// Step out of the charge line rather than backing straight away.
			side := Vec2{-e.facing.y, e.facing.x}
			if side.x*d.x+side.y*d.y < 0 {
				side = -side
			}
			along := e.facing.x*(-d.x) + e.facing.y*(-d.y)
			if along < 0 && dist < danger {
				steer += side * 2.2
			}
		}
		if dist < danger && dist > 0.01 {
			steer += d / dist * ((danger - dist) / danger) * 1.6
		}
		if dist < e.radius+PLAYER_RADIUS+16 {
			threat = true
		}
	}
	if target_score < max(f32) {
		dist := physics.length2(target - p.pos)
		lead := target + target_vel*(dist/BULLET_SPEED)
		result.aim = lead - p.pos
		result.fire = true
		// Keep a comfortable firing range.
		if dist > 300 {
			steer += physics.normalize2(target-p.pos) * 0.6
		}
	}
	oit := pool.iterator(&w.orbs)
	for o, oh in pool.next(&oit) {
		if skill < 1 && f32((oh.index*7919+oh.generation*104729)%100) >= skill*100 {
			continue
		}
		rel := p.pos - o.pos
		dist := physics.length2(rel)
		if dist > 150 {
			continue
		}
		v := physics.normalize2(o.vel)
		closing := rel.x*v.x + rel.y*v.y
		if closing <= 0 {
			continue
		}
		// Sidestep perpendicular to the orb's path.
		off := rel - v*closing
		side := physics.normalize2(off)
		if side == {} {
			side = Vec2{-v.y, v.x}
		}
		steer += side * ((150 - dist) / 150) * 2.6
		if dist < 34 && physics.length2(off) < 14 {
			threat = true
		}
	}
	pit := pool.iterator(&w.pickups)
	for pk in pool.next(&pit) {
		want := pk.kind != .Heart || p.hp < p.max_hp
		if want {
			steer += physics.normalize2(pk.pos-p.pos) * 0.9
		}
	}
	// Stay away from walls and drift back toward the open middle.
	for k in 0..<8 {
		angle := f32(k) * math.PI / 4
		dir := Vec2{math.cos(angle), math.sin(angle)}
		if !open_at(w, p.pos+dir*44) {
			steer -= dir * 0.7
		}
	}
	steer += (player_start() - p.pos) / 520
	result.move = physics.clamp_length2(steer*1.5, 1)
	if threat && p.dash_cooldown <= 0 && skill >= 1 {
		result.dash = true
	}
	return result
}
