package integration

import "core:testing"
import "core:time"
import advisor "../advisor"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"
import run_session "../run"

@(private = "file")
advisor_target_input_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, card_id: game.Card_Id = .Arc_Bolt) -> game.Room {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#..@#...#", "#......>#", "#########"}
	err: level.Parse_Error
	data^, err, _ = level.from_ascii(rows[:])
	testing.expect_value(t, err, .None)
	created: bool
	player^, created = game.create_player({max_health = 20, attack = 1})
	testing.expect(t, created)
	configure_single_card_test_deck(t, player, card_id)
	config := game.EXPEDITION_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	foes := [?]game.Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 2, attack = 1},
		{position = {x = 5, y = 4}, health = 2, attack = 1},
	}
	room, built := game.create_room(data, player, {enemies = foes[:]})
	testing.expect(t, built)
	// Stable bodies isolate LOS and the target contract. They remain genuine
	// enemies in the shared simulator; no targeting result is mocked.
	for &enemy in room.enemies { enemy.recovery_pulses, enemy.intent, enemy.tactical_cooldown = 99, {}, 0 }
	game.plan_enemy_intents(&room)
	return room
}

@(test)
test_held_advisor_card_tracks_a_legal_foe_and_drops_a_blocked_target :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := advisor_target_input_room(t, &data, &player)
	defer game.destroy_room(&room)
	search := new(advisor.Search)
	defer free(search)
	if !testing.expect(t, advisor.search_init(search)) { return }
	defer advisor.search_destroy(search)
	held := advisor.search_whole(search, &room, 4000)
	if !testing.expect(t, held.valid && held.kind == .Card) { return }
	index, found := game.enemy_index_by_id(&room, held.move.target.entity.id)
	if !testing.expect(t, found) { return }
	// Time alone is no player action and no reason to discard this decision.
	game.tactical_tick(&room, .125, true, false)
	testing.expect(t, advisor.advice_possible(&room, held, player.position))
	// The same entity takes a legal step: keep the move, but point at where
	// the card would now land, exactly as the entity-targeted command does.
	room.enemies[index].position = {x = 3, y = 2}
	testing.expect(t, advisor.advice_possible(&room, held, player.position))
	testing.expect_value(t, run_session.advisor_view(&room, held).cell, room.enemies[index].position)
	// The target is now behind the wall but still within the printed range.
	// The pilot must classify this as impossible, independently of search work.
	room.enemies[index].position = {x = 6, y = 4}
	card := player.deck.hand[0]
	definition, _ := game.card_definition_by_id(card.definition_id)
	request, resolved := game.card_target_request_from_target(&room, definition, held.move.target)
	testing.expect(t, resolved && game.evaluate_card_targeting(&room, card, request).error == .Target_Blocked)
	testing.expect(t, !advisor.advice_possible(&room, held, player.position))
	unordered_remove(&room.enemies, index)
	testing.expect(t, !advisor.advice_possible(&room, held, player.position))
}

@(test)
test_held_advisor_card_validity_covers_self_and_cell_targets :: proc(t: ^testing.T) {
	for id in ([2]game.Card_Id{.Guard, .Dash}) {
		data: level.Level
		defer level.destroy(&data)
		player: game.Player
		room := advisor_target_input_room(t, &data, &player, id)
		defer game.destroy_room(&room)
		moves: [advisor.MAX_CANDIDATES]advisor.Move
		count := advisor.card_plays(&room, moves[:])
		if !testing.expect(t, count > 0) { continue }
		move := moves[0]
		// This is an actual candidate produced by the IA, not a mocked target.
		held := advisor.Advice{valid = true, kind = .Card, move = move, cell = advisor.target_cell(&room, move.target)}
		testing.expect(t, advisor.advice_possible(&room, held, player.position))
		game.tactical_tick(&room, .125, true, false)
		testing.expect(t, advisor.advice_possible(&room, held, player.position))
		if id == .Guard {
			testing.expect_value(t, move.target, game.entity_target(game.PLAYER_ENTITY))
			player.deck.energy = 0
			testing.expect(t, !advisor.advice_possible(&room, held, player.position))
		} else {
			testing.expect_value(t, move.target.kind, .Cell)
			append(&room.obstacles, game.Obstacle{position = move.target.cell})
			card := player.deck.hand[0]
			definition, _ := game.card_definition_by_id(id)
			query := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, move.target.cell))
			testing.expect_value(t, query.error, .Target_Blocked)
			testing.expect(t, !advisor.advice_possible(&room, held, player.position))
		}
	}
}

