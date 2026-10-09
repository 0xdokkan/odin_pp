// Enemy archetypes, their telegraphed attacks and the wave composition.
package arena

import "core:math"
import physics "../../engine/physics"
import pool "../../engine/pool"
import rng "../../engine/rng"

Enemy_Kind :: enum u8 {
	Chaser,   // swarm imp: fast, fragile
	Caster,   // keeps its distance and lobs slow orbs
	Charger,  // armoured brute with a telegraphed charge
	Splitter, // magma slime that bursts into shards
	Shard,    // the splitter's offspring
	Boss,     // last wave: the Ember Lord
}

Enemy_State :: enum u8 {
	Move,
	Windup,
	Attack,
	Stunned,
	Recover,
}

Boss_Move :: enum u8 {
	Burst,
	Fan,
	Summon,
	Charge,
}

Enemy :: struct {
	kind:     Enemy_Kind,
	state:    Enemy_State,
	pos:      Vec2,
	prev:     Vec2,
	vel:      Vec2,
	knock:    Vec2,
	facing:   Vec2,
	hp:       f32,
	max_hp:   f32,
	radius:   f32,
	timer:    f32,
	cooldown: f32,
	flash:    f32,
	age:      f32,
	strafe:   f32,
	volleys:  int,
	move:     Boss_Move,
	enraged:  bool,
	id:       u32,
}

// Seconds an enemy blinks white after a hit.
HIT_FLASH :: f32(0.07)

Enemy_Stats :: struct {
	hp:      f32,
	radius:  f32,
	speed:   f32,
	score:   i64,
	contact: int,
	knock:   f32, // knockback taken per hit, 1 = light
	cost:    int, // wave budget
}

enemy_stats :: proc "contextless" (kind: Enemy_Kind) -> Enemy_Stats {
	switch kind {
	case .Chaser:
		return {hp = 2, radius = 9, speed = 138, score = 10, contact = 1, knock = 1, cost = 1}
	case .Caster:
		return {hp = 4, radius = 10, speed = 82, score = 30, contact = 1, knock = 0.9, cost = 3}
	case .Charger:
		return {hp = 11, radius = 14, speed = 54, score = 60, contact = 1, knock = 0.25, cost = 5}
	case .Splitter:
		return {hp = 5, radius = 13, speed = 80, score = 25, contact = 1, knock = 0.6, cost = 3}
	case .Shard:
		return {hp = 1, radius = 7, speed = 150, score = 5, contact = 1, knock = 1.2, cost = 1}
	case .Boss:
		return {hp = 80, radius = 26, speed = 50, score = 1500, contact = 2, knock = 0.05, cost = 0}
	}
	return {}
}

enemy_name :: proc "contextless" (kind: Enemy_Kind) -> string {
	switch kind {
	case .Chaser:
		return "Spiritelli di brace"
	case .Caster:
		return "Streghe di cenere"
	case .Charger:
		return "Bruti d'ossidiana"
	case .Splitter:
		return "Melme ardenti"
	case .Shard:
		return "Gocce di magma"
	case .Boss:
		return "Il Signore delle Braci"
	}
	return ""
}

// Telegraph length before a spawn rune releases its enemy.
spawn_delay :: proc "contextless" (kind: Enemy_Kind) -> f32 {
	#partial switch kind {
	case .Boss:
		return 2.2
	case .Charger:
		return 1.1
	}
	return 0.9
}

@(private)
create_enemy :: proc(w: ^World, kind: Enemy_Kind, pos: Vec2) -> (pool.Handle, bool) {
	stats := enemy_stats(kind)
	hp := stats.hp
	if kind == .Boss {
		hp = w.tuning.boss_hp
	}
	w.next_id += 1
	e := Enemy{
		kind   = kind,
		pos    = pos,
		prev   = pos,
		facing = {1, 0},
		hp     = hp,
		max_hp = hp,
		radius = stats.radius,
		strafe = 1 if rng.chance(&w.ai_rng, 0.5) else -1,
		id     = w.next_id,
	}
	#partial switch kind {
	case .Caster:
		e.cooldown = rng.float_range(&w.ai_rng, 0.8, 1.8)
	case .Charger:
		e.cooldown = rng.float_range(&w.ai_rng, 0.8, 1.6)
	case .Boss:
		e.timer = 1.4
	}
	h, ok := pool.insert(&w.enemies, e)
	if !ok {
		w.spawn_failures += 1
		return pool.INVALID, false
	}
	if kind == .Boss {
		w.boss = h
	}
	return h, true
}

