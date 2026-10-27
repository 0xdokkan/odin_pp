package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// A long corridor, the player at its west end, and the heights written on top.
@(private = "file")
height_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, heights: string, enemies: []Enemy_Spawn = {}) -> (room: Room) {
	rows := [?]string{
		"###########",
		"#@.......>#",
		"#.........#",
		"###########",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	for symbol, x in heights {
		steps := i32(symbol-'0')
		if symbol >= 'a' { steps = i32(symbol-'a')+10 }
		testing.expect(t, level.set_height(data, {x = x, y = 1}, steps))
	}
	player^ = create_test_player(t)
	made: bool
	room, made = create_room(data, player, {enemies = enemies})
	testing.expect(t, made)
	return
}

@(test)
test_a_cliff_is_a_height_difference_of_more_than_one_step :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := height_room(t, &data, &player, "0123478")
	defer level.destroy(&data)
	defer destroy_room(&room)
	// Neighbours one step apart are walkable, up or down; two or more are a cliff.
	testing.expect(t, !step_height_blocked(&room, {x = 0, y = 1}, {x = 1, y = 1}))
	testing.expect(t, !step_height_blocked(&room, {x = 1, y = 1}, {x = 0, y = 1}))
	testing.expect(t, !step_height_blocked(&room, {x = 3, y = 1}, {x = 4, y = 1}))
	testing.expect(t, !step_height_blocked(&room, {x = 5, y = 1}, {x = 6, y = 1}))
	testing.expect(t, step_height_blocked(&room, {x = 4, y = 1}, {x = 5, y = 1}))
	testing.expect(t, step_height_blocked(&room, {x = 5, y = 1}, {x = 4, y = 1}))
	// A force climbs no cliff but goes down a step or a drop.
	testing.expect(t, rise_height_blocked(&room, {x = 4, y = 1}, {x = 5, y = 1}))
	testing.expect(t, !rise_height_blocked(&room, {x = 5, y = 1}, {x = 4, y = 1}))
	testing.expect(t, !rise_height_blocked(&room, {x = 1, y = 1}, {x = 2, y = 1}))
	// A flat map has no cliff anywhere.
	flat: level.Level
	flat_player: Player
	flat_room := height_room(t, &flat, &flat_player, "")
	defer level.destroy(&flat)
	defer destroy_room(&flat_room)
	testing.expect(t, !step_height_blocked(&flat_room, {x = 1, y = 1}, {x = 2, y = 1}) && !rise_height_blocked(&flat_room, {x = 1, y = 1}, {x = 2, y = 1}))
}

@(test)
test_a_fall_costs_the_drop_minus_one_up_to_ten :: proc(t: ^testing.T) {
	testing.expect_value(t, fall_damage(0), i32(0))
	testing.expect_value(t, fall_damage(1), i32(0))
	testing.expect_value(t, fall_damage(2), i32(1))
	testing.expect_value(t, fall_damage(4), i32(3))
	testing.expect_value(t, fall_damage(11), i32(10))
	testing.expect_value(t, fall_damage(200), i32(10))
	testing.expect_value(t, fall_damage(-3), i32(0))
}

@(test)
test_the_player_walks_a_stair_and_stops_at_a_cliff :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	// The player starts on the second cell (height 1): a stair of one step each
	// up to height 3, then a cliff of three down.
	room := height_room(t, &data, &player, "0123006")
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	for x in 2..=3 {
		testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
		testing.expect_value(t, room.player.position, grid.Position{x = x, y = 1})
	}
	// The cell past the stair is three steps down: a cliff, a wall to a walker.
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Blocked)
	testing.expect_value(t, room.player.position, grid.Position{x = 3, y = 1})
	// Back down the stair, one step each.
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 1, y = 1})
}

