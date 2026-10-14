package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import grid "../grid"
import level "../level"

// The board's blows (attack_fx.odin): one prop per blow, landing on the hit
// drawing, every cell swept, bolts that hold the struck card until they land.

attack_test_renderer :: proc(snapshot: ^Room_Presentation) -> ^Renderer {
	renderer := new(Renderer)
	renderer.tactical.enabled, renderer.tactical.scene_3d, renderer.tactical.living, renderer.tactical.no_fog = true, true, true, true
	renderer.tactical.snapshot = snapshot
	renderer.tactical.camera = {position = {4, 9, 12}, target = {4, 0, 3}, up = {0, 1, 0}, fovy = 45}
	renderer.canvas_width, renderer.canvas_height = 1280, 720
	return renderer
}

attack_test_free :: proc(renderer: ^Renderer) {
	destroy_renderer_world_playback(renderer)
	destroy_lab_sounds(renderer)
	if renderer.tactical.living_state != nil {
		living_tokens_free(renderer.tactical.living_state)
		free(renderer.tactical.living_state)
	}
	free(renderer)
}

// One blow's event, marked as the game marks it.
attack_test_blow :: proc(kind: game.Game_Event_Kind, source, target: game.Entity_Ref, from, to: grid.Position,
	cells: []grid.Position = nil, ranged := false, amount := i32(2)) -> game.Game_Event {
	log: game.Event_Log
	game.record_event(&log, {kind = kind, source = source, target = target, amount = amount})
	game.mark_attack_events(&log, 0, source, target, from, to, cells, ranged)
	return log.events[0]
}

attack_test_used :: proc(renderer: ^Renderer) -> (count: int) {
	for fx in renderer.tactical.attack_fx.items { if fx.used { count += 1 } }
	return
}

@(test)
test_attack_fx_one_prop_per_blow_landing_on_the_hit_drawing :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Brute, position = {3, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	brute := game.enemy_entity(1)
	cleave := [3]grid.Position{{2, 1}, {2, 2}, {2, 3}}
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damage_Absorbed, brute, game.PLAYER_ENTITY, {3, 2}, {2, 2}, cleave[:]))
	game.record_event(&events, attack_test_blow(.Damaged, brute, game.PLAYER_ENTITY, {3, 2}, {2, 2}, cleave[:]))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
	for _ in 0..<3 {
		snapshot = renderer_presentation_snapshot(renderer, &room)
		observe_attack_cues(renderer)
		renderer.sprite_assets.elapsed += 1.0/60
	}
	testing.expect_value(t, attack_test_used(renderer), 1)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect_value(t, fx.look, Attack_Look.Cleaver)
	testing.expect_value(t, fx.kind, Attack_Fx_Kind.Swing)
	// A guard, then a wound: the blow got through.
	testing.expect_value(t, fx.outcome, Attack_Outcome.Hit)
	testing.expect(t, abs(fx.contact-fx.start-gfx.living_hit_seconds(&gfx.LIVING_SHEETS[.Brute].clips[.Attack])) < 1e-9)
	testing.expect(t, abs(attack_fx_impact_seconds(.Brute)-0.125) < 1e-9)
	testing.expect_value(t, fx.from, grid.Position{3, 2})
	cells, swept := attack_swept_cells(fx.aim, fx.swept)
	testing.expect_value(t, swept, 3)
	for cell in cleave { testing.expect(t, cell == cells[0] || cell == cells[1] || cell == cells[2]) }
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Cleaver], 1)
	// A blow never holds the player's hand: the world's cues end, the prop goes on.
	testing.expect(t, !renderer_blocks_player_input(renderer))
	update_renderer_event_timeline(renderer, 1)
	testing.expect(t, !renderer_world_is_busy(renderer))
	testing.expect(t, renderer.tactical.attack_fx.items[0].used)
	// Its end on its own clock frees the slot; a fresh board forgets it at once.
	renderer.sprite_assets.elapsed = attack_fx_end(fx)+0.01
	observe_attack_cues(renderer)
	testing.expect_value(t, attack_test_used(renderer), 0)
	_, _ = play_attack_swing(renderer, brute, game.PLAYER_ENTITY, .Cleaver, {2, 2})
	forget_attack_fx(renderer)
	testing.expect_value(t, attack_test_used(renderer), 0)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Cleaver], 2)
}

