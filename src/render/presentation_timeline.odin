package render

import game "../game"
import grid "../grid"
import view "../view"

MAX_PRESENTATION_CUES :: game.MAX_GAME_EVENTS
MAX_PRESENTATION_LOOT :: game.MAX_ENEMIES_PER_ROOM*2
MAX_PRESENTATION_TRAPS :: 64

// Values above one slow every cue while preserving their relative rhythm.
PRESENTATION_TIME_SCALE           :: f32(1.35)
PRESENTATION_PLAYER_MOVE_DURATION :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_ENEMY_MOVE_DURATION  :: f32(0.32)*PRESENTATION_TIME_SCALE
PRESENTATION_DAMAGE_DURATION      :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_HEAL_DURATION        :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_STATUS_DURATION      :: f32(0.14)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_PLAY_DURATION   :: f32(0.20)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_DRAW_DURATION   :: f32(0.12)*PRESENTATION_TIME_SCALE
PRESENTATION_DEFEAT_DURATION      :: f32(0.22)*PRESENTATION_TIME_SCALE
PRESENTATION_LOOT_DURATION        :: f32(0.28)*PRESENTATION_TIME_SCALE
PRESENTATION_NOTICE_DURATION      :: f32(0.12)*PRESENTATION_TIME_SCALE
PRESENTATION_PULSE_DURATION       :: f32(0.06)*PRESENTATION_TIME_SCALE
PRESENTATION_TIME_EPSILON         :: f32(0.00001)

Presentation_Cue_Kind :: enum {
	Move,
	Damage,
	Damage_Absorbed,
	Heal,
	Status_Applied,
	Status_Removed,
	Status_Expired,
	Card_Played,
	Card_Drawn,
	Defeat,
	Loot_Dropped,
	Loot,
	Attack_Missed,
	Move_Blocked,
	Gold_Gained,
	Binding_Added,
	Binding_Exhausted,
	Binding_Expired,
	Pulse_Advanced,
}

Presentation_Actor :: struct {
	entity:     game.Entity_Ref,
	archetype:  game.Enemy_Archetype,
	position:   view.Vec2,
	health:     i32,
	max_health: i32,
	statuses:   game.Status_Set,
	opacity:    f32,
	visible:    bool,
}

Presentation_Loot :: struct {
	position: grid.Position,
	kind:     game.Loot_Kind,
	amount:   i32,
	visible:  bool,
}

Room_Presentation :: struct {
	phase:       game.Room_Phase,
	player:      Presentation_Actor,
	deck:        game.Deck_State,
	enemies:     [game.MAX_ENEMIES_PER_ROOM]Presentation_Actor,
	enemy_count: int,
	traps:       [MAX_PRESENTATION_TRAPS]game.Trap,
	trap_count:  int,
	loot:        [MAX_PRESENTATION_LOOT]Presentation_Loot,
	loot_count:  int,
	gold:        i32,
	pulse_count: u64,
	valid:       bool,
	dropped:     int,
}

Presentation_Cue :: struct {
	kind:     Presentation_Cue_Kind,
	event:    game.Game_Event,
	elapsed:  f32,
	duration: f32,
	started:  bool,
}

Presentation_Timeline :: struct {
	cues:           [MAX_PRESENTATION_CUES]Presentation_Cue,
	head:           int,
	count:          int,
	dropped_count:  int,
	update_failures: int,
	view:           Room_Presentation,
	final_view:     Room_Presentation,
}

presentation_position :: proc(position: grid.Position) -> view.Vec2 {
	return {x = f32(position.x), y = f32(position.y)}
}

capture_room_presentation :: proc(room: ^game.Room) -> (result: Room_Presentation) {
	if room == nil || room.player == nil {
		return
	}
	result.valid = true
	result.phase = room.phase
	result.gold = room.player.gold
	result.pulse_count = room.pulse_count
	result.deck = room.player.deck
	result.player = {
		entity = game.PLAYER_ENTITY,
		position = presentation_position(room.player.position),
		health = room.player.health,
		max_health = room.player.stats.max_health,
		statuses = room.player.statuses,
		opacity = 1,
		visible = true,
	}

	result.enemy_count = min(len(room.enemies), game.MAX_ENEMIES_PER_ROOM)
	result.dropped += max(0, len(room.enemies)-result.enemy_count)
	for index in 0..<result.enemy_count {
		enemy := room.enemies[index]
		result.enemies[index] = {
			entity = game.enemy_entity(enemy.id),
			archetype = enemy.archetype,
			position = presentation_position(enemy.position),
			health = enemy.health,
			max_health = enemy.max_health,
			statuses = enemy.statuses,
			opacity = 1,
			visible = true,
		}
	}
	result.trap_count = min(len(room.traps), MAX_PRESENTATION_TRAPS)
	result.dropped += max(0, len(room.traps)-result.trap_count)
	for index in 0..<result.trap_count {
		result.traps[index] = room.traps[index]
	}

	result.loot_count = min(len(room.loot), MAX_PRESENTATION_LOOT)
	result.dropped += max(0, len(room.loot)-result.loot_count)
	for index in 0..<result.loot_count {
		item := room.loot[index]
		result.loot[index] = {
			position = item.position,
			kind = item.kind,
			amount = item.amount,
			visible = true,
		}
	}
	return
}

