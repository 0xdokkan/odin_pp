// Pure simulation of the crypt crawl: maze, player, enemies, projectiles,
// pickups and the exit portal. Nothing here touches raylib, so the tests run
// the whole game headless from scripted inputs.
package fps

import "core:math"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"

Vec2 :: [2]f32
Vec3 :: [3]f32

SIM_HZ :: 120
// One maze cell is three open voxels plus one voxel of wall.
CELL_VOXELS :: 4
MAX_SIDE :: MAX_CELLS*CELL_VOXELS + 1
MAX_COLUMNS :: MAX_SIDE * MAX_SIDE
MAP_HEIGHT :: 6
FLOOR_Y :: f32(1) // top of the floor voxels
FLOW_UNREACHED :: i32(1 << 28)

MAX_ENEMIES :: 40
MAX_PROJECTILES :: 48
MAX_PICKUPS :: 64
MAX_EVENTS :: 96
RUNE_SCORE :: 500

// Voxel materials; the renderer gives each one a colour.
Material :: enum u8 {
	None,
	Floor,
	Floor_Cracked,
	Floor_Room_A,
	Floor_Room_B,
	Ceiling,
	Slate,
	Slate_Trim,
	Moss,
	Moss_Trim,
	Brick,
	Brick_Trim,
	Obsidian,
	Obsidian_Trim,
	Glyph,
	Pillar,
	Arch,
}

// Round parameters derived from the config. Challenge rounds (inside a
// roguelike run) use a smaller crypt and softer enemies.
Tuning :: struct {
	cells:        int,
	rooms:        int,
	runes:        int,
	enemies:      int,
	health_packs: int,
	mana_packs:   int,
	wave:         int,
	loop_chance:  f32,
	damage_scale: f32,
	speed_scale:  f32,
	// Fraction of the player's velocity cultists lead their bolts by.
	lead:         f32,
}

tuning_for :: proc(config: host.Minigame_Config) -> Tuning {
	d := clamp(config.difficulty, 0, 2)
	t: Tuning
	speed := [3]f32{0.88, 1, 1.12}
	lead := [3]f32{0, 0.5, 0.85}
	loops := [3]f32{0.14, 0.11, 0.08}
	t.speed_scale = speed[d]
	t.lead = lead[d]
	t.loop_chance = loops[d]
	if config.challenge {
		cells := [3]int{6, 7, 7}
		rooms := [3]int{4, 4, 5}
		runes := [3]int{2, 3, 3}
		enemies := [3]int{4, 6, 8}
		health := [3]int{3, 3, 3}
		mana := [3]int{2, 2, 2}
		wave := [3]int{1, 2, 2}
		damage := [3]f32{0.55, 0.75, 0.95}
		t.cells, t.rooms, t.runes, t.enemies = cells[d], rooms[d], runes[d], enemies[d]
		t.health_packs, t.mana_packs, t.wave, t.damage_scale = health[d], mana[d], wave[d], damage[d]
	} else {
		cells := [3]int{8, 9, 10}
		rooms := [3]int{5, 6, 7}
		runes := [3]int{3, 4, 5}
		enemies := [3]int{8, 11, 15}
		health := [3]int{5, 5, 4}
		mana := [3]int{4, 3, 3}
		wave := [3]int{2, 3, 4}
		damage := [3]f32{0.7, 1, 1.3}
		t.cells, t.rooms, t.runes, t.enemies = cells[d], rooms[d], runes[d], enemies[d]
		t.health_packs, t.mana_packs, t.wave, t.damage_scale = health[d], mana[d], wave[d], damage[d]
	}
	return t
}

// Desired actions for one step, already in simulation units.
Player_Input :: struct {
	move:   Vec2, // x strafes right, y walks forward; length <= 1
	look:   Vec2, // radians added to yaw (positive turns left) and pitch (positive looks up)
	sprint: bool,
	jump:   bool, // edge: pressed this step
	fire:   bool, // held
}

Player :: struct {
	body:        physics.Body3,
	prev_eye:    Vec3,
	yaw, pitch:  f32,
	hp, mana:    f32,
	mana_delay:  f32,
	fire_cd:     f32,
	invuln:      f32,
	jump_buffer: f32,
	grounded:    bool,
	sprinting:   bool,
	speed:       f32, // horizontal speed, drives head bob
	stride:      f32,
}