// The swing passes every swept cell once, from the one farthest from the
// camera to the nearest, and the aim at the contact.
@(test)
test_attack_swing_sweeps_every_cell_and_the_aim_at_contact :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Brute, position = {3, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot := capture_room_presentation(&room)
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	mask := u16(1)<<1|u16(1)<<4|u16(1)<<7
	id, ok := play_attack_swing(renderer, game.enemy_entity(1), game.PLAYER_ENTITY, .Cleaver, {2, 2}, mask)
	testing.expect(t, ok)
	fx := attack_fx_by_id(renderer, id)
	plan, planned := attack_swing_plan(renderer, fx)
	testing.expect(t, planned && plan.count == 3)
	begin := attack_swing_begin(fx)
	testing.expect(t, abs(begin-(fx.contact-ATTACK_SWING_LEAD)) < 1e-9)
	testing.expect(t, abs(attack_swing_yaw(fx.contact, begin, fx.contact, plan.follow, plan.start, plan.aim, plan.finish)-plan.aim) < 1e-5)
	times: [3]f64
	first, last := 0, 0
	for index in 0..<3 {
		times[index] = attack_swing_passes(begin, fx.contact, plan.follow, plan.start, plan.aim, plan.finish, plan.yaws[index])
		testing.expect(t, times[index] >= begin && times[index] <= fx.contact+plan.follow)
		if times[index] < times[first] { first = index }
		if times[index] > times[last] { last = index }
		// The aim itself is passed as the blow lands.
		if plan.cells[index] == fx.aim { testing.expect(t, abs(times[index]-fx.contact) < (fx.contact+plan.follow-begin)/48) }
	}
	testing.expect(t, times[0] != times[1] && times[1] != times[2] && times[0] != times[2])
	camera := renderer.tactical.camera.position
	testing.expect(t, rl.Vector3Distance(attack_cell_center(plan.cells[first]), camera) > rl.Vector3Distance(attack_cell_center(plan.cells[last]), camera))
	// Its tip is over the aim's cell when the blow lands, low after it.
	_, tip := attack_swing_pose(fx, &plan, fx.contact)
	testing.expect(t, int(math.floor(tip.x)) == 2 && int(math.floor(tip.z)) == 2)
	_, raised := attack_swing_pose(fx, &plan, fx.start)
	_, lowered := attack_swing_pose(fx, &plan, fx.contact+plan.follow)
	testing.expect(t, raised.y > tip.y && tip.y > lowered.y)
	// The pike lunges at its cell instead.
	pike, _ := play_attack_swing(renderer, game.PLAYER_ENTITY, game.enemy_entity(1), .Storm_Pike, {3, 2})
	thrust := attack_fx_by_id(renderer, pike)
	testing.expect_value(t, thrust.kind, Attack_Fx_Kind.Thrust)
	reach, _ := attack_swing_plan(renderer, thrust)
	_, back := attack_thrust_pose(thrust, &reach, thrust.start)
	_, lunged := attack_thrust_pose(thrust, &reach, thrust.contact)
	testing.expect(t, lunged.x > back.x && int(math.floor(lunged.x)) == 3)
}

// A bolt flies; the struck card's hurt starts so that its strike lands with
// the bolt, the loop beneath going on until then, and its token pops then.
@(test)
test_attack_bolt_holds_the_struck_card_until_it_lands :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	archer := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damaged, archer, game.PLAYER_ENTITY, {6, 2}, {2, 2}, nil, true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	renderer.sprite_assets.elapsed = 5
	observe_attack_cues(renderer)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect_value(t, fx.kind, Attack_Fx_Kind.Projectile)
	testing.expect_value(t, fx.look, Attack_Look.Bolt)
	// The archer looses on its shot's drawing, the first.
	testing.expect_value(t, fx.contact, fx.start)
	left, pending := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 5)
	testing.expect(t, pending && left > 0.2 && left < 0.35)
	// Only the archer's own blows count for what he struck.
	_, by_archer := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 5, archer)
	_, by_trap := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 5, game.SYSTEM_ENTITY)
	testing.expect(t, by_archer && !by_trap)
	living_observe(renderer, renderer.tactical.living_state, nil, snapshot.player, .Pilgrim, 5)
	hurt := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	testing.expect(t, hurt != nil && hurt.action == .Hurt)
	if hurt != nil {
		testing.expect(t, abs(hurt.started-(5+left-LIVING_REACT_STRIKE)) < 1e-6)
		drawing, _ := living_drawing(hurt, 5)
		testing.expect_value(t, drawing, hurt.base)
		drawing, _ = living_drawing(hurt, hurt.started+0.01)
		testing.expect_value(t, drawing, gfx.Living_Action.Hurt)
	}
	// The archer shoots at once, one drawing for the blow.
	living_observe(renderer, renderer.tactical.living_state, nil, snapshot.enemies[0], .Archer, 5)
	shooter := living_find(renderer, archer, .Archer)
	testing.expect(t, shooter != nil && shooter.action == .Attack && shooter.started == 5 && shooter.blow == fx.id)
	// The token waits for the bolt.
	update_living_tokens(renderer, 5, 5)
	popped := false
	for token in renderer.tactical.living_state.tokens {
		if token.used && token.entity == game.PLAYER_ENTITY { popped = abs(token.born-(5+left)) < 1e-6 }
	}
	testing.expect(t, popped)
	// Its flight leaves the shooter's card and ends on the struck one.
	start, _ := attack_flight_point(fx.origin, fx.target, fx.arc, 0)
	end, _ := attack_flight_point(fx.origin, fx.target, fx.arc, 1)
	testing.expect(t, start.x > 5.5 && end.x < 3.2)
	_, rising := attack_flight_point(fx.origin, fx.target, fx.arc, 0.25)
	_, falling := attack_flight_point(fx.origin, fx.target, fx.arc, 0.75)
	testing.expect(t, rising.y > 0 && falling.y < 0)
}

