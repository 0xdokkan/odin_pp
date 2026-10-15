package render

import "core:fmt"
import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import level "../level"

// The player's charges on the board (player_charges.odin): their chips and
// labels, the blow RIFLESSO turns back, the arrow, the die of the Dado del
// Destino and the hearts that wait for the blows to land.

// One blow's event, marked as the game marks it, RIFLESSO's answer too.
charges_test_blow :: proc(kind: game.Game_Event_Kind, source, target: game.Entity_Ref, from, to: grid.Position,
	ranged := false, reflected := false, amount := i32(3)) -> game.Game_Event {
	log: game.Event_Log
	game.record_event(&log, {kind = kind, source = source, target = target, amount = amount})
	game.mark_attack_events(&log, 0, source, target, from, to, nil, ranged, reflected)
	return log.events[0]
}

// One frame of the board: the clocks, the snapshot, the blows and the cards.
charges_test_frame :: proc(renderer: ^Renderer, room: ^game.Room, snapshot: ^Room_Presentation, dt: f32) {
	renderer.sprite_assets.elapsed += f64(dt)
	update_renderer_event_timeline(renderer, dt)
	snapshot^ = renderer_presentation_snapshot(renderer, room)
	observe_attack_cues(renderer)
}

charges_test_world_cue :: proc(renderer: ^Renderer, kind: Presentation_Cue_Kind, source: game.Entity_Ref) -> ^Presentation_Cue {
	if renderer.world_playback == nil { return nil }
	for &entry in renderer.world_playback.cues[:renderer.world_playback.count] {
		if entry.cue.kind == kind && entry.cue.event.source == source { return &entry.cue }
	}
	return nil
}

// One frame of the board as the game plays it (the lab's frame): the frame's
// timeline, where what follows a blow waits for it, then the clocks, the
// snapshot and the blows.
charges_test_live_frame :: proc(renderer: ^Renderer, room: ^game.Room, snapshot: ^Room_Presentation, dt: f32) {
	update_renderer_frame_timeline(renderer, dt)
	renderer.sprite_assets.elapsed += f64(dt)
	snapshot^ = renderer_presentation_snapshot(renderer, room)
	observe_attack_cues(renderer)
}

// A real tactical room on the ground tests' level, the player on its '@'
// (at 5, 3), no fog.
charges_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, enemies: []game.Enemy_Spawn) -> (room: game.Room) {
	made, created: bool
	player^, made = game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	room, created = game.create_room(data, player, {enemies = enemies})
	testing.expect(t, created)
	return
}

// Dice whose next d`sides` shows `face`, rolled as a loaded bump rolls it.
charges_test_dice :: proc(t: ^testing.T, face, sides: i32) -> game.Dice_State {
	for seed in u64(1)..<u64(100_000) {
		dice := game.make_dice_state(seed)
		staged := dice
		if roll, rolled := game.roll_dice_pool(&staged, 1, sides); rolled && roll.total == face { return dice }
	}
	testing.expectf(t, false, "no dice show a %d on a d%d", face, sides)
	return {}
}

// The player's bump on the foe at `cell`, with his dice set to show `face` on
// the Dado del Destino's die, its events shown on the board.
charges_test_bump :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, cell: grid.Position, face: i32 = 1,
	critical := false) -> bool {
	room.player.dice = charges_test_dice(t, face, game.player_fate_sides(room))
	game.clear_event_log(&room.recent_events)
	clear_event_timeline(&renderer.timeline)
	before := capture_room_presentation(room)
	index, found := game.enemy_index_at(room, cell)
	if !found || !game.player_bump(room, index, cell, .Adjacent_Opponent, critical) { return false }
	after := capture_room_presentation(room)
	return begin_renderer_event_timeline(renderer, before, &room.recent_events, &after)
}

// What the board says over the first cue of `kind` in the player's timeline,
// each word in brackets ("?" without such a cue).
charges_test_said :: proc(renderer: ^Renderer, kind: Presentation_Cue_Kind) -> string {
	for offset in 0..<renderer.timeline.count {
		cue, _ := presentation_cue_at(&renderer.timeline, offset)
		if cue.kind != kind { continue }
		badges, count := tactical_feedback_badges(renderer, cue)
		said := ""
		for badge in badges[:count] { said = fmt.tprintf("%s[%s]", said, badge.label) }
		return said
	}
	return "?"
}

