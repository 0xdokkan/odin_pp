package render

import "core:testing"
import game "../game"
import view "../engine/view"

@(test)
test_tactical_full_hand_is_readable_clickable_and_separate_from_grid :: proc(t: ^testing.T) {
	renderer := new_clone(Renderer{canvas_width = 960, canvas_height = 540})
	defer free(renderer)
	for count in 1..=game.MAX_HAND_CARDS {
		deck := game.Deck_State{combat_active = true, hand_count = count}
		for index in 0..<count { deck.hand[index].id = u32(index+1) }
		previous_right: f32
		for index in 0..<count {
			bounds := hand_card_bounds(renderer, index, count)
			testing.expect(t, bounds.x >= previous_right && bounds.x+bounds.width <= renderer.canvas_width)
			testing.expect(t, bounds.y > renderer.canvas_height-TACTICAL_HAND_HEIGHT && bounds.y+bounds.height <= renderer.canvas_height)
			previous_right = bounds.x+bounds.width
			for point in ([?]view.Vec2{{bounds.x+2, bounds.y+2}, {bounds.x+bounds.width-2, bounds.y+bounds.height-2}}) {
				actual, found := hand_card_at_point(renderer, &deck, point, deck.hand[index].id)
				testing.expect(t, found && actual == index)
				testing.expect(t, !card_drop_area_contains(renderer, point))
			}
		}
	}
	map_button := tactical_map_button_bounds(renderer)
	testing.expect(t, !card_drop_area_contains(renderer, {map_button.x+10, map_button.y+10}))
	testing.expect(t, card_drop_area_contains(renderer, {480, 240}))
}

