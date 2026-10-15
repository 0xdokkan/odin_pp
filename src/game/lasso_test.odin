package game

import "core:math"
import "core:testing"
import grid "../grid"
import level "../level"

// A room walled round, `width` by `height` (13 by 13 unless said), the player
// on `at` (its middle unless said) with 100 health, the exit in a far corner.
// Fogless unless `vision` says otherwise.
lasso_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn,
	at := grid.Position{6, 6}, obstacles: []grid.Position = nil, vision := 0, width := 13, height := 13) -> Room {
	cells: [32][32]u8
	rows: [32]string
	for y in 0..<height {
		for x in 0..<width { cells[y][x] = '#' if x == 0 || y == 0 || x == width-1 || y == height-1 else '.' }
	}
	exit := grid.Position{width-2, height-2}
	if exit == at { exit = {1, height-2} }
	cells[at.y][at.x] = '@'
	cells[exit.y][exit.x] = '>'
	for y in 0..<height { rows[y] = string(cells[y][:width]) }
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:height])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	config := DEFAULT_TACTICAL_CONFIG
	config.vision_size = vision
	testing.expect(t, configure_tactical(player, config))
	room, ok := create_room(data, player, {enemies = spawns, obstacles = obstacles})
	testing.expect(t, ok)
	return room
}

// A foe held where it stands, as the mechanics lab holds one: recovering, it
// never moves or strikes.
lasso_test_hold :: proc(room: ^Room, id: u32) {
	index, found := enemy_index_by_id(room, id)
	if !found { return }
	room.enemies[index].recovery_pulses = 999
	room.enemies[index].intent, room.enemies[index].tactical_cooldown = {}, 0
	plan_enemy_intents(room)
}

lasso_test_foe :: proc(room: ^Room, cell: grid.Position) -> (id: u32) {
	for enemy in room.enemies { if enemy.position == cell { return enemy.id } }
	return 0
}

lasso_test_health :: proc(room: ^Room, id: u32) -> i32 {
	index, found := enemy_index_by_id(room, id)
	return room.enemies[index].health if found else 0
}

lasso_test_cell :: proc(room: ^Room, id: u32) -> grid.Position {
	index, found := enemy_index_by_id(room, id)
	return room.enemies[index].position if found else LASSO_NO_CELL
}

// The Lazzo from the hand at the foe `id`, at `upgrade`, on the tick when
// `critical`; its throw's cast run out unless `cast` is kept.
lasso_test_throw :: proc(t: ^testing.T, room: ^Room, id: u32, upgrade := i32(0), critical := false, keep_cast := false) -> Card_Play_Report {
	card := rework_hand_card(t, room, .Lasso)
	if upgrade > 0 {
		room.player.deck.hand[0].upgrade_level = upgrade
		for &owned in room.player.deck.owned[:room.player.deck.owned_count] {
			if owned.id == card.id { owned.upgrade_level = upgrade }
		}
	}
	room.player.tactical.critical_next = critical
	play := play_card(room, card.id, entity_target(enemy_entity(id)))
	room.player.tactical.critical_next = false
	if !keep_cast && tactical_is_casting(room) { tactical_tick(room, room.player.tactical.cast_remaining, true, false) }
	return play
}

// A lasso event as seen in a spin, and the world seconds of spin by then (at
// the end of the frame that brought it).
Lasso_Test_Event :: struct {
	event: Game_Event,
	at: f64,
}

// Spins the rope on `seconds` of world time in frames of `dt`, as the
// controller runs one: the clock, its beats, then the spin. Returns the world
// seconds the rope got; it stops once the rope is gone. The events each
// batch brought go to `events`.
lasso_test_spin :: proc(t: ^testing.T, room: ^Room, seconds, dt: f64, events: ^[dynamic]Lasso_Test_Event = nil) -> (spun: f64) {
	for guard := 0; spun < seconds-1e-9 && room.lasso.active && room.phase == .Combat && guard < 200_000; guard += 1 {
		before := room.lasso.pending
		tactical_tick(room, f32(min(dt, seconds-spun)), true, false)
		spun += room.lasso.pending-before
		drain_tactical_test_pulse(t, room)
		for tactical_lasso_due(room) {
			testing.expect(t, resolve_lasso_spin(room))
			testing.expect_value(t, room.recent_events.dropped_count, 0)
			if events != nil {
				for event in room.recent_events.events[:room.recent_events.count] { append(events, Lasso_Test_Event{event, spun}) }
			}
		}
	}
	return
}

