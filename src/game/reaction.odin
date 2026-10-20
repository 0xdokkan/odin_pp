package game

MAX_REACTION_QUEUE_EVENTS :: MAX_GAME_EVENTS
MAX_REACTIONS_PER_EVENT :: 8
MAX_REACTION_ACTIONS_PER_CHAIN :: 32

Reaction_Activation_Kind :: enum {
	Status,
	Binding,
}

Reaction_Request :: struct {
	definition_id: Reaction_Id,
	reactor:       Entity_Ref,
	trigger:       Game_Event,
	priority:      i32,
	activation:    Reaction_Activation_Kind,
	activation_id: u32,
}

Reaction_Batch :: struct {
	items:         [MAX_REACTIONS_PER_EVENT]Reaction_Request,
	count:         int,
	dropped_count: int,
}

Reaction_Event_Queue :: struct {
	items:         [MAX_REACTION_QUEUE_EVENTS]Game_Event,
	head:          int,
	count:         int,
	dropped_count: int,
}

@(private)
reaction_queue_push :: proc(queue: ^Reaction_Event_Queue, event: Game_Event) -> bool {
	if queue == nil || queue.head < 0 || queue.head >= MAX_REACTION_QUEUE_EVENTS ||
	   queue.count < 0 || queue.count >= MAX_REACTION_QUEUE_EVENTS {
		if queue != nil {
			queue.dropped_count += 1
		}
		return false
	}
	tail := (queue.head+queue.count)%MAX_REACTION_QUEUE_EVENTS
	queue.items[tail] = event
	queue.count += 1
	return true
}

@(private)
reaction_queue_pop :: proc(queue: ^Reaction_Event_Queue) -> (event: Game_Event, ok: bool) {
	if queue == nil || queue.head < 0 || queue.head >= MAX_REACTION_QUEUE_EVENTS ||
	   queue.count <= 0 || queue.count > MAX_REACTION_QUEUE_EVENTS {
		return {}, false
	}
	event = queue.items[queue.head]
	queue.items[queue.head] = {}
	queue.head = (queue.head+1)%MAX_REACTION_QUEUE_EVENTS
	queue.count -= 1
	return event, true
}

@(private)
add_reaction_request :: proc(batch: ^Reaction_Batch, request: Reaction_Request) -> bool {
	if batch == nil || batch.count < 0 || batch.count >= MAX_REACTIONS_PER_EVENT {
		if batch != nil {
			batch.dropped_count += 1
		}
		return false
	}
	batch.items[batch.count] = request
	batch.count += 1
	return true
}

@(private = "file")
reaction_request_precedes :: proc(left, right: Reaction_Request) -> bool {
	if left.priority != right.priority {
		return left.priority > right.priority
	}
	return int(left.definition_id) < int(right.definition_id)
}

@(private)
sort_reaction_batch :: proc(batch: ^Reaction_Batch) {
	if batch == nil || batch.count <= 1 || batch.count > MAX_REACTIONS_PER_EVENT {
		return
	}
	for index in 1..<batch.count {
		request := batch.items[index]
		insert_at := index
		for insert_at > 0 && reaction_request_precedes(request, batch.items[insert_at-1]) {
			batch.items[insert_at] = batch.items[insert_at-1]
			insert_at -= 1
		}
		batch.items[insert_at] = request
	}
}

@(private)
merge_reaction_action_report :: proc(destination, source: ^Action_Report) {
	assert(destination != nil && source != nil && source.accepted)
	destination.applied_effects += source.applied_effects
	destination.skipped_effects += source.skipped_effects
	destination.damage_dealt += source.damage_dealt
	destination.damage_absorbed += source.damage_absorbed
	destination.healing_done += source.healing_done
	destination.gold_gained += source.gold_gained
	destination.enemies_defeated += source.enemies_defeated
	destination.objects_destroyed += source.objects_destroyed
	destination.statuses_applied += source.statuses_applied
	destination.statuses_removed += source.statuses_removed
	destination.cards_drawn += source.cards_drawn
	destination.cards_discarded += source.cards_discarded
	destination.cards_created += source.cards_created
	destination.reaction_bindings_removed += source.reaction_bindings_removed
	destination.reaction_bindings_added += source.reaction_bindings_added
	destination.combat_ended = destination.combat_ended || source.combat_ended
	destination.player_defeated = destination.player_defeated || source.player_defeated
}

@(private)
dispatch_reactions :: proc(room: ^Room, report: ^Action_Report) {
	if room == nil || report == nil || !report.accepted {
		return
	}

	queue: Reaction_Event_Queue
	report.reaction_events_dropped += report.events.dropped_count
	for index in 0..<report.events.count {
		reaction_queue_push(&queue, report.events.events[index])
	}

	for queue.count > 0 {
		event, popped := reaction_queue_pop(&queue)
		assert(popped)
		report.reaction_events_processed += 1
		batch := collect_reactions(room, event)
		report.reactions_dropped += batch.dropped_count

		for index in 0..<batch.count {
			if report.reactions_triggered >= MAX_REACTION_ACTIONS_PER_CHAIN {
				report.reaction_limit_reached = true
				report.reactions_dropped += 1
				continue
			}
			action, built := build_reaction_action(room, batch.items[index])
			if !built {
				continue
			}
			reaction_report: Action_Report
			resolve_action_once(room, &action, &reaction_report)
			if !reaction_report.accepted {
				continue
			}

			report.reactions_triggered += 1
			for event_index in 0..<reaction_report.events.count {
				reaction_queue_push(&queue, reaction_report.events.events[event_index])
			}
			report.reaction_events_dropped += reaction_report.events.dropped_count
			merge_reaction_action_report(report, &reaction_report)
			append_event_log(&report.events, &reaction_report.events)

			if batch.items[index].activation == .Binding {
				binding_event, exhausted := consume_reaction_binding(
					room,
					batch.items[index].activation_id,
				)
				if exhausted {
					report.reaction_bindings_removed += 1
					reaction_queue_push(&queue, binding_event)
					record_report_event(report, binding_event)
				}
			}
		}
	}
	report.reaction_events_dropped += queue.dropped_count
}
