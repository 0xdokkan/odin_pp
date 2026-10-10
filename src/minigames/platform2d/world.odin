// Torre di Cenere: a side-scrolling platformer assembled from hand-authored
// chunks. This file is the pure simulation (no raylib), stepped at a fixed
// rate so rounds replay exactly from a seed and an input log.
package platform2d

import "core:math"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"

Vec2 :: [2]f32
Rect :: physics.Rect

TILE :: f32(16)
STEP_HZ :: 120
SIM_DT :: f32(1.0 / STEP_HZ)

MAX_COLS :: 640
MAX_SEQUENCE :: 16
MAX_EMBERS :: 512
MAX_ENEMIES :: 96
MAX_PROJECTILES :: 24
MAX_CHECKPOINTS :: 12
MAX_CRUMBLES :: 160
MAX_EVENTS :: 48

PLAYER_SIZE :: Vec2{10, 14}
EMBER_POINTS :: 10
STOMP_POINTS :: 25
FINISH_POINTS :: 500
LIFE_POINTS :: 100

// Crumbling blocks hold this long once stepped on, then return after a while.
CRUMBLE_DELAY :: f32(0.45)
CRUMBLE_RESPAWN :: f32(3)
INVULNERABLE_TIME :: f32(1.3)
DYING_TIME :: f32(0.85)
EXIT_TIME :: f32(1.1)

Tile_Kind :: enum u8 {
	Empty,
	Stone,
	Ledge,
	Spike,
	Lava,
	Crumble,
}

Player_Input :: struct {
	move:         f32, // -1..1
	jump_pressed: bool,
	jump_held:    bool,
	dash_pressed: bool,
	down_pressed: bool,
}

Player :: struct {
	ctrl:          physics.Platformer,
	on_one_way:    bool,
	air_dash_used: bool,
	drop_timer:    f32,
	// Knockback: input is ignored until it runs out.
	stun:          f32,
	invulnerable:  f32,
	prev_bottom:   f32,
}

Phase :: enum u8 {
	Alive,
	Dying,
	Exiting,
}

Enemy_Kind :: enum u8 {
	Ghoul,
	Bat,
	Totem,
}

Enemy :: struct {
	kind:   Enemy_Kind,
	alive:  bool,
	body:   physics.Body2,
	home:   Vec2,
	dir:    f32,
	// Difficulty multiplier on movement and fire rate.
	speed:  f32,
	timer:  f32,
	phase:  f32,
	// Totem wind-up before a shot; the renderer shows it as glowing eyes.
	charge: f32,
	aggro:  bool,
}

Projectile :: struct {
	active:   bool,
	position: Vec2, // centre
	velocity: Vec2,
	life:     f32,
}

Ember :: struct {
	position:  Vec2, // centre
	collected: bool,
}

Checkpoint :: struct {
	feet: Vec2,
	lit:  bool,
}

Crumble_State :: enum u8 {
	Intact,
	Shaking,
	Gone,
}

Crumble :: struct {
	x, y:  int,
	state: Crumble_State,
	timer: f32,
}

Event_Kind :: enum u8 {
	Jump,
	Air_Jump,
	Wall_Jump,
	Dash,
	Land,
	Ember,
	Stomp,
	Hurt,
	Death,
	Respawn,
	Checkpoint,
	Charge,
	Shoot,
	Fireball_Pop,
	Enemy_Burn,
	Crumble_Shake,
	Crumble_Break,
	Exit,
	Time_Up,
	Game_Over,
}

// What happened during one step, for sound, particles and popups.
Event :: struct {
	kind:     Event_Kind,
	position: Vec2,
	value:    f32,
	count:    int,
}

