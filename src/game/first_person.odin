package game

import "core:math"
import grid "../engine/grid"

// FIRST PERSON SHOOTER. The card puts the player behind his own eyes for
// FIRST_PERSON_SECONDS of the world's seconds (two more for each upgrade and on
// the tick); the room goes on as ever around him: the window's clock, the
// enemies' intents and blows, their defence prompts, the Bruciatura and the
// fires. No card is played meanwhile, no arrow of Feretro loosed: his one
// weapon is a paper AK whose held trigger fires FIRST_PERSON_SHOTS_PER_SECOND
// shots a second, each a hitscan along the view (first_person_trace) that
// costs no window time and is no action of his (his Veleno does not bite). He
// still steps, bumps, dodges and waits as ever, his keys turned with the view
// (first_person_key_directions). The board (render/first_person.odin) dives
// into his eyes and rises again when the seconds are over, the room ends or he
// falls: the end is no command and no event, the board follows the state.

FIRST_PERSON_SECONDS :: i32(20)
FIRST_PERSON_SECONDS_PER_UPGRADE :: i32(2)
FIRST_PERSON_CRITICAL_SECONDS :: i32(2)
FIRST_PERSON_MAX_UPGRADE_LEVEL :: i32(5)
FIRST_PERSON_SHOTS_PER_SECOND :: 6
FIRST_PERSON_SHOT_SECONDS :: f32(1)/f32(FIRST_PERSON_SHOTS_PER_SECOND)
FIRST_PERSON_SHOT_DAMAGE :: i32(1)
// A held trigger carries at most one shot's lateness from frame to frame: a
// long frame never fires a burst.
FIRST_PERSON_MAX_CARRY :: FIRST_PERSON_SHOT_SECONDS
// The eye above the floor, and how far the view may look up or down (radians).
FIRST_PERSON_EYE_HEIGHT :: f32(1.05)
FIRST_PERSON_PITCH_LIMIT :: f32(0.55)
// How far from the centre of the player's cell the view's eye may be (riding
// his glide from cell to cell, a dodge's two cells at most), and a foe's card
// from its cell's centre (sliding to the cell its step, push or charge took
// it to), on either axis, and how far off its stand a card may be lifted (a
// hop), for a shot to take them as the board shows them.
FIRST_PERSON_EYE_SLACK :: f32(2.05)
FIRST_PERSON_CARD_SLACK :: f32(3.05)
FIRST_PERSON_CARD_LIFT :: f32(1)
// The AK's wounds carry this in Game_Event.visual_group (area_mask has no bit
// left): the board shows them with its own tracer and spark, no swing of the
// player's card and no flinch of the struck one (event_is_first_person_shot).
FIRST_PERSON_VISUAL_GROUP :: u32(0x4B_5000)
// The last shots fired, for the board's tracers.
FIRST_PERSON_TRAIL :: 8
FIRST_PERSON_EPSILON :: f32(1e-5)

// A foe's card as the board shows it when a shot is fired: where it stands on
// the board (its cell's centre once it stands still, between two cells while
// it slides) and how far it is lifted off its stand (a hop).
First_Person_Card :: struct {
	enemy_id: u32,
	at: [2]f32,
	lift: f32,
}

// The view a shot is fired along: `yaw` on the board (0 east, a quarter turn
// south: atan2 of the board's y over its x), `pitch` up from level; and, when
// the board `framed` it, what the view showed as the shot left: the eye on the
// board (riding the player's glide from cell to cell) and the foes' cards
// where they stood. Unframed, the shot leaves the centre of his cell and each
// foe's card stands on its own cell's centre; so does a foe not among `cards`.
First_Person_Aim :: struct {
	yaw, pitch: f32,
	framed: bool,
	eye: [2]f32,
	cards: [MAX_ENEMIES_PER_ROOM]First_Person_Card,
	card_count: int,
}