// Moves toward the player: straight when in sight, otherwise down the flow field.
@(private)
steer_to_player :: proc(w: ^World, e: ^Enemy) -> Vec2 {
	to := w.player.pos - e.pos
	if physics.line_of_sight(&w.tiles, e.pos, w.player.pos) {
		return physics.normalize2(to)
	}
	dir := flow_direction(w, e.pos)
	if dir == {} {
		return physics.normalize2(to)
	}
	return dir
}

@(private)
update_enemies :: proc(w: ^World, dt: f32) {
	p := &w.player
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		e.prev = e.pos
		e.age += dt
		e.flash = max(e.flash-dt, 0)
		stats := enemy_stats(e.kind)
		speed := stats.speed * w.tuning.enemy_speed
		if w.phase == .Defeat {
			e.vel *= max(1-6*dt, 0)
		} else {
			switch e.kind {
			case .Chaser, .Shard:
				dir := steer_to_player(w, e)
				// A sideways wobble keeps the swarm from moving as one blob.
				side := Vec2{-dir.y, dir.x} * math.sin(e.age*4.5+f32(e.id)) * 0.45
				e.vel = physics.normalize2(dir+side) * speed
			case .Splitter:
				// Slimes hop: speed pulses with the squash of the sprite.
				hop := max(math.sin(e.age*5.5), 0)
				e.vel = steer_to_player(w, e) * speed * (0.25 + 1.2*hop)
			case .Caster:
				update_caster(w, e, speed, dt)
			case .Charger:
				update_charger(w, e, speed, dt)
			case .Boss:
				update_boss(w, e, speed, dt)
			}
		}
		e.knock *= max(1-10*dt, 0)
		intended := (e.vel + e.knock) * dt
		before := e.pos
		e.pos += intended
		physics.resolve_circle_tiles(&w.tiles, &e.pos, e.radius)
		charging := e.state == .Attack && (e.kind == .Charger || (e.kind == .Boss && e.move == .Charge))
		if charging && e.age > 0.1 {
			moved := physics.length2(e.pos - before)
			if moved < physics.length2(intended)*0.5 {
				wall_slam(w, e)
			}
		}
		if !p.alive || !physics.circles_overlap(e.pos, e.radius, p.pos, PLAYER_RADIUS) {
			continue
		}
		if p.invuln <= 0 && w.phase != .Victory {
			damage := stats.contact
			if charging {
				damage += 1
			}
			hurt_player(w, damage, e.pos)
			e.knock -= physics.normalize2(p.pos-e.pos) * 220 * stats.knock
		}
		// Enemies never stand inside the player, invulnerable or not.
		e.pos += physics.circle_push(p.pos, PLAYER_RADIUS, e.pos, e.radius)
		physics.resolve_circle_tiles(&w.tiles, &e.pos, e.radius)
	}
}

@(private)
update_caster :: proc(w: ^World, e: ^Enemy, speed: f32, dt: f32) {
	to := w.player.pos - e.pos
	dist := physics.length2(to)
	dir := physics.normalize2(to)
	los := physics.line_of_sight(&w.tiles, e.pos, w.player.pos)
	perp := Vec2{-dir.y, dir.x} * e.strafe
	switch e.state {
	case .Move:
		desired: Vec2
		if !los || dist > 330 {
			desired = steer_to_player(w, e)
		} else if dist < 190 {
			desired = physics.normalize2(-dir + perp*0.6)
		} else {
			desired = perp * 0.8
		}
		e.vel = desired * speed
		e.cooldown -= dt
		if e.cooldown <= 0 && los && dist < 500 {
			e.state = .Windup
			e.timer = 0.6
			e.facing = dir
			emit(w, Event{kind = .Windup, pos = e.pos, enemy = e.kind})
		}
		if rng.chance(&w.ai_rng, dt*0.4) {
			e.strafe = -e.strafe
		}
	case .Windup:
		e.vel *= 0.85
		e.facing = dir
		e.timer -= dt
		if e.timer <= 0 {
			shots := w.tuning.caster_shots
			for i in 0..<shots {
				angle := math.atan2(dir.y, dir.x) + (f32(i)-f32(shots-1)*0.5)*0.32
				fire_orb(w, e.pos+dir*(e.radius+4), Vec2{math.cos(angle), math.sin(angle)}, 185)
			}
			emit(w, Event{kind = .Enemy_Fire, pos = e.pos, dir = dir, enemy = e.kind})
			e.state = .Move
			e.cooldown = rng.float_range(&w.ai_rng, 1.7, 2.5) * w.tuning.cast_interval
		}
	case .Attack, .Stunned, .Recover:
		e.state = .Move
	}
}