World :: struct {
	config:           host.Minigame_Config,
	params:           physics.Platformer_Params,
	chunks:           [MAX_SEQUENCE]Chunk_Def,
	chunk_start:      [MAX_SEQUENCE]int,
	chunk_count:      int,
	cols:             int,
	tiles:            [MAX_COLS * LEVEL_ROWS]Tile_Kind,
	collision:        physics.Tile_Map,
	player:           Player,
	phase:            Phase,
	phase_timer:      f32,
	timed_out:        bool,
	spawn:            Vec2, // feet position of the active respawn point
	lives:            int,
	max_lives:        int,
	hits:             int, // hearts lost, from any source
	falls:            int, // hazard deaths among them
	embers:           [MAX_EMBERS]Ember,
	ember_count:      int,
	embers_collected: int,
	enemies:          [MAX_ENEMIES]Enemy,
	enemy_count:      int,
	stomps:           int,
	stomp_points:     i64,
	combo:            int,
	projectiles:      [MAX_PROJECTILES]Projectile,
	checkpoints:      [MAX_CHECKPOINTS]Checkpoint,
	checkpoint_count: int,
	crumbles:         [MAX_CRUMBLES]Crumble,
	crumble_count:    int,
	has_spawn:        bool,
	has_exit:         bool,
	exit_rect:        Rect,
	time:             f32,
	time_limit:       f32, // 0 = untimed
	par_time:         f32,
	finish_bonus:     i64,
	status:           host.Round_Status,
	steps:            u64,
	events:           [MAX_EVENTS]Event,
	event_count:      int,
	dropped_events:   int,
}

// ---------------------------------------------------------------------------
// Tuning

player_params :: proc() -> physics.Platformer_Params {
	p := physics.DEFAULT_PLATFORMER
	p.max_speed = 150
	p.jump_speed = 335
	p.coyote_time = 0.11
	p.jump_buffer_time = 0.13
	p.air_jumps = 1
	p.dash_cooldown = 0.35
	// The world grants air dashes itself, because stomps refill them too.
	p.air_dashes = 0
	return p
}

middle_chunk_count :: proc(config: host.Minigame_Config) -> int {
	d := clamp(config.difficulty, 0, 2)
	if config.challenge {
		return 4 + d
	}
	return 7 + 2*d
}

lives_for :: proc(config: host.Minigame_Config) -> int {
	switch clamp(config.difficulty, 0, 2) {
	case 0:
		return 5
	case 1:
		return 4
	}
	return 3
}

// Challenges run one notch easier than their difficulty, as they are a single
// attempt inside a longer run.
@(private)
effective_level :: proc(config: host.Minigame_Config) -> int {
	level := clamp(config.difficulty, 0, 2)
	if config.challenge {
		level -= 1
	}
	return level
}

slot_tier :: proc(config: host.Minigame_Config, slot, count: int) -> int {
	t := f32(slot) / f32(max(count-1, 1))
	switch effective_level(config) {
	case -1:
		return 0 if t < 0.6 else 1
	case 0:
		return 0 if t < 0.5 else 1
	case 1:
		if t < 0.25 {
			return 0
		}
		return 1 if t < 0.75 else 2
	}
	return 1 if t < 0.4 else 2
}

@(private)
enemy_keep_chance :: proc(config: host.Minigame_Config) -> f32 {
	switch effective_level(config) {
	case -1:
		return 0.45
	case 0:
		return 0.55
	case 1:
		return 0.8
	}
	return 1
}

@(private)
enemy_speed_scale :: proc(config: host.Minigame_Config) -> f32 {
	switch effective_level(config) {
	case -1, 0:
		return 0.8
	case 1:
		return 1
	}
	return 1.25
}

// ---------------------------------------------------------------------------
// Generation

// Picks the chunk order for a seed: start, a difficulty ramp of middle chunks
// drawn from shuffled per-tier bags, end.
generate_sequence :: proc(config: host.Minigame_Config) -> (sequence: [MAX_SEQUENCE]int, count: int) {
	r := rng.create(rng.derive(config.seed, 11))
	bags: [3][len(CHUNKS)]int
	sizes: [3]int
	for def, i in CHUNKS {
		if def.role == .Middle {
			tier := clamp(def.tier, 0, 2)
			bags[tier][sizes[tier]] = i
			sizes[tier] += 1
		}
	}
	for tier in 0..<3 {
		rng.shuffle(&r, bags[tier][:sizes[tier]])
	}
	cursor: [3]int
	sequence[0] = chunk_index("soglia")
	count = 1
	middle := min(middle_chunk_count(config), MAX_SEQUENCE-2)
	for slot in 0..<middle {
		tier := slot_tier(config, slot, middle)
		size := sizes[tier]
		pick := bags[tier][cursor[tier] % size]
		cursor[tier] += 1
		// Never the same chunk twice in a row when the bag has a choice.
		if pick == sequence[count-1] && size > 1 {
			pick = bags[tier][cursor[tier] % size]
			cursor[tier] += 1
		}
		sequence[count] = pick
		count += 1
	}
	sequence[count] = chunk_index("altare")
	count += 1
	return
}

