package run

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"
import view "../engine/view"

// MOSTRA EFFETTO: the film of a card, the director of its takes. A take
// builds the card's own room (game.create_card_demo_room, the scene of
// game.card_demo_scene), lets it settle, moves a paper glove to the card in
// the hand, plays it as the hand plays it (a drag let go on its target as the
// hand's own drag lets go: game.card_drop_target; a click and a second click;
// the rod's slot through poll_fishing_command), and then runs the room as the
// game runs it, only through the take's own step_tactical_controller, the
// scene's actions pressed when the board lets them; the board is the game's
// renderer, the HUD and the hand the game's. When all is done and still it
// holds a moment, goes dark and starts afresh: the same room, the same seeds,
// the same take. The world waits while the glove carries the card (the game's
// clock would run): a choice of the film, so that every take shows the same.
//
// The window (effect_window.odin) drives a film only through card_demo_open,
// card_demo_step, card_demo_restart, card_demo_prepare (GPU work outside any
// render target: the dice), card_demo_draw (the whole stage, into the target
// bound now), card_demo_close and card_demo_caption. A Card_Demo is large and
// its room points into it: it lives on the heap and is never copied while a
// take lives. Nothing here reads raylib's input or touches its cursor: the
// FIRST PERSON SHOOTER's view turns and fires by the scripted input of the
// take's own controller, whose capture of the mouse is a flag only. Nothing
// here plays a sound either: the board's lab sounds queue only on a board in
// PROVA MECCANICHE (render.set_mechanics_lab), and only its scene plays them.

CARD_DEMO_SETTLE :: f32(0.7)
CARD_DEMO_REACH :: f32(0.55)
CARD_DEMO_PRESS :: f32(0.18)
CARD_DEMO_CARRY :: f32(0.85)
CARD_DEMO_HOVER :: f32(0.35)
// Between the two clicks of a card played as the hand plays it.
CARD_DEMO_CLICK_GAP :: f32(0.4)
// The ring a click leaves, and how long the glove takes to reach a foe or a
// button for an action.
CARD_DEMO_CLICK_SECONDS :: f32(0.3)
CARD_DEMO_AIM_SECONDS :: f32(0.55)
// FIRST PERSON SHOOTER: how fast the scripted mouse turns the view (radians a
// second), how close it must come before the trigger is held, and how long
// it may take at most.
CARD_DEMO_TURN_RATE :: f32(2.5)
CARD_DEMO_TURN_DONE :: f32(0.03)
CARD_DEMO_TURN_SECONDS :: f32(2)
// The glove fades where it let the card go, this long.
CARD_DEMO_GLOVE_FADE :: f32(0.35)
// A done take holds this long; its last FADE seconds and its next's first go dark.
CARD_DEMO_HOLD :: f32(1.1)
CARD_DEMO_FADE :: f32(0.25)
// An action's caption shows this long before it and after it.
CARD_DEMO_CAPTION_BEFORE :: f32(0.6)
CARD_DEMO_CAPTION_AFTER :: f32(1.2)
// The VITA plate lights up this long when what it shows changes once the card
// is played (a shield, gold, a wound, a cure).
CARD_DEMO_VITALS_FLASH :: f32(1.8)
// The board's camera a little nearer than the game's (12.5): the stage shows
// the canvas at three quarters of the game's size, its figures as large.
CARD_DEMO_ORBIT_DISTANCE :: f32(10)
// Seconds a take may run at most before it is cut (and the test fails it).
CARD_DEMO_TAKE_LIMIT :: f32(40)
// No frame of a film is longer than this (a hitch is not a jump).
CARD_DEMO_MAX_STEP :: f32(1.0/15.0)

Card_Demo_Stage :: enum u8 {Settle, Reach, Press, Carry, Hover, Effect, Hold, Done}

// A roll of the take's dice prepared on the stage's own dice for this frame
// (card_demo_prepare), drawn over the stage (card_demo_draw).
Card_Demo_Dice_Frame :: struct {
	shown: bool,
	roll: game.Dice_Roll,
	progress: f32,
	seed: u64,
	card: game.Card_Id,
	outcome: render.Dice_Outcome,
}

Card_Demo :: struct {
	card: game.Card_Instance,
	scene: game.Card_Demo_Scene,
	// The take's dice: found once for the card's faces (game.card_demo_dice).
	dice: game.Dice_State,
	data: level.Level,
	player: game.Player,
	room: game.Room,
	built, failed: bool,
	controller: Tactical_Controller,
	cards: Card_Interaction_State,
	buffer: Buffered_Gameplay_Command,
	stage: Card_Demo_Stage,
	stage_time, effect_time, take_time: f32,
	// The glove's tip on the stage, where its move started, whether it holds
	// the card, and the seconds since its last click (< 0: none).
	pointer, from: view.Vec2,
	grabbing: bool,
	click_age: f32,
	// The card's id in the hand (or the rod's), once dealt.
	hand_id: u32,
	next_action: int,
	// The running action: its own seconds (its aim, its turn), the trigger's
	// seconds left, and the words of the last one done, with the seconds since.
	acting: bool,
	action_time, firing: f32,
	done_key, done_text: cstring,
	since_action: f32,
	// The last action done was the glove's own (an arrow's click, ATTIVA).
	done_by_glove: bool,
	// Seconds since the card's own cast and cues were over (-1: not yet).
	free_time: f32,
	played: bool,
	// What the take showed beyond the board's events (renderer.shown_events):
	// the ground, which has no event of its own, and the AK's hits.
	pooled, burned: bool,
	fps_hits: i32,
	takes: int,
	// What the VITA plate showed last frame, and how long it stays lit.
	vitals: Card_Demo_Vitals,
	vitals_flash: f32,
	// The stage's own dice, its texture made outside any render target.
	dice_view: render.Dice_Renderer,
	dice_frame: Card_Demo_Dice_Frame,
}

