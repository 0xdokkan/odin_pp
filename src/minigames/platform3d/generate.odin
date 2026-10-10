package platform3d

import "core:math"
import physics "../../engine/physics"
import rng "../../engine/rng"

// The course is a chain of pads heading roughly toward +z. Every link is
// sized from the simulated jump reach (jump_reach), and a reserved volume
// around each pad and each flight path keeps later pads from blocking a jump,
// so the generated course is always completable.

HEADROOM :: 6
REACH_MIN_RISE :: -8
REACH_MAX_RISE :: 4
REACH_COUNT :: REACH_MAX_RISE - REACH_MIN_RISE + 1
// Largest fraction of the simulated reach a generated gap may ask for. The
// difficulty safety margins sit below it; the tests check every link.
REACH_LIMIT :: f32(0.8)
SPIRE_DEPTH :: 80
MAX_RESERVES :: 256

IRect :: struct {
	lo, hi: [2]int,
}

Box :: struct {
	lo, hi: [3]int,
}

@(private)
Reserve :: struct {
	box:      Box,
	pad:      int,
	corridor: bool,
}

@(private)
Gen :: struct {
	w:             ^World,
	s:             Gen_Settings,
	r:             rng.Rng,
	reserves:      [MAX_RESERVES]Reserve,
	reserve_count: int,
	x_run:         int, // consecutive sideways links
	force_dir:     int, // direction the next link must take, -1 when free
	straight:      bool,
}

@(private)
Snapshot :: struct {
	pads, path, movers, reserves, bridges: int,
}

@(private)
Link_Choice :: enum u8 {
	Jump,
	Bridge,
	Shuttle,
	Crumble,
}

// +z, +x, -x, -z as (x, z). The main path never heads back toward -z.
@(private)
DIRS :: [4][2]int{{0, 1}, {1, 0}, {-1, 0}, {0, -1}}

dir_vec :: proc "contextless" (d: int) -> [2]int {
	dirs := DIRS
	return dirs[d & 3]
}

// Cell axis across direction d (0 = x, 1 = z).
lateral_axis :: proc "contextless" (d: int) -> int {
	return 0 if d == 0 || d == 3 else 1
}

// Euclidean distance between two footprints on the ground plane.
rect_gap :: proc "contextless" (a, b: IRect) -> f32 {
	dx := max(0, b.lo[0]-a.hi[0], a.lo[0]-b.hi[0])
	dz := max(0, b.lo[1]-a.hi[1], a.lo[1]-b.hi[1])
	return math.sqrt(f32(dx*dx + dz*dz))
}

pad_rect :: proc "contextless" (p: Pad) -> IRect {
	return IRect{p.lo, p.hi}
}

generate :: proc(w: ^World) {
	base := rng.derive(w.config.seed, 0x6775_6731)
	for attempt in 0..<8 {
		if generate_attempt(w, rng.derive(base, u64(attempt)), false) {
			return
		}
	}
	// A straight course always fits: nothing is ever built ahead of it.
	ok := generate_attempt(w, rng.derive(base, 99), true)
	assert(ok, "straight course generation failed")
}

@(private)
generate_attempt :: proc(w: ^World, seed: u64, straight: bool) -> bool {
	physics.voxel_map_destroy(&w.terrain)
	w.pad_count = 0
	w.path_count = 0
	w.mover_count = 0
	w.shard_count = 0
	w.spike_count = 0
	w.sentinel_count = 0
	w.bridge_count = 0
	w.far_count = 0
	w.brazier_count = 0
	g: Gen
	g.w = w
	g.s = w.settings
	g.r = rng.create(seed)
	g.straight = straight
	g.force_dir = -1
	if !gen_main_path(&g) || w.path_count < 4 {
		return false
	}
	total := w.settings.shards_required + w.settings.shards_bonus
	tips: [MAX_SHARDS]int
	tip_count := gen_branches(&g, total, tips[:])
	dims := shift_level(w)
	m, ok := physics.voxel_map_create(dims.x, dims.y, dims.z, 1)
	if !ok {
		return false
	}
	w.terrain = m
	for i in 0..<w.pad_count {
		p := &w.pads[i]
		c := pad_center(p^)
		p.respawn = Vec3{c.x, f32(p.top), c.y}
	}
	for i in 0..<tip_count {
		place_shard(w, tips[i], 1.0)
	}
	place_fallback_shards(&g, total)
	if w.shard_count != total {
		return false
	}
	place_spikes(&g)
	place_sentinels(&g)
	write_terrain(&g)
	build_portal(&g)
	place_decor(&g)
	lowest := max(int)
	for i in 0..<w.pad_count {
		lowest = min(lowest, w.pads[i].top)
	}
	w.kill_y = f32(lowest) - 9
	return true
}