world_reset :: proc(w: ^World, config: host.Minigame_Config) {
	sequence, count := generate_sequence(config)
	defs: [MAX_SEQUENCE]Chunk_Def
	for i in 0..<count {
		defs[i] = CHUNKS[sequence[i]]
	}
	world_build(w, config, defs[:count])
}

// Builds a level from an explicit chunk order (tests drive single chunks).
world_build :: proc(w: ^World, config: host.Minigame_Config, sequence: []Chunk_Def) {
	physics.tile_map_destroy(&w.collision)
	w^ = {}
	w.config = config
	w.params = player_params()
	if config.difficulty <= 0 {
		w.params.coyote_time = 0.13
	}
	gen := rng.create(rng.derive(config.seed, 7))
	keep := enemy_keep_chance(config)
	speed := enemy_speed_scale(config)
	every := 2 if config.difficulty <= 0 || config.challenge else 3

	x0 := 0
	middle_index := 0
	for def, k in sequence {
		if k >= MAX_SEQUENCE {
			break
		}
		width := chunk_width(def)
		if x0+width > MAX_COLS {
			break
		}
		w.chunks[k] = def
		w.chunk_start[k] = x0
		w.chunk_count = k + 1
		w.par_time += def.par
		if def.role == .Middle {
			if middle_index > 0 && middle_index%every == 0 && w.checkpoint_count < MAX_CHECKPOINTS {
				w.checkpoints[w.checkpoint_count] = Checkpoint{feet = {(f32(x0) + 1.5) * TILE, FLOOR_ROW * TILE}}
				w.checkpoint_count += 1
			}
			middle_index += 1
		}
		for y in 0..<LEVEL_ROWS {
			for x in 0..<width {
				cx := x0 + x
				cell := cell_box(cx, y)
				kind := Tile_Kind.Empty
				switch chunk_char(def, x, y) {
				case '#':
					kind = .Stone
				case '=':
					kind = .Ledge
				case '^':
					kind = .Spike
				case '~':
					kind = .Lava
				case '%':
					kind = .Crumble
					if w.crumble_count < MAX_CRUMBLES {
						w.crumbles[w.crumble_count] = Crumble{x = cx, y = y}
						w.crumble_count += 1
					}
				case 'o':
					if w.ember_count < MAX_EMBERS {
						w.embers[w.ember_count] = Ember{position = physics.rect_center(cell)}
						w.ember_count += 1
					}
				case 'g':
					if rng.chance(&gen, keep) {
						add_enemy(w, .Ghoul, cell, speed, &gen)
					}
				case 'b':
					if rng.chance(&gen, keep) {
						add_enemy(w, .Bat, cell, speed, &gen)
					}
				case 't':
					if rng.chance(&gen, keep) {
						add_enemy(w, .Totem, cell, speed, &gen)
					}
				case 'S':
					w.spawn = {cell.x + TILE*0.5, cell.y + TILE}
					w.has_spawn = true
				case 'E':
					w.exit_rect = Rect{cell.x, cell.y + TILE - 48, 32, 48}
					w.has_exit = true
				}
				w.tiles[y*MAX_COLS+cx] = kind
			}
		}
		x0 += width
	}
	w.cols = max(x0, 1)
	w.collision, _ = physics.tile_map_create(w.cols, LEVEL_ROWS, TILE, .Solid)
	for y in 0..<LEVEL_ROWS {
		for x in 0..<w.cols {
			physics.set_tile(&w.collision, x, y, shape_of(w.tiles[y*MAX_COLS+x]))
		}
	}
	w.max_lives = lives_for(config)
	w.lives = w.max_lives
	if config.challenge {
		slack := f32(1.7) if config.difficulty <= 0 else f32(1.45)
		w.time_limit = math.ceil(w.par_time*slack + 10)
	}
	place_player(w, w.spawn)
	w.player.invulnerable = 0
}

