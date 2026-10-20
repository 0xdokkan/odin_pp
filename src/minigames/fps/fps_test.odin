package fps

import rl "vendor:raylib"

import "core:math"
import "core:testing"
import gfx "../../engine/gfx"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"

// Long simulations remain part of the default/full pre-merge suite.
@(private = "file")
ODIN_TEST_FULL :: #config(ODIN_TEST_FULL, true)

@(private = "file")
DT :: f32(1.0 / SIM_HZ)

// Worlds are large: always on the heap (test threads have small stacks).
@(private = "file")
new_world :: proc(seed: u64, challenge := false) -> ^World {
	w := new(World)
	world_reset(w, host.Minigame_Config{seed = seed, challenge = challenge})
	return w
}

@(private = "file")
free_world :: proc(w: ^World) {
	world_destroy(w)
	free(w)
}

@(private = "file")
teleport :: proc(w: ^World, feet: Vec3) {
	p := &w.player
	p.body.position = Vec3{feet.x, FLOOR_Y, feet.z} - Vec3{PLAYER_SIZE.x * 0.5, 0, PLAYER_SIZE.z * 0.5}
	p.body.velocity = {}
	p.prev_eye = player_eye(p^)
}

@(private = "file")
fnv :: proc(h: ^u64, v: u32) {
	h^ = (h^ ~ u64(v)) * 0x100000001b3
}

@(private = "file")
fnv_f :: proc(h: ^u64, v: f32) {
	fnv(h, transmute(u32)v)
}

@(private = "file")
fnv_v :: proc(h: ^u64, v: Vec3) {
	fnv_f(h, v.x)
	fnv_f(h, v.y)
	fnv_f(h, v.z)
}

// Hash of everything that evolves during a round.
@(private = "file")
world_digest :: proc(w: ^World) -> u64 {
	h := u64(0xcbf29ce484222325)
	p := w.player
	fnv_v(&h, p.body.position)
	fnv_v(&h, p.body.velocity)
	fnv_f(&h, p.yaw)
	fnv_f(&h, p.pitch)
	fnv_f(&h, p.hp)
	fnv_f(&h, p.mana)
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		fnv_v(&h, e.body.position)
		fnv_f(&h, e.hp)
		fnv(&h, u32(e.state))
	}
	for pr in w.projectiles {
		if pr.alive {
			fnv_v(&h, pr.position)
		}
	}
	for i in 0..<w.pickup_count {
		fnv(&h, u32(w.pickups[i].taken))
	}
	fnv(&h, u32(w.runes_taken))
	fnv(&h, u32(w.stats.shots))
	fnv(&h, u32(w.stats.hits))
	fnv(&h, u32(w.stats.kills))
	fnv(&h, u32(w.status))
	fnv(&h, u32(w.rng.state))
	return h
}

@(private = "file")
random_input :: proc(r: ^rng.Rng) -> Player_Input {
	return Player_Input{
		move   = physics.clamp_length2(Vec2{rng.float_signed(r), rng.float_signed(r)}, 1),
		look   = Vec2{rng.float_signed(r) * 0.03, rng.float_signed(r) * 0.01},
		sprint = rng.chance(r, 0.3),
		jump   = rng.chance(r, 0.1),
		fire   = rng.chance(r, 0.5),
	}
}

@(private = "file")
run_script :: proc(seed: u64, steps: int) -> u64 {
	w := new_world(seed)
	defer free_world(w)
	script := rng.create(0xFEED)
	in_: Player_Input
	for i in 0..<steps {
		if i%25 == 0 {
			in_ = random_input(&script)
		}
		world_step(w, in_, DT)
		in_.jump = false
	}
	return world_digest(w)
}

@(test)
test_same_seed_and_inputs_replay_identically :: proc(t: ^testing.T) {
	a := run_script(42, 4000)
	b := run_script(42, 4000)
	testing.expect_value(t, a, b)
	c := run_script(43, 4000)
	testing.expect(t, a != c, "different seeds should diverge")
}

