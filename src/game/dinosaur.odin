package game

import grid "../engine/grid"

// DINOSAURO. Played, the card rolls a d4 (whatever its upgrade: the die is
// fixed) and the player rides the dinosaur the face names for RIDE_SECONDS
// world seconds (+RIDE_SECONDS_PER_UPGRADE an upgrade; the tick adds
// RIDE_CRITICAL_SECONDS), one ride at a time:
//
//   1 Velociraptor: a step costs half the time (0.4 s), so two a second; his
//     bump does the usual damage and leaves 1 stack of Sanguinamento (Bleed);
//   2 Stegosauro: every enemy blow that would hit him goes back at its attacker
//     as RIFLESSO sends it, with no charge to spend (bombs, traps and statuses
//     are no blow);
//   3 Dilophosaurus: every damage he deals a foe, and every blow a foe lands on
//     him, leaves 1 Poison on that foe;
//   4 Giganotosauro: each step stomps: the foes on the four cells round where
//     he lands take GIGA_STOMP_DAMAGE; his bump kills a Chaser, an Archer or a
//     Bomber on the spot and does GIGA_BITE_DAMAGE to anything bigger (a Brute,
//     a Custodian, a boss). A foe his bump would kill is not struck: he walks
//     onto its cell and crushes it (giga_crush_step); one that would survive
//     is bitten as before, by the dinosaur.
//
// Sanguinamento (Status_Kind.Bleed) is a foe's stack status: whenever it takes
// damage, from any source, the damage is raised by its stacks (once: the extra
// brings no more); stacks never wear. The ride ends with its time, with the
// combat or with the player.

RIDE_SECONDS :: i32(20)
RIDE_SECONDS_PER_UPGRADE :: i32(3)
RIDE_CRITICAL_SECONDS :: i32(3)
RIDE_DIE_SIDES :: i32(4)
RAPTOR_MOVE_SECONDS :: f32(0.4)
GIGA_STOMP_DAMAGE :: i32(6)
GIGA_BITE_DAMAGE :: i32(12)

Dino_Kind :: enum {
	Raptor,
	Stego,
	Dilo,
	Giga,
}

Ride_State :: struct {
	active: bool,
	kind: Dino_Kind,
	// World seconds left, and gone.
	remaining, elapsed: i32,
}

@(private)
ride_effect :: proc(seconds: i32, kind: Dino_Kind) -> Effect {
	return {kind = .Ride, target = PLAYER_ENTITY, amount = seconds, charges = i32(kind)+1, card_definition = .Dino_Ride}
}

// The dinosaur a d4 face names.
dino_for_face :: proc(face: i32) -> Dino_Kind {
	return Dino_Kind(clamp(face, 1, 4)-1)
}

dino_name :: proc(kind: Dino_Kind) -> string {
	switch kind {
	case .Raptor: return "Velociraptor"
	case .Stego: return "Stegosauro"
	case .Dilo: return "Dilophosaurus"
	case .Giga: return "Giganotosauro"
	}
	return ""
}

tactical_ride_active :: proc(room: ^Room) -> bool {
	return room != nil && room.ride.active && room.phase == .Combat
}

ride_is :: proc(room: ^Room, kind: Dino_Kind) -> bool {
	return tactical_ride_active(room) && room.ride.kind == kind
}

ride_can_begin :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && !room.ride.active
}

// What a step of the player costs: half as much on the Velociraptor.
player_move_seconds :: proc(room: ^Room) -> f32 {
	return RAPTOR_MOVE_SECONDS if ride_is(room, .Raptor) else TACTICAL_MOVE_SECONDS
}

// The Stegosauro turns every blow back (deflect_enemy_blow).
ride_deflects :: proc(room: ^Room) -> bool {
	return ride_is(room, .Stego)
}

@(private)
begin_ride :: proc(room: ^Room, kind: Dino_Kind, seconds: i32, report: ^Action_Report) -> bool {
	if report == nil || seconds <= 0 || !ride_can_begin(room) { return false }
	room.ride = {active = true, kind = kind, remaining = seconds}
	at := room.player.position
	record_report_event(report, {kind = .Ride_Begun, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = seconds, duration = i32(kind), card_definition = .Dino_Ride})
	return true
}

