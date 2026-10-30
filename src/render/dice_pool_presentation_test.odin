package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_barrage_zero_and_three_successes_replay_one_throw_before_any_effect :: proc(t: ^testing.T) {
	for successes in ([2]int{0, 3}) {
		data := create_encounter_presentation_test_level(t)
		player := spell_presentation_player(t, .Prismatic_Barrage)
		fixture := false
		// The hand is dealt by create_room: the owned card is the one played.
		for seed in u64(1)..=4096 {
			candidate := game.make_dice_state(seed)
			staged := candidate
			roll, valid := game.roll_card_dice(&staged, player.deck.owned[0])
			if valid && game.dice_success_count(&roll) == successes {
				player.dice, fixture = candidate, true
				break
			}
		}
		testing.expect(t, fixture)
		enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}}
		room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		room.enemies[0].intent = game.make_wait_intent(&room, room.enemies[0].position)
		before := capture_room_presentation(&room)
		play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
		testing.expect(t, game.card_play_was_committed(play.result))
		after := capture_room_presentation(&room)
		timeline: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
		rolls, impacts := 0, 0
		for cue in timeline.cues[:timeline.count] {
			if cue.kind == .Dice_Rolled {rolls += 1}
			if cue.kind == .Spell_Impact {impacts += 1}
		}
		testing.expect_value(t, rolls, 1)
		testing.expect_value(t, impacts, 0 if successes == 0 else 1)
		spell_presentation_finish_group(t, &timeline)
		cue, found := active_presentation_cue(&timeline)
		testing.expect(t, found && cue.kind == .Dice_Rolled)
		if found {
			testing.expect_value(t, cue.duration, DICE_CUE_DURATION)
			update_event_timeline(&timeline, cue.duration*0.94)
			testing.expect_value(t, timeline.view.player, before.player)
			actor, has_actor := presentation_actor(&timeline, game.enemy_entity(1))
			if has_actor {testing.expect_value(t, actor.health, i32(40))}
		}
		rng := player.dice
		for _ in 0..<10000 {
			if !event_timeline_is_busy(&timeline) {break}
			update_event_timeline(&timeline, 1.0/240.0)
		}
		testing.expect_value(t, player.dice, rng)
		spell_presentation_expect_room(t, &timeline, &room)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_dice_pool_is_one_cue_and_holds_health_and_position_until_the_hit :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Sundering_Blow)
	// An unupgraded Sundering Blow rolls 2D4: only a double four reaches the push.
	for seed in u64(1)..=4096 {
		candidate := game.make_dice_state(seed)
		staged := candidate
		roll, valid := game.roll_card_dice(&staged, player.deck.owned[0])
		if valid && roll.total == game.SUNDERING_PUSH_TOTAL { player.dice = candidate; break }
	}
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	roll_cues := 0
	for cue in timeline.cues[:timeline.count] { if cue.kind == .Dice_Rolled { roll_cues += 1 } }
	testing.expect_value(t, roll_cues, 1)
	spell_presentation_finish_group(t, &timeline)
	die, found := active_presentation_cue(&timeline)
	testing.expect(t, found)
	if !found { return }
	testing.expect_value(t, die.kind, Presentation_Cue_Kind.Dice_Rolled)
	testing.expect_value(t, die.event.dice_roll.count, 2)
	testing.expect_value(t, die.event.amount, game.SUNDERING_PUSH_TOTAL)
	testing.expect_value(t, die.duration, presentation_cue_duration(.Dice_Rolled, {card_definition = .Fate_Strike}))
	update_event_timeline(&timeline, die.duration*0.94)
	actor, visible := presentation_actor(&timeline, game.enemy_entity(1))
	testing.expect(t, visible)
	if visible {
		testing.expect_value(t, actor.health, i32(40))
		testing.expect_value(t, actor.position, presentation_position({x = 3, y = 1}))
	}
	testing.expect_value(t, room.enemies[0].health, i32(32))
	testing.expect_value(t, room.enemies[0].position.x, 4)
	testing.expect_value(t, timeline.view.deck.energy, i32(1))
	testing.expect_value(t, timeline.view.pulse_count, u64(0))
	dice_after_play := player.dice
	// Small presentation steps must replay the same authoritative movement and
	// reactions without rerolling or paying for the second die as another card.
	for _ in 0..<10000 {
		if !event_timeline_is_busy(&timeline) { break }
		update_event_timeline(&timeline, 1.0/240.0)
	}
	testing.expect_value(t, player.dice, dice_after_play)
	spell_presentation_expect_room(t, &timeline, &room)
}

// An upgraded card rolls its level's die in play, and the cue checks the logged
// die against the card's level: a mismatch is a presentation failure.
@(test)
test_dice_cue_rolls_the_die_of_its_card_level :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Prismatic_Barrage)
	for _ in 0..<4 {
		testing.expect_value(t, game.upgrade_owned_card(&player.deck, player.deck.owned[0].id), game.Deck_Mutation_Result.Upgraded)
	}
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	room.enemies[0].intent = game.make_wait_intent(&room, room.enemies[0].position)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
	testing.expect(t, game.card_play_was_committed(play.result))
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	rolls := 0
	for cue in timeline.cues[:timeline.count] {
		if cue.kind != .Dice_Rolled { continue }
		rolls += 1
		testing.expect_value(t, cue.event.dice_roll.sides, i32(12))
		testing.expect_value(t, cue.event.dice_roll.count, i32(3))
		testing.expect_value(t, cue.event.card_upgrade_level, i32(4))
	}
	testing.expect_value(t, rolls, 1)
	update_event_timeline(&timeline, 1000)
	testing.expect_value(t, timeline.update_failures, 0)
	spell_presentation_expect_room(t, &timeline, &room)
	for level_shown in ([2]i32{0, 1}) {
		single: Presentation_Timeline
		event := game.Game_Event{kind = .Dice_Rolled, source = game.PLAYER_ENTITY, card_id = 1, card_definition = .Fate_Strike,
			card_upgrade_level = level_shown, dice_roll = {faces = {5, 0, 0}, total = 5, sides = 6, count = 1}, amount = 5}
		single.count = 1
		single.cues[0] = {kind = .Dice_Rolled, event = event, duration = presentation_cue_duration(.Dice_Rolled, event)}
		update_event_timeline(&single, 0.01)
		// A D6 is the die of level 1 only.
		testing.expect_value(t, single.update_failures, 1 if level_shown == 0 else 0)
	}
}
