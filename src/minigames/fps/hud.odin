package fps

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import camera "../../engine/camera"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import host "../../engine/host"
import physics "../../engine/physics"
import ui "../../engine/ui"

IVORY :: rl.Color{236, 226, 204, 255}
IVORY_DIM :: rl.Color{160, 152, 136, 255}
CRIMSON :: rl.Color{178, 38, 52, 255}
EMBER :: rl.Color{232, 196, 112, 255}
ARCANE :: rl.Color{96, 140, 240, 255}
VIOLET :: rl.Color{196, 130, 255, 255}
WARNING :: rl.Color{226, 168, 72, 255}
PANEL :: rl.Color{14, 14, 20, 175}

draw_hud :: proc(g: ^Game, frame: ^host.Frame, cam: rl.Camera3D) {
	w := &g.world
	v := &g.view
	width, height := frame.canvas.width, frame.canvas.height
	draw_marks(g, frame, cam)
	draw_viewmodel(g, width, height)
	gfx.draw_vignette(width, height, 0.42)
	if w.status == .Playing {
		draw_crosshair(v, width, height)
	}
	draw_damage(g, width, height)
	fx.flash_draw(v.flash, width, height)
	draw_bars(g, frame.theme, height)
	draw_runes(g, frame.theme)
	draw_compass(g, frame.theme, width)
	draw_score(g, frame.theme, width)
	if v.show_map {
		draw_minimap(g, width)
	}
	draw_banner(g, frame.theme, width)
	switch w.status {
	case .Playing:
	case .Lost:
		a := min(v.end_time*0.5, 0.45)
		rl.DrawRectangleRec({0, 0, width, height}, {90, 0, 8, u8(255 * a)})
	case .Won:
		a := min(v.end_time*0.6, 0.35)
		rl.DrawRectangleRec({0, 0, width, height}, {70, 30, 110, u8(255 * a)})
	}
}

@(private)
draw_marks :: proc(g: ^Game, frame: ^host.Frame, cam: rl.Camera3D) {
	v := &g.view
	fwd := camera.fps_forward(v.cam)
	for m in v.marks {
		if m.life <= 0 {
			continue
		}
		to := m.position - Vec3(cam.position)
		if to.x*fwd.x+to.y*fwd.y+to.z*fwd.z < 0.3 {
			continue
		}
		p := rl.GetWorldToScreenEx(m.position, cam, i32(frame.canvas.width), i32(frame.canvas.height))
		ui.draw_text_centered(frame.theme, m.text, {p.x, p.y}, .Body, ui.with_alpha(m.color, min(m.life*2, 1)))
	}
}

// The staff in the bottom-right corner: sways with the head bob, kicks back
// on every bolt and its crystal brightens with the mana it holds.
@(private)
draw_viewmodel :: proc(g: ^Game, width, height: f32) {
	v := &g.view
	w := &g.world
	s := v.sprites[.Staff]
	if s.texture.id == 0 {
		return
	}
	scale := f32(6)
	t := v.cam.bob_time
	sway := Vec2{math.sin(t*0.5) * 12, abs(math.cos(t*0.5)) * 9} * v.cam.bob_amount
	pos := Vec2{width * 0.75, height - f32(s.height)*scale*0.5 + 52} + sway + Vec2{v.kick * 10, v.kick * 34}
	rotation := -9 - v.kick*5 + sway.x*0.25
	if w.player.sprinting {
		pos += {34, 46}
		rotation -= 16
	}
	if w.status == .Lost {
		pos.y += v.end_time * 420
	}
	frame := 1 if v.muzzle > 0 else 0
	shade := u8(200 + 55*clamp(v.muzzle/MUZZLE_TIME, 0, 1))
	gfx.draw_sprite(s, frame, pos, scale, false, {shade, shade, shade, 255}, rotation)

	angle := rotation * math.PI / 180
	local := Vec2{0, -f32(s.height)*scale*0.5 + 3.5*scale}
	crystal := pos + physics.rotate2(local, angle)
	charge := w.player.mana / MAX_MANA
	pulse := 0.85 + 0.15*math.sin(v.time*3)
	rl.BeginBlendMode(.ADDITIVE)
	glow2d(v, crystal, (22+26*charge)*pulse, {255, 160, 70, u8(130 + 110*charge)})
	if v.muzzle > 0 {
		k := v.muzzle / MUZZLE_TIME
		glow2d(v, crystal, 110*k+30, {255, 220, 150, 255})
		rl.DrawCircleV(crystal, 14*k+4, {255, 250, 230, u8(255 * k)})
	}
	rl.EndBlendMode()
}

