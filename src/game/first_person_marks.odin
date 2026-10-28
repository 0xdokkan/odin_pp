package game

import "core:math"
import rng "../engine/rng"

// FIRST PERSON BRAWLER's critical marks (docs/piano-prima-persona.md, sezione 5.5
// and Fase 2): on the foes near him and in sight (FISTS_MARK_RANGE cells, the
// nearest FISTS_MARKS of them), a mark lights at a random moment on one of four
// zones across the foe's card as he sees it, and on its head or its body; it
// stays lit FISTS_MARK_SECONDS. The zone names the punch: the card's left side
// the left hook, left of its middle the jab, right of it the cross, its right
// side the right hook (a left hook lands on the right flank of a foe facing him,
// which he sees on the left). The right punch landing while the crosshair is over
// the lit mark (the user's choice: the punch alone is not enough) is a critical:
// FISTS_CRITICAL_FACTOR times its damage, and a critical hook staggers the foe
// (Stagger, a beat: it breaks the blow it was winding up). The mark goes out and
// the next lights FISTS_MARK_CHAIN seconds later on another zone, for a chain,
// as Fortnite's pickaxe weak point moves on after each hit. The wrong punch does
// its own damage and leaves the mark lit. Times are world seconds on the body's
// clock; the zones come from the view's own stream (First_Person_Fists.random),
// so the tests repeat them.

FISTS_MARKS :: 4
FISTS_MARK_RANGE :: f32(3.5)
FISTS_MARK_SECONDS :: f32(1.2)
FISTS_MARK_WAIT_MIN :: f32(0.6)
FISTS_MARK_WAIT_MAX :: f32(1.4)
FISTS_MARK_CHAIN :: f32(0.3)
FISTS_CRITICAL_FACTOR :: i32(3)
FISTS_STAGGER_BEATS :: i32(1)
FISTS_MARK_SALT :: u64(0x46_4953_5453)

// The zone across a card each punch strikes (-1: none).
@(rodata)
FISTS_PUNCH_ZONE := [First_Person_Punch]i8{.None = -1, .Left_Hook = 0, .Jab = 1, .Cross = 2, .Right_Hook = 3}

First_Person_Mark :: struct {
	// The foe it watches (0: an empty slot).
	enemy_id: u32,
	// Its zone (0 the card's left side .. 3 its right side, as he sees it), on
	// the head or the body; seconds left lit (0: dark), and dark, until it lights.
	zone: i8,
	high: bool,
	lit, wait: f32,
	// The last went out to a critical: the next lights on another zone.
	chained: bool,
}

// The marks' stream, from the room's and the view's count of blows, as the fists are taken up.
@(private)
fists_marks_begin :: proc(room: ^Room) {
	f := &room.first_person.fists
	f.random = mix_room_seed(room.pinball_random~FISTS_MARK_SALT~u64(room.first_person.shots))
	if f.random == 0 { f.random = FISTS_MARK_SALT }
}

@(private = "file")
fists_mark_wait :: proc(f: ^First_Person_Fists) -> f32 {
	span := u64(math.round((FISTS_MARK_WAIT_MAX-FISTS_MARK_WAIT_MIN)*1000))
	return FISTS_MARK_WAIT_MIN+f32(rng.below_state(&f.random, span+1))/1000
}

// Whether a mark may watch `enemy`: in play, in sight, near the body.
@(private = "file")
fists_mark_watches :: proc(room: ^Room, enemy: Enemy) -> (near: bool, distance: f32) {
	if enemy_is_out_of_play(room, enemy.id) || !tactical_cell_visible(room, enemy.position) { return }
	b := room.first_person.fists.body
	d := [2]f32{f32(enemy.position.x)+0.5-b.x, f32(enemy.position.y)+0.5-b.y}
	distance = math.sqrt(d.x*d.x+d.y*d.y)
	return distance <= FISTS_MARK_RANGE, distance
}