@(private)
gen_main_path :: proc(g: ^Gen) -> bool {
	w := g.w
	s := g.s
	spawn := new_pad(IRect{{-3, -3}, {3, 3}}, 0, .Spawn)
	spawn.depth = 7
	w.pads[0] = spawn
	w.pad_count = 1
	add_reserve(g, pad_box(pad_rect(spawn), spawn.top, reserve_depth(spawn), HEADROOM), 0, false)
	path_push(w, 0)
	snaps: [MAX_PATH]Snapshot
	snap_count := 0
	dir := 0
	cur := 0
	shuttles, crumbles := 0, 0
	spikes_left, sentinels_left := s.spikes, s.sentinels
	last_planned := false
	for w.path_count < s.path_pads-1 && w.path_count < MAX_PATH-6 {
		snap := take_snapshot(g)
		end := -1
		choice := Link_Choice.Jump
		d := dir
		// Spread the hazard pads over the course, never two in a row.
		plan := Hazard_Plan.None
		remaining := s.path_pads - 1 - w.path_count
		budget := spikes_left + sentinels_left
		if w.path_count >= 2 && !last_planned && remaining > 1 && budget > 0 &&
		   rng.chance(&g.r, f32(budget)/f32(remaining-1)*1.4) {
			plan = .Sentinel if rng.int_range(&g.r, 1, budget) <= sentinels_left else .Spikes
		}
		used_plan := false
		for attempt in 0..<40 {
			d = choose_dir(g, cur, dir, attempt)
			used_plan = plan != .None && attempt < 24
			choice = .Jump if used_plan else choose_link(g, attempt, shuttles, crumbles)
			switch choice {
			case .Jump:
				kind := Pad_Kind.Spire if rng.chance(&g.r, s.spire_chance) else Pad_Kind.Island
				lo, hi := rise_range(g, cur, s.rise_min, s.rise_max)
				if used_plan {
					end = try_jump_link(g, cur, d, .Island, false, lo, min(hi, 1), hazard_size(g, plan, d))
				} else {
					end = try_jump_link(g, cur, d, kind, false, lo, hi)
				}
			case .Bridge:
				end = try_bridge_link(g, cur, d)
			case .Shuttle:
				end = try_shuttle_link(g, cur, d)
			case .Crumble:
				end = try_crumble_link(g, cur, d)
			}
			if end >= 0 {
				break
			}
		}
		if end < 0 {
			break
		}
		snaps[snap_count] = snap
		snap_count += 1
		if choice == .Shuttle {
			shuttles += 1
		} else if choice == .Crumble {
			crumbles += 1
		}
		// A hazard pad is crossed straight through: the next link keeps going.
		last_planned = used_plan && end >= 0
		g.force_dir = -1
		if last_planned {
			w.pads[end].plan = plan
			g.force_dir = d
			if plan == .Spikes {
				spikes_left -= 1
			} else {
				sentinels_left -= 1
			}
		}
		g.x_run = 0 if d == 0 else g.x_run + 1
		dir = d
		for p in snap.pads..<w.pad_count {
			path_push(w, p)
		}
		cur = end
	}
	// The sanctuary closes the course; back off a few links if it cannot fit.
	for {
		for attempt in 0..<30 {
			d := 0
			switch attempt % 3 {
			case 1:
				d = dir
			case 2:
				d = 1 if rng.chance(&g.r, 0.5) else 2
			}
			if g.straight {
				d = 0
			}
			end := try_jump_link(g, cur, d, .Goal, false, 0, 1)
			if end >= 0 {
				path_push(w, end)
				for i in 0..<w.path_count-1 {
					w.pads[w.path[i]].next = w.path[i+1]
				}
				return true
			}
		}
		if snap_count == 0 {
			return false
		}
		snap_count -= 1
		restore_snapshot(g, snaps[snap_count])
		cur = w.path[w.path_count-1]
	}
}

@(private)
take_snapshot :: proc(g: ^Gen) -> Snapshot {
	w := g.w
	return Snapshot{pads = w.pad_count, path = w.path_count, movers = w.mover_count,
		reserves = g.reserve_count, bridges = w.bridge_count}
}

@(private)
restore_snapshot :: proc(g: ^Gen, s: Snapshot) {
	w := g.w
	w.pad_count = s.pads
	w.path_count = s.path
	w.mover_count = s.movers
	w.bridge_count = s.bridges
	g.reserve_count = s.reserves
}

@(private)
path_push :: proc(w: ^World, p: int) {
	if w.path_count < MAX_PATH {
		w.path[w.path_count] = p
		w.path_count += 1
	}
}

@(private)
choose_dir :: proc(g: ^Gen, cur, dir, attempt: int) -> int {
	if g.straight || g.w.path_count < 2 {
		return 0
	}
	if g.force_dir >= 0 && attempt < 30 {
		return g.force_dir
	}
	p := g.w.pads[cur]
	cx := (p.lo[0] + p.hi[0]) / 2
	turn := rng.chance(&g.r, 0.3+0.02*f32(min(attempt, 20)))
	if dir != 0 {
		// Sideways runs stay short, so the course keeps heading forward.
		if turn || g.x_run >= 2 || (dir == 1 && cx > 20) || (dir == 2 && cx < -20) {
			return 0
		}
		return dir
	}
	if !turn {
		return 0
	}
	if cx > 10 {
		return 2
	}
	if cx < -10 {
		return 1
	}
	return 1 if rng.chance(&g.r, 0.5) else 2
}

@(private)
choose_link :: proc(g: ^Gen, attempt, shuttles, crumbles: int) -> Link_Choice {
	// The first link always teaches the plain jump.
	if attempt >= 20 || g.w.path_count < 2 {
		return .Jump
	}
	s := g.s
	roll := rng.float01(&g.r)
	if roll < s.shuttle_chance {
		return .Shuttle if shuttles < s.max_shuttles else .Jump
	}
	roll -= s.shuttle_chance
	if roll < s.crumble_chance {
		return .Crumble if crumbles < s.max_crumbles else .Jump
	}
	roll -= s.crumble_chance
	if roll < s.bridge_chance {
		return .Bridge
	}
	return .Jump
}

// Keeps the course inside a sensible height band.
@(private)
rise_range :: proc(g: ^Gen, cur, lo, hi: int) -> (int, int) {
	top := g.w.pads[cur].top
	a, b := lo, hi
	if top > 18 {
		b = min(b, 0)
	}
	if top < -10 {
		a = max(a, 0)
	}
	return a, max(a, b)
}

// The course tends to climb: half the time keep the higher of two draws.
@(private)
random_rise :: proc(g: ^Gen, lo, hi: int) -> int {
	r := rng.int_range(&g.r, lo, hi)
	if rng.chance(&g.r, 0.45) {
		r = max(r, rng.int_range(&g.r, lo, hi))
	}
	return r
}

