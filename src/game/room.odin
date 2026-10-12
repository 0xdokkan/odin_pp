package game

import grid "../grid"
import level "../level"

MAX_ENEMIES_PER_ROOM :: 32
MAX_TRAPS_PER_ROOM   :: 64
LOOT_MAGNET_RANGE_CELLS :: 3

Room_Phase :: enum {
	Combat,
	Loot,
	Complete,
	Defeat,
}

room_phase_name :: proc(phase: Room_Phase) -> string {
	switch phase {
	case .Combat:
		return "Combat"
	case .Loot:
		return "Loot"
	case .Complete:
		return "Complete"
	case .Defeat:
		return "Defeat"
	}
	return "Unknown"
}

Player_Stats :: struct {
	max_health: i32,
	attack:     i32,
	defense:    i32,
}

Player :: struct {
	position: grid.Position,
	stats:    Player_Stats,
	health:   i32,
	gold:     i32,
	statuses: Status_Set,
	deck:     Deck_State,
	relics:   Relic_State,
	dice:     Dice_State,
	tactical: Tactical_State,
	equipment: Equipment_State,
	m8_profile: M8_Profile,
	// Easter eggs already opened on this floor (tesla_ring.odin).
	floor_secrets: bit_set[Floor_Secret; u8],
}

create_player :: proc(stats: Player_Stats) -> (Player, bool) {
	if stats.max_health <= 0 || stats.attack <= 0 || stats.defense < 0 {
		return {}, false
	}
	result := Player{
		stats = stats,
		health = stats.max_health,
		dice = make_dice_state(DEFAULT_DICE_SEED),
	}
	if !initialize_starter_deck(&result.deck) {
		return {}, false
	}
	return result, true
}

Enemy_Archetype :: enum {
	Chaser,
	Archer,
	Brute,
	Bomber,
	Custodian,
	Demolitionist,
	Count,
}

enemy_archetype_name :: proc(archetype: Enemy_Archetype) -> string {
	switch archetype {
	case .Chaser:
		return "Chaser"
	case .Archer:
		return "Archer"
	case .Brute:
		return "Brute"
	case .Bomber:
		return "Bomber"
	case .Custodian:
		return "Custode"
	case .Demolitionist:
		return "Demolitore"
	case .Count:
	}
	return "Unknown"
}

Enemy :: struct {
	id:            u32,
	archetype:     Enemy_Archetype,
	position:      grid.Position,
	max_health:    i32,
	health:        i32,
	attack:        i32,
	drops_healing: bool,
	statuses:      Status_Set,
	intent:        Enemy_Intent,
	recovery_pulses: i32,
	boss_phase:      i32,
	boss_cycle:      u32,
	boss_approach_pulses: i32,
	aim_ready: bool,
	aim_anchor: grid.Position,
	bomb_ready: bool,
	bomb_anchor: grid.Position,
	// M7 only: seconds until this enemy resolves its committed intent.
	tactical_cooldown: f32,
}

Trap :: struct {
	id:       u32,
	position: grid.Position,
	damage:   i32,
	armed:    bool,
}

Obstacle :: struct {
	position: grid.Position,
}

Loot_Kind :: enum {
	Gold,
	Healing,
	Weapon,
}

Loot :: struct {
	position: grid.Position,
	kind:     Loot_Kind,
	amount:   i32,
	weapon_id: Weapon_Id,
}

Enemy_Spawn :: struct {
	position:      grid.Position,
	health:        i32,
	attack:        i32,
	archetype:     Enemy_Archetype,
	drops_healing: bool,
}

HEALING_DROP_SPAWN_INTERVAL :: 3

// Il drop di cura e una decisione del contenuto dell'encounter, non di
// kill_enemy: i produttori di spawn marcano un nemico ogni
// HEALING_DROP_SPAWN_INTERVAL, cosi un director futuro puo cambiare la regola
// senza toccare la simulazione.
enemy_spawn_drops_healing :: proc(spawn_index: int) -> bool {
	return spawn_index%HEALING_DROP_SPAWN_INTERVAL == HEALING_DROP_SPAWN_INTERVAL-1
}

Trap_Spawn :: struct {
	position: grid.Position,
	damage:   i32,
}

