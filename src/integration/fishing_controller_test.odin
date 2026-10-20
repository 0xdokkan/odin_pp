package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"
import view "../engine/view"

// The cleared room's slot holds the Canna da Pesca as the hand holds a card:
// picked up and let go over a cell it may fish, or chosen and then a cell
// clicked; Esc puts it back; nothing is picked up while the board shows an
// action; spent, the slot takes nothing. The command fishes once, in a
// cleared room only.
@(test)
test_fishing_slot_picks_the_rod_up_and_drops_it_on_the_water :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	cards: run_session.Card_Interaction_State
	rod, held := game.fishing_rod(&player.deck)
	testing.expect(t, held)
	slot := render.fishing_slot_bounds(renderer)
	on_slot := view.Vec2{slot.x+slot.width*0.5, slot.y+60}
	board := render.tactical_world_bounds(renderer)
	on_board := view.Vec2{board.x+board.width*0.5, board.y+board.height*0.5}
	water := game.add_position(player.position, {2, 0})
	// In the fight the slot is not there.
	_, has, taken := run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_slot, inside = true, pressed = true, down = true}, true)
	testing.expect(t, !has && !taken && cards == {})
	_, cleared := game.sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared)
	// Under the mouse, then picked up.
	_, has, taken = run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_slot, inside = true}, true)
	testing.expect(t, !has && !taken && cards.hovered_card_id == rod.id)
	_, has, taken = run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_slot, inside = true, pressed = true, down = true}, true)
	testing.expect(t, !has && taken && cards.dragged_card_id == rod.id)
	// Let go over a cell it may fish: the command.
	renderer.has_hovered_cell, renderer.hovered_cell = true, water
	command, has_command, _ := run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_board, inside = true, released = true}, true)
	testing.expect(t, has_command && command.kind == .Fish && command.origin_phase == .Loot && command.card_id == rod.id)
	testing.expect(t, command.target == game.cell_target(water) && run_session.gameplay_command_is_valid(command))
	// Let go over his own cell: chosen, no command; a click on the water then
	// fishes.
	cards = {dragged_card_id = rod.id}
	renderer.hovered_cell = player.position
	_, has, _ = run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_board, inside = true, released = true}, true)
	testing.expect(t, !has && cards.selected_card_id == rod.id && cards.dragged_card_id == 0)
	renderer.hovered_cell = water
	clicked, has_click, _ := run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_board, inside = true, pressed = true, down = true}, true)
	testing.expect(t, has_click && clicked.target == game.cell_target(water))
	// Esc puts it back.
	cards = {selected_card_id = rod.id}
	_, has, taken = run_session.poll_fishing_command(&room, renderer, &cards, {cancel = true}, true)
	testing.expect(t, !has && taken && cards == {})
	// While the board shows an action nothing is picked up.
	_, has, taken = run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_slot, inside = true, pressed = true, down = true}, false)
	testing.expect(t, !has && !taken && cards.dragged_card_id == 0)
	// The room's one fishing.
	execution := run_session.execute_gameplay_command(&room, command)
	testing.expect(t, execution.committed && execution.clears_card_interaction)
	testing.expect(t, game.fishing_cell_is_water(&room, water) && game.fishing_casts_left(&room) == 0)
	// Spent: the slot takes nothing more, and the command is refused.
	cards = {}
	_, has, taken = run_session.poll_fishing_command(&room, renderer, &cards, {mouse = on_slot, inside = true, pressed = true, down = true}, true)
	testing.expect(t, !has && !taken && cards == {})
	testing.expect(t, !run_session.execute_gameplay_command(&room, command).committed)
	// Only a cleared room's, and only at a cell.
	fight := command
	fight.origin_phase = .Combat
	testing.expect(t, !run_session.gameplay_command_is_valid(fight))
	no_cell := command
	no_cell.target = game.entity_target(game.PLAYER_ENTITY)
	testing.expect(t, !run_session.gameplay_command_is_valid(no_cell))
}
