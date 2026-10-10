package platform2d

// Reachability through the real controller. From every cell the player can
// stand in, a fixed menu of input "macros" (walk off, hop, full jump, double
// jump, dash...) is simulated with `player_move`; where each one comes to rest
// becomes an edge. The resulting graph proves a level is completable, finds
// unreachable embers and dead ends, and drives the autoplay bot used by tests
// and the preview harness. Pure simulation: no raylib.

import "core:math"
import physics "../../engine/physics"

// Input script relative to its start; counts are fixed steps (120 Hz).
Macro :: struct {
	dir:       f32,
	prerun:    int, // steps of running before the jump
	hold:      int, // steps the first jump is held; 0 = no jump (walk off)
	move:      int, // steps the direction is held, from the start
	double_at: int, // steps after the jump for the air jump; 0 = none
	dash_at:   int, // steps after the jump for the dash; 0 = none
}

FOREVER :: 100000
MAX_SIM_STEPS :: 420
MAX_MACROS :: 64

macro_input :: proc(m: Macro, i: int) -> Player_Input {
	cmd: Player_Input
	if i < m.prerun+m.move {
		cmd.move = m.dir
	}
	if m.hold > 0 && i >= m.prerun {
		j := i - m.prerun
		cmd.jump_pressed = j == 0
		cmd.jump_held = j < m.hold
		if m.double_at > 0 && j >= m.double_at {
			cmd.jump_pressed = cmd.jump_pressed || j == m.double_at
			cmd.jump_held = true
		}
		cmd.dash_pressed = m.dash_at > 0 && j == m.dash_at
	}
	return cmd
}

// Steps after which a macro that never left the ground counts as finished.
macro_length :: proc(m: Macro) -> int {
	n := m.prerun + m.hold
	if m.move < FOREVER {
		n = max(n, m.prerun+m.move)
	}
	n = max(n, m.prerun+m.double_at, m.prerun+m.dash_at)
	return n
}

macro_set :: proc() -> (set: [MAX_MACROS]Macro, count: int) {
	add :: proc(set: ^[MAX_MACROS]Macro, count: ^int, m: Macro) {
		if count^ < MAX_MACROS {
			set[count^] = m
			count^ += 1
		}
	}
	holds := [2]int{10, 42}
	moves := [3]int{14, 36, FOREVER}
	for dir in ([2]f32{-1, 1}) {
		add(&set, &count, Macro{dir = dir, move = 14})
		add(&set, &count, Macro{dir = dir, move = 36})
		for hold in holds {
			for move in moves {
				add(&set, &count, Macro{dir = dir, hold = hold, move = move})
				add(&set, &count, Macro{dir = dir, hold = hold, move = move, double_at = 34})
				add(&set, &count, Macro{dir = dir, hold = hold, move = move, dash_at = 30})
				add(&set, &count, Macro{dir = dir, hold = hold, move = move, double_at = 34, dash_at = 60})
			}
		}
		// Running starts reach further than standing jumps.
		add(&set, &count, Macro{dir = dir, prerun = 12, hold = 42, move = FOREVER})
		add(&set, &count, Macro{dir = dir, prerun = 12, hold = 42, move = FOREVER, double_at = 34})
		add(&set, &count, Macro{dir = dir, prerun = 12, hold = 42, move = FOREVER, double_at = 34, dash_at = 60})
		add(&set, &count, Macro{dir = dir, prerun = 12, hold = 42, move = FOREVER, double_at = 20, dash_at = 46})
	}
	for hold in holds {
		add(&set, &count, Macro{hold = hold})
		add(&set, &count, Macro{hold = hold, double_at = 34})
	}
	return
}

Nav_Edge :: struct {
	target: int,
	macro:  Macro,
	walk:   bool,
	cost:   f32, // seconds
	goal:   bool, // touches the goal on the way
}

Nav_Node :: struct {
	cell:       [2]int,
	first_edge: int,
	edge_count: int,
	expanded:   bool,
	dist:       f32, // seconds to the goal; INF when it cannot be reached
}

INF :: max(f32)

Nav_Graph :: struct {
	cols:          int,
	node_of:       []int, // cell -> node, -1 when unknown
	nodes:         [dynamic]Nav_Node,
	edges:         [dynamic]Nav_Edge,
	ember_cell:    []int, // cell -> ember index, -1 when none
	ember_touched: []bool,
	goal:          Rect,
	sims:          int,
}

standable :: proc(w: ^World, x, y: int) -> bool {
	if tile_kind(w, x, y) != .Empty {
		return false
	}
	below := tile_kind(w, x, y+1)
	return below == .Stone || below == .Ledge || below == .Crumble
}

