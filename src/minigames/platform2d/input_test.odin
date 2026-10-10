package platform2d

import "core:testing"
import host "../../engine/host"
import timing "../../engine/timing"

@(test)
test_pause_discards_buffered_jump_dash_and_drop :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 31})
	defer world_destroy(&g.world)
	g.fixed = timing.fixed_step(STEP_HZ)
	advance_player_controls(g, {}, SIM_DT)
	advance_player_controls(g, {down = {.Jump, .Dash, .Down}}, SIM_DT)
	testing.expect(t, g.pending.jump_pressed && g.pending.dash_pressed && g.pending.down_pressed)
	g.fixed.accumulator = SIM_DT * 0.5
	g.fixed.total_steps = 12
	frame := host.Frame{focused = true, dt = SIM_DT}
	game_step(g, &frame, false)
	testing.expect_value(t, g.pending, Player_Input{})
	testing.expect_value(t, g.fixed.accumulator, f32(0))
	testing.expect_value(t, g.fixed.total_steps, u64(12))
	advance_player_controls(g, {down = {.Jump, .Dash, .Down}}, SIM_DT)
	testing.expect_value(t, g.pending, Player_Input{})
	advance_player_controls(g, {}, SIM_DT)
	advance_player_controls(g, {down = {.Jump, .Dash, .Down}}, SIM_DT)
	testing.expect(t, g.pending.jump_pressed && g.pending.dash_pressed && g.pending.down_pressed)
}
