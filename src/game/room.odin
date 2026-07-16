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
}

create_player :: proc(stats: Player_Stats) -> (Player, bool) {
	if stats.max_health <= 0 || stats.attack <= 0 || stats.defense < 0 {
		return {}, false
	}
	result := Player{
		stats = stats,
		health = stats.max_health,
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
}

Loot :: struct {
	position: grid.Position,
	kind:     Loot_Kind,
	amount:   i32,
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
	enemies:   []Enemy_Spawn,
	traps:     []Trap_Spawn,
	obstacles: []grid.Position,
}

Room :: struct {
	level_data:    ^level.Level,
	player:        ^Player,
	phase:         Room_Phase,
	exit_position: grid.Position,
	enemies:       [dynamic]Enemy,
	traps:         [dynamic]Trap,
	obstacles:     [dynamic]Obstacle,
	loot:          [dynamic]Loot,
	next_enemy_id: u32,
	next_trap_id:  u32,
	pulse_count:   u64,
	recent_events: Event_Log,
	reaction_bindings: Reaction_Binding_Set,
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
	   len(content.traps) > MAX_TRAPS_PER_ROOM {
		return {}, false
	}
	if player.stats.max_health <= 0 || player.health <= 0 || player.health > player.stats.max_health ||
	   player.stats.attack <= 0 || player.stats.defense < 0 ||
	   player.gold < 0 || !validate_deck_state(&player.deck) {
		return {}, false
	}

	exit_position, has_exit := find_exit(level_data)
	if !has_exit {
		return {}, false
	}

	result.level_data = level_data
	result.player = player
	result.exit_position = exit_position
	result.next_enemy_id = 1
	result.next_trap_id = 1
	result.reaction_bindings.next_id = 1
	result.enemies = make([dynamic]Enemy, 0, len(content.enemies))
	result.traps = make([dynamic]Trap, 0, len(content.traps))
	result.obstacles = make([dynamic]Obstacle, 0, len(content.obstacles))
	result.loot = make([dynamic]Loot, 0, len(content.enemies))
	spawn_position := level_data.player_spawn

	for position in content.obstacles {
		if !base_cell_is_walkable(&result, position) || position == spawn_position || position == exit_position || obstacle_at(&result, position) {
			destroy_room(&result)
			return {}, false
		}
		append(&result.obstacles, Obstacle{position = position})
	}

	for spawn in content.enemies {
		_, occupied := enemy_index_at(&result, spawn.position)
		if spawn.health <= 0 || spawn.attack <= 0 || spawn.archetype >= .Count ||
		   !base_cell_is_walkable(&result, spawn.position) ||
		   obstacle_at(&result, spawn.position) || occupied ||
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
		})
		result.next_enemy_id += 1
	}

	for spawn in content.traps {
		_, duplicate := trap_index_at(&result, spawn.position)
		_, overlaps_enemy := enemy_index_at(&result, spawn.position)
		if spawn.damage <= 0 ||
		   !base_cell_is_walkable(&result, spawn.position) ||
		   obstacle_at(&result, spawn.position) || duplicate || overlaps_enemy ||
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

	result.phase = .Combat if len(result.enemies) > 0 else .Loot
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
	delete(room.loot)
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

		action := make_action(.Collect, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := false
		switch item.kind {
		case .Gold:
			added = add_effect(&action, gain_gold_effect(item.amount))
		case .Healing:
			added = add_effect(&action, heal_effect(PLAYER_ENTITY, item.amount))
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

// Epilogo condiviso di ogni comando player accettato durante Combat: loot
// magnetico, un solo pulse nemico, di nuovo loot, poi sync del deck quando il
// fight finisce. Il pulse viene saltato se il comando stesso ha gia chiuso il
// combattimento; l'ordine delle chiamate e un contratto osservato dai test e
// dalla presentation timeline.
finish_player_combat_command :: proc(room: ^Room) -> (
	pulse: Pulse_Report,
	outcome: Player_Command_Outcome,
) {
	assert(room != nil && room.player != nil)
	collect_loot_in_magnet_range(room)
	outcome = player_command_outcome_for_phase(room.phase)
	if outcome != .Combat_Continues {
		sync_deck_with_room_phase(room)
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

kill_enemy :: proc(room: ^Room, enemy_index: int) -> (drops: [2]Loot, drop_count: int) {
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
	if len(room.enemies) == 0 {
		room.phase = .Loot
		clear_enemy_intents(room)
	}
	return
}

enemy_can_move_to :: proc(room: ^Room, enemy_index: int, position: grid.Position) -> bool {
	if !base_cell_is_walkable(room, position) || obstacle_at(room, position) || position == room.player.position {
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
	if room == nil || room.player == nil || (room.phase != .Combat && room.phase != .Loot) {
		return .Invalid_Phase
	}
	clear_event_log(&room.recent_events)

	target := add_position(room.player.position, direction_offset(direction))
	if room.phase == .Combat {
		if enemy_index, found := enemy_index_at(room, target); found {
			enemy := room.enemies[enemy_index]
			action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_entity(enemy.id)), .Adjacent_Opponent)
			added := add_effect(&action, damage_effect(enemy_entity(enemy.id), room.player.stats.attack))
			assert(added)
			report := resolve_action(room, &action)
			assert(report.accepted)
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

	if !base_cell_is_walkable(room, target) || obstacle_at(room, target) {
		return .Blocked
	}

	action := make_action(.Move, PLAYER_ENTITY, cell_target(target), .Walkable_Cell)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, target))
	assert(added)
	report := resolve_action(room, &action)
	if !report.accepted {
		return .Blocked
	}
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
