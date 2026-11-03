package integration
import run_session "../run"

import "core:log"
import "core:testing"
import "core:time"
import advisor "../advisor"
import combatdebug "../combatdebug"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE ADVISOR'S SEARCH (docs/piano-ia.md, Fase 2): the puzzles where everything is announced (as in Into the Breach),
// the same advice however the nodes are cut into frames, the real room never touched, the advice ready at once when
// the player does what was thought ahead, the table of commands, the tournament against the simple rules, the
// measures.

// The work of a whole search (every round: 491 nodes in the IA's arena).
@(private = "file")
WHOLE_WORK :: 4000

// The IA's arena, its foes free to plan.
@(private = "file")
search_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, arena := run_session.Mechanics_Lab_Arena.IA) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, arena)
	testing.expect(t, built)
	return room
}

// The hand: only the `keep` cards stay (and the IA's own), those in `draw` go to the draw pile, the rest to the discard
// pile; every card stays the one it was, in one zone (game.validate_deck_state).
@(private = "file")
search_test_hand :: proc(room: ^game.Room, keep: []game.Card_Id, draw: []game.Card_Id = nil) {
	deck := &room.player.deck
	hand := deck.hand
	count := deck.hand_count
	deck.hand_count = 0
	for card in hand[:count] {
		kept := card.definition_id == .IA
		for id in keep { if card.definition_id == id { kept = true } }
		drawn := false
		for id in draw { if card.definition_id == id { drawn = true } }
		switch {
		case kept: deck.hand[deck.hand_count] = card; deck.hand_count += 1
		case drawn: deck.draw_pile[deck.draw_count] = card; deck.draw_count += 1
		case: deck.discard_pile[deck.discard_count] = card; deck.discard_count += 1
		}
	}
	for &card in deck.hand[deck.hand_count:] { card = {} }
	deck.energy = deck.rules.max_energy
}

@(private = "file")
Puzzle_Foe :: struct { archetype: game.Enemy_Archetype, cell: grid.Position, health: i32 }

// A puzzle: the arena emptied of its foes, the player on `at`, the foes given (each from the arena's own foe of its
// archetype), every intent planned afresh by the rules. The hand keeps the `cards` given (none: the board's moves
// alone, Fase 2's puzzles), the rest goes to the discard pile.
@(private = "file")
search_test_puzzle :: proc(t: ^testing.T, room: ^game.Room, at: grid.Position, foes: []Puzzle_Foe, cards: []game.Card_Id = nil, draw: []game.Card_Id = nil) {
	search_test_hand(room, cards, draw)
	templates: [game.Enemy_Archetype]game.Enemy
	for enemy in room.enemies { templates[enemy.archetype] = enemy }
	clear(&room.enemies)
	room.player.position = at
	for foe, k in foes {
		enemy := templates[foe.archetype]
		testing.expectf(t, enemy.archetype == foe.archetype && enemy.max_health > 0, "the arena has no %v", foe.archetype)
		enemy.id = u32(900+k)
		enemy.position, enemy.health = foe.cell, foe.health
		enemy.max_health = max(enemy.max_health, foe.health)
		enemy.intent, enemy.tactical_cooldown, enemy.recovery_pulses = {}, 0, 0
		append(&room.enemies, enemy)
	}
	game.plan_enemy_intents(room)
}

// The `index`th foe's blow, said by hand: on `cells`, `damage`, in `beats` beats.
@(private = "file")
search_test_blow :: proc(room: ^game.Room, index: int, cells: []grid.Position, damage: i32, beats: f32) {
	enemy := &room.enemies[index]
	// Planned now, as the rules plan (game.validate_enemy_intent_structure).
	enemy.intent = {kind = .Attack, origin = enemy.position, destination = enemy.position, damage = damage, planned_pulse = room.pulse_count+1}
	for cell in cells { enemy.intent.threatened_cells[enemy.intent.threatened_cell_count] = cell; enemy.intent.threatened_cell_count += 1 }
	enemy.tactical_cooldown = beats
}

// The whole search's advice; every first move's value in the log when `t` fails after it.
@(private = "file")
search_test_advice :: proc(search: ^advisor.Search, room: ^game.Room) -> advisor.Advice {
	advice := advisor.search_whole(search, room, WHOLE_WORK)
	log.debugf("advice %v %v cell %v value %.2f depth %d after %d nodes", advice.kind, advice.move.direction, advice.cell, advice.value, advice.depth, advice.nodes)
	return advice
}

@(private = "file")
search_test_log_values :: proc(search: ^advisor.Search) {
	for i in 0..<search.candidate_count {
		c := search.candidates[i]
		log.infof("  %v %v %v %v: legal %v value %.2f", c.kind, c.direction, c.offset, c.defense, search.legal[i], search.values[i])
	}
}

