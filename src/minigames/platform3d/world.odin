// Guglie Sospese: a third-person platformer over an abyss. This file is the
// pure simulation (no raylib): the World, its fixed step and the score. The
// level itself is built in generate.odin, drawing lives in draw.odin.
package platform3d

import "core:math"
import host "../../engine/host"
import physics "../../engine/physics"
import tween "../../engine/tween"

Vec2 :: [2]f32
Vec3 :: [3]f32

SIM_HZ :: 120
SIM_DT :: f32(1) / SIM_HZ

MAX_PADS :: 96
MAX_PATH :: 64
MAX_MOVERS :: 24
MAX_SHARDS :: 16
MAX_SPIKES :: 12
MAX_SENTINELS :: 8
MAX_BRIDGES :: 12
MAX_FAR :: 18
MAX_BRAZIERS :: 6
MAX_EVENTS :: 24

PLAYER_SIZE :: Vec3{0.6, 1.3, 0.6}

// A running single jump covers about four voxels and the air jump about seven;
// the generator derives every gap from these numbers (see jump_reach).
PLAYER_PARAMS :: physics.Platformer_Params{
	max_speed          = 6.5,
	ground_accel       = 70,
	ground_decel       = 80,
	air_accel          = 40,
	air_decel          = 10,
	gravity            = 32,
	fall_gravity_scale = 1.6,
	max_fall_speed     = 28,
	jump_speed         = 11.5,
	jump_cut           = 0.45,
	coyote_time        = 0.11,
	jump_buffer_time   = 0.13,
	air_jumps          = 1,
	dash_speed         = 15,
	dash_time          = 0.15,
	dash_cooldown      = 0.55,
}

SHARD_RADIUS :: f32(1.05)
SHUTTLE_PAUSE :: f32(0.8)
CRUMBLE_FALL_TIME :: f32(1.4)
CRUMBLE_RESPAWN :: f32(3.2)
DEATH_TIME :: f32(1.1)
RESPAWN_GRACE :: f32(1.6)
STUN_TIME :: f32(0.4)

SHARD_POINTS :: 150
WIN_POINTS :: 500
LIFE_POINTS :: 200
TIME_POINTS :: 10

// Voxel material ids. Ember and Rune are drawn as emissive.
Material :: enum u8 {
	Empty,
	Stone,
	Stone_Dark,
	Stone_Top,
	Moss,
	Plank,
	Crystal,
	Ember,
	Rune,
}

material_glows :: proc "contextless" (m: Material) -> bool {
	return m == .Ember || m == .Rune
}

Pad_Kind :: enum u8 {
	Spawn,
	Island,
	Spire,
	Goal,
	Crumble,
	Shuttle,
}

Link_Kind :: enum u8 {
	None,
	Jump,
	Bridge,
}

// A walkable top: islands, spires and the two moving kinds. Movers keep the
// footprint of their first position; the mover holds the live one.
Pad :: struct {
	lo, hi:  [2]int, // footprint cells (x, z), hi exclusive
	top:     int,    // y of the walking surface
	depth:   int,    // solid layers below the surface
	kind:    Pad_Kind,
	link:    Link_Kind,
	parent:  int,    // pad this one is reached from, -1 for the spawn
	next:    int,    // following pad on the main path, -1 elsewhere
	mover:   int,
	shard:   int,
	branch:  bool,
	hazard:  bool,
	plan:    Hazard_Plan, // built to carry this hazard
	respawn: Vec3,
}

Hazard_Plan :: enum u8 {
	None,
	Spikes,
	Sentinel,
}

Mover_Kind :: enum u8 {
	Shuttle,
	Crumble,
}

Crumble_State :: enum u8 {
	Idle,
	Shaking,
	Falling,
	Gone,
}

// Kinematic box the player collides with besides the voxels.
Mover :: struct {
	kind:        Mover_Kind,
	state:       Crumble_State,
	size:        Vec3,
	a, b:        Vec3, // minimum corner at both ends of the run
	travel_time: f32,
	period:      f32,
	phase:       f32,
	position:    Vec3,
	delta:       Vec3, // motion during the last step, carries riders
	timer:       f32,
	fall_speed:  f32,
	pad:         int,
}

Shard :: struct {
	position: Vec3,
	pad:      int,
	taken:    bool,
}

// Retracting spike strip lying on a pad.
Spikes :: struct {
	lo, hi: Vec2,
	top:    f32,
	period: f32,
	phase:  f32,
	pad:    int,
}

