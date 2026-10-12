package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../grid"

// Every enemy intent gets a paper sticker beside its health label: a
// hand-cut ivory disc with an inked pictogram that moves in a short loop, so
// what an enemy is about to do reads at a glance. A committed wind-up warms
// the paper red, shakes it and rings it.

Intent_Icon :: enum u8 {None, Strike, Shoot, Charge, Bombard, Protect, Move, Retreat, Wait, Recover, Interrupted}

INTENT_PAPER :: rl.Color{228, 220, 199, 255}
INTENT_PAPER_ALARM :: rl.Color{240, 196, 172, 255}
INTENT_INK :: rl.Color{13, 20, 30, 255}
INTENT_STEEL :: rl.Color{176, 189, 204, 255}
INTENT_CRIMSON :: rl.Color{196, 44, 44, 255}
INTENT_LEATHER :: rl.Color{122, 82, 52, 255}
INTENT_BLUE :: rl.Color{92, 168, 226, 255}
INTENT_AMBER :: rl.Color{232, 168, 64, 255}
INTENT_AIR :: rl.Color{168, 178, 186, 255}
INTENT_STICKER_RADIUS :: f32(14)

// Between an enemy acting and planning again its intent is briefly empty;
// the sticker keeps the last plan instead of blinking out for that instant.
Intent_Memory :: struct {
	id: u32,
	icon: Intent_Icon,
	alarm, used: bool,
}

remembered_intent_icon :: proc(renderer: ^Renderer, id: u32, icon: Intent_Icon, alarm: bool) -> (Intent_Icon, bool) {
	memory := &renderer.tactical.intent_memory
	slot := -1
	for &entry, index in memory {
		if entry.used && entry.id == id { slot = index; break }
		if !entry.used && slot < 0 { slot = index }
	}
	if slot < 0 { slot = int(id)%len(memory) }
	entry := &memory[slot]
	if !entry.used || entry.id != id { entry^ = {id = id, used = true} }
	if icon == .None && entry.icon != .None { return entry.icon, entry.alarm }
	entry.icon, entry.alarm = icon, alarm
	return icon, alarm
}

tactical_intent_icon :: proc(room: ^game.Room, enemy: ^game.Enemy) -> Intent_Icon {
	if game.enemy_is_staggered(room, enemy) { return .Interrupted }
	switch enemy.intent.kind {
	case .None: return .None
	case .Wait: return .Wait
	case .Recover: return .Recover
	case .Protect: return .Protect
	case .Charge: return .Charge
	case .Bombard: return .Bombard
	case .Attack:
		if enemy.archetype == .Archer { return .Shoot }
		if enemy.archetype == .Bomber || enemy.archetype == .Demolitionist { return .Bombard }
		return .Strike
	case .Move:
		// Moving away from the hero is a retreat, not an approach.
		hero := room.player.position
		before := grid_distance(enemy.intent.origin, hero)
		after := grid_distance(enemy.intent.destination, hero)
		return .Retreat if after > before else .Move
	}
	return .None
}

@(private="file")
grid_distance :: proc(a, b: grid.Position) -> int {
	return max(abs(a.x-b.x), abs(a.y-b.y))
}

@(private="file")
icon_point :: proc(center: rl.Vector2, r: f32, x, y: f32, angle: f32 = 0, pivot := rl.Vector2{}) -> rl.Vector2 {
	p := rl.Vector2{x, y}-pivot
	c, s := math.cos(angle), math.sin(angle)
	return center+(rl.Vector2{p.x*c-p.y*s, p.x*s+p.y*c}+pivot)*r
}

// An inked stroke: the ink first, a little wider, then the colour.
@(private="file")
stroke :: proc(a, b: rl.Vector2, width: f32, color: rl.Color) {
	rl.DrawLineEx(a, b, width+2, INTENT_INK)
	rl.DrawCircleV(a, (width+2)*0.5, INTENT_INK)
	rl.DrawCircleV(b, (width+2)*0.5, INTENT_INK)
	rl.DrawLineEx(a, b, width, color)
}

@(private="file")
blob :: proc(center: rl.Vector2, radius: f32, color: rl.Color) {
	rl.DrawCircleV(center, radius+1, INTENT_INK)
	rl.DrawCircleV(center, radius, color)
}

@(private="file")
fill :: proc(points: []rl.Vector2, color: rl.Color) {
	// Fans around the first point; culling is off while stickers draw.
	for index in 1..<len(points)-1 { rl.DrawTriangle(points[0], points[index], points[index+1], color) }
}

@(private="file")
outlined :: proc(points: []rl.Vector2, color: rl.Color) {
	fill(points, color)
	for index in 0..<len(points) { rl.DrawLineEx(points[index], points[(index+1)%len(points)], 1.6, INTENT_INK) }
}

