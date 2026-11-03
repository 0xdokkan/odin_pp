package render

import "core:testing"

// The nest's look (spider_nest_view.odin): a tear a blow, up to the ones that show; the two sets of legs in turn.
@(test)
test_nest_tears :: proc(t: ^testing.T) {
	testing.expect_value(t, nest_tears_shown(0), 0)
	testing.expect_value(t, nest_tears_shown(2), 2)
	testing.expect_value(t, nest_tears_shown(40), NEST_TEARS_SHOWN)
}

@(test)
test_spiderling_legs_step_in_turn :: proc(t: ^testing.T) {
	step := 1/SPIDER_LEG_STEPS
	testing.expect(t, spider_leg_jerk(step*0.5) != spider_leg_jerk(step*1.5))
	testing.expect_value(t, spider_leg_jerk(step*0.5), spider_leg_jerk(step*2.5))
}
