// Rules of "Sigilli della Cripta", a turn-based Sokoban variant.
//
// The board is static (walls, ice, sigils, plates, gates); everything that
// moves lives in a compact State, so undo stores whole states and the solver
// hashes them into one u64. Nothing here calls raylib: tests and the solver
// run headless, and the renderer only reads states and Move_Results.
//
// Twists over classic Sokoban:
//   - ice: a crate or the player that ends a step on ice keeps sliding in the
//     same direction until the next cell is blocked or the tile is not ice;
//   - plates and gates: every gate is open while ALL plates are pressed by a
//     crate or by the player. A gate is checked on arrival, after the step,
//     so stepping off a plate onto its own gate is not possible.
package puzzle

MAX_W :: 16
MAX_H :: 12
MAX_CELLS :: MAX_W * MAX_H
MAX_CRATES :: 7 // player + 7 crates pack into the solver's u64 key
MAX_PLATES :: 4
HISTORY_CAP :: 4096

Tile :: enum u8 {
	Void, // outside the crypt
	Wall,
	Floor,
	Ice,
	Sigil,
	Plate,
	Gate,
}

Dir :: enum u8 {
	Up,
	Down,
	Left,
	Right,
}

Board :: struct {
	width, height: int,
	tiles:         [MAX_CELLS]Tile, // row-major, stride = width
	sigil_count:   int,
	plates:        [MAX_PLATES]u8,
	plate_count:   int,
}

// Crates keep their slot for the whole level, so the renderer can follow each
// one across moves and undos. Unused slots stay zero to keep `==` meaningful.
State :: struct {
	player:      u8,
	crate_count: u8,
	crates:      [MAX_CRATES]u8,
}

Move_Result :: struct {
	moved:        bool,
	dir:          Dir,
	player_from:  int,
	player_to:    int,
	player_slid:  bool,
	pushed:       bool,
	crate:        int, // slot of the pushed crate, -1 when nothing was pushed
	crate_from:   int,
	crate_to:     int,
	crate_slid:   bool,
	sigil_filled: bool, // the pushed crate came to rest on a sigil
	sigil_left:   bool, // the pushed crate left a sigil
	gates_opened: bool,
	gates_closed: bool,
	solved:       bool,
}

Snapshot :: struct {
	state: State,
	moves: int,
}

// A level being played: board, live state and the undo/redo stacks.
Puzzle :: struct {
	board:       Board,
	start:       State,
	state:       State,
	moves:       int, // moves of the current line of play (undo takes them back)
	undos:       int,
	history:     [HISTORY_CAP]Snapshot,
	history_len: int,
	redo:        [HISTORY_CAP]Snapshot,
	redo_len:    int,
}

dir_delta :: proc "contextless" (d: Dir) -> [2]int {
	switch d {
	case .Up:
		return {0, -1}
	case .Down:
		return {0, 1}
	case .Left:
		return {-1, 0}
	case .Right:
		return {1, 0}
	}
	return {}
}

dir_opposite :: proc "contextless" (d: Dir) -> Dir {
	switch d {
	case .Up:
		return .Down
	case .Down:
		return .Up
	case .Left:
		return .Right
	case .Right:
		return .Left
	}
	return d
}

cell_xy :: proc "contextless" (b: ^Board, cell: int) -> [2]int {
	return {cell % b.width, cell / b.width}
}

cell_at :: proc "contextless" (b: ^Board, x, y: int) -> (int, bool) {
	if x < 0 || y < 0 || x >= b.width || y >= b.height {
		return 0, false
	}
	return y*b.width + x, true
}

tile_at :: proc "contextless" (b: ^Board, x, y: int) -> Tile {
	cell, ok := cell_at(b, x, y)
	return b.tiles[cell] if ok else .Void
}

neighbor :: proc "contextless" (b: ^Board, cell: int, d: Dir) -> (int, bool) {
	p := cell_xy(b, cell) + dir_delta(d)
	return cell_at(b, p.x, p.y)
}

// Tiles a body may ever stand on; gates additionally need open_gates.
walkable :: proc "contextless" (t: Tile) -> bool {
	return t != .Wall && t != .Void
}