@(test)
test_charge_chips_and_labels_are_italian_and_come_first :: proc(t: ^testing.T) {
	names := [4]string{"RIFLESSO", "FRECCE", "DESTINO", "LAMA"}
	shorts := [4]string{"RIF", "FRE", "DES", "LAM"}
	accents := [4]rl.Color{HUD_FROST, HUD_AMBER, HUD_SHADE, HUD_VENOM}
	for kind, index in ([4]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade}) {
		label, accent := tactical_status_label(kind, false)
		short, _ := tactical_status_label(kind, true)
		testing.expect_value(t, label, names[index])
		testing.expect_value(t, short, shorts[index])
		testing.expect(t, accent == accents[index])
	}
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Arrows, potency = 3}, false)), "FRECCE 3")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Deflect, potency = 1}, true)), "RIF 1")
	// What bites the player leads the HUD's chips, then the charges, then the
	// rest, each group as it was gained.
	statuses: game.Status_Set
	for status in ([5]game.Status{{kind = .Poison, potency = 2}, {kind = .Fate, potency = 3}, {kind = .Shield, potency = 2, remaining_pulses = 2},
		{kind = .Arrows, potency = 1}, {kind = .Burn, potency = 1}}) {
		statuses.items[statuses.count] = status
		statuses.count += 1
	}
	ordered := tactical_status_chip_order(&statuses)
	testing.expect_value(t, ordered.count, 5)
	kinds := [5]game.Status_Kind{.Poison, .Burn, .Fate, .Arrows, .Shield}
	for kind, index in kinds { testing.expect_value(t, ordered.items[index].kind, kind) }
	// A Bruciatura gained before three charges is still one of the three
	// chips that show, not the "+1" after them.
	loaded: game.Status_Set
	for kind in ([5]game.Status_Kind{.Burn, .Deflect, .Arrows, .Fate, .Venom_Blade}) {
		loaded.items[loaded.count] = {kind = kind, potency = 1}
		loaded.count += 1
	}
	ordered = tactical_status_chip_order(&loaded)
	shown := [3]game.Status_Kind{.Burn, .Deflect, .Arrows}
	for kind, index in shown { testing.expect_value(t, ordered.items[index].kind, kind) }
	// FERETRO's upgrade reads in Italian too.
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Coffin, lifetime = .Permanent}, true)), "FRECCE 3 -> 4")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .Fate_Dice, lifetime = .Permanent}, true)), "d4 -> d6")
}

@(test)
test_fate_outcome_labels_name_what_the_die_did :: proc(t: ^testing.T) {
	roll := game.Dice_Roll{faces = {16, 0, 0}, total = 16, sides = 20, count = 1}
	cases := [?]struct {outcome: game.Fate_Outcome, amount: i32, label: string}{
		{.Poison, 1, "VELENO 1"}, {.Burn, 2, "BRUCIATURA 2"}, {.Slow, 3, "RALLENTAMENTO 3"},
		{.Lifesteal, 2, "RUBA VITA +2"}, {.Critical, 0, "CRITICO"}, {.Lethal, 0, "LETALE"},
	}
	for row in cases {
		event := game.Game_Event{kind = .Fate_Rolled, source = game.PLAYER_ENTITY, dice_roll = roll, amount = row.amount,
			duration = i32(row.outcome)}
		label, _ := fate_outcome_label(event, false)
		testing.expect_value(t, string(label), row.label)
		with_die, _ := fate_outcome_label(event, true)
		testing.expect_value(t, string(with_die), fmt.tprintf("d20 16 / %s", row.label))
	}
	ladder := game.DICE_LADDER
	for sides, index in ladder { testing.expect_value(t, fate_die_glyph(sides), index) }
	w, h := fate_token_size(16)
	tw, th := living_heart_size("16")
	testing.expect(t, w == tw && h == th)
}

// The die's tag hangs beside the struck card's heart, never over it: out of
// the card's left side, and out past the heart where a narrow card's heart
// reaches beyond that side.
@(test)
test_fate_tag_keeps_clear_of_the_struck_cards_heart :: proc(t: ^testing.T) {
	base := rl.Vector2{400, 300}
	w, h := fate_token_size(16)
	near := f32(20)*0.9+8
	testing.expect_value(t, fate_tag_reach(base, 20, w, h, {}, false), near)
	testing.expect_value(t, fate_tag_reach(base, 20, w, h, {600, 100, 40, 20}, true), near)
	// The heart of a narrow card, centred over its head just above the tag.
	hw, hh := living_heart_size(living_heart_text(56, 60))
	heart := rl.Rectangle{base.x-f32(hw), base.y-10-f32(h)*2-f32(hh), f32(hw)*2, f32(hh)*2}
	tag := rl.Rectangle{base.x-near-f32(w), base.y-10-f32(h)*2, f32(w)*2, f32(h)*2}
	testing.expect(t, rl.CheckCollisionRecs(tag, heart))
	reach := fate_tag_reach(base, 20, w, h, heart, true)
	tag.x = base.x-reach-f32(w)
	testing.expect(t, reach > near && !rl.CheckCollisionRecs(tag, heart) && tag.x+tag.width <= heart.x-2)
	// A wide card's tag already clear of its heart stays where it was.
	testing.expect_value(t, fate_tag_reach(base, 80, w, h, heart, true), f32(80)*0.9+8)
	// Every frame of the narrow card's tag keeps clear too: the pop's three
	// screen pixels a tag pixel, not yet all the way out, and the hang's rise.
	popped := false
	for step in 0..=int(LIVING_FATE_SECONDS*400) {
		at, pixel, alpha := fate_tag_place(base, 20, w, h, f32(step)/400, heart, true)
		drawn := rl.Rectangle{at.x, at.y, f32(w)*pixel, f32(h)*pixel}
		if alpha <= 0 { continue }
		testing.expectf(t, !rl.CheckCollisionRecs(drawn, heart), "at %.4f s the tag %v covers the heart %v", f32(step)/400, drawn, heart)
		popped = popped || pixel == 3
	}
	testing.expect(t, popped)
	// Without a heart, it hangs at its reach out of the card's side, on whole
	// pixels.
	at, pixel, alpha := fate_tag_place(base, 20, w, h, 0.5, {}, false)
	testing.expect(t, pixel == 2 && alpha == 1 && at.x == math.round(base.x-near-f32(w)) && at.y == math.round(base.y-10-2-f32(h)*2))
}

