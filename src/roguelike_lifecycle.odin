package main

import "core:fmt"
import rl "vendor:raylib"
import audio "engine/audio"
import combatdebug "combatdebug"
import host "engine/host"
import game "game"
import grid "grid"
import level "level"
import render "render"

// Run/room ownership and transitions. Prepared rooms are installed atomically;
// restart, node entry and room completion keep their own reset/report ordering.

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
	objects := [?]game.Grid_Object_Spawn{
		{kind = .Ice_Block, position = {x = 6, y = 6}},
		{kind = .Ice_Block, position = {x = 10, y = 6}},
		{kind = .Fire, position = {x = 6, y = 2}},
		{kind = .Fire, position = {x = 11, y = 5}},
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
		objects = objects[:],
		node_kind = node.kind,
		node_depth = node.depth,
		room_seed = node.room_seed,
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
		blueprint, blueprint_error := game.generate_room_blueprint(node, run.last_room_family, run.player.tactical.config.enabled)
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
	run.last_room_family = room.family
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
	new_run, run_ok := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, seed, run.relic_rewards_enabled)
	if !run_ok {
		return false
	}
	defer game.destroy_run(&new_run)
	if run.player.tactical.config.enabled && !configure_demo_tactical_player(&new_run.player, run.player.tactical.config) { return false }
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
	run.last_room_family = room.family
	prepared.room = {}
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

roguelike_restart :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) -> bool {
	if rs.playtest_session_ptr != nil {
		if !rs.playtest_report_written {
			rs.playtest_report_written = finish_seed_playtest_report(
				rs.playtest_session_ptr,
				rs.run_seed,
				rs.options.playtest_output,
				playtest_outcome_for_state(&rs.run_state, &rs.room),
				&rs.room,
			)
			if !rs.playtest_report_written {
				fmt.eprintln("failed to write playtest report before restart")
				return false
			}
		}
		combatdebug.destroy_playtest_session(rs.playtest_session_ptr)
		rs.playtest_session_ptr = nil
	}
	if rs.playtest_report && !write_m7_metrics(&rs.run_state.player, rs.run_seed, rs.options.playtest_output) {
		fmt.eprintln("failed to write M7 metrics before restart")
		return false
	}
	rs.run_seed += 1
	m8_profile := rs.run_state.player.m8_profile
	restarted := restart_demo_session(
		&rs.level_data,
		&rs.run_state,
		&rs.room,
		rs.run_seed,
		rs.procedural_rooms,
	)
	assert(restarted)
	rs.run_state.player.m8_profile = m8_profile
	rs.m8_session.character_open = false
	if rs.options.tactical.enabled {
		configured := game.configure_tactical_room(&rs.room, rs.options.tactical)
		assert(configured)
		rs.tactical_controller = {}
	}
	if rs.options.spell_lab {
		if !prepare_spell_lab(&rs.room, rs.options.dice_lab) { fmt.eprintln("could not reset card practice"); host.quit(hf); return false }
	}
	if rs.options.mechanics_lab {
		if !prepare_mechanics_lab(rs) { fmt.eprintln("could not reset the mechanics lab"); host.quit(hf); return false }
		rs.tactical_controller = {}
	}
	if rs.playtest_report && !game.run_has_relic_choice(&rs.run_state) {
		playtest_started := begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room)
		assert(playtest_started)
		rs.playtest_session_ptr = &rs.playtest_session
		rs.playtest_report_written = false
	}
	rs.show_route_map = false
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	rs.reward_hovered_index = -1
	rs.reward_skip_hovered = false
	rs.shop_render_state = {hovered_offer_index = -1}
	rs.special_render_state = {}
	rs.defeat_hovered = .None
	render.frame_level(&rs.iso_renderer, &rs.level_data)
	render.clear_event_animations(&rs.iso_renderer)
	return true
}

roguelike_enter_node :: proc(rs: ^Roguelike_Session, node_id: game.Node_Id) -> bool {
	if !enter_demo_node(&rs.level_data, &rs.run_state, &rs.room, node_id, rs.procedural_rooms) { return false }
	rs.show_route_map = false
	rs.route_visible = false
	rs.shop_visible = rs.run_state.phase == .Shop
	rs.special_visible = rs.run_state.phase == .Rest || rs.run_state.phase == .Event ||
	                  rs.run_state.phase == .Treasure
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	rs.reward_hovered_index = -1
	rs.reward_skip_hovered = false
	rs.shop_render_state = {}
	rs.special_render_state = {}
	if rs.run_state.phase == .In_Room {
		if rs.playtest_session_ptr != nil {
			playtest_room_started := begin_current_playtest_room(
				rs.playtest_session_ptr,
				&rs.run_state,
				&rs.room,
			)
			assert(playtest_room_started)
		}
		render.frame_level(&rs.iso_renderer, &rs.level_data)
	}
	render.clear_event_animations(&rs.iso_renderer)
	return true
}

roguelike_finish_room :: proc(rs: ^Roguelike_Session) {
	if !room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer) { return }
	transition := game.finish_room(&rs.run_state, rs.room.phase)
	if rs.playtest_session_ptr != nil &&
	   (transition == .Victory || transition == .Defeat) &&
	   !rs.playtest_report_written {
		rs.playtest_report_written = finish_seed_playtest_report(
			rs.playtest_session_ptr,
			rs.run_seed,
			rs.options.playtest_output,
			playtest_outcome_for_state(&rs.run_state, &rs.room),
			&rs.room,
		)
		if !rs.playtest_report_written {
			fmt.eprintln("failed to write completed playtest report")
		}
	}
	if transition == .Reward {
		rs.show_route_map = false
		rs.reward_visible = true
		rs.route_visible = false
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		render.clear_event_animations(&rs.iso_renderer)
	} else if transition == .Victory {
		rs.show_route_map = true
		rs.route_visible = true
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
	} else if transition == .Defeat {
		rs.defeat_visible = true
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		render.clear_event_animations(&rs.iso_renderer)
	}
}

roguelike_destroy :: proc(data: rawptr) {
	rs := cast(^Roguelike_Session)data
	// MOSTRA EFFETTO's film borrows the run renderer's assets: it goes first.
	destroy_effect_window(&rs.effect_window)
	if rs.attached {
		rl.EnableCursor()
		if rs.playtest_session_ptr != nil && !rs.playtest_report_written {
			rs.playtest_report_written = finish_seed_playtest_report(
				rs.playtest_session_ptr,
				rs.run_seed,
				rs.options.playtest_output,
				playtest_outcome_for_state(&rs.run_state, &rs.room),
				&rs.room,
			)
			if !rs.playtest_report_written {
				fmt.eprintln("failed to write playtest report on exit")
			}
		}

		if rs.sprites_loaded {
			render.unload_sprite_assets(&rs.iso_renderer.sprite_assets)
		}
		if rs.playtest_report && !write_m7_metrics(&rs.run_state.player, rs.run_seed, rs.options.playtest_output) {
			fmt.eprintln("failed to write M7 metrics")
		}
		audio.lab_bank_unload(&rs.lab_bank)
		render.destroy_tactical_assets(&rs.iso_renderer)
		combatdebug.destroy_playtest_session(&rs.playtest_session)
		render.destroy_dice_renderer(&rs.dice_renderer)
	}
	if rs.room_created {
		game.destroy_room(&rs.room)
	}
	if rs.run_created {
		game.destroy_run(&rs.run_state)
	}
	level.destroy(&rs.level_data)
	delete(rs.challenge_message)
	free(rs)
}
