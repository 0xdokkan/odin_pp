package main

import "core:testing"
import game "game"
import grid "grid"
import level "level"
import render "render"

// FERETRO's input (main.odin): Ctrl held and a left click on a foe the arrows
// reach looses one, a whole action of the lane like any other, never kept for
// later and never stamped with a beat.

arrow_input_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, timed := false) -> game.Room {
	data^ = create_gameplay_command_test_level(t)
	player^ = create_gameplay_command_test_player(t)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timed_actions = timed
	testing.expect(t, game.configure_tactical(player, config))
	// One foe in the line of fire, one behind cover.
	enemies := [?]game.Enemy_Spawn{{position = {4, 1}, health = 20, attack = 1}, {position = {3, 3}, health = 20, attack = 1}}
	cover := [?]grid.Position{{2, 2}}
	room, built := game.create_room(data, player, {enemies = enemies[:], obstacles = cover[:]})
	testing.expect(t, built)
	return room
}

@(test)
test_ctrl_click_on_a_foe_in_reach_looses_an_arrow :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := arrow_input_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	near, covered := room.enemies[0], room.enemies[1]
	// No arrows: Ctrl is only Ctrl.
	testing.expect(t, !arrows_aiming_at(&room, true))
	_, _, taken := arrow_shot_command(&room, renderer, arrows_aiming_at(&room, true), true)
	testing.expect(t, !taken)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	testing.expect(t, arrows_aiming_at(&room, true) && !arrows_aiming_at(&room, false))
	// Without Ctrl, or without a click, nothing is taken.
	renderer.has_hovered_cell, renderer.hovered_cell = true, near.position
	_, _, taken = arrow_shot_command(&room, renderer, false, true)
	testing.expect(t, !taken)
	_, _, taken = arrow_shot_command(&room, renderer, true, false)
	testing.expect(t, !taken)
	// The foe in reach: an arrow at it.
	command, has_command, picked := arrow_shot_command(&room, renderer, true, true)
	taken = picked
	testing.expect(t, taken && has_command)
	testing.expect_value(t, command, Gameplay_Command{kind = .Shoot, origin_phase = .Combat, target = game.entity_target(game.enemy_entity(near.id))})
	testing.expect(t, gameplay_command_is_valid(command))
	loot := command
	loot.origin_phase = .Loot
	testing.expect(t, !gameplay_command_is_valid(loot))
	// The click is the arrow's anyway: on a floor cell, or on a foe behind cover.
	for cell in ([2]grid.Position{{2, 3}, covered.position}) {
		renderer.hovered_cell = cell
		_, has_command, taken = arrow_shot_command(&room, renderer, true, true)
		testing.expect(t, taken && !has_command)
	}
	renderer.has_hovered_cell = false
	_, has_command, taken = arrow_shot_command(&room, renderer, true, true)
	testing.expect(t, taken && !has_command)
	// Never stamped with a beat, even on the tick: an arrow is never critical.
	room.player.tactical.clock_fraction = 0.95
	testing.expect(t, game.tactical_beat_target(&room) != 0)
	shot := command
	beat_stamp(&room, &shot)
	testing.expect_value(t, shot.beat, u32(0))
	step := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	beat_stamp(&room, &step)
	testing.expect(t, step.beat != 0)
	// It is neither a step, a bump nor a card for the playtest's counts.
	_, kind, _, ok := capture_gameplay_command_telemetry(&room, command)
	testing.expect(t, ok && kind == .Ability)
}

// An arrow is one action: committed through the lane it takes its second,
// the presses during it are dropped, and only a press after it looses another.
@(test)
test_an_arrow_is_one_action_and_presses_during_it_are_dropped :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := arrow_input_test_room(t, &data, &player, timed = true)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	cards: Card_Interaction_State
	held: Buffered_Gameplay_Command
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	shoot := Gameplay_Command{kind = .Shoot, origin_phase = .Combat, target = game.entity_target(game.enemy_entity(room.enemies[0].id))}
	cards.selected_card_id = room.player.deck.hand[0].id
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, shoot))
	testing.expect_value(t, game.player_charges(&room, .Arrows), i32(2))
	testing.expect_value(t, cards, Card_Interaction_State{})
	testing.expect(t, game.tactical_player_busy(&room))
	testing.expect_value(t, room.player.tactical.action_remaining, game.TACTICAL_ARROW_SECONDS)
	// Pressed while the arrow's own second runs: dropped, never kept.
	for _ in 0..<20 {
		busy := render.renderer_blocks_player_input(renderer) || game.tactical_player_busy(&room)
		testing.expect(t, busy)
		_, routed := route_gameplay_command(&held, &room, busy, shoot, true, 1.0/60)
		testing.expect(t, !routed)
		testing.expect_value(t, held, Buffered_Gameplay_Command{})
	}
	testing.expect_value(t, game.player_charges(&room, .Arrows), i32(2))
	// Refused without arrows' reach: a foe behind cover is no target.
	room.player.tactical.action_remaining = 0
	render.update_renderer_event_timeline(renderer, 100)
	covered := shoot
	covered.target = game.entity_target(game.enemy_entity(room.enemies[1].id))
	testing.expect(t, !commit_gameplay_command(&room, renderer, &cards, covered))
	testing.expect_value(t, game.player_charges(&room, .Arrows), i32(2))
	// After it, a press looses the next one.
	ready, routed := route_gameplay_command(&held, &room, false, shoot, true, 1.0/60)
	testing.expect(t, routed)
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, ready))
	testing.expect_value(t, game.player_charges(&room, .Arrows), i32(1))
}
