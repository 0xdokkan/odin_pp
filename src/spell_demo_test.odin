package main

import "core:testing"
import game "game"
import grid "grid"
import level "level"
import render "render"

spell_demo_test_session :: proc(t: ^testing.T, run: ^game.Run_State, data: ^level.Level, room: ^game.Room) -> bool {
	created, valid := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, 0x5E11, false)
	testing.expect(t, valid)
	if !valid {return false}
	run^ = created
	installed := replace_current_demo_room(data, run, room, false)
	testing.expect(t, installed)
	return installed
}

spell_demo_expect_practice_hand :: proc(t: ^testing.T, room: ^game.Room) {
	expected := [?]game.Card_Id{.Firebomb, .Fate_Strike, .Chain_Lightning, .Sundering_Blow, .Guard}
	deck := &room.player.deck
	testing.expect_value(t, deck.owned_count, 5)
	testing.expect_value(t, deck.hand_count, 5)
	testing.expect_value(t, deck.draw_count, 0)
	testing.expect_value(t, deck.discard_count, 0)
	testing.expect_value(t, deck.exhaust_count, 0)
	testing.expect_value(t, deck.energy, deck.rules.max_energy)
	for id, index in expected {testing.expect_value(t, deck.hand[index].definition_id, id)}
	testing.expect(t, game.validate_deck_state(deck))
	testing.expect(t, game.validate_enemy_intents(room))
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.player.position, grid.Position{3, 3})
}

spell_demo_expect_committed_smoke :: proc(t: ^testing.T, kind: Spell_Smoke) {
	run: game.Run_State
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !spell_demo_test_session(t, &run, &data, &room) {return}
	renderer: render.Renderer
	testing.expect(t, prepare_spell_smoke(&room, &renderer, kind))
	if !render.renderer_timeline_is_busy(&renderer) {return}
	cue, found := render.active_presentation_cue(&renderer.timeline)
	testing.expect(t, found && cue.started)
	if !found {return}
	new_dice := kind == .Barrage || kind == .Venom
	expected_kind := render.Presentation_Cue_Kind.Dice_Rolled if kind == .Dice || kind == .Dice_Pool || new_dice else render.Presentation_Cue_Kind.Spell_Impact
	expected_progress := f32(0.84) if kind == .Dice else f32(0.4)
	if kind == .Dice_Pool || new_dice { expected_progress = 0.94 }
	testing.expect_value(t, cue.kind, expected_kind)
	testing.expect(t, abs(render.presentation_cue_progress(cue)-expected_progress) < 0.0001)
	if kind == .Dice {
		// An unupgraded Fate Strike rolls a D4: its top face bounces.
		testing.expect_value(t, cue.event.amount, i32(4))
		testing.expect_value(t, cue.event.dice_roll.sides, i32(4))
		testing.expect_value(t, run.player.dice.roll_count, u64(1))
	}
	if kind == .Dice_Pool {
		testing.expect_value(t, cue.event.dice_roll.count, 2)
		testing.expect_value(t, cue.event.amount, game.SUNDERING_PUSH_TOTAL)
		testing.expect_value(t, run.player.dice.roll_count, u64(2))
	}
	if new_dice {
		testing.expect_value(t, run.player.dice.roll_count, u64(3) if kind == .Barrage else u64(2))
		if kind == .Barrage {testing.expect_value(t, game.dice_success_count(&cue.event.dice_roll), 2)}
		if kind == .Venom {testing.expect(t, game.dice_has_pair(&cue.event.dice_roll))}
	}
	// Setup must freeze the visible frame before applying already committed
	// damage. This catches accidental authoritative-state rendering in smokes.
	current_target := cue.event.target if cue.event.target.kind == .Enemy else game.enemy_entity(1)
	actor, actor_found := render.presentation_actor_in_view(&renderer.timeline.view, current_target)
	testing.expect(t, actor_found)
	if actor_found {testing.expect_value(t, actor.health, i32(12))}
	enemy_index, enemy_found := game.enemy_index_by_id(&room, current_target.id)
	testing.expect(t, enemy_found)
	if enemy_found {testing.expect(t, room.enemies[enemy_index].health < 12)}
	if kind == .Chain {
		previous, previous_found := render.presentation_actor_in_view(&renderer.timeline.view, game.enemy_entity(1))
		testing.expect(t, previous_found && previous.health < 12,
			"the chain smoke shows a later bounce after the earlier hit has visibly resolved")
	}
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, game.validate_run_state(&run) && game.validate_enemy_intents(&room))

	authoritative := render.capture_room_presentation(&room)
	dice_after_action := run.player.dice
	testing.expect(t, finish_spell_smoke(&room, &renderer))
	testing.expect(t, !render.renderer_timeline_is_busy(&renderer))
	testing.expect_value(t, renderer.timeline.view, authoritative)
	testing.expect_value(t, run.player.dice, dice_after_action)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	testing.expect_value(t, renderer.timeline.dropped_count, 0)
	testing.expect_value(t, room.recent_events.dropped_count, 0)
}