// A foe's card as the shots find it: the half width of its paper (the white
// cut-out round the drawing, ink line included) at heights above its stand's
// floor, straight between them; nothing below the first or above the last.
// Measured from the living cards' own paper (render: the card stands on its
// stand facing the eye, its feet on its cell's centre), which
// first_person_view_test checks it against.
@(rodata)
FIRST_PERSON_OUTLINES := #partial [Enemy_Archetype][][2]f32{
	.Chaser = {{0.030, 0.508}, {0.067, 0.566}, {0.096, 0.725}, {0.125, 0.783}, {0.198, 0.856}, {0.285, 0.899}, {0.416, 0.899},
		{0.503, 0.856}, {0.575, 0.783}, {0.880, 0.624}, {1.112, 0.624}, {1.242, 0.566}, {1.453, 0.276}},
	.Archer = {{0.029, 0.465}, {0.229, 0.689}, {0.325, 0.737}, {0.422, 0.737}, {0.534, 0.801}, {0.662, 0.801}, {0.758, 0.737},
		{0.886, 0.753}, {0.982, 0.705}, {1.095, 0.593}, {1.223, 0.689}, {1.383, 0.705}, {1.479, 0.641}, {1.559, 0.497}, {1.575, 0.417},
		{1.591, 0.385}, {1.607, 0.160}, {1.632, 0.128}},
	.Brute = {{0.030, 0.075}, {0.053, 0.104}, {0.068, 0.552}, {0.098, 0.612}, {0.173, 0.657}, {0.381, 0.642}, {0.501, 0.761},
		{0.665, 0.836}, {0.949, 0.791}, {1.158, 0.701}, {1.396, 0.701}, {1.501, 0.657}, {1.680, 0.493}, {1.725, 0.388}, {1.740, 0.239},
		{1.821, 0.090}},
	.Bomber = {{0.029, 0.377}, {0.101, 0.489}, {0.213, 0.521}, {0.678, 0.793}, {0.902, 0.793}, {0.998, 0.745}, {1.127, 0.825},
		{1.239, 0.841}, {1.383, 0.777}, {1.415, 0.713}, {1.431, 0.633}, {1.447, 0.473}, {1.575, 0.377}, {1.632, 0.280}},
	.Custodian = {{0.033, 0.390}, {0.118, 0.509}, {0.171, 0.535}, {0.435, 0.495}, {0.620, 0.575}, {0.739, 0.575}, {0.977, 0.509},
		{1.201, 0.627}, {1.254, 0.627}, {1.373, 0.561}, {1.505, 0.442}, {1.531, 0.390}, {1.545, 0.152}, {1.591, 0.059}},
	.Demolitionist = {{0.029, 0.411}, {0.053, 0.492}, {0.069, 0.702}, {0.134, 0.799}, {0.198, 0.831}, {0.311, 0.863},
		{0.392, 0.863}, {0.472, 0.815}, {0.731, 0.847}, {0.972, 0.766}, {1.085, 0.847}, {1.231, 0.863}, {1.311, 0.815}, {1.505, 0.815},
		{1.602, 0.766}, {1.731, 0.637}, {1.763, 0.573}, {1.795, 0.250}, {1.876, 0.186}, {1.932, 0.089}},
}

// What a shot met: nothing in sight, the floor, a solid thing (a wall, the
// room's edge, cover, a blocking object) or a foe.
First_Person_Hit :: enum u8 {None, Floor, Solid, Foe}

First_Person_Shot :: struct {
	// Counted from the room's first shot (First_Person_State.shots).
	number: i32,
	hit: First_Person_Hit,
	// The foe struck (SYSTEM_ENTITY otherwise) and the cell met.
	target: Entity_Ref,
	cell: grid.Position,
	// From the eye to where it stopped, in world units: x east, y up, z south
	// (the board's y), cell centres at whole numbers plus a half.
	origin, point: [3]f32,
	// What the foe actually lost.
	damage: i32,
}

// The weapon in hand behind the player's eyes. Each is a card of its own; they
// share the view: its dive and rise, its seconds, its pause, its ban on cards
// and its save (docs/piano-prima-persona.md, sezione 4.1). The first is the AK,
// as every save from before the others is.
First_Person_Weapon :: enum u8 {AK, Fists, Sword, Bow}

// What the rules ask of a weapon.
First_Person_Weapon_Rules :: struct {
	// The card whose view it is (First_Person_Begun names it).
	card: Card_Id,
	// Whether it may be taken up on a dinosaur's back (dinosaur.odin).
	while_riding: bool,
}