@(private)
new_pad :: proc(rect: IRect, top: int, kind: Pad_Kind) -> Pad {
	return Pad{lo = rect.lo, hi = rect.hi, top = top, kind = kind, parent = -1, next = -1, mover = -1, shard = -1}
}

@(private)
pad_size :: proc(g: ^Gen, kind: Pad_Kind, branch: bool) -> [2]int {
	s := g.s
	switch kind {
	case .Goal:
		return {7, 7}
	case .Spawn:
		return {6, 6}
	case .Crumble:
		return {2, 2}
	case .Shuttle:
		return {3, 3}
	case .Spire:
		lo := 3 if s.size_min >= 4 else 2
		return {rng.int_range(&g.r, lo, 3), rng.int_range(&g.r, lo, 3)}
	case .Island:
	}
	if branch {
		lo := max(s.size_min-1, 2)
		return {rng.int_range(&g.r, lo, 4), rng.int_range(&g.r, lo, 4)}
	}
	return {rng.int_range(&g.r, s.size_min, s.size_max), rng.int_range(&g.r, s.size_min, s.size_max)}
}

@(private)
pad_depth :: proc(g: ^Gen, kind: Pad_Kind, size: [2]int) -> int {
	#partial switch kind {
	case .Spire:
		return SPIRE_DEPTH
	case .Goal:
		return 6
	case .Crumble, .Shuttle:
		return 1
	}
	if min(size[0], size[1]) >= 4 {
		return rng.int_range(&g.r, 3, 6)
	}
	return rng.int_range(&g.r, 2, 4)
}

// Volume a pad occupies, hanging crystals included.
@(private)
reserve_depth :: proc(p: Pad) -> int {
	#partial switch p.kind {
	case .Spire:
		return SPIRE_DEPTH
	case .Crumble, .Shuttle:
		return 1
	}
	return p.depth + 2
}

// Pad volume plus a one-cell margin and the air a jump needs above it.
@(private)
pad_box :: proc(r: IRect, top, depth, headroom: int) -> Box {
	return Box{lo = {r.lo[0] - 1, top - depth, r.lo[1] - 1}, hi = {r.hi[0] + 1, top + headroom, r.hi[1] + 1}}
}

// Air between two pads that must stay empty for the jump between them.
@(private)
corridor_box :: proc(a: IRect, a_top: int, b: IRect, b_top: int) -> Box {
	return Box{
		lo = {min(a.lo[0], b.lo[0]), min(a_top, b_top) - 1, min(a.lo[1], b.lo[1])},
		hi = {max(a.hi[0], b.hi[0]), max(a_top, b_top) + HEADROOM, max(a.hi[1], b.hi[1])},
	}
}

@(private)
box_union :: proc(a, b: Box) -> Box {
	return Box{
		lo = {min(a.lo[0], b.lo[0]), min(a.lo[1], b.lo[1]), min(a.lo[2], b.lo[2])},
		hi = {max(a.hi[0], b.hi[0]), max(a.hi[1], b.hi[1]), max(a.hi[2], b.hi[2])},
	}
}

box_overlap :: proc "contextless" (a, b: Box) -> bool {
	for i in 0..<3 {
		if a.lo[i] >= b.hi[i] || b.lo[i] >= a.hi[i] {
			return false
		}
	}
	return true
}

@(private)
add_reserve :: proc(g: ^Gen, box: Box, pad: int, corridor: bool) {
	if g.reserve_count < MAX_RESERVES {
		g.reserves[g.reserve_count] = Reserve{box = box, pad = pad, corridor = corridor}
		g.reserve_count += 1
	}
}

// A new pad may not sit in any flight path, and neither the pad nor its own
// flight path may touch another pad (its origin `from` excepted).
@(private)
can_place :: proc(g: ^Gen, box, corridor: Box, from: int) -> bool {
	for i in 0..<g.reserve_count {
		r := g.reserves[i]
		if r.corridor {
			if box_overlap(box, r.box) {
				return false
			}
		} else if r.pad != from {
			if box_overlap(box, r.box) || box_overlap(corridor, r.box) {
				return false
			}
		}
	}
	return true
}

@(private)
has_room :: proc(g: ^Gen, pads, movers: int) -> bool {
	w := g.w
	return w.pad_count+pads <= MAX_PADS && w.mover_count+movers <= MAX_MOVERS && g.reserve_count+2 <= MAX_RESERVES
}

@(private)
commit_pad :: proc(g: ^Gen, pad: Pad, box, corridor: Box) -> int {
	w := g.w
	idx := append_pad(w, pad)
	add_reserve(g, box, idx, false)
	add_reserve(g, corridor, -1, true)
	return idx
}

@(private)
append_pad :: proc(w: ^World, pad: Pad) -> int {
	idx := w.pad_count
	w.pads[idx] = pad
	w.pad_count += 1
	return idx
}

// Footprint `size` beyond `a` along d, `gap` cells away, shifted sideways by
// `lateral` relative to a's low side.
place_rect :: proc "contextless" (a: IRect, d: int, gap: int, size: [2]int, lateral: int) -> IRect {
	r: IRect
	switch d {
	case 0:
		r.lo = {a.lo[0] + lateral, a.hi[1] + gap}
	case 1:
		r.lo = {a.hi[0] + gap, a.lo[1] + lateral}
	case 2:
		r.lo = {a.lo[0] - gap - size[0], a.lo[1] + lateral}
	case:
		r.lo = {a.lo[0] + lateral, a.lo[1] - gap - size[1]}
	}
	r.hi = r.lo + size
	return r
}