// What the HUD's VITA plate shows of the player (render.renderer_status_view:
// what the board shows now): his life, his gold, his statuses and their
// stacks, never their seconds running out.
Card_Demo_Vitals :: struct {
	health, max_health, gold: i32,
	statuses: [game.Status_Kind]i32,
}

card_demo_vitals :: proc(renderer: ^render.Renderer, room: ^game.Room) -> (vitals: Card_Demo_Vitals) {
	v := render.renderer_status_view(renderer, room)
	vitals.health, vitals.max_health, vitals.gold = v.health, v.max_health, v.gold
	for status in v.statuses.items[:clamp(v.statuses.count, 0, len(v.statuses.items))] { vitals.statuses[status.kind] = status.potency+1 }
	return
}

// The board's characters are living cards wherever it is 3D, as in the run;
// never on a board with no window to draw it (the tests): the living cards'
// clips and the blows' props are the drawing's own (render.observe_attack_cues
// runs as the board is drawn), and the board's timing waits on them.
card_demo_living :: proc(renderer: ^render.Renderer) -> bool {
	return renderer != nil && rl.IsWindowReady()
}

// The board is a tactical view: the glove finds its cells on the board's own
// camera. Without one (the tests' plain renderer) the take runs its rules on
// the cells it aims at.
card_demo_visual :: proc(renderer: ^render.Renderer) -> bool {
	return renderer != nil && renderer.tactical.snapshot != nil
}

card_demo_destroy_room :: proc(demo: ^Card_Demo) {
	if demo == nil { return }
	if demo.built { game.destroy_room(&demo.room) }
	level.destroy(&demo.data)
	demo.built = false
}

// The film of `card` on `renderer`'s board, its first take built. False when
// the card has no film (an unknown card or level): the window then says so.
card_demo_open :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, card: game.Card_Instance) -> bool {
	if demo == nil || renderer == nil { return false }
	card_demo_destroy_room(demo)
	// The stage's dice keep their texture from film to film.
	kept := demo.dice_view
	demo^ = {dice_view = kept}
	demo.card = card
	demo.card.id = 1
	if card.definition_id < .Strike || card.definition_id >= .Count || card.upgrade_level < 0 ||
	   card.upgrade_level > game.card_max_upgrade_level(card.definition_id) {
		demo.failed = true
		return false
	}
	demo.card.lifetime = .Combat if game.card_definition_temporary(card.definition_id) else .Permanent
	demo.scene = game.card_demo_scene(card.definition_id, card.upgrade_level)
	if demo.scene.faces != {} {
		if dice, found := game.card_demo_dice(demo.card, demo.scene.faces, game.FISHING_HEAL_SIDES); found { demo.dice = dice }
	}
	return card_demo_begin_take(demo, renderer)
}

// RICOMINCIA: the film from its first frame.
card_demo_restart :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) {
	if demo == nil || renderer == nil || demo.card.id == 0 { return }
	_ = card_demo_begin_take(demo, renderer)
}

// The film closed: its room and the stage's dice go. The board it was drawn
// on is the window's, and is left as it is.
card_demo_close :: proc(demo: ^Card_Demo) {
	if demo == nil { return }
	card_demo_destroy_room(demo)
	render.destroy_dice_renderer(&demo.dice_view)
	demo^ = {}
}

// A fresh take: the room built again, the board told it is a new one.
card_demo_begin_take :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> bool {
	card_demo_destroy_room(demo)
	r := renderer
	// Nothing of the last take's pictures stays: its cues, cards, blows,
	// ground, rope, ball and view (render.forget_living_actors).
	render.clear_event_animations(r)
	r.shown_events = {}
	r.has_hovered_cell = false
	r.tactical.arrow_aim = false
	r.tactical.inspected = 0
	if !game.create_card_demo_room(demo.scene, demo.card, demo.dice, &demo.data, &demo.player, game.GAME_TACTICAL_CONFIG, &demo.room) {
		level.destroy(&demo.data)
		demo.failed = true
		return false
	}
	demo.built, demo.failed = true, false
	demo.controller = {was_focused = true}
	demo.cards, demo.buffer = {}, {}
	demo.stage, demo.stage_time, demo.effect_time, demo.take_time = .Settle, 0, 0, 0
	demo.next_action, demo.acting, demo.action_time, demo.firing = 0, false, 0, 0
	demo.done_key, demo.done_text, demo.since_action = nil, nil, -1
	demo.free_time, demo.played = -1, false
	demo.pooled, demo.burned, demo.fps_hits = false, false, 0
	demo.grabbing, demo.click_age, demo.done_by_glove = false, -1, false
	demo.dice_frame = {}
	demo.hand_id = 0
	if game.card_is_room_tool(demo.card.definition_id) {
		if rod, held := game.fishing_rod(&demo.player.deck); held { demo.hand_id = rod.id }
	} else {
		for held in demo.player.deck.hand[:demo.player.deck.hand_count] {
			if held.definition_id == demo.card.definition_id { demo.hand_id = held.id }
		}
	}
	if demo.hand_id == 0 {
		card_demo_destroy_room(demo)
		demo.failed = true
		return false
	}
	if card_demo_visual(r) {
		render.reset_tactical_orbit(&r.tactical.world_orbit)
		r.tactical.world_orbit.distance = CARD_DEMO_ORBIT_DISTANCE
		render.update_tactical_view(r, &demo.room, {}, false, true)
	}
	render.set_living_cards(r, card_demo_living(r))
	demo.pointer = card_demo_rest_point(demo, r)
	demo.from = demo.pointer
	demo.vitals, demo.vitals_flash = card_demo_vitals(r, &demo.room), 0
	demo.takes += 1
	return true
}

