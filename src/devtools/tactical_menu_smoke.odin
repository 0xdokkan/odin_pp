package devtools
import artifacts "artifacts"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

run_tactical_voxel_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{"#########", "#.......#", "#.......#", "#..#....#", "#...@...#", "#.......#", "#....>..#", "#.......#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	player, ok := game.create_player({max_health = 22, attack = 2, defense = 1})
	if !ok || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	enemies := [?]game.Enemy_Spawn{{position = {x = 6, y = 2}, health = 12, attack = 2, archetype = .Bomber}}
	objects := [?]game.Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 3, y = 4}}, {kind = .Barrel, position = {x = 5, y = 4}},
		{kind = .Fire, position = {x = 5, y = 3}}}
	traps := [?]game.Trap_Spawn{{position = {x = 4, y = 5}, damage = 2}}
	covers := [?]grid.Position{{x = 3, y = 6}}
	room, created := game.create_room(&data, &player, {enemies = enemies[:], objects = objects[:], traps = traps[:], obstacles = covers[:]})
	if !created { return false }
	defer game.destroy_room(&room)
	if !game.spawn_bomb(&room, game.enemy_entity(1), {x = 5, y = 5}, room.recent_events) { return false }
	game.plan_enemy_intents(&room)
	renderer.timeline = {}
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	for view in 0..<3 {
		if view == 1 { render.adjust_tactical_orbit(&renderer.tactical.world_orbit, {95, 0}, 0) }
		if view == 2 { player.tactical.config.vision_size = 0 }
		for _ in 0..<3 {
			render.update_tactical_view(renderer, &room, {}, false, true)
			app.begin_canvas(window, render.GOTHIC_INK)
			render.draw_tactical_world(renderer, &room, 0)
			render.draw_status(renderer, &room, window.scale_mode)
			render.draw_tactical_hand(renderer, &room, 0, 0, 0, {})
			render.draw_tactical_hud(renderer, &room, false, false)
			app.present(window, render.LETTERBOX_COLOR)
		}
		artifacts.screenshot(fmt.ctprintf("odin_pp_m7_voxels_%d.png", view))
	}
	return true
}

capture_tactical_menu :: proc(window: ^app.Window, renderer: ^render.Renderer, run: ^game.Run_State, filename: cstring) {
	w, h := f32(window.config.canvas_width), f32(window.config.canvas_height)
	for _ in 0..<3 {
		app.begin_canvas(window, render.GOTHIC_INK)
		if game.run_has_relic_choice(run) { render.draw_relic_reward_screen(run, w, h, 0, false, theme = renderer) }
		else {
			switch run.phase {
			case .Reward: render.draw_reward_screen(run, w, h, 0, theme = renderer)
			case .Shop: render.draw_shop_screen(run, w, h, {selected_card_id = run.player.deck.owned[0].id}, theme = renderer)
			case .Rest, .Event, .Treasure: render.draw_special_node_screen(run, w, h, {selected_card_id = run.player.deck.owned[0].id}, theme = renderer)
			case .Defeat: render.draw_defeat_overlay(run, w, h, .Restart, true, theme = renderer)
			case .In_Room, .Choose_Path, .Victory: render.draw_run_map(run, w, h, theme = renderer)
			}
		}
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot(filename)
}

run_tactical_menu_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	stats := game.Player_Stats{max_health = 22, attack = 2, defense = 1}
	config := game.Run_Map_Config{layer_count = 5, min_nodes_per_middle_layer = 2, max_nodes_per_middle_layer = 3}
	run, ok := game.create_run(stats, config, 991, true)
	if !ok { return false }
	defer game.destroy_run(&run)
	capture_tactical_menu(window, renderer, &run, "odin_pp_m7_relics.png")
	if !game.choose_run_relic(&run, 0) || game.finish_room(&run, .Complete) != .Reward { return false }
	capture_tactical_menu(window, renderer, &run, "odin_pp_m7_reward.png")
	if game.skip_card_reward(&run) != .Skipped { return false }
	capture_tactical_menu(window, renderer, &run, "odin_pp_m7_route.png")
	// Terminal snapshots exercise the same actual screen renderers.
	run.phase = .Defeat
	capture_tactical_menu(window, renderer, &run, "odin_pp_m7_defeat.png")
	run.phase = .Victory
	capture_tactical_menu(window, renderer, &run, "odin_pp_m7_victory.png")
	for kind in ([?]game.Node_Kind{.Shop, .Rest, .Event, .Treasure}) {
		captured := false
		for seed in u64(1)..<u64(512) {
			sample, created := game.create_run(stats, config, seed)
			if !created { return false }
			current, _ := game.current_run_node(&sample)
			target := game.INVALID_NODE_ID
			for id in current.outgoing[:current.outgoing_count] {
				if node, found := game.node_at(&sample, id); found && node.kind == kind { target = id; break }
			}
			if target == game.INVALID_NODE_ID { game.destroy_run(&sample); continue }
			sample.player.gold = 35
			sample.player.health = 12
			if game.finish_room(&sample, .Complete) != .Reward || game.skip_card_reward(&sample) != .Skipped {
				game.destroy_run(&sample); return false
			}
			if game.enter_node(&sample, target) == .Invalid { game.destroy_run(&sample); return false }
			capture_tactical_menu(window, renderer, &sample, fmt.ctprintf("odin_pp_m7_menu_%s.png", game.node_kind_name(kind)))
			game.destroy_run(&sample)
			captured = true
			break
		}
		if !captured { return false }
	}
	return true
}
