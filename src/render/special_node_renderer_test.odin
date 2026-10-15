package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

SPECIAL_NODE_RENDER_TEST_PLAYER_STATS :: game.Player_Stats{
	max_health = 20,
	attack = 2,
	defense = 1,
}

SPECIAL_NODE_RENDER_TEST_RUN_CONFIG :: game.Run_Map_Config{
	layer_count = 5,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

create_special_node_render_test_run :: proc(
	t: ^testing.T,
	kind: game.Node_Kind,
	event_kind: game.Route_Event_Kind = .Count,
) -> game.Run_State {
	for seed in u64(1)..<u64(1024) {
		run, ok := game.create_run(
			SPECIAL_NODE_RENDER_TEST_PLAYER_STATS,
			SPECIAL_NODE_RENDER_TEST_RUN_CONFIG,
			seed,
		)
		if !ok {
			continue
		}
		current, current_found := game.current_run_node(&run)
		target := game.INVALID_NODE_ID
		if current_found {
			for index in 0..<current.outgoing_count {
				candidate_id := current.outgoing[index]
				candidate, candidate_found := game.node_at(&run, candidate_id)
				if candidate_found && candidate.kind == kind {
					target = candidate_id
					break
				}
			}
		}
		if target == game.INVALID_NODE_ID {
			game.destroy_run(&run)
			continue
		}

		transition := game.finish_room(&run, .Complete)
		testing.expect_value(t, transition, game.Run_Transition.Reward)
		if transition != .Reward {
			game.destroy_run(&run)
			return {}
		}
		reward_result := game.skip_card_reward(&run)
		testing.expect_value(t, reward_result, game.Card_Reward_Result.Skipped)
		if reward_result != .Skipped {
			game.destroy_run(&run)
			return {}
		}
		entry := game.enter_node(&run, target)
		expected_entry := game.Node_Entry_Result.Invalid
		switch kind {
		case .Rest:
			expected_entry = .Rest
		case .Event:
			expected_entry = .Event
		case .Treasure:
			expected_entry = .Treasure
		case .Combat, .Elite, .Boss, .Shop, .Count:
		}
		testing.expect_value(t, entry, expected_entry)
		testing.expect(t, game.validate_special_node_state(&run))
		if kind == .Event && event_kind != .Count && run.route_event.kind != event_kind {
			game.destroy_run(&run)
			continue
		}
		return run
	}
	testing.expect(t, false)
	return {}
}

@(test)
test_blood_offering_primary_is_disabled_when_gold_would_overflow :: proc(t: ^testing.T) {
	run := create_special_node_render_test_run(t, .Event, .Blood_Offering)
	defer game.destroy_run(&run)
	run.player.gold = max(i32)
	testing.expect(t, game.validate_special_node_state(&run))
	testing.expect(t, !special_node_primary_is_enabled(&run))
	primary := special_node_action_bounds(960, 540, 0, 3)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, rectangle_center(primary)).kind,
		Special_Node_Hit_Kind.None,
	)
	testing.expect_value(
		t,
		game.resolve_route_event(&run, .Primary),
		game.Special_Node_Result.Overflow,
	)
}

@(test)
test_special_node_action_and_result_geometry_is_disjoint :: proc(t: ^testing.T) {
	for action_count in 2..=3 {
		actions: [3]rl.Rectangle
		for index in 0..<action_count {
			actions[index] = special_node_action_bounds(960, 540, index, action_count)
			bounds := actions[index]
			testing.expect(t, bounds.x >= 0 && bounds.y >= SPECIAL_NODE_HEADER_HEIGHT)
			testing.expect(t, bounds.x+bounds.width <= 960)
			testing.expect(t, bounds.y+bounds.height <= 540)
			for previous in 0..<index {
				testing.expect(t, !rectangles_overlap(bounds, actions[previous]))
			}
		}
	}

	result := special_node_result_bounds(960, 540)
	continue_bounds := special_node_continue_bounds(960, 540)
	testing.expect(t, result.x >= 0 && result.y >= SPECIAL_NODE_HEADER_HEIGHT)
	testing.expect(t, result.x+result.width <= 960 && result.y+result.height <= 540)
	testing.expect(t, continue_bounds.x >= 0 && continue_bounds.y >= 0)
	testing.expect(t, continue_bounds.x+continue_bounds.width <= 960)
	testing.expect(t, continue_bounds.y+continue_bounds.height <= 540)
	testing.expect(t, !rectangles_overlap(result, continue_bounds))

	for slot in 0..<SHOP_DECK_CARDS_PER_PAGE {
		card := special_node_owned_card_bounds(960, 540, slot)
		testing.expect(t, card.x >= 0 && card.x+card.width <= 960)
		testing.expect(t, card.y > SPECIAL_NODE_ACTION_TOP+SPECIAL_NODE_ACTION_HEIGHT)
		testing.expect(t, card.y+card.height < special_node_previous_page_bounds(960, 540).y)
	}
}

