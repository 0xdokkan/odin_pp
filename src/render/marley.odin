package render

import "core:fmt"
import "core:math"
import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import tween "../engine/tween"

// BOMB MARLEY on the board (game/marley.odin): a mirror ball hangs over the
// player and throws coloured light on the lit cells, its beams, glints and
// floor spots all drawn (no real light source, no shadow); the columns about
// to be bombed glow red, a bomb rolls down the one that lands, and Bomb Marley,
// a paper cut-out, stands on the north wall and throws. Everything is read
// from the shown party (Room_Presentation.marley) and from the active cues, so
// it follows the events as the board plays them. A cell out of the player's
// sight shows its light hovering over the fog's blocks.

MARLEY_GOLD :: rl.Color{240, 196, 64, 255}
MARLEY_RED :: rl.Color{255, 74, 52, 255}
MARLEY_GREEN :: rl.Color{102, 220, 96, 255}
// The beams and spots cycle through these.
MARLEY_LIGHTS :: [5]rl.Color{{255, 64, 168, 255}, {64, 224, 255, 255}, {255, 214, 72, 255}, {128, 255, 96, 255}, {255, 120, 64, 255}}
// The ball hangs this high at rest and comes down from this high.
MARLEY_BALL_HEIGHT :: f32(3.3)
MARLEY_BALL_FROM :: f32(8.5)
MARLEY_BALL_RADIUS :: f32(0.5)
MARLEY_BALL_SECONDS :: f32(1.0)
MARLEY_GLINTS :: 44
// Where the figure stands, and how big.
MARLEY_FIGURE_HEIGHT :: f32(1.7)
MARLEY_FIGURE_W :: 32
MARLEY_FIGURE_H :: 38
MARLEY_FIGURE_MARGIN :: 3
MARLEY_FIGURE_TEXELS :: (MARLEY_FIGURE_W+2*MARLEY_FIGURE_MARGIN)*(MARLEY_FIGURE_H+2*MARLEY_FIGURE_MARGIN)

Marley_View :: struct {
	// How far down the ball is, 0 (gone) to 1 (at rest), and over which point.
	ball: f32,
	ball_x, ball_z: f32,
	// The column the figure stands over.
	figure_x: f32,
	last_time: f64,
	// The figure's print, made the first time it is drawn.
	figure: rl.Texture2D,
	// The party's shown seconds the last time (the clock's chip blinks on a change).
	last_remaining: i32,
	earned_at: f64,
}

@(private)
destroy_marley_view :: proc(renderer: ^Renderer) {
	m := &renderer.tactical.marley
	if m.figure.id != 0 { rl.UnloadTexture(m.figure) }
	m^ = {}
}

// Once per frame, before the camera: paces the ball and the figure on the
// world's clock (still while the world is held).
@(private)
update_tactical_marley :: proc(renderer: ^Renderer, room: ^game.Room) {
	m := &renderer.tactical.marley
	party := &renderer.tactical.snapshot.marley
	now := tactical_world_time(renderer)
	dt := f32(clamp(now-m.last_time, 0, 0.1))
	m.last_time = now
	player := renderer.tactical.snapshot.player.position
	target_x, target_z := player.x+0.5, player.y+0.5
	if party.active {
		if m.ball <= 0 { m.ball_x, m.ball_z, m.figure_x = target_x, target_z, target_x }
		m.ball = min(f32(1), m.ball+dt/MARLEY_BALL_SECONDS)
		follow := min(f32(1), dt*2.4)
		m.ball_x += (target_x-m.ball_x)*follow
		m.ball_z += (target_z-m.ball_z)*follow
		if party.column_count > 0 {
			column := f32(party.columns[party.column_count-1].x)+0.5
			m.figure_x += (column-m.figure_x)*min(f32(1), dt*5)
		}
		if party.remaining > m.last_remaining && m.last_remaining > 0 { m.earned_at = now }
		m.last_remaining = party.remaining
	} else {
		m.ball = max(f32(0), m.ball-dt/0.6)
		m.last_remaining = 0
	}
}