@(private = "file")
cell_in :: proc(cell: grid.Position, cells: []grid.Position) -> bool {
	for c in cells { if c == cell { return true } }
	return false
}

// The brute's cleave is about to fall on three cells, his own in front included: the IA leaves them.
@(test)
test_advisor_search_leaves_the_brutes_cleave :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Brute, {x = 11, y = 13}, 40}})
	cells := []grid.Position{{x = 10, y = 12}, {x = 11, y = 12}, {x = 12, y = 12}}
	search_test_blow(&room, 0, cells, 3, 1)
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind != .Wait && advice.kind != .Bump && !cell_in(advice.cell, cells)
	testing.expectf(t, ok, "the IA stays under the cleave: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// The archer's arrow is about to fly down the player's column: the IA leaves the line.
@(test)
test_advisor_search_leaves_the_archers_line :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Archer, {x = 11, y = 16}, 30}})
	archer := &room.enemies[0]
	testing.expectf(t, archer.intent.kind == .Attack && game.enemy_intent_cell_is_threatened(&archer.intent, room.player.position),
		"the archer does not aim at the player: %v", archer.intent.kind)
	archer.tactical_cooldown = 1
	advice := search_test_advice(&search, &room)
	// Out of the cells the arrow reaches: off the column, or beyond its reach.
	ok := advice.valid && !game.enemy_intent_cell_is_threatened(&archer.intent, advice.cell)
	testing.expectf(t, ok, "the IA stays in the archer's line: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// A foe with 2 of life is next to the player: the IA strikes it.
@(test)
test_advisor_search_strikes_the_weak_foe :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 12, y = 12}, 2}, {.Chaser, {x = 4, y = 15}, 12}})
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind == .Bump && advice.cell == (grid.Position{x = 12, y = 12})
	testing.expectf(t, ok, "the IA does not strike the foe at 2: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// Two foes will strike the same cell, the one where the player would stand to strike the weakest foe (held beyond it),
// and his dodge is still recovering: no defence would answer them. The IA does not step on it.
@(test)
test_advisor_search_keeps_off_a_cell_two_foes_strike :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 10, y = 11}, 12}, {.Chaser, {x = 12, y = 11}, 12}, {.Chaser, {x = 11, y = 10}, 3}})
	trap := grid.Position{x = 11, y = 11}
	search_test_blow(&room, 0, {trap}, 4, 1)
	search_test_blow(&room, 1, {trap}, 4, 1)
	room.enemies[2].recovery_pulses, room.enemies[2].intent, room.enemies[2].tactical_cooldown = 99, {}, 0
	game.plan_enemy_intents(&room)
	room.player.tactical.dodge_recovery = game.TACTICAL_DODGE_RECOVERY+1
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.cell != trap
	testing.expectf(t, ok, "the IA steps where two blows fall: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// A step out of the cleave leads into a blind pocket, the brute at its mouth: safe now, cornered after; the fast rule
// alone takes it (the first free step out of the threat). Looking ahead, the IA does not. From the same room the real
// game is played twice for six seconds, following the IA and following the fast rule: the IA loses no more life.
// (Under today's rules the pocket costs no life in the end: a player there strikes the brute, and a struck foe
// staggers. The puzzle checks the choice.)
@(private = "file")
search_test_corner :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> game.Room {
	room := search_test_arena(t, data, player)
	for cell in ([?]grid.Position{{x = 10, y = 11}, {x = 12, y = 11}, {x = 10, y = 10}, {x = 11, y = 10}, {x = 12, y = 10}}) {
		testing.expect(t, level.set_tile(data, cell, {kind = .Wall}))
	}
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Brute, {x = 11, y = 13}, 40}})
	search_test_blow(&room, 0, {{x = 10, y = 12}, {x = 11, y = 12}, {x = 12, y = 12}}, 3, 1)
	return room
}

// Six seconds of the real game, the player following the IA (or the fast rule) at every free moment and answering
// the defence keys as told (the fast rule: as the copies do). The life lost.
@(private = "file")
search_test_follow :: proc(room: ^game.Room, search: ^advisor.Search, ia: bool, seconds: f32) -> int {
	health := room.player.health
	for ran := f32(0); ran < seconds && room.phase == .Combat; ran += advisor.SIM_STEP {
		if advisor.player_free(room) || room.qte.kind != .None {
			move, ok := advisor.Move{}, false
			if ia {
				advice := advisor.search_whole(search, room, WHOLE_WORK)
				move, ok = advice.move, advice.valid
			} else if room.qte.kind == .Defense {
				move, ok = advisor.best_defense_move(room)
			} else if room.qte.kind == .None {
				move, ok = advisor.fast_move(room), true
			}
			if ok {
				commands, count := run_session.advisor_move_commands(room, move)
				for command in commands[:count] { run_session.execute_gameplay_command(room, command) }
			}
		}
		advisor_test_real_frame(room, advisor.SIM_STEP)
	}
	return int(health-max(0, room.player.health))
}

