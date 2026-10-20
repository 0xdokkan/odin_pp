package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// The events of a roll of their kind, in order.
pinball_test_events_of :: proc(events: []Pinball_Test_Event, kind: Game_Event_Kind, list: ^[dynamic]Game_Event) {
	for seen in events { if seen.event.kind == kind { append(list, seen.event) } }
}

// The value starts at the card's amount, an upgrade or the tick a step higher
// each (both, two), and every solid thing it touches puts it back there, however
// far foes have raised it.
@(test)
test_pinball_value_starts_at_the_card_and_every_wall_puts_it_back :: proc(t: ^testing.T) {
	Case :: struct {upgrade: i32, critical: bool, base: i32}
	cases := [?]Case{{0, false, 2}, {2, false, 4}, {0, true, 3}, {2, true, 5}, {PINBALL_MAX_UPGRADE_LEVEL, false, 7}}
	for want in cases {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
		room := lasso_test_room(t, &data, &player, spawns[:])
		play := pinball_test_strike(t, &room, room.enemies[0].id, want.upgrade, want.critical)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, room.pinball.base, want.base)
		testing.expect_value(t, room.pinball.value, want.base)
		room.pinball.value = want.base+6
		pinball_test_aim(&room, {1, 0})
		events: [dynamic]Pinball_Test_Event
		pinball_test_roll(t, &room, 1, 1.0/60.0, &events)
		bounces: [dynamic]Game_Event
		pinball_test_events_of(events[:], .Pinball_Bounced, &bounces)
		if testing.expect(t, len(bounces) >= 1) {
			testing.expect_value(t, bounces[0].to_position, grid.Position{12, 6})
			testing.expect_value(t, bounces[0].duration, want.base+6)
			testing.expect_value(t, bounces[0].amount, want.base)
		}
		testing.expect_value(t, room.pinball.value, want.base)
		delete(bounces)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// A foe struck is knocked one cell away from the ball under the push rules:
// not into a wall, nor into a body; a pool where it lands gives its Veleno, a
// fire its Bruciatura; a diagonal push through a closed corner is refused.
@(test)
test_pinball_knock_back_keeps_the_push_rules :: proc(t: ^testing.T) {
	Case :: struct {
		name: string,
		struck, other: grid.Position,
		heading: Pinball_Vec,
		landing: grid.Position,
		pool, fire: bool,
		cover: [2]grid.Position,
	}
	cases := [?]Case{
		{name = "wall", struck = {11, 6}, heading = {1, 0}, landing = {11, 6}},
		{name = "body", struck = {9, 6}, other = {10, 6}, heading = {1, 0}, landing = {9, 6}},
		{name = "free", struck = {9, 6}, heading = {1, 0}, landing = {10, 6}},
		{name = "pool", struck = {9, 6}, heading = {1, 0}, landing = {10, 6}, pool = true},
		{name = "fire", struck = {9, 6}, heading = {1, 0}, landing = {10, 6}, fire = true},
		{name = "corner", struck = {9, 8}, heading = {1, 1}, landing = {9, 8}, cover = {{10, 8}, {9, 9}}},
		{name = "diagonal", struck = {9, 8}, heading = {1, 1}, landing = {10, 9}},
	}
	for want in cases {
		data: level.Level
		player: Player
		spawns: [3]Enemy_Spawn
		spawns[0] = {position = {7, 6}, health = 30, attack = 1}
		spawns[1] = {position = want.struck, health = 40, attack = 1}
		count := 2
		if want.other != {} { spawns[2] = {position = want.other, health = 40, attack = 1}; count = 3 }
		obstacles: [2]grid.Position
		cover := 0
		for cell in want.cover { if cell != {} { obstacles[cover] = cell; cover += 1 } }
		room := lasso_test_room(t, &data, &player, spawns[:count], obstacles = obstacles[:cover])
		struck := lasso_test_foe(&room, want.struck)
		for enemy in room.enemies { if enemy.position != (grid.Position{7, 6}) { lasso_test_hold(&room, enemy.id) } }
		if want.pool || want.fire {
			report: Action_Report
			testing.expectf(t, place_ground(&room, .Burn if want.fire else .Poison, want.landing, 2, &report), "%s: no ground", want.name)
			testing.expect_value(t, ground_burn_at(&room, want.struck), 0)
			testing.expect_value(t, ground_pool_at(&room, want.struck), 0)
		}
		pinball_test_strike(t, &room, lasso_test_foe(&room, {7, 6}))
		pinball_test_aim(&room, want.heading)
		events: [dynamic]Pinball_Test_Event
		pinball_test_roll(t, &room, 0.6, 1.0/120.0, &events)
		bumps: [dynamic]Game_Event
		pinball_test_events_of(events[:], .Pinball_Bumped, &bumps)
		testing.expectf(t, len(bumps) == 1 && bumps[0].target == enemy_entity(struck), "%s: %d bumps", want.name, len(bumps))
		testing.expectf(t, lasso_test_cell(&room, struck) == want.landing, "%s: on %v", want.name, lasso_test_cell(&room, struck))
		testing.expectf(t, lasso_test_health(&room, struck) == 38, "%s: %d hp", want.name, lasso_test_health(&room, struck))
		index, _ := enemy_index_by_id(&room, struck)
		_, poisoned := status_index(&room.enemies[index].statuses, .Poison)
		_, burning := status_index(&room.enemies[index].statuses, .Burn)
		testing.expectf(t, poisoned == want.pool && burning == want.fire, "%s: poisoned %v, burning %v",
			want.name, poisoned, burning)
		delete(bumps)
		delete(events)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// The ball rolls over the player (no bounce, no wound) and under the Lazzo's
// foe (no hit), on to the wall beyond them.
@(test)
test_pinball_rolls_over_the_player_and_under_the_lassoed_foe :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}, {position = {3, 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	held := lasso_test_foe(&room, {3, 6})
	lasso_test_hold(&room, held)
	pinball_test_strike(t, &room, lasso_test_foe(&room, {7, 6}))
	// The foe up on a rope (as the Lazzo's spin holds it: lasso.odin).
	room.lasso = {active = true, enemy_id = held, centre = room.player.position, radius = 3}
	index, _ := enemy_index_by_id(&room, held)
	room.enemies[index].intent, room.enemies[index].tactical_cooldown = {}, 0
	testing.expect(t, enemy_is_out_of_play(&room, held))
	health := player.health
	pinball_test_aim(&room, {-1, 0})
	events: [dynamic]Pinball_Test_Event
	defer delete(events)
	pinball_test_roll(t, &room, 1, 1.0/60.0, &events)
	first: Game_Event
	for seen in events {
		if seen.event.kind == .Pinball_Bounced || seen.event.kind == .Pinball_Bumped { first = seen.event; break }
	}
	testing.expect_value(t, first.kind, Game_Event_Kind.Pinball_Bounced)
	testing.expect_value(t, first.to_position, grid.Position{0, 6})
	for seen in events { testing.expect(t, seen.event.kind != .Pinball_Bumped) }
	testing.expect_value(t, player.health, health)
	testing.expect_value(t, lasso_test_health(&room, held), i32(30))
}

// A foe that comes onto the ball (here set down on its cell) is struck at
// once; while the ball still touches it, never again; once the ball has left
// it and comes back, again.
@(test)
test_pinball_strikes_a_foe_once_a_contact :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	pinball_test_strike(t, &room, room.enemies[0].id)
	pinball_test_aim(&room, {1, 0})
	pinball_test_roll(t, &room, 0.15, 1.0/60.0)
	testing.expect_value(t, room.pinball.cell, grid.Position{8, 6})
	// A body behind it stops its push: it stays under the ball.
	behind, _ := spawn_enemy(&room, {position = {7, 6}, health = 40, attack = 1})
	on, placed := spawn_enemy(&room, {position = {8, 6}, health = 40, attack = 1})
	testing.expect(t, placed && behind != 0)
	lasso_test_hold(&room, behind)
	lasso_test_hold(&room, on)
	events: [dynamic]Pinball_Test_Event
	defer delete(events)
	pinball_test_roll(t, &room, 0.9, 1.0/240.0, &events)
	hits: [dynamic]Game_Event
	defer delete(hits)
	walls := 0
	for seen in events {
		if seen.event.kind == .Pinball_Bounced { walls += 1 }
		if seen.event.kind != .Pinball_Bumped || seen.event.target != enemy_entity(on) { continue }
		append(&hits, seen.event)
		// The second only after the wall beyond it.
		if len(hits) == 2 { testing.expect(t, walls == 1) }
	}
	testing.expect_value(t, len(hits), 2)
	if len(hits) == 2 { testing.expect(t, hits[0].amount == 2 && hits[1].amount == 2) }
	testing.expect_value(t, lasso_test_cell(&room, on), grid.Position{8, 6})
}

// A blocking thing set down under the ball is rolled through until its disc
// has left it, then is solid as any; a coil is never set down under it.
@(test)
test_pinball_rolls_through_a_thing_set_under_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	pinball_test_strike(t, &room, room.enemies[0].id)
	pinball_test_aim(&room, {1, 0})
	pinball_test_roll(t, &room, 0.15, 1.0/60.0)
	testing.expect(t, pinball_covers_cell(&room, {8, 6}) && !pinball_covers_cell(&room, {9, 7}))
	testing.expect(t, !board_device_can_deploy(&room, .Tesla_Coil, {8, 6}))
	testing.expect(t, board_device_can_deploy(&room, .Tesla_Coil, {9, 7}))
	append(&room.objects, Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = {8, 6}, health = 4, max_health = 4})
	room.next_object_id += 1
	testing.expect(t, lasso_cell_is_solid(&room, {8, 6}))
	// Rolled on by hand: the disc lies over the block a while.
	bounced: [dynamic]Game_Event
	defer delete(bounced)
	for _ in 0..<240 {
		if !room.pinball.active { break }
		tactical_tick(&room, 1.0/120.0, true, false)
		drain_tactical_test_pulse(t, &room)
		for tactical_pinball_due(&room) {
			testing.expect(t, resolve_pinball_roll(&room))
			for event in room.recent_events.events[:room.recent_events.count] {
				if event.kind == .Pinball_Bounced { append(&bounced, event) }
			}
		}
	}
	// The east wall first, never the block; then back west the block's east face.
	if testing.expect(t, len(bounced) >= 2) {
		testing.expect_value(t, bounced[0].to_position, grid.Position{12, 6})
		testing.expect_value(t, bounced[1].to_position, grid.Position{8, 6})
	}
}