// The blow RIFLESSO turns back on a shot: the archer's one bolt reaches the
// player, turns and flies home; its answer's cue finds that bolt and looses
// none of the player's; the archer's heart keeps its health until it lands.
@(test)
test_deflected_bolt_turns_round_and_is_the_only_bolt :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 9, max_health = 9}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	archer := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	room.enemies[0].health = 6
	after := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, charges_test_blow(.Attack_Deflected, archer, game.PLAYER_ENTITY, {6, 2}, {2, 2}, ranged = true))
	game.record_event(&events, charges_test_blow(.Damaged, game.PLAYER_ENTITY, archer, {2, 2}, {6, 2}, ranged = true, reflected = true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &after))
	renderer.sprite_assets.elapsed = 5
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	testing.expect_value(t, attack_test_used(renderer), 1)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect(t, fx.deflect && !fx.answered && fx.look == .Bolt && fx.kind == .Projectile && fx.outcome == .Absorbed)
	testing.expect(t, fx.attacker == archer && fx.victim == game.PLAYER_ENTITY)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Bolt], 1)
	answer := charges_test_world_cue(renderer, .Damage, game.PLAYER_ENTITY)
	testing.expect(t, answer != nil && !answer.started)
	turned, struck := false, false
	for _ in 0..<120 {
		charges_test_frame(renderer, &room, &snapshot, 1.0/60)
		testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Bolt], 1)
		testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Lantern], 0)
		if fx.used && fx.answered && !turned {
			turned = true
			testing.expect(t, fx.reflected && fx.attacker == game.PLAYER_ENTITY && fx.victim == archer)
			testing.expect_value(t, fx.aim, grid.Position{6, 2})
		}
		left, flying := attack_fx_landing_in(renderer, archer, renderer.sprite_assets.elapsed, game.PLAYER_ENTITY)
		actor, shown := presentation_actor_in_view(&snapshot, archer)
		testing.expect(t, shown)
		if !turned || flying { testing.expectf(t, actor.health == 9, "held while the bolt flies (%.3f s left)", left) }
		if turned && !flying && actor.health == 6 { struck = true }
		if answer = charges_test_world_cue(renderer, .Damage, game.PLAYER_ENTITY); answer != nil && answer.started {
			testing.expect(t, turned)
			testing.expect(t, attack_fx_of_cue(renderer, answer) == fx)
		}
	}
	testing.expect(t, turned && struck)
	// The player's card guards; the archer's shoots once; the answer is not
	// a swing of the player's.
	deflected := Presentation_Cue{kind = .Attack_Deflected, event = events.events[0], started = true}
	returned := Presentation_Cue{kind = .Damage, event = events.events[1], started = true}
	action, matched := living_cue_action(&deflected, game.PLAYER_ENTITY)
	testing.expect(t, matched && action == .Block)
	action, matched = living_cue_action(&deflected, archer)
	testing.expect(t, matched && action == .Attack)
	_, swung := living_cue_action(&returned, game.PLAYER_ENTITY)
	testing.expect(t, !swung)
	action, matched = living_cue_action(&returned, archer)
	testing.expect(t, matched && action == .Hurt)
}

// RIFLESSO on a swing: the brute's cleaver, then the player's riposte with his
// own lantern at the brute.
@(test)
test_deflected_swing_is_answered_by_the_players_riposte :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Brute, position = {3, 2}, health = 9, max_health = 9}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	brute := game.enemy_entity(1)
	before := capture_room_presentation(&room)
	room.enemies[0].health = 6
	after := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, charges_test_blow(.Attack_Deflected, brute, game.PLAYER_ENTITY, {3, 2}, {2, 2}))
	game.record_event(&events, charges_test_blow(.Damaged, game.PLAYER_ENTITY, brute, {2, 2}, {3, 2}, reflected = true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &after))
	renderer.sprite_assets.elapsed = 5
	snapshot = renderer_presentation_snapshot(renderer, &room)
	observe_attack_cues(renderer)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Cleaver], 1)
	riposted := false
	for _ in 0..<90 {
		charges_test_frame(renderer, &room, &snapshot, 1.0/60)
		if riposted || renderer.tactical.attack_fx.spawned[.Lantern] == 0 { continue }
		riposted = true
		riposte, found := attack_fx_find(renderer, game.PLAYER_ENTITY, .Swing)
		fx := attack_fx_by_id(renderer, riposte)
		testing.expect(t, found && fx != nil && fx.victim == brute && fx.aim == grid.Position{3, 2} && fx.damage == 3)
	}
	testing.expect(t, riposted)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Cleaver], 1)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Lantern], 1)
	actor, _ := presentation_actor_in_view(&snapshot, brute)
	testing.expect_value(t, actor.health, i32(6))
}

