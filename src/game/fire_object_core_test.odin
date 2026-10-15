package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_grid_object_definition_validation_couples_health_and_hazard_damage_to_capabilities :: proc(
	t: ^testing.T,
) {
	testing.expect(t, !validate_grid_object_definition({
		kind = .Fire,
		name = "Invalid durable decoration",
		max_health = 1,
	}))
	testing.expect(t, !validate_grid_object_definition({
		kind = .Fire,
		name = "Invalid damageable object",
		damageable = true,
	}))
	testing.expect(t, !validate_grid_object_definition({
		kind = .Fire,
		name = "Invalid harmless hazard",
		hazardous = true,
	}))
	testing.expect(t, !validate_grid_object_definition({
		kind = .Fire,
		name = "Invalid implicit hazard",
		hazard_damage = 2,
	}))
}

@(test)
test_room_materializes_fire_without_movement_or_line_of_sight_blocking :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	fire_position := grid.Position{x = 2, y = 1}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = fire_position}}
	room, ok := create_room(&level_data, &player, {objects = objects[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	testing.expect_value(t, len(room.objects), 1)
	fire := room.objects[0]
	testing.expect_value(t, fire.id, u32(1))
	testing.expect_value(t, fire.kind, Grid_Object_Kind.Fire)
	testing.expect_value(t, fire.position, fire_position)
	testing.expect_value(t, fire.max_health, i32(0))
	testing.expect_value(t, fire.health, i32(0))
	testing.expect(t, !cell_blocks_movement(&room, fire_position))
	testing.expect(t, !cell_blocks_line_of_sight(&room, fire_position))

	movement := query_entity_movement(&room, PLAYER_ENTITY, fire_position)
	testing.expect_value(t, movement.error, Movement_Error.None)
	testing.expect(t, movement_query_is_clear(&movement))
}

@(test)
test_create_room_rejects_enemy_spawn_on_traversable_fire :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	shared_position := grid.Position{x = 2, y = 1}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = shared_position}}
	enemies := [?]Enemy_Spawn{{
		position = shared_position,
		health = 3,
		attack = 1,
	}}

	_, ok := create_room(&level_data, &player, {
		objects = objects[:],
		enemies = enemies[:],
	})

	testing.expect(t, !ok)
}
