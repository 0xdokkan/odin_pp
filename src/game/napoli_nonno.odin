package game

import "core:math"

// BENVENUTI A NAPOLI's face 4 (napoli.odin; docs/piano-napoli.md, Fase 4, the
// user's choices of 2026-11-03): the player turned into the grandpa for
// NAPOLI_NONNO_SECONDS of the world's, seen from behind his back as the club is
// (render/first_person_club.odin). A weapon of the view: its seconds, its ban on
// cards, its save are the view's.
//
// - He walks free on the board with the fists' body (first_person_fists.odin:
//   its bytes are this one's first), slower (NAPOLI_NONNO_SPEED), with neither
//   jump nor dash; no dodge and no defence prompt, as with the fists.
// - The club comes out of his pocket by itself (NAPOLI_NONNO_DRAW_SECONDS: no
//   blow before); then the left button brings it down as the club's view does
//   (first_person_club.odin: the same blow, damage and wearing stagger), on the
//   nearest foe within NAPOLI_NONNO_REACH of his body's edge and NAPOLI_NONNO_CONE of
//   the view's look, else on the cell in front. He stands still for the blow.
// - His own health (the card's number, NAPOLI_NONNO_HEALTH +5 an upgrade): the
//   foes' blows and everything else that would hurt the player hurt him; at none
//   the view ends at once and the player is back, his health as it was.
// - Q, once: he cures half his most health, the player half of his.
// - E, once: the purse's gold (NAPOLI_PURSE_GOLD +2 an upgrade).
// - The minute over (or his health), the player is back where the grandpa
//   stands: the cell under the body.

NAPOLI_NONNO_SPEED :: f32(4)
NAPOLI_NONNO_DRAW_SECONDS :: f32(1.2)
NAPOLI_NONNO_REACH :: f32(1.2)
NAPOLI_NONNO_CONE :: f32(math.PI/4)

First_Person_Nonno :: struct {
	// The fists' body, first: room.first_person.fists is this (the view's arms
	// share their bytes), so the body's rules move it.
	body: First_Person_Fists,
	club: First_Person_Club,
	// His health and its most; the gold of E.
	health, most, gold: i32,
	// Seconds until the club is out of his pocket.
	draw_left: f32,
	// Q and E used.
	healed, paid: bool,
	// What Q cured, him and the player (the board, the lab and the tests).
	cured_self, cured_player: i32,
}

// What the controller asks of the grandpa this frame: the wished way (as the
// fists'), the left button pressed along the view's yaw, Q and E pressed.
First_Person_Nonno_Input :: struct {
	wish: [2]f32,
	yaw: f32,
	swing, heal, pay: bool,
}

napoli_nonno_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Nonno
}

// The grandpa taken up where the player stands: the body at his cell's centre.
napoli_nonno_begin :: proc(room: ^Room, health, gold, damage: i32) {
	if room == nil || room.player == nil { return }
	p := room.player.position
	room.first_person.nonno = {body = {body = {f32(p.x)+0.5, f32(p.y)+0.5}, feet = f32(cell_height(room, p))},
		club = {damage = max(damage, 1)}, health = max(health, 1), most = max(health, 1), gold = max(gold, 0),
		draw_left = NAPOLI_NONNO_DRAW_SECONDS}
}

// The world's seconds (tactical_first_person_tick): the pocket's, the club's.
@(private)
napoli_nonno_tick :: proc(room: ^Room, seconds: f32) {
	n := &room.first_person.nonno
	n.draw_left = max(f32(0), n.draw_left-seconds)
	first_person_club_tick(&n.club, seconds)
}

// The view over: no blow left raised; the player stays where the body is.
@(private)
napoli_nonno_leave :: proc(room: ^Room) {
	n := &room.first_person.nonno
	n.club.blow, n.club.pending = {}, 0
	n.body.velocity = {}
}

// The cure of Q: half the grandpa's most health, half the player's.
napoli_nonno_cures :: proc(most, player_most: i32) -> (self, player: i32) {
	return (max(most, 0)+1)/2, (max(player_most, 0)+1)/2
}

