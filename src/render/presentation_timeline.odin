package render

import game "../game"
import grid "../grid"
import level "../level"
import view "../view"

MAX_PRESENTATION_CUES :: game.MAX_GAME_EVENTS
MAX_PRESENTATION_LOOT :: game.MAX_ENEMIES_PER_ROOM*2
MAX_PRESENTATION_TRAPS :: game.MAX_TRAPS_PER_ROOM
MAX_PRESENTATION_GRID_OBJECTS :: game.MAX_GRID_OBJECTS_PER_ROOM

// Values above one slow every cue while preserving their relative rhythm.
PRESENTATION_TIME_SCALE           :: f32(1.35)
PRESENTATION_PLAYER_MOVE_DURATION :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_ENEMY_MOVE_DURATION  :: f32(0.32)*PRESENTATION_TIME_SCALE
PRESENTATION_MOVEMENT_STEP_DURATION :: f32(0.12)*PRESENTATION_TIME_SCALE
PRESENTATION_DAMAGE_DURATION      :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_HEAL_DURATION        :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_STATUS_DURATION      :: f32(0.14)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_PLAY_DURATION   :: f32(0.20)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_DRAW_DURATION     :: f32(0.12)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_MOVE_DURATION     :: f32(0.14)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_CREATE_DURATION   :: f32(0.16)*PRESENTATION_TIME_SCALE
PRESENTATION_REFOCUS_DURATION       :: f32(0.18)*PRESENTATION_TIME_SCALE
PRESENTATION_CARD_REFOCUS_DURATION  :: f32(0.14)*PRESENTATION_TIME_SCALE
PRESENTATION_DEFEAT_DURATION      :: f32(0.22)*PRESENTATION_TIME_SCALE
PRESENTATION_LOOT_DURATION        :: f32(0.28)*PRESENTATION_TIME_SCALE
PRESENTATION_NOTICE_DURATION      :: f32(0.12)*PRESENTATION_TIME_SCALE
PRESENTATION_PULSE_DURATION       :: f32(0.06)*PRESENTATION_TIME_SCALE
PRESENTATION_MAX_SEQUENCE_DURATION :: f32(12.0)
PRESENTATION_TIME_EPSILON         :: f32(0.00001)

Presentation_Cue_Kind :: enum {
	Move,
	Trap_Triggered,
	Hazard_Triggered,
	Object_Spawned,
	Explosive_Armed,
	Explosion,
	Explosive_Disarmed,
	Room_Hazard_Triggered,
	Damage,
	Damage_Absorbed,
	Heal,
	Status_Applied,
	Status_Removed,
	Status_Expired,
	Card_Played,
	Card_Drawn,
	Card_Moved,
	Card_Created,
	Refocus,
	Card_Refocused,
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
	Energy_Gained,
	Dice_Rolled,
	Spell_Launched,
	Spell_Impact,
}

