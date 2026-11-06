package run

import "core:testing"
import game "../game"
import level "../level"
import render "../render"
import view "../engine/view"

@(private)
Card_Input_Fixture :: struct {
	data: level.Level,
	player: game.Player,
	room: game.Room,
	renderer: render.Renderer,
	cards: Card_Interaction_State,
}

@(private)
card_input_fixture :: proc(t: ^testing.T) -> ^Card_Input_Fixture {
	f := new(Card_Input_Fixture)
	rows := [?]string{"#######", "#@....#", "#..>..#", "#.....#", "#######"}
	data, err, _ := level.from_ascii(rows[:])
	if !testing.expect(t, err == .None) { free(f); return nil }
	f.data = data
	player, created := game.create_player({max_health = 30, attack = 2, defense = 1})
	if !testing.expect(t, created) { level.destroy(&f.data); free(f); return nil }
	f.player = player
	initialized := game.initialize_empty_deck(&f.player.deck, {hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1}, 99)
	testing.expect(t, initialized)
	ids := [3]game.Card_Id{.Cannon, .Firebomb, .Strike}
	for id in ids {
		_, added := game.add_owned_card(&f.player.deck, id)
		testing.expect(t, added)
	}
	configured := game.configure_tactical(&f.player, game.EXPEDITION_TACTICAL_CONFIG)
	testing.expect(t, configured)
	foes := [1]game.Enemy_Spawn{{position = {x = 4, y = 2}, health = 40, attack = 1}}
	room, built := game.create_room(&f.data, &f.player, {enemies = foes[:], room_seed = 42})
	if !testing.expect(t, built) { level.destroy(&f.data); free(f); return nil }
	f.room = room
	f.renderer = render.create(960, 540)
	f.renderer.tactical.expedition = true
	f.renderer.has_hovered_cell, f.renderer.hovered_cell = true, {x = 3, y = 1}
	return f
}

@(private)
card_input_fixture_destroy :: proc(f: ^Card_Input_Fixture) {
	game.destroy_room(&f.room)
	level.destroy(&f.data)
	free(f)
}

@(private)
card_input_find :: proc(f: ^Card_Input_Fixture, id: game.Card_Id) -> (game.Card_Instance, int) {
	for card, i in f.player.deck.hand[:f.player.deck.hand_count] { if card.definition_id == id { return card, i } }
	return {}, -1
}

@(test)
test_card_cancel_drops_pending_play_without_spending_or_replaying :: proc(t: ^testing.T) {
	for busy in 0..<2 {
		f := card_input_fixture(t)
		if f == nil { return }
		card, _ := card_input_find(f, .Firebomb)
		command, valid := targeted_card_command(&f.room, card, f.room.enemies[0].position)
		testing.expect(t, valid)
		buffer: Buffered_Gameplay_Command
		_, emitted := route_gameplay_command(&buffer, &f.room, true, command, true, 1.0/60)
		testing.expect(t, !emitted && buffer.has_pending)
		f.cards.selected_card_id = card.id
		before := f.player
		health_before := f.room.enemies[0].health
		controls := Run_Input{right_pressed = true}
		polled, has := poll_gameplay_command(&f.room, &f.renderer, &f.cards, {470, 240}, true, true, controls = controls)
		testing.expect(t, !has && active_targeting_card_id(f.cards) == 0)
		ready, played := route_gameplay_command(&buffer, &f.room, busy != 0, polled, has, 1.0/60, controls = controls)
		if played { _ = execute_gameplay_command(&f.room, ready) }
		testing.expect(t, !played && !buffer.has_pending, "right-click cancellation kept or replayed the queued card")
		ready, played = route_gameplay_command(&buffer, &f.room, false, {}, false, 1.0/60)
		if played { _ = execute_gameplay_command(&f.room, ready) }
		testing.expect(t, !played, "the cancelled card replayed when the busy lane reopened")
		testing.expect(t, f.player == before && f.room.enemies[0].health == health_before,
			"cancelling a queued card spent energy, time, or damaged its target")
		card_input_fixture_destroy(f)
	}
}

