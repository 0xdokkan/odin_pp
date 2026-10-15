package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import western "../western"

// 6 RANCH 7 is drawn as a comic thought bubble beside the player: a scalloped
// cloud holding one inked panel, with a trail of puffs down to the standee.
// The panel has its own 336x189 page; everything inside it is drawn in page
// units through one transform, so the cartoon scales with the canvas.

WESTERN_PAGE :: rl.Vector2{336, 189}
// Panel width as a share of the canvas: with the cloud around it the bubble
// covers about a sixth of the screen.
WESTERN_PANEL_SHARE :: f32(0.35)
WESTERN_CLOUD_PAD :: f32(6)
WESTERN_BUMP :: f32(21)

WESTERN_INK :: rl.Color{26, 18, 14, 255}
WESTERN_PAPER :: rl.Color{252, 244, 222, 255}
WESTERN_SKY_TOP :: rl.Color{240, 140, 62, 255}
WESTERN_SKY_LOW :: rl.Color{252, 214, 132, 255}
WESTERN_SUN :: rl.Color{255, 238, 168, 255}
WESTERN_MESA :: rl.Color{180, 92, 54, 255}
WESTERN_MESA_DARK :: rl.Color{138, 64, 42, 255}
WESTERN_SAND :: rl.Color{228, 180, 106, 255}
WESTERN_SAND_DARK :: rl.Color{196, 142, 80, 255}
WESTERN_SAND_LIGHT :: rl.Color{242, 208, 146, 255}
WESTERN_WOOD :: rl.Color{142, 92, 50, 255}
WESTERN_WOOD_DARK :: rl.Color{96, 58, 32, 255}
WESTERN_WOOD_LIGHT :: rl.Color{184, 128, 74, 255}
WESTERN_CACTUS :: rl.Color{96, 152, 86, 255}
WESTERN_GOLD :: rl.Color{255, 204, 66, 255}
WESTERN_GOLD_DARK :: rl.Color{190, 132, 30, 255}
WESTERN_RED :: rl.Color{200, 54, 44, 255}
WESTERN_CLOAK :: rl.Color{58, 62, 82, 255}
WESTERN_PONCHO :: rl.Color{206, 120, 58, 255}
WESTERN_HAT :: rl.Color{154, 100, 54, 255}
WESTERN_BAY :: rl.Color{104, 64, 40, 255}
WESTERN_PALOMINO :: rl.Color{226, 178, 104, 255}

// Ride layout in page units.
WESTERN_LANE_X :: [2]f32{84, 252}
WESTERN_GRAB_Y :: f32(94)
WESTERN_RIDER_Y :: f32(150)
WESTERN_SPEED :: f32(150)

Western_Layout :: struct {
	cloud, panel: rl.Rectangle,
	anchor: rl.Vector2,
	scale: f32,
}

western_layout :: proc(renderer: ^Renderer, room: ^game.Room) -> (layout: Western_Layout) {
	width := renderer.canvas_width*WESTERN_PANEL_SHARE
	height := width*WESTERN_PAGE.y/WESTERN_PAGE.x
	layout.scale = width/WESTERN_PAGE.x
	if room != nil && room.player != nil {
		center := tactical_feedback_position(renderer, game.PLAYER_ENTITY, room.player.position)
		p := tactical_project(renderer, {center.x, center.z}, 1.25)
		layout.anchor = {p.x, p.y}
	} else {
		layout.anchor = {renderer.canvas_width*0.5, renderer.canvas_height*0.6}
	}
	margin := WESTERN_CLOUD_PAD+WESTERN_BUMP+4
	world := tactical_world_bounds(renderer)
	// Beside and above the head, leaving room for the trail of puffs; to the
	// left when the right side is too narrow.
	gap := f32(84)
	x := layout.anchor.x+gap
	if x+width+margin > world.x+world.width { x = layout.anchor.x-gap-width }
	y := layout.anchor.y-height*0.5-48
	x = clamp(x, world.x+margin, max(world.x+margin, world.x+world.width-margin-width))
	y = clamp(y, world.y+margin, max(world.y+margin, world.y+world.height-margin-height))
	layout.panel = {x, y, width, height}
	layout.cloud = {x-WESTERN_CLOUD_PAD, y-WESTERN_CLOUD_PAD, width+WESTERN_CLOUD_PAD*2, height+WESTERN_CLOUD_PAD*2}
	return
}

western_page_to_screen :: proc(layout: Western_Layout, p: rl.Vector2) -> rl.Vector2 {
	return {layout.panel.x+p.x*layout.scale, layout.panel.y+p.y*layout.scale}
}

western_hash :: proc(a, b: int) -> f32 {
	h := u32(a)*0x9E37_79B1 ~ u32(b)*0x85EB_CA77
	h ~= h >> 15
	h *= 0x2C1B_3C6D
	h ~= h >> 12
	return f32(h & 0xFFFF)/65535
}

western_smooth :: proc(x: f32) -> f32 {
	t := clamp(x, 0, 1)
	return t*t*(3-2*t)
}

western_back :: proc(x: f32) -> f32 {
	t := clamp(x, 0, 1)-1
	return 1+t*t*(2.7*t+1.7)
}

western_progress :: proc(time, start, length: f32) -> f32 {
	return clamp((time-start)/length, 0, 1)
}

// Inked primitives in page units. Each fill sits on a slightly larger ink.
western_ellipse :: proc(c: rl.Vector2, rx, ry: f32, color: rl.Color, angle: f32 = 0) {
	rlgl.PushMatrix()
	rlgl.Translatef(c.x, c.y, 0)
	if angle != 0 { rlgl.Rotatef(angle, 0, 0, 1) }
	rlgl.Scalef(max(rx, 0.01), max(ry, 0.01), 1)
	rl.DrawCircleV({0, 0}, 1, color)
	rlgl.PopMatrix()
}

