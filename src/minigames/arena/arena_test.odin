package arena

import "core:math"
import "core:testing"
import host "../../engine/host"
import physics "../../engine/physics"
import pool "../../engine/pool"
import rng "../../engine/rng"

// Long simulations remain part of the default/full pre-merge suite.
@(private = "file")
ODIN_TEST_FULL :: #config(ODIN_TEST_FULL, true)

@(private = "file")
new_world :: proc(config: host.Minigame_Config) -> ^World {
	w := new(World)
	world_reset(w, config)
	return w
}

@(private = "file")
drop_world :: proc(w: ^World) {
	world_destroy(w)
	free(w)
}

// Wandering, firing and dashing input that changes every quarter second.
@(private = "file")
scripted_input :: proc(r: ^rng.Rng, step: int, current: ^Player_Input) -> Player_Input {
	if step%30 == 0 {
		angle := rng.float01(r) * 2 * math.PI
		current.move = Vec2{math.cos(angle), math.sin(angle)} * rng.float01(r)
		aim := rng.float01(r) * 2 * math.PI
		current.aim = Vec2{math.cos(aim), math.sin(aim)}
		current.fire = rng.chance(r, 0.8)
	}
	result := current^
	result.dash = rng.chance(r, 0.01)
	return result
}

// Kills everything that spawns, so a round can be driven to its end quickly.
@(private = "file")
kill_all :: proc(w: ^World) {
	it := pool.iterator(&w.enemies)
	for e, h in pool.next(&it) {
		damage_enemy(w, h, e, 10000, {1, 0})
	}
}

@(private = "file")
run_bot :: proc(w: ^World, max_seconds: f32) -> host.Round_Status {
	status := w.status
	for _ in 0..<int(max_seconds*SIM_HZ) {
		status = world_step(w, bot_input(w), SIM_DT)
		events_clear(w)
		if status != .Playing {
			break
		}
	}
	return status
}

@(test)
test_generation_is_valid_for_many_seeds :: proc(t: ^testing.T) {
	w := new(World)
	defer drop_world(w)
	layouts_with_obstacles := 0
	for seed in u64(1)..=80 {
		world_reset(w, {seed = seed})
		for x in 0..<MAP_W {
			testing.expect(t, !open_cell(w, x, 0) && !open_cell(w, x, MAP_H-1))
		}
		for y in 0..<MAP_H {
			testing.expect(t, !open_cell(w, 0, y) && !open_cell(w, MAP_W-1, y))
		}
		testing.expect(t, open_at(w, w.player.pos), "player starts on open floor")
		start := physics.cell_of(&w.tiles, w.player.pos)
		reached := flood_from(w, {start.x, start.y})
		open_count, reached_count := 0, 0
		for y in 0..<MAP_H {
			for x in 0..<MAP_W {
				if open_cell(w, x, y) {
					open_count += 1
					if reached[y*MAP_W+x] {
						reached_count += 1
					}
				}
			}
		}
		testing.expectf(t, open_count == reached_count, "seed %d: every open cell is reachable", seed)
		testing.expect(t, w.portal_count == MAX_PORTALS)
		for i in 0..<w.portal_count {
			testing.expectf(t, open_at(w, w.portals[i]), "seed %d: portal %d on open floor", seed, i)
			testing.expect(t, dist2(w.portals[i], w.player.pos) > 200*200)
		}
		// No one-cell gaps: every open cell next to an obstacle has open room
		// for the boss, i.e. a solid cell never sits exactly two cells from
		// another solid cell of a different obstacle across a single gap.
		for y in 1..<MAP_H-1 {
			for x in 1..<MAP_W-1 {
				if !open_cell(w, x, y) {
					continue
				}
				pinched_x := !open_cell(w, x-1, y) && !open_cell(w, x+1, y)
				pinched_y := !open_cell(w, x, y-1) && !open_cell(w, x, y+1)
				testing.expectf(t, !pinched_x && !pinched_y, "seed %d: one-cell corridor at %d,%d", seed, x, y)
			}
		}
		if w.obstacle_cells > 0 {
			layouts_with_obstacles += 1
		}
	}
	testing.expect(t, layouts_with_obstacles >= 75, "almost every layout has pillars")
}

