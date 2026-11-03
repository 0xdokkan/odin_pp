package game

import "core:math"
import grid "../engine/grid"

// BENVENUTI A NAPOLI's face 1, the club (napoli.odin; docs/piano-napoli.md,
// Fase 2, the user's choices of 2026-11-02): the ace of clubs in hand, the
// player's own back seen from close behind his right shoulder (the board's
// third person camera, render/first_person_club.odin). It is a weapon of the
// view behind his eyes, so it shares the view's seconds, its ban on cards and
// its save. He keeps to the grid as with the AK, his keys turned with the view
// (first_person_key_directions), a step CLUB_MOVE_SECONDS long; the mouse turns
// the view.
//
// THE BLOW. The left button pressed, with his body free (no step, no other
// action under way), brings the club down on the cell in front of him: of the
// eight round him, the one nearest the view's look (club_way), a diagonal one
// closed when both cells beside it are solid. CLUB_WINDUP_SECONDS raised over
// his head, then the impact, then CLUB_RECOVER_SECONDS back: his body busy all
// CLUB_SWING_SECONDS (no step, no new blow). At the impact the foe on that cell
// takes the card's damage (NAPOLI_CLUB_DAMAGE, +1 an upgrade) and a Stagger;
// with no foe a thing a bump breaks (a barrel, an ice block) takes it; with
// neither the club strikes the floor. A dodge mid-blow leaves it unstruck.
//
// THE STAGGER WEARS (the user's choice: diminishing returns, as World of
// Warcraft's): the first blow on a foe staggers him NAPOLI_CLUB_STAGGER_BEATS,
// the next half of it, then none, until CLUB_STAGGER_QUIET_SECONDS of the
// world's pass with no blow of the club on him. The damage is always whole. A
// Stagger never adds up anyway (apply_status: the longer one stays).

CLUB_WINDUP_SECONDS :: f32(0.25)
CLUB_RECOVER_SECONDS :: f32(0.35)
CLUB_SWING_SECONDS :: CLUB_WINDUP_SECONDS+CLUB_RECOVER_SECONDS
CLUB_MOVE_SECONDS :: f32(0.5)
CLUB_STAGGER_QUIET_SECONDS :: f32(4)
// The foes the club remembers staggering at once.
CLUB_MEMORY :: 4
// World seconds a frame's command catches up at most.
CLUB_MAX_PENDING :: f32(1)
// The club's wounds carry this in Game_Event.visual_group.
CLUB_VISUAL_GROUP :: u32(0x4B_5004)

// The eight ways round the player by eighth turns of the view's yaw, from the
// east (a quarter turn is south: the board's y).
@(rodata)
CLUB_WAYS := [8][2]i8{{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}}

// What a blow met.
Club_Hit :: enum u8 {None, Floor, Object, Foe}

// The blow under way: since when (world seconds into it), which way, from
// where, and whether it has struck yet.
Club_Blow :: struct {
	active, landed: bool,
	way: [2]i8,
	from: grid.Position,
	at: f32,
}

// A foe the club staggered: how many blows in a row, the seconds since the last.
Club_Memory :: struct {
	enemy_id: u32,
	count: u8,
	quiet: f32,
}

// The last impact, for the board, the lab and the tests.
Club_Impact :: struct {
	hit: Club_Hit,
	cell: grid.Position,
	target: Entity_Ref,
	damage, stagger: i32,
	number: i32,
}

First_Person_Club :: struct {
	// The blow's damage at the card's upgrade level and tick (napoli.odin).
	damage: i32,
	blow: Club_Blow,
	// World seconds not yet run by the blow (tactical_first_person_tick).
	pending: f32,
	memory: [CLUB_MEMORY]Club_Memory,
	// Counted for the board, the lab's sounds and the tests.
	swings, impacts, strikes, whiffs: i32,
	last: Club_Impact,
}

// What the controller asks of the club this frame: the left button pressed,
// along the view's yaw.
First_Person_Club_Input :: struct {
	swing: bool,
	yaw: f32,
}

first_person_club_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Club
}

// A blow under way (his body is busy with it).
first_person_club_swinging :: proc(room: ^Room) -> bool {
	return first_person_club_active(room) && room.first_person.club.blow.active
}

