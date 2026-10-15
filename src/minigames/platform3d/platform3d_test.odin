package platform3d

import "core:math"
import "core:testing"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"

// Long simulations remain part of the default/full pre-merge suite.
@(private = "file")
ODIN_TEST_FULL :: #config(ODIN_TEST_FULL, true)

when !ODIN_TEST_FULL {
	_ :: math // Only the full-profile soak uses this import.
}

// Worlds are big: tests keep them on the heap (test threads have small stacks).
@(private = "file")
make_world :: proc(seed: u64, challenge := false) -> ^World {
	w := new(World)
	world_reset(w, host.Minigame_Config{seed = seed, challenge = challenge})
	return w
}

@(private = "file")
drop_world :: proc(w: ^World) {
	world_destroy(w)
	free(w)
}

@(private = "file")
cell_at :: proc(w: ^World, p: Vec3) -> Material {
	c := physics.voxel_of(&w.terrain, p)
	return Material(physics.voxel_get(&w.terrain, c.x, c.y, c.z))
}

// Point of `a` closest to `b`, per axis (middle of the shared range if any).
@(private = "file")
facing_point :: proc(a, b: IRect) -> Vec2 {
	r: Vec2
	for i in 0..<2 {
		switch {
		case b.lo[i] >= a.hi[i]:
			r[i] = f32(a.hi[i])
		case b.hi[i] <= a.lo[i]:
			r[i] = f32(a.lo[i])
		case:
			r[i] = f32(max(a.lo[i], b.lo[i])+min(a.hi[i], b.hi[i])) * 0.5
		}
	}
	return r
}

@(private = "file")
check_level :: proc(t: ^testing.T, w: ^World, label: string) {
	s := w.settings
	testing.expectf(t, w.path_count >= 6, "%s: short path %d", label, w.path_count)
	testing.expectf(t, w.pads[w.path[0]].kind == .Spawn, "%s: path does not start at the spawn", label)
	testing.expectf(t, w.pads[w.path[w.path_count-1]].kind == .Goal, "%s: path does not end at the goal", label)
	testing.expectf(t, w.shard_count == s.shards_required+s.shards_bonus, "%s: %d shards", label, w.shard_count)
	testing.expectf(t, w.shards_required == s.shards_required, "%s: required %d", label, w.shards_required)
	for i in 1..<w.path_count {
		testing.expectf(t, w.pads[w.path[i]].parent == w.path[i-1], "%s: path entry %d not linked to its predecessor", label, i)
	}
	size := physics.voxel_world_size(&w.terrain)
	for i in 0..<w.pad_count {
		p := w.pads[i]
		testing.expectf(t, p.lo[0] >= 0 && p.lo[1] >= 0 && f32(p.hi[0]) <= size.x && f32(p.hi[1]) <= size.z &&
			p.top > 0 && f32(p.top+7) <= size.y, "%s: pad %d outside the map", label, i)
		if p.mover < 0 {
			c := pad_center(p)
			testing.expectf(t, cell_at(w, {c.x, f32(p.top) - 0.5, c.y}) != .Empty, "%s: pad %d has no floor", label, i)
			if p.kind != .Spawn && p.kind != .Goal {
				for y in p.top..<p.top+3 {
					for z in p.lo[1]..<p.hi[1] {
						for x in p.lo[0]..<p.hi[0] {
							testing.expectf(t, physics.voxel_get(&w.terrain, x, y, z) == 0,
								"%s: pad %d has no headroom at %v", label, i, [3]int{x, y, z})
						}
					}
				}
			}
		}
		if p.parent < 0 {
			continue
		}
		q := w.pads[p.parent]
		if p.link == .Bridge {
			found := false
			for k in 0..<w.bridge_count {
				br := w.bridges[k]
				if br.from != p.parent || br.to != i {
					continue
				}
				found = true
				testing.expect(t, p.top == q.top)
				length := br.hi[br.axis] - br.lo[br.axis]
				testing.expectf(t, length >= 3, "%s: bridge too short", label)
				run := 0
				for a in 0..<length {
					run = run + 1 if bridge_hole(br, a) else 0
					testing.expectf(t, run <= 2, "%s: bridge hole wider than a hop", label)
				}
				testing.expect(t, !bridge_hole(br, 0) && !bridge_hole(br, length-1))
			}
			testing.expectf(t, found, "%s: bridge link %d without a bridge", label, i)
			continue
		}
		from := pad_rect(q)
		if q.kind == .Shuttle {
			m := w.movers[q.mover]
			end := [2]int{int(m.b.x), int(m.b.z)}
			from = IRect{end, end + {int(m.size.x), int(m.size.z)}}
		}
		rise := p.top - q.top
		gap := rect_gap(from, pad_rect(p))
		double := s.double_jump && p.kind != .Crumble && q.kind != .Crumble
		limit := reach_at(w, rise, double) * REACH_LIMIT
		testing.expectf(t, gap >= 1 && gap <= limit, "%s: link %d->%d gap %v rise %d limit %v",
			label, p.parent, i, gap, rise, limit)
		// The air above the gap stays clear for the jump.
		a := facing_point(from, pad_rect(p))
		b := facing_point(pad_rect(p), from)
		high := max(p.top, q.top)
		for k in 1..<10 {
			f := f32(k) / 10
			g := a + (b-a)*f
			for y in high..<high+2 {
				testing.expectf(t, cell_at(w, {g.x, f32(y) + 0.5, g.y}) == .Empty,
					"%s: link %d->%d blocked at %v", label, p.parent, i, g)
			}
		}
	}
	for i in 0..<w.shard_count {
		sh := w.shards[i]
		p := w.pads[sh.pad]
		testing.expectf(t, cell_at(w, sh.position) == .Empty, "%s: shard %d inside rock", label, i)
		testing.expect(t, sh.position.x > f32(p.lo[0]) && sh.position.x < f32(p.hi[0]))
		testing.expect(t, sh.position.y > f32(p.top) && sh.position.y < f32(p.top)+2.5)
		testing.expect(t, p.shard == i)
	}
	goal := w.pads[w.path[w.path_count-1]]
	testing.expect(t, w.portal_lo.y == f32(goal.top))
	testing.expect(t, cell_at(w, w.portal_center) == .Empty)
	for i in 0..<w.spike_count {
		sp := w.spikes[i]
		r := w.pads[sp.pad].respawn
		testing.expectf(t, r.x+0.3 <= sp.lo.x || r.x-0.3 >= sp.hi.x || r.z+0.3 <= sp.lo.y || r.z-0.3 >= sp.hi.y,
			"%s: respawn on spikes", label)
	}
}

