package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// The Cannone, the Cannone laser, the Buco nero and the Dinosauro, with the
// Sanguinamento they bring (cannon.odin, black_hole.odin, dinosaur.odin).

arsenal_test_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> (count: int) {
	for event in log.events[:log.count] { if event.kind == kind { count += 1 } }
	return
}

arsenal_test_beat :: proc(room: ^Room) -> (pulse: Pulse_Report) {
	emplacement_beat(room, &pulse)
	ride_beat(room, &pulse)
	return
}

arsenal_test_play :: proc(t: ^testing.T, room: ^Room, id: Card_Id, target: Target, upgrade: i32 = 0) -> Card_Play_Report {
	card := ground_test_card(t, room, id, upgrade)
	return play_card(room, card.id, target)
}

@(test)
test_new_cards_are_valid_with_their_rarities_and_evolution :: proc(t: ^testing.T) {
	for id in ([4]Card_Id{.Cannon, .Laser_Cannon, .Black_Hole, .Dinosaur}) {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && validate_card_definition(&definition))
	}
	cannon, _ := card_definition_by_id(.Cannon)
	laser, _ := card_definition_by_id(.Laser_Cannon)
	hole, _ := card_definition_by_id(.Black_Hole)
	dino, _ := card_definition_by_id(.Dinosaur)
	testing.expect_value(t, cannon.name, "Cannone")
	testing.expect_value(t, cannon.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, cannon.cost, i32(2))
	testing.expect_value(t, cannon.evolves_to, Card_Id.Laser_Cannon)
	testing.expect_value(t, cannon.evolve_level, CANNON_EVOLVE_LEVEL)
	testing.expect(t, laser.evolution_only && laser.reward_weight == 0)
	testing.expect_value(t, hole.rarity, Card_Rarity.Rare)
	testing.expect_value(t, hole.cost, i32(3))
	testing.expect_value(t, dino.cost, i32(3))
	testing.expect_value(t, dino.dice_count, 1)
	node := Run_Node{kind = .Combat, depth = 2}
	testing.expect(t, card_offer_weight(cannon, &node) > 0 && card_offer_weight(hole, &node) > 0 && card_offer_weight(dino, &node) > 0)
	// The Cannone laser is never offered: only an upgrade makes it.
	testing.expect_value(t, card_offer_weight(laser, &node), u64(0))
	// The Dinosauro's die is a d4 at every level.
	for level in i32(0)..=MAX_DICE_UPGRADE_LEVEL { testing.expect_value(t, card_die_sides(.Dinosaur, level), i32(4)) }
}

@(test)
test_the_cannon_evolves_into_the_laser_at_its_second_upgrade :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_empty_deck(&deck, DEFAULT_DECK_RULES, 7))
	cannon, added := add_owned_card(&deck, .Cannon)
	testing.expect(t, added)
	testing.expect_value(t, upgrade_owned_card(&deck, cannon.id), Deck_Mutation_Result.Upgraded)
	index, _ := owned_card_index_by_id(&deck, cannon.id)
	testing.expect(t, deck.owned[index].definition_id == .Cannon && deck.owned[index].upgrade_level == 1)
	testing.expect_value(t, upgrade_owned_card(&deck, cannon.id), Deck_Mutation_Result.Upgraded)
	// The second upgrade makes it the laser, starting again from its own level 0.
	testing.expect(t, deck.owned[index].definition_id == .Laser_Cannon && deck.owned[index].upgrade_level == 0)
	testing.expect(t, validate_deck_state(&deck))
	for _ in 0..<LASER_MAX_UPGRADE_LEVEL { testing.expect_value(t, upgrade_owned_card(&deck, cannon.id), Deck_Mutation_Result.Upgraded) }
	testing.expect_value(t, upgrade_owned_card(&deck, cannon.id), Deck_Mutation_Result.Maximum_Upgrade)
	testing.expect_value(t, deck.owned[index].definition_id, Card_Id.Laser_Cannon)
}

