package integration
import run_session "../run"


import "core:math"
import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// A walled room, the player at (5, 4) with one First Person Shooter in hand,
// each action lasting its cost; a foe held three cells north of him.
create_first_person_controller_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, room: ^game.Room) -> bool {
	rows := [?]string{
		"###########",
		"#.........#",
		"#.........#",
		"#.........#",
		"#....@....#",
		"#.........#",
		"#.........#",
		"#........>#",
		"###########",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	if !testing.expect_value(t, parsed, level.Parse_Error.None) { return false }
	player^ = create_gameplay_command_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 30, 30, 0
	configure_single_card_test_deck(t, player, .First_Person)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 1}, health = 60, attack = 1}}
	built: bool
	room^, built = game.create_room(data, player, {enemies = enemies[:]})
	if !testing.expect(t, built) { return false }
	for &enemy in room.enemies {
		enemy.recovery_pulses = 999
		enemy.intent, enemy.tactical_cooldown = {}, 0
	}
	game.plan_enemy_intents(room)
	return true
}

// One controller frame with `input` (focused), on the board's clock.
first_person_controller_frame :: proc(controller: ^run_session.Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^run_session.Card_Interaction_State, held: ^run_session.Buffered_Gameplay_Command, dt: f32, input := run_session.Tactical_Controller_Input{}) -> bool {
	render.update_renderer_frame_timeline(renderer, dt)
	given := input
	given.focused = true
	return run_session.step_tactical_controller(controller, room, renderer, cards, held, dt, true, given)
}

// The card played on himself through the lane (no window time), its cues
// played out.
first_person_controller_play :: proc(t: ^testing.T, room: ^game.Room, renderer: ^render.Renderer, cards: ^run_session.Card_Interaction_State) {
	testing.expect(t, run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = room.player.deck.hand[0].id, target = game.entity_target(game.PLAYER_ENTITY)}))
	testing.expect(t, game.tactical_first_person_active(room))
	for _ in 0..<600 {
		if !render.renderer_blocks_player_input(renderer) { break }
		render.update_renderer_frame_timeline(renderer, 0.05)
	}
}

// The AK through the controller: its shots go out as world commands after
// the frame's beats, six a second, while the player's own timed step runs (a
// press of his meanwhile is dropped, never kept); nothing fires with no view,
// a press held from before the view took the mouse fires nothing, nor does the
// trigger while the camera still dives. The board's lanes replay cleanly.
@(test)
test_first_person_fires_in_world_commands_never_blocked_by_its_steps :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_first_person_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	north := game.First_Person_Aim{yaw = -math.PI/2}
	testing.expect(t, run_session.gameplay_command_is_valid({kind = .First_Person_Fire, origin_phase = .Combat}))
	testing.expect(t, !run_session.gameplay_command_is_valid({kind = .First_Person_Fire, origin_phase = .Loot}))
	// No view: a shot commits nothing, the trigger holds nothing.
	testing.expect(t, !run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .First_Person_Fire, origin_phase = .Combat, aim = north}))
	fire := run_session.Tactical_Controller_Input{fire = true}
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire)
	testing.expect(t, !controller.look_captured && room.first_person.shots == 0)
	first_person_controller_play(t, &room, renderer, &cards)
	renderer.tactical.first_person.yaw = north.yaw
	// The button already down as the view takes the mouse: nothing until it
	// is let go.
	for _ in 0..<10 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire) }
	testing.expect(t, controller.look_captured && controller.fire_latched && room.first_person.shots == 0)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	testing.expect(t, !controller.fire_latched)
	// The camera still diving: no shot yet.
	renderer.tactical.first_person.engaged, renderer.tactical.first_person.amount = true, 0.5
	for _ in 0..<10 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire) }
	testing.expect_value(t, room.first_person.shots, i32(0))
	renderer.tactical.first_person.amount = 1
	// A second of the trigger: six shots, none held back by his own timed
	// step taken meanwhile, whose second the world runs through.
	window := player.tactical.remaining
	health := room.enemies[0].health
	stepped := false
	for frame in 0..<60 {
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire)
		if frame == 5 {
			testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Combat, direction = .South}))
			stepped = game.tactical_player_busy(&room)
		}
		if frame > 5 && frame < 30 {
			// A press during the step is dropped.
			busy := render.renderer_blocks_player_input(renderer) || game.tactical_player_busy(&room)
			_, ok := run_session.route_gameplay_command(&held, &room, busy, {kind = .Move, origin_phase = .Combat, direction = .East}, true, dt)
			testing.expect(t, !ok && held == run_session.Buffered_Gameplay_Command{})
		}
	}
	testing.expect(t, stepped)
	testing.expect_value(t, room.first_person.shots, i32(6))
	testing.expect_value(t, room.first_person.hits, i32(6))
	testing.expect_value(t, room.enemies[0].health, health-6)
	testing.expect(t, abs(window-player.tactical.remaining-1) < 0.01)
	for _ in 0..<600 {
		if !render.renderer_timeline_is_busy(renderer) { break }
		render.update_renderer_frame_timeline(renderer, 0.05)
	}
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	if testing.expect(t, renderer.world_playback != nil) { testing.expect_value(t, renderer.world_playback.rejected_batches, 0) }
}