presentation_actor_in_view :: proc(
	presentation: ^Room_Presentation,
	entity: game.Entity_Ref,
) -> (^Presentation_Actor, bool) {
	if presentation == nil || !presentation.valid {
		return nil, false
	}
	if entity == game.PLAYER_ENTITY {
		return &presentation.player, true
	}
	if entity.kind != .Enemy || entity.id == 0 ||
	   presentation.enemy_count < 0 || presentation.enemy_count > len(presentation.enemies) {
		return nil, false
	}
	for index in 0..<presentation.enemy_count {
		if presentation.enemies[index].entity == entity {
			return &presentation.enemies[index], true
		}
	}
	return nil, false
}

presentation_actor :: proc(
	timeline: ^Presentation_Timeline,
	entity: game.Entity_Ref,
) -> (^Presentation_Actor, bool) {
	if timeline == nil {
		return nil, false
	}
	return presentation_actor_in_view(&timeline.view, entity)
}

presentation_trap :: proc(
	presentation: ^Room_Presentation,
	id: u32,
) -> (^game.Trap, bool) {
	if presentation == nil || !presentation.valid || id == 0 || presentation.trap_count < 0 ||
	   presentation.trap_count > len(presentation.traps) {
		return nil, false
	}
	for index in 0..<presentation.trap_count {
		if presentation.traps[index].id == id {
			return &presentation.traps[index], true
		}
	}
	return nil, false
}

visible_presentation_enemy_count :: proc(presentation: ^Room_Presentation) -> int {
	if presentation == nil || !presentation.valid ||
	   presentation.enemy_count < 0 || presentation.enemy_count > len(presentation.enemies) {
		return 0
	}
	result := 0
	for index in 0..<presentation.enemy_count {
		if presentation.enemies[index].visible {
			result += 1
		}
	}
	return result
}

presentation_cue_kind :: proc(event: game.Game_Event) -> Presentation_Cue_Kind {
	switch event.kind {
	case .Damaged:
		return .Damage
	case .Damage_Absorbed:
		return .Damage_Absorbed
	case .Healed:
		return .Heal
	case .Moved:
		return .Move
	case .Move_Blocked:
		return .Move_Blocked
	case .Attack_Missed:
		return .Attack_Missed
	case .Gold_Gained:
		return .Gold_Gained
	case .Loot_Dropped:
		return .Loot_Dropped
	case .Loot_Collected:
		return .Loot
	case .Card_Played:
		return .Card_Played
	case .Card_Drawn:
		return .Card_Drawn
	case .Entity_Defeated:
		return .Defeat
	case .Status_Applied:
		return .Status_Applied
	case .Status_Removed:
		return .Status_Removed
	case .Status_Expired:
		return .Status_Expired
	case .Reaction_Binding_Added:
		return .Binding_Added
	case .Reaction_Binding_Exhausted:
		return .Binding_Exhausted
	case .Reaction_Binding_Expired:
		return .Binding_Expired
	case .Pulse_Advanced:
		return .Pulse_Advanced
	}
	unreachable()
}