@(test)
test_cannon_is_set_on_a_free_cell_aimed_and_blocks_the_way :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {10, 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	// East of the player: its way is east (from the player to its cell).
	play := arsenal_test_play(t, &room, .Cannon, cell_target({7, 5}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.energy_before-play.energy_after, i32(2))
	testing.expect_value(t, len(room.objects), 1)
	cannon := room.objects[0]
	testing.expect(t, cannon.kind == .Cannon && cannon.position == grid.Position{7, 5} && cannon.facing == .East)
	testing.expect_value(t, cannon.life, CANNON_SECONDS)
	testing.expect_value(t, cannon.power, CANNON_BASE_DAMAGE)
	testing.expect(t, !cannon.laser && cell_blocks_movement(&room, {7, 5}))
	// The wheel's way wins over the cell's, for one play.
	room.aim, room.has_aim = .North, true
	arsenal_test_play(t, &room, .Cannon, cell_target({6, 7}))
	testing.expect_value(t, len(room.objects), 2)
	testing.expect_value(t, room.objects[1].facing, Move_Direction.North)
	testing.expect(t, !room.has_aim)
	// A third is refused, and so is an occupied cell.
	third := arsenal_test_play(t, &room, .Cannon, cell_target({5, 7}))
	testing.expect_value(t, third.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, third.compile_error, Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, arsenal_test_play(t, &room, .Cannon, cell_target({10, 5})).result, Card_Play_Result.Compile_Failed)
}

@(test)
test_cannon_fires_each_beat_at_the_first_foe_and_falls_apart :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {9, 5}, health = 100, attack = 1}, {position = {11, 5}, health = 100, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_play(t, &room, .Cannon, cell_target({7, 5}), 1).result, Card_Play_Result.Played)
	for beat in 1..=int(CANNON_SECONDS) {
		pulse := arsenal_test_beat(&room)
		testing.expect_value(t, arsenal_test_count(&pulse.events, .Cannon_Fired), 1)
		testing.expect_value(t, room.enemies[0].health, 100-i32(beat)*(CANNON_BASE_DAMAGE+1))
		// The ball stops at the first foe: the second is never touched.
		testing.expect_value(t, room.enemies[1].health, i32(100))
		if beat < int(CANNON_SECONDS) { testing.expect_value(t, len(room.objects), 1) }
	}
	// Twenty shots, then it falls apart.
	testing.expect_value(t, len(room.objects), 0)
	pulse := arsenal_test_beat(&room)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Cannon_Fired), 0)
}

@(test)
test_cannon_ball_stops_at_walls_and_covers_and_fires_at_nothing :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {10, 2}, health = 100, attack = 1}}
	obstacles := [?]grid.Position{{9, 5}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], obstacles = obstacles[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	// East along the row 5: a cover at 9 stops it; the foe is on another row.
	room.aim, room.has_aim = .East, true
	testing.expect_value(t, arsenal_test_play(t, &room, .Cannon, cell_target({7, 5})).result, Card_Play_Result.Played)
	pulse := arsenal_test_beat(&room)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Cannon_Fired), 1)
	for event in pulse.events.events[:pulse.events.count] {
		if event.kind == .Cannon_Fired {
			testing.expect_value(t, event.to_position, grid.Position{8, 5})
			testing.expect_value(t, event.target, SYSTEM_ENTITY)
		}
	}
	testing.expect_value(t, room.enemies[0].health, i32(100))
}

