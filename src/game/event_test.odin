package game

import "core:testing"

@(test)
test_event_log_composes_a_dense_maximum_room_pipeline_without_drops :: proc(t: ^testing.T) {
	segment: Event_Log
	combined: Event_Log

	testing.expect(t, record_event(&segment, {kind = .Card_Played}))
	testing.expect(t, record_event(&segment, {kind = .Card_Moved}))
	for index in 0..<MAX_ENEMIES_PER_ROOM {
		enemy := enemy_entity(u32(index+1))
		testing.expect(t, record_event(&segment, {
			kind = .Status_Applied,
			target = enemy,
		}))
	}
	append_event_log(&combined, &segment)
	clear_event_log(&segment)

	for index in 0..<MAX_ENEMIES_PER_ROOM {
		enemy := enemy_entity(u32(index+1))
		testing.expect(t, record_event(&segment, {
			kind = .Moved,
			target = enemy,
		}))
	}
	append_event_log(&combined, &segment)
	clear_event_log(&segment)

	for index in 0..<MAX_ENEMIES_PER_ROOM {
		enemy := enemy_entity(u32(index+1))
		testing.expect(t, record_event(&segment, {
			kind = .Damaged,
			target = enemy,
		}))
		testing.expect(t, record_event(&segment, {
			kind = .Entity_Defeated,
			target = enemy,
		}))
		testing.expect(t, record_event(&segment, {
			kind = .Loot_Dropped,
			source = enemy,
			loot_kind = .Gold,
			amount = 1,
		}))
		if enemy.id%3 == 0 {
			testing.expect(t, record_event(&segment, {
				kind = .Loot_Dropped,
				source = enemy,
				loot_kind = .Healing,
				amount = 2,
			}))
		}
	}
	append_event_log(&combined, &segment)
	clear_event_log(&segment)

	for index in 0..<MAX_ENEMIES_PER_ROOM {
		enemy := enemy_entity(u32(index+1))
		testing.expect(t, record_event(&segment, {
			kind = .Loot_Collected,
			target = PLAYER_ENTITY,
			loot_kind = .Gold,
		}))
		testing.expect(t, record_event(&segment, {
			kind = .Gold_Gained,
			target = PLAYER_ENTITY,
		}))
		if enemy.id%3 == 0 {
			testing.expect(t, record_event(&segment, {
				kind = .Loot_Collected,
				target = PLAYER_ENTITY,
				loot_kind = .Healing,
			}))
			testing.expect(t, record_event(&segment, {
				kind = .Healed,
				target = PLAYER_ENTITY,
			}))
		}
	}
	append_event_log(&combined, &segment)
	clear_event_log(&segment)

	testing.expect(t, record_event(&segment, {kind = .Pulse_Advanced}))
	testing.expect(t, record_event(&segment, {kind = .Card_Drawn}))
	append_event_log(&combined, &segment)

	healing_drop_count := MAX_ENEMIES_PER_ROOM/3
	drop_count := MAX_ENEMIES_PER_ROOM+healing_drop_count
	expected_count := 2+MAX_ENEMIES_PER_ROOM*2+MAX_ENEMIES_PER_ROOM*2+drop_count+drop_count*2+2
	testing.expect_value(t, expected_count, 258)
	testing.expect_value(t, MAX_GAME_EVENTS-expected_count, 158)
	testing.expect_value(t, combined.count, expected_count)
	testing.expect_value(t, combined.dropped_count, 0)
	testing.expect_value(t, combined.events[0].kind, Game_Event_Kind.Card_Played)
	testing.expect_value(t, combined.events[1].kind, Game_Event_Kind.Card_Moved)
	testing.expect_value(t, combined.events[2].kind, Game_Event_Kind.Status_Applied)
	enemy_actions_start := 2+MAX_ENEMIES_PER_ROOM
	testing.expect_value(t, combined.events[enemy_actions_start].kind, Game_Event_Kind.Moved)
	status_ticks_start := enemy_actions_start+MAX_ENEMIES_PER_ROOM
	testing.expect_value(t, combined.events[status_ticks_start].kind, Game_Event_Kind.Damaged)
	loot_start := status_ticks_start+MAX_ENEMIES_PER_ROOM*2+drop_count
	testing.expect_value(t, combined.events[loot_start].kind, Game_Event_Kind.Loot_Collected)
	testing.expect_value(t, combined.events[combined.count-2].kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, combined.events[combined.count-1].kind, Game_Event_Kind.Card_Drawn)
}