// What does not come from the bolt never waits for it: a bite of poison on
// the struck card hurts it at once.
@(test)
test_attack_bolt_never_holds_another_blow :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	before := capture_room_presentation(&room)
	shot: game.Event_Log
	game.record_event(&shot, attack_test_blow(.Attack_Missed, game.enemy_entity(1), game.PLAYER_ENTITY, {6, 2}, {2, 2}, nil, true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &shot, &before))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	renderer.sprite_assets.elapsed = 5
	observe_attack_cues(renderer)
	testing.expect(t, renderer.tactical.attack_fx.items[0].outcome == .Missed)
	bite: game.Event_Log
	game.record_event(&bite, {kind = .Damaged, source = game.SYSTEM_ENTITY, target = game.PLAYER_ENTITY, amount = 1,
		has_status_cause = true, status_cause = .Poison})
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &bite, &before))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	living_observe(renderer, renderer.tactical.living_state, nil, snapshot.player, .Pilgrim, 5)
	hurt := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	testing.expect(t, hurt != nil && hurt.action == .Hurt && hurt.started == 5)
	// A miss into the floor lands a little beyond the aimed cell.
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect(t, fx.target.y < 0.1 && fx.target.x < 2.5)
}

// Phase 2's Deflect: the bolt turns back to its shooter, who is then the one
// waiting for it.
@(test)
test_attack_reflected_bolt_flies_back_to_its_shooter :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot := capture_room_presentation(&room)
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	archer := game.enemy_entity(1)
	id, landing, ok := play_attack_projectile(renderer, archer, game.PLAYER_ENTITY, .Bolt, {2, 2}, .Hit, 0)
	testing.expect(t, ok && landing > 0)
	found, has := attack_fx_find(renderer, archer, .Projectile)
	testing.expect(t, has && found == id)
	renderer.sprite_assets.elapsed += landing*0.5
	fx := attack_fx_by_id(renderer, id)
	midway, _ := attack_flight_point(fx.origin, fx.target, fx.arc, 0.5)
	back, reflected := reflect_attack_projectile(renderer, id)
	testing.expect(t, reflected && back > 0)
	testing.expect(t, fx.attacker == game.PLAYER_ENTITY && fx.victim == archer && fx.reflected)
	testing.expect(t, rl.Vector3Distance(fx.origin, midway) < 0.05)
	_, player_waits := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, renderer.sprite_assets.elapsed)
	archer_left, archer_waits := attack_fx_landing_in(renderer, archer, renderer.sprite_assets.elapsed, game.PLAYER_ENTITY)
	testing.expect(t, !player_waits && archer_waits && abs(archer_left-back) < 1e-6)
	end, _ := attack_flight_point(fx.origin, fx.target, fx.arc, 1)
	testing.expect(t, end.x > 5.5)
	// A swing is no bolt to send back; and the defender can swing at him.
	_, swung := play_attack_swing(renderer, game.PLAYER_ENTITY, archer, .Lantern, {6, 2})
	swing, _ := attack_fx_find(renderer, game.PLAYER_ENTITY, .Swing)
	_, bounced := reflect_attack_projectile(renderer, swing)
	testing.expect(t, swung && !bounced)
}

// The player swings his own weapon: the one in his hand as the board shows
// him, even once the blow has used its last charge.
@(test)
test_attack_player_look_follows_his_weapon_as_shown :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	player.equipment.weapon = {id = .Storm_Pike, uses_remaining = 1}
	enemies := [?]game.Enemy{{id = 1, archetype = .Chaser, position = {3, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	before := capture_room_presentation(&room)
	player.equipment.weapon = {}
	room.enemies[0].health = 2
	after := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damaged, game.PLAYER_ENTITY, game.enemy_entity(1), {2, 2}, {3, 2}))
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &events, &after))
	// The frame's timeline step starts the cue.
	update_renderer_event_timeline(renderer, 0.001)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.weapon, game.Weapon_Id.Storm_Pike)
	observe_attack_cues(renderer)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect(t, fx.used && fx.look == .Storm_Pike && fx.kind == .Thrust)
	testing.expect(t, abs(fx.contact-fx.start-attack_fx_impact_seconds(.Pilgrim)) < 1e-9)
	update_renderer_event_timeline(renderer, 2)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, attack_look(renderer, game.PLAYER_ENTITY, false), Attack_Look.Lantern)
	// Every enemy strikes with its own.
	looks := [game.Enemy_Archetype]Attack_Look{.Chaser = .Claws, .Archer = .Bolt, .Brute = .Cleaver, .Bomber = .Bomb,
		.Custodian = .Crozier, .Demolitionist = .Staff, .Count = .None}
	for archetype in game.Enemy_Archetype {
		if archetype == .Count { continue }
		snapshot.enemies[0].archetype = archetype
		testing.expectf(t, attack_look(renderer, game.enemy_entity(1), archetype == .Archer || archetype == .Bomber) == looks[archetype], "%v", archetype)
	}
	snapshot.enemies[0].archetype = .Demolitionist
	testing.expect_value(t, attack_look(renderer, game.enemy_entity(1), true), Attack_Look.Ember)
}

