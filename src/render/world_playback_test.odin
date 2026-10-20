package render

import "core:testing"
import game "../game"
import view "../engine/view"

@(test)
test_world_movement_and_foreground_move_animate_without_a_shared_input_lock :: proc(t: ^testing.T) {
	player := game.Player{position = {1, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, position = {7, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	before := capture_room_presentation(&room)
	world_events := game.Event_Log{count = 1}
	world_events.events[0] = {kind = .Moved, source = game.enemy_entity(1), target = game.enemy_entity(1), from_position = {7, 2}, to_position = {6, 2}}
	room.enemies[0].position = {6, 2}
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &world_events, &after))
	testing.expect(t, renderer_world_is_busy(renderer))
	testing.expect(t, !renderer_blocks_player_input(renderer))
	before = after
	player.position = {2, 2}
	after = capture_room_presentation(&room)
	player_events := game.Event_Log{count = 1}
	player_events.events[0] = {kind = .Moved, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, from_position = {1, 2}, to_position = {2, 2}}
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &player_events, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_PLAYER_MOVE_DURATION/2)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	expect_presentation_position(t, snapshot.player.position, {1.5, 2})
	testing.expect(t, snapshot.enemies[0].position.x > 6 && snapshot.enemies[0].position.x < 7)
	testing.expect_value(t, renderer_active_cue_count(renderer), 2)
	update_renderer_event_timeline(renderer, PRESENTATION_PLAYER_MOVE_DURATION/2)
	testing.expect(t, !renderer_blocks_player_input(renderer))
	testing.expect(t, renderer_world_is_busy(renderer))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	expect_presentation_position(t, snapshot.player.position, {2, 2})
	update_renderer_event_timeline(renderer, 1)
	testing.expect(t, !renderer_timeline_is_busy(renderer))
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}

@(test)
test_new_world_damage_cannot_be_undone_by_an_older_player_snapshot :: proc(t: ^testing.T) {
	player := game.Player{position = {1, 2}, health = 10, stats = {max_health = 10}}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	before := capture_room_presentation(&room)
	player.position = {2, 2}
	after := capture_room_presentation(&room)
	move := game.Event_Log{count = 1}
	move.events[0] = {kind = .Moved, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, from_position = {1, 2}, to_position = {2, 2}}
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &move, &after))
	before = after
	player.health = 7
	player.deck.energy = 1
	after = capture_room_presentation(&room)
	hit := game.Event_Log{count = 1}
	hit.events[0] = {kind = .Damaged, source = game.enemy_entity(1), target = game.PLAYER_ENTITY, amount = 3}
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &hit, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_PLAYER_MOVE_DURATION/2)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.health, i32(7))
	testing.expect_value(t, snapshot.deck.energy, i32(1))
	expect_presentation_position(t, snapshot.player.position, {1.5, 2})
	update_renderer_event_timeline(renderer, 10)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.health, i32(7))
	expect_presentation_position(t, snapshot.player.position, {2, 2})
}

@(test)
test_world_waypoints_queue_per_actor_but_a_full_encounter_moves_concurrently :: proc(t: ^testing.T) {
	player := game.Player{health = 10}
	enemies: [game.MAX_ENEMIES_PER_ROOM]game.Enemy
	for &enemy, index in enemies {
		enemy = {id = u32(index+1), position = {7, index}, health = 5, max_health = 5}
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	events: game.Event_Log
	for _ in 0..<2 {
		before := capture_room_presentation(&room)
		events.count = 0
		for &enemy in room.enemies {
			events.events[events.count] = {kind = .Moved, source = game.enemy_entity(enemy.id), target = game.enemy_entity(enemy.id), from_position = enemy.position, to_position = {enemy.position.x-1, enemy.position.y}}
			events.count += 1
			enemy.position.x -= 1
		}
		after := capture_room_presentation(&room)
		testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &after))
	}
	testing.expect_value(t, renderer_active_cue_count(renderer), len(enemies))
	// Effects correlating an action with its later waypoints must also see
	// the delayed cues; the drawing iterator deliberately omits them.
	testing.expect_value(t, renderer_queued_cue_count(renderer), len(enemies)*2)
	pending, found := renderer_queued_cue_at(renderer, len(enemies))
	testing.expect(t, found)
	if found {
		testing.expect(t, !pending.started)
		testing.expect_value(t, pending.event.from_position.x, 6)
		testing.expect_value(t, pending.event.from_position.y, 0)
	}
	update_renderer_event_timeline(renderer, PRESENTATION_ENEMY_MOVE_DURATION/2)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	for actor, index in snapshot.enemies[:snapshot.enemy_count] { expect_presentation_position(t, actor.position, {6.5, f32(index)}) }
	update_renderer_event_timeline(renderer, PRESENTATION_ENEMY_MOVE_DURATION)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	for actor, index in snapshot.enemies[:snapshot.enemy_count] { expect_presentation_position(t, actor.position, {5.5, f32(index)}) }
	update_renderer_event_timeline(renderer, PRESENTATION_ENEMY_MOVE_DURATION/2)
	testing.expect(t, !renderer_world_is_busy(renderer))
	testing.expect_value(t, renderer.world_playback.high_water, len(enemies)*2)
	testing.expect_value(t, renderer.world_playback.rejected_batches, 0)
}