@(test)
test_a_push_cannot_climb_a_cliff_but_falls_down_one :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 20, attack = 1}}
	// The foe stands at height 6 on a plateau (cells 3..4); west of it the ground
	// is at 0, east of it at 1: a drop of five one way, a rise of five the other.
	room := height_room(t, &data, &player, "0006600", spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	foe := room.enemies[0]
	// Down a cliff: allowed, and it falls: six steps cost five.
	query := query_entity_movement(&room, enemy_entity(foe.id), {x = 2, y = 1})
	testing.expect(t, movement_query_is_clear(&query))
	action := make_action(.Move, PLAYER_ENTITY, entity_target(enemy_entity(foe.id)), .Entity)
	testing.expect(t, add_effect(&action, move_effect(enemy_entity(foe.id), {x = 2, y = 1})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, room.enemies[0].health, i32(20-5))
	// Up a cliff: a wall to a force.
	up := query_entity_movement(&room, enemy_entity(foe.id), {x = 3, y = 1})
	testing.expect_value(t, up.error, Movement_Error.Static_Blocker)
	testing.expect_value(t, up.blocker, grid.Position{x = 3, y = 1})
}

@(test)
test_a_foe_does_not_walk_over_a_cliff :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 20, attack = 1}}
	room := height_room(t, &data, &player, "0006600", spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	testing.expect(t, !enemy_can_move_to(&room, 0, {x = 2, y = 1}))
	testing.expect(t, enemy_can_move_to(&room, 0, {x = 4, y = 1}))
	positions: [MAX_ENEMIES_PER_ROOM]grid.Position
	positions[0] = {x = 3, y = 1}
	testing.expect(t, !planned_cell_is_available(&room, &positions, 1, 0, {x = 2, y = 1}))
	testing.expect(t, planned_cell_is_available(&room, &positions, 1, 0, {x = 4, y = 1}))
	// The distances to the player round the cliff: the plateau's cells are cut off
	// from the corridor, so the foe on it has no way down.
	distances := make([]int, len(data.tiles.cells))
	defer delete(distances)
	rebuild_tactical_enemy_distances(&room, distances, .Melee)
	index, _ := grid.index_of(&data.tiles, {x = 3, y = 1})
	testing.expect_value(t, distances[index], -1)
}

@(test)
test_the_ground_hides_what_is_behind_a_ridge :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	// A ridge of 7 steps three cells off; the eye at 6 over a floor at 0, the target at 4.
	room := height_room(t, &data, &player, "0007000")
	defer level.destroy(&data)
	defer destroy_room(&room)
	origin, target, ridge := grid.Position{x = 0, y = 1}, grid.Position{x = 6, y = 1}, grid.Position{x = 3, y = 1}
	testing.expect(t, height_hides(&room, origin, target, ridge, 3, 6))
	// A ridge at the line's own height does not hide it; flat ground never does.
	level.set_height(&data, ridge, 5)
	testing.expect(t, !height_hides(&room, origin, target, ridge, 3, 6))
	level.set_height(&data, ridge, 0)
	testing.expect(t, !height_hides(&room, origin, target, ridge, 3, 6))
	// From a high place the same ridge is below the line: the eye looks over it.
	level.set_height(&data, ridge, 7)
	level.set_height(&data, origin, 6)
	testing.expect(t, !height_hides(&room, origin, target, ridge, 3, 6))
	// The end cells are never the ground in the way.
	testing.expect(t, !height_hides(&room, origin, target, target, 6, 6))
	testing.expect(t, !height_hides(&room, origin, target, origin, 0, 6))
	// The cast line follows it: a cell behind the ridge is not reachable by a card
	// that needs sight.
	level.set_height(&data, origin, 0)
	path: [MAX_TARGETING_PATH_CELLS]grid.Position
	count, traced := trace_targeting_line(origin, target, &path)
	testing.expect(t, traced)
	_, blocked := targeting_path_blocker(&room, origin, &path, count)
	testing.expect(t, blocked)
	level.set_height(&data, ridge, 0)
	_, blocked = targeting_path_blocker(&room, origin, &path, count)
	testing.expect(t, !blocked)
}

@(test)
test_a_ranged_card_reaches_one_cell_further_from_four_steps_above :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := height_room(t, &data, &player, "")
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Combat
	definition, _ := card_definition_by_id(.Firebomb)
	card := Card_Instance{id = 1, definition_id = .Firebomb, lifetime = .Permanent}
	reach := definition.targeting.cast_range.maximum
	at := func_cell(reach+1)
	// On flat ground the cell one past the reach is out of range.
	evaluation := evaluate_card_targeting(&room, card, card_target_request_at(definition, at))
	testing.expect_value(t, evaluation.error, Card_Compile_Error.Target_Out_Of_Range)
	// Four steps above it, in reach; three steps above, still out.
	level.set_height(&data, room.player.position, 3)
	evaluation = evaluate_card_targeting(&room, card, card_target_request_at(definition, at))
	testing.expect_value(t, evaluation.error, Card_Compile_Error.Target_Out_Of_Range)
	level.set_height(&data, room.player.position, 4)
	evaluation = evaluate_card_targeting(&room, card, card_target_request_at(definition, at))
	testing.expect(t, evaluation.error != .Target_Out_Of_Range)
	// Two cells past the reach is out of range at any height; a melee card gets no bonus.
	far := func_cell(reach+2)
	evaluation = evaluate_card_targeting(&room, card, card_target_request_at(definition, far))
	testing.expect_value(t, evaluation.error, Card_Compile_Error.Target_Out_Of_Range)
	testing.expect_value(t, height_range_maximum(&room, 1, room.player.position, at), 1)
}

@(private = "file")
func_cell :: proc(distance: int) -> grid.Position { return {x = 1+distance, y = 1} }

