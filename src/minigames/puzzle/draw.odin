package puzzle

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import rng "../../engine/rng"
import tween "../../engine/tween"
import ui "../../engine/ui"

// Presentation: tweened bodies, glows, particles and the HUD. It only reads
// the rules state; every change of position, whatever caused it (move, undo,
// redo, restart), is animated by `view_follow`.

STEP_TIME :: 0.13 // first cell of a move
SLIDE_CELL_TIME :: 0.05 // each extra cell on ice; shorter, so slides feel fast
UNDO_TIME :: 0.09
REWIND_TIME :: 0.32

Body :: struct {
	from, to:   [2]f32, // cell coordinates
	elapsed:    f32,
	duration:   f32,
	squash:     f32, // 1 -> 0 pulse after a push or a landing
	squash_dir: Dir,
	bump:       f32, // 1 -> 0 nudge after a blocked move
	bump_dir:   Dir,
}

Ring :: struct {
	center:   [2]f32,
	t:        f32,
	duration: f32,
	radius:   f32,
	color:    rl.Color,
}

// A sigil lights up when its crate actually arrives, not when the move is
// decided, so the effect waits for the slide to finish.
Pending_Burst :: struct {
	cell:  int,
	delay: f32,
}

Layout :: struct {
	scale:  f32,
	tile:   f32,
	origin: [2]f32, // top-left corner of cell (0, 0)
}

MAX_TORCHES :: 6
MAX_RINGS :: 12
MAX_PENDING :: 4

View :: struct {
	sprites:       Sprites,
	layout:        Layout,
	player:        Body,
	crates:        [MAX_CRATES]Body,
	facing:        Dir,
	gate_open:     f32, // 0 closed .. 1 open
	sigil_fill:    [MAX_CELLS]f32,
	particles:     fx.Particles(640),
	rings:         [MAX_RINGS]Ring,
	ring_count:    int,
	pending:       [MAX_PENDING]Pending_Burst,
	pending_count: int,
	flash:         fx.Flash,
	shake:         f32,
	rng:           rng.Rng,
	torches:       [MAX_TORCHES]int,
	torch_count:   int,
	mote_timer:    f32,
	hint_dir:      Dir,
	hint_time:     f32,
	message:       string, // literal, shown briefly under the HUD
	message_time:  f32,
}

view_create :: proc(v: ^View) {
	v.sprites = sprites_create()
}

view_destroy :: proc(v: ^View) {
	sprites_destroy(&v.sprites)
}

@(private)
cell_vec :: proc(b: ^Board, cell: int) -> [2]f32 {
	p := cell_xy(b, cell)
	return {f32(p.x), f32(p.y)}
}

@(private)
cell_hash :: proc "contextless" (x, y: int) -> u32 {
	h := u32(x)*73856093 ~ u32(y)*19349663
	h ~= h >> 13
	h *= 0x5bd1e995
	return h ~ (h >> 15)
}

compute_layout :: proc(b: ^Board, canvas: rl.Rectangle) -> Layout {
	area := rl.Rectangle{16, 50, canvas.width - 32, canvas.height - 50 - 26}
	scale := 1
	for s := 4; s >= 1; s -= 1 {
		w := f32(b.width * TILE_PX * s)
		h := f32(b.height*TILE_PX*s + WALL_FRONT_PX*s)
		if w <= area.width && h <= area.height {
			scale = s
			break
		}
	}
	tile := f32(TILE_PX * scale)
	w := f32(b.width) * tile
	h := f32(b.height)*tile + f32(WALL_FRONT_PX*scale)
	origin := [2]f32{
		math.round(area.x + (area.width-w)*0.5),
		math.round(area.y + (area.height-h)*0.5 + f32(WALL_FRONT_PX*scale)),
	}
	return Layout{scale = f32(scale), tile = tile, origin = origin}
}

// Snaps everything to the puzzle state, e.g. when a level loads.
view_reset :: proc(v: ^View, p: ^Puzzle, canvas: rl.Rectangle, seed: u64) {
	b := &p.board
	v.layout = compute_layout(b, canvas)
	v.player = Body{from = cell_vec(b, int(p.state.player)), to = cell_vec(b, int(p.state.player))}
	for i in 0..<MAX_CRATES {
		v.crates[i] = {}
		if i < int(p.state.crate_count) {
			c := cell_vec(b, int(p.state.crates[i]))
			v.crates[i] = Body{from = c, to = c}
		}
	}
	v.facing = .Down
	v.gate_open = 1 if gates_open(b, &p.state) else 0
	v.sigil_fill = {}
	for i in 0..<int(p.state.crate_count) {
		if b.tiles[p.state.crates[i]] == .Sigil {
			v.sigil_fill[p.state.crates[i]] = 1
		}
	}
	fx.clear(&v.particles)
	v.ring_count = 0
	v.pending_count = 0
	v.hint_time = 0
	v.message_time = 0
	v.rng = rng.create(rng.derive(seed, 0xF1A3))
	// Torches hang on lit wall faces, spread out so no two are adjacent.
	v.torch_count = 0
	for y in 0..<b.height {
		for x in 0..<b.width {
			// Only on thick walls: a torch on a lone pillar looks misplaced.
			if v.torch_count >= MAX_TORCHES || tile_at(b, x, y) != .Wall || !walkable(tile_at(b, x, y+1)) ||
			   walkable(tile_at(b, x, y-1)) {
				continue
			}
			if cell_hash(x, y)%5 != 0 {
				continue
			}
			near := false
			for i in 0..<v.torch_count {
				q := cell_xy(b, v.torches[i])
				if abs(q.x-x) <= 2 && abs(q.y-y) <= 1 {
					near = true
				}
			}
			if !near {
				cell, _ := cell_at(b, x, y)
				v.torches[v.torch_count] = cell
				v.torch_count += 1
			}
		}
	}
}

