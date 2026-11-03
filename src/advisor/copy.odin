package advisor

import "core:mem"
import "core:mem/virtual"
import game "../game"
import level "../level"

// THE ADVISOR (docs/piano-ia.md): the IA card's search for the best move. Like `game` it draws nothing and plays no
// sound; it tries its moves on copies of the room, never on the room itself.
//
// Fase 1 of the plan: the copies and the simulator. Two copies, each with memory of its own (an arena):
//
// - the SNAPSHOT (la fotografia), taken from the real room by the game's own thread when the situation changes: the
//   room, the player, the level, the room's lists and per-cell tables, all deep;
// - the REHEARSAL (la copia di prova), the working copy a move is tried on, rebuilt from the snapshot for every try.
//   What it copies, and when (the plan's table, «Come simula»):
//     - every try: the room's own bytes, the player, the foes, traps, obstacles, objects and loot;
//     - once from the snapshot, then again only when a try changed them: the level (level.Level.geometry_revision
//       says so) and the pools on the floor (game.Ground_State.pool_writes);
//     - never: the foes' distance field (the foes' planning rewrites it whole before it reads it) and the event log
//       (a log of its own nobody reads: no animation, no sound, no presentation).
//   While a try runs, context.allocator and context.temp_allocator are its arena: the game's memory stays clean.

// The arenas' first blocks: one copy of the largest expedition fits in them (its level and tables near 3 MB).
SNAPSHOT_ARENA_BLOCK :: 8*mem.Megabyte
REHEARSAL_ARENA_BLOCK :: 8*mem.Megabyte
TRY_ARENA_BLOCK :: 4*mem.Megabyte

// Every field reachable from the room that points elsewhere (a pointer, a slice, a list), as core:reflect finds them
// walking Room, Player, Enemy, Grid_Object, Trap, Loot, Obstacle and level.Level: the copy knows each one, and the
// test test_advisor_copy_knows_every_field_that_points fails as soon as the game has one more (the plan's rule for ever:
// docs/piano-ia.md, «La regola per sempre»). Add it to the copy first, then here.
COPIED_FIELDS :: [?]string{
	"Room.level_data", "Room.player", "Room.enemies", "Room.traps", "Room.obstacles", "Room.objects", "Room.loot",
	"Room.enemy_path_distances", "Room.recent_events", "Room.event_allocator.procedure", "Room.event_allocator.data",
	"Room.ground.pool",
	"Level.tiles.cells", "Level.heights", "Level.structures", "Level.structure_plans", "Level.structure_cells",
	"Level.planes[*].tiles", "Level.planes[*].heights", "Level.ladders", "Level.lifts", "Level.gates",
}

Snapshot :: struct {
	arena: virtual.Arena,
	room: game.Room,
	player: game.Player,
	level: level.Level,
	events: ^game.Event_Log,
	taken: bool,
	// The game's state beyond the room (context.odin), as the game's thread knew it when it took the snapshot.
	game_context: Game_Context,
}

Rehearsal :: struct {
	// The level and the pools as the snapshot has them, copied once, then again only when a try changed them.
	root: virtual.Arena,
	// A try's lists and whatever the rules ask memory for while it runs: cleared before every try.
	try: virtual.Arena,
	room: game.Room,
	player: game.Player,
	level: level.Level,
	pool: []i32,
	distances: []int,
	events: ^game.Event_Log,
	// The snapshot it copies; whether a try has run since the last reset.
	snapshot: ^Snapshot,
	used: bool,
	// How many times the level and the pools were copied again (the tests and the measures read them).
	level_copies, pool_copies: int,
}

@(private)
clone_dynamic :: proc(source: [dynamic]$T, allocator: mem.Allocator) -> [dynamic]T {
	result := make([dynamic]T, len(source), max(cap(source), 1), allocator)
	copy(result[:], source[:])
	return result
}

@(private)
clone_slice :: proc(source: []$T, allocator: mem.Allocator) -> []T {
	result := make([]T, len(source), allocator)
	copy(result, source)
	return result
}

// Overwrites `target` with `source`, reusing target's memory when it is large enough.
@(private)
overwrite_dynamic :: proc(target: ^[dynamic]$T, source: [dynamic]T) {
	resize(target, len(source))
	copy(target[:], source[:])
}

// A deep copy of a level: every list of it in `allocator`.
copy_level :: proc(target: ^level.Level, source: ^level.Level, allocator: mem.Allocator) {
	target^ = source^
	target.tiles.cells = clone_dynamic(source.tiles.cells, allocator)
	target.heights = clone_dynamic(source.heights, allocator)
	target.structures = clone_dynamic(source.structures, allocator)
	target.structure_plans = clone_dynamic(source.structure_plans, allocator)
	target.structure_cells = clone_dynamic(source.structure_cells, allocator)
	for &plane, slot in target.planes {
		plane.tiles = clone_dynamic(source.planes[slot].tiles, allocator)
		plane.heights = clone_dynamic(source.planes[slot].heights, allocator)
	}
	target.ladders = clone_dynamic(source.ladders, allocator)
	target.lifts = clone_dynamic(source.lifts, allocator)
	target.gates = clone_dynamic(source.gates, allocator)
}