Room_Content :: struct {
	family: level.Room_Family,
	encounter_kind: Encounter_Kind,
	modifier: Room_Modifier,
	enemies:   []Enemy_Spawn,
	traps:     []Trap_Spawn,
	obstacles: []grid.Position,
	objects:   []Grid_Object_Spawn,
}

Room :: struct {
	family: level.Room_Family,
	encounter_kind: Encounter_Kind,
	modifier: Room_Modifier,
	level_data:    ^level.Level,
	player:        ^Player,
	phase:         Room_Phase,
	exit_position: grid.Position,
	enemies:       [dynamic]Enemy,
	traps:         [dynamic]Trap,
	obstacles:     [dynamic]Obstacle,
	objects:       [dynamic]Grid_Object,
	loot:          [dynamic]Loot,
	// Campo delle distanze condiviso; M7 usa costi pesati per i pericoli.
	enemy_path_distances: []int,
	enemy_path_queue:     []grid.Position,
	next_enemy_id:  u32,
	next_trap_id:   u32,
	next_object_id: u32,
	pulse_count:   u64,
	recent_events: Event_Log,
	tactical_pulse: Tactical_Pulse,
	qte: QTE_State,
	reaction_bindings: Reaction_Binding_Set,
	// A ring opened by a square of coils, awaiting the duel's result.
	tesla_ring: Tesla_Ring,
}

Move_Direction :: enum {
	North,
	East,
	South,
	West,
}

Action_Result :: enum {
	None,
	Moved,
	Attacked,
	Blocked,
	Combat_Ended,
	Used_Ability,
	Room_Completed,
	Player_Defeated,
	Invalid_Phase,
}

direction_offset :: proc(direction: Move_Direction) -> grid.Position {
	switch direction {
	case .North:
		return {x = 0, y = -1}
	case .East:
		return {x = 1, y = 0}
	case .South:
		return {x = 0, y = 1}
	case .West:
		return {x = -1, y = 0}
	}
	return {}
}

add_position :: proc(a, b: grid.Position) -> grid.Position {
	return {x = a.x+b.x, y = a.y+b.y}
}

find_exit :: proc(level_data: ^level.Level) -> (position: grid.Position, ok: bool) {
	if level_data == nil {
		return {}, false
	}

	found := false
	for tile, index in level_data.tiles.cells {
		if tile.kind != .Exit {
			continue
		}
		if found {
			return {}, false
		}
		current, valid := grid.position_of(&level_data.tiles, index)
		assert(valid)
		position = current
		found = true
	}
	return position, found
}

base_cell_is_walkable :: proc(room: ^Room, position: grid.Position) -> bool {
	if room == nil || room.level_data == nil {
		return false
	}
	tile, ok := level.tile_at(room.level_data, position)
	return ok && level.is_walkable(tile.kind)
}

obstacle_at :: proc(room: ^Room, position: grid.Position) -> bool {
	if room == nil {
		return false
	}
	for obstacle in room.obstacles {
		if obstacle.position == position {
			return true
		}
	}
	return false
}

object_index_at :: proc(
	room: ^Room,
	position: grid.Position,
	ignored_index: int = -1,
) -> (int, bool) {
	if room == nil {
		return 0, false
	}
	for object, index in room.objects {
		if index != ignored_index && object.position == position {
			return index, true
		}
	}
	return 0, false
}

object_index_by_id :: proc(room: ^Room, id: u32) -> (int, bool) {
	if room == nil || id == 0 {
		return 0, false
	}
	for object, index in room.objects {
		if object.id == id {
			return index, true
		}
	}
	return 0, false
}

grid_object_at :: proc(room: ^Room, position: grid.Position) -> (^Grid_Object, bool) {
	index, found := object_index_at(room, position)
	if !found {
		return nil, false
	}
	return &room.objects[index], true
}

cell_blocks_movement :: proc(room: ^Room, position: grid.Position) -> bool {
	if !base_cell_is_walkable(room, position) || obstacle_at(room, position) {
		return true
	}
	object, found := grid_object_at(room, position)
	if !found {
		return false
	}
	definition, definition_found := grid_object_definition(object.kind)
	return !definition_found || definition.blocks_movement
}