@(test)
test_lasso_card_is_a_rare_tactical_rope_with_five_upgrades :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	definition, found := card_definition_by_id(.Lasso, true)
	testing.expect(t, found && definition.name == "Lazzo")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(2))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Opponent)
	testing.expect_value(t, definition.targeting.cast_range, Targeting_Range{.Chebyshev, 1, 4})
	testing.expect_value(t, definition.targeting.shape, Target_Shape.Single)
	testing.expect(t, definition.targeting.requires_line_of_sight)
	testing.expect(t, card_requires_tactical(.Lasso))
	testing.expect_value(t, tactical_card_time_cost(.Lasso), f32(2))
	testing.expect_value(t, card_max_upgrade_level(.Lasso), i32(5))
	testing.expect_value(t, card_dice_count(.Lasso), 0)
	for upgrade in i32(0)..=5 {
		card := Card_Instance{id = 1, definition_id = .Lasso, upgrade_level = upgrade}
		testing.expect_value(t, card_can_upgrade(card), upgrade < 5)
		testing.expect_value(t, card_effect_amount(definition.effects[0], upgrade), 1+upgrade)
	}
	testing.expect(t, !validate_card_instance({id = 1, definition_id = .Lasso, upgrade_level = 6}))
	node := Run_Node{kind = .Combat, depth = 4}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	testing.expect_value(t, card_offer_weight(definition, &node, nil, false), u64(0))
	// On the tick, the first hit is one harder.
	room: Room
	player: Player
	room.player = &player
	player.tactical.critical_card = true
	action := make_action(.Card, PLAYER_ENTITY, entity_target(enemy_entity(1)), .Opponent)
	testing.expect(t, add_effect(&action, lasso_effect(enemy_entity(1), 3)))
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(4))
}

@(test)
test_lasso_ring_is_every_cell_the_true_circle_crosses :: proc(t: ^testing.T) {
	for radius in i32(1)..=LASSO_MAX_RADIUS {
		arcs, count := lasso_ring(radius)
		testing.expect_value(t, count, 8*int(radius))
		r := f64(radius)
		for arc, index in arcs[:count] {
			next := arcs[(index+1)%count]
			// One arc a cell, each next cell a side neighbour, the arcs end to end
			// round the whole circle.
			testing.expect_value(t, abs(arc.cell.x-next.cell.x)+abs(arc.cell.y-next.cell.y), 1)
			testing.expect(t, arc.to > arc.from)
			gap := next.from-arc.to if index < count-1 else next.from+math.TAU-arc.to
			testing.expect(t, abs(gap) < 1e-9)
			for other in arcs[:index] { testing.expect(t, other.cell != arc.cell) }
			// The circle crosses the cell: its nearest and farthest points lie on
			// either side of it.
			ax, ay := f64(abs(arc.cell.x)), f64(abs(arc.cell.y))
			near := math.sqrt(max(0, ax-0.5)*max(0, ax-0.5)+max(0, ay-0.5)*max(0, ay-0.5))
			far := math.sqrt((ax+0.5)*(ax+0.5)+(ay+0.5)*(ay+0.5))
			testing.expect(t, near < r && r < far)
		}
		// And every cell the circle crosses is on it.
		crossed := 0
		for dy in -int(radius)-1..=int(radius)+1 {
			for dx in -int(radius)-1..=int(radius)+1 {
				ax, ay := f64(abs(dx)), f64(abs(dy))
				near := math.sqrt(max(0, ax-0.5)*max(0, ax-0.5)+max(0, ay-0.5)*max(0, ay-0.5))
				far := math.sqrt((ax+0.5)*(ax+0.5)+(ay+0.5)*(ay+0.5))
				if near < r && r < far { crossed += 1 }
			}
		}
		testing.expect_value(t, crossed, count)
	}
	one, _ := lasso_ring(1)
	degrees := [8][2]f64{{30, 60}, {60, 120}, {120, 150}, {150, 210}, {210, 240}, {240, 300}, {300, 330}, {330, 390}}
	cells := [8]grid.Position{{1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}, {1, 0}}
	for arc, index in one[:8] {
		testing.expect_value(t, arc.cell, cells[index])
		testing.expect(t, abs(arc.from*180/math.PI-degrees[index][0]) < 1e-6 && abs(arc.to*180/math.PI-degrees[index][1]) < 1e-6)
	}
	two, two_count := lasso_ring(2)
	has :: proc(arcs: []Lasso_Arc, cell: grid.Position) -> bool {
		for arc in arcs { if arc.cell == cell { return true } }
		return false
	}
	testing.expect(t, has(two[:two_count], {1, 1}) && has(two[:two_count], {2, 1}) && !has(two[:two_count], {2, 2}))
	// The integer eight-way snap is the angle's own octant on every ring cell.
	for radius in i32(1)..=LASSO_MAX_RADIUS {
		arcs, count := lasso_ring(radius)
		for arc in arcs[:count] {
			octant := int(math.round(math.atan2(f64(arc.cell.y), f64(arc.cell.x))/(math.PI/4)))
			expected := grid.Position{int(math.round(math.cos(f64(octant)*math.PI/4))), int(math.round(math.sin(f64(octant)*math.PI/4)))}
			testing.expect_value(t, lasso_radial_step({}, arc.cell), expected)
		}
	}
}

