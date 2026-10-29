package render

import "core:fmt"
import game "../game"

@(private)
tactical_card_target_label :: proc(definition: game.Card_Definition) -> cstring {
	if definition.id == .Toxic_Wave { return "VISIBILI / RAGGIO 2" }
	if !game.card_requires_spatial_target(definition) {
		for index in 0..<definition.effect_count { if definition.effects[index].target == .Each_Enemy { return "TUTTI I NEMICI" } }
		return "SU DI TE" if definition.targeting.rule == .Self || definition.targeting.rule == .Player else "SUPPORTO"
	}
	if definition.targeting.cast_range.minimum == definition.targeting.cast_range.maximum { return fmt.ctprintf("RAGGIO %d", definition.targeting.cast_range.maximum) }
	return fmt.ctprintf("RAGGIO %d-%d", definition.targeting.cast_range.minimum, definition.targeting.cast_range.maximum)
}

// The letter of a die. The pixel font draws a capital D like a zero ("1D20"
// reads "1020"), so the texts write dice as "1d20".
DIE_LETTER :: "d"

// "d20": one die.
@(private)
die_label :: proc(sides: i32) -> string {
	return fmt.tprintf("%s%d", DIE_LETTER, sides)
}

// "1d4", "2d8": the dice a dice card rolls at its upgrade level.
@(private)
card_dice_label :: proc(card: game.Card_Instance) -> string {
	return fmt.tprintf("%d%s", game.card_dice_count(card.definition_id), die_label(game.card_die_sides(card.definition_id, card.upgrade_level)))
}

// Hand and inspector share the effective catalog used by gameplay and upgrade previews.
// Amounts, durations and ranges follow the single gameplay definition.
// Poison has no duration: it bites each action of whoever carries it. The
// narrow cards say it shorter.
POISON_RULE_LINE :: cstring("DANNO A OGNI SUA AZIONE")