// The way of the grandpa's blow along `yaw`: toward the nearest foe within his
// reach and cone (always a cell next to his), else the cell in front.
napoli_nonno_aim :: proc(room: ^Room, yaw: f32) -> [2]i8 {
	n := &room.first_person.nonno
	look := [2]f32{math.cos(yaw), math.sin(yaw)}
	p := room.player.position
	best, way := max(f32), club_way(yaw)
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) || enemy.position.layer != p.layer { continue }
		dx, dy := enemy.position.x-p.x, enemy.position.y-p.y
		if abs(dx) > 1 || abs(dy) > 1 || (dx == 0 && dy == 0) { continue }
		d := [2]f32{f32(enemy.position.x)+0.5, f32(enemy.position.y)+0.5}-n.body.body
		dist := math.sqrt(d.x*d.x+d.y*d.y)
		// Within his reach from the edge of his body: a foe a corner away too.
		if dist-FISTS_RADIUS > NAPOLI_NONNO_REACH || dist < 1e-4 || (d.x*look.x+d.y*look.y)/dist < math.cos(NAPOLI_NONNO_CONE) { continue }
		if dist < best { best, way = dist, {i8(dx), i8(dy)} }
	}
	return way
}

// What a wound of the player's takes while he is the grandpa: from the
// grandpa's health, never from the player's.
@(private)
napoli_nonno_wound :: proc(room: ^Room, damage: i32) -> i32 {
	n := &room.first_person.nonno
	taken := min(damage, n.health)
	n.health -= taken
	return taken
}

// After a wound: at no health the grandpa is gone at once (Napoli_Nonno_Left),
// the view over, the player back where he stood.
@(private)
napoli_nonno_after_wound :: proc(room: ^Room, report: ^Action_Report) {
	if !napoli_nonno_active(room) || room.first_person.nonno.health > 0 { return }
	at := room.player.position
	fp := &room.first_person
	fp.active, fp.remaining = false, 0
	napoli_nonno_leave(room)
	record_report_event(report, {kind = .Napoli_Nonno_Left, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
		card_definition = .Napoli})
}

// The grandpa this frame (dt seconds): Q, E, a blow begun, the body's glide (none
// while a blow lasts), the blow run on the world's seconds. Their events are the
// room's recent ones.
napoli_nonno_move :: proc(room: ^Room, input: First_Person_Nonno_Input, dt: f32) -> (result: Action_Result) {
	if !napoli_nonno_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	n := &room.first_person.nonno
	at := room.player.position
	acted := false
	if input.heal && !n.healed {
		n.healed = true
		self, player := napoli_nonno_cures(n.most, room.player.stats.max_health)
		before := n.health
		n.health = min(n.most, n.health+self)
		n.cured_self = n.health-before
		record_event(room.recent_events, {kind = .Napoli_Nonno_Cured, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at,
			to_position = at, amount = n.cured_self, card_definition = .Napoli})
		before = room.player.health
		room.player.health = min(room.player.stats.max_health, before+player)
		n.cured_player = room.player.health-before
		record_event(room.recent_events, {kind = .Healed, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
			amount = n.cured_player, card_definition = .Napoli})
		acted = true
	}
	if input.pay && !n.paid {
		n.paid = true
		room.player.gold += n.gold
		record_event(room.recent_events, {kind = .Gold_Gained, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = at, to_position = at,
			amount = n.gold, card_definition = .Napoli})
		acted = true
	}
	if input.swing && !n.club.blow.active && n.draw_left <= 0 && !room.tactical_pulse.pending && room.qte.kind == .None {
		club_begin_blow(room, &n.club, napoli_nonno_aim(room, input.yaw), input.yaw)
		// He plants his feet for the blow (the user's choice).
		n.body.velocity = {}
		acted = true
	}
	wish := input.wish if !n.club.blow.active else {}
	f := &room.first_person.fists
	f.carry += clamp(dt, 0, FISTS_MAX_FRAME)
	stepped := false
	for f.carry >= FISTS_STEP {
		f.carry -= FISTS_STEP
		entered, ended := fists_step(room, wish)
		stepped = stepped || entered
		if ended { break }
	}
	if napoli_nonno_active(room) && club_run(room, &n.club) { acted = true }
	if !stepped && !acted { return .None }
	switch finish_player_combat_command(room, 0, false) {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}
