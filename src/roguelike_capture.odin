package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import host "engine/host"
import game "game"
import render "render"

// Scripted fixtures and capture dispatch. These hooks run at the same attach
// and after-present boundaries as the interactive scene, preserving smoke order.

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

roguelike_attach_smoke :: proc(rs: ^Roguelike_Session) -> Session_Start {
	if rs.spell_smoke != .None {
		if !prepare_spell_smoke(&rs.room, &rs.iso_renderer, rs.spell_smoke) { fmt.eprintln("spell smoke setup failed"); os.exit(2) }
		if spell_smoke_is_preview(rs.spell_smoke) {
			index := 3 if rs.spell_smoke == .Sunder_Preview else 2
			rs.card_interaction.selected_card_id = rs.room.player.deck.hand[index].id
			rs.iso_renderer.hovered_cell = rs.room.enemies[0].position
			rs.iso_renderer.has_hovered_cell = true
		}
	} else if rs.smoke_map {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		reward_skipped := game.skip_card_reward(&rs.run_state) == .Skipped
		assert(reward_skipped)
		rs.show_route_map = true
	} else if rs.smoke_reward {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		rs.reward_hovered_index = 1
	} else if rs.smoke_shop || rs.smoke_rest || rs.smoke_event || rs.smoke_treasure || rs.smoke_special_result {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		reward_skipped := game.skip_card_reward(&rs.run_state) == .Skipped
		assert(reward_skipped)
		desired_kind := game.Node_Kind.Shop
		if rs.smoke_rest {
			desired_kind = .Rest
			rs.run_state.player.health = rs.run_state.player.stats.max_health/2
		} else if rs.smoke_event {
			desired_kind = .Event
		} else if rs.smoke_treasure || rs.smoke_special_result {
			desired_kind = .Treasure
		}
		if rs.smoke_shop {
			rs.run_state.player.gold = 20
		}
		special_node := available_node_of_kind(&rs.run_state, desired_kind)
		assert(special_node != game.INVALID_NODE_ID)
		node_entered := enter_demo_node(
			&rs.level_data,
			&rs.run_state,
			&rs.room,
			special_node,
			rs.procedural_rooms,
		)
		assert(node_entered)
		if rs.smoke_shop {
			rs.shop_render_state.has_hovered_offer = true
			rs.shop_render_state.hovered_offer_index = 1
			rs.shop_render_state.selected_card_id = rs.run_state.player.deck.owned[0].id
		} else if rs.smoke_rest {
			rs.special_render_state.selected_card_id = rs.run_state.player.deck.owned[0].id
			rs.special_render_state.secondary_hovered = true
		} else {
			rs.special_render_state.primary_hovered = true
		}
		if rs.smoke_special_result {
			treasure_claimed := game.claim_treasure(&rs.run_state) == .Treasure_Claimed
			assert(treasure_claimed)
			rs.special_render_state.primary_hovered = false
			rs.special_render_state.continue_hovered = true
		}
	} else if rs.smoke_tactics {
		prepared := prepare_tactics_smoke(&rs.room)
		assert(prepared)
	} else if rs.smoke_sprites {
		prepared := prepare_tactics_smoke(&rs.room) && prepare_sprite_smoke(&rs.iso_renderer)
		assert(prepared)
		for &object in rs.room.objects {
			if object.kind == .Ice_Block { object.health = 2 }
		}
	} else if rs.smoke_relic_combat {
		prepared := prepare_tactics_smoke(&rs.room)
		assert(prepared)
		for definition in game.RELIC_DEFINITIONS {
			added := game.acquire_relic(rs.room.player, definition.id)
			assert(added)
		}
		game.begin_room_relics(&rs.room)
	} else if rs.smoke_encounters || rs.smoke_miniboss || rs.smoke_furnace {
		kind: Encounter_Smoke = .Escort
		if rs.smoke_miniboss { kind = .Miniboss }
		if rs.smoke_furnace { kind = .Furnace }
		card_id, prepared := prepare_encounter_smoke(&rs.room, &rs.iso_renderer, kind)
		assert(prepared)
		rs.card_interaction.selected_card_id = card_id
	} else if rs.smoke_intents {
		rs.room.enemies[0].position = {x = 2, y = 1}
		rs.room.enemies[1].position = {x = 7, y = 1}
		rs.room.enemies[2].position = {x = 4, y = 6}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_archetypes {
		rs.room.enemies[0].archetype = .Chaser
		rs.room.enemies[0].position = {x = 4, y = 6}
		rs.room.enemies[1].archetype = .Archer
		rs.room.enemies[1].position = {x = 5, y = 1}
		rs.room.enemies[2].archetype = .Brute
		rs.room.enemies[2].position = {x = 1, y = 4}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_defeat {
		rs.room.player.health = 1
		rs.room.enemies[0].archetype = .Chaser
		rs.room.enemies[0].position = {x = 2, y = 1}
		game.plan_enemy_intents(&rs.room)
		before := render.capture_room_presentation(&rs.room)
		result := game.wait_player_turn(&rs.room)
		assert(result == .Player_Defeated)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		timeline_finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
		assert(timeline_finished)
		assert(!render.renderer_timeline_is_busy(&rs.iso_renderer))
	} else if rs.smoke_status {
		game.use_player_ability(&rs.room, .Toxic_Wave)
		game.use_player_ability(&rs.room, .Guard)
		game.use_player_ability(&rs.room, .Thorn_Coat)
		game.use_player_ability(&rs.room, .Afterimage)
		// The stacks on show too: Bruciatura on the player, every one on a foe.
		if len(rs.room.enemies) > 0 {
			foe := game.enemy_entity(rs.room.enemies[0].id)
			for kind in ([3]game.Status_Kind{.Poison, .Burn, .Slow}) { _, _ = game.apply_status(&rs.room, foe, kind, 2, 0) }
		}
		_, _ = game.apply_status(&rs.room, game.PLAYER_ENTITY, .Burn, 1, 0)
	} else if rs.smoke_loot {
		rs.room.player.position = {x = 10, y = 2}
		rs.room.enemies[0].health = rs.room.player.stats.attack
		before := render.capture_room_presentation(&rs.room)
		result := game.try_move_player(&rs.room, .East)
		assert(result == .Attacked && rs.room.phase == .Combat)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_DAMAGE_DURATION+
				render.PRESENTATION_DEFEAT_DURATION+
				render.PRESENTATION_NOTICE_DURATION+
				render.PRESENTATION_LOOT_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Loot)
	} else if rs.smoke_card {
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Arc_Bolt)
		rs.room.enemies[0].position = {x = 4, y = 1}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_targeting {
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Firebomb)
		rs.room.enemies[0].position = {x = 3, y = 1}
		rs.room.enemies[1].position = {x = 4, y = 2}
		rs.room.enemies[2].position = {x = 3, y = 3}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_spatial {
		card, created := game.create_temporary_card(&rs.room.player.deck, .Dash)
		assert(created && len(rs.room.traps) > 0)
		rs.card_interaction.dragged_card_id = card.id
		rs.room.traps[0].position = {x = 3, y = 1}
		rs.room.traps[0].armed = true
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_object {
		assert(len(rs.room.objects) >= 2)
		rs.room.objects[0].position = {x = 2, y = 1}
		rs.room.objects[1].position = {x = 4, y = 2}
		shove, created := game.create_temporary_card(&rs.room.player.deck, .Shove)
		assert(created)
		rs.card_interaction.dragged_card_id = shove.id
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_fire {
		fire_index := -1
		for object, index in rs.room.objects {
			if object.kind == .Fire {
				fire_index = index
				break
			}
		}
		assert(fire_index >= 0)
		rs.room.player.position = {x = 6, y = 5}
		rs.room.objects[fire_index].position = {x = 7, y = 5}
		rs.smoke_fire_entity = game.object_entity(rs.room.objects[fire_index].id)
		game.plan_enemy_intents(&rs.room)
		before := render.capture_room_presentation(&rs.room)
		result := game.try_move_player(&rs.room, .East)
		assert(result == .Moved)
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_PLAYER_MOVE_DURATION+
				render.PRESENTATION_NOTICE_DURATION*0.25,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Hazard_Triggered)
		presentation_fire, fire_visible := render.presentation_grid_object(
			&rs.iso_renderer.timeline,
			rs.smoke_fire_entity,
		)
		assert(fire_visible && presentation_fire.visible && presentation_fire.kind == .Fire)
	} else if rs.smoke_content {
		game.finish_deck_combat(&rs.room.player.deck)
		deck_initialized := game.initialize_empty_deck(
			&rs.room.player.deck,
			game.DEFAULT_DECK_RULES,
			0xC017E17,
		)
		assert(deck_initialized)
		content_cards := [?]game.Card_Id{
			.Heavy_Blow,
			.Venom_Needle,
			.Caustic_Bloom,
			.Purifying_Guard,
			.Volatile_Study,
		}
		for definition_id in content_cards {
			_, added := game.add_owned_card(&rs.room.player.deck, definition_id)
			assert(added)
		}
		combat_started := game.begin_deck_combat(&rs.room.player.deck)
		assert(combat_started)
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Caustic_Bloom)
		rs.card_interaction.hovered_card_id = prepare_smoke_card_drag(&rs.room, .Volatile_Study)
		rs.room.enemies[0].position = {x = 3, y = 1}
		rs.room.enemies[1].position = {x = 4, y = 2}
		rs.room.enemies[2].position = {x = 3, y = 3}
		game.clear_enemy_intents(&rs.room)
	} else if rs.smoke_timeline {
		card_id := prepare_smoke_card_drag(&rs.room, .Guard)
		before := render.capture_room_presentation(&rs.room)
		play := game.play_card(&rs.room, card_id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Card_Played)
	} else if rs.smoke_deck_flow {
		forge, created := game.create_temporary_card(&rs.room.player.deck, .Spark_Forge)
		assert(created)
		before := render.capture_room_presentation(&rs.room)
		play := game.play_card(&rs.room, forge.id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION+
				render.PRESENTATION_CARD_CREATE_DURATION+
				render.PRESENTATION_CARD_MOVE_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Card_Moved && cue.event.to_card_zone == .Exhaust)
	} else if rs.smoke_refocus {
		_, counter_created := game.create_temporary_card(&rs.room.player.deck, .Counter_Rune)
		_, focus_created := game.create_temporary_card(&rs.room.player.deck, .Battle_Focus)
		assert(counter_created && focus_created)
		before := render.capture_room_presentation(&rs.room)
		refocus := game.refocus_player_hand(&rs.room)
		assert(game.refocus_was_committed(refocus.result))
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_REFOCUS_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Refocus)
	} else if rs.smoke_movement {
		before := render.capture_room_presentation(&rs.room)
		result := game.wait_player_turn(&rs.room)
		assert(result != .Invalid_Phase)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_ENEMY_MOVE_DURATION*0.5,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Move)
	}

	if rs.options.m8_view_smoke {
		if !run_m8_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M8 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.western_smoke {
		if !run_western_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("6 RANCH 7 smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.mechanics_lab_smoke {
		if !run_mechanics_lab_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("mechanics lab smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.effect_window_smoke {
		if !run_effect_window_smoke(rs) { fmt.eprintln("effect window smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.m9_lab != .None {
		run_m9_lab(rs.window, &rs.iso_renderer, rs.options.m9_lab)
		return .Finished
	}
	if rs.options.m9_smoke {
		if !run_m9_view_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M9 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.dice_set_lab || rs.options.dice_set_smoke {
		if !run_dice_set_lab(rs.window, &rs.iso_renderer, &rs.dice_renderer, rs.options.dice_set_smoke) {
			fmt.eprintln("Dice set lab failed")
			os.exit(2)
		}
		return .Finished
	}
	if rs.options.arena_view_smoke {
		if !run_arena_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("Arena native smoke failed"); os.exit(2) }
		return .Finished
	}

	return .Ready
}

roguelike_after_present :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	if rs.options.m7_view_smoke {
		done, valid := step_m7_view_smoke(&rs.m7_view_state, &rs.tactical_controller, &rs.room, &rs.iso_renderer, &rs.card_interaction)
		if done {
			if !valid { fmt.eprintln("M7 view playback regression failed"); os.exit(2) }
			fmt.println("M7 view: diagonal + defensive QTE completed; one pulse per response; timeline synchronized")
			if !run_m7_voxel_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 voxel smoke failed"); os.exit(2) }
			if !run_m7_resin_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M7 resin/dice smoke failed"); os.exit(2) }
			if !run_m7_rework_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 cards/enemies rework smoke failed"); os.exit(2) }
			if !run_m7_timed_pulse_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 timed pulse smoke failed"); os.exit(2) }
			if !run_m7_independent_world_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 independent world smoke failed"); os.exit(2) }
			if !run_m7_recovery_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 recovery smoke failed"); os.exit(2) }
			if !run_m7_polish_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 polish flow smoke failed"); os.exit(2) }
			if !run_m7_visual_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 visual feedback smoke failed"); os.exit(2) }
			if !run_m7_room_refresh_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 room refresh smoke failed"); os.exit(2) }
			if !run_m7_wall_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 wall visibility smoke failed"); os.exit(2) }
			if !run_m7_menu_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 menu smoke failed"); os.exit(2) }
			fmt.println("M7 UI: relic, reward, route, shop, rest, event, treasure and terminal screens captured")
			host.quit(hf)
			return
		}
	}
	if rs.smoke_test {
		rs.smoke_frame_count += 1
		if rs.smoke_frame_count >= 3 {
			if rs.spell_smoke != .None {
				switch rs.spell_smoke {
				case .Firebomb: rl.TakeScreenshot("odin_pp_firebomb_spell.png")
				case .Dice: rl.TakeScreenshot("odin_pp_dice.png")
				case .Dice_Pool: rl.TakeScreenshot("odin_pp_dice_pool.png")
				case .Chain: rl.TakeScreenshot("odin_pp_chain.png")
				case .Preview: rl.TakeScreenshot("odin_pp_spell_preview.png")
				case .Sunder_Preview: rl.TakeScreenshot("odin_pp_sunder_preview.png")
				case .Barrage: rl.TakeScreenshot("odin_pp_barrage.png")
				case .Venom: rl.TakeScreenshot("odin_pp_twin_venom.png")
				case .None:
				}
				if !spell_smoke_is_preview(rs.spell_smoke) && !finish_spell_smoke(&rs.room, &rs.iso_renderer) {
					fmt.eprintln("spell replay failed"); os.exit(2)
				}
			} else if rs.smoke_family != .Scattered {
				switch rs.smoke_family {
				case .Pillars: rl.TakeScreenshot("odin_pp_pillars.png")
				case .Ring: rl.TakeScreenshot("odin_pp_ring.png")
				case .Twin_Courts: rl.TakeScreenshot("odin_pp_courts.png")
				case .Asymmetric: rl.TakeScreenshot("odin_pp_cover.png")
				case .Scattered:
				}
			} else if rs.smoke_relics {
				rl.TakeScreenshot("odin_pp_relics.png")
			} else if rs.smoke_relic_combat {
				rl.TakeScreenshot("odin_pp_relic_combat.png")
			} else if rs.smoke_sprites {
				rl.TakeScreenshot("odin_pp_sprites.png")
			} else if rs.smoke_generation {
				rl.TakeScreenshot("odin_pp_procedural_room.png")
			} else if rs.smoke_map {
				rl.TakeScreenshot("odin_pp_route.png")
			} else if rs.smoke_status {
				rl.TakeScreenshot("odin_pp_status.png")
			} else if rs.smoke_loot {
				rl.TakeScreenshot("odin_pp_loot.png")
			} else if rs.smoke_card {
				rl.TakeScreenshot("odin_pp_card_drag.png")
			} else if rs.smoke_targeting {
				rl.TakeScreenshot("odin_pp_advanced_targeting.png")
			} else if rs.smoke_spatial {
				rl.TakeScreenshot("odin_pp_spatial_targeting.png")
			} else if rs.smoke_object {
				rl.TakeScreenshot("odin_pp_ice_block.png")
			} else if rs.smoke_fire {
				rl.TakeScreenshot("odin_pp_fire.png")
				timeline_finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
				assert(timeline_finished)
				assert(!render.renderer_timeline_is_busy(&rs.iso_renderer))
				assert(rs.iso_renderer.timeline.update_failures == 0)
				assert(game.entity_exists(&rs.room, rs.smoke_fire_entity))
				presentation_fire, fire_visible := render.presentation_grid_object(
					&rs.iso_renderer.timeline,
					rs.smoke_fire_entity,
				)
				assert(fire_visible && presentation_fire.visible &&
				       presentation_fire.kind == .Fire)
			} else if rs.smoke_content {
				rl.TakeScreenshot("odin_pp_content_pass.png")
			} else if rs.smoke_movement {
				rl.TakeScreenshot("odin_pp_enemy_movement.png")
			} else if rs.smoke_timeline {
				rl.TakeScreenshot("odin_pp_timeline.png")
			} else if rs.smoke_deck_flow {
				rl.TakeScreenshot("odin_pp_deck_flow.png")
			} else if rs.smoke_refocus {
				rl.TakeScreenshot("odin_pp_refocus.png")
			} else if rs.smoke_reward {
				rl.TakeScreenshot("odin_pp_reward.png")
			} else if rs.smoke_shop {
				rl.TakeScreenshot("odin_pp_shop.png")
			} else if rs.smoke_rest {
				rl.TakeScreenshot("odin_pp_rest.png")
			} else if rs.smoke_event {
				rl.TakeScreenshot("odin_pp_event.png")
			} else if rs.smoke_treasure {
				rl.TakeScreenshot("odin_pp_treasure.png")
			} else if rs.smoke_special_result {
				rl.TakeScreenshot("odin_pp_special_result.png")
			} else if rs.smoke_intents {
				rl.TakeScreenshot("odin_pp_enemy_intents.png")
			} else if rs.smoke_tactics {
				rl.TakeScreenshot("odin_pp_tactics.png")
			} else if rs.smoke_encounters {
				rl.TakeScreenshot("odin_pp_encounters.png")
			} else if rs.smoke_miniboss {
				rl.TakeScreenshot("odin_pp_miniboss.png")
			} else if rs.smoke_furnace {
				rl.TakeScreenshot("odin_pp_furnace.png")
				finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
				assert(finished && rs.iso_renderer.timeline.update_failures == 0)
			} else if rs.smoke_archetypes {
				rl.TakeScreenshot("odin_pp_enemy_archetypes.png")
			} else if rs.smoke_defeat {
				rl.TakeScreenshot("odin_pp_defeat.png")
			} else {
				rl.TakeScreenshot("odin_pp_isometric.png")
			}
			host.quit(hf)
			return
		}
	}

}