cell_blocks_line_of_sight :: proc(room: ^Room, position: grid.Position) -> bool {
	if !base_cell_is_walkable(room, position) || obstacle_at(room, position) {
		return true
	}
	object, found := grid_object_at(room, position)
	if !found {
		return false
	}
	definition, definition_found := grid_object_definition(object.kind)
	return !definition_found || definition.blocks_line_of_sight
}

remove_grid_object :: proc(room: ^Room, index: int) -> bool {
	if room == nil || index < 0 || index >= len(room.objects) {
		return false
	}
	unordered_remove(&room.objects, index)
	return true
}

trap_index_at :: proc(room: ^Room, position: grid.Position) -> (int, bool) {
	if room == nil {
		return 0, false
	}
	for trap, index in room.traps {
		if trap.position == position {
			return index, true
		}
	}
	return 0, false
}

enemy_index_at :: proc(room: ^Room, position: grid.Position, ignored_index := -1) -> (int, bool) {
	if room == nil {
		return 0, false
	}
	for enemy, index in room.enemies {
		if index != ignored_index && enemy.position == position {
			return index, true
		}
	}
	return 0, false
}

enemy_index_by_id :: proc(room: ^Room, id: u32) -> (int, bool) {
	if room == nil || id == 0 {
		return 0, false
	}
	for enemy, index in room.enemies {
		if enemy.id == id {
			return index, true
		}
	}
	return 0, false
}

trap_index_by_id :: proc(room: ^Room, id: u32) -> (int, bool) {
	if room == nil || id == 0 {
		return 0, false
	}
	for trap, index in room.traps {
		if trap.id == id {
			return index, true
		}
	}
	return 0, false
}

