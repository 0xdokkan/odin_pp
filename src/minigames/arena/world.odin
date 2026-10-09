// Simulation of the arena: the player, bullets, pickups, scoring and the wave
// director. Pure math with no raylib calls, so tests drive it headless; the
// renderer and the audio only read the state and the per-step event records.
package arena

import "core:math"
import host "../../engine/host"
import physics "../../engine/physics"
import pool "../../engine/pool"
import rng "../../engine/rng"

Vec2 :: [2]f32

SIM_HZ :: 120
SIM_DT :: f32(1.0 / SIM_HZ)

MAP_W :: 36
MAP_H :: 21
TILE :: f32(32)
WORLD_W :: f32(MAP_W) * TILE
WORLD_H :: f32(MAP_H) * TILE

MAX_ENEMIES :: 96
MAX_BULLETS :: 192
MAX_ORBS :: 256
MAX_PICKUPS :: 24
MAX_SPAWNS :: 24
MAX_EVENTS :: 192
MAX_QUEUE :: 80
MAX_PORTALS :: 8

PLAYER_RADIUS :: f32(10)
PLAYER_SPEED :: f32(205)
// Exponential approach rate of the velocity toward the stick direction.
PLAYER_ACCEL :: f32(16)
DASH_SPEED :: f32(620)
DASH_TIME :: f32(0.16)
DASH_INVULN :: f32(0.28)
DASH_COOLDOWN :: f32(0.7)
HURT_INVULN :: f32(1.1)
FIRE_INTERVAL :: f32(0.13)
BULLET_SPEED :: f32(660)
BULLET_LIFE :: f32(0.85)
POWER_DURATION :: f32(9)
COMBO_WINDOW :: f32(2.4)
PICKUP_LIFE :: f32(11)
PICKUP_MAGNET :: f32(78)
FIRST_CALM :: f32(1.4)
CALM_TIME :: f32(3.2)
VICTORY_TIME :: f32(1.6)
DEFEAT_TIME :: f32(1.3)

Phase :: enum u8 {
	Calm,
	Fight,
	Victory,
	Defeat,
}

Power :: enum u8 {
	Spread,
	Rapid,
	Pierce,
}

Pickup_Kind :: enum u8 {
	Heart,
	Spread,
	Rapid,
	Pierce,
}

// What the hook hands the simulation each step, already device-independent.
Player_Input :: struct {
	move: Vec2, // length <= 1
	aim:  Vec2, // direction; zero keeps the previous aim
	fire: bool,
	dash: bool, // edge: true on exactly one step per press
}

Player :: struct {
	pos, prev, vel: Vec2,
	aim:            Vec2,
	hp, max_hp:     int,
	invuln:         f32,
	hurt_time:      f32, // seconds since the last hit, for the renderer
	dash_time:      f32,
	dash_cooldown:  f32,
	dash_dir:       Vec2,
	fire_cooldown:  f32,
	power:          [Power]f32,
	walk_time:      f32,
	alive:          bool,
}

Bullet :: struct {
	pos, prev, vel: Vec2,
	life:           f32,
	damage:         f32,
	radius:         f32,
	pierce:         int,
	// A piercing bullet overlaps an enemy for several steps; hit it once.
	last_hit:       pool.Handle,
}

Orb :: struct {
	pos, prev, vel: Vec2,
	life:           f32,
	radius:         f32,
	big:            bool,
}

Pickup :: struct {
	kind:     Pickup_Kind,
	pos, vel: Vec2,
	life:     f32,
	age:      f32,
}

// A telegraphed spawn: the rune glows before the enemy steps out.
Spawn :: struct {
	kind:  Enemy_Kind,
	pos:   Vec2,
	timer: f32,
	total: f32,
}

Event_Kind :: enum u8 {
	Shot,
	Bullet_Wall,
	Enemy_Hit,
	Enemy_Killed,
	Enemy_Spawned,
	Spawn_Warning,
	Windup,
	Enemy_Fire,
	Charge,
	Wall_Slam,
	Split,
	Player_Hurt,
	Player_Dash,
	Player_Died,
	Pickup_Dropped,
	Pickup_Taken,
	Orb_Pop,
	Combo_Tier,
	Wave_Start,
	Wave_Clear,
	Boss_Enraged,
	Victory,
}

