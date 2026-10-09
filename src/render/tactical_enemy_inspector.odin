package render

import "core:fmt"
import game "../game"

draw_tactical_enemy_inspector :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !renderer.has_hovered_cell || renderer_blocks_player_input(renderer) ||
	   !tactical_render_visible(renderer, renderer.hovered_cell) { return }
	index, found := game.enemy_index_at(room, renderer.hovered_cell)
	if !found { return }
	enemy := &room.enemies[index]
	title, first, second: cstring
	switch enemy.archetype {
	case .Chaser:
		title, first, second = "INSEGUITORE", "INSEGUE / COLPISCE / RECUPERA", "SCHIVA E CONTRATTACCA"
	case .Archer:
		title, first, second = "ARCIERE", "MIRA / TIRO / RECUPERO", "ESCI DALLA CELLA MIRATA"
	case .Brute:
		title, first, second = "BRUTO", "FENDENTE: 3 CELLE FRONTALI", "CARICA / RECUPERA 2s"
	case .Bomber:
		title, first, second = "BOMBAROLO", "PREPARA / LANCIA / RECUPERA", "MICCIA 3s / UNA BOMBA ATTIVA"
	case .Custodian:
		title, first, second = "CUSTODE", "2 SCUDO / RECUPERO 2s", "SPOSTALO O INTERROMPILO"
	case .Demolitionist:
		title, first, second = "DEMOLITORE", "CARICHE / BOMBE / BARILI", "INTERROMPI / EVITA LE MICCE"
	case .Count: return
	}
	x, y := f32(25), TACTICAL_HUD_HEIGHT+f32(26)
	gothic_frame({x-11, y-8, 218, 172}, GOTHIC_RECESS, GOTHIC_STEEL)
	gothic_text_fit(renderer, title, {x, y, 192, 24}, 18, GOTHIC_PAPER)
	gothic_rule(x, y+29, 190)
	gothic_text_fit(renderer, first, {x, y+38, 192, 20}, 14, GOTHIC_PAPER)
	gothic_text_fit(renderer, second, {x, y+60, 192, 20}, 14, GOTHIC_MUTED)
	intent := tactical_intent_label(enemy.intent)
	if game.enemy_is_staggered(room, enemy) { intent = "STORDITO" }
	gothic_text_fit(renderer, fmt.ctprintf("%s / %.1fs", intent, game.tactical_enemy_seconds(room, enemy)), {x, y+86, 192, 22}, 18, GOTHIC_BLUE)
	gothic_text_fit(renderer, fmt.ctprintf("HP %d / COLPO %d", enemy.health, enemy.attack), {x, y+111, 192, 18}, 12, GOTHIC_PAPER)
	if enemy.recovery_pulses > 0 {
		gothic_text_fit(renderer, fmt.ctprintf("ESPOSTO %ds / STRIKE +2", enemy.recovery_pulses), {x, y+137, 192, 18}, 12, GOTHIC_PAPER)
	} else {
		gothic_text_fit(renderer, "CELLE ACCESE = INTENTO FISSO", {x, y+137, 192, 18}, 12, GOTHIC_MUTED)
	}
}
