package integration
import run_session "../run"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:testing"
import "core:time"
import advisor "../advisor"
import campaign "../campaign"
import expedition "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE ADVISOR'S COPY AND SIMULATOR (docs/piano-ia.md, Fase 1): the copy never touches the real room, knows every field
// that points elsewhere, gives the same game twice from the same moves, copies the level and the pools again only
// when a try changed them, and plays a game exactly as the game itself does (the same commands through
// run.execute_gameplay_command, the same world frames).

// The IA's arena with `config`, its foes free to plan.
@(private = "file")
advisor_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, config := game.DEFAULT_TACTICAL_CONFIG) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, config, .IA)
	testing.expect(t, built)
	return room
}

// A move the player could try now, picked with `generator`: a step, a dodge, a wait, a card of the hand on a fitting
// target (the nearest foe's cell, or himself), now and then a refocus.
@(private = "file")
advisor_test_move :: proc(room: ^game.Room, generator: runtime.Random_Generator) -> advisor.Move {
	roll := rand.int_max(20, generator)
	direction := game.Move_Direction(rand.int_max(4, generator))
	switch {
	case roll < 9: return {kind = .Step, direction = direction}
	case roll < 11: return {kind = .Dodge, direction = direction}
	case roll < 13: return {kind = .Wait}
	case roll == 13: return {kind = .Refocus}
	}
	deck := &room.player.deck
	if deck.hand_count == 0 { return {kind = .Wait} }
	card := deck.hand[rand.int_max(deck.hand_count, generator)]
	target := game.entity_target(game.PLAYER_ENTITY)
	nearest, best := grid.Position{}, max(int)
	for enemy in room.enemies {
		d := max(abs(enemy.position.x-room.player.position.x), abs(enemy.position.y-room.player.position.y))
		if d < best { nearest, best = enemy.position, d }
	}
	if best != max(int) {
		if aimed, ok := game.card_drop_target(room, card, nearest); ok { target = aimed }
	}
	return {kind = .Card, card_id = card.id, target = target, direction = direction}
}

// The same move as the game's own command.
@(private = "file")
advisor_test_command :: proc(move: advisor.Move) -> run_session.Gameplay_Command {
	command := run_session.Gameplay_Command{origin_phase = .Combat, direction = move.direction, card_id = move.card_id, target = move.target}
	switch move.kind {
	case .Step: command.kind = .Move
	case .Dodge: command.kind = .Dodge
	case .Wait: command.kind = .Wait
	case .Card: command.kind = .Play_Card
	case .Refocus: command.kind = .Refocus
	}
	return command
}

// One frame of the game itself, with no key pressed and no window: the controller's order
// (run.step_tactical_controller), every world command through run.execute_gameplay_command.
@(private = "file")
advisor_test_real_frame :: proc(room: ^game.Room, dt: f32) {
	world :: proc(room: ^game.Room, kind: run_session.Gameplay_Command_Kind) -> bool {
		return run_session.execute_gameplay_command(room, {kind = kind, origin_phase = .Combat}).committed
	}
	drain :: proc(room: ^game.Room) -> bool {
		budget := (max(0, room.player.tactical.queued_beats)+1)*(game.MAX_ENEMIES_PER_ROOM+2)
		for _ in 0..<budget {
			if room.qte.kind != .None { return false }
			if room.phase != .Combat || !room.tactical_pulse.pending { return true }
			if !world(room, .Continue_Pulse) { return false }
		}
		return room.qte.kind == .None && !room.tactical_pulse.pending
	}
	if room.phase != .Combat { game.lift_tick(room, dt); return }
	if game.tactical_is_casting(room) { game.tactical_tick(room, dt, true, false); return }
	if room.qte.kind != .None {
		room.qte.remaining = max(f32(0), room.qte.remaining-dt)
		if room.qte.remaining <= 0 { world(room, .QTE_Fail) }
		return
	}
	if !drain(room) { return }
	game.tactical_tick(room, dt, true, false)
	if !drain(room) { return }
	for _ in 0..<run_session.LASSO_SPIN_BATCHES { if !game.tactical_lasso_due(room) || !world(room, .Lasso_Spin) { break } }
	for _ in 0..<run_session.PINBALL_ROLL_BATCHES { if !game.tactical_pinball_due(room) || !world(room, .Pinball_Roll) { break } }
	for _ in 0..<run_session.ENEMY_FLIGHT_BATCHES { if !game.tactical_flights_due(room) || !world(room, .Enemy_Flight) { break } }
	if game.tactical_tick(room, 0, true, false) {
		if run_session.execute_gameplay_command(room, {kind = .Timeout, origin_phase = .Combat}).committed { room.player.tactical.metrics.timeouts += 1 }
	}
}