@(test)
test_laser_hits_every_foe_on_its_line_and_barrels :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {8, 5}, health = 100, attack = 1}, {position = {10, 5}, health = 100, attack = 1}, {position = {10, 2}, health = 100, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {9, 5}}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], objects = objects[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.aim, room.has_aim = .East, true
	testing.expect_value(t, arsenal_test_play(t, &room, .Laser_Cannon, cell_target({7, 5}), 1).result, Card_Play_Result.Played)
	testing.expect(t, room.objects[len(room.objects)-1].laser)
	pulse := arsenal_test_beat(&room)
	damage := LASER_BASE_DAMAGE+1
	testing.expect_value(t, room.enemies[0].health, 100-damage)
	testing.expect_value(t, room.enemies[1].health, 100-damage)
	testing.expect_value(t, room.enemies[2].health, i32(100))
	// The barrel on the line caught; the beam went on past it.
	armed := false
	for object in room.objects { if object.kind == .Barrel && object.detonation_pulse > 0 { armed = true } }
	testing.expect(t, armed || arsenal_test_count(&pulse.events, .Explosive_Armed) > 0)
}

@(test)
test_black_hole_pulls_the_foes_of_its_5x5_and_hurts_those_in_its_3x3 :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {9, 5}, health = 100, attack = 1}, // two cells from the centre (7, 5): pulled
		{position = {7, 6}, health = 100, attack = 1}, // inside: hurt
		{position = {7, 2}, health = 100, attack = 1}, // outside: untouched
		{position = {5, 7}, health = 100, attack = 1, archetype = .Demolitionist}, // a boss: not pulled
	}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	play := arsenal_test_play(t, &room, .Black_Hole, cell_target({7, 5}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.energy_before-play.energy_after, i32(3))
	testing.expect_value(t, len(room.objects), 1)
	hole := room.objects[0]
	testing.expect(t, hole.kind == .Black_Hole && hole.radius == 1 && hole.life == BLACK_HOLE_SECONDS && hole.power == BLACK_HOLE_BASE_DAMAGE)
	// The hole blocks nothing.
	testing.expect(t, !cell_blocks_movement(&room, {7, 5}))
	arsenal_test_beat(&room)
	// The far foe came a cell: (8, 5), then in the 3x3 it is hurt next beat.
	testing.expect_value(t, room.enemies[0].position, grid.Position{8, 5})
	testing.expect_value(t, room.enemies[0].health, 100-BLACK_HOLE_BASE_DAMAGE)
	testing.expect_value(t, room.enemies[1].health, 100-BLACK_HOLE_BASE_DAMAGE)
	testing.expect_value(t, room.enemies[2].health, i32(100))
	testing.expect_value(t, room.enemies[2].position, grid.Position{7, 2})
	// The boss at (5, 7) is two off the centre: damage area is radius 1, so only pulled if not boss.
	testing.expect_value(t, room.enemies[3].position, grid.Position{5, 7})
	testing.expect_value(t, room.enemies[3].health, i32(100))
	// Eight beats, then it closes.
	for _ in 0..<BLACK_HOLE_SECONDS-1 { arsenal_test_beat(&room) }
	testing.expect_value(t, len(room.objects), 0)
}

@(test)
test_black_hole_swallows_a_foe_it_kills_and_widens_with_upgrades :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 3, attack = 1}, {position = {7, 3}, health = 100, attack = 1}, {position = {7, 8}, health = 100, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, black_hole_radius(0), i32(1))
	testing.expect_value(t, black_hole_radius(2), i32(2))
	testing.expect_value(t, black_hole_radius(4), i32(3))
	testing.expect_value(t, arsenal_test_play(t, &room, .Black_Hole, cell_target({7, 5}), 2).result, Card_Play_Result.Played)
	hole := room.objects[0]
	testing.expect_value(t, hole.radius, i32(2))
	testing.expect_value(t, hole.power, BLACK_HOLE_BASE_DAMAGE+2)
	pulse := arsenal_test_beat(&room)
	// The weak foe in the 5x5 damage area dies, swallowed first.
	swallowed, fell := -1, -1
	for event, index in pulse.events.events[:pulse.events.count] {
		if event.kind == .Black_Hole_Swallowed { swallowed = index; testing.expect_value(t, event.to_position, grid.Position{7, 5}) }
		if event.kind == .Entity_Defeated && fell < 0 { fell = index }
	}
	testing.expect(t, swallowed >= 0 && fell > swallowed)
	testing.expect_value(t, len(room.enemies), 2)
	// (7, 3) is inside the 5x5 now (two cells north): hurt; (7, 8) is three off: pulled.
	// The far one, drawn in to (7, 7), is hurt there in the same beat.
	near, near_found := enemy_index_at(&room, {7, 3})
	pulled, pulled_found := enemy_index_at(&room, {7, 7})
	testing.expect(t, near_found && pulled_found)
	if near_found && pulled_found {
		testing.expect_value(t, room.enemies[near].health, 100-(BLACK_HOLE_BASE_DAMAGE+2))
		testing.expect_value(t, room.enemies[pulled].health, 100-(BLACK_HOLE_BASE_DAMAGE+2))
	}
}

