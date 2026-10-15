package render

import game "../game"
import grid "../grid"
import level "../level"
import view "../view"
import tween "../engine/tween"

MAX_PRESENTATION_CUES :: game.MAX_GAME_EVENTS
// A defeated elite can drop gold, healing and a weapon together.
MAX_PRESENTATION_LOOT :: game.MAX_ENEMIES_PER_ROOM*3
MAX_PRESENTATION_TRAPS :: game.MAX_TRAPS_PER_ROOM
MAX_PRESENTATION_GRID_OBJECTS :: game.MAX_GRID_OBJECTS_PER_ROOM
// One bit a cell of the largest level: the pools on its floor.
MAX_PRESENTATION_GROUND_CELLS :: level.MAX_GENERATED_ROOM_DIMENSION*level.MAX_GENERATED_ROOM_DIMENSION

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
// Movimento Ombra: the player sinking into his shadow, and rising from it.
PRESENTATION_SHADOW_SINK_DURATION :: f32(0.2)*PRESENTATION_TIME_SCALE
PRESENTATION_SHADOW_RISE_DURATION :: f32(0.25)*PRESENTATION_TIME_SCALE
// DADO DEL DESTINO: its die at the struck foe, as the blow lands (its paper
// token stays a while longer: player_charges.odin).
PRESENTATION_FATE_DURATION :: f32(0.24)*PRESENTATION_TIME_SCALE
// LAZZO: the throw (the rope flies, wraps the foe, lifts it and pulls it onto
// its ring), stretched with the card's other cues over the cast (lasso.odin).
PRESENTATION_LASSO_THROW_DURATION :: f32(1.1)*PRESENTATION_TIME_SCALE
// CANNA DA PESCA, about three seconds in all (fishing.odin): the rod swings
// and its line flies to the cell; the bobber floats on the new water until a
// fish bites; the catch is reeled out and flies to the player (a caught card
// then hangs over him a moment, its name shown).
PRESENTATION_FISH_CAST_DURATION :: f32(0.62)
PRESENTATION_FISH_BITE_DURATION :: f32(1.15)
PRESENTATION_FISH_CATCH_DURATION :: f32(0.95)
PRESENTATION_FISH_CARD_DURATION :: f32(1.7)
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
	Shadow_Entered,
	Shadow_Emerged,
	// RIFLESSO and the Dado del Destino's die (game.Game_Event_Kind).
	Attack_Deflected,
	Fate_Rolled,
	// LAZZO: the throw, a hit or a smash, the rope let go (game/lasso.odin).
	Lasso_Caught,
	Lasso_Struck,
	Lasso_Released,
	// CANNA DA PESCA: the cast, the bite, the catch (game/fishing.odin).
	Fish_Cast,
	Fish_Bite,
	Fish_Caught,
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
	fuse_pulses: int,
	device_armed: bool,
}

// The pools and fires on the floor as the board shows them (game/ground.odin):
// a bit a pool's cell, row-major, `width` cells a row; the fires as they stand;
// the Canna da Pesca's water (game/fishing.odin).
Presentation_Ground :: struct {
	width: int,
	pool: [MAX_PRESENTATION_GROUND_CELLS/64]u64,
	fires: [game.MAX_GROUND_FIRES]game.Ground_Fire,
	fire_count: int,
	water: [game.MAX_FISHING_WATERS]grid.Position,
	water_count: int,
}

Room_Presentation :: struct {
	tactical: bool,
	phase:       game.Room_Phase,
	encounter_kind: game.Encounter_Kind,
	modifier: game.Room_Modifier,
	family: level.Room_Family,
	relics: game.Relic_State,
	// The M8 weapon in the player's hand as the board shows him (the look of
	// his blows, attack_fx.odin): a blow's last use is still in it while it plays.
	weapon: game.Weapon_Id,
	// DADO DEL DESTINO: the die the player's loaded bumps roll
	// (game.player_fate_sides), shown from the cue that loads them.
	fate_sides: i32,
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
	// Shown from a pool's or a fire's landing (start_presentation_cue).
	ground:      Presentation_Ground,
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
	// The command whose events these are (Renderer.cue_batches): the cues of
	// one blow share it, and no later blow ever does.
	batch:    u32,
}

