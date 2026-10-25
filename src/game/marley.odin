package game

import grid "../engine/grid"
import rng "../engine/rng"

// BOMB MARLEY. Playing the card (its cast is the world's pause) starts a party
// in the room: a mirror ball comes down from above and lights some cells of
// the floor, and Bomb Marley, who is no foe at all, throws bombs to the beat
// from beyond the north wall. Bomb Marley is not an entity of the room: he has
// no cell, no health and no ID, so no card, blow, arrow or ball can reach him
// and no enemy has him in mind.
//
// The party runs on the world's beats of one second each (tactical.odin,
// continue_tactical_pulse), so the cast, a defence prompt, a cinematic die,
// the shadow and a pause stop it as they stop the world. Each beat:
//
//   - the columns warned MARLEY_WARN_BEATS beats ago land: a bomb crosses the
//     whole column, walls and cover aside, and everybody in it, the player and
//     the foes alike, takes the card's damage unless he stands on a lit cell
//     (Marley_Saved); a barrel in the column catches. A foe the bombs kill
//     adds MARLEY_KILL_SECONDS to the party;
//   - the party's clock ticks, within MARLEY_MAX_SECONDS in all;
//   - the lights move every MARLEY_LIGHT_CYCLE beats, and the cells they will
//     move to are on show all the while (not safe yet: they are the next
//     turn's lights). There are MARLEY_EXTRA more than the characters in play
//     (the player and every foe on the floor) at first, one fewer for each
//     MARLEY_DECAY_SECONDS gone, never fewer than half the characters, so that
//     the room is generous at first and not everybody can be saved later; they
//     are spread over the floor, and one is always within MARLEY_NEAR cells of
//     the player;
//   - new columns are warned: few at first, more as the seconds pass, as many
//     again for a wide room. Half of them are the columns of a character.
//
// The party ends when its time is up, with the combat or with the player. The
// room's own stream (Room.marley_random) picks the lights and the columns,
// never a clock. Nothing of Bomb Marley's reaches the player in Movimento Ombra
// (the damage is refused as for every blow) or the Pinball's ball and the
// Lazzo's foe (out of play).

MARLEY_SECONDS :: i32(35)
MARLEY_KILL_SECONDS :: i32(5)
MARLEY_MAX_SECONDS :: i32(90)
MARLEY_CRITICAL_SECONDS :: i32(5)
MARLEY_BASE_DAMAGE :: i32(6)
MARLEY_MAX_UPGRADE_LEVEL :: i32(5)
// Lights above the characters in play at the start, a light fewer after
// every MARLEY_DECAY_SECONDS of party, down to half the characters (2 at least).
MARLEY_EXTRA :: 4
MARLEY_DECAY_SECONDS :: i32(5)
MARLEY_LIGHT_CYCLE :: i32(5)
// Beats between a column's warning and its bomb.
MARLEY_WARN_BEATS :: i32(2)
// One light is always this near (Chebyshev) to the player when they move.
MARLEY_NEAR :: 3
// The bombs of a room 17 cells wide; wider rooms throw more in proportion.
MARLEY_BASE_WIDTH :: 17
// Never more lights than this, however many characters there are (the room
// keeps the state inline: event_test's stack budget, hence the packed cells).
MAX_MARLEY_LIGHTS :: 32
// The bombs of one beat fly together (Game_Event.visual_group).
MARLEY_BOMB_GROUP :: u32(0x4D41_5200)
// Two beats of the widest room's throws.
MAX_MARLEY_COLUMNS :: 16
MARLEY_SEED_SALT :: u64(0xB0B_4A12_1E70_D15C)

// MOSTRA EFFETTO's script (game/card_demo.odin): the film's room fixes the
// lights and the first column so that its take shows a bomb that hurts and a
// character it spares. Everything else is the party's own rules; the lights
// stay where they are and no other column is thrown.
Marley_Demo :: struct {
	scripted: bool,
	lights, next_lights: [3]grid.Position,
	light_count, next_count: int,
	column: int,
}

// A cell packed in two bytes: the party's lights take no more room in the Room.
Marley_Cell :: [2]u8

Marley_Column :: struct {
	x: i32,
	// Beats left before the bomb lands.
	beats: i32,
}