@(test)
test_advisor_search_looks_ahead_out_of_a_corner :: proc(t: ^testing.T) {
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	pocket := grid.Position{x = 11, y = 11}
	fast_lost, ia_lost: int
	{
		data: level.Level
		defer level.destroy(&data)
		player: game.Player
		room := search_test_corner(t, &data, &player)
		defer game.destroy_room(&room)
		fast := advisor.fast_move(&room)
		testing.expectf(t, fast.kind == .Step && fast.direction == .North, "the fast rule does not take the pocket: %v %v", fast.kind, fast.direction)
		fast_lost = search_test_follow(&room, &search, false, 6)
	}
	{
		data: level.Level
		defer level.destroy(&data)
		player: game.Player
		room := search_test_corner(t, &data, &player)
		defer game.destroy_room(&room)
		advice := search_test_advice(&search, &room)
		testing.expectf(t, advice.valid && advice.cell != pocket, "the IA walks into the pocket: %v to %v", advice.kind, advice.cell)
		if advice.cell == pocket { search_test_log_values(&search) }
		ia_lost = search_test_follow(&room, &search, true, 6)
	}
	log.infof("the corner, six seconds: the fast rule lost %d life, the IA %d", fast_lost, ia_lost)
	testing.expectf(t, ia_lost <= fast_lost, "the fast rule lost %d life, the IA %d", fast_lost, ia_lost)
}

// The defence keys up: the IA advises a defence the player has, a dodge onto a cell the blow does not reach.
@(test)
test_advisor_search_answers_the_defence_keys :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 11, y = 13}, 30}})
	search_test_blow(&room, 0, {{x = 11, y = 12}}, 4, 1)
	for _ in 0..<120 {
		if room.qte.kind != .None { break }
		advisor_test_real_frame(&room, 1.0/30.0)
	}
	testing.expectf(t, room.qte.kind == .Defense, "no defence keys came up: %v", room.qte.kind)
	if room.qte.kind != .Defense { return }
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind == .Defend && advice.move.defense in room.qte.defenses
	if ok && advice.move.defense == .Dodge { ok = advice.cell != (grid.Position{x = 11, y = 12}) }
	testing.expectf(t, ok, "the IA does not answer the defence keys: %v %v to %v", advice.kind, advice.move.defense, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// However the nodes are cut into frames (one at a time, eight, all at once), the same root gives the same advice after
// the same nodes; twice the same root, the same advice.
@(test)
test_advisor_search_gives_the_same_advice_however_cut :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for advisor_test_real_until_free(&room, 1.0/30.0); room.enemies[0].intent.kind == .None; {
		advisor_test_real_frame(&room, 1.0/30.0)
	}
	whole := advisor.search_whole(&search, &room, 300)
	again := advisor.search_whole(&search, &room, 300)
	testing.expect(t, whole == again)
	for slice in ([?]int{1, 8}) {
		testing.expect(t, advisor.search_root(&search, &room))
		for spent := 0; spent < 300; spent += slice { advisor.search_step(&search, min(slice, 300-spent)) }
		testing.expectf(t, search.advice == whole, "cut in %d: %v, whole: %v", slice, search.advice, whole)
	}
}

// A thousand nodes of search leave the real room as it was, field by field.
@(test)
test_advisor_search_never_touches_the_real_room :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	before: advisor.Snapshot
	testing.expect(t, advisor.snapshot_init(&before))
	defer advisor.snapshot_destroy(&before)
	testing.expect(t, advisor.snapshot_take(&before, &room))
	advisor.search_whole(&search, &room, 1000)
	equal, where_ := advisor.rooms_equal(&before.room, &room)
	testing.expectf(t, equal, "the search changed the real room at %s", where_)
}

// THINKING AHEAD: the player does the advised move; the new root's advice is there at once, from the last search.
@(test)
test_advisor_search_thinks_ahead :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	advice := advisor.search_whole(&search, &room, WHOLE_WORK)
	testing.expect(t, advice.valid)
	advisor_test_real_until_free(&room, advisor.SIM_STEP, advisor.HORIZON_LONG)
	commands, count := run_session.advisor_move_commands(&room, advice.move)
	for command in commands[:count] { run_session.execute_gameplay_command(&room, command) }
	pondered, found := advisor.search_pondered(&search, advisor.discrete_fingerprint(&room))
	testing.expectf(t, found && pondered.valid && pondered.pondered, "no advice thought ahead after %v", advice.move)
}