@(test)
test_generation_is_valid_for_many_seeds :: proc(t: ^testing.T) {
	free_play := tuning_for({})
	challenge := tuning_for({challenge = true})
	testing.expect_value(t, free_play.cells, 9)
	testing.expect_value(t, free_play.runes, 4)
	testing.expect_value(t, free_play.enemies, 11)
	testing.expect_value(t, free_play.damage_scale, f32(1))
	testing.expect_value(t, challenge.cells, 7)
	testing.expect_value(t, challenge.runes, 3)
	testing.expect_value(t, challenge.enemies, 6)
	testing.expect_value(t, challenge.damage_scale, f32(0.75))
	field := new([MAX_COLUMNS]i32)
	defer free(field)
	for seed in u64(1)..=30 {
		for seed_offset in 0..=2 {
			for challenge in ([2]bool{false, true}) {
				w := new_world(seed*7919+u64(seed_offset), challenge)
				defer free_world(w)
				tuning := tuning_for(w.config)
				m := &w.maze
				// Every maze cell is connected to the antechamber.
				for i in 0..<m.cells*m.cells {
					testing.expectf(t, m.cell_dist[i] >= 0, "seed %d: cell %d unreachable", seed, i)
				}
				spawn := column_of(w, w.spawn)
				testing.expect(t, spawn >= 0 && w.walkable[spawn])
				p := w.player.body
				testing.expect(t, !physics.box_hits_voxels(&w.voxels, p.position, p.position+p.size), "player spawns inside a wall")
				flow_from(w, field, spawn)
				for col in 0..<w.side*w.side {
					if w.walkable[col] {
						testing.expectf(t, field[col] < FLOW_UNREACHED, "seed %d: column %d cut off", seed, col)
					}
				}
				testing.expect_value(t, w.rune_count, tuning.runes)
				runes := 0
				for i in 0..<w.pickup_count {
					pk := w.pickups[i]
					col := column_of(w, pk.position)
					testing.expectf(t, col >= 0 && w.walkable[col] && field[col] < FLOW_UNREACHED,
						"seed %d: pickup %d unreachable", seed, i)
					if pk.kind == .Rune {
						runes += 1
					}
				}
				testing.expect_value(t, runes, tuning.runes)
				portal := column_of(w, w.portal.center+Vec3{0.5, 0, 0})
				testing.expect(t, portal >= 0 && w.walkable[portal] && field[portal] < FLOW_UNREACHED, "portal unreachable")
				testing.expect_value(t, w.enemy_count, tuning.enemies)
				for i in 0..<w.enemy_count {
					e := w.enemies[i]
					testing.expect(t, !physics.box_hits_voxels(&w.voxels, e.body.position, e.body.position+e.body.size),
						"enemy spawned inside a wall")
					col := column_of(w, enemy_feet(e))
					testing.expect(t, col >= 0 && w.walkable[col])
					d := enemy_feet(e) - w.spawn
					testing.expect(t, d.x*d.x+d.z*d.z > 6*6, "enemy too close to the spawn")
				}
				testing.expect(t, w.par_time > 0)
			}
		}
	}
}

@(test)
test_bot_collects_every_rune_and_escapes :: proc(t: ^testing.T) {
	for seed in ([4]u64{1, 7, 1234, 0xC0FFEE}) {
		for seed_offset in 0..=2 {
			for challenge in ([2]bool{false, true}) {
				w := new_world(seed+u64(seed_offset)*101, challenge)
				defer free_world(w)
				// Reachability only: no enemies to fight.
				w.enemy_count = 0
				w.tuning.wave = 0
				for i := 0; i < SIM_HZ*300 && w.status == .Playing; i += 1 {
					world_step(w, bot_input(w, DT), DT)
				}
				testing.expectf(t, w.status == .Won, "seed %d offset %d challenge %v: status %v runes %d/%d",
					seed, seed_offset, challenge, w.status, w.runes_taken, w.rune_count)
				testing.expect_value(t, w.runes_taken, w.rune_count)
				_, stars := world_score(w)
				testing.expect(t, stars >= 1)
			}
		}
	}
}

// With enemies the bot is no expert, but at the fixed balance it should usually make it:
// a sanity check that the round is winnable under fire.
@(test)
test_bot_survives_crypts_with_enemies :: proc(t: ^testing.T) {
	wins := 0
	total := 0
	for seed in u64(1)..=8 {
		w := new_world(seed*31)
		defer free_world(w)
		for i := 0; i < SIM_HZ*400 && w.status == .Playing; i += 1 {
			world_step(w, bot_input(w, DT), DT)
		}
		total += 1
		if w.status == .Won {
			wins += 1
		}
	}
	testing.expectf(t, wins*2 >= total, "bot won only %d of %d rounds", wins, total)
}