// Where the glove waits: low on the stage, right of the hand (left of the
// rod's slot, which is at the right).
card_demo_rest_point :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> view.Vec2 {
	if demo.scene.gesture == .Rod_Slot { return {renderer.canvas_width*0.5, renderer.canvas_height-58} }
	return {renderer.canvas_width*0.7, renderer.canvas_height-54}
}

// Where the glove picks the card up: its card in the hand, or the rod's slot.
card_demo_card_point :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> view.Vec2 {
	if demo.scene.gesture == .Rod_Slot {
		slot := render.fishing_slot_bounds(renderer)
		return {slot.x+slot.width*0.5, slot.y+slot.height*0.42}
	}
	deck := &demo.player.deck
	index, found := game.hand_card_index_by_id(deck, demo.hand_id)
	if !found { return demo.pointer }
	bounds := render.hand_card_bounds(renderer, index, deck.hand_count)
	return {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.42}
}

// The cell the card is let go on: the scene's foe where it stands now, or
// the scene's cell.
card_demo_target_cell :: proc(demo: ^Card_Demo) -> grid.Position {
	scene := &demo.scene
	switch scene.gesture {
	case .Drag_To_Player, .Double_Click: return demo.player.position
	case .Drag_To_Foe:
		if enemy, found := card_demo_foe(demo, scene.target_foe); found { return enemy.position }
	case .Drag_Along_Line:
		// A foe standing on the line's cell is its target as it stands.
		if scene.target_foe < scene.foe_count && scene.foes[scene.target_foe].at == scene.target {
			if enemy, found := card_demo_foe(demo, scene.target_foe); found { return enemy.position }
		}
	case .Drag_To_Cell, .Rod_Slot:
	}
	return scene.target
}

// The stage point over a cell's centre, `height` over the floor (the board's
// own projection); headless, a point of the cell's own.
card_demo_cell_point :: proc(renderer: ^render.Renderer, cell: grid.Position, height: f32 = 0.05) -> view.Vec2 {
	if !card_demo_visual(renderer) { return {f32(cell.x)*10+5, f32(cell.y)*10+5} }
	return render.tactical_project(renderer, {f32(cell.x)+0.5, f32(cell.y)+0.5}, height)
}

// Where the glove's tip touches a cell: a foe there on its figure.
card_demo_touch_point :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, cell: grid.Position) -> view.Vec2 {
	_, foe := game.enemy_index_at(&demo.room, cell)
	return card_demo_cell_point(renderer, cell, 0.4 if foe else 0.05)
}

// The board's cell under a stage point, as the board picks it (its floor's
// ray): what the hand's drag aims at.
card_demo_cell_under :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, point: view.Vec2) -> (cell: grid.Position, ok: bool) {
	r := renderer
	if !card_demo_visual(r) || !render.point_in_rectangle(point, render.tactical_world_bounds(r)) { return }
	ray := rl.GetScreenToWorldRayEx({point.x, point.y}, r.tactical.camera, c.int(r.canvas_width), c.int(r.canvas_height))
	if abs(ray.direction.y) < 0.0001 { return }
	t := -ray.position.y/ray.direction.y
	if t <= 0 { return }
	at := ray.position+ray.direction*t
	cell = {x = int(math.floor(at.x)), y = int(math.floor(at.z))}
	ok = grid.contains(&demo.data.tiles, cell) && render.tactical_render_visible(r, cell)
	return
}

card_demo_ease :: proc(t: f32) -> f32 {
	x := clamp(t, 0, 1)
	return x*x*(3-2*x)
}

card_demo_lerp :: proc(from, to: view.Vec2, t: f32) -> view.Vec2 {
	k := card_demo_ease(t)
	return {from.x+(to.x-from.x)*k, from.y+(to.y-from.y)*k}
}

// The board's hover under the glove while it carries the card: the cell it
// is over, or once it is there (and headless, near the end) the target's.
card_demo_hover :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, arrived: bool) {
	r := renderer
	if arrived || !card_demo_visual(r) {
		r.has_hovered_cell, r.hovered_cell = arrived, card_demo_target_cell(demo)
		return
	}
	r.hovered_cell, r.has_hovered_cell = card_demo_cell_under(demo, r, demo.pointer)
}

// The rod's slot under the glove, as the hand's own pointer works it.
card_demo_rod_input :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, input: Fishing_Input) -> (command: Gameplay_Command, has_command: bool) {
	mouse := input
	mouse.mouse, mouse.inside = demo.pointer, true
	command, has_command, _ = poll_fishing_command(&demo.room, renderer, &demo.cards, mouse, true)
	return
}

