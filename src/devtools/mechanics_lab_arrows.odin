package devtools
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// THE ARCHERS' REAL ARROWS (game/enemy_arrow.odin, docs/piano-succo.md,
// Fasi 3-4), in the real window: an archer looses, the player steps out of its
// line and is missed, the arrow sticking where it lands beyond him; a second
// one, aimed where he stands and left to come, strikes him; the loose, the
// whistle and the miss are heard. Reels odin_pp_living_arrow_dodge_NN and
// odin_pp_living_arrow_hit_NN.png.
mechanics_lab_arrows :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the archers' arrows") { return false }
	player := room.player
	centre := player.position
	archer_id := mechanics_lab_spawn_enemy(room, grid.offset(centre, 4, 0), 60, .Archer)
	if archer_id == 0 { fmt.eprintln("mechanics lab: no room for the archer"); return false }
	frame := 0
	// Aims at where the player stands, shooting at its next beat.
	aim :: proc(room: ^game.Room, id: u32) {
		index, _ := game.enemy_index_by_id(room, id)
		archer := &room.enemies[index]
		archer.recovery_pulses, archer.aim_ready = 0, true
		archer.intent = game.make_attack_intent(room, archer.position, room.player.position, archer.attack)
		archer.tactical_cooldown = 0.2
	}
	// Frames until the arrow is loosed, then until it has landed.
	fly :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, name: string, frame: ^int, landed: bool) -> bool {
		for _ in 0..<240 {
			if (room.arrows.count > 0) != landed && !room.tactical_pulse.pending { return true }
			mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, name, 3, frame)
		}
		return false
	}
	health := player.health
	bolts := &renderer.tactical.enemy_bolts
	missed := bolts.landed[.Wall]+bolts.landed[.Floor]
	aim(room, archer_id)
	if !fly(window, renderer, room, controller, cards, buffer, "arrow_dodge", &frame, false) { fmt.eprintln("mechanics lab: the archer loosed no arrow"); return false }
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .North}) {
		fmt.eprintln("mechanics lab: the step out of the arrow's line was not taken"); return false
	}
	if !fly(window, renderer, room, controller, cards, buffer, "arrow_dodge", &frame, true) || player.health != health {
		fmt.eprintln("mechanics lab: the arrow did not miss the player who stepped out:", player.health, "of", health); return false
	}
	// Missed, it sticks where it landed and quivers there (Fase 4).
	for _ in 0..<12 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "arrow_dodge", 3, &frame) }
	if bolts.landed[.Wall]+bolts.landed[.Floor] != missed+1 {
		fmt.eprintln("mechanics lab: the missed arrow did not stay where it landed"); return false
	}
	// The archer comes level with him again; this time he stays.
	if index, found := game.enemy_index_by_id(room, archer_id); found { room.enemies[index].position = grid.offset(player.position, 4, 0) }
	frame = 0
	aim(room, archer_id)
	if !fly(window, renderer, room, controller, cards, buffer, "arrow_hit", &frame, false) ||
	   !fly(window, renderer, room, controller, cards, buffer, "arrow_hit", &frame, true) || player.health >= health {
		fmt.eprintln("mechanics lab: the second arrow did not strike the player:", player.health, "of", health); return false
	}
	for _ in 0..<30 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "arrow_hit", 3, &frame) }
	// Heard: the loose, the whistle in flight, the miss in the stone.
	if sounds := renderer.tactical.lab_sounds; sounds == nil || sounds.played[.Archer_Loose] < 2 ||
	   sounds.played[render.LAB_BOLT_FLIGHT] < 2 || sounds.played[render.LAB_BOLT_STONE]+sounds.played[render.LAB_BOLT_WOOD] < 1 {
		fmt.eprintln("mechanics lab: the arrows were not heard (loose, whistle, miss)"); return false
	}
	fmt.eprintf("mechanics lab arrows: one dodged with a step, stuck where it missed, one struck (%d to %d)\n", health, player.health)
	return true
}
