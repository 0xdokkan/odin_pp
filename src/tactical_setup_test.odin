package main

import "core:testing"
import game "game"
import level "level"

@(test)
test_new_tactical_run_and_restart_keep_expanded_rooms_and_starter_dice :: proc(t: ^testing.T) {
	run, created := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, DEFAULT_RUNTIME_OPTIONS.seed)
	testing.expect(t, created)
	defer game.destroy_run(&run)
	testing.expect(t, configure_demo_tactical_player(&run.player, game.DEFAULT_TACTICAL_CONFIG))
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&data, &run, &room, true))
	for restart in 0..<2 {
		if restart == 1 {
			run.player.tactical.dodge_recovery = 2
			testing.expect(t, restart_demo_session(&data, &run, &room, DEFAULT_RUNTIME_OPTIONS.seed+1, true))
		}
		testing.expect_value(t, data.tiles.width, 17)
		testing.expect_value(t, data.tiles.height, 11)
		testing.expect_value(t, len(room.enemies), 4)
		testing.expect_value(t, run.player.tactical.config.vision_size, 7)
		testing.expect_value(t, run.player.tactical.dodge_recovery, 0)
		count := 0
		for card in run.player.deck.owned[:run.player.deck.owned_count] {
			if card.definition_id == .Fate_Strike { count += 1 }
		}
		testing.expect_value(t, count, 1)
		for definition in ([?]game.Card_Id{.Heavy_Blow, .Battle_Focus, .Dash}) {
			found := false
			for card in run.player.deck.owned[:run.player.deck.owned_count] { found = found || card.definition_id == definition }
			testing.expect(t, found)
		}
		testing.expect(t, game.validate_enemy_intents(&room))
	}
}