// Sideways offset keeping at least `overlap` cells of shared width; `loose`
// sometimes slides one cell further for a diagonal jump.
@(private)
random_lateral :: proc(g: ^Gen, a: IRect, d: int, size: [2]int, overlap: int, loose: bool) -> int {
	ax := lateral_axis(d)
	la := a.hi[ax] - a.lo[ax]
	k := min(overlap, la, size[ax])
	lo := -(size[ax] - k)
	hi := la - k
	if loose && rng.chance(&g.r, 0.25) {
		return lo - 1 if rng.chance(&g.r, 0.5) else hi + 1
	}
	return rng.int_range(&g.r, lo, hi)
}

@(private)
try_jump_link :: proc(g: ^Gen, from, d: int, kind: Pad_Kind, branch: bool, rise_lo, rise_hi: int,
	forced_size := [2]int{}) -> int {
	w := g.w
	if !has_room(g, 1, 0) {
		return -1
	}
	a := w.pads[from]
	ar := pad_rect(a)
	size := forced_size if forced_size != {} else pad_size(g, kind, branch)
	rise := random_rise(g, rise_lo, rise_hi)
	limit := reach_at(w, rise, g.s.double_jump) * g.s.safety
	max_gap := int(math.floor(limit))
	if max_gap < 1 {
		return -1
	}
	gap := min(1+int(f32(max_gap)*math.pow(rng.float01(&g.r), 1.4)), max_gap)
	rect := place_rect(ar, d, gap, size, random_lateral(g, ar, d, size, 1, true))
	if rect_gap(ar, rect) > limit {
		return -1
	}
	pad := new_pad(rect, a.top+rise, kind)
	pad.depth = pad_depth(g, kind, size)
	pad.parent = from
	pad.link = .Jump
	pad.branch = branch
	headroom := HEADROOM + 2 if kind == .Goal else HEADROOM
	box := pad_box(rect, pad.top, reserve_depth(pad), headroom)
	corridor := corridor_box(ar, a.top, rect, pad.top)
	if !can_place(g, box, corridor, from) {
		return -1
	}
	return commit_pad(g, pad, box, corridor)
}

// A floating slab shuttling across a gap too wide to jump.
@(private)
try_shuttle_link :: proc(g: ^Gen, from, d: int) -> int {
	w := g.w
	if !has_room(g, 2, 1) {
		return -1
	}
	a := w.pads[from]
	ar := pad_rect(a)
	if ar.hi[lateral_axis(d)]-ar.lo[lateral_axis(d)] < 2 {
		return -1
	}
	msize := [2]int{3, 3}
	start := place_rect(ar, d, 1, msize, random_lateral(g, ar, d, msize, 2, false))
	travel := rng.int_range(&g.r, 3, 4+clamp(w.config.difficulty, 0, 2))
	dv := dir_vec(d)
	end := IRect{start.lo + dv*travel, start.hi + dv*travel}
	rise := rng.int_range(&g.r, -1, 1)
	bsize := pad_size(g, .Island, false)
	b_rect := place_rect(end, d, 1, bsize, random_lateral(g, end, d, bsize, 2, false))
	if rect_gap(end, b_rect) > reach_at(w, rise, g.s.double_jump)*g.s.safety ||
	   rect_gap(ar, start) > reach_at(w, 0, g.s.double_jump)*g.s.safety {
		return -1
	}
	b := new_pad(b_rect, a.top+rise, .Island)
	b.depth = pad_depth(g, .Island, bsize)
	b.link = .Jump
	box := pad_box(b_rect, b.top, reserve_depth(b), HEADROOM)
	corridor := corridor_box(ar, a.top, b_rect, b.top)
	if !can_place(g, box, corridor, from) {
		return -1
	}
	mi := w.mover_count
	tt := f32(travel) / 2.4
	period := 2 * (tt + SHUTTLE_PAUSE)
	w.movers[mi] = Mover{
		kind        = .Shuttle,
		size        = {3, 1, 3},
		a           = {f32(start.lo[0]), f32(a.top - 1), f32(start.lo[1])},
		b           = {f32(end.lo[0]), f32(a.top - 1), f32(end.lo[1])},
		travel_time = tt,
		period      = period,
		phase       = rng.float_range(&g.r, 0, period),
	}
	w.mover_count += 1
	mp := new_pad(start, a.top, .Shuttle)
	mp.depth = 1
	mp.parent = from
	mp.link = .Jump
	mp.mover = mi
	m_index := append_pad(w, mp)
	w.movers[mi].pad = m_index
	b.parent = m_index
	return commit_pad(g, b, box, corridor)
}

