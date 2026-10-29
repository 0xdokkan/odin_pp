package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// A walled 13x13 room, the player in its middle (6, 6) with 100 health, the
// bare rules (DEFAULT_TACTICAL_CONFIG) at `vision`, with `spawns`, cover and
// objects.
first_person_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn,
	obstacles: []grid.Position = nil, objects: []Grid_Object_Spawn = nil, vision := 0, walls: []grid.Position = nil, fences: []grid.Position = nil) -> Room {
	rows: [13]string
	cells: [13][13]u8
	for y in 0..<13 {
		for x in 0..<13 { cells[y][x] = '#' if x == 0 || y == 0 || x == 12 || y == 12 else '.' }
	}
	for wall in walls { cells[wall.y][wall.x] = '#' }
	for fence in fences { cells[fence.y][fence.x] = '=' }
	cells[6][6] = '@'
	cells[11][11] = '>'
	for y in 0..<13 { rows[y] = string(cells[y][:]) }
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	config := DEFAULT_TACTICAL_CONFIG
	config.vision_size = vision
	testing.expect(t, configure_tactical(player, config))
	room, ok := create_room(data, player, {enemies = spawns, obstacles = obstacles, objects = objects})
	testing.expect(t, ok)
	return room
}

// The card from the hand (hand[0] turned into it), at `upgrade`, on the tick
// when `critical`.
first_person_test_play :: proc(t: ^testing.T, room: ^Room, upgrade := i32(0), critical := false) -> Card_Play_Report {
	card := rework_hand_card(t, room, .First_Person)
	if upgrade > 0 {
		room.player.deck.hand[0].upgrade_level = upgrade
		for &owned in room.player.deck.owned[:room.player.deck.owned_count] {
			if owned.id == card.id { owned.upgrade_level = upgrade }
		}
	}
	room.player.deck.energy = room.player.deck.rules.max_energy
	room.player.tactical.critical_next = critical
	play := play_card(room, card.id, entity_target(PLAYER_ENTITY))
	room.player.tactical.critical_next = false
	return play
}

// Holds the trigger for `seconds` of world time in frames of `dt`, as the
// controller runs one: the clock, then the trigger read and the shots due.
// Returns the shots fired.
first_person_test_fire :: proc(room: ^Room, seconds, dt: f32, aim: First_Person_Aim) -> (shots: int) {
	elapsed := f32(0)
	for elapsed < seconds-FIRST_PERSON_EPSILON {
		step := min(dt, seconds-elapsed)
		tactical_first_person_tick(room, step)
		elapsed += step
		first_person_set_trigger(room, true)
		for first_person_fire_due(room) {
			_, fired := first_person_fire(room, aim)
			if !fired { break }
			shots += 1
		}
	}
	return
}

FIRST_PERSON_TEST_NORTH :: First_Person_Aim{yaw = -math.PI/2}

@(test)
test_first_person_card_is_a_rare_tactical_self_card :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	definition, found := card_definition_by_id(.First_Person)
	testing.expect(t, found && definition.name == "First Person Shooter")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
	testing.expect(t, !card_requires_spatial_target(definition))
	testing.expect_value(t, tactical_card_time_cost(.First_Person), f32(0))
	testing.expect_value(t, card_max_upgrade_level(.First_Person), FIRST_PERSON_MAX_UPGRADE_LEVEL)
	testing.expect_value(t, card_dice_count(.First_Person), 0)
	testing.expect(t, card_effect_template_is_valid(&definition, definition.effects[0]))
	// Twenty seconds, two more each level, five levels: thirty at the top.
	for upgrade in i32(0)..=5 {
		card := Card_Instance{id = 1, definition_id = .First_Person, upgrade_level = upgrade}
		testing.expect_value(t, card_can_upgrade(card), upgrade < 5)
		testing.expect_value(t, card_effect_amount(definition.effects[0], upgrade), 20+2*upgrade)
	}
	testing.expect(t, !validate_card_instance({id = 1, definition_id = .First_Person, upgrade_level = 6}))
	// On the tick, two seconds more.
	room: Room
	player: Player
	room.player = &player
	player.tactical.critical_card = true
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, first_person_effect(20)))
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(22))
	// Offered to tactical runs only, rewards and wares alike.
	node := Run_Node{kind = .Combat, depth = 4}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	offered := false
	for seed in u64(1)..=400 {
		random := seed
		choices: [3]Card_Id
		testing.expect(t, generate_weighted_card_choices(&random, &node, choices[:]))
		for id in choices { offered = offered || id == .First_Person }
	}
	testing.expect(t, offered)

}