// No card's area or chain takes the ball: Toxic Wave's foes, a chain's
// bounces, an area's foes count only those on the floor.
@(test)
test_pinball_ball_is_on_no_card_area_or_chain :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}, {position = {7, 5}, health = 30, attack = 1}, {position = {7, 4}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	ball := lasso_test_foe(&room, {7, 6})
	near, far := lasso_test_foe(&room, {7, 5}), lasso_test_foe(&room, {7, 4})
	lasso_test_hold(&room, near)
	lasso_test_hold(&room, far)
	pinball_test_strike(t, &room, ball)
	testing.expect(t, enemy_is_pinball(&room, ball) && room.pinball.cell == grid.Position{7, 6})
	// Toxic Wave: every foe in its area, but the ball.
	wave := rework_hand_card(t, &room, .Toxic_Wave)
	action, error := compile_card_action(&room, wave, {})
	testing.expect_value(t, error, Card_Compile_Error.None)
	targets := 0
	for effect in action.effects[:action.effect_count] {
		testing.expect(t, effect.target != enemy_entity(ball))
		if effect.target.kind == .Enemy { targets += 1 }
	}
	testing.expect_value(t, targets, 2)
	// A chain from the foe beside the ball hops on to the far one, never to it.
	chain := rework_hand_card(t, &room, .Chain_Lightning)
	path := query_spell_path(&room, chain, entity_target(enemy_entity(near)))
	testing.expect_value(t, path.error, Card_Compile_Error.None)
	for entity in path.targets[:path.count] { testing.expect(t, entity != enemy_entity(ball)) }
	testing.expect(t, path.count >= 2 && path.targets[1] == enemy_entity(far))
	// An area over the ball's cell finds no foe there.
	result: Target_Query_Result
	result.affected.cells[0], result.affected.count = {7, 6}, 1
	collect_targeted_enemy_ids(&room, &result)
	testing.expect_value(t, result.enemy_count, 0)
}

