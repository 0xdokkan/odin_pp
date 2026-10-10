package arena

import "core:testing"
import timing "../../engine/timing"

@(test)
test_short_fire_and_dash_survive_zero_step_frames_once :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 27})
	defer world_destroy(&g.world)
	g.clock = timing.fixed_step(SIM_HZ)
	advance_player_controls(g, {}, SIM_DT)
	advance_player_controls(g, {down = {.Dash}}, SIM_DT * 0.25)
	queue_player_input(g, {fire = true})
	testing.expect_value(t, timing.fixed_step_advance(&g.clock, SIM_DT * 0.25), 0)
	advance_player_controls(g, {}, SIM_DT * 0.75)
	queue_player_input(g, {})
	testing.expect_value(t, timing.fixed_step_advance(&g.clock, SIM_DT * 0.75), 1)
	cmd := consume_player_input(g, {aim = {1, 0}})
	world_step(&g.world, cmd, SIM_DT)
	testing.expect(t, g.world.player.dash_time > 0 && g.world.bullets.count > 0)
	cmd = consume_player_input(g, {})
	testing.expect(t, !cmd.fire && !cmd.dash, "one-shot edges must not repeat on catch-up steps")
	cmd = consume_player_input(g, {fire = true})
	testing.expect(t, cmd.fire, "held fire still repeats")
}

@(test)
test_pause_clears_queued_actions_and_consumes_menu_click :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	advance_player_controls(g, {}, SIM_DT)
	advance_player_controls(g, {down = {.Dash}}, SIM_DT)
	queue_player_input(g, {fire = true})
	suspend_player_input(g)
	testing.expect(t, !consume_player_input(g, {}).fire && !g.dash_latch)
	for _ in 0..<3 {
		advance_player_controls(g, {down = {.Fire, .Dash}}, SIM_DT)
		testing.expect(t, g.fire_blocked && !g.dash_latch)
	}
	advance_player_controls(g, {}, SIM_DT)
	advance_player_controls(g, {down = {.Fire, .Dash}}, SIM_DT)
	testing.expect(t, !g.fire_blocked && g.dash_latch)
}