Enemy_Kind :: enum u8 {
	Ghoul,
	Wraith,
	Cultist,
}

Enemy_State :: enum u8 {
	Idle,
	Chase,
	Windup,
	Strike,
	Recover,
	Dead,
}

Enemy :: struct {
	kind:        Enemy_Kind,
	state:       Enemy_State,
	body:        physics.Body3,
	prev_feet:   Vec3,
	hp:          f32,
	state_time:  f32,
	attack_cd:   f32,
	hurt_time:   f32,
	anim:        f32, // distance walked, drives the walk cycle
	lost_time:   f32,
	alerted:     bool,
	sees:        bool,
	wander_dir:  Vec2,
	wander_time: f32,
	strafe:      f32,
	strafe_time: f32,
	lunge:       Vec2,
	lunge_hit:   bool,
	push:        Vec2, // knockback velocity
	facing:      Vec2,
	phase:       f32, // per-enemy offset for idle animation
}

Projectile :: struct {
	alive:    bool,
	position: Vec3,
	previous: Vec3,
	velocity: Vec3,
	life:     f32,
	damage:   f32,
}

Pickup_Kind :: enum u8 {
	Health,
	Mana,
	Rune,
}

Pickup :: struct {
	kind:     Pickup_Kind,
	position: Vec3, // on the floor; the renderer floats it
	taken:    bool,
	phase:    f32,
}

Portal :: struct {
	// Centre of the opening between the two arch pillars.
	center:      Vec3,
	open:        bool,
	open_time:   f32,
	sealed_wait: f32,
}

Event_Kind :: enum u8 {
	Shot,
	Dry_Fire,
	Wall_Hit,
	Enemy_Hit,
	Enemy_Killed,
	Projectile_Shot_Down,
	Enemy_Alert,
	Enemy_Windup,
	Enemy_Strike,
	Enemy_Cast,
	Projectile_Burst,
	Player_Hurt,
	Pickup_Health,
	Pickup_Mana,
	Rune_Taken,
	Portal_Open,
	Portal_Sealed,
	Jump,
	Land,
	Footstep,
	Escaped,
	Died,
	Wave,
}

// Something the renderer and audio react to, recorded during one step.
Event :: struct {
	kind:     Event_Kind,
	position: Vec3,
	normal:   Vec3,
	value:    f32,
	enemy:    Enemy_Kind,
	index:    int,
}

Stats :: struct {
	shots:        int,
	hits:         int,
	kills:        int,
	kill_score:   int,
	parries:      int,
	damage_taken: f32,
}

World :: struct {
	config:       host.Minigame_Config,
	tuning:       Tuning,
	rng:          rng.Rng,
	maze:         Maze,
	voxels:       physics.Voxel_Map,
	side:         int, // voxel columns per side
	walkable:     [MAX_COLUMNS]bool,
	explored:     [MAX_COLUMNS]bool,
	// BFS distance (in columns) from the player, steering every chaser.
	flow:         [MAX_COLUMNS]i32,
	flow_origin:  int,
	queue:        [MAX_COLUMNS]i32,
	player:       Player,
	enemies:      [MAX_ENEMIES]Enemy,
	enemy_count:  int,
	projectiles:  [MAX_PROJECTILES]Projectile,
	pickups:      [MAX_PICKUPS]Pickup,
	pickup_count: int,
	rune_count:   int,
	runes_taken:  int,
	portal:       Portal,
	spawn:        Vec3,
	spawn_yaw:    f32,
	status:       host.Round_Status,
	time:         f32,
	steps:        u64,
	par_time:     f32,
	stats:        Stats,
	events:       [MAX_EVENTS]Event,
	event_count:  int,
	dropped_events: int,
	wave_spawned: bool,
	bot:          Bot,
}

world_destroy :: proc(w: ^World) {
	if w.voxels.cells != nil {
		physics.voxel_map_destroy(&w.voxels)
	}
}