// Smooth additive halo from the radial glow texture (call inside ADDITIVE).
@(private)
glow2d :: proc(v: ^View, center: Vec2, radius: f32, color: rl.Color) {
	if v.glow.id == 0 {
		return
	}
	src := rl.Rectangle{0, 0, f32(v.glow.width), f32(v.glow.height)}
	dst := rl.Rectangle{center.x - radius, center.y - radius, radius * 2, radius * 2}
	rl.DrawTexturePro(v.glow, src, dst, {}, 0, color)
}

@(private)
draw_crosshair :: proc(v: ^View, width, height: f32) {
	cx, cy := math.round(width*0.5), math.round(height*0.5)
	gap := 5 + v.kick*8
	arm := f32(6)
	col := ui.with_alpha(IVORY, 0.85)
	rl.DrawRectangleRec({cx - gap - arm, cy - 1, arm, 2}, col)
	rl.DrawRectangleRec({cx + gap, cy - 1, arm, 2}, col)
	rl.DrawRectangleRec({cx - 1, cy - gap - arm, 2, arm}, col)
	rl.DrawRectangleRec({cx - 1, cy + gap, 2, arm}, col)
	rl.DrawRectangleRec({cx - 1, cy - 1, 2, 2}, col)
	if v.hitmarker > 0 {
		kill := v.killmarker > 0
		size := f32(13) if kill else f32(9)
		inner := f32(5)
		c := CRIMSON if kill else EMBER
		c.a = u8(255 * clamp(v.hitmarker/0.12, 0, 1))
		for d in ([4]Vec2{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}}) {
			rl.DrawLineEx({cx + d.x*inner, cy + d.y*inner}, {cx + d.x*size, cy + d.y*size}, 2.5, c)
		}
	}
}

@(private)
draw_damage :: proc(g: ^Game, width, height: f32) {
	v := &g.view
	w := &g.world
	center := rl.Vector2{width * 0.5, height * 0.5}
	if v.hurt_time > 0 {
		angle := -90 - v.hurt_angle*180/math.PI
		a := u8(220 * clamp(v.hurt_time, 0, 1))
		rl.DrawRing(center, 74, 90, angle-26, angle+26, 24, {230, 30, 40, a})
		rl.DrawRing(center, 90, 94, angle-18, angle+18, 16, {255, 140, 120, a / 2})
	}
	// Low health: the edges of the view throb red.
	if w.player.hp < 35 && w.status == .Playing {
		pulse := 0.6 + 0.4*math.sin(v.time*6)
		k := (1 - w.player.hp/35) * 0.55 + 0.25
		a := u8(255 * clamp(k*pulse, 0, 1))
		band := height * 0.28
		red := rl.Color{170, 0, 10, a}
		clear := rl.Color{170, 0, 10, 0}
		rl.DrawRectangleGradientV(0, 0, i32(width), i32(band), red, clear)
		rl.DrawRectangleGradientV(0, i32(height-band), i32(width), i32(band), clear, red)
		rl.DrawRectangleGradientH(0, 0, i32(band), i32(height), red, clear)
		rl.DrawRectangleGradientH(i32(width-band), 0, i32(band), i32(height), clear, red)
	}
}