@(test)
test_black_hole_pull_stops_at_blockers :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {9, 5}, health = 100, attack = 1}, {position = {8, 5}, health = 100, attack = 1}}
	obstacles := [?]grid.Position{{9, 4}, {8, 4}, {8, 6}, {9, 6}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], obstacles = obstacles[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_play(t, &room, .Black_Hole, cell_target({7, 5})).result, Card_Play_Result.Played)
	arsenal_test_beat(&room)
	// The near foe is inside already; the far one is stopped behind it.
	testing.expect_value(t, room.enemies[0].position, grid.Position{9, 5})
}

@(test)
test_bleed_adds_its_stacks_to_every_damage_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	applied, _ := apply_status(&room, foe, .Bleed, 3, 0)
	testing.expect(t, applied && status_kind_stacks(.Bleed))
	// Stacks add up and nothing wears them.
	_, _ = apply_status(&room, foe, .Bleed, 2, 0)
	testing.expect_value(t, ground_test_potency(&room, foe, .Bleed), i32(5))
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(foe), .Opponent)
	testing.expect(t, add_effect(&action, damage_effect(foe, 4)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	// 4 and its 5 stacks: 9; the extra brings no more.
	testing.expect_value(t, room.enemies[0].health, i32(41))
	testing.expect_value(t, arsenal_test_count(&report.events, .Bleed_Bite), 1)
	// A status's bite bleeds too.
	status := make_action(.Trigger, SYSTEM_ENTITY, entity_target(foe), .Entity)
	testing.expect(t, add_effect(&status, status_damage_effect(foe, 2, .Poison)))
	_ = resolve_action(&room, &status)
	testing.expect_value(t, room.enemies[0].health, i32(34))
	// A Shield takes the whole of it, the extra included.
	_, _ = apply_status(&room, foe, .Shield, 20, 2)
	again := make_action(.Trigger, PLAYER_ENTITY, entity_target(foe), .Opponent)
	testing.expect(t, add_effect(&again, damage_effect(foe, 3)))
	_ = resolve_action(&room, &again)
	testing.expect_value(t, room.enemies[0].health, i32(34))
	testing.expect_value(t, ground_test_potency(&room, foe, .Shield), i32(12))
	// The player carries none.
	applied, _ = apply_status(&room, PLAYER_ENTITY, .Bleed, 1, 0)
	testing.expect(t, !applied)
}

arsenal_test_ride :: proc(t: ^testing.T, room: ^Room, face: i32, upgrade: i32 = 0) -> Card_Play_Report {
	room.player.dice = pattern_test_dice_for_faces(t, {face, 0, 0}, 1, 4)
	return arsenal_test_play(t, room, .Dinosaur, entity_target(PLAYER_ENTITY), upgrade)
}

@(test)
test_dinosaur_rolls_a_d4_and_the_face_names_the_ride :: proc(t: ^testing.T) {
	for face in i32(1)..=4 {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {9, 5}, health = 50, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
		play := arsenal_test_ride(t, &room, face, 2)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, play.energy_before-play.energy_after, i32(3))
		testing.expect(t, room.ride.active && room.ride.kind == dino_for_face(face))
		testing.expect_value(t, int(room.ride.kind), int(face)-1)
		// Twenty seconds, three more an upgrade.
		testing.expect_value(t, room.ride.remaining, RIDE_SECONDS+2*RIDE_SECONDS_PER_UPGRADE)
		testing.expect_value(t, arsenal_test_count(room.recent_events, .Dice_Rolled), 1)
		testing.expect_value(t, arsenal_test_count(room.recent_events, .Ride_Begun), 1)
		// One ride at a time.
		again := arsenal_test_ride(t, &room, 1)
		testing.expect(t, again.result != .Played)
		testing.expect(t, room.ride.kind == dino_for_face(face))
		// It ends with its time.
		seconds := room.ride.remaining
		for _ in 0..<seconds-1 { arsenal_test_beat(&room) }
		testing.expect(t, room.ride.active)
		pulse := arsenal_test_beat(&room)
		testing.expect(t, !room.ride.active)
		testing.expect_value(t, arsenal_test_count(&pulse.events, .Ride_Ended), 1)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_velociraptor_halves_the_step_and_leaves_bleeding :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 4}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, player_move_seconds(&room), TACTICAL_MOVE_SECONDS)
	testing.expect_value(t, arsenal_test_ride(t, &room, 1).result, Card_Play_Result.Played)
	testing.expect_value(t, player_move_seconds(&room), RAPTOR_MOVE_SECONDS)
	testing.expect(t, RAPTOR_MOVE_SECONDS*2 == TACTICAL_MOVE_SECONDS/1)
	// The usual bump, and a stack of Sanguinamento.
	foe := enemy_entity(room.enemies[0].id)
	room.player.tactical.phase, room.player.tactical.remaining, room.player.tactical.cast_remaining, room.player.tactical.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	testing.expect(t, player_bump(&room, 0, {6, 4}, .Adjacent_Opponent, false))
	testing.expect_value(t, ground_test_potency(&room, foe, .Bleed), i32(1))
	testing.expect_value(t, room.enemies[0].health, 50-player_basic_attack_damage(room.player))
	// The next blow bleeds: its damage and the stack.
	before := room.enemies[0].health
	testing.expect(t, player_bump(&room, 0, {6, 4}, .Adjacent_Opponent, false))
	testing.expect_value(t, room.enemies[0].health, before-player_basic_attack_damage(room.player)-1)
	testing.expect_value(t, ground_test_potency(&room, foe, .Bleed), i32(2))
}