Event :: struct {
	kind:   Event_Kind,
	pos:    Vec2,
	dir:    Vec2,
	value:  i64,
	enemy:  Enemy_Kind,
	pickup: Pickup_Kind,
	flag:   bool,
}

// Everything the difficulty and the launch mode change.
Tuning :: struct {
	waves:         int,
	max_hp:        int,
	enemy_speed:   f32,
	orb_speed:     f32,
	cast_interval: f32,
	budget_low:    f32,
	budget_high:   f32,
	alive_cap:     int,
	boss_hp:       f32,
	caster_shots:  int,
	boss_ring:     int,
	combo_goal:    int,
	drop_bonus:    f32,
}

tuning_for :: proc(config: host.Minigame_Config) -> Tuning {
	t: Tuning
	switch clamp(config.difficulty, 0, 2) {
	case 0:
		t = Tuning{
			waves = 7, max_hp = 8, enemy_speed = 0.85, orb_speed = 0.8, cast_interval = 1.3,
			budget_low = 7, budget_high = 33, alive_cap = 14, boss_hp = 55, caster_shots = 1,
			boss_ring = 10, combo_goal = 20, drop_bonus = 0.03,
		}
	case 1:
		t = Tuning{
			waves = 8, max_hp = 6, enemy_speed = 1, orb_speed = 1, cast_interval = 1,
			budget_low = 10, budget_high = 46, alive_cap = 20, boss_hp = 85, caster_shots = 1,
			boss_ring = 14, combo_goal = 32, drop_bonus = 0,
		}
	case:
		t = Tuning{
			waves = 10, max_hp = 5, enemy_speed = 1.12, orb_speed = 1.15, cast_interval = 0.85,
			budget_low = 12, budget_high = 60, alive_cap = 26, boss_hp = 115, caster_shots = 3,
			boss_ring = 18, combo_goal = 42, drop_bonus = 0,
		}
	}
	if config.challenge {
		// A run challenge is a short sprint: fewer waves, a lighter final boss.
		t.waves = 3 + clamp(config.difficulty, 0, 2)
		t.max_hp += 1
		t.budget_low *= 0.9
		t.budget_high *= 0.62
		t.boss_hp *= 0.6
		t.combo_goal = t.combo_goal * 11 / 20
	}
	return t
}

World :: struct {
	config:         host.Minigame_Config,
	tuning:         Tuning,
	tiles:          physics.Tile_Map,
	// Breadth-first distance (in cells) to the player, steering enemies around walls.
	flow:           [MAP_W * MAP_H]u16,
	flow_cell:      [2]int,
	flow_ready:     bool,
	portals:        [MAX_PORTALS]Vec2,
	portal_count:   int,
	obstacle_cells: int,
	player:         Player,
	enemies:        pool.Pool(Enemy, MAX_ENEMIES),
	bullets:        pool.Pool(Bullet, MAX_BULLETS),
	orbs:           pool.Pool(Orb, MAX_ORBS),
	pickups:        pool.Pool(Pickup, MAX_PICKUPS),
	spawns:         pool.Pool(Spawn, MAX_SPAWNS),
	events:         [MAX_EVENTS]Event,
	event_count:    int,
	events_dropped: int,
	wave_rng:       rng.Rng,
	ai_rng:         rng.Rng,
	phase:          Phase,
	phase_time:     f32,
	wave:           int, // 1-based once the first wave starts
	queue:          [MAX_QUEUE]Enemy_Kind,
	queue_len:      int,
	queue_next:     int,
	wave_total:     int, // enemies in the current wave, shards excluded
	wave_killed:    int,
	spawn_timer:    f32,
	new_kinds:      bit_set[Enemy_Kind],
	seen_kinds:     bit_set[Enemy_Kind],
	wave_hurt:      bool,
	perfect_waves:  int,
	score:          i64,
	kills:          int,
	combo:          int,
	best_combo:     int,
	combo_timer:    f32,
	time:           f32,
	steps:          u64,
	status:         host.Round_Status,
	boss:           pool.Handle,
	next_id:        u32,
	spawn_failures: int,
}

