package render

import "core:testing"
import game "../game"

make_grid_object_presentation_test_room :: proc(player: ^game.Player) -> game.Room {
	result := game.Room{player = player, phase = .Combat}
	result.objects = make([dynamic]game.Grid_Object, 0, 1)
	append(&result.objects, game.Grid_Object{
		id = 7,
		kind = .Ice_Block,
		position = {3, 2},
		max_health = 4,
		health = 4,
	})
	return result
}

@(test)
test_grid_object_presentation_snapshot_is_independent_from_room_state :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_grid_object_presentation_test_room(&player)
	defer game.destroy_room(&room)

	presentation := capture_room_presentation(&room)
	object_ref := game.object_entity(7)
	object, found := presentation_grid_object_in_view(&presentation, object_ref)
	testing.expect(t, found)
	testing.expect_value(t, presentation.object_count, 1)
	if found {
		testing.expect_value(t, object.entity, object_ref)
		testing.expect_value(t, object.kind, game.Grid_Object_Kind.Ice_Block)
		testing.expect_value(t, object.position.x, f32(3))
		testing.expect_value(t, object.position.y, f32(2))
		testing.expect_value(t, object.health, i32(4))
		testing.expect(t, object.visible)
	}

	room.objects[0].position = {8, 8}
	room.objects[0].health = 1
	object, found = presentation_grid_object_in_view(&presentation, object_ref)
	if found {
		testing.expect_value(t, object.position.x, f32(3))
		testing.expect_value(t, object.position.y, f32(2))
		testing.expect_value(t, object.health, i32(4))
	}
}

@(test)
test_grid_object_timeline_replays_move_damage_and_destruction_after_removal :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_grid_object_presentation_test_room(&player)
	defer game.destroy_room(&room)
	object_ref := game.object_entity(7)
	before := capture_room_presentation(&room)
	unordered_remove(&room.objects, 0)

	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = object_ref,
		from_position = {3, 2},
		to_position = {4, 2},
	})
	game.record_event(&events, {kind = .Damaged, target = object_ref, amount = 2})
	game.record_event(&events, {kind = .Entity_Defeated, target = object_ref})

	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	testing.expect(t, !update_event_timeline(&timeline, PRESENTATION_ENEMY_MOVE_DURATION))
	object, found := presentation_grid_object(&timeline, object_ref)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, object.position.x, f32(4))
		testing.expect_value(t, object.position.y, f32(2))
		testing.expect(t, object.visible)
	}

	testing.expect(t, !update_event_timeline(&timeline, PRESENTATION_DAMAGE_DURATION))
	object, found = presentation_grid_object(&timeline, object_ref)
	if found {
		testing.expect_value(t, object.health, i32(2))
	}

	testing.expect(t, !update_event_timeline(&timeline, PRESENTATION_DEFEAT_DURATION*0.5))
	object, found = presentation_grid_object(&timeline, object_ref)
	if found {
		testing.expect(t, object.visible)
		testing.expect(t, presentation_timeline_values_are_close(object.opacity, 0.5))
	}
	testing.expect(t, update_event_timeline(&timeline, PRESENTATION_DEFEAT_DURATION*0.5))
	object, found = presentation_grid_object(&timeline, object_ref)
	if found {
		testing.expect(t, !object.visible)
		testing.expect_value(t, object.opacity, f32(0))
	}
	testing.expect_value(t, timeline.view.phase, game.Room_Phase.Combat)
	testing.expect_value(t, timeline.update_failures, 0)
}