@(test)
test_stegosaurus_turns_every_blow_back_without_spending_anything :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 30, attack = 3, archetype = .Brute}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_ride(t, &room, 2).result, Card_Play_Result.Played)
	foe := enemy_entity(room.enemies[0].id)
	index, _ := enemy_index_by_id(&room, foe.id)
	expected := player_blow_damage(&room, room.enemies[index].intent.damage)
	testing.expect(t, !offer_defense_qte(&room, &room.enemies[index]))
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, foe.id)
	testing.expect_value(t, player.health, i32(100))
	_, deflected := charges_test_event(&pulse.events, .Attack_Deflected, foe, PLAYER_ENTITY)
	testing.expect(t, deflected)
	after, alive := enemy_index_by_id(&room, foe.id)
	testing.expect(t, alive)
	testing.expect_value(t, room.enemies[after].health, 30-expected)
	// It stays on: no charge was spent, and a second blow comes back too.
	testing.expect(t, room.ride.active && ride_deflects(&room))
	testing.expect_value(t, player_charges(&room, .Deflect), i32(0))
}

@(test)
test_dilophosaurus_poisons_the_foe_it_hurts_and_the_foe_that_hurts_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 4}, health = 50, attack = 1}, {position = {9, 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_ride(t, &room, 3).result, Card_Play_Result.Played)
	first, second := enemy_entity(room.enemies[0].id), enemy_entity(room.enemies[1].id)
	room.player.tactical.phase, room.player.tactical.remaining, room.player.tactical.cast_remaining, room.player.tactical.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	testing.expect(t, player_bump(&room, 0, {6, 4}, .Adjacent_Opponent, false))
	testing.expect_value(t, ground_test_potency(&room, first, .Poison), i32(1))
	// A card's damage poisons too.
	card := make_action(.Card, PLAYER_ENTITY, entity_target(second), .Opponent)
	testing.expect(t, add_effect(&card, damage_effect(second, 2)))
	_ = resolve_action(&room, &card)
	testing.expect_value(t, ground_test_potency(&room, second, .Poison), i32(1))
	// A blow that lands on the player leaves its attacker poisoned.
	blow := make_action(.Attack, second, entity_target(PLAYER_ENTITY), .Opponent)
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 2)))
	_ = resolve_action(&room, &blow)
	testing.expect_value(t, ground_test_potency(&room, second, .Poison), i32(2))
	// A status's own bite does not (it would feed itself).
	bite := make_action(.Trigger, SYSTEM_ENTITY, entity_target(first), .Entity)
	testing.expect(t, add_effect(&bite, status_damage_effect(first, 1, .Poison)))
	_ = resolve_action(&room, &bite)
	testing.expect_value(t, ground_test_potency(&room, first, .Poison), i32(1))
}