// Taking the club up: its damage at the card's level, nothing remembered.
first_person_club_begin :: proc(room: ^Room, damage: i32) {
	if room == nil { return }
	room.first_person.club = {damage = max(damage, 1)}
}

// The way of the eight nearest the view's `yaw` (an exact tie goes clockwise).
club_way :: proc(yaw: f32) -> [2]i8 {
	eighths := lasso_wrap(f64(yaw))/(math.PI/4)
	return CLUB_WAYS[int(math.floor(eighths+0.5))%8]
}

// The cell a blow `way` from `from` strikes, and whether it reaches it: a
// diagonal is closed by two solid cells beside it; a foe a step up or down on
// another layer is struck as a bump would (bump_cell).
club_cell :: proc(room: ^Room, from: grid.Position, way: [2]i8) -> (cell: grid.Position, reached: bool) {
	step := grid.Position{x = int(way.x), y = int(way.y)}
	cell = bump_cell(room, from, step)
	if way.x != 0 && way.y != 0 &&
	   lasso_cell_is_solid(room, grid.offset(from, step.x, 0)) && lasso_cell_is_solid(room, grid.offset(from, 0, step.y)) {
		return cell, false
	}
	return cell, true
}

// The cell the view aims a blow at now (the board marks it on the floor).
club_aimed_cell :: proc(room: ^Room, yaw: f32) -> (cell: grid.Position, reached: bool) {
	if room == nil || room.player == nil { return }
	return club_cell(room, room.player.position, club_way(yaw))
}

// How long a blow on `enemy_id` staggers him now (diminishing returns), and
// the memory slot it counts in.
club_stagger_beats :: proc(club: ^First_Person_Club, enemy_id: u32) -> (beats: i32, slot: int) {
	slot = -1
	oldest := f32(-1)
	for memory, index in club.memory {
		if memory.enemy_id == enemy_id && memory.count > 0 && memory.quiet < CLUB_STAGGER_QUIET_SECONDS {
			slot = index
			break
		}
	}
	count := 0
	if slot >= 0 {
		count = int(club.memory[slot].count)
	} else {
		// A fresh foe takes a free slot, or the one quiet the longest.
		for memory, index in club.memory {
			quiet := memory.quiet if memory.count > 0 && memory.quiet < CLUB_STAGGER_QUIET_SECONDS else max(f32)
			if quiet > oldest { oldest, slot = quiet, index }
		}
	}
	switch count {
	case 0: beats = NAPOLI_CLUB_STAGGER_BEATS
	case 1: beats = NAPOLI_CLUB_STAGGER_BEATS/2
	case: beats = 0
	}
	return
}

// The world's seconds (tactical_first_person_tick): the blow's, run by the
// frame's command; the memory's quiet. The grandpa's club too (napoli_nonno.odin).
@(private)
first_person_club_tick :: proc(c: ^First_Person_Club, seconds: f32) {
	if c.blow.active { c.pending = min(c.pending+seconds, CLUB_MAX_PENDING) }
	for &memory in c.memory { memory.quiet = min(memory.quiet+seconds, 60) }
}