@(private)
update_charger :: proc(w: ^World, e: ^Enemy, speed: f32, dt: f32) {
	to := w.player.pos - e.pos
	dist := physics.length2(to)
	dir := physics.normalize2(to)
	switch e.state {
	case .Move:
		e.vel = steer_to_player(w, e) * speed
		e.cooldown -= dt
		if e.cooldown <= 0 && dist < 340 && physics.line_of_sight(&w.tiles, e.pos, w.player.pos) {
			e.state = .Windup
			e.timer = 0.8
			e.facing = dir
			emit(w, Event{kind = .Windup, pos = e.pos, enemy = e.kind})
		}
	case .Windup:
		e.vel *= 0.8
		// Tracks the player first, then commits: the last beat is the dodge window.
		if e.timer > 0.3 {
			e.facing = dir
		}
		e.timer -= dt
		if e.timer <= 0 {
			e.state = .Attack
			e.timer = 0.85
			emit(w, Event{kind = .Charge, pos = e.pos, dir = e.facing, enemy = e.kind})
		}
	case .Attack:
		e.vel = e.facing * 470 * w.tuning.enemy_speed
		e.timer -= dt
		if e.timer <= 0 {
			e.state = .Recover
			e.timer = 0.45
		}
	case .Stunned, .Recover:
		e.vel *= 0.85
		e.timer -= dt
		if e.timer <= 0 {
			e.state = .Move
			e.cooldown = rng.float_range(&w.ai_rng, 1.4, 2.2)
		}
	}
}

@(private)
boss_windup :: proc "contextless" (move: Boss_Move) -> f32 {
	switch move {
	case .Burst:
		return 0.9
	case .Fan:
		return 0.6
	case .Summon:
		return 0.8
	case .Charge:
		return 0.95
	}
	return 0.8
}

@(private)
update_boss :: proc(w: ^World, e: ^Enemy, speed: f32, dt: f32) {
	to := w.player.pos - e.pos
	dir := physics.normalize2(to)
	pace := f32(1.25) if e.enraged else 1
	switch e.state {
	case .Move:
		e.vel = steer_to_player(w, e) * speed * pace
		e.timer -= dt
		if e.timer <= 0 {
			e.move = pick_boss_move(w, e)
			e.state = .Windup
			e.timer = boss_windup(e.move) / pace
			e.facing = dir
			emit(w, Event{kind = .Windup, pos = e.pos, enemy = e.kind, value = i64(e.move)})
		}
	case .Windup:
		e.vel *= 0.85
		if e.move == .Charge && e.timer > 0.3 {
			e.facing = dir
		}
		e.timer -= dt
		if e.timer <= 0 {
			e.state = .Attack
			e.cooldown = 0
			switch e.move {
			case .Burst:
				e.volleys = 3 if e.enraged else 2
			case .Fan:
				e.volleys = 4 if e.enraged else 3
			case .Summon:
				boss_summon(w, e)
				e.volleys = 0
			case .Charge:
				e.timer = 1.0
				emit(w, Event{kind = .Charge, pos = e.pos, dir = e.facing, enemy = e.kind})
			}
		}
	case .Attack:
		switch e.move {
		case .Burst, .Fan:
			e.vel *= 0.9
			e.cooldown -= dt
			if e.cooldown <= 0 && e.volleys > 0 {
				if e.move == .Burst {
					count := w.tuning.boss_ring
					offset := f32(e.volleys) * math.PI / f32(count)
					for i in 0..<count {
						angle := offset + f32(i)*2*math.PI/f32(count)
						fire_orb(w, e.pos, Vec2{math.cos(angle), math.sin(angle)}, 140, true)
					}
					e.cooldown = 0.38
				} else {
					base := math.atan2(dir.y, dir.x)
					for i in 0..<5 {
						angle := base + (f32(i)-2)*0.16
						fire_orb(w, e.pos+dir*e.radius, Vec2{math.cos(angle), math.sin(angle)}, 195)
					}
					e.cooldown = 0.24
				}
				e.volleys -= 1
				emit(w, Event{kind = .Enemy_Fire, pos = e.pos, dir = dir, enemy = e.kind})
			}
			if e.volleys == 0 && e.cooldown <= 0 {
				e.state = .Recover
				e.timer = 0.6
			}
		case .Summon:
			e.state = .Recover
			e.timer = 0.5
		case .Charge:
			e.vel = e.facing * 500 * pace * w.tuning.enemy_speed
			e.timer -= dt
			if e.timer <= 0 {
				e.state = .Recover
				e.timer = 0.5
			}
		}
	case .Stunned, .Recover:
		e.vel *= 0.85
		e.timer -= dt
		if e.timer <= 0 {
			e.state = .Move
			e.timer = rng.float_range(&w.ai_rng, 0.9, 1.5) / pace
		}
	}
}