// THE COMMANDS THE IA KNOWS (the rule for ever): every command has its use and its reason; every move of the IA is
// the game's own commands, each one the IA advises or will advise; every command it advises is some move of it.
@(test)
test_advisor_knows_every_command :: proc(t: ^testing.T) {
	produced: bit_set[run_session.Gameplay_Command_Kind]
	room: game.Room
	for kind in advisor.Move_Kind {
		commands, count := run_session.advisor_move_commands(&room, {kind = kind, succeed = true})
		testing.expectf(t, count > 0, "the IA's move %v is no command", kind)
		for command in commands[:count] {
			use, _ := run_session.advisor_command_use(command.kind)
			testing.expectf(t, use == .Advised || use == .Later, "the IA's move %v is the command %v (%v)", kind, command.kind, use)
			produced += {command.kind}
		}
	}
	for kind in run_session.Gameplay_Command_Kind {
		use, why := run_session.advisor_command_use(kind)
		testing.expectf(t, why != "", "the command %v has no reason", kind)
		if use == .Advised || use == .Later && kind != .Shoot && kind != .Activate && kind != .Equip && kind != .Shadow_Emerge {
			testing.expectf(t, kind in produced, "the IA advises %v, but no move of it is that command", kind)
		}
	}
	// Every foe has its line (the switch has no default: a new archetype does not build without one).
	for archetype in game.Enemy_Archetype {
		if archetype == .Count { continue }
		k := advisor.enemy_knowledge(archetype)
		testing.expectf(t, k.danger > 0 && k.kill >= advisor.KILL_VALUE, "the IA knows %v as %v", archetype, k)
	}
}

// THE TOURNAMENT. Fixed fights of the IA's arena, played alone, no window, the player starting on a different cell
// each: the player following the IA against the simple rule of today (combatdebug.choose_max_distance_command) and a
// player striking the nearest foe. The simple rules are movement only, as today's; for the record they play again
// answering the defence keys as the IA's copies do (advisor.best_defense_move). A real hand misses the keys: every
// player who answers them lets one in four run out (advisor.MISS_CHANCE). Life lost, foes killed, seconds. The IA
// must lose at least a third less life than the simple rule, and no more than the nearest-foe player (docs/piano-ia.md).
@(private = "file")
TOURNAMENT_FIGHTS :: 20 when ODIN_TEST_FULL else 4
@(private = "file")
TOURNAMENT_SECONDS :: f32(40)
// Every decision: the first two rounds whole (every first move, every reply).
@(private = "file")
TOURNAMENT_WORK :: 182

@(private = "file")
Contender :: enum { IA, Kiting, Nearest, Kiting_Defending, Nearest_Defending }

@(private = "file")
Fight :: struct { lost, kills, cleared: int, seconds: f32 }

@(private = "file")
tournament_move :: proc(room: ^game.Room, who: Contender, search: ^advisor.Search, kiting: ^combatdebug.Max_Distance_Policy_State) -> (advisor.Move, bool) {
	if who == .IA {
		advice := advisor.search_whole(search, room, TOURNAMENT_WORK)
		return advice.move, advice.valid
	}
	if room.qte.kind == .Defense && (who == .Kiting_Defending || who == .Nearest_Defending) { return advisor.best_defense_move(room) }
	if room.qte.kind != .None { return {}, false }
	p := room.player.position
	if who == .Kiting || who == .Kiting_Defending {
		decision := combatdebug.choose_max_distance_command(room, kiting)
		if !decision.valid { return {}, false }
		if decision.kind == .Move {
			kiting.has_last_direction, kiting.last_direction = true, decision.direction
			return {kind = .Step, direction = decision.direction}, true
		}
		return {kind = .Wait}, true
	}
	// The nearest foe: struck when next to him, else a step towards it, else wait.
	nearest, best := grid.Position{}, max(int)
	for enemy in room.enemies {
		d := abs(enemy.position.x-p.x)+abs(enemy.position.y-p.y)
		if d < best { nearest, best = enemy.position, d }
	}
	if best == max(int) { return {kind = .Wait}, true }
	for direction in game.Move_Direction {
		cell := game.add_position(p, game.direction_offset(direction))
		if cell == nearest { return {kind = .Step, direction = direction}, true }
	}
	for direction in game.Move_Direction {
		cell := game.add_position(p, game.direction_offset(direction))
		if abs(nearest.x-cell.x)+abs(nearest.y-cell.y) >= best { continue }
		query := game.query_entity_movement(room, game.PLAYER_ENTITY, cell)
		if game.movement_query_is_clear(&query) { return {kind = .Step, direction = direction}, true }
	}
	return {kind = .Wait}, true
}