@(private)
retarget :: proc(body: ^Body, target: [2]f32, mode: Follow_Mode) {
	if body.to == target {
		return
	}
	current := body_pos(body^)
	d := max(abs(target.x-current.x), abs(target.y-current.y))
	body.from = current
	body.to = target
	body.elapsed = 0
	switch mode {
	case .Move:
		body.duration = STEP_TIME + SLIDE_CELL_TIME*max(d-1, 0)
	case .Undo:
		body.duration = UNDO_TIME + 0.035*max(d-1, 0)
	case .Rewind:
		body.duration = REWIND_TIME
	}
}

Follow_Mode :: enum u8 {
	Move,
	Undo,
	Rewind,
}

// Starts tweens toward the current state for every body that changed cell.
view_follow :: proc(v: ^View, p: ^Puzzle, mode: Follow_Mode) {
	b := &p.board
	retarget(&v.player, cell_vec(b, int(p.state.player)), mode)
	for i in 0..<int(p.state.crate_count) {
		retarget(&v.crates[i], cell_vec(b, int(p.state.crates[i])), mode)
	}
	if mode != .Move {
		// Sigils dim at once on undo; they relight through the burst path.
		for cell in 0..<b.width*b.height {
			if b.tiles[cell] == .Sigil && crate_slot(&p.state, cell) < 0 {
				v.sigil_fill[cell] = min(v.sigil_fill[cell], 0.4)
			}
		}
		for i in 0..<int(p.state.crate_count) {
			cell := int(p.state.crates[i])
			if b.tiles[cell] == .Sigil {
				v.sigil_fill[cell] = max(v.sigil_fill[cell], 0.6)
			}
		}
	}
}

body_pos :: proc(b: Body) -> [2]f32 {
	if b.duration <= 0 || b.elapsed >= b.duration {
		return b.to
	}
	return tween.lerp(b.from, b.to, tween.ease(.Out_Cubic, b.elapsed/b.duration))
}

@(private)
body_moving :: proc(b: Body) -> bool {
	return b.elapsed < b.duration
}

// Busy while bodies are still travelling; the last stretch of a tween is
// left open so a queued move chains without a visible stop.
view_busy :: proc(v: ^View, crate_count: int) -> bool {
	if v.player.elapsed < v.player.duration*0.8 {
		return true
	}
	for i in 0..<crate_count {
		c := v.crates[i]
		if c.elapsed < c.duration*0.8 {
			return true
		}
	}
	return false
}

@(private)
screen_of :: proc(v: ^View, cell: [2]f32) -> [2]f32 {
	return v.layout.origin + cell*v.layout.tile
}

@(private)
cell_center :: proc(v: ^View, cell: [2]f32) -> [2]f32 {
	return screen_of(v, cell) + v.layout.tile*0.5
}

@(private)
add_ring :: proc(v: ^View, center: [2]f32, radius, duration: f32, color: rl.Color) {
	if v.ring_count >= MAX_RINGS {
		return
	}
	v.rings[v.ring_count] = Ring{center = center, radius = radius, duration = duration, color = color}
	v.ring_count += 1
}

// Effects that belong to a move; positions are animated by view_follow.
view_on_move :: proc(v: ^View, p: ^Puzzle, r: Move_Result) {
	b := &p.board
	v.facing = r.dir
	v.hint_time = 0
	delta := dir_delta(r.dir)
	dvec := [2]f32{f32(delta.x), f32(delta.y)}
	s := v.layout.scale
	if r.pushed {
		c := &v.crates[r.crate]
		c.squash = 1
		c.squash_dir = r.dir
		// Grit kicked up behind the relic.
		back := cell_center(v, cell_vec(b, r.crate_from)) - dvec*v.layout.tile*0.35
		e := fx.DUST
		e.direction = {-dvec.x, -dvec.y - 0.6, 0}
		e.size_start = 2.2 * s
		e.speed_min, e.speed_max = 12*s, 34*s
		e.color_start = {170, 160, 150, 170}
		e.color_end = {120, 110, 110, 0}
		fx.emit(&v.particles, e, {back.x, back.y + v.layout.tile*0.3, 0}, 6, &v.rng)
		if r.sigil_filled && v.pending_count < MAX_PENDING {
			delay := STEP_TIME + SLIDE_CELL_TIME*f32(max(abs_cells(b, r.crate_from, r.crate_to)-1, 0))
			v.pending[v.pending_count] = Pending_Burst{cell = r.crate_to, delay = delay*0.85}
			v.pending_count += 1
		}
		if r.sigil_left {
			v.sigil_fill[r.crate_from] = 0.5
		}
	}
	if r.crate_slid || r.player_slid {
		// Frost spray at the start of the slide.
		from := r.crate_from if r.crate_slid else r.player_from
		at := cell_center(v, cell_vec(b, from) + dvec)
		e := fx.SPARKS
		e.direction = {-dvec.x, -dvec.y, 0}
		e.spread = 0.9
		e.speed_min, e.speed_max = 30*s, 80*s
		e.size_start = 1.6 * s
		e.gravity = 40 * s
		e.color_start = {230, 250, 255, 230}
		e.color_end = {120, 190, 255, 0}
		fx.emit(&v.particles, e, {at.x, at.y + v.layout.tile*0.25, 0}, 10, &v.rng)
	}
	if r.gates_opened || r.gates_closed {
		for cell in 0..<b.width*b.height {
			if b.tiles[cell] == .Gate {
				add_ring(v, cell_center(v, cell_vec(b, cell)), v.layout.tile*0.8, 0.45,
					{140, 255, 210, 200} if r.gates_opened else {200, 120, 90, 160})
			}
		}
	}
}