@(private = "file")
advisor_test_real_until_free :: proc(room: ^game.Room, step: f32, limit: f32 = 10) {
	for ran := f32(0); ran < limit; ran += step {
		if room.phase != .Combat || advisor.player_free(room) { return }
		advisor_test_real_frame(room, step)
	}
}

// Every field reachable from the room that points elsewhere, as reflection finds it.
@(private = "file")
advisor_test_pointing_fields :: proc(info: ^runtime.Type_Info, path: string, out: ^[dynamic]string, depth := 0) {
	if depth > 12 { return }
	base := runtime.type_info_base(info)
	#partial switch v in base.variant {
	case runtime.Type_Info_Pointer, runtime.Type_Info_Multi_Pointer, runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array,
	     runtime.Type_Info_Map, runtime.Type_Info_Any, runtime.Type_Info_Procedure:
		append(out, path)
	case runtime.Type_Info_Struct:
		for i in 0..<v.field_count { advisor_test_pointing_fields(v.types[i], fmt.tprintf("%s.%s", path, v.names[i]), out, depth+1) }
	case runtime.Type_Info_Array: advisor_test_pointing_fields(v.elem, fmt.tprintf("%s[*]", path), out, depth+1)
	case runtime.Type_Info_Enumerated_Array: advisor_test_pointing_fields(v.elem, fmt.tprintf("%s[*]", path), out, depth+1)
	case runtime.Type_Info_Union: for variant in v.variants { advisor_test_pointing_fields(variant, path, out, depth+1) }
	}
}

// The rule for ever (docs/piano-ia.md): a field of the room that points elsewhere and the copy does not know fails here.
@(test)
test_advisor_copy_knows_every_field_that_points :: proc(t: ^testing.T) {
	found := make([dynamic]string, context.temp_allocator)
	advisor_test_pointing_fields(type_info_of(game.Room), "Room", &found)
	for info, name in ([?]struct{ info: ^runtime.Type_Info, name: string }{
		{type_info_of(game.Player), "Player"}, {type_info_of(game.Enemy), "Enemy"}, {type_info_of(game.Grid_Object), "Grid_Object"},
		{type_info_of(game.Trap), "Trap"}, {type_info_of(game.Loot), "Loot"}, {type_info_of(game.Obstacle), "Obstacle"},
		{type_info_of(level.Level), "Level"},
	}) {
		_ = name
		advisor_test_pointing_fields(info.info, info.name, &found)
	}
	known := advisor.COPIED_FIELDS
	for path in found { testing.expectf(t, slice.contains(known[:], path), "the advisor's copy does not know %s", path) }
	for path in known { testing.expectf(t, slice.contains(found[:], path), "%s is gone from the game: take it off the copy", path) }
}

// A thousand tries of random moves on copies: the real room is the same field by field, its log untouched, and the
// game's memory never asked for anything.
@(test)
test_advisor_never_touches_the_real_room :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := advisor_test_arena(t, &data, &player)
	defer { game.destroy_room(&room); level.destroy(&data) }
	before: advisor.Snapshot
	testing.expect(t, advisor.snapshot_init(&before))
	defer advisor.snapshot_destroy(&before)
	testing.expect(t, advisor.snapshot_take(&before, &room))
	log_before := room.recent_events^
	snapshot: advisor.Snapshot
	rehearsal: advisor.Rehearsal
	testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&rehearsal))
	defer { advisor.snapshot_destroy(&snapshot); advisor.rehearsal_destroy(&rehearsal) }
	testing.expect(t, advisor.snapshot_take(&snapshot, &room) && advisor.rehearsal_begin(&rehearsal, &snapshot))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	generator := rand.default_random_generator()
	rand.reset(1, generator)
	{
		context.allocator = mem.tracking_allocator(&tracking)
		for _ in 0..<1000 {
			copy := advisor.rehearsal_room(&rehearsal)
			for _ in 0..<3 {
				advisor.play(&rehearsal, advisor_test_move(copy, generator))
				advisor.run_until_free(&rehearsal, 1.0/60.0)
			}
		}
	}
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, tracking.total_allocation_count, i64(0))
	equal, at := advisor.rooms_equal(&room, &before.room)
	testing.expectf(t, equal, "the real room changed at %s", at)
	testing.expect(t, room.recent_events.count == log_before.count && mem.compare(mem.ptr_to_bytes(room.recent_events), mem.ptr_to_bytes(&log_before)) == 0)
}