western_inked_ellipse :: proc(c: rl.Vector2, rx, ry: f32, color: rl.Color, angle: f32 = 0, ink: f32 = 1.6) {
	western_ellipse(c, rx+ink, ry+ink, WESTERN_INK, angle)
	western_ellipse(c, rx, ry, color, angle)
}

western_inked_box :: proc(r: rl.Rectangle, color: rl.Color, ink: f32 = 1.6) {
	rl.DrawRectangleRec({r.x-ink, r.y-ink, r.width+ink*2, r.height+ink*2}, WESTERN_INK)
	rl.DrawRectangleRec(r, color)
}

western_text_center :: proc(renderer: ^Renderer, text: cstring, x, y: f32, size: int, color: rl.Color) {
	gothic_text(renderer, text, x-gothic_text_width(renderer, text, size)*0.5, y, size, color)
}

// Comic lettering: dark outline around light letters.
western_lettering :: proc(renderer: ^Renderer, text: cstring, x, y: f32, size: int, color: rl.Color) {
	width := gothic_text_width(renderer, text, size)
	left := x-width*0.5
	for offset in ([8]rl.Vector2{{-2, 0}, {2, 0}, {0, -2}, {0, 2}, {-1.5, -1.5}, {1.5, -1.5}, {-1.5, 1.5}, {1.5, 1.5}}) {
		gothic_text(renderer, text, left+offset.x, y+offset.y, size, WESTERN_INK)
	}
	gothic_text(renderer, text, left, y, size, color)
}

// A jagged comic burst behind a sound effect or a number.
western_burst :: proc(c: rl.Vector2, radius: f32, color: rl.Color, spikes: int = 12, spin: f32 = 0) {
	for pass in 0..<2 {
		r := radius+(2.2 if pass == 0 else 0)
		fill := WESTERN_INK if pass == 0 else color
		for i in 0..<spikes {
			a0 := spin+f32(i)/f32(spikes)*math.TAU
			a1 := spin+(f32(i)+0.5)/f32(spikes)*math.TAU
			a2 := spin+f32(i+1)/f32(spikes)*math.TAU
			outer := r*(1.0 if i%2 == 0 else 0.86)
			p0 := rl.Vector2{c.x+math.cos(a0)*r*0.62, c.y+math.sin(a0)*r*0.62}
			p1 := rl.Vector2{c.x+math.cos(a1)*outer, c.y+math.sin(a1)*outer}
			p2 := rl.Vector2{c.x+math.cos(a2)*r*0.62, c.y+math.sin(a2)*r*0.62}
			rl.DrawTriangle(c, p2, p1, fill)
			rl.DrawTriangle(c, p1, p0, fill)
		}
		rl.DrawCircleV(c, r*0.64, fill)
	}
}

western_bumps :: proc(cloud: rl.Rectangle, grow: f32, color: rl.Color) {
	columns := max(3, int(cloud.width/34))
	rows := max(2, int(cloud.height/34))
	for i in 0..=columns {
		x := cloud.x+cloud.width*f32(i)/f32(columns)
		r := WESTERN_BUMP*(0.88+0.24*western_hash(i, 1))+grow
		rl.DrawCircleV({x, cloud.y}, r, color)
		r = WESTERN_BUMP*(0.88+0.24*western_hash(i, 2))+grow
		rl.DrawCircleV({x, cloud.y+cloud.height}, r, color)
	}
	for i in 1..<rows {
		y := cloud.y+cloud.height*f32(i)/f32(rows)
		r := WESTERN_BUMP*(0.88+0.24*western_hash(i, 3))+grow
		rl.DrawCircleV({cloud.x, y}, r, color)
		r = WESTERN_BUMP*(0.88+0.24*western_hash(i, 4))+grow
		rl.DrawCircleV({cloud.x+cloud.width, y}, r, color)
	}
	rl.DrawRectangleRec({cloud.x-grow, cloud.y-grow, cloud.width+grow*2, cloud.height+grow*2}, color)
}

// The scalloped cloud and its trail of thought puffs, popped by `scale`.
draw_western_cloud :: proc(layout: Western_Layout, scale: f32, trail: f32) {
	center := rl.Vector2{layout.cloud.x+layout.cloud.width*0.5, layout.cloud.y+layout.cloud.height*0.5}
	cloud := layout.cloud
	if scale < 1 {
		cloud = {center.x-cloud.width*0.5*scale, center.y-cloud.height*0.5*scale, cloud.width*scale, cloud.height*scale}
	}
	// Puffs rise from the head toward the nearest edge of the cloud.
	edge := WESTERN_BUMP*0.7
	start := rl.Vector2{layout.anchor.x, layout.anchor.y-12}
	target := rl.Vector2{clamp(start.x, cloud.x-edge, cloud.x+cloud.width+edge), clamp(start.y-36, cloud.y-edge, cloud.y+cloud.height+edge)}
	fractions := [3]f32{0.2, 0.48, 0.76}
	radii := [3]f32{4, 6.5, 9}
	for i in 0..<3 {
		if trail < f32(i+1)/3 { break }
		f := fractions[i]
		p := rl.Vector2{start.x+(target.x-start.x)*f, start.y+(target.y-start.y)*f}
		r := radii[i]
		rl.DrawCircleV({p.x+2, p.y+3}, r+2.4, {0, 0, 0, 70})
		rl.DrawCircleV(p, r+2.4, WESTERN_INK)
		rl.DrawCircleV(p, r, WESTERN_PAPER)
	}
	shadow := rl.Rectangle{cloud.x+4, cloud.y+6, cloud.width, cloud.height}
	western_bumps(shadow, 2.5, {0, 0, 0, 60})
	western_bumps(cloud, 2.6, WESTERN_INK)
	western_bumps(cloud, 0, WESTERN_PAPER)
}