@(private)
abs_cells :: proc(b: ^Board, a, c: int) -> int {
	pa := cell_xy(b, a)
	pc := cell_xy(b, c)
	return max(abs(pa.x-pc.x), abs(pa.y-pc.y))
}

view_bump :: proc(v: ^View, d: Dir) {
	v.facing = d
	v.player.bump = 1
	v.player.bump_dir = d
}

view_message :: proc(v: ^View, text: string, seconds: f32 = 2.2) {
	v.message = text
	v.message_time = seconds
}

// Big golden burst on every sigil, used when the level is solved.
view_celebrate :: proc(v: ^View, p: ^Puzzle) {
	b := &p.board
	s := v.layout.scale
	for cell in 0..<b.width*b.height {
		if b.tiles[cell] != .Sigil {
			continue
		}
		at := cell_center(v, cell_vec(b, cell))
		e := fx.BURST
		e.speed_min, e.speed_max = 40*s, 120*s
		e.size_start = 3 * s
		e.gravity = 60 * s
		e.life_min, e.life_max = 0.5, 1.2
		e.color_start = {255, 240, 170, 255}
		e.color_end = {255, 140, 60, 0}
		fx.emit(&v.particles, e, {at.x, at.y, 0}, 26, &v.rng)
		add_ring(v, at, v.layout.tile*2.2, 0.9, {255, 220, 130, 220})
	}
	fx.flash_start(&v.flash, {255, 236, 190, 90}, 0.5)
}

// Gameplay animation; frozen while the shell is paused.
view_update :: proc(v: ^View, p: ^Puzzle, dt: f32) {
	b := &p.board
	advance :: proc(body: ^Body, dt: f32) {
		body.elapsed = min(body.elapsed+dt, body.duration)
		body.squash = max(body.squash-dt*5, 0)
		body.bump = max(body.bump-dt*6, 0)
	}
	advance(&v.player, dt)
	for i in 0..<int(p.state.crate_count) {
		advance(&v.crates[i], dt)
	}
	target := f32(1) if gates_open(b, &p.state) else 0
	v.gate_open = tween.approach(v.gate_open, target, dt*5)
	// Sigils fade toward their state; covering ones go through the bursts.
	for cell in 0..<b.width*b.height {
		if b.tiles[cell] != .Sigil {
			continue
		}
		if crate_slot(&p.state, cell) < 0 {
			v.sigil_fill[cell] = tween.approach(v.sigil_fill[cell], 0, dt*3)
		}
	}
	i := 0
	for i < v.pending_count {
		pb := &v.pending[i]
		pb.delay -= dt
		if pb.delay > 0 {
			i += 1
			continue
		}
		if crate_slot(&p.state, pb.cell) >= 0 {
			light_sigil(v, b, pb.cell)
		}
		v.pending[i] = v.pending[v.pending_count-1]
		v.pending_count -= 1
	}
	for cell in 0..<b.width*b.height {
		if b.tiles[cell] == .Sigil && crate_slot(&p.state, cell) >= 0 && v.sigil_fill[cell] >= 0.55 {
			v.sigil_fill[cell] = tween.approach(v.sigil_fill[cell], 1, dt*2)
		}
	}
	j := 0
	for j < v.ring_count {
		v.rings[j].t += dt
		if v.rings[j].t >= v.rings[j].duration {
			v.rings[j] = v.rings[v.ring_count-1]
			v.ring_count -= 1
			continue
		}
		j += 1
	}
	fx.flash_update(&v.flash, dt)
	v.shake = max(v.shake-dt*4, 0)
	v.hint_time = max(v.hint_time-dt, 0)
	v.message_time = max(v.message_time-dt, 0)
}

@(private)
light_sigil :: proc(v: ^View, b: ^Board, cell: int) {
	v.sigil_fill[cell] = 0.6
	at := cell_center(v, cell_vec(b, cell))
	s := v.layout.scale
	e := fx.SPARKS
	e.speed_min, e.speed_max = 40*s, 110*s
	e.size_start = 2 * s
	e.gravity = 80 * s
	e.color_start = {255, 246, 200, 255}
	e.color_end = {255, 170, 60, 0}
	fx.emit(&v.particles, e, {at.x, at.y, 0}, 18, &v.rng)
	add_ring(v, at, v.layout.tile*1.1, 0.5, {255, 214, 120, 230})
	slot := -1
	for i in 0..<MAX_CRATES {
		if v.crates[i].to == cell_vec(b, cell) {
			slot = i
		}
	}
	if slot >= 0 {
		v.crates[slot].squash = 0.7
		v.crates[slot].squash_dir = .Down
	}
	v.shake = max(v.shake, 0.6)
}

