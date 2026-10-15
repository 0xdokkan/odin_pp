package render

import "core:fmt"
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
		// Phase 2: amounts from the catalog, dice from the ladder (d10 at +3).
		{.Poison_Pool, "5 VELENO A CELLA", "SOLO TATTICA", "5 VELENO A CELLA", "SOLO NEMICI / STANZA"},
		{.Wildfire, "4 BRUCIATURA", "SOLO TATTICA", "4 BRUCIATURA A CELLA", "CROCE: +1 A FINESTRA"},
		{.Deflect, "1 RIFLESSO", "SOLO TATTICA", "+1 RIFLESSO", "RIMANDA UN COLPO"},
		{.Coffin, "6 FRECCE", "SOLO TATTICA", "6 FRECCE / CTRL+CLIC", "1 DANNO + 1 STATUS"},
		{.Fate_Dice, "1d10 SU 3 COLPI", "SOLO TATTICA", "1d10 SU 3 COLPI", "UN TIRO A OGNI COLPO"},
		{.Venom_Blade, "1d10 COLPI AVVELENATI", "SOLO TATTICA", "1d10 COLPI AVVELENATI", "2 VELENO A COLPO"},
		// LAZZO: the hits grow from the first (1, +1 a level); a turn costs 1.
		{.Lasso, "COLPI 4, 5, 6...", "SOLO TATTICA", "COLPI 4, 5, 6...", "-1 VITA A OGNI GIRO"},
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

// Seven or eight cards in hand: the cards whose lines would shrink or be cut
// there say them shorter, the rest keep theirs, and the names that would be
// cut there are shorter too (the lab's smoke measures them all at the hand's
// real width: tactical_card_text_misfit); the classic face of a
// tactical-only card reads the catalog like the hand.
@(test)
test_card_descriptions_shorten_for_a_narrow_hand :: proc(t: ^testing.T) {
	cases := [?]struct {
		id: game.Card_Id,
		level: i32,
		first, second: string,
	}{
		{.Shadow_Step, 0, "OMBRA 4s", "MONDO FERMO"},
		{.Poison_Pool, 1, "3 VELENO", "A OGNI CELLA"},
		{.Wildfire, 2, "3 BRUCIATURA", "CRESCE A CROCE"},
		{.Deflect, 0, "+1 RIFLESSO", "IL COLPO TORNA"},
		{.Coffin, 1, "4 FRECCE", "CTRL+CLIC"},
		{.Fate_Dice, 3, "1d10 A COLPO", "PER 3 COLPI"},
		{.Venom_Blade, game.MAX_DICE_UPGRADE_LEVEL, "1d20 COLPI", "2 VELENO L'UNO"},
		{.Lasso, 0, "COLPI 1, 2...", "-1 VITA A GIRO"},
		{.Fishing_Rod, 0, "1 PESCA", "CIBO d4 O CARTA"},
		{.Shock_Floor, 0, "1d4 COLPI + BERS.", "1 DANNO / 3X3"},
		{.Tesla_Coil, 0, "8 / DIST. DANNI", "CAMPO USA 4 TESLA"},
	}
	for row in cases {
		first, second, found := gothic_card_narrow_lines({definition_id = row.id, upgrade_level = row.level}, true)
		testing.expectf(t, found, "%v has no narrow lines", row.id)
		testing.expect_value(t, string(first), row.first)
		testing.expect_value(t, string(second), row.second)
	}
	for id in ([?]game.Card_Id{.Strike, .Guard}) {
		_, _, found := gothic_card_narrow_lines({definition_id = id}, true)
		testing.expectf(t, !found, "%v shortens its lines", id)
	}
	// The narrow names, an upgrade after them; a wide card, and the cards
	// whose names hold, keep the whole name.
	names := [?]struct {
		id: game.Card_Id,
		name: string,
	}{{.Shadow_Step, "Ombra"}, {.Poison_Pool, "Pozza"}, {.Fate_Dice, "Dado"}, {.Venom_Blade, "Lama"}, {.Fishing_Rod, "Canna"}}
	for row in names {
		definition, _ := game.card_definition_by_id(row.id, true)
		testing.expect_value(t, string(tactical_card_face_title({definition_id = row.id}, definition, 109)), row.name)
		testing.expect_value(t, string(tactical_card_face_title({definition_id = row.id, upgrade_level = 2}, definition, 109)), fmt.tprintf("%s +2", row.name))
		testing.expect_value(t, string(tactical_card_face_title({definition_id = row.id}, definition, 166)), definition.name)
	}
	for id in ([?]game.Card_Id{.Lasso, .Wildfire, .Deflect, .Coffin}) {
		_, found := gothic_card_narrow_name(id)
		testing.expectf(t, !found, "%v shortens its name", id)
	}
	for id in game.Card_Id {
		if id == .Count || !game.card_requires_tactical(id) { continue }
		card := game.Card_Instance{definition_id = id, upgrade_level = 2}
		face_first, face_second := card_detail_lines(card)
		first, second := gothic_card_lines(card)
		testing.expect_value(t, string(face_first), string(first))
		testing.expect_value(t, string(face_second), "SOLO TATTICA")
		testing.expect_value(t, string(second), "SOLO TATTICA")
	}
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