@(test)
test_spatial_events_append_without_changing_existing_ordinals :: proc(t: ^testing.T) {
	testing.expect_value(t, int(Game_Event_Kind.Moved), 3)
	testing.expect_value(t, int(Game_Event_Kind.Card_Refocused), 22)
	testing.expect_value(t, int(Game_Event_Kind.Movement_Step), 23)
	testing.expect_value(t, int(Game_Event_Kind.Trap_Triggered), 24)
}

@(test)
test_inline_event_storage_stays_within_the_stack_budget :: proc(t: ^testing.T) {
	testing.expect(t, size_of(Event_Log) <= 96*1024)
	testing.expect(t, size_of(Action_Report) <= 96*1024)
	testing.expect(t, size_of(Pulse_Report) <= 96*1024)
	testing.expect(t, size_of(Reaction_Event_Queue) <= 96*1024)
	testing.expect(t, size_of(Card_Play_Report) <= 192*1024)
}

@(test)
test_event_log_reports_overflow_beyond_fixed_capacity :: proc(t: ^testing.T) {
	log: Event_Log
	for _ in 0..<MAX_GAME_EVENTS {
		testing.expect(t, record_event(&log, {kind = .Moved}))
	}

	testing.expect(t, !record_event(&log, {kind = .Card_Drawn}))
	testing.expect_value(t, log.count, MAX_GAME_EVENTS)
	testing.expect_value(t, log.dropped_count, 1)
	testing.expect_value(t, log.events[MAX_GAME_EVENTS-1].kind, Game_Event_Kind.Moved)
}

@(test)
test_refocus_event_envelope_preserves_fifo_without_changing_existing_ordinals :: proc(t: ^testing.T) {
	log: Event_Log
	testing.expect(t, int(Game_Event_Kind.Hand_Refocused) > int(Game_Event_Kind.Card_Created))
	testing.expect(t, int(Game_Event_Kind.Card_Refocused) > int(Game_Event_Kind.Card_Created))
	testing.expect(t, record_event(&log, {
		kind = .Hand_Refocused,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		amount = i32(MAX_HAND_CARDS),
	}))
	for index in 0..<MAX_HAND_CARDS {
		testing.expect(t, record_event(&log, {
			kind = .Card_Refocused,
			card_id = u32(index+1),
			from_card_zone = .Hand,
			to_card_zone = .Discard,
		}))
	}
	testing.expect(t, record_event(&log, {kind = .Pulse_Advanced}))
	for index in 0..<MAX_HAND_CARDS {
		testing.expect(t, record_event(&log, {
			kind = .Card_Drawn,
			card_id = u32(index+1),
			from_card_zone = .Draw,
			to_card_zone = .Hand,
		}))
	}

	testing.expect_value(t, log.count, 2+MAX_HAND_CARDS*2)
	testing.expect_value(t, log.dropped_count, 0)
	testing.expect_value(t, log.events[0].kind, Game_Event_Kind.Hand_Refocused)
	testing.expect_value(t, log.events[MAX_HAND_CARDS].kind, Game_Event_Kind.Card_Refocused)
	testing.expect_value(t, log.events[MAX_HAND_CARDS+1].kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, log.events[log.count-1].kind, Game_Event_Kind.Card_Drawn)
}