@(test)
test_standing_still_next_to_a_ghoul_loses :: proc(t: ^testing.T) {
	w := new_world(5)
	defer free_world(w)
	w.enemy_count = 0
	i := spawn_enemy(w, .Ghoul, w.spawn+Vec3{1.2, 0, 0}, &w.rng)
	testing.expect(t, i >= 0)
	steps := 0
	for steps < SIM_HZ*90 && w.status == .Playing {
		world_step(w, {}, DT)
		steps += 1
	}
	testing.expect_value(t, w.status, host.Round_Status.Lost)
	testing.expect_value(t, w.player.hp, f32(0))
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(0))
	// The simulation holds still after the round ends.
	before := world_digest(w)
	world_step(w, Player_Input{move = {0, 1}, fire = true}, DT)
	testing.expect_value(t, world_digest(w), before)
}

// Flat arena with an optional wall slab between the player and a target.
@(private = "file")
make_arena :: proc(w: ^World, slab_x: int) {
	vm := &w.voxels
	for z in 0..<w.side {
		for x in 0..<w.side {
			physics.voxel_set(vm, x, 0, z, u8(Material.Floor))
			for y in 1..<MAP_HEIGHT {
				solid := x == slab_x && y < 5
				physics.voxel_set(vm, x, y, z, u8(Material.Slate) if solid else 0)
			}
		}
	}
	compute_walkable(w)
}

@(test)
test_hitscan_is_blocked_by_walls :: proc(t: ^testing.T) {
	w := new_world(9)
	defer free_world(w)
	w.enemy_count = 0
	w.projectiles = {}
	make_arena(w, 10)
	teleport(w, {5.5, FLOOR_Y, 8.5})
	w.player.yaw = math.PI / 2 // facing +x
	w.player.pitch = 0
	target := spawn_enemy(w, .Ghoul, {14.5, FLOOR_Y, 8.5}, &w.rng)
	full := w.enemies[target].hp

	eye := player_eye(w.player)
	hit := hitscan(w, eye, player_forward(w.player), SHOT_RANGE)
	testing.expect_value(t, hit.kind, Hit_Kind.Wall)
	testing.expect(t, abs(hit.distance-4.5) < 0.05, "wall should be hit 4.5 m ahead")
	world_step(w, Player_Input{fire = true}, DT)
	testing.expect_value(t, w.stats.shots, 1)
	testing.expect_value(t, w.enemies[target].hp, full)

	// Remove the slab: the same shot now lands.
	make_arena(w, -1)
	w.player.fire_cd = 0
	hit = hitscan(w, eye, player_forward(w.player), SHOT_RANGE)
	testing.expect_value(t, hit.kind, Hit_Kind.Enemy)
	testing.expect_value(t, hit.index, target)
	world_step(w, Player_Input{fire = true}, DT)
	testing.expect_value(t, w.enemies[target].hp, full-BOLT_DAMAGE)
	testing.expect_value(t, w.stats.hits, 1)

	// Aiming away misses; an enemy bolt in the line of fire is shot down.
	w.player.yaw = -math.PI / 2
	hit = hitscan(w, player_eye(w.player), player_forward(w.player), SHOT_RANGE)
	testing.expect(t, hit.kind != .Enemy)
	w.player.yaw = math.PI / 2
	spawn_projectile(w, eye+Vec3{3, 0, 0}, eye+Vec3{2, 0, 0}, 10)
	hit = hitscan(w, eye, player_forward(w.player), SHOT_RANGE)
	testing.expect_value(t, hit.kind, Hit_Kind.Projectile)
}

@(test)
test_enemy_behind_wall_does_not_notice_player :: proc(t: ^testing.T) {
	w := new_world(13)
	defer free_world(w)
	w.enemy_count = 0
	make_arena(w, 10)
	teleport(w, {5.5, FLOOR_Y, 8.5})
	hidden := spawn_enemy(w, .Cultist, {14.5, FLOOR_Y, 8.5}, &w.rng)
	visible := spawn_enemy(w, .Cultist, {5.5, FLOOR_Y, 16.5}, &w.rng)
	for _ in 0..<SIM_HZ {
		world_step(w, {}, DT)
	}
	testing.expect(t, !w.enemies[hidden].alerted, "a wall should hide the player")
	testing.expect(t, w.enemies[visible].alerted, "open line of sight should alert")
}

@(test)
test_runes_unlock_the_portal :: proc(t: ^testing.T) {
	w := new_world(11)
	defer free_world(w)
	w.enemy_count = 0
	w.tuning.wave = 0
	portal_feet := Vec3{w.portal.center.x + 0.5, FLOOR_Y, w.portal.center.z}
	teleport(w, portal_feet)
	world_step(w, {}, DT)
	testing.expect_value(t, w.status, host.Round_Status.Playing)
	testing.expect(t, !w.portal.open)
	for i in 0..<w.pickup_count {
		if w.pickups[i].kind != .Rune {
			continue
		}
		before := w.runes_taken
		teleport(w, w.pickups[i].position)
		world_step(w, {}, DT)
		testing.expect_value(t, w.runes_taken, before+1)
	}
	testing.expect(t, w.portal.open)
	teleport(w, portal_feet)
	world_step(w, {}, DT)
	testing.expect_value(t, w.status, host.Round_Status.Won)
}