@(test)
test_spell_smoke_frames_replay_real_firebomb_fate_and_chain_actions_to_authoritative_state :: proc(t: ^testing.T) {
	for kind in ([6]Spell_Smoke{.Firebomb, .Dice, .Chain, .Dice_Pool, .Barrage, .Venom}) {
		spell_demo_expect_committed_smoke(t, kind)
	}
}

@(test)
test_dice_practice_restores_all_four_dice_cards_without_rewinding_rng :: proc(t: ^testing.T) {
	run: game.Run_State
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !spell_demo_test_session(t, &run, &data, &room) {return}
	testing.expect(t, prepare_spell_lab(&room, true))
	testing.expect_value(t, run.player.deck.hand_count, 5)
	for id, index in ([5]game.Card_Id{.Fate_Strike, .Sundering_Blow, .Prismatic_Barrage, .Twin_Venom, .Guard}) {
		testing.expect_value(t, run.player.deck.hand[index].definition_id, id)
	}
	play := game.play_card(&room, run.player.deck.hand[2].id, game.entity_target(game.enemy_entity(1)))
	testing.expect(t, game.card_play_was_committed(play.result))
	testing.expect_value(t, run.player.dice.roll_count, u64(3))
	dice := run.player.dice
	testing.expect(t, prepare_spell_lab(&room, true))
	testing.expect_value(t, run.player.dice, dice)
	testing.expect_value(t, run.player.deck.hand_count, 5)
	testing.expect_value(t, run.player.deck.hand[2].definition_id, game.Card_Id.Prismatic_Barrage)
	testing.expect(t, game.validate_run_state(&run) && game.validate_enemy_intents(&room))
}

@(test)
test_spell_preview_smoke_keeps_the_practice_hand_and_dice_unchanged :: proc(t: ^testing.T) {
	run: game.Run_State
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !spell_demo_test_session(t, &run, &data, &room) {return}
	dice_before := run.player.dice
	renderer: render.Renderer
	testing.expect(t, prepare_spell_smoke(&room, &renderer, .Preview))
	spell_demo_expect_practice_hand(t, &room)
	testing.expect(t, !render.renderer_timeline_is_busy(&renderer))
	testing.expect_value(t, room.recent_events.count, 0)
	testing.expect_value(t, run.player.dice, dice_before)
	player_before_preview := run.player
	target := game.entity_target(game.enemy_entity(room.enemies[0].id))
	for index in 1..=2 {
		for _ in 0..<4 {
			path := game.query_spell_path(&room, run.player.deck.hand[index], target)
			testing.expect_value(t, path.error, game.Card_Compile_Error.None)
			testing.expect_value(t, path.count, 2 if index == 1 else 3)
		}
	}
	testing.expect_value(t, run.player, player_before_preview)
	testing.expect(t, game.validate_run_state(&run))
}

@(test)
test_spell_practice_reset_restores_five_cards_and_preserves_existing_dice_until_run_restart :: proc(t: ^testing.T) {
	run: game.Run_State
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !spell_demo_test_session(t, &run, &data, &room) {return}
	testing.expect(t, prepare_spell_lab(&room))
	spell_demo_expect_practice_hand(t, &room)
	play := game.play_card(&room, run.player.deck.hand[1].id, game.entity_target(game.enemy_entity(1)))
	testing.expect(t, game.card_play_was_committed(play.result))
	testing.expect_value(t, run.player.dice.roll_count, u64(1))
	_, added := game.create_temporary_card(&run.player.deck, .Arc_Bolt)
	testing.expect(t, added)
	dice_after_cast := run.player.dice
	testing.expect(t, prepare_spell_lab(&room))
	spell_demo_expect_practice_hand(t, &room)
	testing.expect(t, run.player.dice == dice_after_cast,
		"practice setup must not rewind the existing player's dice stream")
	testing.expect(t, room.player == &run.player && room.level_data == &data)
	testing.expect(t, game.validate_run_state(&run))

	// This is the same restart + practice setup sequence used by F5 in main.
	next_seed := run.seed+1
	testing.expect(t, restart_demo_session(&data, &run, &room, next_seed, false))
	restarted_dice := run.player.dice
	testing.expect_value(t, restarted_dice, game.make_dice_state(next_seed))
	testing.expect(t, prepare_spell_lab(&room))
	spell_demo_expect_practice_hand(t, &room)
	testing.expect_value(t, run.player.dice, restarted_dice)
	testing.expect_value(t, run.player.health, run.player.stats.max_health)
	testing.expect(t, room.player == &run.player && room.level_data == &data)
	testing.expect(t, game.validate_run_state(&run))
}
