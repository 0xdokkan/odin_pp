package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

marley_test_play :: proc(t: ^testing.T, room: ^Room, upgrade: i32 = 0) -> Card_Play_Report {
	card := ground_test_card(t, room, .Bomb_Marley, upgrade)
	return play_card(room, card.id, entity_target(PLAYER_ENTITY))
}

// One world beat of the party, as the pulse runs it.
marley_test_beat :: proc(room: ^Room) -> (pulse: Pulse_Report) {
	marley_beat(room, &pulse)
	return
}

marley_test_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> (count: int) {
	for event in log.events[:log.count] { if event.kind == kind { count += 1 } }
	return
}

@(test)
test_marley_card_is_a_rare_party_with_upgrades :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Bomb_Marley)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Bomb Marley")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
	testing.expect_value(t, tactical_card_time_cost(.Bomb_Marley), f32(2))
	testing.expect_value(t, card_max_upgrade_level(.Bomb_Marley), MARLEY_MAX_UPGRADE_LEVEL)
	node := Run_Node{kind = .Combat, depth = 2}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	for upgrade in i32(0)..=MARLEY_MAX_UPGRADE_LEVEL {
		effect, made := instantiate_card_effect(definition.effects[0], PLAYER_ENTITY, {id = 1, definition_id = .Bomb_Marley, upgrade_level = upgrade})
		testing.expect(t, made)
		testing.expect_value(t, effect.kind, Effect_Kind.Marley)
		testing.expect_value(t, effect.amount, MARLEY_BASE_DAMAGE+upgrade)
		testing.expect_value(t, effect.duration, MARLEY_SECONDS)
	}
	testing.expect(t, card_can_upgrade({id = 1, definition_id = .Bomb_Marley, lifetime = .Permanent}))
	testing.expect(t, !card_can_upgrade({id = 1, definition_id = .Bomb_Marley, upgrade_level = MARLEY_MAX_UPGRADE_LEVEL, lifetime = .Permanent}))
}

// Few bombs at first, then one, two and three a second; a wider room throws
// more in proportion; the lights are the characters less two, one fewer every
// ten seconds, never fewer than one.
@(test)
test_marley_ramps_up_bombs_and_wears_down_lights :: proc(t: ^testing.T) {
	testing.expect_value(t, marley_throw_count(1, 17), 1)
	testing.expect_value(t, marley_throw_count(2, 17), 0)
	testing.expect_value(t, marley_throw_count(9, 17), 1)
	testing.expect_value(t, marley_throw_count(10, 17), 1)
	testing.expect_value(t, marley_throw_count(19, 17), 1)
	testing.expect_value(t, marley_throw_count(20, 17), 2)
	testing.expect_value(t, marley_throw_count(29, 17), 2)
	testing.expect_value(t, marley_throw_count(30, 17), 3)
	testing.expect_value(t, marley_throw_count(89, 17), 3)
	testing.expect_value(t, marley_throw_count(30, 41), 8)
	testing.expect_value(t, marley_throw_count(1, 23), 2)
	// Never fewer through the seconds.
	previous := 0
	for elapsed in i32(10)..<90 {
		count := marley_throw_count(elapsed, 17)
		testing.expect(t, count >= previous)
		previous = count
	}

	data: level.Level
	player: Player
	spawns: [10]Enemy_Spawn
	for &spawn, index in spawns { spawn = {position = {2+index, 2}, health = 50, attack = 1} }
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	// Eleven characters: generous at first, one fewer every five seconds, at
	// least half of them.
	testing.expect_value(t, marley_light_count(&room, 0), 11+MARLEY_EXTRA)
	testing.expect_value(t, marley_light_count(&room, 4), 11+MARLEY_EXTRA)
	testing.expect_value(t, marley_light_count(&room, 5), 11+MARLEY_EXTRA-1)
	testing.expect_value(t, marley_light_count(&room, 35), 11+MARLEY_EXTRA-7)
	testing.expect_value(t, marley_light_count(&room, 90), 11/2)
	level_previous := marley_light_count(&room, 0)
	for elapsed in i32(1)..<90 {
		count := marley_light_count(&room, elapsed)
		testing.expect(t, count <= level_previous && count >= 11/2)
		level_previous = count
	}
	// Not everybody can be saved once the party is old.
	testing.expect(t, marley_light_count(&room, 60) < 11)
}