draw_intent_sticker :: proc(center: rl.Vector2, icon: Intent_Icon, alarm: bool, time: f64, seed: int) {
	if icon == .None { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	t := f32(math.mod(time, 1000))
	c := center
	if alarm { c.x += math.sin(t*46)*1.1 }
	r := INTENT_STICKER_RADIUS
	// Scissor-cut outline: a fixed wobble per enemy, never per frame.
	cut: [14]rl.Vector2
	shadow: [14]rl.Vector2
	for index in 0..<len(cut) {
		a := f32(index)/f32(len(cut))*math.TAU
		wobble := 1+0.07*math.sin(f32(seed%13)*1.7+f32(index)*2.3)
		cut[index] = c+rl.Vector2{math.cos(a), math.sin(a)}*r*wobble
		shadow[index] = cut[index]+{2, 2.5}
	}
	fill(shadow[:], {0, 0, 0, 110})
	if alarm {
		pulse := 0.5+0.5*math.sin(t*9)
		rl.DrawRing(c, r+2, r+3.5+pulse*2, 0, 360, 24, color_with_opacity(INTENT_CRIMSON, 0.35+0.4*pulse))
	}
	outlined(cut[:], INTENT_PAPER_ALARM if alarm else INTENT_PAPER)
	u := r*0.78
	switch icon {
	case .None:
	case .Strike:
		// A sword swinging back and forth about its hilt, with a swish.
		swing := math.sin(t*7)*0.75
		hilt := rl.Vector2{-0.35, 0.42}
		tip := icon_point(c, u, 0.45, -0.52, swing-0.15, hilt)
		guard_a := icon_point(c, u, -0.58, 0.18, swing-0.15, hilt)
		guard_b := icon_point(c, u, -0.12, 0.66, swing-0.15, hilt)
		base := icon_point(c, u, -0.35, 0.42, swing-0.15, hilt)
		pommel := icon_point(c, u, -0.6, 0.68, swing-0.15, hilt)
		trail := icon_point(c, u, 0.62, -0.1, swing*0.5-0.9, hilt)
		rl.DrawLineEx(icon_point(c, u, 0.68, -0.2, swing-0.45, hilt), trail, 1.4, color_with_opacity(INTENT_AIR, 0.8))
		stroke(base, tip, 3, INTENT_STEEL)
		stroke(guard_a, guard_b, 2.4, INTENT_CRIMSON)
		stroke(base, pommel, 2.2, INTENT_LEATHER)
	case .Shoot:
		// A bolt drawn back on the string, then loosed.
		cycle := t*1.3-math.floor(t*1.3)
		pull := -0.25*min(cycle/0.7, 1)
		if cycle > 0.7 { pull = -0.25+(cycle-0.7)/0.3*1.1 }
		bow := [5]rl.Vector2{icon_point(c, u, -0.2, -0.75), icon_point(c, u, -0.45, -0.4), icon_point(c, u, -0.52, 0),
			icon_point(c, u, -0.45, 0.4), icon_point(c, u, -0.2, 0.75)}
		for index in 0..<4 { stroke(bow[index], bow[index+1], 2.2, INTENT_LEATHER) }
		string_x := min(-0.2+pull, -0.2)
		rl.DrawLineEx(bow[0], icon_point(c, u, string_x, 0), 1.2, INTENT_INK)
		rl.DrawLineEx(bow[4], icon_point(c, u, string_x, 0), 1.2, INTENT_INK)
		stroke(icon_point(c, u, -0.3+pull, 0), icon_point(c, u, 0.55+pull, 0), 2, INTENT_STEEL)
		head := [3]rl.Vector2{icon_point(c, u, 0.75+pull, 0), icon_point(c, u, 0.5+pull, -0.18), icon_point(c, u, 0.5+pull, 0.18)}
		outlined(head[:], INTENT_CRIMSON)
	case .Charge:
		// Two chevrons dashing forward over speed lines.
		dash := t*2.2-math.floor(t*2.2)
		for index in 0..<2 {
			x := -0.45+f32(index)*0.45+dash*0.25
			stroke(icon_point(c, u, x-0.18, -0.42), icon_point(c, u, x+0.18, 0), 2.6, INTENT_CRIMSON)
			stroke(icon_point(c, u, x+0.18, 0), icon_point(c, u, x-0.18, 0.42), 2.6, INTENT_CRIMSON)
		}
		for index in 0..<3 {
			y := -0.5+f32(index)*0.5
			rl.DrawLineEx(icon_point(c, u, -0.95+dash*0.3, y), icon_point(c, u, -0.6+dash*0.3, y), 1.2, color_with_opacity(INTENT_AIR, 1-dash))
		}
	case .Bombard:
		// A bomb rocking on its lit fuse.
		rock := math.sin(t*5)*0.18
		blob(icon_point(c, u, 0, 0.18, rock, {0, 0.18}), u*0.52, {44, 46, 54, 255})
		rl.DrawCircleV(icon_point(c, u, -0.16, 0.0, rock, {0, 0.18}), u*0.12, {120, 124, 136, 255})
		fuse_top := icon_point(c, u, 0.38, -0.62, rock, {0, 0.18})
		stroke(icon_point(c, u, 0.22, -0.28, rock, {0, 0.18}), fuse_top, 1.6, INTENT_LEATHER)
		spark := 0.5+0.5*math.sin(t*31)
		for index in 0..<4 {
			a := f32(index)*math.PI*0.5+t*6
			rl.DrawLineEx(fuse_top, fuse_top+rl.Vector2{math.cos(a), math.sin(a)}*(2+spark*3), 1.4, INTENT_AMBER)
		}
		rl.DrawCircleV(fuse_top, 1.6+spark, {255, 236, 170, 255})
	case .Protect:
		// A shield with a cross, its ward pulsing.
		ward := 0.5+0.5*math.sin(t*4)
		rl.DrawRing(c, u*(0.8+ward*0.15), u*(0.9+ward*0.15), 0, 360, 20, color_with_opacity(INTENT_BLUE, 0.6-ward*0.3))
		shield := [6]rl.Vector2{icon_point(c, u, -0.5, -0.55), icon_point(c, u, 0.5, -0.55), icon_point(c, u, 0.5, 0.05),
			icon_point(c, u, 0, 0.7), icon_point(c, u, -0.5, 0.05), icon_point(c, u, -0.5, -0.55)}
		outlined(shield[:5], INTENT_BLUE)
		stroke(icon_point(c, u, 0, -0.38), icon_point(c, u, 0, 0.36), 1.6, INTENT_PAPER)
		stroke(icon_point(c, u, -0.28, -0.12), icon_point(c, u, 0.28, -0.12), 1.6, INTENT_PAPER)
	case .Move, .Retreat:
		// A running boot with puffs of air behind it; a retreat runs the
		// other way under a turning-back arrow.
		dir := f32(-1) if icon == .Retreat else 1
		bob := math.abs(math.sin(t*9))*0.16
		// Listed from the heel, so the fan stays inside the boot.
		boot := [6]rl.Vector2{
			icon_point(c, u, dir*-0.28, 0.48+bob), icon_point(c, u, dir*-0.28, -0.62+bob), icon_point(c, u, dir*0.12, -0.62+bob),
			icon_point(c, u, dir*0.12, 0.08+bob), icon_point(c, u, dir*0.62, 0.22+bob), icon_point(c, u, dir*0.62, 0.48+bob)}
		outlined(boot[:], INTENT_LEATHER)
		stroke(icon_point(c, u, dir*-0.28, -0.42+bob), icon_point(c, u, dir*0.12, -0.42+bob), 1.2, {84, 54, 34, 255})
		for index in 0..<3 {
			phase := t*2.4+f32(index)/3
			k := phase-math.floor(phase)
			p := icon_point(c, u, dir*(-0.45-k*0.45), 0.38-f32(index)*0.22-k*0.1)
			rl.DrawCircleV(p, (1.5+k*2.5), color_with_opacity(INTENT_AIR, 1-k))
		}
		if icon == .Retreat {
			arc := [4]rl.Vector2{icon_point(c, u, 0.55, -0.35), icon_point(c, u, 0.42, -0.7), icon_point(c, u, 0.05, -0.78), icon_point(c, u, -0.2, -0.62)}
			for index in 0..<3 { stroke(arc[index], arc[index+1], 1.6, INTENT_CRIMSON) }
			head := [3]rl.Vector2{icon_point(c, u, -0.36, -0.52), icon_point(c, u, -0.12, -0.8), icon_point(c, u, -0.06, -0.48)}
			outlined(head[:], INTENT_CRIMSON)
		}
	case .Wait:
		// An hourglass that turns over every second and a half.
		cycle := t/1.5-math.floor(t/1.5)
		angle := f32(0) if cycle < 0.8 else (cycle-0.8)/0.2*math.PI
		top := [3]rl.Vector2{icon_point(c, u, -0.42, -0.62, angle), icon_point(c, u, 0.42, -0.62, angle), icon_point(c, u, 0, 0, angle)}
		bottom := [3]rl.Vector2{icon_point(c, u, 0, 0, angle), icon_point(c, u, 0.42, 0.62, angle), icon_point(c, u, -0.42, 0.62, angle)}
		outlined(top[:], INTENT_AMBER)
		outlined(bottom[:], INTENT_PAPER)
		stroke(icon_point(c, u, -0.5, -0.66, angle), icon_point(c, u, 0.5, -0.66, angle), 1.6, INTENT_LEATHER)
		stroke(icon_point(c, u, -0.5, 0.66, angle), icon_point(c, u, 0.5, 0.66, angle), 1.6, INTENT_LEATHER)
	case .Recover, .Interrupted:
		// Dizzy stars circling a knot.
		for index in 0..<3 {
			a := t*3.4+f32(index)*math.TAU/3
			p := c+rl.Vector2{math.cos(a)*u*0.55, math.sin(a)*u*0.3}
			star: [10]rl.Vector2
			for k in 0..<10 {
				ka := f32(k)*math.PI/5-math.PI*0.5+t*2
				rr := u*(0.3 if k%2 == 0 else 0.13)
				star[k] = p+rl.Vector2{math.cos(ka), math.sin(ka)}*rr
			}
			for k in 0..<10 { rl.DrawTriangle(p, star[k], star[(k+1)%10], INTENT_AMBER if icon == .Recover else INTENT_PAPER_ALARM) }
			for k in 0..<10 { rl.DrawLineEx(star[k], star[(k+1)%10], 1.4, INTENT_INK) }
		}
	}
}