@(test)
test_lasso_radius_is_the_largest_clear_ring_and_smashes_beside_walls :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := lasso_test_room(t, &data, &player, nil)
	defer level.destroy(&data)
	defer destroy_room(&room)
	centre := grid.Position{6, 6}
	radius, smash := lasso_radius(&room, centre)
	testing.expect(t, radius == 4 && !smash)
	// One block east: on the outer ring (four cells away) it takes the ring
	// inside it; nearer, inside the outer ring, the foe flies over it at 4,
	// even beside the player.
	for distance, index in ([4]int{4, 3, 2, 1}) {
		append(&room.obstacles, Obstacle{position = {centre.x+distance, centre.y}})
		radius, smash = lasso_radius(&room, centre)
		expected := [4]i32{3, 4, 4, 4}
		testing.expect_value(t, radius, expected[index])
		testing.expect(t, !smash)
		clear(&room.obstacles)
	}
	// The west wall (x = 0) a straight line away: the user's own example, a
	// wall on the fourth cell giving 3. Beside it every ring crosses it: 1,
	// and a smash; so in a corner.
	for x, index in ([4]int{2, 3, 4, 5}) {
		radius, smash = lasso_radius(&room, {x, 6})
		testing.expect_value(t, radius, i32(index+1))
		testing.expect(t, !smash)
	}
	radius, smash = lasso_radius(&room, {1, 6})
	testing.expect(t, radius == 1 && smash)
	radius, smash = lasso_radius(&room, {1, 1})
	testing.expect(t, radius == 1 && smash)
	// A block inside the circle, off any axis (on the ring of 3 only): the
	// outer ring is clear, 4.
	append(&room.obstacles, Obstacle{position = {8, 8}})
	radius, smash = lasso_radius(&room, centre)
	testing.expect(t, radius == 4 && !smash)
	// Blocks on the rings of 4 and 3 (east), and of 2 (west): 1, no smash.
	clear(&room.obstacles)
	for cell in ([3]grid.Position{{10, 6}, {9, 6}, {4, 6}}) { append(&room.obstacles, Obstacle{position = cell}) }
	radius, smash = lasso_radius(&room, centre)
	testing.expect(t, radius == 1 && !smash)
	// And one beside the player too: every ring holds one, 1 and a smash.
	append(&room.obstacles, Obstacle{position = {6, 7}})
	radius, smash = lasso_radius(&room, centre)
	testing.expect(t, radius == 1 && smash)
	clear(&room.obstacles)
}

