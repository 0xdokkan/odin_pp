package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../grid"

// POZZA DI VELENO and INCENDIO on the board (game/ground.odin), cut from paper
// like the cards and the props. The pools and the scorch under the fires are
// one decal laid on the floor: a texture of the whole room, GROUND_TEXELS a
// cell, pixel art never filtered. Each layer is the union of its cells,
// blurred and cut at a wobbly level, so neighbouring pools are one puddle with
// rounded edges and cells that only touch at a corner stay apart; around the
// liquid, a margin of white paper, its ink line and the cut edge one texel
// toward the camera, the light on the liquid's far side: both follow the camera
// as it orbits, to the nearest diagonal of the board. A texel depends only on
// the cells around its own, so a change rebakes only the cells near it, a few
// each frame, the nearest to the pour first: an area that fills floods out
// from the cell poured on. Standing
// on the decal, the fires' paper flames (gfx.ATTACK_PROPS Flame_*) flicker,
// pop up where the fire catches and sink where it goes out. An enemy whose
// card steps into a pool splashes, into a fire throws cinders. Everything
// keeps the world's clock (tactical_world_time), still in the player's shadow.

GROUND_TEXELS :: 32
GROUND_TEXTURE_MAX :: 2048
// Just over the floor's fittings, under the walls' contact shadows.
GROUND_DECAL_HEIGHT :: f32(0.0235)
// Texels of the region baked around a cell: the liquid's rings, the paper,
// the ink and the cut edge reach this far.
GROUND_BAKE_MARGIN :: 6
GROUND_BAKE_SIZE :: GROUND_TEXELS+2*GROUND_BAKE_MARGIN
GROUND_BAKES_PER_FRAME :: 12
// The camera keeps the diagonal the decal was baked for until it looks along
// the board more than 55 degrees from it (the cosine): one resting on an axis
// never rebakes the floor back and forth.
GROUND_FACING_SLACK :: f32(0.5736)
GROUND_PAPER_TEXELS :: 2
GROUND_SPLASHES :: 16
GROUND_SPLASH_SECONDS :: f64(0.5)
GROUND_FLAME_POP_SECONDS :: f64(0.25)
GROUND_FLAME_OUT_SECONDS :: f64(0.4)
GROUND_IMPACTS_SEEN :: 8

GROUND_VENOM_DEEP :: rl.Color{28, 74, 52, 255}
GROUND_VENOM :: rl.Color{52, 128, 72, 255}
GROUND_VENOM_LIGHT :: rl.Color{104, 186, 98, 255}
GROUND_VENOM_GLINT :: rl.Color{206, 244, 168, 255}
GROUND_VENOM_BUBBLE :: rl.Color{150, 222, 132, 255}
GROUND_CHAR_DEEP :: rl.Color{46, 20, 22, 255}
GROUND_CHAR :: rl.Color{92, 34, 26, 255}
GROUND_CHAR_EMBER :: rl.Color{196, 76, 34, 255}
GROUND_CHAR_HOT :: rl.Color{244, 157, 104, 255}

// The scorch lies under the pool where both are.
Ground_Layer :: enum u8 {Char, Pool}
Ground_Layers :: bit_set[Ground_Layer; u8]

Ground_Fx_Cell :: struct {
	// The layers drawn on the cell: the snapshot's, the scorch kept while its
	// flame sinks.
	layers: Ground_Layers,
	// Its texels need baking again; baked, they wait for the upload.
	dirty, upload: bool,
	// Some texel of it is drawn.
	content: bool,
	// A fire burns on it in the snapshot; its flame: a fire's centre, a fire
	// on its last window; on the world's clock, when it caught and when it
	// went out (0: never). The scorch stays while the flame sinks.
	fire, centre, last: bool,
	lit, quenched: f64,
}

Ground_Splash :: struct {
	used, fire: bool,
	cell: grid.Position,
	born: f64,
	seed: int,
}

Ground_Tracked :: struct {
	entity: game.Entity_Ref,
	cell: grid.Position,
}

Ground_Impact :: struct {
	batch: u32,
	cell: grid.Position,
}

Ground_Fx :: struct {
	width, height, texels: int,
	cells: []Ground_Fx_Cell,
	pixels: []u8,
	// Per cell, made with the board: what the snapshot shows this frame.
	wanted: []Ground_Layers,
	centre, last: []bool,
	texture: rl.Texture2D,
	// The whole texture waits for its upload (a new board).
	upload_all: bool,
	// Cells left to bake, the nearest to `seed` first.
	pending: int,
	seed: grid.Position,
	// The camera's side of the board the decal is baked for: the default
	// camera's (+x and +z toward it) when both are false.
	camera_west, camera_north: bool,
	// The twice box-blurred share of a cell's square at each texel of a cell,
	// from the cell before it, itself and the cell after it, per layer.
	profile: [Ground_Layer][3][GROUND_TEXELS]f32,
	profile_texels: int,
	splashes: [GROUND_SPLASHES]Ground_Splash,
	splash_next: int,
	// Where each enemy's card stood last frame.
	tracked: [game.MAX_ENEMIES_PER_ROOM]Ground_Tracked,
	tracked_count: int,
	impacts: [GROUND_IMPACTS_SEEN]Ground_Impact,
	impact_next: int,
	// The fires shown last frame: the lab hears one grow and one go out.
	fires: [game.MAX_GROUND_FIRES]game.Ground_Fire,
	fire_count: int,
	// What the board has shown so far (smoke and tests).
	splashed, cinders, catches: int,
}

