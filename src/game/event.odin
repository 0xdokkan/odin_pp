package game

import grid "../engine/grid"

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
	// Movimento Ombra (tactical_shadow.odin): the player sinks at from_position
	// for `duration` seconds; he rises again at to_position.
	Shadow_Entered,
	Shadow_Emerged,
	// RIFLESSO (player_charges.odin): an enemy blow that would have hit the
	// player is turned back at its attacker. The attacker's own event, marked
	// as its blow (mark_attack_events); `amount` is what goes back to it.
	Attack_Deflected,
	// DADO DEL DESTINO: a loaded bump's die (dice_roll), rolled as the blow
	// lands on `target`; `duration` is its Fate_Outcome, `amount` the stacks it
	// left or the life it stole.
	Fate_Rolled,
	// LAZZO (lasso.odin): the rope caught `target` at from_position and pulled
	// it, off the floor, onto its ring at to_position; `amount` is the ring's
	// radius, `duration` the first hit's number.
	Lasso_Caught,
	// LAZZO: the swung foe (`source`) struck `target`, a foe on the ring cell
	// it entered (from_position = to_position), or smashed into the solid cell
	// to_position (`target` SYSTEM_ENTITY): hit number `amount`.
	Lasso_Struck,
	// LAZZO: the player moved and let go; the held foe (`target`) fell from
	// the cell under it (from_position) onto to_position. `amount` is the turns
	// it was swung, `duration` its hits.
	Lasso_Released,
	// CANNA DA PESCA (fishing.odin): the player at from_position casts his rod
	// (card_id, card_upgrade_level) at the cell to_position; `duration` is 1
	// when the cell turns to water now, `amount` the room's fishings left.
	Fish_Cast,
	// The bobber floats on the water (from_position = to_position) and a fish
	// bites.
	Fish_Bite,
	// The catch reeled out of the water (from_position) to the player
	// (to_position): food (card_definition the rod, `duration` its
	// Fishing_Food; its d4 and the cure follow), or a card added to the run
	// deck (card_definition and card_id the new card).
	Fish_Caught,
	// PINBALL (pinball.odin): the foe `target` turned into a steel ball on its
	// cell (from_position = to_position); `amount` is the ball's value,
	// `duration` its seconds.
	Pinball_Made,
	// The player at from_position strikes the ball on to_position away;
	// `amount` is its value, `duration` the launch's turn off the line (degrees,
	// + clockwise on a north-up board).
	Pinball_Launched,
	// The ball (`source`, on the cell from_position) touched the solid cell
	// to_position; its value `duration` goes back to `amount`.
	Pinball_Bounced,
	// The ball (`source`, on from_position) struck the foe `target` on
	// to_position: `amount` is the value it took.
	Pinball_Bumped,
	// The ball's time is up: it bursts on its cell and the foe falls there;
	// `amount` is the foes it struck, `duration` the solid things it touched.
	Pinball_Burst,
	// FIRST PERSON SHOOTER (first_person.odin): the player at from_position
	// (= to_position) goes behind his own eyes for `duration` world seconds
	// (card_definition the card). Its end records nothing: the board follows
	// the room's state, and so do the AK's shots (First_Person_State.trail).
	First_Person_Begun,
	// BOMB MARLEY (marley.odin): the party begins at the player's cell
	// (from_position = to_position); `amount` is the bombs' damage and `duration`
	// its world seconds.
	Marley_Begun,
	// The lights are on (at the start, and at every turn of them): `amount` is how many.
	Marley_Lights,
	// A column is warned: the bomb will cross it from from_position (north end)
	// to to_position (south end) in `amount` beats.
	Marley_Warned,
	// A bomb lands on its column, from_position to to_position, `amount` damage.
	Marley_Bomb,
	// `target` stood in a lit cell (from_position = to_position) as the bomb
	// crossed its column: no damage.
	Marley_Saved,
	// The bombs killed a foe: `amount` seconds more, `duration` the seconds left.
	Marley_Bonus,
	// The party is over: `amount` is the foes the bombs killed, `duration` its seconds.
	Marley_Ended,
	// INONDAZIONE (flood.odin): the wave goes from from_position (the middle of
	// the wall behind it) to to_position (the wall in front); `amount` is the
	// push in cells and `duration` its Move_Direction.
	Flood_Swept,
	// A fire went out on from_position (one event a cell it burned over).
	Fire_Extinguished,
	// CANNONE / CANNONE LASER (cannon.odin): the cannon (`source`) at from_position
	// fires along its way to to_position, the last cell it reached; `target` is
	// the first foe struck (SYSTEM_ENTITY: none), `amount` the damage, `duration`
	// 1 for the beam, 0 for the ball.
	Cannon_Fired,
	// A cannon's time is up: it falls apart at from_position.
	Cannon_Broken,
	// BUCO NERO (black_hole.odin): the hole (`source` = `target`) at from_position
	// goes through a beat: `amount` the beats left, `duration` its damage radius.
	Black_Hole_Tick,
	// A foe the hole's damage will kill (`target`, at from_position) is swallowed
	// toward the hole's centre at to_position.
	Black_Hole_Swallowed,
	// The hole's time is up: it closes at from_position.
	Black_Hole_Closed,
	// DINOSAURO (dinosaur.odin): the ride begins (`duration` the Dino_Kind,
	// `amount` the seconds), ends (`amount` the seconds ridden), a Giganotosauro's
	// step stomps (`amount` the damage, `duration` the foes round it).
	Ride_Begun,
	Ride_Ended,
	Dino_Stomp,
	// Sanguinamento: `target` takes `amount` more for its stacks.
	Bleed_Bite,
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

