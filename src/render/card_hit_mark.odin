package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import level "../level"

// "THIS ONE CAN BE HIT": while a card is held (or only under the mouse, faintly)
// each foe some valid cast of it would really affect (game.card_hit_enemies)
// gets its cell lit hot, a rising column of sparks, and, once the cast under the
// mouse would hit it, closing brackets and a ring that opens once.
//
// A tile of the floor is tinted by the biome and four colours are already the
// range's (blue reach, amber effect, mint target, red refusal), so no single hue
// reads everywhere. The mark says it four ways at once: it is the brightest
// thing on the board (a near-white core that pulses), it has a dark ink outline
// (the paper figures' own), a corner-bracket shape, and a saturated halo in a hue
// kept away from all the others (card_hit_halo_color).

CARD_HIT_VIOLET :: rl.Color{170, 90, 255, 255}
CARD_HIT_ACID :: rl.Color{190, 255, 60, 255}
CARD_HIT_CORE :: rl.Color{255, 250, 235, 255}
CARD_HIT_INK :: rl.Color{24, 25, 32, 255}
// The halo stays at least this many degrees of hue from every colour it sits with.
CARD_HIT_MIN_HUE_GAP :: f32(40)
// The ring that opens when a cast closes on a foe lasts this long.
CARD_HIT_RING_SECONDS :: f32(0.6)

// When each foe the cast under the mouse hits was first locked, to open its
// ring once. Rewritten every frame from the preview: a foe that is not locked
// this frame is forgotten.
Card_Hit_Memory :: struct {
	ids:   [game.MAX_CARD_HITS]u32,
	since: [game.MAX_CARD_HITS]f64,
	count: int,
}

@(private)
card_hit_hue :: proc(color: rl.Color) -> f32 {
	r, g, b := f32(color.r)/255, f32(color.g)/255, f32(color.b)/255
	high, low := max(r, g, b), min(r, g, b)
	if high == low { return 0 }
	span := high-low
	hue: f32
	if high == r { hue = math.mod((g-b)/span, f32(6)) } else if high == g { hue = (b-r)/span+2 } else { hue = (r-g)/span+4 }
	hue *= 60
	if hue < 0 { hue += 360 }
	return hue
}

@(private)
card_hit_hue_gap :: proc(a, b: f32) -> f32 {
	gap := abs(a-b)
	return min(gap, 360-gap)
}

// The halo's hue: violet, or acid green where the biome's own tint is violet
// (Spazio). Away from the four range colours and the biome tint by at least
// CARD_HIT_MIN_HUE_GAP degrees; `tint` is the biome's colour (none in the lab).
@(private)
card_hit_halo_color :: proc(tint: [3]u8, has_tint: bool) -> rl.Color {
	avoid := [5]f32{card_hit_hue(CARD_LIGHT_REACH), card_hit_hue(CARD_LIGHT_EFFECT), card_hit_hue(CARD_LIGHT_TARGET),
		card_hit_hue(CARD_LIGHT_INVALID), card_hit_hue({tint.x, tint.y, tint.z, 255})}
	count := 5 if has_tint else 4
	best, best_gap := CARD_HIT_VIOLET, f32(-1)
	for candidate in ([2]rl.Color{CARD_HIT_VIOLET, CARD_HIT_ACID}) {
		gap := f32(360)
		for hue in avoid[:count] { gap = min(gap, card_hit_hue_gap(card_hit_hue(candidate), hue)) }
		if gap >= CARD_HIT_MIN_HUE_GAP { return candidate }
		if gap > best_gap { best, best_gap = candidate, gap }
	}
	return best
}

// How strong the marks are: faint under the mouse in the hand, dim when the
// card cannot be paid.
@(private="file")
card_hit_strength :: proc(preview: ^Card_Range_Preview) -> f32 {
	return (f32(1) if preview.affordable else f32(0.36))*(f32(0.5) if preview.faint else f32(1))
}

@(private="file")
card_hit_color :: proc(color: rl.Color, alpha: f32) -> rl.Color {
	return {color.r, color.g, color.b, u8(clamp(alpha, f32(0), f32(255)))}
}

@(private="file")
CARD_HIT_EDGE_OUT :: [4]rl.Vector3{{0, 0, -1}, {1, 0, 0}, {0, 0, 1}, {-1, 0, 0}}