@(test)
test_layouts_differ_between_seeds :: proc(t: ^testing.T) {
	a := new_world({seed = 11})
	defer drop_world(a)
	b := new_world({seed = 12})
	defer drop_world(b)
	c := new_world({seed = 11})
	defer drop_world(c)
	differ := false
	for i in 0..<len(a.tiles.cells.cells) {
		testing.expect(t, a.tiles.cells.cells[i] == c.tiles.cells.cells[i])
		if a.tiles.cells.cells[i] != b.tiles.cells.cells[i] {
			differ = true
		}
	}
	testing.expect(t, differ)
}

@(test)
test_same_seed_and_inputs_are_deterministic :: proc(t: ^testing.T) {
	config := host.Minigame_Config{seed = 4242}
	a := new_world(config)
	defer drop_world(a)
	b := new_world(config)
	defer drop_world(b)
	ra := rng.create(9)
	rb := rng.create(9)
	ia, ib: Player_Input
	for step in 0..<9000 {
		world_step(a, scripted_input(&ra, step, &ia), SIM_DT)
		world_step(b, scripted_input(&rb, step, &ib), SIM_DT)
		events_clear(a)
		events_clear(b)
	}
	testing.expect_value(t, a.score, b.score)
	testing.expect_value(t, a.steps, b.steps)
	testing.expect_value(t, a.wave, b.wave)
	testing.expect_value(t, a.kills, b.kills)
	testing.expect_value(t, a.player.pos, b.player.pos)
	testing.expect_value(t, a.player.hp, b.player.hp)
	testing.expect_value(t, a.status, b.status)
	testing.expect_value(t, a.ai_rng.state, b.ai_rng.state)
	testing.expect_value(t, a.enemies.count, b.enemies.count)
	for i in 0..<MAX_ENEMIES {
		testing.expect_value(t, a.enemies.alive[i], b.enemies.alive[i])
		if a.enemies.alive[i] {
			testing.expect_value(t, a.enemies.items[i].pos, b.enemies.items[i].pos)
			testing.expect_value(t, a.enemies.items[i].hp, b.enemies.items[i].hp)
		}
	}
	testing.expect(t, a.kills > 0, "the scripted run fought something")
}

@(test)
test_bot_wins_challenge_rounds :: proc(t: ^testing.T) {
	w := new(World)
	defer drop_world(w)
	wins := 0
	for seed in u64(1)..=4 {
		world_reset(w, {seed = seed, challenge = true})
		status := run_bot(w, 240)
		if status == .Won {
			wins += 1
			score, stars := world_score(w)
			testing.expect(t, score > 0)
			testing.expect(t, stars >= 1)
		}
	}
	testing.expectf(t, wins >= 3, "bot won %d of 4 challenges", wins)
}

@(test)
test_driven_full_round_reaches_victory :: proc(t: ^testing.T) {
	w := new_world({seed = 77})
	defer drop_world(w)
	boss_seen := false
	for _ in 0..<SIM_HZ*600 {
		world_step(w, {}, SIM_DT)
		if pool.valid(&w.enemies, w.boss) {
			boss_seen = true
		}
		kill_all(w)
		events_clear(w)
		if w.status != .Playing {
			break
		}
	}
	testing.expect_value(t, w.status, host.Round_Status.Won)
	testing.expect_value(t, w.wave, w.tuning.waves)
	testing.expect(t, boss_seen, "the last wave brings the boss")
	score, stars := world_score(w)
	testing.expect(t, score > 0)
	testing.expect(t, w.best_combo > 0)
	// Untouched: the hearts star is guaranteed, the combo star depends on pacing.
	expected := u8(3) if w.best_combo >= w.tuning.combo_goal else u8(2)
	testing.expect_value(t, stars, expected)
	testing.expect_value(t, w.perfect_waves, w.tuning.waves)
	testing.expect_value(t, w.player.hp, w.player.max_hp)
}

