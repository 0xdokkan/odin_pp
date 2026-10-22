package run

import game "../game"

// Wheel ticks select every card, even unaffordable ones. The first tick always
// starts at the first card, then each further notch wraps at either edge.
expedition_cycle_hand :: proc(cards: ^Card_Interaction_State, deck: ^game.Deck_State, wheel: f32) {
	if cards == nil || deck == nil || deck.hand_count <= 0 || wheel == 0 { return }
	steps := max(1, int(abs(wheel)))
	direction := -1 if wheel > 0 else 1
	if cards.placing {
		cards.placement_direction = game.Move_Direction((int(cards.placement_direction)+direction*(steps%4)+4)%4)
		return
	}
	index, found := game.hand_card_index_by_id(deck, cards.selected_card_id)
	if !found { index = 0; steps -= 1 }
	index = (index+direction*(steps%deck.hand_count)+deck.hand_count)%deck.hand_count
	cards.selected_card_id = deck.hand[index].id
	cards.dragged_card_id, cards.hovered_card_id = 0, 0
}
