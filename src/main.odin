package main

import "core:os"
import "core:fmt"
import rl "vendor:raylib"
import app "app"
import game "game"
import grid "grid"
import level "level"
import render "render"
import view "view"

DEMO_PLAYER_STATS :: game.Player_Stats{
	max_health = 22,
	attack = 2,
	defense = 1,
}

DEMO_RUN_CONFIG :: game.Run_Map_Config{
	layer_count = 7,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

create_demo_room :: proc(
	level_data: ^level.Level,
	player: ^game.Player,
	node: ^game.Run_Node,
) -> (game.Room, bool) {
	assert(level_data != nil && player != nil && node != nil)
	enemy_positions := [?]grid.Position{
		{x = 11, y = 2},
		{x = 11, y = 6},
		{x = 3, y = 6},
		{x = 7, y = 2},
		{x = 12, y = 4},
	}
	trap_positions := [?]grid.Position{
		{x = 5, y = 2},
		{x = 9, y = 6},
		{x = 2, y = 4},
	}
	obstacles := [?]grid.Position{
		{x = 5, y = 5},
		{x = 9, y = 3},
	}

	enemy_count := min(3+node.depth/3, len(enemy_positions))
	if node.kind == .Elite {
		enemy_count = min(enemy_count+1, len(enemy_positions))
	} else if node.kind == .Boss {
		enemy_count = 4
	}
	enemies: [len(enemy_positions)]game.Enemy_Spawn
	archetypes := [?]game.Enemy_Archetype{.Chaser, .Archer, .Brute}
	for index in 0..<enemy_count {
		position_index := (index+int(node.id))%len(enemy_positions)
		archetype := archetypes[(index+int(node.id))%len(archetypes)]
		if node.kind == .Boss && index == 0 {
			archetype = .Brute
		}
		health := i32(4+node.depth/3)
		attack := i32(2+node.depth/4)
		if archetype == .Brute {
			health += 2
		}
		if node.kind == .Elite {
			health += 1
			attack += 1
		} else if node.kind == .Boss && index == 0 {
			health += 4
			attack += 1
		}
		enemies[index] = {
			position = enemy_positions[position_index],
			health = health,
			attack = attack,
			archetype = archetype,
			drops_healing = game.enemy_spawn_drops_healing(index),
		}
	}

	trap_count := 2
	if node.kind == .Elite || node.kind == .Boss {
		trap_count = 3
	}
	traps: [len(trap_positions)]game.Trap_Spawn
	for index in 0..<trap_count {
		position_index := (index+int(node.id))%len(trap_positions)
		traps[index] = {
			position = trap_positions[position_index],
			damage = i32(3+node.depth/3),
		}
	}

	return game.create_room(level_data, player, {
		enemies = enemies[:enemy_count],
		traps = traps[:trap_count],
		obstacles = obstacles[:],
	})
}

Prepared_Demo_Room :: struct {
	level_data: level.Level,
	player:     game.Player,
	room:       game.Room,
}

destroy_prepared_demo_room :: proc(prepared: ^Prepared_Demo_Room) {
	if prepared == nil {
		return
	}
	game.destroy_room(&prepared.room)
	level.destroy(&prepared.level_data)
	prepared^ = {}
}

prepare_demo_room :: proc(
	prepared: ^Prepared_Demo_Room,
	run: ^game.Run_State,
	node: ^game.Run_Node,
	procedural: bool,
) -> bool {
	if prepared == nil || run == nil || node == nil || !game.node_kind_has_room(node.kind) {
		return false
	}
	destroy_prepared_demo_room(prepared)
	prepared.player = run.player

	if procedural {
		blueprint, blueprint_error := game.generate_room_blueprint(node)
		if blueprint_error != .None {
			return false
		}
		defer game.destroy_room_blueprint(&blueprint)

		prepared.level_data = blueprint.level_data
		blueprint.level_data = {}
		content := game.room_blueprint_content(&blueprint)
		new_room, room_ok := game.create_room(&prepared.level_data, &prepared.player, content)
		if !room_ok {
			destroy_prepared_demo_room(prepared)
			return false
		}
		prepared.room = new_room
		return true
	}

	rows := [?]string{
		"###############",
		"#@............#",
		"#.............#",
		"#...###.......#",
		"#......>......#",
		"#.......###...#",
		"#.............#",
		"#.............#",
		"###############",
	}
	static_level, parse_error, _ := level.from_ascii(rows[:])
	if parse_error != .None {
		return false
	}
	prepared.level_data = static_level
	new_room, room_ok := create_demo_room(&prepared.level_data, &prepared.player, node)
	if !room_ok {
		destroy_prepared_demo_room(prepared)
		return false
	}
	prepared.room = new_room
	return true
}

install_prepared_demo_room :: proc(
	level_data: ^level.Level,
	run: ^game.Run_State,
	room: ^game.Room,
	prepared: ^Prepared_Demo_Room,
) {
	assert(level_data != nil && run != nil && room != nil && prepared != nil)
	game.destroy_room(room)
	level.destroy(level_data)
	run.player = prepared.player
	level_data^ = prepared.level_data
	prepared.level_data = {}
	prepared.room.player = &run.player
	prepared.room.level_data = level_data
	// Keep this large assignment out of main; LLVM otherwise scalarizes Room field by field.
	room^ = prepared.room
	prepared.room = {}
}

replace_current_demo_room :: proc(
	level_data: ^level.Level,
	run: ^game.Run_State,
	room: ^game.Room,
	procedural: bool,
) -> bool {
	if level_data == nil || run == nil || room == nil {
		return false
	}
	node, node_ok := game.current_run_node(run)
	if !node_ok {
		return false
	}
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	if !prepare_demo_room(&prepared, run, node, procedural) {
		return false
	}
	install_prepared_demo_room(level_data, run, room, &prepared)
	return true
}

enter_demo_node :: proc(
	level_data: ^level.Level,
	run: ^game.Run_State,
	room: ^game.Room,
	node_id: game.Node_Id,
	procedural: bool,
) -> bool {
	if level_data == nil || run == nil || room == nil || !game.can_choose_node(run, node_id) {
		return false
	}
	node, node_ok := game.node_at(run, node_id)
	if !node_ok {
		return false
	}
	if !game.node_kind_has_room(node.kind) {
		return game.enter_node(run, node_id) != .Invalid
	}
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	if !prepare_demo_room(&prepared, run, node, procedural) ||
	   game.enter_node(run, node_id) != .In_Room {
		return false
	}
	install_prepared_demo_room(level_data, run, room, &prepared)
	return true
}

restart_demo_session :: proc(
	level_data: ^level.Level,
	run: ^game.Run_State,
	room: ^game.Room,
	seed: u64,
	procedural: bool,
) -> bool {
	if level_data == nil || run == nil || room == nil {
		return false
	}
	new_run, run_ok := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, seed)
	if !run_ok {
		return false
	}
	defer game.destroy_run(&new_run)
	node, node_ok := game.current_run_node(&new_run)
	if !node_ok {
		return false
	}
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	if !prepare_demo_room(&prepared, &new_run, node, procedural) {
		return false
	}

	new_run.player = prepared.player
	game.destroy_room(room)
	level.destroy(level_data)
	game.destroy_run(run)
	run^ = new_run
	new_run = {}
	level_data^ = prepared.level_data
	prepared.level_data = {}
	prepared.room.player = &run.player
	prepared.room.level_data = level_data
	room^ = prepared.room
	prepared.room = {}
	return true
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key)
}