@(test)
test_first_person_begins_on_self_and_locks_the_cards :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 40, attack = 1}, {position = {x = 6, y = 2}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	for enemy in room.enemies { lasso_test_hold(&room, enemy.id) }
	// The Scopa pair in hand: the ranch could open now.
	for index in 1..=2 {
		card := &player.deck.hand[index]
		card.definition_id = .Sei_Denari if index == 1 else .Sette_Denari
		for &owned in player.deck.owned[:player.deck.owned_count] {
			if owned.id == card.id { owned.definition_id = card.definition_id }
		}
	}
	testing.expect(t, validate_deck_state(&player.deck) && western_ranch_can_start(&room))
	window, decisions, hand := player.tactical.remaining, player.tactical.metrics.decisions, player.deck.hand_count
	play := first_person_test_play(t, &room)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, tactical_first_person_active(&room))
	testing.expect_value(t, room.first_person.duration, f32(20))
	testing.expect_value(t, room.first_person.remaining, f32(20))
	// Three energy, no window time, no cast; a decision of its own, its
	// replacement drawn now.
	testing.expect_value(t, play.energy_after, play.energy_before-3)
	testing.expect_value(t, player.tactical.remaining, window)
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect_value(t, player.tactical.metrics.decisions, decisions+1)
	testing.expect_value(t, player.deck.hand_count, hand)
	begun := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind != .First_Person_Begun { continue }
		begun = true
		testing.expect(t, event.source == PLAYER_ENTITY && event.target == PLAYER_ENTITY && event.card_definition == .First_Person)
		testing.expect(t, event.from_position == player.position && event.to_position == player.position && event.duration == 20)
	}
	testing.expect(t, begun)
	// No card, refocus, arrow, ability or ranch now; no second view.
	testing.expect(t, !tactical_allows_cards(&room))
	other := player.deck.hand[1]
	testing.expect_value(t, play_card(&room, other.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Invalid_Phase)
	testing.expect_value(t, refocus_player_hand(&room).result, Refocus_Result.Invalid_Phase)
	applied, _ := apply_status(&room, PLAYER_ENTITY, .Arrows, 3, 0)
	testing.expect(t, applied)
	testing.expect_value(t, shoot_player_arrow(&room, enemy_entity(room.enemies[1].id)), Action_Result.Invalid_Phase)
	testing.expect_value(t, use_player_ability(&room, .Thorn_Coat), Action_Result.Invalid_Phase)
	testing.expect(t, !western_ranch_can_start(&room))
	testing.expect(t, !tactical_can_begin_first_person(&room) && !tactical_can_begin_shadow(&room))
	// He still waits, steps, bumps and dodges as ever.
	testing.expect_value(t, wait_player_turn(&room), Action_Result.None)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	struck := lasso_test_health(&room, room.enemies[0].id)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Attacked)
	testing.expect(t, lasso_test_health(&room, room.enemies[0].id) < struck)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, try_dodge_player(&room, .West))
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, tactical_first_person_active(&room))
	// Where actions do not last their cost, each one's seconds were the world's.
	// Two walks (0.8 each), a wait, a bump and a dodge spend 4.6 seconds.
	testing.expect(t, abs(room.first_person.remaining-15.4) < 0.001)
	// Nothing else begins it: not inside the shadow, nor with a foe on the rope.
	room.first_person = {}
	room.lasso.active = true
	testing.expect(t, !tactical_can_begin_first_person(&room))
	room.lasso.active = false
	testing.expect(t, tactical_begin_shadow(&room, 4))
	testing.expect(t, !tactical_can_begin_first_person(&room))
}