@(test)
test_marley_card_starts_the_party_after_its_cast :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {9, 3}, health = 50, attack = 1}, {position = {9, 7}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	play := marley_test_play(t, &room, 2)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.energy_before-play.energy_after, i32(3))
	m := &room.marley
	testing.expect(t, m.active && tactical_marley_active(&room))
	testing.expect_value(t, m.remaining, MARLEY_SECONDS)
	testing.expect_value(t, m.damage, MARLEY_BASE_DAMAGE+2)
	// Four characters and four more: eight lights, and one fewer shown ahead,
	// none on the cells now lit; one within three cells of the player.
	testing.expect_value(t, m.light_count, 4+MARLEY_EXTRA)
	testing.expect_value(t, m.next_count, 4+MARLEY_EXTRA-1)
	testing.expect(t, m.has_next)
	near := false
	for index in 0..<m.light_count {
		light := marley_light(m, index)
		testing.expect(t, base_cell_is_walkable(&room, light) && !cell_blocks_movement(&room, light))
		if max(abs(light.x-player.position.x), abs(light.y-player.position.y)) <= MARLEY_NEAR { near = true }
		for other in 0..<m.light_count { if other != index { testing.expect(t, marley_light(m, other) != light) } }
		for ahead in 0..<m.next_count { testing.expect(t, marley_next_light(m, ahead) != light) }
	}
	testing.expect(t, near)
	testing.expect_value(t, marley_test_count(room.recent_events, .Marley_Begun), 1)
	testing.expect_value(t, marley_test_count(room.recent_events, .Marley_Lights), 1)
	// No second party while it plays.
	testing.expect(t, !marley_can_begin(&room))
	card := ground_test_card(t, &room, .Bomb_Marley)
	testing.expect(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result != .Played)
	testing.expect_value(t, m.remaining, MARLEY_SECONDS)
}

@(test)
test_marley_critical_play_adds_five_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := ground_test_card(t, &room, .Bomb_Marley)
	room.player.tactical.critical_next = true
	testing.expect_value(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Played)
	testing.expect_value(t, room.marley.remaining, MARLEY_SECONDS+MARLEY_CRITICAL_SECONDS)
}

// The beats: a column warned at one beat lands two beats on; a character off
// the lights takes the damage, one on a light does not.
@(test)
test_marley_bomb_hurts_everyone_off_the_lights :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {6, 2}, health = 50, attack = 1}, // lit
		{position = {6, 8}, health = 50, attack = 1}, // not lit
		{position = {2, 4}, health = 50, attack = 1}, // another column
	}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	marley_set_lights(m, {room.enemies[0].position})
	m.column_count = 1
	m.columns[0] = {x = 6, beats = 1}
	pulse := marley_test_beat(&room)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Bomb), 1)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Saved), 1)
	testing.expect_value(t, player.health, 100-MARLEY_BASE_DAMAGE)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	testing.expect_value(t, room.enemies[1].health, 50-MARLEY_BASE_DAMAGE)
	testing.expect_value(t, room.enemies[2].health, i32(50))
	for event in pulse.events.events[:pulse.events.count] {
		if event.kind == .Marley_Bomb {
			testing.expect_value(t, event.from_position, grid.Position{6, 0})
			testing.expect_value(t, event.to_position, grid.Position{6, 10})
			testing.expect_value(t, event.amount, MARLEY_BASE_DAMAGE)
		}
		if event.kind == .Marley_Saved { testing.expect_value(t, event.target, enemy_entity(room.enemies[0].id)) }
	}
	// The player on a light is safe too.
	marley_set_lights(m, {player.position})
	m.column_count = 1
	m.columns[0] = {x = i32(player.position.x), beats = 1}
	before := player.health
	pulse = marley_test_beat(&room)
	testing.expect_value(t, player.health, before)
	testing.expect(t, marley_test_count(&pulse.events, .Marley_Saved) >= 1)
}

@(test)
test_marley_warns_columns_two_beats_ahead :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {9, 7}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	// Beat one: the first column is warned and lands two beats later.
	pulse := marley_test_beat(&room)
	testing.expect_value(t, m.elapsed, i32(1))
	testing.expect_value(t, m.column_count, 1)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Warned), 1)
	x := int(m.columns[0].x)
	testing.expect_value(t, m.columns[0].beats, MARLEY_WARN_BEATS)
	testing.expect(t, marley_column_is_warned(&room, x))
	testing.expect_value(t, marley_column_beats(&room, x), MARLEY_WARN_BEATS)
	pulse = marley_test_beat(&room)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Bomb), 0)
	pulse = marley_test_beat(&room)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Bomb), 1)
	testing.expect(t, !marley_column_is_warned(&room, x) || m.column_count > 0)
}

