package game

import "core:math"
import grid "../engine/grid"
import level "../level"

// LANCIAFIAMME (docs/piano-ia.md, Fase 13). A weapon of the views' family with one difference: the camera stays on the board
// (FIRST_PERSON_WEAPONS, on_board). From the family it takes the seconds, the ban on cards and bumps, the save and the IA's
// pause. He walks on the board's own keys at his own pace (tactical_player_pace), firing or not, and dodges as always.
//
// THE AIM. The point of the board under the mouse gives a way; he turns to it at 720 degrees a second.
//
// THE FLAME. A piece of flame leaves him every FLAME_STEP while the left button is held, and goes straight the way it left at
// 15 cells a second for 3 cells, a fifth of a second: turning, the tip stays behind him, the trail. The rules keep the
// pieces in flight and strike where the flame is seen, not only where the nozzle points; let go, what is out runs on.
// The flame is 0.4 cells wide at the nozzle and 1.2 at the tip. Walls and covers stop a piece; low walls do not.
//
// WHAT IT TOUCHES. A foe takes 3 and a stack of Bruciatura, then nothing from the flame for 2 seconds, each foe his own time.
// A barrel goes off, a block of ice melts, and each stops the piece. A cell the tip stays on for a second catches fire as the
// Incendio does, at most one new fire a second; the fires on the floor never touch the player.

FLAMETHROWER_SECONDS :: i32(20)
FLAME_DAMAGE :: i32(3)
FLAME_BURN :: i32(1)
// How long a foe touched stays untouched.
FLAME_WAIT_SECONDS :: f32(2)
FLAME_TURN_RADIANS :: f32(4*math.PI)
FLAME_SPEED :: f32(15)
FLAME_LENGTH :: f32(3)
FLAME_WIDTH_NEAR :: f32(0.4)
FLAME_WIDTH_FAR :: f32(1.2)
FLAME_STEP :: f32(1.0/120.0)
// The pieces in flight: as many as its length takes in steps.
FLAME_PIECES :: 24
// The foes it remembers at once.
FLAME_MEMORY :: 8
FLAME_TIP_SECONDS :: f32(1)
FLAME_FIRE_SECONDS :: f32(1)
// World seconds a frame's command catches up at most.
FLAME_MAX_PENDING :: f32(0.25)
FLAME_VISUAL_GROUP :: u32(0x4B_5013)

Flame_Piece :: struct {
	// Where it left (board cells) and the way it goes.
	x, y, way: f32,
	alive: bool,
}

Flame_Memory :: struct {
	enemy_id: u32,
	wait: f32,
}

First_Person_Flame :: struct {
	// The way the nozzle points, and the left button as the last frame held it.
	yaw: f32,
	firing: bool,
	// World seconds not yet run (tactical_first_person_tick).
	pending: f32,
	// A ring: `head` the piece that left last, each next one a step older.
	pieces: [FLAME_PIECES]Flame_Piece,
	head: i32,
	memory: [FLAME_MEMORY]Flame_Memory,
	// The cell the tip stands on, for how long, and the seconds before another fire.
	tip: grid.Position,
	tip_seconds, fire_wait: f32,
	// Counted for the board and the tests.
	hits, fires, barrels: i32,
}

// What the controller asks of it this frame: the left button held, the board's point under the mouse.
First_Person_Flame_Input :: struct {
	fire, aimed: bool,
	aim: [2]f32,
}

first_person_flame_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Flamethrower
}

// Whether the view open keeps the camera on the board (the weapon's rules).
first_person_on_board :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && FIRST_PERSON_WEAPONS[room.first_person.weapon].on_board
}

@(private)
first_person_flame_begin :: proc(room: ^Room) {
	room.first_person.flame = {yaw = first_person_yaw(room.player.tactical.facing)}
}

// The world's seconds (tactical_first_person_tick): run by the frame's command.
@(private)
first_person_flame_tick :: proc(f: ^First_Person_Flame, seconds: f32) {
	f.pending = min(f.pending+seconds, FLAME_MAX_PENDING)
}

