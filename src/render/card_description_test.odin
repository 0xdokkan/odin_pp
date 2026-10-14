package render

import "core:testing"
import game "../game"

@(test)
test_card_descriptions_preserve_classic_and_tactical_rules :: proc(t: ^testing.T) {
	cases := [?]struct {
		id: game.Card_Id,
		classic_first, classic_second: string,
		tactical_first, tactical_second: string,
	}{
		{.Arc_Bolt, "6 DANNI", "", "5 DANNI", "TIRO RAPIDO"},
		{.Guard, "6 SCUDO", "DURATA 3 PULSE", "7 SCUDO / 2s", "ABILITA BLOCK / PARRY"},
		{.Shove, "4 DANNO / SPINTA 1", "", "SPINGE 1 / POI COLPISCE", "4 DANNO / ANCHE BOMBE"},
		{.Dash, "MUOVI 1-3 CELLE", "ATTRAVERSA I PERICOLI", "MUOVI 1-4 / SCUDO 2", "SCUDO PRIMA / 2s"},
		{.Venom_Needle, "4 DANNO + 1 VELENO", "VELENO: 3 PULSE", "4 DANNO + 2 VELENO", "VELENO: 2s"},
		{.Volatile_Study, "CREA 1 SPARK", "PESCA 4 / EXHAUST", "CREA 1 SPARK", "PESCA 5 / EXHAUST"},
		{.Afterimage, "4 AFTERIMAGE", "DURATA 4 PULSE", "SCHIVA SENZA RECUPERO", "4 SCUDO SE MUOVI / 4s"},
		{.Battle_Focus, "PESCA 2", "EXHAUST / ETHEREAL", "PESCA 2 / ESPLORA", "VISTA: 3s / MAX 9"},
		{.Shadow_Step, "OMBRA 4s", "SOLO TATTICA", "OMBRA 4s / MONDO FERMO", "INTANGIBILE / SOLO PASSI"},
	}
	for row in cases {
		card := game.Card_Instance{definition_id = row.id, upgrade_level = 3}
		first, second := gothic_card_lines(card)
		testing.expect_value(t, string(first), row.classic_first)
		testing.expect_value(t, string(second), row.classic_second)
		first, second = gothic_card_lines(card, true)
		testing.expect_value(t, string(first), row.tactical_first)
		testing.expect_value(t, string(second), row.tactical_second)
	}
}

@(test)
test_card_descriptions_keep_special_dice_rules_and_visibility :: proc(t: ^testing.T) {
	// Dice results use custom resolvers: the catalog's minimum damage is not
	// the rolled bonus. Both presentation modes must keep that distinction.
	modes := [?]bool{false, true}
	for tactical in modes {
		first, second := gothic_card_lines({definition_id = .Sundering_Blow, upgrade_level = 2}, tactical)
		testing.expect_value(t, string(first), "2D6 + 2 DANNI")
		testing.expect_value(t, string(second), "TIRO 8+: SPINTA 1")
		first, second = gothic_card_lines({definition_id = .Twin_Venom, upgrade_level = 2}, tactical)
		testing.expect_value(t, string(first), "MAX(2D6) + 3 DANNI")
		testing.expect_value(t, string(second), "COPPIA: 2 VELENO")
		definition, _ := game.card_definition_by_id(.Toxic_Wave, tactical)
		expected := "VISIBILI / RAGGIO 2" if tactical else "TUTTI I NEMICI"
		testing.expect_value(t, string(tactical_card_target_label(definition)), expected)
	}
}