// Rebuilds the round from the config. The tile map is allocated once and
// reused, so retries do not churn memory; world_destroy releases it.
world_reset :: proc(w: ^World, config: host.Minigame_Config) {
	tiles := w.tiles
	if tiles.cells.width != MAP_W || tiles.cells.height != MAP_H {
		physics.tile_map_destroy(&tiles)
		tiles, _ = physics.tile_map_create(MAP_W, MAP_H, TILE)
	}
	w^ = {}
	w.tiles = tiles
	w.config = config
	w.tuning = tuning_for(config)
	w.wave_rng = rng.create(rng.derive(config.seed, 2))
	w.ai_rng = rng.create(rng.derive(config.seed, 3))
	map_rng := rng.create(rng.derive(config.seed, 1))
	generate_level(w, &map_rng)

	p := &w.player
	p.pos = player_start()
	p.prev = p.pos
	p.aim = {1, 0}
	p.max_hp = w.tuning.max_hp
	p.hp = p.max_hp
	p.alive = true
	p.hurt_time = 99
	w.phase = .Calm
	w.status = .Playing
}

world_destroy :: proc(w: ^World) {
	physics.tile_map_destroy(&w.tiles)
}

player_start :: proc "contextless" () -> Vec2 {
	return Vec2{WORLD_W * 0.5, WORLD_H * 0.5}
}

world_step :: proc(w: ^World, input: Player_Input, dt: f32) -> host.Round_Status {
	if w.status != .Playing {
		return w.status
	}
	w.steps += 1
	w.time += dt
	w.phase_time += dt
	update_player(w, input, dt)
	flow_update(w)
	update_director(w, dt)
	update_spawns(w, dt)
	update_enemies(w, dt)
	separate_enemies(w)
	update_bullets(w, dt)
	update_orbs(w, dt)
	update_pickups(w, dt)
	if w.combo > 0 {
		w.combo_timer -= dt
		if w.combo_timer <= 0 {
			w.combo = 0
			w.combo_timer = 0
		}
	}
	return w.status
}

world_score :: proc(w: ^World) -> (score: i64, stars: u8) {
	score = w.score
	if w.status == .Won || w.phase == .Victory {
		// One star per goal: survive, keep half the hearts, chain a long combo.
		stars = 1
		if w.player.hp*2 >= w.player.max_hp {
			stars += 1
		}
		if w.best_combo >= w.tuning.combo_goal {
			stars += 1
		}
	}
	return
}

combo_multiplier :: proc "contextless" (combo: int) -> i64 {
	return i64(min(1 + combo/5, 8))
}

events_clear :: proc(w: ^World) {
	w.event_count = 0
	w.events_dropped = 0
}

@(private)
emit :: proc(w: ^World, e: Event) {
	// Cosmetic events give way first, so a shower of orb pops can never
	// crowd out a wave clear or the victory.
	cosmetic := e.kind == .Orb_Pop || e.kind == .Bullet_Wall || e.kind == .Enemy_Hit || e.kind == .Shot
	if w.event_count >= MAX_EVENTS || (cosmetic && w.event_count >= MAX_EVENTS-32) {
		w.events_dropped += 1
		return
	}
	w.events[w.event_count] = e
	w.event_count += 1
}