// The launch's turn comes from the room's own stream: the same room and dice
// give the same turn, other rooms both ways and every whole degree from 15 to
// 35, never along the line; the card's aim shows the very launch it gives.
@(test)
test_pinball_launch_turn_comes_from_the_room_stream :: proc(t: ^testing.T) {
	player: Player
	player.dice.random_state = 0x1234_5678
	left, right := 0, 0
	seen: [PINBALL_MAX_TURN+1]bool
	for seed in u64(1)..=600 {
		random := pinball_room_stream(&player, {room_seed = seed})
		again := pinball_room_stream(&player, {room_seed = seed})
		testing.expect_value(t, random, again)
		turn := pinball_launch_turn(&random)
		testing.expect(t, abs(turn) >= PINBALL_MIN_TURN && abs(turn) <= PINBALL_MAX_TURN)
		if turn < 0 { left += 1 } else { right += 1 }
		seen[abs(turn)] = true
	}
	testing.expect(t, left > 200 && right > 200)
	for degrees in PINBALL_MIN_TURN..=PINBALL_MAX_TURN { testing.expectf(t, seen[degrees], "%d degrees never", degrees) }
	data: level.Level
	room_player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 7}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &room_player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	heading, turn := pinball_next_launch(&room, {7, 7})
	again, _ := pinball_next_launch(&room, {7, 7})
	testing.expect_value(t, again, heading)
	pinball_test_strike(t, &room, room.enemies[0].id)
	testing.expect_value(t, room.pinball.turn, turn)
	testing.expect(t, pinball_length(room.pinball.heading-heading) < 1e-12)
	// Diagonally beside him: the line itself at 45 degrees, turned.
	angle := math.PI/4+f64(turn)*math.PI/180
	testing.expect(t, abs(heading.x-math.cos(angle)) < 1e-12 && abs(heading.y-math.sin(angle)) < 1e-12)
}

