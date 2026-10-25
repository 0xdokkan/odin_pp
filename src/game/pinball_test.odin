package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// The Pinball from the hand at the foe `id`, at `upgrade`, on the tick when
// `critical`; its strike's cast run out unless `keep_cast`.
pinball_test_strike :: proc(t: ^testing.T, room: ^Room, id: u32, upgrade := i32(0), critical := false, keep_cast := false) -> Card_Play_Report {
	card := rework_hand_card(t, room, .Pinball)
	if upgrade > 0 {
		room.player.deck.hand[0].upgrade_level = upgrade
		for &owned in room.player.deck.owned[:room.player.deck.owned_count] {
			if owned.id == card.id { owned.upgrade_level = upgrade }
		}
	}
	room.player.deck.energy = room.player.deck.rules.max_energy
	room.player.tactical.critical_next = critical
	play := play_card(room, card.id, entity_target(enemy_entity(id)))
	room.player.tactical.critical_next = false
	if !keep_cast && tactical_is_casting(room) { tactical_tick(room, room.player.tactical.cast_remaining, true, false) }
	return play
}

// The ball sent along `heading` from where it stands (the launch's turn is
// the room stream's; a test picks its own line).
pinball_test_aim :: proc(room: ^Room, heading: Pinball_Vec) {
	s := &room.pinball
	s.origin = pinball_position(s)
	s.before += s.run/PINBALL_SPEED
	s.run = 0
	s.heading = heading/pinball_length(heading)
}

Pinball_Test_Event :: struct {
	event: Game_Event,
	// The ball's world seconds rolled by the end of the batch that brought it.
	at: f64,
}

// Rolls the ball on `seconds` of world time in frames of `dt`, as the
// controller runs one: the clock, its beats, then the roll. Returns the world
// seconds given to the ball; it stops once the ball is gone. Each frame the
// ball's disc is checked clear of every solid cell (no wall rolled through).
pinball_test_roll :: proc(t: ^testing.T, room: ^Room, seconds, dt: f64, events: ^[dynamic]Pinball_Test_Event = nil) -> (rolled: f64) {
	for guard := 0; rolled < seconds-1e-9 && room.pinball.active && room.phase == .Combat && guard < 400_000; guard += 1 {
		before := room.pinball.pending
		tactical_tick(room, f32(min(dt, seconds-rolled)), true, false)
		rolled += room.pinball.pending-before
		drain_tactical_test_pulse(t, room)
		for tactical_pinball_due(room) {
			testing.expect(t, resolve_pinball_roll(room))
			testing.expect_value(t, room.recent_events.dropped_count, 0)
			if events != nil {
				for event in room.recent_events.events[:room.recent_events.count] { append(events, Pinball_Test_Event{event, rolled}) }
			}
		}
		if !room.pinball.active { break }
		p := pinball_position(&room.pinball)
		for dy in -1..=1 {
			for dx in -1..=1 {
				cell := grid.offset(room.pinball.cell, dx, dy)
				if !lasso_cell_is_solid(room, cell) { continue }
				closest := Pinball_Vec{clamp(p.x, f64(cell.x)-0.5, f64(cell.x)+0.5), clamp(p.y, f64(cell.y)-0.5, f64(cell.y)+0.5)}
				testing.expectf(t, pinball_length(p-closest) >= PINBALL_RADIUS-1e-6, "the ball at %v sinks into %v", p, cell)
			}
		}
		testing.expect(t, abs(pinball_length(room.pinball.heading)-1) < 1e-9)
	}
	return
}