// Two or three small slabs that drop soon after being stepped on.
@(private)
try_crumble_link :: proc(g: ^Gen, from, d: int) -> int {
	w := g.w
	count := rng.int_range(&g.r, 2, 3)
	if !has_room(g, count+1, count) {
		return -1
	}
	a := w.pads[from]
	ar := pad_rect(a)
	hop := min(2, int(math.floor(reach_at(w, 0, false)*g.s.safety)))
	if hop < 1 {
		return -1
	}
	rects: [3]IRect
	cur := ar
	for i in 0..<count {
		size := [2]int{2, 2}
		rects[i] = place_rect(cur, d, rng.int_range(&g.r, 1, hop), size, random_lateral(g, cur, d, size, 1, false))
		cur = rects[i]
	}
	rise := rng.int_range(&g.r, -1, 1)
	last_hop := min(2, int(math.floor(reach_at(w, rise, false)*g.s.safety)))
	if last_hop < 1 {
		return -1
	}
	bsize := pad_size(g, .Island, false)
	b_rect := place_rect(cur, d, rng.int_range(&g.r, 1, last_hop), bsize, random_lateral(g, cur, d, bsize, 1, false))
	b := new_pad(b_rect, a.top+rise, .Island)
	b.depth = pad_depth(g, .Island, bsize)
	b.link = .Jump
	box := pad_box(b_rect, b.top, reserve_depth(b), HEADROOM)
	corridor := corridor_box(ar, a.top, b_rect, b.top)
	for i in 0..<count {
		r := rects[i]
		corridor = box_union(corridor, Box{lo = {r.lo[0], a.top - 2, r.lo[1]}, hi = {r.hi[0], a.top + HEADROOM, r.hi[1]}})
	}
	if !can_place(g, box, corridor, from) {
		return -1
	}
	prev := from
	for i in 0..<count {
		mi := w.mover_count
		pos := Vec3{f32(rects[i].lo[0]), f32(a.top - 1), f32(rects[i].lo[1])}
		w.movers[mi] = Mover{kind = .Crumble, size = {2, 1, 2}, a = pos, b = pos, position = pos}
		w.mover_count += 1
		cp := new_pad(rects[i], a.top, .Crumble)
		cp.depth = 1
		cp.parent = prev
		cp.link = .Jump
		cp.mover = mi
		prev = append_pad(w, cp)
		w.movers[mi].pad = prev
	}
	b.parent = prev
	return commit_pad(g, b, box, corridor)
}

// A plank walkway, sometimes missing a plank or two to hop over.
@(private)
try_bridge_link :: proc(g: ^Gen, from, d: int) -> int {
	w := g.w
	if w.bridge_count >= MAX_BRIDGES || !has_room(g, 1, 0) {
		return -1
	}
	a := w.pads[from]
	ar := pad_rect(a)
	lat := lateral_axis(d)
	along := 1 - lat
	width := 2 if w.config.difficulty == 0 else rng.int_range(&g.r, 1, 2)
	if ar.hi[lat]-ar.lo[lat] < width {
		return -1
	}
	gap := rng.int_range(&g.r, 3, 6)
	bsize := pad_size(g, .Island, false)
	bsize[lat] = max(bsize[lat], width)
	b_rect := place_rect(ar, d, gap, bsize, random_lateral(g, ar, d, bsize, width, false))
	ol := max(ar.lo[lat], b_rect.lo[lat])
	oh := min(ar.hi[lat], b_rect.hi[lat])
	if oh-ol < width {
		return -1
	}
	start := rng.int_range(&g.r, ol, oh-width)
	br := Bridge{from = from, axis = along, y = a.top - 1, holes = {-1, -1}, hole_len = 1}
	if dir_vec(d)[along] > 0 {
		br.lo[along] = ar.hi[along]
		br.hi[along] = b_rect.lo[along]
	} else {
		br.lo[along] = b_rect.hi[along]
		br.hi[along] = ar.lo[along]
	}
	br.lo[lat] = start
	br.hi[lat] = start + width
	length := br.hi[along] - br.lo[along]
	holes := min(g.s.bridge_holes, 2)
	if holes == 2 && length >= 5 {
		br.holes = {1, length - 2}
	} else if holes >= 1 {
		if w.config.difficulty >= 2 && length >= 5 {
			br.hole_len = 2
		}
		br.holes[0] = rng.int_range(&g.r, 1, length-1-br.hole_len)
	}
	b := new_pad(b_rect, a.top, .Island)
	b.depth = pad_depth(g, .Island, bsize)
	b.parent = from
	b.link = .Bridge
	box := pad_box(b_rect, b.top, reserve_depth(b), HEADROOM)
	corridor := corridor_box(ar, a.top, b_rect, b.top)
	if !can_place(g, box, corridor, from) {
		return -1
	}
	idx := commit_pad(g, b, box, corridor)
	br.to = idx
	w.bridges[w.bridge_count] = br
	w.bridge_count += 1
	return idx
}

bridge_hole :: proc "contextless" (b: Bridge, k: int) -> bool {
	for h in b.holes {
		if h >= 0 && k >= h && k < h+b.hole_len {
			return true
		}
	}
	return false
}

// Side branches climbing to a shard at their tip. Rises are never negative,
// so the way back down is always the easier jump.
@(private)
gen_branches :: proc(g: ^Gen, wanted: int, tips: []int) -> int {
	w := g.w
	candidates: [MAX_PATH]int
	n := 0
	for i in 1..<w.path_count-1 {
		p := w.path[i]
		if k := w.pads[p].kind; (k == .Island || k == .Spire) && w.pads[p].plan == .None {
			candidates[n] = p
			n += 1
		}
	}
	rng.shuffle(&g.r, candidates[:n])
	rise_hi := 1 if w.config.difficulty == 0 else 2
	count := 0
	for ci in 0..<n {
		if count >= wanted || count >= len(tips) {
			break
		}
		root := candidates[ci]
		dirs := [4]int{0, 1, 2, 3}
		rng.shuffle(&g.r, dirs[:])
		length := rng.int_range(&g.r, 1, g.s.branch_max)
		for d in dirs {
			cur := root
			placed := 0
			for _ in 0..<length {
				next := -1
				for _ in 0..<8 {
					kind := Pad_Kind.Spire if rng.chance(&g.r, 0.3) else Pad_Kind.Island
					next = try_jump_link(g, cur, d, kind, true, 0, rise_hi)
					if next >= 0 {
						break
					}
				}
				if next < 0 {
					break
				}
				cur = next
				placed += 1
			}
			if placed > 0 {
				tips[count] = cur
				count += 1
				break
			}
		}
	}
	return count
}

