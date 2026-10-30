package game

import "core:encoding/json"
import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON BRAWLER among the foes (first_person_fists.odin, Fase 2 passo 4):
// the foes' blows on the cells the body touches, in the air only those from
// afar, no defence prompt, traps flown over, the card ending in the air, the save.

@(private = "file")
foes_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn, traps: []Trap_Spawn = nil) -> Room {
	rows: [13]string
	cells: [13][13]u8
	for y in 0..<13 {
		for x in 0..<13 { cells[y][x] = '#' if x == 0 || y == 0 || x == 12 || y == 12 else '.' }
	}
	cells[6][6], cells[11][11] = '@', '>'
	for y in 0..<13 { rows[y] = string(cells[y][:]) }
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	testing.expect(t, configure_tactical(player, DEFAULT_TACTICAL_CONFIG))
	room, made := create_room(data, player, {enemies = spawns, traps = traps})
	testing.expect(t, made)
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	return room
}

@(private = "file")
foes_run :: proc(room: ^Room, seconds: f32, input := First_Person_Fists_Input{}) {
	given := input
	for _ in 0..<int(math.round(seconds/FISTS_STEP)) {
		_ = first_person_fists_move(room, given, FISTS_STEP)
		given.jump, given.dash, given.punch = false, false, .None
	}
}

// The foe's committed blow on (7, 6), resolved as on its beat; the health it took.
@(private = "file")
foes_blow :: proc(room: ^Room, target: grid.Position, damage := i32(5)) -> i32 {
	foe := &room.enemies[0]
	foe.intent = make_attack_intent(room, foe.position, target, damage)
	health := room.player.health
	pulse: Pulse_Report
	resolve_enemy_intents(room, &pulse, foe.id)
	return health-room.player.health
}

// A blow on a cell his body touches reaches him though his centre is in the next
// one; on a cell it does not touch, never. In the air a blow on the ground passes
// under him.
@(test)
test_fists_blows_reach_the_body_where_it_touches :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 40, attack = 5}}
	room := foes_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	target := grid.Position{x = 7, y = 6}
	// At his cell's centre the body does not touch (7, 6).
	testing.expect(t, !first_person_fists_touches(&room, target))
	testing.expect_value(t, foes_blow(&room, target), i32(0))
	// Leaning toward it, still in (6, 6): it does.
	f.body = {6.8, 6.5}
	testing.expect(t, room.player.position == {x = 6, y = 6} && first_person_fists_touches(&room, target))
	testing.expect(t, foes_blow(&room, target) > 0, "the touched cell's blow missed")
	// In the air: under him.
	f.airborne, f.feet, f.rise_speed = true, 3, 0
	testing.expect_value(t, foes_blow(&room, target), i32(0))
	// The AK's view keeps the old rule: only his cell.
	f.airborne = false
	room.first_person.weapon = .AK
	intent := make_attack_intent(&room, room.enemies[0].position, target, 5)
	testing.expect(t, !enemy_blow_reaches_player(&room, &intent, false))
}

// An arrow reaches him in the air.
@(test)
test_fists_arrows_reach_him_in_the_air :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 6}, health = 40, attack = 5, archetype = .Archer}}
	room := foes_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	f.airborne, f.feet = true, 3
	intent := make_attack_intent(&room, room.enemies[0].position, room.player.position, 5)
	testing.expect(t, enemy_blow_reaches_player(&room, &intent, true))
	testing.expect(t, foes_blow(&room, room.player.position) > 0, "the arrow missed him in the air")
}

// With the fists no blow opens the defence prompt; with the AK it does.
@(test)
test_fists_open_no_defence_prompt :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 40, attack = 5}}
	room := foes_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	shielded, _ := apply_status(&room, PLAYER_ENTITY, .Shield, 3, 3)
	testing.expect(t, shielded)
	foe := &room.enemies[0]
	foe.intent = make_attack_intent(&room, foe.position, room.player.position, 5)
	testing.expect(t, !offer_defense_qte(&room, foe), "a defence prompt with the fists")
	room.first_person.weapon = .AK
	testing.expect(t, offer_defense_qte(&room, foe), "no defence prompt with the AK")
}

// A trap flown over does nothing; walked into, it bites; a jump in place on it
// does not set it off again.
@(test)
test_fists_fly_over_a_trap :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	traps := [?]Trap_Spawn{{position = {x = 7, y = 6}, damage = 3}}
	room := foes_room(t, &data, &player, spawns[:], traps[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	foes_run(&room, 0.6, {wish = {1, 0}, jump = true})
	testing.expect(t, room.player.position.x >= 8 && !f.airborne, "not over the trap")
	testing.expect_value(t, room.player.health, i32(100))
	foes_run(&room, 0.5)
	// Back west on foot until his centre is in (7, 6).
	for room.player.position.x > 7 { foes_run(&room, FISTS_STEP, {wish = {-1, 0}}) }
	foes_run(&room, 0.3)
	testing.expect_value(t, room.player.health, i32(100-3))
	foes_run(&room, 0.6, {jump = true})
	testing.expect(t, room.player.position == {x = 7, y = 6} && room.player.health == 100-3, "the jump in place set it off again")
}

// The card ending in the air lands him at once on the cell under him.
@(test)
test_fists_card_ends_in_the_air :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := foes_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	foes_run(&room, 0.1, {jump = true})
	testing.expect(t, f.airborne && f.feet > 0)
	room.first_person.remaining = 0.01
	tactical_first_person_tick(&room, 0.02)
	testing.expect(t, !tactical_first_person_active(&room) && !f.airborne && f.feet == 0)
}

// The save keeps the fists' body, punch and marks, through JSON as a save writes it.
@(test)
test_fists_save_keeps_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 40, attack = 1}}
	room := foes_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	foes_run(&room, 0.3, {wish = {1, 0.4}, jump = true, punch = .Jab})
	foes_run(&room, 1.0)
	state := room.first_person
	bytes, err := json.marshal(first_person_save(state), allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	read: First_Person_Save
	testing.expect(t, json.unmarshal(bytes, &read, allocator = context.temp_allocator) == nil)
	back, ok := first_person_load(read)
	testing.expect(t, ok && back.weapon == .Fists)
	a, b := state.fists, back.fists
	testing.expect(t, a.body == b.body && a.velocity == b.velocity && a.feet == b.feet && a.airborne == b.airborne)
	testing.expect(t, a.punch == b.punch && a.punch_clock == b.punch_clock && a.random == b.random && a.marks == b.marks)
	testing.expect(t, a.dash_recharge == b.dash_recharge && a.carry == b.carry && a.crits == b.crits)
}