// Hovering wraith patrolling across a pad; touching it knocks the player away.
Sentinel :: struct {
	a, b:     Vec3, // centre at both ends of the patrol
	speed:    f32,
	phase:    f32,
	position: Vec3,
	pad:      int,
}

Bridge :: struct {
	from, to: int,
	lo, hi:   [2]int,
	y:        int,
	axis:     int, // 0 runs along x, 1 along z
	holes:    [2]int, // offsets along the axis, -1 for none
	hole_len: int,
}

Far_Spire :: struct {
	position: Vec3,
	width:    f32,
	height:   f32,
}

Death_Kind :: enum u8 {
	Fall,
	Spikes,
}

Phase :: enum u8 {
	Alive,
	Dying,
	Finished,
}

Event_Kind :: enum u8 {
	Jump,
	Air_Jump,
	Dash,
	Land,
	Shard,
	Portal_Open,
	Portal_Sealed,
	Knockback,
	Death,
	Respawn,
	Crumble_Shake,
	Crumble_Fall,
	Time_Low,
	Win,
	Lose,
}

// Something the renderer and the audio react to; reset every step.
Event :: struct {
	kind:     Event_Kind,
	position: Vec3,
	value:    f32,
}

Player_Input :: struct {
	move:         Vec2, // world-space (x, z), length <= 1
	jump_pressed: bool,
	jump_held:    bool,
	dash_pressed: bool,
}

Gen_Settings :: struct {
	path_pads:       int,
	shards_required: int,
	shards_bonus:    int,
	lives:           int,
	safety:          f32, // fraction of the jump reach a gap may use
	double_jump:     bool, // main links may need the air jump
	rise_min:        int,
	rise_max:        int,
	size_min:        int,
	size_max:        int,
	shuttle_chance:  f32,
	crumble_chance:  f32,
	bridge_chance:   f32,
	spire_chance:    f32,
	max_shuttles:    int,
	max_crumbles:    int,
	spikes:          int,
	sentinels:       int,
	branch_max:      int,
	bridge_holes:    int,
	crumble_delay:   f32,
	knockback:       f32,
	timed:           bool, // challenge rounds run on a clock
}

World :: struct {
	config:          host.Minigame_Config,
	settings:        Gen_Settings,
	params:          physics.Platformer_Params,
	reach_single:    [REACH_COUNT]f32,
	reach_double:    [REACH_COUNT]f32,
	terrain:         physics.Voxel_Map,
	// Bumped by every reset so the renderer knows to rebuild its meshes.
	generation:      u64,
	pads:            [MAX_PADS]Pad,
	pad_count:       int,
	path:            [MAX_PATH]int, // main route, spawn first and goal last
	path_count:      int,
	movers:          [MAX_MOVERS]Mover,
	mover_count:     int,
	shards:          [MAX_SHARDS]Shard,
	shard_count:     int,
	spikes:          [MAX_SPIKES]Spikes,
	spike_count:     int,
	sentinels:       [MAX_SENTINELS]Sentinel,
	sentinel_count:  int,
	bridges:         [MAX_BRIDGES]Bridge,
	bridge_count:    int,
	far:             [MAX_FAR]Far_Spire,
	far_count:       int,
	braziers:        [MAX_BRAZIERS]Vec3,
	brazier_count:   int,
	portal_center:   Vec3,
	portal_axis:     int, // travel axis through the arch: 0 = x, 1 = z
	portal_lo:       Vec3,
	portal_hi:       Vec3,
	kill_y:          f32,
	player:          physics.Platformer3,
	riding:          int,
	safe_pad:        int,
	lives:           int,
	deaths:          int,
	shards_taken:    int,
	shards_required: int,
	portal_open:     bool,
	time:            f32,
	time_limit:      f32,
	time_warned:     bool,
	par_time:        f32,
	phase:           Phase,
	phase_timer:     f32,
	death_kind:      Death_Kind,
	invulnerable:    f32,
	stun:            f32,
	sealed_cooldown: f32,
	stride:          f32, // distance walked, drives the leg cycle
	status:          host.Round_Status,
	events:          [MAX_EVENTS]Event,
	event_count:     int,
	steps:           u64,
}