// Builds the whole round from the config: same seed, same crypt.
world_reset :: proc(w: ^World, config: host.Minigame_Config) {
	world_destroy(w)
	w^ = {}
	w.config = config
	w.tuning = tuning_for(config)
	w.rng = rng.create(rng.derive(config.seed, 1))
	gen := rng.create(rng.derive(config.seed, 2))
	maze_generate(&w.maze, w.tuning.cells, w.tuning.rooms, w.tuning.loop_chance, &gen)
	build_voxels(w, &gen)
	compute_walkable(w)
	place_player(w)
	place_objects(w, &gen)
	w.flow_origin = -1
	update_flow(w)
	w.par_time = estimate_par_time(w)
	explore(w)
	w.bot.target = -1
}

emit_event :: proc(w: ^World, e: Event) {
	if w.event_count >= MAX_EVENTS {
		w.dropped_events += 1
		return
	}
	w.events[w.event_count] = e
	w.event_count += 1
}

// ---------------------------------------------------------------------------
// Grid helpers

tile_of_voxel :: proc "contextless" (v: int) -> int {
	q := v / CELL_VOXELS
	if v%CELL_VOXELS == 0 {
		return 2 * q
	}
	return 2*q + 1
}

cell_center :: proc "contextless" (cx, cy: int) -> Vec3 {
	return Vec3{f32(cx*CELL_VOXELS) + 2.5, FLOOR_Y, f32(cy*CELL_VOXELS) + 2.5}
}

// Centre voxel of a room; rooms span an odd number of voxels.
room_center_voxel :: proc "contextless" (room: Room) -> [2]int {
	lo_x, hi_x := room.x*CELL_VOXELS + 1, (room.x+room.w)*CELL_VOXELS - 1
	lo_z, hi_z := room.y*CELL_VOXELS + 1, (room.y+room.h)*CELL_VOXELS - 1
	return {(lo_x + hi_x) / 2, (lo_z + hi_z) / 2}
}

column_xz :: proc "contextless" (w: ^World, x, z: int) -> int {
	if x < 0 || z < 0 || x >= w.side || z >= w.side {
		return -1
	}
	return z*w.side + x
}

column_of :: proc "contextless" (w: ^World, p: Vec3) -> int {
	return column_xz(w, int(math.floor(p.x)), int(math.floor(p.z)))
}

column_center :: proc "contextless" (w: ^World, col: int) -> Vec3 {
	return Vec3{f32(col%w.side) + 0.5, FLOOR_Y, f32(col/w.side) + 0.5}
}

walkable_xz :: proc "contextless" (w: ^World, x, z: int) -> bool {
	col := column_xz(w, x, z)
	return col >= 0 && w.walkable[col]
}

// Which maze cell a voxel column belongs to (walls go to the cell after them).
column_cell :: proc "contextless" (w: ^World, x, z: int) -> [2]int {
	return {clamp(x/CELL_VOXELS, 0, w.maze.cells-1), clamp(z/CELL_VOXELS, 0, w.maze.cells-1)}
}

// 0 near the antechamber, 2 in the deepest third of the crypt.
column_zone :: proc "contextless" (w: ^World, x, z: int) -> int {
	c := column_cell(w, x, z)
	d := w.maze.cell_dist[cell_index(&w.maze, c.x, c.y)]
	if d < 0 {
		return 0
	}
	return clamp(int(d*3/(w.maze.max_dist+1)), 0, 2)
}

// ---------------------------------------------------------------------------
// Generation

@(private)
build_voxels :: proc(w: ^World, r: ^rng.Rng) {
	m := &w.maze
	w.side = m.cells*CELL_VOXELS + 1
	// Outside counts as solid: the shell faces are culled and nothing leaves.
	w.voxels, _ = physics.voxel_map_create(w.side, MAP_HEIGHT, w.side, 1, outside = 1)
	vm := &w.voxels
	for z in 0..<w.side {
		for x in 0..<w.side {
			tx, tz := tile_of_voxel(x), tile_of_voxel(z)
			room := tile_room(m, tx, tz)
			if tile_open(m, tx, tz) {
				floor := Material.Floor
				if room >= 0 {
					floor = .Floor_Room_A if (x+z)%2 == 0 else .Floor_Room_B
				} else if rng.chance(r, 0.2) {
					floor = .Floor_Cracked
				}
				physics.voxel_set(vm, x, 0, z, u8(floor))
				// Halls get a vaulted ceiling one voxel higher than corridors.
				top := 5 if room >= 0 else 4
				for y in top..<MAP_HEIGHT {
					physics.voxel_set(vm, x, y, z, u8(Material.Ceiling))
				}
				continue
			}
			if room >= 0 {
				for y in 0..<MAP_HEIGHT {
					physics.voxel_set(vm, x, y, z, u8(Material.Pillar))
				}
				continue
			}
			c := column_cell(w, x, z)
			base, trim := Material.Slate, Material.Slate_Trim
			if cell_room(m, c.x, c.y) == m.exit_room {
				base, trim = .Obsidian, .Obsidian_Trim
			} else {
				switch column_zone(w, x, z) {
				case 1:
					base, trim = .Moss, .Moss_Trim
				case 2:
					base, trim = .Brick, .Brick_Trim
				}
			}
			for y in 0..<MAP_HEIGHT {
				mat := base
				if y == 1 || y == 3 {
					mat = trim
				}
				if y == 2 && rng.chance(r, 0.03) {
					mat = .Glyph
				}
				physics.voxel_set(vm, x, y, z, u8(mat))
			}
		}
	}
	build_arch(w)
}