// The player's shot is a paper arrow, and its blow is done when it lands.
@(test)
test_the_players_shot_is_an_arrow :: proc(t: ^testing.T) {
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	testing.expect_value(t, attack_look(renderer, game.PLAYER_ENTITY, true), Attack_Look.Bolt)
	testing.expect_value(t, attack_look(renderer, game.PLAYER_ENTITY, false), Attack_Look.Lantern)
	shot := charges_test_blow(.Damaged, game.PLAYER_ENTITY, game.enemy_entity(1), {2, 2}, {6, 2}, ranged = true, amount = 1)
	snapshot.valid = true
	testing.expect(t, abs(world_blow_done(&snapshot, shot)-f32(attack_fx_done_seconds(.Pilgrim, .Bolt, shot))) < 1e-6)
	// It sounds as a shot, not as a swing.
	loosed, _ := lab_actor_sfx(.Pilgrim, .Attack, .Damage, 0, true)
	swung, _ := lab_actor_sfx(.Pilgrim, .Attack, .Damage, 0)
	testing.expect(t, loosed != swung)
}

// An enemy bolt on the player: his health shows as it lands, not as it is loosed.
@(test)
test_hearts_wait_for_the_blow_to_land :: proc(t: ^testing.T) {
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Archer, position = {6, 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	before := capture_room_presentation(&room)
	player.health = 7
	after := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, charges_test_blow(.Damaged, game.enemy_entity(1), game.PLAYER_ENTITY, {6, 2}, {2, 2}, ranged = true))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &after))
	renderer.sprite_assets.elapsed = 5
	// The frame its cue starts, before the bolt is on the board.
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.health, i32(10))
	observe_attack_cues(renderer)
	landed := false
	for _ in 0..<60 {
		charges_test_frame(renderer, &room, &snapshot, 1.0/60)
		_, flying := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, renderer.sprite_assets.elapsed, game.enemy_entity(1))
		if flying { testing.expect_value(t, snapshot.player.health, i32(10)) }
		else if snapshot.player.health == 7 { landed = true }
	}
	testing.expect(t, landed)
	// A flat board has no bolt to wait for: the started blow shows at once.
	renderer.tactical.scene_3d = false
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &after))
	snapshot = renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.player.health, i32(7))
}

// The Dado del Destino's cue: not cinematic, a die of the ladder rolled by
// the player, its charges shown spent at the blow, its paper die once.
@(test)
test_fate_cue_validates_its_die_and_shows_it_once :: proc(t: ^testing.T) {
	testing.expect_value(t, presentation_cue_kind({kind = .Fate_Rolled}), Presentation_Cue_Kind.Fate_Rolled)
	testing.expect_value(t, presentation_cue_kind({kind = .Attack_Deflected}), Presentation_Cue_Kind.Attack_Deflected)
	testing.expect(t, !presentation_cue_is_cinematic(.Fate_Rolled))
	testing.expect_value(t, presentation_cue_duration(.Fate_Rolled, {}), PRESENTATION_FATE_DURATION)
	player := game.Player{position = {2, 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Chaser, position = {2, 1}, health = 9, max_health = 9}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	foe := game.enemy_entity(1)
	player.statuses.items[0] = {kind = .Fate, potency = 3}
	player.statuses.items[1] = {kind = .Venom_Blade, potency = 2}
	player.statuses.count = 2
	before := capture_room_presentation(&room)
	player.statuses.items[0].potency = 2
	player.statuses.items[1].potency = 1
	room.enemies[0].health = 7
	after := capture_room_presentation(&room)
	roll := game.Dice_Roll{faces = {2, 0, 0}, total = 2, sides = 4, count = 1}
	fate := game.Game_Event{kind = .Fate_Rolled, source = game.PLAYER_ENTITY, target = foe, dice_roll = roll, amount = 2,
		duration = i32(game.Fate_Outcome.Burn), from_position = {2, 2}, to_position = {2, 1}, card_definition = .Fate_Dice}
	events: game.Event_Log
	game.record_event(&events, charges_test_blow(.Damaged, game.PLAYER_ENTITY, foe, {2, 2}, {2, 1}, amount = 2))
	game.record_event(&events, fate)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &events, &after))
	update_renderer_event_timeline(renderer, 0.001)
	// The blow's cue: the charges it spent show spent.
	index, found := game.status_index(&renderer.timeline.view.player.statuses, .Fate)
	testing.expect(t, found && renderer.timeline.view.player.statuses.items[index].potency == 2)
	index, found = game.status_index(&renderer.timeline.view.player.statuses, .Venom_Blade)
	testing.expect(t, found && renderer.timeline.view.player.statuses.items[index].potency == 1)
	update_renderer_event_timeline(renderer, PRESENTATION_DAMAGE_DURATION)
	cue, active := active_presentation_cue(&renderer.timeline)
	testing.expect(t, active && cue.kind == .Fate_Rolled && cue.started)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	renderer.sprite_assets.elapsed = 5
	renderer.tactical.snapshot^ = renderer_presentation_snapshot(renderer, &room)
	for _ in 0..<3 { update_fate_tokens(renderer, renderer.sprite_assets.elapsed); renderer.sprite_assets.elapsed += 1.0/60 }
	tokens := 0
	for token in renderer.tactical.living_state.fates.tokens { if token.used { tokens += 1; testing.expect(t, token.event == fate) } }
	testing.expect_value(t, tokens, 1)
	// Gone after its moment; never back for the same die.
	renderer.sprite_assets.elapsed += LIVING_FATE_SECONDS+0.1
	update_fate_tokens(renderer, renderer.sprite_assets.elapsed)
	for token in renderer.tactical.living_state.fates.tokens { testing.expect(t, !token.used) }
	// A die of no ladder, or not the player's, is refused.
	for bad in ([2]game.Game_Event{{kind = .Fate_Rolled, source = game.PLAYER_ENTITY, dice_roll = {faces = {2, 0, 0}, total = 2, sides = 7, count = 1}},
		{kind = .Fate_Rolled, source = foe, dice_roll = roll}}) {
		timeline: Presentation_Timeline
		bad_events := game.Event_Log{count = 1}
		bad_events.events[0] = bad
		testing.expect(t, begin_event_timeline(&timeline, before, &bad_events, &after))
		update_event_timeline(&timeline, 0.001)
		testing.expect(t, timeline.update_failures > 0)
	}
}