crate_slot :: proc "contextless" (s: ^State, cell: int) -> int {
	for i in 0..<int(s.crate_count) {
		if int(s.crates[i]) == cell {
			return i
		}
	}
	return -1
}

occupied :: proc "contextless" (s: ^State, cell: int) -> bool {
	return int(s.player) == cell || crate_slot(s, cell) >= 0
}

// Gates are open while every plate carries a crate or the player.
gates_open :: proc "contextless" (b: ^Board, s: ^State) -> bool {
	if b.plate_count == 0 {
		return false
	}
	for i in 0..<b.plate_count {
		if !occupied(s, int(b.plates[i])) {
			return false
		}
	}
	return true
}

pressed_plates :: proc "contextless" (b: ^Board, s: ^State) -> int {
	n := 0
	for i in 0..<b.plate_count {
		if occupied(s, int(b.plates[i])) {
			n += 1
		}
	}
	return n
}

covered_sigils :: proc "contextless" (b: ^Board, s: ^State) -> int {
	n := 0
	for i in 0..<int(s.crate_count) {
		if b.tiles[s.crates[i]] == .Sigil {
			n += 1
		}
	}
	return n
}

is_solved :: proc "contextless" (b: ^Board, s: ^State) -> bool {
	return b.sigil_count > 0 && covered_sigils(b, s) == b.sigil_count
}

// `next` already holds the mover on `cell`: a gate is judged after arrival.
@(private)
arrival_ok :: proc "contextless" (b: ^Board, next: ^State, cell: int) -> bool {
	return b.tiles[cell] != .Gate || gates_open(b, next)
}

// Slides one body across ice; returns the number of extra cells travelled.
@(private)
slide :: proc "contextless" (b: ^Board, s: ^State, d: Dir, slot: int) -> int {
	cells := 0
	for {
		here := int(s.player) if slot < 0 else int(s.crates[slot])
		if b.tiles[here] != .Ice {
			return cells
		}
		next, ok := neighbor(b, here, d)
		if !ok || !walkable(b.tiles[next]) || occupied(s, next) {
			return cells
		}
		if slot < 0 {
			s.player = u8(next)
		} else {
			s.crates[slot] = u8(next)
		}
		if !arrival_ok(b, s, next) {
			if slot < 0 {
				s.player = u8(here)
			} else {
				s.crates[slot] = u8(here)
			}
			return cells
		}
		cells += 1
	}
}

// Pure transition used by play and by the solver. A blocked move returns the
// input state and `moved = false`.
simulate :: proc "contextless" (b: ^Board, s: State, d: Dir) -> (next: State, r: Move_Result) {
	state := s
	r.dir = d
	r.crate = -1
	r.player_from = int(state.player)
	r.player_to = r.player_from
	target, ok := neighbor(b, int(state.player), d)
	if !ok || !walkable(b.tiles[target]) {
		return s, r
	}
	next = state
	slot := crate_slot(&state, target)
	if slot >= 0 {
		beyond, ok2 := neighbor(b, target, d)
		if !ok2 || !walkable(b.tiles[beyond]) || occupied(&state, beyond) {
			return s, r
		}
		next.crates[slot] = u8(beyond)
		next.player = u8(target)
		if !arrival_ok(b, &next, beyond) || !arrival_ok(b, &next, target) {
			return s, r
		}
		r.pushed = true
		r.crate = slot
		r.crate_from = target
		r.crate_slid = slide(b, &next, d, slot) > 0
		r.crate_to = int(next.crates[slot])
		r.sigil_left = b.tiles[target] == .Sigil
		r.sigil_filled = b.tiles[r.crate_to] == .Sigil
	} else {
		next.player = u8(target)
		if !arrival_ok(b, &next, target) {
			return s, r
		}
	}
	r.player_slid = slide(b, &next, d, -1) > 0
	r.player_to = int(next.player)
	r.moved = true
	before := gates_open(b, &state)
	after := gates_open(b, &next)
	r.gates_opened = after && !before
	r.gates_closed = before && !after
	r.solved = is_solved(b, &next)
	return next, r
}