// Whether the board shows any of the party now.
marley_on_stage :: proc(renderer: ^Renderer) -> bool {
	return renderer.tactical.snapshot.marley.active || renderer.tactical.marley.ball > 0
}

// The light of `index` at `t`: the five colours, turning.
@(private = "file")
marley_light_color :: proc(index: int, t: f64) -> rl.Color {
	lights := MARLEY_LIGHTS
	return lights[(index+int(t*0.9))%len(lights)]
}

@(private = "file")
marley_alpha :: proc(color: rl.Color, alpha: f32) -> rl.Color {
	return {color.r, color.g, color.b, u8(clamp(alpha, f32(0), f32(1))*255)}
}

// A soft round spot on the floor: `alpha` at its middle, nothing at its edge.
@(private = "file")
marley_glow :: proc(cx, y, cz, radius: f32, color: rl.Color, alpha: f32) {
	segments :: 20
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0..<segments {
		a0 := f32(i)/segments*2*math.PI
		a1 := f32(i+1)/segments*2*math.PI
		rlgl.Color4ub(color.r, color.g, color.b, u8(clamp(alpha, f32(0), f32(1))*255))
		rlgl.Vertex3f(cx, y, cz)
		rlgl.Color4ub(color.r, color.g, color.b, 0)
		rlgl.Vertex3f(cx+math.cos(a1)*radius, y, cz+math.sin(a1)*radius)
		rlgl.Vertex3f(cx+math.cos(a0)*radius, y, cz+math.sin(a0)*radius)
	}
	rlgl.End()
}

// A flat square on the floor.
@(private = "file")
marley_square :: proc(cx, y, cz, half: f32, color: rl.Color) {
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.Vertex3f(cx-half, y, cz-half)
	rlgl.Vertex3f(cx-half, y, cz+half)
	rlgl.Vertex3f(cx+half, y, cz+half)
	rlgl.Vertex3f(cx+half, y, cz-half)
	rlgl.End()
}

// The outline of a cell, `inset` in from its edge, `width` thick.
@(private = "file")
marley_frame :: proc(cx, y, cz, half, width: f32, color: rl.Color) {
	marley_square_rect(cx-half, cz-half, cx+half, cz-half+width, y, color)
	marley_square_rect(cx-half, cz+half-width, cx+half, cz+half, y, color)
	marley_square_rect(cx-half, cz-half+width, cx-half+width, cz+half-width, y, color)
	marley_square_rect(cx+half-width, cz-half+width, cx+half, cz+half-width, y, color)
}

@(private = "file")
marley_square_rect :: proc(x0, z0, x1, z1, y: f32, color: rl.Color) {
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.Vertex3f(x0, y, z0)
	rlgl.Vertex3f(x0, y, z1)
	rlgl.Vertex3f(x1, y, z1)
	rlgl.Vertex3f(x1, y, z0)
	rlgl.End()
}

// The height a cell's overlay lies at: on the floor, or over the fog's blocks.
@(private = "file")
marley_floor_height :: proc(renderer: ^Renderer, cell: grid.Position) -> f32 {
	return 0.031 if tactical_render_visible(renderer, cell) else 0.56
}

@(private = "file")
marley_cell_drawn :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) -> bool {
	return grid.contains(&room.level_data.tiles, cell) && tactical_cell_on_screen(renderer, cell) && !game.cell_blocks_movement(room, cell)
}

// The ball's centre now.
@(private = "file")
marley_ball_center :: proc(renderer: ^Renderer) -> rl.Vector3 {
	m := &renderer.tactical.marley
	rise := tween.smoothstep(m.ball)
	return {m.ball_x, MARLEY_BALL_FROM+(MARLEY_BALL_HEIGHT-MARLEY_BALL_FROM)*rise, m.ball_z}
}