gen_settings :: proc(config: host.Minigame_Config) -> Gen_Settings {
	s := Gen_Settings{
		path_pads = 18, shards_required = 7, shards_bonus = 2, lives = 3, safety = 0.64,
		double_jump = true, rise_min = -2, rise_max = 2, size_min = 3, size_max = 6,
		shuttle_chance = 0.14, crumble_chance = 0.14, bridge_chance = 0.16, spire_chance = 0.22,
		max_shuttles = 2, max_crumbles = 2, spikes = 3, sentinels = 2, branch_max = 2,
		bridge_holes = 1, crumble_delay = 0.62, knockback = 8,
	}
	if config.challenge {
		// One attempt inside a run: a shorter course, a little gentler, on a clock.
		s.path_pads = s.path_pads/2 + 2
		s.shards_required = 4
		s.shards_bonus = 1
		s.safety -= 0.04
		s.spikes = (s.spikes + 1) / 2
		s.sentinels = (s.sentinels + 1) / 2
		s.max_shuttles = max(1, s.max_shuttles/2)
		s.max_crumbles = max(1, s.max_crumbles/2)
		s.branch_max = max(1, s.branch_max-1)
		s.crumble_delay += 0.1
		s.timed = true
	}
	return s
}

world_reset :: proc(w: ^World, config: host.Minigame_Config) {
	physics.voxel_map_destroy(&w.terrain)
	generation := w.generation + 1
	w^ = {}
	w.generation = generation
	w.config = config
	w.settings = gen_settings(config)
	w.params = PLAYER_PARAMS
	compute_reach(w)
	generate(w)
	w.lives = w.settings.lives
	w.shards_required = min(w.settings.shards_required, w.shard_count)
	w.par_time = f32(w.path_count)*2.4 + f32(w.shard_count)*5 + 8
	if w.settings.timed {
		// About twice what a quick, clean run needs, rounded to 5 s.
		w.time_limit = math.ceil(w.par_time*1.45/5) * 5
	}
	w.safe_pad = 0
	w.status = .Playing
	spawn_player(w, 0)
	update_movers(w, 0)
	update_sentinels(w)
}

world_destroy :: proc(w: ^World) {
	physics.voxel_map_destroy(&w.terrain)
}

compute_reach :: proc(w: ^World) {
	for i in 0..<REACH_COUNT {
		rise := f32(REACH_MIN_RISE + i)
		w.reach_single[i] = jump_reach(w.params, rise, false)
		w.reach_double[i] = jump_reach(w.params, rise, true)
	}
}

// Horizontal distance a running jump covers before the feet come back down to
// `rise` (relative to the take-off), measured by running the real controller
// in empty space. With `double_jump` the air jump fires at the first apex.
jump_reach :: proc(params: physics.Platformer_Params, rise: f32, double_jump: bool) -> f32 {
	space := physics.Voxel_Map{voxel_size = 1}
	p := physics.platformer3_create({0, 0, 0}, PLAYER_SIZE)
	p.grounded = true
	p.body.velocity = {0, 0, params.max_speed}
	ctl := physics.Platformer3_Input{move = {0, 1}, jump_pressed = true, jump_held = true}
	above := rise <= 0
	air_used := false
	for _ in 0..<SIM_HZ*4 {
		physics.platformer3_step(&p, params, ctl, &space, SIM_DT)
		ctl.jump_pressed = false
		feet := physics.body3_feet(p.body)
		if feet.y > rise+0.05 {
			above = true
		}
		if p.body.velocity.y <= 0 {
			if double_jump && !air_used {
				ctl.jump_pressed = true
				air_used = true
				continue
			}
			if above && feet.y <= rise {
				return feet.z
			}
		}
	}
	return 0
}

reach_at :: proc(w: ^World, rise: int, double_jump: bool) -> f32 {
	i := clamp(rise, REACH_MIN_RISE, REACH_MAX_RISE) - REACH_MIN_RISE
	return w.reach_double[i] if double_jump else w.reach_single[i]
}

pad_center :: proc "contextless" (p: Pad) -> Vec2 {
	return Vec2{f32(p.lo[0]+p.hi[0]) * 0.5, f32(p.lo[1]+p.hi[1]) * 0.5}
}

// Live walkable area of a pad (movers report where they are now).
pad_area :: proc(w: ^World, index: int) -> (lo, hi: Vec2, top: f32) {
	p := w.pads[index]
	if p.mover >= 0 {
		m := w.movers[p.mover]
		return Vec2{m.position.x, m.position.z}, Vec2{m.position.x + m.size.x, m.position.z + m.size.z},
			m.position.y + m.size.y
	}
	return Vec2{f32(p.lo[0]), f32(p.lo[1])}, Vec2{f32(p.hi[0]), f32(p.hi[1])}, f32(p.top)
}