@(test)
test_pinball_card_is_a_rare_tactical_ball_with_five_upgrades :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	definition, found := card_definition_by_id(.Pinball)
	testing.expect(t, found && definition.name == "Pinball")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Opponent)
	testing.expect_value(t, definition.targeting.cast_range, Targeting_Range{.Chebyshev, 1, 1})
	testing.expect_value(t, definition.targeting.shape, Target_Shape.Single)
	testing.expect_value(t, tactical_card_time_cost(.Pinball), f32(2))
	testing.expect_value(t, card_max_upgrade_level(.Pinball), i32(5))
	testing.expect_value(t, card_dice_count(.Pinball), 0)
	for upgrade in i32(0)..=5 {
		card := Card_Instance{id = 1, definition_id = .Pinball, upgrade_level = upgrade}
		testing.expect_value(t, card_can_upgrade(card), upgrade < 5)
		testing.expect_value(t, card_effect_amount(definition.effects[0], upgrade), 2+upgrade)
	}
	testing.expect(t, !validate_card_instance({id = 1, definition_id = .Pinball, upgrade_level = 6}))
	node := Run_Node{kind = .Combat, depth = 4}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	// On the tick, the value is one higher.
	room: Room
	player: Player
	room.player = &player
	player.tactical.critical_card = true
	action := make_action(.Card, PLAYER_ENTITY, entity_target(enemy_entity(1)), .Opponent)
	testing.expect(t, add_effect(&action, pinball_effect(enemy_entity(1), 4)))
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(5))
}

@(test)
test_pinball_takes_one_foe_beside_the_player_never_the_heavy :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {x = 7, y = 6}, health = 20, attack = 1},
		{position = {x = 5, y = 5}, health = 20, attack = 1},
		{position = {x = 8, y = 6}, health = 20, attack = 1},
		{position = {x = 6, y = 7}, health = 40, attack = 1, archetype = .Custodian},
		{position = {x = 5, y = 7}, health = 40, attack = 1, archetype = .Demolitionist},
	}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	for enemy in room.enemies { lasso_test_hold(&room, enemy.id) }
	card := rework_hand_card(t, &room, .Pinball)
	definition, _ := card_definition_by_id(.Pinball)
	aim :: proc(room: ^Room, card: Card_Instance, definition: Card_Definition, cell: grid.Position) -> Card_Compile_Error {
		return evaluate_card_targeting(room, card, card_target_request_at(definition, cell)).error
	}
	// Beside him, the diagonals too; two cells off, out of reach.
	testing.expect_value(t, aim(&room, card, definition, {x = 7, y = 6}), Card_Compile_Error.None)
	testing.expect_value(t, aim(&room, card, definition, {x = 5, y = 5}), Card_Compile_Error.None)
	testing.expect_value(t, aim(&room, card, definition, {x = 8, y = 6}), Card_Compile_Error.Target_Out_Of_Range)
	testing.expect_value(t, aim(&room, card, definition, {x = 7, y = 7}), Card_Compile_Error.Invalid_Target)
	// The miniboss and the boss are too heavy, and the drop takes neither.
	testing.expect_value(t, aim(&room, card, definition, {x = 6, y = 7}), Card_Compile_Error.Target_Too_Heavy)
	testing.expect_value(t, aim(&room, card, definition, {x = 5, y = 7}), Card_Compile_Error.Target_Too_Heavy)
	_, takes := card_drop_target(&room, card, {x = 6, y = 7})
	testing.expect(t, !takes)
	// A closed corner hides the diagonal.
	cover := [?]grid.Position{{x = 5, y = 6}, {x = 6, y = 5}}
	walled_data: level.Level
	walled_player: Player
	walled := lasso_test_room(t, &walled_data, &walled_player, spawns[1:2], obstacles = cover[:])
	walled_card := rework_hand_card(t, &walled, .Pinball)
	testing.expect_value(t, aim(&walled, walled_card, definition, {x = 5, y = 5}), Card_Compile_Error.Target_Blocked)
	destroy_room(&walled)
	level.destroy(&walled_data)
	// One ball at a time, and never the ball itself.
	east := lasso_test_foe(&room, {x = 7, y = 6})
	play := pinball_test_strike(t, &room, east)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, pinball_target_error(&room, entity_target(enemy_entity(lasso_test_foe(&room, {x = 5, y = 5})))), Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, pinball_target_error(&room, entity_target(enemy_entity(east))), Card_Compile_Error.Invalid_Target)
}