// Lets go: the command the hand's own routing makes of the drop.
card_demo_release :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> bool {
	r := renderer
	room := &demo.room
	if demo.scene.gesture == .Rod_Slot {
		command, dropped := card_demo_rod_input(demo, r, {released = true})
		return dropped && commit_gameplay_command(room, r, &demo.cards, command)
	}
	index, found := game.hand_card_index_by_id(&demo.player.deck, demo.hand_id)
	if !found { return false }
	card := demo.player.deck.hand[index]
	if demo.scene.gesture == .Double_Click {
		// The second click on the chosen card plays it (poll_gameplay_command).
		command, immediate := immediate_card_command(card)
		return immediate && commit_gameplay_command(room, r, &demo.cards, command)
	}
	dragged := demo.cards.dragged_card_id
	demo.cards.dragged_card_id = 0
	demo.cards.selected_card_id = dragged
	if !r.has_hovered_cell || !render.card_drop_area_contains(r, demo.pointer) { return false }
	command, has_target := targeted_card_command(room, card, r.hovered_cell, demo.scene.aim, demo.scene.has_aim)
	return has_target && commit_gameplay_command(room, r, &demo.cards, command)
}

// The board lets the player act (the hand's lane would take a press now).
card_demo_board_free :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> bool {
	room := &demo.room
	return !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) &&
	       !game.tactical_is_casting(room) && room.qte.kind == .None && !room.tactical_pulse.pending
}

// A mode of the card's own runs on: his shadow, the rope, the ball, his eyes.
card_demo_mode_active :: proc(demo: ^Card_Demo) -> bool {
	room := &demo.room
	return game.tactical_shadow_active(room) || game.tactical_lasso_active(room) || game.tactical_pinball_active(room) ||
	       game.tactical_first_person_active(room)
}

// The scene's foe `foe` as it stands now (it may have moved, or fallen).
card_demo_foe :: proc(demo: ^Card_Demo, foe: int) -> (enemy: ^game.Enemy, ok: bool) {
	index, found := game.enemy_index_by_id(&demo.room, u32(foe+1))
	if !found { return }
	return &demo.room.enemies[index], true
}

// FIRST PERSON SHOOTER: the turn left for the eyes to face the scene's foe
// `foe` (0 once it has fallen).
card_demo_turn_left :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, foe: int) -> f32 {
	enemy, found := card_demo_foe(demo, foe)
	if !found { return 0 }
	p := demo.player.position
	want := math.atan2(f32(enemy.position.y-p.y), f32(enemy.position.x-p.x))
	return render.first_person_wrap(want-renderer.tactical.first_person.yaw)
}

// What the take's controller is given this frame: focus, and for the running
// shot of the AK the mouse's turn of the view and the trigger.
card_demo_input :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, dt: f32) -> (input: Tactical_Controller_Input) {
	input.focused, input.sensitivity = true, 1
	if !demo.acting || demo.next_action >= demo.scene.action_count { return }
	action := demo.scene.actions[demo.next_action]
	if action.kind != .Fire { return }
	if demo.firing > 0 { input.fire = true; return }
	turn := card_demo_turn_left(demo, renderer, action.foe)
	step := clamp(turn, -CARD_DEMO_TURN_RATE*dt, CARD_DEMO_TURN_RATE*dt)
	input.look.x = clamp(step/FIRST_PERSON_MOUSE_SENSITIVITY, -FIRST_PERSON_LOOK_CLAMP, FIRST_PERSON_LOOK_CLAMP)
	return
}

// The scene's next action, once its time has come and the board lets it,
// carried on frame by frame until it is done.
card_demo_act :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, dt: f32) {
	r := renderer
	room := &demo.room
	scene := &demo.scene
	if demo.since_action >= 0 { demo.since_action += dt }
	if demo.next_action >= scene.action_count || demo.free_time < 0 { return }
	action := scene.actions[demo.next_action]
	if !demo.acting {
		if demo.free_time < action.after { return }
		// A shadow step waits only for the shadow's own lockout; the AK for the
		// eyes to be his; the rest for the board to let the player act.
		switch {
		case game.tactical_shadow_active(room):
			if render.renderer_blocks_player_input(r) || game.tactical_shadow_step_busy(room) { return }
		case action.kind == .Fire:
			if game.tactical_first_person_active(room) && render.first_person_diving(r) { return }
		case:
			if !card_demo_board_free(demo, r) { return }
		}
		demo.acting, demo.action_time, demo.from = true, 0, demo.pointer
	}
	demo.action_time += dt
	key, text := card_demo_action_words(demo, demo.next_action)
	done := false
	switch action.kind {
	case .None:
		done = true
	case .Step:
		_ = commit_gameplay_command(room, r, &demo.cards, {kind = .Move, origin_phase = .Combat, direction = action.direction})
		done = true
	case .Wait:
		_ = commit_gameplay_command(room, r, &demo.cards, {kind = .Wait, origin_phase = .Combat})
		done = true
	case .Shoot:
		// Ctrl held: the board marks the foes the arrows reach; the glove goes
		// to the foe, then the click looses one (the hand's own routing).
		enemy, found := card_demo_foe(demo, action.foe)
		if !found { done = true; break }
		r.tactical.arrow_aim = arrows_aiming_at(room, true)
		demo.pointer = card_demo_lerp(demo.from, card_demo_touch_point(demo, r, enemy.position), demo.action_time/CARD_DEMO_AIM_SECONDS)
		r.has_hovered_cell, r.hovered_cell = demo.action_time >= CARD_DEMO_AIM_SECONDS*0.6, enemy.position
		if demo.action_time < CARD_DEMO_AIM_SECONDS { break }
		shot, has_shot, _ := arrow_shot_command(room, r, r.tactical.arrow_aim, true)
		demo.click_age = 0
		if has_shot { _ = commit_gameplay_command(room, r, &demo.cards, shot) }
		r.tactical.arrow_aim, r.has_hovered_cell, r.tactical.inspected = false, false, 0
		done = true
	case .Activate:
		// The glove goes to ATTIVA on the board's bar and clicks it.
		button := render.m8_control_bounds(r, .Activate, room)
		demo.pointer = card_demo_lerp(demo.from, {button.x+button.width*0.5, button.y+button.height*0.55}, demo.action_time/CARD_DEMO_AIM_SECONDS)
		if demo.action_time < CARD_DEMO_AIM_SECONDS { break }
		demo.click_age = 0
		_ = commit_gameplay_command(room, r, &demo.cards, {kind = .Activate, origin_phase = room.phase})
		done = true
	case .Fire:
		// Behind his eyes: the view turned on the foe (card_demo_input), then
		// the trigger held; the view's end ends it, and a foe already down
		// takes no burst.
		if _, standing := card_demo_foe(demo, action.foe); !standing || !game.tactical_first_person_active(room) { done = true; break }
		if demo.firing > 0 {
			demo.firing -= dt
			done = demo.firing <= 0
			break
		}
		if abs(card_demo_turn_left(demo, r, action.foe)) <= CARD_DEMO_TURN_DONE || demo.action_time >= CARD_DEMO_TURN_SECONDS {
			demo.firing = action.seconds
		}
	}
	if done {
		demo.done_key, demo.done_text, demo.since_action = key, text, 0
		demo.done_by_glove = action.kind == .Shoot || action.kind == .Activate
		demo.next_action += 1
		demo.acting, demo.action_time, demo.firing = false, 0, 0
		if action.kind == .Shoot || action.kind == .Activate { demo.from = demo.pointer }
	}
}