// Ambient life that keeps going during intro and pause.
view_ambient :: proc(v: ^View, p: ^Puzzle, dt: f32) {
	fx.update(&v.particles, dt)
	v.mote_timer -= dt
	if v.mote_timer > 0 {
		return
	}
	v.mote_timer = 0.18
	b := &p.board
	cell := int(rng.below(&v.rng, u64(b.width*b.height)))
	if !walkable(b.tiles[cell]) {
		return
	}
	at := screen_of(v, cell_vec(b, cell)) + {rng.float01(&v.rng), rng.float01(&v.rng)}*v.layout.tile
	s := v.layout.scale
	fx.spawn(&v.particles, fx.Particle{
		position    = {at.x, at.y, 0},
		velocity    = {rng.float_signed(&v.rng)*4*s, -6*s - rng.float01(&v.rng)*6*s, 0},
		life        = 2.6,
		max_life    = 2.6,
		size_start  = 1.2 * s,
		size_end    = 0,
		color_start = {200, 190, 255, 90},
		color_end   = {160, 150, 220, 0},
	})
}

// ---------------------------------------------------------------------------
// Drawing

Draw_Params :: struct {
	time:        f32,
	reveal:      f32, // 0..1 level entrance; 1 = fully built
	celebrate:   f32, // seconds since the level was solved, < 0 when not
	shake_scale: f32,
}

@(private)
reveal_at :: proc(params: Draw_Params, x, y, w, h: int) -> f32 {
	if params.reveal >= 1 {
		return 1
	}
	order := f32(x+y) / f32(max(w+h-2, 1))
	return clamp((params.reveal*1.6 - order*0.6) / 0.4, 0, 1)
}

draw_world :: proc(v: ^View, p: ^Puzzle, params: Draw_Params) {
	b := &p.board
	L := v.layout
	T := L.tile
	s := L.scale
	time := params.time

	offset := [2]f32{}
	if v.shake > 0 && params.shake_scale > 0 {
		k := v.shake * v.shake * 3 * s * params.shake_scale
		offset = {math.sin(time*91)*k, math.cos(time*77)*k}
	}
	saved := L.origin
	v.layout.origin += offset
	defer v.layout.origin = saved

	// Floor layer.
	for y in 0..<b.height {
		for x in 0..<b.width {
			t := tile_at(b, x, y)
			if !walkable(t) {
				continue
			}
			k := reveal_at(params, x, y, b.width, b.height)
			if k <= 0 {
				continue
			}
			pos := screen_of(v, {f32(x), f32(y)})
			pos.y += (1 - tween.ease(.Out_Cubic, k)) * 10 * s
			dest := rl.Rectangle{pos.x, pos.y, T, T}
			tint := ui.with_alpha(rl.WHITE, k)
			h := cell_hash(x, y)
			switch t {
			case .Floor:
				frame := 0 if h%7 < 4 else (1 if h%7 < 6 else 2)
				blit(v.sprites.floor, frame, dest, tint)
			case .Ice:
				blit(v.sprites.ice, int(h%2), dest, tint)
				// A slow glint sweeps diagonally across the frozen floor.
				phase := math.mod(f32(x+y)*0.8 - time*2.4, 14)
				shine := max(1 - abs(phase-2)/1.4, 0)
				if shine > 0 {
					rl.DrawRectangleRec(dest, {255, 255, 255, u8(46*shine*k)})
				}
			case .Sigil:
				blit(v.sprites.sigil, 0, dest, tint)
			case .Plate:
				pressed := occupied(&p.state, y*b.width+x)
				blit(v.sprites.plate, 1 if pressed else 0, dest, tint)
			case .Gate:
				blit(v.sprites.gate_slot, 0, dest, tint)
			case .Void, .Wall:
			}
			// Contact shadow from walls above and to the left.
			if tile_at(b, x, y-1) == .Wall {
				rl.DrawRectangleGradientV(i32(pos.x), i32(pos.y), i32(T), i32(T*0.4),
					{0, 0, 0, u8(130*k)}, {0, 0, 0, 0})
			}
			if tile_at(b, x-1, y) == .Wall {
				rl.DrawRectangleGradientH(i32(pos.x), i32(pos.y), i32(T*0.25), i32(T),
					{0, 0, 0, u8(70*k)}, {0, 0, 0, 0})
			}
		}
	}

	draw_sigil_glows(v, p, params)
	draw_rings(v)

	// Shadows of the bodies, under everything that stands.
	if params.reveal >= 1 {
		for i in 0..<int(p.state.crate_count) {
			c := screen_of(v, body_pos(v.crates[i])) + {T*0.5, T*0.92}
			rl.DrawEllipse(i32(c.x), i32(c.y), T*0.44, T*0.13, {0, 0, 0, 90})
		}
		pc := screen_of(v, body_pos(v.player)) + {T*0.5, T*0.9}
		rl.DrawEllipse(i32(pc.x), i32(pc.y), T*0.3, T*0.1, {0, 0, 0, 100})
	}

	// Standing layer, back to front by row.
	for y in 0..<b.height {
		for x in 0..<b.width {
			t := tile_at(b, x, y)
			k := reveal_at(params, x, y, b.width, b.height)
			if k <= 0 {
				continue
			}
			lift := (1 - tween.ease(.Out_Cubic, k)) * 10 * s
			if t == .Wall {
				draw_wall(v, b, x, y, k, lift, time)
			} else if t == .Gate {
				draw_gate(v, p, x, y, k, lift)
			}
		}
		if params.reveal < 0.85 {
			continue
		}
		appear := clamp((params.reveal-0.85)/0.15, 0, 1)
		for i in 0..<int(p.state.crate_count) {
			if body_row(v.crates[i]) == y {
				draw_crate(v, b, i, appear, params)
			}
		}
		if body_row(v.player) == y {
			draw_hero(v, appear, time)
		}
	}

	fx.draw2d(&v.particles)
	draw_lights(v, p, params)
}

