package game

import "core:math"

// FIRST PERSON BRAWLER's punches (docs/piano-prima-persona.md, sezione 5.4 and
// Fase 2): the left button a jab, the right a cross, with Shift the left and
// the right hook. One at a time, on the rules' own clock (first_person_fists.odin):
// a punch lands after its `land` seconds on the first foe's card along the view
// within its reach (the AK's hitscan from the body, level and shortened), a hook
// also on one up to FISTS_HOOK_DEGREES to its own side; the next may start after
// its `recover` seconds. A press during a punch waits when it comes in the last
// FISTS_PUNCH_BUFFER seconds of it (a fighting game's input buffer), so a 1-2
// comes out clean; an earlier one is dropped, as one during a dash is. While a
// punch is out he moves at half his speed. A punch, like an AK's shot, is no
// action of his: no window time, no Veleno; a miss costs nothing more than its
// own time. Counted in the view's shots (thrown) and hits (landed).

First_Person_Punch :: enum u8 {None, Jab, Cross, Left_Hook, Right_Hook}

First_Person_Punch_Rules :: struct {
	// Seconds to land, seconds before the next may start.
	land, recover: f32,
	// Cells from the eye; the side a hook also reaches (-1 the view's left, +1 its right).
	reach: f32,
	side: i32,
	damage: i32,
}

// The user's "più forti" damage (Fase 2, question 14); the plan's times.
@(rodata)
FISTS_PUNCHES := [First_Person_Punch]First_Person_Punch_Rules{
	.None = {},
	.Jab = {land = 0.12, recover = 0.30, reach = 1.4, damage = 3},
	.Cross = {land = 0.16, recover = 0.40, reach = 1.4, damage = 4},
	.Left_Hook = {land = 0.20, recover = 0.50, reach = 1.1, side = -1, damage = 6},
	.Right_Hook = {land = 0.20, recover = 0.50, reach = 1.1, side = 1, damage = 6},
}
FISTS_PUNCH_BUFFER :: f32(0.15)
FISTS_HOOK_DEGREES :: f32(25)
FISTS_HOOK_RAYS :: 5
FISTS_PUNCH_SPEED_FACTOR :: f32(0.5)
// The fists' wounds carry this in Game_Event.visual_group, as the AK's carry theirs.
FISTS_VISUAL_GROUP :: u32(0x4B_5001)

// Which punch the buttons ask: the left a jab, the right a cross, with Shift the hooks.
first_person_punch_for :: proc(left, right, shift: bool) -> First_Person_Punch {
	if left { return .Left_Hook if shift else .Jab }
	if right { return .Right_Hook if shift else .Cross }
	return .None
}

// A press of `punch`: thrown now when no punch is out, kept for the end of the one
// out when it comes in its last FISTS_PUNCH_BUFFER seconds, else dropped; never
// during a dash.
@(private)
fists_press :: proc(room: ^Room, punch: First_Person_Punch) {
	f := &room.first_person.fists
	if punch == .None || f.dash_left > 0 || lift_player_riding(room) { return }
	if f.punch == .None {
		fists_throw(room, punch)
		return
	}
	if FISTS_PUNCHES[f.punch].recover-f.punch_clock <= FISTS_PUNCH_BUFFER+1e-5 { f.queued = punch }
}

@(private = "file")
fists_throw :: proc(room: ^Room, punch: First_Person_Punch) {
	f := &room.first_person.fists
	f.punch, f.punch_clock, f.punch_landed = punch, 0, false
	room.first_person.shots += 1
}

// One FISTS_STEP of the punch out: it lands, it ends, the one kept starts. Whether
// it struck a foe.
@(private)
fists_punch_step :: proc(room: ^Room, aim: First_Person_Aim, h: f32) -> (struck: bool) {
	f := &room.first_person.fists
	if f.punch == .None { return }
	f.punch_clock += h
	rules := FISTS_PUNCHES[f.punch]
	if !f.punch_landed && f.punch_clock >= rules.land-1e-5 {
		f.punch_landed = true
		struck = fists_land(room, f.punch, aim)
		if room.phase != .Combat || !first_person_fists_active(room) { return }
	}
	if f.punch_clock >= rules.recover-1e-5 {
		over := max(f32(0), f.punch_clock-rules.recover)
		f.punch, f.punch_landed = .None, false
		if f.queued != .None {
			fists_throw(room, f.queued)
			f.punch_clock, f.queued = over, .None
		}
	}
	return
}

// The punch lands: the foe it reaches takes its damage from him, as any blow of
// his (a Shield first, its reactions, a kill's loot); the right punch on its lit
// mark, the crosshair over it, three times its damage, and a hook's staggers it
// (first_person_marks.odin).
@(private = "file")
fists_land :: proc(room: ^Room, punch: First_Person_Punch, aim: First_Person_Aim) -> bool {
	target, found := first_person_punch_target(room, punch, aim)
	if !found { return false }
	critical := first_person_punch_critical(room, punch, target.id, aim)
	damage := FISTS_PUNCHES[punch].damage*(FISTS_CRITICAL_FACTOR if critical else 1)
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
	action.visual_group = FISTS_VISUAL_GROUP
	if !add_effect(&action, damage_effect(target, damage)) { return false }
	if critical && FISTS_PUNCHES[punch].side != 0 {
		if !add_effect(&action, apply_status_effect(target, .Stagger, 1, FISTS_STAGGER_BEATS)) { return false }
	}
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	if critical { fists_mark_struck(room, target.id) }
	room.first_person.hits += 1
	append_event_log(room.recent_events, &report.events)
	collect_loot_in_magnet_range(room)
	return true
}

// The foe `punch` reaches along `aim` from the body: the AK's hitscan from the
// body's centre, level, met within the punch's reach; a hook tries again turned
// toward its side, up to FISTS_HOOK_DEGREES, and takes the first it meets.
first_person_punch_target :: proc(room: ^Room, punch: First_Person_Punch, aim: First_Person_Aim) -> (target: Entity_Ref, found: bool) {
	if !first_person_fists_active(room) || punch == .None { return }
	rules := FISTS_PUNCHES[punch]
	look := aim
	look.framed, look.eye, look.pitch = true, room.first_person.fists.body, 0
	rays := FISTS_HOOK_RAYS if rules.side != 0 else 0
	for ray in 0..=rays {
		look.yaw = aim.yaw+f32(rules.side)*f32(ray)*(FISTS_HOOK_DEGREES*math.PI/180)/f32(max(rays, 1))
		shot := first_person_trace(room, room.player.position, look)
		if shot.hit != .Foe { continue }
		dx, dz := shot.point.x-shot.origin.x, shot.point.z-shot.origin.z
		if math.sqrt(dx*dx+dz*dz) <= rules.reach { return shot.target, true }
	}
	return
}

// The fists' own wounds (and what else their action recorded).
event_is_first_person_punch :: proc(event: Game_Event) -> bool {
	return event.visual_group == FISTS_VISUAL_GROUP
}
