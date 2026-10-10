package platform2d

import "core:math"
import "core:testing"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"

@(private = "file")
build_single :: proc(w: ^World, def: Chunk_Def, config := host.Minigame_Config{seed = 1, difficulty = 2}) {
	sequence := [3]Chunk_Def{CHUNKS[chunk_index("soglia")], def, CHUNKS[chunk_index("altare")]}
	world_build(w, config, sequence[:])
}

@(private = "file")
Reach :: struct {
	reachable: bool,
	dead:      int,
	missed:    int,
	nodes:     int,
	dist:      f32,
}

@(private = "file")
analyse :: proc(w: ^World) -> Reach {
	g := bot_create(w).graph
	defer nav_destroy(g)
	cell, _ := resting_cell(w, w.player.ctrl.body)
	root := nav_find(g, cell)
	r := Reach{nodes = len(g.nodes), dist = g.nodes[root].dist}
	r.reachable = r.dist < INF
	for node in g.nodes {
		if node.dist == INF {
			r.dead += 1
		}
	}
	for touched in g.ember_touched {
		if !touched {
			r.missed += 1
		}
	}
	return r
}

// FNV-1a over everything that evolves during play.
@(private = "file")
world_hash :: proc(w: ^World) -> u64 {
	h := u64(0xcbf29ce484222325)
	mix_u64 :: proc(h: ^u64, v: u64) {
		x := v
		for _ in 0..<8 {
			h^ = (h^ ~ (x & 0xff)) * 0x100000001b3
			x >>= 8
		}
	}
	mix_f :: proc(h: ^u64, f: f32) {
		mix_u64(h, u64(transmute(u32)f))
	}
	b := w.player.ctrl.body
	mix_f(&h, b.position.x)
	mix_f(&h, b.position.y)
	mix_f(&h, b.velocity.x)
	mix_f(&h, b.velocity.y)
	mix_f(&h, w.time)
	mix_u64(&h, u64(w.lives))
	mix_u64(&h, u64(w.embers_collected))
	mix_u64(&h, u64(w.stomps))
	mix_u64(&h, u64(w.status))
	mix_u64(&h, u64(w.phase))
	mix_u64(&h, w.steps)
	for e in w.enemies[:w.enemy_count] {
		mix_f(&h, e.body.position.x)
		mix_f(&h, e.body.position.y)
		mix_u64(&h, u64(e.alive))
	}
	for p in w.projectiles {
		mix_f(&h, p.position.x)
		mix_u64(&h, u64(p.active))
	}
	for c in w.crumbles[:w.crumble_count] {
		mix_u64(&h, u64(c.state))
	}
	score, stars := world_score(w)
	mix_u64(&h, u64(score))
	mix_u64(&h, u64(stars))
	return h
}

@(private = "file")
random_input :: proc(r: ^rng.Rng, previous: Player_Input) -> Player_Input {
	cmd := previous
	cmd.jump_pressed = false
	cmd.dash_pressed = false
	cmd.down_pressed = false
	if rng.chance(r, 0.05) {
		cmd.move = f32(rng.int_range(r, -1, 1))
	}
	if rng.chance(r, 0.04) {
		cmd.jump_pressed = true
		cmd.jump_held = true
	}
	if rng.chance(r, 0.03) {
		cmd.jump_held = false
	}
	cmd.dash_pressed = rng.chance(r, 0.01)
	cmd.down_pressed = rng.chance(r, 0.01)
	return cmd
}

@(private = "file")
check_invariants :: proc(t: ^testing.T, w: ^World) -> bool {
	ok := true
	collected := 0
	for e in w.embers[:w.ember_count] {
		if e.collected {
			collected += 1
		}
	}
	ok &= collected == w.embers_collected
	ok &= w.lives >= 0 && w.lives <= w.max_lives
	ok &= w.hits == w.max_lives - w.lives
	ok &= w.event_count <= MAX_EVENTS
	b := w.player.ctrl.body
	size := level_size(w)
	ok &= !math.is_nan(b.position.x) && !math.is_nan(b.position.y)
	ok &= b.position.x >= -1 && b.position.x+b.size.x <= size.x+1
	ok &= b.position.y >= -1 && b.position.y <= size.y+1
	// A live, resting player never overlaps solid rock.
	if w.phase == .Alive {
		ok &= !physics.rect_hits_solid(&w.collision, physics.rect_inset(player_rect(w.player), 0.5))
	}
	if !ok {
		testing.expectf(t, false, "invariants broken at step %d", w.steps)
	}
	return ok
}

// ---------------------------------------------------------------------------
// Level content

