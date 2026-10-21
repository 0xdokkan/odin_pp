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
MARLEY_BALL_HEIGHT :: f32(2.15)
MARLEY_BALL_FROM :: f32(6.5)
MARLEY_BALL_RADIUS :: f32(0.5)
MARLEY_BALL_SECONDS :: f32(1.0)
MARLEY_GLINTS :: 44
// Where the figure stands, and how big.
MARLEY_FIGURE_HEIGHT :: f32(1.7)
MARLEY_FIGURE_W :: 32
MARLEY_FIGURE_H :: 38
MARLEY_FIGURE_MARGIN :: 3
MARLEY_FIGURE_TEXELS :: (MARLEY_FIGURE_W+2*MARLEY_FIGURE_MARGIN)*(MARLEY_FIGURE_H+2*MARLEY_FIGURE_MARGIN)
// The bomb's print, and the puff's, in texels.
MARLEY_BOMB_SIZE :: 20
MARLEY_PUFF_SIZE :: 12
// A thrown bomb bounces down its column: one hop every this many cells, this
// high; it is as big as this in the world.
MARLEY_BOUNCE_CELLS :: f32(3)
MARLEY_BOUNCE_HEIGHT :: f32(0.95)
MARLEY_BOMB_SCALE :: f32(1.2)

Marley_View :: struct {
	// How far down the ball is, 0 (gone) to 1 (at rest), and over which point.
	ball: f32,
	ball_x, ball_z: f32,
	// The column the figure stands over.
	figure_x: f32,
	last_time: f64,
	// The prints, made the first time they are drawn: the figure, the bomb and
	// the puffs of smoke it leaves, all cut from paper.
	figure, bomb, puff: rl.Texture2D,
	// The party's shown seconds the last time (the clock's chip blinks on a change).
	last_remaining: i32,
	earned_at: f64,
}