// Two loaded bumps in a row from the same cell on the same foe that roll the
// same face have the very same event: each is still a die of its own, with its
// paper die on the board and its bounce in the lab.
@(test)
test_every_loaded_bump_shows_its_die_even_on_the_same_face :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	cell := grid.Position{data.player_spawn.x, data.player_spawn.y-1}
	enemies := [?]game.Enemy_Spawn{{position = cell, health = 60, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Fate, game.FATE_DICE_CHARGES, 0)
	player.tactical.fate_sides = 4
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	renderer.tactical.mechanics_lab = true
	renderer.sprite_assets.elapsed = 5
	fates: [2]game.Game_Event
	for bump in 0..<2 {
		testing.expect(t, charges_test_bump(t, renderer, &room, cell, 2))
		for event in room.recent_events.events[:room.recent_events.count] { if event.kind == .Fate_Rolled { fates[bump] = event } }
		// A bump a second after the other, as soon as the first's second is
		// over: well inside the time a die and a blow are remembered.
		for _ in 0..<60 {
			charges_test_live_frame(renderer, &room, &snapshot, 1.0/60)
			update_living_tokens(renderer, renderer.sprite_assets.elapsed, renderer.sprite_assets.elapsed)
			update_fate_tokens(renderer, renderer.sprite_assets.elapsed)
			update_lab_sounds(renderer, &room, renderer.sprite_assets.elapsed)
		}
	}
	testing.expect(t, fates[0].kind == .Fate_Rolled && fates[0] == fates[1])
	// Two blows of the same 2 on the same foe: two damage tokens as well.
	wounds := 0
	for blow in renderer.tactical.living_state.blows {
		if blow.used && !blow.heal && blow.source == game.PLAYER_ENTITY && blow.entity == fates[0].target && blow.amount == 2 { wounds += 1 }
	}
	testing.expect_value(t, wounds, 2)
	dice := 0
	for seen in renderer.tactical.living_state.fates.seen {
		if seen.at <= 0 { continue }
		dice += 1
		testing.expect(t, seen.event == fates[0])
	}
	testing.expect_value(t, dice, 2)
	bounces := 0
	sounds := renderer.tactical.lab_sounds
	testing.expect(t, sounds != nil)
	if sounds != nil {
		for sound in sounds.queue[:sounds.count] { if sound.sfx == .Ui_Fate_Die { bounces += 1 } }
	}
	testing.expect_value(t, bounces, 2)
	// The same die again in the same command is the one already shown.
	fated: Living_Fates
	testing.expect(t, living_fate_spawn(&fated, fates[0], 10, 3) && !living_fate_spawn(&fated, fates[0], 10.5, 3))
	testing.expect(t, living_fate_spawn(&fated, fates[0], 11.5, 4))
	heard: Lab_Sounds
	testing.expect(t, !lab_sound_heard(&heard, .Fate_Rolled, fates[0], 10, 3) && lab_sound_heard(&heard, .Fate_Rolled, fates[0], 10.5, 3))
	testing.expect(t, !lab_sound_heard(&heard, .Fate_Rolled, fates[0], 11.5, 4))
}

