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
		{.Venom_Needle, "4 DANNO + 1 VELENO", "DANNO A OGNI SUA AZIONE", "4 DANNO + 2 VELENO", "DANNO A OGNI SUA AZIONE"},
		{.Toxic_Wave, "APPLICA 4 VELENO", "DANNO A OGNI SUA AZIONE", "APPLICA 4 VELENO", "DANNO A OGNI SUA AZIONE"},
		{.Caustic_Bloom, "5 VELENO NEL 3X3", "DANNO A OGNI SUA AZIONE", "5 VELENO NEL 3X3", "DANNO A OGNI SUA AZIONE"},
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
		// Each card names the dice of its level: an upgrade changes only the die.
		first, second := gothic_card_lines({definition_id = .Sundering_Blow, upgrade_level = 2}, tactical)
		testing.expect_value(t, string(first), "2d8 DANNI")
		testing.expect_value(t, string(second), "TIRO 8+: SPINTA 1")
		first, second = gothic_card_lines({definition_id = .Twin_Venom, upgrade_level = 2}, tactical)
		testing.expect_value(t, string(first), "MAX(2d8) + 1 DANNI")
		testing.expect_value(t, string(second), "COPPIA: 2 VELENO")
		first, second = gothic_card_lines({definition_id = .Fate_Strike}, tactical)
		testing.expect_value(t, string(first), "2 + 1d4 DANNI")
		testing.expect_value(t, string(second), "4: RIMBALZO 3")
		first, second = gothic_card_lines({definition_id = .Fate_Strike, upgrade_level = game.MAX_DICE_UPGRADE_LEVEL}, tactical)
		testing.expect_value(t, string(first), "2 + 1d20 DANNI")
		testing.expect_value(t, string(second), "20: RIMBALZO 3")
		first, second = gothic_card_lines({definition_id = .Prismatic_Barrage, upgrade_level = 3}, tactical)
		testing.expect_value(t, string(first), "3d10: 4+ = 3 DANNI")
		testing.expect_value(t, string(second), "1-3: 1 SCUDO / DADO")
		first, second = gothic_card_lines({definition_id = .Shock_Floor, upgrade_level = 4}, tactical)
		testing.expect_value(t, string(first), "1d12 SCARICHE / 1d12 BERSAGLI")
		testing.expect_value(t, string(second), "1 DANNO / TRAPPOLA 3X3")
		definition, _ := game.card_definition_by_id(.Toxic_Wave, tactical)
		expected := "VISIBILI / RAGGIO 2" if tactical else "TUTTI I NEMICI"
		testing.expect_value(t, string(tactical_card_target_label(definition)), expected)
	}
	// The classic hand shares those texts; the floor keeps its short form.
	first, second := card_detail_lines({definition_id = .Fate_Strike, upgrade_level = 1})
	testing.expect_value(t, string(first), "2 + 1d6 DANNI")
	testing.expect_value(t, string(second), "6: RIMBALZO 3")
	first, second = card_detail_lines({definition_id = .Shock_Floor, upgrade_level = game.MAX_DICE_UPGRADE_LEVEL})
	testing.expect_value(t, string(first), "1d20 COLPI + BERS.")
	testing.expect_value(t, string(second), "1 DANNO / 3X3")
	lines := dice_card_detail_lines({definition_id = .Prismatic_Barrage, upgrade_level = 2})
	testing.expect_value(t, string(lines[0]), "3d8: 4+ = 3 DANNI")
	testing.expect_value(t, string(lines[2]), "SCUDO PRIMA / 2P")
	testing.expect_value(t, string(lines[3]), "RAGGIO 1-3 / VISTA")
}

// The path preview's odds follow the die of the card's level.
@(test)
test_dice_spell_previews_follow_the_level_die :: proc(t: ^testing.T) {
	lines, count := dice_spell_preview_lines({definition_id = .Fate_Strike, upgrade_level = 5})
	testing.expect_value(t, count, 1)
	testing.expect_value(t, string(lines[0]), "1d20: 1-20 ALLA PARI / RIMBALZO SU 20 (1/20)")
	lines, count = dice_spell_preview_lines({definition_id = .Sundering_Blow})
	testing.expect_value(t, count, 1)
	testing.expect_value(t, string(lines[0]), "2d4: 2-8 / 8+: SPINTA 1 (1/16) / RAGGIO 1-2")
	lines, _ = dice_spell_preview_lines({definition_id = .Sundering_Blow, upgrade_level = 1})
	testing.expect_value(t, string(lines[0]), "2d6: 2-12 / 8+: SPINTA 1 (15/36) / RAGGIO 1-2")
	lines, count = dice_spell_preview_lines({definition_id = .Prismatic_Barrage, upgrade_level = 1})
	testing.expect_value(t, count, 3)
	testing.expect_value(t, string(lines[0]), "3d6: OGNI 4+ COLPISCE (50%) / RAGGIO 1-3 / VISTA")
	lines, _ = dice_spell_preview_lines({definition_id = .Prismatic_Barrage, upgrade_level = 5})
	testing.expect_value(t, string(lines[0]), "3d20: OGNI 4+ COLPISCE (85%) / RAGGIO 1-3 / VISTA")
	lines, count = dice_spell_preview_lines({definition_id = .Twin_Venom, upgrade_level = 3})
	testing.expect_value(t, count, 3)
	testing.expect_value(t, string(lines[1]), "COPPIA (1/10): 2 VELENO")
	_, count = dice_spell_preview_lines({definition_id = .Shock_Floor})
	testing.expect_value(t, count, 0)
	_, count = dice_spell_preview_lines({definition_id = .Strike})
	testing.expect_value(t, count, 0)
}