@(private)
draw_bar :: proc(r: rl.Rectangle, value, ghost: f32, fill, back: rl.Color) {
	rl.DrawRectangleRec(r, back)
	g := r
	g.width = r.width * clamp(ghost, 0, 1)
	rl.DrawRectangleRec(g, {236, 226, 204, 150})
	f := r
	f.width = r.width * clamp(value, 0, 1)
	rl.DrawRectangleRec(f, fill)
	shine := f
	shine.height = max(r.height*0.3, 2)
	rl.DrawRectangleRec(shine, {255, 255, 255, 50})
	rl.DrawRectangleLinesEx({r.x - 1, r.y - 1, r.width + 2, r.height + 2}, 1, {0, 0, 0, 200})
}

@(private)
draw_bars :: proc(g: ^Game, theme: ^ui.Theme, height: f32) {
	w := &g.world
	v := &g.view
	p := w.player
	x, y := f32(18), height-64
	rl.DrawRectangleRounded({x - 10, y - 12, 262, 60}, 0.25, 6, PANEL)
	if v.pickup_pulse > 0 {
		// A pickup makes the vitals panel glint.
		rl.DrawRectangleRoundedLinesEx({x - 10, y - 12, 262, 60}, 0.25, 6, 2, ui.with_alpha(EMBER, v.pickup_pulse))
	}
	ui.draw_text(theme, "Vita", {x, y - 4}, .Small, IVORY_DIM)
	draw_bar({x + 46, y, 160, 14}, p.hp/MAX_HP, v.ghost_hp/MAX_HP, CRIMSON, {44, 18, 24, 255})
	hp_color := IVORY if p.hp >= 35 else rl.Color{255, 110, 110, 255}
	ui.draw_text(theme, fmt.tprintf("%d", int(math.ceil(p.hp))), {x + 214, y - 4}, .Body, hp_color)
	mana_back := rl.Color{20, 24, 48, 255}
	if v.dry_time > 0 && int(v.time*16)%2 == 0 {
		mana_back = {120, 20, 30, 255}
	}
	ui.draw_text(theme, "Mana", {x, y + 18}, .Small, IVORY_DIM)
	draw_bar({x + 46, y + 22, 160, 10}, p.mana/MAX_MANA, p.mana/MAX_MANA, ARCANE, mana_back)
	ui.draw_text(theme, fmt.tprintf("%d", int(p.mana)), {x + 214, y + 16}, .Small, IVORY)
}

@(private)
draw_runes :: proc(g: ^Game, theme: ^ui.Theme) {
	w := &g.world
	v := &g.view
	x, y := f32(18), f32(14)
	slots := f32(w.rune_count)
	rl.DrawRectangleRounded({x - 10, y - 8, 70 + slots*24, 44}, 0.25, 6, PANEL)
	ui.draw_text(theme, "Rune", {x, y + 4}, .Body, IVORY_DIM)
	for i in 0..<w.rune_count {
		c := rl.Vector2{x + 62 + f32(i)*24, y + 14}
		if i < w.runes_taken {
			rl.BeginBlendMode(.ADDITIVE)
			glow2d(v, c, 22 + 4*math.sin(v.time*3+f32(i)), {255, 170, 70, 200})
			rl.EndBlendMode()
			rl.DrawPoly(c, 4, 9, 0, EMBER)
			rl.DrawPoly(c, 4, 4, 0, {255, 244, 210, 255})
		} else {
			rl.DrawPoly(c, 4, 9, 0, {30, 30, 40, 230})
			rl.DrawPolyLinesEx(c, 4, 9, 0, 1.5, IVORY_DIM)
		}
	}
}

