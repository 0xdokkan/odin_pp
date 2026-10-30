package integration
import run_session "../run"

import "core:fmt"
import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// Through the real controller and presentation: each window that runs out
// burns (on the Timeout command, with its cues), the player's walk bites his
// poison, and nothing loses its presentation.
@(test)
test_status_burn_and_poison_through_the_controller :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#...>...#", "#.......#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 1000, attack = 2, defense = 0})
	testing.expect(t, created)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 2
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 7, y = 4}, health = 1000, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Burn, 3, 0)
	_, _ = game.apply_status(&room, game.enemy_entity(1), .Burn, 5, 0)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Poison, 4, 0)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	probe := Tactical_Liveness_Probe{controller = {was_focused = true}}
	burn_cues := 0
	frames := 0
	for frames < 4000 && player.tactical.cycle < 3 {
		frames += 1
		input := run_session.Tactical_Controller_Input{focused = true}
		// One walk at the start: its poison bites.
		if frames == 2 { input.directions[int(game.Move_Direction.East)] = true }
		tactical_liveness_frame(&probe, &room, renderer, input, 1.0/60.0)
		if renderer.world_playback != nil {
			for entry in renderer.world_playback.cues[:renderer.world_playback.count] {
				if entry.cue.event.has_status_cause && entry.cue.event.status_cause == .Burn && entry.cue.elapsed == 0 { burn_cues += 1 }
			}
		}
	}
	testing.expect(t, player.tactical.cycle >= 3, fmt.tprintf("cycle %d after %d frames", player.tactical.cycle, frames))
	poison, poisoned := game.status_for_entity(&room, game.PLAYER_ENTITY, .Poison)
	testing.expect(t, poisoned && poison.potency == 3)
	// Three windows ran out: three burns each, on top of one poison bite of 4.
	testing.expect_value(t, room.enemies[0].health, i32(1000-5*3))
	testing.expect(t, player.health <= 1000-4-3*3)
	testing.expect(t, burn_cues >= 2)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}
