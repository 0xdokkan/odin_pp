package render

import "core:testing"
import game "../game"
import view "../engine/view"

create_reward_render_test_run :: proc(t: ^testing.T) -> game.Run_State {
	run, ok := game.create_run(RENDER_TEST_PLAYER_STATS, RENDER_TEST_RUN_CONFIG, 991)
	testing.expect(t, ok)
	transition := game.finish_room(&run, .Complete)
	testing.expect_value(t, transition, game.Run_Transition.Reward)
	return run
}

@(test)
test_reward_cards_are_centered_non_overlapping_and_hittable :: proc(t: ^testing.T) {
	run := create_reward_render_test_run(t)
	defer game.destroy_run(&run)
	choices := game.available_card_rewards(&run)
	previous_right: f32
	for index in 0..<len(choices) {
		bounds := reward_card_bounds(960, 540, index, len(choices))
		testing.expect(t, bounds.x >= 0 && bounds.y >= 0)
		testing.expect(t, bounds.x+bounds.width <= 960)
		testing.expect(t, bounds.y+bounds.height <= 540)
		if index > 0 {
			testing.expect(t, bounds.x > previous_right)
		}
		previous_right = bounds.x+bounds.width
		point := view.Vec2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
		found_index, found := reward_card_at_point(&run, 960, 540, point)
		testing.expect(t, found)
		testing.expect_value(t, found_index, index)
	}
}

@(test)
test_raised_reward_card_and_skip_have_stable_hit_areas :: proc(t: ^testing.T) {
	run := create_reward_render_test_run(t)
	defer game.destroy_run(&run)
	choices := game.available_card_rewards(&run)
	raised := reward_card_bounds(960, 540, 1, len(choices), true)
	raised_only_point := view.Vec2{raised.x+raised.width*0.5, raised.y+4}
	index, found := reward_card_at_point(&run, 960, 540, raised_only_point, 1)
	testing.expect(t, found)
	testing.expect_value(t, index, 1)

	skip := reward_skip_bounds(960, 540)
	skip_point := view.Vec2{skip.x+skip.width*0.5, skip.y+skip.height*0.5}
	testing.expect(t, reward_skip_at_point(960, 540, skip_point))
	testing.expect(t, !reward_skip_at_point(960, 540, {10, 10}))
	for card_index in 0..<len(choices) {
		card := reward_card_bounds(960, 540, card_index, len(choices))
		testing.expect(t, card.y+card.height < skip.y)
	}
}