@(test)
test_the_first_person_shot_is_stopped_by_a_cliff_face_above_its_eye :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := height_room(t, &data, &player, "")
	defer level.destroy(&data)
	defer destroy_room(&room)
	from := room.player.position
	aim := First_Person_Aim{yaw = 0, pitch = 0}
	// Level ground: the shot flies along the corridor to its end wall.
	shot := first_person_trace(&room, from, aim)
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 10, y = 1})
	// A cell two steps up (0.24) is below the eye (1.05): the shot goes over it.
	level.set_height(&data, {x = 4, y = 1}, 2)
	shot = first_person_trace(&room, from, aim)
	testing.expect_value(t, shot.cell, grid.Position{x = 10, y = 1})
	// A cell ten steps up (1.2) is above the eye: its face stops the shot.
	level.set_height(&data, {x = 4, y = 1}, 10)
	shot = first_person_trace(&room, from, aim)
	testing.expect_value(t, shot.hit, First_Person_Hit.Solid)
	testing.expect_value(t, shot.cell, grid.Position{x = 4, y = 1})
	// The same cell seen from a floor at its own height: the eye is above it again.
	level.set_height(&data, from, 10)
	shot = first_person_trace(&room, from, aim)
	testing.expect_value(t, shot.cell, grid.Position{x = 10, y = 1})
	testing.expect(t, abs(shot.origin.y-(FIRST_PERSON_EYE_HEIGHT+1.2)) < 0.001)
	_ = math.PI
}

// The sculpted surface (level/surface.odin) links two cells side by side exactly where a walker can step between
// them, so a ramp drawn is a ramp walked and a cliff drawn stops the step.
@(test)
test_the_surface_links_the_cells_a_walker_steps_between :: proc(t: ^testing.T) {
	testing.expect_value(t, level.SURFACE_LINK_STEPS, int(HEIGHT_MAX_STEP))
}

// Section 12 of docs/piano-profondita.md: the brute's charge looked at the height of its first step only. A cliff
// further along its way (two steps up at its second cell) stops it as it stops a walk; a step of one does not.
@(test)
test_a_brute_charges_only_along_steps_it_can_walk :: proc(t: ^testing.T) {
	for heights, case_index in ([2]string{"0002000000", "0001000000"}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 5, y = 1}, health = 20, attack = 2, archetype = .Brute}}
		room := height_room(t, &data, &player, heights, spawns[:])
		cliff := case_index == 0
		intent := room.enemies[0].intent
		testing.expectf(t, (intent.kind == .Charge) == !cliff, "case %d: %v", case_index, intent.kind)
		if !cliff { testing.expect_value(t, intent.path_count, 3) }
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
		// Over the cliff he never stands: he is still east of it, or (a step of one) next to the player.
		testing.expectf(t, room.enemies[0].position.x > 3 if cliff else room.enemies[0].position.x == 2,
			"case %d: the brute at %v", case_index, room.enemies[0].position)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// Section 12 of docs/piano-profondita.md: the diagonal with its QTE, the defense's dodge and the shadow's step looked
// at the rise only (the movement's rule, a push's), so they took the player down a cliff that a step does not go down.
// They are walks: a cliff stops them either way, a step of one does not.
@(test)
test_the_diagonal_the_dodge_and_the_shadow_walk_no_cliff :: proc(t: ^testing.T) {
	for steps in ([2]i32{2, 1}) {
		cliff := steps > 1
		{
			data: level.Level
			player: Player
			room := tactical_test_room(t, &data, &player)
			testing.expect(t, level.set_height(&data, player.position, steps))
			testing.expectf(t, begin_diagonal_qte(&room, {x = 1, y = 1}) == !cliff, "diagonal, %d steps", steps)
			destroy_room(&room)
			level.destroy(&data)
		}
		{
			data: level.Level
			player: Player
			room := tactical_test_room(t, &data, &player, true)
			testing.expect(t, level.set_height(&data, player.position, steps))
			room.qte = {kind = .Defense, selected = true, mode = .Dodge, enemy_id = room.enemies[0].id, defenses = {.Dodge}, remaining = 1}
			resolve_qte(&room, true, .South)
			testing.expectf(t, player.position == (cliff ? grid.Position{x = 1, y = 1} : grid.Position{x = 1, y = 2}),
				"dodge, %d steps: %v", steps, player.position)
			destroy_room(&room)
			level.destroy(&data)
		}
		{
			data: level.Level
			player: Player
			room := shadow_test_room(t, &data, &player)
			testing.expect_value(t, shadow_test_play(t, &room).result, Card_Play_Result.Played)
			testing.expect(t, level.set_height(&data, player.tactical.shadow_position, steps))
			testing.expectf(t, try_shadow_step(&room, .West) == (Action_Result.Blocked if cliff else Action_Result.Moved), "shadow, %d steps", steps)
			destroy_room(&room)
			level.destroy(&data)
		}
	}
}
