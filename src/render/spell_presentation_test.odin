package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

spell_presentation_player :: proc(t: ^testing.T, definition: game.Card_Id) -> game.Player {
	player, ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, ok)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	_, added := game.add_owned_card(&player.deck, definition)
	testing.expect(t, added)
	return player
}

// The next roll of an unupgraded dice card shows the D4's top face.
spell_presentation_top_face :: proc(t: ^testing.T) -> game.Dice_State {
	for seed in u64(1)..<u64(1000) {
		dice := game.make_dice_state(seed)
		staged := dice
		face, ok := game.roll_die(&staged, 4)
		if ok && face == 4 { return dice }
	}
	testing.expect(t, false, "missing deterministic top face fixture")
	return game.make_dice_state(1)
}

spell_presentation_finish_group :: proc(t: ^testing.T, timeline: ^Presentation_Timeline) {
	current, found := active_presentation_cue(timeline)
	testing.expect(t, found)
	if !found { return }
	span := presentation_group_size(timeline)
	count_before := timeline.count
	update_event_timeline(timeline, current.duration-current.elapsed)
	testing.expect_value(t, timeline.count, count_before-span)
}

spell_presentation_expect_room :: proc(t: ^testing.T, timeline: ^Presentation_Timeline, room: ^game.Room) {
	testing.expect(t, !event_timeline_is_busy(timeline))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
	testing.expect_value(t, timeline.view.player.health, room.player.health)
	testing.expect_value(t, timeline.view.player.position, presentation_position(room.player.position))
	testing.expect_value(t, timeline.view.player.statuses, room.player.statuses)
	testing.expect_value(t, timeline.view.phase, room.phase)
	testing.expect_value(t, timeline.view.pulse_count, room.pulse_count)
	testing.expect_value(t, timeline.view.gold, room.player.gold)
	testing.expect_value(t, timeline.view.deck, room.player.deck)
	for enemy in room.enemies {
		actor, found := presentation_actor(timeline, game.enemy_entity(enemy.id))
		testing.expect(t, found && actor.visible)
		if !found { continue }
		testing.expect_value(t, actor.health, enemy.health)
		testing.expect_value(t, actor.statuses, enemy.statuses)
		testing.expect_value(t, actor.position, presentation_position(enemy.position))
	}
}