pressed_hand_slot :: proc() -> int {
	keys := [?]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT}
	for key, index in keys {
		if rl.IsKeyPressed(key) {
			return index
		}
	}
	return -1
}

card_requires_chosen_target :: proc(definition: game.Card_Definition) -> bool {
	return definition.targeting.shape != .None
}

Card_Interaction_State :: struct {
	hovered_card_id:  u32,
	selected_card_id: u32,
	dragged_card_id:  u32,
}

clear_card_interaction :: proc(state: ^Card_Interaction_State) {
	if state != nil {
		state^ = {}
	}
}

active_targeting_card_id :: proc(state: Card_Interaction_State) -> u32 {
	if state.dragged_card_id != 0 {
		return state.dragged_card_id
	}
	return state.selected_card_id
}

immediate_card_command :: proc(card: game.Card_Instance) -> (Gameplay_Command, bool) {
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found || card_requires_chosen_target(definition) {
		return {}, false
	}
	target: game.Target
	if definition.targeting.rule == .Self || definition.targeting.rule == .Player {
		target = game.entity_target(game.PLAYER_ENTITY)
	}
	return {
		kind = .Play_Card,
		origin_phase = .Combat,
		card_id = card.id,
		target = target,
	}, true
}

poll_gameplay_command :: proc(
	room: ^game.Room,
	renderer: ^render.Renderer,
	card_interaction: ^Card_Interaction_State,
	mouse_canvas: view.Vec2,
	mouse_inside: bool,
	spatial_interaction_enabled: bool,
) -> (command: Gameplay_Command, has_command: bool) {
	assert(room != nil && room.player != nil && renderer != nil && card_interaction != nil)
	input_deck, input_phase := render.renderer_hand_deck(renderer, room)
	if input_phase == .Loot {
		clear_card_interaction(card_interaction)
		if key_pressed(.W) {
			return Gameplay_Command{kind = .Move, origin_phase = .Loot, direction = .North}, true
		} else if key_pressed(.D) {
			return Gameplay_Command{kind = .Move, origin_phase = .Loot, direction = .East}, true
		} else if key_pressed(.S) {
			return Gameplay_Command{kind = .Move, origin_phase = .Loot, direction = .South}, true
		} else if key_pressed(.A) {
			return Gameplay_Command{kind = .Move, origin_phase = .Loot, direction = .West}, true
		}
		return
	}
	if input_phase != .Combat || !input_deck.combat_active {
		clear_card_interaction(card_interaction)
		return
	}
	if rl.IsKeyPressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) {
		clear_card_interaction(card_interaction)
		return
	}
	if card_interaction.selected_card_id != 0 {
		_, selected_found := game.hand_card_index_by_id(
			input_deck,
			card_interaction.selected_card_id,
		)
		if !selected_found {
			card_interaction.selected_card_id = 0
		}
	}
	if !spatial_interaction_enabled {
		card_interaction.dragged_card_id = 0
	}

	previous_hovered_card_id := card_interaction.hovered_card_id
	card_interaction.hovered_card_id = 0
	if card_interaction.dragged_card_id == 0 && mouse_inside {
		raised_card_id := previous_hovered_card_id
		if raised_card_id == 0 {
			raised_card_id = card_interaction.selected_card_id
		}
		if hand_index, found := render.hand_card_at_point(
			renderer,
			input_deck,
			mouse_canvas,
			raised_card_id,
		); found {
			card_interaction.hovered_card_id = input_deck.hand[hand_index].id
		}
	}

	if spatial_interaction_enabled && card_interaction.dragged_card_id != 0 {
		if rl.IsMouseButtonReleased(.LEFT) || !rl.IsMouseButtonDown(.LEFT) {
			dragged_card_id := card_interaction.dragged_card_id
			card_interaction.dragged_card_id = 0
			if mouse_inside && render.card_drop_area_contains(renderer, mouse_canvas) &&
			   renderer.has_hovered_cell {
				if hand_index, found := game.hand_card_index_by_id(input_deck, dragged_card_id); found {
					card := input_deck.hand[hand_index]
					if target, has_target := game.card_drop_target(
						room,
						card,
						renderer.hovered_cell,
					); has_target {
						return Gameplay_Command{
							kind = .Play_Card,
							origin_phase = .Combat,
							card_id = dragged_card_id,
							target = target,
						}, true
					}
				}
			}
		}
		return
	}

	if key_pressed(.F) ||
	   (spatial_interaction_enabled && mouse_inside && rl.IsMouseButtonPressed(.LEFT) &&
	    render.refocus_button_at_point(renderer, mouse_canvas)) {
		return Gameplay_Command{kind = .Refocus, origin_phase = .Combat}, true
	}

	requested_slot := pressed_hand_slot()
	if spatial_interaction_enabled && mouse_inside && rl.IsMouseButtonPressed(.LEFT) &&
	   card_interaction.hovered_card_id != 0 {
		card_interaction.dragged_card_id = card_interaction.hovered_card_id
		card_interaction.hovered_card_id = 0
		card_interaction.selected_card_id = 0
		return
	}
	if requested_slot >= 0 && requested_slot < input_deck.hand_count {
		card := input_deck.hand[requested_slot]
		if card_command, immediate := immediate_card_command(card); immediate {
			return card_command, true
		}
		if !spatial_interaction_enabled {
			return
		}
		card_interaction.selected_card_id = card.id
		return
	}

	if spatial_interaction_enabled && card_interaction.selected_card_id != 0 && mouse_inside &&
	   render.card_drop_area_contains(renderer, mouse_canvas) && rl.IsMouseButtonPressed(.LEFT) &&
	   renderer.has_hovered_cell {
		if hand_index, found := game.hand_card_index_by_id(
			input_deck,
			card_interaction.selected_card_id,
		); found {
			card := input_deck.hand[hand_index]
			if target, has_target := game.card_drop_target(room, card, renderer.hovered_cell); has_target {
				return Gameplay_Command{
					kind = .Play_Card,
					origin_phase = .Combat,
					card_id = card.id,
					target = target,
				}, true
			}
		}
		return
	}

	if key_pressed(.C) {
		return Gameplay_Command{kind = .Ability, origin_phase = .Combat, ability = .Thorn_Coat}, true
	} else if key_pressed(.V) {
		return Gameplay_Command{kind = .Ability, origin_phase = .Combat, ability = .Afterimage}, true
	} else if key_pressed(.W) {
		return Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .North}, true
	} else if key_pressed(.D) {
		return Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}, true
	} else if key_pressed(.S) {
		return Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .South}, true
	} else if key_pressed(.A) {
		return Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .West}, true
	} else if key_pressed(.SPACE) {
		return Gameplay_Command{kind = .Wait, origin_phase = .Combat}, true
	}
	return
}