// Seconds of scrolling: the ride clock, continued through the outro.
western_ride_clock :: proc(s: ^western.State) -> f32 {
	#partial switch s.phase {
	case .Ride: return s.time
	case .Outro, .Done:
		last := s.results[max(0, s.resolved-1)].at
		return last+s.time
	}
	return 0
}

// Hand rectangle of a Scopa card's face, as the hand draws it.
western_hand_face :: proc(bounds: rl.Rectangle) -> rl.Rectangle {
	scale := max(f32(0.5), f32(int((bounds.height-12)/SCOPA_CARD_SIZE.y*2))*0.5)
	return {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5, SCOPA_CARD_SIZE.x*scale, SCOPA_CARD_SIZE.y*scale}
}

// Sign slots for the 6 (left of RANCH) and the 7 (right), page units, center form.
western_slot :: proc(index: int) -> rl.Rectangle {
	return {82 if index == 0 else 254, 39, 25, 40}
}

draw_western_bubble :: proc(renderer: ^Renderer, room: ^game.Room, s: ^western.State, card_from: [2]rl.Rectangle) {
	if renderer == nil || s == nil || s.phase == .Done { return }
	layout := western_layout(renderer, room)
	scale := f32(1)
	trail := f32(1)
	if s.phase == .Intro {
		scale = western_back(s.time/western.INTRO_POP)
		trail = western_progress(s.time, 0, western.INTRO_POP*1.2)
	} else if s.phase == .Outro && s.time > western.OUTRO_SECONDS-western.OUTRO_CLOSE {
		scale = 1-western_smooth((s.time-(western.OUTRO_SECONDS-western.OUTRO_CLOSE))/western.OUTRO_CLOSE)
		trail = scale
	}
	draw_western_cloud(layout, max(scale, 0.05), trail)
	if scale >= 0.999 {
		panel := layout.panel
		rl.DrawRectangleRec({panel.x-3, panel.y-3, panel.width+6, panel.height+6}, WESTERN_INK)
		rlgl.DrawRenderBatchActive()
		rl.BeginScissorMode(i32(panel.x), i32(panel.y), i32(math.ceil(panel.width)), i32(math.ceil(panel.height)))
		rlgl.PushMatrix()
		rlgl.Translatef(panel.x, panel.y, 0)
		rlgl.Scalef(layout.scale, layout.scale, 1)
		if s.phase == .Intro && s.time < western.INTRO_SECONDS {
			draw_western_ranch(renderer, s)
		} else {
			draw_western_ride(renderer, s)
		}
		rlgl.PopMatrix()
		rlgl.DrawRenderBatchActive()
		rl.EndScissorMode()
	}
	if s.phase == .Intro { draw_western_flying_cards(renderer, layout, s, card_from) }
}

// The 6 and the 7 rise from where they sat in the hand and fly to the sign.
draw_western_flying_cards :: proc(renderer: ^Renderer, layout: Western_Layout, s: ^western.State, card_from: [2]rl.Rectangle) {
	starts := [2]f32{western.INTRO_CARD_SIX, western.INTRO_CARD_SEVEN}
	ids := [2]game.Card_Id{.Sei_Denari, .Sette_Denari}
	for index in 0..<2 {
		p := western_progress(s.time, starts[index], western.INTRO_CARD_FLIGHT)
		if p >= 1 || card_from[index].width <= 0 { continue }
		from := western_hand_face(card_from[index])
		// Before the flight the card lifts out of the hand.
		lift := western_smooth(s.time/max(starts[index], 0.01))*14
		slot := western_slot(index)
		center := western_page_to_screen(layout, {slot.x, slot.y})
		to := rl.Rectangle{center.x, center.y, slot.width*layout.scale, slot.height*layout.scale}
		e := western_smooth(p)
		x := from.x+(to.x-from.x)*e
		y := from.y-lift+(to.y-from.y+lift)*e-math.sin(p*math.PI)*80
		w := from.width+(to.width-from.width)*e
		h := from.height+(to.height-from.height)*e
		spin := math.sin(p*math.PI)*(-24 if index == 0 else 24)
		// A short sparkle wake behind the card.
		for k in 1..=3 {
			q := max(f32(0), p-f32(k)*0.06)
			if q <= 0 { break }
			eq := western_smooth(q)
			wx := from.x+(to.x-from.x)*eq
			wy := from.y-lift+(to.y-from.y+lift)*eq-math.sin(q*math.PI)*80
			rl.DrawCircleV({wx, wy}, 5-f32(k), rl.Fade(WESTERN_GOLD, 0.7-f32(k)*0.18))
		}
		draw_scopa_face(renderer, ids[index], {x+3, y+4, w, h}, spin, {0, 0, 0, 90})
		draw_scopa_face(renderer, ids[index], {x, y, w, h}, spin, rl.WHITE)
	}
}

