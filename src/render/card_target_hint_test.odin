package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_card_aim_hint_explains_real_target_queries :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	player.deck.energy = 3
	for sample in ([?]struct {id: game.Card_Id, cell: grid.Position, error: game.Card_Compile_Error, hint: string}{
		{.Strike, {x = 7, y = 6}, .None, ""},
		{.Strike, {x = 5, y = 6}, .Invalid_Target, "NESSUN BERSAGLIO VALIDO"},
		{.Strike, {x = 9, y = 9}, .Target_Out_Of_Range, "FUORI PORTATA"},
		{.Dash, {x = 5, y = 4}, .Invalid_Target, "BERSAGLIO NON ALLINEATO"},
		{.Dash, {x = 6, y = 3}, .Target_Blocked, "LINEA DI TIRO BLOCCATA"},
		{.Dash, {x = 7, y = 6}, .Target_Blocked, "PERCORSO BLOCCATO"},
		// Shove's blocked knockback is optional: damage still resolves. Do not
		// turn that successful query into a false refusal.
		{.Shove, {x = 7, y = 6}, .None, ""},
		{.Pinball, {x = 6, y = 7}, .Target_Too_Heavy, "TROPPO PESANTE PER IL PINBALL"},
	}) {
		card := game.Card_Instance{id = 91, definition_id = sample.id}
		definition, _ := game.card_definition_by_id(sample.id)
		evaluation := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, sample.cell))
		testing.expect_value(t, evaluation.error, sample.error)
		testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, sample.cell)), sample.hint)
	}
	room.pinball.active = true
	testing.expect_value(t, string(tactical_card_aim_hint(&room, {id = 91, definition_id = .Pinball}, true, {x = 7, y = 6})), "UNA PALLA ALLA VOLTA")
}

@(test)
test_card_aim_hint_and_floor_follow_the_wheel_forced_flood_anchor :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	card := game.Card_Instance{id = 93, definition_id = .Flood_Wave}
	player.deck.hand_count, player.deck.hand[0] = 1, card
	player.deck.energy = game.card_energy_cost(&room, card.definition_id)
	update_tactical_view(renderer, &room, {}, false)
	set_flood_aim(renderer, true, true, .North)
	renderer.has_hovered_cell = true
	definition, _ := game.card_definition_by_id(card.definition_id)
	for hovered in ([2]grid.Position{{x = 6, y = 8}, {x = 10, y = 10}}) {
		renderer.hovered_cell = hovered
		anchor := game.flood_card_anchor(&room, card, hovered, true, .North)
		evaluation := game.evaluate_card_targeting(&room, card, game.card_target_request_at(definition, anchor))
		testing.expect_value(t, evaluation.error, game.Card_Compile_Error.None)
		testing.expect(t, anchor.y < player.position.y)
		testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, hovered, renderer.tactical.flood_aim)), "")
		preview: Card_Range_Preview
		prepare_card_range_preview(renderer, &room, card.id, &preview)
		testing.expect(t, preview.has_hover)
		testing.expect_value(t, preview.hover.query.anchor, anchor)
		testing.expect_value(t, preview.hover.error, evaluation.error)
		hits := game.card_hit_enemies(&room, card, &evaluation)
		for mark in preview.hits[:preview.hit_count] {
			locked := false
			for id in hits.ids[:hits.count] { if id == mark.id { locked = true } }
			testing.expect_value(t, mark.locked, locked)
		}
	}
	set_flood_aim(renderer, true, false, .North)
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 10, y = 10}, renderer.tactical.flood_aim)), "FUORI PORTATA")
}

@(test)
test_card_aim_hint_prioritizes_current_energy_and_forgets_old_targets :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	card := game.Card_Instance{id = 91, definition_id = .Strike}
	player.deck.energy = 0
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 9, y = 9})), "ENERGIA INSUFFICIENTE")
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, false, {})), "ENERGIA INSUFFICIENTE")
	player.deck.energy = game.card_energy_cost(&room, card.definition_id)
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, false, {x = 9, y = 9})), "")
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 7, y = 6})), "")
	card.definition_id = .Guard
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 100, y = 100})), "")
	player.tactical.config.vision_size = 3
	card.definition_id = .Arc_Bolt
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 9, y = 6})), "NESSUN BERSAGLIO VALIDO")
	room.phase = .Loot
	testing.expect_value(t, string(tactical_card_aim_hint(&room, card, true, {x = 9, y = 6})), "")
}
