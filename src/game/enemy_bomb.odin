package game

import grid "../engine/grid"

// THE BOMBERS' BOMBS IN FLIGHT (docs/piano-succo.md, Fase 5). On its throw's
// beat a bomber (or the Demolitionist) lobs its bomb at the cell it chose; the
// bomb flies ENEMY_BOMB_FLIGHT world seconds in an arc (the user's choice of
// 2026-11-02) and only then is on its cell: it lands (Object_Spawned) and its
// fuse is lit (Explosive_Armed), TACTICAL_BOMB_FUSE beats as before. A flight
// is shorter than a beat's world second, so it always lands before the next
// beat: that beat lands any still in the air first, before its own work, and
// the blast comes on the same beat as when the bomb appeared at once. A cell taken while
// it flew (an object set there) and it rolls off and goes out: a miss.
//
// Like the archers' arrows (enemy_arrow.odin) it flies on the world's seconds:
// a shadow, a cast, a defence or a die hold it as they hold the world.

ENEMY_BOMB_FLIGHT :: f32(0.6)
// Bombs in the air at once: a bomber keeps one bomb at a time
// (TACTICAL_BOMB_LIMIT), the Demolitionist's overdrive throws two; a third
// throw misses.
MAX_ENEMY_BOMB_FLIGHTS :: 2
@(private = "file")
ENEMY_BOMB_EPSILON :: f32(0.00001)

// Small: the room keeps them inline, under its stack budget (event_test.odin).
Enemy_Bomb :: struct {
	// Its thrower's cell as it threw and the cell it falls on (x, y, layer).
	origin, target: [3]i16,
	thrower: u32,
	// World seconds flown.
	flown: f32,
}

Enemy_Bombs :: struct {
	items: [MAX_ENEMY_BOMB_FLIGHTS]Enemy_Bomb,
	count: i32,
	// World seconds not flown out yet.
	pending: f32,
}

enemy_bomb_origin :: proc(bomb: Enemy_Bomb) -> grid.Position {
	return {x = int(bomb.origin.x), y = int(bomb.origin.y), layer = i8(bomb.origin.z)}
}

enemy_bomb_target :: proc(bomb: Enemy_Bomb) -> grid.Position {
	return {x = int(bomb.target.x), y = int(bomb.target.y), layer = i8(bomb.target.z)}
}

// How far along its arc a bomb is, 0 to 1, its seconds still waiting included
// (the board draws it there).
enemy_bomb_progress :: proc(room: ^Room, bomb: Enemy_Bomb) -> f32 {
	pending := room.bombs.pending if room != nil else 0
	return clamp((bomb.flown+pending)/ENEMY_BOMB_FLIGHT, 0, 1)
}

// The bomber lobs its bomb at `target`. False when it cannot (no room for
// another bomb in the air).
@(private)
throw_enemy_bomb :: proc(room: ^Room, enemy: ^Enemy, target: grid.Position, pulse: ^Pulse_Report) -> bool {
	if room == nil || enemy == nil || pulse == nil || room.bombs.count >= MAX_ENEMY_BOMB_FLIGHTS { return false }
	room.bombs.items[room.bombs.count] = {
		origin = {i16(enemy.position.x), i16(enemy.position.y), i16(enemy.position.layer)},
		target = {i16(target.x), i16(target.y), i16(target.layer)},
		thrower = enemy.id,
	}
	room.bombs.count += 1
	record_event(&pulse.events, {kind = .Bomb_Thrown, source = enemy_entity(enemy.id), target = SYSTEM_ENTITY,
		object_kind = .Bomb, from_position = enemy.position, to_position = target})
	return true
}

// The bombs fly their seconds waiting into `pulse`: each one at its arc's end
// lands, in order; at a beat's start (`beat`) every one lands.
@(private)
fly_enemy_bombs :: proc(room: ^Room, pulse: ^Pulse_Report, beat := false) {
	b := &room.bombs
	seconds := b.pending
	b.pending = 0
	for index := i32(0); index < b.count; {
		bomb := &b.items[index]
		bomb.flown += seconds
		if !beat && bomb.flown+ENEMY_BOMB_EPSILON < ENEMY_BOMB_FLIGHT {
			index += 1
			continue
		}
		landed := bomb^
		b.items[index] = b.items[b.count-1]
		b.count -= 1
		land_enemy_bomb(room, landed, pulse)
		if room.phase != .Combat { return }
	}
}

// A bomb at its arc's end: on its cell with its fuse lit, or, the cell taken
// while it flew, a miss.
@(private = "file")
land_enemy_bomb :: proc(room: ^Room, bomb: Enemy_Bomb, pulse: ^Pulse_Report) {
	source := enemy_entity(bomb.thrower)
	target := enemy_bomb_target(bomb)
	if !spawn_bomb(room, source, target, &pulse.events, true) {
		record_enemy_attack_miss(pulse, source, enemy_bomb_origin(bomb), target)
	}
}