// One frame of the film, `dt` real seconds of it: a done take starts afresh.
card_demo_step :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, dt: f32) {
	if demo == nil || renderer == nil || demo.card.id == 0 { return }
	if demo.built && demo.stage == .Done { _ = card_demo_begin_take(demo, renderer) }
	card_demo_advance(demo, renderer, dt)
}

// One frame of the take, `frame_dt` real seconds of it (none: it waits).
card_demo_advance :: proc(demo: ^Card_Demo, renderer: ^render.Renderer, frame_dt: f32) {
	if demo == nil || renderer == nil || !demo.built || demo.stage == .Done { return }
	dt := min(frame_dt, CARD_DEMO_MAX_STEP)
	if !(dt > 0) { return }
	r := renderer
	room := &demo.room
	visual := card_demo_visual(r)
	demo.stage_time += dt
	demo.take_time += dt
	if demo.click_age >= 0 { demo.click_age += dt }
	// The board's clocks as the run keeps them: the sprite clock waits out a
	// cinematic roll of the dice.
	if render.presentation_time_policy(&r.timeline) != .Cinematic { render.advance_sprite_assets(&r.sprite_assets, dt) }
	render.update_renderer_frame_timeline(r, dt)
	if visual {
		render.update_tactical_view(r, room, demo.pointer, card_demo_glove_alpha(demo) > 0, true)
		render.update_tactical_atmosphere(r, dt)
	}
	switch demo.stage {
	case .Settle:
		if demo.stage_time >= CARD_DEMO_SETTLE { demo.stage, demo.stage_time, demo.from = .Reach, 0, demo.pointer }
	case .Reach:
		demo.pointer = card_demo_lerp(demo.from, card_demo_card_point(demo, r), demo.stage_time/CARD_DEMO_REACH)
		if demo.scene.gesture == .Rod_Slot { _, _ = card_demo_rod_input(demo, r, {}) }
		else { demo.cards.hovered_card_id = demo.hand_id if demo.stage_time >= CARD_DEMO_REACH*0.7 else 0 }
		if demo.stage_time >= CARD_DEMO_REACH { demo.stage, demo.stage_time = .Press, 0; demo.click_age = 0 }
	case .Press:
		switch demo.scene.gesture {
		case .Double_Click:
			// The first click chooses it (CLIC DI NUOVO: GIOCA), the second plays it.
			demo.cards.hovered_card_id, demo.cards.selected_card_id = demo.hand_id, demo.hand_id
			if demo.stage_time >= CARD_DEMO_CLICK_GAP {
				demo.click_age = 0
				demo.played = card_demo_release(demo, r)
				demo.cards.hovered_card_id = 0
				demo.stage, demo.stage_time = .Effect, 0
			}
		case .Rod_Slot:
			_, _ = card_demo_rod_input(demo, r, {pressed = true, down = true})
			demo.grabbing = true
			if demo.stage_time >= CARD_DEMO_PRESS { demo.stage, demo.stage_time, demo.from = .Carry, 0, demo.pointer }
		case .Drag_To_Player, .Drag_To_Foe, .Drag_To_Cell, .Drag_Along_Line:
			// The press picks it up: the hand's drag (poll_gameplay_command).
			demo.cards = {dragged_card_id = demo.hand_id}
			demo.grabbing = true
			if demo.stage_time >= CARD_DEMO_PRESS { demo.stage, demo.stage_time, demo.from = .Carry, 0, demo.pointer }
		}
	case .Carry:
		t := demo.stage_time/CARD_DEMO_CARRY
		demo.pointer = card_demo_lerp(demo.from, card_demo_touch_point(demo, r, card_demo_target_cell(demo)), t)
		if demo.scene.gesture == .Rod_Slot { _, _ = card_demo_rod_input(demo, r, {down = true}) }
		card_demo_hover(demo, r, !visual && t >= 0.6)
		if demo.stage_time >= CARD_DEMO_CARRY { demo.stage, demo.stage_time = .Hover, 0 }
	case .Hover:
		demo.pointer = card_demo_touch_point(demo, r, card_demo_target_cell(demo))
		if demo.scene.gesture == .Rod_Slot { _, _ = card_demo_rod_input(demo, r, {down = true}) }
		card_demo_hover(demo, r, true)
		if demo.stage_time >= CARD_DEMO_HOVER {
			demo.played = card_demo_release(demo, r)
			demo.grabbing = false
			demo.cards.hovered_card_id, demo.cards.selected_card_id = 0, 0
			r.has_hovered_cell = false
			demo.stage, demo.stage_time = .Effect, 0
		}
	case .Effect, .Hold, .Done:
		demo.effect_time += dt
		// The card's own seconds: from when its cast and cues are over; behind
		// his eyes or in his shadow its actions go as soon as the board lets them.
		free := card_demo_board_free(demo, r)
		if demo.free_time >= 0 { demo.free_time += dt }
		else if demo.played && free && !card_demo_mode_active(demo) { demo.free_time = 0 }
		else if demo.played && free && demo.effect_time > 0.2 &&
		   (game.tactical_first_person_active(room) || game.tactical_shadow_active(room)) { demo.free_time = 0 }
		step_tactical_controller(&demo.controller, room, r, &demo.cards, &demo.buffer, dt, true, card_demo_input(demo, r, dt))
		card_demo_act(demo, r, dt)
		// The ground has no event: the take samples it, and the AK's hits.
		for value in room.ground.pool { if value > 0 { demo.pooled = true } }
		for fire in room.ground.fires[:room.ground.fire_count] { if fire.stage >= 2 { demo.burned = true } }
		demo.fps_hits = max(demo.fps_hits, room.first_person.hits)
		finished := demo.next_action >= demo.scene.action_count && !demo.acting && demo.free_time >= demo.scene.seconds &&
			!render.renderer_timeline_is_busy(r) && !game.tactical_is_casting(room) && !card_demo_mode_active(demo) &&
			render.first_person_amount(r) <= 0
		if demo.stage == .Effect && (finished || !demo.played && demo.effect_time > 2) { demo.stage, demo.stage_time = .Hold, 0 }
		if demo.stage == .Hold && demo.stage_time >= CARD_DEMO_HOLD { demo.stage = .Done }
		if demo.take_time > CARD_DEMO_TAKE_LIMIT { demo.stage = .Done }
	}
	render.set_living_cards(r, card_demo_living(r))
	// What the card did to him shows on his plate: it lights up.
	demo.vitals_flash = max(0, demo.vitals_flash-dt)
	if vitals := card_demo_vitals(r, room); vitals != demo.vitals {
		if demo.stage >= .Effect { demo.vitals_flash = CARD_DEMO_VITALS_FLASH }
		demo.vitals = vitals
	}
}