@(private = "file")
tournament_fight :: proc(t: ^testing.T, who: Contender, start: grid.Position, search: ^advisor.Search, arena := run_session.Mechanics_Lab_Arena.IA) -> (fight: Fight) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player, arena)
	defer game.destroy_room(&room)
	if arena == .IA {
		room.player.position = start
		// The arena's four foes and, across the arena, one more of each: eight, so that the fight can hurt.
		extra := [?]grid.Position{{x = 18, y = 15}, {x = 3, y = 14}, {x = 11, y = 2}, {x = 3, y = 9}}
		for k in 0..<4 {
			foe := room.enemies[k]
			foe.id, foe.position = u32(800+k), extra[k]
			foe.intent, foe.tactical_cooldown, foe.recovery_pulses = {}, 0, 0
			if _, taken := game.enemy_index_at(&room, foe.position); !taken && foe.position != start { append(&room.enemies, foe) }
		}
		game.plan_enemy_intents(&room)
	}
	health, foes := room.player.health, len(room.enemies)
	kiting: combatdebug.Max_Distance_Policy_State
	defences := 0
	answering: u32
	for fight.seconds < TOURNAMENT_SECONDS && room.phase == .Combat {
		// One defence in four is missed: its window runs out.
		if room.qte.kind == .Defense && !room.qte.selected && answering != room.qte.enemy_id+1 {
			answering = room.qte.enemy_id+1
			defences += 1
		}
		missed := room.qte.kind == .Defense && defences%4 == 0
		if (advisor.player_free(&room) || room.qte.kind != .None) && !missed {
			if move, ok := tournament_move(&room, who, search, &kiting); ok {
				commands, count := run_session.advisor_move_commands(&room, move)
				for command in commands[:count] { run_session.execute_gameplay_command(&room, command) }
			}
		}
		if room.qte.kind == .None { answering = 0 }
		advisor_test_real_frame(&room, advisor.SIM_STEP)
		fight.seconds += advisor.SIM_STEP
	}
	fight.lost = int(health-max(0, room.player.health))
	fight.kills = foes-len(room.enemies)
	fight.cleared = 1 if room.phase != .Combat && room.player.health > 0 else 0
	return
}

@(test)
test_advisor_tournament :: proc(t: ^testing.T) {
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	// The starting cells: free cells spread over the arena, three cells from every foe at least, the same every run.
	starts: [TOURNAMENT_FIGHTS]grid.Position
	{
		data: level.Level
		defer level.destroy(&data)
		player: game.Player
		room := search_test_arena(t, &data, &player)
		defer game.destroy_room(&room)
		found := 0
		for k := 0; found < TOURNAMENT_FIGHTS && k < 400; k += 1 {
			cell := grid.Position{x = 2+(k*7)%19, y = 2+(k*5)%14}
			query := game.query_entity_movement(&room, game.PLAYER_ENTITY, cell)
			_, foe := game.enemy_index_at(&room, cell)
			if !game.movement_query_is_clear(&query) || foe { continue }
			near := false
			for enemy in room.enemies { if abs(enemy.position.x-cell.x)+abs(enemy.position.y-cell.y) < 3 { near = true } }
			if near { continue }
			starts[found] = cell
			found += 1
		}
		testing.expect_value(t, found, TOURNAMENT_FIGHTS)
	}
	totals: [Contender]Fight
	for start, k in starts {
		for who in Contender {
			fight := tournament_fight(t, who, start, &search)
			log.debugf("fight %d from %v, %v: lost %d, killed %d, %.1f s", k, start, who, fight.lost, fight.kills, fight.seconds)
			totals[who].lost += fight.lost
			totals[who].kills += fight.kills
			totals[who].cleared += fight.cleared
			totals[who].seconds += fight.seconds
		}
	}
	for who in Contender {
		log.infof("tournament %v: %d fights, life lost %d, foes killed %d, rooms cleared %d, %.0f s", who, TOURNAMENT_FIGHTS,
			totals[who].lost, totals[who].kills, totals[who].cleared, totals[who].seconds)
	}
	testing.expectf(t, 3*totals[.IA].lost <= 2*totals[.Kiting].lost, "the IA lost %d life, the simple rule %d", totals[.IA].lost, totals[.Kiting].lost)
	testing.expectf(t, totals[.IA].lost <= totals[.Nearest].lost, "the IA lost %d life, the nearest-foe player %d", totals[.IA].lost, totals[.Nearest].lost)
}