// A piece's distance from the nozzle, `age` steps old.
flame_piece_distance :: proc(age: int) -> f32 { return f32(age)*FLAME_SPEED*FLAME_STEP }

// The flame's width `distance` cells from the nozzle.
flame_width :: proc(distance: f32) -> f32 {
	return FLAME_WIDTH_NEAR+(FLAME_WIDTH_FAR-FLAME_WIDTH_NEAR)*clamp(distance/FLAME_LENGTH, 0, 1)
}

// The piece `age` steps old.
flame_piece_at :: proc(f: ^First_Person_Flame, age: int) -> ^Flame_Piece {
	return &f.pieces[(int(f.head)-age+FLAME_PIECES*2)%FLAME_PIECES]
}

// Where the piece stands `distance` from where it left.
flame_piece_point :: proc(piece: Flame_Piece, distance: f32) -> [2]f32 {
	return {piece.x+math.cos(piece.way)*distance, piece.y+math.sin(piece.way)*distance}
}

// Walls and covers stop it; a low wall does not.
@(private = "file")
flame_is_stopped :: proc(room: ^Room, cell: grid.Position) -> bool {
	if !level.layer_contains(room.level_data, cell) || obstacle_at(room, cell) { return true }
	tile, found := level.tile_at(room.level_data, cell)
	if !found { return true }
	return !level.is_walkable(tile.kind) && tile.kind != .Fence
}

// A foe touched, unless the flame touched him within his 2 seconds. Whether it struck.
@(private = "file")
flame_touch_foe :: proc(room: ^Room, f: ^First_Person_Flame, enemy: Enemy) -> bool {
	slot := -1
	for memory, index in f.memory {
		if memory.enemy_id == enemy.id { if memory.wait > 0 { return false }; slot = index; break }
		if slot < 0 && memory.wait <= 0 { slot = index }
	}
	if slot < 0 { return false }
	f.memory[slot] = {enemy_id = enemy.id, wait = FLAME_WAIT_SECONDS}
	target := enemy_entity(enemy.id)
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
	action.visual_group = FLAME_VISUAL_GROUP
	if !add_effect(&action, damage_effect(target, FLAME_DAMAGE)) { return false }
	if !add_effect(&action, apply_status_effect(target, .Burn, FLAME_BURN, 0)) { return false }
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	append_event_log(room.recent_events, &report.events)
	f.hits += 1
	room.first_person.hits += 1
	collect_loot_in_magnet_range(room)
	return true
}

// The object on `cell`: a barrel goes off, ice melts. Whether it stops the piece.
@(private = "file")
flame_touch_object :: proc(room: ^Room, f: ^First_Person_Flame, cell: grid.Position) -> (stopped, acted: bool) {
	object, found := grid_object_at(room, cell)
	if !found { return }
	definition, known := grid_object_definition(object.kind)
	if !known || !definition.blocks_movement { return }
	stopped = true
	if definition.explosive {
		if object.detonation_pulse == 0 { acted = arm_explosive(room, object.id, PLAYER_ENTITY, room.recent_events) }
		if acted { f.barrels += 1 }
		return
	}
	if object.kind == .Ice_Block {
		ref := object_entity(object.id)
		action := make_action(.Attack, PLAYER_ENTITY, entity_target(ref), .Opponent_Or_Object)
		action.visual_group = FLAME_VISUAL_GROUP
		if add_effect(&action, damage_effect(ref, max(object.health, definition.max_health))) {
			report := resolve_action(room, &action)
			if report.accepted { append_event_log(room.recent_events, &report.events); acted = true }
		}
	}
	return
}

// How near the piece at `point`, `radius` wide, comes to a foe's cell.
@(private = "file")
flame_reaches_cell :: proc(point: [2]f32, radius: f32, cell: grid.Position) -> bool {
	dx := point.x-clamp(point.x, f32(cell.x), f32(cell.x)+1)
	dy := point.y-clamp(point.y, f32(cell.y), f32(cell.y)+1)
	return dx*dx+dy*dy <= radius*radius
}