@(test)
test_first_person_clock_runs_on_the_worlds_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 40, attack = 1}, {position = {x = 2, y = 2}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	for enemy in room.enemies { lasso_test_hold(&room, enemy.id) }
	testing.expect_value(t, first_person_test_play(t, &room).result, Card_Play_Result.Played)
	tactical_tick(&room, 0.5, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, abs(room.first_person.remaining-19.5) < 0.001)
	// A defence prompt and a beat resolving hold it with the world.
	room.qte.kind = .Defense
	tactical_tick(&room, 0.5, true, false)
	room.qte = {}
	room.tactical_pulse.pending = true
	tactical_tick(&room, 0.5, true, false)
	room.tactical_pulse.pending = false
	testing.expect(t, abs(room.first_person.remaining-19.5) < 0.001)
	// The window's end: recovery's second, and a stun's, run it on.
	player.tactical.remaining = 0.25
	tactical_tick(&room, 0.25, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, first_person_test_recovering(&room))
	tactical_tick(&room, 0.5, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, abs(room.first_person.remaining-18.75) < 0.001)
	tactical_tick(&room, 0.5, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, abs(room.first_person.remaining-18.25) < 0.001 && player.tactical.phase == .Decision)
	player.tactical.phase, player.tactical.remaining, player.tactical.stun_duration = .Stunned, 1, 1
	tactical_tick(&room, 0.5, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, abs(room.first_person.remaining-17.75) < 0.001)
	player.tactical.phase, player.tactical.remaining = .Decision, 20
	// Its last second ends it: no trigger held, the cards are back.
	first_person_set_trigger(&room, true)
	for _ in 0..<40 {
		tactical_tick(&room, 0.5, true, false)
		drain_tactical_test_pulse(t, &room)
		if !room.first_person.active { break }
	}
	testing.expect(t, !room.first_person.active && !room.first_person.trigger && room.first_person.remaining == 0)
	testing.expect(t, tactical_allows_cards(&room))
	// The room cleared ends it, and so does the player's fall.
	testing.expect_value(t, first_person_test_play(t, &room).result, Card_Play_Result.Played)
	testing.expect(t, room.first_person.active)
	room.endless = true
	_, cleared := sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared && room.phase == .Loot && !room.first_person.active)
	destroy_room(&room)
	level.destroy(&data)
	room = first_person_test_room(t, &data, &player, spawns[:])
	testing.expect(t, !room.first_person.active && room.first_person.shots == 0)
	testing.expect_value(t, first_person_test_play(t, &room).result, Card_Play_Result.Played)
	blow := make_action(.Attack, enemy_entity(room.enemies[0].id), entity_target(PLAYER_ENTITY))
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 500)))
	testing.expect(t, resolve_action(&room, &blow).accepted && room.phase == .Defeat)
	tactical_end_combat(&room)
	testing.expect(t, !room.first_person.active && !tactical_first_person_active(&room))
}

first_person_test_recovering :: proc(room: ^Room) -> bool {
	return room.player.tactical.phase == .Recovery
}