// The mark on each cell of the hit foes, in the light pass under every actor.
@(private)
draw_card_hit_marks :: proc(renderer: ^Renderer, room: ^game.Room, preview: ^Card_Range_Preview, halo: rl.Color) {
	v := &renderer.tactical
	if !preview.active || preview.hit_count == 0 { v.hit_marks = {}; return }
	now := renderer.sprite_assets.elapsed
	t := f32(now)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	scale := card_hit_strength(preview)
	next: Card_Hit_Memory
	for mark in preview.hits[:preview.hit_count] {
		age := f32(-1)
		if mark.locked {
			since := now
			for i in 0..<v.hit_marks.count {
				if v.hit_marks.ids[i] == mark.id { since = v.hit_marks.since[i]; break }
			}
			next.ids[next.count], next.since[next.count] = mark.id, since
			next.count += 1
			age = f32(now-since)
		}
		if !tactical_render_visible(renderer, mark.cell) || !tactical_cell_on_screen(renderer, mark.cell) { continue }
		rlgl.CheckRenderBatchLimit(c.int(320))
		draw_card_hit_cell(room, mark, t, age, scale, halo)
	}
	v.hit_marks = next
}

@(private="file")
draw_card_hit_cell :: proc(room: ^game.Room, mark: Card_Hit_Mark, t, age, scale: f32, halo: rl.Color) {
	tile, exists := level.tile_at(room.level_data, mark.cell)
	if !exists || tile.kind == .Void { return }
	y := f32(0.05)
	if tile.kind == .Exit { y = 0.128 }
	if tile.kind == .Wall { y = 0.202 }
	locked := age >= 0
	pulse := 0.5+0.5*math.sin(t*5.2+f32(mark.id)*0.7)
	center := rl.Vector3{f32(mark.cell.x)+0.5, y, f32(mark.cell.y)+0.5}
	corner :: proc(center: rl.Vector3, i: int, radius: f32) -> rl.Vector3 {
		x := f32(-1) if i == 0 || i == 3 else f32(1)
		z := f32(-1) if i == 0 || i == 1 else f32(1)
		return center+rl.Vector3{x*radius, 0, z*radius}
	}
	out := CARD_HIT_EDGE_OUT
	rlgl.Begin(rlgl.TRIANGLES)
	// The core: a near-white fill, brightest at the middle and pulsing.
	fill := card_hit_color(CARD_HIT_CORE, (195+60*pulse)*scale)
	rim := card_hit_color(CARD_HIT_CORE, (110+50*pulse)*scale)
	for i in 0..<4 {
		a, b := corner(center, i, 0.5), corner(center, (i+1)%4, 0.5)
		rlgl.Color4ub(fill.r, fill.g, fill.b, fill.a); rlgl.Vertex3f(center.x, center.y, center.z)
		rlgl.Color4ub(rim.r, rim.g, rim.b, rim.a); rlgl.Vertex3f(b.x, b.y, b.z)
		rlgl.Color4ub(rim.r, rim.g, rim.b, rim.a); rlgl.Vertex3f(a.x, a.y, a.z)
	}
	for i in 0..<4 {
		// Outside the cell: the halo, feathered over the neighbours.
		a, b := corner(center, i, 0.5), corner(center, (i+1)%4, 0.5)
		card_light_strip(a, b, out[i], 0.75, halo, (215+40*pulse)*scale)
		// The ink outline, and the hot edge inside it.
		card_light_strip(b, a, -out[i], 0.08, CARD_HIT_INK, 245*scale)
		a2, b2 := corner(center, i, 0.42), corner(center, (i+1)%4, 0.42)
		card_light_strip(b2, a2, -out[i], 0.3, CARD_HIT_CORE, 255*scale)
	}
	// Four corner brackets that breathe, and close tight once the cast under
	// the mouse would hit this foe.
	// They stand outside the cell, around the foe's feet, where its paper does
	// not cover them.
	reach := f32(0.40)
	breathe := f32(0.03) if locked else 0.05+0.08*(0.5+0.5*math.sin(t*3.3+f32(mark.id)))
	width := f32(0.16) if locked else f32(0.12)
	radius := 0.58+breathe
	for i in 0..<4 {
		a, b := corner(center, i, radius), corner(center, (i+1)%4, radius)
		for piece in 0..<2 {
			p, q := a, a+(b-a)*reach
			if piece == 1 { p, q = b+(a-b)*reach, b }
			card_light_strip(q, p, -out[i], width+0.06, CARD_HIT_INK, 250*scale)
			card_light_strip(q, p, -out[i], width, CARD_HIT_CORE, 255*scale)
		}
	}
	// The ring that opens once when the cast under the mouse closes on the foe.
	if locked && age < CARD_HIT_RING_SECONDS {
		k := age/CARD_HIT_RING_SECONDS
		inner := 0.35+0.85*k
		fade := (1-k)*(1-k)
		SEGMENTS :: 36
		for i in 0..<SEGMENTS {
			s0, s1 := f32(i)*math.TAU/SEGMENTS, f32(i+1)*math.TAU/SEGMENTS
			for layer in 0..<2 {
				grow := f32(0.075) if layer == 0 else f32(0.035)
				color := halo if layer == 0 else CARD_HIT_CORE
				w := inner+grow
				p0 := center+rl.Vector3{math.cos(s0)*inner, 0.02, math.sin(s0)*inner}
				p1 := center+rl.Vector3{math.cos(s1)*inner, 0.02, math.sin(s1)*inner}
				q0 := center+rl.Vector3{math.cos(s0)*w, 0.02, math.sin(s0)*w}
				q1 := center+rl.Vector3{math.cos(s1)*w, 0.02, math.sin(s1)*w}
				alpha := 255*fade*scale
				card_light_vertex(p0, color, alpha); card_light_vertex(p1, color, alpha); card_light_vertex(q1, color, alpha)
				card_light_vertex(p0, color, alpha); card_light_vertex(q1, color, alpha); card_light_vertex(q0, color, alpha)
			}
		}
	}
	rlgl.End()
}