// --------------------------------------------------------------------------
// Bookkeeping.

ground_fx_texels :: proc(width, height: int) -> int {
	return clamp(GROUND_TEXTURE_MAX/max(width, height, 1), 4, GROUND_TEXELS)
}

// A fresh board starts with a dry floor.
forget_ground_fx :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.ground == nil { return }
	fx := renderer.tactical.ground
	for &cell in fx.cells { cell = {} }
	for &value in fx.pixels { value = 0 }
	fx.upload_all = true
	fx.pending = 0
	fx.splashes, fx.splash_next = {}, 0
	fx.tracked_count = 0
	fx.impacts, fx.impact_next = {}, 0
	fx.fire_count = 0
}

destroy_ground_fx :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.ground == nil { return }
	fx := renderer.tactical.ground
	if fx.texture.id != 0 { rl.UnloadTexture(fx.texture) }
	delete(fx.cells)
	delete(fx.pixels)
	delete(fx.wanted)
	delete(fx.centre)
	delete(fx.last)
	free(fx)
	renderer.tactical.ground = nil
}

ground_fx_cell :: proc(fx: ^Ground_Fx, cell: grid.Position) -> ^Ground_Fx_Cell {
	if fx == nil || cell.x < 0 || cell.y < 0 || cell.x >= fx.width || cell.y >= fx.height { return nil }
	return &fx.cells[cell.y*fx.width+cell.x]
}

ground_fx_layers :: proc(fx: ^Ground_Fx, cell: grid.Position) -> Ground_Layers {
	at := ground_fx_cell(fx, cell)
	return at.layers if at != nil else {}
}

// The board's size: a new one starts over.
ground_fx_resize :: proc(fx: ^Ground_Fx, width, height: int) {
	if fx.width == width && fx.height == height && fx.cells != nil { return }
	delete(fx.cells)
	delete(fx.pixels)
	delete(fx.wanted)
	delete(fx.centre)
	delete(fx.last)
	fx.width, fx.height = width, height
	fx.texels = ground_fx_texels(width, height)
	fx.cells = make([]Ground_Fx_Cell, width*height)
	fx.pixels = make([]u8, width*fx.texels*height*fx.texels*4)
	fx.wanted = make([]Ground_Layers, width*height)
	fx.centre = make([]bool, width*height)
	fx.last = make([]bool, width*height)
	fx.upload_all = true
	fx.pending = 0
	fx.tracked_count = 0
	ground_fx_profiles(fx)
}

// Each layer's twice box-blurred cell square, sampled at its texels' centres.
ground_fx_profiles :: proc(fx: ^Ground_Fx) {
	t := fx.texels
	if fx.profile_texels == t { return }
	fx.profile_texels = t
	for layer in Ground_Layer {
		radius := max(2, t/5 if layer == .Pool else t/6)
		line, blurred: [GROUND_TEXELS*5]f32
		for i in 2*t..<3*t { line[i] = 1 }
		for _ in 0..<2 {
			for i in 0..<5*t {
				sum: f32
				for j in i-radius..=i+radius { if j >= 0 && j < 5*t { sum += line[j] } }
				blurred[i] = sum/f32(2*radius+1)
			}
			line = blurred
		}
		for d in 0..<3 {
			for u in 0..<t { fx.profile[layer][d][u] = line[u+2*t-(d-1)*t] }
		}
	}
}

// --------------------------------------------------------------------------
// The decal.

ground_noise :: proc(x, y: f32, period: f32, seed: int) -> f32 {
	fx, fy := x/period, y/period
	ix, iy := int(math.floor(fx)), int(math.floor(fy))
	ax, ay := fx-f32(ix), fy-f32(iy)
	ax, ay = ax*ax*(3-2*ax), ay*ay*(3-2*ay)
	h :: proc(x, y, seed: int) -> f32 { return f32(gothic_hash(x*31+seed, y*17-seed*3)%1024)/1023 }
	a := h(ix, iy, seed)*(1-ax)+h(ix+1, iy, seed)*ax
	b := h(ix, iy+1, seed)*(1-ax)+h(ix+1, iy+1, seed)*ax
	return a*(1-ay)+b*ay
}

// The cut of a texel whose blurred cells come to `value`: at a level the noise
// wobbles, never so low that two cells meeting at a corner join.
ground_liquid_cut :: proc(layer: Ground_Layer, value: f32, gx, gy, texels: int) -> bool {
	level, wobble, seed := f32(0.62), f32(0.30), 1
	if layer == .Char { level, wobble, seed = 0.60, 0.18, 3 }
	if value <= 0.53 { return false }
	if value >= level+wobble*0.5 { return true }
	x, y := f32(gx)+0.5, f32(gy)+0.5
	n := 0.7*ground_noise(x, y, max(f32(4), f32(texels)*0.5), seed)+0.3*ground_noise(x, y, max(f32(2), f32(texels)*0.125), seed+11)
	return value > max(f32(0.53), level+wobble*(n-0.5))
}

