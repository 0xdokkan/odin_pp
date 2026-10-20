package run

import game "../game"
import grid "../engine/grid"
import level "../level"

// A small 3D practice arena exposes the spell and dice cards immediately.
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
	practice := player.tactical.config
	practice.vision_size = 0
	practice.timed_actions = true
	if !game.configure_tactical_room(room, practice) { return false }
	return game.validate_deck_state(&player.deck) && game.validate_enemy_intents(room)
}