// A critical the Dado del Destino's die makes is said once, by the die as it
// shows: the blow it doubles says nothing of it as it is swung. A critical of
// the tick still says so on its blow, whatever the die then does.
@(test)
test_a_critical_the_die_makes_is_said_by_the_die :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	cell := grid.Position{data.player_spawn.x, data.player_spawn.y-1}
	enemies := [?]game.Enemy_Spawn{{position = cell, health = 60, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	load :: proc(room: ^game.Room, sides: i32) {
		_, _ = game.apply_status(room, game.PLAYER_ENTITY, .Fate, game.FATE_DICE_CHARGES, 0)
		room.player.tactical.fate_sides = sides
	}
	// A d6's 5: the bump doubled, CRITICO by the die alone.
	load(&room, 6)
	testing.expect(t, charges_test_bump(t, renderer, &room, cell, 5))
	testing.expect_value(t, charges_test_said(renderer, .Damage), "")
	testing.expect_value(t, charges_test_said(renderer, .Fate_Rolled), "[CRITICO]")
	// The flat 3D board says the die too, and the blow's wound plainly.
	renderer.tactical.living = false
	testing.expect_value(t, charges_test_said(renderer, .Damage), "[-4]")
	testing.expect_value(t, charges_test_said(renderer, .Fate_Rolled), "[d6 5 / CRITICO]")
	renderer.tactical.living = true
	// The tick's critical, with no die loaded, and with a die that poisons.
	_, _ = game.remove_status(&room, game.PLAYER_ENTITY, .Fate)
	testing.expect(t, charges_test_bump(t, renderer, &room, cell, critical = true))
	testing.expect_value(t, charges_test_said(renderer, .Damage), "[CRITICO]")
	load(&room, 4)
	testing.expect(t, charges_test_bump(t, renderer, &room, cell, 1, critical = true))
	testing.expect_value(t, charges_test_said(renderer, .Damage), "[CRITICO]")
	testing.expect_value(t, charges_test_said(renderer, .Fate_Rolled), "[VELENO 1]")
}

// An arrow's status shows on its foe as the arrow strikes, never while it
// flies: what follows the shot in the player's timeline waits for it to land,
// while the world's time runs on.
@(test)
test_an_arrows_status_shows_as_it_lands :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	enemies := [?]game.Enemy_Spawn{{position = {data.player_spawn.x+4, data.player_spawn.y}, health = 20, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	foe := game.enemy_entity(room.enemies[0].id)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	renderer.sprite_assets.elapsed = 5
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.shoot_player_arrow(&room, foe), game.Action_Result.Attacked)
	after := capture_room_presentation(&room)
	kind: game.Status_Kind
	marked := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Status_Applied && event.target == foe { kind, marked = event.status, true }
	}
	testing.expect(t, marked)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	flew, waited, struck := false, false, false
	for _ in 0..<120 {
		charges_test_live_frame(renderer, &room, &snapshot, 1.0/60)
		testing.expectf(t, abs(renderer.frame_simulation_dt-1.0/60) < 1e-5, "the world ran %.4f s of a frame", renderer.frame_simulation_dt)
		_, flying := attack_fx_landing_in(renderer, foe, renderer.sprite_assets.elapsed, game.PLAYER_ENTITY)
		loosed := renderer.tactical.attack_fx.spawned[.Bolt] > 0
		flew = flew || flying
		actor, shown := presentation_actor_in_view(&snapshot, foe)
		_, has := game.status_index(&actor.statuses, kind)
		if flying || !loosed {
			testing.expectf(t, shown && !has, "the arrow's %v shows while it flies", kind)
			// The inspector of the foe under the mouse that shot says the same.
			health, _, statuses := tactical_inspected_state(renderer, &room.enemies[0])
			_, inspected := game.status_index(&statuses, kind)
			testing.expect(t, health == 20 && !inspected)
		}
		if cue, busy := active_presentation_cue(&renderer.timeline); busy && !cue.started && flying { waited = true }
		struck = struck || (shown && has)
	}
	testing.expect(t, flew && waited && struck)
	testing.expect(t, !renderer_timeline_is_busy(renderer))
}

// RIFLESSO's chip stays on the HUD, in its place among the player's statuses,
// until the blow it turns back reaches him.
@(test)
test_riflesso_shows_until_the_blow_reaches_him :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	spawn := data.player_spawn
	enemies := [?]game.Enemy_Spawn{{position = {spawn.x+4, spawn.y}, health = 20, attack = 3, archetype = .Archer}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Deflect, 1, 0)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	archer := &room.enemies[0]
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	renderer.sprite_assets.elapsed = 5
	before := capture_room_presentation(&room)
	intent := game.make_attack_intent(&room, archer.position, spawn, 3)
	pulse: game.Pulse_Report
	testing.expect(t, game.deflect_enemy_blow(&room, game.enemy_entity(archer.id), archer.position, &intent, true, &pulse))
	after := capture_room_presentation(&room)
	testing.expect_value(t, game.player_charges(&room, .Deflect), i32(0))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &pulse.events, &after))
	held, reached, turned := 0, false, false
	for _ in 0..<90 {
		charges_test_frame(renderer, &room, &snapshot, 1.0/60)
		for fx in renderer.tactical.attack_fx.items { turned = turned || (fx.used && fx.deflect && fx.answered) }
		statuses := &snapshot.player.statuses
		index, carried := game.status_index(statuses, .Deflect)
		if !turned {
			testing.expect(t, carried && index == 0 && statuses.items[0].potency == 1 && statuses.count == 2)
			held += 1
		} else if !carried {
			reached = true
			testing.expect(t, statuses.count == 1 && statuses.items[0].kind == .Arrows)
		}
	}
	testing.expect(t, held > 3 && reached)
}

