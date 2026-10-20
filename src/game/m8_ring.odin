package game

// Profile contains only durable, bounded progression. Ring simulation and room
// state never enter the save, so returning from a challenge cannot rewind combat.
M8_Profile :: struct { ring_wins: u32 }
M8_PROFILE_VERSION :: 1
M8_MAX_RING_WINS :: u32(1_000_000)
// Only a progression receipt: all live combat is owned by package fight.
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

// Every ring won counts toward the durable card unlocks.
@(private)
record_ring_win :: proc(room: ^Room) -> (result: Ring_Reward) {
	if room == nil || room.player == nil || !m8_profile_valid(room.player.m8_profile) { return }
	result.settled, result.won = true, true
	profile := &room.player.m8_profile
	profile.ring_wins = min(profile.ring_wins+1, M8_MAX_RING_WINS)
	if profile.ring_wins == 1 { result.has_unlock = true; result.unlocked = .Titan_Grip }
	if profile.ring_wins == 3 { result.has_unlock = true; result.unlocked = .Storm_Crown }
	if result.has_unlock {
		_, result.card_added = add_owned_card(&room.player.deck, result.unlocked)
	}
	return
}