presentation_cue_duration :: proc(kind: Presentation_Cue_Kind, event: game.Game_Event) -> f32 {
	switch kind {
	case .Move:
		if event.target.kind == .Enemy {
			return PRESENTATION_ENEMY_MOVE_DURATION
		}
		return PRESENTATION_PLAYER_MOVE_DURATION
	case .Damage:
		return PRESENTATION_DAMAGE_DURATION
	case .Heal:
		return PRESENTATION_HEAL_DURATION
	case .Status_Applied, .Status_Removed, .Status_Expired, .Damage_Absorbed,
	     .Binding_Added, .Binding_Exhausted, .Binding_Expired:
		return PRESENTATION_STATUS_DURATION
	case .Card_Played:
		return PRESENTATION_CARD_PLAY_DURATION
	case .Card_Drawn:
		return PRESENTATION_CARD_DRAW_DURATION
	case .Defeat:
		return PRESENTATION_DEFEAT_DURATION
	case .Loot:
		return PRESENTATION_LOOT_DURATION
	case .Attack_Missed, .Move_Blocked, .Gold_Gained, .Loot_Dropped:
		return PRESENTATION_NOTICE_DURATION
	case .Pulse_Advanced:
		return PRESENTATION_PULSE_DURATION
	}
	unreachable()
}

event_timeline_is_busy :: proc(timeline: ^Presentation_Timeline) -> bool {
	return timeline != nil && timeline.count > 0 && timeline.count <= MAX_PRESENTATION_CUES &&
	       timeline.head >= 0 && timeline.head < MAX_PRESENTATION_CUES
}

clear_event_timeline :: proc(timeline: ^Presentation_Timeline) {
	if timeline != nil {
		timeline^ = {}
	}
}

begin_event_timeline :: proc(
	timeline: ^Presentation_Timeline,
	before: Room_Presentation,
	events: ^game.Event_Log,
	after: ^Room_Presentation = nil,
) -> (started: bool) {
	if timeline == nil || event_timeline_is_busy(timeline) {
		return false
	}
	clear_event_timeline(timeline)
	timeline.view = before
	timeline.dropped_count = max(0, before.dropped)
	if after != nil {
		timeline.final_view = after^
		timeline.dropped_count += max(0, after.dropped)
	}
	if events == nil {
		return false
	}

	timeline.dropped_count += max(0, events.dropped_count)
	if events.count < 0 {
		timeline.dropped_count += 1
		return false
	}
	event_count := min(events.count, len(events.events))
	timeline.dropped_count += max(0, events.count-event_count)
	for index in 0..<event_count {
		if timeline.count >= MAX_PRESENTATION_CUES {
			timeline.dropped_count += event_count-index
			break
		}
		event := events.events[index]
		kind := presentation_cue_kind(event)
		tail := (timeline.head+timeline.count)%MAX_PRESENTATION_CUES
		timeline.cues[tail] = {
			kind = kind,
			event = event,
			duration = presentation_cue_duration(kind, event),
		}
		timeline.count += 1
	}
	return timeline.count > 0
}

presentation_cue_at :: proc(
	timeline: ^Presentation_Timeline,
	offset: int,
) -> (^Presentation_Cue, bool) {
	if !event_timeline_is_busy(timeline) || offset < 0 || offset >= timeline.count {
		return nil, false
	}
	index := (timeline.head+offset)%MAX_PRESENTATION_CUES
	return &timeline.cues[index], true
}

active_presentation_cue :: proc(timeline: ^Presentation_Timeline) -> (^Presentation_Cue, bool) {
	return presentation_cue_at(timeline, 0)
}

presentation_cue_progress :: proc(cue: ^Presentation_Cue) -> f32 {
	if cue == nil || cue.duration <= 0 {
		return 0
	}
	return clamp(cue.elapsed/cue.duration, f32(0), f32(1))
}

presentation_cue_eased_progress :: proc(cue: ^Presentation_Cue) -> f32 {
	linear := presentation_cue_progress(cue)
	return linear*linear*(3-2*linear)
}

active_presentation_cue_progress :: proc(timeline: ^Presentation_Timeline) -> f32 {
	if cue, found := active_presentation_cue(timeline); found {
		return presentation_cue_progress(cue)
	}
	return 0
}

remove_presentation_status :: proc(statuses: ^game.Status_Set, kind: game.Status_Kind) -> bool {
	if statuses == nil {
		return false
	}
	index, found := game.status_index(statuses, kind)
	if !found {
		return false
	}
	for current in index..<statuses.count-1 {
		statuses.items[current] = statuses.items[current+1]
	}
	statuses.count -= 1
	statuses.items[statuses.count] = {}
	return true
}