@(test)
test_spell_firebomb_group_starts_all_damage_shield_death_and_loot_before_reactions :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Firebomb)
	enemies := [?]game.Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 8, attack = 1},
		{position = {x = 4, y = 1}, health = 1, attack = 1, drops_healing = true},
		{position = {x = 3, y = 2}, health = 8, attack = 1},
	}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	applied, _ := game.apply_status(&room, game.enemy_entity(1), .Shield, 1, 3)
	testing.expect(t, applied)
	applied, _ = game.apply_status(&room, game.enemy_entity(1), .Thorns, 1, 3)
	testing.expect(t, applied)
	definition, _ := game.card_definition_by_id(.Firebomb)
	footprint := game.evaluate_card_targeting(&room, player.deck.hand[0], game.card_target_request_at(definition, {x = 3, y = 1}))
	testing.expect_value(t, footprint.error, game.Card_Compile_Error.None)
	expected_mask: u16
	for dy in -1..=1 {
		for dx in -1..=1 {
			if game.target_cell_set_contains(&footprint.query.affected, {x = 3+dx, y = 1+dy}) {
				expected_mask |= u16(1)<<u32((dy+1)*3+dx+1)
			}
		}
	}
	// The top row lies inside the boundary wall, so exactly six floor cells flash.
	testing.expect_value(t, expected_mask, u16(0b111111000))
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.cell_target({x = 3, y = 1}))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	testing.expect_value(t, play.action_report.events.events[1].kind, game.Game_Event_Kind.Spell_Impact)
	testing.expect_value(t, play.action_report.events.events[1].area_mask, expected_mask)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	for event_timeline_is_busy(&timeline) && timeline.cues[timeline.head].event.visual_group == 0 {
		if timeline.cues[timeline.head].kind == .Spell_Impact {
			testing.expect_value(t, timeline.cues[timeline.head].event.area_mask, expected_mask)
		}
		spell_presentation_finish_group(t, &timeline)
	}
	testing.expect(t, event_timeline_is_busy(&timeline))
	span := presentation_group_size(&timeline)
	testing.expect_value(t, span, 8)
	first, first_found := presentation_actor(&timeline, game.enemy_entity(1))
	dead, dead_found := presentation_actor(&timeline, game.enemy_entity(2))
	third, third_found := presentation_actor(&timeline, game.enemy_entity(3))
	testing.expect(t, first_found && dead_found && third_found)
	testing.expect_value(t, first.health, i32(8))
	testing.expect_value(t, third.health, i32(8))
	update_event_timeline(&timeline, 0.001)
	testing.expect_value(t, first.health, i32(7))
	testing.expect_value(t, third.health, i32(6))
	testing.expect_value(t, dead.health, i32(0))
	testing.expect(t, dead.visible)
	_, shielded := game.status_index(&first.statuses, .Shield)
	testing.expect(t, !shielded)
	testing.expect_value(t, timeline.view.player.health, i32(20))
	visible_drops := 0
	for drop in timeline.view.loot[:timeline.view.loot_count] {
		if drop.visible && drop.position == (grid.Position{x = 4, y = 1}) { visible_drops += 1 }
	}
	testing.expect_value(t, visible_drops, 2)
	for offset in 0..<span {
		member, _ := presentation_cue_at(&timeline, offset)
		testing.expect(t, member.started)
		testing.expect_value(t, member.elapsed, f32(0.001))
	}
	spell_presentation_finish_group(t, &timeline)
	testing.expect(t, !dead.visible)
	testing.expect_value(t, timeline.view.player.health, i32(20))
	counter, counter_found := active_presentation_cue(&timeline)
	testing.expect(t, counter_found)
	testing.expect_value(t, counter.kind, Presentation_Cue_Kind.Damage)
	testing.expect_value(t, counter.event.target, game.PLAYER_ENTITY)
	testing.expect_value(t, counter.event.visual_group, u32(0))
	update_event_timeline(&timeline, 0.001)
	testing.expect_value(t, timeline.view.player.health, i32(19))
	update_event_timeline(&timeline, 1000)
	spell_presentation_expect_room(t, &timeline, &room)
}