// Moves everything into positive voxel coordinates; returns the map size.
@(private)
shift_level :: proc(w: ^World) -> [3]int {
	lo := [3]int{max(int), max(int), max(int)}
	hi := [3]int{min(int), min(int), min(int)}
	grow :: proc(lo, hi: ^[3]int, a, b: [3]int) {
		for i in 0..<3 {
			lo[i] = min(lo[i], a[i])
			hi[i] = max(hi[i], b[i])
		}
	}
	for i in 0..<w.pad_count {
		p := w.pads[i]
		bottom := p.top - p.depth - 3
		if p.kind == .Spire {
			bottom = p.top - 2
		}
		grow(&lo, &hi, {p.lo[0], bottom, p.lo[1]}, {p.hi[0], p.top + 9, p.hi[1]})
	}
	for i in 0..<w.mover_count {
		m := w.movers[i]
		e := [3]int{int(m.b.x), int(m.b.y), int(m.b.z)}
		grow(&lo, &hi, e, e + {int(m.size.x), 1, int(m.size.z)})
	}
	margin := 3
	offset := [3]int{margin - lo[0], 1 - lo[1], margin - lo[2]}
	shift := Vec3{f32(offset[0]), f32(offset[1]), f32(offset[2])}
	flat := [2]int{offset[0], offset[2]}
	for i in 0..<w.pad_count {
		p := &w.pads[i]
		p.lo += flat
		p.hi += flat
		p.top += offset[1]
		if p.kind == .Spire {
			p.depth = p.top
		}
	}
	for i in 0..<w.mover_count {
		m := &w.movers[i]
		m.a += shift
		m.b += shift
		m.position += shift
	}
	for i in 0..<w.bridge_count {
		b := &w.bridges[i]
		b.lo += flat
		b.hi += flat
		b.y += offset[1]
	}
	return {hi[0] - lo[0] + 2*margin, hi[1] - lo[1] + 2, hi[2] - lo[2] + 2*margin}
}

@(private)
place_shard :: proc(w: ^World, pad: int, height: f32) -> bool {
	if w.shard_count >= MAX_SHARDS || w.pads[pad].shard >= 0 {
		return false
	}
	p := &w.pads[pad]
	c := pad_center(p^)
	w.shards[w.shard_count] = Shard{position = {c.x, f32(p.top) + height, c.y}, pad = pad}
	p.shard = w.shard_count
	w.shard_count += 1
	return true
}

// Shards the branches could not hold float high above path pads instead,
// where a jump grabs them.
@(private)
place_fallback_shards :: proc(g: ^Gen, total: int) {
	w := g.w
	candidates: [MAX_PADS]int
	n := 0
	for i in 1..<w.path_count-1 {
		p := w.path[i]
		if k := w.pads[p].kind; (k == .Island || k == .Spire) && w.pads[p].shard < 0 {
			candidates[n] = p
			n += 1
		}
	}
	rng.shuffle(&g.r, candidates[:n])
	// Pads kept for hazards are used only when nothing else is left.
	for pass in 0..<2 {
		for i in 0..<n {
			if w.shard_count >= total {
				return
			}
			if (w.pads[candidates[i]].plan == .None) == (pass == 0) {
				place_shard(w, candidates[i], 2.2)
			}
		}
	}
	for i in 0..<w.pad_count {
		if w.shard_count >= total {
			return
		}
		if w.pads[i].branch || w.pads[i].kind == .Spawn {
			place_shard(w, i, 2.2)
		}
	}
}

// Axis (0 = x, 1 = z) along which the player crosses a main path pad.
travel_axis :: proc(w: ^World, index: int) -> int {
	p := w.pads[index]
	if p.parent < 0 || p.next < 0 {
		return 1
	}
	diff := pad_center(w.pads[p.next]) - pad_center(w.pads[p.parent])
	return 0 if abs(diff.x) >= abs(diff.y) else 1
}

// Footprint of a pad built for a hazard: long enough along d for a band in
// the middle with room on both sides, and wide enough for a patrol.
@(private)
hazard_size :: proc(g: ^Gen, plan: Hazard_Plan, d: int) -> [2]int {
	along, across := rng.int_range(&g.r, 5, 6), rng.int_range(&g.r, 3, 5)
	if plan == .Sentinel {
		along, across = rng.int_range(&g.r, 4, 5), 5
	}
	size: [2]int
	size[lateral_axis(d)] = across
	size[1-lateral_axis(d)] = along
	return size
}

// Respawn point on the arrival side of a hazard band [block_lo, block_hi).
@(private)
entry_point :: proc(w: ^World, index, axis: int, block_lo, block_hi: f32) -> Vec3 {
	p := w.pads[index]
	r := pad_center(p)
	from := pad_center(w.pads[p.parent])
	if from[axis] < r[axis] {
		r[axis] = (f32(p.lo[axis]) + block_lo) * 0.5
	} else {
		r[axis] = (block_hi + f32(p.hi[axis])) * 0.5
	}
	return Vec3{r.x, f32(p.top), r.y}
}

@(private)
has_branch :: proc(w: ^World, index: int) -> bool {
	for i in 0..<w.pad_count {
		if w.pads[i].branch && w.pads[i].parent == index {
			return true
		}
	}
	return false
}