mover_solid :: proc "contextless" (m: Mover) -> bool {
	return m.kind == .Shuttle || m.state == .Idle || m.state == .Shaking
}

// 0 at end a, 1 at end b; shuttles pause at both ends.
shuttle_progress :: proc(m: Mover, time: f32) -> f32 {
	s := math.mod(time+m.phase, m.period)
	tt := m.travel_time
	switch {
	case s < SHUTTLE_PAUSE:
		return 0
	case s < SHUTTLE_PAUSE+tt:
		return tween.ease(.Smoothstep, (s - SHUTTLE_PAUSE) / tt)
	case s < 2*SHUTTLE_PAUSE+tt:
		return 1
	}
	return 1 - tween.ease(.Smoothstep, (s-2*SHUTTLE_PAUSE-tt)/tt)
}

// Which end the shuttle rests at (-1 while travelling) and for how long still.
shuttle_dwell :: proc(m: Mover, time: f32) -> (end: int, remaining: f32) {
	s := math.mod(time+m.phase, m.period)
	tt := m.travel_time
	if s < SHUTTLE_PAUSE {
		return 0, SHUTTLE_PAUSE - s
	}
	if s >= SHUTTLE_PAUSE+tt && s < 2*SHUTTLE_PAUSE+tt {
		return 1, 2*SHUTTLE_PAUSE + tt - s
	}
	return -1, 0
}

// Spike extension 0..1: retracted for the first half of the cycle, then a
// quick rise, a long stab and a quick retreat.
spike_extension :: proc(s: Spikes, time: f32) -> f32 {
	u := math.mod(time+s.phase, s.period) / s.period
	switch {
	case u < 0.5:
		return 0
	case u < 0.56:
		return (u - 0.5) / 0.06
	case u < 0.94:
		return 1
	}
	return (1 - u) / 0.06
}

// 0..1 during the moment before the spikes rise, so they can rattle a warning.
spike_warning :: proc(s: Spikes, time: f32) -> f32 {
	u := math.mod(time+s.phase, s.period) / s.period
	if u < 0.36 || u >= 0.5 {
		return 0
	}
	return (u - 0.36) / 0.14
}

sentinel_position :: proc(s: Sentinel, time: f32) -> Vec3 {
	span := physics.length3(s.b - s.a)
	u := math.mod(time*s.speed/max(span, 0.1)+s.phase, 2)
	if u > 1 {
		u = 2 - u
	}
	return s.a + (s.b-s.a)*tween.ease(.Smoothstep, u)
}

update_movers :: proc(w: ^World, dt: f32) {
	for i in 0..<w.mover_count {
		m := &w.movers[i]
		old := m.position
		switch m.kind {
		case .Shuttle:
			m.position = m.a + (m.b-m.a)*shuttle_progress(m^, w.time)
		case .Crumble:
			switch m.state {
			case .Idle:
			case .Shaking:
				m.timer -= dt
				if m.timer <= 0 {
					m.state = .Falling
					m.timer = CRUMBLE_FALL_TIME
					m.fall_speed = 0
					emit(w, .Crumble_Fall, m.position+m.size*0.5)
				}
			case .Falling:
				m.fall_speed += 22 * dt
				m.position.y -= m.fall_speed * dt
				m.timer -= dt
				if m.timer <= 0 {
					m.state = .Gone
					m.timer = CRUMBLE_RESPAWN
				}
			case .Gone:
				m.timer -= dt
				if m.timer <= 0 && !player_overlaps(w, m.a, m.a+m.size) {
					m.state = .Idle
					m.position = m.a
					old = m.a
				}
			}
		}
		m.delta = m.position - old
	}
}

update_sentinels :: proc(w: ^World) {
	for i in 0..<w.sentinel_count {
		s := &w.sentinels[i]
		s.position = sentinel_position(s^, w.time)
	}
}

emit :: proc(w: ^World, kind: Event_Kind, position: Vec3, value: f32 = 0) {
	if w.event_count >= MAX_EVENTS {
		return
	}
	w.events[w.event_count] = Event{kind = kind, position = position, value = value}
	w.event_count += 1
}