// A charge strikes once it has arrived (on a living board, once its card has
// slid all the way); on a living board a push gives ground as the blow lands
// and the brute's own poison bites once he is done striking. Unmarked cues
// keep starting at once: thirty enemies are not thirty turns.
@(test)
test_world_charge_and_push_wait_for_their_blow :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Brute, position = {5, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	brute := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, {kind = .Moved, source = brute, target = brute, from_position = {5, 2}, to_position = {3, 2}})
	game.record_event(&events, attack_test_blow(.Damaged, brute, game.PLAYER_ENTITY, {3, 2}, {2, 2}))
	game.record_event(&events, {kind = .Moved, source = brute, target = game.PLAYER_ENTITY, from_position = {2, 2}, to_position = {1, 2}})
	game.record_event(&events, {kind = .Damaged, source = game.SYSTEM_ENTITY, target = brute, amount = 1, has_status_cause = true, status_cause = .Poison})
	stomp := &gfx.LIVING_SHEETS[.Brute].clips[.Move_Side]
	slid := (f32(stomp.travel_start)+f32(stomp.travel_ms))/1000
	testing.expect(t, slid > PRESENTATION_ENEMY_MOVE_DURATION)
	for living in ([2]bool{false, true}) {
		renderer := new(Renderer)
		renderer.tactical.living = living
		testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
		world := renderer.world_playback
		arrival := slid if living else PRESENTATION_ENEMY_MOVE_DURATION
		testing.expect(t, world.cues[0].cue.started && !world.cues[1].cue.started && !world.cues[2].cue.started)
		testing.expect(t, abs(world.cues[1].delay-arrival) < 1e-5)
		contact := f32(attack_fx_impact_seconds(.Brute)) if living else 0
		testing.expect(t, abs(world.cues[2].delay-(arrival+contact)) < 1e-5)
		// What the batch shows after the blow (the bite of his poison) waits
		// too: for his blow to be over, where the board shows it.
		done := f32(attack_fx_done_seconds(.Brute, .Cleaver, world.cues[1].cue.event)) if living else 0
		testing.expect(t, !living || done > contact)
		testing.expect(t, abs(world.cues[3].delay-(arrival+done)) < 1e-5)
		testing.expect(t, world.cues[0].cue.batch == world.cues[3].cue.batch && world.cues[0].cue.batch == renderer.cue_batches)
		plain: game.Event_Log
		game.record_event(&plain, {kind = .Damaged, source = brute, target = game.PLAYER_ENTITY, amount = 1})
		clear_renderer_world_playback(renderer)
		testing.expect(t, begin_renderer_world_timeline(renderer, before, &plain, &before))
		testing.expect(t, world.cues[0].cue.started && world.cues[0].cue.batch == renderer.cue_batches)
		destroy_renderer_world_playback(renderer)
		free(renderer)
	}
}

// A poisoned ghoul strikes and the bite of its own poison kills it in the
// same beat, as the game resolves it: its bite, its fall and its gold wait
// until it is done striking. It stands at full opacity and shows its blow
// first, its claws play on to their end after it has left the board, and its
// gold lies on the floor only once it falls.
@(test)
test_world_attacker_killed_by_its_own_bite_strikes_first :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
	data, parsed, _ := level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 30, attack = 2})
	testing.expect(t, made && game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	spawns := [?]game.Enemy_Spawn{{position = {5, 4}, health = 2, attack = 1, archetype = .Chaser},
		{position = {1, 1}, health = 20, attack = 1, archetype = .Chaser}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	ghoul := game.enemy_entity(room.enemies[0].id)
	_, _ = game.apply_status(&room, ghoul, .Poison, 3, 0)
	room.enemies[0].intent = game.make_attack_intent(&room, room.enemies[0].position, room.player.position, 1)
	before := capture_room_presentation(&room)
	pulse: game.Pulse_Report
	game.resolve_enemy_intents(&room, &pulse, ghoul.id)
	_, alive := game.enemy_index_by_id(&room, ghoul.id)
	testing.expect(t, !alive && len(room.loot) == 1)
	after := capture_room_presentation(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &pulse.events, &after))
	world := renderer.world_playback
	testing.expect(t, world.count >= 4 && game.event_is_attack(world.cues[0].cue.event) && world.cues[0].cue.started)
	done := f32(attack_fx_done_seconds(.Ghoul, .Claws, world.cues[0].cue.event))
	testing.expect(t, done > f32(attack_fx_impact_seconds(.Ghoul))+f32(ATTACK_RAKE_SECOND))
	for entry in world.cues[1:world.count] {
		testing.expectf(t, !entry.cue.started && abs(entry.delay-done) < 1e-5, "%v waits %.3f", entry.cue.kind, entry.delay)
	}
	start := f64(5)
	attacked, fell := false, false
	for frame in 0..=60 {
		now := start+f64(frame)/60
		age := f32(frame)/60
		renderer.sprite_assets.elapsed = now
		if frame > 0 { update_renderer_event_timeline(renderer, 1.0/60) }
		snapshot = renderer_presentation_snapshot(renderer, &room)
		observe_attack_cues(renderer)
		actor, shown := presentation_actor_in_view(&snapshot, ghoul)
		if age < done-0.01 {
			testing.expectf(t, shown && actor.opacity == 1, "frame %d: the ghoul still strikes", frame)
			testing.expectf(t, snapshot.loot_count == 1 && !snapshot.loot[0].visible, "frame %d: no gold yet", frame)
		}
		if age > done+0.01 { testing.expectf(t, snapshot.loot_count == 1 && snapshot.loot[0].visible, "frame %d: its gold", frame) }
		if shown { living_observe(renderer, renderer.tactical.living_state, nil, actor^, .Ghoul, now) }
		card := living_find(renderer, ghoul, .Ghoul)
		testing.expect(t, card != nil)
		if card == nil { return }
		if frame == 0 { testing.expect_value(t, card.action, gfx.Living_Action.Attack) }
		if card.action == .Attack { testing.expect(t, !fell); attacked = true }
		if card.action == .Death { fell = true }
		// Its claws are drawn to their end, even once its body has left the board.
		fx := &renderer.tactical.attack_fx.items[0]
		if fx.used {
			_, planned := attack_swing_plan(renderer, fx)
			testing.expectf(t, planned, "frame %d: its claws lost their ghoul", frame)
		}
	}
	testing.expect(t, attacked && fell)
	_, still := presentation_actor_in_view(&snapshot, ghoul)
	testing.expect(t, !still && attack_test_used(renderer) == 0)
}

