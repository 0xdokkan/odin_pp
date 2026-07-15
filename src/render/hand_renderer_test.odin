package render

import "core:testing"
import game "../game"
import view "../view"

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
	testing.expect(t, !point_in_rectangle(aim, dragged))
	testing.expect(t, card_drop_area_contains(&renderer, {x = 480, y = 300}))
	testing.expect(t, !card_drop_area_contains(&renderer, {x = 480, y = 500}))
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