cell_feet :: proc "contextless" (cell: [2]int) -> Vec2 {
	return {(f32(cell.x) + 0.5) * TILE, f32(cell.y+1) * TILE}
}

standing_rect :: proc "contextless" (cell: [2]int) -> Rect {
	f := cell_feet(cell)
	return Rect{f.x - PLAYER_SIZE.x*0.5, f.y - PLAYER_SIZE.y, PLAYER_SIZE.x, PLAYER_SIZE.y}
}

// The standable cell a resting body occupies: the one under its centre, or
// failing that (balanced on a lip) whichever covered cell has support.
resting_cell :: proc(w: ^World, body: physics.Body2) -> ([2]int, bool) {
	feet := Vec2{body.position.x + body.size.x*0.5, body.position.y + body.size.y}
	y := int(math.floor((feet.y - 1) / TILE))
	x := int(math.floor(feet.x / TILE))
	if standable(w, x, y) {
		return {x, y}, true
	}
	x0 := int(math.floor(body.position.x / TILE))
	x1 := int(math.floor((body.position.x + body.size.x - 0.01) / TILE))
	for cx in x0..=x1 {
		if standable(w, cx, y) {
			return {cx, y}, true
		}
	}
	return {}, false
}

nav_build :: proc(w: ^World, start: [2]int, goal: Rect, allocator := context.allocator) -> ^Nav_Graph {
	context.allocator = allocator
	g := new(Nav_Graph)
	g.cols = w.cols
	g.goal = goal
	g.node_of = make([]int, w.cols*LEVEL_ROWS)
	g.ember_cell = make([]int, w.cols*LEVEL_ROWS)
	for &v in g.node_of {
		v = -1
	}
	for &v in g.ember_cell {
		v = -1
	}
	g.ember_touched = make([]bool, w.ember_count)
	for e, i in w.embers[:w.ember_count] {
		x := int(e.position.x / TILE)
		y := int(e.position.y / TILE)
		if x >= 0 && x < w.cols && y >= 0 && y < LEVEL_ROWS {
			g.ember_cell[y*w.cols+x] = i
		}
	}
	nav_node(g, start)
	// Nodes are appended as they are discovered, so this is a BFS.
	for i := 0; i < len(g.nodes); i += 1 {
		nav_expand(g, w, i)
	}
	nav_distances(g)
	return g
}

nav_destroy :: proc(g: ^Nav_Graph) {
	if g == nil {
		return
	}
	delete(g.node_of)
	delete(g.ember_cell)
	delete(g.ember_touched)
	delete(g.nodes)
	delete(g.edges)
	free(g)
}

nav_node :: proc(g: ^Nav_Graph, cell: [2]int) -> int {
	if cell.x < 0 || cell.x >= g.cols || cell.y < 0 || cell.y >= LEVEL_ROWS {
		return -1
	}
	index := cell.y*g.cols + cell.x
	if g.node_of[index] >= 0 {
		return g.node_of[index]
	}
	append(&g.nodes, Nav_Node{cell = cell, dist = INF})
	g.node_of[index] = len(g.nodes) - 1
	return len(g.nodes) - 1
}

nav_find :: proc(g: ^Nav_Graph, cell: [2]int) -> int {
	if cell.x < 0 || cell.x >= g.cols || cell.y < 0 || cell.y >= LEVEL_ROWS {
		return -1
	}
	return g.node_of[cell.y*g.cols+cell.x]
}

@(private)
touch_embers :: proc(g: ^Nav_Graph, w: ^World, r: Rect, found: ^[16]int, count: ^int) {
	x0 := int(math.floor(r.x / TILE))
	x1 := int(math.floor((r.x + r.width) / TILE))
	y0 := int(math.floor(r.y / TILE))
	y1 := int(math.floor((r.y + r.height) / TILE))
	for y in max(y0, 0)..=min(y1, LEVEL_ROWS-1) {
		for x in max(x0, 0)..=min(x1, g.cols-1) {
			e := g.ember_cell[y*g.cols+x]
			if e >= 0 && count^ < len(found) && physics.rect_overlaps(r, ember_box(w.embers[e])) {
				found[count^] = e
				count^ += 1
			}
		}
	}
}

Sim_Result :: struct {
	ok:          bool,
	cell:        [2]int,
	steps:       int,
	goal:        bool,
	embers:      [16]int, // touched on the way, committed only on success
	ember_count: int,
}