// The column of sparks that rises from the cell under each foe to its chest,
// inside a shaft of light. Computed from the clock and the cell alone, like the
// dust of the diorama: no state. Drawn after the paper actors and a little
// towards the camera, so the shaft and the sparks show over the body too.
@(private)
draw_card_hit_sparks :: proc(renderer: ^Renderer, room: ^game.Room, preview: ^Card_Range_Preview, halo: rl.Color) {
	if !preview.active || preview.hit_count == 0 { return }
	camera := renderer.tactical.camera
	forward := camera.target-camera.position
	forward.y = 0
	length := math.sqrt(forward.x*forward.x+forward.z*forward.z)
	if length < 0.0001 { return }
	forward /= length
	right := rl.Vector3{-forward.z, 0, forward.x}
	toward := -forward*0.55
	t := f32(renderer.sprite_assets.elapsed)
	scale := card_hit_strength(preview)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	for mark in preview.hits[:preview.hit_count] {
		if !tactical_render_visible(renderer, mark.cell) || !tactical_cell_on_screen(renderer, mark.cell) { continue }
		base := rl.Vector3{f32(mark.cell.x)+0.5, 0.05, f32(mark.cell.y)+0.5}+toward
		pulse := 0.5+0.5*math.sin(t*5.2+f32(mark.id)*0.7)
		// The shaft: a halo-coloured sheet fading upwards with a hot white core.
		rlgl.CheckRenderBatchLimit(c.int(24))
		rlgl.Begin(rlgl.TRIANGLES)
		for layer in 0..<2 {
			half := f32(0.46) if layer == 0 else f32(0.1)
			top := f32(1.9) if layer == 0 else f32(1.5)
			color := halo if layer == 0 else CARD_HIT_CORE
			bottom_alpha := (f32(120)+40*pulse if layer == 0 else f32(210))*scale
			l, r := base-right*half, base+right*half
			card_light_vertex(l, color, bottom_alpha); card_light_vertex(r, color, bottom_alpha); card_light_vertex(r+rl.Vector3{0, top, 0}, color, 0)
			card_light_vertex(l, color, bottom_alpha); card_light_vertex(r+rl.Vector3{0, top, 0}, color, 0); card_light_vertex(l+rl.Vector3{0, top, 0}, color, 0)
		}
		rlgl.End()
		rlgl.DrawRenderBatchActive()
		count := 14 if mark.locked else 9
		speed := f32(1.3) if mark.locked else f32(0.85)
		for i in 0..<count {
			seed := f32(i)/f32(count)
			phase := math.mod(t*speed+seed+f32(mark.id)*0.137, f32(1))
			side := math.sin(t*1.9+f32(i)*2.3+f32(mark.id))*0.36*(1-phase*0.35)
			at := base+right*side+rl.Vector3{0, 0.08+phase*1.45, 0}
			size := 0.085*(1-phase*0.45)
			alpha := math.sin(phase*math.PI)*255*scale
			rl.DrawCube(at, size*1.7, size*1.7, size*1.7, card_hit_color(CARD_HIT_INK, alpha*0.85))
			rl.DrawCube(at, size, size, size, card_hit_color(CARD_HIT_CORE if i%2 == 0 else halo, alpha))
		}
		rlgl.DrawRenderBatchActive()
	}
}