@(test)
test_first_person_fires_six_shots_a_second_at_any_frame_rate :: proc(t: ^testing.T) {
	for dt in ([?]f32{1.0/30, 1.0/50, 1.0/60, 1.0/144, 1.0/165, 0.037}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 200, attack = 1}}
		room := first_person_test_room(t, &data, &player, spawns[:])
		lasso_test_hold(&room, room.enemies[0].id)
		testing.expect(t, tactical_begin_first_person(&room, 20))
		applied, _ := apply_status(&room, PLAYER_ENTITY, .Poison, 3, 0)
		testing.expect(t, applied)
		window := player.tactical.remaining
		shots := first_person_test_fire(&room, 1, dt, FIRST_PERSON_TEST_NORTH)
		testing.expectf(t, shots == 6, "%d shots in a second at dt %v", shots, dt)
		testing.expect_value(t, room.first_person.shots, i32(6))
		testing.expect_value(t, room.first_person.hits, i32(6))
		testing.expect_value(t, room.enemies[0].health, i32(200-6))
		testing.expect(t, abs(room.first_person.remaining-19) < 0.001)
		// No window time, and no action of his: his Veleno never bit.
		testing.expect_value(t, player.tactical.remaining, window)
		poison, _ := status_for_entity(&room, PLAYER_ENTITY, .Poison)
		testing.expect_value(t, poison.potency, i32(3))
		testing.expect_value(t, player.health, i32(100))
		destroy_room(&room)
		level.destroy(&data)
	}
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 200, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	testing.expect(t, tactical_begin_first_person(&room, 20))
	// Let go soon after a shot, pressed again: it still waits its turn. Let go
	// longer, nothing is banked: one shot, no burst.
	testing.expect_value(t, first_person_test_fire(&room, 0.05, 0.05, FIRST_PERSON_TEST_NORTH), 1)
	first_person_set_trigger(&room, false)
	tactical_first_person_tick(&room, 0.05)
	first_person_set_trigger(&room, true)
	testing.expect(t, room.first_person.cooldown > 0.05 && !first_person_fire_due(&room))
	first_person_set_trigger(&room, false)
	tactical_first_person_tick(&room, 3)
	before := room.first_person.shots
	testing.expect_value(t, first_person_test_fire(&room, 0.01, 0.01, FIRST_PERSON_TEST_NORTH), 1)
	testing.expect_value(t, room.first_person.shots, before+1)
	// A long frame carries one shot at most.
	tactical_first_person_tick(&room, 0.4)
	shots := 0
	for first_person_fire_due(&room) { _, _ = first_person_fire(&room, FIRST_PERSON_TEST_NORTH); shots += 1 }
	testing.expect_value(t, shots, 2)
	// Never during a defence prompt or a beat resolving.
	tactical_first_person_tick(&room, 1)
	room.qte.kind = .Defense
	testing.expect(t, !first_person_fire_due(&room))
	_, fired := first_person_fire(&room, FIRST_PERSON_TEST_NORTH)
	testing.expect(t, !fired)
	room.qte = {}
	room.tactical_pulse.pending = true
	testing.expect(t, !first_person_fire_due(&room))
	room.tactical_pulse.pending = false
	testing.expect(t, first_person_fire_due(&room))
}

