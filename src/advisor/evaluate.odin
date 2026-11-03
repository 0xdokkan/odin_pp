package advisor

import game "../game"
import grid "../engine/grid"

// THE EVALUATION AND THE FAST RULE (docs/piano-ia.md, Fase 2, «La valutazione»): what a branch is worth at its end, and
// the simple rule that plays a branch on to the horizon after its first moves (the playout).

// The room at the root, as the evaluation compares a branch's end with it.
Root_Facts :: struct {
	health: i32,
	enemy_count: int,
	ids: [game.MAX_ENEMIES_PER_ROOM]u32,
	healths: [game.MAX_ENEMIES_PER_ROOM]i32,
	archetypes: [game.MAX_ENEMIES_PER_ROOM]game.Enemy_Archetype,
	// The statuses on the board at the root, at their worth (cards.odin, statuses_value).
	statuses: f32,
	// The game's state (context.odin) and the weight of a point of life it gives.
	game_context: Game_Context,
	life_weight: f32,
}

root_facts :: proc(room: ^game.Room, game_context: Game_Context = {}) -> (facts: Root_Facts) {
	facts.game_context = game_context
	facts.life_weight = life_weight(game_context, game_context.heal_outside > 0 || room_heal(room) > 0)
	facts.health = room.player.health
	for enemy in room.enemies {
		if facts.enemy_count == len(facts.ids) { break }
		facts.ids[facts.enemy_count] = enemy.id
		facts.healths[facts.enemy_count] = enemy.health
		facts.archetypes[facts.enemy_count] = enemy.archetype
		facts.enemy_count += 1
	}
	facts.statuses = statuses_value(room)
	return
}

player_dead :: proc(room: ^game.Room) -> bool {
	return room.phase == .Defeat || room.player.health <= 0
}

// The damage the blows already announced will do on `cell` (the foes' intents: their cells, a charge's path).
cell_threat :: proc(room: ^game.Room, cell: grid.Position) -> (damage: f32) {
	for &enemy in room.enemies {
		intent := &enemy.intent
		if intent.kind != .Attack && intent.kind != .Charge && intent.kind != .Bombard { continue }
		if game.enemy_is_staggered(room, &enemy) { continue }
		hit := game.enemy_intent_cell_is_threatened(intent, cell)
		if !hit && intent.kind == .Charge {
			for step in intent.path[:intent.path_count] { if step == cell { hit = true; break } }
		}
		if hit { damage += f32(max(intent.damage, 1))*enemy_knowledge(enemy.archetype).danger }
	}
	return
}

// Whether the player may walk onto `cell` with a plain step: free, no foe on it, no cliff between.
@(private)
step_is_free :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	if _, foe := game.enemy_index_at(room, cell); foe { return false }
	query := game.query_entity_movement(room, game.PLAYER_ENTITY, cell)
	return game.movement_query_is_clear(&query) && !game.step_height_blocked(room, room.player.position, cell)
}

@(private)
manhattan :: proc(a, b: grid.Position) -> int { return abs(a.x-b.x)+abs(a.y-b.y) }

// The weakest foe (the least life; the nearest of equals, then the first): the one the fast rule goes for.
@(private)
weakest_enemy :: proc(room: ^game.Room) -> (index: int, found: bool) {
	best_health, best_distance := i32(max(i32)), max(int)
	for enemy, i in room.enemies {
		distance := manhattan(enemy.position, room.player.position)
		if enemy.health < best_health || (enemy.health == best_health && distance < best_distance) {
			index, found, best_health, best_distance = i, true, enemy.health, distance
		}
	}
	return
}

// Whether an archer stands in a line with `cell`, within its reach, with nothing standing in between.
@(private)
archer_in_line :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	for enemy in room.enemies {
		if enemy.archetype != .Archer || (enemy.position.x != cell.x && enemy.position.y != cell.y) { continue }
		distance := manhattan(enemy.position, cell)
		if distance < game.ARCHER_MIN_ATTACK_RANGE || distance > game.ARCHER_MAX_ATTACK_RANGE { continue }
		dx, dy := sign(cell.x-enemy.position.x), sign(cell.y-enemy.position.y)
		clear := true
		for k in 1..<distance {
			between := grid.offset(enemy.position, dx*k, dy*k)
			if game.cell_blocks_movement(room, between) { clear = false; break }
		}
		if clear { return true }
	}
	return false
}

@(private)
sign :: proc(v: int) -> int { return 1 if v > 0 else (-1 if v < 0 else 0) }

// What the branch is worth at its end, `elapsed` world seconds after the root, its keys' `risk` run: the user's weights.
evaluate :: proc(room: ^game.Room, facts: ^Root_Facts, elapsed: f32, risk: f32 = 0) -> f32 {
	// Death is the worst branch, always; a later one a little less bad.
	if player_dead(room) { return DEATH_VALUE+elapsed }
	value := -facts.life_weight*f32(facts.health-room.player.health)
	for k in 0..<facts.enemy_count {
		index, alive := game.enemy_index_by_id(room, facts.ids[k])
		if alive {
			value += DAMAGE_WEIGHT*f32(max(0, facts.healths[k]-room.enemies[index].health))
		} else {
			value += DAMAGE_WEIGHT*f32(max(0, facts.healths[k]))+enemy_knowledge(facts.archetypes[k]).kill
		}
	}
	value -= risk
	// What the statuses gained or lost since the root will do past the horizon.
	value += statuses_value(room)-facts.statuses
	if room.phase != .Combat { return value+WIN_VALUE }
	// The position: the blows still to land past the horizon, the ways out, the weakest foe near, an archer's line.
	p := room.player.position
	value -= THREAT_WEIGHT*facts.life_weight*cell_threat(room, p)
	value += SLEEPER_VALUE*f32(sleepers_woken(&facts.game_context, p))
	for direction in game.Move_Direction {
		if step_is_free(room, game.add_position(p, game.direction_offset(direction))) { value += EXIT_VALUE }
	}
	if index, found := weakest_enemy(room); found { value -= CLOSE_VALUE*f32(manhattan(room.enemies[index].position, p)) }
	if archer_in_line(room, p) { value += ARCHER_LINE_VALUE }
	return value
}