Presentation_Timeline :: struct {
	card_cast: bool,
	cues:           [MAX_PRESENTATION_CUES]Presentation_Cue,
	head:           int,
	count:          int,
	dropped_count:  int,
	update_failures: int,
	view:           Room_Presentation,
	final_view:     Room_Presentation,
	// The stacks of the player's charges his blow spent, as it found them
	// (sync_presentation_player_charges_from_final; 0: none spent): the board
	// keeps them on show until the blow lands (hold_unlanded_blows).
	charges_before: [game.Status_Kind]i32,
}

presentation_position :: proc(position: grid.Position) -> view.Vec2 {
	return {x = f32(position.x), y = f32(position.y)}
}

capture_room_presentation :: proc(room: ^game.Room) -> (result: Room_Presentation) {
	if room == nil || room.player == nil {
		return
	}
	result.valid = true
	result.tactical = game.tactical_enabled(room)
	result.phase = room.phase
	result.encounter_kind = room.encounter_kind
	result.modifier = room.modifier
	result.family = room.family
	result.relics = room.player.relics
	result.weapon = room.player.equipment.weapon.id
	result.fate_sides = game.player_fate_sides(room)
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
			fuse_pulses = object.fuse_pulses,
			device_armed = object.device_armed,
			position = presentation_position(object.position),
			health = object.health,
			max_health = object.max_health,
			opacity = 1,
			visible = true,
		}
	}

	result.dropped += capture_presentation_ground(room, &result.ground)
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

// The room's ground into `ground`; the pool cells it had no bit for.
capture_presentation_ground :: proc(room: ^game.Room, ground: ^Presentation_Ground) -> (dropped: int) {
	ground^ = {}
	if room == nil || room.level_data == nil { return }
	ground.width = room.level_data.tiles.width
	for value, index in room.ground.pool {
		if value <= 0 { continue }
		if index >= MAX_PRESENTATION_GROUND_CELLS { dropped += 1; continue }
		ground.pool[index/64] |= u64(1)<<u64(index%64)
	}
	ground.fire_count = min(room.ground.fire_count, len(ground.fires))
	copy(ground.fires[:], room.ground.fires[:ground.fire_count])
	ground.water_count = clamp(room.fishing.water_count, 0, len(ground.water))
	copy(ground.water[:], room.fishing.water[:ground.water_count])
	return
}

// Whether `cell` is the Canna da Pesca's water in the shown ground.
presentation_ground_water :: proc(ground: ^Presentation_Ground, cell: grid.Position) -> bool {
	if ground == nil { return false }
	for water in ground.water[:clamp(ground.water_count, 0, len(ground.water))] {
		if water == cell { return true }
	}
	return false
}

// Whether `cell` is a pool's in the shown ground.
presentation_ground_pool :: proc(ground: ^Presentation_Ground, cell: grid.Position) -> bool {
	if ground == nil || cell.x < 0 || cell.y < 0 || cell.x >= ground.width || ground.width <= 0 { return false }
	index := cell.y*ground.width+cell.x
	return index < MAX_PRESENTATION_GROUND_CELLS && ground.pool[index/64]&(u64(1)<<u64(index%64)) != 0
}