@(test)
test_pinball_strike_freezes_like_a_cast_then_rolls_on_world_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}, {position = {x = 2, y = 2}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := lasso_test_foe(&room, {x = 7, y = 6})
	lasso_test_hold(&room, lasso_test_foe(&room, {x = 2, y = 2}))
	_, _ = apply_status(&room, enemy_entity(id), .Poison, 3, 0)
	_, _ = apply_status(&room, enemy_entity(id), .Burn, 2, 0)
	play := pinball_test_strike(t, &room, id, keep_cast = true)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, player.deck.rules.max_energy-3)
	testing.expect(t, tactical_is_casting(&room) && room.pinball.active && enemy_is_pinball(&room, id))
	made, launched, removed := false, false, 0
	for event in room.recent_events.events[:room.recent_events.count] {
		#partial switch event.kind {
		case .Pinball_Made: made = event.target == enemy_entity(id) && event.amount == 2 && event.to_position == grid.Position{x = 7, y = 6}
		case .Pinball_Launched:
			launched = event.from_position == grid.Position{x = 6, y = 6} && event.to_position == grid.Position{x = 7, y = 6}
			testing.expect(t, abs(event.duration) >= PINBALL_MIN_TURN && abs(event.duration) <= PINBALL_MAX_TURN)
		case .Status_Removed: if event.target == enemy_entity(id) { removed += 1 }
		}
	}
	testing.expect(t, made && launched && removed == 2)
	// Struck east, turned 15 to 35 degrees off it.
	turn := room.pinball.turn
	angle := f64(turn)*math.PI/180
	testing.expect(t, abs(room.pinball.heading.x-math.cos(angle)) < 1e-12 && abs(room.pinball.heading.y-math.sin(angle)) < 1e-12)
	// The ball is out of the world: no cell, no intent, no status, nothing reaches it.
	index, _ := enemy_index_by_id(&room, id)
	testing.expect_value(t, room.enemies[index].statuses.count, 0)
	testing.expect_value(t, room.enemies[index].intent.kind, Enemy_Intent_Kind.None)
	_, standing := enemy_index_at(&room, {x = 7, y = 6})
	testing.expect(t, !standing)
	testing.expect(t, !can_apply_status(&room, enemy_entity(id), .Poison))
	testing.expect(t, !effect_is_valid(&room, damage_effect(enemy_entity(id), 5)))
	testing.expect(t, !player_arrow_target_is_valid(&room, enemy_entity(id)))
	testing.expect(t, validate_enemy_intents(&room))
	// The strike is a cast: the world, and the ball, stand still through it.
	fraction := player.tactical.clock_fraction
	tactical_tick(&room, 1, true, false)
	tactical_tick(&room, 1, true, false)
	testing.expect(t, !tactical_is_casting(&room))
	testing.expect(t, player.tactical.clock_fraction == fraction && room.pinball.pending == 0 && room.pinball.run == 0)
	// Then the player is free: a step, a card, while the ball rolls.
	testing.expect(t, !tactical_player_busy(&room) && tactical_allows_action(&room) && tactical_allows_cards(&room))
	// Half a second of the world's time: 3.5 cells along its line, before any wall.
	rolled := pinball_test_roll(t, &room, 0.5, 1.0/60.0)
	testing.expect(t, abs(rolled-0.5) < 1e-4)
	p := pinball_position(&room.pinball)
	testing.expect(t, abs(p.x-(7+3.5*math.cos(angle))) < 1e-3 && abs(p.y-(6+3.5*math.sin(angle))) < 1e-3)
	testing.expect_value(t, room.enemies[index].position, room.pinball.cell)
	testing.expect_value(t, room.pinball.cell, grid.Position{x = int(math.round(p.x)), y = int(math.round(p.y))})
	testing.expect_value(t, lasso_test_health(&room, id), i32(30))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
}