// Sky, mesas and sand behind both scenes.
draw_western_backdrop :: proc(horizon: f32) {
	page := WESTERN_PAGE
	rl.DrawRectangleGradientV(0, 0, i32(page.x), i32(horizon), WESTERN_SKY_TOP, WESTERN_SKY_LOW)
	western_inked_ellipse({272, 46}, 24, 24, WESTERN_SUN, 0, 1.4)
	// Ben-Day dots grow toward the horizon.
	for row in 0..<int(horizon/7) {
		y := f32(row)*7+3
		for col in 0..<int(page.x/7)+1 {
			x := f32(col)*7+(3.5 if row%2 == 1 else 0)
			rl.DrawCircleV({x, y}, 0.5+1.5*y/horizon, {255, 248, 226, 70})
		}
	}
	mesas := [4]rl.Vector4{{-10, 64, 40, 28}, {62, 120, 26, 18}, {196, 262, 34, 22}, {282, 350, 22, 14}}
	for m in mesas {
		top := horizon-m.z
		left, right := m.x, m.y
		a := rl.Vector2{left, horizon}
		b := rl.Vector2{right, horizon}
		c := rl.Vector2{right-10, top}
		d := rl.Vector2{left+12, top}
		for pass in 0..<2 {
			grow := f32(1.6) if pass == 0 else 0
			color := WESTERN_INK if pass == 0 else WESTERN_MESA
			rl.DrawTriangle({a.x-grow, a.y}, {b.x+grow, b.y}, {c.x+grow, c.y-grow}, color)
			rl.DrawTriangle({a.x-grow, a.y}, {c.x+grow, c.y-grow}, {d.x-grow, d.y-grow}, color)
		}
		rl.DrawRectangleRec({d.x, top+m.w*0.45, c.x-d.x, 2}, WESTERN_MESA_DARK)
	}
	rl.DrawRectangleRec({0, horizon, page.x, page.y-horizon}, WESTERN_SAND)
	rl.DrawRectangleRec({0, horizon, page.x, 1.6}, WESTERN_INK)
}

draw_western_ranch :: proc(renderer: ^Renderer, s: ^western.State) {
	t := s.time
	horizon := f32(118)
	draw_western_backdrop(horizon)
	// Converging ruts lead the eye to the gate.
	for i in 0..<7 {
		x := f32(i)*56-6
		rl.DrawLineEx({168+(x-168)*0.18, horizon+4}, {x, WESTERN_PAGE.y}, 1.4, WESTERN_SAND_DARK)
	}
	for i in 0..<14 {
		x := western_hash(i, 9)*WESTERN_PAGE.x
		y := horizon+8+western_hash(i, 10)*60
		western_inked_ellipse({x, y}, 2+western_hash(i, 11)*2, 1.2, WESTERN_SAND_LIGHT, 0, 0.8)
	}
	// Fence rails either side of the gate.
	for side in 0..<2 {
		x0 := f32(0) if side == 0 else 250
		x1 := f32(86) if side == 0 else WESTERN_PAGE.x
		western_inked_box({x0, 108, x1-x0, 4}, WESTERN_WOOD_LIGHT, 1.2)
		western_inked_box({x0, 120, x1-x0, 4}, WESTERN_WOOD_LIGHT, 1.2)
		for x := x0+6; x < x1-4; x += 22 { western_inked_box({x, 100, 6, 36}, WESTERN_WOOD, 1.2) }
	}
	// Behind the doors: the dark barn, a lantern glow and the dust of the riders.
	opening := rl.Rectangle{102, 64, 132, 86}
	rl.DrawRectangleRec(opening, {60, 36, 22, 255})
	rl.DrawRectangleGradientV(i32(opening.x), i32(opening.y+40), i32(opening.width), 46, {60, 36, 22, 0}, {150, 96, 50, 180})
	doors := western_smooth(western_progress(t, western.INTRO_DOORS, western.INTRO_DOORS_OPEN-western.INTRO_DOORS))
	if doors > 0 {
		glow := rl.Fade(WESTERN_SUN, 0.35*doors)
		rl.DrawTriangle({168, 70}, {120, 150}, {216, 150}, glow)
	}
	riders := western_progress(t, western.INTRO_RIDERS, western.INTRO_SECONDS-western.INTRO_RIDERS)
	if riders > 0 { draw_western_riders_out(riders, t) }
	// Door leaves swing on their hinges at the posts.
	for side in 0..<2 {
		leaf := 66*(1-0.86*doors)
		x := opening.x if side == 0 else opening.x+opening.width-leaf
		shade := u8(255-90*doors)
		color := rl.Color{u8(f32(WESTERN_WOOD_LIGHT.r)*f32(shade)/255), u8(f32(WESTERN_WOOD_LIGHT.g)*f32(shade)/255), u8(f32(WESTERN_WOOD_LIGHT.b)*f32(shade)/255), 255}
		r := rl.Rectangle{x, opening.y+2, leaf, opening.height-2}
		western_inked_box(r, color, 1.4)
		for k in 1..<4 {
			px := r.x+r.width*f32(k)/4
			rl.DrawLineEx({px, r.y}, {px, r.y+r.height}, 1, WESTERN_WOOD_DARK)
		}
		rl.DrawRectangleRec({r.x, r.y+12, r.width, 6}, WESTERN_WOOD_DARK)
		rl.DrawRectangleRec({r.x, r.y+r.height-18, r.width, 6}, WESTERN_WOOD_DARK)
		if side == 0 {
			rl.DrawLineEx({r.x+2, r.y+r.height-15}, {r.x+r.width-2, r.y+15}, 4, WESTERN_WOOD_DARK)
		} else {
			rl.DrawLineEx({r.x+r.width-2, r.y+r.height-15}, {r.x+2, r.y+15}, 4, WESTERN_WOOD_DARK)
		}
	}
	// Posts and the sign plank: [ ] RANCH [ ].
	western_inked_box({86, 20, 16, 132}, WESTERN_WOOD, 1.6)
	western_inked_box({234, 20, 16, 132}, WESTERN_WOOD, 1.6)
	shake := f32(0)
	punch := western_progress(t, western.INTRO_SIGN, 0.3)
	if punch > 0 && punch < 1 { shake = math.sin(punch*40)*(1-punch)*2.5 }
	plank := rl.Rectangle{62+shake, 16, 212, 46}
	western_inked_box(plank, WESTERN_WOOD, 2)
	for k in 0..<3 {
		y := plank.y+8+f32(k)*13
		rl.DrawLineEx({plank.x+4, y}, {plank.x+plank.width-4, y+1.5}, 1, WESTERN_WOOD_LIGHT)
	}
	for nail in ([4]rl.Vector2{{plank.x+5, plank.y+5}, {plank.x+plank.width-5, plank.y+5}, {plank.x+5, plank.y+plank.height-5}, {plank.x+plank.width-5, plank.y+plank.height-5}}) {
		rl.DrawCircleV(nail, 1.6, WESTERN_INK)
	}
	western_lettering(renderer, "RANCH", 168+shake, 24, 24, WESTERN_PAPER)
	landed := [2]f32{western.INTRO_CARD_SIX+western.INTRO_CARD_FLIGHT, western.INTRO_SIGN}
	ids := [2]game.Card_Id{.Sei_Denari, .Sette_Denari}
	for index in 0..<2 {
		slot := western_slot(index)
		slot.x += shake
		frame := rl.Rectangle{slot.x-slot.width*0.5, slot.y-slot.height*0.5, slot.width, slot.height}
		if t < landed[index] {
			rl.DrawRectangleRec(frame, WESTERN_WOOD_DARK)
			// Dashed outline: an empty place waiting for its card.
			for k in 0..<5 {
				f := f32(k)/5
				rl.DrawRectangleRec({frame.x+frame.width*f+1, frame.y-1, frame.width/10, 1.6}, WESTERN_PAPER)
				rl.DrawRectangleRec({frame.x+frame.width*f+1, frame.y+frame.height-0.6, frame.width/10, 1.6}, WESTERN_PAPER)
				rl.DrawRectangleRec({frame.x-1, frame.y+frame.height*f+1, 1.6, frame.height/10}, WESTERN_PAPER)
				rl.DrawRectangleRec({frame.x+frame.width-0.6, frame.y+frame.height*f+1, 1.6, frame.height/10}, WESTERN_PAPER)
			}
		} else {
			rl.DrawRectangleRec({frame.x-1.6, frame.y-1.6, frame.width+3.2, frame.height+3.2}, WESTERN_INK)
			draw_scopa_face(renderer, ids[index], slot, 0, rl.WHITE)
		}
	}
	if punch > 0 && punch < 1 {
		// Impact strokes around the completed sign.
		for k in 0..<6 {
			a := f32(k)/6*math.TAU+0.3
			c := rl.Vector2{168, 39}
			r0 := 112+punch*10
			rl.DrawLineEx({c.x+math.cos(a)*r0, c.y+math.sin(a)*r0*0.4}, {c.x+math.cos(a)*(r0+12), c.y+math.sin(a)*(r0+12)*0.4}, 2, WESTERN_INK)
		}
	}
	if riders > 0.35 {
		pop := western_back((riders-0.35)/0.25)
		western_burst({70, 160}, 26*pop, WESTERN_GOLD, 12, t*0.5)
		western_lettering(renderer, "YEE-HAW!", 70, 152, 14, WESTERN_RED)
	}
	// White flash into the ride.
	if riders > 0.86 {
		rl.DrawRectangleRec({0, 0, WESTERN_PAGE.x, WESTERN_PAGE.y}, rl.Fade(WESTERN_PAPER, (riders-0.86)/0.14))
	}
}

