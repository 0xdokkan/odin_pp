package render

import "core:fmt"
import game "../game"

tactical_card_target_label :: proc(definition: game.Card_Definition) -> cstring {
	if definition.tactical && definition.id == .Toxic_Wave { return "VISIBILI / RAGGIO 2" }
	if !game.card_requires_spatial_target(definition) {
		for index in 0..<definition.effect_count { if definition.effects[index].target == .Each_Enemy { return "TUTTI I NEMICI" } }
		return "SU DI TE" if definition.targeting.rule == .Self || definition.targeting.rule == .Player else "SUPPORTO"
	}
	if definition.targeting.cast_range.minimum == definition.targeting.cast_range.maximum { return fmt.ctprintf("RAGGIO %d", definition.targeting.cast_range.maximum) }
	return fmt.ctprintf("RAGGIO %d-%d", definition.targeting.cast_range.minimum, definition.targeting.cast_range.maximum)
}

// Hand and inspector share the effective catalog used by gameplay and upgrade previews.
// Mode-specific rules and dice formulas remain explicit; ordinary amounts, durations
// and ranges follow the selected definition instead of a second balance table.
gothic_card_lines :: proc(card: game.Card_Instance, tactical: bool = false) -> (cstring, cstring) {
	u := card.upgrade_level
	d, found := game.card_definition_by_id(card.definition_id, tactical)
	if !found { return "", "" }
	a := game.card_effect_amount(d.effects[0], u) if d.effects[0].base_amount > 0 else 0
	b := game.card_effect_amount(d.effects[1], u) if d.effects[1].base_amount > 0 else 0
	if tactical {
		switch card.definition_id {
		case .Strike: return fmt.ctprintf("%d DANNI / +2 ESPOSTO", a), "RECUPERO O STORDITO"
		case .Arc_Bolt: return fmt.ctprintf("%d DANNI", a), "TIRO RAPIDO"
		case .Piercing_Ray: return fmt.ctprintf("%d DANNI IN LINEA", a), "SOLO CELLE VISIBILI"
		case .Cross_Slash: return fmt.ctprintf("%d DANNI A CROCE", a), "SOLO CELLE VISIBILI"
		case .Guard, .Purifying_Guard:
			return fmt.ctprintf("%d SCUDO / %ds", a, d.effects[0].duration), "RIMUOVE VELENO" if card.definition_id == .Purifying_Guard else "ABILITA BLOCK / PARRY"
		case .Thorn_Coat: return fmt.ctprintf("%d SPINE / %ds", a, d.effects[0].duration), "ABILITA DEFLECT"
		case .Counter_Rune: return fmt.ctprintf("CONTRATTACCO %d", a), fmt.ctprintf("%d CARICHE / RETAIN", d.effects[0].charges)
		case .Battle_Focus: return fmt.ctprintf("PESCA %d / ESPLORA", a), fmt.ctprintf("VISTA: %ds / MAX %d", d.effects[1].duration, game.MAX_TACTICAL_VISION)
		case .Spark_Forge: return fmt.ctprintf("CREA %d SPARK", a), "TEMPORANEE / ENERGIA 0"
		case .Shove: return fmt.ctprintf("SPINGE %d / POI COLPISCE", d.effects[0].movement_distance), fmt.ctprintf("%d DANNO / ANCHE BOMBE", b)
		case .Dash: return fmt.ctprintf("MUOVI 1-%d / SCUDO %d", d.targeting.cast_range.maximum, a), fmt.ctprintf("SCUDO PRIMA / %ds", d.effects[0].duration)
		case .Heavy_Blow: return fmt.ctprintf("%d DANNI + STORDISCE", a), "INTERROMPE L'INTENTO"
		case .Venom_Needle: return fmt.ctprintf("%d DANNO + %d VELENO", a, b), fmt.ctprintf("VELENO: %ds", d.effects[1].duration)
		case .Toxic_Wave: return fmt.ctprintf("APPLICA %d VELENO", a), fmt.ctprintf("DURATA %ds", d.effects[0].duration)
		case .Caustic_Bloom: return fmt.ctprintf("%d VELENO NEL %dX%d", a, d.targeting.radius*2+1, d.targeting.radius*2+1), fmt.ctprintf("DURATA %ds", d.effects[0].duration)
		case .Volatile_Study: return fmt.ctprintf("CREA %d SPARK", a), fmt.ctprintf("PESCA %d / EXHAUST", b)
		case .Afterimage: return "SCHIVA SENZA RECUPERO", fmt.ctprintf("%d SCUDO SE MUOVI / %ds", a, d.effects[0].duration)
		case .Chain_Lightning: return fmt.ctprintf("%d DANNI / NEMICO", a), fmt.ctprintf("%d VISIBILI / SALTO %d", game.MAX_SPELL_TARGETS, game.SPELL_BOUNCE_RANGE)
		case .Titan_Grip, .Storm_Crown, .Shock_Floor, .Tesla_Coil, .Firebomb, .Calculated_Risk, .Spark, .Grappling_Hook,
		     .Fate_Strike, .Sundering_Blow, .Prismatic_Barrage, .Twin_Venom, .Count:
		}
	}
	switch card.definition_id {
	case .Strike, .Arc_Bolt: return fmt.ctprintf("%d DANNI", a), ""
	case .Piercing_Ray: return fmt.ctprintf("%d DANNI IN LINEA", a), ""
	case .Cross_Slash: return fmt.ctprintf("%d DANNI A CROCE", a), ""
	case .Firebomb: return fmt.ctprintf("%d DANNI NEL %dX%d", a, d.targeting.radius*2+1, d.targeting.radius*2+1), "ACCENDE I BARILI"
	case .Guard: return fmt.ctprintf("%d SCUDO", a), fmt.ctprintf("DURATA %d PULSE", d.effects[0].duration)
	case .Toxic_Wave: return fmt.ctprintf("APPLICA %d VELENO", a), fmt.ctprintf("DURATA %d PULSE", d.effects[0].duration)
	case .Thorn_Coat: return fmt.ctprintf("%d SPINE", a), fmt.ctprintf("DURATA %d PULSE", d.effects[0].duration)
	case .Afterimage: return fmt.ctprintf("%d AFTERIMAGE", a), fmt.ctprintf("DURATA %d PULSE", d.effects[0].duration)
	case .Counter_Rune: return fmt.ctprintf("CONTRATTACCO %d", a), fmt.ctprintf("%d CARICHE / RETAIN", d.effects[0].charges)
	case .Battle_Focus: return fmt.ctprintf("PESCA %d", a), "EXHAUST / ETHEREAL"
	case .Calculated_Risk: return fmt.ctprintf("PESCA %d", a), fmt.ctprintf("SCARTA %d", b)
	case .Spark_Forge: return fmt.ctprintf("CREA %d SPARK", a), "TEMPORANEA"
	case .Spark: return fmt.ctprintf("%d DANNI", a), "TEMPORANEA"
	case .Shove: return fmt.ctprintf("%d DANNO / SPINTA %d", a, d.effects[1].movement_distance), ""
	case .Dash: return fmt.ctprintf("MUOVI %d-%d CELLE", d.targeting.cast_range.minimum, d.targeting.cast_range.maximum), "ATTRAVERSA I PERICOLI"
	case .Grappling_Hook: return fmt.ctprintf("%d DANNO", a), "ATTIRA ADIACENTE"
	case .Heavy_Blow: return fmt.ctprintf("%d DANNI", a), ""
	case .Venom_Needle: return fmt.ctprintf("%d DANNO + %d VELENO", a, b), fmt.ctprintf("VELENO: %d PULSE", d.effects[1].duration)
	case .Caustic_Bloom: return fmt.ctprintf("%d VELENO NEL %dX%d", a, d.targeting.radius*2+1, d.targeting.radius*2+1), fmt.ctprintf("DURATA %d PULSE", d.effects[0].duration)
	case .Purifying_Guard: return fmt.ctprintf("%d SCUDO / %d PULSE", a, d.effects[0].duration), "RIMUOVE VELENO"
	case .Volatile_Study: return fmt.ctprintf("CREA %d SPARK", a), fmt.ctprintf("PESCA %d / EXHAUST", b)
	case .Fate_Strike: return fmt.ctprintf("%d + D6 DANNI", a), fmt.ctprintf("6: RIMBALZO %d", 3+u)
	case .Chain_Lightning: return fmt.ctprintf("%d DANNI / NEMICO", a), fmt.ctprintf("FINO A %d / SALTO %d", game.MAX_SPELL_TARGETS, game.SPELL_BOUNCE_RANGE)
	case .Sundering_Blow: return fmt.ctprintf("2D6 + %d DANNI", u), "TIRO 8+: SPINTA 1"
	case .Prismatic_Barrage: return fmt.ctprintf("3D6: 4+ = %d DANNI", 3+u), "1-3: 1 SCUDO / DADO"
	case .Twin_Venom: return fmt.ctprintf("MAX(2D6) + %d DANNI", 1+u), "COPPIA: 2 VELENO"
	case .Shock_Floor: return "D4 SCARICHE / D4 BERSAGLI", fmt.ctprintf("%d DANNO / AREA 3X3", a)
	case .Tesla_Coil: return fmt.ctprintf("%d / DISTANZA DANNI", a), "MAX 4 / OGGETTO ATTIVO"
	case .Titan_Grip: return fmt.ctprintf("%d DANNI / LANCIA 2", a), "INTERROMPE / STORDISCE 1s"
	case .Storm_Crown: return fmt.ctprintf("%d DANNI / 3 BERSAGLI", a), "LEGGENDARIA / RIMBALZO 3"
	case .Count: return "", ""
	}
	return "", ""
}

