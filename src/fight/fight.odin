package fight

import "core:math"
import engine "../engine"

// Ring simulation is intentionally independent from the tactical board and
// rendering. Call tick once for each fixed 1/60 s simulation step.
Action :: enum { Idle, Jab, Heavy, Guard, Dodge, Grab, Hurt, Thrown }
Result :: enum { Active, Won, Lost }
Action_Mask :: bit_set[Action]
Move_Def :: struct {
	startup, active, recovery: int,
	damage: i32,
	reach, radius, knockback: f32,
	stun, hitstop: int,
	cancel_from, cancel_until: int,
	cancels: Action_Mask,
}
Input :: struct {
	move: engine.Vec3,
	jab, heavy, dodge, grab, guard: bool,
}
Fighter :: struct {
	position, previous, facing: engine.Vec3,
	health, max_health: i32,
	action: Action,
	action_tick: int,
	active_move: Move_Def,
	move_serial: u32,
	has_hit: bool,
	hurt_remaining: int,
	dodge_direction, knockback: engine.Vec3,
	buffered_action: Action,
	buffer_ticks: int,
}
// Spherical attack and hurt volumes are distinct from locomotion bodies. The
// debug renderer can draw these without knowing any fighting-game rules.
Box :: struct { center: engine.Vec3, radius: f32 }
State :: struct {
	world: engine.World,
	fighters: [2]Fighter,
	moves: [Action]Move_Def,
	result: Result,
	ticks, combat_ticks: u64,
	hitstop_ticks: int,
	successful_throws: int,
	practice, dummy: bool,
	ai_wait, ai_attack_count: int,
	throw_active: bool,
	throw_tick, throw_attacker, throw_victim: int,
	throw_start, throw_landing: engine.Vec3,
	throw_landed: bool,
	last_hit_position: engine.Vec3,
	hit_flash_ticks: int,
	last_hit_blocked: bool,
	landed_hits, blocked_hits: [2]int,
}

BODY_RADIUS :: f32(0.36)
BODY_HEIGHT :: f32(1.6)
HURT_RADIUS :: f32(0.39)
RING_EXTENT :: f32(4.5)
PLAYER_SPEED :: f32(3.5)
ENEMY_SPEED :: f32(2.25)
THROW_POSE_TICKS :: 18
THROW_DURATION_TICKS :: THROW_POSE_TICKS*4
FIXED_DT :: f32(1.0/60.0)

default_moves :: proc() -> (moves: [Action]Move_Def) {
	moves[.Jab] = {startup = 8, active = 4, recovery = 16, damage = 1,
		reach = 0.63, radius = 0.39, knockback = 0.20, stun = 15, hitstop = 5,
		cancel_from = 12, cancel_until = 20, cancels = {.Heavy, .Dodge}}
	moves[.Heavy] = {startup = 22, active = 5, recovery = 28, damage = 2,
		reach = 0.83, radius = 0.45, knockback = 0.72, stun = 25, hitstop = 8,
		cancel_from = -1, cancel_until = -1}
	moves[.Dodge] = {startup = 3, active = 12, recovery = 11,
		reach = 0.1, radius = 0.1, stun = 1, cancel_from = -1, cancel_until = -1}
	moves[.Grab] = {startup = 10, active = 3, recovery = 25, damage = 3,
		reach = 0.52, radius = 0.33, knockback = 2.7, stun = 35, hitstop = 9,
		cancel_from = -1, cancel_until = -1}
	return
}

move_valid :: proc(move: Move_Def) -> bool {
	if move.startup < 0 || move.startup > 120 || move.active < 1 || move.active > 120 ||
	   move.recovery < 1 || move.recovery > 180 || move.damage < 0 || move.damage > 20 ||
	   !(move.reach >= 0 && move.reach <= 3) || !(move.radius > 0 && move.radius <= 2) ||
	   !(move.knockback >= 0 && move.knockback <= 6) || move.stun < 1 || move.stun > 180 ||
	   move.hitstop < 0 || move.hitstop > 30 { return false }
	if move.cancel_from == -1 && move.cancel_until == -1 { return card(move.cancels) == 0 }
	return move.cancel_from >= move.startup+move.active &&
	       move.cancel_until >= move.cancel_from &&
	       move.cancel_until < move.startup+move.active+move.recovery &&
	       move.cancels <= Action_Mask{.Jab, .Heavy, .Dodge, .Grab}
}

set_move :: proc(state: ^State, action: Action, move: Move_Def) -> bool {
	if state == nil || !is_move(action) || !move_valid(move) { return false }
	state.moves[action] = move
	return true
}