// A level copied before brought back to `source`, in its own memory.
@(private)
restore_level :: proc(target: ^level.Level, source: ^level.Level) {
	tiles, heights, structures, plans, cells := target.tiles.cells, target.heights, target.structures, target.structure_plans, target.structure_cells
	planes := target.planes
	ladders, lifts, gates := target.ladders, target.lifts, target.gates
	target^ = source^
	target.tiles.cells, target.heights, target.structures, target.structure_plans, target.structure_cells = tiles, heights, structures, plans, cells
	target.planes = planes
	target.ladders, target.lifts, target.gates = ladders, lifts, gates
	overwrite_dynamic(&target.tiles.cells, source.tiles.cells)
	overwrite_dynamic(&target.heights, source.heights)
	overwrite_dynamic(&target.structures, source.structures)
	overwrite_dynamic(&target.structure_plans, source.structure_plans)
	overwrite_dynamic(&target.structure_cells, source.structure_cells)
	for &plane, slot in target.planes {
		overwrite_dynamic(&plane.tiles, source.planes[slot].tiles)
		overwrite_dynamic(&plane.heights, source.planes[slot].heights)
	}
	overwrite_dynamic(&target.ladders, source.ladders)
	overwrite_dynamic(&target.lifts, source.lifts)
	overwrite_dynamic(&target.gates, source.gates)
}

// The room's lists, deep, in `allocator`, and its pointers to the copies' own player, level and log.
@(private)
copy_room_lists :: proc(room: ^game.Room, source: ^game.Room, allocator: mem.Allocator) {
	room.enemies = clone_dynamic(source.enemies, allocator)
	room.traps = clone_dynamic(source.traps, allocator)
	room.obstacles = clone_dynamic(source.obstacles, allocator)
	room.objects = clone_dynamic(source.objects, allocator)
	room.loot = clone_dynamic(source.loot, allocator)
	room.event_allocator = allocator
}

snapshot_init :: proc(s: ^Snapshot) -> bool {
	return virtual.arena_init_growing(&s.arena, SNAPSHOT_ARENA_BLOCK) == nil
}

snapshot_destroy :: proc(s: ^Snapshot) {
	virtual.arena_destroy(&s.arena)
	s^ = {}
}

// The photograph of the real room: everything it owns, deep, in the snapshot's own memory. The real room is only read.
snapshot_take :: proc(s: ^Snapshot, real: ^game.Room, game_context: Game_Context = {}) -> bool {
	if s == nil || real == nil || real.player == nil || real.level_data == nil || real.recent_events == nil { return false }
	s.game_context = game_context
	virtual.arena_free_all(&s.arena)
	allocator := virtual.arena_allocator(&s.arena)
	s.room = real^
	s.player = real.player^
	copy_level(&s.level, real.level_data, allocator)
	copy_room_lists(&s.room, real, allocator)
	s.room.enemy_path_distances = clone_slice(real.enemy_path_distances, allocator)
	s.room.ground.pool = clone_slice(real.ground.pool, allocator)
	s.events = new(game.Event_Log, allocator)
	s.room.recent_events = s.events
	s.room.player = &s.player
	s.room.level_data = &s.level
	s.taken = true
	return true
}

rehearsal_init :: proc(r: ^Rehearsal) -> bool {
	return virtual.arena_init_growing(&r.root, REHEARSAL_ARENA_BLOCK) == nil && virtual.arena_init_growing(&r.try, TRY_ARENA_BLOCK) == nil
}

rehearsal_destroy :: proc(r: ^Rehearsal) {
	virtual.arena_destroy(&r.root)
	virtual.arena_destroy(&r.try)
	r^ = {}
}

// A new snapshot to rehearse on: its level and pools copied once, the distance field and the log of the copy's own.
rehearsal_begin :: proc(r: ^Rehearsal, s: ^Snapshot) -> bool {
	if r == nil || s == nil || !s.taken { return false }
	virtual.arena_free_all(&r.root)
	allocator := virtual.arena_allocator(&r.root)
	copy_level(&r.level, &s.level, allocator)
	r.pool = clone_slice(s.room.ground.pool, allocator)
	r.distances = clone_slice(s.room.enemy_path_distances, allocator)
	r.events = new(game.Event_Log, allocator)
	r.snapshot = s
	r.used = false
	r.level_copies, r.pool_copies = 0, 0
	return true
}

// The copy rebuilt from the snapshot for one more try, and the room to try on. The level and the pools are copied
// again only when the last try changed them.
rehearsal_room :: proc(r: ^Rehearsal) -> ^game.Room {
	s := r.snapshot
	if s == nil { return nil }
	if r.used {
		if r.level.geometry_revision != s.level.geometry_revision {
			restore_level(&r.level, &s.level)
			r.level_copies += 1
		}
		if r.room.ground.pool_writes != s.room.ground.pool_writes {
			copy(r.pool, s.room.ground.pool)
			r.pool_copies += 1
		}
	}
	virtual.arena_free_all(&r.try)
	allocator := virtual.arena_allocator(&r.try)
	r.room = s.room
	r.player = s.player
	copy_room_lists(&r.room, &s.room, allocator)
	r.room.player = &r.player
	r.room.level_data = &r.level
	r.room.ground.pool = r.pool
	r.room.enemy_path_distances = r.distances
	game.clear_event_log(r.events)
	r.room.recent_events = r.events
	r.used = true
	return &r.room
}

// The allocator a try runs with: the try's own arena.
@(private)
try_allocator :: proc(r: ^Rehearsal) -> mem.Allocator {
	return virtual.arena_allocator(&r.try)
}