@(test)
test_special_node_geometry_and_hit_tests_reject_invalid_inputs :: proc(t: ^testing.T) {
	testing.expect(t, !special_node_canvas_is_supported(899, 540))
	testing.expect(t, !special_node_canvas_is_supported(960, 519))
	testing.expect(t, special_node_canvas_is_supported(960, 540))
	testing.expect(t, special_node_action_bounds(899, 540, 0, 2) == rl.Rectangle{})
	testing.expect(t, special_node_action_bounds(960, 519, 0, 2) == rl.Rectangle{})
	testing.expect(t, special_node_action_bounds(960, 540, -1, 2) == rl.Rectangle{})
	testing.expect(t, special_node_action_bounds(960, 540, 2, 2) == rl.Rectangle{})
	testing.expect(t, special_node_action_bounds(960, 540, 0, 4) == rl.Rectangle{})
	testing.expect(t, special_node_result_bounds(899, 540) == rl.Rectangle{})
	testing.expect(t, special_node_continue_bounds(960, 519) == rl.Rectangle{})
	testing.expect(t, special_node_previous_page_bounds(899, 540) == rl.Rectangle{})
	testing.expect(t, special_node_next_page_bounds(960, 519) == rl.Rectangle{})
	testing.expect(t, special_node_owned_card_bounds(899, 540, 0) == rl.Rectangle{})
	testing.expect(t, special_node_hit_test(nil, 960, 540, 0, {}).kind == .None)

	run, ok := game.create_run(
		SPECIAL_NODE_RENDER_TEST_PLAYER_STATS,
		SPECIAL_NODE_RENDER_TEST_RUN_CONFIG,
		42,
	)
	testing.expect(t, ok)
	defer game.destroy_run(&run)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, {x = 480, y = 180}).kind,
		Special_Node_Hit_Kind.None,
	)
}

@(test)
test_rest_deck_adapter_preserves_page_and_hover_selection :: proc(t: ^testing.T) {
	run := create_special_node_render_test_run(t, .Rest)
	defer game.destroy_run(&run)
	deck := &run.player.deck
	page_count := special_node_deck_page_count(deck)
	testing.expect_value(
		t,
		page_count,
		(deck.owned_count+SHOP_DECK_CARDS_PER_PAGE-1)/SHOP_DECK_CARDS_PER_PAGE,
	)
	testing.expect_value(t, special_node_clamp_deck_page(deck, -3), 0)
	testing.expect_value(t, special_node_clamp_deck_page(deck, page_count+2), page_count-1)

	// Exhaustive deck geometry/picking lives with the shared Shop row. Here
	// verify Rest routes both ends of its deck through that row unchanged.
	for page in ([2]int{0, page_count-1}) {
		start, valid := special_node_deck_page_start(deck, page)
		testing.expect(t, valid)
		visible_count := special_node_deck_cards_on_page(deck, page)
		testing.expect(t, visible_count > 0 && visible_count <= SHOP_DECK_CARDS_PER_PAGE)
		slot := visible_count-1
		bounds := special_node_owned_card_bounds(960, 540, slot)
		hit := special_node_hit_test(
			&run,
			960,
			540,
			page,
			rectangle_center(bounds),
		)
		testing.expect_value(t, hit.kind, Special_Node_Hit_Kind.Owned_Card)
		testing.expect_value(t, hit.card_id, deck.owned[start+slot].id)
	}

	raised_card_id := deck.owned[1].id
	raised := special_node_owned_card_bounds(960, 540, 1, true)
	raised_only_point := view.Vec2{x = raised.x+raised.width*0.5, y = raised.y+2}
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, raised_only_point).kind,
		Special_Node_Hit_Kind.None,
	)
	raised_hit := special_node_hit_test(
		&run,
		960,
		540,
		0,
		raised_only_point,
		raised_card_id,
	)
	testing.expect_value(t, raised_hit.kind, Special_Node_Hit_Kind.Owned_Card)
	testing.expect_value(t, raised_hit.card_id, raised_card_id)
}

