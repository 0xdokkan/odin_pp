package puzzle

import "core:testing"
import host "../../engine/host"

@(test)
test_pause_discards_queued_move_and_repeat :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	session_start(&g.session, 37, 0, false)
	view_reset(&g.view, &g.session.puzzle, {0, 0, 960, 540}, 37)
	g.was_playing = true
	g.controls.down = {.Right}
	g.controls.pressed = {.Right}
	g.repeat = {action = .Right, active = true, timer = 0}
	queue_command(g, .Right)
	before := g.session.puzzle.state
	frame := host.Frame{focused = true, dt = 1.0 / 60}
	game_step(g, &frame, false)
	testing.expect(t, !g.has_queued && !g.repeat.active && !g.was_playing)
	testing.expect(t, card(g.controls.down) == 0 && card(g.controls.pressed) == 0)
	testing.expect_value(t, g.session.puzzle.state, before)
}