// The impact: the foe on the cell, else a damageable thing, else the floor.
@(private = "file")
club_land :: proc(room: ^Room, c: ^First_Person_Club) {
	cell, reached := club_cell(room, c.blow.from, c.blow.way)
	c.impacts += 1
	c.last = {hit = .Floor, cell = cell, target = SYSTEM_ENTITY, number = c.impacts}
	if !reached { c.whiffs += 1; return }
	if index, found := enemy_index_at(room, cell); found && !enemy_is_out_of_play(room, room.enemies[index].id) {
		enemy := room.enemies[index]
		target := enemy_entity(enemy.id)
		action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
		action.visual_group = CLUB_VISUAL_GROUP
		if !add_effect(&action, damage_effect(target, c.damage)) { return }
		report := resolve_action(room, &action)
		if !report.accepted { return }
		append_event_log(room.recent_events, &report.events)
		c.strikes += 1
		room.first_person.hits += 1
		c.last.hit, c.last.target, c.last.damage = .Foe, target, player_damage_dealt(&report, target)
		beats, slot := club_stagger_beats(c, enemy.id)
		if slot >= 0 {
			memory := &c.memory[slot]
			if memory.enemy_id != enemy.id || memory.quiet >= CLUB_STAGGER_QUIET_SECONDS { memory^ = {enemy_id = enemy.id} }
			memory.count = min(memory.count, 254)+1
			memory.quiet = 0
		}
		if beats > 0 && room.phase == .Combat {
			if _, alive := enemy_index_by_id(room, enemy.id); alive {
				stagger := make_action(.Trigger, PLAYER_ENTITY, entity_target(target), .Opponent)
				stagger.visual_group = CLUB_VISUAL_GROUP
				if add_effect(&stagger, apply_status_effect(target, .Stagger, 1, beats)) {
					staggered := resolve_action(room, &stagger)
					if staggered.accepted {
						append_event_log(room.recent_events, &staggered.events)
						c.last.stagger = beats
					}
				}
			}
		}
		collect_loot_in_magnet_range(room)
		return
	}
	if object, found := grid_object_at(room, cell); found {
		// What a bump breaks (a barrel, an ice block: try_move_player), never the
		// player's own devices.
		if definition, known := grid_object_definition(object.kind); known && definition.damageable && definition.movable {
			ref := object_entity(object.id)
			action := make_action(.Attack, PLAYER_ENTITY, entity_target(ref), .Opponent_Or_Object)
			action.visual_group = CLUB_VISUAL_GROUP
			if add_effect(&action, damage_effect(ref, c.damage)) {
				report := resolve_action(room, &action)
				if report.accepted {
					append_event_log(room.recent_events, &report.events)
					c.last.hit, c.last.target, c.last.damage = .Object, ref, c.damage
					return
				}
			}
		}
	}
	c.whiffs += 1
}

// The club this frame: a blow begun on a press, the blow run over the world's
// seconds since the last frame, its impact. Their events are the room's
// recent ones.
first_person_club_move :: proc(room: ^Room, input: First_Person_Club_Input) -> (result: Action_Result) {
	if !first_person_club_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	c := &room.first_person.club
	acted := false
	// A dodge (or anything else that moved him) mid-blow leaves it unstruck.
	if c.blow.active && room.player.position != c.blow.from { c.blow, c.pending = {}, 0 }
	if input.swing && !c.blow.active && tactical_allows_action(room) {
		club_begin_blow(room, c, club_way(input.yaw), input.yaw)
		switch finish_player_combat_command(room, 0) {
		case .Player_Defeated: return .Player_Defeated
		case .Combat_Ended: return .Combat_Ended
		case .Combat_Continues:
		}
		// His body is the blow's all through it (with untimed actions the world
		// runs it out at once: tactical_spend_action_time).
		tactical_spend_action_time(room, CLUB_SWING_SECONDS)
		acted = true
	}
	if club_run(room, c) { acted = true }
	if !acted { return .None }
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
		return .Combat_Ended
	}
	return .Moved
}

// A blow begun `way` from where he stands, the view along `yaw`.
@(private)
club_begin_blow :: proc(room: ^Room, c: ^First_Person_Club, way: [2]i8, yaw: f32) {
	c.blow = {active = true, way = way, from = room.player.position}
	c.pending = 0
	c.swings += 1
	room.first_person.shots += 1
	room.player.tactical.facing = first_person_key_directions(yaw)[0]
}

// The blow under way run over the world's seconds since the last frame: its
// impact once raised, its end. Whether it struck now.
@(private)
club_run :: proc(room: ^Room, c: ^First_Person_Club) -> (struck: bool) {
	if !c.blow.active { c.pending = 0; return }
	c.blow.at += c.pending
	c.pending = 0
	if !c.blow.landed && c.blow.at >= CLUB_WINDUP_SECONDS-1e-5 {
		c.blow.landed = true
		club_land(room, c)
		struck = true
	}
	if c.blow.at >= CLUB_SWING_SECONDS-1e-5 { c.blow = {} }
	return
}

// The club's own wounds.
event_is_first_person_club :: proc(event: Game_Event) -> bool {
	return event.visual_group == CLUB_VISUAL_GROUP
}
