package render

import "core:testing"
import game "../game"
import level "../level"

// Real plays exercise the distinction that the old overlay lost: the die's
// number, the base part of a spell and the tick bonus are different values.
@(test)
test_dice_overlay_reports_committed_card_effects_with_and_without_tick_bonus :: proc(t: ^testing.T) {
	for card in ([6]game.Card_Id{.Shock_Floor, .Venom_Blade, .Fate_Strike, .Twin_Venom, .Sundering_Blow, .Prismatic_Barrage}) {
		for critical in ([2]bool{false, true}) {
			data := create_encounter_presentation_test_level(t)
			player := spell_presentation_player(t, card)
			// All one-die cards show 3, including the critical floor that used
			// to claim "3 SCARICHE" while actually deploying four.
			for seed in u64(1)..=4096 {
				candidate := game.make_dice_state(seed)
				staged := candidate
				roll, rolled := game.roll_card_dice(&staged, player.deck.owned[0])
				if rolled && roll.faces[0] == 3 { player.dice = candidate; break }
			}
			enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 100, attack = 1}}
			room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
			testing.expect(t, ok)
			room.enemies[0].intent = game.make_wait_intent(&room, room.enemies[0].position)
			// Existing shield is included in the post-effect total, not claimed
			// as another bonus from this roll.
			if card == .Prismatic_Barrage {
				applied, _ := game.apply_status(&room, game.PLAYER_ENTITY, .Shield, 5, 3)
				testing.expect(t, applied)
			}
			before := capture_room_presentation(&room)
			expected_rng := player.dice
			expected_roll, rolled := game.roll_card_dice(&expected_rng, player.deck.hand[0])
			testing.expect(t, rolled)
			target := game.entity_target(game.enemy_entity(1))
			if card == .Shock_Floor { target = game.cell_target({x = 2, y = 1}) }
			if card == .Venom_Blade { target = game.entity_target(game.PLAYER_ENTITY) }
			player.tactical.critical_next = critical
			play := game.play_card(&room, player.deck.hand[0].id, target)
			testing.expectf(t, game.card_play_was_committed(play.result), "%v critical=%v: %v", card, critical, play.result)
			after := capture_room_presentation(&room)
			timeline: Presentation_Timeline
			testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
			spell_presentation_finish_group(t, &timeline)
			cue, found := active_presentation_cue(&timeline)
			if testing.expect(t, found && cue.kind == .Dice_Rolled) {
				testing.expect_value(t, cue.event.dice_roll, expected_roll)
				result := dice_presentation_outcome(&timeline)
				testing.expect(t, result.valid)
				testing.expect_value(t, result.critical, critical)
				#partial switch card {
				case .Shock_Floor:
					testing.expect_value(t, expected_roll.total, i32(3))
					testing.expect_value(t, result.charges, i32(4 if critical else 3))
					testing.expect_value(t, result.charges, room.objects[0].device_charges)
					testing.expect_value(t, result.targets, room.objects[0].device_target_limit)
					testing.expect_value(t, result.device_damage, room.objects[0].device_damage)
					text, _ := dice_outcome_text(card, result)
					testing.expect_value(t, string(text), "4 SCARICHE" if critical else "3 SCARICHE")
				case .Venom_Blade:
					testing.expect_value(t, result.charges, game.player_charges(&room, .Venom_Blade))
					testing.expect_value(t, result.charges, i32(4 if critical else 3))
				case:
					testing.expect_value(t, result.damage, 100-room.enemies[0].health)
					if card == .Prismatic_Barrage {
						status, applied := game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
						if result.shield > 0 { testing.expect(t, applied && result.shield == status.potency) }
					}
				}
				testing.expect_value(t, player.dice, expected_rng)
			}
			game.destroy_room(&room)
			level.destroy(&data)
		}
	}
}

@(test)
test_dice_outcome_keeps_shield_absorption_and_queued_commands_separate :: proc(t: ^testing.T) {
	timeline: Presentation_Timeline
	timeline.head, timeline.count = MAX_PRESENTATION_CUES-2, 5
	target := game.enemy_entity(1)
	events := [?]game.Game_Event{
		{kind = .Dice_Rolled, card_definition = .Fate_Strike, target = target},
		{kind = .Damage_Absorbed, source = game.PLAYER_ENTITY, target = target, amount = 2},
		{kind = .Damaged, source = game.PLAYER_ENTITY, target = target, amount = 3},
		{kind = .Card_Moved},
		{kind = .Damaged, source = game.PLAYER_ENTITY, target = target, amount = 99},
	}
	for event, offset in events {
		timeline.cues[(timeline.head+offset)%MAX_PRESENTATION_CUES] = {kind = presentation_cue_kind(event), event = event, batch = 1}
	}
	result := dice_presentation_outcome(&timeline)
	testing.expect(t, result.valid && result.damage == 3 && result.absorbed == 2)
	timeline.cues[0].batch = 2
	result = dice_presentation_outcome(&timeline)
	testing.expect(t, result.valid && result.damage == 0 && result.absorbed == 2)
	testing.expect_value(t, dice_presentation_outcome(nil), Dice_Outcome{})
	// The shield absorbing damage is separate from the card's other effect:
	// do not replace its poison, shield total or bounce caption with absorption.
	result = {valid = true, damage = 3, absorbed = 2, poison = 4, shield = 5, bounce_damage = 6}
	cards := [3]game.Card_Id{.Twin_Venom, .Prismatic_Barrage, .Fate_Strike}
	details := [3]string{"VELENO TOTALE 4", "SCUDO TOTALE 5", "RIMBALZO 6 DANNI"}
	for card, index in cards {
		primary, detail := dice_outcome_text(card, result)
		testing.expect_value(t, string(primary), "3 DANNI INFLITTI")
		testing.expect_value(t, string(detail), details[index])
	}
}