world_destroy :: proc(w: ^World) {
	physics.tile_map_destroy(&w.collision)
}

@(private)
add_enemy :: proc(w: ^World, kind: Enemy_Kind, cell: Rect, speed: f32, gen: ^rng.Rng) {
	if w.enemy_count >= MAX_ENEMIES {
		return
	}
	e := Enemy{kind = kind, alive = true, dir = -1, speed = speed}
	switch kind {
	case .Ghoul:
		e.body = physics.Body2{position = {cell.x + 2, cell.y + TILE - 12}, size = {12, 12}}
		e.dir = -1 if rng.chance(gen, 0.5) else 1
	case .Bat:
		e.body = physics.Body2{position = {cell.x + 2, cell.y + 3}, size = {12, 10}}
		e.phase = rng.float_range(gen, 0, 6.28)
	case .Totem:
		e.body = physics.Body2{position = {cell.x + 1, cell.y + TILE - 14}, size = {14, 14}}
		e.timer = rng.float_range(gen, 0.6, 1.8)
	}
	e.home = physics.body2_center(e.body)
	w.enemies[w.enemy_count] = e
	w.enemy_count += 1
}

shape_of :: proc(kind: Tile_Kind) -> physics.Tile_Shape {
	#partial switch kind {
	case .Stone, .Crumble:
		return .Solid
	case .Ledge:
		return .One_Way
	}
	return .Empty
}

// ---------------------------------------------------------------------------
// Queries shared with the solver and the renderer

cell_box :: proc "contextless" (x, y: int) -> Rect {
	return Rect{f32(x) * TILE, f32(y) * TILE, TILE, TILE}
}

tile_kind :: proc(w: ^World, x, y: int) -> Tile_Kind {
	if x < 0 || x >= w.cols || y < 0 || y >= LEVEL_ROWS {
		return .Stone
	}
	return w.tiles[y*MAX_COLS+x]
}

// Spikes point away from the surface they grow on.
spike_points_up :: proc(w: ^World, x, y: int) -> bool {
	below := tile_kind(w, x, y+1)
	if below == .Stone || below == .Crumble {
		return true
	}
	above := tile_kind(w, x, y-1)
	return !(above == .Stone || above == .Crumble)
}

hazard_box :: proc(w: ^World, x, y: int) -> (Rect, bool) {
	#partial switch tile_kind(w, x, y) {
	case .Spike:
		if spike_points_up(w, x, y) {
			return Rect{f32(x)*TILE + 3, f32(y)*TILE + 9, 10, 7}, true
		}
		return Rect{f32(x)*TILE + 3, f32(y) * TILE, 10, 7}, true
	case .Lava:
		return Rect{f32(x) * TILE, f32(y)*TILE + 6, TILE, 10}, true
	}
	return {}, false
}

hazard_hit :: proc(w: ^World, r: Rect) -> bool {
	x0 := int(math.floor(r.x / TILE))
	x1 := int(math.floor((r.x + r.width) / TILE))
	y0 := int(math.floor(r.y / TILE))
	y1 := int(math.floor((r.y + r.height) / TILE))
	for y in y0..=y1 {
		for x in x0..=x1 {
			if box, ok := hazard_box(w, x, y); ok && physics.rect_overlaps(box, r) {
				return true
			}
		}
	}
	return false
}

player_rect :: proc "contextless" (p: Player) -> Rect {
	return physics.body2_rect(p.ctrl.body)
}

player_center :: proc "contextless" (p: Player) -> Vec2 {
	return physics.body2_center(p.ctrl.body)
}

player_feet :: proc "contextless" (p: Player) -> Vec2 {
	b := p.ctrl.body
	return {b.position.x + b.size.x*0.5, b.position.y + b.size.y}
}