// An archer's bolt on a player wearing Thorns: their answer waits for the
// bolt to land, so the archer is seen to shoot, then to flinch, and its
// token comes after the bolt. A flat board, with no bolts, answers at once.
@(test)
test_world_thorns_answer_waits_for_the_blow_it_answers :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	archer := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damaged, archer, game.PLAYER_ENTITY, {6, 2}, {2, 2}, nil, true, 3))
	// The Thorns' answer, unmarked as the game records it.
	game.record_event(&events, {kind = .Damaged, source = game.PLAYER_ENTITY, target = archer, amount = 1})
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
	answer := renderer.world_playback.cues[1]
	testing.expect(t, !answer.cue.started)
	renderer.sprite_assets.elapsed = 5
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	landing, flying := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 5, archer)
	testing.expect(t, flying && abs(f64(answer.delay)-landing) < 0.01)
	flinched := false
	for frame in 0..=40 {
		now := 5+f64(frame)/60
		renderer.sprite_assets.elapsed = now
		if frame > 0 { update_renderer_event_timeline(renderer, 1.0/60) }
		snapshot = renderer_presentation_snapshot(renderer, &room)
		observe_attack_cues(renderer)
		living_observe(renderer, renderer.tactical.living_state, nil, snapshot.enemies[0], .Archer, now)
		update_living_tokens(renderer, now, now)
		shooter := living_find(renderer, archer, .Archer)
		testing.expect(t, shooter != nil)
		if shooter == nil { return }
		if now-5 < landing-0.01 { testing.expectf(t, shooter.action == .Attack, "frame %d: %v before its bolt lands", frame, shooter.action) }
		if shooter.action == .Hurt || shooter.action == .Hurt_Back { flinched = true }
		for token in renderer.tactical.living_state.tokens {
			if token.used && token.entity == archer { testing.expect(t, token.born >= 5+landing-0.01) }
		}
	}
	testing.expect(t, flinched)
	flat := new(Renderer)
	defer { destroy_renderer_world_playback(flat); free(flat) }
	testing.expect(t, begin_renderer_world_timeline(flat, before, &events, &before))
	testing.expect(t, flat.world_playback.cues[1].cue.started)
}

// The impact's star is centred on the struck point (its sheet's grip is its
// centre), whatever its swell and turn.
@(test)
test_attack_impact_star_is_centred_on_the_struck_point :: proc(t: ^testing.T) {
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	sheet := gfx.ATTACK_PROPS[.Impact]
	testing.expect(t, sheet.grip == [2]f32{f32(sheet.rect.z)*0.5, f32(sheet.rect.w)*0.5})
	camera := renderer.tactical.camera
	view := rl.Vector3Normalize(camera.target-camera.position)
	at := rl.Vector3{3.5, 0.62, 2.5}
	for age in ([3]f64{0.01, 0.12, 0.25}) {
		grip, tip, texel, opacity := attack_impact_star(renderer, at, age, 3)
		u, v := attack_prop_axes(tip-grip, view, {sheet.tip.x-sheet.grip.x, sheet.tip.y-sheet.grip.y}, texel)
		centre := grip+u*(f32(sheet.rect.z)*0.5-sheet.grip.x)+v*(f32(sheet.rect.w)*0.5-sheet.grip.y)
		testing.expectf(t, rl.Vector3Distance(centre, at) < 1e-5 && opacity > 0, "at %.2f s: %v", age, centre)
	}
}

// A blow on an object lands on the side of its box toward the camera, never
// inside it where the box would hide it: an ember's flight, a swing's star.
@(test)
test_attack_impact_on_an_object_lands_before_its_box :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Demolitionist, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot := capture_room_presentation(&room)
	barrel := game.object_entity(7)
	snapshot.objects[0] = {entity = barrel, kind = .Barrel, position = {4, 3}, health = 1, max_health = 1, opacity = 1, visible = true}
	snapshot.object_count = 1
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	box := voxel_object_bounds(.Barrel, {4, 3})
	camera := renderer.tactical.camera.position
	for bolt in ([2]bool{false, true}) {
		point, ok := attack_struck_point(renderer, barrel, bolt)
		testing.expect(t, ok && point.y > box.min.y && point.y < box.max.y)
		inside := point.x > box.min.x && point.x < box.max.x && point.z > box.min.z && point.z < box.max.z
		testing.expect(t, !inside)
		// Nothing of the box stands between it and the eye.
		hit := rl.GetRayCollisionBox({position = camera, direction = rl.Vector3Normalize(point-camera)}, box)
		testing.expect(t, !hit.hit || hit.distance >= rl.Vector3Distance(point, camera)-1e-4)
	}
	id, _, _ := play_attack_projectile(renderer, game.enemy_entity(1), barrel, .Ember, {4, 3}, .Hit)
	fx := attack_fx_by_id(renderer, id)
	point, _ := attack_struck_point(renderer, barrel, true)
	testing.expect(t, fx != nil && rl.Vector3Distance(fx.target, point) < 1e-5)
	// A card is still struck at its middle.
	feet, height, _ := attack_card(renderer, game.PLAYER_ENTITY)
	middle, _ := attack_struck_point(renderer, game.PLAYER_ENTITY)
	testing.expect(t, rl.Vector3Distance(middle, feet+{0, height*0.5, 0}) < 1e-5)
}

