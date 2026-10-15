package main

import game "game"

// Called only for a fresh demo run, before its first room/deck is dealt.
// Introduce dice, interruption and scouting in the first run without growing the deck;
// the devices, the Scopa pair and Movimento Ombra ride along on top of it.
configure_demo_tactical_player :: proc(player: ^game.Player, config: game.Tactical_Config) -> bool {
	if !game.configure_tactical(player, config) { return false }
	if config.enabled && !player.deck.combat_active {
		for &card in player.deck.owned[:player.deck.owned_count] {
			if card.definition_id == .Arc_Bolt { card.definition_id = .Fate_Strike }
			else if card.definition_id == .Piercing_Ray { card.definition_id = .Heavy_Blow }
			else if card.definition_id == .Toxic_Wave { card.definition_id = .Battle_Focus }
		}
		// The Scopa pair rides along from the first room: gold, and an easter egg.
		// One Movimento Ombra too: a tactical run always holds its shadow.
		for id in ([5]game.Card_Id{.Shock_Floor, .Tesla_Coil, .Sei_Denari, .Sette_Denari, .Shadow_Step}) {
			present := false
			for card in player.deck.owned[:player.deck.owned_count] { if card.definition_id == id { present = true } }
			if !present { if _, added := game.add_owned_card(&player.deck, id); !added { return false } }
		}
	}
	return game.validate_deck_state(&player.deck)
}