level_size :: proc(w: ^World) -> Vec2 {
	return {f32(w.cols) * TILE, LEVEL_ROWS * TILE}
}

ember_box :: proc "contextless" (e: Ember) -> Rect {
	return physics.rect_from_center(e.position, {12, 12})
}

// ---------------------------------------------------------------------------
// Player movement, shared verbatim by the world and the solver

player_move :: proc(p: ^Player, params: physics.Platformer_Params, input: Player_Input, m: ^physics.Tile_Map,
	dt: f32) -> (physics.Move_Result2, physics.Platformer_Events) {
	cmd := input
	if p.stun > 0 {
		p.stun = max(p.stun-dt, 0)
		cmd = Player_Input{jump_held = input.jump_held}
	}
	// Ground and walls give the air dash back.
	if p.ctrl.grounded || p.ctrl.wall_side != 0 {
		p.air_dash_used = false
	}
	p.drop_timer = max(p.drop_timer-dt, 0)
	if cmd.down_pressed && p.ctrl.grounded && p.on_one_way {
		p.drop_timer = 0.12
		cmd.jump_pressed = false
	}
	pin := physics.Platformer_Input{
		move         = cmd.move,
		jump_pressed = cmd.jump_pressed,
		jump_held    = cmd.jump_held,
		drop_through = p.drop_timer > 0,
		dash_pressed = cmd.dash_pressed && (p.ctrl.grounded || !p.air_dash_used),
	}
	p.prev_bottom = p.ctrl.body.position.y + p.ctrl.body.size.y
	result, events := physics.platformer_step(&p.ctrl, params, pin, m, dt)
	p.on_one_way = result.on_one_way && p.ctrl.grounded
	if events.dashed && !p.ctrl.grounded {
		p.air_dash_used = true
	}
	return result, events
}

@(private)
place_player :: proc(w: ^World, feet: Vec2) {
	w.player = Player{}
	w.player.ctrl = physics.platformer_create(feet - {PLAYER_SIZE.x * 0.5, PLAYER_SIZE.y}, PLAYER_SIZE)
	w.player.ctrl.grounded = true
	w.player.invulnerable = INVULNERABLE_TIME
}

// ---------------------------------------------------------------------------
// Step

@(private)
emit :: proc(w: ^World, kind: Event_Kind, position: Vec2, value: f32 = 0, count := 0) {
	if w.event_count >= MAX_EVENTS {
		w.dropped_events += 1
		return
	}
	w.events[w.event_count] = Event{kind = kind, position = position, value = value, count = count}
	w.event_count += 1
}

world_step :: proc(w: ^World, input: Player_Input, dt: f32) -> host.Round_Status {
	w.event_count = 0
	if w.status != .Playing {
		return w.status
	}
	w.steps += 1
	update_crumbles(w, dt)
	switch w.phase {
	case .Alive:
		w.time += dt
		update_player(w, input, dt)
		if w.phase == .Alive && w.time_limit > 0 && w.time >= w.time_limit {
			w.timed_out = true
			emit(w, .Time_Up, player_center(w.player))
			start_dying(w)
		}
	case .Dying:
		w.time += dt
		w.phase_timer -= dt
		if w.phase_timer <= 0 {
			if w.lives <= 0 || w.timed_out {
				w.status = .Lost
				emit(w, .Game_Over, player_center(w.player))
			} else {
				respawn(w)
			}
		}
	case .Exiting:
		w.phase_timer -= dt
		// The portal draws the player into its centre.
		target := physics.rect_center(w.exit_rect)
		c := player_center(w.player)
		k := 1 - math.exp(-8*dt)
		w.player.ctrl.body.position += (target - c) * k
		if w.phase_timer <= 0 {
			w.status = .Won
		}
	}
	update_enemies(w, dt)
	update_projectiles(w, dt)
	return w.status
}