@(test)
test_chunks_are_well_formed :: proc(t: ^testing.T) {
	starts, ends := 0, 0
	tiers: [3]int
	for def in CHUNKS {
		testing.expectf(t, chunk_valid(def), "chunk %s is malformed", def.name)
		switch def.role {
		case .Start:
			starts += 1
		case .End:
			ends += 1
		case .Middle:
			tiers[clamp(def.tier, 0, 2)] += 1
		}
		testing.expectf(t, def.par > 0, "chunk %s has no par time", def.name)
	}
	testing.expect_value(t, starts, 1)
	testing.expect_value(t, ends, 1)
	for count in tiers {
		testing.expect(t, count >= 3)
	}
}

// Every chunk, between the start and end pieces, is crossable with the real
// controller, has no dead ends, and every ember on it can be collected.
@(test)
test_every_chunk_is_completable :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	for def in CHUNKS {
		if def.role != .Middle {
			continue
		}
		build_single(w, def)
		r := analyse(w)
		testing.expectf(t, r.reachable, "%s: exit unreachable", def.name)
		testing.expectf(t, r.dead == 0, "%s: %d dead-end cells", def.name, r.dead)
		testing.expectf(t, r.missed == 0, "%s: %d unreachable embers", def.name, r.missed)
	}
}

// The solver must not be optimistic: a gap beyond the controller's reach, a
// sealed pit and an ember out of reach are all reported.
@(test)
test_solver_rejects_impossible_chunks :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	too_wide := Chunk_Def{name = "test", role = .Middle, rows = {
		"........................................",
		"####......................##############",
		"####~~~~~~~~~~~~~~~~~~~~~~##############",
		"########################################",
		"########################################",
	}}
	build_single(w, too_wide)
	r := analyse(w)
	testing.expect(t, !r.reachable)

	pit := Chunk_Def{name = "test", role = .Middle, rows = {
		"........................................",
		"..............o.........................",
		"........................................",
		"#############........###################",
		"#############........###################",
		"#############........###################",
		"#############........###################",
		"#############........###################",
		"#############........###################",
		"########################################",
	}}
	build_single(w, pit)
	r = analyse(w)
	testing.expect(t, r.reachable)
	testing.expect(t, r.dead > 0)

	high := Chunk_Def{name = "test", role = .Middle, rows = {
		"....................o...................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"........................................",
		"########################################",
	}}
	build_single(w, high)
	r = analyse(w)
	testing.expect(t, r.reachable)
	testing.expect_value(t, r.missed, 1)
}

@(test)
test_generation_is_valid_for_many_seeds :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	start, end := chunk_index("soglia"), chunk_index("altare")
	for seed in u64(1)..=40 {
		for difficulty in 0..=2 {
			for challenge in ([2]bool{false, true}) {
				config := host.Minigame_Config{seed = seed * 7919, difficulty = difficulty, challenge = challenge}
				sequence, count := generate_sequence(config)
				again, again_count := generate_sequence(config)
				testing.expect(t, sequence == again && count == again_count)
				testing.expect_value(t, count, middle_chunk_count(config)+2)
				testing.expect_value(t, sequence[0], start)
				testing.expect_value(t, sequence[count-1], end)
				last_tier := 0
				for i in 1..<count-1 {
					def := CHUNKS[sequence[i]]
					testing.expect(t, def.role == .Middle)
					// Tiers only ramp up, and no chunk repeats back to back.
					testing.expect(t, def.tier >= last_tier)
					last_tier = def.tier
					testing.expect(t, sequence[i] != sequence[i-1])
				}

				world_reset(w, config)
				testing.expect(t, w.has_spawn && w.has_exit)
				testing.expect_value(t, w.chunk_count, count)
				testing.expect(t, w.cols <= MAX_COLS)
				testing.expect(t, w.ember_count > 20)
				testing.expect(t, w.checkpoint_count >= 1)
				spawn, on_ground := resting_cell(w, w.player.ctrl.body)
				testing.expect(t, on_ground && spawn.x < 6)
				exit := cell_of_point(physics.rect_center(w.exit_rect))
				testing.expect(t, exit.x > w.cols-12 && exit.x < w.cols)
				testing.expect_value(t, w.time_limit > 0, challenge)
				testing.expect(t, w.lives == lives_for(config) && w.lives >= 3)
				for c in w.checkpoints[:w.checkpoint_count] {
					cell := cell_of_point(c.feet - {0, 1})
					testing.expect(t, standable(w, cell.x, cell.y))
				}
				if challenge {
					// Challenges are short: about a minute of par.
					testing.expect(t, w.par_time >= 40 && w.par_time <= 90)
				} else {
					testing.expect(t, w.par_time >= 50 && w.par_time <= 150)
				}
			}
		}
	}
	// Different seeds give different levels.
	a, _ := generate_sequence({seed = 1, difficulty = 1})
	differs := false
	for seed in u64(2)..=6 {
		b, _ := generate_sequence({seed = seed, difficulty = 1})
		differs |= a != b
	}
	testing.expect(t, differs)
}