// A critical bump through a Shield in the player's lane, as the game records
// it: its guard, the Shield it breaks and its wound start together, one blow
// that got through and is critical, whose star takes the wound's place.
@(test)
test_attack_bump_through_a_shield_is_one_critical_blow :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Chaser, position = {3, 3}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	ghoul := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	log: game.Event_Log
	game.record_event(&log, {kind = .Damage_Absorbed, source = game.PLAYER_ENTITY, target = ghoul, amount = 1, status = .Shield})
	game.record_event(&log, {kind = .Status_Removed, source = game.PLAYER_ENTITY, target = ghoul, status = .Shield})
	game.record_event(&log, {kind = .Damaged, source = game.PLAYER_ENTITY, target = ghoul, amount = 2})
	game.record_event(&log, {kind = .Damaged, source = game.SYSTEM_ENTITY, target = game.PLAYER_ENTITY, amount = 1,
		has_status_cause = true, status_cause = .Poison})
	game.mark_attack_events(&log, 0, game.PLAYER_ENTITY, ghoul, {2, 2}, {3, 3}, {}, false)
	game.mark_critical_events(&log)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &log, &before))
	// The bite after it is no part of the blow.
	testing.expect_value(t, presentation_group_size(&renderer.timeline), 3)
	update_renderer_event_timeline(renderer, 0.001)
	renderer.sprite_assets.elapsed = 5
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	testing.expect_value(t, attack_test_used(renderer), 1)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect(t, fx.outcome == .Hit && fx.critical)
	testing.expect_value(t, attack_impact_tint(fx), TACTICAL_FEEDBACK_CRITICAL)
	living_observe(renderer, renderer.tactical.living_state, nil, snapshot.enemies[0], .Ghoul, 5)
	struck := living_find(renderer, ghoul, .Ghoul)
	testing.expect(t, struck != nil && (struck.action == .Hurt || struck.action == .Hurt_Back))
	renderer.tactical.attack_props.loaded = true
	for offset in 0..<3 {
		cue, found := renderer_active_cue_at(renderer, offset)
		testing.expect(t, found && attack_fx_shows(renderer, cue) == (cue.kind != .Status_Removed))
	}
	renderer.tactical.attack_props.loaded = false
}

// A blow never struck (an aim broken, as the game records it: an unmarked
// miss) shows no attack, no prop and no dodge. The archmage's ember at a
// barrel that has moved flies and plants all the same, and nobody dodges it.
@(test)
test_attack_fx_unstruck_miss_shows_nothing_and_a_missed_barrel_shot_flies :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5},
		{id = 2, archetype = .Demolitionist, position = {6, 4}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	archer, mage, barrel := game.enemy_entity(1), game.enemy_entity(2), game.object_entity(9)
	before := capture_room_presentation(&room)
	for struck in ([2]bool{false, true}) {
		snapshot: Room_Presentation
		renderer := attack_test_renderer(&snapshot)
		defer attack_test_free(renderer)
		renderer.tactical.living_state = new(Living_State)
		events: game.Event_Log
		if struck {
			game.record_event(&events, attack_test_blow(.Attack_Missed, mage, barrel, {6, 4}, {4, 3}, nil, true))
		} else {
			game.record_event(&events, {kind = .Attack_Missed, source = archer, target = game.PLAYER_ENTITY, from_position = {6, 3}, to_position = {2, 2}})
		}
		testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
		snapshot = renderer_presentation_snapshot(renderer, &room)
		renderer.sprite_assets.elapsed = 5
		observe_attack_cues(renderer)
		living_observe(renderer, renderer.tactical.living_state, nil, snapshot.enemies[0], .Archer, 5)
		living_observe(renderer, renderer.tactical.living_state, nil, snapshot.enemies[1], .Archmage, 5)
		living_observe(renderer, renderer.tactical.living_state, nil, snapshot.player, .Pilgrim, 5)
		shooter := living_find(renderer, archer, .Archer)
		caster := living_find(renderer, mage, .Archmage)
		pilgrim := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
		testing.expect(t, shooter != nil && caster != nil && pilgrim != nil)
		if shooter == nil || caster == nil || pilgrim == nil { return }
		testing.expect_value(t, shooter.action, gfx.Living_Action.Idle)
		// Nothing was thrown at the player: he has nothing to dodge.
		testing.expect_value(t, pilgrim.action, gfx.Living_Action.Idle)
		if !struck {
			testing.expect_value(t, attack_test_used(renderer), 0)
			continue
		}
		testing.expect_value(t, attack_test_used(renderer), 1)
		fx := &renderer.tactical.attack_fx.items[0]
		testing.expect(t, fx.attacker == mage && fx.victim == barrel && fx.look == .Ember && fx.outcome == .Missed)
		// Into the floor of the cell the barrel stood on.
		testing.expect(t, fx.target.y < 0.1 && attack_board_cell(fx.target) == grid.Position{4, 3})
		testing.expect(t, caster.action == .Attack && caster.blow == fx.id)
	}
}