is_move :: proc(action: Action) -> bool { return action == .Jab || action == .Heavy || action == .Dodge || action == .Grab }

begin :: proc(practice := false, dummy := false) -> State {
	state := State{moves = default_moves(), practice = practice, dummy = dummy, ai_wait = 50}
	state.fighters[0] = {position = {-1.3, 0, 0}, previous = {-1.3, 0, 0}, facing = {1, 0, 0}, health = 8, max_health = 8}
	state.fighters[1] = {position = {1.3, 0, 0}, previous = {1.3, 0, 0}, facing = {-1, 0, 0}, health = 12, max_health = 12}
	init_world(&state)
	return state
}

reset :: proc(state: ^State) {
	if state == nil { return }
	moves := state.moves
	state^ = begin(state.practice, state.dummy)
	for action in Action {
		if is_move(action) && move_valid(moves[action]) { state.moves[action] = moves[action] }
	}
}

planar_direction :: proc(vector: engine.Vec3) -> engine.Vec3 {
	if !(abs(vector.x) < max(f32) && abs(vector.z) < max(f32)) { return {} }
	length := math.sqrt(vector.x*vector.x+vector.z*vector.z)
	if !(length > 0.00001 && length < max(f32)) { return {} }
	return {vector.x/length, 0, vector.z/length}
}

distance_squared :: proc(a, b: engine.Vec3) -> f32 {
	return (a.x-b.x)*(a.x-b.x)+(a.z-b.z)*(a.z-b.z)
}

facing_opponent :: proc(state: ^State, index: int) {
	fighter := &state.fighters[index]
	opponent := state.fighters[1-index].position
	direction := planar_direction({opponent.x-fighter.position.x, 0, opponent.z-fighter.position.z})
	if direction.x != 0 || direction.z != 0 { fighter.facing = direction }
}

requested_action :: proc(input: Input) -> Action {
	if input.dodge { return .Dodge }
	if input.grab { return .Grab }
	if input.heavy { return .Heavy }
	if input.jab { return .Jab }
	return .Idle
}

can_start :: proc(fighter: ^Fighter, action: Action) -> bool {
	if !is_move(action) { return false }
	if fighter.action == .Idle || fighter.action == .Guard { return true }
	return fighter.has_hit && fighter.action_tick >= fighter.active_move.cancel_from &&
	       fighter.action_tick <= fighter.active_move.cancel_until && action in fighter.active_move.cancels
}

start_action :: proc(state: ^State, index: int, action: Action, movement: engine.Vec3) -> bool {
	fighter := &state.fighters[index]
	if !can_start(fighter, action) || !move_valid(state.moves[action]) { return false }
	facing_opponent(state, index)
	fighter.action, fighter.action_tick, fighter.has_hit = action, 0, false
	fighter.active_move = state.moves[action]
	// Instant moves still receive their first active sample; otherwise a
	// zero-startup, one-frame strike would be skipped by the tick increment.
	if fighter.active_move.startup == 0 { fighter.action_tick = -1 }
	fighter.move_serial += 1
	fighter.buffer_ticks = 0
	fighter.buffered_action = .Idle
	if action == .Dodge {
		fighter.dodge_direction = planar_direction(movement)
		if fighter.dodge_direction.x == 0 && fighter.dodge_direction.z == 0 {
			fighter.dodge_direction = {-fighter.facing.x, 0, -fighter.facing.z}
		}
	}
	return true
}

invulnerable :: proc(fighter: ^Fighter) -> bool {
	return fighter.action == .Dodge && fighter.action_tick >= fighter.active_move.startup &&
	       fighter.action_tick < fighter.active_move.startup+fighter.active_move.active
}

hurtbox :: proc(state: ^State, index: int) -> Box {
	if state == nil || index < 0 || index >= len(state.fighters) { return {} }
	position := state.fighters[index].position
	return {{position.x, position.y+0.8, position.z}, HURT_RADIUS}
}

hitbox :: proc(state: ^State, index: int) -> (Box, bool) {
	if state == nil || index < 0 || index >= len(state.fighters) || state.throw_active { return {}, false }
	fighter := &state.fighters[index]
	if !is_move(fighter.action) || fighter.action == .Dodge || fighter.action_tick < fighter.active_move.startup ||
	   fighter.action_tick >= fighter.active_move.startup+fighter.active_move.active { return {}, false }
	return {{fighter.position.x+fighter.facing.x*fighter.active_move.reach, fighter.position.y+0.8,
		fighter.position.z+fighter.facing.z*fighter.active_move.reach}, fighter.active_move.radius}, true
}