Presentation_Actor :: struct {
	entity:     game.Entity_Ref,
	archetype:  game.Enemy_Archetype,
	boss_phase: i32,
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

Presentation_Grid_Object :: struct {
	entity:     game.Entity_Ref,
	kind:       game.Grid_Object_Kind,
	position:   view.Vec2,
	health:     i32,
	max_health: i32,
	opacity:    f32,
	visible:    bool,
	detonation_pulse: u64,
}

Room_Presentation :: struct {
	phase:       game.Room_Phase,
	encounter_kind: game.Encounter_Kind,
	modifier: game.Room_Modifier,
	family: level.Room_Family,
	relics: game.Relic_State,
	player:      Presentation_Actor,
	deck:        game.Deck_State,
	enemies:     [game.MAX_ENEMIES_PER_ROOM]Presentation_Actor,
	enemy_count: int,
	traps:       [MAX_PRESENTATION_TRAPS]game.Trap,
	trap_count:  int,
	objects:      [MAX_PRESENTATION_GRID_OBJECTS]Presentation_Grid_Object,
	object_count: int,
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
	result.encounter_kind = room.encounter_kind
	result.modifier = room.modifier
	result.family = room.family
	result.relics = room.player.relics
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
			boss_phase = enemy.boss_phase,
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
	result.object_count = min(len(room.objects), MAX_PRESENTATION_GRID_OBJECTS)
	result.dropped += max(0, len(room.objects)-result.object_count)
	for index in 0..<result.object_count {
		object := room.objects[index]
		result.objects[index] = {
			entity = game.object_entity(object.id),
			kind = object.kind,
			detonation_pulse = object.detonation_pulse,
			position = presentation_position(object.position),
			health = object.health,
			max_health = object.max_health,
			opacity = 1,
			visible = true,
		}
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

presentation_grid_object_in_view :: proc(
	presentation: ^Room_Presentation,
	entity: game.Entity_Ref,
) -> (^Presentation_Grid_Object, bool) {
	if presentation == nil || !presentation.valid || entity.kind != .Object || entity.id == 0 ||
	   presentation.object_count < 0 || presentation.object_count > len(presentation.objects) {
		return nil, false
	}
	for index in 0..<presentation.object_count {
		if presentation.objects[index].entity == entity {
			return &presentation.objects[index], true
		}
	}
	return nil, false
}

presentation_grid_object :: proc(
	timeline: ^Presentation_Timeline,
	entity: game.Entity_Ref,
) -> (^Presentation_Grid_Object, bool) {
	if timeline == nil {
		return nil, false
	}
	return presentation_grid_object_in_view(&timeline.view, entity)
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
	case .Movement_Step, .Moved:
		return .Move
	case .Move_Blocked:
		return .Move_Blocked
	case .Attack_Missed:
		return .Attack_Missed
	case .Trap_Triggered:
		return .Trap_Triggered
	case .Hazard_Triggered:
		return .Hazard_Triggered
	case .Object_Spawned:
		return .Object_Spawned
	case .Explosive_Armed:
		return .Explosive_Armed
	case .Explosion:
		return .Explosion
	case .Explosive_Disarmed:
		return .Explosive_Disarmed
	case .Room_Hazard_Triggered:
		return .Room_Hazard_Triggered
	case .Gold_Gained:
		return .Gold_Gained
	case .Energy_Gained:
		return .Energy_Gained
	case .Dice_Rolled:
		return .Dice_Rolled
	case .Spell_Launched:
		return .Spell_Launched
	case .Spell_Impact:
		return .Spell_Impact
	case .Loot_Dropped:
		return .Loot_Dropped
	case .Loot_Collected:
		return .Loot
	case .Card_Played:
		return .Card_Played
	case .Card_Drawn:
		return .Card_Drawn
	case .Card_Moved:
		return .Card_Moved
	case .Card_Created:
		return .Card_Created
	case .Hand_Refocused:
		return .Refocus
	case .Card_Refocused:
		return .Card_Refocused
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
	case .Dice_Rolled:
		return DICE_CUE_DURATION
	case .Spell_Launched:
		return 0.28 if event.card_definition == .Firebomb else 0.12
	case .Spell_Impact:
		return 0.28 if event.card_definition == .Firebomb else 0.16
	case .Move:
		if event.kind == .Movement_Step {
			return PRESENTATION_MOVEMENT_STEP_DURATION
		}
		if event.target.kind == .Enemy || event.target.kind == .Object {
			return PRESENTATION_ENEMY_MOVE_DURATION
		}
		return PRESENTATION_PLAYER_MOVE_DURATION
	case .Damage:
		return PRESENTATION_DAMAGE_DURATION
	case .Explosion, .Room_Hazard_Triggered:
		return f32(0.32)*PRESENTATION_TIME_SCALE
	case .Heal:
		return PRESENTATION_HEAL_DURATION
	case .Status_Applied, .Status_Removed, .Status_Expired, .Damage_Absorbed,
	     .Binding_Added, .Binding_Exhausted, .Binding_Expired:
		return PRESENTATION_STATUS_DURATION
	case .Card_Played:
		return PRESENTATION_CARD_PLAY_DURATION
	case .Card_Drawn:
		return PRESENTATION_CARD_DRAW_DURATION
	case .Card_Moved:
		return PRESENTATION_CARD_MOVE_DURATION
	case .Card_Created:
		return PRESENTATION_CARD_CREATE_DURATION
	case .Refocus:
		return PRESENTATION_REFOCUS_DURATION
	case .Card_Refocused:
		return PRESENTATION_CARD_REFOCUS_DURATION
	case .Defeat:
		return PRESENTATION_DEFEAT_DURATION
	case .Loot:
		return PRESENTATION_LOOT_DURATION
	case .Attack_Missed, .Move_Blocked, .Trap_Triggered, .Hazard_Triggered, .Gold_Gained, .Energy_Gained,
	     .Loot_Dropped, .Object_Spawned, .Explosive_Armed, .Explosive_Disarmed:
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
	total_duration: f32
	for offset := 0; offset < timeline.count; {
		span := presentation_group_size(timeline, offset)
		duration: f32
		for index in offset..<offset+span { duration = max(duration, timeline.cues[index].duration) }
		for index in offset..<offset+span { timeline.cues[index].duration = duration }
		total_duration += duration
		offset += span
	}
	if total_duration > PRESENTATION_MAX_SEQUENCE_DURATION {
		duration_scale := PRESENTATION_MAX_SEQUENCE_DURATION/total_duration
		for index in 0..<timeline.count {
			timeline.cues[index].duration *= duration_scale
		}
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

// Explicit groups combine direct impacts only; movement, reactions and pulse
// boundaries retain FIFO timing. Mutations within a group retain log order.
presentation_cue_can_group :: proc(kind: Presentation_Cue_Kind) -> bool {
	return kind == .Damage || kind == .Damage_Absorbed || kind == .Status_Removed ||
	       kind == .Defeat || kind == .Loot_Dropped || kind == .Explosive_Armed
}

presentation_group_size :: proc(timeline: ^Presentation_Timeline, offset: int = 0) -> int {
	first, found := presentation_cue_at(timeline, offset)
	if !found { return 0 }
	if first.event.visual_group == 0 || !presentation_cue_can_group(first.kind) { return 1 }
	span := 1
	for index in offset+1..<timeline.count {
		cue, _ := presentation_cue_at(timeline, index)
		if cue.event.visual_group != first.event.visual_group || !presentation_cue_can_group(cue.kind) { break }
		span += 1
	}
	return span
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
	if deck == nil || !game.validate_deck_state(deck) || event.amount < 0 ||
	   event.amount > deck.energy || event.from_card_zone != .Hand ||
	   event.to_card_zone != .Resolving || event.source != game.PLAYER_ENTITY ||
	   event.target != game.PLAYER_ENTITY {
		return false
	}
	hand_index, found := game.hand_card_index_by_id(deck, event.card_id)
	if !found {
		return false
	}
	card := deck.hand[hand_index]
	definition, definition_found := game.card_definition_by_id(card.definition_id)
	if !game.validate_card_instance(card) || card.definition_id != event.card_definition ||
	   card.upgrade_level != event.card_upgrade_level || card.lifetime != event.card_lifetime ||
	   !definition_found || definition.cost != event.amount {
		return false
	}

	before := deck^
	deck.energy -= event.amount
	resolving_card, resolving := game.begin_resolving_hand_card(deck, hand_index)
	if !resolving || resolving_card != card || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}

apply_presentation_card_moved :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   (event.from_card_zone != .Hand && event.from_card_zone != .Resolving) ||
	   (event.to_card_zone != .Discard && event.to_card_zone != .Exhaust) {
		return false
	}
	card: game.Card_Instance
	hand_index := 0
	if event.from_card_zone == .Hand {
		found: bool
		hand_index, found = game.hand_card_index_by_id(deck, event.card_id)
		if !found {
			return false
		}
		card = deck.hand[hand_index]
	} else {
		if !deck.has_resolving_card {
			return false
		}
		card = deck.resolving_card
		expected_destination, valid_destination := game.card_destination_after_play(card)
		if !valid_destination || event.to_card_zone != expected_destination {
			return false
		}
	}
	if !game.validate_card_instance(card) || card.definition_id != event.card_definition ||
	   card.id != event.card_id || card.upgrade_level != event.card_upgrade_level ||
	   card.lifetime != event.card_lifetime {
		return false
	}

	before := deck^
	moved_card: game.Card_Instance
	moved := false
	if event.from_card_zone == .Hand {
		moved_card, moved = game.move_hand_card_to_zone(deck, hand_index, event.to_card_zone)
	} else {
		moved_card, moved = game.finish_resolving_card(deck, event.to_card_zone)
	}
	if !moved || !game.validate_card_instance(moved_card) || moved_card.id != event.card_id ||
	   moved_card.definition_id != event.card_definition ||
	   moved_card.upgrade_level != event.card_upgrade_level ||
	   moved_card.lifetime != event.card_lifetime ||
	   (event.from_card_zone == .Hand && moved_card != card) || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}

apply_presentation_card_drawn :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   event.from_card_zone != .Draw || event.to_card_zone != .Hand {
		return false
	}
	before := deck^
	drawn_card, drawn := game.draw_card(deck)
	if !drawn || !game.validate_deck_state(deck) || drawn_card.id != event.card_id ||
	   drawn_card.definition_id != event.card_definition ||
	   drawn_card.upgrade_level != event.card_upgrade_level ||
	   drawn_card.lifetime != event.card_lifetime {
		deck^ = before
		return false
	}
	return true
}

apply_presentation_card_created :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   event.from_card_zone != .Count || event.to_card_zone != .Hand ||
	   event.card_lifetime != .Combat {
		return false
	}

	before := deck^
	created_card, created := game.create_temporary_card(
		deck,
		event.card_definition,
		event.card_upgrade_level,
	)
	if !created || !game.validate_deck_state(deck) || created_card.id != event.card_id ||
	   created_card.definition_id != event.card_definition ||
	   created_card.upgrade_level != event.card_upgrade_level ||
	   created_card.lifetime != event.card_lifetime {
		deck^ = before
		return false
	}
	return true
}

apply_presentation_hand_refocused :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	return deck != nil && game.validate_deck_state(deck) && event.source == game.PLAYER_ENTITY &&
	       event.target == game.PLAYER_ENTITY && event.amount == i32(deck.hand_count)
}

apply_presentation_card_refocused :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.source != game.PLAYER_ENTITY ||
	   event.target != game.PLAYER_ENTITY || event.from_card_zone != .Hand {
		return false
	}
	hand_index, found := game.hand_card_index_by_id(deck, event.card_id)
	if !found {
		return false
	}
	card := deck.hand[hand_index]
	if !game.validate_card_instance(card) || card.id != event.card_id ||
	   card.definition_id != event.card_definition ||
	   card.upgrade_level != event.card_upgrade_level || card.lifetime != event.card_lifetime {
		return false
	}
	expected_destination, valid_destination := game.card_destination_after_refocus(card)
	if !valid_destination || event.to_card_zone != expected_destination {
		return false
	}
	if expected_destination == .Hand {
		return true
	}
	if expected_destination != .Discard && expected_destination != .Exhaust {
		return false
	}

	before := deck^
	moved_card, moved := game.move_hand_card_to_zone(deck, hand_index, expected_destination)
	if !moved || moved_card != card || !game.validate_deck_state(deck) {
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

apply_presentation_trap_triggered :: proc(
	timeline: ^Presentation_Timeline,
	event: game.Game_Event,
) -> bool {
	if timeline == nil || event.kind != .Trap_Triggered || event.source.kind != .Trap ||
	   (event.target.kind != .Player && event.target.kind != .Enemy) ||
	   event.from_position != event.to_position {
		return false
	}
	trap, found := presentation_trap(&timeline.view, event.source.id)
	if !found || !trap.armed || trap.position != event.to_position {
		return false
	}
	trap.armed = false
	return true
}

presentation_hazard_trigger_is_valid :: proc(
	timeline: ^Presentation_Timeline,
	event: game.Game_Event,
) -> bool {
	if timeline == nil || event.kind != .Hazard_Triggered || event.source.kind != .Object ||
	   (event.target.kind != .Player && event.target.kind != .Enemy) || event.amount <= 0 ||
	   event.from_position != event.to_position {
		return false
	}
	object, object_found := presentation_grid_object(timeline, event.source)
	actor, actor_found := presentation_actor(timeline, event.target)
	if !object_found || !actor_found || !object.visible ||
	   object.position != presentation_position(event.from_position) ||
	   actor.position != presentation_position(event.to_position) {
		return false
	}
	definition, definition_found := game.grid_object_definition(object.kind)
	return definition_found && definition.hazardous &&
	       definition.hazard_damage == event.amount
}

start_presentation_cue :: proc(timeline: ^Presentation_Timeline, cue: ^Presentation_Cue) {
	assert(timeline != nil && cue != nil && !cue.started)
	cue.started = true
	event := cue.event
	actor, has_actor := presentation_actor(timeline, event.target)
	object, has_object := presentation_grid_object(timeline, event.target)

	switch cue.kind {
	case .Dice_Rolled:
		expected_dice := game.card_dice_count(event.card_definition)
		if !game.validate_dice_roll(&event.dice_roll) || event.amount != event.dice_roll.total ||
		   event.dice_roll.count != expected_dice ||
		   expected_dice == 0 ||
		   event.source != game.PLAYER_ENTITY {
			timeline.update_failures += 1
		}
	case .Spell_Launched, .Spell_Impact:
		if event.card_definition != .Firebomb && event.card_definition != .Chain_Lightning &&
		   game.card_dice_count(event.card_definition) == 0 {
			timeline.update_failures += 1
		}
	case .Room_Hazard_Triggered:
		timeline.view.modifier.activation_pulse = event.pulse_count
	case .Object_Spawned:
		if !show_spawned_presentation_object(&timeline.view, event) {
			timeline.update_failures += 1
		}
	case .Explosive_Armed, .Explosive_Disarmed, .Explosion:
		if !has_object {
			timeline.update_failures += 1
		} else if cue.kind == .Explosive_Armed {
			object.detonation_pulse = event.pulse_count
		} else {
			object.detonation_pulse = 0
			if cue.kind == .Explosion {
				object.visible = false
				object.opacity = 0
			}
		}
	case .Move:
		if has_actor {
			actor.position = presentation_position(event.from_position)
		} else if has_object {
			object.position = presentation_position(event.from_position)
		} else {
			timeline.update_failures += 1
		}
	case .Trap_Triggered:
		if !apply_presentation_trap_triggered(timeline, event) {
			timeline.update_failures += 1
		}
	case .Hazard_Triggered:
		if !presentation_hazard_trigger_is_valid(timeline, event) {
			timeline.update_failures += 1
		}
	case .Damage:
		if has_actor {
			actor.health = max(i32(0), actor.health-max(i32(0), event.amount))
		} else if has_object {
			object.health = max(i32(0), object.health-max(i32(0), event.amount))
		} else {
			timeline.update_failures += 1
		}
	case .Damage_Absorbed:
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
		} else if has_object {
			object.health = 0
			object.opacity = 1
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
	case .Energy_Gained:
		if event.target != game.PLAYER_ENTITY || event.amount <= 0 ||
		   event.energy < 0 || event.energy > timeline.view.deck.rules.max_energy ||
		   timeline.view.deck.energy+event.amount != event.energy {
			timeline.update_failures += 1
		} else {
			timeline.view.deck.energy = event.energy
		}
	case .Card_Played:
		if !apply_presentation_card_played(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Card_Drawn:
		if !apply_presentation_card_drawn(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Card_Moved:
		if !apply_presentation_card_moved(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Card_Created:
		if !apply_presentation_card_created(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Refocus:
		if !apply_presentation_hand_refocused(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Card_Refocused:
		if !apply_presentation_card_refocused(&timeline.view.deck, event) {
			timeline.update_failures += 1
		}
	case .Pulse_Advanced:
		timeline.view.pulse_count = event.pulse_count
		timeline.view.deck.energy = event.energy
		if timeline.final_view.valid {
			timeline.view.modifier = timeline.final_view.modifier
			timeline.view.relics = timeline.final_view.relics
			for &enemy in timeline.view.enemies[:timeline.view.enemy_count] {
				if final_enemy, found := presentation_actor_in_view(&timeline.final_view, enemy.entity); found {
					enemy.boss_phase = final_enemy.boss_phase
				}
			}
		}
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
	object, has_object := presentation_grid_object(timeline, cue.event.target)
	if !has_actor && !has_object {
		return
	}
	progress := presentation_cue_eased_progress(cue)
	switch cue.kind {
	case .Move:
		from := presentation_position(cue.event.from_position)
		to := presentation_position(cue.event.to_position)
		position := view.Vec2{
			x = from.x+(to.x-from.x)*progress,
			y = from.y+(to.y-from.y)*progress,
		}
		if has_actor {
			actor.position = position
		} else {
			object.position = position
		}
	case .Defeat:
		opacity := 1-presentation_cue_progress(cue)
		if has_actor {
			actor.opacity = opacity
		} else {
			object.opacity = opacity
		}
	case .Trap_Triggered, .Hazard_Triggered, .Damage, .Damage_Absorbed, .Heal, .Status_Applied,
	     .Status_Removed, .Status_Expired, .Card_Played, .Card_Drawn, .Card_Moved, .Card_Created,
	     .Refocus, .Card_Refocused,
	     .Loot_Dropped, .Loot, .Attack_Missed,
	     .Move_Blocked, .Gold_Gained, .Energy_Gained, .Binding_Added, .Binding_Exhausted,
	     .Binding_Expired, .Pulse_Advanced, .Object_Spawned, .Explosive_Armed,
	     .Explosive_Disarmed, .Explosion, .Room_Hazard_Triggered, .Dice_Rolled, .Spell_Launched, .Spell_Impact:
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
			timeline.view.modifier.activation_pulse = 0
		} else if visible_presentation_enemy_count(&timeline.view) == 0 && timeline.view.phase != .Defeat {
			timeline.view.phase = .Loot
			timeline.view.modifier.activation_pulse = 0
		}
	} else if object, object_found := presentation_grid_object(
		timeline,
		cue.event.target,
	); object_found {
		object.opacity = 0
		object.visible = false
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
		span := presentation_group_size(timeline)
		for offset in 0..<span {
			member, _ := presentation_cue_at(timeline, offset)
			if !member.started { start_presentation_cue(timeline, member) }
		}
		available := max(f32(0), cue.duration-cue.elapsed)
		step := min(remaining, available)
		remaining -= step
		for offset in 0..<span {
			member, _ := presentation_cue_at(timeline, offset)
			member.elapsed += step
			if member.duration-member.elapsed <= PRESENTATION_TIME_EPSILON { member.elapsed = member.duration }
			update_active_presentation_cue(timeline, member)
		}
		if cue.elapsed < cue.duration {
			break
		}
		for _ in 0..<span {
			finish_presentation_cue(timeline, &timeline.cues[timeline.head])
			pop_presentation_cue(timeline)
		}
	}
	return was_busy && !event_timeline_is_busy(timeline)
}