@(test)
test_first_person_hitscan_stops_on_solids_and_takes_the_first_foe :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {x = 6, y = 3}, health = 20, attack = 1, archetype = .Chaser},
		{position = {x = 6, y = 2}, health = 20, attack = 1, archetype = .Brute},
		{position = {x = 9, y = 6}, health = 20, attack = 1, archetype = .Archer},
		{position = {x = 3, y = 9}, health = 20, attack = 1, archetype = .Demolitionist},
	}
	cover := [?]grid.Position{{x = 4, y = 6}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 6, y = 8}}, {kind = .Fire, position = {x = 9, y = 9}}, {kind = .Barrel, position = {x = 2, y = 4}}}
	room := first_person_test_room(t, &data, &player, spawns[:], cover[:], objects[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	from := player.position
	// North: the nearer foe takes it, on its card three cells away.
	shot := first_person_trace(&room, from, FIRST_PERSON_TEST_NORTH)
	testing.expect_value(t, shot.hit, First_Person_Hit.Foe)
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[0].id))
	testing.expect(t, abs(shot.point.z-3.5) < 0.001 && abs(shot.point.y-FIRST_PERSON_EYE_HEIGHT) < 0.001)
	testing.expect(t, abs(shot.origin.x-6.5) < 0.001 && abs(shot.origin.y-FIRST_PERSON_EYE_HEIGHT) < 0.001)
	// Up the ghoul's card, high on it; over its top (1.45) and into the
	// brute's behind it (1.82).
	shot = first_person_trace(&room, from, {yaw = -math.PI/2, pitch = 0.1})
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[0].id))
	shot = first_person_trace(&room, from, {yaw = -math.PI/2, pitch = 0.16})
	testing.expect_value(t, shot.hit, First_Person_Hit.Foe)
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[1].id))
	// East: the archer three cells off.
	shot = first_person_trace(&room, from, {yaw = 0})
	testing.expect_value(t, shot.hit, First_Person_Hit.Foe)
	testing.expect_value(t, shot.cell, grid.Position{x = 9, y = 6})
	// West: the cover two cells off stops it at its face.
	shot = first_person_trace(&room, from, {yaw = math.PI})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 4, y = 6})
	testing.expect(t, abs(shot.point.x-5) < 0.001)
	// South: the ice block, a blocking object, two cells off.
	shot = first_person_trace(&room, from, {yaw = math.PI/2})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 6, y = 8})
	// Down: the floor, 1.05/tan(0.5) cells away (the archer is farther).
	shot = first_person_trace(&room, from, {yaw = 0, pitch = -0.5})
	testing.expect_value(t, shot.hit, First_Person_Hit.Floor)
	testing.expect_value(t, shot.cell, grid.Position{x = 8, y = 6})
	testing.expect(t, abs(shot.point.x-(6.5+FIRST_PERSON_EYE_HEIGHT/math.tan(f32(0.5)))) < 0.001 && shot.point.y == 0)
	// The exact diagonal south-east goes over the fire (no blocker) to the
	// room's closed corner, stopped at the first of its two walls.
	shot = first_person_trace(&room, from, {yaw = math.PI/4})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 12, y = 11})
	// South-west, the boss (the Demolitionist) is hit as any foe.
	shot = first_person_trace(&room, from, {yaw = 3*math.PI/4})
	testing.expect_value(t, shot.hit, First_Person_Hit.Foe)
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[3].id))
	// A foe on the Lazzo's rope is no body: the shot goes on to the brute.
	room.lasso.active, room.lasso.enemy_id = true, room.enemies[0].id
	shot = first_person_trace(&room, from, FIRST_PERSON_TEST_NORTH)
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[1].id))
	room.lasso = {}
	// A barrel and a coil stop it too (from another cell, north to the barrel);
	// a shock floor does not, the shot goes on to the room's corner.
	shot = first_person_trace(&room, {x = 2, y = 6}, FIRST_PERSON_TEST_NORTH)
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 2, y = 4})
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Shock_Floor, {x = 7, y = 5}, 1, 1, &log))
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {x = 5, y = 5}, 4, 0, &log))
	shot = first_person_trace(&room, from, {yaw = -math.PI/4})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 12, y = 1})
	shot = first_person_trace(&room, from, {yaw = -3*math.PI/4})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 5, y = 5})
	// Out of his sight the shot is lost. With vision 7 the ghoul three cells
	// north is seen and struck; off the board (the rope's) it leaves the brute
	// four cells off, out of sight: nothing is struck.
	player.tactical.config.vision_size = 7
	shot = first_person_trace(&room, from, FIRST_PERSON_TEST_NORTH)
	testing.expect_value(t, shot.target, enemy_entity(room.enemies[0].id))
	room.lasso.active, room.lasso.enemy_id = true, room.enemies[0].id
	shot = first_person_trace(&room, from, FIRST_PERSON_TEST_NORTH)
	testing.expect_value(t, shot.hit, First_Person_Hit.None)
	testing.expect_value(t, shot.cell, grid.Position{x = 6, y = 2})
	room.lasso = {}
	shot = first_person_trace(&room, from, {yaw = math.PI/2})
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
}

// The aim from the eye `o` that crosses the card standing at `card`
// `lateral` to the left of its middle (looking at it) and `height` above
// its stand's floor.
first_person_test_aim_at :: proc(o, card: [2]f32, lateral, height: f32) -> First_Person_Aim {
	way := card-o
	dist := math.sqrt(way.x*way.x+way.y*way.y)
	turn := math.asin(lateral/dist)
	depth := math.sqrt(dist*dist-lateral*lateral)
	return {yaw = math.atan2(way.y, way.x)-turn, pitch = math.atan((height-FIRST_PERSON_EYE_HEIGHT)/depth)}
}