// THE FAST RULE (the user's choice): «stai fuori dalle caselle minacciate, vai verso il nemico più debole, aspetta se
// sei già al sicuro». On a threatened cell: the first free step out of every threat, else a dodge out of it; a foe
// next to him: the bump on the weakest one; else a safe step towards the weakest foe; else wait.
fast_move :: proc(room: ^game.Room) -> Move {
	p := room.player.position
	if cell_threat(room, p) > 0 {
		for direction in game.Move_Direction {
			cell := game.add_position(p, game.direction_offset(direction))
			if step_is_free(room, cell) && cell_threat(room, cell) == 0 { return {kind = .Step, direction = direction} }
		}
		for direction in game.Move_Direction {
			if cell, ok := game.tactical_dodge_destination(room, direction); ok && cell_threat(room, cell) == 0 {
				return {kind = .Dodge, direction = direction}
			}
		}
	}
	bump, bump_health, has_bump := game.Move_Direction.North, i32(max(i32)), false
	for direction in game.Move_Direction {
		if index, foe := game.enemy_index_at(room, game.add_position(p, game.direction_offset(direction))); foe && room.enemies[index].health < bump_health {
			bump, bump_health, has_bump = direction, room.enemies[index].health, true
		}
	}
	if has_bump { return {kind = .Step, direction = bump} }
	if index, found := weakest_enemy(room); found {
		target := room.enemies[index].position
		dx, dy := target.x-p.x, target.y-p.y
		// The longer way first, then the other.
		ways: [2]game.Move_Direction
		ways[0] = (.East if dx > 0 else .West) if abs(dx) >= abs(dy) else (.South if dy > 0 else .North)
		ways[1] = (.South if dy > 0 else .North) if abs(dx) >= abs(dy) else (.East if dx > 0 else .West)
		gaps := [2]int{abs(dx), abs(dy)} if abs(dx) >= abs(dy) else [2]int{abs(dy), abs(dx)}
		for direction, k in ways {
			if gaps[k] == 0 { continue }
			cell := game.add_position(p, game.direction_offset(direction))
			if step_is_free(room, cell) && cell_threat(room, cell) == 0 { return {kind = .Step, direction = direction} }
		}
	}
	return {kind = .Wait}
}

// THE DANGER (the held advice's one exception, run/advisor_driver.odin): the blows announced on the player's cell now,
// as one number (each foe and its intent); 0 when none.
player_danger :: proc(room: ^game.Room) -> (key: u64) {
	cell := room.player.position
	for &enemy in room.enemies {
		intent := &enemy.intent
		if intent.kind != .Attack && intent.kind != .Charge && intent.kind != .Bombard { continue }
		if game.enemy_is_staggered(room, &enemy) { continue }
		hit := game.enemy_intent_cell_is_threatened(intent, cell)
		if !hit && intent.kind == .Charge {
			for step in intent.path[:intent.path_count] { if step == cell { hit = true; break } }
		}
		if !hit { continue }
		h := u64(0xcbf29ce484222325)
		mix(&h, u64(enemy.id))
		mix(&h, intent.planned_pulse)
		mix(&h, u64(intent.kind))
		key ~= h
	}
	return
}

// Whether an advice held since the player stood on `at` can still be done: he has not been moved, its cell is free,
// its foe alive, its card in hand; with the defence keys up only a defence can be done, and a defence only with them.
advice_possible :: proc(room: ^game.Room, advice: Advice, at: grid.Position) -> bool {
	move := advice.move
	answers := move.kind == .Defend || move.kind == .Key
	if (room.qte.kind != .None) != answers { return false }
	if room.player.position != at && room.qte.kind == .None { return false }
	switch move.kind {
	case .Wait, .Refocus: return true
	case .Step:
		if advice.kind == .Bump { _, foe := game.enemy_index_at(room, advice.cell); return foe }
		return step_is_free(room, advice.cell)
	case .Diagonal: return step_is_free(room, advice.cell)
	case .Dodge:
		_, ok := game.tactical_dodge_destination(room, move.direction)
		return ok
	case .Shoot:
		_, alive := game.enemy_index_by_id(room, move.target.entity.id)
		return alive && game.player_charges(room, .Arrows) > 0
	case .Card:
		index, held := game.hand_card_index_by_id(&room.player.deck, move.card_id)
		return held && room.player.deck.energy >= game.card_energy_cost(room, room.player.deck.hand[index].definition_id)
	case .Defend: return room.qte.kind == .Defense && !room.qte.selected
	case .Key: return room.qte.kind != .None && room.qte.selected
	}
	return false
}