// Riders burst out of the gate toward the reader, front view.
draw_western_riders_out :: proc(p: f32, t: f32) {
	e := western_smooth(p)
	// Speed lines from the doorway.
	if p > 0.15 {
		for k in 0..<14 {
			a := f32(k)/14*math.TAU
			c := rl.Vector2{168, 108}
			r0 := 40+western_hash(k, 21)*20
			rl.DrawLineEx({c.x+math.cos(a)*r0, c.y+math.sin(a)*r0*0.6}, {c.x+math.cos(a)*(r0+60), c.y+math.sin(a)*(r0+60)*0.6}, 1.2, rl.Fade(WESTERN_INK, 0.5))
		}
	}
	for side in 0..<2 {
		start := rl.Vector2{150 if side == 0 else 186, 118}
		end := rl.Vector2{116 if side == 0 else 220, 168}
		c := rl.Vector2{start.x+(end.x-start.x)*e, start.y+(end.y-start.y)*e}
		k := 0.45+0.9*e
		bob := math.sin(t*18+f32(side)*1.7)*2*k
		// Dust kicked behind the hooves.
		for d in 0..<4 {
			dx := (f32(d)-1.5)*10*k
			rl.DrawCircleV({c.x+dx, c.y+18*k}, (4+western_hash(d, side)*4)*k, rl.Fade(WESTERN_SAND_LIGHT, 0.8))
		}
		draw_western_front_rider(c+{0, bob}, k, side == 0, t)
	}
}