@(test)
test_world_defeat_cannot_resurrect_an_actor_in_an_older_foreground_snapshot :: proc(t: ^testing.T) {
	player := game.Player{position = {1, 2}, health = 10}
	enemies := [?]game.Enemy{{id = 1, position = {7, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	before := capture_room_presentation(&room)
	foreground := game.Event_Log{count = 1}
	foreground.events[0] = {kind = .Attack_Missed, target = game.PLAYER_ENTITY}
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &foreground, &before))
	renderer.timeline.cues[0].duration = 2
	clear(&room.enemies)
	world := game.Event_Log{count = 1}
	world.events[0] = {kind = .Entity_Defeated, target = game.enemy_entity(1)}
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &world, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_DEFEAT_DURATION/2)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.enemy_count, 1)
	testing.expect_value(t, snapshot.enemies[0].health, i32(0))
	testing.expect(t, presentation_timeline_values_are_close(snapshot.enemies[0].opacity, 0.5))
	update_renderer_event_timeline(renderer, PRESENTATION_DEFEAT_DURATION)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.enemy_count, 0)
	testing.expect(t, renderer_blocks_player_input(renderer))
	testing.expect(t, !renderer_world_is_busy(renderer))
	clear_event_animations(renderer)
	testing.expect(t, !renderer_timeline_is_busy(renderer))
	testing.expect_value(t, snapshot.player.position, view.Vec2{1, 2})
}

@(test)
test_world_shield_consumption_and_expiry_override_the_older_card_reveal :: proc(t: ^testing.T) {
	player := game.Player{position = {1, 2}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	before := capture_room_presentation(&room)
	player.statuses.count = 1
	player.statuses.items[0] = {kind = .Shield, potency = 3, remaining_pulses = 2}
	after := capture_room_presentation(&room)
	shield := game.Event_Log{count = 1}
	shield.events[0] = {kind = .Status_Applied, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, status = .Shield, amount = 3, duration = 2}
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &shield, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_STATUS_DURATION/4)
	before = after
	player.statuses.items[0].potency = 1
	after = capture_room_presentation(&room)
	hit := game.Event_Log{count = 1}
	hit.events[0] = {kind = .Damage_Absorbed, source = game.enemy_entity(1), target = game.PLAYER_ENTITY, amount = 2}
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &hit, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_STATUS_DURATION/4)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.statuses.items[0].potency, i32(1))
	before = after
	player.statuses = {}
	after = capture_room_presentation(&room)
	hit.events[0] = {kind = .Status_Expired, target = game.PLAYER_ENTITY, status = .Shield}
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &hit, &after))
	update_renderer_event_timeline(renderer, PRESENTATION_STATUS_DURATION/4)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.statuses.count, 0)
	testing.expect(t, renderer_blocks_player_input(renderer))
	update_renderer_event_timeline(renderer, 10)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.statuses.count, 0)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}

@(test)
test_world_capacity_rejection_is_atomic_and_clear_releases_all_slots :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	events := game.Event_Log{count = 1}
	events.events[0] = {kind = .Pulse_Advanced, pulse_count = 1}
	testing.expect(t, begin_renderer_world_timeline(renderer, {}, &events))
	renderer.world_playback.count = MAX_WORLD_PRESENTATION_CUES-1
	testing.expect_value(t, renderer_world_available_cues(renderer), 1)
	events.count = 2
	events.events[1] = {kind = .Pulse_Advanced, pulse_count = 2}
	testing.expect(t, !renderer_world_can_accept(renderer, &events))
	testing.expect(t, !begin_renderer_world_timeline(renderer, {}, &events))
	testing.expect_value(t, renderer.world_playback.count, MAX_WORLD_PRESENTATION_CUES-1)
	testing.expect_value(t, renderer.world_playback.cues[0].cue.event.pulse_count, u64(1))
	testing.expect_value(t, renderer.world_playback.rejected_batches, 1)
	clear_event_animations(renderer)
	testing.expect_value(t, renderer_world_available_cues(renderer), MAX_WORLD_PRESENTATION_CUES)
	testing.expect_value(t, renderer_active_cue_count(renderer), 0)
	testing.expect(t, begin_renderer_world_timeline(renderer, {}, &events))
	update_renderer_event_timeline(renderer, 1)
	testing.expect(t, !renderer_timeline_is_busy(renderer))
}