@(test)
test_jump_reach_follows_the_controller :: proc(t: ^testing.T) {
	w := make_world(1)
	defer drop_world(w)
	single := reach_at(w, 0, false)
	double := reach_at(w, 0, true)
	testing.expectf(t, single > 3.5 && single < 5, "single reach %v", single)
	testing.expectf(t, double > single+1.5, "double reach %v vs %v", double, single)
	for r in REACH_MIN_RISE..<REACH_MAX_RISE {
		testing.expect(t, reach_at(w, r, true) >= reach_at(w, r+1, true))
		testing.expect(t, reach_at(w, r, false) >= reach_at(w, r+1, false))
	}
	// Above the single jump's apex only the air jump gets there.
	testing.expect_value(t, reach_at(w, 3, false), f32(0))
	testing.expect(t, reach_at(w, 3, true) > 2)
}

@(test)
test_generation_is_valid_for_many_seeds :: proc(t: ^testing.T) {
	free_play := gen_settings({})
	challenge := gen_settings({challenge = true})
	testing.expect_value(t, free_play.path_pads, 18)
	testing.expect_value(t, free_play.shards_required, 7)
	testing.expect_value(t, free_play.lives, 3)
	testing.expect(t, free_play.double_jump && !free_play.timed)
	testing.expect_value(t, challenge.path_pads, 11)
	testing.expect_value(t, challenge.shards_required, 4)
	testing.expect(t, challenge.timed)
	for seed_offset in 0..<3 {
		for challenge in ([2]bool{false, true}) {
			for seed in u64(1)..=24 {
				w := make_world(seed*7919+u64(seed_offset), challenge)
				check_level(t, w, "level")
				drop_world(w)
			}
		}
	}
}