Gameplay_Command_Execution :: struct {
	committed:              bool,
	clears_card_interaction: bool,
}

execute_gameplay_command :: proc(room: ^game.Room, command: Gameplay_Command) -> (
	execution: Gameplay_Command_Execution,
) {
	if room == nil || room.player == nil || !gameplay_command_is_valid(command) ||
	   room.phase != command.origin_phase {
		return
	}
	switch command.kind {
	case .None:
		return
	case .Move:
		result := game.try_move_player(room, command.direction)
		execution.committed = result != .Invalid_Phase && result != .Blocked
	case .Wait:
		result := game.wait_player_turn(room)
		execution.committed = result != .Invalid_Phase
	case .Ability:
		result := game.use_player_ability(room, command.ability)
		execution.committed = result != .Invalid_Phase
	case .Play_Card:
		play := game.play_card(room, command.card_id, command.target)
		execution.committed = game.card_play_was_committed(play.result)
		execution.clears_card_interaction = execution.committed
	case .Refocus:
		refocus := game.refocus_player_hand(room)
		execution.committed = game.refocus_was_committed(refocus.result)
		execution.clears_card_interaction = execution.committed
	}
	return
}

commit_gameplay_command :: proc(
	room: ^game.Room,
	renderer: ^render.Renderer,
	card_interaction: ^Card_Interaction_State,
	command: Gameplay_Command,
) -> bool {
	if room == nil || renderer == nil || card_interaction == nil ||
	   render.renderer_timeline_is_busy(renderer) {
		return false
	}
	before := render.capture_room_presentation(room)
	execution := execute_gameplay_command(room, command)
	if !execution.committed {
		return false
	}
	after := render.capture_room_presentation(room)
	if execution.clears_card_interaction || room.phase != .Combat {
		clear_card_interaction(card_interaction)
	}
	render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after)
	return true
}

route_map_toggle_is_allowed :: proc(
	run: ^game.Run_State,
	room: ^game.Room,
	renderer: ^render.Renderer,
) -> bool {
	return run != nil && room != nil && renderer != nil && run.phase == .In_Room &&
	       (room.phase == .Combat || room.phase == .Loot) &&
	       !render.renderer_timeline_is_busy(renderer)
}

room_transition_is_ready :: proc(
	run: ^game.Run_State,
	room: ^game.Room,
	renderer: ^render.Renderer,
) -> bool {
	return run != nil && room != nil && renderer != nil && run.phase == .In_Room &&
	       (room.phase == .Complete || room.phase == .Defeat) &&
	       !render.renderer_timeline_is_busy(renderer)
}

prepare_smoke_card_drag :: proc(room: ^game.Room, definition_id: game.Card_Id) -> u32 {
	assert(room != nil && room.player != nil)
	deck := &room.player.deck
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			return deck.hand[index].id
		}
	}
	for index in 0..<deck.draw_count {
		if deck.draw_pile[index].definition_id == definition_id {
			deck.hand[0], deck.draw_pile[index] = deck.draw_pile[index], deck.hand[0]
			assert(game.validate_deck_state(deck))
			return deck.hand[0].id
		}
	}
	panic("smoke card definition is missing from hand and draw pile")
}

keyboard_route_choice :: proc(run: ^game.Run_State) -> (game.Node_Id, bool) {
	choices := game.available_nodes(run)
	choice_index := -1
	if rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.KP_1) {
		choice_index = 0
	} else if rl.IsKeyPressed(.TWO) || rl.IsKeyPressed(.KP_2) {
		choice_index = 1
	} else if rl.IsKeyPressed(.THREE) || rl.IsKeyPressed(.KP_3) {
		choice_index = 2
	}
	if choice_index < 0 || choice_index >= len(choices) {
		return game.INVALID_NODE_ID, false
	}
	return choices[choice_index], true
}

available_node_of_kind :: proc(run: ^game.Run_State, kind: game.Node_Kind) -> game.Node_Id {
	for choice in game.available_nodes(run) {
		node, found := game.node_at(run, choice)
		if found && node.kind == kind {
			return choice
		}
	}
	return game.INVALID_NODE_ID
}

demo_seed_with_first_special :: proc(start_seed: u64, kind: game.Node_Kind) -> (u64, bool) {
	if !game.node_kind_is_special(kind) {
		return 0, false
	}
	for offset in u64(0)..<u64(512) {
		seed := start_seed+offset
		route_map, ok := game.generate_run_map(DEMO_RUN_CONFIG, seed)
		if !ok {
			continue
		}
		found := false
		root := &route_map.nodes[0]
		for index in 0..<root.outgoing_count {
			if route_map.nodes[int(root.outgoing[index])].kind == kind {
				found = true
				break
			}
		}
		game.destroy_run_map(&route_map)
		if found {
			return seed, true
		}
	}
	return 0, false
}

