package integration
import run_session "../run"


import "core:testing"
import game "../game"
import level "../level"

@(test)
test_new_tactical_run_and_restart_keep_expanded_rooms_and_starter_dice :: proc(t: ^testing.T) {
	run, created := game.create_run(run_session.DEMO_PLAYER_STATS, run_session.DEMO_RUN_CONFIG, run_session.DEFAULT_OPTIONS.seed)
	testing.expect(t, created)
	defer game.destroy_run(&run)
	testing.expect(t, run_session.configure_demo_tactical_player(&run.player, game.DEFAULT_TACTICAL_CONFIG))
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
	for restart in 0..<2 {
		if restart == 1 {
			run.player.tactical.dodge_recovery = 2
			testing.expect(t, run_session.restart_demo_session(&data, &run, &room, run_session.DEFAULT_OPTIONS.seed+1, true))
		}
		testing.expect_value(t, data.tiles.width, 17)
		testing.expect_value(t, data.tiles.height, 11)
		testing.expect_value(t, len(room.enemies), 4)
		testing.expect_value(t, run.player.tactical.config.vision_size, 7)
		testing.expect_value(t, run.player.tactical.dodge_recovery, 0)
		count, shadows := 0, 0
		for card in run.player.deck.owned[:run.player.deck.owned_count] {
			if card.definition_id == .Fate_Strike { count += 1 }
			if card.definition_id == .Shadow_Step { shadows += 1 }
		}
		testing.expect_value(t, count, 1)
		// One Movimento Ombra in every tactical run, a restart included.
		testing.expect_value(t, shadows, 1)
		for definition in ([?]game.Card_Id{.Heavy_Blow, .Battle_Focus, .Dash}) {
			found := false
			for card in run.player.deck.owned[:run.player.deck.owned_count] { found = found || card.definition_id == definition }
			testing.expect(t, found)
		}
		testing.expect(t, game.validate_enemy_intents(&room))
	}
}