// Whether the texel (gx, gy) of the room is liquid in `layer`: its cell and
// the eight around it blurred together, then cut. Texel by texel (the bake
// computes the same in rows).
ground_texel_liquid :: proc(fx: ^Ground_Fx, layer: Ground_Layer, gx, gy: int) -> bool {
	t := fx.texels
	cx, cy := int(math.floor(f32(gx)/f32(t))), int(math.floor(f32(gy)/f32(t)))
	u, v := gx-cx*t, gy-cy*t
	value: f32
	for dy in -1..=1 { for dx in -1..=1 {
		if layer not_in ground_fx_layers(fx, {cx+dx, cy+dy}) { continue }
		value += fx.profile[layer][dx+1][u]*fx.profile[layer][dy+1][v]
	} }
	return ground_liquid_cut(layer, value, gx, gy, t)
}

Ground_Mask :: [GROUND_BAKE_SIZE*GROUND_BAKE_SIZE]bool

// The colour of every texel of `cell` (RGBA rows of the room's texture), from
// the region GROUND_BAKE_MARGIN texels around it.
bake_ground_cell :: proc(fx: ^Ground_Fx, cell: grid.Position) -> (content: bool) {
	t := fx.texels
	if t <= 0 || t > GROUND_TEXELS { return }
	M :: GROUND_BAKE_MARGIN
	size := t+2*M
	left, top := cell.x*t-M, cell.y*t-M
	// The layers of the 5x5 cells around, and per row and column of the region
	// its cell (-1, 0, 1 from this one) and its texel there.
	near: [Ground_Layer][5][5]bool
	any_near: [Ground_Layer]bool
	for dy in -2..=2 { for dx in -2..=2 {
		layers := ground_fx_layers(fx, {cell.x+dx, cell.y+dy})
		for layer in Ground_Layer {
			if layer not_in layers { continue }
			near[layer][dy+2][dx+2], any_near[layer] = true, true
		}
	} }
	offset, within: [GROUND_BAKE_SIZE]int
	for i in 0..<size {
		d := i-M
		o := -1 if d < 0 else (1 if d >= t else 0)
		offset[i], within[i] = o, d-o*t
	}
	liquid, paper, sheet, e1, e2, e3: [Ground_Layer]Ground_Mask
	present: [Ground_Layer]bool
	for layer in Ground_Layer {
		if !any_near[layer] { continue }
		profile := &fx.profile[layer]
		// Per row of cells (-2..2) and column of the region: the row's blurred
		// share there; a texel's value is three of them, weighed by its row.
		rows: [5][GROUND_BAKE_SIZE]f32
		for r in 0..<5 { for x in 0..<size {
			ox, u := offset[x], within[x]
			sum: f32
			for dx in -1..=1 { if near[layer][r][ox+dx+2] { sum += profile[dx+1][u] } }
			rows[r][x] = sum
		} }
		for y in 0..<size {
			oy, v := offset[y], within[y]
			for x in 0..<size {
				value := profile[0][v]*rows[oy+1][x]+profile[1][v]*rows[oy+2][x]+profile[2][v]*rows[oy+3][x]
				if value > 0.53 && ground_liquid_cut(layer, value, left+x, top+y, t) {
					liquid[layer][y*size+x], present[layer] = true, true
				}
			}
		}
		if !present[layer] { continue }
		ground_mask_paper(&liquid[layer], &paper[layer], size)
		ground_mask_grow(&paper[layer], &sheet[layer], size)
		// The liquid eroded one, two and three texels: its rim and its core.
		ground_mask_erode(&liquid[layer], &e1[layer], size)
		ground_mask_erode(&e1[layer], &e2[layer], size)
		ground_mask_erode(&e2[layer], &e3[layer], size)
	}
	width := fx.width*t
	sx, sz := ground_fx_toward(fx)
	for v in 0..<t { for u in 0..<t {
		x, y := u+M, v+M
		gx, gy := cell.x*t+u, cell.y*t+v
		colour := rl.BLANK
		for layer in ([2]Ground_Layer{.Pool, .Char}) {
			if !present[layer] { continue }
			at := y*size+x
			if liquid[layer][at] {
				colour = ground_liquid_colour(layer, &e1[layer], &e2[layer], &e3[layer], size, x, y, gx, gy, sx, sz)
			} else if paper[layer][at] {
				colour = LIVING_TOKEN_PAPER
			} else if sheet[layer][at] {
				colour = LIVING_TOKEN_INK
			} else if sheet[layer][(y-sz)*size+x-sx] {
				// The cut edge, a texel toward the camera (down the screen).
				colour = LIVING_TOKEN_EDGE
			} else { continue }
			break
		}
		at := (gy*width+gx)*4
		fx.pixels[at], fx.pixels[at+1], fx.pixels[at+2], fx.pixels[at+3] = colour.r, colour.g, colour.b, colour.a
		content = content || colour.a != 0
	} }
	return
}

// The paper: the liquid grown GROUND_PAPER_TEXELS round (a 5x5 square less its
// corners), in rows: a run of five, or of three two rows away.
ground_mask_paper :: proc(from, to: ^Ground_Mask, size: int) {
	wide, narrow: Ground_Mask
	for y in 0..<size { for x in 0..<size {
		w, n := false, false
		for dx in -2..=2 {
			xx := x+dx
			if xx < 0 || xx >= size || !from[y*size+xx] { continue }
			w = true
			if abs(dx) <= 1 { n = true }
		}
		wide[y*size+x], narrow[y*size+x] = w, n
	} }
	for y in 0..<size { for x in 0..<size {
		found := false
		for dy in -2..=2 {
			yy := y+dy
			if yy < 0 || yy >= size { continue }
			found = found || (wide[yy*size+x] if abs(dy) <= 1 else narrow[yy*size+x])
		}
		to[y*size+x] = found
	} }
}