@(private = "file")
cell_of_point :: proc(p: Vec2) -> [2]int {
	return {int(math.floor(p.x / TILE)), int(math.floor(p.y / TILE))}
}

// Whole generated levels, not just chunks: the exit is reachable from the
// spawn and from every checkpoint, with no dead ends and no missed embers.
@(test)
test_generated_levels_are_completable :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	configs := [3]host.Minigame_Config{{seed = 11, difficulty = 0}, {seed = 12, difficulty = 1, challenge = true},
		{seed = 13, difficulty = 2}}
	for config in configs {
		world_reset(w, config)
		g := bot_create(w).graph
		defer nav_destroy(g)
		cell, _ := resting_cell(w, w.player.ctrl.body)
		testing.expect(t, g.nodes[nav_find(g, cell)].dist < INF)
		for node in g.nodes {
			testing.expect(t, node.dist < INF)
		}
		for touched in g.ember_touched {
			testing.expect(t, touched)
		}
		for c in w.checkpoints[:w.checkpoint_count] {
			n := nav_find(g, cell_of_point(c.feet - {0, 1}))
			testing.expect(t, n >= 0 && g.nodes[n].dist < INF)
		}
	}
}

// ---------------------------------------------------------------------------
// Rules

@(test)
test_bot_wins_a_generated_level :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	for config in ([2]host.Minigame_Config{{seed = 21, difficulty = 1}, {seed = 22, difficulty = 2}}) {
		world_reset(w, config)
		// Enemies would make the scripted route a gamble; the route itself is
		// what this test proves.
		w.enemy_count = 0
		bot := bot_create(w)
		bot.snap = true
		defer bot_destroy(&bot)
		status := host.Round_Status.Playing
		for _ in 0..<STEP_HZ*300 {
			status = world_step(w, bot_input(&bot, w), SIM_DT)
			if status != .Playing {
				break
			}
		}
		testing.expect_value(t, status, host.Round_Status.Won)
		testing.expect_value(t, w.hits, 0)
		score, stars := world_score(w)
		testing.expect(t, score >= FINISH_POINTS)
		testing.expect(t, stars >= 1)
		testing.expect(t, w.finish_bonus > 0)
	}
}

@(test)
test_lava_costs_lives_until_the_round_is_lost :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	lava := Chunk_Def{name = "lava", role = .Middle, rows = {
		"........................................",
		"#########...............################",
		"#########~~~~~~~~~~~~~~~################",
		"########################################",
		"########################################",
	}}
	build_single(w, lava, {seed = 3, difficulty = 1})
	start := w.spawn
	deaths := 0
	status := host.Round_Status.Playing
	for _ in 0..<STEP_HZ*120 {
		status = world_step(w, Player_Input{move = 1}, SIM_DT)
		for e in w.events[:w.event_count] {
			if e.kind == .Respawn {
				deaths += 1
				// No checkpoint was lit: back to the very start.
				testing.expect_value(t, e.position, start)
			}
		}
		if status != .Playing {
			break
		}
	}
	testing.expect_value(t, status, host.Round_Status.Lost)
	testing.expect_value(t, w.lives, 0)
	testing.expect_value(t, w.falls, w.max_lives)
	testing.expect_value(t, deaths, w.max_lives-1)
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(0))
}

@(test)
test_challenge_time_limit_loses :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	world_reset(w, {seed = 9, difficulty = 1, challenge = true})
	testing.expect(t, w.time_limit > 30)
	w.enemy_count = 0
	status := host.Round_Status.Playing
	for _ in 0..<int(w.time_limit+5)*STEP_HZ {
		status = world_step(w, {}, SIM_DT)
		if status != .Playing {
			break
		}
	}
	testing.expect_value(t, status, host.Round_Status.Lost)
	testing.expect(t, w.timed_out)
	testing.expect_value(t, w.lives, w.max_lives)
}

@(private = "file")
step_until :: proc(w: ^World, cmd: Player_Input, steps: int, kind: Event_Kind) -> bool {
	for _ in 0..<steps {
		world_step(w, cmd, SIM_DT)
		for e in w.events[:w.event_count] {
			if e.kind == kind {
				return true
			}
		}
	}
	return false
}