@(test)
test_lasso_targets_one_visible_foe_in_reach_and_refuses_the_heavy :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {10, 6}, health = 20, attack = 1},
		{position = {6, 1}, health = 20, attack = 1},
		{position = {2, 2}, health = 20, attack = 1},
		{position = {3, 9}, health = 40, attack = 1, archetype = .Custodian},
		{position = {9, 9}, health = 40, attack = 1, archetype = .Demolitionist},
		{position = {3, 6}, health = 20, attack = 1},
	}
	cover := [?]grid.Position{{4, 6}}
	room := lasso_test_room(t, &data, &player, spawns[:], obstacles = cover[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Lasso)
	definition, _ := card_definition_by_id(.Lasso, true)
	aim :: proc(room: ^Room, card: Card_Instance, definition: Card_Definition, cell: grid.Position) -> Card_Compile_Error {
		return evaluate_card_targeting(room, card, card_target_request_at(definition, cell)).error
	}
	testing.expect_value(t, aim(&room, card, definition, {10, 6}), Card_Compile_Error.None)
	testing.expect_value(t, aim(&room, card, definition, {6, 1}), Card_Compile_Error.Target_Out_Of_Range)
	testing.expect_value(t, aim(&room, card, definition, {2, 2}), Card_Compile_Error.None)
	testing.expect_value(t, aim(&room, card, definition, {3, 6}), Card_Compile_Error.Target_Blocked)
	// The boss and the miniboss are too heavy, and the drop takes neither.
	testing.expect_value(t, aim(&room, card, definition, {3, 9}), Card_Compile_Error.Target_Too_Heavy)
	testing.expect_value(t, aim(&room, card, definition, {9, 9}), Card_Compile_Error.Target_Too_Heavy)
	_, takes := card_drop_target(&room, card, {3, 9})
	testing.expect(t, !takes)
	testing.expect_value(t, aim(&room, card, definition, {7, 7}), Card_Compile_Error.Invalid_Target)
	// In the fog (sight 7: three cells round), four cells away is out of sight.
	player.tactical.config.vision_size = 7
	testing.expect_value(t, aim(&room, card, definition, {10, 6}), Card_Compile_Error.Invalid_Target)
	player.tactical.config.vision_size = 0
	// One rope at a time.
	play := lasso_test_throw(t, &room, lasso_test_foe(&room, {10, 6}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, lasso_target_error(&room, entity_target(enemy_entity(lasso_test_foe(&room, {2, 2})))), Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, lasso_target_error(&room, entity_target(enemy_entity(room.lasso.enemy_id))), Card_Compile_Error.Invalid_Target)
	// A classic room never plays it.
	classic_data: level.Level
	classic_player: Player
	classic := lasso_test_room(t, &classic_data, &classic_player, spawns[:1])
	defer level.destroy(&classic_data)
	defer destroy_room(&classic)
	classic_player.tactical.config.enabled = false
	classic_card := rework_hand_card(t, &classic, .Lasso)
	testing.expect_value(t, aim(&classic, classic_card, definition, {10, 6}), Card_Compile_Error.Invalid_Phase)
}

@(test)
test_lasso_throw_freezes_like_a_cast_then_spins_on_world_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 60, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := room.enemies[0].id
	energy := player.deck.energy
	play := lasso_test_throw(t, &room, id, keep_cast = true)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, energy-2)
	testing.expect(t, tactical_is_casting(&room) && room.lasso.active)
	testing.expect(t, room.lasso.radius == 4 && !room.lasso.smash && room.lasso.direction == -1)
	caught := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind != .Lasso_Caught { continue }
		caught = true
		testing.expect(t, event.source == PLAYER_ENTITY && event.target == enemy_entity(id))
		testing.expect(t, event.from_position == grid.Position{9, 6} && event.to_position == grid.Position{10, 6})
		testing.expect(t, event.amount == 4 && event.duration == 1)
	}
	testing.expect(t, caught)
	// Off the floor, onto its ring, its intent dropped: in the air it stands
	// on no cell.
	testing.expect_value(t, room.enemies[0].position, grid.Position{10, 6})
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.None)
	_, standing := enemy_index_at(&room, {10, 6})
	testing.expect(t, !standing)
	testing.expect(t, validate_enemy_intents(&room))
	testing.expect(t, enemy_is_lassoed(&room, id))
	// The throw is a cast: the world stands still through it.
	testing.expect(t, tactical_player_busy(&room) && !tactical_allows_cards(&room) && !tactical_allows_action(&room, true))
	testing.expect(t, !tactical_can_begin_shadow(&room))
	fraction, along, left := player.tactical.clock_fraction, room.lasso.along, room.lasso.turn_left
	tactical_tick(&room, 1, true, false)
	testing.expect(t, tactical_is_casting(&room))
	tactical_tick(&room, 1, true, false)
	testing.expect(t, !tactical_is_casting(&room))
	testing.expect(t, player.tactical.clock_fraction == fraction && room.lasso.along == along && room.lasso.turn_left == left)
	testing.expect(t, room.lasso.pending == 0 && !tactical_lasso_due(&room))
	// Then the pivot is busy: no step, bump, wait, card, arrow or shadow, but
	// a dodge would still go.
	testing.expect(t, tactical_player_busy(&room) && !tactical_allows_action(&room) && tactical_allows_action(&room, true))
	testing.expect(t, !tactical_allows_cards(&room) && !tactical_allows_movement(&room) && !tactical_can_begin_shadow(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	testing.expect_value(t, wait_player_turn(&room), Action_Result.Invalid_Phase)
	testing.expect_value(t, shoot_player_arrow(&room, enemy_entity(id)), Action_Result.Invalid_Phase)
	testing.expect_value(t, play_card(&room, player.deck.hand[0].id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Invalid_Phase)
	// A second of the world's own time: a full turn (0.9 s) and a bit of the
	// next, counter-clockwise from east.
	spun := lasso_test_spin(t, &room, 1, 1.0/60.0)
	testing.expect(t, abs(spun-1) < 1e-4)
	testing.expect_value(t, room.lasso.turns, i32(1))
	testing.expect_value(t, lasso_arc_cell(&room.lasso, room.lasso.arc), grid.Position{9, 3})
	testing.expect(t, abs(lasso_angle(&room.lasso)*180/math.PI-314.545) < 0.05)
	testing.expect_value(t, lasso_test_health(&room, id), i32(59))
	testing.expect_value(t, room.enemies[0].position, grid.Position{9, 3})
	testing.expect(t, validate_enemy_intents(&room))
}

@(test)
test_lasso_turns_speed_up_to_eight_a_second :: proc(t: ^testing.T) {
	testing.expect(t, abs(lasso_turn_seconds(0)-0.9) < 1e-12)
	testing.expect(t, abs(lasso_turn_seconds(1)-0.792) < 1e-12)
	testing.expect(t, abs(lasso_turn_seconds(15)-0.9*math.pow(0.88, 15)) < 1e-12 && lasso_turn_seconds(15) > 0.125)
	testing.expect_value(t, lasso_turn_seconds(16), LASSO_FASTEST_TURN_SECONDS)
	testing.expect_value(t, lasso_turn_seconds(200), LASSO_FASTEST_TURN_SECONDS)
	ends := [5]f64{0.9, 1.692, 2.38896, 3.0022848, 3.54201062}
	total: f64
	for end, turn in ends {
		total += lasso_turn_seconds(i32(turn))
		testing.expect(t, abs(total-end) < 1e-6)
	}
	sixty: f64
	for turn in 0..<60 { sixty += lasso_turn_seconds(i32(turn)) }
	testing.expect(t, abs(sixty-12.0300) < 0.001)
	// A lone unhurt foe of 60 falls after its 60th turn, at any frame rate.
	for dt in ([3]f64{1.0/60.0, 1.0/30.0, 0.5}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 60, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		play := lasso_test_throw(t, &room, room.enemies[0].id)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		events: [dynamic]Lasso_Test_Event
		spun := lasso_test_spin(t, &room, 20, dt, &events)
		turns := 0
		for seen in events { if seen.event.kind == .Damaged && event_is_lasso_turn(seen.event) { turns += 1 } }
		testing.expect_value(t, turns, 60)
		testing.expect(t, spun >= sixty-1e-6 && spun < sixty+dt+1e-6)
		testing.expect(t, !room.lasso.active && room.phase == .Loot)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// The ring of radius 4 round (6, 6), with foes standing on two of its cells.
lasso_test_bystanders :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, cells: []grid.Position) -> Room {
	spawns: [8]Enemy_Spawn
	spawns[0] = {position = {9, 6}, health = 60, attack = 1}
	for cell, index in cells { spawns[index+1] = {position = cell, health = 30, attack = 1} }
	room := lasso_test_room(t, data, player, spawns[:len(cells)+1])
	for cell in cells { lasso_test_hold(&room, lasso_test_foe(&room, cell)) }
	return room
}

@(test)
test_lasso_hits_number_up_and_knock_the_struck_away :: proc(t: ^testing.T) {
	for strong in ([2]bool{false, true}) {
		data: level.Level
		player: Player
		cells := [2]grid.Position{{6, 2}, {2, 7}}
		room := lasso_test_bystanders(t, &data, &player, cells[:])
		target := lasso_test_foe(&room, {9, 6})
		north, west := lasso_test_foe(&room, {6, 2}), lasso_test_foe(&room, {2, 7})
		// Upgraded twice and played on the tick, the first hit is a 4.
		play := lasso_test_throw(t, &room, target, 2 if strong else 0, strong)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		first := i32(4) if strong else 1
		testing.expect_value(t, room.lasso.first_hit, first)
		events: [dynamic]Lasso_Test_Event
		spun := lasso_test_spin(t, &room, 20, 1.0/240.0, &events)
		struck: [dynamic]Lasso_Test_Event
		for seen in events { if seen.event.kind == .Lasso_Struck { append(&struck, seen) } }
		testing.expect_value(t, len(struck), 2)
		if len(struck) == 2 {
			// Each the next number, the swung foe striking a foe on its cell.
			testing.expect(t, struck[0].event.target == enemy_entity(north) && struck[0].event.amount == first)
			testing.expect(t, struck[1].event.target == enemy_entity(west) && struck[1].event.amount == first+1)
			testing.expect(t, struck[0].event.source == enemy_entity(target) && struck[0].event.to_position == grid.Position{6, 2})
			testing.expect(t, abs(struck[0].at-0.207) < 0.005 && abs(struck[1].at-0.468) < 0.005)
		}
		// Both foes of a hit take its number; the one struck is knocked away from
		// the player as far as the wall lets it.
		testing.expect_value(t, lasso_test_health(&room, north), 30-first)
		testing.expect_value(t, lasso_test_health(&room, west), 30-first-1)
		testing.expect_value(t, lasso_test_cell(&room, north), grid.Position{6, 1})
		testing.expect_value(t, lasso_test_cell(&room, west), grid.Position{1, 7})
		wounded, pushed := 0, false
		for seen in events {
			if seen.event.kind == .Damaged && seen.event.source == PLAYER_ENTITY && event_is_lasso(seen.event) && !event_is_lasso_turn(seen.event) { wounded += 1 }
			if seen.event.kind == .Moved && seen.event.target == enemy_entity(north) && seen.event.source == PLAYER_ENTITY { pushed = true }
		}
		testing.expect(t, wounded >= 4 && pushed)
		death := 10.905 if strong else 11.655
		testing.expect(t, spun >= death-0.005 && spun < death+0.005)
		_, alive := enemy_index_by_id(&room, target)
		testing.expect(t, !alive && !room.lasso.active)
		delete(struck)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_lasso_knockback_follows_the_push_rules :: proc(t: ^testing.T) {
	// A foe behind the struck one stops its push; a pool where it lands
	// poisons it, a fire burns it; a hit three is three cells, straight south
	// from a cell a little off the axis, as far as the wall.
	data: level.Level
	player: Player
	cells := [4]grid.Position{{6, 2}, {6, 1}, {2, 7}, {7, 10}}
	room := lasso_test_bystanders(t, &data, &player, cells[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	north, behind, west, south := lasso_test_foe(&room, {6, 2}), lasso_test_foe(&room, {6, 1}), lasso_test_foe(&room, {2, 7}), lasso_test_foe(&room, {7, 10})
	index, _ := ground_index(&room, {1, 7})
	room.ground.pool[index] = 2
	room.ground.fires[0] = {id = 1, center = {7, 11}, burn = 1}
	room.ground.fire_count = 1
	room.ground.next_fire_id = 1
	play := lasso_test_throw(t, &room, lasso_test_foe(&room, {9, 6}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	lasso_test_spin(t, &room, 0.8, 1.0/240.0)
	testing.expect_value(t, lasso_test_cell(&room, north), grid.Position{6, 2})
	testing.expect_value(t, lasso_test_cell(&room, behind), grid.Position{6, 1})
	testing.expect_value(t, lasso_test_cell(&room, west), grid.Position{1, 7})
	testing.expect_value(t, lasso_test_cell(&room, south), grid.Position{7, 11})
	poison, poisoned := status_for_entity(&room, enemy_entity(west), .Poison)
	testing.expect(t, poisoned && poison.potency == 2)
	burn, burned := status_for_entity(&room, enemy_entity(south), .Burn)
	testing.expect(t, burned && burn.potency == 1)
	testing.expect_value(t, lasso_test_health(&room, north), i32(29))
	testing.expect_value(t, lasso_test_health(&room, south), i32(27))
	// The push never runs past the movement path's limit.
	long_data: level.Level
	long_player: Player
	long_spawns := [?]Enemy_Spawn{{position = {3, 2}, health = 30, attack = 1}}
	long := lasso_test_room(t, &long_data, &long_player, long_spawns[:], at = {1, 2}, width = 30, height = 5)
	defer level.destroy(&long_data)
	defer destroy_room(&long)
	lasso_knock_back(&long, long.enemies[0].id, 50)
	testing.expect_value(t, long.enemies[0].position, grid.Position{3+MAX_MOVEMENT_PATH_CELLS, 2})
}

@(test)
test_lasso_smashes_and_bounces_beside_a_wall :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 1}, health = 60, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:], at = {1, 1})
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := room.enemies[0].id
	play := lasso_test_throw(t, &room, id)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, room.lasso.radius == 1 && room.lasso.smash)
	// Pulled onto the one free cell its way lies.
	testing.expect_value(t, room.enemies[0].position, grid.Position{2, 1})
	events: [dynamic]Lasso_Test_Event
	defer delete(events)
	spun := lasso_test_spin(t, &room, 20, 1.0/240.0, &events)
	smashes: [dynamic]Lasso_Test_Event
	defer delete(smashes)
	turns := 0
	first_turn := f64(-1)
	for seen in events {
		if seen.event.kind == .Lasso_Struck { append(&smashes, seen) }
		if seen.event.kind == .Damaged && event_is_lasso_turn(seen.event) {
			turns += 1
			if first_turn < 0 { first_turn = seen.at }
		}
	}
	// Into the wall north (2, 0), bounced back into the one west (0, 2), and
	// back: each a hit of the next number, on the swung foe alone.
	expected := [3]struct{at: f64, cell: grid.Position}{{0.075, {2, 0}}, {0.45, {0, 2}}, {0.825, {2, 0}}}
	testing.expect(t, len(smashes) == 11)
	for want, index in expected {
		if index >= len(smashes) { break }
		event := smashes[index].event
		testing.expect(t, event.target == SYSTEM_ENTITY && event.source == enemy_entity(id) && event.amount == i32(index+1))
		testing.expect_value(t, event.to_position, want.cell)
		testing.expect(t, abs(smashes[index].at-want.at) < 0.005)
	}
	testing.expect(t, abs(first_turn-0.9) < 0.005 && turns == 4)
	testing.expect(t, abs(spun-3.1372) < 0.005)
	testing.expect(t, !room.lasso.active && room.phase == .Loot)
	testing.expect_value(t, len(room.obstacles), 0)
}

@(test)
test_lasso_holds_its_foe_out_of_the_world :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {9, 6}, health = 60, attack = 1},
		{position = {2, 2}, health = 30, attack = 1, archetype = .Custodian},
		{position = {11, 7}, health = 30, attack = 1},
	}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := lasso_test_foe(&room, {9, 6})
	walker := lasso_test_foe(&room, {11, 7})
	custodian := lasso_test_foe(&room, {2, 2})
	lasso_test_hold(&room, walker)
	lasso_test_hold(&room, custodian)
	_, _ = apply_status(&room, enemy_entity(id), .Poison, 3, 0)
	_, _ = apply_status(&room, enemy_entity(id), .Burn, 2, 0)
	// Pools on every cell of its ring, a fire beside its first cell.
	arcs, count := lasso_ring(4)
	for arc in arcs[:count] {
		if index, inside := ground_index(&room, add_position({6, 6}, arc.cell)); inside { room.ground.pool[index] = 3 }
	}
	room.ground.fires[0] = {id = 1, center = {10, 7}, burn = 4}
	room.ground.fire_count, room.ground.next_fire_id = 1, 1
	play := lasso_test_throw(t, &room, id)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	// Another foe walks into the cell under it.
	query := query_movement_from(&room, enemy_entity(walker), {11, 6}, {10, 6})
	testing.expect(t, movement_query_is_clear(&query))
	// The fire grows over its cell: nothing catches it in the air.
	pulse: Pulse_Report
	grow_ground_fires(&room, &pulse)
	_, caught := status_for_entity(&room, enemy_entity(id), .Burn)
	burn, _ := status_for_entity(&room, enemy_entity(id), .Burn)
	testing.expect(t, caught && burn.potency == 2)
	// Three seconds over the pools: no action of its own (its Veleno never
	// bites), nothing from the floor; the turns' damage only.
	lasso_test_spin(t, &room, 3, 1.0/60.0)
	poison, poisoned := status_for_entity(&room, enemy_entity(id), .Poison)
	testing.expect(t, poisoned && poison.potency == 3)
	turns := room.lasso.turns
	testing.expect_value(t, lasso_test_health(&room, id), 60-turns)
	// Bruciatura still bites as a new window opens.
	burns: Pulse_Report
	tick_combatants(&room, &burns, burn_status)
	testing.expect_value(t, lasso_test_health(&room, id), 58-turns)
	// The Custodian never takes it for an ally to guard, and the planner's
	// work stays sound with it in the air.
	custodian_index, _ := enemy_index_by_id(&room, custodian)
	room.enemies[custodian_index].recovery_pulses = 0
	room.enemies[custodian_index].intent, room.enemies[custodian_index].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	testing.expect(t, validate_enemy_intents(&room))
	intent := room.enemies[custodian_index].intent
	testing.expect(t, intent.kind != .Protect || intent.protected_ally != enemy_entity(id))
	index, _ := enemy_index_by_id(&room, id)
	testing.expect_value(t, room.enemies[index].intent.kind, Enemy_Intent_Kind.None)
}

@(test)
test_lasso_lets_go_when_the_player_moves :: proc(t: ^testing.T) {
	{
		// A dodge after a second: the foe falls on the cell under it (a pool
		// there poisons it) and plans afresh at once, with no daze, though it
		// was recovering when the rope caught it.
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 60, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		defer level.destroy(&data)
		defer destroy_room(&room)
		id := room.enemies[0].id
		index, _ := ground_index(&room, {9, 3})
		room.ground.pool[index] = 2
		room.enemies[0].recovery_pulses = 1
		lasso_test_throw(t, &room, id)
		lasso_test_spin(t, &room, 1, 1.0/60.0)
		testing.expect_value(t, room.enemies[0].position, grid.Position{9, 3})
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1))
		testing.expect(t, try_dodge_player(&room, .West))
		testing.expect(t, !room.lasso.active)
		released := false
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind == .Lasso_Released { released = event.target == enemy_entity(id) && event.to_position == grid.Position{9, 3} }
		}
		testing.expect(t, released)
		foe := &room.enemies[0]
		testing.expect_value(t, foe.position, grid.Position{9, 3})
		// Its fresh intent at once: a step toward the player, its two seconds
		// counted as any foe's newly planned.
		testing.expect_value(t, foe.intent.kind, Enemy_Intent_Kind.Move)
		testing.expect_value(t, foe.recovery_pulses, i32(0))
		testing.expect_value(t, foe.tactical_cooldown, tactical_enemy_intent_seconds(foe))
		testing.expect(t, abs(tactical_enemy_seconds(&room, foe)-(2-player.tactical.clock_fraction)) < 1e-4)
		poison, poisoned := status_for_entity(&room, enemy_entity(id), .Poison)
		testing.expect(t, poisoned && poison.potency == 2)
		testing.expect(t, validate_enemy_intents(&room))
		_, standing := enemy_index_at(&room, {9, 3})
		testing.expect(t, standing)
		// It acts when that intent is due, and plans on as any foe.
		destination := foe.intent.destination
		for _ in 0..<3 {
			tactical_tick(&room, 1, true, false)
			drain_tactical_test_pulse(t, &room)
		}
		testing.expect_value(t, room.enemies[0].position, destination)
		kind := room.enemies[0].intent.kind
		testing.expect(t, kind != .Recover && kind != .None)
	}
	{
		// The player dodges onto the cell under it: it falls beside him.
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {5, 6}, health = 60, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:], at = {3, 6})
		defer level.destroy(&data)
		defer destroy_room(&room)
		lasso_test_throw(t, &room, room.enemies[0].id)
		testing.expect_value(t, room.lasso.radius, i32(2))
		for _ in 0..<240 {
			if lasso_arc_cell(&room.lasso, room.lasso.arc) == (grid.Position{3, 4}) { break }
			lasso_test_spin(t, &room, 1.0/240.0, 1.0/240.0)
		}
		testing.expect_value(t, lasso_arc_cell(&room.lasso, room.lasso.arc), grid.Position{3, 4})
		testing.expect(t, try_dodge_player(&room, .North))
		testing.expect_value(t, player.position, grid.Position{3, 4})
		testing.expect(t, !room.lasso.active)
		landed := room.enemies[0].position
		testing.expect(t, landed != player.position && max(abs(landed.x-3), abs(landed.y-4)) == 1)
		testing.expect_value(t, landed, grid.Position{2, 3})
	}
	{
		// A brute's push, in the middle of its beat, lets go too; and so does the
		// defence prompt's dodge. Mid-beat the planner's work waits: the foe
		// holds a wait of no length, and the beat's end plans it afresh.
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 60, attack = 1}, {position = {6, 7}, health = 60, attack = 3, archetype = .Brute}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		defer level.destroy(&data)
		defer destroy_room(&room)
		target, brute := lasso_test_foe(&room, {9, 6}), lasso_test_foe(&room, {6, 7})
		lasso_test_hold(&room, brute)
		lasso_test_throw(t, &room, target)
		lasso_test_spin(t, &room, 0.3, 1.0/60.0)
		testing.expect(t, room.lasso.active)
		// The beat's end, as finish_combat_pulse plans: the released foe's fresh
		// intent, never a daze.
		beat_ends :: proc(t: ^testing.T, room: ^Room, id: u32) {
			index, found := enemy_index_by_id(room, id)
			if !testing.expect(t, found) { return }
			testing.expect_value(t, room.enemies[index].intent.kind, Enemy_Intent_Kind.Wait)
			testing.expect_value(t, room.enemies[index].tactical_cooldown, f32(0))
			testing.expect_value(t, room.enemies[index].recovery_pulses, i32(0))
			testing.expect(t, validate_enemy_intent(room, &room.enemies[index]))
			room.tactical_pulse = {}
			plan_enemy_intents(room)
			kind := room.enemies[index].intent.kind
			testing.expect(t, kind != .Wait && kind != .Recover && kind != .None)
			testing.expect_value(t, room.enemies[index].tactical_cooldown, tactical_enemy_intent_seconds(&room.enemies[index]))
			testing.expect(t, validate_enemy_intents(room))
		}
		brute_index, _ := enemy_index_by_id(&room, brute)
		intent := make_attack_intent(&room, {6, 7}, player.position, 3)
		intent.push = true
		room.enemies[brute_index].intent = intent
		room.tactical_pulse.pending, room.tactical_pulse.started = true, true
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, brute)
		testing.expect_value(t, player.position, grid.Position{6, 5})
		testing.expect(t, !room.lasso.active)
		beat_ends(t, &room, target)
		// Caught again, then let go by the prompt's dodge (offered mid-beat).
		player.tactical.dodge_recovery = 0
		player.deck.energy = player.deck.rules.max_energy
		lasso_test_throw(t, &room, target)
		testing.expect(t, room.lasso.active)
		room.tactical_pulse.pending, room.tactical_pulse.started = true, true
		room.qte = {kind = .Defense, selected = true, mode = .Dodge, enemy_id = brute, defenses = {.Dodge}, remaining = 1}
		testing.expect(t, resolve_qte(&room, true, .West))
		testing.expect(t, !room.lasso.active)
		beat_ends(t, &room, target)
	}
}