@(private)
body_row :: proc(b: Body) -> int {
	return int(math.ceil(body_pos(b).y - 0.01))
}

@(private)
draw_wall :: proc(v: ^View, b: ^Board, x, y: int, k, lift: f32, time: f32) {
	T := v.layout.tile
	s := v.layout.scale
	H := f32(WALL_FRONT_PX) * s
	pos := screen_of(v, {f32(x), f32(y)})
	pos.y += lift
	h := cell_hash(x, y)
	// Walls with no walkable neighbour are backdrop: darker, so the room reads.
	inner := false
	for dy in -1..=1 {
		for dx in -1..=1 {
			if walkable(tile_at(b, x+dx, y+dy)) {
				inner = true
			}
		}
	}
	shade := rl.Color{255, 255, 255, 255} if inner else rl.Color{150, 146, 166, 255}
	tint := ui.with_alpha(shade, k)
	// The top face rises into the cell above only when nothing playable is
	// there, so a wall never hides a sigil or a relic standing behind it.
	raise := H if !walkable(tile_at(b, x, y-1)) else 0
	top := pos.y - raise
	blit(v.sprites.wall_top, int(h%2), {pos.x, top, T, T}, tint)
	rim := ui.with_alpha({112, 106, 132, 255}, k)
	dark := ui.with_alpha({30, 27, 40, 255}, k)
	if tile_at(b, x, y-1) != .Wall {
		rl.DrawRectangleRec({pos.x, top, T, s}, rim)
	}
	if tile_at(b, x-1, y) != .Wall {
		rl.DrawRectangleRec({pos.x, top, s, T}, ui.with_alpha({96, 90, 114, 255}, k))
	}
	if tile_at(b, x+1, y) != .Wall {
		rl.DrawRectangleRec({pos.x + T - s, top, s, T}, dark)
	}
	below := tile_at(b, x, y+1)
	if below != .Wall {
		front := rl.Rectangle{pos.x, pos.y + T - H, T, H}
		blit(v.sprites.wall_front, int((h>>3)%2), front, tint)
		if below == .Void {
			// Outer face: fade into the dark instead of floating.
			rl.DrawRectangleGradientV(i32(front.x), i32(front.y + front.height), i32(T), i32(H*1.5),
				ui.with_alpha({0, 0, 0, 160}, k), {0, 0, 0, 0})
		}
	}
	cell, _ := cell_at(b, x, y)
	for i in 0..<v.torch_count {
		if v.torches[i] != cell {
			continue
		}
		fpos := [2]f32{pos.x + T*0.5 - 3*s, pos.y + T - H - 7*s}
		frame := int(time*9 + f32(h%3)) % 3
		blit(v.sprites.flame, frame, {fpos.x, fpos.y, 6*s, 8*s}, ui.with_alpha(rl.WHITE, k))
	}
}

@(private)
draw_gate :: proc(v: ^View, p: ^Puzzle, x, y: int, k, lift: f32) {
	b := &p.board
	T := v.layout.tile
	s := v.layout.scale
	cell, _ := cell_at(b, x, y)
	shown := 1 - v.gate_open
	if occupied(&p.state, cell) && !gates_open(b, &p.state) {
		// Jammed on whatever stands in the doorway.
		shown = min(shown, 0.3)
	}
	if shown <= 0.01 {
		return
	}
	pos := screen_of(v, {f32(x), f32(y)})
	pos.y += lift
	bars_h := f32(v.sprites.gate_bars.height)
	visible := bars_h * shown
	src := rl.Rectangle{0, 0, f32(v.sprites.gate_bars.width), visible}
	bottom := pos.y + T - s
	dest := rl.Rectangle{pos.x, bottom - visible*s, T, visible * s}
	if v.sprites.gate_bars.texture.id != 0 {
		rl.DrawTexturePro(v.sprites.gate_bars.texture, src, dest, {0, 0}, 0, ui.with_alpha(rl.WHITE, k))
	}
}

@(private)
draw_crate :: proc(v: ^View, b: ^Board, i: int, appear: f32, params: Draw_Params) {
	T := v.layout.tile
	s := v.layout.scale
	body := v.crates[i]
	cell_pos := body_pos(body)
	pos := screen_of(v, cell_pos)
	// Squash along the push: shorter in the direction of travel, then back.
	sq := body.squash
	sx, sy := f32(1), f32(1)
	if sq > 0 {
		k := math.sin(sq*math.PI) * 0.12
		switch body.squash_dir {
		case .Left, .Right:
			sx, sy = 1-k, 1+k*0.6
		case .Up, .Down:
			sx, sy = 1+k*0.6, 1-k
		}
	}
	drop := (1 - tween.ease(.Out_Bounce, appear)) * 28 * s
	w := 16 * s * sx
	h := 18 * s * sy
	feet := [2]f32{pos.x + T*0.5, pos.y + T - s + 0.5*s}
	dest := rl.Rectangle{feet.x - w*0.5, feet.y - h + s - drop, w, h}
	cell := int(math.round(cell_pos.y))*b.width + int(math.round(cell_pos.x))
	lit := !body_moving(body) && cell >= 0 && cell < MAX_CELLS && b.tiles[cell] == .Sigil && v.sigil_fill[cell] > 0.5
	if params.celebrate >= 0 {
		lit = true
	}
	blit(v.sprites.crate, 1 if lit else 0, dest, ui.with_alpha(rl.WHITE, appear))
}