// Twenty seconds waiting at once in a narrow corridor (a bounce a few
// hundredths of a second): the roll goes out in several batches, none near a
// full log, not an event dropped, and the burst once, at the end.
@(test)
test_pinball_long_rolls_go_out_in_batches_and_burst_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	cover: [22]grid.Position
	for x in 1..=11 { cover[x-1], cover[10+x] = {x, 5}, {x, 7} }
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:], obstacles = cover[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.endless = true
	id := room.enemies[0].id
	pinball_test_strike(t, &room, id)
	pinball_test_aim(&room, {math.cos(f64(0.5)), math.sin(f64(0.5))})
	tactical_pinball_tick(&room, f32(PINBALL_SECONDS)+1)
	batches, bounces, bursts := 0, 0, 0
	for tactical_pinball_due(&room) && batches < 64 {
		testing.expect(t, resolve_pinball_roll(&room))
		batches += 1
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		testing.expect(t, room.recent_events.count <= MAX_GAME_EVENTS-PINBALL_EVENT_HEADROOM+8)
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind == .Pinball_Bounced { bounces += 1 }
			if event.kind == .Pinball_Burst { bursts += 1 }
		}
	}
	testing.expect(t, batches >= 2)
	testing.expect(t, bounces > MAX_GAME_EVENTS)
	testing.expect_value(t, bursts, 1)
	testing.expect(t, !room.pinball.active && lasso_test_health(&room, id) == 0)
}