@(private)
destroy_marley_view :: proc(renderer: ^Renderer) {
	m := &renderer.tactical.marley
	if m.figure.id != 0 { rl.UnloadTexture(m.figure) }
	if m.bomb.id != 0 { rl.UnloadTexture(m.bomb) }
	if m.puff.id != 0 { rl.UnloadTexture(m.puff) }
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
	// Over the player, a little to the north so that it hangs clear of his head.
	target_x, target_z := player.x+0.5, player.y-0.4
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
		for index in 0..<party.light_count {
			light := game.marley_light(party, index)
			if !marley_cell_drawn(renderer, room, light) { continue }
			height := marley_floor_height(renderer, light)
			color := marley_light_color(index, t)
			pulse := 0.72+0.28*math.sin(f32(t)*4.2+f32(index)*1.7)
			marley_glow(f32(light.x)+0.5, height+0.004, f32(light.y)+0.5, 0.78, color, 0.78*pulse*lit)
			marley_glow(f32(light.x)+0.5, height+0.005, f32(light.y)+0.5, 0.36, {255, 255, 255, 255}, 0.55*pulse*lit)
			marley_frame(f32(light.x)+0.5, height+0.006, f32(light.y)+0.5, 0.47, 0.045, marley_alpha(MARLEY_GOLD, (0.55+0.35*pulse)*lit))
		}
		// The next lights, on show all the while but not safe yet: a pale cold
		// glow under a thin frame whose corners run round, much fainter than the
		// lit cells, so that the two never read alike.
		if party.has_next {
			breath := 0.5+0.5*math.sin(f32(t)*3)
			for index in 0..<party.next_count {
				light := game.marley_next_light(party, index)
				if !marley_cell_drawn(renderer, room, light) || marley_shown_lit(party, light) { continue }
				height := marley_floor_height(renderer, light)
				x, z := f32(light.x)+0.5, f32(light.y)+0.5
				marley_glow(x, height+0.004, z, 0.62, {150, 200, 255, 255}, (0.16+0.1*breath)*lit)
				marley_frame(x, height+0.006, z, 0.42, 0.03, marley_alpha({200, 228, 255, 255}, (0.4+0.3*breath)*lit))
				// A bright spark running round the frame.
				run := math.mod(f32(t)*0.9+f32(index)*0.37, f32(1))*4
				side, along := int(run), run-f32(int(run))
				corner := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
				a, b := corner[side%4], corner[(side+1)%4]
				marley_square(x+(a[0]+(b[0]-a[0])*along)*0.42, height+0.008, z+(a[1]+(b[1]-a[1])*along)*0.42, 0.05, marley_alpha({255, 255, 255, 255}, 0.9*lit))
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
	packed := game.marley_cell(cell)
	for light in party.lights[:party.light_count] { if light == packed { return true } }
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
	for index in 0..<party.light_count {
		light := game.marley_light(party, index)
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

// Where the thrown bomb is at `p` (0 to 1 of its flight) over `column`: thrown
// from the figure in an arc to the column's first cell, then bouncing down it,
// a hop every MARLEY_BOUNCE_CELLS cells, beyond the south wall at the end.
// `landing` is how far through a hop it is (0 on the floor), `hops` the hops
// made so far.
@(private = "file")
marley_bomb_at :: proc(origin: rl.Vector3, column, board_height: f32, p: f32) -> (at: rl.Vector3, landing: f32, hops: int) {
	throw_end :: f32(0.16)
	start := rl.Vector3{column, 0.3, 0.6}
	if p < throw_end {
		k := p/throw_end
		at = origin+(start-origin)*k
		at.y = origin.y+(start.y-origin.y)*k+1.1*math.sin(k*math.PI)
		return at, 0, 0
	}
	k := (p-throw_end)/(1-throw_end)
	reach := board_height+1.4-start.z
	z := start.z+k*reach
	hop := (z-start.z)/MARLEY_BOUNCE_CELLS
	landing = hop-f32(int(hop))
	hops = int(hop)
	return {column, 0.3+MARLEY_BOUNCE_HEIGHT*math.abs(math.sin(landing*math.PI)), z}, landing, hops
}

// A paper print stood on the board: always facing the camera, spun by
// `rotation` degrees.
@(private = "file")
marley_draw_print :: proc(renderer: ^Renderer, texture: rl.Texture2D, at: rl.Vector3, height, rotation: f32, tint: rl.Color) {
	if texture.id == 0 { return }
	ratio := f32(texture.width)/f32(texture.height)
	size := rl.Vector2{height*ratio, height}
	source := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
	rl.DrawBillboardPro(renderer.tactical.camera, texture, source, at, {0, 1, 0}, size, size*0.5, rotation, tint)
}

// The bomb on its way down its column: a paper bomb thrown by the figure, that
// bounces every few cells, a soft shadow on the floor under it, paper puffs
// behind it and a ring where it lands. It strikes wherever it is, in the air
// or on the floor (marley_resolve_column): the hops are only its manner. Each
// cell it has passed flashes (green where a light saves).
@(private = "file")
draw_marley_bomb :: proc(renderer: ^Renderer, room: ^game.Room, cue: ^Presentation_Cue) {
	m := &renderer.tactical.marley
	p := presentation_cue_progress(cue)
	board := f32(room.level_data.tiles.height)
	party := &renderer.tactical.snapshot.marley
	x := f32(cue.event.from_position.x)+0.5
	if m.bomb.id == 0 { m.bomb = marley_bomb_texture() }
	if m.puff.id == 0 { m.puff = marley_puff_texture() }
	origin := marley_figure_center(renderer, room)
	t := tactical_world_time(renderer)
	at, landing, _ := marley_bomb_at(origin, x, board, p)
	rl.BeginBlendMode(.ADDITIVE)
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	// A flash on every cell the bomb has crossed, and a ring where it lands.
	for y in 0..<room.level_data.tiles.height {
		cell := grid.Position{cue.event.from_position.x, y}
		if !marley_cell_drawn(renderer, room, cell) { continue }
		floor := marley_floor_height(renderer, cell)
		crossed := marley_bomb_arrival(origin, x, board, f32(y)+0.5)
		age := (p-crossed)*cue.duration
		if age < 0 || age > 0.45 { continue }
		fade := 1-age/0.45
		if marley_shown_lit(party, cell) {
			marley_glow(x, floor+0.01, f32(y)+0.5, 0.85, MARLEY_GREEN, 0.55*fade)
		} else {
			marley_glow(x, floor+0.01, f32(y)+0.5, 0.8, {255, 150, 60, 255}, 0.55*fade)
		}
	}
	// A ring where it touches the floor.
	for hop in 0..<int((board+1.4)/MARLEY_BOUNCE_CELLS)+1 {
		z := 0.6+f32(hop)*MARLEY_BOUNCE_CELLS
		touched := marley_bomb_arrival(origin, x, board, z)
		age := (p-touched)*cue.duration
		if z > board+0.5 || age < 0 || age > 0.35 { continue }
		cell := grid.Position{cue.event.from_position.x, clamp(int(z), 0, room.level_data.tiles.height-1)}
		floor := marley_floor_height(renderer, cell)
		ring := 0.2+age*2.6
		marley_glow(x, floor+0.014, z, ring, {255, 230, 170, 255}, 0.8*(1-age/0.35))
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	// A soft shadow on the floor under it, smaller the higher it is.
	floor_cell := grid.Position{cue.event.from_position.x, clamp(int(at.z), 0, room.level_data.tiles.height-1)}
	if at.z > 0 && at.z < board {
		lift := clamp(at.y/(MARLEY_BOUNCE_HEIGHT+0.3), f32(0), f32(1))
		radius := 0.34*(1-0.45*lift)
		rl.BeginBlendMode(.ALPHA)
		marley_glow(x, marley_floor_height(renderer, floor_cell)+0.02, at.z, radius, {0, 0, 8, 255}, 0.55*(1-0.5*lift))
		rl.EndBlendMode()
		rlgl.DrawRenderBatchActive()
	}
	rlgl.EnableDepthMask()
	// Paper puffs of smoke on its way behind it, then the bomb, spinning.
	for puff in 1..=6 {
		back, _, _ := marley_bomb_at(origin, x, board, max(f32(0), p-f32(puff)*0.03))
		fade := 1-f32(puff)/7
		marley_draw_print(renderer, m.puff, back+{0, 0.14, 0}, (0.34-0.03*f32(puff))*MARLEY_BOMB_SCALE*1.2, f32(puff)*40+p*120, {255, 255, 255, u8(235*fade)})
	}
	spin := p*900
	marley_draw_print(renderer, m.bomb, at, 0.62*MARLEY_BOMB_SCALE*(1+0.08*math.sin(f32(t)*30)*(1-landing)), spin, rl.WHITE)
}

// The cue progress at which the bomb has crossed the world z `z` of its column.
@(private = "file")
marley_bomb_arrival :: proc(origin: rl.Vector3, column, board_height, z: f32) -> f32 {
	throw_end :: f32(0.16)
	start_z := f32(0.6)
	reach := board_height+1.4-start_z
	return throw_end+(1-throw_end)*clamp((z-start_z)/reach, f32(0), f32(1))
}

// The figure's centre now: on the north wall over his column; when that is
// off the screen, on the nearest cell of his column the screen shows.
@(private = "file")
marley_figure_center :: proc(renderer: ^Renderer, room: ^game.Room) -> rl.Vector3 {
	m := &renderer.tactical.marley
	size := MARLEY_FIGURE_HEIGHT
	x := clamp(m.figure_x, 0.6, f32(room.level_data.tiles.width)-0.6)
	column := int(x)
	at := rl.Vector3{x, 1.58+size*0.5-0.15+0.3, 0.5}
	if !tactical_cell_on_screen(renderer, {column, 0}) {
		for row in 1..<room.level_data.tiles.height {
			if tactical_cell_on_screen(renderer, {column, row}) {
				at = {x, size*0.5+0.1+0.3, f32(row)+0.5}
				break
			}
		}
	}
	return at
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
	at := marley_figure_center(renderer, room)
	at.y += hop-0.3
	marley_draw_print(renderer, m.figure, at, size, 0, rl.WHITE)
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

// A print: `pixels` (w by h, transparent where nothing is) cut from paper as
// the board's props are: an ink line, `paper` rings of white paper, an ink
// cut, the cut edge down and right, with `margin` texels of room round it.
@(private = "file")
marley_paper_texture :: proc(pixels: []rl.Color, w, h, margin, paper: int) -> rl.Texture2D {
	if !rl.IsWindowReady() { return {} }
	tw, th := w+2*margin, h+2*margin
	out := make([]rl.Color, tw*th)
	layers := make([]Paper_Outline_Layer, tw*th)
	staged := make([]Paper_Outline_Layer, tw*th)
	defer { delete(out); delete(layers); delete(staged) }
	for y in 0..<h {
		for x in 0..<w {
			color := pixels[y*w+x]
			if color.a == 0 { continue }
			out[(y+margin)*tw+x+margin] = color
			layers[(y+margin)*tw+x+margin] = .Print
		}
	}
	paper_outline_grow(layers, staged, tw, th, .Ink, true)
	for ring in 0..<paper { paper_outline_grow(layers, staged, tw, th, .Paper, ring%2 == 1) }
	paper_outline_grow(layers, staged, tw, th, .Cut, true)
	for index in 0..<tw*th {
		#partial switch layers[index] {
		case .Ink, .Cut: out[index] = LIVING_TOKEN_INK
		case .Paper: out[index] = LIVING_TOKEN_PAPER
		}
	}
	for y := th-1; y > 0; y -= 1 {
		for x := tw-1; x > 0; x -= 1 {
			if layers[y*tw+x] == .Clear && layers[(y-1)*tw+x-1] != .Clear { out[y*tw+x] = LIVING_TOKEN_EDGE }
		}
	}
	image := rl.GenImageColor(c.int(tw), c.int(th), rl.BLANK)
	defer rl.UnloadImage(image)
	for y in 0..<th {
		for x in 0..<tw { rl.ImageDrawPixel(&image, c.int(x), c.int(y), out[y*tw+x]) }
	}
	texture := rl.LoadTextureFromImage(image)
	if texture.id != 0 { rl.SetTextureFilter(texture, .POINT) }
	return texture
}

@(private = "file")
marley_figure_texture :: proc() -> rl.Texture2D {
	pixels := marley_figure_pixels()
	return marley_paper_texture(pixels[:], MARLEY_FIGURE_W, MARLEY_FIGURE_H, MARLEY_FIGURE_MARGIN, 2)
}

// The bomb: a round black bomb with a stripe of red, gold and green round its
// middle, a glint, and a fuse with a spark.
@(private = "file")
marley_bomb_texture :: proc() -> rl.Texture2D {
	pixels: [MARLEY_BOMB_SIZE*MARLEY_BOMB_SIZE]rl.Color
	set :: proc(pixels: ^[MARLEY_BOMB_SIZE*MARLEY_BOMB_SIZE]rl.Color, x, y: int, color: rl.Color) {
		if x < 0 || y < 0 || x >= MARLEY_BOMB_SIZE || y >= MARLEY_BOMB_SIZE { return }
		pixels[y*MARLEY_BOMB_SIZE+x] = color
	}
	black, shade := rl.Color{26, 26, 34, 255}, rl.Color{70, 70, 88, 255}
	for y in 0..<MARLEY_BOMB_SIZE {
		for x in 0..<MARLEY_BOMB_SIZE {
			dx, dy := f32(x)-9.5, f32(y)-12
			d := dx*dx+dy*dy
			if d > 7.6*7.6 { continue }
			set(&pixels, x, y, shade if d > 6.2*6.2 && dx < 0 && dy > 0 else black)
		}
	}
	// The stripe: red, gold, green, thirds of the bomb's width.
	for y in 12..<14 {
		for x in 3..<17 {
			dx, dy := f32(x)-9.5, f32(y)-12
			if dx*dx+dy*dy > 7.6*7.6 { continue }
			stripe := [3]rl.Color{{214, 48, 40, 255}, {246, 204, 60, 255}, {52, 164, 76, 255}}
			set(&pixels, x, y, stripe[min((x-3)/5, 2)])
		}
	}
	for point in ([?][2]int{{6, 9}, {7, 8}, {6, 8}, {8, 7}}) { set(&pixels, point.x, point.y, rl.Color{200, 206, 220, 255}) }
	// The fuse and its spark.
	for y in 2..<6 { set(&pixels, 10+(1 if y < 4 else 0), y, rl.Color{120, 72, 34, 255}) }
	for point in ([?][2]int{{12, 1}, {13, 1}, {12, 0}, {11, 1}}) { set(&pixels, point.x, point.y, rl.Color{255, 150, 44, 255}) }
	set(&pixels, 12, 1, rl.Color{255, 244, 190, 255})
	return marley_paper_texture(pixels[:], MARLEY_BOMB_SIZE, MARLEY_BOMB_SIZE, 2, 1)
}

// A puff of smoke: a pale round blot with a grey lower edge.
@(private = "file")
marley_puff_texture :: proc() -> rl.Texture2D {
	pixels: [MARLEY_PUFF_SIZE*MARLEY_PUFF_SIZE]rl.Color
	for y in 0..<MARLEY_PUFF_SIZE {
		for x in 0..<MARLEY_PUFF_SIZE {
			dx, dy := f32(x)-5.5, f32(y)-5.5
			d := dx*dx+dy*dy
			if d > 4.8*4.8 { continue }
			pixels[y*MARLEY_PUFF_SIZE+x] = rl.Color{176, 176, 186, 255} if (dx+dy > 2.5 && d > 3*3) else rl.Color{222, 222, 230, 255}
		}
	}
	return marley_paper_texture(pixels[:], MARLEY_PUFF_SIZE, MARLEY_PUFF_SIZE, 2, 1)
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
