package render

import "core:testing"
import game "../game"

@(test)
test_animation_speed_changes_duration_and_preserves_event_order_and_final_view :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved, target = game.PLAYER_ENTITY,
		from_position = {1, 1}, to_position = {2, 1},
	})
	game.record_event(&events, {kind = .Damaged, target = game.PLAYER_ENTITY, amount = 2})
	normal, fast: Renderer
	before := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(&normal, before, &events))
	testing.expect(t, begin_renderer_event_timeline(&fast, before, &events))
	testing.expect(t, set_renderer_playback_speed(&fast, 4))
	testing.expect(t, !set_renderer_playback_speed(&fast, 0))
	testing.expect(t, !set_renderer_playback_speed(&fast, -1))
	testing.expect(t, !set_renderer_playback_speed(&fast, 5))
	testing.expect_value(t, renderer_playback_speed(&fast), f32(4))
	step := PRESENTATION_PLAYER_MOVE_DURATION/4
	update_renderer_event_timeline(&fast, step)
	update_renderer_event_timeline(&normal, step)
	fast_cue, fast_active := active_presentation_cue(&fast.timeline)
	normal_cue, normal_active := active_presentation_cue(&normal.timeline)
	testing.expect(t, fast_active && normal_active)
	testing.expect_value(t, fast_cue.kind, Presentation_Cue_Kind.Damage)
	testing.expect_value(t, normal_cue.kind, Presentation_Cue_Kind.Move)
	testing.expect_value(t, fast.timeline.view.player.health, before.player.health)
	testing.expect(t, update_renderer_event_timeline(&fast, PRESENTATION_DAMAGE_DURATION/4))
	testing.expect(t, renderer_timeline_is_busy(&normal))
	testing.expect(t, update_renderer_event_timeline(&normal, 1000))
	testing.expect_value(t, fast.timeline.view, normal.timeline.view)
	testing.expect_value(t, fast.timeline.update_failures, 0)
	clear_event_animations(&fast)
	testing.expect_value(t, renderer_playback_speed(&fast), f32(4))
}

@(test)
test_upgrade_preview_uses_effect_values_and_rest_disables_no_op_upgrade :: proc(t: ^testing.T) {
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Strike})), "DAMAGE 3 -> 4")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Volatile_Study, upgrade_level = 2})), "DRAW 3 -> 4")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Dash})), "NO UPGRADE AVAILABLE")
	run: game.Run_State
	run.phase = .Rest
	testing.expect(t, game.initialize_empty_deck(&run.player.deck))
	card, added := game.add_owned_card(&run.player.deck, .Dash)
	testing.expect(t, added)
	testing.expect(t, !special_node_secondary_is_enabled(&run, card.id))
}