guard_blocks :: proc(victim: ^Fighter, attacker: ^Fighter) -> bool {
	if victim.action != .Guard { return false }
	direction := planar_direction({attacker.position.x-victim.position.x, 0, attacker.position.z-victim.position.z})
	return victim.facing.x*direction.x+victim.facing.z*direction.z >= 0.25
}

check_result :: proc(state: ^State) {
	if state.practice {
		for &fighter in state.fighters { if fighter.health <= 0 { fighter.health = fighter.max_health } }
		return
	}
	if state.fighters[0].health <= 0 { state.result = .Lost }
	else if state.fighters[1].health <= 0 { state.result = .Won }
}

impact :: proc(state: ^State, attacker_index: int, move: Move_Def, blocked: bool) {
	attacker := &state.fighters[attacker_index]
	victim := &state.fighters[1-attacker_index]
	damage := move.damage
	if blocked { damage = 0 }
	victim.health = max(i32(0), victim.health-damage)
	victim.action, victim.action_tick = .Hurt, 0
	victim.hurt_remaining = 8 if blocked else move.stun
	victim.buffer_ticks = 0
	victim.buffered_action = .Idle
	force := move.knockback*(0.25 if blocked else 1)
	victim.knockback = {attacker.facing.x*force, 0, attacker.facing.z*force}
	attacker.has_hit = true
	state.hitstop_ticks = max(state.hitstop_ticks, move.hitstop)
	state.last_hit_position = hurtbox(state, 1-attacker_index).center
	state.last_hit_blocked = blocked
	state.hit_flash_ticks = 12
	if blocked { state.blocked_hits[attacker_index] += 1 }
	else { state.landed_hits[attacker_index] += 1 }
	if !state.throw_active { check_result(state) }
}

throw_pose :: proc(state: ^State) -> int {
	if state == nil || !state.throw_active { return 0 }
	return clamp(state.throw_tick/THROW_POSE_TICKS, 0, 3)
}

begin_throw :: proc(state: ^State, attacker_index: int) {
	attacker := &state.fighters[attacker_index]
	victim_index := 1-attacker_index
	victim := &state.fighters[victim_index]
	state.throw_active = true
	state.throw_tick = 0
	state.throw_attacker, state.throw_victim = attacker_index, victim_index
	state.throw_landed = false
	state.throw_start = victim.position
	state.throw_landing = sweep_position(state, victim_index,
		{attacker.facing.x*attacker.active_move.knockback, 0, attacker.facing.z*attacker.active_move.knockback})
	attacker.has_hit = true
	victim.action, victim.action_tick = .Thrown, 0
	victim.buffer_ticks = 0
	victim.knockback = {}
}

tick_throw :: proc(state: ^State) {
	state.throw_tick += 1
	attacker := &state.fighters[state.throw_attacker]
	victim := &state.fighters[state.throw_victim]
	pose := throw_pose(state)
	if pose < 2 {
		victim.position = state.throw_start
		victim.position.y = 0.75 if pose == 1 else 0
	} else if pose == 2 {
		progress := f32(state.throw_tick-2*THROW_POSE_TICKS)/f32(THROW_POSE_TICKS)
		victim.position = {
			state.throw_start.x+(state.throw_landing.x-state.throw_start.x)*progress,
			0.75*(1-progress)+math.sin(progress*math.PI)*0.8,
			state.throw_start.z+(state.throw_landing.z-state.throw_start.z)*progress,
		}
	} else {
		victim.position = state.throw_landing
		if !state.throw_landed {
			state.throw_landed = true
			state.successful_throws += 1
			impact(state, state.throw_attacker, attacker.active_move, false)
			victim.action = .Thrown
			victim.knockback = {}
		}
	}
	if state.throw_tick >= THROW_DURATION_TICKS {
		state.throw_active = false
		attacker.action, attacker.action_tick = .Idle, 0
		victim.action, victim.action_tick = .Hurt, 0
		victim.hurt_remaining = 24
		victim.position = state.throw_landing
		state.ai_wait = 36
		check_result(state)
	}
	sync_fighters(state)
}