@(private)
gothic_card_lines :: proc(card: game.Card_Instance) -> (cstring, cstring) {
	u := card.upgrade_level
	d, found := game.card_definition_by_id(card.definition_id)
	if !found { return "", "" }
	a := game.card_effect_amount(d.effects[0], u) if d.effects[0].base_amount > 0 else 0
	b := game.card_effect_amount(d.effects[1], u) if d.effects[1].base_amount > 0 else 0
	switch card.definition_id {
	case .Strike: return fmt.ctprintf("%d DANNI / +2 ESPOSTO", a), "RECUPERO O STORDITO"
	case .Arc_Bolt: return fmt.ctprintf("%d DANNI", a), "TIRO RAPIDO"
	case .Piercing_Ray: return fmt.ctprintf("%d DANNI IN LINEA", a), "SOLO CELLE VISIBILI"
	case .Cross_Slash: return fmt.ctprintf("%d DANNI A CROCE", a), "SOLO CELLE VISIBILI"
	case .Guard, .Purifying_Guard:
		return fmt.ctprintf("%d SCUDO / %ds", a, d.effects[0].duration), "RIMUOVE VELENO" if card.definition_id == .Purifying_Guard else "ABILITA BLOCK / PARRY"
	// The defence prompt's own name (DEVIAZIONE): Deflect is the card that
	// sends a blow back.
	case .Thorn_Coat: return fmt.ctprintf("%d SPINE / %ds", a, d.effects[0].duration), "ABILITA DEVIAZIONE"
	case .Counter_Rune: return fmt.ctprintf("CONTRATTACCO %d", a), fmt.ctprintf("%d CARICHE / RETAIN", d.effects[0].charges)
	case .Battle_Focus: return fmt.ctprintf("PESCA %d / ESPLORA", a), fmt.ctprintf("VISTA: %ds / MAX %d", d.effects[1].duration, game.MAX_TACTICAL_VISION)
	case .Spark_Forge: return fmt.ctprintf("CREA %d SPARK", a), "TEMPORANEE / ENERGIA 0"
	case .Shove: return fmt.ctprintf("SPINGE %d / POI COLPISCE", d.effects[0].movement_distance), fmt.ctprintf("%d DANNO / ANCHE BOMBE", b)
	case .Dash: return fmt.ctprintf("MUOVI 1-%d / SCUDO %d", d.targeting.cast_range.maximum, a), fmt.ctprintf("SCUDO PRIMA / %ds", d.effects[0].duration)
	case .Heavy_Blow: return fmt.ctprintf("%d DANNI + STORDISCE", a), "INTERROMPE L'INTENTO"
	case .Venom_Needle: return fmt.ctprintf("%d DANNO + %d VELENO", a, b), POISON_RULE_LINE
	case .Toxic_Wave: return fmt.ctprintf("APPLICA %d VELENO", a), POISON_RULE_LINE
	case .Caustic_Bloom: return fmt.ctprintf("%d VELENO NEL %dX%d", a, d.targeting.radius*2+1, d.targeting.radius*2+1), POISON_RULE_LINE
	case .Volatile_Study: return fmt.ctprintf("CREA %d SPARK", a), fmt.ctprintf("PESCA %d / EXHAUST", b)
	case .Afterimage: return "SCHIVA SENZA RECUPERO", fmt.ctprintf("%d SCUDO SE MUOVI / %ds", a, d.effects[0].duration)
	case .Chain_Lightning: return fmt.ctprintf("%d DANNI / NEMICO", a), fmt.ctprintf("%d VISIBILI / SALTO %d", game.MAX_SPELL_TARGETS, game.SPELL_BOUNCE_RANGE)
	case .Shadow_Step: return fmt.ctprintf("OMBRA %ds / MONDO FERMO", a), "INTANGIBILE / SOLO PASSI"
	case .Poison_Pool: return fmt.ctprintf("%d VELENO A CELLA", a), "SOLO NEMICI / STANZA"
	case .Wildfire: return fmt.ctprintf("%d BRUCIATURA A CELLA", a), "CROCE: +1 A FINESTRA"
	// The player's charges (game/player_charges.odin).
	case .Deflect: return fmt.ctprintf("+%d RIFLESSO", a), "RIMANDA UN COLPO"
	case .Coffin: return fmt.ctprintf("%d FRECCE / CTRL+CLIC", a), fmt.ctprintf("%d DANNO + 1 STATUS", game.COFFIN_ARROW_DAMAGE)
	case .Fate_Dice: return fmt.ctprintf("%s SU %d COLPI", card_dice_label(card), game.FATE_DICE_CHARGES), "UN TIRO A OGNI COLPO"
	case .Venom_Blade: return fmt.ctprintf("%s COLPI AVVELENATI", card_dice_label(card)), fmt.ctprintf("%d VELENO A COLPO", game.VENOM_BLADE_POISON)
	// LAZZO (game/lasso.odin): the hits it numbers, and a full turn's bite.
	case .Lasso: return fmt.ctprintf("COLPI %d, %d, %d...", a, a+1, a+2), fmt.ctprintf("-%d VITA A OGNI GIRO", game.LASSO_TURN_DAMAGE)
	// CANNA DA PESCA (game/fishing.odin): the room's fishings, and the catch.
	case .Fishing_Rod: return fishing_rod_first_line(a), fmt.ctprintf("CIBO %s / %d%% CARTA", die_label(game.FISHING_HEAL_SIDES), game.FISHING_CARD_PERCENT)
	// PINBALL (game/pinball.odin): the values a foe takes, and the wall's rule.
	case .Pinball: return fmt.ctprintf("COLPI %d, %d, %d...", a, a+1, a+2), fmt.ctprintf("MURO: TORNA A %d / %ds", a, int(game.PINBALL_SECONDS))
	// FIRST PERSON SHOOTER (game/first_person.odin): its seconds, and the AK.
	case .First_Person:
		return fmt.ctprintf("PRIMA PERSONA %ds", a), fmt.ctprintf("AK: %d COLPI/s, %d DANNO", game.FIRST_PERSON_SHOTS_PER_SECOND, game.FIRST_PERSON_SHOT_DAMAGE)
	// FIRST PERSON BRAWLER (game/first_person_fists.odin): its seconds, the fists' damage and the critical.
	case .First_Person_Brawler:
		return fmt.ctprintf("PRIMA PERSONA %ds", a), fmt.ctprintf("PUGNI %d/%d/%d, CRITICO x%d", game.FISTS_PUNCHES[.Jab].damage,
			game.FISTS_PUNCHES[.Cross].damage, game.FISTS_PUNCHES[.Left_Hook].damage, game.FISTS_CRITICAL_FACTOR)
	// FIRST PERSON FENCER (game/first_person_sword.odin): its seconds, the cut's best and the guard.
	case .First_Person_Fencer:
		return fmt.ctprintf("PRIMA PERSONA %ds", a), "SPADA: TAGLIA E PARA"
	// BOMB MARLEY (game/marley.odin): the bombs' damage and the party's seconds;
	// INONDAZIONE (game/flood.odin): the push, and the fires.
	case .Marley_Party: return fmt.ctprintf("BOMBE DA %d DANNI", a), fmt.ctprintf("%ds / LUCI = SALVI", d.effects[0].duration)
	case .Flood_Wave: return fmt.ctprintf("SPINGE TUTTI DI %d", a), "SPEGNE I FUOCHI"
	// CANNONE (game/cannon.odin), BUCO NERO (game/black_hole.odin), DINOSAURO
	// (game/dinosaur.odin).
	case .Field_Cannon: return fmt.ctprintf("1 PALLA/s: %d DANNI", a), fmt.ctprintf("%ds / ROTELLA: MIRA", game.CANNON_SECONDS)
	case .Laser_Cannon: return fmt.ctprintf("RAGGIO/s: %d DANNI", a), fmt.ctprintf("%ds / TUTTA LA LINEA", game.CANNON_SECONDS)
	case .Devouring_Hole:
		return fmt.ctprintf("%d DANNI NEL %dX%d", a, game.black_hole_radius(u)*2+1, game.black_hole_radius(u)*2+1), fmt.ctprintf("%ds / TIRA I NEMICI", game.BLACK_HOLE_SECONDS)
	case .Dino_Ride: return fmt.ctprintf("D4: UN DINO PER %ds", a), "RAPTOR STEGO DILO GIGA"
	case .Sei_Denari, .Sette_Denari: return fmt.ctprintf("+%d ORO", a), "SCOPA / UNA VOLTA PER STANZA"
	case .Firebomb: return fmt.ctprintf("%d DANNI NEL %dX%d", a, d.targeting.radius*2+1, d.targeting.radius*2+1), "ACCENDE I BARILI"
	case .Calculated_Risk: return fmt.ctprintf("PESCA %d", a), fmt.ctprintf("SCARTA %d", b)
	case .Spark: return fmt.ctprintf("%d DANNI", a), "TEMPORANEA"
	case .Grappling_Hook: return fmt.ctprintf("%d DANNO", a), "ATTIRA ADIACENTE"
	case .Fate_Strike:
		return fmt.ctprintf("%d + %s DANNI", a, card_dice_label(card)),
		       fmt.ctprintf("%d: RIMBALZO %d", game.card_die_sides(card.definition_id, u), game.FATE_BOUNCE_DAMAGE)
	case .Sundering_Blow: return fmt.ctprintf("%s DANNI", card_dice_label(card)), fmt.ctprintf("TIRO %d+: SPINTA %d", game.SUNDERING_PUSH_TOTAL, d.effects[1].movement_distance)
	case .Prismatic_Barrage:
		return fmt.ctprintf("%s: %d+ = %d DANNI", card_dice_label(card), game.DICE_SUCCESS_THRESHOLD, game.PRISMATIC_HIT_DAMAGE),
		       fmt.ctprintf("1-%d: %d SCUDO / DADO", game.DICE_SUCCESS_THRESHOLD-1, a)
	case .Twin_Venom: return fmt.ctprintf("MAX(%s) + 1 DANNI", card_dice_label(card)), fmt.ctprintf("COPPIA: %d VELENO", b)
	case .Shock_Floor:
		dice := card_dice_label(card)
		return fmt.ctprintf("%s SCARICHE / %s BERSAGLI", dice, dice), fmt.ctprintf("%d DANNO / TRAPPOLA 3X3", a)
	case .Tesla_Coil: return fmt.ctprintf("%d / DISTANZA DANNI", a), fmt.ctprintf("CAMPO: CONSUMA %d TESLA", game.MAX_TESLA_COILS)
	case .Titan_Grip: return fmt.ctprintf("%d DANNI / LANCIA %d", a, d.effects[1].movement_distance), fmt.ctprintf("INTERROMPE / STORDISCE %ds", d.effects[2].duration)
	case .Storm_Crown: return fmt.ctprintf("%d DANNI / %d BERSAGLI", a, game.MAX_SPELL_TARGETS), fmt.ctprintf("LEGGENDARIA / RIMBALZO %d", game.SPELL_BOUNCE_RANGE)
	case .Cannon: return fmt.ctprintf("%d DANNI / 3 BATTITI", a), "LASER / PERFORA" if u > 0 else "4 COLPI / ORIENTABILE"
	case .Flood: return fmt.ctprintf("%d DANNI / ONDA", a), "SPINGE / RALLENTA"
	case .Black_Hole: return fmt.ctprintf("%d DANNI / ATTRAE", a), "RAGGIO 3 / 4 IMPULSI"
	case .Bomb_Marley: return fmt.ctprintf("%d DANNI / RAGGIO 3", a), "ESPLODE FRA 3 BATTITI"
	case .Dinosaur: return fmt.ctprintf("CAVALCA %ds / +%d URTO", 12+u*2, 2+u), "SCUDO / URTO SPINGE"
	case .Count: return "", ""
	}
	return "", ""
}

