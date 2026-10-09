package game

// Profile contains only durable, bounded progression. Ring simulation and room
// state never enter the save, so returning from a challenge cannot rewind combat.
M8_Profile :: struct { ring_wins: u32 }
M8_PROFILE_VERSION :: 1
M8_MAX_RING_WINS :: u32(1_000_000)
RING_PLAYER_MAX_HEALTH :: i32(6)
RING_ENEMY_MAX_HEALTH :: i32(9)
RING_GRAB_DURATION :: f32(1.2)
RING_GRAB_POSE_COUNT :: 4

Ring_Phase :: enum { Active, Won, Lost }
Ring_Action :: enum { Idle, Jab, Dodge, Grab_Throw, Hurt }
Ring_Command :: enum { Left, Right, Jab, Dodge, Grab }
Ring_Challenge :: struct {
	phase: Ring_Phase,
	player_health, enemy_health: i32,
	player_x, enemy_x: f32,
	action: Ring_Action,
	action_time: f32,
	enemy_windup, enemy_recovery: f32,
	successful_throws: i32,
	throw_landed: bool,
	settled: bool,
}
Ring_Reward :: struct {
	settled, won, has_unlock, card_added: bool,
	unlocked: Card_Id,
}

m8_profile_valid :: proc(profile: M8_Profile) -> bool {
	return profile.ring_wins <= M8_MAX_RING_WINS
}

m8_card_unlocked :: proc(id: Card_Id, profile: ^M8_Profile = nil) -> bool {
	wins := u32(0)
	if profile != nil && m8_profile_valid(profile^) { wins = profile.ring_wins }
	if id == .Titan_Grip { return wins >= 1 }
	if id == .Storm_Crown { return wins >= 3 }
	return true
}

begin_ring_challenge :: proc(room: ^Room) -> (Ring_Challenge, bool) {
	if room == nil || room.player == nil || room.phase != .Loot || room.ring_challenge_attempted { return {}, false }
	room.ring_challenge_attempted = true
	return {
		phase = .Active, player_health = RING_PLAYER_MAX_HEALTH, enemy_health = RING_ENEMY_MAX_HEALTH,
		player_x = 0.32, enemy_x = 0.68, enemy_windup = 1.8,
	}, true
}

ring_grab_pose :: proc(ring: ^Ring_Challenge) -> int {
	if ring == nil || ring.action != .Grab_Throw { return 0 }
	return clamp(int(ring.action_time/(RING_GRAB_DURATION/f32(RING_GRAB_POSE_COUNT))), 0, RING_GRAB_POSE_COUNT-1)
}

ring_enemy_vulnerable :: proc(ring: ^Ring_Challenge) -> bool {
	return ring != nil && ring.phase == .Active && ring.enemy_recovery > 0
}

ring_command :: proc(ring: ^Ring_Challenge, command: Ring_Command) -> bool {
	if ring == nil || ring.phase != .Active || ring.action != .Idle { return false }
	distance := abs(ring.player_x-ring.enemy_x)
	switch command {
	case .Left: ring.player_x = max(f32(0.08), ring.player_x-0.08)
	case .Right: ring.player_x = min(f32(0.92), ring.player_x+0.08)
	case .Jab:
		if distance > 0.24 { return false }
		ring.action = .Jab
		ring.enemy_health = max(i32(0), ring.enemy_health-1)
	case .Dodge:
		ring.action = .Dodge
		side: f32 = -1 if ring.player_x <= ring.enemy_x else 1
		ring.player_x = clamp(ring.player_x+side*0.12, 0.08, 0.92)
	case .Grab:
		if distance > 0.25 || !ring_enemy_vulnerable(ring) { return false }
		ring.action = .Grab_Throw
		ring.throw_landed = false
	}
	ring.action_time = 0
	if ring.enemy_health == 0 { ring.phase = .Won }
	return true
}

ring_tick_step :: proc(ring: ^Ring_Challenge, dt: f32) {
	if ring.action != .Idle {
		ring.action_time += dt
		if ring.action == .Grab_Throw {
			// Four held poses, with impact on the last one. Enemy rhythm remains
			// stopped for this animation, independently of the main game clocks.
			if !ring.throw_landed && ring_grab_pose(ring) == 3 {
				ring.throw_landed = true
				ring.successful_throws += 1
				ring.enemy_health = max(i32(0), ring.enemy_health-3)
				side: f32 = 1 if ring.player_x <= ring.enemy_x else -1
				ring.enemy_x = clamp(ring.player_x+side*0.3, 0.08, 0.92)
			}
			if ring.action_time >= RING_GRAB_DURATION {
				ring.action = .Idle
				ring.action_time = 0
				ring.enemy_recovery = 0.7
				if ring.enemy_health == 0 { ring.phase = .Won }
			}
			return
		}
		duration: f32 = 0.28
		if ring.action == .Dodge { duration = 0.5 }
		if ring.action == .Hurt { duration = 0.35 }
		if ring.action_time >= duration { ring.action = .Idle; ring.action_time = 0 }
	}
	if ring.enemy_recovery > 0 {
		ring.enemy_recovery = max(f32(0), ring.enemy_recovery-dt)
		if ring.enemy_recovery == 0 { ring.enemy_windup = 1.2 }
		return
	}
	if ring.enemy_windup > 0.45 && abs(ring.player_x-ring.enemy_x) > 0.18 {
		direction: f32 = 1 if ring.player_x > ring.enemy_x else -1
		ring.enemy_x += direction*0.2*dt
	}
	ring.enemy_windup = max(f32(0), ring.enemy_windup-dt)
	if ring.enemy_windup == 0 {
		if abs(ring.player_x-ring.enemy_x) <= 0.26 && ring.action != .Dodge {
			ring.player_health = max(i32(0), ring.player_health-2)
			ring.action = .Hurt
			ring.action_time = 0
			if ring.player_health == 0 { ring.phase = .Lost }
		}
		ring.enemy_recovery = 1.0
	}
}

// Bounded substeps preserve telegraphs and the four held poses at low frame
// rates. Focus loss is paused by the caller, as with all other modal gameplay.
tick_ring :: proc(ring: ^Ring_Challenge, dt: f32) {
	if ring == nil || ring.phase != .Active || !(dt > 0 && dt < max(f32)) { return }
	remaining := min(dt, f32(30))
	for remaining > 0 && ring.phase == .Active {
		step := min(remaining, f32(1.0/120.0))
		ring_tick_step(ring, step)
		remaining -= step
	}
}

settle_ring_challenge :: proc(room: ^Room, ring: ^Ring_Challenge) -> (result: Ring_Reward) {
	if room == nil || room.player == nil || room.phase != .Loot || ring == nil ||
	   ring.phase == .Active || ring.settled || !m8_profile_valid(room.player.m8_profile) { return }
	ring.settled = true
	result.settled = true
	result.won = ring.phase == .Won
	if !result.won { return }
	profile := &room.player.m8_profile
	profile.ring_wins = min(profile.ring_wins+1, M8_MAX_RING_WINS)
	if profile.ring_wins == 1 { result.has_unlock = true; result.unlocked = .Titan_Grip }
	if profile.ring_wins == 3 { result.has_unlock = true; result.unlocked = .Storm_Crown }
	if result.has_unlock {
		_, result.card_added = add_owned_card(&room.player.deck, result.unlocked)
	}
	return
}