create_room :: proc(level_data: ^level.Level, player: ^Player, content: Room_Content) -> (result: Room, ok: bool) {
	if level_data == nil || player == nil || !level_data.has_player_spawn ||
	   len(content.enemies) > MAX_ENEMIES_PER_ROOM ||
	   len(content.traps) > MAX_TRAPS_PER_ROOM ||
	   len(content.objects) > MAX_GRID_OBJECTS_PER_ROOM ||
	   !validate_grid_object_definitions() {
		return {}, false
	}
	if player.stats.max_health <= 0 || player.health <= 0 || player.health > player.stats.max_health ||
	   player.stats.attack <= 0 || player.stats.defense < 0 ||
	   player.gold < 0 || !validate_deck_state(&player.deck) || !validate_relic_state(&player.relics) ||
	   !validate_dice_state(&player.dice) || !weapon_slot_valid(player.equipment.weapon) ||
	   !weapon_slot_valid(player.equipment.reserve) || !m8_profile_valid(player.m8_profile) {
		return {}, false
	}

	exit_position, has_exit := find_exit(level_data)
	if !has_exit {
		return {}, false
	}

	result.level_data = level_data
	result.player = player
	result.exit_position = exit_position
	result.encounter_kind = content.encounter_kind
	result.family = content.family
	result.modifier = content.modifier
	result.next_enemy_id = 1
	result.next_trap_id = 1
	result.next_object_id = 1
	result.reaction_bindings.next_id = 1
	result.enemies = make([dynamic]Enemy, 0, len(content.enemies))
	result.traps = make([dynamic]Trap, 0, len(content.traps))
	result.obstacles = make([dynamic]Obstacle, 0, len(content.obstacles))
	result.objects = make([dynamic]Grid_Object, 0, MAX_GRID_OBJECTS_PER_ROOM)
	loot_capacity := len(content.enemies)
	for spawn in content.enemies {
		if tactical_enabled(&result) && spawn.archetype == .Brute { loot_capacity += 1 }
		if spawn.drops_healing {
			loot_capacity += 1
		}
	}
	result.loot = make([dynamic]Loot, 0, loot_capacity)
	result.enemy_path_distances = make([]int, len(level_data.tiles.cells))
	result.enemy_path_queue = make([]grid.Position, len(level_data.tiles.cells))
	spawn_position := level_data.player_spawn

	for position in content.obstacles {
		if !base_cell_is_walkable(&result, position) || position == spawn_position || position == exit_position || obstacle_at(&result, position) {
			destroy_room(&result)
			return {}, false
		}
		append(&result.obstacles, Obstacle{position = position})
	}

	for spawn in content.objects {
		definition, found := grid_object_definition(spawn.kind)
		_, duplicate := object_index_at(&result, spawn.position)
		if !found || !base_cell_is_walkable(&result, spawn.position) ||
		   obstacle_at(&result, spawn.position) || duplicate ||
		   spawn.position == spawn_position || spawn.position == exit_position {
			destroy_room(&result)
			return {}, false
		}
		append(&result.objects, Grid_Object{
			id = result.next_object_id,
			kind = spawn.kind,
			position = spawn.position,
			max_health = definition.max_health,
			health = definition.max_health,
		})
		result.next_object_id += 1
	}

	for spawn in content.enemies {
		_, occupied := enemy_index_at(&result, spawn.position)
		_, overlaps_object := object_index_at(&result, spawn.position)
		if spawn.health <= 0 || spawn.attack <= 0 || spawn.archetype >= .Count ||
		   !base_cell_is_walkable(&result, spawn.position) ||
		   cell_blocks_movement(&result, spawn.position) || occupied || overlaps_object ||
		   spawn.position == spawn_position || spawn.position == exit_position {
			destroy_room(&result)
			return {}, false
		}
		append(&result.enemies, Enemy{
			id = result.next_enemy_id,
			archetype = spawn.archetype,
			position = spawn.position,
			max_health = spawn.health,
			health = spawn.health,
			attack = spawn.attack,
			drops_healing = spawn.drops_healing,
			boss_phase = 1 if spawn.archetype == .Demolitionist else 0,
		})
		result.next_enemy_id += 1
	}

	for spawn in content.traps {
		_, duplicate := trap_index_at(&result, spawn.position)
		_, overlaps_enemy := enemy_index_at(&result, spawn.position)
		_, overlaps_object := object_index_at(&result, spawn.position)
		if spawn.damage <= 0 ||
		   !base_cell_is_walkable(&result, spawn.position) ||
		   obstacle_at(&result, spawn.position) || duplicate || overlaps_enemy || overlaps_object ||
		   spawn.position == spawn_position || spawn.position == exit_position {
			destroy_room(&result)
			return {}, false
		}
		append(&result.traps, Trap{
			id = result.next_trap_id,
			position = spawn.position,
			damage = spawn.damage,
			armed = true,
		})
		result.next_trap_id += 1
	}

	if !valid_room_modifier(&result, &result.modifier) {
		destroy_room(&result)
		return {}, false
	}
	result.phase = .Combat if len(result.enemies) > 0 else .Loot
	disarm_room_modifier_after_combat(&result)
	if result.phase == .Combat {
		if !begin_deck_combat(&player.deck) {
			destroy_room(&result)
			return {}, false
		}
	} else {
		finish_deck_combat(&player.deck)
	}
	player.position = spawn_position
	clear_statuses(&player.statuses)
	begin_tactical_room(&result)
	begin_room_relics(&result)
	if result.phase == .Combat {
		plan_enemy_intents(&result)
	}
	return result, true
}

destroy_room :: proc(room: ^Room) {
	if room == nil {
		return
	}
	delete(room.enemies)
	delete(room.traps)
	delete(room.obstacles)
	delete(room.objects)
	delete(room.loot)
	delete(room.enemy_path_distances)
	delete(room.enemy_path_queue)
	room^ = {}
}

trigger_trap :: proc(room: ^Room) {
	assert(room != nil && room.player != nil)
	resolution := resolve_trap_for_entity(room, PLAYER_ENTITY)
	if resolution.triggered {
		append_event_log(&room.recent_events, &resolution.report.events)
	}
}

loot_is_in_magnet_range :: proc(player_position, loot_position: grid.Position) -> bool {
	distance := max(abs(player_position.x-loot_position.x), abs(player_position.y-loot_position.y))
	return distance <= LOOT_MAGNET_RANGE_CELLS
}

