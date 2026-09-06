package main

import game "game"

prepare_tactics_smoke :: proc(room: ^game.Room) -> bool {
	player := room.player
	data := room.level_data
	game.destroy_room(room)
	game.finish_deck_combat(&player.deck)
	enemies := [?]game.Enemy_Spawn{
		{position = {6, 2}, health = 5, attack = 2, archetype = .Bomber},
		{position = {2, 4}, health = 9, attack = 3, archetype = .Brute},
		{position = {10, 4}, health = 5, attack = 2, archetype = .Chaser},
	}
	objects := [?]game.Grid_Object_Spawn{
		{kind = .Barrel, position = {3, 2}}, {kind = .Barrel, position = {5, 4}},
		{kind = .Ice_Block, position = {6, 6}}, {kind = .Fire, position = {5, 2}},
	}
	created, ok := game.create_room(data, player, {enemies = enemies[:], objects = objects[:]})
	if !ok {
		return false
	}
	room^ = created
	player.position = {4, 4}
	room.pulse_count = 2
	room.objects[0].detonation_pulse = 3
	if !game.spawn_bomb(room, game.enemy_entity(1), {8, 4}, &room.recent_events) {
		return false
	}
	room.objects[len(room.objects)-1].detonation_pulse = 4
	room.enemies[1].recovery_pulses = 1
	game.plan_enemy_intents(room)
	return game.validate_enemy_intents(room)
}