// One world beat of the ride (the pulse): the time runs down; at its end the
// dinosaur goes.
ride_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || !room.ride.active { return }
	if room.phase != .Combat { room.ride = {}; return }
	room.ride.elapsed += 1
	room.ride.remaining -= 1
	if room.ride.remaining > 0 { return }
	at := room.player.position
	record_event(&pulse.events, {kind = .Ride_Ended, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		amount = room.ride.elapsed, duration = i32(room.ride.kind), card_definition = .Dino_Ride})
	room.ride = {}
}

// The Giganotosauro's step: the foes on the four cells round where he lands
// take GIGA_STOMP_DAMAGE (Dino_Stomp first, so that the board shakes as they
// fall). Called after a step of the player's.
@(private)
ride_stomp :: proc(room: ^Room) {
	if !ride_is(room, .Giga) || room.player == nil { return }
	at := room.player.position
	victims: [4]u32
	count := 0
	for step in ([4]grid.Position{{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}}) {
		if index, found := enemy_index_at(room, grid.offset(at, step.x, step.y)); found {
			victims[count] = room.enemies[index].id
			count += 1
		}
	}
	if count == 0 { return }
	record_event(room.recent_events, {kind = .Dino_Stomp, source = PLAYER_ENTITY, target = SYSTEM_ENTITY, from_position = at, to_position = at,
		amount = GIGA_STOMP_DAMAGE, duration = i32(count), card_definition = .Dino_Ride})
	action := make_action(.Trigger, PLAYER_ENTITY)
	for id in victims[:count] {
		added := add_effect(&action, damage_effect(enemy_entity(id), GIGA_STOMP_DAMAGE))
		assert(added)
	}
	report := resolve_action(room, &action)
	// The dinosaur's own damage: the board shows its stomp, not a blow of his.
	for &event in report.events.events[:report.events.count] { if event.kind == .Damaged { event.card_definition = .Dino_Ride } }
	if report.accepted { append_event_log(room.recent_events, &report.events) }
}

// Whether the Giganotosauro's bump on `enemy_index` would kill it, whatever
// the foe's shield: then he does not strike, he walks onto it (giga_crush_step).
@(private)
giga_crushes :: proc(room: ^Room, enemy_index: int, critical: bool) -> bool {
	if !ride_is(room, .Giga) || room.player == nil { return false }
	enemy := room.enemies[enemy_index]
	damage := player_basic_attack_damage(room.player)
	if critical { damage = critical_bump_damage(damage) }
	damage = max(damage, giga_bite_damage(room, enemy))
	guard: i32
	if shield, shielded := status_for_entity(room, enemy_entity(enemy.id), .Shield); shielded { guard = shield.potency }
	return enemy.health+guard <= damage
}