// The charges the player's own blows spend show spent as those blows land: a
// loaded bump's LAMA as the lantern comes down, an arrow's FRECCE as it
// strikes. His timeline's view spends them as the blow starts.
@(test)
test_his_blows_spend_their_charges_as_they_land :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	spawn := data.player_spawn
	north := grid.Position{spawn.x, spawn.y-1}
	enemies := [?]game.Enemy_Spawn{{position = north, health = 20, attack = 1}, {position = {spawn.x+4, spawn.y}, health = 20, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Venom_Blade, 2, 0)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	far := game.enemy_entity(room.enemies[1].id)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	renderer.sprite_assets.elapsed = 5
	stacks :: proc(statuses: ^game.Status_Set, kind: game.Status_Kind) -> i32 {
		index, found := game.status_index(statuses, kind)
		return statuses.items[index].potency if found else 0
	}
	watch :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, snapshot: ^Room_Presentation, kind: game.Status_Kind, full, spent: i32) {
		held, landed := 0, false
		for _ in 0..<90 {
			charges_test_live_frame(renderer, room, snapshot, 1.0/60)
			if !renderer_timeline_is_busy(renderer) { break }
			testing.expect_value(t, stacks(&renderer.timeline.view.player.statuses, kind), spent)
			if attack_fx_foreground_pending(renderer) {
				testing.expect_value(t, stacks(&snapshot.player.statuses, kind), full)
				held += 1
			} else if stacks(&snapshot.player.statuses, kind) == spent { landed = true }
		}
		testing.expectf(t, held > 0 && landed, "%v held %d frames, landed %v", kind, held, landed)
	}
	testing.expect(t, charges_test_bump(t, renderer, &room, north))
	watch(t, renderer, &room, &snapshot, .Venom_Blade, 2, 1)
	game.clear_event_log(&room.recent_events)
	clear_event_timeline(&renderer.timeline)
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.shoot_player_arrow(&room, far), game.Action_Result.Attacked)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	watch(t, renderer, &room, &snapshot, .Arrows, 3, 2)
}

// A blow that fells its foe keeps the foe's heart as it was until it lands:
// the lantern's swing, an arrow's flight. Then the foe falls.
@(test)
test_a_felling_blow_keeps_the_heart_until_it_lands :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	spawn := data.player_spawn
	north := grid.Position{spawn.x, spawn.y-1}
	// The third keeps the fight going once the other two fall.
	enemies := [?]game.Enemy_Spawn{{position = north, health = 2, attack = 1}, {position = {spawn.x+4, spawn.y}, health = 1, attack = 1},
		{position = {1, 5}, health = 20, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	near, far := game.enemy_entity(room.enemies[0].id), game.enemy_entity(room.enemies[1].id)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	renderer.sprite_assets.elapsed = 5
	watch :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, snapshot: ^Room_Presentation, foe: game.Entity_Ref, health: i32) {
		held, fell := 0, false
		for _ in 0..<90 {
			charges_test_live_frame(renderer, room, snapshot, 1.0/60)
			actor, shown := presentation_actor_in_view(snapshot, foe)
			if attack_fx_foreground_pending(renderer) {
				testing.expect(t, shown && actor.health == health && living_heart_shown(renderer, actor^))
				held += 1
			} else if !shown || actor.health == 0 { fell = true }
		}
		testing.expectf(t, held > 0 && fell, "held %d frames, fell %v", held, fell)
	}
	testing.expect(t, charges_test_bump(t, renderer, &room, north))
	testing.expect(t, !game.entity_exists(&room, near))
	watch(t, renderer, &room, &snapshot, near, 2)
	game.clear_event_log(&room.recent_events)
	clear_event_timeline(&renderer.timeline)
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.shoot_player_arrow(&room, far), game.Action_Result.Attacked)
	after := capture_room_presentation(&room)
	testing.expect(t, !game.entity_exists(&room, far))
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	watch(t, renderer, &room, &snapshot, far, 1)
}