// Build card-zone metadata without recording it: action reports also dispatch
// reactions, while room logs and staged Refocus logs only preserve event order.
@(private)
make_card_zone_event :: proc(
	kind: Game_Event_Kind,
	source, target: Entity_Ref,
	card: Card_Instance,
	from, to: Card_Zone,
) -> Game_Event {
	return {
		kind = kind,
		source = source,
		target = target,
		card_id = card.id,
		card_definition = card.definition_id,
		card_upgrade_level = card.upgrade_level,
		card_lifetime = card.lifetime,
		from_card_zone = from,
		to_card_zone = to,
	}
}

@(private)
record_card_draw :: proc(log: ^Event_Log, card: Card_Instance) -> bool {
	return record_event(log, make_card_zone_event(
		.Card_Drawn, PLAYER_ENTITY, PLAYER_ENTITY, card, .Draw, .Hand,
	))
}

// The 3x3 footprint uses nine bits of area_mask; its top bit marks an action
// played on the tick (tactical_beat.odin) without growing every event log.
EVENT_CRITICAL_BIT :: u16(1)<<15

event_is_critical :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_CRITICAL_BIT != 0
}

// The bit below it marks a Moved made by a teleport (Movement_Mode.Teleport):
// the body vanishes and reappears instead of walking the line between.
EVENT_TELEPORT_BIT :: u16(1)<<14

event_is_teleport :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_TELEPORT_BIT != 0
}

// The two bits below it mark a physical blow (a bump, an enemy's Attack or
// Charge) for the board (render/attack_fx.odin), and whether it flies there
// (a bolt, a bomb, an ember) instead of being swung. The attacker's own
// Damage_Absorbed, Damaged, Explosive_Armed or Attack_Missed then carries
// the attacker's cell in from_position, the aimed cell in to_position and, in
// the footprint bits around to_position, every cell the blow sweeps.
EVENT_ATTACK_BIT :: u16(1)<<13
EVENT_RANGED_BIT :: u16(1)<<12
EVENT_FOOTPRINT_BITS :: u16(0x1ff)
// The bit below them marks the blow RIFLESSO gives back: the attacker's own
// bolt flying home (the board turns that bolt round instead of loosing one of
// the player's), or the player's riposte to a swing.
EVENT_REFLECTED_BIT :: u16(1)<<11

event_is_reflected :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_REFLECTED_BIT != 0
}

// The two bits below mark the LAZZO's own wounds (lasso.odin): the player's
// damage that no blow of his swings (his card keeps spinning), and among them
// the 1 of a full turn (a small token, no flinch on the swung card).
EVENT_LASSO_BIT :: u16(1)<<10
EVENT_LASSO_TURN_BIT :: u16(1)<<9