@(test)
test_idle_player_loses :: proc(t: ^testing.T) {
	w := new_world({seed = 5})
	defer drop_world(w)
	died := false
	for _ in 0..<SIM_HZ*180 {
		world_step(w, {}, SIM_DT)
		for i in 0..<w.event_count {
			if w.events[i].kind == .Player_Died {
				died = true
			}
		}
		events_clear(w)
		if w.status != .Playing {
			break
		}
	}
	testing.expect(t, died)
	testing.expect_value(t, w.status, host.Round_Status.Lost)
	testing.expect_value(t, w.player.hp, 0)
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(0))
}

@(test)
test_wave_plans_cover_every_archetype :: proc(t: ^testing.T) {
	configs := [?]host.Minigame_Config{
		{seed = 1},
		{seed = 2},
		{seed = 3},
		{seed = 4, challenge = true},
		{seed = 5, challenge = true},
		{seed = 6, challenge = true},
	}
	w := new(World)
	defer drop_world(w)
	for config in configs {
		world_reset(w, config)
		seen: bit_set[Enemy_Kind]
		previous_cost := 0
		for wave in 1..=w.tuning.waves {
			w.wave = wave
			build_wave(w)
			testing.expect(t, w.queue_len > 0 && w.queue_len <= MAX_QUEUE)
			cost := 0
			bosses := 0
			for i in 0..<w.queue_len {
				kind := w.queue[i]
				seen += {kind}
				cost += enemy_stats(kind).cost
				testing.expect(t, kind != .Shard, "shards only come from splitters")
				if kind == .Boss {
					bosses += 1
					testing.expect(t, i == 0, "the boss opens its wave")
				}
			}
			testing.expect_value(t, bosses, 1 if wave == w.tuning.waves else 0)
			if wave < w.tuning.waves {
				// Costlier archetypes mean fewer bodies, but the budget only grows.
				testing.expectf(t, cost+2 >= previous_cost, "wave %d spends %d after %d", wave, cost, previous_cost)
				previous_cost = cost
			}
		}
		testing.expect(t, seen >= {.Chaser, .Caster, .Charger, .Splitter, .Boss}, "every archetype appears")
	}
	free_play := tuning_for({})
	challenge := tuning_for({challenge = true})
	testing.expect(t, challenge.waves < free_play.waves, "challenges are shorter")
	testing.expect_value(t, free_play.waves, 8)
	testing.expect_value(t, challenge.waves, 4)
}

@(test)
test_combo_grows_scores_and_expires :: proc(t: ^testing.T) {
	w := new_world({seed = 3})
	defer drop_world(w)
	w.phase = .Fight
	w.queue_len = 0
	for i in 0..<10 {
		h, ok := create_enemy(w, .Chaser, cell_center(4+i, 4))
		testing.expect(t, ok)
		e := pool.get(&w.enemies, h)
		damage_enemy(w, h, e, 100, {1, 0})
	}
	testing.expect_value(t, w.combo, 10)
	testing.expect_value(t, combo_multiplier(w.combo), i64(3))
	// 4 kills at x1, 5 at x2, the tenth at x3.
	testing.expect_value(t, w.score, i64(4*10+5*20+30))
	for _ in 0..<int(COMBO_WINDOW*SIM_HZ)+2 {
		world_step(w, {}, SIM_DT)
		events_clear(w)
	}
	testing.expect_value(t, w.combo, 0)
	testing.expect_value(t, w.best_combo, 10)
}

@(test)
test_dash_passes_through_orbs :: proc(t: ^testing.T) {
	w := new_world({seed = 8})
	defer drop_world(w)
	p := &w.player
	fire_orb(w, p.pos+{30, 0}, {-1, 0}, 200)
	world_step(w, {move = {0, 1}, dash = true}, SIM_DT)
	for _ in 0..<30 {
		world_step(w, {}, SIM_DT)
	}
	testing.expect_value(t, p.hp, p.max_hp)
	// Without the dash the same orb lands.
	fire_orb(w, p.pos+{30, 0}, {-1, 0}, 200)
	for _ in 0..<60 {
		world_step(w, {}, SIM_DT)
	}
	testing.expect_value(t, p.hp, p.max_hp-1)
	testing.expect(t, p.invuln > 0)
}