@(private)
update_player :: proc(w: ^World, input: Player_Input, dt: f32) {
	p := &w.player
	p.prev = p.pos
	p.hurt_time += dt
	p.invuln = max(p.invuln-dt, 0)
	p.dash_cooldown = max(p.dash_cooldown-dt, 0)
	p.fire_cooldown = max(p.fire_cooldown-dt, 0)
	for &t in p.power {
		t = max(t-dt, 0)
	}
	if !p.alive {
		p.vel *= max(1-8*dt, 0)
		p.pos += p.vel * dt
		physics.resolve_circle_tiles(&w.tiles, &p.pos, PLAYER_RADIUS)
		return
	}
	move := physics.clamp_length2(input.move, 1)
	if input.aim != {} {
		p.aim = physics.normalize2(input.aim)
	}
	if input.dash && p.dash_cooldown <= 0 && p.dash_time <= 0 {
		dir := physics.normalize2(move)
		if dir == {} {
			dir = p.aim
		}
		p.dash_dir = dir
		p.dash_time = DASH_TIME
		p.dash_cooldown = DASH_COOLDOWN
		p.invuln = max(p.invuln, DASH_INVULN)
		emit(w, Event{kind = .Player_Dash, pos = p.pos, dir = dir})
	}
	if p.dash_time > 0 {
		p.dash_time -= dt
		p.vel = p.dash_dir * DASH_SPEED
		if p.dash_time <= 0 {
			// Keep some momentum out of the dash so it does not feel like a stop.
			p.vel = p.dash_dir * PLAYER_SPEED
		}
	} else {
		target := move * PLAYER_SPEED
		p.vel += (target - p.vel) * (1 - math.exp(-PLAYER_ACCEL*dt))
	}
	p.pos += p.vel * dt
	physics.resolve_circle_tiles(&w.tiles, &p.pos, PLAYER_RADIUS)
	speed := physics.length2(p.vel)
	if speed > 20 {
		p.walk_time += dt * (speed / PLAYER_SPEED)
	}
	if input.fire && p.fire_cooldown <= 0 && w.phase != .Defeat {
		fire_player(w)
	}
}

@(private)
fire_player :: proc(w: ^World) {
	p := &w.player
	interval := FIRE_INTERVAL
	if p.power[.Rapid] > 0 {
		interval *= 0.5
	}
	p.fire_cooldown = interval
	count := 3 if p.power[.Spread] > 0 else 1
	pierce := p.power[.Pierce] > 0
	base := math.atan2(p.aim.y, p.aim.x)
	muzzle := p.pos + p.aim*16
	for i in 0..<count {
		angle := base + rng.float_signed(&w.ai_rng)*0.035
		if count > 1 {
			angle += (f32(i) - f32(count-1)*0.5) * 0.2
		}
		dir := Vec2{math.cos(angle), math.sin(angle)}
		b := Bullet{
			pos    = muzzle,
			prev   = muzzle,
			vel    = dir * BULLET_SPEED,
			life   = BULLET_LIFE,
			damage = 1,
			radius = 6 if pierce else 4,
			pierce = 3 if pierce else 0,
		}
		pool.insert(&w.bullets, b)
	}
	// A touch of recoil sells the shot without fighting the stick.
	p.vel -= p.aim * 14
	emit(w, Event{kind = .Shot, pos = muzzle, dir = p.aim, flag = pierce})
}

@(private)
hurt_player :: proc(w: ^World, amount: int, from: Vec2) {
	p := &w.player
	if !p.alive || p.invuln > 0 || w.phase == .Victory {
		return
	}
	p.hp = max(p.hp-amount, 0)
	p.invuln = HURT_INVULN
	p.hurt_time = 0
	away := physics.normalize2(p.pos - from)
	if away == {} {
		away = -p.aim
	}
	p.vel = away * 360
	p.dash_time = 0
	if w.combo >= 5 {
		emit(w, Event{kind = .Combo_Tier, pos = p.pos, value = 0})
	}
	w.combo = 0
	w.combo_timer = 0
	w.wave_hurt = true
	emit(w, Event{kind = .Player_Hurt, pos = p.pos, dir = away, value = i64(amount)})
	if p.hp <= 0 {
		p.alive = false
		w.phase = .Defeat
		w.phase_time = 0
		// The last ember flares: the swarm is blown back from the body.
		it := pool.iterator(&w.enemies)
		for e in pool.next(&it) {
			push := physics.normalize2(e.pos - p.pos)
			if push == {} {
				push = {0, -1}
			}
			e.knock += push * 520 * enemy_stats(e.kind).knock
		}
		emit(w, Event{kind = .Player_Died, pos = p.pos})
	}
}