CARD_DEMO_EFFECT_WORDS :: cstring("L'EFFETTO, CON LE REGOLE DEL GIOCO")
CARD_DEMO_NO_FILM_WORDS :: cstring("NESSUNA PROVA PER QUESTA CARTA")

// Every caption a film shows: what the glove does as it plays the card, what
// the player does after it, the effect at work, or no film at all. The smoke
// holds each one on its plate, with its key's cap.
Card_Demo_Words :: enum u8 {
	Double_Click, Drag_To_Player, Drag_To_Foe, Drag_To_Cell, Drag_To_Foe_In_Line, Drag_In_Line, Drag_Rod,
	Step, Bump, Shadow_Step, Wait, Shoot, Activate, Fire, Turn, Effect, No_Film,
}

@(rodata)
CARD_DEMO_WORDS := [Card_Demo_Words]cstring{
	.Double_Click = "DOPPIO CLIC SULLA CARTA",
	.Drag_To_Player = "TRASCINA LA CARTA SU DI TE",
	.Drag_To_Foe = "TRASCINA LA CARTA SUL NEMICO",
	.Drag_To_Cell = "TRASCINA LA CARTA SU UNA CASELLA",
	.Drag_To_Foe_In_Line = "TRASCINA SUL NEMICO IN LINEA RETTA",
	.Drag_In_Line = "TRASCINA LA CARTA IN LINEA RETTA",
	.Drag_Rod = "TRASCINA LA CANNA SU UNA CASELLA",
	.Step = "UN PASSO",
	.Bump = "COLPISCI IL NEMICO",
	.Shadow_Step = "UN PASSO NELL'OMBRA",
	.Wait = "ASPETTI UN TEMPO",
	.Shoot = "+ CLIC SUL NEMICO: FRECCIA",
	.Activate = "CLIC SU ATTIVA: SCARICA LE TESLA",
	.Fire = "TIENI PREMUTO IL CLIC: SPARI",
	.Turn = "MUOVI IL MOUSE: GIRI LA VISTA",
	.Effect = CARD_DEMO_EFFECT_WORDS,
	.No_Film = CARD_DEMO_NO_FILM_WORDS,
}

// The key each caption's cap shows (nil: the mouse alone). A step's is the
// one of its way (CARD_DEMO_STEP_KEYS), each a letter, one cap as wide.
@(rodata)
CARD_DEMO_WORDS_KEY := #partial [Card_Demo_Words]cstring{
	.Step = "W", .Bump = "W", .Shadow_Step = "W", .Wait = "SPAZIO", .Shoot = "CTRL",
}