// Two pillars and a lintel in the middle of the exit hall frame the portal.
@(private)
build_arch :: proc(w: ^World) {
	room := w.maze.rooms[w.maze.exit_room]
	c := room_center_voxel(room)
	vm := &w.voxels
	for y in 1..=3 {
		physics.voxel_set(vm, c.x-1, y, c.y, u8(Material.Arch))
		physics.voxel_set(vm, c.x+2, y, c.y, u8(Material.Arch))
	}
	for x in c.x-1..=c.x+2 {
		physics.voxel_set(vm, x, 4, c.y, u8(Material.Arch))
	}
	w.portal.center = Vec3{f32(c.x) + 1, FLOOR_Y + 1.5, f32(c.y) + 0.5}
}

@(private)
compute_walkable :: proc(w: ^World) {
	vm := &w.voxels
	for z in 0..<w.side {
		for x in 0..<w.side {
			w.walkable[z*w.side+x] = physics.voxel_get(vm, x, 0, z) != 0 &&
				physics.voxel_get(vm, x, 1, z) == 0 && physics.voxel_get(vm, x, 2, z) == 0
		}
	}
}

PLAYER_SIZE :: Vec3{0.6, 1.7, 0.6}
EYE_HEIGHT :: f32(1.55)
MAX_HP :: f32(100)
MAX_MANA :: f32(100)

@(private)
place_player :: proc(w: ^World) {
	room := w.maze.rooms[w.maze.spawn_room]
	c := room_center_voxel(room)
	feet := Vec3{f32(c.x) + 0.5, FLOOR_Y, f32(c.y) + 0.5}
	w.spawn = feet
	middle := f32(w.side) * 0.5
	w.spawn_yaw = math.atan2(middle-feet.x, middle-feet.z)
	p := &w.player
	p.body = physics.Body3{position = feet - Vec3{PLAYER_SIZE.x * 0.5, 0, PLAYER_SIZE.z * 0.5}, size = PLAYER_SIZE}
	p.yaw = w.spawn_yaw
	p.hp = MAX_HP
	p.mana = MAX_MANA
	p.grounded = true
	p.prev_eye = player_eye(p^)
}

@(private)
Spot :: struct {
	cell:     [2]int,
	position: Vec3,
	used:     bool,
}

MAX_SPOTS :: MAX_MAZE_CELLS

