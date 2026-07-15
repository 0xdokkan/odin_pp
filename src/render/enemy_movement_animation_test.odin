package render

import "core:testing"
import game "../game"
import view "../view"

enemy_animation_values_are_close :: proc(a, b: f32, epsilon: f32 = 0.001) -> bool {
	return abs(a-b) <= epsilon
}

expect_enemy_animation_position :: proc(t: ^testing.T, actual, expected: view.Vec2) {
	testing.expectf(
		t,
		enemy_animation_values_are_close(actual.x, expected.x),
		"x: expected %v, got %v",
		expected.x,
		actual.x,
	)
	testing.expectf(
		t,
		enemy_animation_values_are_close(actual.y, expected.y),
		"y: expected %v, got %v",
		expected.y,
		actual.y,
	)
}

@(test)
test_enemy_move_events_create_interpolate_and_expire_animation :: proc(t: ^testing.T) {
	renderer: Renderer
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	enemy := game.enemy_entity(7)
	game.record_event(&events, {
		kind = .Moved,
		target = enemy,
		from_position = {x = 5, y = 2},
		to_position = {x = 4, y = 2},
	})

	enqueue_event_animations(&renderer, &events)

	testing.expect_value(t, renderer.enemy_move_animation_count, 1)
	animation := &renderer.enemy_move_animations[0]
	testing.expect_value(t, animation.target, enemy)
	expect_enemy_animation_position(t, animation.from_grid, {x = 5, y = 2})
	expect_enemy_animation_position(t, animation.to_grid, {x = 4, y = 2})
	expect_enemy_animation_position(t, enemy_move_animation_grid_position(animation), {x = 5, y = 2})

	update_enemy_move_animations(&renderer, ENEMY_MOVE_ANIMATION_DURATION*0.5)
	testing.expect_value(t, renderer.enemy_move_animation_count, 1)
	expect_enemy_animation_position(
		t,
		enemy_move_animation_grid_position(&renderer.enemy_move_animations[0]),
		{x = 4.5, y = 2},
	)
	update_enemy_move_animations(&renderer, ENEMY_MOVE_ANIMATION_DURATION*0.5)
	testing.expect_value(t, renderer.enemy_move_animation_count, 0)
}

@(test)
test_retargeting_enemy_move_starts_from_current_visual_position :: proc(t: ^testing.T) {
	renderer: Renderer
	enemy := game.enemy_entity(3)
	first := game.Game_Event{
		kind = .Moved,
		target = enemy,
		from_position = {x = 5, y = 1},
		to_position = {x = 4, y = 1},
	}
	enqueue_enemy_move_animation(&renderer, first)
	update_enemy_move_animations(&renderer, ENEMY_MOVE_ANIMATION_DURATION*0.25)
	current := enemy_move_animation_grid_position(&renderer.enemy_move_animations[0])

	enqueue_enemy_move_animation(&renderer, {
		kind = .Moved,
		target = enemy,
		from_position = {x = 4, y = 1},
		to_position = {x = 3, y = 1},
	})

	testing.expect_value(t, renderer.enemy_move_animation_count, 1)
	animation := &renderer.enemy_move_animations[0]
	expect_enemy_animation_position(t, animation.from_grid, current)
	expect_enemy_animation_position(t, animation.to_grid, {x = 3, y = 1})
	testing.expect_value(t, animation.elapsed, f32(0))
}

@(test)
test_enemy_move_animation_storage_has_fixed_capacity_and_can_be_cleared :: proc(t: ^testing.T) {
	renderer: Renderer
	events: game.Event_Log
	for index in 0..<MAX_ENEMY_MOVE_ANIMATIONS+1 {
		game.record_event(&events, {
			kind = .Moved,
			target = game.enemy_entity(u32(index+1)),
			from_position = {x = index+1, y = 1},
			to_position = {x = index, y = 1},
		})
	}

	enqueue_event_animations(&renderer, &events)
	testing.expect_value(t, renderer.enemy_move_animation_count, MAX_ENEMY_MOVE_ANIMATIONS)
	testing.expect_value(t, renderer.enemy_move_animations_dropped, 1)

	clear_event_animations(&renderer)
	testing.expect_value(t, renderer.enemy_move_animation_count, 0)
	testing.expect_value(t, renderer.enemy_move_animations_dropped, 0)
}
