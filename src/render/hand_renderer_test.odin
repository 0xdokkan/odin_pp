package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

@(test)
test_tactical_full_hand_is_readable_clickable_and_separate_from_grid :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540, tactical = {enabled = true}}
	for count in 1..=game.MAX_HAND_CARDS {
		deck := game.Deck_State{combat_active = true, hand_count = count}
		for index in 0..<count { deck.hand[index].id = u32(index+1) }
		previous_right: f32
		for index in 0..<count {
			bounds := hand_card_bounds(&renderer, index, count)
			testing.expect(t, bounds.x >= previous_right && bounds.x+bounds.width <= renderer.canvas_width)
			testing.expect(t, bounds.y > renderer.canvas_height-TACTICAL_HAND_HEIGHT && bounds.y+bounds.height <= renderer.canvas_height)
			previous_right = bounds.x+bounds.width
			for point in ([?]view.Vec2{{bounds.x+2, bounds.y+2}, {bounds.x+bounds.width-2, bounds.y+bounds.height-2}}) {
				actual, found := hand_card_at_point(&renderer, &deck, point, deck.hand[index].id)
				testing.expect(t, found && actual == index)
				testing.expect(t, !card_drop_area_contains(&renderer, point))
			}
		}
	}
	map_button := tactical_map_button_bounds(&renderer)
	testing.expect(t, !card_drop_area_contains(&renderer, {map_button.x+10, map_button.y+10}))
	testing.expect(t, card_drop_area_contains(&renderer, {480, 240}))
}

@(test)
test_overlapping_hand_headers_hit_the_visually_topmost_card :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540}
	deck := game.Deck_State{combat_active = true, hand_count = 5}
	for index in 0..<deck.hand_count {
		deck.hand[index].id = u32(index+1)
	}

	for index in 0..<deck.hand_count {
		bounds := hand_card_bounds(&renderer, index, deck.hand_count)
		point := view.Vec2{x = bounds.x+8, y = bounds.y+12}
		found_index, found := hand_card_at_point(&renderer, &deck, point)
		testing.expect(t, found)
		testing.expect_value(t, found_index, index)
	}
	raised := hand_raised_card_bounds(&renderer, 2, deck.hand_count)
	raised_point := view.Vec2{x = raised.x+raised.width*0.5, y = raised.y+raised.height*0.5}
	found_index, found := hand_card_at_point(&renderer, &deck, raised_point, deck.hand[2].id)
	testing.expect(t, found)
	testing.expect_value(t, found_index, 2)

	_, found = hand_card_at_point(&renderer, &deck, {x = 10, y = 10})
	testing.expect(t, !found)
}

@(test)
test_maximum_hand_layout_stays_inside_canvas_with_intentional_overlap :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540}
	previous_x: f32
	for index in 0..<game.MAX_HAND_CARDS {
		bounds := hand_card_bounds(&renderer, index, game.MAX_HAND_CARDS)
		testing.expect(t, bounds.x >= 0)
		testing.expect(t, bounds.y >= renderer.canvas_height-HAND_CARD_VISIBLE_HEIGHT)
		testing.expect(t, bounds.x+bounds.width <= renderer.canvas_width)
		testing.expect(t, bounds.y < renderer.canvas_height)
		if index > 0 {
			testing.expect(t, bounds.x > previous_x)
			testing.expect(t, bounds.x < previous_x+HAND_CARD_WIDTH)
		}
		previous_x = bounds.x
	}
	raised := hand_raised_card_bounds(&renderer, 0, game.MAX_HAND_CARDS)
	testing.expect(t, raised.x >= 0 && raised.x+raised.width <= renderer.canvas_width)
	testing.expect(t, raised.y >= 0 && raised.y+raised.height <= renderer.canvas_height)

	top_left := dragged_card_bounds(&renderer, {x = -100, y = -100})
	bottom_right := dragged_card_bounds(&renderer, {x = 2000, y = 2000})
	aim := view.Vec2{x = 480, y = 250}
	dragged := dragged_card_bounds(&renderer, aim)
	testing.expect(t, top_left.x >= 0 && top_left.y >= 0)
	testing.expect(t, bottom_right.x+bottom_right.width <= renderer.canvas_width)
	testing.expect(t, bottom_right.y+bottom_right.height <= renderer.canvas_height)
	testing.expect(t, point_in_rectangle(aim, dragged))
	testing.expect_value(t, dragged.x+dragged.width*0.5, aim.x)
	testing.expect_value(t, dragged.y+dragged.height*0.5, aim.y)
	testing.expect(t, card_drop_area_contains(&renderer, {x = 480, y = 300}))
	testing.expect(t, !card_drop_area_contains(&renderer, {x = 480, y = 500}))
	testing.expect(t, !dragged_card_is_over_grid(&renderer, aim))
	renderer.has_hovered_cell = true
	testing.expect(t, dragged_card_is_over_grid(&renderer, aim))
	testing.expect(t, !dragged_card_is_over_grid(&renderer, {x = 480, y = 500}))
}