// The floor's part, in the board's first 3D pass after the ground: the spots
// of the lit cells, the cells that will be lit next, the columns about to be
// bombed and the glints that wheel over the floor.
@(private)
draw_marley_floor :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !marley_on_stage(renderer) { return }
	party := &renderer.tactical.snapshot.marley
	m := &renderer.tactical.marley
	t := tactical_world_time(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	lit := f32(m.ball)

	// The columns about to land: red, brighter and flashing as the bomb nears.
	if party.active {
		for column in party.columns[:party.column_count] {
			for y in 0..<room.level_data.tiles.height {
				cell := grid.Position{int(column.x), y}
				if !marley_cell_drawn(renderer, room, cell) { continue }
				if marley_shown_lit(party, cell) { continue }
				height := marley_floor_height(renderer, cell)
				pulse := 0.5+0.5*math.sin(f32(t)*(8 if column.beats <= 1 else 3)+f32(y)*0.4)
				alpha := (0.22+0.12*pulse) if column.beats >= 2 else (0.40+0.30*pulse)
				marley_square(f32(cell.x)+0.5, height+0.001, f32(cell.y)+0.5, 0.46, marley_alpha(MARLEY_RED, alpha))
				// A chevron that runs down the column, so that its way reads.
				run := math.mod(f32(t)*5-f32(y)*0.5, f32(3))
				if run < 1 {
					half := 0.2*(1-run*0.4)
					marley_square_rect(f32(cell.x)+0.5-half, f32(cell.y)+0.3+run*0.2, f32(cell.x)+0.5+half, f32(cell.y)+0.38+run*0.2, height+0.002, marley_alpha({255, 214, 190, 255}, 0.6))
				}
			}
		}
	}

	rl.BeginBlendMode(.ADDITIVE)
	if party.active || m.ball > 0 {
		// The spots of the lit cells.
		for light, index in party.lights[:party.light_count] {
			if !marley_cell_drawn(renderer, room, light) { continue }
			height := marley_floor_height(renderer, light)
			color := marley_light_color(index, t)
			pulse := 0.72+0.28*math.sin(f32(t)*4.2+f32(index)*1.7)
			marley_glow(f32(light.x)+0.5, height+0.004, f32(light.y)+0.5, 0.78, color, 0.78*pulse*lit)
			marley_glow(f32(light.x)+0.5, height+0.005, f32(light.y)+0.5, 0.36, {255, 255, 255, 255}, 0.55*pulse*lit)
			marley_frame(f32(light.x)+0.5, height+0.006, f32(light.y)+0.5, 0.47, 0.045, marley_alpha(MARLEY_GOLD, (0.55+0.35*pulse)*lit))
		}
		// The next lights, shown ahead of their turn: only their edges, blinking.
		if party.has_next {
			blink := 0.3+0.35*(0.5+0.5*math.sin(f32(t)*9))
			for light in party.next_lights[:party.next_count] {
				if !marley_cell_drawn(renderer, room, light) { continue }
				height := marley_floor_height(renderer, light)
				marley_frame(f32(light.x)+0.5, height+0.006, f32(light.y)+0.5, 0.42, 0.035, marley_alpha({255, 255, 255, 255}, blink*lit))
			}
		}
		// The glints: tiny spots wheeling round the ball over the floor.
		center := marley_ball_center(renderer)
		for glint in 0..<MARLEY_GLINTS {
			seed := gothic_hash(glint*7+3, glint*13+5)
			turn := f32(seed%628)/100+f32(t)*(0.34 if glint%2 == 0 else -0.27)
			slope := 0.45+f32(seed/628%100)/100*1.05
			reach := center.y/math.tan(slope)
			x, z := center.x+math.cos(turn)*reach, center.z+math.sin(turn)*reach
			cell := grid.Position{int(math.floor(x)), int(math.floor(z))}
			if !marley_cell_drawn(renderer, room, cell) { continue }
			height := marley_floor_height(renderer, cell)
			flash := 0.5+0.5*math.sin(f32(t)*5+f32(glint))
			marley_square(x, height+0.007, z, 0.075, marley_alpha(marley_light_color(glint, t), (0.35+0.6*flash)*lit))
		}
	}
	rl.EndBlendMode()
}

