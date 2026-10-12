package fight

import engine "../engine"

// Tag match: one player against a roster. One opponent fights in the ring
// (fighters[1]); the others wait on the apron at their own corner post.
// A knocked-out opponent is replaced from the next corner. An opponent in
// trouble may run to a healthy ally's corner and slap its hand: the two swap,
// the tired one waiting where the fresh one stood. The player always fights
// alone, and wins only when the whole roster is down.

MAX_RING_ROSTER :: 4
RING_PLAYER_HEALTH :: i32(8)
RING_CHAMPION_HEALTH :: i32(12)
TAG_COOLDOWN_TICKS :: 300
TAG_ENTER_TICKS :: 40
TAG_FLASH_TICKS :: 45
TAG_REACH :: f32(0.65)
// Where a fighter reaches a post inside the ropes, and where allies wait outside.
TAG_POST :: f32(3.95)
APRON_POST :: f32(4.95)

Roster_Entry :: struct {
	// The board's archetype (an index), for the presentation only.
	kind: int,
	enemy_id: u32,
	health, max_health: i32,
	corner: int,
	ko: bool,
}

Roster :: struct {
	entries: [MAX_RING_ROSTER]Roster_Entry,
	count: int,
	player_health, player_max: i32,
}

corner_sign :: proc(corner: int) -> (x, z: f32) {
	switch corner & 3 {
	case 0: return 1, -1
	case 1: return 1, 1
	case 2: return -1, 1
	}
	return -1, -1
}

tag_post :: proc(corner: int) -> engine.Vec3 {
	x, z := corner_sign(corner)
	return {x*TAG_POST, 0, z*TAG_POST}
}

apron_post :: proc(corner: int) -> engine.Vec3 {
	x, z := corner_sign(corner)
	return {x*APRON_POST, 0, z*APRON_POST}
}

// Seats a roster in a fresh fight: the first entry fights, the rest wait.
apply_roster :: proc(state: ^State, roster: Roster) {
	if state == nil || roster.count <= 0 { return }
	state.roster_count = min(roster.count, MAX_RING_ROSTER)
	for index in 0..<state.roster_count {
		state.roster[index] = roster.entries[index]
		state.roster[index].corner = index
		state.roster[index].health = max(i32(1), state.roster[index].health)
		state.roster[index].max_health = max(state.roster[index].health, state.roster[index].max_health)
	}
	state.active = 0
	state.tag_target = -1
	if roster.player_max > 0 {
		state.fighters[0].max_health = roster.player_max
		state.fighters[0].health = clamp(roster.player_health, 1, roster.player_max)
	}
	entry := state.roster[0]
	state.fighters[1].health, state.fighters[1].max_health = entry.health, entry.max_health
	state.tag_cooldown = TAG_COOLDOWN_TICKS/2
}

// Opponents of a tag match share the load: each enters with less health.
ring_opponent_health :: proc(count: int) -> i32 {
	switch count {
	case 2: return 9
	case 3: return 7
	case 4: return 6
	}
	return RING_CHAMPION_HEALTH
}

roster_waiting :: proc(state: ^State, index: int) -> bool {
	return index >= 0 && index < state.roster_count && index != state.active && !state.roster[index].ko
}

// Puts roster entry `next` into the ring at its corner post. The opponent it
// replaces keeps its health and, if still standing, waits at that corner.
bring_in :: proc(state: ^State, next: int) {
	leaving := state.active
	corner := state.roster[next].corner
	if leaving >= 0 && leaving < state.roster_count {
		state.roster[leaving].health = max(i32(0), state.fighters[1].health)
		state.roster[leaving].corner = corner
	}
	state.active = next
	entry := &state.roster[next]
	entry.corner = -1
	post := tag_post(corner)
	fighter := &state.fighters[1]
	fighter^ = {position = post, previous = post, facing = {-post.x, 0, -post.z}, health = entry.health, max_health = entry.max_health}
	state.ai_wait = TAG_ENTER_TICKS
	state.tag_target = -1
	state.tag_cooldown = TAG_COOLDOWN_TICKS
	state.tag_flash_ticks = TAG_FLASH_TICKS
	state.tags += 1
	sync_fighters(state)
}

// A knockout with allies still waiting brings the next one in instead of
// ending the match. Returns true when the match continues.
roster_replace_knockout :: proc(state: ^State) -> bool {
	if state.roster_count <= 1 || state.active < 0 { return false }
	state.roster[state.active].ko = true
	state.roster[state.active].health = 0
	for offset in 1..<state.roster_count {
		next := (state.active+offset)%state.roster_count
		if roster_waiting(state, next) {
			// The fallen opponent leaves the ring; its corner stays empty.
			state.roster[state.active].corner = -1
			bring_in(state, next)
			return true
		}
	}
	return false
}

// The opponent's own decision to tag out, run every tick before its input.
tick_tag :: proc(state: ^State) {
	if state.tag_flash_ticks > 0 { state.tag_flash_ticks -= 1 }
	if state.roster_count <= 1 { return }
	if state.tag_cooldown > 0 { state.tag_cooldown -= 1 }
	enemy := &state.fighters[1]
	if state.tag_target >= 0 {
		if !roster_waiting(state, state.tag_target) { state.tag_target = -1; return }
		post := tag_post(state.roster[state.tag_target].corner)
		if enemy.action == .Idle && distance_squared(enemy.position, post) <= TAG_REACH*TAG_REACH {
			bring_in(state, state.tag_target)
		}
		return
	}
	if state.tag_cooldown > 0 || enemy.action != .Idle || enemy.health*10 > enemy.max_health*4 { return }
	best := -1
	for index in 0..<state.roster_count {
		if !roster_waiting(state, index) { continue }
		entry := state.roster[index]
		if entry.health*2 <= entry.max_health { continue }
		if best < 0 || entry.health > state.roster[best].health { best = index }
	}
	state.tag_target = best
}

// Final health of every roster entry, including the one still in the ring.
roster_outcome :: proc(state: ^State) -> (roster: Roster) {
	roster.count = state.roster_count
	roster.player_health, roster.player_max = state.fighters[0].health, state.fighters[0].max_health
	for index in 0..<state.roster_count {
		roster.entries[index] = state.roster[index]
		if index == state.active { roster.entries[index].health = max(i32(0), state.fighters[1].health) }
	}
	return
}