// RIFLESSO against a shielded attacker: the guard of its answer says PARATA
// over the attacker and RIFLESSO is said once over the player, by the wound,
// or by the guard when the Shield takes all of it. A bolt sent back into a
// Shield that takes all of it lands as a guard, not as a wound.
@(test)
test_riflesso_on_a_guard_says_it_once_and_keeps_parata :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	spawn := data.player_spawn
	Case :: struct {archetype: game.Enemy_Archetype, at: grid.Position, shield: i32, guard, wound: string, outcome: Attack_Outcome}
	cases := [?]Case{
		{.Brute, {spawn.x+1, spawn.y}, 2, "[PARATA 2]", "[RIFLESSO]", .Hit},
		{.Brute, {spawn.x+1, spawn.y}, 10, "[PARATA 5][RIFLESSO]", "?", .Hit},
		{.Archer, {spawn.x+4, spawn.y}, 2, "[PARATA 2]", "[RIFLESSO]", .Hit},
		{.Archer, {spawn.x+4, spawn.y}, 10, "[PARATA 5][RIFLESSO]", "?", .Absorbed},
	}
	said :: proc(renderer: ^Renderer, kind: Presentation_Cue_Kind) -> (text: string, owners: [2]game.Entity_Ref) {
		cue := charges_test_world_cue(renderer, kind, game.PLAYER_ENTITY)
		if cue == nil { return "?", {} }
		badges, count := tactical_feedback_badges(renderer, cue)
		for badge, index in badges[:count] {
			text = fmt.tprintf("%s[%s]", text, badge.label)
			owners[index] = badge.over
		}
		return
	}
	for row in cases {
		player: game.Player
		enemies := [?]game.Enemy_Spawn{{position = row.at, health = 30, attack = 5, archetype = row.archetype}}
		room := charges_test_room(t, &data, &player, enemies[:])
		defer game.destroy_room(&room)
		_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Deflect, 1, 0)
		attacker := game.enemy_entity(room.enemies[0].id)
		_, _ = game.apply_status(&room, attacker, .Shield, row.shield, 3)
		snapshot: Room_Presentation
		renderer := attack_test_renderer(&snapshot)
		defer attack_test_free(renderer)
		renderer.tactical.living_state = new(Living_State)
		renderer.sprite_assets.elapsed = 5
		before := capture_room_presentation(&room)
		ranged := row.archetype == .Archer
		intent := game.make_attack_intent(&room, row.at, spawn, 5)
		pulse: game.Pulse_Report
		testing.expect(t, game.deflect_enemy_blow(&room, attacker, row.at, &intent, ranged, &pulse))
		after := capture_room_presentation(&room)
		testing.expect(t, begin_renderer_world_timeline(renderer, before, &pulse.events, &after))
		guard, guard_over := said(renderer, .Damage_Absorbed)
		wound, wound_over := said(renderer, .Damage)
		testing.expect_value(t, guard, row.guard)
		testing.expect_value(t, wound, row.wound)
		// PARATA over the attacker, RIFLESSO over the player.
		testing.expect(t, guard_over[0] == attacker)
		if row.shield == 10 { testing.expect(t, guard_over[1] == game.PLAYER_ENTITY) }
		else { testing.expect(t, wound_over[0] == game.PLAYER_ENTITY) }
		if !ranged { continue }
		turned := false
		for _ in 0..<90 {
			charges_test_frame(renderer, &room, &snapshot, 1.0/60)
			for fx in renderer.tactical.attack_fx.items {
				if !fx.used || !fx.deflect || !fx.answered { continue }
				turned = true
				testing.expect_value(t, fx.outcome, row.outcome)
			}
		}
		testing.expect(t, turned)
	}
}

// DESTINO's chip names the die its loaded bumps will roll (DESTINO 3 d8): the
// die of the card that loaded them, shown with the charges as their cue
// shows them, never before.
@(test)
test_destino_chip_names_the_die_its_bumps_roll :: proc(t: ^testing.T) {
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Fate, potency = 3}, false, 8)), "DESTINO 3 d8")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Fate, potency = 2}, true, 20)), "DES 2 d20")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Fate, potency = 3}, false)), "DESTINO 3")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Arrows, potency = 3}, false, 8)), "FRECCE 3")
	data := ground_test_level(t)
	defer level.destroy(&data)
	player: game.Player
	enemies := [?]game.Enemy_Spawn{{position = {data.player_spawn.x+4, data.player_spawn.y}, health = 20, attack = 1}}
	room := charges_test_room(t, &data, &player, enemies[:])
	defer game.destroy_room(&room)
	// A Dado del Destino +2 in hand: a d8.
	deck := &room.player.deck
	id := deck.hand[0].id
	deck.hand[0].definition_id, deck.hand[0].upgrade_level = .Fate_Dice, 2
	for &owned in deck.owned[:deck.owned_count] { if owned.id == id { owned.definition_id, owned.upgrade_level = .Fate_Dice, 2 } }
	testing.expect(t, game.validate_deck_state(deck))
	deck.energy = deck.rules.max_energy
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	renderer.tactical.living_state = new(Living_State)
	before := capture_room_presentation(&room)
	testing.expect_value(t, before.fate_sides, i32(4))
	game.clear_event_log(&room.recent_events)
	testing.expect_value(t, game.play_card(&room, id, game.entity_target(game.PLAYER_ENTITY)).result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	testing.expect_value(t, after.fate_sides, i32(8))
	testing.expect(t, begin_renderer_event_timeline(renderer, before, &room.recent_events, &after))
	charged, early := false, false
	for _ in 0..<240 {
		charges_test_live_frame(renderer, &room, &snapshot, 1.0/60)
		status := renderer_status_view(renderer, &room)
		index, loaded := game.status_index(&status.statuses, .Fate)
		if !loaded {
			early = early || status.fate_sides != 4
			continue
		}
		charged = true
		testing.expect_value(t, status.fate_sides, i32(8))
		testing.expect_value(t, string(tactical_status_chip_text(status.statuses.items[index], false, status.fate_sides)), "DESTINO 3 d8")
	}
	testing.expect(t, charged && !early)
	testing.expect(t, !renderer_timeline_is_busy(renderer))
}