// Whether the shown party lights `cell`.
@(private = "file")
marley_shown_lit :: proc(party: ^game.Marley_State, cell: grid.Position) -> bool {
	for light in party.lights[:party.light_count] { if light == cell { return true } }
	return false
}

// A ribbon from `from` down to `to`, wider and fainter at the bottom, turned
// to the camera.
@(private = "file")
marley_beam :: proc(eye, from, to: rl.Vector3, w0, w1: f32, color: rl.Color, a0, a1: f32) {
	dir := to-from
	mid := (from+to)*0.5
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(dir, eye-mid))
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, u8(clamp(a0, f32(0), f32(1))*255))
	rlgl.Vertex3f(from.x-right.x*w0, from.y-right.y*w0, from.z-right.z*w0)
	rlgl.Vertex3f(from.x+right.x*w0, from.y+right.y*w0, from.z+right.z*w0)
	rlgl.Color4ub(color.r, color.g, color.b, u8(clamp(a1, f32(0), f32(1))*255))
	rlgl.Vertex3f(to.x+right.x*w1, to.y+right.y*w1, to.z+right.z*w1)
	rlgl.Vertex3f(to.x-right.x*w1, to.y-right.y*w1, to.z-right.z*w1)
	rlgl.End()
}

// The faceted ball: rings of mirror tiles, turning, each shaded by the light
// from over its shoulder, a few flashing in the colours of the beams.
@(private = "file")
marley_draw_ball :: proc(center: rl.Vector3, radius: f32, t: f64) {
	rings, slices :: 8, 14
	turn := f32(t)*0.7
	sun := rl.Vector3Normalize({0.35, 0.8, 0.45})
	rlgl.Begin(rlgl.QUADS)
	for ring in 0..<rings {
		lat0 := (f32(ring)/rings-0.5)*math.PI
		lat1 := (f32(ring+1)/rings-0.5)*math.PI
		for slice in 0..<slices {
			lon0 := f32(slice)/slices*2*math.PI+turn
			lon1 := f32(slice+1)/slices*2*math.PI+turn
			point :: proc(center: rl.Vector3, radius, lat, lon: f32) -> rl.Vector3 {
				return center+rl.Vector3{math.cos(lat)*math.cos(lon), math.sin(lat), math.cos(lat)*math.sin(lon)}*radius
			}
			a, b, c2, d := point(center, radius, lat0, lon0), point(center, radius, lat0, lon1), point(center, radius, lat1, lon1), point(center, radius, lat1, lon0)
			normal := rl.Vector3Normalize((a+b+c2+d)*0.25-center)
			light := 0.45+0.55*max(f32(0), rl.Vector3DotProduct(normal, sun))
			seed := gothic_hash(ring*17+slice, slice*5+ring)
			shade := 150+f32(seed%70)
			color := rl.Color{u8(min(f32(255), shade*light)), u8(min(f32(255), (shade+8)*light)), u8(min(f32(255), (shade+22)*light)), 255}
			// A tile catching a coloured beam now and again.
			if (int(seed)+int(t*6))%9 == 0 {
				lit := marley_light_color(int(seed), t)
				color = {u8(min(255, int(color.r)/2+int(lit.r)/2+30)), u8(min(255, int(color.g)/2+int(lit.g)/2+30)), u8(min(255, int(color.b)/2+int(lit.b)/2+30)), 255}
			}
			rlgl.Color4ub(color.r, color.g, color.b, color.a)
			rlgl.Vertex3f(a.x, a.y, a.z)
			rlgl.Vertex3f(b.x, b.y, b.z)
			rlgl.Vertex3f(c2.x, c2.y, c2.z)
			rlgl.Vertex3f(d.x, d.y, d.z)
		}
	}
	rlgl.End()
}