// A foe is its card: the shots meet its paper wherever the board draws it,
// as wide as the card is at each height (its claws far out, its head
// narrower, nothing over its top), also where the paper reaches over the
// cell beside the ray's own; a wall still stops a shot before a card's edge
// behind it. Each archetype's card is wider than the old column at its
// widest.
@(test)
test_first_person_shots_meet_the_whole_card :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 3}, health = 50, attack = 1, archetype = .Chaser}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	from := player.position
	o, ghoul := [2]f32{6.5, 6.5}, [2]f32{6.5, 3.5}
	Case :: struct {
		lateral, height: f32,
		hit: First_Person_Hit,
	}
	cases := [?]Case{
		// The claws, low and far out; the middle; the side of the head.
		{0.55, 0.2, .Foe}, {0.8, 0.35, .Foe}, {-0.8, 0.35, .Foe}, {0.95, 0.35, .Floor}, {0, 0.9, .Foe}, {0.3, 1.38, .Foe},
		{0.5, 1.38, .Solid}, {0, 1.5, .Solid},
	}
	for c in cases {
		shot := first_person_trace(&room, from, first_person_test_aim_at(o, ghoul, c.lateral, c.height))
		testing.expectf(t, shot.hit == c.hit, "%.2f left at %.2f: %v", c.lateral, c.height, shot.hit)
		if c.hit != .Foe { continue }
		testing.expect_value(t, shot.target, enemy_entity(room.enemies[0].id))
		testing.expect(t, abs(shot.point.y-c.height) < 0.002)
	}
	// From (5, 6) toward the ghoul's left claw the ray never leaves the cells
	// west of the ghoul's: the card reaches over to it. Cover on (5, 3) stops
	// the same shot at its near face, before the card's edge behind it.
	room.player.position = {x = 5, y = 6}
	claw := First_Person_Aim{yaw = math.atan2(f32(-3), f32(0.3)), pitch = math.atan((0.3-FIRST_PERSON_EYE_HEIGHT)/3)}
	beside := first_person_trace(&room, room.player.position, claw)
	testing.expect(t, beside.hit == .Foe && beside.target == enemy_entity(room.enemies[0].id) && beside.cell == grid.Position{x = 6, y = 3})
	testing.expect(t, beside.point.x > 5.7 && beside.point.x < 5.9)
	append(&room.obstacles, Obstacle{position = {x = 5, y = 3}})
	blocked := first_person_trace(&room, room.player.position, claw)
	testing.expect(t, blocked.hit == .Solid && blocked.cell == grid.Position{x = 5, y = 3} && abs(blocked.point.z-4) < 1e-3)
	// Every card at its widest is wider than the old column (0.34), and stands
	// as tall as its paper.
	for archetype in Enemy_Archetype {
		if archetype == .Count { continue }
		widest := f32(0)
		for knot in FIRST_PERSON_OUTLINES[archetype] { widest = max(widest, knot.y) }
		testing.expectf(t, widest > 0.6 && first_person_outline_top(archetype) > 1.4, "%v: %.2f wide, %.2f tall", archetype, widest,
			first_person_outline_top(archetype))
		testing.expect_value(t, first_person_outline_half_width(archetype, first_person_outline_top(archetype)+0.01), f32(0))
		testing.expect_value(t, first_person_outline_half_width(archetype, 0.01), f32(0))
	}
}

