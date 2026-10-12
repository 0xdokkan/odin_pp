package game

// Easter eggs open once per floor. A floor is the whole run until floors
// exist; begin_floor clears them for the next one.
Floor_Secret :: enum u8 {
	// Four coils in a square around enemies (tesla_ring.odin).
	Tesla_Ring,
	// The 6 and the 7 of coins together in hand: 6 RANCH 7.
	Western_Ranch,
}

begin_floor :: proc(player: ^Player) {
	if player != nil { player.floor_secrets = {} }
}

// Winning the ranch duel refills health and pays this much gold.
WESTERN_RANCH_GOLD :: i32(10)

Western_Ranch_Reward :: struct {
	won: bool,
	healed, gold: i32,
}

// Hand slots of the Scopa pair, when both are held.
western_ranch_hand :: proc(room: ^Room) -> (six, seven: int, ok: bool) {
	if room == nil || room.player == nil { return -1, -1, false }
	six, seven = -1, -1
	deck := &room.player.deck
	for index in 0..<deck.hand_count {
		#partial switch deck.hand[index].definition_id {
		case .Sei_Denari: if six < 0 { six = index }
		case .Sette_Denari: if seven < 0 { seven = index }
		}
	}
	return six, seven, six >= 0 && seven >= 0
}

western_ranch_can_start :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || .Western_Ranch in room.player.floor_secrets ||
	   !room.player.deck.combat_active || room.qte.kind != .None || tactical_is_casting(room) { return false }
	_, _, ok := western_ranch_hand(room)
	return ok
}

// The pair leaves the hand for the ranch sign and lands in the discard pile.
begin_western_ranch :: proc(room: ^Room) -> bool {
	if !western_ranch_can_start(room) { return false }
	six, seven, _ := western_ranch_hand(room)
	deck := &room.player.deck
	// The higher slot first, so the other index stays valid.
	for index in ([2]int{max(six, seven), min(six, seven)}) {
		_, discarded := discard_hand_card(deck, index)
		assert(discarded)
	}
	room.player.floor_secrets += {.Western_Ranch}
	return true
}

// A win refills health and pays the purse; a loss costs nothing.
settle_western_ranch :: proc(room: ^Room, won: bool) -> (reward: Western_Ranch_Reward) {
	if room == nil || room.player == nil { return }
	reward.won = won
	if !won { return }
	player := room.player
	reward.healed = max(i32(0), player.stats.max_health-player.health)
	player.health = player.stats.max_health
	reward.gold = WESTERN_RANCH_GOLD
	player.gold += reward.gold
	return
}