// The sky's part, after the board's actors: the ball and its chain, the beams,
// the bomb in flight, the figure on the wall.
@(private)
draw_marley_sky :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !marley_on_stage(renderer) { return }
	party := &renderer.tactical.snapshot.marley
	m := &renderer.tactical.marley
	t := tactical_world_time(renderer)
	camera := renderer.tactical.camera
	center := marley_ball_center(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	// The beams: additive ribbons from the ball to every lit cell.
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	for light, index in party.lights[:party.light_count] {
		if !marley_cell_drawn(renderer, room, light) { continue }
		color := marley_light_color(index, t)
		sway := 0.06*math.sin(f32(t)*2.3+f32(index))
		to := rl.Vector3{f32(light.x)+0.5+sway, marley_floor_height(renderer, light), f32(light.y)+0.5}
		pulse := 0.6+0.4*math.sin(f32(t)*3.1+f32(index)*2.1)
		marley_beam(camera.position, center, to, 0.025, 0.34, color, 0.5*pulse*m.ball, 0.12*pulse*m.ball)
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	// The chain, and the ball.
	rl.DrawLine3D(center+rl.Vector3{0, MARLEY_BALL_RADIUS, 0}, center+rl.Vector3{0, 12, 0}, {170, 170, 182, 255})
	marley_draw_ball(center, MARLEY_BALL_RADIUS, t)
	rlgl.DrawRenderBatchActive()

	// The cues: a bomb in flight.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Marley_Bomb { continue }
		draw_marley_bomb(renderer, room, cue)
	}
	draw_marley_figure(renderer, room)
	rlgl.EnableBackfaceCulling()
}