@(test)
test_generation_is_deterministic :: proc(t: ^testing.T) {
	a := make_world(42)
	defer drop_world(a)
	b := make_world(42)
	defer drop_world(b)
	testing.expect_value(t, a.pad_count, b.pad_count)
	testing.expect(t, a.pads == b.pads)
	testing.expect(t, a.movers == b.movers)
	testing.expect(t, a.shards == b.shards)
	testing.expect_value(t, len(a.terrain.cells), len(b.terrain.cells))
	same := true
	for c, i in a.terrain.cells {
		same = same && c == b.terrain.cells[i]
	}
	testing.expect(t, same)
	c := make_world(43)
	defer drop_world(c)
	testing.expect(t, c.pads != a.pads)
}

@(private = "file")
random_input :: proc(r: ^rng.Rng, current: Player_Input) -> Player_Input {
	cmd := current
	if rng.chance(r, 0.04) {
		cmd.move = Vec2{rng.float_signed(r), rng.float_signed(r)}
		if physics.length2(cmd.move) > 1 {
			cmd.move = physics.normalize2(cmd.move)
		}
	}
	cmd.jump_pressed = rng.chance(r, 0.02)
	if cmd.jump_pressed {
		cmd.jump_held = true
	} else if rng.chance(r, 0.05) {
		cmd.jump_held = false
	}
	cmd.dash_pressed = rng.chance(r, 0.005)
	return cmd
}

@(test)
test_same_seed_and_inputs_give_the_same_round :: proc(t: ^testing.T) {
	a := make_world(9)
	defer drop_world(a)
	b := make_world(9)
	defer drop_world(b)
	ra := rng.create(77)
	rb := rng.create(77)
	ia, ib: Player_Input
	for _ in 0..<5000 {
		ia = random_input(&ra, ia)
		ib = random_input(&rb, ib)
		world_step(a, ia, SIM_DT)
		world_step(b, ib, SIM_DT)
	}
	testing.expect(t, a.player == b.player)
	testing.expect_value(t, a.lives, b.lives)
	testing.expect_value(t, a.shards_taken, b.shards_taken)
	testing.expect_value(t, a.time, b.time)
	testing.expect(t, a.movers == b.movers)
	sa, ka := world_score(a)
	sb, kb := world_score(b)
	testing.expect_value(t, sa, sb)
	testing.expect_value(t, ka, kb)
	// The bot is deterministic too.
	c := make_world(5)
	defer drop_world(c)
	d := make_world(5)
	defer drop_world(d)
	bc := new(Bot)
	defer free(bc)
	bd := new(Bot)
	defer free(bd)
	bot_init(bc, c)
	bot_init(bd, d)
	for _ in 0..<6000 {
		world_step(c, bot_input(bc, c), SIM_DT)
		world_step(d, bot_input(bd, d), SIM_DT)
	}
	testing.expect(t, c.player == d.player)
	testing.expect_value(t, c.status, d.status)
	testing.expect_value(t, c.shards_taken, d.shards_taken)
}

@(private = "file")
run_bot :: proc(w: ^World, max_seconds: f32) {
	b := new(Bot)
	defer free(b)
	bot_init(b, w)
	for _ in 0..<int(max_seconds*SIM_HZ) {
		if world_step(w, bot_input(b, w), SIM_DT) != .Playing {
			return
		}
	}
}

// Plays whole courses with the real controller: every gap, shuttle, crumble
// chain, bridge, spike strip and sentinel the generator makes is crossable.
@(test)
test_bot_finishes_courses :: proc(t: ^testing.T) {
	for seed_offset in 0..<3 {
		for challenge in ([2]bool{false, true}) {
			for seed in u64(1)..=5 {
				w := make_world(seed*31+u64(seed_offset), challenge)
				run_bot(w, 400)
				testing.expectf(t, w.status == .Won, "seed offset %d challenge %v seed %d: %v after %.1fs, %d/%d shards, %d deaths",
					seed_offset, challenge, seed, w.status, w.time, w.shards_taken, w.shard_count, w.deaths)
				drop_world(w)
			}
		}
	}
}

