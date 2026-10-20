package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_clear_room_light_follows_presentation_then_resets_in_next_combat :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#....>..#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 3
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {7, 3}, health = 1, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer^ = create(960, 540)
	snapshot: Room_Presentation
	renderer.tactical = {snapshot = &snapshot}
	update_tactical_view(renderer, &room, {}, false)
	before := snapshot
	testing.expect_value(t, before.phase, game.Room_Phase.Combat)
	testing.expect(t, !tactical_render_visible(renderer, room.exit_position))

	// The authoritative final kill happens before its presentation. Neither
	// room reveal nor light may jump ahead of the still-visible combat snapshot.
	game.kill_enemy(&room, 0)
	game.finish_player_combat_command(&room)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	renderer.timeline.view = before
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Defeat, duration = 1}
	update_tactical_view(renderer, &room, {}, false)
	update_tactical_atmosphere(renderer, 1.2)
	testing.expect(t, !renderer.tactical.no_fog)
	testing.expect(t, !tactical_render_visible(renderer, room.exit_position))
	testing.expect_value(t, renderer.tactical.clear_light, f32(0))

	renderer.timeline.view = capture_room_presentation(&room)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, renderer.tactical.no_fog)
	testing.expect(t, tactical_render_visible(renderer, room.exit_position))
	testing.expect_value(t, renderer.tactical.clear_light, f32(0))
	update_tactical_atmosphere(renderer, 0.6)
	testing.expect_value(t, renderer.tactical.clear_light, f32(0.5))
	renderer.timeline.count = 0
	update_tactical_view(renderer, &room, {}, false)
	update_tactical_atmosphere(renderer, 0.6)
	testing.expect_value(t, renderer.tactical.clear_light, f32(1))

	// Reusing the renderer for a newly constructed room restores fight fog and
	// lighting immediately, rather than retaining a fully-lit exploration map.
	game.destroy_room(&room)
	room, built = game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	update_tactical_view(renderer, &room, {}, false)
	testing.expect_value(t, snapshot.phase, game.Room_Phase.Combat)
	testing.expect_value(t, renderer.tactical.clear_light, f32(0))
	testing.expect(t, !renderer.tactical.no_fog)
	testing.expect(t, !tactical_render_visible(renderer, room.exit_position))
}

@(test)
test_clear_room_light_takes_real_seconds_independent_of_animation_speed :: proc(t: ^testing.T) {
	for speed in ([4]f32{0.25, 1, 2, 4}) {
		renderer := new(Renderer)
		defer free(renderer)
		snapshot := Room_Presentation{valid = true, phase = .Loot}
		renderer.tactical = {snapshot = &snapshot}
		testing.expect(t, set_renderer_playback_speed(renderer, speed))
		previous: f32
		for step in 1..=4 {
			update_tactical_atmosphere(renderer, 0.3)
			testing.expect(t, renderer.tactical.clear_light > previous)
			testing.expect_value(t, renderer.tactical.clear_light, f32(step)*0.25)
			previous = renderer.tactical.clear_light
			update_tactical_atmosphere(renderer, 0)
			testing.expect_value(t, renderer.tactical.clear_light, previous)
		}
		update_tactical_atmosphere(renderer, 20)
		testing.expect_value(t, renderer.tactical.clear_light, f32(1))
		snapshot.phase = .Complete
		update_tactical_atmosphere(renderer, 0.3)
		testing.expect_value(t, renderer.tactical.clear_light, f32(1))
		snapshot.phase = .Combat
		update_tactical_atmosphere(renderer, 0)
		testing.expect_value(t, renderer.tactical.clear_light, f32(0))
	}
}