// Direction (and path length) to the nearest rune, or to the portal once
// it is open: the crypt is a maze, so this only says where, not how.
@(private)
draw_compass :: proc(g: ^Game, theme: ^ui.Theme, width: f32) {
	w := &g.world
	p := w.player
	target: Vec3
	best := FLOW_UNREACHED
	is_portal := false
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		if pk.kind != .Rune || pk.taken {
			continue
		}
		col := column_of(w, pk.position)
		if col >= 0 && w.flow[col] < best {
			best, target = w.flow[col], pk.position
		}
	}
	if w.portal.open {
		target = w.portal.center
		col := column_of(w, target + Vec3{0.5, 0, 0})
		best = w.flow[col] if col >= 0 else FLOW_UNREACHED
		is_portal = true
	}
	if best >= FLOW_UNREACHED {
		return
	}
	strip := rl.Rectangle{width*0.5 - 130, 12, 260, 18}
	rl.DrawRectangleRounded({strip.x - 6, strip.y - 4, strip.width + 12, strip.height + 26}, 0.3, 6, PANEL)
	half := strip.width * 0.5
	mid := strip.x + half
	RANGE :: f32(1.6) // radians shown either side of the centre
	// Ticks every 45 degrees of world heading.
	for k in 0..<8 {
		heading := f32(k) * math.PI / 4
		rel := math.angle_diff(p.yaw, heading)
		if abs(rel) > RANGE {
			continue
		}
		tx := mid - rel/RANGE*half
		tall := k%2 == 0
		rl.DrawRectangleRec({tx - 1, strip.y + (2 if tall else 6), 2, 14 if tall else 6}, {120, 112, 100, 200})
	}
	rl.DrawRectangleRec({mid - 1, strip.y - 2, 2, strip.height + 4}, {236, 226, 204, 120})
	to := target - player_eye(p)
	rel := math.angle_diff(p.yaw, math.atan2(to.x, to.z))
	mx := clamp(mid-rel/RANGE*half, strip.x+6, strip.x+strip.width-6)
	color := VIOLET if is_portal else EMBER
	rl.DrawPoly({mx, strip.y + strip.height*0.5}, 4, 8, 0, color)
	rl.DrawPolyLinesEx({mx, strip.y + strip.height*0.5}, 4, 8, 0, 1.5, {20, 16, 12, 255})
	if abs(rel) > RANGE {
		dir := f32(-1) if rel > 0 else f32(1)
		tip := rl.Vector2{mx + dir*14, strip.y + strip.height*0.5}
		rl.DrawTriangle(tip, {mx + dir*6, strip.y + 2}, {mx + dir*6, strip.y + strip.height - 2}, color)
		rl.DrawTriangle(tip, {mx + dir*6, strip.y + strip.height - 2}, {mx + dir*6, strip.y + 2}, color)
	}
	label := fmt.tprintf("%s  %d m", "Portale" if is_portal else "Runa", best)
	ui.draw_text_centered(theme, label, {mid, strip.y + strip.height + 11}, .Small, ui.with_alpha(color, 0.9))
}

@(private)
draw_right :: proc(theme: ^ui.Theme, text: string, right, y: f32, size: ui.Text_Size, color: rl.Color) {
	m := ui.measure(theme, text, size)
	ui.draw_text(theme, text, {right - m.x, y}, size, color)
}

@(private)
draw_score :: proc(g: ^Game, theme: ^ui.Theme, width: f32) {
	w := &g.world
	right := width - 18
	rl.DrawRectangleRounded({right - 176, 6, 186, 82}, 0.2, 6, PANEL)
	draw_right(theme, fmt.tprintf("%d", live_score(w)), right, 8, .Large, EMBER)
	draw_right(theme, "Punti", right-96, 14, .Small, IVORY_DIM)
	par_color := IVORY if w.time <= w.par_time else WARNING
	draw_right(theme, fmt.tprintf("%s / %s", host.format_time(w.time), host.format_time(w.par_time)), right, 40, .Small, par_color)
	draw_right(theme, fmt.tprintf("Uccisioni %d   Mira %d%%", w.stats.kills, int(accuracy(w)*100)), right, 60, .Small, IVORY_DIM)
}

