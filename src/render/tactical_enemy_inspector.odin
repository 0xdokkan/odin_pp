package render

import "core:fmt"
import rl "vendor:raylib"
import game "../game"

// The enemy under the mouse. A living board keeps showing it while an
// animation plays, and while the camera glides under a mouse that stays still.
tactical_inspected_enemy :: proc(renderer: ^Renderer, room: ^game.Room) -> (^game.Enemy, bool) {
	v := &renderer.tactical
	if renderer.has_hovered_cell && !renderer_blocks_player_input(renderer) && tactical_render_visible(renderer, renderer.hovered_cell) {
		if index, found := game.enemy_index_at(room, renderer.hovered_cell); found {
			if v.living { v.inspected, v.inspected_mouse = room.enemies[index].id, rl.GetMousePosition() }
			return &room.enemies[index], true
		}
	}
	if !v.living || v.inspected == 0 { return nil, false }
	if renderer_blocks_player_input(renderer) || rl.GetMousePosition() == v.inspected_mouse {
		if index, found := game.enemy_index_by_id(room, v.inspected); found { return &room.enemies[index], true }
	}
	v.inspected = 0
	return nil, false
}

// What the inspector says of `enemy`'s health and statuses: what the board
// shows of it (the snapshot: a blow still on its way, as its heart and its
// paper tags, has not yet taken the health nor left the status), else the
// room's.
tactical_inspected_state :: proc(renderer: ^Renderer, enemy: ^game.Enemy) -> (health, max_health: i32, statuses: game.Status_Set) {
	health, max_health, statuses = enemy.health, enemy.max_health, enemy.statuses
	if actor, shown := presentation_actor_in_view(renderer.tactical.snapshot, game.enemy_entity(enemy.id)); shown {
		health, max_health, statuses = actor.health, actor.max_health, actor.statuses
	}
	return
}

draw_tactical_enemy_inspector :: proc(renderer: ^Renderer, room: ^game.Room) {
	// A defence prompt takes the same corner; it comes first.
	if renderer.tactical.living && room.qte.kind != .None { return }
	enemy, found := tactical_inspected_enemy(renderer, room)
	if !found { return }
	health, max_health, statuses := tactical_inspected_state(renderer, enemy)
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
	// Its statuses, when it has any, on one more line: each one's name and
	// stacks (or potency and seconds) in its colour.
	statused := statuses.count > 0
	gothic_frame({x-11, y-8, 218, 172+(24 if statused else 0)}, GOTHIC_RECESS, GOTHIC_STEEL)
	gothic_text_fit(renderer, title, {x, y, 192, 24}, 18, GOTHIC_PAPER)
	gothic_rule(x, y+29, 190)
	gothic_text_fit(renderer, first, {x, y+38, 192, 20}, 14, GOTHIC_PAPER)
	gothic_text_fit(renderer, second, {x, y+60, 192, 20}, 14, GOTHIC_MUTED)
	intent := tactical_intent_label(enemy.intent)
	if game.enemy_is_staggered(room, enemy) { intent = "STORDITO" }
	gothic_text_fit(renderer, fmt.ctprintf("%s / %.1fs", intent, game.tactical_enemy_seconds(room, enemy)), {x, y+86, 192, 22}, 18, GOTHIC_BLUE)
	if renderer.tactical.living {
		gothic_text_fit(renderer, fmt.ctprintf("HP %d/%d / COLPO %d", health, max_health, enemy.attack), {x, y+109, 192, 22}, 16, GOTHIC_PAPER)
	} else {
		gothic_text_fit(renderer, fmt.ctprintf("HP %d / COLPO %d", health, enemy.attack), {x, y+111, 192, 18}, 12, GOTHIC_PAPER)
	}
	if enemy.recovery_pulses > 0 {
		gothic_text_fit(renderer, fmt.ctprintf("ESPOSTO %ds / STRIKE +2", enemy.recovery_pulses), {x, y+137, 192, 18}, 12, GOTHIC_PAPER)
	} else {
		gothic_text_fit(renderer, "CELLE ACCESE = INTENTO FISSO", {x, y+137, 192, 18}, 12, GOTHIC_MUTED)
	}
	if statused {
		count := statuses.count
		shown := min(count, 3)
		chip := (f32(192)-f32(shown-1)*4-(26 if count > shown else 0))/f32(shown)
		for status, index in statuses.items[:shown] {
			_, accent := tactical_status_label(status.kind, false)
			hud_chip(renderer, {x+f32(index)*(chip+4), y+158, chip, 18}, tactical_status_chip_text(status, shown > 1), accent)
		}
		if count > shown {
			gothic_text_fit(renderer, fmt.ctprintf("+%d", count-shown), {x+f32(shown)*(chip+4), y+159, 24, 17}, 12, GOTHIC_MUTED)
		}
	}
}