Marley_State :: struct {
	active: bool,
	// World seconds left, and gone.
	remaining, elapsed: i32,
	// The bombs' damage.
	damage: i32,
	// Seconds earned by kills so far, and the foes the bombs killed.
	earned, kills: i32,
	lights: [MAX_MARLEY_LIGHTS]Marley_Cell,
	light_count: int,
	// The lights the next turn will light: on show, never safe.
	next_lights: [MAX_MARLEY_LIGHTS]Marley_Cell,
	next_count: int,
	has_next: bool,
	columns: [MAX_MARLEY_COLUMNS]Marley_Column,
	column_count: int,
}

@(private)
marley_effect :: proc(damage, seconds: i32) -> Effect {
	return {kind = .Marley, target = PLAYER_ENTITY, amount = damage, duration = seconds}
}

tactical_marley_active :: proc(room: ^Room) -> bool {
	return room != nil && room.marley.active && room.phase == .Combat
}

marley_cell :: proc(cell: grid.Position) -> Marley_Cell {
	return {u8(clamp(cell.x, 0, 255)), u8(clamp(cell.y, 0, 255))}
}

marley_position :: proc(cell: Marley_Cell) -> grid.Position {
	return {x = int(cell.x), y = int(cell.y)}
}

// The cell of light `index`, and of the next turn's.
marley_light :: proc(m: ^Marley_State, index: int) -> grid.Position {
	return marley_position(m.lights[index])
}

marley_next_light :: proc(m: ^Marley_State, index: int) -> grid.Position {
	return marley_position(m.next_lights[index])
}

// Sets the lit cells (tests, the film's script).
marley_set_lights :: proc(m: ^Marley_State, cells: []grid.Position) {
	m.light_count = min(len(cells), MAX_MARLEY_LIGHTS)
	for index in 0..<m.light_count { m.lights[index] = marley_cell(cells[index]) }
}

marley_set_next_lights :: proc(m: ^Marley_State, cells: []grid.Position) {
	m.next_count = min(len(cells), MAX_MARLEY_LIGHTS)
	m.has_next = m.next_count > 0
	for index in 0..<m.next_count { m.next_lights[index] = marley_cell(cells[index]) }
}

// The room's own stream for the party: from its seed and the run's dice as the
// room begins (create_room), never a clock.
@(private)
marley_room_stream :: proc(player: ^Player, content: Room_Content) -> u64 {
	seed := content.room_seed~MARLEY_SEED_SALT
	if player != nil { seed ~= player.dice.random_state }
	random := mix_room_seed(seed)
	return random if random != 0 else MARLEY_SEED_SALT
}

// Whether a cell is lit now: whoever stands on it is safe.
marley_cell_is_lit :: proc(room: ^Room, cell: grid.Position) -> bool {
	if !tactical_marley_active(room) { return false }
	cell_packed := marley_cell(cell)
	for light in room.marley.lights[:room.marley.light_count] { if light == cell_packed { return true } }
	return false
}

// Whether a column holds a warned bomb.
marley_column_is_warned :: proc(room: ^Room, x: int) -> bool {
	if !tactical_marley_active(room) { return false }
	for column in room.marley.columns[:room.marley.column_count] { if int(column.x) == x { return true } }
	return false
}

// Beats left before the bomb of column `x` lands (0: none warned there).
marley_column_beats :: proc(room: ^Room, x: int) -> i32 {
	if !tactical_marley_active(room) { return 0 }
	for column in room.marley.columns[:room.marley.column_count] { if int(column.x) == x { return column.beats } }
	return 0
}

// Why the card cannot be played now: one party at a time.
marley_can_begin :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.level_data != nil && room.phase == .Combat && !room.marley.active
}

// A character: the player and every foe on the floor.
@(private = "file")
marley_character_count :: proc(room: ^Room) -> (count: int) {
	count = 1
	for enemy in room.enemies { if !enemy_is_out_of_play(room, enemy.id) { count += 1 } }
	return
}

// The lights a party has `elapsed` seconds in, for the characters now.
marley_light_count :: proc(room: ^Room, elapsed: i32) -> int {
	characters := marley_character_count(room)
	wanted := characters+MARLEY_EXTRA-int(elapsed/MARLEY_DECAY_SECONDS)
	return clamp(max(wanted, max(2, characters/2)), 1, MAX_MARLEY_LIGHTS)
}