// Behind his eyes a shot leaves the eye where the view shows it, riding his
// glide from cell to cell (a dodge's two cells at most, and over open floor),
// and meets each foe's card where the board shows it, sliding from cell to
// cell or hopping off its stand; a card shown far from its cell stands on it.
// An aim the board did not frame leaves his cell's centre for the cards'
// cells.
@(test)
test_first_person_shots_leave_the_eye_the_view_shows :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 3}, health = 50, attack = 1, archetype = .Chaser}}
	cover := [?]grid.Position{{x = 8, y = 6}}
	room := first_person_test_room(t, &data, &player, spawns[:], cover[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	ghoul := room.enemies[0].id
	lasso_test_hold(&room, ghoul)
	from := player.position
	// Gliding east from (6, 6) to (7, 6): the eye already half way, the cell
	// his; the ray north from the eye still crosses the ghoul's card.
	room.player.position = {x = 7, y = 6}
	glide := First_Person_Aim{yaw = -math.PI/2, framed = true, eye = {6.8, 6.5}}
	shot := first_person_trace(&room, room.player.position, glide)
	testing.expect(t, shot.hit == .Foe && shot.target == enemy_entity(ghoul))
	testing.expect(t, abs(shot.origin.x-6.8) < 1e-4 && abs(shot.origin.z-6.5) < 1e-4 && abs(shot.point.z-3.5) < 1e-4)
	// Unframed, the shot leaves (7, 6): 1 to the right of the ghoul's middle,
	// past its shoulder.
	unframed := first_person_trace(&room, room.player.position, {yaw = -math.PI/2})
	testing.expect(t, unframed.hit == .Solid && abs(unframed.origin.x-7.5) < 1e-4)
	// An eye too far from his cell, or over the cover, is his cell's centre.
	for eye in ([2][2]f32{{4.4, 6.5}, {8.5, 6.5}}) {
		far := glide
		far.eye = eye
		testing.expect(t, abs(first_person_trace(&room, room.player.position, far).origin.x-7.5) < 1e-4)
	}
	room.player.position = from
	// The ghoul's step east: its cell (7, 3) at once, its card sliding there.
	room.enemies[0].position = {x = 7, y = 3}
	slide := First_Person_Aim{yaw = -math.PI/2, framed = true, eye = {6.5, 6.5}, card_count = 1}
	slide.cards[0] = {enemy_id = ghoul, at = {6.6, 3.5}}
	testing.expect_value(t, first_person_trace(&room, from, slide).target, enemy_entity(ghoul))
	testing.expect_value(t, first_person_trace(&room, from, {yaw = -math.PI/2}).hit, First_Person_Hit.Solid)
	// Done sliding, as the board shows it: past it; a card shown three cells
	// and more from its cell stands on its cell.
	slide.cards[0].at = {7.5, 3.5}
	testing.expect_value(t, first_person_trace(&room, from, slide).hit, First_Person_Hit.Solid)
	slide.cards[0].at = {3.5, 3.5}
	toward := slide
	toward.yaw = math.atan2(f32(-3), f32(-3))
	testing.expect(t, first_person_trace(&room, from, toward).hit != .Foe)
	// A card hopping half a cell off its stand: its feet over a low shot, its
	// head under a high one.
	slide.cards[0] = {enemy_id = ghoul, at = {6.5, 3.5}, lift = 0.5}
	low, high := slide, slide
	low.pitch = math.atan((0.3-FIRST_PERSON_EYE_HEIGHT)/3)
	high.pitch = math.atan((1.8-FIRST_PERSON_EYE_HEIGHT)/3)
	testing.expect(t, first_person_trace(&room, from, low).hit == .Floor && first_person_trace(&room, from, high).hit == .Foe)
	testing.expect(t, first_person_trace(&room, from, high).hit != first_person_trace(&room, from, {yaw = high.yaw, pitch = high.pitch}).hit)
}

@(test)
test_first_person_shot_is_the_players_normal_damage :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 3}, health = 1, attack = 1}, {position = {x = 9, y = 6}, health = 3, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	for enemy in room.enemies { lasso_test_hold(&room, enemy.id) }
	east := room.enemies[1].id
	testing.expect(t, tactical_begin_first_person(&room, 20))
	// A Shield takes it first.
	applied, _ := apply_status(&room, enemy_entity(east), .Shield, 2, 2)
	testing.expect(t, applied)
	first_person_set_trigger(&room, true)
	shot, fired := first_person_fire(&room, {yaw = 0})
	testing.expect(t, fired && shot.hit == .Foe && shot.number == 1 && shot.damage == 0)
	testing.expect_value(t, lasso_test_health(&room, east), i32(3))
	absorbed := false
	for event in room.recent_events.events[:room.recent_events.count] {
		absorbed = absorbed || event.kind == .Damage_Absorbed
		testing.expect(t, event_is_first_person_shot(event))
		testing.expect(t, !event_is_attack(event) && !event_is_lasso(event))
	}
	testing.expect(t, absorbed)
	testing.expect_value(t, room.first_person.trail[0].number, i32(1))
	// The wound: its own event, marked as the AK's.
	tactical_first_person_tick(&room, FIRST_PERSON_SHOT_SECONDS)
	shot, fired = first_person_fire(&room, {yaw = 0})
	tactical_first_person_tick(&room, FIRST_PERSON_SHOT_SECONDS)
	shot, fired = first_person_fire(&room, {yaw = 0})
	testing.expect(t, fired && shot.damage == 1)
	testing.expect_value(t, lasso_test_health(&room, east), i32(2))
	wounded := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Damaged && event.source == PLAYER_ENTITY && event.target == enemy_entity(east) {
			wounded = true
			testing.expect(t, event_is_first_person_shot(event) && !event.has_status_cause)
		}
	}
	testing.expect(t, wounded)
	// Into the floor: no event, a shot all the same.
	tactical_first_person_tick(&room, FIRST_PERSON_SHOT_SECONDS)
	shot, fired = first_person_fire(&room, {yaw = 0, pitch = -0.5})
	testing.expect(t, fired && shot.hit == .Floor && room.recent_events.count == 0)
	testing.expect_value(t, room.first_person.shots, i32(4))
	testing.expect_value(t, room.first_person.hits, i32(3))
	testing.expect_value(t, room.first_person.trail[3].hit, First_Person_Hit.Floor)
	// A 1-health foe falls, with its loot; the last one clears the room, which
	// ends the view.
	tactical_first_person_tick(&room, FIRST_PERSON_SHOT_SECONDS)
	shot, fired = first_person_fire(&room, FIRST_PERSON_TEST_NORTH)
	testing.expect(t, fired && shot.damage == 1 && len(room.enemies) == 1)
	defeated := false
	for event in room.recent_events.events[:room.recent_events.count] { defeated = defeated || event.kind == .Entity_Defeated }
	testing.expect(t, defeated && room.phase == .Combat)
	for _ in 0..<8 {
		tactical_first_person_tick(&room, FIRST_PERSON_SHOT_SECONDS)
		_, _ = first_person_fire(&room, {yaw = 0})
		if room.phase != .Combat { break }
	}
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect(t, !room.first_person.active && len(room.enemies) == 0)
	// The trail keeps the last eight shots by number.
	last := room.first_person.shots
	testing.expect_value(t, room.first_person.trail[(last-1)%FIRST_PERSON_TRAIL].number, last)
}

