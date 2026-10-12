package render

import "core:testing"
import game "../game"

@(test)
test_intent_display_shows_on_living_boards_and_cycles :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	// Only living boards (the 3D board) show it, with seals and ground.
	testing.expect(t, !intent_seals_on(renderer) && !intent_ground_on(renderer))
	renderer.tactical.living = true
	testing.expect(t, intent_seals_on(renderer) && intent_ground_on(renderer))
	cycle_intent_display(renderer)
	testing.expect(t, intent_seals_on(renderer) && !intent_ground_on(renderer))
	cycle_intent_display(renderer)
	testing.expect(t, !intent_seals_on(renderer) && intent_ground_on(renderer))
	cycle_intent_display(renderer)
	testing.expect(t, !intent_seals_on(renderer) && !intent_ground_on(renderer))
	cycle_intent_display(renderer)
	testing.expect_value(t, renderer.tactical.intent_display, Intent_Display.Both)
	for a in Intent_Display {
		testing.expect(t, len(string(intent_display_name(a))) > 0)
		for b in Intent_Display { if a != b { testing.expect(t, intent_display_name(a) != intent_display_name(b)) } }
	}
}

// Quiet while the action is far; in its last moments a luminance flicker.
@(test)
test_intent_urgency_flickers_only_at_the_end :: proc(t: ^testing.T) {
	testing.expect(t, intent_loudness(3) == 0 && intent_loudness(0) == 1)
	testing.expect(t, intent_loudness(INTENT_LOUD_SECONDS*0.5) > 0.4)
	testing.expect_value(t, intent_flicker(1.0, 0.1), f32(1))
	testing.expect_value(t, intent_flicker(0.3, 0.02), f32(1))
	testing.expect(t, intent_flicker(0.3, 0.1) < 1)
}

// When a countdown runs out and a new plan takes its place, the action that
// landed flashes where it struck.
@(test)
test_intent_traces_flash_the_action_that_landed :: proc(t: ^testing.T) {
	strike := game.Enemy_Intent{kind = .Attack, planned_pulse = 1, threatened_cell_count = 1}
	strike.threatened_cells[0] = {5, 5}
	enemies := [?]game.Enemy{{id = 3, archetype = .Chaser, position = {5, 4}, intent = strike, tactical_cooldown = 0.2}}
	room := make_enemy_intent_renderer_test_room(enemies[:])
	defer game.destroy_room(&room)
	player: game.Player
	player.tactical.config.enabled = true
	room.player = &player
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.living = true
	update_intent_traces(renderer, &room, 1.0)
	trace := intent_trace(renderer, 3)
	testing.expect(t, trace.kind == .Strike && trace.flash_kind == .None)
	room.enemies[0].intent = {kind = .Move, planned_pulse = 2, destination = {6, 4}}
	room.enemies[0].tactical_cooldown = 2
	update_intent_traces(renderer, &room, 1.1)
	trace = intent_trace(renderer, 3)
	testing.expect(t, trace.flash == 1.1 && trace.flash_kind == .Strike && trace.flash_count == 1)
	testing.expect(t, trace.flash_cells[0] == {5, 5} && trace.kind == .Move)
	// A plan kept from frame to frame does not flash again.
	update_intent_traces(renderer, &room, 1.2)
	testing.expect_value(t, intent_trace(renderer, 3).flash, f64(1.1))
}
