package render

import "core:fmt"
import game "../game"

// Le cifre della preview provengono dagli stessi template del resolver.
card_upgrade_preview :: proc(card: game.Card_Instance) -> cstring {
	if !game.card_can_upgrade(card) {
		if card.upgrade_level >= game.MAX_CARD_UPGRADE_LEVEL {
			return "MAX UPGRADE"
		}
		return "NO UPGRADE AVAILABLE"
	}
	definition, _ := game.card_definition_by_id(card.definition_id)
	line := ""
	for index in 0..<definition.effect_count {
		template := definition.effects[index]
		if template.amount_per_upgrade == 0 {
			continue
		}
		label := ""
		switch template.kind {
		case .Damage: label = "DAMAGE"
		case .Heal: label = "HEAL"
		case .Gain_Gold: label = "GOLD"
		case .Draw_Cards: label = "DRAW"
		case .Discard_Cards: label = "DISCARD"
		case .Create_Card: label = "CREATE"
		case .Apply_Status: label = game.status_kind_name(template.status)
		case .Add_Reaction_Binding: label = "COUNTER"
		case .Move, .Remove_Status:
		}
		before := game.card_effect_amount(template, card.upgrade_level)
		after := game.card_effect_amount(template, card.upgrade_level+1)
		separator := "  |  " if len(line) > 0 else ""
		line = fmt.tprintf("%s%s%s %d -> %d", line, separator, label, before, after)
	}
	return fmt.ctprintf("%s", line)
}
