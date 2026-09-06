package game

affected_damageable_object_ids :: proc(room: ^Room, cells: ^Target_Cell_Set) -> (ids: [MAX_GRID_OBJECTS_PER_ROOM]u32, count: int) {
	for object in room.objects {
		if !target_cell_set_contains(cells, object.position) ||
		   !effect_is_valid(room, damage_effect(object_entity(object.id), 1)) {
			continue
		}
		insert_at := count
		for insert_at > 0 && ids[insert_at-1] > object.id {
			ids[insert_at] = ids[insert_at-1]
			insert_at -= 1
		}
		ids[insert_at] = object.id
		count += 1
	}
	return
}