player_box :: proc "contextless" (w: ^World) -> (lo, hi: Vec3) {
	b := w.player.body
	return b.position, b.position + b.size
}

player_overlaps :: proc "contextless" (w: ^World, lo, hi: Vec3) -> bool {
	plo, phi := player_box(w)
	return physics.boxes_overlap3(plo, phi, lo, hi)
}

// Static pad (or ridden mover's pad) under the grounded player, -1 if none.
standing_pad :: proc(w: ^World) -> int {
	p := w.player
	if !p.grounded {
		return -1
	}
	if w.riding >= 0 {
		return w.movers[w.riding].pad
	}
	feet := physics.body3_feet(p.body)
	lo := Vec2{p.body.position.x, p.body.position.z}
	hi := lo + Vec2{p.body.size.x, p.body.size.z}
	for i in 0..<w.pad_count {
		pd := w.pads[i]
		if pd.mover >= 0 || abs(feet.y-f32(pd.top)) > 0.05 {
			continue
		}
		// The body may hang over an edge, so test its footprint, not the feet point.
		if lo.x < f32(pd.hi[0]) && hi.x > f32(pd.lo[0]) && lo.y < f32(pd.hi[1]) && hi.y > f32(pd.lo[1]) {
			return i
		}
	}
	return -1
}

facing_yaw :: proc(w: ^World, pad: int) -> f32 {
	pd := w.pads[pad]
	toward := pd.next
	if toward < 0 && pd.branch {
		toward = pd.parent
	}
	if toward < 0 {
		return 0
	}
	from := pad_center(pd)
	to := pad_center(w.pads[toward])
	return math.atan2(to.x-from.x, to.y-from.y)
}

spawn_player :: proc(w: ^World, pad: int) {
	w.player = physics.platformer3_create(w.pads[pad].respawn, PLAYER_SIZE)
	w.player.grounded = true
	w.player.yaw = facing_yaw(w, pad)
	w.riding = -1
	w.stun = 0
}

world_step :: proc(w: ^World, input: Player_Input, dt: f32) -> host.Round_Status {
	w.event_count = 0
	if w.status != .Playing {
		return w.status
	}
	w.steps += 1
	w.time += dt
	update_movers(w, dt)
	update_sentinels(w)
	if w.phase == .Dying {
		w.phase_timer -= dt
		if w.death_kind == .Fall {
			// Keep falling for the camera, without collisions.
			b := &w.player.body
			b.velocity.y = max(b.velocity.y-w.params.gravity*w.params.fall_gravity_scale*dt, -w.params.max_fall_speed)
			b.position += b.velocity * dt
		}
		if w.phase_timer <= 0 {
			if w.lives <= 0 {
				finish(w, .Lost)
			} else {
				respawn(w)
			}
		}
		return w.status
	}
	w.invulnerable = max(w.invulnerable-dt, 0)
	w.stun = max(w.stun-dt, 0)
	w.sealed_cooldown = max(w.sealed_cooldown-dt, 0)
	if w.time_limit > 0 {
		left := w.time_limit - w.time
		if !w.time_warned && left <= 10 {
			w.time_warned = true
			emit(w, .Time_Low, physics.body3_feet(w.player.body))
		}
		if left <= 0 {
			finish(w, .Lost)
			return w.status
		}
	}
	move_player(w, input, dt)
	check_pickups(w)
	if w.phase == .Alive {
		check_hazards(w)
	}
	if w.phase == .Alive {
		check_portal(w)
	}
	if w.phase == .Alive {
		check_fall(w)
	}
	return w.status
}