// The fight's end (the player fallen) stops the roll: the foe it was stays
// on its cell, alive, carrying nothing; a new room starts with no ball.
@(test)
test_pinball_ends_with_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}, {position = {2, 2}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	id := lasso_test_foe(&room, {7, 6})
	lasso_test_hold(&room, lasso_test_foe(&room, {2, 2}))
	pinball_test_strike(t, &room, id)
	pinball_test_roll(t, &room, 0.3, 1.0/60.0)
	player.health = 1
	blow := make_action(.Attack, enemy_entity(lasso_test_foe(&room, {2, 2})))
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 50)))
	testing.expect(t, resolve_action(&room, &blow).accepted)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	tactical_end_combat(&room)
	testing.expect(t, !room.pinball.active && !enemy_is_pinball(&room, id))
	testing.expect_value(t, lasso_test_health(&room, id), i32(30))
	testing.expect(t, !tactical_pinball_due(&room))
	fresh_data: level.Level
	fresh_player: Player
	fresh := lasso_test_room(t, &fresh_data, &fresh_player, spawns[:])
	testing.expect(t, !fresh.pinball.active && fresh.pinball_random != 0)
	destroy_room(&fresh)
	level.destroy(&fresh_data)
}

// Its bites end as it turns: a Veleno and a Bruciatura it carried never bite
// the ball (a window's end, the world's beats), and no new one takes; its
// foe's life is untouched until its burst.
@(test)
test_pinball_ball_carries_no_bite :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.endless = true
	id := room.enemies[0].id
	_, _ = apply_status(&room, enemy_entity(id), .Burn, 3, 0)
	_, _ = apply_status(&room, enemy_entity(id), .Poison, 3, 0)
	_, _ = apply_status(&room, enemy_entity(id), .Slow, 2, 0)
	pinball_test_strike(t, &room, id)
	index, _ := enemy_index_by_id(&room, id)
	testing.expect_value(t, room.enemies[index].statuses.count, 0)
	_, applied := apply_status(&room, enemy_entity(id), .Burn, 2, 0)
	testing.expect(t, !applied)
	// Two windows' ends with their bites, and the world's beats: nothing.
	for _ in 0..<2 {
		player.tactical.remaining = 0
		testing.expect(t, tactical_expire_window(&room))
		player.tactical.phase, player.tactical.remaining = .Decision, f32(player.tactical.budget)
	}
	pinball_test_roll(t, &room, 5, 1.0/30.0)
	testing.expect_value(t, lasso_test_health(&room, id), i32(30))
}

// The ball's marks on its wounds are its own: never the Lazzo's, nor a turn's.
@(test)
test_pinball_marks_are_its_own :: proc(t: ^testing.T) {
	ball := Game_Event{kind = .Damaged, area_mask = EVENT_PINBALL_BIT}
	hit := Game_Event{kind = .Damaged, area_mask = EVENT_LASSO_BIT}
	turn := Game_Event{kind = .Damaged, area_mask = EVENT_LASSO_BIT|EVENT_LASSO_TURN_BIT}
	testing.expect(t, event_is_pinball(ball) && !event_is_lasso(ball) && !event_is_lasso_turn(ball))
	testing.expect(t, !event_is_pinball(hit) && event_is_lasso(hit) && !event_is_lasso_turn(hit))
	testing.expect(t, !event_is_pinball(turn) && event_is_lasso(turn) && event_is_lasso_turn(turn))
	critical := ball
	critical.area_mask |= EVENT_CRITICAL_BIT
	testing.expect(t, event_is_pinball(critical))
}