@(private)
update_bullets :: proc(w: ^World, dt: f32) {
	it := pool.iterator(&w.bullets)
	for b, h in pool.next(&it) {
		b.prev = b.pos
		b.pos += b.vel * dt
		b.life -= dt
		if b.life <= 0 {
			pool.remove(&w.bullets, h)
			continue
		}
		if !open_at(w, b.pos) {
			emit(w, Event{kind = .Bullet_Wall, pos = b.prev, dir = -physics.normalize2(b.vel)})
			pool.remove(&w.bullets, h)
			continue
		}
		eit := pool.iterator(&w.enemies)
		for e, eh in pool.next(&eit) {
			if eh == b.last_hit || !physics.circles_overlap(b.pos, b.radius, e.pos, e.radius) {
				continue
			}
			damage_enemy(w, eh, e, b.damage, physics.normalize2(b.vel))
			if b.pierce > 0 {
				b.pierce -= 1
				b.last_hit = eh
			} else {
				pool.remove(&w.bullets, h)
			}
			break
		}
	}
}

@(private)
update_orbs :: proc(w: ^World, dt: f32) {
	p := &w.player
	it := pool.iterator(&w.orbs)
	for o, h in pool.next(&it) {
		o.prev = o.pos
		o.pos += o.vel * dt
		o.life -= dt
		if o.life <= 0 || !open_at(w, o.pos) {
			emit(w, Event{kind = .Orb_Pop, pos = o.prev})
			pool.remove(&w.orbs, h)
			continue
		}
		// The hurtbox is a little smaller than the sprite: near misses feel fair.
		if p.alive && physics.circles_overlap(o.pos, o.radius, p.pos, PLAYER_RADIUS*0.7) {
			if p.invuln <= 0 {
				hurt_player(w, 1, o.pos)
				emit(w, Event{kind = .Orb_Pop, pos = o.pos})
				pool.remove(&w.orbs, h)
			}
		}
	}
}

@(private)
fire_orb :: proc(w: ^World, from: Vec2, dir: Vec2, speed: f32, big := false) {
	o := Orb{
		pos    = from,
		prev   = from,
		vel    = dir * speed * w.tuning.orb_speed,
		life   = 5,
		radius = 8 if big else 6,
		big    = big,
	}
	pool.insert(&w.orbs, o)
}

@(private)
clear_orbs :: proc(w: ^World) {
	it := pool.iterator(&w.orbs)
	for o, h in pool.next(&it) {
		emit(w, Event{kind = .Orb_Pop, pos = o.pos})
		pool.remove(&w.orbs, h)
	}
}

@(private)
drop_pickup :: proc(w: ^World, kind: Pickup_Kind, pos: Vec2) {
	if pool.full(&w.pickups) {
		return
	}
	angle := rng.float01(&w.ai_rng) * 2 * math.PI
	pk := Pickup{
		kind = kind,
		pos  = pos,
		vel  = Vec2{math.cos(angle), math.sin(angle)} * 70,
		life = PICKUP_LIFE,
	}
	pool.insert(&w.pickups, pk)
	emit(w, Event{kind = .Pickup_Dropped, pos = pos, pickup = kind})
}

@(private)
roll_drop :: proc(w: ^World, kind: Enemy_Kind, pos: Vec2) {
	p := &w.player
	hearts := 0
	it := pool.iterator(&w.pickups)
	for pk in pool.next(&it) {
		if pk.kind == .Heart {
			hearts += 1
		}
	}
	heart := 0.035 + w.tuning.drop_bonus
	if p.hp*2 <= p.max_hp {
		heart += 0.06
	}
	power := f32(0.045)
	if kind == .Caster || kind == .Charger || kind == .Splitter {
		heart *= 1.6
		power *= 2
	}
	roll := rng.float01(&w.ai_rng)
	if roll < heart && hearts < 2 && p.hp < p.max_hp {
		drop_pickup(w, .Heart, pos)
	} else if roll < heart+power {
		drop_pickup(w, Pickup_Kind(1 + rng.int_range(&w.ai_rng, 0, 2)), pos)
	}
}