@(private)
move_player :: proc(w: ^World, input: Player_Input, dt: f32) {
	p := &w.player
	if w.riding >= 0 {
		m := w.movers[w.riding]
		if mover_solid(m) {
			physics.move_body3(&w.terrain, &p.body, m.delta)
		} else {
			w.riding = -1
		}
	}
	prev := p.body.position
	was_grounded := p.grounded
	ctl := physics.Platformer3_Input{move = input.move, jump_pressed = input.jump_pressed,
		jump_held = input.jump_held, dash_pressed = input.dash_pressed}
	if w.stun > 0 {
		ctl = physics.Platformer3_Input{jump_held = input.jump_held}
	}
	result, ev := physics.platformer3_step(p, w.params, ctl, &w.terrain, dt)
	falling := max(-p.body.velocity.y, 0)
	on_mover := resolve_movers(w, prev)
	p.grounded = result.on_ground || on_mover
	feet := physics.body3_feet(p.body)
	if ev.jumped {
		emit(w, .Jump, feet)
	}
	if ev.air_jumped {
		emit(w, .Air_Jump, feet)
	}
	if ev.dashed {
		emit(w, .Dash, physics.body3_center(p.body), p.yaw)
	}
	if ev.landed {
		emit(w, .Land, feet, ev.landing_speed)
	} else if on_mover && !was_grounded {
		emit(w, .Land, feet, falling)
	}
	if w.riding >= 0 {
		m := &w.movers[w.riding]
		if m.kind == .Crumble && m.state == .Idle {
			m.state = .Shaking
			m.timer = w.settings.crumble_delay
			emit(w, .Crumble_Shake, m.position+m.size*0.5)
		}
	}
	if p.grounded && w.riding < 0 {
		if pad := standing_pad(w); pad >= 0 {
			w.safe_pad = pad
		}
	}
	if p.grounded {
		w.stride += physics.length2(Vec2{p.body.velocity.x, p.body.velocity.z}) * dt
	}
}

// Collides the player with every solid mover after the voxel move. Returns
// true when standing on one (w.riding is set to it).
@(private)
resolve_movers :: proc(w: ^World, prev: Vec3) -> bool {
	p := &w.player
	grounded := false
	w.riding = -1
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if !mover_solid(m) {
			continue
		}
		mlo := m.position
		mhi := m.position + m.size
		plo := p.body.position
		phi := plo + p.body.size
		if !physics.boxes_overlap3(plo, phi, mlo, mhi) {
			continue
		}
		if prev.y >= mhi.y-0.15 && p.body.velocity.y <= 0.01 {
			p.body.position.y = mhi.y
			p.body.velocity.y = 0
			grounded = true
			w.riding = i
			continue
		}
		if prev.y+p.body.size.y <= mlo.y+0.15 && p.body.velocity.y > 0 {
			p.body.position.y = mlo.y - p.body.size.y
			p.body.velocity.y = 0
			continue
		}
		// Side contact: leave along the shortest horizontal way out.
		outs := [4]f32{mhi.x - plo.x, phi.x - mlo.x, mhi.z - plo.z, phi.z - mlo.z}
		best := 0
		for k in 1..<4 {
			if outs[k] < outs[best] {
				best = k
			}
		}
		push: Vec3
		switch best {
		case 0:
			push.x = outs[0] + 0.001
		case 1:
			push.x = -outs[1] - 0.001
		case 2:
			push.z = outs[2] + 0.001
		case:
			push.z = -outs[3] - 0.001
		}
		physics.move_body3(&w.terrain, &p.body, push)
		if push.x != 0 {
			p.body.velocity.x = 0
		} else {
			p.body.velocity.z = 0
		}
	}
	return grounded
}

@(private)
check_pickups :: proc(w: ^World) {
	center := physics.body3_center(w.player.body)
	for i in 0..<w.shard_count {
		s := &w.shards[i]
		if s.taken || physics.length3(s.position-center) > SHARD_RADIUS {
			continue
		}
		s.taken = true
		w.shards_taken += 1
		emit(w, .Shard, s.position, f32(w.shards_taken))
		if !w.portal_open && w.shards_taken >= w.shards_required {
			w.portal_open = true
			emit(w, .Portal_Open, w.portal_center)
		}
	}
}

@(private)
check_hazards :: proc(w: ^World) {
	if w.invulnerable > 0 {
		return
	}
	plo, phi := player_box(w)
	for i in 0..<w.spike_count {
		s := w.spikes[i]
		ext := spike_extension(s, w.time)
		if ext < 0.45 {
			continue
		}
		// Slightly smaller than drawn, so grazes feel fair.
		lo := Vec3{s.lo.x + 0.1, s.top, s.lo.y + 0.1}
		hi := Vec3{s.hi.x - 0.1, s.top + 0.7*ext, s.hi.y - 0.1}
		if physics.boxes_overlap3(plo, phi, lo, hi) {
			die(w, .Spikes)
			return
		}
	}
	half := Vec3{0.42, 0.5, 0.42}
	for i in 0..<w.sentinel_count {
		s := w.sentinels[i]
		if !physics.boxes_overlap3(plo, phi, s.position-half, s.position+half) {
			continue
		}
		center := physics.body3_center(w.player.body)
		away := Vec2{center.x - s.position.x, center.z - s.position.z}
		if physics.length2(away) < 0.05 {
			patrol := s.b - s.a
			away = Vec2{-patrol.z, patrol.x}
		}
		dir := physics.normalize2(away)
		p := &w.player
		p.body.velocity = Vec3{dir.x * w.settings.knockback, 6.5, dir.y * w.settings.knockback}
		p.jump_cut_used = true
		p.dash_remaining = 0
		p.grounded = false
		w.riding = -1
		w.stun = STUN_TIME
		w.invulnerable = 0.8
		emit(w, .Knockback, (center+s.position)*0.5)
		return
	}
}