// Bombs thrown at the end of the beat that makes `elapsed` seconds: one every
// other second at first, then one, two and three a second, more for a wider room.
marley_throw_count :: proc(elapsed: i32, width: int) -> int {
	base := 0
	switch {
	case elapsed < 10: base = 1 if elapsed%2 == 1 else 0
	case elapsed < 20: base = 1
	case elapsed < 30: base = 2
	case: base = 3
	}
	return (base*width+MARLEY_BASE_WIDTH-1)/MARLEY_BASE_WIDTH
}

@(private = "file")
marley_cell_is_floor :: proc(room: ^Room, cell: grid.Position) -> bool {
	return base_cell_is_walkable(room, cell) && !cell_blocks_movement(room, cell)
}

@(private = "file")
marley_below :: proc(room: ^Room, n: int) -> int {
	if n <= 1 { return 0 }
	return int(rng.below_state(&room.marley_random, u64(n)))
}

// Picks `count` lit cells from the room's floor, none of `avoid` (the lights
// now lit, when the next ones are chosen): the cells nobody stands on first,
// one within MARLEY_NEAR cells of the player, the rest spread out (of a few
// candidates, the one farthest from the lights already chosen). Row-major
// candidates and the room's stream make the same room give the same lights.
@(private = "file")
marley_choose_lights :: proc(room: ^Room, count: int, avoid: []Marley_Cell, out: ^[MAX_MARLEY_LIGHTS]Marley_Cell) -> (chosen: int) {
	tiles := &room.level_data.tiles
	free, taken: [dynamic]grid.Position
	defer delete(free)
	defer delete(taken)
	for y in 0..<tiles.height {
		for x in 0..<tiles.width {
			cell := grid.Position{x = x, y = y}
			if !marley_cell_is_floor(room, cell) { continue }
			skip := false
			for lit in avoid { if lit == marley_cell(cell) { skip = true; break } }
			if skip { continue }
			occupied := room.player.position == cell
			if _, found := enemy_index_at(room, cell); found { occupied = true }
			append(&taken if occupied else &free, cell)
		}
	}
	player := room.player.position
	near :: proc(player, cell: grid.Position) -> bool {
		return max(abs(cell.x-player.x), abs(cell.y-player.y)) <= MARLEY_NEAR
	}
	want := min(count, MAX_MARLEY_LIGHTS, len(free)+len(taken))
	if want <= 0 { return 0 }
	// One light near the player: from the free cells there, or else from any.
	nearby: [dynamic]int
	defer delete(nearby)
	for cell, index in free { if near(player, cell) { append(&nearby, index) } }
	if len(nearby) > 0 {
		pick := nearby[marley_below(room, len(nearby))]
		out[chosen] = marley_cell(free[pick])
		chosen += 1
		unordered_remove(&free, pick)
	} else {
		for cell, index in taken { if near(player, cell) { append(&nearby, index) } }
		if len(nearby) > 0 {
			pick := nearby[marley_below(room, len(nearby))]
			out[chosen] = marley_cell(taken[pick])
			chosen += 1
			unordered_remove(&taken, pick)
		}
	}
	// How far a cell is from the lights chosen (and from the ones on).
	spread :: proc(cell: grid.Position, out: ^[MAX_MARLEY_LIGHTS]Marley_Cell, chosen: int, avoid: []Marley_Cell) -> int {
		best := 1000
		for lit in out[:chosen] { best = min(best, max(abs(cell.x-int(lit.x)), abs(cell.y-int(lit.y)))) }
		for lit in avoid { best = min(best, max(abs(cell.x-int(lit.x)), abs(cell.y-int(lit.y)))) }
		return best
	}
	for pool in ([2]^[dynamic]grid.Position{&free, &taken}) {
		for chosen < want && len(pool^) > 0 {
			best, best_distance := marley_below(room, len(pool^)), -1
			for _ in 0..<3 {
				candidate := marley_below(room, len(pool^))
				distance := spread(pool^[candidate], out, chosen, avoid)
				if distance > best_distance { best, best_distance = candidate, distance }
			}
			out[chosen] = marley_cell(pool^[best])
			chosen += 1
			unordered_remove(pool, best)
		}
	}
	return
}

