package render

import "core:fmt"
import game "../game"

draw_tactical_enemy_inspector :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !renderer.has_hovered_cell || renderer_timeline_is_busy(renderer) ||
	   !tactical_render_visible(renderer, renderer.hovered_cell) { return }
	index, found := game.enemy_index_at(room, renderer.hovered_cell)
	if !found { return }
	enemy := &room.enemies[index]
	title, first, second: cstring
	switch enemy.archetype {
	case .Chaser:
		title, first, second = "INSEGUITORE", "COLPO / RECUPERO 1 PULSE", "SCHIVA E CONTRATTACCA"
	case .Archer:
		title, first, second = "ARCIERE", "MIRA 1 / TIRO / RECUPERO 1", "ESCI DALLA CELLA MIRATA"
	case .Brute:
		title, first, second = "BRUTO", "FENDENTE: 3 CELLE FRONTALI", "CARICA: RECUPERO 2 PULSE"
	case .Bomber:
		title, first, second = "BOMBAROLO", "PREPARA / LANCIA / RECUPERA 2", "MICCIA 3 / UNA BOMBA ATTIVA"
	case .Custodian:
		title, first, second = "CUSTODE", "2 SCUDO / RECUPERO 2 PULSE", "SPOSTALO O INTERROMPILO"
	case .Demolitionist:
		title, first, second = "DEMOLITORE", "CARICHE / BOMBE / BARILI", "INTERROMPI / EVITA LE MICCE"
	case .Count: return
	}
	x, y := f32(25), f32(145)
	gothic_frame({x-11, y-8, 218, 148}, GOTHIC_INK, GOTHIC_MUTED)
	gothic_text_fit(renderer, title, {x, y, 192, 24}, 18, GOTHIC_PAPER)
	gothic_rule(x, y+29, 190)
	gothic_text_fit(renderer, first, {x, y+38, 192, 20}, 14, GOTHIC_PAPER)
	gothic_text_fit(renderer, second, {x, y+60, 192, 20}, 14, GOTHIC_MUTED)
	intent := tactical_intent_label(enemy.intent)
	if game.enemy_is_staggered(room, enemy) { intent = "STORDITO" }
	gothic_text_fit(renderer, fmt.ctprintf("ORA: %s / HP %d", intent, enemy.health), {x, y+86, 192, 20}, 14, GOTHIC_RED)
	if enemy.recovery_pulses > 0 {
		gothic_text_fit(renderer, fmt.ctprintf("ESPOSTO %d PULSE / STRIKE +2", enemy.recovery_pulses), {x, y+110, 192, 18}, 12, GOTHIC_PAPER)
	} else {
		gothic_text_fit(renderer, "CELLE ACCESE = INTENTO FISSO", {x, y+110, 192, 18}, 12, GOTHIC_MUTED)
	}
}