@(private)
draw_hero :: proc(v: ^View, appear: f32, time: f32) {
	T := v.layout.tile
	s := v.layout.scale
	body := v.player
	pos := screen_of(v, body_pos(body))
	if body.bump > 0 {
		d := dir_delta(body.bump_dir)
		k := math.sin(body.bump*math.PI) * 0.12 * T
		pos += {f32(d.x), f32(d.y)} * k
	}
	frame := 0
	flip := false
	switch v.facing {
	case .Down:
		frame = 0
	case .Up:
		frame = 2
	case .Left:
		frame = 4
	case .Right:
		frame = 4
		flip = true
	}
	bob := f32(0)
	if body_moving(body) {
		t := body.elapsed / max(body.duration, 0.001)
		bob = -math.sin(t*math.PI) * 1.5 * s
		if t > 0.3 && t < 0.8 {
			frame += 1
		}
	} else {
		// Idle breathing keeps the hero alive while the player thinks.
		bob = -math.round(tween.pulse01(time, 1.6)) * s
	}
	drop := (1 - tween.ease(.Out_Back, appear)) * 18 * s
	dest := rl.Rectangle{pos.x, pos.y + T - 17*s + bob - drop, 16 * s, 16 * s}
	lantern := lantern_pixel(v.facing)
	lx := dest.x + lantern.x*s
	ly := dest.y + lantern.y*s
	behind := v.facing == .Up
	if behind {
		draw_lantern(lx, ly, s, appear)
	}
	blit(v.sprites.hero, frame, dest, ui.with_alpha(rl.WHITE, appear), flip)
	if !behind {
		draw_lantern(lx, ly, s, appear)
	}
}

// Hand position in sprite pixels for each facing.
@(private)
lantern_pixel :: proc(facing: Dir) -> [2]f32 {
	switch facing {
	case .Down:
		return {12, 9}
	case .Up:
		return {2, 8}
	case .Left:
		return {1, 8}
	case .Right:
		return {13, 8}
	}
	return {12, 9}
}

@(private)
draw_lantern :: proc(x, y, s, alpha: f32) {
	rl.DrawRectangleRec({x + s*0.5, y - s, s, s}, ui.with_alpha({60, 46, 30, 255}, alpha))
	rl.DrawRectangleRec({x, y, 2*s, 3*s}, ui.with_alpha({120, 84, 40, 255}, alpha))
	rl.DrawRectangleRec({x + s*0.5, y + s*0.5, s, 2*s}, ui.with_alpha({255, 226, 140, 255}, alpha))
}

@(private)
lantern_pos :: proc(v: ^View) -> [2]f32 {
	s := v.layout.scale
	pos := screen_of(v, body_pos(v.player))
	l := lantern_pixel(v.facing)
	return {pos.x + (l.x+1)*s, pos.y + v.layout.tile - 17*s + (l.y+1.5)*s}
}

@(private)
draw_sigil_glows :: proc(v: ^View, p: ^Puzzle, params: Draw_Params) {
	b := &p.board
	T := v.layout.tile
	time := params.time
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()
	for cell in 0..<b.width*b.height {
		if b.tiles[cell] != .Sigil {
			continue
		}
		xy := cell_xy(b, cell)
		k := reveal_at(params, xy.x, xy.y, b.width, b.height)
		if k <= 0 {
			continue
		}
		c := cell_center(v, cell_vec(b, cell))
		fill := v.sigil_fill[cell]
		pulse := tween.pulse01(time + f32(cell)*0.37, 2.4)
		idle := rl.Color{90, 110, 255, u8((70 + 60*pulse) * (1-fill) * k)}
		gold := rl.Color{255, 196, 90, u8(190 * fill * k)}
		soft_glow(c, T*(0.62 + 0.08*pulse), idle)
		soft_glow(c, T*0.95, gold)
		ring := ui.mix_color({120, 130, 255, 255}, {255, 210, 120, 255}, fill)
		ring.a = u8((60 + 70*pulse) * k)
		rl.DrawRing(c, T*0.33, T*0.33 + v.layout.scale, 0, 360, 28, ring)
		// Six motes orbit an empty sigil; they speed up as it lights.
		n := 6
		radius := T * 0.36
		spin := time * (0.8 + 2*fill)
		for i in 0..<n {
			a := spin + f32(i)*2*math.PI/f32(n)
			q := c + {math.cos(a)*radius, math.sin(a)*radius*0.7}
			color := ui.mix_color({140, 160, 255, 255}, {255, 220, 140, 255}, fill)
			color.a = u8(f32(150 + 80*pulse) * k)
			sz := v.layout.scale * 1.5
			rl.DrawRectangleRec({q.x - sz*0.5, q.y - sz*0.5, sz, sz}, color)
		}
		if params.celebrate >= 0 {
			// Light shaft rising from each sigil.
			h := T * 3 * clamp(params.celebrate*2, 0, 1)
			a := u8(120 * clamp(1.4-params.celebrate*0.6, 0, 1))
			rl.DrawRectangleGradientV(i32(c.x - T*0.3), i32(c.y - h), i32(T*0.6), i32(h),
				{255, 220, 140, 0}, {255, 220, 140, a})
		}
	}
}

// Radial falloff without the banding of stacked discs; meant for additive
// blending, where a transparent rim adds nothing.
@(private)
soft_glow :: proc(center: [2]f32, radius: f32, color: rl.Color) {
	if radius <= 0 || color.a == 0 {
		return
	}
	outer := rl.Color{color.r, color.g, color.b, 0}
	rl.DrawCircleGradient(center, radius, color, outer)
}

