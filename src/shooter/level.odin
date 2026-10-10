package shooter

import "../engine"

// Solids are collision geometry and can be skinned independently by a renderer.
// The room is grounded at y=0; the first FPS deliberately has no jumping.
reset :: proc(state: ^State, level_index: int = 0) {
	if state == nil { return }
	state^ = {}
	state.level_index = ((level_index%level_count())+level_count())%level_count()
	state.player = {position = {0, 0, -7}, health = 100, ammo = MAGAZINE_SIZE, reserve = 30}
	state.enemy_count = MAX_ENEMIES
	engine.add_solid(&state.world, {{-10.5, 0, -10.5}, {-10, 3.8, 10.5}}, 100)
	engine.add_solid(&state.world, {{10, 0, -10.5}, {10.5, 3.8, 10.5}}, 101)
	engine.add_solid(&state.world, {{-10, 0, -10.5}, {10, 3.8, -10}}, 102)
	engine.add_solid(&state.world, {{-10, 0, 10}, {10, 3.8, 10.5}}, 103)
	if state.level_index == 0 {
		engine.add_solid(&state.world, {{-4.4, 0, -0.7}, {-2.0, 1.05, 0.7}}, 104)
		engine.add_solid(&state.world, {{2.0, 0, -0.7}, {4.4, 1.05, 0.7}}, 105)
		engine.add_solid(&state.world, {{-6.8, 0, -3.1}, {-5.6, 3.2, -1.9}}, 106)
		engine.add_solid(&state.world, {{5.6, 0, -3.1}, {6.8, 3.2, -1.9}}, 107)
	} else {
		engine.add_solid(&state.world, {{-1.2, 0, -1.2}, {1.2, 1.2, 1.2}}, 104)
		for x in ([?]f32{-3.5, 3.5}) {
			for z in ([?]f32{-3.0, 3.0}) {
				id := u32(100+state.world.solid_count)
				engine.add_solid(&state.world, {{x-0.55, 0, z-0.55}, {x+0.55, 3.2, z+0.55}}, id)
			}
		}
	}
	positions := [MAX_ENEMIES]engine.Vec3{{-5, 0, 5}, {0, 0, 7}, {5, 0, 5}}
	for &enemy, index in state.enemies {
		enemy = {position = positions[index], health = 30, phase = .Recovery,
			phase_remaining = 1.5+f32(index)*0.4}
	}
	sync_bodies(state)
}

player_body :: proc(state: ^State) -> engine.Body {
	return {position = state.player.position, radius = PLAYER_RADIUS, height = PLAYER_HEIGHT,
		id = 1, layer = .Actor}
}

enemy_body :: proc(state: ^State, index: int) -> engine.Body {
	return {position = state.enemies[index].position, radius = ENEMY_RADIUS, height = ENEMY_HEIGHT,
		id = u32(index+2), layer = .Actor}
}

sync_bodies :: proc(state: ^State) {
	state.world.actor_count = 0
	if state.player.health > 0 { engine.add_actor(&state.world, player_body(state)) }
	for enemy, index in state.enemies[:state.enemy_count] {
		if enemy.health > 0 { engine.add_actor(&state.world, enemy_body(state, index)) }
	}
}