// The same moves from the same snapshot give the same game.
@(test)
test_advisor_tries_are_deterministic :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := advisor_test_arena(t, &data, &player, game.GAME_TACTICAL_CONFIG)
	defer { game.destroy_room(&room); level.destroy(&data) }
	snapshot: advisor.Snapshot
	first, second: advisor.Rehearsal
	testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&first) && advisor.rehearsal_init(&second))
	defer { advisor.snapshot_destroy(&snapshot); advisor.rehearsal_destroy(&first); advisor.rehearsal_destroy(&second) }
	testing.expect(t, advisor.snapshot_take(&snapshot, &room) && advisor.rehearsal_begin(&first, &snapshot) && advisor.rehearsal_begin(&second, &snapshot))
	for seed in u64(1)..=20 {
		a, b := advisor.rehearsal_room(&first), advisor.rehearsal_room(&second)
		generator_a, generator_b := rand.default_random_generator(), rand.default_random_generator()
		state_a, state_b: rand.Default_Random_State
		generator_a.data, generator_b.data = &state_a, &state_b
		rand.reset(seed, generator_a)
		rand.reset(seed, generator_b)
		for _ in 0..<12 {
			advisor.play(&first, advisor_test_move(a, generator_a))
			advisor.run_until_free(&first, 1.0/60.0)
			advisor.play(&second, advisor_test_move(b, generator_b))
			advisor.run_until_free(&second, 1.0/60.0)
		}
		equal, at := advisor.rooms_equal(a, b)
		testing.expectf(t, equal, "seed %d: the two games part at %s", seed, at)
	}
}

// A try that writes the pools or changes the level has them copied again for the next try, and only then.
@(test)
test_advisor_copies_level_and_pools_again_only_when_changed :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := advisor_test_arena(t, &data, &player)
	defer { game.destroy_room(&room); level.destroy(&data) }
	snapshot: advisor.Snapshot
	rehearsal: advisor.Rehearsal
	testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&rehearsal))
	defer { advisor.snapshot_destroy(&snapshot); advisor.rehearsal_destroy(&rehearsal) }
	testing.expect(t, advisor.snapshot_take(&snapshot, &room) && advisor.rehearsal_begin(&rehearsal, &snapshot))
	copy := advisor.rehearsal_room(&rehearsal)
	advisor.play(&rehearsal, {kind = .Wait})
	copy = advisor.rehearsal_room(&rehearsal)
	testing.expect(t, rehearsal.level_copies == 0 && rehearsal.pool_copies == 0)
	// A pool poured and a wall raised on the copy.
	cell := grid.offset(copy.player.position, 2, 0)
	action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
	testing.expect(t, game.add_effect(&action, game.place_ground_effect(cell, .Poison, 2)))
	report := game.resolve_action(copy, &action)
	testing.expect(t, report.accepted && copy.ground.pool_writes != snapshot.room.ground.pool_writes)
	testing.expect(t, level.set_tile(copy.level_data, grid.offset(copy.player.position, 0, 3), {kind = .Wall}))
	copy = advisor.rehearsal_room(&rehearsal)
	testing.expect_value(t, rehearsal.level_copies, 1)
	testing.expect_value(t, rehearsal.pool_copies, 1)
	equal, at := advisor.rooms_equal(copy, &snapshot.room)
	testing.expectf(t, equal, "the copy after the changes differs at %s", at)
	testing.expect(t, slice.equal(copy.ground.pool, snapshot.room.ground.pool))
	// The real room never saw either.
	testing.expect(t, slice.equal(room.ground.pool, snapshot.room.ground.pool))
}

// The same games played by the game and by the copy: after every move the two rooms are the same, field by field.
// 100 games of 15 moves in the lab's pace and 100 in the game's as it is played (no window).
@(test)
test_advisor_plays_the_game_as_the_game_does :: proc(t: ^testing.T) {
	for config, which in ([2]game.Tactical_Config{game.DEFAULT_TACTICAL_CONFIG, game.GAME_TACTICAL_CONFIG}) {
		for seed in u64(1)..=100 {
			data: level.Level
			player: game.Player
			room := advisor_test_arena(t, &data, &player, config)
			snapshot: advisor.Snapshot
			rehearsal: advisor.Rehearsal
			testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&rehearsal))
			testing.expect(t, advisor.snapshot_take(&snapshot, &room) && advisor.rehearsal_begin(&rehearsal, &snapshot))
			copy := advisor.rehearsal_room(&rehearsal)
			state: rand.Default_Random_State
			generator := rand.default_random_generator(&state)
			rand.reset(seed+u64(which)*1000, generator)
			parted := false
			for step in 0..<15 {
				if room.phase != .Combat { break }
				move := advisor_test_move(&room, generator)
				real_took := run_session.execute_gameplay_command(&room, advisor_test_command(move)).committed
				copy_took := advisor.play(&rehearsal, move)
				advisor_test_real_until_free(&room, 1.0/60.0)
				advisor.run_until_free(&rehearsal, 1.0/60.0)
				equal, at := advisor.rooms_equal(&room, copy)
				// The same events too: what the game would show and sound is what the copy wrote (and nobody reads).
				if equal && room.recent_events.count != copy.recent_events.count {
					equal, at = false, fmt.tprintf("the log (%d events, %d)", room.recent_events.count, copy.recent_events.count)
				}
				if equal {
					for event, index in room.recent_events.events[:room.recent_events.count] {
						other := copy.recent_events.events[index]
						if event.kind != other.kind || event.source != other.source || event.target != other.target || event.amount != other.amount ||
						   event.from_position != other.from_position || event.to_position != other.to_position {
							equal, at = false, fmt.tprintf("the log's event %d (%v, %v)", index, event.kind, other.kind)
							break
						}
					}
				}
				if real_took != copy_took || !equal {
					testing.expectf(t, false, "config %d seed %d move %d (%v): the game took it %v, the copy %v; they part at %s",
						which, seed, step, move.kind, real_took, copy_took, at)
					parted = true
					break
				}
			}
			advisor.snapshot_destroy(&snapshot)
			advisor.rehearsal_destroy(&rehearsal)
			game.destroy_room(&room)
			level.destroy(&data)
			if parted { return }
		}
	}
}