@(private)
draw_rings :: proc(v: ^View) {
	for i in 0..<v.ring_count {
		r := v.rings[i]
		gfx.draw_shockwave(r.center, r.t/r.duration, r.radius, r.color)
	}
}

@(private)
draw_lights :: proc(v: ^View, p: ^Puzzle, params: Draw_Params) {
	b := &p.board
	T := v.layout.tile
	time := params.time
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()
	if params.reveal >= 0.85 {
		// The acolyte's lantern.
		c := lantern_pos(v)
		flicker := 0.9 + 0.1*math.sin(time*11) + 0.05*math.sin(time*23)
		soft_glow(c, T*2.6*flicker, {255, 170, 90, 58})
		soft_glow(c, T*0.5, {255, 220, 150, 90})
	}
	for i in 0..<b.plate_count {
		cell := int(b.plates[i])
		if occupied(&p.state, cell) {
			soft_glow(cell_center(v, cell_vec(b, cell)), T*0.8, {90, 255, 200, 34})
		}
	}
	for i in 0..<v.torch_count {
		xy := cell_xy(b, v.torches[i])
		pos := screen_of(v, {f32(xy.x), f32(xy.y)})
		c := pos + {T*0.5, T - f32(WALL_FRONT_PX)*v.layout.scale - 3*v.layout.scale}
		flicker := 0.85 + 0.1*math.sin(time*13+f32(i)) + 0.05*math.sin(time*29+f32(i)*2)
		soft_glow(c, T*1.7*flicker, {255, 140, 60, 70})
	}
}

// ---------------------------------------------------------------------------
// HUD

Hud_Info :: struct {
	level_index: int,
	level_count: int,
	level_name:  string,
	moves:       int,
	par:         int,
	torch:       int,
	torch_max:   int,
	plates:      int,
	plates_down: int,
	hints:       int,
	challenge:   bool,
}

draw_hud :: proc(v: ^View, theme: ^ui.Theme, canvas: rl.Rectangle, info: Hud_Info, time: f32) {
	p := theme.palette
	// Top band.
	rl.DrawRectangleGradientV(0, 0, i32(canvas.width), 46, {8, 8, 14, 230}, {8, 8, 14, 0})
	ui.draw_text(theme, fmt.tprintf("Cripta %d di %d", info.level_index+1, info.level_count), {18, 6}, .Small, p.text_dim)
	ui.draw_text(theme, info.level_name, {18, 20}, .Large, p.text)

	// Moves, par and the stars still within reach.
	right := canvas.width - 18
	moves_text := fmt.tprintf("Mosse %d", info.moves)
	par_text := fmt.tprintf("Par %d", info.par)
	mw := ui.measure(theme, moves_text, .Large).x
	ui.draw_text(theme, moves_text, {right - mw, 16}, .Large, p.text)
	pw := ui.measure(theme, par_text, .Small).x
	ui.draw_text(theme, par_text, {right - mw - pw - 18, 25}, .Small, p.text_dim)
	reach := level_stars(info.moves, info.par, info.hints)
	for i in 0..<3 {
		filled := u8(i) < reach
		c := [2]f32{right - mw - pw - 92 + f32(i)*22, 32}
		ui.draw_star(c + {1, 2}, 9, {0, 0, 0, 150})
		ui.draw_star(c, 9, p.focus if filled else rl.Color{70, 66, 80, 255})
	}
	if info.plates > 0 {
		label := fmt.tprintf("Piastre %d/%d", info.plates_down, info.plates)
		color := p.success if info.plates_down == info.plates else p.text_dim
		lw := ui.measure(theme, label, .Small).x
		ui.draw_text(theme, label, {right - lw, 44}, .Small, color)
	}

	if info.torch_max > 0 {
		draw_torch_bar(theme, canvas, info, time)
	}

	if v.message_time > 0 {
		a := clamp(v.message_time*2, 0, 1)
		ui.draw_text_centered(theme, v.message, {canvas.width*0.5, 64}, .Body, ui.with_alpha(p.warning, a))
	}

	help := "Frecce/WASD muovi   Z annulla   Y ripeti   R ricomincia   H aiuto   Esc pausa"
	if info.challenge {
		help = "Frecce/WASD muovi   Z annulla (la torcia non torna)   R ricomincia   Esc pausa"
	}
	ui.draw_text_centered(theme, help, {canvas.width*0.5, canvas.height - 13}, .Small, ui.with_alpha(p.text_dim, 0.85))
}

@(private)
draw_torch_bar :: proc(theme: ^ui.Theme, canvas: rl.Rectangle, info: Hud_Info, time: f32) {
	p := theme.palette
	w := f32(220)
	bar := rl.Rectangle{canvas.width*0.5 - w*0.5, 18, w, 12}
	frac := f32(info.torch) / f32(max(info.torch_max, 1))
	low := frac < 0.2
	rl.DrawRectangleRounded({bar.x - 2, bar.y - 2, bar.width + 4, bar.height + 4}, 0.5, 6, {0, 0, 0, 170})
	fill := rl.Color{255, 170, 70, 255}
	if low {
		fill = ui.mix_color({255, 90, 60, 255}, {255, 200, 120, 255}, tween.pulse01(time, 0.6))
	}
	rl.DrawRectangleRounded({bar.x, bar.y, bar.width * frac, bar.height}, 0.5, 6, fill)
	label := fmt.tprintf("Torcia %d", info.torch)
	ui.draw_text_centered(theme, label, {canvas.width*0.5, 8}, .Small, p.warning if low else p.text_dim)
}