@(private)
hazard_candidates :: proc(g: ^Gen, out: []int, want: Hazard_Plan, min_along, min_lateral: int) -> int {
	w := g.w
	n := 0
	for i in 2..<w.path_count-1 {
		index := w.path[i]
		p := w.pads[index]
		if p.kind != .Island || p.shard >= 0 || p.hazard || p.next < 0 || p.parent < 0 {
			continue
		}
		if p.plan != .None && p.plan != want {
			continue
		}
		// Never two hazards back to back, and never right where a jump lands
		// from a moving slab.
		if w.pads[p.parent].hazard || w.pads[p.next].hazard || w.pads[p.parent].mover >= 0 {
			continue
		}
		axis := travel_axis(w, index)
		if p.hi[axis]-p.lo[axis] < min_along || p.hi[1-axis]-p.lo[1-axis] < min_lateral {
			continue
		}
		// The band lies across the travel axis, so the course must arrive on
		// one side of the pad and leave from the other.
		q := w.pads[p.parent]
		r := w.pads[p.next]
		through := (q.hi[axis] <= p.lo[axis] && r.lo[axis] >= p.hi[axis]) ||
			(q.lo[axis] >= p.hi[axis] && r.hi[axis] <= p.lo[axis])
		if !through || has_branch(w, index) {
			continue
		}
		if n < len(out) {
			out[n] = index
			n += 1
		}
	}
	rng.shuffle(&g.r, out[:n])
	// Pads built for this hazard come first.
	front := 0
	for i in 0..<n {
		if w.pads[out[i]].plan == want {
			out[front], out[i] = out[i], out[front]
			front += 1
		}
	}
	return n
}

@(private)
place_spikes :: proc(g: ^Gen) {
	w := g.w
	candidates: [MAX_PATH]int
	n := hazard_candidates(g, candidates[:], .Spikes, 5, 2)
	difficulty := clamp(w.config.difficulty, 0, 2)
	for k in 0..<n {
		if w.spike_count >= min(g.s.spikes, MAX_SPIKES) {
			break
		}
		index := candidates[k]
		p := &w.pads[index]
		if p.hazard || w.pads[p.parent].hazard || w.pads[p.next].hazard {
			continue
		}
		axis := travel_axis(w, index)
		lat := 1 - axis
		length := p.hi[axis] - p.lo[axis]
		width := 2 if difficulty == 2 && length >= 6 else 1
		mid := p.lo[axis] + (length-width)/2
		lo, hi: Vec2
		lo[axis] = f32(mid)
		hi[axis] = f32(mid + width)
		lo[lat] = f32(p.lo[lat])
		hi[lat] = f32(p.hi[lat])
		period := 2.4 - 0.2*f32(difficulty)
		w.spikes[w.spike_count] = Spikes{lo = lo, hi = hi, top = f32(p.top), period = period,
			phase = rng.float_range(&g.r, 0, period), pad = index}
		w.spike_count += 1
		p.hazard = true
		p.respawn = entry_point(w, index, axis, f32(mid), f32(mid+width))
	}
}

@(private)
place_sentinels :: proc(g: ^Gen) {
	w := g.w
	candidates: [MAX_PATH]int
	n := hazard_candidates(g, candidates[:], .Sentinel, 4, 5)
	difficulty := clamp(w.config.difficulty, 0, 2)
	for k in 0..<n {
		if w.sentinel_count >= min(g.s.sentinels, MAX_SENTINELS) {
			break
		}
		index := candidates[k]
		p := &w.pads[index]
		if p.hazard || w.pads[p.parent].hazard || w.pads[p.next].hazard {
			continue
		}
		axis := travel_axis(w, index)
		lat := 1 - axis
		mid := f32(p.lo[axis]+p.hi[axis]) * 0.5
		a, b: Vec3
		a.y = f32(p.top) + 0.75
		b.y = a.y
		along := 0 if axis == 0 else 2
		across := 2 - along
		a[along] = mid
		b[along] = mid
		a[across] = f32(p.lo[lat]) + 0.6
		b[across] = f32(p.hi[lat]) - 0.6
		w.sentinels[w.sentinel_count] = Sentinel{a = a, b = b, speed = 1.7 + 0.35*f32(difficulty),
			phase = rng.float_range(&g.r, 0, 2), pad = index, position = a}
		w.sentinel_count += 1
		p.hazard = true
		p.respawn = entry_point(w, index, axis, mid-1, mid+1)
	}
}

@(private)
set_cell :: proc(w: ^World, x, y, z: int, m: Material) {
	physics.voxel_set(&w.terrain, x, y, z, u8(m))
}

@(private)
write_terrain :: proc(g: ^Gen) {
	w := g.w
	for i in 0..<w.pad_count {
		p := w.pads[i]
		switch p.kind {
		case .Spawn, .Island, .Goal:
			write_island(g, p)
		case .Spire:
			write_spire(g, p)
		case .Crumble, .Shuttle:
		}
	}
	for i in 0..<w.bridge_count {
		write_bridge(w, w.bridges[i])
	}
	// Spawn: braziers (drawn props, no collision) on the back corners and a
	// rune ring in the floor.
	s := w.pads[0]
	for x in ([2]f32{f32(s.lo[0]) + 0.6, f32(s.hi[0]) - 0.6}) {
		add_brazier(w, Vec3{x, f32(s.top), f32(s.lo[1]) + 0.6})
	}
	c := pad_center(s)
	for z in s.lo[1]..<s.hi[1] {
		for x in s.lo[0]..<s.hi[0] {
			if abs(f32(x)+0.5-c.x)+abs(f32(z)+0.5-c.y) == 2 {
				set_cell(w, x, s.top-1, z, .Rune)
			}
		}
	}
}

@(private)
add_brazier :: proc(w: ^World, p: Vec3) {
	if w.brazier_count < MAX_BRAZIERS {
		w.braziers[w.brazier_count] = p
		w.brazier_count += 1
	}
}

