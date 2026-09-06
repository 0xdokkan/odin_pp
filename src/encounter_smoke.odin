package main

import game "game"
import render "render"

Encounter_Smoke :: enum { Escort, Miniboss, Furnace }

prepare_encounter_smoke :: proc(room: ^game.Room, renderer: ^render.Renderer, kind: Encounter_Smoke) -> (card_id: u32, ok: bool) {
	player, data := room.player, room.level_data
	game.destroy_room(room)
	game.finish_deck_combat(&player.deck)
	enemies := [?]game.Enemy_Spawn{
		{position = {6, 4}, health = 7, attack = 1, archetype = .Custodian},
		{position = {8, 4}, health = 7, attack = 2, archetype = .Archer},
	}
	objects := [?]game.Grid_Object_Spawn{
		{kind = .Barrel, position = {5, 4}},
		{kind = .Barrel, position = {8, 6}},
		{kind = .Ice_Block, position = {5, 6}},
	}
	content := game.Room_Content{enemies = enemies[:], objects = objects[:], encounter_kind = .Escort}
	if kind == .Miniboss {
		enemies[0] = {position = {4, 6}, health = 30, attack = 2, archetype = .Demolitionist}
		enemies[1] = {position = {10, 6}, health = 6, attack = 2, archetype = .Bomber}
		content.encounter_kind = .Demolitionist
	} else {
		content.modifier = {kind = .Furnace, cell_count = 6, activation_pulse = 2, damage = game.ROOM_HAZARD_DAMAGE}
		for index in 0..<content.modifier.cell_count {
			content.modifier.cells[index] = {index+1, 6}
		}
	}
	created, valid := game.create_room(data, player, content)
	if !valid { return }
	room^ = created
	player.position = {4, 4}
	if kind == .Miniboss {
		room.enemies[0].health = 15
		game.update_demolitionist_phase(&room.enemies[0])
		room.enemies[0].boss_cycle = 2
		if !game.spawn_bomb(room, game.enemy_entity(room.enemies[0].id), {3, 4}, &room.recent_events) { return }
	} else if kind == .Escort {
		// Keep the barrel's landing cell open while the support pair stays linked.
		room.enemies[0].position = {7, 4}
		card, added := game.create_temporary_card(&player.deck, .Shove)
		if !added { return }
		card_id = card.id
	} else {
		player.position = {3, 6}
		room.pulse_count = 1
	}
	game.plan_enemy_intents(room)
	if !game.validate_enemy_intents(room) { return }
	if kind == .Furnace {
		before := render.capture_room_presentation(room)
		game.wait_player_turn(room)
		after := render.capture_room_presentation(room)
		if !render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after) { return }
		for _ in 0..<2048 {
			cue, active := render.active_presentation_cue(&renderer.timeline)
			if active && cue.started && cue.kind == .Room_Hazard_Triggered {
				render.update_renderer_event_timeline(renderer, 0.08)
				return card_id, true
			}
			if !active { return }
			render.update_renderer_event_timeline(renderer, 0.005)
		}
		return
	}
	return card_id, true
}
