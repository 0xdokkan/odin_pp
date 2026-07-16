package main

import "core:testing"
import game "game"

@(test)
test_gameplay_command_buffer_keeps_the_first_offer :: proc(t: ^testing.T) {
	buffer: Buffered_Gameplay_Command
	first := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .North}
	second := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}

	testing.expect(t, offer_gameplay_command(&buffer, first))
	testing.expect(t, !offer_gameplay_command(&buffer, second))
	testing.expect(t, buffer.occupied)
	testing.expect_value(t, buffer.command, first)
	testing.expect_value(t, buffer.offered_count, 2)
	testing.expect_value(t, buffer.dropped_count, 1)
}

@(test)
test_taking_a_gameplay_command_is_atomic :: proc(t: ^testing.T) {
	buffer: Buffered_Gameplay_Command
	expected := Gameplay_Command{kind = .Wait, origin_phase = .Combat}
	testing.expect(t, offer_gameplay_command(&buffer, expected))

	actual, ok := take_gameplay_command(&buffer)
	testing.expect(t, ok)
	testing.expect_value(t, actual, expected)
	testing.expect(t, !buffer.occupied)
	testing.expect_value(t, buffer.command, Gameplay_Command{})
	testing.expect_value(t, buffer.consumed_count, 1)

	_, second_ok := take_gameplay_command(&buffer)
	testing.expect(t, !second_ok)
	testing.expect_value(t, buffer.consumed_count, 1)
}

@(test)
test_clearing_the_gameplay_command_buffer_resets_state_and_counters :: proc(t: ^testing.T) {
	buffer: Buffered_Gameplay_Command
	testing.expect(t, offer_gameplay_command(&buffer, {kind = .Wait, origin_phase = .Combat}))
	testing.expect(t, !offer_gameplay_command(&buffer, {
		kind = .Move,
		origin_phase = .Combat,
		direction = .South,
	}))

	clear_gameplay_command_buffer(&buffer)

	testing.expect_value(t, buffer, Buffered_Gameplay_Command{})
	_, ok := take_gameplay_command(&buffer)
	testing.expect(t, !ok)
}

@(test)
test_buffered_card_command_preserves_instance_and_target :: proc(t: ^testing.T) {
	buffer: Buffered_Gameplay_Command
	target := game.entity_target(game.enemy_entity(27))
	expected := Gameplay_Command{
		kind = .Play_Card,
		origin_phase = .Combat,
		card_id = 91,
		target = target,
	}

	testing.expect(t, offer_gameplay_command(&buffer, expected))
	actual, ok := take_gameplay_command(&buffer)

	testing.expect(t, ok)
	testing.expect_value(t, actual, expected)
	testing.expect_value(t, actual.card_id, u32(91))
	testing.expect_value(t, actual.target, target)
}

@(test)
test_buffer_accepts_every_executable_gameplay_command_kind :: proc(t: ^testing.T) {
	commands := [?]Gameplay_Command{
		{kind = .Move, origin_phase = .Combat, direction = .West},
		{kind = .Move, origin_phase = .Loot, direction = .West},
		{kind = .Wait, origin_phase = .Combat},
		{kind = .Ability, origin_phase = .Combat, ability = .Afterimage},
		{kind = .Play_Card, origin_phase = .Combat, card_id = 5},
		{kind = .Refocus, origin_phase = .Combat},
	}

	for expected in commands {
		buffer: Buffered_Gameplay_Command
		testing.expect(t, offer_gameplay_command(&buffer, expected))
		actual, ok := take_gameplay_command(&buffer)
		testing.expect(t, ok)
		testing.expect_value(t, actual, expected)
	}
}

@(test)
test_gameplay_command_rejects_kinds_outside_their_origin_phase :: proc(t: ^testing.T) {
	testing.expect(t, gameplay_command_is_valid({
		kind = .Move,
		origin_phase = .Loot,
		direction = .North,
	}))
	testing.expect(t, !gameplay_command_is_valid({kind = .Wait, origin_phase = .Loot}))
	testing.expect(t, !gameplay_command_is_valid({kind = .Refocus, origin_phase = .Loot}))
	testing.expect(t, !gameplay_command_is_valid({
		kind = .Play_Card,
		origin_phase = .Complete,
		card_id = 1,
	}))
}

@(test)
test_none_command_is_not_buffered_or_counted :: proc(t: ^testing.T) {
	buffer: Buffered_Gameplay_Command

	testing.expect(t, !offer_gameplay_command(&buffer, {}))
	testing.expect_value(t, buffer, Buffered_Gameplay_Command{})
}