apply_presentation_status :: proc(
	statuses: ^game.Status_Set,
	kind: game.Status_Kind,
	potency, duration: i32,
) -> bool {
	if statuses == nil || !game.status_kind_is_valid(kind) || potency <= 0 || duration <= 0 ||
	   statuses.count < 0 || statuses.count > len(statuses.items) {
		return false
	}
	if index, found := game.status_index(statuses, kind); found {
		statuses.items[index].potency = potency
		statuses.items[index].remaining_pulses = duration
		return true
	}
	if statuses.count >= len(statuses.items) {
		return false
	}
	statuses.items[statuses.count] = {
		kind = kind,
		potency = potency,
		remaining_pulses = duration,
	}
	statuses.count += 1
	return true
}

hide_collected_presentation_loot :: proc(
	presentation: ^Room_Presentation,
	event: game.Game_Event,
) {
	if presentation == nil || presentation.loot_count < 0 ||
	   presentation.loot_count > len(presentation.loot) {
		return
	}
	for index in 0..<presentation.loot_count {
		item := &presentation.loot[index]
		if item.visible && item.position == event.from_position && item.kind == event.loot_kind &&
		   item.amount == event.amount {
			item.visible = false
			return
		}
	}
}

show_dropped_presentation_loot :: proc(
	presentation: ^Room_Presentation,
	event: game.Game_Event,
) -> bool {
	if presentation == nil || presentation.loot_count < 0 ||
	   presentation.loot_count >= len(presentation.loot) || event.amount <= 0 {
		if presentation != nil {
			presentation.dropped += 1
		}
		return false
	}
	presentation.loot[presentation.loot_count] = {
		position = event.from_position,
		kind = event.loot_kind,
		amount = event.amount,
		visible = true,
	}
	presentation.loot_count += 1
	return true
}

apply_presentation_card_played :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.amount < 0 || event.amount > deck.energy {
		return false
	}
	hand_index, found := game.hand_card_index_by_id(deck, event.card_id)
	if !found {
		return false
	}
	card := deck.hand[hand_index]
	if !game.validate_card_instance(card) || card.definition_id != event.card_definition {
		return false
	}

	before := deck^
	deck.energy -= event.amount
	discarded_card, discarded := game.discard_hand_card(deck, hand_index)
	if !discarded || discarded_card != card || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}

apply_presentation_card_drawn :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) {
		return false
	}
	before := deck^
	drawn_card, drawn := game.draw_card(deck)
	if !drawn || !game.validate_deck_state(deck) || drawn_card.id != event.card_id ||
	   drawn_card.definition_id != event.card_definition {
		deck^ = before
		return false
	}
	return true
}

sync_presentation_statuses_from_final :: proc(timeline: ^Presentation_Timeline) -> bool {
	if timeline == nil || !timeline.view.valid || !timeline.final_view.valid {
		return false
	}
	timeline.view.player.statuses = timeline.final_view.player.statuses
	for index in 0..<timeline.view.enemy_count {
		actor := &timeline.view.enemies[index]
		if final_actor, found := presentation_actor_in_view(&timeline.final_view, actor.entity); found {
			actor.statuses = final_actor.statuses
		}
	}
	return true
}

disarm_presentation_trap_for_event :: proc(
	timeline: ^Presentation_Timeline,
	event: game.Game_Event,
) -> bool {
	if event.source.kind != .Trap {
		return true
	}
	trap, found := presentation_trap(&timeline.view, event.source.id)
	if !found {
		return false
	}
	trap.armed = false
	return true
}

