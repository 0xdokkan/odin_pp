package game

import grid "../grid"
import rng "../engine/rng"

// The mechanics sandbox ("PROVA MECCANICHE"): one open arena where the combat
// never ends. Enemies keep arriving on random free cells away from the
// player, and the floor's easter eggs open again every time, so a mechanic can
// be tried over and over.
SANDBOX_MAX_ENEMIES :: 6
// Seconds of board time between arrivals, while below the maximum.
SANDBOX_SPAWN_SECONDS :: f32(4)
// Newcomers appear at least this many cells away (Chebyshev) from the player.
SANDBOX_SPAWN_DISTANCE :: 4

Sandbox_State :: struct {
	random: u64,
	timer: f32,
	spawned: int,
}

// Who may arrive, with health and attack; the boss stays out.
SANDBOX_ROSTER :: [5]Enemy_Spawn{
	{health = 12, attack = 2, archetype = .Chaser},
	{health = 10, attack = 2, archetype = .Archer},
	{health = 18, attack = 3, archetype = .Brute},
	{health = 12, attack = 2, archetype = .Bomber},
	{health = 14, attack = 2, archetype = .Custodian},
}

begin_sandbox :: proc(seed: u64) -> Sandbox_State {
	return {random = seed if seed != 0 else 0x5A9D_B0C5, timer = SANDBOX_SPAWN_SECONDS}
}

sandbox_random :: proc(sandbox: ^Sandbox_State, below: int) -> int {
	return int(rng.step(&sandbox.random)%u64(max(below, 1)))
}

// Advances the arrivals by `dt` seconds of running board time. A new enemy
// only appears between actions, never in the middle of a world beat; an empty
// arena is refilled at once. Returns the newcomer's id.
sandbox_tick :: proc(room: ^Room, sandbox: ^Sandbox_State, dt: f32) -> (id: u32, spawned: bool) {
	if room == nil || room.player == nil || sandbox == nil || !room.endless || room.phase != .Combat { return }
	// The arrivals' clock stops with the world inside Movimento Ombra.
	if tactical_shadow_active(room) { return }
	// Easter eggs stay open here: the sandbox is for trying them again.
	if !room.tesla_ring.pending { room.player.floor_secrets = {} }
	sandbox.timer = max(sandbox.timer-max(dt, 0), 0)
	if len(room.enemies) >= SANDBOX_MAX_ENEMIES || (len(room.enemies) > 0 && sandbox.timer > 0) { return }
	if !tactical_allows_action(room) { return }
	cell, found := sandbox_spawn_cell(room, sandbox)
	if !found { return }
	roster := SANDBOX_ROSTER
	spawn := roster[sandbox_random(sandbox, len(roster))]
	spawn.position = cell
	// Every third arrival carries a healing drop.
	spawn.drops_healing = sandbox.spawned%3 == 2
	id, spawned = spawn_enemy(room, spawn)
	if spawned {
		sandbox.spawned += 1
		sandbox.timer = SANDBOX_SPAWN_SECONDS
	}
	return
}

// A random free cell at least SANDBOX_SPAWN_DISTANCE from the player; in a
// room too small for that, one of the farthest free cells.
sandbox_spawn_cell :: proc(room: ^Room, sandbox: ^Sandbox_State) -> (grid.Position, bool) {
	data := room.level_data
	if data == nil { return {}, false }
	farthest := -1
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			cell := grid.Position{x, y}
			if enemy_spawn_cell_is_free(room, cell) { farthest = max(farthest, sandbox_distance(room, cell)) }
		}
	}
	if farthest < 1 { return {}, false }
	needed := min(farthest, SANDBOX_SPAWN_DISTANCE)
	candidates := 0
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			cell := grid.Position{x, y}
			if sandbox_distance(room, cell) >= needed && enemy_spawn_cell_is_free(room, cell) { candidates += 1 }
		}
	}
	pick := sandbox_random(sandbox, candidates)
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			cell := grid.Position{x, y}
			if sandbox_distance(room, cell) < needed || !enemy_spawn_cell_is_free(room, cell) { continue }
			if pick == 0 { return cell, true }
			pick -= 1
		}
	}
	return {}, false
}

sandbox_distance :: proc(room: ^Room, cell: grid.Position) -> int {
	return max(abs(cell.x-room.player.position.x), abs(cell.y-room.player.position.y))
}