// The strongest shown fire on `cell` (0: none), and whether it is a fire's centre.
presentation_ground_burn :: proc(ground: ^Presentation_Ground, cell: grid.Position) -> (burn: i32, centre: bool, last: bool) {
	if ground == nil { return }
	for fire in ground.fires[:ground.fire_count] {
		if !game.ground_fire_covers(fire, cell) { continue }
		burn = max(burn, fire.burn)
		centre = centre || fire.center == cell
		last = last || fire.stage >= game.GROUND_FIRE_STAGES
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
	case .Shadow_Entered:
		return .Shadow_Entered
	case .Shadow_Emerged:
		return .Shadow_Emerged
	case .Attack_Deflected:
		return .Attack_Deflected
	case .Fate_Rolled:
		return .Fate_Rolled
	case .Lasso_Caught:
		return .Lasso_Caught
	case .Lasso_Struck:
		return .Lasso_Struck
	case .Lasso_Released:
		return .Lasso_Released
	case .Fish_Cast:
		return .Fish_Cast
	case .Fish_Bite:
		return .Fish_Bite
	case .Fish_Caught:
		return .Fish_Caught
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
		// A teleport has no road to walk: it only marks the landing.
		if game.event_is_teleport(event) {
			return PRESENTATION_NOTICE_DURATION
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
	case .Shadow_Entered:
		return PRESENTATION_SHADOW_SINK_DURATION
	case .Shadow_Emerged:
		return PRESENTATION_SHADOW_RISE_DURATION
	// The blow RIFLESSO turns back is still a blow.
	case .Attack_Deflected:
		return PRESENTATION_DAMAGE_DURATION
	case .Fate_Rolled:
		return PRESENTATION_FATE_DURATION
	case .Lasso_Caught:
		return PRESENTATION_LASSO_THROW_DURATION
	// A hit is a blow; letting go only marks the fall.
	case .Lasso_Struck:
		return PRESENTATION_DAMAGE_DURATION
	case .Lasso_Released:
		return PRESENTATION_NOTICE_DURATION
	case .Fish_Cast:
		return PRESENTATION_FISH_CAST_DURATION
	case .Fish_Bite:
		return PRESENTATION_FISH_BITE_DURATION
	// A caught card hangs over the player a while, its name shown.
	case .Fish_Caught:
		return PRESENTATION_FISH_CATCH_DURATION if event.card_definition == .Fishing_Rod else PRESENTATION_FISH_CARD_DURATION
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
	if first.kind == .Damage_Absorbed && game.event_is_attack(first.event) { return presentation_blow_span(timeline, offset) }
	if first.event.visual_group == 0 || !presentation_cue_can_group(first.kind) { return 1 }
	span := 1
	for index in offset+1..<timeline.count {
		cue, _ := presentation_cue_at(timeline, index)
		if cue.event.visual_group != first.event.visual_group || !presentation_cue_can_group(cue.kind) { break }
		span += 1
	}
	return span
}

// A blow met by a guard (game.mark_attack_events) is one blow, as the world
// shows it: its guard, the Shield it breaks and the wound that gets through
// start together.
presentation_blow_span :: proc(timeline: ^Presentation_Timeline, offset: int) -> int {
	first, _ := presentation_cue_at(timeline, offset)
	span := 1
	for index in offset+1..<timeline.count {
		cue, _ := presentation_cue_at(timeline, index)
		event := cue.event
		if event.source != first.event.source || event.target != first.event.target { break }
		if cue.kind == .Status_Removed && event.status == .Shield { span += 1; continue }
		if cue.kind == .Damage && game.event_is_attack(event) && event.to_position == first.event.to_position { span += 1 }
		break
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
	return tween.smoothstep(linear)
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
	if statuses == nil || !game.status_kind_is_valid(kind) || potency <= 0 ||
	   (duration <= 0 && !game.status_kind_stacks(kind)) ||
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

apply_presentation_card_played :: proc(deck: ^game.Deck_State, event: game.Game_Event, tactical: bool = false) -> bool {
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
	definition, definition_found := game.card_definition_by_id(card.definition_id, tactical)
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
	timeline.view.fate_sides = timeline.final_view.fate_sides
	for index in 0..<timeline.view.enemy_count {
		actor := &timeline.view.enemies[index]
		if final_actor, found := presentation_actor_in_view(&timeline.final_view, actor.entity); found {
			actor.statuses = final_actor.statuses
		}
	}
	return true
}

// A poison bite wears a stack without an event of its own: at the bite, the
// bitten actor's poison takes the final view's stacks. A bite that ends it
// leaves it for its Status_Expired to remove. (A command bites each actor at
// most once: the player's own action, each enemy's in its pulse.)
sync_presentation_poison_from_final :: proc(timeline: ^Presentation_Timeline, actor: ^Presentation_Actor) {
	if timeline == nil || actor == nil || !timeline.final_view.valid { return }
	index, poisoned := game.status_index(&actor.statuses, .Poison)
	if !poisoned { return }
	final_actor, found := presentation_actor_in_view(&timeline.final_view, actor.entity)
	if !found { return }
	if final_index, kept := game.status_index(&final_actor.statuses, .Poison); kept {
		actor.statuses.items[index].potency = final_actor.statuses.items[final_index].potency
	}
}

// The player's charges his own blow spends (a bump's Lama and Destino, an
// arrow) wear without an event of their own: at the blow, they take the final
// view's stacks, and what they were is kept in charges_before. A last one spent
// is left for its Status_Expired to remove.
sync_presentation_player_charges_from_final :: proc(timeline: ^Presentation_Timeline) {
	if timeline == nil || !timeline.final_view.valid { return }
	shown, final := &timeline.view.player.statuses, &timeline.final_view.player.statuses
	for kind in game.Status_Kind {
		if !game.status_kind_is_player_charge(kind) { continue }
		index, carried := game.status_index(shown, kind)
		if !carried { continue }
		final_index, kept := game.status_index(final, kind)
		if !kept { continue }
		if shown.items[index].potency != final.items[final_index].potency { timeline.charges_before[kind] = shown.items[index].potency }
		shown.items[index].potency = final.items[final_index].potency
	}
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
	if timeline != nil && event.kind == .Hazard_Triggered && event.object_kind == .Shock_Floor &&
	   event.source.kind == .Enemy && event.target.kind == .Object && event.amount == 0 &&
	   event.from_position == event.to_position {
		object, object_found := presentation_grid_object(timeline,event.target)
		actor, actor_found := presentation_actor(timeline,event.source)
		return object_found && actor_found && object.visible && actor.visible &&
		       object.kind == .Shock_Floor && object.position == presentation_position(event.to_position)
	}
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
		// The Canna da Pesca's food: one d4 of life, at every level of the rod
		// (it is no dice card: game/fishing.odin).
		if event.card_definition == .Fishing_Rod {
			if !game.validate_dice_roll(&event.dice_roll) || event.amount != event.dice_roll.total || event.dice_roll.count != 1 ||
			   event.dice_roll.sides != game.FISHING_HEAL_SIDES || event.source != game.PLAYER_ENTITY {
				timeline.update_failures += 1
			}
			break
		}
		expected_dice := game.card_dice_count(event.card_definition)
		// The die must be the one of the card's logged level.
		if !game.validate_dice_roll(&event.dice_roll) || event.amount != event.dice_roll.total ||
		   int(event.dice_roll.count) != expected_dice ||
		   event.dice_roll.sides != game.card_die_sides(event.card_definition, event.card_upgrade_level) ||
		   expected_dice == 0 ||
		   event.source != game.PLAYER_ENTITY {
			timeline.update_failures += 1
		}
	case .Spell_Launched, .Spell_Impact:
		if event.card_definition != .Firebomb && event.card_definition != .Chain_Lightning &&
		   game.card_dice_count(event.card_definition) == 0 && !game.card_is_board_device(event.card_definition) &&
		   !game.card_places_ground(event.card_definition) {
			timeline.update_failures += 1
		}
		// A pool or a fire is on the floor from its landing on.
		if cue.kind == .Spell_Impact && game.card_places_ground(event.card_definition) && timeline.final_view.valid {
			timeline.view.ground = timeline.final_view.ground
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
			object.fuse_pulses = int(event.duration)
		} else {
			object.detonation_pulse = 0
			if cue.kind == .Explosion {
				object.visible = false
				object.opacity = 0
			}
		}
	case .Move:
		// A teleport shows the body on its landing at once, never on the line
		// between.
		start := event.to_position if game.event_is_teleport(event) else event.from_position
		if has_actor {
			actor.position = presentation_position(start)
		} else if has_object {
			object.position = presentation_position(start)
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
		} else if has_object && object.kind == .Shock_Floor {
			object.device_armed = true
		}
	case .Damage:
		if event.source == game.PLAYER_ENTITY && game.event_is_attack(event) { sync_presentation_player_charges_from_final(timeline) }
		if has_actor {
			actor.health = max(i32(0), actor.health-max(i32(0), event.amount))
			if event.has_status_cause && event.status_cause == .Poison { sync_presentation_poison_from_final(timeline, actor) }
		} else if has_object {
			object.health = max(i32(0), object.health-max(i32(0), event.amount))
		} else {
			timeline.update_failures += 1
		}
	case .Damage_Absorbed:
		if event.source == game.PLAYER_ENTITY && game.event_is_attack(event) { sync_presentation_player_charges_from_final(timeline) }
		if has_actor {
			if index, found := game.status_index(&actor.statuses, .Shield); found {
				actor.statuses.items[index].potency =
					max(i32(0), actor.statuses.items[index].potency-max(i32(0), event.amount))
			}
			if event.has_status_cause && event.status_cause == .Poison { sync_presentation_poison_from_final(timeline, actor) }
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
		// DESTINO loaded: its bumps' die shows with it.
		if event.status == .Fate && event.target == game.PLAYER_ENTITY && timeline.final_view.valid {
			timeline.view.fate_sides = timeline.final_view.fate_sides
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
		if !apply_presentation_card_played(&timeline.view.deck, event, timeline.view.tactical) {
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
	case .Fate_Rolled:
		// One die of the ladder, rolled by the player's own bump.
		roll := event.dice_roll
		if !game.validate_dice_roll(&roll) || roll.count != 1 || event.source != game.PLAYER_ENTITY ||
		   event.duration < 0 || event.duration > i32(max(game.Fate_Outcome)) {
			timeline.update_failures += 1
		}
		sync_presentation_player_charges_from_final(timeline)
	case .Lasso_Caught, .Lasso_Released:
		// The player's own rope, on a foe the board shows.
		if event.source != game.PLAYER_ENTITY || event.card_definition != .Lasso || !has_actor {
			timeline.update_failures += 1
		}
	case .Lasso_Struck:
		if event.card_definition != .Lasso || event.source.kind != .Enemy || event.amount <= 0 {
			timeline.update_failures += 1
		}
	// CANNA DA PESCA: the player's own rod; its water shows from the bobber's
	// landing, as the bite's cue starts.
	case .Fish_Cast, .Fish_Bite:
		if event.source != game.PLAYER_ENTITY || event.card_definition != .Fishing_Rod || !has_actor {
			timeline.update_failures += 1
		}
		if cue.kind == .Fish_Bite && timeline.final_view.valid { timeline.view.ground = timeline.final_view.ground }
	case .Fish_Caught:
		if event.source != game.PLAYER_ENTITY || !has_actor || (event.card_definition != .Fishing_Rod &&
		   (game.card_is_room_tool(event.card_definition) || event.card_id == 0)) {
			timeline.update_failures += 1
		}
	case .Attack_Missed, .Move_Blocked, .Attack_Deflected,
	     .Binding_Added, .Binding_Exhausted, .Binding_Expired, .Shadow_Entered, .Shadow_Emerged:
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
		if game.event_is_teleport(cue.event) { from = to }
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
	     .Explosive_Disarmed, .Explosion, .Room_Hazard_Triggered, .Dice_Rolled, .Spell_Launched, .Spell_Impact,
	     .Shadow_Entered, .Shadow_Emerged, .Attack_Deflected, .Fate_Rolled, .Lasso_Caught, .Lasso_Struck, .Lasso_Released,
	     .Fish_Cast, .Fish_Bite, .Fish_Caught:
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
		} else if visible_presentation_enemy_count(&timeline.view) == 0 && timeline.view.phase != .Defeat &&
		          !(timeline.final_view.valid && timeline.final_view.phase == .Combat) {
			// A room that stays in combat (the endless sandbox) is not cleared.
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