@(private)
place_objects :: proc(w: ^World, r: ^rng.Rng) {
	m := &w.maze
	// Candidate spots: dead ends first, then a random cell of each hall.
	spots: [MAX_SPOTS]Spot
	count := 0
	for cy in 0..<m.cells {
		for cx in 0..<m.cells {
			if is_dead_end(m, cx, cy) && m.cell_dist[cell_index(m, cx, cy)] >= 2 {
				spots[count] = Spot{cell = {cx, cy}, position = cell_center(cx, cy)}
				count += 1
			}
		}
	}
	for i in 0..<m.room_count {
		if i == m.spawn_room || i == m.exit_room {
			continue
		}
		room := m.rooms[i]
		cx := room.x + rng.int_range(r, 0, room.w-1)
		cy := room.y + rng.int_range(r, 0, room.h-1)
		spots[count] = Spot{cell = {cx, cy}, position = cell_center(cx, cy)}
		count += 1
	}
	exit_cell := room_center_cell(m.rooms[m.exit_room])
	spawn_cell := room_center_cell(m.rooms[m.spawn_room])

	// Runes: farthest-point sampling, so they are spread over the crypt and
	// away from both the start and the exit.
	chosen: [8][2]int
	chosen[0] = spawn_cell
	chosen[1] = exit_cell
	chosen_count := 2
	w.rune_count = 0
	for _ in 0..<w.tuning.runes {
		best, best_score := -1, f32(-1)
		for i in 0..<count {
			if spots[i].used {
				continue
			}
			nearest := f32(1e9)
			for j in 0..<chosen_count {
				d := Vec2{f32(spots[i].cell.x - chosen[j].x), f32(spots[i].cell.y - chosen[j].y)}
				nearest = min(nearest, d.x*d.x + d.y*d.y)
			}
			depth := f32(m.cell_dist[cell_index(m, spots[i].cell.x, spots[i].cell.y)])
			score := nearest + depth*0.4 + rng.float01(r)*0.5
			if score > best_score {
				best, best_score = i, score
			}
		}
		if best < 0 {
			break
		}
		spots[best].used = true
		if chosen_count < len(chosen) {
			chosen[chosen_count] = spots[best].cell
			chosen_count += 1
		}
		add_pickup(w, .Rune, spots[best].position, r)
		w.rune_count += 1
	}
	// Fallback for tiny mazes: any reachable corridor cell far from spawn.
	for w.rune_count < w.tuning.runes {
		cx, cy := rng.int_range(r, 0, m.cells-1), rng.int_range(r, 0, m.cells-1)
		if cell_room(m, cx, cy) >= 0 || m.cell_dist[cell_index(m, cx, cy)] < 2 {
			continue
		}
		add_pickup(w, .Rune, cell_center(cx, cy), r)
		w.rune_count += 1
	}

	// Supplies go to leftover spots, then to random corridor cells.
	place_supply :: proc(w: ^World, kind: Pickup_Kind, n: int, spots: []Spot, r: ^rng.Rng) {
		m := &w.maze
		for _ in 0..<n {
			placed := false
			start := int(rng.below(r, u64(max(len(spots), 1))))
			for k in 0..<len(spots) {
				i := (start + k) % len(spots)
				if !spots[i].used {
					spots[i].used = true
					add_pickup(w, kind, spots[i].position, r)
					placed = true
					break
				}
			}
			for tries := 0; !placed && tries < 200; tries += 1 {
				cx, cy := rng.int_range(r, 0, m.cells-1), rng.int_range(r, 0, m.cells-1)
				if cell_room(m, cx, cy) == m.spawn_room || cell_room(m, cx, cy) == m.exit_room {
					continue
				}
				offset := Vec3{rng.float_signed(r), 0, rng.float_signed(r)} * 0.8
				add_pickup(w, kind, cell_center(cx, cy)+offset, r)
				placed = true
			}
		}
	}
	place_supply(w, .Health, w.tuning.health_packs, spots[:count], r)
	place_supply(w, .Mana, w.tuning.mana_packs, spots[:count], r)

	// Enemies: some guard runes, the rest roam cells away from the start.
	cells: [MAX_MAZE_CELLS][2]int
	n := 0
	for cy in 0..<m.cells {
		for cx in 0..<m.cells {
			room := cell_room(m, cx, cy)
			if room == m.spawn_room || room == m.exit_room || m.cell_dist[cell_index(m, cx, cy)] < 3 ||
			   !far_from_spawn(w, cell_center(cx, cy)) {
				continue
			}
			cells[n] = {cx, cy}
			n += 1
		}
	}
	rng.shuffle(r, cells[:n])
	guards := w.tuning.enemies / 3
	for i in 0..<w.pickup_count {
		if guards <= 0 {
			break
		}
		pk := w.pickups[i]
		if pk.kind != .Rune || !far_from_spawn(w, pk.position) {
			continue
		}
		offset := Vec3{rng.float_signed(r), 0, rng.float_signed(r)} * 0.9
		kind := Enemy_Kind.Cultist if rng.chance(r, 0.5) else Enemy_Kind.Ghoul
		spawn_enemy(w, kind, pk.position+offset, r)
		guards -= 1
	}
	next := 0
	for w.enemy_count < w.tuning.enemies && n > 0 {
		c := cells[next % n]
		next += 1
		offset := Vec3{rng.float_signed(r), 0, rng.float_signed(r)} * 0.7
		spawn_enemy(w, pick_kind(w, c, next-1, r), cell_center(c.x, c.y)+offset, r)
	}
}

