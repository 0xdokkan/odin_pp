package advisor

import game "../game"
import grid "../engine/grid"

// THE CARDS IN THE SEARCH (docs/piano-ia.md, Fase 3): what the IA knows of every card, effect and status (the rule for
// ever: a new one does not build until it has its line here), the plays it tries (every card in hand, on its few best
// targets, chosen as the mouse chooses them: game.card_drop_target), and the dice, the one thing it does not know.

// How the IA uses a card:
// - Advised: it tries it, on its targets, and the rules in the copy play it out;
// - Later: a card the IA will advise in a later phase (none, since Fase 7);
// - Never: a card whose worth no copy can tell: the views (first person, Napoli's club and grandpa), played by the
//   player's own hand and eyes, where the IA stands still (the user's choice); no card to play in a fight (the rod's
//   slot fishes a cleared room); the IA itself. «O le sa simulare, o sta zitta» (docs/piano-ia.md, Fase 7).
Advisor_Card_Use :: enum u8 { Advised, Later, Never }

Advisor_Card :: struct {
	use: Advisor_Card_Use,
	why: string,
	// The test that plays it (similar cards share one).
	puzzle: string,
}

@(private = "file")
EVERY_CARD :: "test_advisor_tries_every_card"
@(private = "file")
ADVISED :: Advisor_Card{use = .Advised, why = "giocata nella copia con le regole vere", puzzle = EVERY_CARD}
@(private = "file")
VIEW :: Advisor_Card{use = .Never, why = "apre una vista: dentro si gioca a mano e la IA sta zitta; quanto vale non si simula", puzzle = EVERY_CARD}

// Every card (an enumerated array: a card without its line does not build).
@(rodata)
ADVISOR_CARDS := [game.Card_Id]Advisor_Card{
	.Strike = {use = .Advised, why = "danno a un nemico accanto", puzzle = "test_advisor_card_kills_sooner"},
	.Arc_Bolt = ADVISED, .Piercing_Ray = ADVISED, .Cross_Slash = ADVISED,
	.Firebomb = {use = .Advised, why = "danno su un'area", puzzle = "test_advisor_card_firebomb_on_three, test_advisor_card_waits_for_the_next_draw"},
	.Guard = {use = .Advised, why = "scudo prima del colpo", puzzle = "test_advisor_card_guard_before_the_blow, test_advisor_card_none_when_a_step_is_enough"},
	.Toxic_Wave = ADVISED, .Thorn_Coat = ADVISED, .Afterimage = ADVISED, .Counter_Rune = ADVISED, .Battle_Focus = ADVISED,
	.Calculated_Risk = ADVISED, .Spark_Forge = ADVISED, .Spark = ADVISED, .Shove = ADVISED, .Dash = ADVISED,
	.Grappling_Hook = ADVISED,
	.Heavy_Blow = ADVISED,
	.Venom_Needle = ADVISED, .Caustic_Bloom = ADVISED, .Purifying_Guard = ADVISED, .Volatile_Study = ADVISED,
	.Fate_Strike = ADVISED, .Chain_Lightning = ADVISED, .Sundering_Blow = ADVISED, .Prismatic_Barrage = ADVISED,
	.Twin_Venom = ADVISED, .Shock_Floor = ADVISED, .Tesla_Coil = ADVISED, .Titan_Grip = ADVISED, .Storm_Crown = ADVISED,
	.Sei_Denari = ADVISED, .Sette_Denari = ADVISED,
	.Shadow_Step = {use = .Advised, why = "Movimento Ombra: la copia fa i passi dell'ombra", puzzle = "test_advisor_walks_the_shadow"},
	.Poison_Pool = ADVISED, .Wildfire = ADVISED, .Deflect = ADVISED, .Coffin = ADVISED, .Fate_Dice = ADVISED,
	.Venom_Blade = ADVISED, .Lasso = ADVISED,
	.Fishing_Rod = {use = .Never, why = "pesca a stanza vuota, fuori dal combattimento", puzzle = EVERY_CARD},
	.Pinball = ADVISED,
	.First_Person = VIEW,
	.Cannon = ADVISED, .Flood = ADVISED, .Black_Hole = ADVISED, .Bomb_Marley = ADVISED, .Dinosaur = ADVISED,
	.Marley_Party = ADVISED, .Flood_Wave = ADVISED, .Field_Cannon = ADVISED, .Laser_Cannon = ADVISED,
	.Devouring_Hole = ADVISED, .Dino_Ride = ADVISED,
	.First_Person_Brawler = VIEW, .First_Person_Fencer = VIEW, .First_Person_Archer = VIEW,
	.Napoli = {use = .Never, why = "il D4 può aprire una vista (il bastone, il nonno): quanto vale non si simula", puzzle = EVERY_CARD},
	.IA = {use = .Never, why = "la IA non consiglia se stessa: rigiocata ripartirebbe dai suoi secondi", puzzle = EVERY_CARD},
	.Count = {use = .Never, why = "nessuna carta"},
}