// The weapons whose cards are still to come name the AK's until then (Fasi 2,
// 4 and 6 of docs/piano-prima-persona.md); none of them is taken up riding (the
// user's choice).
@(rodata)
FIRST_PERSON_WEAPONS := [First_Person_Weapon]First_Person_Weapon_Rules{
	.AK = {card = .First_Person, while_riding = true},
	.Fists = {card = .First_Person_Brawler},
	.Sword = {card = .First_Person},
	.Bow = {card = .First_Person},
}

// The AK's own.
First_Person_AK :: struct {
	// Seconds until the trigger may fire again (below zero: a shot overdue).
	cooldown: f32,
	// The left button held, as the controller read it this frame.
	trigger: bool,
	// The last FIRST_PERSON_TRAIL shots by number (First_Person_State.shots).
	trail: [FIRST_PERSON_TRAIL]First_Person_Shot,
}

// What only the weapon in hand keeps. One view is open at a time, so they
// share their bytes (Room keeps under 9 KB, event_test): taking up another
// weapon clears them. A save keeps them through First_Person_Save, as JSON
// reads no raw union.
First_Person_Arms :: struct #raw_union {
	using ak: First_Person_AK,
	// FIRST PERSON BRAWLER's body (first_person_fists.odin).
	fists: First_Person_Fists,
	// FIRST PERSON FENCER's blade, guard and grapple (first_person_sword.odin).
	sword: First_Person_Sword,
}

First_Person_State :: struct {
	active: bool,
	weapon: First_Person_Weapon,
	// World seconds left of `duration`.
	remaining, duration: f32,
	// Shots fired in the room so far and those that struck a foe, whatever
	// was in hand between them.
	shots, hits: i32,
	using arms: First_Person_Arms,
}

// The view as a save keeps it (expedition/snapshot.odin). JSON reads no raw
// union, so here each weapon's own have keys of their own; the AK's keep the
// names they had before the other weapons, and a save without `weapon` is the
// AK's.
First_Person_Save :: struct {
	active: bool,
	weapon: First_Person_Weapon,
	remaining, duration: f32,
	cooldown: f32,
	trigger: bool,
	shots, hits: i32,
	trail: [FIRST_PERSON_TRAIL]First_Person_Shot,
	// The fists' body, punches and marks (first_person_fists.odin).
	fists: First_Person_Fists,
	// The sword's blade, guard and grapple (first_person_sword.odin).
	sword: First_Person_Sword,
}

first_person_save :: proc(state: First_Person_State) -> (save: First_Person_Save) {
	save.active, save.weapon, save.remaining, save.duration = state.active, state.weapon, state.remaining, state.duration
	save.shots, save.hits = state.shots, state.hits
	switch state.weapon {
	case .AK: save.cooldown, save.trigger, save.trail = state.cooldown, state.trigger, state.trail
	case .Fists: save.fists = state.fists
	case .Sword: save.sword = state.sword
	// Nothing of its own yet.
	case .Bow:
	}
	return
}

// Refuses a weapon the game does not know.
first_person_load :: proc(save: First_Person_Save) -> (state: First_Person_State, ok: bool) {
	if _, known := first_person_effect_weapon(i32(save.weapon)); !known { return }
	state.active, state.weapon, state.remaining, state.duration = save.active, save.weapon, save.remaining, save.duration
	state.shots, state.hits = save.shots, save.hits
	switch save.weapon {
	case .AK: state.cooldown, state.trigger, state.trail = save.cooldown, save.trigger, save.trail
	case .Fists: state.fists = save.fists
	case .Sword: state.sword = save.sword
	case .Bow:
	}
	return state, true
}

@(private)
first_person_effect :: proc(seconds: i32, weapon := First_Person_Weapon.AK) -> Effect {
	return {kind = .First_Person, target = PLAYER_ENTITY, amount = seconds, charges = i32(weapon)}
}

// The weapon an effect of .First_Person takes up (its charges), if one.
first_person_effect_weapon :: proc(charges: i32) -> (weapon: First_Person_Weapon, ok: bool) {
	if charges < 0 || charges > i32(max(First_Person_Weapon)) { return }
	return First_Person_Weapon(charges), true
}