// Explored floor only, walls appear as they are seen. North-up: world x to
// the right, world z downward.
@(private)
draw_minimap :: proc(g: ^Game, width: f32) {
	w := &g.world
	v := &g.view
	cell := min(f32(3), 120/f32(w.side))
	size := cell * f32(w.side)
	ox := math.round(width - 18 - size)
	oy := f32(98)
	rl.DrawRectangleRounded({ox - 6, oy - 6, size + 12, size + 12}, 0.06, 6, PANEL)
	for z in 0..<w.side {
		for x in 0..<w.side {
			col := z*w.side + x
			r := rl.Rectangle{ox + f32(x)*cell, oy + f32(z)*cell, cell, cell}
			if w.walkable[col] {
				if w.explored[col] {
					rl.DrawRectangleRec(r, {54, 52, 64, 230})
				}
				continue
			}
			seen := false
			for dz in -1..=1 {
				for dx in -1..=1 {
					n := column_xz(w, x+dx, z+dz)
					if n >= 0 && w.walkable[n] && w.explored[n] {
						seen = true
					}
				}
			}
			if seen {
				rl.DrawRectangleRec(r, {150, 140, 120, 235})
			}
		}
	}
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		col := column_of(w, pk.position)
		if pk.taken || col < 0 || !w.explored[col] {
			continue
		}
		c := rl.Vector2{ox + pk.position.x*cell, oy + pk.position.z*cell}
		switch pk.kind {
		case .Rune:
			rl.DrawPoly(c, 4, cell*1.4 + math.sin(v.time*5), 0, EMBER)
		case .Health:
			rl.DrawRectangleRec({c.x - 1.5, c.y - 1.5, 3, 3}, {230, 70, 70, 255})
		case .Mana:
			rl.DrawRectangleRec({c.x - 1.5, c.y - 1.5, 3, 3}, ARCANE)
		}
	}
	pc := column_of(w, w.portal.center + Vec3{0.5, 0, 0})
	if pc >= 0 && (w.explored[pc] || w.portal.open) {
		c := rl.Vector2{ox + w.portal.center.x*cell, oy + w.portal.center.z*cell}
		color := VIOLET if w.portal.open else rl.Color{120, 100, 140, 255}
		rl.DrawCircleV(c, cell*1.3, color)
	}
	feet := player_feet(w.player)
	c := rl.Vector2{ox + feet.x*cell, oy + feet.z*cell}
	f := rl.Vector2{math.sin(w.player.yaw), math.cos(w.player.yaw)}
	side := rl.Vector2{-f.y, f.x}
	tip := c + f*6
	a := c - f*3 + side*3.5
	b := c - f*3 - side*3.5
	rl.DrawTriangle(tip, a, b, CRIMSON)
	rl.DrawTriangle(tip, b, a, CRIMSON)
	rl.DrawCircleV(c, 1.5, IVORY)
}

@(private)
draw_banner :: proc(g: ^Game, theme: ^ui.Theme, width: f32) {
	w := &g.world
	v := &g.view
	duration := f32(3)
	title, sub: string
	color := EMBER
	switch v.banner {
	case .None:
		return
	case .Start:
		duration = 4.5
		title = fmt.tprintf("Trova %d rune", w.rune_count)
		sub = "Il portale nell'arco si apre solo con tutte le rune"
		color = IVORY
	case .Rune:
		title = fmt.tprintf("Runa trovata  %d/%d", v.banner_value, w.rune_count)
		sub = "Il portale è aperto: fuggi!" if v.banner_value >= w.rune_count else "Il sigillo si indebolisce..."
	case .Portal_Open:
		duration = 3.5
		title = "Il portale si è aperto!"
		sub = "La cripta si risveglia: raggiungi l'arco"
		color = VIOLET
	case .Sealed:
		duration = 2.2
		title = "Il portale è sigillato"
		sub = fmt.tprintf("Rune mancanti: %d", v.banner_value)
		color = WARNING
	case .Wave:
		return
	}
	t := v.banner_time
	if t >= duration {
		return
	}
	a := min(t*5, 1) * min((duration-t)*2.5, 1)
	y := f32(132) - (1-min(t*5, 1))*10
	ui.draw_text_centered(theme, title, {width * 0.5, y}, .Title, ui.with_alpha(color, a))
	ui.draw_text_centered(theme, sub, {width * 0.5, y + 34}, .Body, ui.with_alpha(IVORY, a*0.9))
}