puzzle_init :: proc(p: ^Puzzle, b: Board, start: State) {
	p.board = b
	p.start = start
	p.state = start
	p.moves = 0
	p.undos = 0
	p.history_len = 0
	p.redo_len = 0
}

@(private)
push_snapshot :: proc(stack: []Snapshot, length: ^int, snap: Snapshot) {
	if length^ >= len(stack) {
		// Full: forget the oldest entry rather than refusing to record.
		copy(stack[0:], stack[1:])
		length^ = len(stack) - 1
	}
	stack[length^] = snap
	length^ += 1
}

apply_move :: proc(p: ^Puzzle, d: Dir) -> Move_Result {
	next, r := simulate(&p.board, p.state, d)
	if !r.moved {
		return r
	}
	push_snapshot(p.history[:], &p.history_len, Snapshot{p.state, p.moves})
	p.redo_len = 0
	p.state = next
	p.moves += 1
	return r
}

undo :: proc(p: ^Puzzle) -> bool {
	if p.history_len == 0 {
		return false
	}
	push_snapshot(p.redo[:], &p.redo_len, Snapshot{p.state, p.moves})
	p.history_len -= 1
	snap := p.history[p.history_len]
	p.state = snap.state
	p.moves = snap.moves
	p.undos += 1
	return true
}

redo :: proc(p: ^Puzzle) -> bool {
	if p.redo_len == 0 {
		return false
	}
	push_snapshot(p.history[:], &p.history_len, Snapshot{p.state, p.moves})
	p.redo_len -= 1
	snap := p.redo[p.redo_len]
	p.state = snap.state
	p.moves = snap.moves
	return true
}

// Back to the opening position. The restart itself is undoable, so a hasty
// R never throws away a long line of play.
restart :: proc(p: ^Puzzle) -> bool {
	if p.state == p.start && p.moves == 0 {
		return false
	}
	push_snapshot(p.history[:], &p.history_len, Snapshot{p.state, p.moves})
	p.redo_len = 0
	p.state = p.start
	p.moves = 0
	return true
}

solved :: proc(p: ^Puzzle) -> bool {
	return is_solved(&p.board, &p.state)
}

// ---------------------------------------------------------------------------
// Parsing

Parse_Error :: enum u8 {
	None,
	Empty,
	Too_Large,
	Bad_Char,
	No_Player,
	Many_Players,
	No_Sigils,
	Too_Few_Crates,
	Too_Many_Crates,
	Too_Many_Plates,
	Gate_Without_Plate,
	Open_Edge, // a walkable cell touches the outside
}