// Whether a card is one of the views behind his eyes (the cards of FIRST_PERSON_WEAPONS).
card_is_first_person :: proc(id: Card_Id) -> bool {
	for rules in FIRST_PERSON_WEAPONS { if rules.card == id { return true } }
	return false
}

tactical_first_person_active :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.first_person.active && room.phase == .Combat
}

// The shots and hits of the room go on counting: the board numbers its
// tracers by them. The weapon kept what it had when it is the one taken up
// again (the AK's trail, for the board's tracers); another one starts clear.
tactical_begin_first_person :: proc(room: ^Room, seconds: f32, weapon := First_Person_Weapon.AK) -> bool {
	if !(seconds > 0) || !tactical_can_begin_first_person(room, weapon) { return false }
	fp := &room.first_person
	if fp.weapon != weapon { fp.arms = {} }
	fp.active, fp.weapon, fp.remaining, fp.duration = true, weapon, seconds, seconds
	if weapon == .AK { fp.cooldown, fp.trigger = 0, false }
	if weapon == .Fists { first_person_fists_begin(room) }
	if weapon == .Sword { first_person_sword_begin(room) }
	return true
}

// The world's seconds (tactical_advance_clock: frame time, and an action's
// cost where actions do not last it): the view's own, and the trigger's.
// The last one ends it.
tactical_first_person_tick :: proc(room: ^Room, seconds: f32) {
	if !tactical_first_person_active(room) || !(seconds > 0) { return }
	fp := &room.first_person
	fp.remaining = max(f32(0), fp.remaining-seconds)
	if fp.remaining < FIRST_PERSON_EPSILON { fp.remaining = 0 }
	if fp.weapon == .AK { fp.cooldown = max(fp.cooldown-seconds, -FIRST_PERSON_MAX_CARRY if fp.trigger else 0) }
	if fp.weapon == .Sword { first_person_sword_tick(room, seconds) }
	if fp.remaining <= 0 {
		fp.active = false
		if fp.weapon == .AK { fp.trigger, fp.cooldown = false, 0 }
		// Out of the air at once onto the cell under him (the user's choice).
		if fp.weapon == .Fists { fp.fists.airborne, fp.fists.rise_speed, fp.fists.feet = false, 0, f32(cell_height(room, room.player.position)) }
	}
}

// The left button as the controller reads it this frame. Let go, nothing is
// banked: the next press fires at once, or as soon as the last shot allows.
// Only the AK has a trigger.
first_person_set_trigger :: proc(room: ^Room, held: bool) {
	if room == nil || room.first_person.weapon != .AK { return }
	fp := &room.first_person
	fp.trigger = held && tactical_first_person_active(room)
	if !fp.trigger { fp.cooldown = max(fp.cooldown, 0) }
}

// A shot is due: the AK in hand, its trigger held and its time come, the
// world's clock free (no beat resolving, no defence prompt, no cast).
first_person_fire_due :: proc(room: ^Room) -> bool {
	if !tactical_first_person_active(room) { return false }
	fp := &room.first_person
	return fp.weapon == .AK && fp.trigger && fp.remaining > 0 && fp.cooldown <= FIRST_PERSON_EPSILON && !room.tactical_pulse.pending &&
	       room.qte.kind == .None && room.player.tactical.cast_remaining <= 0
}

// One shot along `aim` from the player's eye: the first foe's card on its line
// takes FIRST_PERSON_SHOT_DAMAGE from him, as any blow of his (a Shield takes
// it first, its reactions answer, a kill leaves its loot and may clear the
// room); a solid thing or the floor stops it. Its events go to
// room.recent_events (none when it struck no foe); the trail keeps it either
// way.
first_person_fire :: proc(room: ^Room, aim: First_Person_Aim) -> (shot: First_Person_Shot, fired: bool) {
	if !first_person_fire_due(room) { return }
	clear_event_log(room.recent_events)
	fp := &room.first_person
	fp.cooldown += FIRST_PERSON_SHOT_SECONDS
	fp.shots += 1
	shot = first_person_trace(room, room.player.position, aim)
	shot.number = fp.shots
	fired = true
	if shot.hit == .Foe {
		action := make_action(.Attack, PLAYER_ENTITY, entity_target(shot.target), .Opponent)
		action.visual_group = FIRST_PERSON_VISUAL_GROUP
		added := add_effect(&action, damage_effect(shot.target, FIRST_PERSON_SHOT_DAMAGE))
		assert(added)
		report := resolve_action(room, &action)
		if report.accepted {
			shot.damage = player_damage_dealt(&report, shot.target)
			fp.hits += 1
			append_event_log(room.recent_events, &report.events)
		}
	}
	fp.trail[(shot.number-1)%FIRST_PERSON_TRAIL] = shot
	collect_loot_in_magnet_range(room)
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return
}

