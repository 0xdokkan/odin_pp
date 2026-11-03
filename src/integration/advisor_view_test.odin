package integration
import run_session "../run"

import "core:log"
import "core:testing"
import "core:time"
import advisor "../advisor"
import game "../game"
import level "../level"
import render "../render"

// THE IA'S SIGNS AND ITS HELD ADVICE (docs/piano-ia.md, Fase 5): the right sign and word for every kind of advice, none
// behind the eyes of a view, the card's frame on its target only while it is held, the defence's key framed in the
// panel; and the user's rule: an advice shown stays until the player's next action, but for a blow newly announced on
// his cell or an advice no longer possible.

@(private = "file")
view_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	testing.expect(t, built)
	room.player.tactical.ia_remaining = 999
	return room
}

@(test)
test_advisor_view_signs_every_kind :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := view_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	p := room.player.position
	near := game.add_position(p, {x = 1, y = 0})
	Case :: struct { kind: advisor.Advice_Kind, move: advisor.Move, mark: render.Advice_Mark, word: string }
	cases := [?]Case{
		{.Step, {kind = .Step, direction = .East}, .Step, "VAI"},
		{.Diagonal, {kind = .Diagonal, offset = {x = 1, y = 1}}, .Step, "VAI"},
		{.Dodge, {kind = .Dodge, direction = .East}, .Step, "SCHIVA"},
		{.Bump, {kind = .Step, direction = .East}, .Bump, "COLPISCI"},
		{.Shoot, {kind = .Shoot}, .Bump, "FRECCIA"},
		{.Wait, {kind = .Wait}, .Wait, "ASPETTA"},
		{.Refocus, {kind = .Refocus}, .Refocus, "RIMESCOLA"},
		{.Card, {kind = .Card, card_id = 7}, .Card, "CARTA"},
		{.Defend, {kind = .Defend, defense = .Dodge, direction = .West}, .Defend, "DIFENDI"},
		{.Key, {kind = .Key, direction = .North}, .Defend, "DIFENDI"},
	}
	for c in cases {
		view := run_session.advisor_view(&room, {valid = true, kind = c.kind, move = c.move, cell = near})
		testing.expectf(t, view.mark == c.mark && string(view.word) == c.word, "%v: %v %s", c.kind, view.mark, view.word)
	}
	// Every kind has its sign (the switch has no default; .None has none).
	for kind in advisor.Advice_Kind {
		view := run_session.advisor_view(&room, {valid = true, kind = kind, cell = near})
		testing.expectf(t, (view.mark == .None) == (kind == .None), "%v: %v", kind, view.mark)
	}
	// A step out of a cell a blow is coming to says SCHIVA.
	room.enemies[0].position = game.add_position(p, {x = -1, y = 0})
	room.enemies[0].intent = {kind = .Attack, origin = room.enemies[0].position, destination = room.enemies[0].position, damage = 2, planned_pulse = room.pulse_count+1}
	room.enemies[0].intent.threatened_cells[0], room.enemies[0].intent.threatened_cell_count = p, 1
	view := run_session.advisor_view(&room, {valid = true, kind = .Step, move = {kind = .Step, direction = .East}, cell = near})
	testing.expectf(t, string(view.word) == "SCHIVA", "a step out of the blow says %s", view.word)
	testing.expect(t, advisor.player_danger(&room) != 0)
	// The defence's key, framed in the panel; the dodge's landing on the floor.
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.tactical.advice = run_session.advisor_view(&room, {valid = true, kind = .Defend, move = {kind = .Defend, defense = .Deflect}, cell = p})
	testing.expect(t, render.advice_frames_defense(renderer, &room, .Deflect))
	testing.expect(t, !render.advice_frames_defense(renderer, &room, .Block))
}

// Behind the eyes of a view no sign; the card's frame goes to its target only while the player holds the card; nothing
// on a cell in the fog.
@(test)
test_advisor_view_hides_in_views_and_frames_a_held_card :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := view_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	target := game.add_position(room.player.position, {x = 0, y = -1})
	renderer.tactical.advice = {mark = .Card, cell = target, word = "CARTA", card_id = 7}
	renderer.tactical.no_fog = true
	_, on_floor := render.advice_floor_cell(renderer, &room, 0)
	testing.expect(t, !on_floor)
	cell, held := render.advice_floor_cell(renderer, &room, 7)
	testing.expect(t, held && cell == target)
	// In the fog the sign shows nothing (the advice reveals no cell the player cannot see).
	renderer.tactical.no_fog, renderer.tactical.visible_count = false, 0
	_, fogged := render.advice_floor_cell(renderer, &room, 7)
	testing.expect(t, !fogged)
	testing.expect(t, game.tactical_begin_first_person(&room, 2, .AK))
	testing.expect(t, !render.advice_shown(renderer, &room))
}