// The step keys, in game.MOVEMENT_KEY_DIRECTIONS's order.
@(rodata)
CARD_DEMO_STEP_KEYS := [4]cstring{"W", "D", "S", "A"}

// The words of the scene's action `index`: the key it presses (nil for the
// mouse alone) and what it does.
card_demo_action_words :: proc(demo: ^Card_Demo, index: int) -> (key, text: cstring) {
	if index < 0 || index >= demo.scene.action_count { return }
	action := demo.scene.actions[index]
	room := &demo.room
	words: Card_Demo_Words
	switch action.kind {
	case .None: return
	case .Step:
		origin := game.tactical_view_origin(room) if game.tactical_shadow_active(room) else room.player.position
		_, bump := game.enemy_index_at(room, game.add_position(origin, game.direction_offset(action.direction)))
		words = .Step
		if bump { words = .Bump }
		if game.tactical_shadow_active(room) { words = .Shadow_Step }
		for way, at in game.MOVEMENT_KEY_DIRECTIONS { if way == action.direction { key = CARD_DEMO_STEP_KEYS[at] } }
		return key, CARD_DEMO_WORDS[words]
	case .Wait: words = .Wait
	case .Shoot: words = .Shoot
	case .Activate: words = .Activate
	case .Fire:
		words = .Fire
		if demo.acting && index == demo.next_action && demo.firing <= 0 { words = .Turn }
	}
	return CARD_DEMO_WORDS_KEY[words], CARD_DEMO_WORDS[words]
}

// How much of the glove shows: all of it while it plays the card and while it
// works an action of its own (an arrow's click, ATTIVA), then fading where it
// let go; nothing the rest of the time.
card_demo_glove_alpha :: proc(demo: ^Card_Demo) -> f32 {
	if demo.stage < .Effect { return 1 }
	if demo.acting {
		kind := demo.scene.actions[demo.next_action].kind
		return 1 if kind == .Shoot || kind == .Activate else 0
	}
	if demo.next_action == 0 { return max(0, 1-demo.effect_time/CARD_DEMO_GLOVE_FADE) }
	if demo.done_by_glove && demo.since_action >= 0 { return max(0, 1-demo.since_action/CARD_DEMO_GLOVE_FADE) }
	return 0
}

// The words of what the glove does as the take plays the card.
card_demo_gesture_words :: proc(demo: ^Card_Demo) -> cstring {
	scene := &demo.scene
	words: Card_Demo_Words
	switch scene.gesture {
	case .Double_Click: words = .Double_Click
	case .Drag_To_Player: words = .Drag_To_Player
	case .Drag_To_Foe: words = .Drag_To_Foe
	case .Drag_To_Cell: words = .Drag_To_Cell
	case .Drag_Along_Line:
		words = .Drag_In_Line
		if scene.target_foe < scene.foe_count && scene.foes[scene.target_foe].at == scene.target { words = .Drag_To_Foe_In_Line }
	case .Rod_Slot: words = .Drag_Rod
	}
	return CARD_DEMO_WORDS[words]
}

// The caption now: the key its cap shows (nil for the mouse alone) and its words.
card_demo_caption_words :: proc(demo: ^Card_Demo) -> (key, text: cstring) {
	if demo == nil { return }
	if demo.failed || !demo.built { return nil, CARD_DEMO_NO_FILM_WORDS }
	if demo.stage < .Effect { return nil, card_demo_gesture_words(demo) }
	scene := &demo.scene
	if demo.next_action < scene.action_count && demo.free_time >= 0 &&
	   (demo.acting || demo.free_time >= scene.actions[demo.next_action].after-CARD_DEMO_CAPTION_BEFORE) {
		return card_demo_action_words(demo, demo.next_action)
	}
	if demo.done_text != nil && demo.since_action >= 0 && demo.since_action < CARD_DEMO_CAPTION_AFTER { return demo.done_key, demo.done_text }
	return nil, CARD_DEMO_EFFECT_WORDS
}

// The caption now, as one line ("CTRL + CLIC SUL NEMICO: FRECCIA").
card_demo_caption :: proc(demo: ^Card_Demo) -> string {
	key, text := card_demo_caption_words(demo)
	words := string(text)
	if key == nil { return words }
	if len(words) > 0 && words[0] == '+' { return fmt.tprintf("%s %s", key, words) }
	return fmt.tprintf("%s: %s", key, words)
}

// GPU work outside any render target, before card_demo_draw: a roll of the
// take's dice is drawn on the stage's own dice, sized to the stage.
card_demo_prepare :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) {
	if demo == nil { return }
	demo.dice_frame = {}
	if renderer == nil || !demo.built || !rl.IsWindowReady() { return }
	cue, found := render.active_presentation_cue(&renderer.timeline)
	if !found || !cue.started || cue.kind != .Dice_Rolled { return }
	frame := Card_Demo_Dice_Frame{shown = true, roll = cue.event.dice_roll, progress = render.presentation_cue_progress(cue),
		seed = dice_event_visual_seed(cue.event), card = cue.event.card_definition,
		outcome = render.dice_presentation_outcome(&renderer.timeline)}
	demo.dice_view.theme = renderer
	render.update_dice_pool_texture(&demo.dice_view, frame.roll, frame.progress, renderer.canvas_width, renderer.canvas_height, {}, frame.seed)
	demo.dice_frame = frame
}