@(private)
update_player :: proc(w: ^World, input: Player_Input, dt: f32) {
	p := &w.player
	p.invulnerable = max(p.invulnerable-dt, 0)
	_, ev := player_move(p, w.params, input, &w.collision, dt)
	feet := player_feet(p^)
	if ev.jumped {
		emit(w, .Jump, feet)
	}
	if ev.air_jumped {
		emit(w, .Air_Jump, feet)
	}
	if ev.wall_jumped {
		emit(w, .Wall_Jump, player_center(p^), -p.ctrl.facing)
	}
	if ev.dashed {
		emit(w, .Dash, player_center(p^), p.ctrl.facing)
	}
	if ev.landed {
		emit(w, .Land, feet, ev.landing_speed)
		w.combo = 0
	}
	if p.ctrl.grounded {
		touch_crumbles(w)
	}

	rect := player_rect(p^)
	if hazard_hit(w, physics.rect_inset(rect, 1)) || rect.y > LEVEL_ROWS*TILE {
		w.falls += 1
		lose_life(w, player_center(p^))
		start_dying(w)
		return
	}
	for &e in w.embers[:w.ember_count] {
		if !e.collected && physics.rect_overlaps(rect, ember_box(e)) {
			e.collected = true
			w.embers_collected += 1
			emit(w, .Ember, e.position, count = w.embers_collected)
		}
	}
	for &c, i in w.checkpoints[:w.checkpoint_count] {
		if c.lit {
			continue
		}
		zone := Rect{c.feet.x - 12, c.feet.y - 40, 24, 40}
		if physics.rect_overlaps(rect, zone) {
			c.lit = true
			w.spawn = c.feet
			emit(w, .Checkpoint, c.feet, count = i)
		}
	}
	for &e in w.enemies[:w.enemy_count] {
		if !e.alive || w.phase != .Alive {
			continue
		}
		er := physics.rect_inset(physics.body2_rect(e.body), 1)
		if !physics.rect_overlaps(rect, er) {
			continue
		}
		if p.ctrl.body.velocity.y >= 0 && p.prev_bottom <= er.y+5 {
			stomp(w, &e, input.jump_held)
		} else if p.invulnerable <= 0 {
			hurt(w, physics.body2_center(e.body))
		}
	}
	for &b in w.projectiles {
		if b.active && w.phase == .Alive && physics.circle_overlaps_rect(b.position, 4, rect) {
			b.active = false
			emit(w, .Fireball_Pop, b.position)
			if p.invulnerable <= 0 {
				hurt(w, b.position - b.velocity)
			}
		}
	}
	if w.phase == .Alive && w.has_exit && physics.rect_overlaps(rect, physics.rect_inset(w.exit_rect, 6)) {
		w.phase = .Exiting
		w.phase_timer = EXIT_TIME
		time_bonus := max(i64(0), i64(math.round((w.par_time - w.time) * 10)))
		w.finish_bonus = FINISH_POINTS + time_bonus + i64(w.lives)*LIFE_POINTS
		p.ctrl.body.velocity = {}
		emit(w, .Exit, physics.rect_center(w.exit_rect))
	}
}

@(private)
stomp :: proc(w: ^World, e: ^Enemy, jump_held: bool) {
	p := &w.player
	e.alive = false
	w.stomps += 1
	w.combo += 1
	points := i64(STOMP_POINTS * min(w.combo, 8))
	w.stomp_points += points
	emit(w, .Stomp, physics.body2_center(e.body), f32(points), w.combo)
	// Holding jump turns the bounce into a full leap; the cut still applies
	// when it is released, exactly like a normal jump.
	p.ctrl.body.velocity.y = -w.params.jump_speed if jump_held else -230
	p.ctrl.jump_cut_used = !jump_held
	p.ctrl.grounded = false
	p.ctrl.coyote = 0
	p.ctrl.dash_remaining = 0
	p.ctrl.air_jumps_left = w.params.air_jumps
	p.air_dash_used = false
}

@(private)
lose_life :: proc(w: ^World, at: Vec2) {
	w.lives = max(w.lives-1, 0)
	w.hits += 1
	w.combo = 0
	emit(w, .Hurt, at, f32(w.lives))
}