test_attack :: proc(state: ^State, index: int) {
	fighter := &state.fighters[index]
	if fighter.has_hit { return }
	attack, active := hitbox(state, index)
	if !active { return }
	victim := &state.fighters[1-index]
	if invulnerable(victim) { return }
	hurt := hurtbox(state, 1-index)
	radius := attack.radius+hurt.radius
	if distance_squared(attack.center, hurt.center) > radius*radius { return }
	// A generous/tuned hit sphere cannot reach through scenery. The strike or
	// grab needs an unobstructed line between the two characters' hurt centers.
	origin := hurtbox(state, index).center
	direction := engine.vec_sub(hurt.center, origin)
	if engine.raycast(&state.world, origin, direction, engine.vec_length(direction), {.World}).hit { return }
	if fighter.action == .Grab { begin_throw(state, index); return }
	impact(state, index, fighter.active_move, guard_blocks(victim, fighter))
}

tick_fighter :: proc(state: ^State, index: int, input: Input) {
	fighter := &state.fighters[index]
	if fighter.action == .Hurt {
		// A bounded fraction of the remaining impulse is swept every tick.
		delta := engine.Vec3{fighter.knockback.x*0.3, 0, fighter.knockback.z*0.3}
		move_fighter(state, index, delta)
		fighter.knockback.x *= 0.7
		fighter.knockback.z *= 0.7
		fighter.hurt_remaining -= 1
		fighter.action_tick += 1
		if fighter.hurt_remaining <= 0 { fighter.action, fighter.action_tick = .Idle, 0 }
		return
	}
	if fighter.action == .Thrown { return }
	requested := requested_action(input)
	if requested != .Idle { fighter.buffered_action, fighter.buffer_ticks = requested, 8 }
	if fighter.buffer_ticks > 0 {
		if !start_action(state, index, fighter.buffered_action, input.move) { fighter.buffer_ticks -= 1 }
	}
	if fighter.action == .Guard && !input.guard { fighter.action = .Idle }
	if fighter.action == .Idle {
		facing_opponent(state, index)
		if input.guard { fighter.action, fighter.action_tick = .Guard, 0 }
	}
	if fighter.action == .Idle || fighter.action == .Guard {
		speed := PLAYER_SPEED if index == 0 else ENEMY_SPEED
		if fighter.action == .Guard { speed *= 0.35 }
		direction := planar_direction(input.move)
		move_fighter(state, index, {direction.x*speed*FIXED_DT, 0, direction.z*speed*FIXED_DT})
		return
	}
	if is_move(fighter.action) {
		fighter.action_tick += 1
		if fighter.action == .Dodge && fighter.action_tick < fighter.active_move.startup+fighter.active_move.active {
			move_fighter(state, index, {fighter.dodge_direction.x*6.8*FIXED_DT, 0, fighter.dodge_direction.z*6.8*FIXED_DT})
		}
		if fighter.action_tick >= fighter.active_move.startup+fighter.active_move.active+fighter.active_move.recovery {
			fighter.action, fighter.action_tick = .Idle, 0
		}
	}
}

enemy_input :: proc(state: ^State) -> Input {
	if state.dummy { return {} }
	enemy := &state.fighters[1]
	if enemy.action != .Idle { return {} }
	player := state.fighters[0]
	distance := distance_squared(player.position, enemy.position)
	if state.ai_wait > 0 { state.ai_wait -= 1 }
	if distance > 1.08*1.08 {
		return {move = {player.position.x-enemy.position.x, 0, player.position.z-enemy.position.z}}
	}
	if state.ai_wait > 0 { return {} }
	state.ai_attack_count += 1
	state.ai_wait = 42
	// The slow heavy gives a clear opening; every third strike is a quicker jab.
	return {heavy = state.ai_attack_count%3 != 0, jab = state.ai_attack_count%3 == 0}
}

tick :: proc(state: ^State, input: Input) {
	if state == nil || state.result != .Active { return }
	state.ticks += 1
	sync_fighters(state)
	for &fighter in state.fighters { fighter.previous = fighter.position }
	if state.hit_flash_ticks > 0 { state.hit_flash_ticks -= 1 }
	if state.hitstop_ticks > 0 {
		state.hitstop_ticks -= 1
		// Preserve one deliberate press through a short impact pause.
		action := requested_action(input)
		if action != .Idle && !state.throw_active { state.fighters[0].buffered_action, state.fighters[0].buffer_ticks = action, 8 }
		return
	}
	state.combat_ticks += 1
	if state.throw_active { tick_throw(state); return }
	ai := enemy_input(state)
	tick_fighter(state, 0, input)
	tick_fighter(state, 1, ai)
	test_attack(state, 0)
	if !state.throw_active && state.result == .Active { test_attack(state, 1) }
}