@(test)
test_stomp_bounces_and_side_contact_hurts :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	arena := Chunk_Def{name = "arena", role = .Middle, rows = {
		"........................................",
		"........................................",
		"..........g.............g...............",
		"########################################",
		"########################################",
		"########################################",
		"########################################",
	}}
	build_single(w, arena, {seed = 4, difficulty = 2})
	testing.expect_value(t, w.enemy_count, 2)
	w.player.invulnerable = 0
	// Drop the player onto the first ghoul.
	g := &w.enemies[0]
	w.player.ctrl.body.position = physics.body2_center(g.body) - {5, 40}
	w.player.ctrl.body.velocity = {}
	w.player.ctrl.grounded = false
	testing.expect(t, step_until(w, {jump_held = true}, STEP_HZ, .Stomp))
	testing.expect(t, !w.enemies[0].alive)
	testing.expect_value(t, w.stomps, 1)
	testing.expect(t, w.player.ctrl.body.velocity.y < -200)
	testing.expect_value(t, w.lives, w.max_lives)
	score, _ := world_score(w)
	testing.expect_value(t, score, i64(STOMP_POINTS))

	// Walk into the second one at ground level.
	for _ in 0..<STEP_HZ {
		world_step(w, {}, SIM_DT)
	}
	other := &w.enemies[1]
	w.player.ctrl.body.position = {other.body.position.x - 40, other.body.position.y + other.body.size.y - PLAYER_SIZE.y}
	w.player.ctrl.body.velocity = {}
	w.player.invulnerable = 0
	other.dir = -1
	testing.expect(t, step_until(w, {move = 1}, STEP_HZ*2, .Hurt))
	testing.expect_value(t, w.lives, w.max_lives-1)
	testing.expect(t, w.player.invulnerable > 0)
	testing.expect(t, w.enemies[1].alive)
	testing.expect(t, w.phase == .Alive)
	// Invulnerable: touching it again costs nothing.
	for _ in 0..<20 {
		world_step(w, {move = 1}, SIM_DT)
	}
	testing.expect_value(t, w.lives, w.max_lives-1)
}

@(test)
test_checkpoint_becomes_the_respawn_point :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	flat := Chunk_Def{name = "flat", role = .Middle, rows = {
		"........................................",
		"########################################",
		"########################################",
		"########################################",
		"########################################",
	}}
	spikes := Chunk_Def{name = "spikes", role = .Middle, rows = {
		"..............^^^^......................",
		"########################################",
		"########################################",
		"########################################",
		"########################################",
	}}
	// With easy every second middle chunk gets a checkpoint.
	sequence := [5]Chunk_Def{CHUNKS[chunk_index("soglia")], flat, flat, spikes, CHUNKS[chunk_index("altare")]}
	world_build(w, {seed = 5, difficulty = 0}, sequence[:])
	testing.expect_value(t, w.checkpoint_count, 1)
	testing.expect(t, step_until(w, {move = 1}, STEP_HZ*20, .Checkpoint))
	lit := w.checkpoints[0].feet
	testing.expect(t, step_until(w, {move = 1}, STEP_HZ*10, .Death))
	testing.expect(t, step_until(w, {}, STEP_HZ*2, .Respawn))
	testing.expect_value(t, player_feet(w.player), lit)
	testing.expect(t, w.player.invulnerable > 0)
}

@(test)
test_crumbling_blocks_fall_and_return :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	bridge := Chunk_Def{name = "bridge", role = .Middle, rows = {
		"........................................",
		"........................................",
		"........................................",
		"..............%%%%......................",
		"........................................",
		"########################################",
		"########################################",
		"########################################",
		"########################################",
	}}
	build_single(w, bridge)
	testing.expect_value(t, w.crumble_count, 4)
	c := w.crumbles[1]
	w.player.ctrl.body.position = {f32(c.x)*TILE + 3, f32(c.y)*TILE - PLAYER_SIZE.y - 2}
	w.player.ctrl.grounded = false
	testing.expect(t, step_until(w, {}, STEP_HZ, .Crumble_Shake))
	testing.expect(t, step_until(w, {}, STEP_HZ, .Crumble_Break))
	testing.expect_value(t, physics.tile_at(&w.collision, c.x, c.y), physics.Tile_Shape.Empty)
	// The player falls through to the floor, and the block comes back.
	for _ in 0..<int(CRUMBLE_RESPAWN+1)*STEP_HZ {
		world_step(w, {}, SIM_DT)
	}
	testing.expect(t, w.player.ctrl.grounded)
	testing.expect_value(t, physics.tile_at(&w.collision, c.x, c.y), physics.Tile_Shape.Solid)
	testing.expect(t, crumble_at(w, c.x, c.y).state == .Intact)
}