// The party begins (apply_effect): the ball comes down over the first lights.
@(private)
begin_marley :: proc(room: ^Room, damage, seconds: i32, report: ^Action_Report) -> bool {
	if report == nil || damage <= 0 || seconds <= 0 || !marley_can_begin(room) { return false }
	room.marley = {active = true, remaining = min(seconds, MARLEY_MAX_SECONDS), damage = damage}
	m := &room.marley
	if room.marley_demo.scripted {
		marley_set_lights(m, room.marley_demo.lights[:room.marley_demo.light_count])
		marley_set_next_lights(m, room.marley_demo.next_lights[:room.marley_demo.next_count])
	} else {
		m.light_count = marley_choose_lights(room, marley_light_count(room, 0), nil, &m.lights)
		m.next_count = marley_choose_lights(room, marley_light_count(room, MARLEY_LIGHT_CYCLE), m.lights[:m.light_count], &m.next_lights)
		m.has_next = m.next_count > 0
	}
	at := room.player.position
	record_report_event(report, {kind = .Marley_Begun, source = PLAYER_ENTITY, target = SYSTEM_ENTITY, from_position = at,
		to_position = at, amount = damage, duration = m.remaining, card_definition = .Marley_Party})
	record_report_event(report, {kind = .Marley_Lights, source = PLAYER_ENTITY, target = SYSTEM_ENTITY, from_position = at,
		to_position = at, amount = i32(m.light_count), card_definition = .Marley_Party})
	return true
}

// A bomb crosses column `x` (Marley_Bomb, recorded first, with the beat's
// others, so that they fly together); damage to everybody in it off the lit
// cells follows (marley_resolve_column).
@(private = "file")
marley_throw_bomb :: proc(room: ^Room, pulse: ^Pulse_Report, x: i32) {
	record_event(&pulse.events, {kind = .Marley_Bomb, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
		from_position = {x = int(x), y = 0}, to_position = {x = int(x), y = room.level_data.tiles.height-1}, amount = room.marley.damage,
		card_definition = .Marley_Party, visual_group = MARLEY_BOMB_GROUP})
}

// Wherever along its column the bomb is, whoever stands in it is struck: it is
// no matter whether it bounces over him or rolls under.
@(private = "file")
marley_resolve_column :: proc(room: ^Room, pulse: ^Pulse_Report, x: i32) {
	damage := room.marley.damage
	action := make_action(.Trigger, SYSTEM_ENTITY)
	if room.player.position.x == int(x) {
		if marley_cell_is_lit(room, room.player.position) {
			record_event(&pulse.events, {kind = .Marley_Saved, source = SYSTEM_ENTITY, target = PLAYER_ENTITY,
				from_position = room.player.position, to_position = room.player.position, card_definition = .Marley_Party})
		} else {
			added := add_effect(&action, damage_effect(PLAYER_ENTITY, damage))
			assert(added)
		}
	}
	for enemy in room.enemies {
		if enemy.position.x != int(x) || enemy_is_out_of_play(room, enemy.id) { continue }
		if marley_cell_is_lit(room, enemy.position) {
			record_event(&pulse.events, {kind = .Marley_Saved, source = SYSTEM_ENTITY, target = enemy_entity(enemy.id),
				from_position = enemy.position, to_position = enemy.position, card_definition = .Marley_Party})
			continue
		}
		added := add_effect(&action, damage_effect(enemy_entity(enemy.id), damage))
		assert(added)
	}
	for object in room.objects {
		if object.position.x != int(x) { continue }
		definition, found := grid_object_definition(object.kind)
		if !found || !definition.explosive { continue }
		effect := damage_effect(object_entity(object.id), damage)
		if effect_is_valid(room, effect) && action.effect_count < MAX_ACTION_EFFECTS { add_effect(&action, effect) }
	}
	if action.effect_count == 0 { return }
	report := resolve_action(room, &action)
	merge_action_report(pulse, &report)
	// Every foe the bombs killed earns the party its seconds, within its total.
	if report.enemies_defeated > 0 {
		m := &room.marley
		m.kills += i32(report.enemies_defeated)
		gain := min(i32(report.enemies_defeated)*MARLEY_KILL_SECONDS, max(i32(0), MARLEY_MAX_SECONDS-m.elapsed-m.remaining))
		m.remaining += gain
		m.earned += gain
		record_event(&pulse.events, {kind = .Marley_Bonus, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
			from_position = {x = int(x), y = 0}, to_position = {x = int(x), y = 0}, amount = gain, duration = m.remaining,
			card_definition = .Marley_Party})
	}
}