@(test)
test_splitter_bursts_into_shards :: proc(t: ^testing.T) {
	w := new_world({seed = 21})
	defer drop_world(w)
	h, _ := create_enemy(w, .Splitter, cell_center(6, 6))
	damage_enemy(w, h, pool.get(&w.enemies, h), 100, {1, 0})
	shards := 0
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		if e.kind == .Shard {
			shards += 1
		}
	}
	testing.expect_value(t, shards, 3)
}

@(test)
test_stars_follow_the_rules :: proc(t: ^testing.T) {
	w := new_world({seed = 1})
	defer drop_world(w)
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(0))
	w.status = .Won
	w.player.hp = 1
	w.best_combo = 0
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(1))
	w.player.hp = w.player.max_hp
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(2))
	w.best_combo = w.tuning.combo_goal
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(3))
}

@(test)
test_important_events_survive_a_full_buffer :: proc(t: ^testing.T) {
	w := new_world({seed = 2})
	defer drop_world(w)
	for _ in 0..<MAX_EVENTS {
		emit(w, Event{kind = .Orb_Pop})
	}
	emit(w, Event{kind = .Wave_Clear})
	testing.expect_value(t, w.events[w.event_count-1].kind, Event_Kind.Wave_Clear)
	testing.expect(t, w.events_dropped > 0)
}

@(test)
test_sprite_rows_are_rectangular :: proc(t: ^testing.T) {
	for id in Sprite_Id {
		first := sprite_rows(id, 0)
		testing.expect(t, len(first) > 0 && len(first[0]) > 0)
		for f in 0..<sprite_frame_count(id) {
			rows := sprite_rows(id, f)
			testing.expectf(t, len(rows) == len(first), "%v frame %d has %d rows", id, f, len(rows))
			for row in rows {
				testing.expectf(t, len(row) == len(first[0]), "%v frame %d: row %q", id, f, row)
			}
		}
	}
}

when ODIN_TEST_FULL {
	@(test)
	test_random_input_soak :: proc(t: ^testing.T) {
		w := new(World)
		defer drop_world(w)
		r := rng.create(1234)
		current: Player_Input
		seed := u64(100)
		world_reset(w, {seed = seed})
		last_score := i64(0)
		rounds := 1
		for step in 0..<60000 {
			input := scripted_input(&r, step, &current)
			// Every few seconds let the bot drive, so later waves get exercised too.
			if (step/1200)%2 == 1 {
				input = bot_input(w)
			}
			status := world_step(w, input, SIM_DT)
			testing.expect(t, w.event_count <= MAX_EVENTS)
			events_clear(w)
			p := &w.player
			if !open_at(w, p.pos) || p.pos.x < 0 || p.pos.y < 0 || p.pos.x > WORLD_W || p.pos.y > WORLD_H {
				testing.expectf(t, false, "step %d: player escaped to %v", step, p.pos)
				return
			}
			testing.expect(t, p.hp >= 0 && p.hp <= p.max_hp)
			testing.expect(t, w.score >= last_score, "score never decreases")
			last_score = w.score
			testing.expect(t, w.combo >= 0 && w.best_combo >= w.combo)
			testing.expect(t, w.wave <= w.tuning.waves)
			testing.expect(t, w.queue_next <= w.queue_len && w.queue_len <= MAX_QUEUE)
			testing.expect(t, w.enemies.count <= MAX_ENEMIES && w.bullets.count <= MAX_BULLETS)
			testing.expect(t, w.orbs.count <= MAX_ORBS && w.pickups.count <= MAX_PICKUPS && w.spawns.count <= MAX_SPAWNS)
			it := pool.iterator(&w.enemies)
			for e in pool.next(&it) {
				if !open_at(w, e.pos) {
					testing.expectf(t, false, "step %d: %v inside a wall at %v", step, e.kind, e.pos)
					return
				}
				testing.expect(t, e.hp > 0)
			}
			if status != .Playing {
				testing.expectf(t, w.spawn_failures == 0, "seed %d: enemy or spawn pool overflowed", seed)
				seed += 1
				world_reset(w, {seed = seed, challenge = seed%2 == 0})
				last_score = 0
				rounds += 1
			}
		}
		testing.expect_value(t, w.spawn_failures, 0)
		testing.expect(t, rounds >= 1)
	}
}