// The board of a real fight: the game's own marks make the props, the
// player's lantern on a bump and the brute's cleaver over its three cells.
@(test)
test_attack_fx_from_the_game_bump_and_cleave :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
	data, parsed, _ := level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 30, attack = 2})
	testing.expect(t, made && game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	spawns := [?]game.Enemy_Spawn{{position = {3, 4}, health = 20, attack = 1, archetype = .Chaser},
		{position = {5, 4}, health = 20, attack = 2, archetype = .Brute}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.try_move_player(&room, .West), game.Action_Result.Attacked)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	update_renderer_event_timeline(renderer, 0.001)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	bump, bumped := attack_fx_find(renderer, game.PLAYER_ENTITY, .Swing)
	testing.expect(t, bumped)
	if fx := attack_fx_by_id(renderer, bump); fx != nil {
		testing.expect(t, fx.look == .Lantern && fx.aim == grid.Position{3, 4} && fx.from == grid.Position{4, 4} && fx.swept == u16(1)<<4)
	}
	update_renderer_event_timeline(renderer, 2)
	brute := room.enemies[1]
	testing.expect_value(t, brute.archetype, game.Enemy_Archetype.Brute)
	pulse: game.Pulse_Report
	game.resolve_enemy_intents(&room, &pulse, brute.id)
	testing.expect(t, begin_renderer_world_timeline(renderer, after, &pulse.events, &after))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	cleave, cleaved := attack_fx_find(renderer, game.enemy_entity(brute.id), .Swing)
	testing.expect(t, cleaved)
	if fx := attack_fx_by_id(renderer, cleave); fx != nil {
		_, cells := attack_swept_cells(fx.aim, fx.swept)
		testing.expect(t, fx.look == .Cleaver && fx.aim == grid.Position{4, 4} && cells == 3)
	}
}

// The world's blows hold with the world while the player is in his shadow;
// his own go on.
@(test)
test_attack_fx_world_blows_hold_in_the_shadow :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot := capture_room_presentation(&room)
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	archer := game.enemy_entity(1)
	renderer.sprite_assets.elapsed = 2
	_, landing, _ := play_attack_projectile(renderer, archer, game.PLAYER_ENTITY, .Bolt, {2, 2}, .Hit, 0)
	_, _ = play_attack_swing(renderer, game.PLAYER_ENTITY, archer, .Lantern, {6, 2})
	renderer.tactical.shadow.active, renderer.tactical.shadow.frozen_at = true, 2
	renderer.sprite_assets.elapsed = 3
	left, pending := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 3)
	testing.expect(t, pending && abs(left-landing) < 1e-9)
	_, swinging := attack_fx_landing_in(renderer, archer, 3)
	testing.expect(t, !swinging)
	// Long after both would be over, the bolt is still there, held.
	renderer.sprite_assets.elapsed = 9
	observe_attack_cues(renderer)
	_, still := attack_fx_find(renderer, archer, .Projectile)
	_, gone := attack_fx_find(renderer, game.PLAYER_ENTITY, .Swing)
	testing.expect(t, still && !gone)
}

// Without its props (no GL, or a failed load) the board keeps the old cut,
// shield and tint for every blow; with them, the blow's own impact replaces them.
@(test)
test_attack_fx_props_replace_the_generic_hit :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Chaser, position = {3, 2}, health = 5, max_health = 5},
		{id = 2, archetype = .Chaser, position = {5, 4}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damaged, game.enemy_entity(1), game.PLAYER_ENTITY, {3, 2}, {2, 2}))
	// On another ghoul: what befalls the striker waits for its blow.
	game.record_event(&events, {kind = .Damaged, source = game.SYSTEM_ENTITY, target = game.enemy_entity(2), amount = 1})
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	// Halfway into the cue, where its flash is strongest.
	update_renderer_event_timeline(renderer, 0.12)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	blow, _ := renderer_active_cue_at(renderer, 0)
	plain, _ := renderer_active_cue_at(renderer, 1)
	testing.expect(t, !attack_fx_shows(renderer, blow) && !attack_fx_shows(renderer, plain))
	struck := tactical_feedback_pose(renderer, .Player, snapshot.player.position)
	testing.expect(t, struck.tint != rl.WHITE)
	renderer.tactical.attack_props.loaded = true
	testing.expect(t, attack_fx_shows(renderer, blow) && !attack_fx_shows(renderer, plain))
	testing.expect_value(t, tactical_feedback_pose(renderer, .Player, snapshot.player.position).tint, rl.WHITE)
	// The unmarked blow keeps its old look.
	testing.expect(t, tactical_feedback_pose(renderer, .Chaser, snapshot.enemies[1].position).tint != rl.WHITE)
	renderer.tactical.attack_props.loaded = false
}