event_is_lasso :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_LASSO_BIT != 0
}

event_is_lasso_turn :: proc(event: Game_Event) -> bool {
	return event.area_mask&(EVENT_LASSO_BIT|EVENT_LASSO_TURN_BIT) == EVENT_LASSO_BIT|EVENT_LASSO_TURN_BIT
}

// The PINBALL's wounds (pinball.odin): the player's damage that no blow of his
// swings, the ball's. area_mask has no bit left, so they carry the turn bit
// alone, which the Lazzo only ever sets together with its own: nothing else
// may set it alone.
EVENT_PINBALL_BIT :: EVENT_LASSO_TURN_BIT

event_is_pinball :: proc(event: Game_Event) -> bool {
	return event.area_mask&(EVENT_LASSO_BIT|EVENT_LASSO_TURN_BIT) == EVENT_PINBALL_BIT
}

event_is_attack :: proc(event: Game_Event) -> bool {
	return event.area_mask&EVENT_ATTACK_BIT != 0
}

event_is_ranged_attack :: proc(event: Game_Event) -> bool {
	return event.area_mask&(EVENT_ATTACK_BIT|EVENT_RANGED_BIT) == EVENT_ATTACK_BIT|EVENT_RANGED_BIT
}

// The footprint bit of `cell` around `center` (row-major 3x3, as a spell's);
// not ok beyond it.
@(private)
event_footprint_bit :: proc(center, cell: grid.Position) -> (bit: u16, ok: bool) {
	dx, dy := cell.x-center.x, cell.y-center.y
	if abs(dx) > 1 || abs(dy) > 1 { return }
	return u16(1)<<u32((dy+1)*3+dx+1), true
}

// Marks one blow's own events in `log`, from `first` on: the attacker's
// Damage_Absorbed on `target`, then its Damaged, Explosive_Armed,
// Attack_Missed or Attack_Deflected, where the marking stops. The reactions and
// pushes that follow keep their own events, unmarked, and so does damage with
// a status cause. `reflected` marks the blow RIFLESSO gives back.
mark_attack_events :: proc(log: ^Event_Log, first: int, source, target: Entity_Ref,
	origin, aim: grid.Position, cells: []grid.Position, ranged: bool, reflected := false) {
	if log == nil { return }
	// The aim is always swept, whatever else is.
	centre, _ := event_footprint_bit(aim, aim)
	mask := EVENT_ATTACK_BIT|(EVENT_RANGED_BIT if ranged else 0)|(EVENT_REFLECTED_BIT if reflected else 0)|centre
	for cell in cells {
		if bit, ok := event_footprint_bit(aim, cell); ok { mask |= bit }
	}
	for &event in log.events[clamp(first, 0, log.count):log.count] {
		if event.source != source || event.target != target || event.has_status_cause { continue }
		#partial switch event.kind {
		case .Damage_Absorbed, .Damaged, .Explosive_Armed, .Attack_Missed, .Attack_Deflected:
		case: continue
		}
		event.from_position, event.to_position = origin, aim
		event.area_mask = event.area_mask&~EVENT_FOOTPRINT_BITS|mask
		if event.kind != .Damage_Absorbed { break }
	}
}

// Only events[:count] is valid. Clearing a log retains its backing storage;
// callers that need a snapshot must copy the valid prefix into their own log.
Event_Log :: struct {
	events:        [MAX_GAME_EVENTS]Game_Event,
	count:         int,
	dropped_count: int,
}

clear_event_log :: proc(log: ^Event_Log) {
	if log != nil {
		log.count, log.dropped_count = 0, 0
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

// Replace a log without copying the unused tail. The destination owns its
// storage; this never aliases source storage and is safe for self-assignment.
@(private)
copy_event_log :: proc(destination, source: ^Event_Log) {
	if destination == nil || destination == source { return }
	clear_event_log(destination)
	if source == nil { return }
	count := clamp(source.count, 0, MAX_GAME_EVENTS)
	copy(destination.events[:count], source.events[:count])
	destination.count = count
	destination.dropped_count = source.dropped_count+max(0, source.count-MAX_GAME_EVENTS)
}