@(private)
hurt :: proc(w: ^World, source: Vec2) {
	p := &w.player
	c := player_center(p^)
	lose_life(w, c)
	if w.lives <= 0 {
		start_dying(w)
		return
	}
	dir := math.sign(c.x - source.x)
	if dir == 0 {
		dir = -p.ctrl.facing
	}
	p.invulnerable = INVULNERABLE_TIME
	p.stun = 0.22
	p.ctrl.dash_remaining = 0
	p.ctrl.body.velocity = {dir * 170, -230}
	p.ctrl.jump_cut_used = true
	p.ctrl.grounded = false
}

@(private)
start_dying :: proc(w: ^World) {
	w.phase = .Dying
	w.phase_timer = DYING_TIME
	w.player.ctrl.body.velocity = {}
	w.player.ctrl.dash_remaining = 0
	emit(w, .Death, player_center(w.player), f32(w.lives))
}

@(private)
respawn :: proc(w: ^World) {
	place_player(w, w.spawn)
	w.phase = .Alive
	w.combo = 0
	for &b in w.projectiles {
		b.active = false
	}
	// Bridges come back so the route from the checkpoint is whole again.
	for &c in w.crumbles[:w.crumble_count] {
		if c.state != .Intact {
			c.state = .Intact
			physics.set_tile(&w.collision, c.x, c.y, .Solid)
		}
	}
	emit(w, .Respawn, w.spawn)
}

// ---------------------------------------------------------------------------
// Crumbling blocks

@(private)
touch_crumbles :: proc(w: ^World) {
	b := w.player.ctrl.body
	row := int(math.floor((b.position.y + b.size.y + 0.5) / TILE))
	x0 := int(math.floor(b.position.x / TILE))
	x1 := int(math.floor((b.position.x + b.size.x - 0.01) / TILE))
	for &c in w.crumbles[:w.crumble_count] {
		if c.state == .Intact && c.y == row && c.x >= x0 && c.x <= x1 {
			c.state = .Shaking
			c.timer = CRUMBLE_DELAY
			emit(w, .Crumble_Shake, physics.rect_center(cell_box(c.x, c.y)))
		}
	}
}

@(private)
update_crumbles :: proc(w: ^World, dt: f32) {
	for &c in w.crumbles[:w.crumble_count] {
		switch c.state {
		case .Intact:
		case .Shaking:
			c.timer -= dt
			if c.timer <= 0 {
				c.state = .Gone
				c.timer = CRUMBLE_RESPAWN
				physics.set_tile(&w.collision, c.x, c.y, .Empty)
				emit(w, .Crumble_Break, physics.rect_center(cell_box(c.x, c.y)))
			}
		case .Gone:
			c.timer -= dt
			// Never rebuild a block inside the player.
			if c.timer <= 0 && !physics.rect_overlaps(player_rect(w.player), cell_box(c.x, c.y)) {
				c.state = .Intact
				physics.set_tile(&w.collision, c.x, c.y, .Solid)
			}
		}
	}
}