@(test)
test_card_change_during_placement_releases_orientation_for_keyboard_and_drag :: proc(t: ^testing.T) {
	for dragging in 0..<2 {
		f := card_input_fixture(t)
		if f == nil { return }
		cannon, _ := card_input_find(f, .Cannon)
		firebomb, slot := card_input_find(f, .Firebomb)
		f.cards.selected_card_id = cannon.id
		_, has := poll_gameplay_command(&f.room, &f.renderer, &f.cards, {470, 240}, true, true,
			controls = {left_pressed = true})
		testing.expect(t, !has && f.cards.placing && f.renderer.tactical.expedition_placement)
		before := f.player
		controls: Run_Input
		point := view.Vec2{470, 240}
		hand_actions := RUN_HAND_ACTIONS
		if dragging == 0 { controls.actions.pressed += {hand_actions[slot]} }
		else {
			bounds := render.tactical_hand_card_bounds(&f.renderer, slot, f.player.deck.hand_count)
			point = {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
			controls.left_pressed, controls.left_down = true, true
		}
		_, has = poll_gameplay_command(&f.room, &f.renderer, &f.cards, point, true, true, controls = controls)
		testing.expect(t, !has && active_targeting_card_id(f.cards) == firebomb.id)
		testing.expect(t, !f.cards.placing && !f.renderer.tactical.expedition_placement,
			"changing card retained the old card's placement and preview mode")
		// An invalid drop keeps the new card selected without playing it.
		if dragging != 0 {
			f.renderer.has_hovered_cell = false
			_, has = poll_gameplay_command(&f.room, &f.renderer, &f.cards, {470, 240}, true, true,
				controls = {left_released = true})
			testing.expect(t, !has && f.cards.dragged_card_id == 0 && f.cards.selected_card_id == firebomb.id)
		}
		_, has = poll_gameplay_command(&f.room, &f.renderer, &f.cards, {470, 240}, true, true, controls = {wheel = -1})
		testing.expect(t, !has && f.cards.selected_card_id != firebomb.id,
			"wheel rotated an abandoned placement instead of cycling the newly selected hand")
		testing.expect(t, f.player == before, "selection, invalid drop and wheel changed gameplay state")
		card_input_fixture_destroy(f)
	}
}

@(test)
test_card_cancel_preserves_other_queued_actions_and_only_holds_its_own_frame :: proc(t: ^testing.T) {
	f := card_input_fixture(t)
	if f == nil { return }
	defer card_input_fixture_destroy(f)
	kinds := [2]Gameplay_Command_Kind{.Move, .Wait}
	for kind in kinds {
		buffer: Buffered_Gameplay_Command
		queued := Gameplay_Command{kind = kind, origin_phase = .Combat, direction = .East}
		_, emitted := route_gameplay_command(&buffer, &f.room, true, queued, true, 1.0/60)
		testing.expect(t, !emitted && buffer.has_pending)
		_, emitted = route_gameplay_command(&buffer, &f.room, true, {}, false, 1.0/60, controls = {right_pressed = true})
		testing.expect(t, !emitted && buffer.has_pending && buffer.pending.kind == kind)
		ready, accepted := route_gameplay_command(&buffer, &f.room, false, {}, false, 1.0/60)
		testing.expect(t, accepted && ready.kind == kind, "card cancel erased another kind of queued action")
	}
	card, _ := card_input_find(f, .Firebomb)
	command, valid := targeted_card_command(&f.room, card, f.room.enemies[0].position)
	testing.expect(t, valid)
	buffer := Buffered_Gameplay_Command{walk = 2}
	_, _ = route_gameplay_command(&buffer, &f.room, true, command, true, 1.0/60)
	controls := Run_Input{actions = {pressed = {.Cancel}, down = {.East}}}
	_, emitted := route_gameplay_command(&buffer, &f.room, false, {}, false, 1.0/60, controls = controls)
	testing.expect(t, !emitted && !buffer.has_pending, "cancel fell through to a held walk in the same frame")
	controls.actions.pressed = {}
	ready, accepted := route_gameplay_command(&buffer, &f.room, false, {}, false, 1.0/60, controls = controls)
	testing.expect(t, accepted && ready.kind == .Move && ready.direction == .East,
		"a card cancellation swallowed held movement after its own frame")
}