@(test)
test_first_person_keys_turn_with_the_view :: proc(t: ^testing.T) {
	testing.expect_value(t, first_person_key_directions(-math.PI/2), [4]Move_Direction{.North, .East, .South, .West})
	testing.expect_value(t, first_person_key_directions(0), [4]Move_Direction{.East, .South, .West, .North})
	testing.expect_value(t, first_person_key_directions(math.PI/2-0.3), [4]Move_Direction{.South, .West, .North, .East})
	testing.expect_value(t, first_person_key_directions(math.PI+0.7), [4]Move_Direction{.West, .North, .East, .South})
	testing.expect_value(t, first_person_key_directions(-math.PI+0.2), [4]Move_Direction{.West, .North, .East, .South})
	// Either side of a view between two ways.
	testing.expect_value(t, first_person_key_directions(-3*math.PI/4+0.01)[0], Move_Direction.North)
	testing.expect_value(t, first_person_key_directions(-3*math.PI/4-0.01)[0], Move_Direction.West)
	testing.expect_value(t, first_person_key_directions(math.PI/4+0.01)[0], Move_Direction.South)
	for direction in Move_Direction {
		testing.expect_value(t, first_person_key_directions(first_person_yaw(direction))[0], direction)
		testing.expect_value(t, first_person_key_directions(first_person_yaw(direction)+2*math.PI)[0], direction)
	}
	testing.expect_value(t, MOVEMENT_KEY_DIRECTIONS, [4]Move_Direction{.North, .East, .South, .West})
}