// Nothing hostile starts near the antechamber, even behind a wall.
SAFE_RADIUS :: f32(8)

@(private)
far_from_spawn :: proc "contextless" (w: ^World, p: Vec3) -> bool {
	d := p - w.spawn
	return d.x*d.x+d.z*d.z > SAFE_RADIUS*SAFE_RADIUS
}

// The first three enemies cover every kind; deeper zones favour casters.
@(private)
pick_kind :: proc(w: ^World, cell: [2]int, index: int, r: ^rng.Rng) -> Enemy_Kind {
	if index < 3 {
		return Enemy_Kind(index)
	}
	zone := column_zone(w, cell.x*CELL_VOXELS+2, cell.y*CELL_VOXELS+2)
	weights: [3]int
	switch zone {
	case 0:
		weights = {6, 2, 2}
	case 1:
		weights = {4, 3, 3}
	case:
		weights = {3, 3, 4}
	}
	i, _ := rng.weighted_index(r, weights[:])
	return Enemy_Kind(max(i, 0))
}

add_pickup :: proc(w: ^World, kind: Pickup_Kind, position: Vec3, r: ^rng.Rng) -> bool {
	if w.pickup_count >= MAX_PICKUPS {
		return false
	}
	w.pickups[w.pickup_count] = Pickup{kind = kind, position = Vec3{position.x, FLOOR_Y, position.z}, phase = rng.float01(r) * math.TAU}
	w.pickup_count += 1
	return true
}

ENEMY_SIZE :: Vec3{0.6, 1.5, 0.6}

spawn_enemy :: proc(w: ^World, kind: Enemy_Kind, feet: Vec3, r: ^rng.Rng) -> int {
	if w.enemy_count >= MAX_ENEMIES {
		return -1
	}
	params := enemy_params(kind)
	e := Enemy{
		kind  = kind,
		state = .Idle,
		body  = physics.Body3{position = Vec3{feet.x, FLOOR_Y, feet.z} - Vec3{ENEMY_SIZE.x * 0.5, 0, ENEMY_SIZE.z * 0.5}, size = ENEMY_SIZE},
		hp    = params.hp,
		phase = rng.float01(r) * math.TAU,
		strafe = 1 if rng.chance(r, 0.5) else -1,
		facing = {0, 1},
	}
	// Offsets near walls may overlap a voxel: slide back toward the cell
	// centre until the body is free.
	center := column_center(w, column_of(w, feet))
	for _ in 0..<8 {
		if !physics.box_hits_voxels(&w.voxels, e.body.position, e.body.position+e.body.size) {
			break
		}
		f := physics.body3_feet(e.body)
		f += (center - f) * 0.5
		e.body.position = Vec3{f.x, FLOOR_Y, f.z} - Vec3{ENEMY_SIZE.x * 0.5, 0, ENEMY_SIZE.z * 0.5}
	}
	e.prev_feet = physics.body3_feet(e.body)
	w.enemies[w.enemy_count] = e
	w.enemy_count += 1
	return w.enemy_count - 1
}

// Par time from the length of the rune tour (greedy nearest rune, then the
// portal) with margins for exploring and fighting. Beating it earns a star.
@(private)
estimate_par_time :: proc(w: ^World) -> f32 {
	field := &w.bot.field
	taken: [MAX_PICKUPS]bool
	position := w.spawn
	total := f32(0)
	for _ in 0..<w.rune_count {
		flow_from(w, field, column_of(w, position))
		best, best_d := -1, FLOW_UNREACHED
		for i in 0..<w.pickup_count {
			pk := w.pickups[i]
			if pk.kind != .Rune || taken[i] {
				continue
			}
			col := column_of(w, pk.position)
			if col >= 0 && field[col] < best_d {
				best, best_d = i, field[col]
			}
		}
		if best < 0 {
			break
		}
		taken[best] = true
		total += f32(best_d)
		position = w.pickups[best].position
	}
	flow_from(w, field, column_of(w, position))
	if col := column_of(w, w.portal.center); col >= 0 && field[col] < FLOW_UNREACHED {
		total += f32(field[col])
	}
	// A player who knows the way covers the tour in about a third of this;
	// the factor leaves room for dead ends, backtracking and fights.
	return math.round(total*0.4 + 10 + f32(w.tuning.enemies)*2)
}

