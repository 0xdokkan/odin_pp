package main

import game "game"
import grid "grid"
import level "level"
import render "render"

Spell_Smoke :: enum { None, Firebomb, Dice, Chain, Preview, Dice_Pool, Sunder_Preview, Barrage, Venom }

spell_smoke_is_preview :: proc(kind: Spell_Smoke) -> bool {
	return kind == .Preview || kind == .Sunder_Preview
}

// A small interactive arena exposes the spell and dice cards immediately. This helper
// also gives graphical smokes real cards, targets and authoritative event logs.
prepare_spell_lab :: proc(room: ^game.Room, dice_lab: bool = false) -> bool {
	player, data := room.player, room.level_data
	game.destroy_room(room)
	game.finish_deck_combat(&player.deck)
	for y in 1..<data.tiles.height-1 {
		for x in 1..<data.tiles.width-1 {
			cell: grid.Position = {x, y}
			tile, _ := level.tile_at(data, cell)
			if tile.kind == .Wall { level.set_tile(data, cell, {.Floor}) }
		}
	}
	if !game.initialize_empty_deck(&player.deck) { return false }
	cards := [?]game.Card_Id{.Firebomb, .Fate_Strike, .Chain_Lightning, .Sundering_Blow, .Guard}
	if dice_lab { cards = {.Fate_Strike, .Sundering_Blow, .Prismatic_Barrage, .Twin_Venom, .Guard} }
	for id in cards {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	enemies := [?]game.Enemy_Spawn{
		{position = {5, 3}, health = 12, attack = 2, archetype = .Chaser},
		{position = {6, 2}, health = 12, attack = 2, archetype = .Chaser},
		{position = {7, 3}, health = 12, attack = 2, archetype = .Archer},
		{position = {10, 6}, health = 12, attack = 2, archetype = .Brute},
	}
	created, valid := game.create_room(data, player, {enemies = enemies[:]})
	if !valid { return false }
	room^ = created
	player.position = {3, 3}
	// Five cards fill the hand; sort only the practice hand for stable shortcuts.
	for card, index in player.deck.owned[:player.deck.owned_count] { player.deck.hand[index] = card }
	game.plan_enemy_intents(room)
	return game.validate_deck_state(&player.deck) && game.validate_enemy_intents(room)
}

prepare_spell_smoke :: proc(room: ^game.Room, renderer: ^render.Renderer, kind: Spell_Smoke) -> bool {
	dice_lab := kind == .Barrage || kind == .Venom
	if !prepare_spell_lab(room, dice_lab) { return false }
	if spell_smoke_is_preview(kind) { return true }
	index := 0
	if kind == .Dice { index = 1 }
	if kind == .Chain { index = 2 }
	if kind == .Dice_Pool { index = 3 }
	if kind == .Barrage { index = 2 }
	if kind == .Venom { index = 3 }
	if kind == .Dice {
		// Choose a real RNG state whose next fair die is six to exercise the bonus.
		for seed in u64(1)..=256 {
			candidate := game.make_dice_state(seed)
			staged := candidate
			face, valid := game.roll_d6(&staged)
			if valid && face == 6 { room.player.dice = candidate; break }
		}
	}
	if kind == .Dice_Pool {
		// A committed nine shows both the sum and conditional push without killing
		// the target before the movement portion of the same action resolves.
		for seed in u64(1)..=256 {
			candidate := game.make_dice_state(seed)
			staged := candidate
			roll, valid := game.roll_d6_pool(&staged, 2)
			if valid && roll.total == 9 { room.player.dice = candidate; break }
		}
	}
	if dice_lab {
		for seed in u64(1)..=256 {
			candidate := game.make_dice_state(seed)
			staged := candidate
			roll, valid := game.roll_d6_pool(&staged, 3 if kind == .Barrage else 2)
			matches := game.dice_success_count(&roll) == 2 if kind == .Barrage else
				game.dice_has_pair(&roll) && roll.faces[0] == 4
			if valid && matches { room.player.dice = candidate; break }
		}
	}
	card := room.player.deck.hand[index]
	target := game.entity_target(game.enemy_entity(room.enemies[0].id))
	if kind == .Firebomb { target = game.cell_target({6, 3}) }
	before := render.capture_room_presentation(room)
	played := game.play_card(room, card.id, target)
	if !game.card_play_was_committed(played.result) { return false }
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after) { return false }
	desired := render.Presentation_Cue_Kind.Spell_Impact
	if kind == .Dice || kind == .Dice_Pool || dice_lab { desired = .Dice_Rolled }
	impacts_seen := 0
	for _ in 0..<game.MAX_GAME_EVENTS {
		cue, found := render.active_presentation_cue(&renderer.timeline)
		if !found { return false }
		if cue.kind == desired {
			impacts_seen += 1
			if kind == .Chain && impacts_seen == 1 {
				render.update_renderer_event_timeline(renderer, cue.duration-cue.elapsed)
				continue
			}
			progress: f32 = 0.4
			if kind == .Dice { progress = 0.84 }
			if kind == .Dice_Pool || dice_lab { progress = 0.94 }
			render.update_renderer_event_timeline(renderer, cue.duration*progress)
			return renderer.timeline.update_failures == 0
		}
		render.update_renderer_event_timeline(renderer, cue.duration-cue.elapsed)
	}
	return false
}

finish_spell_smoke :: proc(room: ^game.Room, renderer: ^render.Renderer) -> bool {
	render.update_renderer_event_timeline(renderer, 1000)
	if render.renderer_timeline_is_busy(renderer) || renderer.timeline.update_failures != 0 ||
	   renderer.timeline.dropped_count != 0 || room.recent_events.dropped_count != 0 { return false }
	view := &renderer.timeline.view
	if view.player.health != room.player.health || view.player.position != render.presentation_position(room.player.position) ||
	   view.deck != room.player.deck { return false }
	for enemy in room.enemies {
		actor, found := render.presentation_actor_in_view(view, game.enemy_entity(enemy.id))
		if !found || actor.health != enemy.health || actor.position != render.presentation_position(enemy.position) ||
		   !actor.visible { return false }
	}
	return true
}