// One texel grown all round (3x3): the ink line's outer edge.
ground_mask_grow :: proc(from, to: ^Ground_Mask, size: int) {
	across: Ground_Mask
	for y in 0..<size { for x in 0..<size {
		across[y*size+x] = from[y*size+x] || (x > 0 && from[y*size+x-1]) || (x < size-1 && from[y*size+x+1])
	} }
	for y in 0..<size { for x in 0..<size {
		to[y*size+x] = across[y*size+x] || (y > 0 && across[(y-1)*size+x]) || (y < size-1 && across[(y+1)*size+x])
	} }
}

ground_mask_erode :: proc(from, to: ^Ground_Mask, size: int) {
	for y in 0..<size { for x in 0..<size {
		to[y*size+x] = from[y*size+x] && (x > 0 && from[y*size+x-1]) && (x < size-1 && from[y*size+x+1]) &&
			(y > 0 && from[(y-1)*size+x]) && (y < size-1 && from[(y+1)*size+x])
	} }
}

// A liquid texel's colour, (x, y) in the baked region, (gx, gy) in the room;
// (sx, sz) the texel step toward the camera (ground_fx_toward).
ground_liquid_colour :: proc(layer: Ground_Layer, e1, e2, e3: ^Ground_Mask, size, x, y, gx, gy: int, sx := 1, sz := 1) -> rl.Color {
	at := y*size+x
	n := gothic_hash(gx*3+int(layer)*101, gy*5+7)
	if layer == .Char {
		if !e1[at] { return GROUND_CHAR_DEEP }
		if e2[at] && n%41 == 0 { return GROUND_CHAR_EMBER }
		if e2[at] && n%113 == 0 { return GROUND_CHAR_HOT }
		return GROUND_CHAR
	}
	if !e1[at] { return GROUND_VENOM_DEEP }
	if !e3[at] { return GROUND_VENOM }
	// The light catches the far side of the surface (away from the camera: up
	// the screen).
	far_x, far_y := x-2*sx, y-2*sz
	if far_x >= 0 && far_y >= 0 && far_x < size && far_y < size && !e3[far_y*size+far_x] { return GROUND_VENOM_LIGHT }
	// A glint, a bubble's ring, here and there on three-texel cells.
	g := gothic_hash(gx/3+911, gy/3+37)
	if g%61 == 0 && gx%3 == 1 && gy%3 == 1 { return GROUND_VENOM_GLINT }
	if g%67 == 3 {
		ox, oy := gx%3-1, gy%3-1
		if abs(ox)+abs(oy) == 1 { return GROUND_VENOM_BUBBLE }
	}
	return GROUND_VENOM
}

// The texel step toward the camera across the board, each of x and z one way
// or the other, as the decal is baked (Ground_Fx.camera_west, camera_north).
ground_fx_toward :: proc(fx: ^Ground_Fx) -> (sx, sz: int) {
	return -1 if fx.camera_west else 1, -1 if fx.camera_north else 1
}

// The decal follows the camera as it orbits: once the camera looks along the
// board well away from the diagonal it was baked for (GROUND_FACING_SLACK), it
// takes the diagonal nearest the camera and every cell that draws anything
// bakes again, from the cell the camera looks at out. True when it turned.
ground_fx_face :: proc(fx: ^Ground_Fx, toward: rl.Vector3, looked_at: grid.Position) -> bool {
	if !(abs(toward.x)+abs(toward.z) > 0.01) { return false }
	sx, sz := ground_fx_toward(fx)
	if (toward.x*f32(sx)+toward.z*f32(sz))/math.SQRT_TWO >= GROUND_FACING_SLACK { return false }
	west, north := toward.x < 0, toward.z < 0
	if west == fx.camera_west && north == fx.camera_north { return false }
	fx.camera_west, fx.camera_north = west, north
	for cell, index in fx.cells {
		if cell.layers != {} { ground_fx_mark(fx, {index%fx.width, index/fx.width}) }
	}
	fx.seed = {clamp(looked_at.x, 0, max(fx.width-1, 0)), clamp(looked_at.y, 0, max(fx.height-1, 0))}
	return true
}

// The cells whose layers changed since last seen make the cells around them
// stale: a texel's colour depends on the cells two away from its own.
ground_fx_mark :: proc(fx: ^Ground_Fx, cell: grid.Position) {
	for dy in -2..=2 { for dx in -2..=2 {
		at := ground_fx_cell(fx, {cell.x+dx, cell.y+dy})
		if at == nil || at.dirty { continue }
		at.dirty = true
		fx.pending += 1
	} }
}