// One FISTS_STEP of the marks: the slots follow the nearest foes in reach, each
// mark lights and goes out on its time.
@(private)
fists_marks_step :: proc(room: ^Room, h: f32) {
	f := &room.first_person.fists
	for &mark in f.marks {
		if mark.enemy_id == 0 { continue }
		index, found := enemy_index_by_id(room, mark.enemy_id)
		near := false
		if found { near, _ = fists_mark_watches(room, room.enemies[index]) }
		if !near { mark = {} }
	}
	// The nearest foes in reach not watched yet take the free slots, or a nearer
	// one the farthest slot.
	for _ in 0..<FISTS_MARKS {
		best, best_distance := u32(0), max(f32)
		for enemy in room.enemies {
			near, distance := fists_mark_watches(room, enemy)
			if !near || distance >= best_distance { continue }
			watched := false
			for mark in f.marks { watched = watched || mark.enemy_id == enemy.id }
			if !watched { best, best_distance = enemy.id, distance }
		}
		if best == 0 { break }
		slot, slot_distance := -1, f32(-1)
		for mark, at in f.marks {
			if mark.enemy_id == 0 { slot, slot_distance = at, max(f32); break }
			index, _ := enemy_index_by_id(room, mark.enemy_id)
			_, distance := fists_mark_watches(room, room.enemies[index])
			if distance > slot_distance { slot, slot_distance = at, distance }
		}
		if slot < 0 || slot_distance <= best_distance { break }
		f.marks[slot] = {enemy_id = best, wait = fists_mark_wait(f)}
	}
	for &mark in f.marks {
		if mark.enemy_id == 0 { continue }
		if mark.lit > 0 {
			mark.lit -= h
			if mark.lit <= 1e-6 { mark.lit, mark.wait, mark.chained = 0, fists_mark_wait(f), false }
			continue
		}
		mark.wait -= h
		if mark.wait > 1e-6 { continue }
		zone := i8(rng.below_state(&f.random, 4))
		if mark.chained { zone = i8((int(mark.zone)+1+int(rng.below_state(&f.random, 3)))%4) }
		mark.zone, mark.high, mark.lit, mark.wait, mark.chained = zone, rng.below_state(&f.random, 2) == 0, FISTS_MARK_SECONDS, 0, false
	}
}

// The lit mark on `enemy_id` (nil: none lit).
first_person_lit_mark :: proc(room: ^Room, enemy_id: u32) -> ^First_Person_Mark {
	if !first_person_fists_active(room) { return nil }
	for &mark in room.first_person.fists.marks {
		if mark.enemy_id == enemy_id && mark.lit > 0 { return &mark }
	}
	return nil
}

// Where the crosshair is on `enemy`'s card along `aim` from the body: its zone
// across the card and whether on its head; not `on` when the view's ray meets
// something else first, or nothing.
first_person_crosshair_zone :: proc(room: ^Room, enemy_id: u32, aim: First_Person_Aim) -> (zone: i8, high, on: bool) {
	if !first_person_fists_active(room) { return }
	index, found := enemy_index_by_id(room, enemy_id)
	if !found { return }
	look := aim
	look.framed, look.eye = true, room.first_person.fists.body
	shot := first_person_trace(room, room.player.position, look)
	if shot.hit != .Foe || shot.target != enemy_entity(enemy_id) { return }
	enemy := room.enemies[index]
	at, lift := first_person_card(enemy, look)
	// Across the card as he sees it: his view's right is the way's quarter turn.
	d := [2]f32{math.cos(aim.yaw), math.sin(aim.yaw)}
	across := (shot.point.x-at.x)*(-d.y)+(shot.point.z-at.y)*d.x
	height := shot.point.y-f32(cell_height(room, enemy.position))*HEIGHT_STEP_DRAWN-lift
	half := first_person_outline_half_width(enemy.archetype, height)
	if half <= 0 { return }
	zone = i8(clamp(int(math.floor((across/half+1)*2)), 0, 3))
	return zone, height >= first_person_outline_top(enemy.archetype)*0.5, true
}

// Whether `punch` landing on `enemy_id` along `aim` is a critical: the mark lit on
// it asks that punch and the crosshair is over it.
first_person_punch_critical :: proc(room: ^Room, punch: First_Person_Punch, enemy_id: u32, aim: First_Person_Aim) -> bool {
	mark := first_person_lit_mark(room, enemy_id)
	if mark == nil || FISTS_PUNCH_ZONE[punch] != mark.zone { return false }
	zone, high, on := first_person_crosshair_zone(room, enemy_id, aim)
	return on && zone == mark.zone && high == mark.high
}

// A critical put the mark out: the next lights soon, elsewhere.
@(private)
fists_mark_struck :: proc(room: ^Room, enemy_id: u32) {
	mark := first_person_lit_mark(room, enemy_id)
	if mark == nil { return }
	mark.lit, mark.wait, mark.chained = 0, FISTS_MARK_CHAIN, true
	room.first_person.fists.crits += 1
}