// Runs one macro from rest at a cell centre, exactly as the bot replays it.
simulate_macro :: proc(g: ^Nav_Graph, w: ^World, start: [2]int, m: Macro) -> Sim_Result {
	res: Sim_Result
	g.sims += 1
	p: Player
	p.ctrl = physics.platformer_create(cell_feet(start) - {PLAYER_SIZE.x * 0.5, PLAYER_SIZE.y}, PLAYER_SIZE)
	p.ctrl.grounded = true
	p.ctrl.facing = m.dir if m.dir != 0 else 1
	tracker: Macro_Tracker
	length := macro_length(m)
	for i in 0..<MAX_SIM_STEPS {
		cmd := Player_Input{} if tracker.landed else macro_input(m, i)
		player_move(&p, w.params, cmd, &w.collision, SIM_DT)
		rect := player_rect(p)
		if hazard_hit(w, physics.rect_inset(rect, 1)) || rect.y > LEVEL_ROWS*TILE {
			return {}
		}
		touch_embers(g, w, rect, &res.embers, &res.ember_count)
		if physics.rect_overlaps(rect, g.goal) {
			res.goal = true
		}
		if tracker_update(&tracker, p, i, length) {
			cell, ok := resting_cell(w, p.ctrl.body)
			if !ok {
				return {}
			}
			res.ok = true
			res.cell = cell
			res.steps = i + 1
			return res
		}
	}
	return {}
}

// Shared by the simulation and the bot so both see the same landing moment.
Macro_Tracker :: struct {
	airborne: bool,
	landed:   bool,
	still:    int,
}

// Call after each step; true once the body rests on the ground again.
tracker_update :: proc(t: ^Macro_Tracker, p: Player, step, length: int) -> bool {
	if !p.ctrl.grounded {
		t.airborne = true
	} else if t.airborne {
		t.landed = true
	}
	if !t.airborne && step >= length {
		t.landed = true
	}
	if t.landed && p.ctrl.grounded && abs(p.ctrl.body.velocity.x) < 1 {
		t.still += 1
		return t.still >= 2
	}
	t.still = 0
	return false
}

nav_expand :: proc(g: ^Nav_Graph, w: ^World, n: int) {
	if n < 0 || g.nodes[n].expanded {
		return
	}
	cell := g.nodes[n].cell
	first := len(g.edges)
	for d in ([2]int{-1, 1}) {
		next := cell + {d, 0}
		if standable(w, next.x, next.y) && !hazard_hit(w, standing_rect(next)) {
			found: [16]int
			count := 0
			touch_embers(g, w, standing_rect(next), &found, &count)
			for e in found[:count] {
				g.ember_touched[e] = true
			}
			target := nav_node(g, next)
			add_edge(g, first, Nav_Edge{target = target, walk = true, cost = TILE / 150,
				goal = physics.rect_overlaps(standing_rect(next), g.goal)})
		}
	}
	macros, count := macro_set()
	for m in macros[:count] {
		// Walking off only makes sense at a ledge.
		if m.hold == 0 && standable(w, cell.x+int(m.dir), cell.y) {
			continue
		}
		r := simulate_macro(g, w, cell, m)
		if !r.ok || (r.cell == cell && !r.goal) {
			continue
		}
		for e in r.embers[:r.ember_count] {
			g.ember_touched[e] = true
		}
		target := nav_node(g, r.cell)
		add_edge(g, first, Nav_Edge{target = target, macro = m, cost = f32(r.steps) * SIM_DT, goal = r.goal})
	}
	g.nodes[n].first_edge = first
	g.nodes[n].edge_count = len(g.edges) - first
	g.nodes[n].expanded = true
}

// Keeps only the cheapest edge per target (goal edges are kept apart).
@(private)
add_edge :: proc(g: ^Nav_Graph, first: int, e: Nav_Edge) {
	if e.target < 0 {
		return
	}
	for &old in g.edges[first:] {
		if old.target == e.target && old.goal == e.goal {
			if e.cost < old.cost {
				old = e
			}
			return
		}
	}
	append(&g.edges, e)
}

edge_score :: proc(g: ^Nav_Graph, e: Nav_Edge) -> f32 {
	if e.goal {
		return e.cost
	}
	d := g.nodes[e.target].dist
	return INF if d == INF else e.cost + d
}

// Seconds-to-goal for every node, by relaxing edges until nothing improves.
nav_distances :: proc(g: ^Nav_Graph) {
	for &node in g.nodes {
		node.dist = 0 if physics.rect_overlaps(standing_rect(node.cell), g.goal) else INF
	}
	for {
		changed := false
		for &node in g.nodes {
			for e in g.edges[node.first_edge:][:node.edge_count] {
				s := edge_score(g, e)
				if s < node.dist {
					node.dist = s
					changed = true
				}
			}
		}
		if !changed {
			break
		}
	}
}

