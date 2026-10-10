package platform3d

import "core:testing"
import host "../../engine/host"
import timing "../../engine/timing"

@(test)
test_resume_does_not_jump_or_dash_from_menu_buttons :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 33})
	defer world_destroy(&g.world)
	g.clock = timing.fixed_step(SIM_HZ)
	advance_player_controls(g, {}, g.clock.step)
	advance_player_controls(g, {down = {.Jump, .Dash}}, g.clock.step)
	testing.expect(t, g.pending_jump && g.pending_dash)
	g.clock.accumulator = g.clock.step * 0.5
	g.clock.total_steps = 17
	frame := host.Frame{focused = true, dt = g.clock.step}
	game_step(g, &frame, false)
	testing.expect(t, !g.pending_jump && !g.pending_dash)
	testing.expect_value(t, g.clock.accumulator, f32(0))
	testing.expect_value(t, g.clock.total_steps, u64(17))
	for _ in 0..<3 {
		advance_player_controls(g, {down = {.Jump, .Dash}}, g.clock.step)
		testing.expect(t, !g.pending_jump && !g.pending_dash)
	}
	advance_player_controls(g, {}, g.clock.step)
	advance_player_controls(g, {down = {.Jump, .Dash}}, g.clock.step)
	testing.expect(t, g.pending_jump && g.pending_dash)
}