draw_western_front_rider :: proc(c: rl.Vector2, k: f32, player: bool, t: f32) {
	horse := WESTERN_BAY if player else WESTERN_PALOMINO
	// Front legs, alternating.
	stride := math.sin(t*18)*4*k
	western_inked_box({c.x-6*k, c.y+4*k-stride, 4*k, 14*k}, horse, 1.2)
	western_inked_box({c.x+2*k, c.y+4*k+stride, 4*k, 14*k}, horse, 1.2)
	// Chest and head with a white blaze.
	western_inked_ellipse({c.x, c.y}, 11*k, 9*k, horse)
	western_inked_ellipse({c.x, c.y-12*k}, 6.5*k, 11*k, horse)
	western_ellipse({c.x, c.y-14*k}, 1.6*k, 6*k, WESTERN_PAPER)
	rl.DrawTriangle({c.x-6*k, c.y-21*k}, {c.x-3*k, c.y-19*k}, {c.x-5*k, c.y-27*k}, WESTERN_INK)
	rl.DrawTriangle({c.x+3*k, c.y-19*k}, {c.x+6*k, c.y-21*k}, {c.x+5*k, c.y-27*k}, WESTERN_INK)
	rl.DrawCircleV({c.x-3.4*k, c.y-15*k}, 1.2*k, WESTERN_INK)
	rl.DrawCircleV({c.x+3.4*k, c.y-15*k}, 1.2*k, WESTERN_INK)
	// Rider behind the head.
	body := WESTERN_CLOAK if player else WESTERN_PONCHO
	western_inked_ellipse({c.x, c.y-28*k}, 9*k, 8*k, body)
	if player {
		western_inked_ellipse({c.x, c.y-39*k}, 5.5*k, 6.5*k, WESTERN_CLOAK)
		western_ellipse({c.x, c.y-37.5*k}, 3*k, 3.4*k, {236, 206, 170, 255})
		western_inked_box({c.x-6*k, c.y-32*k, 12*k, 3*k}, WESTERN_RED, 1)
	} else {
		western_ellipse({c.x, c.y-37*k}, 3.4*k, 3.8*k, {236, 196, 150, 255})
		western_inked_ellipse({c.x, c.y-42*k}, 13*k, 3*k, WESTERN_HAT)
		western_inked_ellipse({c.x, c.y-45*k}, 6*k, 4*k, WESTERN_HAT)
		rl.DrawRectangleRec({c.x-6*k, c.y-43.5*k, 12*k, 1.6*k}, WESTERN_WOOD_DARK)
	}
}

// Top-down horse and rider galloping toward the top of the page.
draw_western_top_rider :: proc(c: rl.Vector2, player: bool, clock: f32, reach: f32) {
	phase := clock*14+(0 if player else 1.3)
	horse := WESTERN_BAY if player else WESTERN_PALOMINO
	sway := math.sin(phase*0.5)*1.5
	p := rl.Vector2{c.x+sway, c.y}
	western_ellipse({p.x+4, p.y+6}, 14, 26, {0, 0, 0, 55})
	// Legs reach forward and back in a gallop.
	stride := math.sin(phase)*5
	for leg in 0..<4 {
		front := leg < 2
		lx := p.x+(-8 if leg%2 == 0 else 8)
		ly := p.y+(-12 if front else 15)+(stride if (leg == 0) == (leg == 3) else -stride)*(1 if front else -1)
		western_inked_ellipse({lx, ly}, 2.6, 4.6, WESTERN_WOOD_DARK, 0, 1)
	}
	// Tail flicks behind.
	western_inked_ellipse({p.x+math.sin(phase*0.8)*3, p.y+25}, 3, 8, WESTERN_INK if player else WESTERN_SAND_LIGHT, math.sin(phase*0.8)*18, 1)
	western_inked_ellipse(p, 11, 21, horse)
	western_inked_ellipse({p.x, p.y-24}, 5.5, 11, horse)
	western_ellipse({p.x, p.y-33}, 4, 4.5, WESTERN_WOOD_DARK)
	rl.DrawRectangleRec({p.x-1.2, p.y-30, 2.4, 22}, WESTERN_INK if player else WESTERN_WOOD_LIGHT)
	rl.DrawTriangle({p.x-4, p.y-30}, {p.x-1.5, p.y-30}, {p.x-3.5, p.y-35}, WESTERN_INK)
	rl.DrawTriangle({p.x+1.5, p.y-30}, {p.x+4, p.y-30}, {p.x+3.5, p.y-35}, WESTERN_INK)
	// The rider reaches for the coin on a press.
	shoulder := rl.Vector2{p.x+(7 if player else -7), p.y-2}
	if reach > 0 {
		hand := rl.Vector2{shoulder.x+(-3 if player else 3)*reach, shoulder.y-40*reach}
		rl.DrawLineEx(shoulder, hand, 4.4, WESTERN_INK)
		rl.DrawLineEx(shoulder, hand, 2.6, WESTERN_CLOAK if player else WESTERN_PONCHO)
		rl.DrawCircleV(hand, 2.4, {236, 200, 160, 255})
	}
	if player {
		western_inked_ellipse({p.x, p.y-2}, 10, 7, WESTERN_CLOAK)
		western_inked_ellipse({p.x, p.y-5}, 6.5, 6.5, {40, 44, 60, 255})
		rl.DrawRectangleRec({p.x-6.5, p.y-1, 13, 2.4}, WESTERN_RED)
	} else {
		western_inked_ellipse({p.x, p.y-2}, 10, 7, WESTERN_PONCHO)
		western_inked_ellipse({p.x, p.y-5}, 10, 9, WESTERN_HAT)
		western_inked_ellipse({p.x, p.y-5}, 5, 4.5, {120, 76, 40, 255})
		rl.DrawRing({p.x, p.y-5}, 5, 6.2, 0, 360, 24, WESTERN_WOOD_DARK)
	}
}

draw_western_coin :: proc(c: rl.Vector2, clock: f32, scale: f32 = 1, grey: bool = false) {
	turn := max(f32(0.25), abs(math.cos(clock*6)))
	gold := rl.Color{170, 160, 140, 255} if grey else WESTERN_GOLD
	dark := rl.Color{120, 112, 98, 255} if grey else WESTERN_GOLD_DARK
	western_inked_ellipse(c, 7*turn*scale, 7*scale, gold, 0, 1.4)
	western_ellipse(c, 4.6*turn*scale, 4.6*scale, dark)
	western_ellipse({c.x-1.4*turn*scale, c.y-1.6*scale}, 1.6*turn*scale, 1.6*scale, {255, 250, 214, 255})
}

