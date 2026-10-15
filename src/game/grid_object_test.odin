package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_grid_object_catalog_preserves_solid_and_hazard_capabilities :: proc(t: ^testing.T) {
	testing.expect(t, validate_grid_object_definitions())
	// Capability expectations are independent of the definitions. Health and
	// damage tuning are exercised by materialization and hazard behavior tests.
	cases := [?]struct {
		kind: Grid_Object_Kind,
		blocks_movement, blocks_line_of_sight: bool,
		targetable, damageable, movable, hazardous: bool,
	}{
		{.Ice_Block, true, true, true, true, true, false},
		{.Fire, false, false, false, false, false, true},
	}
	for fixture in cases {
		definition, found := grid_object_definition(fixture.kind)
		testing.expect(t, found)
		testing.expect_value(t, definition.kind, fixture.kind)
		testing.expect_value(t, definition.blocks_movement, fixture.blocks_movement)
		testing.expect_value(t, definition.blocks_line_of_sight, fixture.blocks_line_of_sight)
		testing.expect_value(t, definition.targetable, fixture.targetable)
		testing.expect_value(t, definition.damageable, fixture.damageable)
		testing.expect_value(t, definition.movable, fixture.movable)
		testing.expect_value(t, definition.hazardous, fixture.hazardous)
	}
	_, found := grid_object_definition(.Count)
	testing.expect(t, !found)
}

@(test)
test_room_materializes_grid_objects_with_stable_ids_and_blockers :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	spawns := [?]Grid_Object_Spawn{
		{kind = .Ice_Block, position = {x = 2, y = 1}},
		{kind = .Ice_Block, position = {x = 4, y = 1}},
	}
	obstacles := [?]grid.Position{{x = 5, y = 1}}
	room, ok := create_room(&level_data, &player, {
		objects = spawns[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	testing.expect_value(t, len(room.objects), 2)
	testing.expect_value(t, room.next_object_id, u32(3))
	first := &room.objects[0]
	testing.expect_value(t, first.id, u32(1))
	testing.expect_value(t, first.kind, Grid_Object_Kind.Ice_Block)
	testing.expect_value(t, first.position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, first.health, i32(4))
	testing.expect_value(t, first.max_health, i32(4))

	index, found := object_index_at(&room, {x = 2, y = 1})
	testing.expect(t, found)
	testing.expect_value(t, index, 0)
	_, found = object_index_at(&room, {x = 2, y = 1}, 0)
	testing.expect(t, !found)
	index, found = object_index_by_id(&room, 2)
	testing.expect(t, found)
	testing.expect_value(t, index, 1)
	object, object_found := grid_object_at(&room, {x = 4, y = 1})
	testing.expect(t, object_found)
	testing.expect_value(t, object.id, u32(2))

	testing.expect(t, cell_blocks_movement(&room, {x = 2, y = 1}))
	testing.expect(t, cell_blocks_line_of_sight(&room, {x = 2, y = 1}))
	testing.expect(t, cell_blocks_movement(&room, {x = 5, y = 1}))
	testing.expect(t, cell_blocks_line_of_sight(&room, {x = 5, y = 1}))
	testing.expect(t, cell_blocks_movement(&room, {x = 0, y = 0}))
	testing.expect(t, cell_blocks_line_of_sight(&room, {x = 0, y = 0}))
	testing.expect(t, !cell_blocks_movement(&room, {x = 3, y = 1}))
	testing.expect(t, !cell_blocks_line_of_sight(&room, {x = 3, y = 1}))
}

@(test)
test_remove_grid_object_keeps_remaining_object_addressable_by_id :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	spawns := [?]Grid_Object_Spawn{
		{kind = .Ice_Block, position = {x = 2, y = 1}},
		{kind = .Ice_Block, position = {x = 4, y = 1}},
	}
	room, ok := create_room(&level_data, &player, {objects = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	testing.expect(t, remove_grid_object(&room, 0))
	testing.expect_value(t, len(room.objects), 1)
	_, removed_found := object_index_by_id(&room, 1)
	testing.expect(t, !removed_found)
	index, remaining_found := object_index_by_id(&room, 2)
	testing.expect(t, remaining_found)
	testing.expect_value(t, room.objects[index].position, grid.Position{x = 4, y = 1})
	testing.expect(t, !remove_grid_object(&room, -1))
	testing.expect(t, !remove_grid_object(&room, 1))
}

@(test)
test_create_room_rejects_invalid_or_overlapping_grid_objects :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)

	invalid := [?]Grid_Object_Spawn{{kind = .Count, position = {x = 2, y = 1}}}
	_, ok := create_room(&level_data, &player, {objects = invalid[:]})
	testing.expect(t, !ok)

	duplicate := [?]Grid_Object_Spawn{
		{kind = .Ice_Block, position = {x = 2, y = 1}},
		{kind = .Ice_Block, position = {x = 2, y = 1}},
	}
	_, ok = create_room(&level_data, &player, {objects = duplicate[:]})
	testing.expect(t, !ok)

	spawn_overlap := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = level_data.player_spawn}}
	_, ok = create_room(&level_data, &player, {objects = spawn_overlap[:]})
	testing.expect(t, !ok)

	exit_overlap := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 3, y = 2}}}
	_, ok = create_room(&level_data, &player, {objects = exit_overlap[:]})
	testing.expect(t, !ok)

	object_spawn := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 2, y = 1}}}
	obstacles := [?]grid.Position{{x = 2, y = 1}}
	_, ok = create_room(&level_data, &player, {
		objects = object_spawn[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, !ok)

	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	_, ok = create_room(&level_data, &player, {
		objects = object_spawn[:],
		enemies = enemies[:],
	})
	testing.expect(t, !ok)

	traps := [?]Trap_Spawn{{position = {x = 2, y = 1}, damage = 1}}
	_, ok = create_room(&level_data, &player, {
		objects = object_spawn[:],
		traps = traps[:],
	})
	testing.expect(t, !ok)
}

@(test)
test_create_room_rejects_grid_objects_beyond_capacity :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	spawns: [MAX_GRID_OBJECTS_PER_ROOM+1]Grid_Object_Spawn

	_, ok := create_room(&level_data, &player, {objects = spawns[:]})

	testing.expect(t, !ok)
}