// Bakes up to `budget` stale cells, the nearest to the seed first.
ground_fx_bake :: proc(fx: ^Ground_Fx, budget: int) {
	for _ in 0..<budget {
		if fx.pending <= 0 { return }
		best, best_distance := -1, max(int)
		for &cell, index in fx.cells {
			if !cell.dirty { continue }
			x, y := index%fx.width, index/fx.width
			distance := max(abs(x-fx.seed.x), abs(y-fx.seed.y))*fx.width*fx.height+index
			if distance < best_distance { best, best_distance = index, distance }
		}
		if best < 0 { fx.pending = 0; return }
		cell := &fx.cells[best]
		cell.dirty, cell.upload = false, true
		cell.content = bake_ground_cell(fx, {best%fx.width, best/fx.width})
		fx.pending -= 1
	}
}

// --------------------------------------------------------------------------
// Following the board.

// Once per frame, as the board begins (draw_tactical_world): before its decal
// and the sorted pass that stands the flames, one budget of cells baked.
update_ground_fx :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !v.enabled || v.snapshot == nil || room == nil || room.level_data == nil { return }
	shown := &v.snapshot.ground
	// A board that never had a pool or a fire needs nothing.
	if v.ground == nil {
		if shown.fire_count == 0 && shown.pool == {} { return }
		v.ground = new(Ground_Fx)
	}
	fx := v.ground
	ground_fx_resize(fx, room.level_data.tiles.width, room.level_data.tiles.height)
	looked_at := v.camera.target
	ground_fx_face(fx, attack_toward_camera(renderer), {int(math.floor(looked_at.x)), int(math.floor(looked_at.z))})
	world := tactical_world_time(renderer)
	// The layers and the flames the snapshot shows.
	wanted, centre, last := fx.wanted, fx.centre, fx.last
	for index in 0..<len(fx.cells) {
		wanted[index], centre[index], last[index] = {}, false, false
		if presentation_ground_pool(shown, {index%fx.width, index/fx.width}) { wanted[index] += {.Pool} }
	}
	steps := game.GROUND_ARM_STEPS
	for fire in shown.fires[:shown.fire_count] {
		final := fire.stage >= game.GROUND_FIRE_STAGES
		ground_fx_mark_fire(fx, fire.center, final)
		if at := ground_fx_cell(fx, fire.center); at != nil { centre[fire.center.y*fx.width+fire.center.x] = true }
		for step, direction in steps {
			for reach in 1..=int(fire.arms[direction]) {
				ground_fx_mark_fire(fx, {fire.center.x+step.x*reach, fire.center.y+step.y*reach}, final)
			}
		}
	}
	changed := false
	lab := v.mechanics_lab && v.lab_sounds != nil
	for &cell, index in fx.cells {
		at := grid.Position{index%fx.width, index/fx.width}
		now_burning := .Char in wanted[index]
		if now_burning && !cell.fire {
			cell.lit, cell.quenched = world, 0
			// The fire catches under a card standing there.
			for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
				if actor.visible && int(math.round(actor.position.x)) == at.x && int(math.round(actor.position.y)) == at.y { fx.catches += 1 }
			}
		} else if !now_burning && cell.fire {
			cell.quenched = world
		}
		cell.fire = now_burning
		// A flame keeps its look as it sinks, and its scorch under it.
		if now_burning { cell.centre, cell.last = centre[index], last[index] }
		if !now_burning && cell.quenched > 0 && world-cell.quenched < GROUND_FLAME_OUT_SECONDS { wanted[index] += {.Char} }
		if cell.layers != wanted[index] {
			if !changed { fx.seed = at }
			changed = true
			cell.layers = wanted[index]
			ground_fx_mark(fx, at)
		}
	}
	// A fire whose arms reach further at a new window roars, one that goes
	// out at its fifth hisses; one just lit is its card's landing (lab_cue_sounds).
	grew, out := false, false
	for before in fx.fires[:fx.fire_count] {
		kept := false
		for fire in shown.fires[:shown.fire_count] {
			if fire.id != before.id { continue }
			kept = true
			grew = grew || ground_fx_fire_reach(fire) > ground_fx_fire_reach(before)
		}
		out = out || !kept
	}
	fx.fires, fx.fire_count = shown.fires, shown.fire_count
	if grew && lab { lab_sound_queue(v.lab_sounds, .World_Fire_Spread, renderer.sprite_assets.elapsed) }
	if out && lab { lab_sound_queue(v.lab_sounds, .World_Fire_Out, renderer.sprite_assets.elapsed) }
	// A pool or a fire landing: the flood starts from its cell, which splashes.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Spell_Impact || !game.card_places_ground(cue.event.card_definition) { continue }
		key := Ground_Impact{batch = cue.batch, cell = cue.event.to_position}
		seen := false
		for impact in fx.impacts { seen = seen || (impact == key && key.batch != 0) }
		if seen { continue }
		fx.impacts[fx.impact_next] = key
		fx.impact_next = (fx.impact_next+1)%len(fx.impacts)
		fx.seed = key.cell
		ground_splash(fx, key.cell, cue.event.card_definition == .Wildfire, world)
	}
	// The cards that step into a pool or a fire.
	tracked: [game.MAX_ENEMIES_PER_ROOM]Ground_Tracked
	tracked_count := 0
	for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if !actor.visible || actor.health <= 0 || tracked_count == len(tracked) { continue }
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		tracked[tracked_count] = {entity = actor.entity, cell = cell}
		tracked_count += 1
		for before in fx.tracked[:fx.tracked_count] {
			if before.entity != actor.entity || before.cell == cell { continue }
			layers := ground_fx_layers(fx, cell)
			at := ground_fx_cell(fx, cell)
			if .Pool in layers {
				ground_splash(fx, cell, false, world)
				fx.splashed += 1
				if lab { lab_sound_queue(v.lab_sounds, .World_Pool_Splash, renderer.sprite_assets.elapsed, 1, lab_sound_pan(renderer, actor.entity)) }
			}
			if at != nil && at.fire {
				ground_splash(fx, cell, true, world)
				fx.cinders += 1
				if lab { lab_sound_queue(v.lab_sounds, .World_Fire, renderer.sprite_assets.elapsed, 0.7, lab_sound_pan(renderer, actor.entity)) }
			}
		}
	}
	fx.tracked, fx.tracked_count = tracked, tracked_count
	ground_fx_bake(fx, GROUND_BAKES_PER_FRAME)
}

