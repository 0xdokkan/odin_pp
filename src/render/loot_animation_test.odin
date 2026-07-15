package render

import "core:testing"
import game "../game"
import grid "../grid"

@(test)
test_loot_events_create_and_expire_presentational_animations :: proc(t: ^testing.T) {
	renderer: Renderer
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Damaged,
		amount = 2,
	})
	game.record_event(&events, {
		kind = .Loot_Collected,
		target = game.PLAYER_ENTITY,
		amount = 3,
		loot_kind = .Gold,
		from_position = {x = 4, y = 2},
		to_position = {x = 1, y = 1},
	})

	enqueue_event_animations(&renderer, &events)

	testing.expect_value(t, renderer.loot_animation_count, 1)
	animation := renderer.loot_animations[0]
	testing.expect_value(t, animation.kind, game.Loot_Kind.Gold)
	testing.expect_value(t, animation.amount, i32(3))
	testing.expect_value(t, animation.from_position, grid.Position{x = 4, y = 2})
	testing.expect_value(t, animation.to_position, grid.Position{x = 1, y = 1})
	testing.expect_value(t, animation.target, game.PLAYER_ENTITY)

	update_loot_animations(&renderer, LOOT_ANIMATION_DURATION*0.5)
	testing.expect_value(t, renderer.loot_animation_count, 1)
	update_loot_animations(&renderer, LOOT_ANIMATION_DURATION*0.5)
	testing.expect_value(t, renderer.loot_animation_count, 0)
}

@(test)
test_loot_animation_queue_has_a_fixed_capacity :: proc(t: ^testing.T) {
	renderer: Renderer
	events: game.Event_Log
	for index in 0..<MAX_LOOT_ANIMATIONS+1 {
		game.record_event(&events, {
			kind = .Loot_Collected,
			amount = i32(index+1),
		})
	}

	enqueue_event_animations(&renderer, &events)

	testing.expect_value(t, renderer.loot_animation_count, MAX_LOOT_ANIMATIONS)
	testing.expect_value(t, renderer.loot_animations_dropped, 1)
}