// The AK's own wounds (and what else its action recorded).
event_is_first_person_shot :: proc(event: Game_Event) -> bool {
	return event.visual_group == FIRST_PERSON_VISUAL_GROUP
}

// How far the card of `archetype` reaches to either side of its middle
// `height` above its stand's floor (0: none of it there).
first_person_outline_half_width :: proc(archetype: Enemy_Archetype, height: f32) -> f32 {
	knots := FIRST_PERSON_OUTLINES[archetype]
	count := len(knots)
	if count < 2 { return 0 }
	if !(height >= knots[0].x && height <= knots[count-1].x) { return 0 }
	for index in 1..<count {
		a, b := knots[index-1], knots[index]
		if height > b.x { continue }
		if b.x-a.x <= FIRST_PERSON_EPSILON { return max(a.y, b.y) }
		return a.y+(b.y-a.y)*(height-a.x)/(b.x-a.x)
	}
	return 0
}

// The top of the card of `archetype` above its stand's floor.
first_person_outline_top :: proc(archetype: Enemy_Archetype) -> f32 {
	knots := FIRST_PERSON_OUTLINES[archetype]
	return knots[len(knots)-1].x if len(knots) > 0 else 0
}

// The eye a shot of `aim` leaves from: the view's own when it framed one near
// the centre of `from` and over an open cell, else that centre (the sword's
// cuts look from it too, first_person_sword.odin).
@(private)
first_person_eye :: proc(room: ^Room, from: grid.Position, aim: First_Person_Aim) -> [2]f32 {
	centre := [2]f32{f32(from.x)+0.5, f32(from.y)+0.5}
	if !aim.framed { return centre }
	eye := aim.eye
	if !(abs(eye.x-centre.x) <= FIRST_PERSON_EYE_SLACK && abs(eye.y-centre.y) <= FIRST_PERSON_EYE_SLACK) { return centre }
	if lasso_cell_is_solid(room, {x = int(math.floor(eye.x)), y = int(math.floor(eye.y))}) { return centre }
	return eye
}

// Where the card of `enemy` stands for a shot of `aim`: where the view showed
// it, when that is near its cell, else on its cell's centre; and how far it
// is lifted off its stand. The fists' marks find their zones on it too
// (first_person_marks.odin).
@(private)
first_person_card :: proc(enemy: Enemy, aim: First_Person_Aim) -> (at: [2]f32, lift: f32) {
	at = {f32(enemy.position.x)+0.5, f32(enemy.position.y)+0.5}
	if !aim.framed { return }
	for index in 0..<clamp(aim.card_count, 0, len(aim.cards)) {
		card := aim.cards[index]
		if card.enemy_id != enemy.id { continue }
		if abs(card.at.x-at.x) <= FIRST_PERSON_CARD_SLACK && abs(card.at.y-at.y) <= FIRST_PERSON_CARD_SLACK {
			at = card.at
			if card.lift > 0 { lift = min(card.lift, FIRST_PERSON_CARD_LIFT) }
		}
		break
	}
	return
}

