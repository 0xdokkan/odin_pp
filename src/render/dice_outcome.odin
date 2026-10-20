package render

import "core:c"
import "core:fmt"
import game "../game"
import rl "vendor:raylib"

// The committed effects following a throw, not a second calculation of its
// rules. In particular, the die stays a 3 when the tick adds a fourth charge.
Dice_Outcome :: struct {
	valid, critical: bool,
	damage, absorbed, bounce_damage: i32,
	charges, targets, device_damage: i32,
	shield, poison, healed: i32,
	pushed: bool,
}

dice_presentation_outcome :: proc(timeline: ^Presentation_Timeline) -> (result: Dice_Outcome) {
	roll, found := active_presentation_cue(timeline)
	if !found || roll.kind != .Dice_Rolled { return }
	card := roll.event.card_definition
	#partial switch card {
	case .Fate_Strike, .Sundering_Blow, .Prismatic_Barrage, .Twin_Venom, .Venom_Blade, .Shock_Floor, .Fishing_Rod:
		result.valid = true
	case: return
	}
	result.critical = roll.event.area_mask&game.EVENT_CRITICAL_BIT != 0
	for offset in 1..<timeline.count {
		cue := &timeline.cues[(timeline.head+offset)%MAX_PRESENTATION_CUES]
		event := cue.event
		// Do not count a queued command, the card's later relics or another cast.
		if cue.batch != roll.batch || event.kind == .Card_Moved || event.kind == .Card_Played || event.kind == .Dice_Rolled { break }
		if event.source != game.PLAYER_ENTITY || event.has_status_cause { continue }
		#partial switch event.kind {
		case .Damaged:
			if event.target == roll.event.target { result.damage += event.amount }
			else if card == .Fate_Strike && event.target.kind == .Enemy { result.bounce_damage += event.amount }
		case .Damage_Absorbed:
			if event.target == roll.event.target { result.absorbed += event.amount }
		case .Healed:
			if card == .Fishing_Rod && event.target == game.PLAYER_ENTITY { result.healed += event.amount }
		case .Moved:
			if card == .Sundering_Blow && event.target == roll.event.target { result.pushed = true }
		case .Status_Applied:
			if event.target == game.PLAYER_ENTITY {
				if card == .Venom_Blade && event.status == .Venom_Blade { result.charges = event.amount }
				if card == .Prismatic_Barrage && event.status == .Shield { result.shield = event.amount }
			} else if card == .Twin_Venom && event.target == roll.event.target && event.status == .Poison {
				result.poison = event.amount
			}
		case .Object_Spawned:
			if card == .Shock_Floor && event.object_kind == .Shock_Floor {
				result.charges, result.targets, result.device_damage = event.duration, event.duration, event.amount
			}
		}
	}
	return
}

@(private)
dice_outcome_text :: proc(card: game.Card_Id, outcome: Dice_Outcome) -> (primary, detail: cstring) {
	primary, detail = fmt.ctprintf("%d DANNI INFLITTI", outcome.damage), "AL BERSAGLIO"
	#partial switch card {
	case .Shock_Floor:
		return fmt.ctprintf("%d SCARICHE", outcome.charges), fmt.ctprintf("%d NEMICI / %d DANNO", outcome.targets, outcome.device_damage)
	case .Venom_Blade: return fmt.ctprintf("%d CARICHE", outcome.charges), "LAMA VELENOSA / TOTALI"
	case .Fishing_Rod: return fmt.ctprintf("+%d VITA", outcome.healed), "CURA EFFETTIVA"
	case .Prismatic_Barrage:
		if outcome.shield > 0 { detail = fmt.ctprintf("SCUDO TOTALE %d", outcome.shield) }
	case .Twin_Venom:
		if outcome.poison > 0 { detail = fmt.ctprintf("VELENO TOTALE %d", outcome.poison) }
	case .Sundering_Blow:
		if outcome.pushed { detail = "RESPINTA +1" }
	case .Fate_Strike:
		if outcome.bounce_damage > 0 { detail = fmt.ctprintf("RIMBALZO %d DANNI", outcome.bounce_damage) }
	}
	return
}

@(private)
draw_dice_outcome :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, roll: game.Dice_Roll,
	progress: f32, card: game.Card_Id, outcome: Dice_Outcome) {
	reveals := DICE_POOL_REVEAL_TIMES
	if !outcome.valid || progress < reveals[roll.count-1] { return }
	theme := renderer.theme if renderer != nil else nil
	target := dice_total_target(renderer, layout, true)
	scale := layout.scale
	line_count := 5 if outcome.absorbed > 0 else 4
	width, height := f32(200)*scale, f32(104+22*(line_count-4))*scale
	bounds := rl.Rectangle{target.x-width*0.5, target.y-38*scale, width, height}
	gothic_frame(bounds, RESIN_BACKGROUND, GOTHIC_BLUE)
	face := fmt.ctprintf("D%d: %d", roll.sides, roll.total)
	if roll.count == 2 { face = fmt.ctprintf("2D%d: %d + %d = %d", roll.sides, roll.faces[0], roll.faces[1], roll.total) }
	if roll.count == 3 { face = fmt.ctprintf("3D%d: %d + %d + %d = %d", roll.sides, roll.faces[0], roll.faces[1], roll.faces[2], roll.total) }
	primary, detail := dice_outcome_text(card, outcome)
	lines := [5]cstring{face, primary, detail, "", ""}
	// Absorption has its own short line: it must never hide a pair's poison,
	// the barrage's shield or Fate Strike's bounce.
	if outcome.absorbed > 0 { lines[3] = fmt.ctprintf("SCUDO NEMICO: -%d", outcome.absorbed) }
	lines[line_count-1] = "CRITICO / BONUS INCLUSO" if outcome.critical else "ESITO DEL LANCIO"
	for line, index in lines[:line_count] {
		size := c.int(max(f32(9), (20 if index == 1 else 11)*scale))
		// A D20 pool or a shield caption must stay inside its panel at any scale.
		for size > 8 && f32(menu_measure_text(theme, line, size)) > width-16*scale { size -= 1 }
		y := bounds.y+10*scale+f32(index)*22*scale
		color := GOTHIC_PAPER if index == 1 else GOTHIC_BLUE
		menu_text(theme, line, c.int(target.x)-menu_measure_text(theme, line, size)/2, c.int(y), size, color)
	}
}