// The columns a throw can choose: those with floor in them, not already warned.
@(private = "file")
marley_warn_columns :: proc(room: ^Room, count: int) {
	m := &room.marley
	tiles := &room.level_data.tiles
	candidates: [dynamic]i32
	defer delete(candidates)
	for x in 0..<tiles.width {
		if marley_column_is_warned(room, x) { continue }
		for y in 0..<tiles.height {
			if marley_cell_is_floor(room, {x = x, y = y}) { append(&candidates, i32(x)); break }
		}
	}
	// Half of them are a character's column.
	aimed := (count+1)/2
	pool: [dynamic]i32
	defer delete(pool)
	append(&pool, i32(room.player.position.x))
	for enemy in room.enemies { if !enemy_is_out_of_play(room, enemy.id) { append(&pool, i32(enemy.position.x)) } }
	for _ in 0..<count {
		if m.column_count >= MAX_MARLEY_COLUMNS || len(candidates) == 0 { return }
		pick := -1
		if aimed > 0 {
			aimed -= 1
			// A random character's column that is still free.
			start := marley_below(room, len(pool))
			for step in 0..<len(pool) {
				x := pool[(start+step)%len(pool)]
				for candidate, index in candidates { if candidate == x { pick = index; break } }
				if pick >= 0 { break }
			}
		}
		if pick < 0 { pick = marley_below(room, len(candidates)) }
		x := candidates[pick]
		unordered_remove(&candidates, pick)
		m.columns[m.column_count] = {x = x, beats = MARLEY_WARN_BEATS}
		m.column_count += 1
	}
}

// One world beat of the party (continue_tactical_pulse), after the bombs of
// the room and before the foes act.
marley_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || !room.marley.active { return }
	if room.phase != .Combat { room.marley = {}; return }
	m := &room.marley
	// The warned columns come due.
	landing: [MAX_MARLEY_COLUMNS]i32
	landed, kept := 0, 0
	for index in 0..<m.column_count {
		column := m.columns[index]
		column.beats -= 1
		if column.beats <= 0 {
			landing[landed] = column.x
			landed += 1
		} else {
			m.columns[kept] = column
			kept += 1
		}
	}
	for index in kept..<m.column_count { m.columns[index] = {} }
	m.column_count = kept
	for index in 0..<landed { marley_throw_bomb(room, pulse, landing[index]) }
	for index in 0..<landed {
		marley_resolve_column(room, pulse, landing[index])
		if room.phase != .Combat { room.marley = {}; return }
	}
	// The clock.
	m.elapsed += 1
	m.remaining -= 1
	if m.remaining <= 0 {
		record_event(&pulse.events, {kind = .Marley_Ended, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
			from_position = room.player.position, to_position = room.player.position, amount = m.kills,
			duration = m.elapsed, card_definition = .Marley_Party})
		room.marley = {}
		return
	}
	// The lights: at every turn the next ones become the lit ones and the cells
	// after them are chosen and shown (a film's stay put).
	if !room.marley_demo.scripted && m.elapsed%MARLEY_LIGHT_CYCLE == 0 {
		if m.has_next {
			m.lights, m.light_count = m.next_lights, m.next_count
		} else {
			m.light_count = marley_choose_lights(room, marley_light_count(room, m.elapsed), nil, &m.lights)
		}
		m.next_count = marley_choose_lights(room, marley_light_count(room, m.elapsed+MARLEY_LIGHT_CYCLE), m.lights[:m.light_count], &m.next_lights)
		m.has_next = m.next_count > 0
		record_event(&pulse.events, {kind = .Marley_Lights, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
			from_position = room.player.position, to_position = room.player.position, amount = i32(m.light_count),
			card_definition = .Marley_Party})
	}
	// New columns are warned.
	before := m.column_count
	if room.marley_demo.scripted {
		if m.elapsed == 1 && m.column_count < MAX_MARLEY_COLUMNS {
			m.columns[m.column_count] = {x = i32(room.marley_demo.column), beats = MARLEY_WARN_BEATS}
			m.column_count += 1
		}
	} else {
		marley_warn_columns(room, marley_throw_count(m.elapsed, room.level_data.tiles.width))
	}
	for index in before..<m.column_count {
		record_event(&pulse.events, {kind = .Marley_Warned, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
			from_position = {x = int(m.columns[index].x), y = 0}, to_position = {x = int(m.columns[index].x), y = room.level_data.tiles.height-1},
			amount = m.columns[index].beats, card_definition = .Marley_Party})
	}
}