// What a copy and a second of the world cost, in the IA's arena, the arena of structures and the largest expedition
// (Space, 224x224 cells with its layers). Logged for the plan's Esito; nothing is asserted but that it runs.
@(test)
test_advisor_measures :: proc(t: ^testing.T) {
	measure :: proc(t: ^testing.T, name: string, room: ^game.Room) {
		snapshot: advisor.Snapshot
		rehearsal: advisor.Rehearsal
		testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&rehearsal))
		defer { advisor.snapshot_destroy(&snapshot); advisor.rehearsal_destroy(&rehearsal) }
		start := time.tick_now()
		for _ in 0..<20 { advisor.snapshot_take(&snapshot, room) }
		take := time.duration_microseconds(time.tick_since(start))/20
		start = time.tick_now()
		for _ in 0..<20 { advisor.rehearsal_begin(&rehearsal, &snapshot) }
		begin := time.duration_microseconds(time.tick_since(start))/20
		start = time.tick_now()
		tries := 500
		for _ in 0..<tries { advisor.rehearsal_room(&rehearsal) }
		per_try := time.duration_microseconds(time.tick_since(start))/f64(tries)
		// Seconds of the world: a wait and the world run until the player is free, again and again.
		simulated := f32(0)
		start = time.tick_now()
		for _ in 0..<50 {
			advisor.rehearsal_room(&rehearsal)
			for _ in 0..<4 {
				advisor.play(&rehearsal, {kind = .Wait})
				simulated += advisor.run_until_free(&rehearsal, 1.0/60.0)
			}
		}
		spent := time.duration_microseconds(time.tick_since(start))
		log.infof("ADVISOR %s: snapshot %.0f us, rehearsal %.0f us, a try's copy %.1f us (%d foes), a second of the world %.0f us (%.1f s simulated)",
			name, take, begin, per_try, len(room.enemies), spent/f64(max(simulated, 0.001)), simulated)
	}
	{
		data: level.Level
		player: game.Player
		room := advisor_test_arena(t, &data, &player, game.GAME_TACTICAL_CONFIG)
		measure(t, "IA arena", &room)
		game.destroy_room(&room)
		level.destroy(&data)
	}
	{
		data: level.Level
		player: game.Player
		created: bool
		player, created = game.create_player(run_session.DEMO_PLAYER_STATS)
		testing.expect(t, created)
		room, built := run_session.create_mechanics_lab_room(&data, &player, game.GAME_TACTICAL_CONFIG, .Structures)
		testing.expect(t, built)
		measure(t, "structures arena", &room)
		game.destroy_room(&room)
		level.destroy(&data)
	}
	{
		w: expedition.World
		data: level.Level
		player: game.Player
		testing.expect(t, expedition.generate(&w, &data, campaign.Biome.Space, 42))
		created: bool
		player, created = game.create_player({100, 5, 0})
		testing.expect(t, created)
		// A fight that never ends by itself, as the lab's: its foes come on the open map.
		room, built := game.create_room(&data, &player, {room_seed = 42, endless = true})
		testing.expect(t, built && game.configure_expedition_combat(&room))
		room.endless = true
		for offset in ([4]grid.Position{{x = 4, y = 0}, {x = -4, y = 1}, {x = 2, y = 4}, {x = -1, y = -4}}) {
			game.spawn_enemy(&room, {position = grid.offset(player.position, offset.x, offset.y), health = 20, attack = 2, archetype = .Chaser})
		}
		measure(t, fmt.tprintf("expedition Space %dx%d", data.tiles.width, data.tiles.height), &room)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}