@(test)
test_pinball_bounces_off_walls_and_every_touch_resets_its_value :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := room.enemies[0].id
	pinball_test_strike(t, &room, id)
	pinball_test_aim(&room, {0.6, 0.8})
	room.pinball.value = 7
	events: [dynamic]Pinball_Test_Event
	defer delete(events)
	pinball_test_roll(t, &room, 3, 1.0/240.0, &events)
	bounces: [dynamic]Pinball_Test_Event
	defer delete(bounces)
	for seen in events { if seen.event.kind == .Pinball_Bounced { append(&bounces, seen) } }
	// The south wall first (6.3125 cells on), then the east one a little after
	// (0.4375), then the north one (12.1875): each bounce at the disc's edge.
	testing.expect_value(t, len(bounces), 3)
	if len(bounces) >= 3 {
		testing.expect(t, bounces[0].event.to_position.y == 12 && bounces[0].event.duration == 7 && bounces[0].event.amount == 2)
		testing.expect(t, bounces[1].event.to_position.x == 12 && bounces[1].event.duration == 2)
		testing.expect(t, bounces[2].event.to_position.y == 0)
		testing.expect(t, abs(bounces[0].at-6.3125/7) < 1.0/240.0+1e-6)
		testing.expect(t, abs(bounces[2].at-18.9375/7) < 1.0/240.0+1e-6)
	}
	// Off the north wall at (3.7375, 0.95), on south-west for the rest of the
	// three seconds: 2.0625 cells, to (2.5, 2.6).
	p := pinball_position(&room.pinball)
	testing.expect(t, abs(p.x-2.5) < 1e-4 && abs(p.y-2.6) < 1e-4)
	testing.expect_value(t, room.pinball.value, i32(2))
	testing.expect(t, room.pinball.bounces >= 3)
}

@(test)
test_pinball_strikes_foes_knocks_them_away_and_counts_up :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}, {position = {x = 9, y = 6}, health = 40, attack = 1}, {position = {x = 4, y = 6}, health = 40, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	ball, east, west := lasso_test_foe(&room, {x = 7, y = 6}), lasso_test_foe(&room, {x = 9, y = 6}), lasso_test_foe(&room, {x = 4, y = 6})
	lasso_test_hold(&room, east)
	lasso_test_hold(&room, west)
	pinball_test_strike(t, &room, ball)
	// Straight east: it meets the foe there, bounces back west over the
	// player, meets the other one, and so on, the value climbing: no wall is
	// touched while they stand between.
	pinball_test_aim(&room, {1, 0})
	events: [dynamic]Pinball_Test_Event
	defer delete(events)
	pinball_test_roll(t, &room, 5, 1.0/240.0, &events)
	bumps: [dynamic]Game_Event
	defer delete(bumps)
	for seen in events {
		if seen.event.kind == .Pinball_Bumped { append(&bumps, seen.event) }
		testing.expect(t, seen.event.kind != .Pinball_Bounced || len(bumps) >= 6)
	}
	expected := [6]struct{target: u32, amount: i32, cell: grid.Position}{
		{east, 2, {x = 9, y = 6}}, {west, 3, {x = 4, y = 6}}, {east, 4, {x = 10, y = 6}}, {west, 5, {x = 3, y = 6}}, {east, 6, {x = 11, y = 6}}, {west, 7, {x = 2, y = 6}},
	}
	testing.expect(t, len(bumps) >= len(expected))
	for want, index in expected {
		if index >= len(bumps) { break }
		testing.expect_value(t, bumps[index].target, enemy_entity(want.target))
		testing.expect_value(t, bumps[index].amount, want.amount)
		testing.expect_value(t, bumps[index].to_position, want.cell)
	}
	// Each struck foe took the value and was knocked a cell away from the ball;
	// against the wall it stays.
	testing.expect_value(t, lasso_test_cell(&room, east), grid.Position{x = 11, y = 6})
	testing.expect(t, lasso_test_health(&room, east) < 40-2-4-6+1)
	wounds := 0
	for seen in events {
		if seen.event.kind == .Damaged && seen.event.source == PLAYER_ENTITY && event_is_pinball(seen.event) { wounds += 1 }
		testing.expect(t, seen.event.kind != .Damaged || !event_is_lasso(seen.event))
	}
	testing.expect(t, wounds >= 6)
	testing.expect_value(t, lasso_test_health(&room, ball), i32(30))
}