@(test)
test_hand_input_uses_the_visible_deck_and_phase_while_timeline_is_busy :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	player.deck.combat_active = true
	player.deck.hand_count = 1
	player.deck.hand[0] = {id = 11, definition_id = .Guard}
	room := game.Room{player = &player, phase = .Combat}
	before := capture_room_presentation(&room)
	player.deck.hand[0] = {id = 22, definition_id = .Thorn_Coat}
	room.phase = .Loot
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	renderer: Renderer
	testing.expect(t, begin_renderer_event_timeline(&renderer, before, &events))

	visible_deck, visible_phase := renderer_hand_deck(&renderer, &room)

	testing.expect_value(t, visible_phase, game.Room_Phase.Combat)
	testing.expect_value(t, visible_deck.hand[0].id, u32(11))
	testing.expect_value(t, room.player.deck.hand[0].id, u32(22))
}

@(test)
test_m4_card_labels_and_timeline_verbs_cover_new_zone_feedback :: proc(t: ^testing.T) {
	cards := [?]game.Card_Instance{
		{definition_id = .Battle_Focus},
		{definition_id = .Calculated_Risk},
		{definition_id = .Spark_Forge},
		{definition_id = .Spark, upgrade_level = 2, lifetime = .Combat},
	}
	expected_short_names := [?]string{"FOCUS", "RISK", "FORGE", "SPARK"}
	expected_first_lines := [?]string{"DRAW 2", "DRAW 2", "CREATE 1 SPARK", "DEAL 4 DAMAGE"}
	expected_second_lines := [?]string{"EXHAUST", "DISCARD 1", "TEMPORARY", "TEMP - RANGE 1-2"}
	for card, index in cards {
		first, second := card_detail_lines(card)
		testing.expect_value(t, string(card_short_name(card.definition_id)), expected_short_names[index])
		testing.expect_value(t, string(first), expected_first_lines[index])
		testing.expect_value(t, string(second), expected_second_lines[index])
	}

	cues := [?]Presentation_Cue{
		{kind = .Card_Played},
		{kind = .Card_Drawn},
		{kind = .Card_Moved, event = {to_card_zone = .Discard}},
		{kind = .Card_Moved, event = {to_card_zone = .Exhaust}},
		{kind = .Card_Created},
		{kind = .Card_Refocused, event = {to_card_zone = .Hand}},
		{kind = .Card_Refocused, event = {to_card_zone = .Exhaust}},
		{kind = .Card_Refocused, event = {to_card_zone = .Discard}},
	}
	expected_verbs := [?]string{
		"PLAY",
		"DRAW",
		"DISCARD",
		"EXHAUST",
		"CREATE",
		"RETAIN",
		"ETHEREAL",
		"DISCARD",
	}
	for &cue, index in cues {
		testing.expect_value(t, string(timeline_card_cue_verb(&cue)), expected_verbs[index])
	}
	invalid := Presentation_Cue{kind = .Card_Moved, event = {to_card_zone = .Resolving}}
	testing.expect(t, timeline_card_cue_verb(&invalid) == nil)
	invalid = {kind = .Card_Refocused, event = {to_card_zone = .Draw}}
	testing.expect(t, timeline_card_cue_verb(&invalid) == nil)
}