draw_western_ride :: proc(renderer: ^Renderer, s: ^western.State) {
	page := WESTERN_PAGE
	clock := western_ride_clock(s)
	scroll := clock*WESTERN_SPEED
	rl.DrawRectangleRec({0, 0, page.x, page.y}, WESTERN_SAND)
	// Wind ripples in the sand stream past.
	for k in 0..<12 {
		y := math.mod(f32(k)*17+scroll, page.y+17)-8
		for lane in 0..<2 {
			x0 := f32(10) if lane == 0 else page.x*0.5+8
			wave := math.sin(f32(k)*1.7+f32(lane))*3
			rl.DrawLineEx({x0, y+wave}, {x0+page.x*0.5-20, y-wave}, 1, rl.Fade(WESTERN_SAND_DARK, 0.35))
		}
	}
	// Hoof prints trail behind each horse.
	for lane in 0..<2 {
		cx := WESTERN_LANE_X[0] if lane == 0 else WESTERN_LANE_X[1]
		for k in 0..<6 {
			y := WESTERN_RIDER_Y+18+math.mod(scroll+f32(k)*11, 66)
			side := f32(-4) if k%2 == 0 else 4
			western_ellipse({cx+side, y}, 2.2, 1.6, rl.Fade(WESTERN_WOOD_DARK, 0.45*(1-(y-WESTERN_RIDER_Y-18)/66)))
		}
	}
	// Desert floor scrolling past: cracks, stones, tufts, cacti and a skull.
	step := f32(18)
	first := int(math.floor((scroll-page.y)/step))-1
	for k in first..=first+int(page.y/step)+5 {
		for lane in 0..<2 {
			r := western_hash(k, lane)
			y := WESTERN_GRAB_Y-(f32(k)*step-scroll)
			x := (12+r*142) if lane == 0 else (180+r*142)
			// The lane centers stay clear for the riders and coins.
			if abs(x-(WESTERN_LANE_X[0] if lane == 0 else WESTERN_LANE_X[1])) < 16 { x += 30 if r < 0.5 else -30 }
			kind := int(western_hash(k, lane+7)*12)
			switch {
			case kind < 3:
				rl.DrawLineEx({x, y}, {x+7, y+5}, 1.2, WESTERN_SAND_DARK)
				rl.DrawLineEx({x+7, y+5}, {x+4, y+11}, 1.2, WESTERN_SAND_DARK)
			case kind < 6, kind == 10:
				western_inked_ellipse({x, y}, 2.4, 1.8, WESTERN_SAND_LIGHT, 0, 0.9)
			case kind < 8:
				for blade in 0..<3 {
					a := f32(blade-1)*0.5
					rl.DrawLineEx({x, y}, {x+math.sin(a)*6, y-math.cos(a)*6}, 1.4, {150, 140, 70, 255})
				}
			case kind < 10:
				western_inked_ellipse({x, y}, 7, 7, WESTERN_CACTUS, 0, 1.4)
				western_ellipse({x-1.5, y-1.5}, 3, 3, {136, 190, 110, 255})
				for spine in 0..<6 {
					a := f32(spine)/6*math.TAU
					rl.DrawLineEx({x+math.cos(a)*7, y+math.sin(a)*7}, {x+math.cos(a)*10, y+math.sin(a)*10}, 1, WESTERN_INK)
				}
			case:
				western_inked_ellipse({x, y}, 4.5, 3.6, WESTERN_PAPER, 0, 1)
				rl.DrawCircleV({x-1.6, y-0.4}, 0.9, WESTERN_INK)
				rl.DrawCircleV({x+1.6, y-0.4}, 0.9, WESTERN_INK)
				rl.DrawLineEx({x-4, y-2}, {x-8, y-5}, 1.6, WESTERN_PAPER)
				rl.DrawLineEx({x+4, y-2}, {x+8, y-5}, 1.6, WESTERN_PAPER)
			}
		}
	}
	// Fence posts at the edges, and the black line between the lanes.
	for k in first..=first+int(page.y/step)+5 {
		if k%2 != 0 { continue }
		y := WESTERN_GRAB_Y-(f32(k)*step-scroll)
		western_inked_box({2, y, 5, 5}, WESTERN_WOOD, 1)
		western_inked_box({page.x-7, y, 5, 5}, WESTERN_WOOD, 1)
	}
	rl.DrawRectangleRec({page.x*0.5-2.5, 0, 5, page.y}, WESTERN_INK)
	// Speed streaks.
	for k in 0..<8 {
		y := math.mod(f32(k)*31+scroll*2.2, page.y+40)-20
		x := western_hash(k, 33)*page.x
		rl.DrawLineEx({x, y}, {x, y+16}, 1, rl.Fade(WESTERN_PAPER, 0.55))
	}
	lanes := WESTERN_LANE_X
	// Coins: each tick's pair rolls down to the grab line, the winner's is taken.
	for j in 0..<western.COUNTDOWN_FROM {
		arrival := western.tick_time(j)
		for side in 0..<2 {
			x := lanes[side]
			if j < s.resolved {
				result := s.results[j]
				since := clock-result.at
				if result.winner == side {
					if since > 0.45 { continue }
					// Collected: it pops up toward this rider's purse.
					f := western_smooth(since/0.45)
					target := rl.Vector2{40 if side == 0 else page.x-40, 22}
					c := rl.Vector2{x+(target.x-x)*f, WESTERN_GRAB_Y+(target.y-WESTERN_GRAB_Y)*f-math.sin(f*math.PI)*20}
					draw_western_coin(c, clock, 1+0.5*math.sin(f*math.PI))
				} else {
					y := WESTERN_GRAB_Y+since*WESTERN_SPEED
					if y > page.y+12 { continue }
					draw_western_coin({x, y}, clock, 1, true)
				}
			} else {
				y := WESTERN_GRAB_Y-(arrival-clock)*WESTERN_SPEED
				// The pending coin waits at the line until the tick is settled.
				y = min(y, WESTERN_GRAB_Y)
				if y < -12 { continue }
				draw_western_coin({x, y}, clock)
			}
		}
	}
	rl.DrawLineEx({0, WESTERN_GRAB_Y}, {page.x, WESTERN_GRAB_Y}, 1, rl.Fade(WESTERN_INK, 0.25))
	// Riders, with dust behind and a reach toward the coin after a press.
	for side in 0..<2 {
		x := lanes[side]
		for d in 0..<3 {
			age := math.mod(clock*2.5+f32(d)/3, 1)
			rl.DrawCircleV({x+(f32(d)-1)*8, WESTERN_RIDER_Y+12+age*30}, 3+age*7, rl.Fade(WESTERN_SAND_LIGHT, 0.85*(1-age)))
		}
		draw_western_top_rider({x, WESTERN_RIDER_Y}, side == 0, clock, western_reach(s, side, clock))
	}
	draw_western_ride_hud(renderer, s, clock)
}