@(private)
check_portal :: proc(w: ^World) {
	if !player_overlaps(w, w.portal_lo, w.portal_hi) {
		return
	}
	if w.portal_open {
		finish(w, .Won)
	} else if w.sealed_cooldown <= 0 {
		w.sealed_cooldown = 2.5
		emit(w, .Portal_Sealed, w.portal_center, f32(w.shards_required-w.shards_taken))
	}
}

@(private)
check_fall :: proc(w: ^World) {
	p := w.player
	feet := physics.body3_feet(p.body)
	if feet.y < w.kill_y {
		die(w, .Fall)
		return
	}
	// End hopeless falls early instead of waiting for the kill plane.
	safe_top := f32(w.pads[w.safe_pad].top)
	if p.body.velocity.y < -6 && feet.y < safe_top-4 && !ground_below(w) {
		die(w, .Fall)
	}
}

// Anything (voxel or solid mover) below any corner of the player's footprint.
ground_below :: proc(w: ^World) -> bool {
	b := w.player.body
	depth := b.position.y - w.kill_y + 1
	corners := [5]Vec2{
		{b.position.x, b.position.z},
		{b.position.x + b.size.x, b.position.z},
		{b.position.x, b.position.z + b.size.z},
		{b.position.x + b.size.x, b.position.z + b.size.z},
		{b.position.x + b.size.x*0.5, b.position.z + b.size.z*0.5},
	}
	for c in corners {
		origin := Vec3{clamp(c.x, b.position.x+0.01, b.position.x+b.size.x-0.01), b.position.y,
			clamp(c.y, b.position.z+0.01, b.position.z+b.size.z-0.01)}
		if physics.raycast_voxels(&w.terrain, origin, {0, -1, 0}, depth).hit {
			return true
		}
	}
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if !mover_solid(m) || m.position.y+m.size.y > b.position.y {
			continue
		}
		if b.position.x < m.position.x+m.size.x && b.position.x+b.size.x > m.position.x &&
		   b.position.z < m.position.z+m.size.z && b.position.z+b.size.z > m.position.z {
			return true
		}
	}
	return false
}

@(private)
die :: proc(w: ^World, kind: Death_Kind) {
	w.lives -= 1
	w.deaths += 1
	w.phase = .Dying
	w.death_kind = kind
	w.phase_timer = DEATH_TIME
	w.riding = -1
	if kind == .Spikes {
		w.player.body.velocity = {}
	}
	emit(w, .Death, physics.body3_center(w.player.body), f32(kind))
}

@(private)
respawn :: proc(w: ^World) {
	spawn_player(w, w.safe_pad)
	w.phase = .Alive
	w.invulnerable = RESPAWN_GRACE
	emit(w, .Respawn, physics.body3_feet(w.player.body), w.player.yaw)
}

@(private)
finish :: proc(w: ^World, status: host.Round_Status) {
	w.status = status
	w.phase = .Finished
	emit(w, .Win if status == .Won else .Lose, physics.body3_center(w.player.body))
}

// Score: shards always count; a win adds a bonus, lives left and the time
// under par. Stars: 1 for reaching the portal, 2 with every shard, 3 with
// every shard and no life lost.
world_score :: proc(w: ^World) -> (score: i64, stars: u8) {
	score = i64(w.shards_taken) * SHARD_POINTS
	if w.status != .Won {
		return score, 0
	}
	score += WIN_POINTS + i64(max(w.lives, 0))*LIFE_POINTS + i64(max(w.par_time-w.time, 0)*TIME_POINTS)
	stars = 1
	if w.shards_taken >= w.shard_count {
		stars = 2
		if w.deaths == 0 {
			stars = 3
		}
	}
	return score, stars
}