@(test)
test_refocus_button_hitbox_stays_in_the_status_panel_and_out_of_the_card_drop_area :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540}
	bounds := refocus_button_bounds(&renderer)
	testing.expect(t, bounds.x >= 14 && bounds.x+bounds.width <= 14+460)
	testing.expect(t, bounds.y >= 14 && bounds.y+bounds.height <= 14+84)
	center := view.Vec2{x = bounds.x+bounds.width*0.5, y = bounds.y+bounds.height*0.5}
	testing.expect(t, refocus_button_at_point(&renderer, center))
	testing.expect(t, !refocus_button_at_point(&renderer, {x = bounds.x-1, y = center.y}))
	testing.expect(t, !card_drop_area_contains(&renderer, center))
	testing.expect(t, refocus_button_is_enabled(&renderer))

	renderer.timeline.count = 1
	renderer.timeline.head = 0
	testing.expect(t, renderer_timeline_is_busy(&renderer))
	testing.expect(t, !refocus_button_is_enabled(&renderer))
	marker := view.Vec2{x = 480, y = 300}
	testing.expect(t, card_drop_area_contains(&renderer, marker))
}

@(test)
test_card_keyword_tags_cover_refocus_and_lifetime_without_overlap :: proc(t: ^testing.T) {
	counter, counter_found := game.card_definition_by_id(.Counter_Rune)
	focus, focus_found := game.card_definition_by_id(.Battle_Focus)
	spark, spark_found := game.card_definition_by_id(.Spark)
	testing.expect(t, counter_found && focus_found && spark_found)

	tags, count := card_keyword_tags({definition_id = .Counter_Rune}, counter)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, tags[0], Card_Keyword_Tag.Retain)
	testing.expect_value(t, string(card_keyword_tag_label(tags[0], false)), "RET")
	testing.expect_value(t, string(card_keyword_tag_label(tags[0], true)), "RETAIN")

	tags, count = card_keyword_tags({definition_id = .Battle_Focus}, focus)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, tags[0], Card_Keyword_Tag.Ethereal)
	testing.expect_value(t, string(card_keyword_tag_label(tags[0], false)), "ETH")
	testing.expect_value(t, string(card_keyword_tag_label(tags[0], true)), "ETHEREAL")

	tags, count = card_keyword_tags({definition_id = .Spark, lifetime = .Combat}, spark)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, tags[0], Card_Keyword_Tag.Temporary)

	tags, count = card_keyword_tags({definition_id = .Battle_Focus, lifetime = .Combat}, focus)
	testing.expect_value(t, count, 2)
	bounds := rl.Rectangle{x = 100, y = 200, width = HAND_CARD_WIDTH, height = HAND_CARD_HEIGHT}
	previous_bottom := bounds.y
	for index in 0..<count {
		tag_bounds := card_keyword_tag_bounds(bounds, index, false)
		testing.expect(t, tag_bounds.x >= bounds.x && tag_bounds.x+tag_bounds.width <= bounds.x+bounds.width)
		testing.expect(t, tag_bounds.y >= previous_bottom)
		testing.expect(t, tag_bounds.y+tag_bounds.height <= bounds.y+HAND_CARD_VISIBLE_HEIGHT)
		previous_bottom = tag_bounds.y+tag_bounds.height
	}
	expanded := card_keyword_tag_bounds(bounds, 0, true)
	testing.expect(t, expanded.x >= bounds.x && expanded.x+expanded.width <= bounds.x+bounds.width)
	testing.expect(t, expanded.width > card_keyword_tag_bounds(bounds, 0, false).width)
}