@(test)
test_pinball_bursts_after_twenty_seconds_and_its_foe_falls :: proc(t: ^testing.T) {
	for endless in ([2]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		room.endless = endless
		id := room.enemies[0].id
		pinball_test_strike(t, &room, id)
		events: [dynamic]Pinball_Test_Event
		rolled := pinball_test_roll(t, &room, 25, 1.0/60.0, &events)
		burst, defeated, dropped := false, false, false
		for seen in events {
			#partial switch seen.event.kind {
			case .Pinball_Burst: burst = seen.event.target == enemy_entity(id)
			case .Entity_Defeated: defeated = defeated || seen.event.target == enemy_entity(id)
			case .Loot_Dropped: dropped = true
			}
		}
		testing.expect(t, burst && defeated && dropped)
		testing.expect(t, rolled >= PINBALL_SECONDS-1e-6 && rolled < PINBALL_SECONDS+1.0/60.0+1e-6)
		testing.expect(t, !room.pinball.active && len(room.enemies) == 0)
		testing.expect_value(t, room.phase, Room_Phase.Combat if endless else Room_Phase.Loot)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_pinball_roll_is_the_same_at_any_frame_rate :: proc(t: ^testing.T) {
	Seen :: struct {kind: Game_Event_Kind, target: Entity_Ref, amount: i32, cell: grid.Position}
	runs: [2][dynamic]Seen
	ends: [2]Pinball_Vec
	for dt, run in ([2]f64{1.0/240.0, 0.5}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}, {position = {x = 9, y = 3}, health = 60, attack = 1}, {position = {x = 3, y = 9}, health = 60, attack = 1}}
		cover := [?]grid.Position{{x = 4, y = 3}, {x = 9, y = 9}, {x = 2, y = 6}}
		room := lasso_test_room(t, &data, &player, spawns[:], obstacles = cover[:])
		for enemy in room.enemies { if enemy.position != (grid.Position{x = 7, y = 6}) { lasso_test_hold(&room, enemy.id) } }
		pinball_test_strike(t, &room, lasso_test_foe(&room, {x = 7, y = 6}))
		pinball_test_aim(&room, {0.8, -0.6})
		events: [dynamic]Pinball_Test_Event
		pinball_test_roll(t, &room, 12, dt, &events)
		for seen in events {
			if seen.event.kind == .Pinball_Bounced || seen.event.kind == .Pinball_Bumped {
				append(&runs[run], Seen{seen.event.kind, seen.event.target, seen.event.amount, seen.event.to_position})
			}
		}
		ends[run] = pinball_position(&room.pinball)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
	testing.expect(t, len(runs[0]) > 10)
	testing.expect_value(t, len(runs[1]), len(runs[0]))
	for seen, index in runs[0] {
		if index < len(runs[1]) { testing.expect_value(t, runs[1][index], seen) }
	}
	testing.expect(t, pinball_length(ends[0]-ends[1]) < 1e-9)
	delete(runs[0])
	delete(runs[1])
}

@(test)
test_pinball_ball_is_out_of_every_reach :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}, {position = {x = 3, y = 3}, health = 30, attack = 1, archetype = .Custodian}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := lasso_test_foe(&room, {x = 7, y = 6})
	custodian := lasso_test_foe(&room, {x = 3, y = 3})
	pinball_test_strike(t, &room, id)
	// A coil square round the ball's cell: its discharge would strike only the
	// ball, and so strikes nothing (and asks nothing of it).
	log: Event_Log
	cell := room.pinball.cell
	for offset in ([4]grid.Position{{x = -1, y = -1}, {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}}) {
		_ = deploy_board_device(&room, .Tesla_Coil, add_position(cell, offset), 8, 0, &log)
	}
	_ = activate_board_devices(&room)
	testing.expect_value(t, lasso_test_health(&room, id), i32(30))
	// The Custodian never takes it for an ally to guard.
	custodian_index, _ := enemy_index_by_id(&room, custodian)
	room.enemies[custodian_index].recovery_pulses = 0
	room.enemies[custodian_index].intent, room.enemies[custodian_index].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	intent := room.enemies[custodian_index].intent
	testing.expect(t, intent.kind != .Protect || intent.protected_ally != enemy_entity(id))
	testing.expect(t, validate_enemy_intents(&room))
	// A window's end: nothing to bite, nothing to catch.
	burns: Pulse_Report
	tick_combatants(&room, &burns, burn_status)
	grow_ground_fires(&room, &burns)
	testing.expect_value(t, lasso_test_health(&room, id), i32(30))
	// F7 in the lab: the ball falls with the rest.
	room.endless = true
	_, cleared := sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared && len(room.enemies) == 0 && !room.pinball.active)
}
