package game

// Minigame challenges: after a combat room is cleared the player may take one
// minigame (platform, arena, FPS, puzzle...) for extra gold. The run never
// sees the minigame itself, only its outcome, so any game mode can plug in
// without touching combat state or the run's random streams.
MINIGAME_CHALLENGE_SALT :: u64(0x51F1DA)

// Gold by stars earned on a win; a loss or an abandoned attempt pays nothing.
MINIGAME_CHALLENGE_GOLD :: [4]i32{4, 8, 12, 18}

Minigame_Challenge_Outcome :: enum u8 {
	Won,
	Lost,
	Abandoned,
}

Minigame_Challenge :: struct {
	seed:       u64,
	difficulty: int, // 0..2, grows with depth
	// Index into the host's minigame catalog, chosen from the seed.
	minigame:   int,
}

minigame_challenge_available :: proc(run: ^Run_State, room: ^Room) -> bool {
	if run == nil || room == nil || room.player == nil {
		return false
	}
	if run.phase != .In_Room || room.phase != .Loot || room.minigame_challenge_attempted {
		return false
	}
	node, ok := current_run_node(run)
	return ok && (node.kind == .Combat || node.kind == .Elite)
}

// Locks the room's single attempt and picks the minigame deterministically
// from the node, so the same seed and route always offer the same challenge.
begin_minigame_challenge :: proc(run: ^Run_State, room: ^Room, catalog_size: int) -> (Minigame_Challenge, bool) {
	if catalog_size <= 0 || !minigame_challenge_available(run, room) {
		return {}, false
	}
	node, _ := current_run_node(run)
	room.minigame_challenge_attempted = true
	seed := mix_room_seed(node.room_seed ~ MINIGAME_CHALLENGE_SALT)
	return Minigame_Challenge{
		seed       = seed,
		difficulty = minigame_challenge_difficulty(node.depth, node.kind),
		minigame   = int(seed % u64(catalog_size)),
	}, true
}

minigame_challenge_difficulty :: proc(depth: int, kind: Node_Kind) -> int {
	d := 0 if depth <= 2 else (1 if depth <= 4 else 2)
	if kind == .Elite {
		d = min(d+1, 2)
	}
	return d
}

minigame_challenge_gold :: proc(outcome: Minigame_Challenge_Outcome, stars: u8) -> i32 {
	if outcome != .Won {
		return 0
	}
	table := MINIGAME_CHALLENGE_GOLD
	return table[min(int(stars), 3)]
}

// Applies the reward; returns the gold granted.
settle_minigame_challenge :: proc(run: ^Run_State, outcome: Minigame_Challenge_Outcome, stars: u8) -> i32 {
	if run == nil {
		return 0
	}
	gold := minigame_challenge_gold(outcome, stars)
	run.player.gold += gold
	return gold
}