@(private)
pick_boss_move :: proc(w: ^World, e: ^Enemy) -> Boss_Move {
	weights := [Boss_Move]int{
		.Burst  = 4,
		.Fan    = 4,
		.Summon = 2,
		.Charge = 3,
	}
	// Never the same move twice in a row, and no summons into a crowded arena.
	if e.age > 2 {
		weights[e.move] = 0
	}
	if w.enemies.count+w.spawns.count >= w.tuning.alive_cap-3 {
		weights[.Summon] = 0
	}
	if !physics.line_of_sight(&w.tiles, e.pos, w.player.pos) {
		weights[.Charge] = 0
	}
	list := [4]int{weights[.Burst], weights[.Fan], weights[.Summon], weights[.Charge]}
	index, ok := rng.weighted_index(&w.ai_rng, list[:])
	if !ok {
		return .Burst
	}
	return Boss_Move(index)
}

@(private)
boss_summon :: proc(w: ^World, e: ^Enemy) {
	count := 3 + clamp(w.config.difficulty, 0, 2) / 2
	for i in 0..<count {
		angle := f32(i)*2*math.PI/f32(count) + rng.float01(&w.ai_rng)
		pos := e.pos + Vec2{math.cos(angle), math.sin(angle)} * (e.radius + 34)
		if !open_at(w, pos) {
			continue
		}
		add_spawn(w, .Chaser, pos, 0.7)
	}
}

@(private)
wall_slam :: proc(w: ^World, e: ^Enemy) {
	e.state = .Stunned
	e.timer = 1.2 if e.kind == .Boss else 1.0
	e.vel = {}
	e.knock = -e.facing * 120
	emit(w, Event{kind = .Wall_Slam, pos = e.pos + e.facing*e.radius, dir = e.facing, enemy = e.kind})
	if e.kind == .Boss {
		count := w.tuning.boss_ring - 4
		for i in 0..<count {
			angle := f32(i) * 2 * math.PI / f32(count)
			fire_orb(w, e.pos, Vec2{math.cos(angle), math.sin(angle)}, 120, true)
		}
	}
}

@(private)
separate_enemies :: proc(w: ^World) {
	p := &w.enemies
	for i in 0..<p.high_water {
		if !p.alive[i] {
			continue
		}
		a := &p.items[i]
		for j in i+1..<p.high_water {
			if !p.alive[j] {
				continue
			}
			b := &p.items[j]
			push := physics.circle_push(a.pos, a.radius, b.pos, b.radius)
			if push == {} {
				continue
			}
			// Heavier (larger) enemies yield less.
			wa := b.radius / (a.radius + b.radius)
			a.pos -= push * wa * 0.5
			b.pos += push * (1 - wa) * 0.5
		}
	}
	for i in 0..<p.high_water {
		if p.alive[i] {
			physics.resolve_circle_tiles(&w.tiles, &p.items[i].pos, p.items[i].radius)
		}
	}
}

@(private)
damage_enemy :: proc(w: ^World, h: pool.Handle, e: ^Enemy, amount: f32, dir: Vec2) {
	if e.hp <= 0 {
		return
	}
	stats := enemy_stats(e.kind)
	damage := amount
	// A brute stunned against a wall is the reward for baiting its charge.
	if e.state == .Stunned {
		damage *= 2
	}
	e.hp -= damage
	e.flash = HIT_FLASH
	e.knock += dir * 170 * stats.knock
	emit(w, Event{kind = .Enemy_Hit, pos = e.pos, dir = dir, enemy = e.kind, value = i64(damage), flag = e.state == .Stunned})
	if e.kind == .Boss && !e.enraged && e.hp < e.max_hp*0.5 {
		e.enraged = true
		emit(w, Event{kind = .Boss_Enraged, pos = e.pos})
	}
	if e.hp <= 0 {
		kill_enemy(w, h, e, dir, true)
	}
}