// The shot's hitscan from the eye along the view, as the view shows the room.
// On the board, cell by cell (no cell skipped; a corner closed by two solid
// cells stops it): a solid cell stops it at its face, whatever stands there,
// the floor where the ray reaches it, and a cell out of the player's sight
// loses it. Before that, the first foe's card it meets takes it: each card
// stands facing the eye across the view (the board turns every card to its
// camera, and behind his eyes the view is the camera), where the board shows
// it (first_person_card), its paper as wide as its outline at the height the
// ray crosses it; over a card and beside it the shot goes on, and a card
// reaching into the cells beside the ray's own is met there too. A foe out of
// play (enemy_is_out_of_play: on the Lazzo's rope, or the Pinball's ball) or
// out of the player's sight is no body for it.
first_person_trace :: proc(room: ^Room, from: grid.Position, aim: First_Person_Aim) -> (shot: First_Person_Shot) {
	pitch := clamp(aim.pitch, -FIRST_PERSON_PITCH_LIMIT, FIRST_PERSON_PITCH_LIMIT)
	o := first_person_eye(room, from, aim)
	d := [2]f32{math.cos(aim.yaw), math.sin(aim.yaw)}
	rise := math.tan(pitch)
	// The eye stands on its cell's floor, which may be above the board's level.
	base := f32(cell_height(room, from))*HEIGHT_STEP_DRAWN
	shot.origin = {o.x, FIRST_PERSON_EYE_HEIGHT+base, o.y}
	shot.target = SYSTEM_ENTITY
	at :: proc(o, d: [2]f32, base, rise, s: f32) -> [3]f32 {
		return {o.x+d.x*s, FIRST_PERSON_EYE_HEIGHT+base+rise*s, o.y+d.y*s}
	}
	nearest := first_person_trace_board(room, o, d, base, rise, &shot, from.layer)
	if room == nil { return }
	side := max(f32)
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) { continue }
		card, lift := first_person_card(enemy, aim)
		shown := grid.Position{x = int(math.floor(card.x)), y = int(math.floor(card.y)), layer = enemy.position.layer}
		if !tactical_cell_visible(room, enemy.position) && !tactical_cell_visible(room, shown) { continue }
		t := (card.x-o.x)*d.x+(card.y-o.y)*d.y
		if t <= FIRST_PERSON_EPSILON || t > nearest+FIRST_PERSON_EPSILON { continue }
		lateral := abs((card.x-o.x)*d.y-(card.y-o.y)*d.x)
		// The ray's height over the foe's own floor.
		foe_base := f32(cell_height(room, enemy.position))*HEIGHT_STEP_DRAWN
		if lateral > first_person_outline_half_width(enemy.archetype, FIRST_PERSON_EYE_HEIGHT+base-foe_base+rise*t-lift) { continue }
		// Nearer than all before it; two cards as deep, the one the ray
		// crosses nearer its middle.
		if shot.hit == .Foe && t >= nearest-FIRST_PERSON_EPSILON && lateral >= side { continue }
		nearest, side = t, lateral
		shot.hit, shot.target, shot.cell, shot.point = .Foe, enemy_entity(enemy.id), enemy.position, at(o, d, base, rise, t)
	}
	return
}