nav_best_edge :: proc(g: ^Nav_Graph, n: int) -> (Nav_Edge, bool) {
	if n < 0 {
		return {}, false
	}
	node := g.nodes[n]
	best: Nav_Edge
	best_score := INF
	found := false
	for e in g.edges[node.first_edge:][:node.edge_count] {
		s := edge_score(g, e)
		if s < best_score {
			best, best_score, found = e, s, true
		}
	}
	return best, found
}

// ---------------------------------------------------------------------------
// Autoplay bot: follows the graph toward the goal, re-planning after every
// landing, so knockbacks or crumbled bridges only cost a detour.

Bot_Mode :: enum u8 {
	Plan,
	Walk,
	Macro,
}

Bot :: struct {
	graph:    ^Nav_Graph,
	mode:     Bot_Mode,
	macro:    Macro,
	length:   int,
	step:     int,
	tracker:  Macro_Tracker,
	target_x: f32,
	timer:    int,
	// Tests: place the body exactly on the cell centre before each macro, so
	// replays match the graph to the bit.
	snap:     bool,
}

bot_create :: proc(w: ^World, allocator := context.allocator) -> Bot {
	start, _ := resting_cell(w, w.player.ctrl.body)
	return Bot{graph = nav_build(w, start, w.exit_rect, allocator)}
}

bot_destroy :: proc(b: ^Bot) {
	nav_destroy(b.graph)
	b^ = {}
}

bot_input :: proc(b: ^Bot, w: ^World) -> Player_Input {
	if b.graph == nil || w.phase != .Alive {
		b.mode = .Plan
		return {}
	}
	p := &w.player
	feet := player_feet(p^)
	b.timer += 1
	switch b.mode {
	case .Macro:
		if b.step > 0 && tracker_update(&b.tracker, p^, b.step-1, b.length) {
			b.mode = .Plan
			return bot_plan(b, w)
		}
		cmd := Player_Input{} if b.tracker.landed else macro_input(b.macro, b.step)
		b.step += 1
		if b.step > MAX_SIM_STEPS*2 {
			b.mode = .Plan
		}
		return cmd
	case .Walk:
		if !p.ctrl.grounded {
			// Slipped off while walking: just wait to land.
			start_macro(b, Macro{})
			b.tracker.airborne = true
			return {}
		}
		dx := b.target_x - feet.x
		if abs(dx) < 0.75 && abs(p.ctrl.body.velocity.x) < 5 || b.timer > 600 {
			b.mode = .Plan
			return bot_plan(b, w)
		}
		return Player_Input{move = clamp(dx/10, -1, 1)}
	case .Plan:
		return bot_plan(b, w)
	}
	return {}
}

@(private)
start_macro :: proc(b: ^Bot, m: Macro) {
	b.mode = .Macro
	b.macro = m
	b.length = macro_length(m)
	b.step = 0
	b.tracker = {}
	b.timer = 0
}

@(private)
bot_plan :: proc(b: ^Bot, w: ^World) -> Player_Input {
	p := &w.player
	b.timer = 0
	if !p.ctrl.grounded {
		return {}
	}
	cell, ok := resting_cell(w, p.ctrl.body)
	if !ok {
		return Player_Input{move = p.ctrl.facing}
	}
	g := b.graph
	n := nav_find(g, cell)
	if n < 0 || !g.nodes[n].expanded {
		n = nav_node(g, cell)
		nav_expand(g, w, n)
		nav_distances(g)
	}
	e, found := nav_best_edge(g, n)
	if !found {
		return Player_Input{move = 1}
	}
	if e.walk {
		// Chain consecutive walks in one direction into a single stride.
		target := e.target
		dir := g.nodes[target].cell.x - cell.x
		for _ in 0..<64 {
			next, more := nav_best_edge(g, target)
			if !more || !next.walk || g.nodes[next.target].cell.x-g.nodes[target].cell.x != dir {
				break
			}
			target = next.target
		}
		b.target_x = cell_feet(g.nodes[target].cell).x
		b.mode = .Walk
		return Player_Input{move = f32(dir)}
	}
	center := cell_feet(cell).x
	vx := p.ctrl.body.velocity.x
	// Start every macro from rest at the centre, with no stale timers, as the
	// graph assumed.
	if !b.snap && (abs(player_feet(p^).x-center) > 0.75 || abs(vx) > 5) {
		b.target_x = center
		b.mode = .Walk
		return Player_Input{move = clamp((center-player_feet(p^).x)/10, -1, 1)}
	}
	if p.ctrl.jump_buffer > 0 || p.ctrl.dash_cooldown > 0 {
		return {}
	}
	if b.snap {
		p.ctrl.body.position.x = center - PLAYER_SIZE.x*0.5
		p.ctrl.body.velocity = {}
	}
	start_macro(b, e.macro)
	cmd := macro_input(b.macro, 0)
	b.step = 1
	return cmd
}