// The Canna da Pesca's fishings a room: "1 PESCA A STANZA", "2 PESCHE...".
@(private = "file")
fishing_rod_first_line :: proc(casts: i32) -> cstring {
	return fmt.ctprintf("%d PESCA A STANZA" if casts == 1 else "%d PESCHE A STANZA", casts)
}

// A hand of seven or eight cards: narrower than this, a card's lines shrink
// or are cut. PROVA MECCANICHE holds its whole deck in hand, ten cards (the
// Canna da Pesca waits in Exhaust) overlapping at a full eight-card hand's
// width, 109 pixels on the 960 canvas (tactical_hand_card_bounds): its smoke
// measures every one of their words there (tactical_card_text_misfit).
CARD_NARROW_WIDTH :: f32(130)

// The short lines of the cards whose hand lines would not hold their size on
// a narrow card; the inspector keeps the whole text. found is false for the
// cards whose lines fit as they are.
@(private)
gothic_card_narrow_lines :: proc(card: game.Card_Instance) -> (first, second: cstring, found: bool) {
	d, defined := game.card_definition_by_id(card.definition_id)
	if !defined { return }
	a := game.card_effect_amount(d.effects[0], card.upgrade_level) if d.effects[0].base_amount > 0 else 0
	#partial switch card.definition_id {
	case .Shock_Floor: return fmt.ctprintf("%s COLPI + BERS.", card_dice_label(card)), fmt.ctprintf("%d DANNO / 3X3", a), true
	case .Tesla_Coil: return fmt.ctprintf("%d / DIST. DANNI", a), fmt.ctprintf("CAMPO USA %d TESLA", game.MAX_TESLA_COILS), true
	case .Shadow_Step: return fmt.ctprintf("OMBRA %ds", a), "MONDO FERMO", true
	case .Poison_Pool: return fmt.ctprintf("%d VELENO", a), "A OGNI CELLA", true
	case .Wildfire: return fmt.ctprintf("%d BRUCIATURA", a), "CRESCE A CROCE", true
	case .Deflect: return fmt.ctprintf("+%d RIFLESSO", a), "IL COLPO TORNA", true
	case .Coffin: return fmt.ctprintf("%d FRECCE", a), "CTRL+CLIC", true
	case .Fate_Dice: return fmt.ctprintf("%s A COLPO", card_dice_label(card)), fmt.ctprintf("PER %d COLPI", game.FATE_DICE_CHARGES), true
	case .Venom_Blade: return fmt.ctprintf("%s COLPI", card_dice_label(card)), fmt.ctprintf("%d VELENO L'UNO", game.VENOM_BLADE_POISON), true
	case .Lasso: return fmt.ctprintf("COLPI %d, %d...", a, a+1), fmt.ctprintf("-%d VITA A GIRO", game.LASSO_TURN_DAMAGE), true
	case .Pinball: return fmt.ctprintf("COLPI %d, %d...", a, a+1), fmt.ctprintf("MURO: %d / %ds", a, int(game.PINBALL_SECONDS)), true
	// Its slot is narrower on a canvas narrower than the game's.
	case .Fishing_Rod:
		return fmt.ctprintf("%d PESCA" if a == 1 else "%d PESCHE", a), fmt.ctprintf("CIBO %s O CARTA", die_label(game.FISHING_HEAL_SIDES)), true
	case .First_Person: return fmt.ctprintf("FPS %ds", a), fmt.ctprintf("AK: %d COLPI/s", game.FIRST_PERSON_SHOTS_PER_SECOND), true
	case .First_Person_Brawler: return fmt.ctprintf("FPB %ds", a), fmt.ctprintf("PUGNI, CRITICI x%d", game.FISTS_CRITICAL_FACTOR), true
	case .First_Person_Fencer: return fmt.ctprintf("FPF %ds", a), "SPADA, PARATA", true
	case .Marley_Party: return fmt.ctprintf("BOMBE %d", a), "LUCI: SALVI", true
	case .Flood_Wave: return fmt.ctprintf("SPINTA %d", a), "NO FUOCHI", true
	case .Field_Cannon: return fmt.ctprintf("PALLA %d", a), fmt.ctprintf("%ds", game.CANNON_SECONDS), true
	case .Laser_Cannon: return fmt.ctprintf("RAGGIO %d", a), fmt.ctprintf("%ds", game.CANNON_SECONDS), true
	case .Devouring_Hole: return fmt.ctprintf("BUCO %d", a), fmt.ctprintf("%ds", game.BLACK_HOLE_SECONDS), true
	case .Dino_Ride: return fmt.ctprintf("D4 %ds", a), "UN DINO", true
	}
	return
}