// The board's part of the hitscan (first_person_trace) from the eye `o`: what
// stops the shot, written into `shot` (nothing struck: a cell out of sight, or
// the walk's end), and how far along the board it stops.
@(private="file")
first_person_trace_board :: proc(room: ^Room, o, d: [2]f32, base, rise: f32, shot: ^First_Person_Shot, layer := i8(grid.GROUND_LAYER)) -> (stop: f32) {
	at :: proc(o, d: [2]f32, base, rise, s: f32) -> [3]f32 {
		return {o.x+d.x*s, FIRST_PERSON_EYE_HEIGHT+base+rise*s, o.y+d.y*s}
	}
	// What the ray meets entering `cell` at `s` along it: with layers, the floor of the column under it, or
	// the column's rock, deck or wall (layers.odin); then a wall, cover or a blocking object on that floor.
	meets :: proc(room: ^Room, cell: grid.Position, base, rise, s: f32) -> (floor: grid.Position, solid: bool) {
		inside: bool
		floor, inside = layer_ray_cell(room, cell, (FIRST_PERSON_EYE_HEIGHT+base+rise*s)/HEIGHT_STEP_DRAWN)
		return floor, inside || lasso_cell_is_solid(room, floor)
	}
	// How far along the ray it meets the floor of `cell` (the height of its steps).
	floor_of :: proc(room: ^Room, cell: grid.Position, base, rise: f32) -> f32 {
		if rise < -FIRST_PERSON_EPSILON { return (FIRST_PERSON_EYE_HEIGHT+base-f32(cell_height(room, cell))*HEIGHT_STEP_DRAWN)/-rise }
		return max(f32)
	}
	big :: f32(1e30)
	cell := grid.Position{x = int(math.floor(o.x)), y = int(math.floor(o.y)), layer = layer}
	step := [2]int{1 if d.x > 0 else -1, 1 if d.y > 0 else -1}
	delta := [2]f32{abs(1/d.x) if abs(d.x) > FIRST_PERSON_EPSILON else big, abs(1/d.y) if abs(d.y) > FIRST_PERSON_EPSILON else big}
	// To the first edge of the eye's cell on either axis.
	next := [2]f32{big, big}
	if delta.x < big { next.x = (f32(cell.x+1)-o.x if d.x > 0 else o.x-f32(cell.x))*delta.x }
	if delta.y < big { next.y = (f32(cell.y+1)-o.y if d.y > 0 else o.y-f32(cell.y))*delta.y }
	s := f32(0)
	limit := 4
	if room != nil && room.level_data != nil { limit += room.level_data.tiles.width+room.level_data.tiles.height }
	for _ in 0..<limit*2 {
		leave := min(next.x, next.y)
		if floor := floor_of(room, cell, base, rise); floor <= leave {
			shot.hit, shot.cell, shot.point = .Floor, cell, at(o, d, base, rise, floor)
			shot.point.y = f32(cell_height(room, cell))*HEIGHT_STEP_DRAWN
			return floor
		}
		entered := cell
		if abs(next.x-next.y) <= FIRST_PERSON_EPSILON {
			// Through a corner: both cells beside it must be open.
			side_a, solid_a := meets(room, grid.offset(cell, step.x, 0), base, rise, next.x)
			_, solid_b := meets(room, grid.offset(cell, 0, step.y), base, rise, next.x)
			if solid_a && solid_b {
				shot.hit, shot.cell, shot.point = .Solid, side_a, at(o, d, base, rise, next.x)
				return next.x
			}
			entered = grid.offset(cell, step.x, step.y)
			s = next.x
			next.x += delta.x
			next.y += delta.y
		} else if next.x < next.y {
			entered.x += step.x
			s = next.x
			next.x += delta.x
		} else {
			entered.y += step.y
			s = next.y
			next.y += delta.y
		}
		solid: bool
		if entered, solid = meets(room, entered, base, rise, s); solid {
			shot.hit, shot.cell, shot.point = .Solid, entered, at(o, d, base, rise, s)
			return s
		}
		// A cell whose floor is above the ray is a cliff face: it stops the shot.
		if f32(cell_height(room, entered))*HEIGHT_STEP_DRAWN > FIRST_PERSON_EYE_HEIGHT+base+rise*s+FIRST_PERSON_EPSILON {
			shot.hit, shot.cell, shot.point = .Solid, entered, at(o, d, base, rise, s)
			return s
		}
		if !tactical_cell_visible(room, entered) {
			shot.cell, shot.point = entered, at(o, d, base, rise, s)
			return s
		}
		cell = entered
	}
	shot.cell, shot.point = cell, at(o, d, base, rise, s)
	return s
}

// The order of the movement keys W, D, S and A (the controller's direction
// keys), as they step off the view.
MOVEMENT_KEY_DIRECTIONS :: [4]Move_Direction{.North, .East, .South, .West}

// The grid's ways by quarter turns of the view's yaw, from the east.
@(private="file")
FIRST_PERSON_WAYS :: [4]Move_Direction{.East, .South, .West, .North}

// The grid way nearest the view's yaw (an exact tie goes clockwise).
@(private = "file")
first_person_way_index :: proc(yaw: f32) -> int {
	turns := lasso_wrap(f64(yaw))/(math.PI/2)
	return int(math.floor(turns+0.5))%4
}

// The ways the movement keys W, D, S and A step, in that order: forward,
// right, back and left of the view, forward the view snapped to the grid.
first_person_key_directions :: proc(yaw: f32) -> (keys: [4]Move_Direction) {
	ways := FIRST_PERSON_WAYS
	k := first_person_way_index(yaw)
	for index in 0..<4 { keys[index] = ways[(k+index)%4] }
	return
}

// The yaw that looks along `direction`.
first_person_yaw :: proc(direction: Move_Direction) -> f32 {
	switch direction {
	case .East: return 0
	case .South: return math.PI/2
	case .West: return math.PI
	case .North: return -math.PI/2
	}
	return 0
}