// Level rows use:
//   #  wall          .  floor        -  outside (spaces work too)
//   ~  ice           o  sigil        ^  plate          |  gate
//   @  player        $  crate        *  crate on sigil
//   +  player on sigil  =  player on ice   %  crate on ice
//   &  crate on plate   !  player on plate
// Rows may differ in length; short rows are padded with outside.
parse_level :: proc(rows: []string) -> (b: Board, s: State, err: Parse_Error) {
	if len(rows) == 0 {
		return {}, {}, .Empty
	}
	width := 0
	for r in rows {
		width = max(width, len(r))
	}
	if width == 0 {
		return {}, {}, .Empty
	}
	if width > MAX_W || len(rows) > MAX_H {
		return {}, {}, .Too_Large
	}
	b.width = width
	b.height = len(rows)
	players := 0
	crates := 0
	for r, y in rows {
		for x in 0..<width {
			ch := r[x] if x < len(r) else '-'
			cell := y*width + x
			tile := Tile.Floor
			crate := false
			player := false
			switch ch {
			case '#':
				tile = .Wall
			case '.':
				tile = .Floor
			case '-', ' ':
				tile = .Void
			case '~':
				tile = .Ice
			case 'o':
				tile = .Sigil
			case '^':
				tile = .Plate
			case '|':
				tile = .Gate
			case '@':
				player = true
			case '$':
				crate = true
			case '*':
				tile, crate = .Sigil, true
			case '+':
				tile, player = .Sigil, true
			case '=':
				tile, player = .Ice, true
			case '%':
				tile, crate = .Ice, true
			case '&':
				tile, crate = .Plate, true
			case '!':
				tile, player = .Plate, true
			case:
				return {}, {}, .Bad_Char
			}
			b.tiles[cell] = tile
			if player {
				players += 1
				s.player = u8(cell)
			}
			if crate {
				if crates >= MAX_CRATES {
					return {}, {}, .Too_Many_Crates
				}
				s.crates[crates] = u8(cell)
				crates += 1
			}
			switch tile {
			case .Sigil:
				b.sigil_count += 1
			case .Plate:
				if b.plate_count >= MAX_PLATES {
					return {}, {}, .Too_Many_Plates
				}
				b.plates[b.plate_count] = u8(cell)
				b.plate_count += 1
			case .Void, .Wall, .Floor, .Ice, .Gate:
			}
		}
	}
	s.crate_count = u8(crates)
	switch {
	case players == 0:
		return {}, {}, .No_Player
	case players > 1:
		return {}, {}, .Many_Players
	case b.sigil_count == 0:
		return {}, {}, .No_Sigils
	case crates < b.sigil_count:
		return {}, {}, .Too_Few_Crates
	}
	gates := false
	for i in 0..<b.width*b.height {
		if b.tiles[i] == .Gate {
			gates = true
		}
		if !walkable(b.tiles[i]) {
			continue
		}
		for d in Dir {
			n, ok := neighbor(&b, i, d)
			if !ok || b.tiles[n] == .Void {
				return {}, {}, .Open_Edge
			}
		}
	}
	if gates && b.plate_count == 0 {
		return {}, {}, .Gate_Without_Plate
	}
	return b, s, .None
}

// ---------------------------------------------------------------------------
// Symmetries. Every rule is the same in all four directions, so the eight
// symmetries of the square map a level onto an equally hard one with the
// same optimal move count.

Transform :: enum u8 {
	Identity,
	Mirror_X,
	Mirror_Y,
	Rotate_180,
	Transpose,
	Rotate_90,
	Rotate_270,
	Anti_Transpose,
}

transform_swaps_axes :: proc "contextless" (t: Transform) -> bool {
	return t >= .Transpose
}

@(private)
transform_xy :: proc "contextless" (t: Transform, x, y, w, h: int) -> [2]int {
	switch t {
	case .Identity:
		return {x, y}
	case .Mirror_X:
		return {w - 1 - x, y}
	case .Mirror_Y:
		return {x, h - 1 - y}
	case .Rotate_180:
		return {w - 1 - x, h - 1 - y}
	case .Transpose:
		return {y, x}
	case .Rotate_90:
		return {h - 1 - y, x}
	case .Rotate_270:
		return {y, w - 1 - x}
	case .Anti_Transpose:
		return {h - 1 - y, w - 1 - x}
	}
	return {x, y}
}

transform_level :: proc(b: Board, s: State, t: Transform) -> (Board, State) {
	out: Board
	out.width, out.height = b.width, b.height
	if transform_swaps_axes(t) {
		out.width, out.height = b.height, b.width
	}
	src := b
	remap :: proc "contextless" (src: ^Board, out: ^Board, t: Transform, cell: int) -> u8 {
		p := cell_xy(src, cell)
		q := transform_xy(t, p.x, p.y, src.width, src.height)
		return u8(q.y*out.width + q.x)
	}
	for cell in 0..<b.width*b.height {
		out.tiles[remap(&src, &out, t, cell)] = b.tiles[cell]
	}
	out.sigil_count = b.sigil_count
	out.plate_count = b.plate_count
	for i in 0..<b.plate_count {
		out.plates[i] = remap(&src, &out, t, int(b.plates[i]))
	}
	ns := s
	ns.player = remap(&src, &out, t, int(s.player))
	for i in 0..<int(s.crate_count) {
		ns.crates[i] = remap(&src, &out, t, int(s.crates[i]))
	}
	return out, ns
}