collect_loot_in_magnet_range :: proc(room: ^Room) -> (collected: int) {
	assert(room != nil && room.player != nil)
	if room.phase != .Combat && room.phase != .Loot {
		return
	}

	index := 0
	for index < len(room.loot) {
		item := room.loot[index]
		if !loot_is_in_magnet_range(room.player.position, item.position) {
			index += 1
			continue
		}

		if item.kind == .Weapon {
			if collect_weapon(room.player, item.weapon_id, item.amount) {
				record_event(&room.recent_events, {
					kind = .Loot_Collected, source = PLAYER_ENTITY, target = PLAYER_ENTITY,
					amount = item.amount, from_position = item.position, to_position = room.player.position, loot_kind = .Weapon,
				})
				unordered_remove(&room.loot, index)
				collected += 1
			} else { index += 1 }
			continue
		}

		action := make_action(.Collect, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := false
		switch item.kind {
		case .Gold:
			added = add_effect(&action, gain_gold_effect(item.amount))
		case .Healing:
			added = add_effect(&action, heal_effect(PLAYER_ENTITY, item.amount))
		case .Weapon:
			unreachable()
		}
		assert(added)
		report := resolve_action(room, &action)
		if report.accepted {
			record_event(&room.recent_events, {
				kind = .Loot_Collected,
				source = PLAYER_ENTITY,
				target = PLAYER_ENTITY,
				amount = item.amount,
				from_position = item.position,
				to_position = room.player.position,
				loot_kind = item.kind,
			})
			append_event_log(&room.recent_events, &report.events)
			unordered_remove(&room.loot, index)
			collected += 1
		} else {
			index += 1
		}
	}
	return
}

Player_Command_Outcome :: enum {
	Combat_Continues,
	Combat_Ended,
	Player_Defeated,
}

player_command_outcome_for_phase :: proc(phase: Room_Phase) -> Player_Command_Outcome {
	switch phase {
	case .Combat:
		return .Combat_Continues
	case .Loot, .Complete:
		return .Combat_Ended
	case .Defeat:
		return .Player_Defeated
	}
	return .Combat_Continues
}

// Accepted commands share loot and terminal cleanup. Classic advances one
// response pulse; M7 pays combat time and queues the world beats it crosses.
finish_player_combat_command :: proc(room: ^Room, time_cost: f32 = TACTICAL_ATTACK_SECONDS) -> (
	pulse: Pulse_Report,
	outcome: Player_Command_Outcome,
) {
	assert(room != nil && room.player != nil)
	collect_loot_in_magnet_range(room)
	outcome = player_command_outcome_for_phase(room.phase)
	if outcome != .Combat_Continues {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
		return
	}
	if tactical_enabled(room) {
		tactical_spend_action_time(room, time_cost)
		return
	}
	pulse = advance_combat_pulse(room)
	append_event_log(&room.recent_events, &pulse.events)
	collect_loot_in_magnet_range(room)
	outcome = player_command_outcome_for_phase(room.phase)
	if outcome != .Combat_Continues {
		sync_deck_with_room_phase(room)
	}
	return
}

kill_enemy :: proc(room: ^Room, enemy_index: int) -> (drops: [3]Loot, drop_count: int) {
	assert(room != nil)
	enemy := room.enemies[enemy_index]
	position := enemy.position
	remove_reaction_bindings_for_owner(room, enemy_entity(enemy.id))
	unordered_remove(&room.enemies, enemy_index)
	drops[drop_count] = {position = position, kind = .Gold, amount = 1}
	append(&room.loot, drops[drop_count])
	drop_count += 1
	if enemy.drops_healing {
		drops[drop_count] = {position = position, kind = .Healing, amount = 2}
		append(&room.loot, drops[drop_count])
		drop_count += 1
	}
	if tactical_enabled(room) && enemy.archetype == .Brute {
		definition, _ := weapon_definition(.Iron_Cleaver)
		drops[drop_count] = {position = position, kind = .Weapon, amount = definition.max_uses, weapon_id = .Iron_Cleaver}
		append(&room.loot, drops[drop_count])
		drop_count += 1
	}
	if len(room.enemies) == 0 {
		if room.phase != .Defeat {
			room.phase = .Loot
		}
		clear_enemy_intents(room)
	}
	return
}

enemy_can_move_to :: proc(room: ^Room, enemy_index: int, position: grid.Position) -> bool {
	if cell_blocks_movement(room, position) || position == room.player.position {
		return false
	}
	_, occupied := enemy_index_at(room, position, enemy_index)
	return !occupied
}

sign :: proc(value: int) -> int {
	if value < 0 do return -1
	if value > 0 do return 1
	return 0
}

try_move_player :: proc(room: ^Room, direction: Move_Direction) -> Action_Result {
	if !tactical_allows_movement(room) { return .Invalid_Phase }
	if room == nil || room.player == nil || (room.phase != .Combat && room.phase != .Loot) {
		return .Invalid_Phase
	}
	critical := tactical_take_critical(room)
	target := add_position(room.player.position, direction_offset(direction))
	// Walking remains available during recovery, but walking into an enemy is
	// an attack and must pass the offensive gate before mutating the event log.
	if room.phase == .Combat && !tactical_allows_action(room) {
		if _, found := enemy_index_at(room, target); found { return .Invalid_Phase }
	}
	clear_event_log(&room.recent_events)
	if room.phase == .Combat {
		if enemy_index, found := enemy_index_at(room, target); found {
			enemy := room.enemies[enemy_index]
			action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_entity(enemy.id)), .Adjacent_Opponent)
			damage := player_basic_attack_damage(room.player)
			if critical { damage = critical_bump_damage(damage) }
			added := add_effect(&action, damage_effect(enemy_entity(enemy.id), damage))
			assert(added)
			report := resolve_action(room, &action)
			assert(report.accepted)
			consume_equipped_weapon_use(room.player)
			if critical { mark_critical_events(&report.events) }
			append_event_log(&room.recent_events, &report.events)
			_, outcome := finish_player_combat_command(room)
			switch outcome {
			case .Player_Defeated:
				return .Player_Defeated
			case .Combat_Ended:
				return .Combat_Ended
			case .Combat_Continues:
			}
			return .Attacked
		}
	}

	if cell_blocks_movement(room, target) {
		// Loot cannot softlock when a movable block was pushed into a corridor.
		if room.phase == .Loot {
			if object, found := grid_object_at(room, target); found {
				definition, _ := grid_object_definition(object.kind)
				if definition.movable && definition.damageable {
					ref := object_entity(object.id)
					action := make_action(.Attack, PLAYER_ENTITY, entity_target(ref), .Opponent_Or_Object)
					added := add_effect(&action, damage_effect(ref, player_basic_attack_damage(room.player)))
					assert(added)
					report := resolve_action(room, &action)
					if report.accepted {
						consume_equipped_weapon_use(room.player)
						append_event_log(&room.recent_events, &report.events)
						return .Attacked
					}
				}
			}
		}
		return .Blocked
	}

	// On the tick a straight step carries one cell further when it is clear.
	if critical && room.phase == .Combat {
		further := add_position(target, direction_offset(direction))
		query := query_entity_movement(room, PLAYER_ENTITY, further)
		if movement_query_is_clear(&query) { target = further }
	}
	action := make_action(.Move, PLAYER_ENTITY, cell_target(target), .Walkable_Cell)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, target))
	assert(added)
	report := resolve_action(room, &action)
	if !report.accepted {
		return .Blocked
	}
	if critical { mark_critical_events(&report.events) }
	append_event_log(&room.recent_events, &report.events)
	collect_loot_in_magnet_range(room)

	if room.phase == .Loot {
		collect_loot_in_magnet_range(room)
		sync_deck_with_room_phase(room)
		if room.player.position == room.exit_position {
			room.phase = .Complete
			return .Room_Completed
		}
		return .Moved
	}

	_, outcome := finish_player_combat_command(room)
	switch outcome {
	case .Player_Defeated:
		return .Player_Defeated
	case .Combat_Ended:
		return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}

wait_player_turn :: proc(room: ^Room) -> Action_Result {
	if !tactical_allows_action(room) { return .Invalid_Phase }
	if room == nil || room.phase != .Combat {
		return .Invalid_Phase
	}
	clear_event_log(&room.recent_events)
	action := make_action(.Wait, PLAYER_ENTITY, {}, .None)
	report := resolve_action(room, &action)
	if !report.accepted do return .Invalid_Phase
	append_event_log(&room.recent_events, &report.events)
	_, outcome := finish_player_combat_command(room)
	switch outcome {
	case .Player_Defeated:
		return .Player_Defeated
	case .Combat_Ended:
		return .Combat_Ended
	case .Combat_Continues:
	}
	return .None
}