@(test)
test_star_rules :: proc(t: ^testing.T) {
	w := new_world(3)
	defer free_world(w)
	w.status = .Won
	w.runes_taken = w.rune_count
	w.time = w.par_time + 10
	w.player.hp = 20
	w.stats = Stats{shots = 10, hits = 2}
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(1))
	w.time = w.par_time - 1
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(2))
	w.player.hp = 80
	w.stats = Stats{shots = 10, hits = 7}
	score, stars3 := world_score(w)
	testing.expect_value(t, stars3, u8(3))
	testing.expect(t, score > i64(w.rune_count*RUNE_SCORE))
	w.status = .Lost
	_, stars = world_score(w)
	testing.expect_value(t, stars, u8(0))
}

@(private = "file")
check_invariants :: proc(t: ^testing.T, w: ^World) -> bool {
	p := w.player
	ok := true
	ok &= p.hp >= 0 && p.hp <= MAX_HP
	ok &= p.mana >= 0 && p.mana <= MAX_MANA
	ok &= !physics.box_hits_voxels(&w.voxels, p.body.position, p.body.position+p.body.size)
	ok &= p.body.position.x == p.body.position.x && p.yaw == p.yaw && p.pitch == p.pitch
	ok &= abs(p.pitch) <= PITCH_LIMIT
	size := f32(w.side)
	ok &= p.body.position.x >= 0 && p.body.position.z >= 0 && p.body.position.x <= size && p.body.position.z <= size
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		ok &= !physics.box_hits_voxels(&w.voxels, e.body.position, e.body.position+e.body.size)
		ok &= e.body.position.x == e.body.position.x
		ok &= (e.state == .Dead) == (e.hp <= 0)
	}
	ok &= w.runes_taken <= w.rune_count
	ok &= w.event_count <= MAX_EVENTS
	for pr in w.projectiles {
		if pr.alive {
			ok &= pr.position.x >= -1 && pr.position.x <= size+1 && pr.position.z >= -1 && pr.position.z <= size+1
		}
	}
	if !ok {
		testing.fail_now(t, "invariant broken")
	}
	return ok
}

when ODIN_TEST_FULL {
	@(test)
	test_long_random_soak_keeps_invariants :: proc(t: ^testing.T) {
		script := rng.create(777)
		for round in 0..<4 {
			w := new_world(u64(round)*101+5, round == 3)
			defer free_world(w)
			in_: Player_Input
			use_bot := false
			for i in 0..<15000 {
				if i%40 == 0 {
					in_ = random_input(&script)
					use_bot = rng.chance(&script, 0.5)
				}
				step := bot_input(w, DT) if use_bot else in_
				world_step(w, step, DT)
				in_.jump = false
				if !check_invariants(t, w) {
					return
				}
				if w.status != .Playing {
					// Keep soaking from a fresh round.
					world_reset(w, host.Minigame_Config{seed = u64(i)})
				}
			}
			testing.expect_value(t, w.dropped_events, 0)
		}
	}
}

@(test)
test_sprite_atlases_preserve_frame_layout :: proc(t: ^testing.T) {
	expected := [Sprite_Id][3]int{
		.Ghoul = {16, 20, 5},
		.Wraith = {16, 20, 5},
		.Cultist = {16, 20, 5},
		.Rune = {12, 16, 2},
		.Health = {10, 12, 1},
		.Mana = {10, 12, 1},
		.Staff = {12, 32, 2},
		.Candle = {6, 8, 1},
		.Flame = {5, 8, 2},
		.Skull = {8, 7, 1},
		.Bones = {12, 5, 1},
		.Brazier = {10, 12, 1},
	}
	for id in Sprite_Id {
		asset := SPRITE_ASSETS[id]
		img := gfx.sprite_asset_image(asset)
		testing.expectf(t, img.data != nil, "%v: embedded atlas did not decode", id)
		if img.data == nil { continue }
		testing.expect_value(t, [3]int{int(img.width)/asset.frames, int(img.height), asset.frames}, expected[id])
		rl.UnloadImage(img)
	}
}
