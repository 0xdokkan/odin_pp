package render

import "core:testing"
import game "../game"
import view "../view"

@(test)
test_relic_bar_yields_to_a_visible_raised_card_and_blocks_when_uncovered :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540}
	player := game.Player{stats = {max_health = 10}, health = 10}
	player.deck.combat_active = true
	player.deck.hand_count = 8
	for index in 0..<player.deck.hand_count {
		player.deck.hand[index] = {id = u32(index+1), definition_id = .Strike}
	}
	room := game.Room{player = &player, phase = .Combat}
	covered := view.Vec2{120, 450}
	uncovered := view.Vec2{20, 450}
	raised_card_id := player.deck.hand[0].id

	for definition in game.RELIC_DEFINITIONS {
		testing.expect(t, game.acquire_relic(&player, definition.id))
		if player.relics.count < 4 {continue}
		testing.expect(t, relic_bar_contains_point(&renderer, &room, covered),
			"with the card resting, this point belongs to the visible relic bar")
		index, over_card := hand_card_at_point(&renderer, &player.deck, covered, raised_card_id)
		testing.expect(t, over_card && index == 0)
		testing.expect(t, !relic_bar_contains_point(&renderer, &room, covered, raised_card_id),
			"the raised card is drawn above the relic and must retain hover and clicks")
		testing.expect(t, relic_bar_contains_point(&renderer, &room, uncovered, raised_card_id),
			"an uncovered relic still blocks card targeting through the HUD")
		testing.expect(t, relic_bar_contains_point(&renderer, &room, covered, 999),
			"a card no longer present in the hand cannot hide the relic bar")
	}
}