// What an effect is worth for every foe it reaches, in the quick guess that picks a card's few targets (the search
// then plays them for real). A switch with no default: a new effect does not build without its line.
effect_value :: proc(kind: game.Effect_Kind) -> f32 {
	switch kind {
	case .Damage: return 1
	case .Heal: return 1
	case .Gain_Gold: return 0
	case .Move: return 0.5
	case .Apply_Status: return 0.5
	case .Remove_Status: return 0.3
	case .Add_Reaction_Binding: return 0.5
	case .Draw_Cards: return 0.5
	case .Discard_Cards: return 0
	case .Create_Card: return 0.3
	case .Gain_Energy: return 0.5
	case .Deploy_Device: return 1
	case .Enter_Shadow: return 0
	case .Place_Ground: return 1
	case .Lasso: return 2
	case .Fish: return 0
	case .Pinball: return 2
	case .First_Person: return 0
	case .Marley: return 2
	case .Flood_Wave: return 1
	case .Place_Cannon: return 2
	case .Open_Black_Hole: return 2
	case .Ride: return 1
	case .Napoli: return 0
	case .IA: return 0
	}
	return 0
}

// What a stack (or a point) of a status is worth past the horizon, on a foe and on the player, in the evaluation's
// points (a point of damage done is 1, a point of life lost is -3). A switch with no default.
status_value :: proc(kind: game.Status_Kind, on_player: bool) -> f32 {
	switch kind {
	// Damage still to come: on a foe it is damage done later, on the player life lost later.
	case .Poison: return -LIFE_WEIGHT*0.5 if on_player else 0.8
	case .Burn: return -LIFE_WEIGHT if on_player else 1.5
	case .Bleed: return -LIFE_WEIGHT*0.5 if on_player else 1
	// A blow absorbed or turned back; on a foe, the player's blows absorbed or hurting him.
	case .Shield: return 0.5 if on_player else -0.8
	case .Thorns: return 0.3 if on_player else -0.5
	case .Afterimage: return 1 if on_player else 0
	// A foe that loses its action; a player that loses his.
	case .Stagger: return -LIFE_WEIGHT if on_player else 1
	case .Slow: return 0 if on_player else 0.5
	case .Survey: return 0.1 if on_player else 0.2
	// The player's charges: each one a blow turned back, an arrow, a loaded bump.
	case .Deflect: return 1.5 if on_player else 0
	case .Arrows: return 1 if on_player else 0
	case .Fate: return 1 if on_player else 0
	case .Venom_Blade: return 1 if on_player else 0
	}
	return 0
}

// The statuses on the board, at their worth (the evaluation compares them with the root's).
statuses_value :: proc(room: ^game.Room) -> (value: f32) {
	for status in room.player.statuses.items[:room.player.statuses.count] {
		value += status_value(status.kind, true)*f32(max(status.potency, 1))
	}
	for &enemy in room.enemies {
		for status in enemy.statuses.items[:enemy.statuses.count] {
			value += status_value(status.kind, false)*f32(max(status.potency, 1))
		}
	}
	return
}