@(private)
kill_enemy :: proc(w: ^World, h: pool.Handle, e: ^Enemy, dir: Vec2, by_player: bool) {
	stats := enemy_stats(e.kind)
	kind := e.kind
	pos := e.pos
	gained := stats.score
	if by_player {
		previous := combo_multiplier(w.combo)
		w.combo += 1
		w.best_combo = max(w.best_combo, w.combo)
		w.combo_timer = COMBO_WINDOW
		gained *= combo_multiplier(w.combo)
		if combo_multiplier(w.combo) > previous {
			emit(w, Event{kind = .Combo_Tier, pos = pos, value = combo_multiplier(w.combo)})
		}
	}
	w.score += gained
	w.kills += 1
	if kind != .Shard {
		w.wave_killed += 1
	}
	emit(w, Event{kind = .Enemy_Killed, pos = pos, dir = dir, enemy = kind, value = gained, flag = by_player})
	pool.remove(&w.enemies, h)
	if !by_player {
		return
	}
	switch kind {
	case .Splitter:
		emit(w, Event{kind = .Split, pos = pos, dir = dir})
		base := math.atan2(dir.y, dir.x)
		for i in 0..<3 {
			angle := base + (f32(i)-1)*1.2 + math.PI*0.5*rng.float_signed(&w.ai_rng)*0.3
			if sh, ok := create_enemy(w, .Shard, pos); ok {
				shard := pool.get(&w.enemies, sh)
				shard.knock = Vec2{math.cos(angle), math.sin(angle)} * 260
			}
		}
		roll_drop(w, kind, pos)
	case .Boss:
		// The lord's fall drags every minion down with him.
		w.boss = pool.INVALID
		it := pool.iterator(&w.enemies)
		for other, oh in pool.next(&it) {
			kill_enemy(w, oh, other, physics.normalize2(other.pos-pos), false)
		}
		sit := pool.iterator(&w.spawns)
		for _, sh in pool.next(&sit) {
			pool.remove(&w.spawns, sh)
		}
		w.queue_next = w.queue_len
		clear_orbs(w)
	case .Shard:
	case .Chaser, .Caster, .Charger:
		roll_drop(w, kind, pos)
	}
}

@(private)
add_spawn :: proc(w: ^World, kind: Enemy_Kind, pos: Vec2, delay: f32) -> bool {
	s := Spawn{kind = kind, pos = pos, timer = delay, total = delay}
	if _, ok := pool.insert(&w.spawns, s); !ok {
		w.spawn_failures += 1
		return false
	}
	emit(w, Event{kind = .Spawn_Warning, pos = pos, enemy = kind})
	return true
}

@(private)
update_spawns :: proc(w: ^World, dt: f32) {
	it := pool.iterator(&w.spawns)
	for s, h in pool.next(&it) {
		s.timer -= dt
		if s.timer > 0 {
			continue
		}
		kind := s.kind
		pos := s.pos
		pool.remove(&w.spawns, h)
		if w.phase == .Defeat {
			continue
		}
		// The rune is placed on open floor; nudge it clear of walls for big bodies.
		physics.resolve_circle_tiles(&w.tiles, &pos, enemy_stats(kind).radius)
		if _, ok := create_enemy(w, kind, pos); ok {
			emit(w, Event{kind = .Enemy_Spawned, pos = pos, enemy = kind})
		}
	}
}