// How far a rider's arm is out, from the moment of its press.
western_reach :: proc(s: ^western.State, side: int, clock: f32) -> f32 {
	pressed := f32(-10)
	if s.phase == .Ride && s.offsets[side] != western.NO_PRESS {
		pressed = western.tick_time(s.tick)+s.offsets[side]
	} else if s.resolved > 0 {
		last := s.results[s.resolved-1]
		if last.offsets[side] != western.NO_PRESS { pressed = western.tick_time(s.resolved-1)+last.offsets[side] }
	}
	since := clock-pressed
	if since < 0 || since > 0.35 { return 0 }
	return math.sin(since/0.35*math.PI)
}

draw_western_ride_hud :: proc(renderer: ^Renderer, s: ^western.State, clock: f32) {
	page := WESTERN_PAGE
	// Purses: three coin places each.
	names := [2]cstring{"TU", "COWBOY"}
	for side in 0..<2 {
		left := side == 0
		label_x := f32(10) if left else page.x-10
		width := gothic_text_width(renderer, names[side], 12)
		western_inked_box({(label_x if left else label_x-width-8)-2, 4, width+12, 15}, WESTERN_PAPER, 1.2)
		gothic_text(renderer, names[side], (label_x+4) if left else label_x-width-4, 3, 12, WESTERN_INK)
		for k in 0..<western.COINS_TO_WIN {
			c := rl.Vector2{(18+f32(k)*16) if left else page.x-18-f32(k)*16, 30}
			if k < s.coins[side] {
				draw_western_coin(c, 0, 0.9)
			} else {
				rl.DrawCircleV(c, 6.6, WESTERN_INK)
				rl.DrawCircleV(c, 5.2, rl.Fade(WESTERN_PAPER, 0.55))
			}
		}
	}
	// The countdown number in a burst; it jumps on each tick.
	number := western.countdown(s)
	jump := f32(0)
	for j in 0..<western.COUNTDOWN_FROM {
		since := clock-western.tick_time(j)
		if since >= 0 && since < 0.25 { jump = 1-since/0.25 }
	}
	if s.phase == .Ride {
		western_burst({page.x*0.5, 28}, 24+jump*7, WESTERN_RED if jump > 0 else WESTERN_GOLD, 14, clock*0.3)
		western_lettering(renderer, fmt.ctprintf("%d", number), page.x*0.5, 14+(1-jump)*2-jump*3, 24, WESTERN_PAPER)
		if clock < western.tick_time(0)-0.2 {
			western_lettering(renderer, "SPAZIO SUL TICK!", page.x*0.5, 58, 12, WESTERN_GOLD)
		}
	}
	// The last tick's verdict beside each rider.
	if s.resolved > 0 {
		last := s.results[s.resolved-1]
		since := clock-last.at
		if since < 0.9 {
			for side in 0..<2 {
				offset := last.offsets[side]
				text := fmt.ctprintf("%+.2fs", offset) if offset != western.NO_PRESS else cstring("TARDI!")
				if side == 0 && last.winner == 0 && abs(offset) < 0.04 { text = "PERFETTO!" }
				color := WESTERN_GOLD if last.winner == side else rl.Color{210, 200, 190, 255}
				lanes := WESTERN_LANE_X
				western_lettering(renderer, text, lanes[side], 60-since*10, 12, color)
			}
		}
	}
	if s.phase == .Outro || s.phase == .Done {
		pop := western_back(s.time/0.3)
		title: cstring = "HAI VINTO!" if s.won else "IL COWBOY VINCE"
		detail: cstring = "VITA PIENA  +10 ORO" if s.won else "NESSUNA PERDITA"
		rlgl.PushMatrix()
		rlgl.Translatef(page.x*0.5, 92, 0)
		rlgl.Rotatef(-6, 0, 0, 1)
		rlgl.Scalef(0.6+0.4*pop, 0.6+0.4*pop, 1)
		western_inked_box({-112, -26, 224, 52}, WESTERN_RED if s.won else WESTERN_WOOD, 2.4)
		rl.DrawRectangleLinesEx({-108, -22, 216, 44}, 1.4, WESTERN_PAPER)
		western_lettering(renderer, title, 0, -22, 24, WESTERN_GOLD if s.won else WESTERN_PAPER)
		western_text_center(renderer, detail, 0, 6, 12, WESTERN_PAPER)
		rlgl.PopMatrix()
	}
}