// Behind his eyes W, D, S and A step forward, right, back and left of the
// view, Space waits and nothing else is read; Shift with a key dodges the same
// way; a dodge's landing in the defence prompt turns with the view, a key the
// panel names stays its own; the diagonal keys and the map do nothing.
@(test)
test_first_person_keys_dodge_and_defence_turn_with_the_view :: proc(t: ^testing.T) {
	east := game.first_person_key_directions(0)
	pressed: [4]bool
	pressed[0] = true
	command, has := run_session.first_person_lane_command(pressed, false, false, east)
	testing.expect(t, has && command.kind == .Move && command.direction == .East && command.origin_phase == .Combat)
	pressed = {false, false, false, true}
	command, has = run_session.first_person_lane_command(pressed, false, false, east)
	testing.expect(t, has && command.direction == .North)
	_, has = run_session.first_person_lane_command(pressed, true, false, east)
	testing.expect(t, !has)
	command, has = run_session.first_person_lane_command({}, false, true, east)
	testing.expect(t, has && command.kind == .Wait)
	_, has = run_session.first_person_lane_command({}, false, false, east)
	testing.expect(t, !has)

	data: level.Level
	player: game.Player
	room: game.Room
	if !create_first_person_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	first_person_controller_play(t, &room, renderer, &cards)
	view := &renderer.tactical.first_person
	view.engaged, view.amount, view.yaw = true, 1, 0
	testing.expect_value(t, render.first_person_keys(renderer), east)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	// The diagonal keys and the map: nothing.
	nothing := run_session.Tactical_Controller_Input{}
	nothing.diagonals[0] = true
	nothing.map_input.toggle = true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, nothing)
	testing.expect(t, room.qte.kind == .None && !controller.hologram)
	// Shift and W: a dodge east, two cells.
	start := player.position
	dodge := run_session.Tactical_Controller_Input{shift = true}
	dodge.directions[0] = true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, dodge)
	testing.expect_value(t, player.position, game.add_position(start, {x = 2, y = 0}))
	for _ in 0..<600 {
		if !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(&room) { break }
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	}
	// The defence prompt: E, then W lands east (forward).
	foe := room.enemies[0].id
	player.tactical.dodge_recovery = 0
	room.qte = {kind = .Defense, remaining = 1, enemy_id = foe, defenses = {.Dodge}, length = 1}
	choose := run_session.Tactical_Controller_Input{}
	choose.defenses[3] = true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, choose)
	testing.expect(t, room.qte.selected && room.qte.mode == .Dodge)
	from := player.position
	land := run_session.Tactical_Controller_Input{}
	land.directions[0] = true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, land)
	testing.expect(t, room.qte.kind == .None)
	testing.expect_value(t, player.position, game.add_position(from, {x = 1, y = 0}))
	// A key the panel names: its own letter (W is north), whatever the view.
	room.qte = {kind = .Defense, remaining = 1, enemy_id = foe, defenses = {.Parry}, length = 1, selected = true, mode = .Parry,
		keys = {.North, .North}}
	before := player.tactical.metrics.qte_successes
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, land)
	testing.expect(t, room.qte.kind == .None && player.tactical.metrics.qte_successes == before+1)
}

// The view takes the mouse when it begins, gives it back on a pause, on losing
// focus and when it ends; each time a press already down fires nothing until
// let go, and the first frames' moves are no look. Then the mouse turns the
// view by the profile's sensitivity.
@(test)
test_first_person_capture_follows_the_view_and_latches_the_press :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_first_person_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	testing.expect(t, !controller.look_captured)
	first_person_controller_play(t, &room, renderer, &cards)
	view := &renderer.tactical.first_person
	view.engaged, view.amount, view.yaw = true, 1, 0
	controls := run_session.Run_Input{focused = true, mouse_motion = {100, -40}}
	look := run_session.tactical_controller_input(&controller, &room, controls, {}, false, 2)
	testing.expect_value(t, look.look, [2]f32{})
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, look)
	testing.expect(t, controller.look_captured && controller.fire_latched && controller.look_settle == run_session.FIRST_PERSON_LOOK_SETTLE_FRAMES)
	// The snapshot sampled before capture cannot turn the view. Subsequent
	// captured frames still pass through the settle gate before mouse-look.
	look = run_session.tactical_controller_input(&controller, &room, controls, {}, false, 2)
	testing.expect_value(t, look.look, [2]f32{100, -40})
	for _ in 0..<run_session.FIRST_PERSON_LOOK_SETTLE_FRAMES { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, look) }
	testing.expect(t, view.yaw == 0 && view.pitch == 0)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, look)
	testing.expect(t, abs(view.yaw-100*run_session.FIRST_PERSON_MOUSE_SENSITIVITY*2) < 1e-5)
	testing.expect(t, abs(view.pitch-40*run_session.FIRST_PERSON_MOUSE_SENSITIVITY*2) < 1e-5)
	// A pause gives the mouse back; the resume takes it again, the click that
	// resumed still down fires nothing.
	pause := run_session.Tactical_Controller_Input{pause = true}
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, pause)
	testing.expect(t, controller.paused && !controller.look_captured && !room.first_person.trigger)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, pause)
	testing.expect(t, !controller.paused)
	fire := run_session.Tactical_Controller_Input{fire = true}
	shots := room.first_person.shots
	for _ in 0..<5 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire) }
	testing.expect(t, controller.look_captured && controller.fire_latched && room.first_person.shots == shots)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, fire)
	testing.expect_value(t, room.first_person.shots, shots+1)
	// Focus lost: given back.
	render.update_renderer_frame_timeline(renderer, dt)
	run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, dt, true, {})
	testing.expect(t, !controller.look_captured && !room.first_person.trigger)
	for _ in 0..<3 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	testing.expect(t, controller.look_captured)
	// The view over: given back for good.
	room.first_person.remaining = 0.01
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
	testing.expect(t, !game.tactical_first_person_active(&room) && !controller.look_captured)
}