// Arrow over the hero pointing the suggested way.
draw_hint :: proc(v: ^View, time: f32) {
	if v.hint_time <= 0 {
		return
	}
	T := v.layout.tile
	c := cell_center(v, body_pos(v.player))
	d := dir_delta(v.hint_dir)
	dv := [2]f32{f32(d.x), f32(d.y)}
	bounce := 0.55 + 0.12*tween.pulse01(time, 0.5)
	tip := c + dv*T*(bounce+0.35)
	base := c + dv*T*bounce
	side := [2]f32{-dv.y, dv.x} * T * 0.22
	a := u8(255 * clamp(v.hint_time*2, 0, 1))
	color := rl.Color{140, 255, 210, a}
	rl.DrawTriangle(tip, base + side, base - side, color)
	rl.DrawTriangle(tip, base - side, base + side, color)
}

// Name card shown while a level assembles.
draw_title_card :: proc(theme: ^ui.Theme, canvas: rl.Rectangle, index, count: int, name: string, k: f32) {
	if k <= 0 {
		return
	}
	p := theme.palette
	a := clamp(k, 0, 1)
	cy := canvas.height * 0.5
	rl.DrawRectangleGradientH(0, i32(cy - 46), i32(canvas.width*0.5), 92, {4, 3, 8, 0}, {4, 3, 8, u8(225*a)})
	rl.DrawRectangleGradientH(i32(canvas.width*0.5), i32(cy - 46), i32(canvas.width*0.5), 92, {4, 3, 8, u8(225*a)}, {4, 3, 8, 0})
	rise := (1 - a) * 8
	ui.draw_text_centered(theme, fmt.tprintf("Cripta %d di %d", index+1, count), {canvas.width*0.5, cy - 20 + rise}, .Body, ui.with_alpha(p.focus, a))
	ui.draw_text_centered(theme, name, {canvas.width*0.5, cy + 12 + rise}, .Title, ui.with_alpha(p.text, a))
}

// Banner and stars once a level is solved.
draw_clear_card :: proc(theme: ^ui.Theme, canvas: rl.Rectangle, res: Level_Result, t: f32, last: bool) {
	p := theme.palette
	a := clamp(t*3, 0, 1)
	cy := canvas.height * 0.5
	slide := (1 - tween.ease(.Out_Back, clamp(t*2.5, 0, 1))) * 30
	rl.DrawRectangleGradientH(0, i32(cy - 62), i32(canvas.width*0.5), 124, {0, 0, 0, 0}, {6, 4, 10, u8(190*a)})
	rl.DrawRectangleGradientH(i32(canvas.width*0.5), i32(cy - 62), i32(canvas.width*0.5), 124, {6, 4, 10, u8(190*a)}, {0, 0, 0, 0})
	title := "La cripta si apre!" if last else "Sigilli risvegliati!"
	ui.draw_text_centered(theme, title, {canvas.width*0.5, cy - 32 + slide}, .Title, ui.with_alpha(p.focus, a))
	for i in 0..<3 {
		appear := clamp((t - 0.25 - f32(i)*0.15) * 4, 0, 1)
		if appear <= 0 {
			continue
		}
		filled := u8(i) < res.stars
		c := [2]f32{canvas.width*0.5 + f32(i-1)*44, cy + 14}
		r := 15 * tween.ease(.Out_Back, appear)
		ui.draw_star(c + {2, 3}, r, {0, 0, 0, 150})
		ui.draw_star(c, r, p.focus if filled else rl.Color{70, 66, 80, 255})
	}
	stats := fmt.tprintf("Mosse %d   Par %d", res.moves, res.par)
	ui.draw_text_centered(theme, stats, {canvas.width*0.5, cy + 44}, .Body, ui.with_alpha(p.text_dim, a))
}

// Darkness closes in as the challenge torch burns down.
vignette_strength :: proc(torch, torch_max: int) -> f32 {
	strength := f32(0.55)
	if torch_max > 0 {
		strength += (1 - f32(torch)/f32(torch_max)) * 0.35
	}
	return strength
}

draw_backdrop :: proc(canvas: rl.Rectangle, time: f32) {
	gfx.draw_vertical_gradient(canvas, {16, 14, 24, 255}, {8, 7, 12, 255})
	// A vast sigil carved into the dark, turning very slowly behind the crypt.
	c := [2]f32{canvas.width*0.5, canvas.height*0.5 + 10}
	for ring in 0..<2 {
		radius := f32(330 - ring*70)
		spin := time * (0.03 if ring == 0 else -0.045)
		rl.DrawRing(c, radius - 2, radius, 0, 360, 96, {70, 60, 120, 34})
		marks := 36 - ring*12
		for i in 0..<marks {
			a := spin + f32(i)*2*math.PI/f32(marks)
			q := c + {math.cos(a), math.sin(a)} * (radius + 9)
			size := f32(4 if i%3 == 0 else 2)
			rl.DrawRectangleRec({q.x - size*0.5, q.y - size*0.5, size, size}, {96, 84, 160, 40})
		}
	}
	// Slow drifting fog bands.
	for i in 0..<3 {
		y := canvas.height * (0.25 + 0.25*f32(i)) + math.sin(time*0.2+f32(i)*2)*20
		rl.DrawRectangleGradientV(0, i32(y - 60), i32(canvas.width), 60, {40, 34, 60, 0}, {40, 34, 60, 26})
		rl.DrawRectangleGradientV(0, i32(y), i32(canvas.width), 60, {40, 34, 60, 26}, {40, 34, 60, 0})
	}
}
