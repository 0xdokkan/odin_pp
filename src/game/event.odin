package game

import grid "../grid"

// A dense 32-enemy command currently reaches 257 events before reaction headroom.
MAX_GAME_EVENTS :: 288

Game_Event_Kind :: enum {
	Damaged,
	Damage_Absorbed,
	Healed,
	Moved,
	Move_Blocked,
	Attack_Missed,
	Gold_Gained,
	Loot_Dropped,
	Loot_Collected,
	Card_Played,
	Card_Drawn,
	Entity_Defeated,
	Status_Applied,
	Status_Removed,
	Status_Expired,
	Reaction_Binding_Added,
	Reaction_Binding_Exhausted,
	Reaction_Binding_Expired,
	Pulse_Advanced,
}

Game_Event :: struct {
	kind:             Game_Event_Kind,
	source:           Entity_Ref,
	target:           Entity_Ref,
	amount:           i32,
	status:           Status_Kind,
	duration:         i32,
	from_position:    grid.Position,
	to_position:      grid.Position,
	loot_kind:        Loot_Kind,
	card_id:          u32,
	card_definition:  Card_Id,
	reaction:         Reaction_Id,
	binding_id:       u32,
	binding_source:   Reaction_Binding_Source,
	pulse_count:      u64,
	energy:           i32,
	statuses_advanced: bool,
}

Event_Log :: struct {
	events:        [MAX_GAME_EVENTS]Game_Event,
	count:         int,
	dropped_count: int,
}

clear_event_log :: proc(log: ^Event_Log) {
	if log != nil {
		log^ = {}
	}
}

record_event :: proc(log: ^Event_Log, event: Game_Event) -> bool {
	if log == nil || log.count < 0 || log.count >= MAX_GAME_EVENTS {
		if log != nil {
			log.dropped_count += 1
		}
		return false
	}
	log.events[log.count] = event
	log.count += 1
	return true
}

append_event_log :: proc(destination: ^Event_Log, source: ^Event_Log) {
	if destination == nil || source == nil {
		return
	}
	for index in 0..<source.count {
		record_event(destination, source.events[index])
	}
	destination.dropped_count += source.dropped_count
}