@(test)
test_collecting_everything_wins_with_three_stars :: proc(t: ^testing.T) {
	w := make_world(3)
	defer drop_world(w)
	opened := false
	for i in 0..<w.shard_count {
		testing.expect(t, w.portal_open == (i >= w.shards_required))
		s := w.shards[i]
		w.player.body.position = s.position - PLAYER_SIZE*0.5
		w.player.body.velocity = {}
		world_step(w, {}, SIM_DT)
		testing.expect(t, w.shards[i].taken)
		for k in 0..<w.event_count {
			opened = opened || w.events[k].kind == .Portal_Open
		}
		if i+1 == w.shards_required {
			testing.expect(t, w.portal_open)
		}
	}
	testing.expect(t, opened)
	testing.expect_value(t, w.shards_taken, w.shard_count)
	before, _ := world_score(w)
	testing.expect_value(t, before, i64(w.shard_count*SHARD_POINTS))
	center := (w.portal_lo + w.portal_hi) * 0.5
	w.player.body.position = Vec3{center.x - 0.3, w.portal_lo.y, center.z - 0.3}
	testing.expect_value(t, world_step(w, {}, SIM_DT), host.Round_Status.Won)
	score, stars := world_score(w)
	testing.expect_value(t, stars, u8(3))
	testing.expect(t, score > before+WIN_POINTS)
	// Finished rounds hold still.
	testing.expect_value(t, world_step(w, {move = {1, 0}}, SIM_DT), host.Round_Status.Won)
}

@(test)
test_sealed_portal_does_not_win :: proc(t: ^testing.T) {
	w := make_world(4)
	defer drop_world(w)
	center := (w.portal_lo + w.portal_hi) * 0.5
	w.player.body.position = Vec3{center.x - 0.3, w.portal_lo.y, center.z - 0.3}
	testing.expect_value(t, world_step(w, {}, SIM_DT), host.Round_Status.Playing)
	sealed := false
	for k in 0..<w.event_count {
		sealed = sealed || w.events[k].kind == .Portal_Sealed
	}
	testing.expect(t, sealed)
}

@(test)
test_falling_costs_lives_until_the_round_is_lost :: proc(t: ^testing.T) {
	w := make_world(6)
	defer drop_world(w)
	lives := w.lives
	respawns := 0
	for _ in 0..<SIM_HZ*30 {
		if w.phase == .Alive {
			// Step off into the void far from every island.
			w.player.body.position.x = -40
		}
		status := world_step(w, {}, SIM_DT)
		for k in 0..<w.event_count {
			if w.events[k].kind == .Respawn {
				respawns += 1
			}
		}
		if status != .Playing {
			break
		}
	}
	testing.expect_value(t, w.status, host.Round_Status.Lost)
	testing.expect_value(t, w.lives, 0)
	testing.expect_value(t, w.deaths, lives)
	testing.expect_value(t, respawns, lives-1)
	_, stars := world_score(w)
	testing.expect_value(t, stars, u8(0))
}

@(test)
test_challenge_runs_out_of_time :: proc(t: ^testing.T) {
	w := make_world(8, true)
	defer drop_world(w)
	testing.expect(t, w.time_limit > 0)
	warned := false
	for _ in 0..<int((w.time_limit+1)*SIM_HZ) {
		world_step(w, {}, SIM_DT)
		for k in 0..<w.event_count {
			warned = warned || w.events[k].kind == .Time_Low
		}
	}
	testing.expect(t, warned)
	testing.expect_value(t, w.status, host.Round_Status.Lost)
	free_play := make_world(8)
	defer drop_world(free_play)
	testing.expect_value(t, free_play.time_limit, f32(0))
	testing.expect(t, free_play.path_count > w.path_count)
}

@(private = "file")
find_world_with :: proc(kind: Mover_Kind) -> ^World {
	for seed in u64(1)..=60 {
		w := make_world(seed)
		for i in 0..<w.mover_count {
			if w.movers[i].kind == kind {
				return w
			}
		}
		drop_world(w)
	}
	return nil
}

@(test)
test_shuttle_carries_its_rider :: proc(t: ^testing.T) {
	w := find_world_with(.Shuttle)
	testing.expect(t, w != nil)
	if w == nil {
		return
	}
	defer drop_world(w)
	index := 0
	for w.movers[index].kind != .Shuttle {
		index += 1
	}
	m := w.movers[index]
	top := m.position.y + m.size.y
	w.player.body.position = Vec3{m.position.x + 1.2, top, m.position.z + 1.2}
	w.player.body.velocity = {}
	// The first step lands on the slab; carrying starts with the next one.
	world_step(w, {}, SIM_DT)
	m = w.movers[index]
	start := w.player.body.position
	start_mover := m.position
	for _ in 0..<SIM_HZ*3 {
		world_step(w, {}, SIM_DT)
	}
	m = w.movers[index]
	testing.expect_value(t, w.riding, index)
	testing.expect(t, abs(w.player.body.position.y-top) < 0.01)
	moved := m.position - start_mover
	carried := w.player.body.position - start
	testing.expectf(t, abs(moved.x-carried.x) < 0.02 && abs(moved.z-carried.z) < 0.02, "moved %v carried %v", moved, carried)
}