@(private)
update_pickups :: proc(w: ^World, dt: f32) {
	p := &w.player
	it := pool.iterator(&w.pickups)
	for pk, h in pool.next(&it) {
		pk.age += dt
		pk.life -= dt
		if pk.life <= 0 {
			pool.remove(&w.pickups, h)
			continue
		}
		to := p.pos - pk.pos
		dist := physics.length2(to)
		if p.alive && dist < PICKUP_MAGNET {
			pk.vel += physics.normalize2(to) * 1400 * dt
		}
		pk.vel *= max(1-5*dt, 0)
		pk.pos += pk.vel * dt
		physics.resolve_circle_tiles(&w.tiles, &pk.pos, 6)
		if p.alive && dist < PLAYER_RADIUS+10 {
			collect(w, pk^)
			pool.remove(&w.pickups, h)
		}
	}
}

@(private)
collect :: proc(w: ^World, pk: Pickup) {
	p := &w.player
	bonus: i64
	switch pk.kind {
	case .Heart:
		if p.hp < p.max_hp {
			p.hp += 1
		} else {
			bonus = 50
		}
	case .Spread:
		p.power[.Spread] = POWER_DURATION
	case .Rapid:
		p.power[.Rapid] = POWER_DURATION
	case .Pierce:
		p.power[.Pierce] = POWER_DURATION
	}
	w.score += bonus
	emit(w, Event{kind = .Pickup_Taken, pos = pk.pos, pickup = pk.kind, value = bonus})
}

// The wave director: calm, fight, and the short outros before the result.
@(private)
update_director :: proc(w: ^World, dt: f32) {
	switch w.phase {
	case .Calm:
		calm := FIRST_CALM if w.wave == 0 else CALM_TIME
		if w.phase_time >= calm {
			start_wave(w)
		}
	case .Fight:
		w.spawn_timer -= dt
		if w.queue_next < w.queue_len && w.spawn_timer <= 0 {
			spawn_batch(w)
		}
		if w.queue_next >= w.queue_len && w.enemies.count == 0 && w.spawns.count == 0 {
			finish_wave(w)
		}
	case .Victory:
		if w.phase_time >= VICTORY_TIME {
			w.status = .Won
		}
	case .Defeat:
		if w.phase_time >= DEFEAT_TIME {
			w.status = .Lost
		}
	}
}

is_boss_wave :: proc(w: ^World, wave: int) -> bool {
	return wave == w.tuning.waves
}

@(private)
start_wave :: proc(w: ^World) {
	w.wave += 1
	w.phase = .Fight
	w.phase_time = 0
	w.wave_hurt = false
	w.spawn_timer = 1.0
	w.wave_killed = 0
	build_wave(w)
	emit(w, Event{kind = .Wave_Start, value = i64(w.wave), flag = is_boss_wave(w, w.wave)})
}

@(private)
finish_wave :: proc(w: ^World) {
	perfect := !w.wave_hurt
	bonus := i64(150 * w.wave)
	if perfect {
		bonus *= 2
		w.perfect_waves += 1
	}
	w.score += bonus
	clear_orbs(w)
	emit(w, Event{kind = .Wave_Clear, pos = w.player.pos, value = bonus, flag = perfect})
	w.phase_time = 0
	if w.wave >= w.tuning.waves {
		w.phase = .Victory
		win := i64(w.player.hp) * 200
		w.score += win
		emit(w, Event{kind = .Victory, pos = w.player.pos, value = win})
		return
	}
	w.phase = .Calm
	// A reward waits in the ritual circle: hearts when hurt, otherwise a power.
	reward := Pickup_Kind.Heart
	if w.player.hp >= w.player.max_hp {
		reward = Pickup_Kind(1 + rng.int_range(&w.wave_rng, 0, 2))
	}
	drop_pickup(w, reward, player_start())
}

// Squared distance helper used by AI and the bot.
dist2 :: proc "contextless" (a, b: Vec2) -> f32 {
	d := b - a
	return d.x*d.x + d.y*d.y
}

open_cell :: proc(w: ^World, x, y: int) -> bool {
	return physics.tile_at(&w.tiles, x, y) == .Empty
}

open_at :: proc(w: ^World, p: Vec2) -> bool {
	c := physics.cell_of(&w.tiles, p)
	return open_cell(w, c.x, c.y)
}

cell_center :: proc "contextless" (x, y: int) -> Vec2 {
	return Vec2{(f32(x) + 0.5) * TILE, (f32(y) + 0.5) * TILE}
}