@(test)
test_giganotosaurus_stomps_on_each_step_and_bites_small_foes_dead :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {7, 4}, health = 40, attack = 1}, // beside where he lands (6, 5)? (7, 5 is east of it)
		{position = {2, 2}, health = 40, attack = 1, archetype = .Archer},
		{position = {10, 8}, health = 60, attack = 1, archetype = .Brute},
	}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_ride(t, &room, 4).result, Card_Play_Result.Played)
	room.player.tactical.phase, room.player.tactical.remaining, room.player.tactical.cast_remaining, room.player.tactical.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	// A step north puts him on (6, 4): the foe at (7, 4) is beside him: stomped.
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
	testing.expect_value(t, player.position, grid.Position{6, 4})
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Dino_Stomp), 1)
	testing.expect_value(t, room.enemies[0].health, 40-GIGA_STOMP_DAMAGE)
	// The step costs the usual time.
	testing.expect_value(t, player_move_seconds(&room), TACTICAL_MOVE_SECONDS)
	// His bite: a small foe falls at once, a brute takes 12.
	room.enemies[1].position, room.enemies[2].position = {5, 4}, {6, 3}
	room.player.tactical.phase, room.player.tactical.remaining, room.player.tactical.cast_remaining, room.player.tactical.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	archer_id := room.enemies[1].id
	testing.expect(t, player_bump(&room, 1, {5, 4}, .Adjacent_Opponent, false))
	_, archer_alive := enemy_index_by_id(&room, archer_id)
	testing.expect(t, !archer_alive)
	brute_index := 1
	testing.expect_value(t, room.enemies[brute_index].archetype, Enemy_Archetype.Brute)
	room.player.tactical.phase, room.player.tactical.remaining, room.player.tactical.cast_remaining, room.player.tactical.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	testing.expect(t, player_bump(&room, brute_index, {6, 3}, .Adjacent_Opponent, false))
	testing.expect_value(t, room.enemies[brute_index].health, 60-GIGA_BITE_DAMAGE)
}

@(test)
test_the_ride_and_the_emplacements_go_with_the_combat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {10, 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, arsenal_test_ride(t, &room, 1).result, Card_Play_Result.Played)
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect(t, !room.ride.active && !tactical_ride_active(&room))
	// An emplacement is only set down in a fight.
	testing.expect(t, !emplacement_can_place(&room, .Cannon, {7, 5}))
}