@(test)
test_crumbling_slab_drops_its_rider :: proc(t: ^testing.T) {
	w := find_world_with(.Crumble)
	testing.expect(t, w != nil)
	if w == nil {
		return
	}
	defer drop_world(w)
	index := 0
	for w.movers[index].kind != .Crumble {
		index += 1
	}
	m := w.movers[index]
	w.player.body.position = Vec3{m.position.x + 0.7, m.position.y + m.size.y, m.position.z + 0.7}
	shook := false
	for _ in 0..<int((w.settings.crumble_delay+0.5)*SIM_HZ) {
		world_step(w, {}, SIM_DT)
		for k in 0..<w.event_count {
			shook = shook || w.events[k].kind == .Crumble_Shake
		}
	}
	testing.expect(t, shook)
	testing.expect_value(t, w.movers[index].state, Crumble_State.Falling)
	testing.expect(t, !w.player.grounded || w.phase != .Alive)
	// It comes back later.
	for _ in 0..<SIM_HZ*6 {
		world_step(w, {}, SIM_DT)
	}
	testing.expect_value(t, w.movers[index].state, Crumble_State.Idle)
	testing.expect_value(t, w.movers[index].position, w.movers[index].a)
}

@(test)
test_spikes_and_sentinels_hurt :: proc(t: ^testing.T) {
	spiked, knocked := false, false
	for seed in u64(1)..=40 {
		if spiked && knocked {
			break
		}
		w := make_world(seed)
		if !spiked && w.spike_count > 0 {
			s := w.spikes[0]
			// Wait for the stab, then stand in the middle of the strip.
			for spike_extension(s, w.time) < 1 {
				world_step(w, {}, SIM_DT)
			}
			c := (s.lo + s.hi) * 0.5
			w.player.body.position = Vec3{c.x - 0.3, s.top, c.y - 0.3}
			w.invulnerable = 0
			world_step(w, {}, SIM_DT)
			testing.expect_value(t, w.phase, Phase.Dying)
			testing.expect_value(t, w.death_kind, Death_Kind.Spikes)
			spiked = true
		}
		if !knocked && w.sentinel_count > 0 && w.phase == .Alive {
			s := w.sentinels[0]
			w.player.body.position = s.position - Vec3{0.3, 0.6, 0.6}
			w.invulnerable = 0
			world_step(w, {}, SIM_DT)
			testing.expect(t, w.stun > 0)
			testing.expect(t, w.player.body.velocity.y > 0)
			knocked = true
		}
		drop_world(w)
	}
	testing.expect(t, spiked)
	testing.expect(t, knocked)
}

// Thousands of random steps on several courses: nothing breaks.
when ODIN_TEST_FULL {
	@(test)
	test_random_input_soak :: proc(t: ^testing.T) {
		r := rng.create(2024)
		for round in 0..<6 {
			w := make_world(u64(round)*101+3, round >= 4)
			cmd: Player_Input
			for _ in 0..<9000 {
				cmd = random_input(&r, cmd)
				status := world_step(w, cmd, SIM_DT)
				p := w.player.body
				ok := !math.is_nan(p.position.x) && !math.is_nan(p.position.y) && !math.is_nan(p.position.z) &&
					!math.is_inf(p.position.y)
				testing.expect(t, ok)
				testing.expect(t, w.lives >= 0 && w.lives <= w.settings.lives)
				testing.expect(t, w.shards_taken <= w.shard_count)
				testing.expect(t, w.event_count <= MAX_EVENTS)
				testing.expect(t, w.safe_pad >= 0 && w.safe_pad < w.pad_count && w.pads[w.safe_pad].mover < 0)
				if w.phase == .Alive {
					eps := Vec3{0.01, 0.01, 0.01}
					testing.expect(t, !physics.box_hits_voxels(&w.terrain, p.position+eps, p.position+p.size-eps))
				}
				if !ok {
					break
				}
				if status != .Playing {
					world_reset(w, host.Minigame_Config{seed = u64(round) + 900})
				}
			}
			drop_world(w)
		}
	}
}
