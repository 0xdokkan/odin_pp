package fps

import "core:testing"
import host "../../engine/host"
import input "../../engine/input"
import timing "../../engine/timing"

@(test)
test_quick_fire_between_fixed_steps_is_delivered_once :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 17})
	defer world_destroy(&g.world)
	g.clock = timing.fixed_step(SIM_HZ)
	view_reset(&g.view, &g.world)
	frame := host.Frame{dt = g.clock.step * 0.25}
	advance_simulation(g, &frame, {fire = true}, {})
	testing.expect_value(t, g.world.stats.shots, 0)
	// The button is already released when the first simulation step runs.
	frame.dt = g.clock.step * 0.75
	advance_simulation(g, &frame, {}, {})
	testing.expect_value(t, g.world.stats.shots, 1)
	for _ in 0..<60 {
		frame.dt = g.clock.step
		advance_simulation(g, &frame, {}, {})
	}
	testing.expect(t, g.world.stats.shots == 1, "a consumed click must not become held fire")
}

@(test)
test_pause_discards_unconsumed_fire_and_jump :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 18})
	defer world_destroy(&g.world)
	g.clock = timing.fixed_step(SIM_HZ)
	view_reset(&g.view, &g.world)
	g.jump_queued = true
	g.input_gate.active = true
	frame := host.Frame{dt = g.clock.step * 0.25, focused = true}
	advance_simulation(g, &frame, {fire = true}, {})
	testing.expect(t, g.fire_queued && g.jump_queued)
	ticks := g.clock.total_steps
	hook_step(g, &frame, false)
	testing.expect(t, !g.fire_queued && !g.jump_queued && !g.input_gate.active)
	testing.expect_value(t, g.clock.accumulator, f32(0))
	testing.expect_value(t, g.clock.total_steps, ticks)
	frame.dt = g.clock.step
	advance_simulation(g, &frame, {}, {})
	testing.expect_value(t, g.world.stats.shots, 0)
	testing.expect(t, g.world.player.body.velocity.y <= 0, "a pre-pause jump must not run on resume")
}

@(test)
test_start_click_requires_release_but_new_hold_keeps_firing :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	world_reset(&g.world, {seed = 19})
	defer world_destroy(&g.world)
	g.clock = timing.fixed_step(SIM_HZ)
	view_reset(&g.view, &g.world)
	frame := host.Frame{dt = g.clock.step, focused = true}
	held := input.Sample(Action){down = {.Fire, .Jump}}
	for _ in 0..<10 {
		cmd := advance_player_controls(g, held, frame.dt)
		advance_simulation(g, &frame, cmd, {})
	}
	testing.expect_value(t, g.world.stats.shots, 0)
	testing.expect(t, !g.jump_queued && g.world.player.body.velocity.y <= 0)
	advance_player_controls(g, {}, frame.dt)
	for _ in 0..<60 {
		cmd := advance_player_controls(g, {down = {.Fire}}, frame.dt)
		advance_simulation(g, &frame, cmd, {})
	}
	testing.expect(t, g.world.stats.shots > 1, "a fresh held click must preserve automatic fire")
}