// ---------------------------------------------------------------------------
// Flow fields

flow_from :: proc(w: ^World, field: ^[MAX_COLUMNS]i32, origin: int) {
	total := w.side * w.side
	for i in 0..<total {
		field[i] = FLOW_UNREACHED
	}
	if origin < 0 || origin >= total || !w.walkable[origin] {
		return
	}
	head, tail := 0, 0
	field[origin] = 0
	w.queue[tail] = i32(origin)
	tail += 1
	for head < tail {
		current := int(w.queue[head])
		head += 1
		x, z := current%w.side, current/w.side
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			n := column_xz(w, x+d.x, z+d.y)
			if n < 0 || !w.walkable[n] || field[n] != FLOW_UNREACHED {
				continue
			}
			field[n] = field[current] + 1
			w.queue[tail] = i32(n)
			tail += 1
		}
	}
}

// Centre of the neighbouring column closest to the field's origin. Diagonal
// moves need both side columns free, so bodies never clip wall corners.
flow_step :: proc(w: ^World, field: ^[MAX_COLUMNS]i32, from: Vec3) -> (target: Vec3, ok: bool) {
	col := column_of(w, from)
	if col < 0 {
		return {}, false
	}
	x, z := col%w.side, col/w.side
	best, best_col := field[col], -1
	for dz in -1..=1 {
		for dx in -1..=1 {
			if dx == 0 && dz == 0 {
				continue
			}
			if !walkable_xz(w, x+dx, z+dz) {
				continue
			}
			if dx != 0 && dz != 0 && (!walkable_xz(w, x+dx, z) || !walkable_xz(w, x, z+dz)) {
				continue
			}
			n := column_xz(w, x+dx, z+dz)
			if field[n] < best {
				best, best_col = field[n], n
			}
		}
	}
	if best_col < 0 {
		return column_center(w, col), field[col] < FLOW_UNREACHED
	}
	return column_center(w, best_col), true
}

@(private)
update_flow :: proc(w: ^World) {
	col := column_of(w, player_feet(w.player))
	if col < 0 || !w.walkable[col] || col == w.flow_origin {
		return
	}
	w.flow_origin = col
	flow_from(w, &w.flow, col)
}

