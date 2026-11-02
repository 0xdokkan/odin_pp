package devtools
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// THE BOMBERS' BOMBS IN FLIGHT (game/enemy_bomb.odin, docs/piano-succo.md,
// Fase 5), in the real window: a bomber lobs its bomb at the player's cell;
// it is in the air, not on the cell, then lands there with its fuse lit and
// its thud; the player walks out of the ring before it bursts and is not
// hurt. Reels odin_pp_living_bomb_throw_NN and odin_pp_living_bomb_escape_NN.png.
mechanics_lab_bombs :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the bombers' bombs") { return false }
	player := room.player
	centre := player.position
	bomber_id := mechanics_lab_spawn_enemy(room, grid.offset(centre, 3, 1), 60, .Bomber)
	if bomber_id == 0 { fmt.eprintln("mechanics lab: no room for the bomber"); return false }
	index, _ := game.enemy_index_by_id(room, bomber_id)
	bomber := &room.enemies[index]
	bomber.recovery_pulses, bomber.bomb_ready = 0, true
	bomber.intent = game.make_tactical_bomb_intent(room, bomber.position, centre, false)
	bomber.tactical_cooldown = 0.2
	health := player.health
	frame := 0
	// Thrown: in the air, not yet on its cell.
	thrown := false
	for _ in 0..<240 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "bomb_throw", 3, &frame)
		if room.bombs.count > 0 { thrown = true; break }
	}
	if !thrown || len(room.objects) != 0 { fmt.eprintln("mechanics lab: the bomber threw no bomb in the air"); return false }
	// Landed on his cell, its fuse lit.
	landed := false
	for _ in 0..<120 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "bomb_throw", 3, &frame)
		if room.bombs.count == 0 && len(room.objects) == 1 { landed = true; break }
	}
	if !landed || room.objects[0].position != centre || room.objects[0].detonation_pulse == 0 {
		fmt.eprintln("mechanics lab: the bomb did not land on its cell with its fuse lit"); return false
	}
	for _ in 0..<12 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "bomb_throw", 3, &frame) }
	// Out of the ring: two steps away.
	frame = 0
	for _ in 0..<2 {
		if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .North}) {
			fmt.eprintln("mechanics lab: the step out of the ring was not taken"); return false
		}
	}
	burst := false
	for _ in 0..<360 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "bomb_escape", 3, &frame)
		if len(room.objects) == 0 { burst = true; break }
	}
	for _ in 0..<20 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "bomb_escape", 3, &frame) }
	if !burst || player.health != health {
		fmt.eprintln("mechanics lab: the bomb did not burst behind the player who ran:", burst, player.health, "of", health); return false
	}
	if sounds := renderer.tactical.lab_sounds; sounds == nil || sounds.played[.World_Bomb_Land] < 1 || sounds.played[.Bomber_Throw] < 1 {
		fmt.eprintln("mechanics lab: the bomb was not heard (throw, landing)"); return false
	}
	fmt.eprintln("mechanics lab bombs: thrown, flew, landed on its cell, escaped before it burst")
	return true
}
