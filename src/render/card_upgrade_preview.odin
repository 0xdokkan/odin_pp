package render

import "core:fmt"
import game "../game"

// Le cifre della preview provengono dagli stessi template del resolver.
card_upgrade_preview :: proc(card: game.Card_Instance, tactical: bool = false) -> cstring {
	if !game.card_can_upgrade(card) {
		if card.upgrade_level >= game.card_max_upgrade_level(card.definition_id) {
			return "MAX UPGRADE"
		}
		return "NO UPGRADE AVAILABLE"
	}
	// A dice card's upgrade changes only its die.
	if game.card_dice_count(card.definition_id) > 0 {
		return fmt.ctprintf("%s -> %s", die_label(game.card_die_sides(card.definition_id, card.upgrade_level)),
			die_label(game.card_die_sides(card.definition_id, card.upgrade_level+1)))
	}
	definition, _ := game.card_definition_by_id(card.definition_id, tactical)
	line := ""
	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		if template.amount_per_upgrade == 0 {
			continue
		}
		label := ""
		switch template.kind {
		case .Damage, .Deploy_Device: label = "DAMAGE"
		case .Heal: label = "HEAL"
		case .Gain_Gold: label = "GOLD"
		case .Gain_Energy: label = "ENERGY"
		case .Draw_Cards: label = "DRAW"
		case .Discard_Cards: label = "DISCARD"
		case .Create_Card: label = "CREATE"
		case .Apply_Status: label = game.status_kind_name(template.status)
		case .Add_Reaction_Binding: label = "COUNTER"
		case .Move, .Remove_Status, .Enter_Shadow:
		}
		before := game.card_effect_amount(template, card.upgrade_level)
		after := game.card_effect_amount(template, card.upgrade_level+1)
		separator := "  |  " if len(line) > 0 else ""
		line = fmt.tprintf("%s%s%s %d -> %d", line, separator, label, before, after)
	}
	return fmt.ctprintf("%s", line)
}