// A card's targets the search tries, at most this many: the best by the quick guess (all of them when fewer).
MAX_CARD_TARGETS :: 6

Card_Target :: struct {
	target: game.Target,
	cell: grid.Position,
	guess: f32,
}

// The way from the player to `cell` (the card's direction: a shove's, a wave's).
@(private)
direction_to :: proc(from, to: grid.Position) -> game.Move_Direction {
	dx, dy := to.x-from.x, to.y-from.y
	if abs(dx) >= abs(dy) { return .East if dx > 0 else .West }
	return .South if dy > 0 else .North
}

// The few best targets of a card in hand now, as the mouse would aim them: every cell in its reach tried with
// game.card_drop_target (on a foe's cell, the foe), the same target once, guessed by the foes its shape takes, the worth
// of its effects, how near a foe it lands, and (for a card that carries the player) whether the cell is threatened.
card_targets :: proc(room: ^game.Room, card: game.Card_Instance, out: ^[MAX_CARD_TARGETS]Card_Target) -> (count: int) {
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found { return }
	worth := f32(0)
	for effect in definition.effects[:definition.effect_count] { worth += effect_value(effect.kind) }
	p := room.player.position
	if definition.targeting.shape == .None || definition.targeting.rule == .Self || definition.targeting.rule == .Player {
		target, ok := game.card_drop_target(room, card, p)
		if !ok { target = game.entity_target(game.PLAYER_ENTITY) }
		out[0] = {target = target, cell = p, guess = worth}
		return 1
	}
	reach := max(definition.targeting.cast_range.maximum, 1)
	carries := definition.targeting.rule == .Walkable_Cell
	for y in p.y-reach..=p.y+reach {
		for x in p.x-reach..=p.x+reach {
			cell := grid.Position{x = x, y = y, layer = p.layer}
			target, ok := game.card_drop_target(room, card, cell)
			if !ok { continue }
			seen := false
			for k in 0..<count { if out[k].target == target { seen = true; break } }
			if seen { continue }
			request := game.card_target_request_at(definition, cell)
			evaluation := game.evaluate_card_targeting(room, card, request)
			guess := 10*f32(evaluation.query.enemy_count)*max(worth, 0.1)
			nearest := max(int)
			for enemy in room.enemies { nearest = min(nearest, manhattan(enemy.position, cell)) }
			if nearest != max(int) { guess -= 0.5*f32(nearest) }
			if carries && cell_threat(room, cell) > 0 { guess -= 20 }
			// Kept in order, best first; the first of equals stays first.
			slot := count
			for slot > 0 && guess > out[slot-1].guess { slot -= 1 }
			if slot >= MAX_CARD_TARGETS { continue }
			last := min(count, MAX_CARD_TARGETS-1)
			for k := last; k > slot; k -= 1 { out[k] = out[k-1] }
			out[slot] = {target = target, cell = cell, guess = guess}
			count = min(count+1, MAX_CARD_TARGETS)
		}
	}
	return
}

// Whether the IA may play this card now: advised, affordable, the rules letting cards be played.
card_playable :: proc(room: ^game.Room, card: game.Card_Instance) -> bool {
	if ADVISOR_CARDS[card.definition_id].use != .Advised || !game.tactical_allows_cards(room) { return false }
	return room.player.deck.energy >= game.card_energy_cost(room, card.definition_id)
}

// The plays of a hand: every playable card, the cheaper first (at equal worth, less energy spent), on its targets.
card_plays :: proc(room: ^game.Room, out: []Move) -> (count: int) {
	deck := &room.player.deck
	order: [game.MAX_HAND_CAPACITY]int
	n := 0
	for card, index in deck.hand[:deck.hand_count] {
		if !card_playable(room, card) { continue }
		cost := game.card_energy_cost(room, card.definition_id)
		slot := n
		for slot > 0 && game.card_energy_cost(room, deck.hand[order[slot-1]].definition_id) > cost { order[slot] = order[slot-1]; slot -= 1 }
		order[slot] = index
		n += 1
	}
	for index in order[:n] {
		card := deck.hand[index]
		targets: [MAX_CARD_TARGETS]Card_Target
		found := card_targets(room, card, &targets)
		for target in targets[:found] {
			if count == len(out) { return }
			out[count] = {kind = .Card, card_id = card.id, target = target.target, direction = direction_to(room.player.position, target.cell)}
			count += 1
		}
	}
	return
}