@(test)
test_lasso_ends_with_its_foe_and_clears_the_room :: proc(t: ^testing.T) {
	for endless in ([2]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 3, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		room.endless = endless
		id := room.enemies[0].id
		lasso_test_throw(t, &room, id)
		events: [dynamic]Lasso_Test_Event
		lasso_test_spin(t, &room, 10, 1.0/60.0, &events)
		// Three turns, and the rope goes slack: the room is cleared, unless it
		// never clears; the player is free again.
		testing.expect(t, !room.lasso.active && len(room.enemies) == 0)
		testing.expect_value(t, room.phase, Room_Phase.Combat if endless else Room_Phase.Loot)
		testing.expect(t, !tactical_player_busy(&room))
		dropped := false
		for seen in events {
			if seen.event.kind == .Loot_Dropped { dropped = true; testing.expect_value(t, seen.event.from_position, grid.Position{10, 6}) }
		}
		testing.expect(t, dropped)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
	// The player falls mid-spin: no rope is left out.
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 60, attack = 1}, {position = {2, 2}, health = 60, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_throw(t, &room, lasso_test_foe(&room, {9, 6}))
	lasso_test_spin(t, &room, 0.5, 1.0/60.0)
	player.health = 1
	blow := make_action(.Attack, enemy_entity(lasso_test_foe(&room, {2, 2})))
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 50)))
	testing.expect(t, resolve_action(&room, &blow).accepted)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	tactical_end_combat(&room)
	testing.expect(t, !room.lasso.active)
}