// The lab hears a blow when it lands: the miss when the bolt reaches the
// floor, the dodge when the card starts it.
@(test)
test_attack_fx_lab_sounds_wait_for_the_landing :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.mechanics_lab = true
	renderer.tactical.living_state = new(Living_State)
	before := capture_room_presentation(&room)
	shot: game.Event_Log
	game.record_event(&shot, attack_test_blow(.Attack_Missed, game.enemy_entity(1), game.PLAYER_ENTITY, {6, 2}, {2, 2}, nil, true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &shot, &before))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	renderer.sprite_assets.elapsed = 5
	observe_attack_cues(renderer)
	left, pending := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, 5)
	testing.expect(t, pending)
	living_observe(renderer, renderer.tactical.living_state, &room, snapshot.player, .Pilgrim, 5)
	update_lab_sounds(renderer, &room, 5)
	s := renderer.tactical.lab_sounds
	miss, dodge := -1.0, -1.0
	for sound in s.queue[:s.count] {
		if sound.sfx == .Ui_Miss { miss = sound.at }
		if sound.sfx == .Pilgrim_Dodge { dodge = sound.at }
	}
	testing.expect(t, abs(miss-(5+left)) < 1e-6)
	testing.expect(t, abs(dodge-(5+left-LIVING_REACT_STRIKE)) < 1e-6)
	// Nothing plays before its moment.
	play_lab_sounds(renderer, nil, 0)
	testing.expect(t, s.played[.Ui_Miss] == 0 && s.played[.Pilgrim_Dodge] == 0)
	renderer.sprite_assets.elapsed = 5+left
	play_lab_sounds(renderer, nil, 0)
	testing.expect(t, s.played[.Ui_Miss] == 1 && s.played[.Pilgrim_Dodge] == 1)
}

// A prop faces the viewer as a cut-out: full length on screen whichever way
// it points (straight at the eye too), never mirrored, its cut edge down and
// to the right on screen.
@(test)
test_attack_props_face_the_viewer_unmirrored_and_cut_down_right :: proc(t: ^testing.T) {
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	camera := renderer.tactical.camera
	view := rl.Vector3Normalize(camera.target-camera.position)
	at := rl.Vector3{4, 0.6, 3}
	sheet := gfx.ATTACK_PROPS[.Bolt]
	axis := [2]f32{sheet.tip.x-sheet.grip.x, sheet.tip.y-sheet.grip.y}
	longs := [?]rl.Vector3{{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, 1, 0}, {0.3, -1, 0.2}, -view, view, {1, 1, 1}}
	for long in longs {
		u, v := attack_prop_axes(long, view, axis, 0.02)
		testing.expect(t, abs(rl.Vector3Length(u)-0.02) < 1e-5 && abs(rl.Vector3Length(v)-0.02) < 1e-5)
		testing.expect(t, abs(rl.Vector3DotProduct(u, v)) < 1e-7)
		// In the plane facing the eye: nothing of it runs along the view.
		testing.expect(t, abs(rl.Vector3DotProduct(u, view)) < 1e-6 && abs(rl.Vector3DotProduct(v, view)) < 1e-6)
		o := tactical_project(renderer, {at.x, at.z}, at.y)
		pu := tactical_project(renderer, {at.x+u.x, at.z+u.z}, at.y+u.y)
		pv := tactical_project(renderer, {at.x+v.x, at.z+v.z}, at.y+v.y)
		su, sv := [2]f32{pu.x-o.x, pu.y-o.y}, [2]f32{pv.x-o.x, pv.y-o.y}
		testing.expectf(t, su.x*sv.y-su.y*sv.x > 0, "%v mirrors the print", long)
		edge := attack_edge_dir(renderer, at, u, v)
		screen := [2]f32{edge.x*su.x+edge.y*sv.x, edge.x*su.y+edge.y*sv.y}
		testing.expectf(t, screen.x > 0 && screen.y > 0 && abs(screen.x-screen.y) < 0.05*(screen.x+screen.y), "%v: edge %v", long, screen)
	}
}

// The props' table points inside its atlas, and every look has a prop.
@(test)
test_attack_props_table_matches_its_atlas :: proc(t: ^testing.T) {
	be32 :: proc(b: []u8) -> int { return int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3]) }
	for png in ([2][]u8{gfx.ATTACK_PROPS_PNG, gfx.ATTACK_PROPS_PAPER_PNG}) {
		testing.expect(t, len(png) > 24 && string(png[12:16]) == "IHDR")
		width, height := be32(png[16:20]), be32(png[20:24])
		m := i32(gfx.ATTACK_PROP_MARGIN)
		for prop in gfx.Attack_Prop {
			sheet := gfx.ATTACK_PROPS[prop]
			testing.expectf(t, sheet.rect.x >= m && sheet.rect.y >= m && int(sheet.rect.x+sheet.rect.z+m) <= width &&
				int(sheet.rect.y+sheet.rect.w+m) <= height, "%v leaves its atlas", prop)
			for point in ([2][2]f32{sheet.grip, sheet.tip}) {
				testing.expectf(t, point.x >= 0 && point.y >= 0 && point.x <= f32(sheet.rect.z) && point.y <= f32(sheet.rect.w), "%v: %v", prop, point)
			}
		}
	}
	for look in Attack_Look {
		if look == .None { continue }
		testing.expect(t, attack_look_prop(look, 0) != .Impact)
	}
	testing.expect(t, attack_look_prop(.Ember, 0) != attack_look_prop(.Ember, 1.0/16))
}