crumble_at :: proc(w: ^World, x, y: int) -> ^Crumble {
	for &c in w.crumbles[:w.crumble_count] {
		if c.x == x && c.y == y {
			return &c
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Enemies and projectiles

@(private)
update_enemies :: proc(w: ^World, dt: f32) {
	pc := player_center(w.player)
	player_active := w.phase == .Alive
	for &e in w.enemies[:w.enemy_count] {
		if !e.alive {
			continue
		}
		switch e.kind {
		case .Ghoul:
			update_ghoul(w, &e, dt)
		case .Bat:
			e.phase += dt
			to_player := pc - e.home
			e.aggro = player_active && physics.length2(to_player) < 120
			target: Vec2
			speed := 40 * e.speed
			if e.aggro {
				target = e.home + physics.clamp_length2(to_player, 96)
				speed = 62 * e.speed
			} else {
				target = e.home + Vec2{math.sin(e.phase*1.1) * 26, math.sin(e.phase*2.2) * 9}
			}
			c := physics.body2_center(e.body)
			step := physics.clamp_length2(target-c, speed*dt)
			e.body.position += step
			if abs(step.x) > 0.01 {
				e.dir = math.sign(step.x)
			}
		case .Totem:
			update_totem(w, &e, pc, player_active, dt)
		}
	}
}

@(private)
update_ghoul :: proc(w: ^World, e: ^Enemy, dt: f32) {
	e.phase += dt
	e.body.velocity.x = e.dir * 30 * e.speed
	e.body.velocity.y = min(e.body.velocity.y+900*dt, 300)
	r := physics.move_body2(&w.collision, &e.body, e.body.velocity*dt)
	if r.hit_left || r.hit_right {
		e.dir = -e.dir
	} else if r.on_ground {
		// Turn back at ledges and before hazards instead of walking into them.
		front := e.body.position.x + (e.body.size.x + 1 if e.dir > 0 else -1)
		feet := e.body.position.y + e.body.size.y
		cx := int(math.floor(front / TILE))
		here := tile_kind(w, cx, int(math.floor((feet - 1) / TILE)))
		below := tile_kind(w, cx, int(math.floor((feet + 1) / TILE)))
		supported := below == .Stone || below == .Ledge || below == .Crumble
		if !supported || here == .Spike || here == .Lava {
			e.dir = -e.dir
		}
	}
	if hazard_hit(w, physics.body2_rect(e.body)) {
		e.alive = false
		emit(w, .Enemy_Burn, physics.body2_center(e.body))
	}
}

@(private)
update_totem :: proc(w: ^World, e: ^Enemy, pc: Vec2, player_active: bool, dt: f32) {
	tc := physics.body2_center(e.body)
	dx := pc.x - tc.x
	in_range := player_active && abs(dx) < 210 && abs(pc.y-tc.y) < 56 &&
		physics.line_of_sight(&w.collision, tc, pc)
	if in_range && abs(dx) > 1 {
		e.dir = math.sign(dx)
	}
	e.aggro = in_range
	if e.charge > 0 {
		e.charge -= dt
		if e.charge <= 0 {
			e.charge = 0
			for &b in w.projectiles {
				if !b.active {
					speed := 115 * e.speed
					b = Projectile{active = true, position = tc + {e.dir * 8, -1}, velocity = {e.dir * speed, 0}, life = 4}
					emit(w, .Shoot, b.position, e.dir)
					break
				}
			}
			e.timer = 2.6 / e.speed
		}
		return
	}
	e.timer = max(e.timer-dt, 0)
	if e.timer <= 0 && in_range {
		e.charge = 0.55
		emit(w, .Charge, tc)
	}
}

@(private)
update_projectiles :: proc(w: ^World, dt: f32) {
	for &b in w.projectiles {
		if !b.active {
			continue
		}
		b.position += b.velocity * dt
		b.life -= dt
		cell := physics.cell_of(&w.collision, b.position)
		if b.life <= 0 || physics.tile_at(&w.collision, cell.x, cell.y) == .Solid {
			b.active = false
			emit(w, .Fireball_Pop, b.position)
		}
	}
}

// ---------------------------------------------------------------------------
// Score

ember_ratio :: proc(w: ^World) -> f32 {
	if w.ember_count == 0 {
		return 1
	}
	return f32(w.embers_collected) / f32(w.ember_count)
}

// 1 star for escaping, 2 with 60% of the embers, 3 with 90% and no wounds.
world_score :: proc(w: ^World) -> (score: i64, stars: u8) {
	score = i64(w.embers_collected)*EMBER_POINTS + w.stomp_points + w.finish_bonus
	if w.status == .Won {
		stars = 1
		ratio := ember_ratio(w)
		if ratio >= 0.6 {
			stars = 2
		}
		if ratio >= 0.9 && w.hits == 0 {
			stars = 3
		}
	}
	return
}

// Index of the chunk the player stands in.
world_area :: proc(w: ^World) -> int {
	column := int(player_center(w.player).x / TILE)
	area := 0
	for k in 0..<w.chunk_count {
		if column >= w.chunk_start[k] {
			area = k
		}
	}
	return area
}

// Progress through the level, 0 at spawn and 1 at the portal.
world_progress :: proc(w: ^World) -> f32 {
	if !w.has_exit {
		return 0
	}
	goal := physics.rect_center(w.exit_rect).x
	return clamp(player_center(w.player).x/max(goal, 1), 0, 1)
}
