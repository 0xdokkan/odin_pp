package render

import "core:testing"
import game "../game"
import view "../view"

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

	found_id, found := run_node_at_point(&run, 960, 540, view.Vec2{x = 10, y = 10})
	testing.expect(t, !found)
	testing.expect_value(t, found_id, game.INVALID_NODE_ID)
}
