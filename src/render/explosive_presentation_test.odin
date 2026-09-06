package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_bomb_spawn_arm_and_explosion_replay_without_reading_future_state :: proc(t: ^testing.T) {
	rows := [?]string{"########", "#@.....#", "#......#", "#.....>#", "########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, player_ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_ok)
	enemies := [?]game.Enemy_Spawn{{position = {5, 1}, health = 8, attack = 1, archetype = .Bomber}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	timeline: Presentation_Timeline
	for step in 0..<3 {
		before := capture_room_presentation(&room)
		game.wait_player_turn(&room)
		after := capture_room_presentation(&room)
		testing.expect(t, begin_event_timeline(&timeline, before, &room.recent_events, &after))
		if step == 0 {
			testing.expect_value(t, timeline.view.object_count, 0)
		}
		if step == 2 {
			// Bomb 1 has disappeared from the simulation, but must exist until its cue.
			object, found := presentation_grid_object(&timeline, game.object_entity(1))
			testing.expect(t, found && object.visible)
			testing.expect_value(t, timeline.view.player.health, i32(20))
		}
		testing.expect(t, update_event_timeline(&timeline, 1000))
		testing.expect_value(t, timeline.update_failures, 0)
		testing.expect_value(t, timeline.dropped_count, 0)
		testing.expect_value(t, timeline.view.player.health, player.health)
		testing.expect_value(t, timeline.view.pulse_count, room.pulse_count)
		for object in room.objects {
			visual, found := presentation_grid_object(&timeline, game.object_entity(object.id))
			testing.expect(t, found && visual.visible)
			testing.expect_value(t, visual.detonation_pulse, object.detonation_pulse)
		}
	}
	testing.expect_value(t, player.health, i32(16))
}

@(test)
test_bomb_spawn_reuses_hidden_slot_at_full_presentation_capacity :: proc(t: ^testing.T) {
	presentation := Room_Presentation{valid = true, object_count = MAX_PRESENTATION_GRID_OBJECTS}
	for &object, index in presentation.objects {
		object = {entity = game.object_entity(u32(index+1)), kind = .Ice_Block, visible = true, opacity = 1}
	}
	presentation.objects[7].visible = false
	event := game.Game_Event{kind = .Object_Spawned, object_kind = .Bomb, target = game.object_entity(99), to_position = {4, 3}}
	testing.expect(t, show_spawned_presentation_object(&presentation, event))
	testing.expect_value(t, presentation.object_count, MAX_PRESENTATION_GRID_OBJECTS)
	testing.expect_value(t, presentation.objects[7].entity, event.target)
	testing.expect_value(t, presentation.objects[7].kind, game.Grid_Object_Kind.Bomb)
	testing.expect(t, !show_spawned_presentation_object(&presentation, event))
	event.target = game.object_entity(100)
	testing.expect(t, !show_spawned_presentation_object(&presentation, event))
}

@(test)
test_explosion_snapshot_preserves_defeat_when_last_enemy_also_dies :: proc(t: ^testing.T) {
	presentation := Room_Presentation{valid = true, phase = .Combat, enemy_count = 1}
	presentation.player = {entity = game.PLAYER_ENTITY, visible = true, health = 1, opacity = 1}
	presentation.enemies[0] = {entity = game.enemy_entity(1), visible = true, health = 1, opacity = 1}
	events: game.Event_Log
	testing.expect(t, game.record_event(&events, {kind = .Entity_Defeated, target = game.PLAYER_ENTITY}))
	testing.expect(t, game.record_event(&events, {kind = .Entity_Defeated, target = game.enemy_entity(1)}))
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, presentation, &events))
	testing.expect(t, update_event_timeline(&timeline, 1000))
	testing.expect_value(t, timeline.view.phase, game.Room_Phase.Defeat)
	testing.expect_value(t, timeline.update_failures, 0)
}
