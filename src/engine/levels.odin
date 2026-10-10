package engine

MAX_SPAWNS :: 8
Level :: struct {
	name: string,
	world: World,
	spawns: [MAX_SPAWNS]Vec3,
	spawn_count: int,
}

add_boundary :: proc(world: ^World, half_x, half_z, height: f32) {
	add_solid(world, {{-half_x-0.5, -0.25, -half_z-0.5}, {-half_x, height, half_z+0.5}}, 101)
	add_solid(world, {{half_x, -0.25, -half_z-0.5}, {half_x+0.5, height, half_z+0.5}}, 102)
	add_solid(world, {{-half_x, -0.25, -half_z-0.5}, {half_x, height, -half_z}}, 103)
	add_solid(world, {{-half_x, -0.25, half_z}, {half_x, height, half_z+0.5}}, 104)
}

create_ring_level :: proc() -> Level {
	level := Level{name = "Ring", spawn_count = 2}
	add_boundary(&level.world, 4.5, 4.5, 1.3)
	level.spawns[0] = {-2, 0, 0}
	level.spawns[1] = {2, 0, 0}
	return level
}

create_courtyard_level :: proc() -> Level {
	level := Level{name = "Courtyard", spawn_count = 2}
	add_boundary(&level.world, 7, 7, 2.8)
	positions := [2]f32{-3.3, 3.3}
	for x in positions {
		for z in positions {
			add_solid(&level.world, {{x-0.5, 0, z-0.5}, {x+0.5, 2.3, z+0.5}}, u32(level.world.solid_count+101))
		}
	}
	level.spawns[0] = {-2, 0, 0}
	level.spawns[1] = {2, 0, 0}
	add_trigger(&level.world, {{-1, 0, -6.8}, {1, 2.5, -5.8}}, 301)
	return level
}

create_gallery_level :: proc() -> Level {
	level := Level{name = "Shooting Gallery", spawn_count = 4}
	add_boundary(&level.world, 8, 10, 3)
	add_solid(&level.world, {{-5.5, 0, -1}, {-2.5, 1.1, 0}}, 201)
	add_solid(&level.world, {{2.5, 0, -1}, {5.5, 1.1, 0}}, 202)
	add_solid(&level.world, {{-0.65, 0, -3.5}, {0.65, 2.5, -2.5}}, 203)
	level.spawns[0] = {0, 0, 7}
	level.spawns[1] = {-4, 0, -5}
	level.spawns[2] = {4, 0, -5}
	level.spawns[3] = {0, 0, -7}
	add_trigger(&level.world, {{-1.5, 0, -9.8}, {1.5, 2.5, -8.5}}, 301)
	return level
}

validate_level :: proc(level: ^Level) -> bool {
	if level == nil || !valid_world(&level.world) || level.spawn_count < 1 || level.spawn_count > MAX_SPAWNS { return false }
	for solid in level.world.solids[:level.world.solid_count] { if !valid_bounds(solid.bounds) { return false } }
	for trigger in level.world.triggers[:level.world.trigger_count] { if !valid_bounds(trigger.bounds) { return false } }
	for spawn, index in level.spawns[:level.spawn_count] {
		body := Body{position = spawn, radius = 0.4, height = 1.8, id = u32(index+1), layer = .Actor}
		if !valid_body(body) || spawn.y != 0 || body_overlaps(&level.world, body) { return false }
		for other in level.spawns[:index] {
			if vec_length(vec_sub(spawn, other)) < 0.8 { return false }
		}
	}
	return true
}