// The film's hand grows past one card (its card draws or makes cards): the
// caption's plate then stands clear of it (render.card_demo_caption_bounds).
card_demo_hand_grows :: proc(demo: ^Card_Demo) -> bool {
	definition, found := game.card_definition_by_id(demo.card.definition_id)
	if !found { return false }
	for template in definition.effects[:definition.effect_count] {
		if template.kind == .Draw_Cards || template.kind == .Create_Card { return true }
	}
	return false
}

// The caption's plate on the stage now.
card_demo_caption_plate :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> rl.Rectangle {
	if demo == nil || !demo.built { return render.card_demo_caption_bounds(renderer, nil, false) }
	return render.card_demo_caption_bounds(renderer, &demo.room, card_demo_hand_grows(demo))
}

// What of the stage the caption's plate covers now, if anything: a card of
// the hand as the board shows it (the raised one as high as it rises), the
// rod's slot, the board's bar. Its place is chosen clear of them all; the
// tests hold it there.
card_demo_plate_covers :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> cstring {
	if demo == nil || renderer == nil || !demo.built { return nil }
	plate := card_demo_caption_plate(demo, renderer)
	room := &demo.room
	deck, phase := render.renderer_hand_deck(renderer, room)
	if phase == .Combat && deck.combat_active {
		for index in 0..<deck.hand_count {
			if rl.CheckCollisionRecs(plate, render.hand_raised_card_bounds(renderer, index, deck.hand_count)) { return "a card of the hand" }
		}
	}
	if phase == .Loot && rl.CheckCollisionRecs(plate, render.fishing_slot_bounds(renderer)) { return "the rod's slot" }
	if render.card_demo_bar_shown(room) {
		// The traps' line stands over the bar.
		bar := render.m8_active_bar_bounds(renderer, room)
		if rl.CheckCollisionRecs(plate, {bar.x, bar.y-20, bar.width, bar.height+20}) { return "the board's bar" }
	}
	return nil
}

// The whole stage, into the render target bound now (the window's stage,
// renderer.canvas_width by renderer.canvas_height): the board, its HUD's
// plates and the hand as the game draws them, the dice, the glove and the
// caption.
card_demo_draw :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) {
	rl.ClearBackground(render.RESIN_BACKGROUND)
	if demo == nil || renderer == nil { return }
	r := renderer
	if !demo.built || !card_demo_visual(r) {
		_, text := card_demo_caption_words(demo)
		if text != nil { render.draw_card_demo_caption(r, card_demo_caption_plate(demo, r), nil, text) }
		return
	}
	room := &demo.room
	cards := demo.cards
	active := cards.dragged_card_id if cards.dragged_card_id != 0 else cards.selected_card_id
	render.draw_tactical_world(r, room, active)
	render.draw_tactical_status(r, room)
	render.draw_tactical_hand(r, room, cards.hovered_card_id, cards.selected_card_id, cards.dragged_card_id, demo.pointer)
	render.draw_tactical_hud(r, room, false, false)
	if demo.vitals_flash > 0 { render.draw_card_demo_highlight(render.tactical_hud_layout(r).vitals, demo.vitals_flash/CARD_DEMO_VITALS_FLASH) }
	if f := demo.dice_frame; f.shown {
		render.draw_dice_pool_overlay(&demo.dice_view, f.roll, f.progress, r.canvas_width, r.canvas_height, {}, f.seed, f.card, f.outcome)
	}
	// Behind the player's eyes the pointer is the view's: no glove.
	if alpha := card_demo_glove_alpha(demo); alpha > 0 && !render.first_person_owns_pointer(r, room) {
		if demo.click_age >= 0 { render.draw_card_demo_click(demo.pointer, demo.click_age/CARD_DEMO_CLICK_SECONDS) }
		render.draw_card_demo_glove(demo.pointer, .Grab if demo.grabbing else .Point, alpha)
	}
	key, text := card_demo_caption_words(demo)
	render.draw_card_demo_caption(r, card_demo_caption_plate(demo, r), key, text)
	// Between two takes the stage goes dark a moment.
	dark := f32(0)
	if demo.stage == .Settle { dark = 1-demo.stage_time/CARD_DEMO_FADE }
	if demo.stage == .Hold { dark = (demo.stage_time-(CARD_DEMO_HOLD-CARD_DEMO_FADE))/CARD_DEMO_FADE }
	if demo.stage == .Done { dark = 1 }
	render.draw_card_demo_fade(r, dark)
}

// What the take showed of what its card promises (game.card_demo_expected_events),
// with the ground and the AK's hits: the events missing, and whether all is shown.
card_demo_shown :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> (missing: bit_set[game.Game_Event_Kind], ok: bool) {
	id := demo.card.definition_id
	expected, hurt := game.card_demo_expected_events(id, demo.card.upgrade_level)
	missing = expected-renderer.shown_events
	ok = demo.played && card(missing) == 0 && card_demo_foes_hurt(demo) >= hurt
	switch game.card_demo_ground_expected(id) {
	case .None:
	case .Pool: ok = ok && demo.pooled
	case .Fire: ok = ok && demo.burned
	}
	if game.card_demo_counts_shots(id) { ok = ok && demo.fps_hits > 0 }
	return
}

// How many of the scene's foes have lost life (or fallen) by now.
card_demo_foes_hurt :: proc(demo: ^Card_Demo) -> (hurt: int) {
	for foe, index in demo.scene.foes[:demo.scene.foe_count] {
		at, alive := game.enemy_index_by_id(&demo.room, u32(index+1))
		if !alive || demo.room.enemies[at].health < foe.health { hurt += 1 }
	}
	return
}