// The Giganotosauro's step onto a foe he kills: the foe dies, he is on its cell
// (events in that order for the board: the step, the stomp that crushes, the
// foe's fall), the foes round his new cell are stomped as in any step, and it
// costs a step's time. A foe that somehow stands on is bitten instead.
@(private)
giga_crush_step :: proc(room: ^Room, enemy_index: int, aim: grid.Position, rule: Target_Rule, diagonal: bool) -> Action_Result {
	enemy := room.enemies[enemy_index]
	ref := enemy_entity(enemy.id)
	offset := grid.offset(aim, -room.player.position.x, -room.player.position.y)
	guard: i32
	if shield, shielded := status_for_entity(room, ref, .Shield); shielded { guard = shield.potency }
	blow := enemy.health+guard
	kill := make_action(.Attack, PLAYER_ENTITY, entity_target(ref), rule)
	added := add_effect(&kill, damage_effect(ref, blow))
	assert(added)
	killed := resolve_action(room, &kill)
	if !killed.accepted { return .Blocked }
	for &event in killed.events.events[:killed.events.count] { if event.kind == .Damaged { event.card_definition = .Dino_Ride } }
	moved: Action_Report
	query := query_entity_movement(room, PLAYER_ENTITY, aim)
	if movement_query_is_clear(&query) {
		step := make_action(.Move, PLAYER_ENTITY, cell_target(aim), .Walkable_Cell)
		added = add_effect(&step, move_effect(PLAYER_ENTITY, aim))
		assert(added)
		moved = resolve_action(room, &step)
	}
	if moved.accepted { append_event_log(room.recent_events, &moved.events) }
	record_event(room.recent_events, {kind = .Dino_Stomp, source = PLAYER_ENTITY, target = ref, from_position = aim, to_position = aim,
		amount = blow, duration = 0, card_definition = .Dino_Ride})
	append_event_log(room.recent_events, &killed.events)
	collect_loot_in_magnet_range(room)
	if diagonal && moved.accepted { room.player.tactical.facing = .North if offset.y < 0 else .South }
	ride_stomp(room)
	outcome := finish_player_combat_command(room, player_move_seconds(room))
	switch outcome {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved if moved.accepted else .Attacked
}

// The Giganotosauro's bump on `enemy`: a small foe falls at once, the rest take
// GIGA_BITE_DAMAGE. 0 when the bump is not his.
@(private)
giga_bite_damage :: proc(room: ^Room, enemy: Enemy) -> i32 {
	if !ride_is(room, .Giga) { return 0 }
	switch enemy.archetype {
	case .Chaser, .Archer, .Bomber:
		guard: i32
		if shield, shielded := status_for_entity(room, enemy_entity(enemy.id), .Shield); shielded { guard = shield.potency }
		return enemy.health+guard
	case .Brute, .Custodian, .Demolitionist, .Count:
	}
	return GIGA_BITE_DAMAGE
}

// The Dilophosaurus's venom (apply_damage_effect): the foe the player has just
// damaged, or the foe whose blow has just landed on him, takes 1 Poison.
@(private)
ride_after_damage :: proc(room: ^Room, source: Entity_Ref, effect: Effect, dealt: i32, report: ^Action_Report) {
	if !ride_is(room, .Dilo) || dealt <= 0 || effect.has_status_cause || report == nil { return }
	foe: Entity_Ref
	if effect.target.kind == .Enemy && source == PLAYER_ENTITY {
		foe = effect.target
	} else if effect.target.kind == .Player && source.kind == .Enemy {
		foe = source
	} else { return }
	if !entity_exists(room, foe) || foe.kind != .Enemy || enemy_is_out_of_play(room, foe.id) || !can_apply_status(room, foe, .Poison) { return }
	applied, _ := apply_status(room, foe, .Poison, 1, 0)
	if !applied { return }
	status, found := status_for_entity(room, foe, .Poison)
	if !found { return }
	report.statuses_applied += 1
	record_report_event(report, {kind = .Status_Applied, source = SYSTEM_ENTITY, target = foe, amount = status.potency, status = .Poison})
}

// The card played: its d4 rolls (shown as any dice card's roll, before the ride
// begins) and the face names the dinosaur.
@(private)
resolve_dinosaur_card :: proc(room: ^Room, instance: Card_Instance, target: Target, compiled: ^Action) -> (report: Action_Report) {
	if compiled == nil || instance.definition_id != .Dino_Ride || compiled.kind != .Card || compiled.source != PLAYER_ENTITY ||
	   compiled.target != target || compiled.effect_count != 1 || compiled.effects[0].kind != .Ride { return }
	action := compiled^
	staged_dice := room.player.dice
	roll, rolled := roll_card_dice(&staged_dice, instance)
	if !rolled { return }
	kind := dino_for_face(roll.total)
	action.effects[0].charges = i32(kind)+1
	tactical_critical_scale(room, &action)
	origin := room.player.position
	hit := resolve_action(room, &action)
	if !hit.accepted { return }
	room.player.dice = staged_dice
	record_report_event(&report, spell_dice_event(instance, origin, origin, PLAYER_ENTITY, roll))
	merge_spell_hit_report(&report, &hit)
	return
}