// The bomb crossing its column: it rolls from beyond the north wall to beyond
// the south one, trailing smoke, leaving a flash on every cell it has passed
// (a lit cell glows green instead: it is safe).
@(private = "file")
draw_marley_bomb :: proc(renderer: ^Renderer, room: ^game.Room, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	height := f32(room.level_data.tiles.height)
	party := &renderer.tactical.snapshot.marley
	x := f32(cue.event.from_position.x)+0.5
	span := height+3.2
	z := -2.2+p*span
	// Flashes on the cells it has passed.
	rl.BeginBlendMode(.ADDITIVE)
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	for y in 0..<room.level_data.tiles.height {
		cell := grid.Position{cue.event.from_position.x, y}
		if !marley_cell_drawn(renderer, room, cell) { continue }
		arrival := (f32(y)+0.5+2.2)/span
		age := (p-arrival)*cue.duration
		if age < 0 || age > 0.4 { continue }
		fade := 1-age/0.4
		floor := marley_floor_height(renderer, cell)
		if marley_shown_lit(party, cell) {
			marley_glow(x, floor+0.01, f32(y)+0.5, 0.9, MARLEY_GREEN, 0.6*fade)
		} else {
			marley_glow(x, floor+0.01, f32(y)+0.5, 0.95, {255, 150, 60, 255}, 0.85*fade)
			marley_glow(x, floor+0.012, f32(y)+0.5, 0.5, {255, 244, 200, 255}, 0.8*fade)
		}
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	// The smoke behind it, then the bomb.
	for puff in 1..=6 {
		behind := z-f32(puff)*0.45
		fade := 1-f32(puff)/7
		rl.DrawSphereEx({x, 0.55+0.04*f32(puff), behind}, 0.2*fade+0.04, 6, 8, {120, 118, 124, u8(150*fade)})
	}
	bounce := 0.1*math.abs(math.sin(p*math.PI*10))
	rl.DrawSphereEx({x, 0.55+bounce, z}, 0.3, 10, 12, {24, 24, 30, 255})
	rl.DrawSphereEx({x-0.1, 0.65+bounce, z-0.1}, 0.07, 6, 8, {170, 176, 190, 255})
	flicker := 0.5+0.5*math.sin(p*80)
	rl.DrawSphere({x, 0.9+bounce, z}, 0.07+0.04*flicker, {255, u8(160+80*flicker), 60, 255})
	rl.DrawLine3D({x, 0.82+bounce, z}, {x, 0.9+bounce, z}, {96, 60, 30, 255})
}

// The figure: Bomb Marley's paper cut-out on top of the north wall over the
// column he throws at, bobbing to the beat, bigger for a moment as he throws.
@(private = "file")
draw_marley_figure :: proc(renderer: ^Renderer, room: ^game.Room) {
	m := &renderer.tactical.marley
	if m.ball <= 0.01 { return }
	if m.figure.id == 0 { m.figure = marley_figure_texture() }
	if m.figure.id == 0 { return }
	t := tactical_world_time(renderer)
	beat := f32(math.mod(t, 1))
	hop := 0.12*math.abs(math.sin(beat*math.PI))
	throw := math.exp(-beat*6)
	size := MARLEY_FIGURE_HEIGHT*(1+0.1*throw)*tween.smoothstep(m.ball)
	ratio := f32(m.figure.width)/f32(m.figure.height)
	source := rl.Rectangle{0, 0, f32(m.figure.width), f32(m.figure.height)}
	at := rl.Vector3{clamp(m.figure_x, 0.6, f32(room.level_data.tiles.width)-0.6), 1.58+size*0.5+hop-0.15, 0.5}
	rl.DrawBillboardRec(renderer.tactical.camera, m.figure, source, at, {size*ratio, size}, rl.WHITE)
}

// --------------------------------------------------------------------------
// The figure's print: a bomb in a red, gold and green cap, sunglasses and
// dreadlocks of fuse with a glowing end, cut from paper like the board's props.

@(private = "file")
marley_figure_pixels :: proc() -> (pixels: [MARLEY_FIGURE_W*MARLEY_FIGURE_H]rl.Color) {
	set :: proc(pixels: ^[MARLEY_FIGURE_W*MARLEY_FIGURE_H]rl.Color, x, y: int, color: rl.Color) {
		if x < 0 || y < 0 || x >= MARLEY_FIGURE_W || y >= MARLEY_FIGURE_H { return }
		pixels[y*MARLEY_FIGURE_W+x] = color
	}
	black, shade := rl.Color{28, 28, 36, 255}, rl.Color{62, 62, 78, 255}
	brown, brown_light := rl.Color{96, 58, 30, 255}, rl.Color{150, 96, 48, 255}
	red, gold, green := rl.Color{214, 48, 40, 255}, rl.Color{246, 204, 60, 255}, rl.Color{52, 164, 76, 255}
	// The body: a round bomb.
	for y in 14..<MARLEY_FIGURE_H {
		for x in 0..<MARLEY_FIGURE_W {
			dx, dy := f32(x)-15.5, f32(y)-25
			if dx*dx+dy*dy <= 12.5*12.5 { set(&pixels, x, y, black) }
		}
	}
	// A rim of light on the lower left.
	for y in 26..<MARLEY_FIGURE_H {
		for x in 0..<MARLEY_FIGURE_W {
			dx, dy := f32(x)-15.5, f32(y)-25
			d := dx*dx+dy*dy
			if d <= 12.5*12.5 && d >= 10.2*10.2 && dx < -2 && dy > 1 { set(&pixels, x, y, shade) }
		}
	}
	// The cap: a dome of red, gold and green bands, over a dark brim.
	for y in 4..<17 {
		for x in 0..<MARLEY_FIGURE_W {
			dx, dy := f32(x)-15.5, f32(y)-16
			if y > 16 || dx*dx/(12.5*12.5)+dy*dy/(11.5*11.5) > 1 { continue }
			band := (y-4)/4
			bands := [4]rl.Color{red, red, gold, green}
			set(&pixels, x, y, bands[min(band, 3)])
		}
	}
	for x in 3..<29 { for y in 16..<19 { set(&pixels, x, y, black if y == 18 else shade) } }
	// The fuse on the cap, and its spark.
	for y in 0..<5 { set(&pixels, 16, y+1, brown) }
	for point in ([?][2]int{{15, 0}, {16, 0}, {17, 0}, {16, 1}}) { set(&pixels, point.x, point.y, rl.Color{255, 140, 40, 255}) }
	set(&pixels, 16, 0, rl.Color{255, 244, 190, 255})
	// Sunglasses.
	lens := rl.Color{10, 10, 16, 255}
	for y in 21..<25 {
		for x in 7..<14 { set(&pixels, x, y, lens) }
		for x in 18..<25 { set(&pixels, x, y, lens) }
	}
	for x in 14..<18 { set(&pixels, x, 22, lens) }
	set(&pixels, 8, 22, rl.Color{150, 190, 230, 255})
	set(&pixels, 9, 21, rl.Color{150, 190, 230, 255})
	set(&pixels, 19, 22, rl.Color{150, 190, 230, 255})
	set(&pixels, 20, 21, rl.Color{150, 190, 230, 255})
	// A wide smile.
	smile := rl.Color{232, 232, 236, 255}
	for x in 10..<22 {
		d := f32(x)-15.5
		set(&pixels, x, 29+int(math.round(d*d/22)), smile)
	}
	for point in ([?][2]int{{10, 28}, {21, 28}}) { set(&pixels, point.x, point.y, smile) }
	// Dreadlocks of fuse, either side, brown in segments with a lit end.
	strands := [?][3]int{{3, 17, 31}, {1, 18, 27}, {5, 18, 34}, {28, 17, 31}, {30, 18, 27}, {26, 18, 34}}
	for strand in strands {
		for y in strand[1]..=strand[2] {
			set(&pixels, strand[0], y, brown if (y/3)%2 == 0 else brown_light)
		}
		set(&pixels, strand[0], strand[2]+1, rl.Color{255, 140, 40, 255})
	}
	return
}

// The print: the pixels cut from paper as the board's props are (an ink line,
// white paper, an ink cut, the cut edge down and right).
@(private = "file")
marley_figure_texture :: proc() -> rl.Texture2D {
	if !rl.IsWindowReady() { return {} }
	pixels := marley_figure_pixels()
	margin :: MARLEY_FIGURE_MARGIN
	w, h :: MARLEY_FIGURE_W+2*margin, MARLEY_FIGURE_H+2*margin
	out: [MARLEY_FIGURE_TEXELS]rl.Color
	layers, staged: [MARLEY_FIGURE_TEXELS]Paper_Outline_Layer
	for y in 0..<MARLEY_FIGURE_H {
		for x in 0..<MARLEY_FIGURE_W {
			color := pixels[y*MARLEY_FIGURE_W+x]
			if color.a == 0 { continue }
			out[(y+margin)*w+x+margin] = color
			layers[(y+margin)*w+x+margin] = .Print
		}
	}
	paper_outline_grow(layers[:], staged[:], w, h, .Ink, true)
	for ring in 0..<2 { paper_outline_grow(layers[:], staged[:], w, h, .Paper, ring%2 == 1) }
	paper_outline_grow(layers[:], staged[:], w, h, .Cut, true)
	for index in 0..<w*h {
		#partial switch layers[index] {
		case .Ink, .Cut: out[index] = LIVING_TOKEN_INK
		case .Paper: out[index] = LIVING_TOKEN_PAPER
		}
	}
	for y := h-1; y > 0; y -= 1 {
		for x := w-1; x > 0; x -= 1 {
			if layers[y*w+x] == .Clear && layers[(y-1)*w+x-1] != .Clear { out[y*w+x] = LIVING_TOKEN_EDGE }
		}
	}
	image := rl.GenImageColor(c.int(w), c.int(h), rl.BLANK)
	defer rl.UnloadImage(image)
	for y in 0..<h {
		for x in 0..<w { rl.ImageDrawPixel(&image, c.int(x), c.int(y), out[y*w+x]) }
	}
	texture := rl.LoadTextureFromImage(image)
	if texture.id != 0 { rl.SetTextureFilter(texture, .POINT) }
	return texture
}

// --------------------------------------------------------------------------
// The HUD's chip.

// The party's chip under VITA (BOMB MARLEY 23s), after the bites; the clock is
// the shown party's.
@(private)
marley_chip :: proc(renderer: ^Renderer, short: bool) -> (text: cstring, shown: bool) {
	party := &renderer.tactical.snapshot.marley
	if !party.active { return }
	return fmt.ctprintf("MARLEY %ds" if !short else "MAR %ds", party.remaining), true
}