// THE TOURNAMENT IN THE SPECIAL ARENAS (Fase 7): heights, structures, layers, lifts, the player starting where each
// arena puts him: the IA loses no more life than the nearest-foe player, and strikes down at least as many foes as
// half of what he does (its own cells, cliffs and shafts are the copy's too).
@(test)
test_advisor_tournament_in_the_special_arenas :: proc(t: ^testing.T) {
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for arena in ([?]run_session.Mechanics_Lab_Arena{.Heights, .Structures, .Layers, .Lifts}) {
		ia := tournament_fight(t, .IA, {}, &search, arena)
		nearest := tournament_fight(t, .Nearest, {}, &search, arena)
		log.infof("tournament %v: the IA lost %d and killed %d, the nearest-foe player lost %d and killed %d", arena, ia.lost, ia.kills, nearest.lost, nearest.kills)
		testing.expectf(t, ia.lost <= nearest.lost, "%v: the IA lost %d life, the nearest-foe player %d", arena, ia.lost, nearest.lost)
		testing.expectf(t, 2*ia.kills >= nearest.kills, "%v: the IA killed %d foes, the nearest-foe player %d", arena, ia.kills, nearest.kills)
	}
}

// THE MEASURES (logged): nodes a second; the round reached in 1, 10 and 100 ms; a frame's slice of the pilot.
@(test)
test_advisor_search_measures :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for advisor_test_real_until_free(&room, 1.0/30.0); room.enemies[0].intent.kind == .None; {
		advisor_test_real_frame(&room, 1.0/30.0)
	}
	testing.expect(t, advisor.search_root(&search, &room))
	start := time.tick_now()
	marks := [?]f64{1, 10, 100}
	mark := 0
	for !search.done {
		advisor.search_step(&search, 1)
		ms := time.duration_milliseconds(time.tick_since(start))
		for mark < len(marks) && ms >= marks[mark] {
			log.infof("advisor search after %.0f ms: %d nodes, advice of depth %d at horizon %.0f s", marks[mark], search.nodes, search.advice.depth, search.advice.horizon)
			mark += 1
		}
	}
	total := time.duration_milliseconds(time.tick_since(start))
	log.infof("advisor search whole: %d nodes in %.1f ms (%.0f nodes a second), %d seen again", search.nodes, total, f64(search.nodes)/(total/1000), search.table_hits)
	worst: f64
	testing.expect(t, advisor.search_root(&search, &room))
	for !search.done {
		frame := time.tick_now()
		advisor.search_step(&search, run_session.ADVISOR_FRAME_WORK)
		worst = max(worst, time.duration_milliseconds(time.tick_since(frame)))
	}
	log.infof("advisor frame slice of %d work: at most %.2f ms", run_session.ADVISOR_FRAME_WORK, worst)
}

// THE CARDS (docs/piano-ia.md, Fase 3).

// The advice is the card `id` of the hand (and its play).
@(private = "file")
advice_is_card :: proc(room: ^game.Room, advice: advisor.Advice, id: game.Card_Id) -> bool {
	if !advice.valid || advice.kind != .Card { return false }
	index, found := game.hand_card_index_by_id(&room.player.deck, advice.move.card_id)
	return found && room.player.deck.hand[index].definition_id == id
}

// Three foes close together, the Firebomb in hand: the IA throws it where its square takes all three.
@(test)
test_advisor_card_firebomb_on_three :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 10, y = 9}, 12}, {.Chaser, {x = 11, y = 9}, 12}, {.Chaser, {x = 12, y = 9}, 12}}, {.Firebomb})
	advice := search_test_advice(&search, &room)
	ok := advice_is_card(&room, advice, .Firebomb)
	if ok {
		index, _ := game.hand_card_index_by_id(&room.player.deck, advice.move.card_id)
		definition, _ := game.card_definition_by_id(.Firebomb)
		request, _ := game.card_target_request_from_target(&room, definition, advice.move.target)
		evaluation := game.evaluate_card_targeting(&room, room.player.deck.hand[index], request)
		ok = evaluation.query.enemy_count == 3
		testing.expectf(t, ok, "the Firebomb takes %d foes at %v", evaluation.query.enemy_count, advice.cell)
	}
	testing.expectf(t, ok, "the IA does not throw the Firebomb on the three: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// Shut in a dead end in the archer's line, his dodge recovering, the Guard in hand: the arrow costs nothing.
@(test)
test_advisor_card_guard_before_the_blow :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for cell in ([?]grid.Position{{x = 10, y = 12}, {x = 12, y = 12}, {x = 11, y = 11}, {x = 10, y = 11}, {x = 12, y = 11}, {x = 10, y = 13}, {x = 12, y = 13}, {x = 10, y = 14}, {x = 12, y = 14}}) {
		testing.expect(t, level.set_tile(&data, cell, {kind = .Wall}))
	}
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Archer, {x = 11, y = 15}, 30}}, {.Guard})
	archer := &room.enemies[0]
	testing.expectf(t, archer.intent.kind == .Attack && game.enemy_intent_cell_is_threatened(&archer.intent, room.player.position),
		"the archer does not aim at the player: %v", archer.intent.kind)
	archer.tactical_cooldown = 1
	room.player.tactical.dodge_recovery = game.TACTICAL_DODGE_RECOVERY+1
	// The answer is the IA's: the Guard, a rush (next to him his shot is off) or a refocus that brings the Guard back in
	// time. What counts: it does not stand there, and the arrow costs no life.
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind != .Wait
	testing.expectf(t, ok, "the IA does not answer the arrow: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
	lost := search_test_follow(&room, &search, true, 3)
	testing.expectf(t, lost == 0, "following the IA the arrow cost %d of life", lost)
}