// The game's hand never rises nor overlaps. PROVA MECCANICHE's ten cards keep
// a full eight-card hand's width and overlap across the canvas but for its
// gutters, each showing most of itself, evenly until the board has measured
// what each one's words need, then as much as each needs and the spare width
// shared out; the pointer finds the one on top; the card under it rises
// whole, over the rest, and keeps the pointer from where it rested to where it
// rose.
@(test)
test_tactical_hand_of_ten_overlaps_at_a_full_hands_width :: proc(t: ^testing.T) {
	renderer := new_clone(Renderer{canvas_width = 960, canvas_height = 540})
	defer free(renderer)
	full := game.MAX_HAND_CARDS
	first := tactical_hand_card_bounds(renderer, 0, full)
	last := tactical_hand_card_bounds(renderer, full-1, full)
	for count in 1..=full {
		testing.expect(t, !tactical_hand_overlaps(count))
		for index in 0..<count {
			bounds := tactical_hand_card_bounds(renderer, index, count)
			testing.expect_value(t, tactical_hand_raised_card_bounds(renderer, index, count), bounds)
			testing.expect_value(t, hand_raised_card_bounds(renderer, index, count), bounds)
			testing.expect_value(t, tactical_hand_card_visible_width(renderer, index, count), bounds.width)
		}
	}
	count := game.MAX_HAND_CAPACITY
	testing.expect(t, tactical_hand_overlaps(count))
	deck := game.Deck_State{combat_active = true, hand_count = count}
	for index in 0..<count { deck.hand[index].id = u32(index+1) }
	for index in 0..<count {
		bounds := tactical_hand_card_bounds(renderer, index, count)
		shown := tactical_hand_card_visible_width(renderer, index, count)
		testing.expect(t, bounds.width == first.width && bounds.height == first.height && bounds.y == first.y)
		testing.expect(t, shown >= bounds.width*0.8 && (shown < bounds.width) == (index < count-1))
		// Resting, the card shows where the next one does not cover it.
		found_index, found := hand_card_at_point(renderer, &deck, {bounds.x+shown*0.5, bounds.y+bounds.height*0.5})
		testing.expect(t, found && found_index == index)
		// Raised, it rises whole over the others, inside the canvas.
		raised := tactical_hand_raised_card_bounds(renderer, index, count)
		testing.expect(t, raised.y == bounds.y-TACTICAL_HAND_RAISE && raised.x == bounds.x && raised.width == bounds.width)
		testing.expect(t, raised.x >= 0 && raised.x+raised.width <= renderer.canvas_width && raised.y+raised.height <= renderer.canvas_height)
		for point in ([3]view.Vec2{{raised.x+raised.width-3, raised.y+2}, {bounds.x+bounds.width-3, bounds.y+bounds.height-2},
			{bounds.x+3, bounds.y+bounds.height-2}}) {
			found_index, found = hand_card_at_point(renderer, &deck, point, deck.hand[index].id)
			testing.expect(t, found && found_index == index)
		}
	}
	testing.expect_value(t, tactical_hand_card_bounds(renderer, 0, count).x, TACTICAL_HAND_OVERLAP_GUTTER)
	right := tactical_hand_card_bounds(renderer, count-1, count)
	testing.expect_value(t, right.x+right.width, renderer.canvas_width-TACTICAL_HAND_OVERLAP_GUTTER)
	testing.expect(t, first.x > TACTICAL_HAND_OVERLAP_GUTTER && last.x+last.width < renderer.canvas_width-TACTICAL_HAND_OVERLAP_GUTTER)
	// Measured: each card as far on as the ones before it show.
	renderer.tactical.hand_reveal = {shown = {90, 100, 86, 95, 92, 88, 97, 86, 91, first.width}, count = count}
	x := TACTICAL_HAND_OVERLAP_GUTTER
	for index in 0..<count {
		bounds := tactical_hand_card_bounds(renderer, index, count)
		testing.expect(t, abs(bounds.x-x) < 1e-3 && bounds.width == first.width)
		testing.expect(t, abs(tactical_hand_card_visible_width(renderer, index, count)-renderer.tactical.hand_reveal.shown[index]) < 1e-3)
		x += renderer.tactical.hand_reveal.shown[index]
	}
	// For another hand than it was measured for: evenly again.
	renderer.tactical.hand_reveal.count = count-1
	testing.expect(t, abs(tactical_hand_card_visible_width(renderer, 0, count)-tactical_hand_card_visible_width(renderer, 4, count)) < 1e-3)
	// Measured from the hand (here with no font: every card needs its icon
	// only), the spare width shared out: the last card where the hand ends;
	// the game's hand is never measured.
	for &card in deck.hand[:count] { card.definition_id = .Strike }
	update_tactical_hand_reveal(renderer, &deck)
	testing.expect_value(t, renderer.tactical.hand_reveal.count, count)
	for shown in renderer.tactical.hand_reveal.shown[:count-1] { testing.expect(t, shown >= TACTICAL_HAND_REVEAL_ICON) }
	right = tactical_hand_card_bounds(renderer, count-1, count)
	testing.expect(t, abs(right.x+right.width-(renderer.canvas_width-TACTICAL_HAND_OVERLAP_GUTTER)) < 1e-3)
	eight := deck
	eight.hand_count = full
	update_tactical_hand_reveal(renderer, &eight)
	testing.expect_value(t, renderer.tactical.hand_reveal.count, 0)
	// The card that rises: the one under the mouse, the one aimed, the one
	// chosen; never one in the game's hand.
	testing.expect_value(t, tactical_hand_raised_card(&deck, 3, 5, 7), u32(3))
	testing.expect_value(t, tactical_hand_raised_card(&deck, 0, 5, 7), u32(7))
	testing.expect_value(t, tactical_hand_raised_card(&deck, 0, 5, 0), u32(5))
	testing.expect_value(t, tactical_hand_raised_card(&deck, 0, 0, 0), u32(0))
	testing.expect_value(t, tactical_hand_raised_card(&deck, 99, 0, 0), u32(0))
	game_hand := deck
	game_hand.hand_count = full
	testing.expect_value(t, tactical_hand_raised_card(&game_hand, 3, 5, 7), u32(0))
	// Its keys: 1 to 9, then 0.
	testing.expect_value(t, string(tactical_hand_slot_key(0)), "1")
	testing.expect_value(t, string(tactical_hand_slot_key(8)), "9")
	testing.expect_value(t, string(tactical_hand_slot_key(9)), "0")
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
	renderer := new(Renderer)
	defer free(renderer)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &events))

	visible_deck, visible_phase := renderer_hand_deck(renderer, &room)

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
	for card, index in cards {
		testing.expect_value(t, string(card_short_name(card.definition_id)), expected_short_names[index])
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
test_refocus_button_hitbox_stays_in_the_hud_and_out_of_the_card_drop_area :: proc(t: ^testing.T) {
	renderer := new_clone(Renderer{canvas_width = 960, canvas_height = 540})
	defer free(renderer)
	renderer.tactical.refocus_enabled = true
	bounds := refocus_button_bounds(renderer)
	testing.expect(t, bounds.x >= 0 && bounds.x+bounds.width <= renderer.canvas_width)
	testing.expect(t, bounds.y >= 0 && bounds.y+bounds.height <= TACTICAL_HUD_HEIGHT)
	center := view.Vec2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
	testing.expect(t, refocus_button_at_point(renderer, center))
	testing.expect(t, !refocus_button_at_point(renderer, {bounds.x-1, center.y}))
	testing.expect(t, !card_drop_area_contains(renderer, center))
	testing.expect(t, refocus_button_is_enabled(renderer))

	renderer.timeline.count = 1
	renderer.timeline.head = 0
	testing.expect(t, renderer_timeline_is_busy(renderer))
	testing.expect(t, !refocus_button_is_enabled(renderer))
	marker := view.Vec2{480, 300}
	testing.expect(t, card_drop_area_contains(renderer, marker))
}

@(test)
test_card_keyword_tags_cover_refocus_and_lifetime :: proc(t: ^testing.T) {
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
	testing.expect_value(t, tags[0], Card_Keyword_Tag.Ethereal)
	testing.expect_value(t, tags[1], Card_Keyword_Tag.Temporary)
}