@(test)
test_spell_firebomb_direct_cast_duration_does_not_scale_with_damage_target_count :: proc(t: ^testing.T) {
	baseline: f32
	for target_count in 1..=3 {
		data := create_encounter_presentation_test_level(t)
		player := spell_presentation_player(t, .Firebomb)
		enemies := [?]game.Enemy_Spawn{
			{position = {x = 3, y = 1}, health = 30, attack = 1},
			{position = {x = 4, y = 1}, health = 30, attack = 1},
			{position = {x = 3, y = 2}, health = 30, attack = 1},
		}
		room, ok := game.create_room(&data, &player, {enemies = enemies[:target_count]})
		testing.expect(t, ok)
		before := capture_room_presentation(&room)
		play := game.play_card(&room, player.deck.hand[0].id, game.cell_target({x = 3, y = 1}))
		testing.expect_value(t, play.result, game.Card_Play_Result.Played)
		after := capture_room_presentation(&room)
		timeline: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
		duration: f32
		direct_groups := 0
		for offset := 0; offset < timeline.count; {
			cue, _ := presentation_cue_at(&timeline, offset)
			if cue.kind == .Card_Moved { break }
			span := presentation_group_size(&timeline, offset)
			duration += cue.duration
			if cue.event.visual_group != 0 {
				direct_groups += 1
				testing.expect_value(t, span, target_count)
			}
			offset += span
		}
		testing.expect_value(t, direct_groups, 1)
		if target_count == 1 { baseline = duration }
		testing.expect_value(t, duration, baseline)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_spell_fate_die_cue_preserves_health_until_impacts_and_replays_final_deck :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Fate_Strike)
	player.dice = spell_presentation_top_face(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}, {position = {x = 4, y = 1}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	spell_presentation_finish_group(t, &timeline)
	die, found := active_presentation_cue(&timeline)
	testing.expect(t, found)
	testing.expect_value(t, die.kind, Presentation_Cue_Kind.Dice_Rolled)
	testing.expect_value(t, die.event.amount, i32(4))
	update_event_timeline(&timeline, 0.1)
	first, _ := presentation_actor(&timeline, game.enemy_entity(1))
	second, _ := presentation_actor(&timeline, game.enemy_entity(2))
	testing.expect_value(t, first.health, i32(40))
	testing.expect_value(t, second.health, i32(40))
	testing.expect_value(t, timeline.view.deck.energy, i32(1))
	testing.expect_value(t, timeline.view.pulse_count, u64(0))
	testing.expect_value(t, room.enemies[0].health, i32(34))
	testing.expect_value(t, room.enemies[1].health, i32(37))
	update_event_timeline(&timeline, 1000)
	spell_presentation_expect_room(t, &timeline, &room)
}

@(test)
test_spell_chain_replays_visible_impacts_before_the_next_world_beat :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Chain_Lightning)
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}, {position = {x = 4, y = 1}, health = 40, attack = 1}, {position = {x = 5, y = 1}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(game.enemy_entity(1)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	impacts, damage_hits, pulses := 0, 0, 0
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		if cue.kind == .Spell_Impact {
			impacts += 1
			testing.expect_value(t, damage_hits, impacts-1)
			testing.expect_value(t, cue.event.target, game.enemy_entity(u32(impacts)))
			actor, _ := presentation_actor(&timeline, cue.event.target)
			testing.expect_value(t, actor.health, i32(40))
		}
		spell_presentation_finish_group(t, &timeline)
		if cue.kind == .Damage && cue.event.source == game.PLAYER_ENTITY {
			damage_hits += 1
			testing.expect_value(t, impacts, damage_hits)
			actor, _ := presentation_actor(&timeline, cue.event.target)
			testing.expect_value(t, actor.health, i32(37))
		}
		if cue.kind == .Pulse_Advanced {
			pulses += 1
			testing.expect_value(t, damage_hits, 2)
		}
	}
	testing.expect_value(t, impacts, 2)
	testing.expect_value(t, damage_hits, 2)
	testing.expect_value(t, pulses, 1)
	spell_presentation_expect_room(t, &timeline, &room)
}

@(test)
test_spell_replay_large_dt_and_small_steps_produce_identical_final_state :: proc(t: ^testing.T) {
	for definition in ([3]game.Card_Id{.Firebomb, .Fate_Strike, .Chain_Lightning}) {
		data := create_encounter_presentation_test_level(t)
		player := spell_presentation_player(t, definition)
		player.dice = spell_presentation_top_face(t)
		enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}, {position = {x = 4, y = 1}, health = 40, attack = 1}, {position = {x = 3, y = 2}, health = 40, attack = 1}}
		room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		before := capture_room_presentation(&room)
		target := game.cell_target({x = 3, y = 1}) if definition == .Firebomb else game.entity_target(game.enemy_entity(1))
		play := game.play_card(&room, player.deck.hand[0].id, target)
		testing.expect_value(t, play.result, game.Card_Play_Result.Played)
		after := capture_room_presentation(&room)
		fast, slow: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&fast, before, room.recent_events, &after))
		testing.expect(t, begin_event_timeline(&slow, before, room.recent_events, &after))
		update_event_timeline(&fast, 1000)
		for _ in 0..<10000 {
			if !event_timeline_is_busy(&slow) { break }
			update_event_timeline(&slow, 0.005)
		}
		spell_presentation_expect_room(t, &fast, &room)
		spell_presentation_expect_room(t, &slow, &room)
		testing.expect_value(t, fast.view, slow.view)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}