main :: proc() {
	smoke_test := false
	smoke_generation := false
	smoke_map := false
	smoke_status := false
	smoke_loot := false
	smoke_card := false
	smoke_targeting := false
	smoke_spatial := false
	smoke_content := false
	smoke_movement := false
	smoke_timeline := false
	smoke_deck_flow := false
	smoke_refocus := false
	smoke_reward := false
	smoke_shop := false
	smoke_rest := false
	smoke_event := false
	smoke_treasure := false
	smoke_special_result := false
	smoke_intents := false
	smoke_archetypes := false
	smoke_defeat := false
	smoke_mode_count := 0
	for argument in os.args {
		if argument == "--smoke" {
			smoke_test = true
			smoke_mode_count += 1
		} else if argument == "--smoke-generation" {
			smoke_test = true
			smoke_generation = true
			smoke_mode_count += 1
		} else if argument == "--smoke-map" {
			smoke_test = true
			smoke_map = true
			smoke_mode_count += 1
		} else if argument == "--smoke-status" {
			smoke_test = true
			smoke_status = true
			smoke_mode_count += 1
		} else if argument == "--smoke-loot" {
			smoke_test = true
			smoke_loot = true
			smoke_mode_count += 1
		} else if argument == "--smoke-card" {
			smoke_test = true
			smoke_card = true
			smoke_mode_count += 1
		} else if argument == "--smoke-targeting" {
			smoke_test = true
			smoke_targeting = true
			smoke_mode_count += 1
		} else if argument == "--smoke-spatial" {
			smoke_test = true
			smoke_spatial = true
			smoke_mode_count += 1
		} else if argument == "--smoke-content" {
			smoke_test = true
			smoke_content = true
			smoke_mode_count += 1
		} else if argument == "--smoke-movement" {
			smoke_test = true
			smoke_movement = true
			smoke_mode_count += 1
		} else if argument == "--smoke-timeline" {
			smoke_test = true
			smoke_timeline = true
			smoke_mode_count += 1
		} else if argument == "--smoke-deck-flow" {
			smoke_test = true
			smoke_deck_flow = true
			smoke_mode_count += 1
		} else if argument == "--smoke-refocus" {
			smoke_test = true
			smoke_refocus = true
			smoke_mode_count += 1
		} else if argument == "--smoke-reward" {
			smoke_test = true
			smoke_reward = true
			smoke_mode_count += 1
		} else if argument == "--smoke-shop" {
			smoke_test = true
			smoke_shop = true
			smoke_mode_count += 1
		} else if argument == "--smoke-rest" {
			smoke_test = true
			smoke_rest = true
			smoke_mode_count += 1
		} else if argument == "--smoke-event" {
			smoke_test = true
			smoke_event = true
			smoke_mode_count += 1
		} else if argument == "--smoke-treasure" {
			smoke_test = true
			smoke_treasure = true
			smoke_mode_count += 1
		} else if argument == "--smoke-special-result" {
			smoke_test = true
			smoke_special_result = true
			smoke_mode_count += 1
		} else if argument == "--smoke-intents" {
			smoke_test = true
			smoke_intents = true
			smoke_mode_count += 1
		} else if argument == "--smoke-archetypes" {
			smoke_test = true
			smoke_archetypes = true
			smoke_mode_count += 1
		} else if argument == "--smoke-defeat" {
			smoke_test = true
			smoke_defeat = true
			smoke_mode_count += 1
		}
	}
	if smoke_mode_count > 1 {
		fmt.eprintln("choose exactly one --smoke* mode")
		os.exit(2)
	}
	procedural_rooms := !smoke_test || smoke_generation

	level_data: level.Level
	defer level.destroy(&level_data)

	run_seed: u64 = 0xC0FFEE
	if smoke_shop || smoke_rest || smoke_event || smoke_treasure || smoke_special_result {
		desired_kind := game.Node_Kind.Shop
		if smoke_rest {
			desired_kind = .Rest
		} else if smoke_event {
			desired_kind = .Event
		} else if smoke_treasure || smoke_special_result {
			desired_kind = .Treasure
		}
		found_seed: bool
		run_seed, found_seed = demo_seed_with_first_special(run_seed, desired_kind)
		if !found_seed {
			return
		}
	}
	run_state, run_ok := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, run_seed)
	if !run_ok {
		return
	}
	defer game.destroy_run(&run_state)
	room: game.Room
	if !replace_current_demo_room(&level_data, &run_state, &room, procedural_rooms) {
		return
	}
	defer game.destroy_room(&room)

	window, window_ok := app.open(app.Window_Config{
		title = "Odin Grid Roguelike Prototype",
		initial_width = 1280,
		initial_height = 720,
		canvas_width = 960,
		canvas_height = 540,
		minimum_window_width = 640,
		minimum_window_height = 360,
		target_fps = 60,
		initial_scale_mode = .Fit,
	})
	if !window_ok {
		return
	}
	defer app.close(&window)

	iso_renderer := render.create(window.config.canvas_width, window.config.canvas_height, &level_data)
	show_route_map := false
	card_interaction: Card_Interaction_State
	gameplay_buffer: Buffered_Gameplay_Command
	reward_hovered_index := -1
	reward_skip_hovered := false
	shop_render_state := render.Shop_Render_State{hovered_offer_index = -1}
	special_render_state: render.Special_Node_Render_State
	smoke_frame_count := 0
	if smoke_map {
		room.phase = .Complete
		transition := game.finish_room(&run_state, room.phase)
		assert(transition == .Reward)
		assert(game.skip_card_reward(&run_state) == .Skipped)
		show_route_map = true
	} else if smoke_reward {
		room.phase = .Complete
		transition := game.finish_room(&run_state, room.phase)
		assert(transition == .Reward)
		reward_hovered_index = 1
	} else if smoke_shop || smoke_rest || smoke_event || smoke_treasure || smoke_special_result {
		room.phase = .Complete
		transition := game.finish_room(&run_state, room.phase)
		assert(transition == .Reward)
		assert(game.skip_card_reward(&run_state) == .Skipped)
		desired_kind := game.Node_Kind.Shop
		if smoke_rest {
			desired_kind = .Rest
			run_state.player.health = run_state.player.stats.max_health/2
		} else if smoke_event {
			desired_kind = .Event
		} else if smoke_treasure || smoke_special_result {
			desired_kind = .Treasure
		}
		if smoke_shop {
			run_state.player.gold = 20
		}
		special_node := available_node_of_kind(&run_state, desired_kind)
		assert(special_node != game.INVALID_NODE_ID)
		assert(enter_demo_node(
			&level_data,
			&run_state,
			&room,
			special_node,
			procedural_rooms,
		))
		if smoke_shop {
			shop_render_state.has_hovered_offer = true
			shop_render_state.hovered_offer_index = 1
			shop_render_state.selected_card_id = run_state.player.deck.owned[0].id
		} else if smoke_rest {
			special_render_state.selected_card_id = run_state.player.deck.owned[0].id
			special_render_state.secondary_hovered = true
		} else {
			special_render_state.primary_hovered = true
		}
		if smoke_special_result {
			assert(game.claim_treasure(&run_state) == .Treasure_Claimed)
			special_render_state.primary_hovered = false
			special_render_state.continue_hovered = true
		}
	} else if smoke_intents {
		room.enemies[0].position = {x = 2, y = 1}
		room.enemies[1].position = {x = 7, y = 1}
		room.enemies[2].position = {x = 4, y = 6}
		game.plan_enemy_intents(&room)
	} else if smoke_archetypes {
		room.enemies[0].archetype = .Chaser
		room.enemies[0].position = {x = 4, y = 6}
		room.enemies[1].archetype = .Archer
		room.enemies[1].position = {x = 5, y = 1}
		room.enemies[2].archetype = .Brute
		room.enemies[2].position = {x = 1, y = 4}
		game.plan_enemy_intents(&room)
	} else if smoke_defeat {
		room.player.health = 1
		room.enemies[0].archetype = .Chaser
		room.enemies[0].position = {x = 2, y = 1}
		game.plan_enemy_intents(&room)
		before := render.capture_room_presentation(&room)
		result := game.wait_player_turn(&room)
		assert(result == .Player_Defeated)
		assert(render.begin_renderer_event_timeline(&iso_renderer, before, &room.recent_events))
		assert(render.update_renderer_event_timeline(&iso_renderer, 1000))
		assert(!render.renderer_timeline_is_busy(&iso_renderer))
	} else if smoke_status {
		game.use_player_ability(&room, .Toxic_Wave)
		game.use_player_ability(&room, .Guard)
		game.use_player_ability(&room, .Thorn_Coat)
		game.use_player_ability(&room, .Afterimage)
	} else if smoke_loot {
		room.player.position = {x = 10, y = 2}
		room.enemies[0].health = room.player.stats.attack
		before := render.capture_room_presentation(&room)
		result := game.try_move_player(&room, .East)
		assert(result == .Attacked && room.phase == .Combat)
		assert(render.begin_renderer_event_timeline(&iso_renderer, before, &room.recent_events))
		render.update_renderer_event_timeline(
			&iso_renderer,
			render.PRESENTATION_DAMAGE_DURATION+
				render.PRESENTATION_DEFEAT_DURATION+
				render.PRESENTATION_NOTICE_DURATION+
				render.PRESENTATION_LOOT_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&iso_renderer.timeline)
		assert(active && cue.kind == .Loot)
	} else if smoke_card {
		card_interaction.dragged_card_id = prepare_smoke_card_drag(&room, .Arc_Bolt)
		room.enemies[0].position = {x = 4, y = 1}
		game.plan_enemy_intents(&room)
	} else if smoke_targeting {
		card_interaction.dragged_card_id = prepare_smoke_card_drag(&room, .Firebomb)
		room.enemies[0].position = {x = 3, y = 1}
		room.enemies[1].position = {x = 4, y = 2}
		room.enemies[2].position = {x = 3, y = 3}
		game.plan_enemy_intents(&room)
	} else if smoke_spatial {
		card, created := game.create_temporary_card(&room.player.deck, .Dash)
		assert(created && len(room.traps) > 0)
		card_interaction.dragged_card_id = card.id
		room.traps[0].position = {x = 3, y = 1}
		room.traps[0].armed = true
		game.plan_enemy_intents(&room)
	} else if smoke_content {
		game.finish_deck_combat(&room.player.deck)
		assert(game.initialize_empty_deck(
			&room.player.deck,
			game.DEFAULT_DECK_RULES,
			0xC017E17,
		))
		content_cards := [?]game.Card_Id{
			.Heavy_Blow,
			.Venom_Needle,
			.Caustic_Bloom,
			.Purifying_Guard,
			.Volatile_Study,
		}
		for definition_id in content_cards {
			_, added := game.add_owned_card(&room.player.deck, definition_id)
			assert(added)
		}
		assert(game.begin_deck_combat(&room.player.deck))
		card_interaction.dragged_card_id = prepare_smoke_card_drag(&room, .Caustic_Bloom)
		card_interaction.hovered_card_id = prepare_smoke_card_drag(&room, .Volatile_Study)
		room.enemies[0].position = {x = 3, y = 1}
		room.enemies[1].position = {x = 4, y = 2}
		room.enemies[2].position = {x = 3, y = 3}
		game.clear_enemy_intents(&room)
	} else if smoke_timeline {
		card_id := prepare_smoke_card_drag(&room, .Guard)
		before := render.capture_room_presentation(&room)
		play := game.play_card(&room, card_id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		assert(render.begin_renderer_event_timeline(&iso_renderer, before, &room.recent_events))
		render.update_renderer_event_timeline(
			&iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&iso_renderer.timeline)
		assert(active && cue.kind == .Card_Played)
	} else if smoke_deck_flow {
		forge, created := game.create_temporary_card(&room.player.deck, .Spark_Forge)
		assert(created)
		before := render.capture_room_presentation(&room)
		play := game.play_card(&room, forge.id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		after := render.capture_room_presentation(&room)
		assert(render.begin_renderer_event_timeline(
			&iso_renderer,
			before,
			&room.recent_events,
			&after,
		))
		render.update_renderer_event_timeline(
			&iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION+
				render.PRESENTATION_CARD_CREATE_DURATION+
				render.PRESENTATION_CARD_MOVE_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&iso_renderer.timeline)
		assert(active && cue.kind == .Card_Moved && cue.event.to_card_zone == .Exhaust)
	} else if smoke_refocus {
		_, counter_created := game.create_temporary_card(&room.player.deck, .Counter_Rune)
		_, focus_created := game.create_temporary_card(&room.player.deck, .Battle_Focus)
		assert(counter_created && focus_created)
		before := render.capture_room_presentation(&room)
		refocus := game.refocus_player_hand(&room)
		assert(game.refocus_was_committed(refocus.result))
		after := render.capture_room_presentation(&room)
		assert(render.begin_renderer_event_timeline(
			&iso_renderer,
			before,
			&room.recent_events,
			&after,
		))
		render.update_renderer_event_timeline(
			&iso_renderer,
			render.PRESENTATION_REFOCUS_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&iso_renderer.timeline)
		assert(active && cue.kind == .Refocus)
	} else if smoke_movement {
		before := render.capture_room_presentation(&room)
		result := game.wait_player_turn(&room)
		assert(result != .Invalid_Phase)
		assert(render.begin_renderer_event_timeline(&iso_renderer, before, &room.recent_events))
		render.update_renderer_event_timeline(
			&iso_renderer,
			render.PRESENTATION_ENEMY_MOVE_DURATION*0.5,
		)
		cue, active := render.active_presentation_cue(&iso_renderer.timeline)
		assert(active && cue.kind == .Move)
	}

	for !app.should_close(&window) {
		defer free_all(context.temp_allocator)

		app.update_window_controls(&window)
		frame_time := rl.GetFrameTime()
		render.update_renderer_event_timeline(&iso_renderer, frame_time)
		mouse_canvas, mouse_inside := app.mouse_canvas_position(&window)
		mouse_delta := app.mouse_canvas_delta(&window)
		defeat_restart_hovered := run_state.phase == .Defeat && mouse_inside &&
			render.defeat_restart_at_point(
				f32(window.config.canvas_width),
				f32(window.config.canvas_height),
				mouse_canvas,
			)
		restart_requested := rl.IsKeyPressed(.F5) ||
			(run_state.phase == .Defeat && rl.IsKeyPressed(.ENTER)) ||
			(defeat_restart_hovered && rl.IsMouseButtonPressed(.LEFT))
		if restart_requested {
			run_seed += 1
			restarted := restart_demo_session(
				&level_data,
				&run_state,
				&room,
				run_seed,
				procedural_rooms,
			)
			assert(restarted)
			show_route_map = false
			clear_card_interaction(&card_interaction)
			clear_gameplay_command_buffer(&gameplay_buffer)
			reward_hovered_index = -1
			reward_skip_hovered = false
			shop_render_state = {hovered_offer_index = -1}
			special_render_state = {}
			defeat_restart_hovered = false
			render.frame_level(&iso_renderer, &level_data)
			render.clear_event_animations(&iso_renderer)
		}

		timeline_busy := render.renderer_timeline_is_busy(&iso_renderer)
		if rl.IsKeyPressed(.M) && route_map_toggle_is_allowed(&run_state, &room, &iso_renderer) {
			show_route_map = !show_route_map
			if show_route_map {
				clear_card_interaction(&card_interaction)
				clear_gameplay_command_buffer(&gameplay_buffer)
			}
		}
		defeat_visible := run_state.phase == .Defeat
		reward_visible := run_state.phase == .Reward
		shop_visible := run_state.phase == .Shop
		special_visible := run_state.phase == .Rest || run_state.phase == .Event ||
		                   run_state.phase == .Treasure
		route_visible := !reward_visible && !shop_visible && !special_visible &&
		                 (show_route_map || run_state.phase == .Choose_Path || run_state.phase == .Victory)
		hovered_node := game.INVALID_NODE_ID
		shop_button_hovered := false

		if defeat_visible {
			clear_card_interaction(&card_interaction)
			clear_gameplay_command_buffer(&gameplay_buffer)
		} else if reward_visible {
			clear_gameplay_command_buffer(&gameplay_buffer)
			previous_hovered_index := reward_hovered_index
			reward_hovered_index = -1
			reward_skip_hovered = false
			if smoke_reward {
				reward_hovered_index = 1
			} else if mouse_inside {
				if hovered_index, found := render.reward_card_at_point(
					&run_state,
					f32(window.config.canvas_width),
					f32(window.config.canvas_height),
					mouse_canvas,
					previous_hovered_index,
				); found {
					reward_hovered_index = hovered_index
				} else {
					reward_skip_hovered = render.reward_skip_at_point(
						f32(window.config.canvas_width),
						f32(window.config.canvas_height),
						mouse_canvas,
					)
				}
			}

			choice_index := pressed_hand_slot()
			choice_requested := choice_index >= 0 && choice_index < game.CARD_REWARD_CHOICE_COUNT
			skip_requested := rl.IsKeyPressed(.S)
			if mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
				if reward_hovered_index >= 0 {
					choice_index = reward_hovered_index
					choice_requested = true
				} else if reward_skip_hovered {
					skip_requested = true
				}
			}

			resolved := false
			if choice_requested {
				result := game.choose_card_reward(&run_state, choice_index)
				resolved = result == .Added
			} else if skip_requested {
				result := game.skip_card_reward(&run_state)
				resolved = result == .Skipped
			}
			if resolved {
				reward_visible = false
				shop_visible = false
				route_visible = true
				show_route_map = true
				reward_hovered_index = -1
				reward_skip_hovered = false
			}
		} else if shop_visible {
			clear_card_interaction(&card_interaction)
			clear_gameplay_command_buffer(&gameplay_buffer)
			shop_render_state.page = render.shop_clamp_deck_page(
				&run_state.player.deck,
				shop_render_state.page,
			)
			previous_hovered_offer := -1
			if shop_render_state.has_hovered_offer {
				previous_hovered_offer = shop_render_state.hovered_offer_index
			}
			previous_hovered_card := shop_render_state.hovered_card_id
			shop_render_state.has_hovered_offer = false
			shop_render_state.hovered_offer_index = 0
			shop_render_state.hovered_card_id = 0
			shop_render_state.previous_page_hovered = false
			shop_render_state.next_page_hovered = false
			shop_render_state.upgrade_hovered = false
			shop_render_state.remove_hovered = false
			shop_render_state.continue_hovered = false

			shop_hit: render.Shop_Hit
			if smoke_shop {
				shop_render_state.has_hovered_offer = true
				shop_render_state.hovered_offer_index = 1
			} else if mouse_inside {
				shop_hit = render.shop_hit_test(
					&run_state,
					f32(window.config.canvas_width),
					f32(window.config.canvas_height),
					shop_render_state.page,
					mouse_canvas,
					previous_hovered_offer,
					previous_hovered_card,
				)
				switch shop_hit.kind {
				case .None:
				case .Offer:
					shop_render_state.has_hovered_offer = true
					shop_render_state.hovered_offer_index = shop_hit.offer_index
				case .Owned_Card:
					shop_render_state.hovered_card_id = shop_hit.card_id
				case .Previous_Page:
					shop_render_state.previous_page_hovered = true
				case .Next_Page:
					shop_render_state.next_page_hovered = true
				case .Upgrade:
					shop_render_state.upgrade_hovered = true
				case .Remove:
					shop_render_state.remove_hovered = true
				case .Continue:
					shop_render_state.continue_hovered = true
				}
			}

			if !smoke_shop {
				offer_index := pressed_hand_slot()
				if offer_index >= 0 && offer_index < game.SHOP_CARD_OFFER_COUNT {
					game.buy_shop_card(&run_state, offer_index)
				}
				if rl.IsKeyPressed(.LEFT) {
					shop_render_state.page = max(0, shop_render_state.page-1)
					shop_render_state.selected_card_id = 0
				} else if rl.IsKeyPressed(.RIGHT) {
					shop_render_state.page = min(
						render.shop_deck_page_count(&run_state.player.deck)-1,
						shop_render_state.page+1,
					)
					shop_render_state.selected_card_id = 0
				}
				if rl.IsKeyPressed(.U) && shop_render_state.selected_card_id != 0 {
					game.buy_shop_upgrade(&run_state, shop_render_state.selected_card_id)
				} else if rl.IsKeyPressed(.R) && shop_render_state.selected_card_id != 0 {
					result := game.buy_shop_removal(&run_state, shop_render_state.selected_card_id)
					if result == .Removed {
						shop_render_state.selected_card_id = 0
					}
				}

				leave_requested := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.ESCAPE)
				if mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
					switch shop_hit.kind {
					case .None:
					case .Offer:
						game.buy_shop_card(&run_state, shop_hit.offer_index)
					case .Owned_Card:
						shop_render_state.selected_card_id = shop_hit.card_id
					case .Previous_Page:
						shop_render_state.page = max(0, shop_render_state.page-1)
						shop_render_state.selected_card_id = 0
					case .Next_Page:
						shop_render_state.page = min(
							render.shop_deck_page_count(&run_state.player.deck)-1,
							shop_render_state.page+1,
						)
						shop_render_state.selected_card_id = 0
					case .Upgrade:
						if shop_render_state.selected_card_id != 0 {
							game.buy_shop_upgrade(&run_state, shop_render_state.selected_card_id)
						}
					case .Remove:
						if shop_render_state.selected_card_id != 0 {
							result := game.buy_shop_removal(
								&run_state,
								shop_render_state.selected_card_id,
							)
							if result == .Removed {
								shop_render_state.selected_card_id = 0
							}
						}
					case .Continue:
						leave_requested = true
					}
				}
				shop_render_state.page = render.shop_clamp_deck_page(
					&run_state.player.deck,
					shop_render_state.page,
				)
				if leave_requested && game.leave_shop(&run_state) == .Left {
					shop_visible = false
					route_visible = true
					show_route_map = true
					shop_render_state = {}
				}
			}
		} else if special_visible {
			clear_card_interaction(&card_interaction)
			clear_gameplay_command_buffer(&gameplay_buffer)
			special_render_state.page = render.special_node_clamp_deck_page(
				&run_state.player.deck,
				special_render_state.page,
			)
			previous_hovered_card := special_render_state.hovered_card_id
			special_render_state.hovered_card_id = 0
			special_render_state.previous_page_hovered = false
			special_render_state.next_page_hovered = false
			special_render_state.primary_hovered = false
			special_render_state.secondary_hovered = false
			special_render_state.leave_hovered = false
			special_render_state.continue_hovered = false

			special_hit: render.Special_Node_Hit
			special_smoke := smoke_rest || smoke_event || smoke_treasure || smoke_special_result
			if special_smoke {
				if smoke_special_result {
					special_render_state.continue_hovered = true
				} else if smoke_rest {
					special_render_state.secondary_hovered = true
				} else {
					special_render_state.primary_hovered = true
				}
			} else if mouse_inside {
				special_hit = render.special_node_hit_test(
					&run_state,
					f32(window.config.canvas_width),
					f32(window.config.canvas_height),
					special_render_state.page,
					mouse_canvas,
					previous_hovered_card,
					special_render_state.selected_card_id,
				)
				switch special_hit.kind {
				case .None:
				case .Primary:
					special_render_state.primary_hovered = true
				case .Secondary:
					special_render_state.secondary_hovered = true
				case .Leave:
					special_render_state.leave_hovered = true
				case .Owned_Card:
					special_render_state.hovered_card_id = special_hit.card_id
				case .Previous_Page:
					special_render_state.previous_page_hovered = true
				case .Next_Page:
					special_render_state.next_page_hovered = true
				case .Continue:
					special_render_state.continue_hovered = true
				}
			}

			if !special_smoke {
				requested := render.Special_Node_Hit{kind = .None}
				if game.special_node_can_continue(&run_state) {
					if rl.IsKeyPressed(.ENTER) {
						requested.kind = .Continue
					}
				} else {
					choice_index := pressed_hand_slot()
					if choice_index == 0 {
						requested.kind = .Primary
					} else if choice_index == 1 {
						requested.kind = .Secondary
					}
					if rl.IsKeyPressed(.L) {
						requested.kind = .Leave
					} else if run_state.phase == .Rest && rl.IsKeyPressed(.U) {
						requested.kind = .Secondary
					}
				}
				if run_state.phase == .Rest && rl.IsKeyPressed(.LEFT) {
					special_render_state.page = max(0, special_render_state.page-1)
					special_render_state.selected_card_id = 0
				} else if run_state.phase == .Rest && rl.IsKeyPressed(.RIGHT) {
					special_render_state.page = min(
						render.special_node_deck_page_count(&run_state.player.deck)-1,
						special_render_state.page+1,
					)
					special_render_state.selected_card_id = 0
				}
				if mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
					requested = special_hit
				}
				primary_enabled := render.special_node_primary_is_enabled(&run_state)
				secondary_enabled := render.special_node_secondary_is_enabled(
					&run_state,
					special_render_state.selected_card_id,
				)
				if requested.kind == .Primary && !primary_enabled {
					requested.kind = .None
				} else if requested.kind == .Secondary && !secondary_enabled {
					requested.kind = .None
				}

				switch requested.kind {
				case .None:
				case .Owned_Card:
					special_render_state.selected_card_id = requested.card_id
				case .Previous_Page:
					special_render_state.page = max(0, special_render_state.page-1)
					special_render_state.selected_card_id = 0
				case .Next_Page:
					special_render_state.page = min(
						render.special_node_deck_page_count(&run_state.player.deck)-1,
						special_render_state.page+1,
					)
					special_render_state.selected_card_id = 0
				case .Primary:
					switch run_state.phase {
					case .Rest:
						game.use_rest_recovery(&run_state)
					case .Event:
						game.resolve_route_event(&run_state, .Primary)
					case .Treasure:
						game.claim_treasure(&run_state)
					case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
					}
				case .Secondary:
					if run_state.phase == .Rest {
						game.use_rest_upgrade(
							&run_state,
							special_render_state.selected_card_id,
						)
					} else if run_state.phase == .Event {
						game.resolve_route_event(&run_state, .Secondary)
					}
				case .Leave:
					game.leave_special_node(&run_state)
				case .Continue:
					if game.continue_special_node(&run_state) == .Continued {
						special_visible = false
						route_visible = true
						show_route_map = true
						special_render_state = {}
					}
				}
				special_render_state.page = render.special_node_clamp_deck_page(
					&run_state.player.deck,
					special_render_state.page,
				)
			}
		} else if route_visible {
			if mouse_inside {
				shop_button_hovered = run_state.phase == .Choose_Path &&
					run_state.shop.offer_count > 0 && render.run_shop_button_at_point(
						f32(window.config.canvas_width),
						f32(window.config.canvas_height),
						mouse_canvas,
					)
				if !shop_button_hovered {
					if hovered, found := render.run_node_at_point(
					&run_state,
					f32(window.config.canvas_width),
					f32(window.config.canvas_height),
					mouse_canvas,
				); found {
					hovered_node = hovered
					}
				}
			}

			if run_state.phase == .Choose_Path {
				shop_requested := shop_button_hovered && rl.IsMouseButtonPressed(.LEFT)
				if shop_requested && game.open_shop(&run_state) == .Opened {
					shop_visible = true
					route_visible = false
					show_route_map = false
					shop_render_state = {}
				}
				selected_node, selected := keyboard_route_choice(&run_state)
				if mouse_inside && rl.IsMouseButtonPressed(.LEFT) && hovered_node != game.INVALID_NODE_ID {
					selected_node = hovered_node
					selected = true
				}
				if selected && enter_demo_node(
					&level_data,
					&run_state,
					&room,
					selected_node,
					procedural_rooms,
				) {
					show_route_map = false
					route_visible = false
					shop_visible = run_state.phase == .Shop
					special_visible = run_state.phase == .Rest || run_state.phase == .Event ||
					                  run_state.phase == .Treasure
					clear_card_interaction(&card_interaction)
					clear_gameplay_command_buffer(&gameplay_buffer)
					reward_hovered_index = -1
					reward_skip_hovered = false
					shop_render_state = {}
					special_render_state = {}
					if run_state.phase == .In_Room {
						render.frame_level(&iso_renderer, &level_data)
					}
					render.clear_event_animations(&iso_renderer)
				}
			}
		} else {
			render.update_camera(
				&iso_renderer,
				&level_data,
				mouse_canvas,
				mouse_inside,
				mouse_delta,
				frame_time,
			)
			if !smoke_card && !smoke_targeting && !smoke_spatial && !smoke_content {
				timeline_busy = render.renderer_timeline_is_busy(&iso_renderer)
				command, has_command := poll_gameplay_command(
					&room,
					&iso_renderer,
					&card_interaction,
					mouse_canvas,
					mouse_inside,
					!timeline_busy && !gameplay_buffer.occupied,
				)
				if room.phase == .Complete || room.phase == .Defeat {
					clear_gameplay_command_buffer(&gameplay_buffer)
				} else if timeline_busy {
					if has_command {
						offer_gameplay_command(&gameplay_buffer, command)
					}
				} else if buffered, has_buffered := take_gameplay_command(&gameplay_buffer); has_buffered {
					if has_command {
						offer_gameplay_command(&gameplay_buffer, command)
					}
					commit_gameplay_command(
						&room,
						&iso_renderer,
						&card_interaction,
						buffered,
					)
				} else if has_command {
					commit_gameplay_command(
						&room,
						&iso_renderer,
						&card_interaction,
						command,
					)
				}
			}
			if room_transition_is_ready(&run_state, &room, &iso_renderer) {
				transition := game.finish_room(&run_state, room.phase)
				if transition == .Reward {
					show_route_map = false
					reward_visible = true
					route_visible = false
					clear_card_interaction(&card_interaction)
					clear_gameplay_command_buffer(&gameplay_buffer)
					render.clear_event_animations(&iso_renderer)
				} else if transition == .Victory {
					show_route_map = true
					route_visible = true
					clear_card_interaction(&card_interaction)
					clear_gameplay_command_buffer(&gameplay_buffer)
				} else if transition == .Defeat {
					defeat_visible = true
					clear_card_interaction(&card_interaction)
					clear_gameplay_command_buffer(&gameplay_buffer)
					render.clear_event_animations(&iso_renderer)
				}
			}
		}
		app.begin_canvas(&window, render.CANVAS_BACKGROUND)
		if reward_visible {
			render.draw_reward_screen(
				&run_state,
				f32(window.config.canvas_width),
				f32(window.config.canvas_height),
				reward_hovered_index,
				reward_skip_hovered,
			)
		} else if shop_visible {
			render.draw_shop_screen(
				&run_state,
				f32(window.config.canvas_width),
				f32(window.config.canvas_height),
				shop_render_state,
			)
		} else if special_visible {
			render.draw_special_node_screen(
				&run_state,
				f32(window.config.canvas_width),
				f32(window.config.canvas_height),
				special_render_state,
			)
		} else if route_visible {
			render.draw_run_map(
				&run_state,
				f32(window.config.canvas_width),
				f32(window.config.canvas_height),
				hovered_node,
				shop_button_hovered,
			)
		} else {
			if smoke_card || smoke_targeting || smoke_spatial || smoke_content {
				iso_renderer.hovered_cell = {x = 4, y = 1}
				if smoke_targeting || smoke_content {
					iso_renderer.hovered_cell = {x = 4, y = 2}
				}
				iso_renderer.has_hovered_cell = true
			}
			timeline_busy = render.renderer_timeline_is_busy(&iso_renderer)
			active_card_id := active_targeting_card_id(card_interaction)
			if timeline_busy {
				active_card_id = 0
			}
			render.draw_level(&iso_renderer, &level_data)
			if !timeline_busy {
				render.draw_enemy_intent_ground(
					&iso_renderer,
					&room,
					active_card_id != 0,
				)
				render.draw_card_target_range(
					&iso_renderer,
					&room,
					active_card_id,
				)
			}
			render.draw_room(&iso_renderer, &room)
			if !timeline_busy {
				render.draw_enemy_intent_badges(&iso_renderer, &room)
			}
			render.draw_status(&iso_renderer, &room, window.scale_mode)
			draw_mouse_canvas := mouse_canvas
			if smoke_card || smoke_targeting || smoke_spatial || smoke_content {
				draw_mouse_canvas = {x = 520, y = 165}
			}
			render.draw_hand(
				&iso_renderer,
				&room,
				card_interaction.hovered_card_id,
				card_interaction.selected_card_id,
				card_interaction.dragged_card_id,
				draw_mouse_canvas,
			)
			if defeat_visible {
				render.draw_defeat_overlay(
					&run_state,
					f32(window.config.canvas_width),
					f32(window.config.canvas_height),
					defeat_restart_hovered,
				)
			}
		}
		app.present(&window, render.LETTERBOX_COLOR)

		if smoke_test {
			smoke_frame_count += 1
			if smoke_frame_count >= 3 {
				if smoke_generation {
					rl.TakeScreenshot("odin_pp_procedural_room.png")
				} else if smoke_map {
					rl.TakeScreenshot("odin_pp_route.png")
				} else if smoke_status {
					rl.TakeScreenshot("odin_pp_status.png")
				} else if smoke_loot {
					rl.TakeScreenshot("odin_pp_loot.png")
				} else if smoke_card {
					rl.TakeScreenshot("odin_pp_card_drag.png")
				} else if smoke_targeting {
					rl.TakeScreenshot("odin_pp_advanced_targeting.png")
				} else if smoke_spatial {
					rl.TakeScreenshot("odin_pp_spatial_targeting.png")
				} else if smoke_content {
					rl.TakeScreenshot("odin_pp_content_pass.png")
				} else if smoke_movement {
					rl.TakeScreenshot("odin_pp_enemy_movement.png")
				} else if smoke_timeline {
					rl.TakeScreenshot("odin_pp_timeline.png")
				} else if smoke_deck_flow {
					rl.TakeScreenshot("odin_pp_deck_flow.png")
				} else if smoke_refocus {
					rl.TakeScreenshot("odin_pp_refocus.png")
				} else if smoke_reward {
					rl.TakeScreenshot("odin_pp_reward.png")
				} else if smoke_shop {
					rl.TakeScreenshot("odin_pp_shop.png")
				} else if smoke_rest {
					rl.TakeScreenshot("odin_pp_rest.png")
				} else if smoke_event {
					rl.TakeScreenshot("odin_pp_event.png")
				} else if smoke_treasure {
					rl.TakeScreenshot("odin_pp_treasure.png")
				} else if smoke_special_result {
					rl.TakeScreenshot("odin_pp_special_result.png")
				} else if smoke_intents {
					rl.TakeScreenshot("odin_pp_enemy_intents.png")
				} else if smoke_archetypes {
					rl.TakeScreenshot("odin_pp_enemy_archetypes.png")
				} else if smoke_defeat {
					rl.TakeScreenshot("odin_pp_defeat.png")
				} else {
					rl.TakeScreenshot("odin_pp_isometric.png")
				}
				break
			}
		}
	}
}