// THE HELD ADVICE: the IA's arena, its foes free, the player standing still for five seconds of the world: whenever the
// advice changes, a blow has been newly announced on the player's cell or the advice held could no longer be done.
// Then the player does the advice: the next one is a new advice.
@(test)
test_advisor_pilot_holds_its_advice_until_the_player_acts :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := view_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer run_session.advisor_pilot_release()
	// The first advice.
	start := time.tick_now()
	for !run_session.advisor_current_advice().valid && time.duration_seconds(time.tick_since(start)) < 10 {
		run_session.drive_advisor(&room, renderer, 0)
		time.sleep(time.Millisecond)
	}
	held := run_session.advisor_current_advice()
	testing.expect(t, held.valid)
	held_at, held_danger := room.player.position, advisor.player_danger(&room)
	changes, kept := 0, 0
	for _ in 0..<150 {
		advisor_test_real_frame(&room, advisor.SIM_STEP)
		if room.phase != .Combat { break }
		// The worker has its time, as it would in a real frame.
		time.sleep(2*time.Millisecond)
		danger := advisor.player_danger(&room)
		possible := advisor.advice_possible(&room, held, held_at)
		run_session.drive_advisor(&room, renderer, advisor.SIM_STEP)
		now := run_session.advisor_current_advice()
		if now.move != held.move || now.cell != held.cell {
			changes += 1
			reason := (danger != 0 && danger != held_danger) || !possible
			testing.expectf(t, reason, "the advice changed from %v to %v with no new danger and still possible", held.kind, now.kind)
			held, held_at, held_danger = now, room.player.position, danger
		} else {
			kept += 1
		}
	}
	log.infof("the held advice: %d frames kept, %d changes, each for a blow announced or an advice no longer possible", kept, changes)
	// The player does it: a new advice follows (thinking ahead, or the worker's next).
	advisor_test_real_until_free(&room, advisor.SIM_STEP)
	before := run_session.advisor_current_advice()
	commands, count := run_session.advisor_move_commands(&room, before.move)
	for command in commands[:count] { run_session.execute_gameplay_command(&room, command) }
	run_session.drive_advisor(&room, renderer, 0)
	after := run_session.advisor_current_advice()
	testing.expectf(t, !after.valid || after.root != before.root || after.pondered, "the advice did not let go after the player's move")
}

// The held advice's exception: a blow newly announced on the player's cell. The IA changes its mind (once) without the
// player acting: the advice shown is the new root's.
@(test)
test_advisor_pilot_changes_its_mind_for_a_blow :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := view_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer run_session.advisor_pilot_release()
	for &enemy in room.enemies { enemy.recovery_pulses, enemy.intent, enemy.tactical_cooldown = 99, {}, 0 }
	game.plan_enemy_intents(&room)
	start := time.tick_now()
	for !run_session.advisor_current_advice().valid && time.duration_seconds(time.tick_since(start)) < 10 {
		run_session.drive_advisor(&room, renderer, 0)
		time.sleep(time.Millisecond)
	}
	testing.expect(t, run_session.advisor_current_advice().valid)
	// A foe next to the player announces its blow on his cell.
	p := room.player.position
	foe := &room.enemies[0]
	foe.position = game.add_position(p, {x = 1, y = 0})
	foe.intent = {kind = .Attack, origin = foe.position, destination = foe.position, damage = 4, planned_pulse = room.pulse_count+1}
	foe.intent.threatened_cells[0], foe.intent.threatened_cell_count = p, 1
	foe.tactical_cooldown, foe.recovery_pulses = 1, 0
	testing.expect(t, advisor.player_danger(&room) != 0)
	root := advisor.discrete_fingerprint(&room)
	changed := false
	for time.duration_seconds(time.tick_since(start)) < 20 {
		run_session.drive_advisor(&room, renderer, 0)
		if advice := run_session.advisor_current_advice(); advice.valid && advice.root == root { changed = true; break }
		time.sleep(time.Millisecond)
	}
	testing.expect(t, changed)
}

// THE LOOK (Fase 8): the chip blinks in the last five seconds and only then; the sweep crosses the board one way as the
// card starts, the other as it ends, and is over in its time.
@(test)
test_advisor_chip_blinks_and_the_sweep_crosses :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := view_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	room.player.tactical.ia_remaining = 20
	testing.expect(t, render.ia_chip_color(&room) == render.IA_COLOR)
	seen: [2]bool
	for left := f32(4.95); left > 0; left -= 0.05 {
		room.player.tactical.ia_remaining = left
		color := render.ia_chip_color(&room)
		if color == render.IA_COLOR { seen[0] = true }
		if color == render.IA_COLOR_DIM { seen[1] = true }
	}
	testing.expect(t, seen[0] && seen[1])
	renderer := new(render.Renderer)
	defer free(renderer)
	render.advice_begin_sweep(renderer, false)
	on_start := render.advice_sweep_column(renderer.tactical.advice_sweep, 10)
	render.advice_tick_sweep(renderer, render.ADVICE_SWEEP_SECONDS*0.5)
	on_middle := render.advice_sweep_column(renderer.tactical.advice_sweep, 10)
	testing.expect(t, on_middle > on_start)
	render.advice_begin_sweep(renderer, true)
	off_start := render.advice_sweep_column(renderer.tactical.advice_sweep, 10)
	render.advice_tick_sweep(renderer, render.ADVICE_SWEEP_SECONDS*0.5)
	testing.expect(t, render.advice_sweep_column(renderer.tactical.advice_sweep, 10) < off_start)
	render.advice_tick_sweep(renderer, render.ADVICE_SWEEP_SECONDS)
	testing.expect_value(t, renderer.tactical.advice_sweep.left, f32(0))
}
