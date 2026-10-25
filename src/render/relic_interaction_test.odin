package render

import "core:testing"
import game "../game"
import view "../engine/view"

@(test)
test_tactical_relics_remain_visible_and_interactive_with_a_full_hand :: proc(t: ^testing.T) {
	renderer := new_clone(Renderer{canvas_width = 960, canvas_height = 540})
	defer free(renderer)
	player := game.Player{}
	player.deck.combat_active = true
	player.deck.hand_count = game.MAX_HAND_CARDS
	for &card, i in player.deck.hand { card = {id = u32(i+1), definition_id = .Strike} }
	for definition in game.RELIC_DEFINITIONS { testing.expect(t, game.acquire_relic(&player, definition.id)) }
	room := game.Room{player = &player, phase = .Combat}
	bar := relic_bar_bounds(renderer, player.relics.count)
	point := view.Vec2{bar.x+5, bar.y+5}
	testing.expect(t, relic_bar_contains_point(renderer, &room, point, player.deck.hand[0].id))
	_, card_hit := hand_card_at_point(renderer, &player.deck, point, player.deck.hand[0].id)
	testing.expect(t, !card_hit)
	testing.expect(t, bar.y+bar.height < renderer.canvas_height-TACTICAL_HAND_HEIGHT)
	for index in 0..<player.deck.hand_count {
		card := tactical_hand_card_bounds(renderer, index, player.deck.hand_count)
		testing.expect(t, !relic_bar_contains_point(renderer, &room, {card.x+5, card.y+5}))
	}
}
