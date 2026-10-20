package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

RENDER_TEST_PLAYER_STATS :: game.Player_Stats{
	max_health = 10,
	attack = 2,
	defense = 1,
}

RENDER_TEST_RUN_CONFIG :: game.Run_Map_Config{
	layer_count = 7,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

@(test)
test_every_run_node_center_can_be_hit :: proc(t: ^testing.T) {
	run, ok := game.create_run(RENDER_TEST_PLAYER_STATS, RENDER_TEST_RUN_CONFIG, 123)
	testing.expect(t, ok)
	defer game.destroy_run(&run)

	for &node in run.route_map.nodes {
		center := run_node_center(&run, &node, 960, 540)
		found_id, found := run_node_at_point(&run, 960, 540, center)
		testing.expect(t, found)
		testing.expect_value(t, found_id, node.id)
	}
}

@(test)
test_run_map_hit_test_rejects_empty_canvas_space :: proc(t: ^testing.T) {
	run, ok := game.create_run(RENDER_TEST_PLAYER_STATS, RENDER_TEST_RUN_CONFIG, 123)
	testing.expect(t, ok)
	defer game.destroy_run(&run)

	found_id, found := run_node_at_point(&run, 960, 540, view.Vec2{10, 10})
	testing.expect(t, !found)
	testing.expect_value(t, found_id, game.INVALID_NODE_ID)
}

@(test)
test_run_shop_button_has_a_stable_hit_area :: proc(t: ^testing.T) {
	bounds := run_shop_button_bounds(960, 540)
	center := view.Vec2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
	testing.expect(t, bounds.x >= 0 && bounds.y >= 0)
	testing.expect(t, bounds.x+bounds.width <= 960 && bounds.y+bounds.height <= 540)
	testing.expect(t, run_shop_button_at_point(960, 540, center))
	testing.expect(t, !run_shop_button_at_point(960, 540, {10, 10}))
	testing.expect_value(t, run_shop_button_bounds(200, 540), rl.Rectangle{})
	testing.expect_value(t, run_shop_button_bounds(960, 50), rl.Rectangle{})
	testing.expect(t, !run_shop_button_at_point(200, 540, {}))
}