// A reply's card (a later move of a branch): the card in hand slot `slot`, on its best target, now. Whether it can.
resolve_slot :: proc(room: ^game.Room, move: Move) -> (Move, bool) {
	deck := &room.player.deck
	index := int(move.slot)-1
	if index < 0 || index >= deck.hand_count { return {}, false }
	card := deck.hand[index]
	if !card_playable(room, card) { return {}, false }
	targets: [MAX_CARD_TARGETS]Card_Target
	if card_targets(room, card, &targets) == 0 { return {}, false }
	return {kind = .Card, card_id = card.id, target = targets[0].target, direction = direction_to(room.player.position, targets[0].cell)}, true
}

// Where a card's target is, for the marks.
target_cell :: proc(room: ^game.Room, target: game.Target) -> grid.Position {
	switch target.kind {
	case .Cell: return target.cell
	case .Entity:
		if target.entity == game.PLAYER_ENTITY { return room.player.position }
		if index, found := game.enemy_index_by_id(room, target.entity.id); found && target.entity.kind == .Enemy { return room.enemies[index].position }
		for object in room.objects { if game.object_entity(object.id) == target.entity { return object.position } }
	case .None:
	}
	return room.player.position
}

// THE DICE: the IA knows everything but their faces. Every try rolls from dice of its own (DICE_SEED), never the
// player's; a card with one die is tried on every face of it and the faces weighed equally (expectimax); one with more
// dice on DICE_SAMPLES fixed rolls. The dice that give each face are found once (dice_faces_find).
DICE_SEED :: u64(0x1A_D1CE)
DICE_SAMPLES :: 6

Dice_Faces :: struct {
	// For every die of the ladder (4, 6, 8, 10, 12, 20 sides) and every face, dice whose next roll is that face.
	dice: [len(game.DICE_LADDER)][game.MAX_DIE_SIDES+1]game.Dice_State,
	ready: bool,
}

@(private)
ladder_index :: proc(sides: i32) -> int {
	for step, index in game.DICE_LADDER { if step == sides { return index } }
	return -1
}

dice_faces_find :: proc(faces: ^Dice_Faces) {
	if faces.ready { return }
	missing := 0
	for step in game.DICE_LADDER { missing += int(step) }
	for seed := u64(1); missing > 0 && seed < 1_000_000; seed += 1 {
		dice := game.make_dice_state(seed)
		for step, index in game.DICE_LADDER {
			staged := dice
			roll, rolled := game.roll_dice_pool(&staged, 1, step)
			if !rolled || roll.total < 1 || roll.total > step { continue }
			if faces.dice[index][roll.total] == {} { faces.dice[index][roll.total] = dice; missing -= 1 }
		}
	}
	faces.ready = true
}

// How many ways a play's dice are tried (1 when it rolls none), and the dice of the `k`th.
dice_ways :: proc(room: ^game.Room, move: Move, faces: ^Dice_Faces) -> (ways: int, sides: i32, many: bool) {
	if move.kind != .Card { return 1, 0, false }
	index, found := game.hand_card_index_by_id(&room.player.deck, move.card_id)
	if !found { return 1, 0, false }
	card := room.player.deck.hand[index]
	count := game.card_dice_count(card.definition_id)
	if count == 0 { return 1, 0, false }
	sides = game.card_die_sides(card.definition_id, card.upgrade_level)
	if count == 1 && ladder_index(sides) >= 0 && faces.ready { return int(sides), sides, false }
	return DICE_SAMPLES, sides, true
}

dice_way :: proc(faces: ^Dice_Faces, k: int, sides: i32, many: bool) -> game.Dice_State {
	if !many { return faces.dice[ladder_index(sides)][k+1] }
	return game.make_dice_state(DICE_SEED+u64(k)+1)
}