@(private)
write_island :: proc(g: ^Gen, p: Pad) {
	w := g.w
	r := &g.r
	lo, hi := p.lo, p.hi
	mossy := p.kind == .Island && rng.chance(r, 0.55)
	for layer in 0..<p.depth {
		y := p.top - 1 - layer
		if layer >= 2 {
			// Taper the underside into a hanging rock.
			for axis in 0..<2 {
				if hi[axis]-lo[axis] > 1 && rng.chance(r, 0.6) {
					lo[axis] += 1
				}
				if hi[axis]-lo[axis] > 1 && rng.chance(r, 0.6) {
					hi[axis] -= 1
				}
			}
		}
		for z in lo[1]..<hi[1] {
			for x in lo[0]..<hi[0] {
				edge := x == lo[0] || x == hi[0]-1 || z == lo[1] || z == hi[1]-1
				mat := Material.Stone
				switch {
				case layer == 0:
					mat = .Moss if mossy else .Stone_Top
				case layer == 1 && mossy && edge && rng.chance(r, 0.4):
					mat = .Moss
				case layer >= 3:
					mat = .Stone_Dark
				}
				if layer >= 2 && edge && rng.chance(r, 0.05) {
					mat = .Ember
				}
				set_cell(w, x, y, z, mat)
			}
		}
	}
	bottom := p.top - p.depth - 1
	if rng.chance(r, 0.45) {
		x := rng.int_range(r, lo[0], hi[0]-1)
		z := rng.int_range(r, lo[1], hi[1]-1)
		for k in 0..<rng.int_range(r, 1, 2) {
			set_cell(w, x, bottom-k, z, .Crystal)
		}
	}
}

@(private)
write_spire :: proc(g: ^Gen, p: Pad) {
	w := g.w
	ring := p.top - 3 - rng.int_range(&g.r, 0, 2)
	for y in 0..<p.top {
		for z in p.lo[1]..<p.hi[1] {
			for x in p.lo[0]..<p.hi[0] {
				mat := Material.Stone_Dark if (y/2)%3 == 0 else Material.Stone
				if y == p.top-1 {
					mat = .Stone_Top
				} else if y == ring && rng.chance(&g.r, 0.22) {
					mat = .Ember
				}
				set_cell(w, x, y, z, mat)
			}
		}
	}
}

@(private)
write_bridge :: proc(w: ^World, b: Bridge) {
	along := b.axis
	lat := 1 - along
	for a in b.lo[along]..<b.hi[along] {
		k := a - b.lo[along]
		if bridge_hole(b, k) {
			continue
		}
		for l in b.lo[lat]..<b.hi[lat] {
			cell: [2]int
			cell[along] = a
			cell[lat] = l
			set_cell(w, cell[0], b.y, cell[1], .Stone_Dark if k%3 == 2 else .Plank)
		}
	}
}

// The sanctuary arch, facing the way the player arrives, one cell in from
// the far edge so a sealed portal never walks anyone off the island.
@(private)
build_portal :: proc(g: ^Gen) {
	w := g.w
	index := w.path[w.path_count-1]
	p := w.pads[index]
	diff := pad_center(p) - pad_center(w.pads[p.parent])
	axis := 0 if abs(diff.x) >= abs(diff.y) else 1
	lat := 1 - axis
	row := p.hi[axis] - 2 if diff[axis] > 0 else p.lo[axis] + 1
	mid := (p.lo[lat] + p.hi[lat]) / 2
	put :: proc(w: ^World, axis, along, side, y: int, m: Material) {
		cell: [2]int
		cell[axis] = along
		cell[1-axis] = side
		set_cell(w, cell[0], y, cell[1], m)
	}
	for y in p.top..<p.top+5 {
		put(w, axis, row, mid-2, y, .Rune if y == p.top+4 else .Stone_Dark)
		put(w, axis, row, mid+2, y, .Rune if y == p.top+4 else .Stone_Dark)
	}
	for side in mid-2..=mid+2 {
		put(w, axis, row, side, p.top+5, .Stone)
	}
	put(w, axis, row, mid, p.top+6, .Rune)
	// A rune path on the floor leading to the arch.
	from := p.lo[axis] if diff[axis] > 0 else p.hi[axis]-1
	step := 1 if diff[axis] > 0 else -1
	for a := from; a != row; a += step {
		put(w, axis, a, mid, p.top-1, .Rune)
	}
	for side in ([2]int{mid - 3, mid + 3}) {
		b: [2]f32
		b[axis] = f32(row) + 0.5
		b[lat] = f32(side) + 0.5
		add_brazier(w, Vec3{b[0], f32(p.top), b[1]})
	}
	w.portal_axis = axis
	c: [2]f32
	c[axis] = f32(row) + 0.5
	c[lat] = f32(mid) + 0.5
	w.portal_center = Vec3{c[0], f32(p.top) + 2.3, c[1]}
	lo, hi: [2]f32
	lo[axis] = f32(row) + 0.2
	hi[axis] = f32(row) + 0.8
	lo[lat] = f32(mid - 1)
	hi[lat] = f32(mid + 2)
	w.portal_lo = Vec3{lo[0], f32(p.top), lo[1]}
	w.portal_hi = Vec3{hi[0], f32(p.top) + 4.5, hi[1]}
}

// Distant spires ringing the course, outside its bounds.
@(private)
place_decor :: proc(g: ^Gen) {
	w := g.w
	size := physics.voxel_world_size(&w.terrain)
	center := Vec3{size.x * 0.5, 0, size.z * 0.5}
	radius := math.sqrt(size.x*size.x+size.z*size.z)*0.5 + 10
	for i in 0..<MAX_FAR {
		angle := f32(i)/f32(MAX_FAR)*math.TAU + rng.float_range(&g.r, -0.12, 0.12)
		dist := radius + rng.float_range(&g.r, 4, 26)
		w.far[i] = Far_Spire{
			position = {center.x + math.cos(angle)*dist, -24, center.z + math.sin(angle)*dist},
			width    = rng.float_range(&g.r, 2.5, 6),
			height   = rng.float_range(&g.r, 24, size.y+30),
		}
	}
	w.far_count = MAX_FAR
}