// The brute's cleave about to fall, the Guard in hand: a step out is enough, so no card (at equal worth, no card).
@(test)
test_advisor_card_none_when_a_step_is_enough :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Brute, {x = 11, y = 13}, 40}}, {.Guard})
	cells := []grid.Position{{x = 10, y = 12}, {x = 11, y = 12}, {x = 12, y = 12}}
	search_test_blow(&room, 0, cells, 3, 1)
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind != .Card && advice.kind != .Wait && !cell_in(advice.cell, cells)
	testing.expectf(t, ok, "the IA spends a card where a step is enough: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// A foe at 3 of life next to the player, Strike in hand: two bumps kill it, Strike at once. The IA plays the Strike.
@(test)
test_advisor_card_kills_sooner :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 12, y = 12}, 3}, {.Chaser, {x = 4, y = 15}, 12}}, {.Strike})
	advice := search_test_advice(&search, &room)
	ok := advice_is_card(&room, advice, .Strike) && advice.cell == (grid.Position{x = 12, y = 12})
	testing.expectf(t, ok, "the IA does not kill with the Strike: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// The cell of an advised nest.
@(private = "file")
nest_test_cell :: proc(room: ^game.Room, advice: advisor.Advice) -> (cell: grid.Position, ok: bool) {
	if !advice_is_card(room, advice, .Spider_Nest) { return }
	return advice.cell, true
}

// A brute's cleave about to fall on three cells between him and the player: the nest stays out of them.
@(test)
test_advisor_nest_away_from_the_brute :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Brute, {x = 13, y = 12}, 30}}, {.Spider_Nest})
	cells := []grid.Position{{x = 12, y = 11}, {x = 12, y = 12}, {x = 12, y = 13}}
	search_test_blow(&room, 0, cells, 3, 1)
	advice := search_test_advice(&search, &room)
	cell, ok := nest_test_cell(&room, advice)
	ok = ok && !cell_in(cell, cells)
	testing.expectf(t, ok, "the nest is not out of the brute's blow: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// Shut in a dead end, his dodge recovering, a chaser coming up the only way in: the nest in the way holds it, its blows go to the nest.
@(test)
test_advisor_nest_as_bait :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for cell in ([?]grid.Position{{x = 10, y = 12}, {x = 12, y = 12}, {x = 11, y = 11}, {x = 10, y = 11}, {x = 12, y = 11}, {x = 10, y = 13}, {x = 12, y = 13}, {x = 10, y = 14}, {x = 12, y = 14}}) {
		testing.expect(t, level.set_tile(&data, cell, {kind = .Wall}))
	}
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 11, y = 15}, 30}}, {.Spider_Nest})
	room.player.tactical.dodge_recovery = game.TACTICAL_DODGE_RECOVERY+1
	search_test_advice(&search, &room)
	// Against the walking and the waiting (the refocus has the other cards of the deck to bring: not this puzzle's).
	nest, walk := f32(-1e30), f32(-1e30)
	for i in 0..<search.candidate_count {
		if !search.legal[i] { continue }
		#partial switch search.candidates[i].kind {
		case .Card: nest = max(nest, search.values[i])
		case .Step, .Wait: walk = max(walk, search.values[i])
		}
	}
	testing.expectf(t, nest > walk, "the nest in the chaser's way is worth %.2f, walking and waiting %.2f", nest, walk)
}

