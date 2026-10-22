package integration

import "core:testing"
import game "../game"
import level "../level"
import render "../render"
import run_session "../run"

@(test)
test_expedition_wheel_wraps_and_rotates_only_during_placement :: proc(t: ^testing.T) {
	deck := game.Deck_State{hand_count = 3}
	for i in 0..<3 { deck.hand[i].id = u32(11+i) }
	cards: run_session.Card_Interaction_State
	run_session.expedition_cycle_hand(&cards, &deck, -1)
	testing.expect_value(t, cards.selected_card_id, u32(11))
	run_session.expedition_cycle_hand(&cards, &deck, 1)
	testing.expect_value(t, cards.selected_card_id, u32(13))
	run_session.expedition_cycle_hand(&cards, &deck, -2)
	testing.expect_value(t, cards.selected_card_id, u32(12))
	cards.placing = true
	run_session.expedition_cycle_hand(&cards, &deck, -1)
	testing.expect_value(t, cards.selected_card_id, u32(12))
	testing.expect_value(t, cards.placement_direction, game.Move_Direction.East)
	run_session.expedition_cycle_hand(&cards, &deck, 2)
	testing.expect_value(t, cards.placement_direction, game.Move_Direction.West)
}

@(test)
test_expedition_oriented_card_uses_two_clicks_and_cancel_returns_to_selection :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Cannon)
	testing.expect(t, game.configure_tactical(&player, game.EXPEDITION_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := render.create(960, 540)
	renderer.has_hovered_cell, renderer.hovered_cell = true, {3, 1}
	card_id := player.deck.hand[0].id
	cards := run_session.Card_Interaction_State{selected_card_id = card_id}
	// The central board point is outside every HUD/hand hit target.
	point := [2]f32{470, 240}
	_, first := run_session.poll_gameplay_command(&room, &renderer, &cards, {point[0], point[1]}, true, true,
		controls = {left_pressed = true})
	testing.expect(t, !first && cards.placing)
	_, cancelled := run_session.poll_gameplay_command(&room, &renderer, &cards, {point[0], point[1]}, true, true,
		controls = {right_pressed = true})
	testing.expect(t, !cancelled && !cards.placing && cards.selected_card_id == card_id)
	_, _ = run_session.poll_gameplay_command(&room, &renderer, &cards, {point[0], point[1]}, true, true,
		controls = {left_pressed = true})
	_, _ = run_session.poll_gameplay_command(&room, &renderer, &cards, {point[0], point[1]}, true, true,
		controls = {wheel = -1})
	command, placed := run_session.poll_gameplay_command(&room, &renderer, &cards, {point[0], point[1]}, true, true,
		controls = {left_pressed = true})
	testing.expect(t, placed)
	testing.expect_value(t, command.direction, game.Move_Direction.East)
	testing.expect(t, run_session.execute_gameplay_command(&room, command).committed)
	testing.expect_value(t, len(room.objects), 1)
	if len(room.objects) == 1 { testing.expect_value(t, room.objects[0].device_direction, game.Move_Direction.East) }
	testing.expect_value(t, player.deck.energy, i32(60))
}