@(test)
test_advisor_card_target_matches_preview_and_execution_around_cover :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := advisor_target_input_room(t, &data, &player)
	defer game.destroy_room(&room)
	card := player.deck.hand[0]
	definition, found := game.card_definition_by_id(card.definition_id)
	testing.expect(t, found)
	visible, covered := grid.Position{x = 3, y = 1}, grid.Position{x = 5, y = 4}
	bad_preview := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, covered))
	testing.expect(t, bad_preview.error == .Target_Blocked && bad_preview.query.error == .Line_Of_Sight_Blocked)
	_, accepted := run_session.targeted_card_command(&room, card, covered)
	testing.expect(t, !accepted)
	targets: [advisor.MAX_CARD_TARGETS]advisor.Card_Target
	count := advisor.card_targets(&room, card, &targets)
	testing.expect_value(t, count, 1)
	if !testing.expect(t, count > 0) { return }
	testing.expect_value(t, targets[0].cell, visible)

	search := new(advisor.Search)
	defer free(search)
	if !testing.expect(t, advisor.search_init(search)) { return }
	defer advisor.search_destroy(search)
	advice := advisor.search_whole(search, &room, 4000)
	if !testing.expect(t, advice.valid && advice.kind == .Card && advice.move.card_id == card.id) { return }
	testing.expect_value(t, advice.cell, visible)
	preview := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, advice.cell))
	testing.expect(t, preview.error == .None && preview.query.primary_target == advice.move.target)
	mark := run_session.advisor_view(&room, advice)
	testing.expect(t, mark.mark == .Card && mark.card_id == card.id && mark.cell == preview.query.anchor)
	human, legal := run_session.targeted_card_command(&room, card, advice.cell)
	commands, command_count := run_session.advisor_move_commands(&room, advice.move)
	if !testing.expect(t, legal && command_count == 1) { return }
	testing.expect(t, human.target == commands[0].target && human.card_id == commands[0].card_id)
	testing.expect_value(t, human.direction, commands[0].direction)

	snapshot: advisor.Snapshot
	rehearsal: advisor.Rehearsal
	if !testing.expect(t, advisor.snapshot_init(&snapshot)) { return }
	defer advisor.snapshot_destroy(&snapshot)
	if !testing.expect(t, advisor.rehearsal_init(&rehearsal)) { return }
	defer advisor.rehearsal_destroy(&rehearsal)
	testing.expect(t, advisor.snapshot_take(&snapshot, &room) && advisor.rehearsal_begin(&rehearsal, &snapshot))
	copy := advisor.rehearsal_room(&rehearsal)
	testing.expect(t, advisor.play(&rehearsal, advice.move))
	testing.expect(t, run_session.execute_gameplay_command(&room, human).committed)
	equal, at := advisor.rooms_equal(&room, copy)
	testing.expectf(t, equal, "the preview's human command and advisor copy differ at %s", at)
	_, alive := game.enemy_index_at(&room, visible)
	testing.expect(t, !alive)
	index, blocked_alive := game.enemy_index_at(&room, covered)
	testing.expect(t, blocked_alive && room.enemies[index].health == 2)
}

@(test)
test_cancelled_advisor_card_never_executes_or_releases_the_held_advice :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := advisor_target_input_room(t, &data, &player)
	defer game.destroy_room(&room)
	renderer := new_clone(render.create(960, 540))
	defer free(renderer)
	defer run_session.advisor_pilot_release()
	player.tactical.ia_remaining = 999
	started := time.tick_now()
	for !run_session.advisor_current_advice().valid && time.duration_seconds(time.tick_since(started)) < 10 {
		run_session.drive_advisor(&room, renderer, 0)
		time.sleep(time.Millisecond)
	}
	held := run_session.advisor_current_advice()
	if !testing.expect(t, held.valid) { return }
	run_session.advisor_pilot_hold(true)
	generation := run_session.advisor_pilot_generation()
	card := player.deck.hand[0]
	targets: [advisor.MAX_CARD_TARGETS]advisor.Card_Target
	if !testing.expect(t, advisor.card_targets(&room, card, &targets) == 1) { return }
	move := advisor.Move{kind = .Card, card_id = card.id, target = targets[0].target, direction = .North}
	commands, count := run_session.advisor_move_commands(&room, move)
	if !testing.expect(t, count == 1) { return }
	before, fingerprint := player, advisor.state_fingerprint(&room)
	for cancel in ([2]run_session.Run_Input{{right_pressed = true}, {actions = {pressed = {.Cancel}}}}) {
		buffer: run_session.Buffered_Gameplay_Command
		_, emitted := run_session.route_gameplay_command(&buffer, &room, true, commands[0], true, 1.0/60)
		testing.expect(t, !emitted && buffer.has_pending)
		cards := run_session.Card_Interaction_State{selected_card_id = card.id}
		polled, has := run_session.poll_gameplay_command(&room, renderer, &cards, {470, 240}, true, true, controls = cancel)
		testing.expect(t, !has)
		ready, passed := run_session.route_gameplay_command(&buffer, &room, false, polled, has, 1.0/60, controls = cancel)
		// Exercise the same dispatcher if a regression leaks the cancelled edge.
		if passed { run_session.execute_gameplay_command(&room, ready) }
		testing.expect(t, !passed && !buffer.has_pending)
		testing.expect_value(t, player, before)
		testing.expect_value(t, advisor.state_fingerprint(&room), fingerprint)
		run_session.drive_advisor(&room, renderer, 0)
		testing.expect_value(t, run_session.advisor_current_advice(), held)
		testing.expect_value(t, run_session.advisor_pilot_generation(), generation)
	}
}
