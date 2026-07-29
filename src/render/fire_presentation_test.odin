package render

import "core:testing"
import game "../game"
import view "../view"

make_fire_presentation_test_room :: proc(player: ^game.Player) -> game.Room {
	result := game.Room{player = player, phase = .Combat}
	result.objects = make([dynamic]game.Grid_Object, 0, 1)
	definition, found := game.grid_object_definition(.Fire)
	assert(found)
	append(&result.objects, game.Grid_Object{
		id = 19,
		kind = .Fire,
		position = {x = 4, y = 3},
		max_health = definition.max_health,
		health = definition.max_health,
	})
	return result
}

@(test)
test_fire_presentation_snapshot_keeps_persistent_hazard_identity :: proc(t: ^testing.T) {
	player := game.Player{
		position = {x = 4, y = 3},
		stats = {max_health = 10},
		health = 10,
	}
	room := make_fire_presentation_test_room(&player)
	defer game.destroy_room(&room)

	presentation := capture_room_presentation(&room)
	object, found := presentation_grid_object_in_view(
		&presentation,
		game.object_entity(19),
	)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, object.kind, game.Grid_Object_Kind.Fire)
		testing.expect(t, object.visible)
		testing.expect_value(t, object.opacity, f32(1))
		expect_presentation_position(t, object.position, {x = 4, y = 3})
	}
}

@(test)
test_fire_hazard_cue_targets_actor_without_consuming_persistent_fire :: proc(t: ^testing.T) {
	player := game.Player{
		position = {x = 4, y = 3},
		stats = {max_health = 10},
		health = 10,
	}
	room := make_fire_presentation_test_room(&player)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	fire_definition, found := game.grid_object_definition(.Fire)
	testing.expect(t, found)

	event := game.Game_Event{
		kind = .Hazard_Triggered,
		source = game.object_entity(19),
		target = game.PLAYER_ENTITY,
		amount = fire_definition.hazard_damage,
		from_position = {x = 4, y = 3},
		to_position = {x = 4, y = 3},
	}
	events: game.Event_Log
	testing.expect(t, game.record_event(&events, event))

	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	cue, cue_found := active_presentation_cue(&timeline)
	testing.expect(t, cue_found)
	if cue_found {
		testing.expect_value(t, cue.kind, Presentation_Cue_Kind.Hazard_Triggered)
		testing.expect_value(t, cue.event, event)
	}

	renderer := Renderer{
		projection = {tile_width = 64, tile_height = 32},
		camera = view.make_camera({x = 100, y = 80}),
		timeline = timeline,
	}
	center, has_center := presentation_event_center(&renderer, event)
	testing.expect(t, has_center)
	expected_center := presentation_actor_center(&renderer, &renderer.timeline.view.player)
	expect_presentation_position(t, center, expected_center)

	testing.expect(t, update_event_timeline(&timeline, PRESENTATION_NOTICE_DURATION))
	object, object_found := presentation_grid_object(&timeline, game.object_entity(19))
	testing.expect(t, object_found)
	if object_found {
		testing.expect(t, object.visible)
		testing.expect_value(t, object.opacity, f32(1))
		testing.expect_value(t, object.kind, game.Grid_Object_Kind.Fire)
	}
	testing.expect_value(t, timeline.view.player.health, i32(10))
	testing.expect_value(t, timeline.update_failures, 0)
}