@(test)
test_marley_kill_earns_seconds_within_ninety :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 8}, health = 3, attack = 1}, {position = {3, 3}, health = 50, attack = 1}, {position = {9, 2}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	m.light_count = 0
	m.column_count = 1
	m.columns[0] = {x = 6, beats = 1}
	pulse := marley_test_beat(&room)
	testing.expect_value(t, len(room.enemies), 2)
	testing.expect_value(t, m.kills, i32(1))
	testing.expect_value(t, m.earned, MARLEY_KILL_SECONDS)
	// The clock ticked once as well.
	testing.expect_value(t, m.remaining, MARLEY_SECONDS+MARLEY_KILL_SECONDS-1)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Bonus), 1)

	// Near the end of the ninety seconds the bonus is cut short.
	room.enemies[0].position, room.enemies[0].health = {6, 8}, 1
	room.enemies[0].max_health = max(room.enemies[0].max_health, 1)
	m.elapsed, m.remaining = 80, 8
	m.column_count = 1
	m.columns[0] = {x = 6, beats = 1}
	m.light_count = 0
	marley_test_beat(&room)
	// 80 + 8 left leaves two; the clock then ticks to 81 and 9.
	testing.expect_value(t, m.elapsed+m.remaining, MARLEY_MAX_SECONDS)
}

@(test)
test_marley_ends_with_its_time_and_with_the_combat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {9, 7}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	room.marley.remaining = 1
	pulse := marley_test_beat(&room)
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Ended), 1)
	testing.expect(t, !room.marley.active)
	testing.expect(t, marley_can_begin(&room))
	// A new party, cut off by the end of the combat.
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect(t, !room.marley.active)
	testing.expect_value(t, room.marley.light_count, 0)
}

// The same room, the same lights and columns; nothing reads a clock.
@(test)
test_marley_is_deterministic :: proc(t: ^testing.T) {
	record :: proc(t: ^testing.T, lights: ^[dynamic]grid.Position, columns: ^[dynamic]i32) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 500, attack = 1}, {position = {9, 7}, health = 500, attack = 1}, {position = {6, 2}, health = 500, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:], room_seed = 77})
		defer level.destroy(&data)
		defer destroy_room(&room)
		player.health, player.stats.max_health = 100000, 100000
		testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
		for _ in 0..<30 {
			marley_test_beat(&room)
			for index in 0..<room.marley.light_count { append(lights, marley_light(&room.marley, index)) }
			for index in 0..<room.marley.next_count { append(lights, marley_next_light(&room.marley, index)) }
			for column in room.marley.columns[:room.marley.column_count] { append(columns, column.x) }
		}
	}
	a_lights, b_lights: [dynamic]grid.Position
	a_columns, b_columns: [dynamic]i32
	defer { delete(a_lights); delete(b_lights); delete(a_columns); delete(b_columns) }
	record(t, &a_lights, &a_columns)
	record(t, &b_lights, &b_columns)
	testing.expect(t, len(a_lights) > 0 && len(a_columns) > 0)
	testing.expect_value(t, len(a_lights), len(b_lights))
	testing.expect_value(t, len(a_columns), len(b_columns))
	for i in 0..<min(len(a_lights), len(b_lights)) { testing.expect_value(t, a_lights[i], b_lights[i]) }
	for i in 0..<min(len(a_columns), len(b_columns)) { testing.expect_value(t, a_columns[i], b_columns[i]) }
}

// The lights move every five beats; the cells they will move to are on show
// all the while, never the cells now lit, and become the lit ones at the turn.
@(test)
test_marley_lights_move_every_five_beats_with_the_next_always_shown :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 500, attack = 1}, {position = {9, 7}, health = 500, attack = 1}, {position = {6, 2}, health = 500, attack = 1}, {position = {2, 8}, health = 500, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health, player.stats.max_health = 100000, 100000
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	first := m.lights
	next := m.next_lights
	testing.expect(t, m.has_next)
	for _ in 1..=4 {
		marley_test_beat(&room)
		testing.expect_value(t, m.lights, first)
		testing.expect_value(t, m.next_lights, next)
		testing.expect(t, m.has_next)
	}
	pulse := marley_test_beat(&room)
	testing.expect_value(t, m.elapsed, i32(5))
	testing.expect_value(t, m.lights, next)
	// New cells are on show at once, apart from the ones now lit.
	testing.expect(t, m.has_next && m.next_lights != next)
	for index in 0..<m.next_count {
		for lit in 0..<m.light_count { testing.expect(t, marley_next_light(m, index) != marley_light(m, lit)) }
	}
	testing.expect_value(t, marley_test_count(&pulse.events, .Marley_Lights), 1)
}

