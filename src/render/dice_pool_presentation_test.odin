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
		for seed in u64(1)..=256 {
			candidate := game.make_dice_state(seed)
			staged := candidate
			roll, valid := game.roll_d6_pool(&staged, 3)
			if valid && game.dice_success_count(&roll) == successes {
				player.dice, fixture = candidate, true
				break
			}
		}
		testing.expect(t, fixture)
		enemies := [?]game.Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}}
		room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		room.enemies[0].intent = game.make_wait_intent(&room, room.enemies[0].position)
		before := capture_room_presentation(&room)
		play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
		testing.expect(t, game.card_play_was_committed(play.result))
		after := capture_room_presentation(&room)
		timeline: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&timeline, before, &room.recent_events, &after))
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
	for seed in u64(1)..=256 {
		candidate := game.make_dice_state(seed)
		staged := candidate
		roll, valid := game.roll_d6_pool(&staged, 2)
		if valid && roll.total == 9 { player.dice = candidate; break }
	}
	enemies := [?]game.Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &room.recent_events, &after))
	roll_cues := 0
	for cue in timeline.cues[:timeline.count] { if cue.kind == .Dice_Rolled { roll_cues += 1 } }
	testing.expect_value(t, roll_cues, 1)
	spell_presentation_finish_group(t, &timeline)
	die, found := active_presentation_cue(&timeline)
	testing.expect(t, found)
	if !found { return }
	testing.expect_value(t, die.kind, Presentation_Cue_Kind.Dice_Rolled)
	testing.expect_value(t, die.event.dice_roll.count, 2)
	testing.expect_value(t, die.event.amount, i32(9))
	testing.expect_value(t, die.duration, presentation_cue_duration(.Dice_Rolled, {card_definition = .Fate_Strike}))
	update_event_timeline(&timeline, die.duration*0.94)
	actor, visible := presentation_actor(&timeline, game.enemy_entity(1))
	testing.expect(t, visible)
	if visible {
		testing.expect_value(t, actor.health, i32(40))
		testing.expect_value(t, actor.position, presentation_position({3, 1}))
	}
	testing.expect_value(t, room.enemies[0].health, i32(31))
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
