package game

// Profile contains only durable, bounded progression. Ring simulation and room
// state never enter the save, so returning from a challenge cannot rewind combat.
M8_Profile :: struct { ring_wins: u32 }
M8_PROFILE_VERSION :: 1
M8_MAX_RING_WINS :: u32(1_000_000)
// Only a progression receipt: all live combat is owned by package fight.
Ring_Phase :: enum { Active, Won, Lost }
Ring_Challenge :: struct { phase: Ring_Phase, settled: bool }
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
	return {phase=.Active}, true
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
