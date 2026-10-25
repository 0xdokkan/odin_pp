package render

import "core:testing"
import game "../game"

@(test)
test_recovery_step_keeps_enemy_telegraphs_visible_until_actions_resume :: proc(t: ^testing.T) {
	player := game.Player{position = {x = 1, y = 2}, health = 10, stats = {max_health = 10}}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	player.tactical.phase = .Recovery
	player.tactical.remaining = game.TACTICAL_RECOVERY_SECONDS
	renderer := new(Renderer)
	defer free(renderer)
	before := capture_room_presentation(&room)
	player.position = {x = 2, y = 2}
	after := capture_room_presentation(&room)
	events := game.Event_Log{count = 1}
	events.events[0] = {kind = .Moved, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 2}, to_position = {x = 2, y = 2}}
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &events, &after))
	testing.expect(t, renderer_blocks_player_input(renderer))
	player.tactical.phase = .Decision
	testing.expect(t, !tactical_telegraphs_are_visible(renderer, &room))
	player.tactical.phase = .Recovery
	testing.expect(t, tactical_telegraphs_are_visible(renderer, &room))
	testing.expect(t, !game.tactical_allows_action(&room))
	testing.expect(t, game.tactical_allows_movement(&room))
	update_renderer_event_timeline(renderer, PRESENTATION_PLAYER_MOVE_DURATION)
	testing.expect(t, tactical_telegraphs_are_visible(renderer, &room))
	testing.expect(t, game.tactical_is_recovering(&room))
	player.tactical.phase = .Decision
	player.tactical.remaining = f32(player.tactical.budget)
	testing.expect(t, game.tactical_allows_action(&room))
	testing.expect(t, tactical_telegraphs_are_visible(renderer, &room))
}