// How many cells a fire's arms cover beyond its centre.
ground_fx_fire_reach :: proc(fire: game.Ground_Fire) -> (cells: i32) {
	for arm in fire.arms { cells += arm }
	return
}

ground_fx_mark_fire :: proc(fx: ^Ground_Fx, cell: grid.Position, final: bool) {
	if ground_fx_cell(fx, cell) == nil { return }
	index := cell.y*fx.width+cell.x
	fx.wanted[index] += {.Char}
	fx.last[index] = fx.last[index] || final
}

ground_splash :: proc(fx: ^Ground_Fx, cell: grid.Position, fire: bool, world: f64) {
	fx.splashes[fx.splash_next] = {used = true, fire = fire, cell = cell, born = world, seed = cell.x*7+cell.y*13+fx.splash_next}
	fx.splash_next = (fx.splash_next+1)%len(fx.splashes)
}

// --------------------------------------------------------------------------
// Drawing.

// The decal, in the 3D pass after the lit floor: depth kept, never written,
// one quad for every cell drawn on (draw_tactical_world).
draw_ground_decal :: proc(renderer: ^Renderer, room: ^game.Room) {
	fx := renderer.tactical.ground
	if fx == nil || fx.cells == nil || room == nil { return }
	t := fx.texels
	width, height := i32(fx.width*t), i32(fx.height*t)
	if fx.texture.id != 0 && (fx.texture.width != width || fx.texture.height != height) {
		rl.UnloadTexture(fx.texture)
		fx.texture = {}
	}
	if fx.texture.id == 0 {
		image := rl.Image{data = raw_data(fx.pixels), width = width, height = height, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		fx.texture = rl.LoadTextureFromImage(image)
		if fx.texture.id == 0 { return }
		rl.SetTextureFilter(fx.texture, .POINT)
		rl.SetTextureWrap(fx.texture, .CLAMP)
		fx.upload_all = false
		for &cell in fx.cells { cell.upload = false }
	}
	if fx.upload_all {
		rl.UpdateTexture(fx.texture, raw_data(fx.pixels))
		fx.upload_all = false
		for &cell in fx.cells { cell.upload = false }
	}
	block: [GROUND_TEXELS*GROUND_TEXELS*4]u8
	for &cell, index in fx.cells {
		if !cell.upload { continue }
		cell.upload = false
		x, y := index%fx.width*t, index/fx.width*t
		for row in 0..<t {
			from := ((y+row)*int(width)+x)*4
			copy(block[row*t*4:(row+1)*t*4], fx.pixels[from:from+t*4])
		}
		rl.UpdateTextureRec(fx.texture, {f32(x), f32(y), f32(t), f32(t)}, raw_data(block[:]))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	rlgl.SetTexture(fx.texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, 255)
	for cell, index in fx.cells {
		if !cell.content { continue }
		at := grid.Position{index%fx.width, index/fx.width}
		if !tactical_cell_on_screen(renderer, at) || !tactical_render_visible(renderer, at) { continue }
		x0, z0 := f32(at.x), f32(at.y)
		u0, v0 := f32(at.x)/f32(fx.width), f32(at.y)/f32(fx.height)
		u1, v1 := f32(at.x+1)/f32(fx.width), f32(at.y+1)/f32(fx.height)
		rlgl.TexCoord2f(u0, v0); rlgl.Vertex3f(x0, GROUND_DECAL_HEIGHT, z0)
		rlgl.TexCoord2f(u0, v1); rlgl.Vertex3f(x0, GROUND_DECAL_HEIGHT, z0+1)
		rlgl.TexCoord2f(u1, v1); rlgl.Vertex3f(x0+1, GROUND_DECAL_HEIGHT, z0+1)
		rlgl.TexCoord2f(u1, v0); rlgl.Vertex3f(x0+1, GROUND_DECAL_HEIGHT, z0)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// The flames and splashes, sorted with the cards and walls (one entry each).
collect_ground_entries :: proc(renderer: ^Renderer, room: ^game.Room, entries: ^[dynamic]Tactical_Alpha_Entry) {
	fx := renderer.tactical.ground
	if fx == nil || fx.cells == nil || room == nil || !renderer.tactical.attack_props.loaded { return }
	world := tactical_world_time(renderer)
	toward := attack_toward_camera(renderer)
	for cell, index in fx.cells {
		if !cell.fire && (cell.quenched <= 0 || world-cell.quenched > GROUND_FLAME_OUT_SECONDS) { continue }
		at := grid.Position{index%fx.width, index/fx.width}
		if !tactical_cell_on_screen(renderer, at) || !tactical_render_visible(renderer, at) || game.cell_blocks_movement(room, at) { continue }
		// A hair toward the camera: the flame stands in front of a card on its cell.
		append(entries, Tactical_Alpha_Entry{kind = .Ground, ground = i32(index), position = {f32(at.x)+toward.x*0.12, f32(at.y)+toward.z*0.12}})
	}
	for splash, index in fx.splashes {
		if !splash.used || world-splash.born > GROUND_SPLASH_SECONDS || !tactical_render_visible(renderer, splash.cell) { continue }
		append(entries, Tactical_Alpha_Entry{kind = .Ground, ground = i32(len(fx.cells)+index),
			position = {f32(splash.cell.x)+toward.x*0.3, f32(splash.cell.y)+toward.z*0.3}})
	}
}

draw_ground_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	fx := renderer.tactical.ground
	if fx == nil || entry.ground < 0 { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	world := tactical_world_time(renderer)
	index := int(entry.ground)
	if index < len(fx.cells) {
		draw_ground_flame(renderer, fx, index, world)
		return
	}
	index -= len(fx.cells)
	if index < len(fx.splashes) { draw_ground_splash(renderer, &fx.splashes[index], world) }
}

draw_ground_flame :: proc(renderer: ^Renderer, fx: ^Ground_Fx, index: int, world: f64) {
	cell := &fx.cells[index]
	at := grid.Position{index%fx.width, index/fx.width}
	seed := int(gothic_hash(at.x, at.y)%997)
	// Up from the pop, down to nothing once out; lower on its last window.
	scale := f32(1)
	if cell.fire {
		u := f32(clamp((world-cell.lit)/GROUND_FLAME_POP_SECONDS, 0, 1))
		c := f32(1.7)
		w := u-1
		scale = 1+w*w*((c+1)*w+c)
		if cell.last { scale *= 0.72 }
	} else {
		u := f32(clamp((world-cell.quenched)/GROUND_FLAME_OUT_SECONDS, 0, 1))
		scale = (1-u)*(0.72 if cell.last else 1)
	}
	if scale <= 0.02 { return }
	flicker := int(math.floor(world*8+f64(seed)*0.37))%2 == 0
	prop := gfx.Attack_Prop.Flame_A if flicker else .Flame_B
	size := f32(1.5)
	if !cell.centre { prop, size = gfx.Attack_Prop.Flame_C if flicker else gfx.Attack_Prop.Flame_D, 1.3 }
	sway := f32(math.sin(world*3.1+f64(seed)))*0.05
	right := flipbook_camera_right(renderer)
	grip := rl.Vector3{f32(at.x)+0.5, 0.03, f32(at.y)+0.5}+right*(f32(seed%5-2)*0.03)
	tip := grip+rl.Vector3{0, 1, 0}+right*sway
	draw_attack_prop(renderer, prop, grip, tip, attack_texel(.Pilgrim)*size*scale, clamp(scale*1.6, 0, 1))
}

draw_ground_splash :: proc(renderer: ^Renderer, splash: ^Ground_Splash, world: f64) {
	t := f32((world-splash.born)/GROUND_SPLASH_SECONDS)
	if t < 0 || t > 1 { return }
	right, up := attack_screen_axes(renderer)
	toward := attack_toward_camera(renderer)
	centre := rl.Vector3{f32(splash.cell.x)+0.5, 0.05, f32(splash.cell.y)+0.5}
	texel := attack_texel(.Pilgrim)
	count := 6 if splash.fire else 7
	for drop in 0..<count {
		angle := f32(drop)*math.TAU/f32(count)+f32(splash.seed%7)*0.4
		out := right*math.cos(angle)+toward*math.sin(angle)*0.6
		speed := 0.42+f32((splash.seed+drop*5)%4)*0.07
		point := centre+out*(speed*t)+rl.Vector3{0, (0.9 if splash.fire else 0.75)*t-0.8*t*t, 0}
		prop := gfx.Attack_Prop.Cinder if splash.fire else (gfx.Attack_Prop.Drop_A if drop%2 == 0 else gfx.Attack_Prop.Drop_B)
		turn := t*6+f32(drop)
		draw_attack_prop(renderer, prop, point, point+up*math.cos(turn)+right*math.sin(turn), texel*1.8, clamp((1-t)*2.5, 0, 1))
	}
	if !splash.fire {
		// A ripple of the pool's light spreading out on its surface.
		rl.DrawCircle3D(centre+rl.Vector3{0, -0.024, 0}, 0.1+0.25*t, {1, 0, 0}, 90, color_with_opacity(GROUND_VENOM_GLINT, (1-t)*0.45))
	}
}

// The thrown flask or ember of a ground card's Spell_Launched: on a paper arc
// from the player to its cell (draw_tactical_spell_flight's place).
draw_ground_throw :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	if !renderer.tactical.attack_props.loaded { return }
	p := presentation_cue_progress(cue)
	from := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.7, f32(cue.event.from_position.y)+0.5}
	to := rl.Vector3{f32(cue.event.to_position.x)+0.5, 0.08, f32(cue.event.to_position.y)+0.5}
	point := from+(to-from)*p+rl.Vector3{0, math.sin(p*math.PI)*0.75, 0}
	if !tactical_render_visible(renderer, attack_board_cell(point)) { return }
	fire := cue.event.card_definition == .Wildfire
	world := tactical_world_time(renderer)
	right := flipbook_camera_right(renderer)
	texel := attack_texel(.Pilgrim)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	if fire {
		prop := gfx.Attack_Prop.Ember_A if int(math.floor(world*16))%2 == 0 else .Ember_B
		heading := rl.Vector3Normalize((to-from)+rl.Vector3{0, math.cos(p*math.PI)*0.75*math.PI, 0})
		draw_attack_prop(renderer, prop, point-heading*attack_prop_length(prop, texel*1.2), point, texel*1.2, 1)
		return
	}
	// The flask tumbles as it flies.
	spin := p*9
	axis := rl.Vector3{0, 1, 0}*math.cos(spin)+right*math.sin(spin)
	length := attack_prop_length(.Flask, texel*1.2)
	draw_attack_prop(renderer, .Flask, point-axis*length*0.5, point+axis, texel*1.2, 1)
}

// The flat board's ground (draw_tactical_world without the 3D scene): a pool
// a green diamond edged with paper and ink where the floor is dry beside it, a
// burning cell an ember diamond and its pixel flame.
draw_ground_flat :: proc(renderer: ^Renderer, room: ^game.Room) {
	fx := renderer.tactical.ground
	if fx == nil || fx.cells == nil { return }
	world := tactical_world_time(renderer)
	pixel := max(f32(2), 2.5*renderer.camera.zoom)
	for cell, index in fx.cells {
		if cell.layers == {} { continue }
		at := grid.Position{index%fx.width, index/fx.width}
		if !tactical_render_visible(renderer, at) { continue }
		vertices := tile_vertices(renderer, at)
		if .Char in cell.layers { draw_diamond(inset_vertices(vertices, 0.9), {92, 34, 26, 210}, {196, 76, 34, 255}) }
		if .Pool in cell.layers {
			draw_diamond(inset_vertices(vertices, 0.94), {52, 128, 72, 200}, {52, 128, 72, 200})
			// Each side whose neighbour is dry: paper, and its ink outside.
			sides := [4]struct{offset: grid.Position, a, b: rl.Vector2}{
				{{0, -1}, to_raylib(vertices.top), to_raylib(vertices.right)},
				{{1, 0}, to_raylib(vertices.right), to_raylib(vertices.bottom)},
				{{0, 1}, to_raylib(vertices.bottom), to_raylib(vertices.left)},
				{{-1, 0}, to_raylib(vertices.left), to_raylib(vertices.top)},
			}
			centre := to_raylib(cell_center(renderer, at))
			for side in sides {
				if .Pool in ground_fx_layers(fx, {at.x+side.offset.x, at.y+side.offset.y}) { continue }
				inward := rl.Vector2Normalize(centre-(side.a+side.b)*0.5)
				rl.DrawLineEx(side.a+inward*2, side.b+inward*2, 2, LIVING_TOKEN_PAPER)
				rl.DrawLineEx(side.a, side.b, 1, LIVING_TOKEN_INK)
			}
		}
		if .Char in cell.layers {
			centre := cell_center(renderer, at)
			size := pixel+(1 if cell.centre else 0)
			x := math.round(centre.x-f32(STATUS_TAG_WIDTH)*size*0.5)
			y := math.round(centre.y-7*size*0.8)
			glow := int(math.floor(world*6+f64(index)))%2 == 0
			for row in 0..<7 {
				draw_pixel_row(STATUS_TAG_FLAME[row]&~(STATUS_TAG_FLAME_CORE[row] if glow else 0), STATUS_TAG_WIDTH, x, y+f32(row)*size, size, STATUS_TAG_EMBER)
				if glow { draw_pixel_row(STATUS_TAG_FLAME_CORE[row], STATUS_TAG_WIDTH, x, y+f32(row)*size, size, STATUS_TAG_EMBER_CORE) }
			}
		}
	}
	_ = room
}

// The cells a ground card would cover from the hovered cell: a pool's own and
// those it would close (game.ground_pool_fill), a fire's whole reach. Drawn
// by the card's target range (draw_card_target_range).
draw_ground_preview :: proc(renderer: ^Renderer, room: ^game.Room, id: game.Card_Id, anchor: grid.Position, valid: bool) {
	if !valid { return }
	if id == .Poison_Pool {
		cells: [dynamic]grid.Position
		defer delete(cells)
		game.ground_pool_fill(room, anchor, &cells)
		if len(cells) < 2 { return }
		for cell in cells[1:] { draw_card_range_cell(renderer, cell, {52, 128, 72, 120}, {150, 222, 132, 255}) }
		return
	}
	reach := game.ground_fire_reach(room, anchor)
	steps := game.GROUND_ARM_STEPS
	for step, direction in steps {
		for distance in 1..=int(reach.arms[direction]) {
			cell := grid.Position{anchor.x+step.x*distance, anchor.y+step.y*distance}
			draw_card_range_cell(renderer, cell, {196, 76, 34, u8(90-distance*14)}, {244, 157, 104, u8(230-distance*30)})
		}
	}
}