start_presentation_cue :: proc(timeline: ^Presentation_Timeline, cue: ^Presentation_Cue) {
	assert(timeline != nil && cue != nil && !cue.started)
	cue.started = true
	event := cue.event
	actor, has_actor := presentation_actor(timeline, event.target)

	switch cue.kind {
	case .Move:
		if has_actor {
			actor.position = presentation_position(event.from_position)
		} else {
			timeline.update_failures += 1
		}
	case .Damage:
		if !disarm_presentation_trap_for_event(timeline, event) {
			timeline.update_failures += 1
		}
		if has_actor {
			actor.health = max(i32(0), actor.health-max(i32(0), event.amount))
		} else {
			timeline.update_failures += 1
		}
	case .Damage_Absorbed:
		if !disarm_presentation_trap_for_event(timeline, event) {
			timeline.update_failures += 1
		}
		if has_actor {
			if index, found := game.status_index(&actor.statuses, .Shield); found {
				actor.statuses.items[index].potency =
					max(i32(0), actor.statuses.items[index].potency-max(i32(0), event.amount))
			}
		} else {
			timeline.update_failures += 1
		}
	case .Heal:
		if has_actor {
			actor.health = min(actor.max_health, actor.health+max(i32(0), event.amount))
		} else {
			timeline.update_failures += 1
		}
	case .Status_Applied:
		if !has_actor || !apply_presentation_status(
			&actor.statuses,
			event.status,
			event.amount,
			event.duration,
		) {
			timeline.update_failures += 1
		}
	case .Status_Removed, .Status_Expired:
		if !has_actor || !remove_presentation_status(&actor.statuses, event.status) {
			timeline.update_failures += 1
		}
	case .Defeat:
		if has_actor {
			actor.health = 0
			actor.opacity = 1
		} else {
			timeline.update_failures += 1
		}
	case .Loot_Dropped:
		if !show_dropped_presentation_loot(&timeline.view, event) {
			timeline.update_failures += 1
		}
	case .Loot:
		hide_collected_presentation_loot(&timeline.view, event)
	case .Gold_Gained:
		timeline.view.gold += event.amount
	case .Card_Played:
		if !apply_presentation_card_played(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Card_Drawn:
		if !apply_presentation_card_drawn(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Pulse_Advanced:
		timeline.view.pulse_count = event.pulse_count
		timeline.view.deck.energy = event.energy
		if event.statuses_advanced && !sync_presentation_statuses_from_final(timeline) {
			timeline.update_failures += 1
		}
	case .Attack_Missed, .Move_Blocked,
	     .Binding_Added, .Binding_Exhausted, .Binding_Expired:
	}
}

update_active_presentation_cue :: proc(timeline: ^Presentation_Timeline, cue: ^Presentation_Cue) {
	assert(timeline != nil && cue != nil && cue.started)
	actor, has_actor := presentation_actor(timeline, cue.event.target)
	if !has_actor {
		return
	}
	progress := presentation_cue_eased_progress(cue)
	switch cue.kind {
	case .Move:
		from := presentation_position(cue.event.from_position)
		to := presentation_position(cue.event.to_position)
		actor.position = {
			x = from.x+(to.x-from.x)*progress,
			y = from.y+(to.y-from.y)*progress,
		}
	case .Defeat:
		actor.opacity = 1-presentation_cue_progress(cue)
	case .Damage, .Damage_Absorbed, .Heal, .Status_Applied, .Status_Removed,
	     .Status_Expired, .Card_Played, .Card_Drawn, .Loot_Dropped, .Loot, .Attack_Missed,
	     .Move_Blocked, .Gold_Gained, .Binding_Added, .Binding_Exhausted,
	     .Binding_Expired, .Pulse_Advanced:
	}
}

finish_presentation_cue :: proc(timeline: ^Presentation_Timeline, cue: ^Presentation_Cue) {
	assert(timeline != nil && cue != nil && cue.started)
	if cue.kind != .Defeat {
		return
	}
	if actor, found := presentation_actor(timeline, cue.event.target); found {
		actor.opacity = 0
		actor.visible = false
		if cue.event.target == game.PLAYER_ENTITY {
			timeline.view.phase = .Defeat
		} else if visible_presentation_enemy_count(&timeline.view) == 0 {
			timeline.view.phase = .Loot
		}
	}
}

pop_presentation_cue :: proc(timeline: ^Presentation_Timeline) {
	assert(event_timeline_is_busy(timeline))
	timeline.cues[timeline.head] = {}
	timeline.head = (timeline.head+1)%MAX_PRESENTATION_CUES
	timeline.count -= 1
	if timeline.count == 0 {
		timeline.head = 0
	}
}

update_event_timeline :: proc(timeline: ^Presentation_Timeline, dt: f32) -> (became_idle: bool) {
	if !event_timeline_is_busy(timeline) || dt <= 0 {
		return false
	}
	was_busy := true
	remaining := dt
	for remaining > 0 && event_timeline_is_busy(timeline) {
		cue := &timeline.cues[timeline.head]
		if !cue.started {
			start_presentation_cue(timeline, cue)
		}
		available := max(f32(0), cue.duration-cue.elapsed)
		step := min(remaining, available)
		cue.elapsed += step
		remaining -= step
		if cue.duration-cue.elapsed <= PRESENTATION_TIME_EPSILON {
			cue.elapsed = cue.duration
		}
		update_active_presentation_cue(timeline, cue)
		if cue.elapsed < cue.duration {
			break
		}
		finish_presentation_cue(timeline, cue)
		pop_presentation_cue(timeline)
	}
	return was_busy && !event_timeline_is_busy(timeline)
}
