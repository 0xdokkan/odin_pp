package game

import "core:testing"

@(test)
test_tactical_card_catalog_has_bounded_nonzero_time_costs :: proc(t: ^testing.T) {
	for index in 0..<int(Card_Id.Count) {
		id := Card_Id(index)
		definition, found := card_definition_by_id(id, true)
		testing.expect(t, found)
		cost := tactical_card_time_cost(id)
		// Movimento Ombra stands outside the window: its four seconds freeze
		// the world instead of spending it. The Canna da Pesca fishes a
		// cleared room, which has no window.
		if id == .Shadow_Step || id == .Fishing_Rod { testing.expect_value(t, cost, f32(0)); continue }
		testing.expect(t, cost >= 1 && cost <= 4, definition.name)
	}
	testing.expect_value(t, tactical_card_time_cost(.Count), f32(0))
	testing.expect_value(t, tactical_card_time_cost(.Shadow_Step), f32(0))
	// Creating zero-energy Spark cards must not create zero-time actions.
	testing.expect_value(t, tactical_card_time_cost(.Spark), f32(1))
	testing.expect(t, tactical_card_time_cost(.Guard) < tactical_card_time_cost(.Strike))
	testing.expect(t, tactical_card_time_cost(.Heavy_Blow) < tactical_card_time_cost(.Firebomb))
}