// Spends the wave budget on archetypes unlocked so far; the newest one is
// guaranteed to appear so every wave teaches something.
@(private)
build_wave :: proc(w: ^World) {
	w.queue_len = 0
	w.queue_next = 0
	w.new_kinds = {}
	n := w.tuning.waves
	r := &w.wave_rng
	if is_boss_wave(w, w.wave) {
		push_queue(w, .Boss)
		escorts := 2 + clamp(w.config.difficulty, 0, 2)*2
		for _ in 0..<escorts {
			push_queue(w, .Chaser)
		}
		push_queue(w, .Caster)
		if !(.Boss in w.seen_kinds) {
			w.new_kinds += {.Boss}
		}
		w.seen_kinds += {.Boss, .Chaser, .Caster}
		w.wave_total = w.queue_len
		return
	}
	fighting_waves := max(n-1, 1)
	frac := f32(w.wave-1) / f32(max(fighting_waves-1, 1))
	budget := int(math.round(w.tuning.budget_low + (w.tuning.budget_high-w.tuning.budget_low)*frac))
	unlocked: bit_set[Enemy_Kind] = {.Chaser}
	if frac >= 0.15 {
		unlocked += {.Caster}
	}
	if frac >= 0.4 {
		unlocked += {.Splitter}
	}
	if frac >= 0.65 {
		unlocked += {.Charger}
	}
	// Short runs (challenges) still meet every archetype before the boss.
	if fighting_waves <= 3 && w.wave == fighting_waves {
		unlocked += {.Caster, .Splitter, .Charger}
	}
	w.new_kinds = unlocked - w.seen_kinds
	w.seen_kinds += unlocked
	for kind in Enemy_Kind {
		if kind in w.new_kinds {
			count := 2 if kind == .Caster || kind == .Splitter else 1
			for _ in 0..<count {
				budget -= enemy_stats(kind).cost
				push_queue(w, kind)
			}
		}
	}
	kinds := [4]Enemy_Kind{.Chaser, .Caster, .Splitter, .Charger}
	weights := [4]int{6, 3, 3, 2}
	for i in 0..<4 {
		if !(kinds[i] in unlocked) {
			weights[i] = 0
		}
	}
	for budget > 0 && w.queue_len < MAX_QUEUE {
		index, ok := rng.weighted_index(r, weights[:])
		if !ok {
			break
		}
		kind := kinds[index]
		cost := enemy_stats(kind).cost
		if cost > budget {
			kind = .Chaser
			cost = 1
		}
		budget -= cost
		push_queue(w, kind)
	}
	rng.shuffle(r, w.queue[:w.queue_len])
	w.wave_total = w.queue_len
}

@(private)
push_queue :: proc(w: ^World, kind: Enemy_Kind) {
	if w.queue_len < MAX_QUEUE {
		w.queue[w.queue_len] = kind
		w.queue_len += 1
	}
}

@(private)
spawn_batch :: proc(w: ^World) {
	limit := w.tuning.alive_cap
	if w.enemies.count+w.spawns.count >= limit {
		w.spawn_timer = 0.3
		return
	}
	r := &w.wave_rng
	kind := w.queue[w.queue_next]
	batch := 1
	#partial switch kind {
	case .Chaser:
		batch = rng.int_range(r, 2, 4)
	case .Boss:
		batch = 1
	case:
		batch = rng.int_range(r, 1, 2)
	}
	portal := pick_portal(w, kind == .Boss)
	for i in 0..<batch {
		if w.queue_next >= w.queue_len || w.enemies.count+w.spawns.count >= limit {
			break
		}
		k := w.queue[w.queue_next]
		if i > 0 && k == .Boss {
			break
		}
		pos := portal
		for _ in 0..<8 {
			candidate := portal + rng.unit_disc(r)*34
			if open_at(w, candidate) {
				pos = candidate
				break
			}
		}
		if !add_spawn(w, k, pos, spawn_delay(k)) {
			break
		}
		w.queue_next += 1
	}
	fighting := f32(max(w.tuning.waves-1, 1))
	frac := clamp(f32(w.wave-1)/fighting, 0, 1)
	w.spawn_timer = (1.9 - 0.8*frac) * rng.float_range(r, 0.8, 1.2)
}

// A rune far from the player, so nothing spawns on top of them.
@(private)
pick_portal :: proc(w: ^World, farthest: bool) -> Vec2 {
	far: [MAX_PORTALS]int
	count := 0
	best := 0
	best_d := f32(-1)
	for i in 0..<w.portal_count {
		d := dist2(w.portals[i], w.player.pos)
		if d > best_d {
			best_d = d
			best = i
		}
		if d >= 300*300 {
			far[count] = i
			count += 1
		}
	}
	if farthest || count == 0 {
		return w.portals[best]
	}
	return w.portals[far[rng.int_range(&w.wave_rng, 0, count-1)]]
}