@(test)
test_rest_hit_test_exposes_selection_actions_and_page_controls :: proc(t: ^testing.T) {
	run := create_special_node_render_test_run(t, .Rest)
	defer game.destroy_run(&run)
	deck := &run.player.deck
	selected_card_id := deck.owned[0].id

	primary := special_node_action_bounds(960, 540, 0, 3)
	secondary := special_node_action_bounds(960, 540, 1, 3)
	leave := special_node_action_bounds(960, 540, 2, 3)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, rectangle_center(primary)).kind,
		Special_Node_Hit_Kind.Primary,
	)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, rectangle_center(secondary)).kind,
		Special_Node_Hit_Kind.None,
	)
	testing.expect_value(
		t,
		special_node_hit_test(
			&run,
			960,
			540,
			0,
			rectangle_center(secondary),
			0,
			selected_card_id,
		).kind,
		Special_Node_Hit_Kind.Secondary,
	)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, rectangle_center(leave)).kind,
		Special_Node_Hit_Kind.Leave,
	)

	previous := rectangle_center(special_node_previous_page_bounds(960, 540))
	next := rectangle_center(special_node_next_page_bounds(960, 540))
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, previous).kind,
		Special_Node_Hit_Kind.None,
	)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, next).kind,
		Special_Node_Hit_Kind.Next_Page,
	)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 1, previous).kind,
		Special_Node_Hit_Kind.Previous_Page,
	)
}

@(test)
test_resolved_rest_exposes_only_continue :: proc(t: ^testing.T) {
	run := create_special_node_render_test_run(t, .Rest)
	defer game.destroy_run(&run)
	result := game.use_rest_recovery(&run)
	testing.expect_value(t, result, game.Special_Node_Result.Recovered)
	testing.expect(t, special_node_is_resolved(&run))
	testing.expect_value(t, special_node_action_count(&run), 0)

	old_action := special_node_action_bounds(960, 540, 0, 3)
	testing.expect_value(
		t,
		special_node_hit_test(&run, 960, 540, 0, rectangle_center(old_action)).kind,
		Special_Node_Hit_Kind.None,
	)
	testing.expect_value(
		t,
		special_node_hit_test(
			&run,
			960,
			540,
			0,
			rectangle_center(special_node_owned_card_bounds(960, 540, 0)),
		).kind,
		Special_Node_Hit_Kind.None,
	)
	testing.expect_value(
		t,
		special_node_hit_test(
			&run,
			960,
			540,
			0,
			rectangle_center(special_node_continue_bounds(960, 540)),
		).kind,
		Special_Node_Hit_Kind.Continue,
	)
}

@(test)
test_event_and_treasure_actions_switch_to_continue_after_resolution :: proc(t: ^testing.T) {
	event_run := create_special_node_render_test_run(t, .Event)
	defer game.destroy_run(&event_run)
	testing.expect_value(t, special_node_action_count(&event_run), 3)
	expected_kinds := [?]Special_Node_Hit_Kind{
		.Primary,
		.Secondary,
		.Leave,
	}
	for expected, index in expected_kinds {
		hit := special_node_hit_test(
			&event_run,
			960,
			540,
			0,
			rectangle_center(special_node_action_bounds(960, 540, index, 3)),
		)
		testing.expect_value(t, hit.kind, expected)
	}
	resolution := game.resolve_route_event(&event_run, .Secondary)
	testing.expect_value(t, resolution, game.Special_Node_Result.Event_Resolved)
	testing.expect_value(
		t,
		special_node_hit_test(
			&event_run,
			960,
			540,
			0,
			rectangle_center(special_node_continue_bounds(960, 540)),
		).kind,
		Special_Node_Hit_Kind.Continue,
	)

	treasure_run := create_special_node_render_test_run(t, .Treasure)
	defer game.destroy_run(&treasure_run)
	testing.expect_value(t, special_node_action_count(&treasure_run), 2)
	testing.expect_value(
		t,
		special_node_hit_test(
			&treasure_run,
			960,
			540,
			0,
			rectangle_center(special_node_action_bounds(960, 540, 0, 2)),
		).kind,
		Special_Node_Hit_Kind.Primary,
	)
	testing.expect_value(
		t,
		special_node_hit_test(
			&treasure_run,
			960,
			540,
			0,
			rectangle_center(special_node_action_bounds(960, 540, 1, 2)),
		).kind,
		Special_Node_Hit_Kind.Leave,
	)
	claim := game.claim_treasure(&treasure_run)
	testing.expect_value(t, claim, game.Special_Node_Result.Treasure_Claimed)
	testing.expect_value(
		t,
		special_node_hit_test(
			&treasure_run,
			960,
			540,
			0,
			rectangle_center(special_node_continue_bounds(960, 540)),
		).kind,
		Special_Node_Hit_Kind.Continue,
	)
}
