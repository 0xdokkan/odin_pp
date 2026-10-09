package render

import "core:testing"
import game "../game"
import view "../view"

@(test)
test_tactical_relics_remain_visible_and_interactive_with_a_full_hand :: proc(t: ^testing.T) {
	renderer := Renderer{canvas_width = 960, canvas_height = 540, tactical = {enabled = true}}
	player := game.Player{}
	player.deck.combat_active = true
	player.deck.hand_count = game.MAX_HAND_CARDS
	for &card, i in player.deck.hand { card = {id = u32(i+1), definition_id = .Strike} }
	for definition in game.RELIC_DEFINITIONS { testing.expect(t, game.acquire_relic(&player, definition.id)) }
	room := game.Room{player = &player, phase = .Combat}
	bar := relic_bar_bounds(&renderer, player.relics.count)
	point := view.Vec2{bar.x+5, bar.y+5}
	testing.expect(t, relic_bar_contains_point(&renderer, &room, point, player.deck.hand[0].id))
	_, card_hit := hand_card_at_point(&renderer, &player.deck, point, player.deck.hand[0].id)
	testing.expect(t, !card_hit)
	testing.expect(t, bar.y+bar.height < renderer.canvas_height-TACTICAL_HAND_HEIGHT)
	for index in 0..<player.deck.hand_count {
		card := tactical_hand_card_bounds(&renderer, index, player.deck.hand_count)
		testing.expect(t, !relic_bar_contains_point(&renderer, &room, {card.x+5, card.y+5}))
	}
}

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