// One step of the rules: the nozzle turns, a piece leaves, those out run on and touch. Whether anything happened.
@(private = "file")
flame_step :: proc(room: ^Room, f: ^First_Person_Flame, input: First_Person_Flame_Input) -> (acted: bool) {
	p := room.player.position
	nozzle := [2]f32{f32(p.x)+0.5, f32(p.y)+0.5}
	if input.aimed && (input.aim.x != nozzle.x || input.aim.y != nozzle.y) {
		wish := math.atan2(input.aim.y-nozzle.y, input.aim.x-nozzle.x)
		turn := first_person_wrap_turn(wish-f.yaw)
		reach := FLAME_TURN_RADIANS*FLAME_STEP
		f.yaw = f.yaw+clamp(turn, -reach, reach)
	}
	for &memory in f.memory { memory.wait = max(0, memory.wait-FLAME_STEP) }
	f.fire_wait = max(0, f.fire_wait-FLAME_STEP)
	f.head = (f.head+1)%FLAME_PIECES
	f.pieces[f.head] = {x = nozzle.x, y = nozzle.y, way = f.yaw, alive = input.fire}

	tip_age := -1
	tip_cell := grid.Position{}
	for age in 0..<FLAME_PIECES {
		piece := flame_piece_at(f, age)
		if !piece.alive { continue }
		distance := flame_piece_distance(age)
		point := flame_piece_point(piece^, distance)
		cell := grid.Position{x = int(math.floor(point.x)), y = int(math.floor(point.y)), layer = p.layer}
		if flame_is_stopped(room, cell) { piece.alive = false; continue }
		stopped, touched := flame_touch_object(room, f, cell)
		if touched { acted = true }
		if stopped { piece.alive = false; continue }
		radius := flame_width(distance)/2
		for index := len(room.enemies)-1; index >= 0; index -= 1 {
			enemy := room.enemies[index]
			if enemy_is_out_of_play(room, enemy.id) || enemy.position.layer != p.layer || !flame_reaches_cell(point, radius, enemy.position) { continue }
			if flame_touch_foe(room, f, enemy) { acted = true }
			if room.phase != .Combat { return }
		}
		if age > tip_age { tip_age, tip_cell = age, cell }
	}

	// The tip on one cell a second: a fire, one new a second at most.
	if tip_age < 0 { f.tip_seconds = 0; return }
	if tip_cell != f.tip { f.tip, f.tip_seconds = tip_cell, 0 }
	f.tip_seconds += FLAME_STEP
	if f.tip_seconds >= FLAME_TIP_SECONDS && f.fire_wait <= 0 {
		report: Action_Report
		if place_ground(room, .Burn, tip_cell, 1, &report) {
			append_event_log(room.recent_events, &report.events)
			f.fires += 1
			f.fire_wait = FLAME_FIRE_SECONDS
			f.tip_seconds = 0
			acted = true
		}
	}
	return
}

// The way to turn from one yaw to another, the short way round.
first_person_wrap_turn :: proc(turn: f32) -> f32 {
	wrapped := math.mod(turn+math.PI, 2*math.PI)
	if wrapped < 0 { wrapped += 2*math.PI }
	return wrapped-math.PI
}

// The flame this frame: the world's seconds since the last, in steps. Their events are the room's recent ones.
first_person_flame_move :: proc(room: ^Room, input: First_Person_Flame_Input) -> (result: Action_Result) {
	if !first_person_flame_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	f := &room.first_person.flame
	f.firing = input.fire
	acted := false
	for f.pending >= FLAME_STEP {
		f.pending -= FLAME_STEP
		if flame_step(room, f, input) { acted = true }
		if room.phase != .Combat { break }
	}
	room.player.tactical.facing = first_person_key_directions(f.yaw)[0]
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
		return .Combat_Ended
	}
	return .Moved if acted else .None
}