// The lights are spread over the floor rather than clumped: no two of them
// side by side when the floor has room.
@(test)
test_marley_lights_are_spread_out :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 500, attack = 1}, {position = {9, 7}, health = 500, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	side_by_side := 0
	for a in 0..<m.light_count {
		for b in a+1..<m.light_count {
			la, lb := marley_light(m, a), marley_light(m, b)
			if max(abs(la.x-lb.x), abs(la.y-lb.y)) <= 1 { side_by_side += 1 }
		}
	}
	testing.expect(t, side_by_side <= 2)
}

// The bombs of one beat are recorded together, before any damage, in one visual
// group: they fly side by side.
@(test)
test_marley_bombs_of_a_beat_share_a_group :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 500, attack = 1}, {position = {9, 7}, health = 500, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health, player.stats.max_health = 100000, 100000
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	m.light_count = 0
	m.column_count = 3
	m.columns[0], m.columns[1], m.columns[2] = {x = 3, beats = 1}, {x = 9, beats = 1}, {x = 6, beats = 1}
	pulse := marley_test_beat(&room)
	bombs, last_bomb, first_damage := 0, -1, -1
	for event, index in pulse.events.events[:pulse.events.count] {
		if event.kind == .Marley_Bomb {
			bombs += 1
			last_bomb = index
			testing.expect_value(t, event.visual_group, MARLEY_BOMB_GROUP)
		}
		if event.kind == .Damaged && first_damage < 0 { first_damage = index }
	}
	testing.expect_value(t, bombs, 3)
	testing.expect(t, first_damage > last_bomb)
}

// Bombs set a barrel in the column off; the player in Movimento Ombra is not hurt.
@(test)
test_marley_bombs_catch_barrels_and_spare_the_shadow :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {6, 8}}, {kind = .Ice_Block, position = {6, 2}}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], objects = objects[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	m.light_count = 0
	m.column_count = 1
	m.columns[0] = {x = 6, beats = 1}
	marley_test_beat(&room)
	armed := false
	for object in room.objects { if object.kind == .Barrel && object.detonation_pulse > 0 { armed = true } }
	testing.expect(t, armed)
	// The ice block is no explosive: it stands, whole.
	for object in room.objects { if object.kind == .Ice_Block { testing.expect_value(t, object.health, object.max_health) } }
}

// A foe in a warned column leaves it; a foe off the lights, with a free light
// near, makes for it; a foe beside the player stays to fight.
@(test)
test_marley_enemies_flee_columns_and_make_for_the_lights :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 500, attack = 1}, {position = {10, 8}, health = 500, attack = 1}, {position = {5, 5}, health = 500, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, marley_test_play(t, &room).result, Card_Play_Result.Played)
	m := &room.marley
	// Foe 0 stands in a warned column; foe 1 has a light two cells off; foe 2
	// is beside the player (6, 5).
	marley_set_lights(m, {{8, 8}})
	m.column_count = 1
	m.columns[0] = {x = 3, beats = 2}
	for &enemy in room.enemies { enemy.intent, enemy.tactical_cooldown = {}, 0 }
	plan_enemy_intents(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect(t, room.enemies[0].intent.destination.x != 3)
	testing.expect_value(t, room.enemies[1].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, room.enemies[1].intent.destination, grid.Position{9, 8})
	testing.expect(t, room.enemies[2].intent.kind != .Move || !marley_cell_is_lit(&room, room.enemies[2].intent.destination))
	// A lit cell in a warned column is safe: no blast zone there.
	testing.expect_value(t, enemy_terrain_danger(&room, {3, 3}), MARLEY_COLUMN_DANGER)
	marley_set_lights(m, {{3, 3}})
	testing.expect_value(t, enemy_terrain_danger(&room, {3, 3}), 0)
	testing.expect_value(t, enemy_terrain_danger(&room, {3, 4}), MARLEY_COLUMN_DANGER)
}