@(test)
test_lasso_spin_never_skips_and_keeps_its_batches :: proc(t: ^testing.T) {
	// The same hits, in the same order, and the same death, in frames of
	// 1/240 s or of half a second.
	Hit :: struct {target: Entity_Ref, amount: i32, cell: grid.Position}
	runs: [2][dynamic]Hit
	deaths: [2]int
	for dt, run in ([2]f64{1.0/240.0, 0.5}) {
		data: level.Level
		player: Player
		cells := [3]grid.Position{{6, 2}, {2, 7}, {7, 10}}
		room := lasso_test_bystanders(t, &data, &player, cells[:])
		lasso_test_throw(t, &room, lasso_test_foe(&room, {9, 6}), 1)
		events: [dynamic]Lasso_Test_Event
		lasso_test_spin(t, &room, 30, dt, &events)
		for seen in events {
			if seen.event.kind == .Lasso_Struck { append(&runs[run], Hit{seen.event.target, seen.event.amount, seen.event.to_position}) }
			if seen.event.kind == .Damaged && event_is_lasso_turn(seen.event) { deaths[run] += 1 }
		}
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
	testing.expect_value(t, len(runs[0]), 3)
	testing.expect_value(t, len(runs[1]), len(runs[0]))
	for hit, index in runs[0] {
		if index < len(runs[1]) { testing.expect_value(t, runs[1][index], hit) }
	}
	testing.expect(t, deaths[0] == deaths[1] && deaths[0] > 0)
	delete(runs[0])
	delete(runs[1])
	// Two minutes of the fastest spin at once: one turn's wound after another,
	// in batches that never fill their log.
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {9, 6}, health = 5000, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_throw(t, &room, room.enemies[0].id)
	room.lasso.pending = 120
	batches, wounds := 0, 0
	for tactical_lasso_due(&room) && batches < 100 {
		testing.expect(t, resolve_lasso_spin(&room))
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		testing.expect(t, room.recent_events.count <= MAX_GAME_EVENTS)
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind == .Damaged && event_is_lasso_turn(event) { wounds += 1 }
		}
		batches += 1
	}
	testing.expect(t, batches > 1)
	testing.expect_value(t, i32(wounds), room.lasso.turns)
	testing.expect(t, room.lasso.pending <= LASSO_EPSILON)
	testing.expect_value(t, lasso_test_health(&room, room.enemies[0].id), 5000-room.lasso.turns)
}
