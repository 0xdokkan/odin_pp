package game

import grid "../grid"

// Multi-cell movement and neutral hazards need headroom beyond dense 32-enemy AoE.
MAX_GAME_EVENTS :: 416

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
	Card_Moved,
	Card_Created,
	Hand_Refocused,
	Card_Refocused,
	Movement_Step,
	Trap_Triggered,
	Hazard_Triggered,
	Object_Spawned,
	Explosive_Armed,
	Explosion,
	Explosive_Disarmed,
	Room_Hazard_Triggered,
	Energy_Gained,
	Dice_Rolled,
	Spell_Launched,
	Spell_Impact,
}

Game_Event :: struct {
	// Keep naturally aligned payloads together: the fixed event logs must stay
	// within their stack budget even when a cast carries three individual dice.
	kind:             Game_Event_Kind,
	source:           Entity_Ref,
	target:           Entity_Ref,
	dice_roll:        Dice_Roll,
	status_cause:     Status_Kind,
	status:           Status_Kind,
	from_position:    grid.Position,
	to_position:      grid.Position,
	loot_kind:        Loot_Kind,
	object_kind:      Grid_Object_Kind,
	card_definition:  Card_Id,
	card_lifetime:      Card_Lifetime,
	from_card_zone:     Card_Zone,
	to_card_zone:       Card_Zone,
	reaction:         Reaction_Id,
	binding_source:   Reaction_Binding_Source,
	pulse_count:      u64,
	visual_group:     u32,
	amount:           i32,
	duration:         i32,
	card_id:          u32,
	card_upgrade_level: i32,
	binding_id:       u32,
	energy:           i32,
	energy_restored:  i32,
	energy_wasted:    i32,
	// Row-major bits of a spell's 3x3 footprint, captured before its effects.
	area_mask:        u16,
	has_status_cause: bool,
	statuses_advanced: bool,
}

// The 3x3 footprint uses nine bits of area_mask; its top bit marks an action
// played on the tick (tactical_beat.odin) without growing every event log.
EVENT_CRITICAL_BIT :: u16(1)<<15

event_is_critical :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_CRITICAL_BIT != 0
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

// Contratto dei chiamanti: un comando che accumula eventi in un log staged
// prima del commit tratta un ritorno false come fallimento della transazione;
// dopo il commit gli eventi in eccesso vengono solo scartati e contati in
// dropped_count, e non possono mai annullare una mutazione autorevole.
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