// A foe of 3 life beside the player (2 the bump kills, no card spent), another far: the Strike kills it now, the nest can
// wait.
@(test)
test_advisor_strike_before_the_nest :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 12, y = 12}, 3}, {.Chaser, {x = 4, y = 15}, 12}}, {.Strike, .Spider_Nest})
	advice := search_test_advice(&search, &room)
	ok := advice_is_card(&room, advice, .Strike) && advice.cell == (grid.Position{x = 12, y = 12})
	testing.expectf(t, ok, "the IA does not kill with the Strike first: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// Nothing useful in hand, the Firebomb the next card drawn, three foes close together, held inside a ring of low walls
// that blows over it reach and feet do not: the IA refocuses the hand to draw it (the copy knows the deck: the user's
// choice).
@(test)
test_advisor_card_waits_for_the_next_draw :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := search_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	for x in 9..=13 {
		testing.expect(t, level.set_tile(&data, {x = x, y = 8}, {kind = .Fence}))
		testing.expect(t, level.set_tile(&data, {x = x, y = 10}, {kind = .Fence}))
	}
	testing.expect(t, level.set_tile(&data, {x = 9, y = 9}, {kind = .Fence}))
	testing.expect(t, level.set_tile(&data, {x = 13, y = 9}, {kind = .Fence}))
	search_test_puzzle(t, &room, {x = 11, y = 12}, {{.Chaser, {x = 10, y = 9}, 12}, {.Chaser, {x = 11, y = 9}, 12}, {.Chaser, {x = 12, y = 9}, 12}}, nil, {.Firebomb})
	for &enemy in room.enemies { enemy.recovery_pulses, enemy.intent, enemy.tactical_cooldown = 99, {}, 0 }
	game.plan_enemy_intents(&room)
	advice := search_test_advice(&search, &room)
	ok := advice.valid && advice.kind == .Refocus
	testing.expectf(t, ok, "the IA does not refocus for the Firebomb: %v to %v", advice.kind, advice.cell)
	if !ok { search_test_log_values(&search) }
}

// Every card the IA advises, alone in hand in the IA's arena: the search finds its plays and the rules take at least
// one; the cards it does not advise yet have their reason (advisor.ADVISOR_CARDS).
@(test)
test_advisor_tries_every_card :: proc(t: ^testing.T) {
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	unplayed := 0
	for id in game.Card_Id {
		if id == .Count { continue }
		known := advisor.ADVISOR_CARDS[id]
		testing.expectf(t, known.why != "" && known.puzzle != "", "the IA knows %v as %v", id, known)
		if known.use != .Advised { continue }
		// A card only ever made by another (the Spark, by the Spark Forge) is never a card of the deck.
		if definition, _ := game.card_definition_by_id(id); definition.temporary_only { continue }
		legal, count := false, 0
		// Two rooms: a foe next to the player, then a foe three cells away in his row (the hook's).
		for distance in ([?]int{1, 3}) {
			if legal { break }
			legal, count = search_test_card_plays(t, &search, id, distance)
		}
		if !legal { unplayed += 1; log.infof("the IA finds no play of %v in the arena (%d targets)", id, count) }
	}
	testing.expectf(t, unplayed == 0, "cards the IA could not play in the arena: %d", unplayed)
}

// The card `id` alone in hand (the Strike's place taken), a foe `distance` cells east of the player: the IA's plays of
// it, and whether the rules take one.
@(private = "file")
search_test_card_plays :: proc(t: ^testing.T, search: ^advisor.Search, id: game.Card_Id, distance: int) -> (legal: bool, count: int) {
	{
		data: level.Level
		player: game.Player
		room := search_test_arena(t, &data, &player)
		room.enemies[0].position = game.add_position(room.player.position, {x = distance, y = 0})
		game.plan_enemy_intents(&room)
		search_test_hand(&room, {.Strike})
		deck := &room.player.deck
		index, held := -1, false
		for card, k in deck.hand[:deck.hand_count] { if card.definition_id == .Strike { index, held = k, true } }
		testing.expect(t, held)
		if held {
			card := &deck.hand[index]
			if owned, found := game.owned_card_index_by_id(deck, card.id); found { deck.owned[owned].definition_id, deck.owned[owned].upgrade_level = id, 0 }
			card.definition_id, card.upgrade_level = id, 0
			plays: [advisor.MAX_CANDIDATES]advisor.Move
			count = advisor.card_plays(&room, plays[:])
			if count > 0 {
				advisor.search_whole(search, &room, 80)
				for i in 0..<search.candidate_count {
					if search.candidates[i].kind == .Card && search.legal[i] { legal = true }
				}
			}
		}
		game.destroy_room(&room)
		level.destroy(&data)
	}
	return
}