// Marks floor columns the player can see nearby, for the minimap.
explore :: proc(w: ^World) {
	eye := player_eye(w.player)
	pc := column_of(w, eye)
	if pc < 0 {
		return
	}
	px, pz := pc%w.side, pc/w.side
	RADIUS :: 7
	for dz in -RADIUS..=RADIUS {
		for dx in -RADIUS..=RADIUS {
			if dx*dx+dz*dz > RADIUS*RADIUS {
				continue
			}
			col := column_xz(w, px+dx, pz+dz)
			if col < 0 || w.explored[col] || !w.walkable[col] {
				continue
			}
			target := Vec3{f32(px+dx) + 0.5, eye.y, f32(pz+dz) + 0.5}
			if abs(dx) <= 1 && abs(dz) <= 1 || physics.voxel_line_of_sight(&w.voxels, eye, target) {
				w.explored[col] = true
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Step

world_step :: proc(w: ^World, input: Player_Input, dt: f32) -> host.Round_Status {
	w.event_count = 0
	if w.status != .Playing {
		return w.status
	}
	w.steps += 1
	w.time += dt
	player_update(w, input, dt)
	weapon_update(w, input, dt)
	pickups_update(w)
	update_flow(w)
	enemies_update(w, dt)
	projectiles_update(w, dt)
	portal_update(w, dt)
	if w.steps%6 == 0 {
		explore(w)
	}
	return w.status
}

@(private)
pickups_update :: proc(w: ^World) {
	p := &w.player
	feet := player_feet(p^)
	for i in 0..<w.pickup_count {
		pk := &w.pickups[i]
		if pk.taken {
			continue
		}
		d := Vec2{pk.position.x - feet.x, pk.position.z - feet.z}
		if d.x*d.x+d.y*d.y > PICKUP_RADIUS*PICKUP_RADIUS || abs(pk.position.y-feet.y) > 1.2 {
			continue
		}
		switch pk.kind {
		case .Health:
			if p.hp >= MAX_HP {
				continue
			}
			p.hp = min(p.hp+HEALTH_PACK, MAX_HP)
			emit_event(w, Event{kind = .Pickup_Health, position = pk.position, value = HEALTH_PACK})
		case .Mana:
			if p.mana >= MAX_MANA-1 {
				continue
			}
			p.mana = min(p.mana+MANA_PACK, MAX_MANA)
			emit_event(w, Event{kind = .Pickup_Mana, position = pk.position, value = MANA_PACK})
		case .Rune:
			w.runes_taken += 1
			emit_event(w, Event{kind = .Rune_Taken, position = pk.position, value = f32(w.runes_taken), index = i})
			if w.runes_taken >= w.rune_count && !w.portal.open {
				w.portal.open = true
				emit_event(w, Event{kind = .Portal_Open, position = w.portal.center})
				spawn_wave(w)
			}
		}
		pk.taken = true
	}
}

@(private)
portal_update :: proc(w: ^World, dt: f32) {
	if w.status != .Playing {
		return
	}
	pt := &w.portal
	pt.sealed_wait = max(pt.sealed_wait-dt, 0)
	if pt.open {
		pt.open_time += dt
	}
	c := physics.body3_center(w.player.body)
	dx, dz := c.x-pt.center.x, c.z-pt.center.z
	inside := abs(dx) < 0.75 && abs(dz) < 0.45
	if !inside {
		return
	}
	if pt.open {
		w.status = .Won
		emit_event(w, Event{kind = .Escaped, position = pt.center})
	} else if pt.sealed_wait <= 0 {
		pt.sealed_wait = 2.5
		emit_event(w, Event{kind = .Portal_Sealed, position = pt.center})
	}
}

// When the last rune is taken the crypt sends its guardians after the
// player, from places out of sight.
@(private)
spawn_wave :: proc(w: ^World) {
	if w.wave_spawned {
		return
	}
	w.wave_spawned = true
	m := &w.maze
	eye := player_eye(w.player)
	spawned := 0
	for tries := 0; spawned < w.tuning.wave && tries < 400; tries += 1 {
		cx, cy := rng.int_range(&w.rng, 0, m.cells-1), rng.int_range(&w.rng, 0, m.cells-1)
		feet := cell_center(cx, cy)
		col := column_of(w, feet)
		if col < 0 || !w.walkable[col] || w.flow[col] < 14 || w.flow[col] >= FLOW_UNREACHED {
			continue
		}
		if physics.voxel_line_of_sight(&w.voxels, eye, feet+Vec3{0, 1.2, 0}) {
			continue
		}
		kind := Enemy_Kind.Wraith if spawned%2 == 0 else Enemy_Kind.Ghoul
		i := spawn_enemy(w, kind, feet, &w.rng)
		if i < 0 {
			break
		}
		enemy_alert(w, i, quiet = true)
		spawned += 1
	}
	if spawned > 0 {
		emit_event(w, Event{kind = .Wave, value = f32(spawned)})
	}
}

// ---------------------------------------------------------------------------
// Score

accuracy :: proc "contextless" (w: ^World) -> f32 {
	if w.stats.shots == 0 {
		return 1
	}
	return f32(w.stats.hits) / f32(w.stats.shots)
}

// Running score shown in the HUD: runes and kills.
live_score :: proc "contextless" (w: ^World) -> i64 {
	return i64(w.runes_taken*RUNE_SCORE + w.stats.kill_score)
}

// Stars (only on escape): 1 for escaping, +1 within the par time, +1 with at
// least half health and half of the bolts on target.
world_score :: proc "contextless" (w: ^World) -> (score: i64, stars: u8) {
	score = live_score(w)
	if w.status != .Won {
		return score, 0
	}
	acc := accuracy(w)
	score += i64(max(w.par_time-w.time, 0) * 20)
	score += i64(w.player.hp * 10)
	score += i64(acc * 1000)
	stars = 1
	if w.time <= w.par_time {
		stars += 1
	}
	if w.player.hp >= 50 && acc >= 0.5 {
		stars += 1
	}
	return score, stars
}