@(test)
test_star_rules :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	world_reset(w, {seed = 2, difficulty = 1})
	w.status = .Won
	set_embers :: proc(w: ^World, ratio: f32) {
		w.embers_collected = int(math.ceil(f32(w.ember_count) * ratio))
	}
	set_embers(w, 0.3)
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(1))
	set_embers(w, 0.6)
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(2))
	set_embers(w, 0.95)
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(3))
	w.hits = 1
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(2))
	w.status = .Lost
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(0))
}

// ---------------------------------------------------------------------------
// Determinism and robustness

@(test)
test_same_seed_and_inputs_replay_exactly :: proc(t: ^testing.T) {
	a := new(World)
	b := new(World)
	defer free(a)
	defer free(b)
	defer world_destroy(a)
	defer world_destroy(b)
	config := host.Minigame_Config{seed = 77, difficulty = 2}
	world_reset(a, config)
	world_reset(b, config)
	ra := rng.create(5)
	rb := rng.create(5)
	ca, cb: Player_Input
	for _ in 0..<STEP_HZ*60 {
		ca = random_input(&ra, ca)
		cb = random_input(&rb, cb)
		world_step(a, ca, SIM_DT)
		world_step(b, cb, SIM_DT)
	}
	testing.expect_value(t, world_hash(a), world_hash(b))
	testing.expect(t, a.steps > 0 && a.player.ctrl.body.position.x != a.spawn.x - PLAYER_SIZE.x*0.5)

	// A different seed is a different round.
	world_reset(b, {seed = 78, difficulty = 2})
	rb = rng.create(5)
	cb = {}
	for _ in 0..<STEP_HZ*60 {
		cb = random_input(&rb, cb)
		world_step(b, cb, SIM_DT)
	}
	testing.expect(t, world_hash(a) != world_hash(b))
}

@(test)
test_random_input_soak :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	for seed in u64(1)..=4 {
		config := host.Minigame_Config{seed = seed, difficulty = int(seed % 3), challenge = seed == 4}
		world_reset(w, config)
		r := rng.create(seed * 31)
		cmd: Player_Input
		for _ in 0..<40000 {
			cmd = random_input(&r, cmd)
			// Lean rightward so the walk covers the whole level.
			if cmd.move == 0 && rng.chance(&r, 0.5) {
				cmd.move = 1
			}
			status := world_step(w, cmd, SIM_DT)
			if !check_invariants(t, w) {
				return
			}
			if status != .Playing {
				testing.expect(t, w.status == status)
				// Finished rounds stay finished.
				world_step(w, cmd, SIM_DT)
				testing.expect_value(t, w.status, status)
				world_reset(w, config)
			}
		}
	}
}

// The bot playing with enemies on hard: knockbacks, deaths and crumbled
// bridges force constant re-planning; nothing may break.
@(test)
test_bot_soak_with_enemies :: proc(t: ^testing.T) {
	w := new(World)
	defer free(w)
	defer world_destroy(w)
	world_reset(w, {seed = 31, difficulty = 2})
	bot := bot_create(w)
	defer bot_destroy(&bot)
	status := host.Round_Status.Playing
	for _ in 0..<STEP_HZ*240 {
		status = world_step(w, bot_input(&bot, w), SIM_DT)
		if !check_invariants(t, w) || status != .Playing {
			break
		}
	}
	testing.expect(t, status != .Playing || w.time > 200)
	testing.expect(t, w.embers_collected > 0)
}

// The hook layer runs headless: reset, unfocused steps with hit-stop and
// pending presses, score and destroy (sprites stay unloaded without a GPU).
@(test)
test_hooks_step_headless :: proc(t: ^testing.T) {
	g := new(Game)
	game_reset(g, {seed = 6, difficulty = 1})
	frame := host.Frame{dt = 1.0 / 60}
	testing.expect_value(t, game_step(g, &frame, false), host.Round_Status.Playing)
	testing.expect_value(t, g.world.steps, u64(0))
	for _ in 0..<120 {
		game_step(g, &frame, true)
	}
	testing.expect(t, g.world.steps >= 230 && g.world.steps <= 240)
	score, stars := game_score(g)
	testing.expect(t, score >= 0 && stars == 0)
	game_reset(g, {seed = 6, difficulty = 1})
	testing.expect_value(t, g.world.steps, u64(0))
	game_destroy(g)
}
