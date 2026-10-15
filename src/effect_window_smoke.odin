package main

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import app "app"
import host "engine/host"
import game "game"
import grid "grid"
import render "render"
import view "view"

// --smoke-effect-window: MOSTRA EFFETTO in the real window, from each of its
// entries on the session's own run, then every card's film through it (the
// one smoke of the films: they are filmed as the player sees them).
//
// First the frame's cost in the first room: its board alone, uncapped; then
// the window open over it at the game's 60 frames a second, over some of the
// heaviest films (each frame's wall time, those that missed their turn, the
// longest, and the opening's own time). Then, in the first room, the card
// inspector (a card under the mouse, its key; then a card chosen, its button,
// dimmed and asking for nothing while Movimento Ombra holds the board) and
// the sheet's MAZZO (a line chosen on its second page, the window over the
// sheet, Esc closing the window alone), the Canna da Pesca's slot once the
// room is cleared, the reward's cards, the shop's offers and its owned card
// chosen, the rest's owned card chosen. Each entry is filmed with its button
// (odin_pp_effect_entry_*.png), then the window opened from it
// (odin_pp_effect_window_*_NN.png). While the window is open the run must not
// move, the scene's frame being the window's; once it closes the run's first
// frame takes no time. Then the window at other sizes
// (odin_pp_effect_scale_*.png; at 1280x720 the stage is 960x540 window pixels,
// 1:1).
//
// Then every card's film, at its first upgrade and its last: one whole take
// of each through the window, from its first frame to its end, as the host
// makes the frames (the scene's update, the canvas, the window's pass), each a
// sixtieth of a second of the film, uncapped. Its stage is saved at its
// moments, its own pixels as the window shows them 1:1
// (odin_pp_effect_film_<Card>_<level>_NN.png: the glove on the card, on its
// way (the card chosen, for a double click), on its target; then the effect
// every 0.6 s, every 1.5 s from its eighth second; the take held at its end),
// and the whole window once, the glove on its target
// (odin_pp_effect_film_<Card>_<level>_window.png). Each take must show what
// its card promises (card_demo_shown) within its time, with no timeline
// failure, and leave the run as it was; at every frame its caption says
// something and holds on its plate as it is, in the game's font, the plate
// covers nothing of the board's (card_demo_plate_covers), the glove stays on
// the stage, and the film's board queues no sound (outside PROVA MECCANICHE
// it is silent); one STRIKE take with the run's lab flag on plays the lab's
// sounds through the window first. The cursor is never hidden (the FIRST
// PERSON SHOOTER's view turns by script). -define:EFFECT_SMOKE_CARDS=,A,B,
// films only those cards; --flat films them on a flat board.
//
// Last, every new word in the room it is drawn in, in the game's font, whole
// (every caption of the films' table on its plate too), and the films' frame
// cost, uncapped (its mean, its 95th and 99th hundredth, its worst, the
// longest opening).

EFFECT_SMOKE_FRAMES :: 72
EFFECT_SMOKE_CARDS :: #config(EFFECT_SMOKE_CARDS, "")
// A frame at the game's 60 frames a second.
EFFECT_SMOKE_FRAME_MS :: f64(1000.0/60.0)
// Stage frames saved of a take at most: the longest (the AK's at its top, 33 s)
// to its end.
EFFECT_SMOKE_TAKE_SHOTS :: 40

Effect_Smoke :: struct {
	rs: ^Roguelike_Session,
	commands: host.Commands,
	pointer: view.Vec2,
	failures: int,
	// Every film frame's cost (ms), and the worst one's take; the longest
	// opening (ms) and its film.
	costs: [dynamic]f64,
	worst: f64,
	worst_card: game.Card_Id,
	worst_level: i32,
	worst_at: f32,
	opening: f64,
	opening_card: game.Card_Id,
	opening_level: i32,
	films, stills: int,
}

// What must not move while the window is open.
Effect_Smoke_Run :: struct {
	phase: game.Run_Phase,
	gold, health, energy: i32,
	owned_count, hand_count: int,
	owned: [game.MAX_OWNED_CARDS]game.Card_Instance,
	position: grid.Position,
	room_phase: game.Room_Phase,
	pulse: u64,
	remaining: f32,
	events, enemy_count: int,
	enemy_health: [game.MAX_ENEMIES_PER_ROOM]i32,
	sold: [game.SHOP_CARD_OFFER_COUNT]bool,
	timeline_head, timeline_count: int,
	sprites: f64,
}

effect_smoke_run :: proc(rs: ^Roguelike_Session) -> (run: Effect_Smoke_Run) {
	player := &rs.run_state.player
	run.phase, run.gold, run.health, run.energy = rs.run_state.phase, player.gold, player.health, player.deck.energy
	run.owned_count, run.hand_count, run.owned = player.deck.owned_count, player.deck.hand_count, player.deck.owned
	run.position, run.room_phase, run.pulse = player.position, rs.room.phase, rs.room.pulse_count
	run.remaining, run.events, run.enemy_count = player.tactical.remaining, rs.room.recent_events.count, len(rs.room.enemies)
	for enemy, index in rs.room.enemies[:min(len(rs.room.enemies), len(run.enemy_health))] { run.enemy_health[index] = enemy.health }
	for offer, index in rs.run_state.shop.offers[:min(rs.run_state.shop.offer_count, len(run.sold))] { run.sold[index] = offer.sold }
	run.timeline_head, run.timeline_count = rs.iso_renderer.timeline.head, rs.iso_renderer.timeline.count
	run.sprites = rs.iso_renderer.sprite_assets.elapsed
	return
}

effect_smoke_frame_for :: proc(s: ^Effect_Smoke) -> host.Frame {
	window := s.rs.window
	return {dt = 1.0/60.0, canvas = {0, 0, f32(window.config.canvas_width), f32(window.config.canvas_height)},
		mouse = {s.pointer.x, s.pointer.y}, mouse_inside = true, focused = true, visible = true, window_focused = true,
		window = window, commands = &s.commands}
}

Effect_Smoke_Pass :: struct {
	rs: ^Roguelike_Session,
	frame: ^host.Frame,
}

effect_smoke_window_pass :: proc(window: ^app.Window, data: rawptr) {
	pass := cast(^Effect_Smoke_Pass)data
	roguelike_draw_window(pass.rs, pass.frame)
}

// The room as the scene draws it (roguelike_draw's board, never its pause
// veil: the smoke's window may be in the background).
effect_smoke_draw_room :: proc(s: ^Effect_Smoke) {
	rs := s.rs
	r := &rs.iso_renderer
	cards := rs.card_interaction
	render.update_tactical_view(r, &rs.room, s.pointer, false, true)
	render.tactical_hud_pointer(r, s.pointer, true)
	render.draw_tactical_world(r, &rs.room, active_targeting_card_id(cards))
	render.draw_status(r, &rs.room, rs.window.scale_mode)
	render.draw_relic_bar(r, &rs.room, s.pointer, true, cards.hovered_card_id if cards.hovered_card_id != 0 else cards.selected_card_id)
	render.draw_hand(r, &rs.room, cards.hovered_card_id, cards.selected_card_id, cards.dragged_card_id, s.pointer)
	render.draw_tactical_hud(r, &rs.room, false, false)
	if rs.m8_session.character_open { render.draw_m8_character_panel(r, &rs.room, rs.m8_session.sheet) }
}

// One frame as the host makes it: the scene's update (with the window open,
// its gate; in a room with it closed, none: the room would run on), the
// canvas, then the window's pass. The run's screens see the smoke's mouse
// over their buttons as a focused window would (the smoke's window may be in
// the background: its update then takes the mouse for outside).
effect_smoke_frame :: proc(s: ^Effect_Smoke, update := true) {
	rs := s.rs
	app.refresh_viewport(rs.window)
	frame := effect_smoke_frame_for(s)
	in_room := rs.run_state.phase == .In_Room && !game.run_has_relic_choice(&rs.run_state)
	if rs.effect_window.open || (update && !in_room) { roguelike_update(rs, &frame) }
	if !rs.effect_window.open && !in_room { render.tactical_hud_pointer(&rs.iso_renderer, s.pointer, true) }
	app.begin_canvas(rs.window, render.CANVAS_BACKGROUND)
	if !rs.effect_window.open && in_room { effect_smoke_draw_room(s) } else { roguelike_draw(rs, &frame) }
	pass := Effect_Smoke_Pass{rs = rs, frame = &frame}
	app.present(rs.window, render.LETTERBOX_COLOR, effect_smoke_window_pass, &pass)
	if rl.IsCursorHidden() { fmt.eprintln("effect window smoke: the cursor is hidden"); s.failures += 1 }
	free_all(context.temp_allocator)
}

effect_smoke_frames :: proc(s: ^Effect_Smoke, count: int, update := true) {
	for _ in 0..<count { effect_smoke_frame(s, update) }
}

effect_smoke_center :: proc(bounds: rl.Rectangle) -> view.Vec2 {
	return {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
}

effect_smoke_fail :: proc(s: ^Effect_Smoke, message: string, args: ..any) {
	fmt.eprintf("effect window smoke: ")
	fmt.eprintf(message, ..args)
	fmt.eprintln()
	s.failures += 1
}

// The scene's input to the sheet and the inspector (update_m8_session's,
// given): a click at `point`, or the I key.
effect_smoke_m8 :: proc(s: ^Effect_Smoke, point: view.Vec2, pressed, inspect: bool) {
	rs := s.rs
	s.pointer = point
	input := M8_Session_Input{focused = true, inside = true, mouse = point, pressed = pressed, inspect = inspect}
	_ = step_m8_session(&rs.m8_session, &rs.room, &rs.iso_renderer, &rs.tactical_controller, &rs.card_interaction,
		&rs.gameplay_buffer, true, 1.0/60.0, input)
	if roguelike_take_effect_request(rs) {}
}

// How the smoke closes the window.
Effect_Smoke_Close :: enum u8 {Chiudi, Escape, Right_Click}

// The window just opened: its frames filmed, the run still meanwhile; then
// closed by `close`. Returns whether it was open.
effect_smoke_film :: proc(s: ^Effect_Smoke, name: string, close: Effect_Smoke_Close) -> bool {
	rs := s.rs
	w := &rs.effect_window
	if !w.open { effect_smoke_fail(s, "%s: the window did not open (%v)", name, effect_window_refusal(rs)); return false }
	if w.stage.id == 0 || w.stage.texture.width != EFFECT_STAGE_WIDTH || w.stage.texture.height != EFFECT_STAGE_HEIGHT {
		effect_smoke_fail(s, "%s: no 960x540 stage", name)
	}
	before := effect_smoke_run(rs)
	s.pointer = effect_smoke_center(effect_window_stage_bounds(rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height))
	shot := 0
	for frame in 0..<EFFECT_SMOKE_FRAMES {
		effect_smoke_frame(s)
		if frame%24 == 2 {
			rl.TakeScreenshot(fmt.ctprintf("odin_pp_effect_window_%s_%02d.png", name, shot))
			shot += 1
		}
	}
	fmt.printf("effect window %s: %v %v +%d, %.2fs of film, caption \"%s\"\n", name, w.source, w.card.definition_id, w.card.upgrade_level,
		w.film_time, effect_window_caption(w))
	if w.film_time < f32(EFFECT_SMOKE_FRAMES-1)/60 { effect_smoke_fail(s, "%s: the film ran %.2fs", name, w.film_time) }
	if after := effect_smoke_run(rs); after != before { effect_smoke_fail(s, "%s: the run moved while the window was open", name) }
	// Closed, CHIUDI under the mouse first so that it shows lit.
	width, height := rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height
	input := Effect_Window_Input{focused = true, inside = true, mouse = effect_smoke_center(effect_window_close_bounds(width, height))}
	s.pointer = input.mouse
	effect_smoke_frames(s, 2)
	rl.TakeScreenshot(fmt.ctprintf("odin_pp_effect_window_%s_close.png", name))
	switch close {
	case .Chiudi: input.pressed = true
	case .Escape: input.escape = true
	case .Right_Click: input.right_pressed = true
	}
	step_effect_window_in_run(rs, input, 1.0/60.0)
	if w.open || w.film != nil || w.renderer != nil { effect_smoke_fail(s, "%s: the window did not close", name) }
	if rs.tactical_controller.was_focused || rs.iso_renderer.frame_clock_valid || rs.card_interaction != {} {
		effect_smoke_fail(s, "%s: the run resumes with input or time held", name)
	}
	// The run's first frame back takes no time and no click.
	effect_smoke_frame(s)
	if after := effect_smoke_run(rs); after.pulse != before.pulse || after.remaining != before.remaining || after.phase != before.phase ||
	   after.owned_count != before.owned_count || after.gold != before.gold {
		effect_smoke_fail(s, "%s: the run's first frame back moved it", name)
	}
	return true
}

// Holds every foe of the room where it stands: the smoke's minutes never
// bring a blow.
effect_smoke_hold_foes :: proc(room: ^game.Room) {
	for &enemy in room.enemies {
		enemy.recovery_pulses = 99
		enemy.intent, enemy.tactical_cooldown = {}, 0
	}
	game.plan_enemy_intents(room)
}

// Every new word in the room it is drawn in, in the game's font, whole (the
// films' captions are held on their plates frame by frame, effect_smoke_take).
effect_smoke_words :: proc(s: ^Effect_Smoke) {
	r := &s.rs.iso_renderer
	width, height := r.canvas_width, r.canvas_height
	Words :: struct { what: string, text: cstring, room: f32, size: int }
	// hud_button's room for its label, with a key's cap and without.
	key_room :: proc(r: ^render.Renderer, bounds: rl.Rectangle, key: cstring) -> f32 {
		return bounds.width-(4+max(f32(20), render.gothic_text_width(r, key, 12)+8)+7)-6
	}
	plain_room :: proc(bounds: rl.Rectangle) -> f32 { return bounds.width-13 }
	layout := render.character_sheet_deck_layout(r, &s.rs.room, 0)
	words := [?]Words{
		{"reward button", render.EFFECT_ENTRY_LABEL, plain_room(render.reward_effect_bounds(width, height, 0, game.CARD_REWARD_CHOICE_COUNT)), 14},
		{"shop offer button", render.EFFECT_ENTRY_LABEL, plain_room(render.shop_offer_effect_bounds(width, height, 0)), 14},
		{"sheet button", render.EFFECT_ENTRY_LABEL, key_room(r, layout.button, render.EFFECT_ENTRY_KEY), 14},
		{"inspector button", render.EFFECT_ENTRY_LABEL, key_room(r, render.tactical_inspector_effect_bounds(), render.EFFECT_ENTRY_KEY), 14},
		{"inspector hint", render.EFFECT_ENTRY_LABEL, render.effect_entry_label_bounds(render.tactical_inspector_effect_bounds(), true).width, 14},
		{"window subtitle", EFFECT_WINDOW_SUBTITLE, effect_window_subtitle_bounds(width, height).width, 10},
		{"CHIUDI", "CHIUDI", key_room(r, effect_window_close_bounds(width, height), "ESC"), 14},
		{"RICOMINCIA", "RICOMINCIA", key_room(r, effect_window_restart_bounds(width, height), "R"), 14},
		{"no film", EFFECT_WINDOW_NO_FILM, f32(EFFECT_STAGE_WIDTH)-40, 18},
		{"sheet pager", fmt.ctprintf("%d/%d", game.MAX_OWNED_CARDS, game.MAX_OWNED_CARDS), layout.next.x-(layout.previous.x+layout.previous.width)-8, 10},
	}
	for words in words {
		if _, _, _, fit := render.gothic_text_fit_plan(r, words.text, words.room, words.size); fit != .Fits {
			effect_smoke_fail(s, "%s \"%s\" does not fit %.0f px at %d (%v)", words.what, words.text, words.room, words.size, fit)
		}
	}
	// The owned card's button is one of the controls row's (draw_shop_button:
	// its words at 13, centred inside its frame), unfitted: they must fit.
	owned := render.owned_card_effect_bounds(width, height)
	if label := f32(render.menu_measure_text(r, render.EFFECT_ENTRY_OWNED_LABEL, 13)); label > owned.width-16 {
		effect_smoke_fail(s, "owned card button \"%s\" is %.0f px in %.0f", render.EFFECT_ENTRY_OWNED_LABEL, label, owned.width-16)
	}
	// The sheet's MAZZO head: its title, at its fullest, ends before the button.
	if title_end := layout.section.x+12+render.gothic_text_width(r, fmt.ctprintf("MAZZO / %d", game.MAX_OWNED_CARDS), 12); title_end+8 > layout.button.x {
		effect_smoke_fail(s, "the sheet's MAZZO title ends at %.0f, under its button at %.0f", title_end, layout.button.x)
	}
	// Every caption a film shows, on its plate low and high, after its key's
	// cap (the takes hold each one shown on its plate as it is, frame by frame).
	for words in Card_Demo_Words {
		key, text := CARD_DEMO_WORDS_KEY[words], CARD_DEMO_WORDS[words]
		for high in ([2]bool{false, true}) {
			room := render.card_demo_caption_text_bounds(r, render.card_demo_caption_bounds(r, nil, high), key).width
			if _, _, _, fit := render.gothic_text_fit_plan(r, text, room, render.CARD_DEMO_CAPTION_SIZE); fit != .Fits {
				effect_smoke_fail(s, "caption %v \"%s\" does not fit %.0f px at %d (%v)", words, text, room, render.CARD_DEMO_CAPTION_SIZE, fit)
			}
		}
	}
	// Every card at its first upgrade and its last: its title in the window's
	// head, and its line in the sheet's MAZZO as many times over as a deck holds.
	title := effect_window_title_bounds(width, height)
	line := render.character_sheet_deck_row_bounds(&layout, 0).width-10
	for id in game.Card_Id {
		if id == .Count { continue }
		definition, _ := game.card_definition_by_id(id, true)
		for level in ([2]i32{0, game.card_max_upgrade_level(id)}) {
			card := game.Card_Instance{id = 1, definition_id = id, upgrade_level = level}
			if _, _, _, fit := render.gothic_text_fit_plan(r, render.tactical_card_title(card, definition), title.width, 24); fit != .Fits {
				effect_smoke_fail(s, "title \"%s\" does not fit %.0f px (%v)", render.tactical_card_title(card, definition), title.width, fit)
			}
			text := render.character_sheet_deck_row_text({card = card, count = game.MAX_OWNED_CARDS})
			if _, _, _, fit := render.gothic_text_fit_plan(r, text, line, 12); fit != .Fits {
				effect_smoke_fail(s, "sheet line \"%s\" does not fit %.0f px (%v)", text, line, fit)
			}
		}
	}
}

// The moments of a take its stage is saved at (run_effect_window_smoke's films).
Effect_Smoke_Shots :: struct {
	reach, carry, target, held: bool,
	next: f32,
	count: int,
}

// `aimed`: the moment the glove stands on its target (for a double click, the
// card chosen before its second click), filmed as the whole window too.
effect_smoke_shot_due :: proc(film: ^Card_Demo, shots: ^Effect_Smoke_Shots) -> (due, aimed: bool) {
	if shots.count >= EFFECT_SMOKE_TAKE_SHOTS { return }
	#partial switch film.stage {
	case .Press:
		// The glove on the card; then, for a double click, the card chosen.
		if !shots.reach { shots.reach, due = true, true }
		else if film.scene.gesture == .Double_Click && !shots.target && film.stage_time >= CARD_DEMO_CLICK_GAP*0.6 {
			shots.target, due, aimed = true, true, true
		}
	case .Carry:
		if !shots.carry && film.stage_time >= CARD_DEMO_CARRY*0.5 { shots.carry, due = true, true }
	case .Hover:
		if !shots.target && film.stage_time >= CARD_DEMO_HOVER*0.5 { shots.target, due, aimed = true, true, true }
	case .Effect:
		if shots.next == 0 { shots.next = 0.3 }
		if film.effect_time >= shots.next {
			shots.next += 0.6 if film.effect_time < 8 else 1.5
			due = true
		}
	case .Hold:
		if !shots.held && film.stage_time >= 0.4 { shots.held, due = true, true }
	}
	if due { shots.count += 1 }
	return
}

// The stage as the window shows it now (1:1 at 1280x720), to a PNG of its own
// size, opaque as its blit is.
effect_smoke_save_stage :: proc(w: ^Effect_Window, name: cstring) {
	image := rl.LoadImageFromTexture(w.stage.texture)
	defer rl.UnloadImage(image)
	rl.ImageFlipVertical(&image)
	rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8)
	_ = rl.ExportImage(image, name)
}

// One whole take of `id` at `level` through the window (run_effect_window_smoke's
// films), filmed at its moments and held to what its card promises.
effect_smoke_take :: proc(s: ^Effect_Smoke, id: game.Card_Id, level: i32) {
	rs := s.rs
	w := &rs.effect_window
	definition, _ := game.card_definition_by_id(id, true)
	card := game.Card_Instance{id = 1, definition_id = id, upgrade_level = level, lifetime = .Combat if definition.temporary_only else .Permanent}
	opened := time.now()
	if !open_effect_window_in_run(rs, card, .None) { effect_smoke_fail(s, "%v +%d: the window did not open (%v)", id, level, effect_window_refusal(rs)); return }
	if opening := time.duration_milliseconds(time.since(opened)); opening > s.opening {
		s.opening, s.opening_card, s.opening_level = opening, id, level
	}
	defer step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	if !w.film_ready { effect_smoke_fail(s, "%v +%d: no film", id, level); return }
	before := effect_smoke_run(rs)
	s.pointer = effect_smoke_center(effect_window_stage_bounds(rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height))
	shots: Effect_Smoke_Shots
	misfit, covered: cstring
	covered_at: f32
	mute, lost_glove, windowed := false, false, false
	frames, slow := 0, 0
	total, worst: f64
	worst_at: f32
	for w.open && w.film_ready && w.film.stage != .Done && w.film_time < 45 {
		started := time.now()
		effect_smoke_frame(s)
		cost := time.duration_milliseconds(time.since(started))
		if !w.open || !w.film_ready { break }
		film, r := w.film, w.renderer
		append(&s.costs, cost)
		frames, total = frames+1, total+cost
		if cost > worst { worst, worst_at = cost, film.take_time }
		if cost > EFFECT_SMOKE_FRAME_MS { slow += 1 }
		if cost > s.worst { s.worst, s.worst_card, s.worst_level, s.worst_at = cost, id, level, film.take_time }
		key, text := card_demo_caption_words(film)
		if text == nil || text == "" { mute = true }
		else if misfit == nil {
			bounds := render.card_demo_caption_text_bounds(r, card_demo_caption_plate(film, r), key)
			if _, _, _, fit := render.gothic_text_fit_plan(r, text, bounds.width, render.CARD_DEMO_CAPTION_SIZE); fit != .Fits { misfit = text }
		}
		if covered == nil { covered, covered_at = card_demo_plate_covers(film, r), film.take_time }
		if card_demo_glove_alpha(film) > 0 && !render.first_person_owns_pointer(r, &film.room) {
			g := render.card_demo_glove_bounds(film.pointer, .Grab if film.grabbing else .Point)
			if g.x < 0 || g.y < 0 || g.x+g.width > r.canvas_width || g.y+g.height > r.canvas_height { lost_glove = true }
		}
		if due, aimed := effect_smoke_shot_due(film, &shots); due {
			effect_smoke_save_stage(w, fmt.ctprintf("odin_pp_effect_film_%v_%d_%02d.png", id, level, shots.count-1))
			s.stills += 1
			if aimed {
				rl.TakeScreenshot(fmt.ctprintf("odin_pp_effect_film_%v_%d_window.png", id, level))
				windowed = true
			}
		}
	}
	if !w.open || !w.film_ready { effect_smoke_fail(s, "%v +%d: the film was lost", id, level); return }
	film, r := w.film, w.renderer
	missing, shown := card_demo_shown(film, r)
	down := film.scene.foe_count-len(film.room.enemies)
	fmt.printf("effect window film %v +%d: %.1f s, shown %v, missing %v, foes hurt %d (down %d), timeline failures %d, %d stills; frames %.2f ms mean, worst %.2f ms at %.2f s, %d of %d over %.1f ms\n",
		id, level, film.take_time, shown, missing, card_demo_foes_hurt(film), down, r.timeline.update_failures, shots.count,
		total/f64(max(frames, 1)), worst, worst_at, slow, frames, EFFECT_SMOKE_FRAME_MS)
	if !shown || film.stage != .Done || film.take_time >= CARD_DEMO_TAKE_LIMIT || r.timeline.update_failures != 0 {
		effect_smoke_fail(s, "%v +%d: its card's effect was not shown", id, level)
	}
	// Outside PROVA MECCANICHE the film's board queues no sound at all.
	if r.tactical.lab_sounds != nil { effect_smoke_fail(s, "%v +%d: the film queued sounds outside the lab", id, level) }
	if mute { effect_smoke_fail(s, "%v +%d: a frame with no caption", id, level) }
	if misfit != nil { effect_smoke_fail(s, "%v +%d: the caption \"%s\" does not hold on its plate", id, level, misfit) }
	if covered != nil { effect_smoke_fail(s, "%v +%d: the caption's plate covers %s at %.2f s", id, level, covered, covered_at) }
	if lost_glove { effect_smoke_fail(s, "%v +%d: the glove left the stage", id, level) }
	if !windowed { effect_smoke_fail(s, "%v +%d: no frame of the glove on its target", id, level) }
	if after := effect_smoke_run(rs); after != before { effect_smoke_fail(s, "%v +%d: the run moved while the window was open", id, level) }
	s.films += 1
}

// The frame's cost in the room: its board alone, uncapped and without vsync;
// then the window open over it as a player sees it, at the game's 60 frames a
// second, over some of the heaviest films (the first one past its take's end
// into the next take): each frame's wall time, the frames that missed their
// turn (half a frame late or more) and the longest; and the opening's own
// time (the film's room built, its first frame drawn). More than one frame in
// fifty missed fails it.
effect_smoke_cost :: proc(s: ^Effect_Smoke) {
	rs := s.rs
	board: f64
	{
		rl.SetTargetFPS(0)
		rl.ClearWindowState({.VSYNC_HINT})
		defer {
			rl.SetWindowState({.VSYNC_HINT})
			rl.SetTargetFPS(i32(rs.window.config.target_fps))
		}
		started := time.now()
		effect_smoke_frames(s, 120, false)
		board = time.duration_milliseconds(time.since(started))/120
	}
	fmt.printf("effect window cost: %.2f ms a frame for the room's board alone (uncapped)\n", board)
	Paced :: struct { id: game.Card_Id, seconds: f32 }
	paced := [?]Paced{{.Strike, 9}, {.Pinball, 8}, {.Wildfire, 8}, {.First_Person, 8}}
	all_frames, all_missed := 0, 0
	for film in paced {
		opened := time.now()
		if !open_effect_window_in_run(rs, {id = 1, definition_id = film.id, lifetime = .Permanent}, .None) {
			effect_smoke_fail(s, "cost: the window did not open on %v", film.id)
			continue
		}
		opening := time.duration_milliseconds(time.since(opened))
		last := time.now()
		frames, missed := 0, 0
		sum, longest: f64
		longest_at: f32
		for rs.effect_window.open && rs.effect_window.film_time < film.seconds {
			effect_smoke_frame(s)
			now := time.now()
			interval := time.duration_milliseconds(time.diff(last, now))
			last = now
			frames, sum = frames+1, sum+interval
			if interval > longest { longest, longest_at = interval, rs.effect_window.film_time }
			if interval > EFFECT_SMOKE_FRAME_MS*1.5 { missed += 1 }
		}
		takes := rs.effect_window.film.takes if rs.effect_window.film != nil else 0
		step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
		fmt.printf("effect window cost %v at %d fps: opened in %.2f ms; %d frames (%d takes), %.2f ms a frame, the longest %.2f ms at %.2f s, %d missed their turn\n",
			film.id, rs.window.config.target_fps, opening, frames, takes, sum/f64(max(frames, 1)), longest, longest_at, missed)
		all_frames, all_missed = all_frames+frames, all_missed+missed
	}
	if all_missed*50 > all_frames {
		effect_smoke_fail(s, "cost: %d of %d frames missed their turn at %d fps", all_missed, all_frames, rs.window.config.target_fps)
	}
}

// In PROVA MECCANICHE the film's board is the lab's (its renderer takes the
// run's lab flag): a take of the STRIKE through the window queues the lab's
// sounds and the window plays them (effect_window_film_sounds; the smoke has
// no audio bank, so they are played silently), its card's own among them.
effect_smoke_lab_sounds :: proc(s: ^Effect_Smoke) {
	rs := s.rs
	lab, flag, menu := rs.options.mechanics_lab, rs.iso_renderer.tactical.mechanics_lab, rs.iso_renderer.tactical.mechanics_lab_menu
	defer {
		rs.options.mechanics_lab = lab
		rs.iso_renderer.tactical.mechanics_lab, rs.iso_renderer.tactical.mechanics_lab_menu = flag, menu
	}
	rs.options.mechanics_lab = true
	render.set_mechanics_lab(&rs.iso_renderer, true, false)
	w := &rs.effect_window
	if !open_effect_window_in_run(rs, {id = 1, definition_id = .Strike, lifetime = .Permanent}, .None) || !w.film_ready {
		effect_smoke_fail(s, "lab: the window did not open")
		return
	}
	defer step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	for w.open && w.film_ready && w.film.stage != .Done && w.film_time < 45 { effect_smoke_frame(s) }
	if !w.open || !w.film_ready { effect_smoke_fail(s, "lab: the film was lost"); return }
	sounds := w.renderer.tactical.lab_sounds
	card, _ := render.lab_card_sfx(.Strike)
	played, own := 0, 0
	if sounds != nil {
		for count in sounds.played { played += count }
		own = sounds.played[card]
	}
	fmt.printf("effect window lab: the STRIKE's film played %d lab sounds, its card's %d times\n", played, own)
	if !w.renderer.tactical.mechanics_lab || own == 0 || played < 2 { effect_smoke_fail(s, "lab: the film played no lab sound") }
}

// The films' frames, uncapped: their mean, their 95th and 99th hundredth,
// the worst and its take.
effect_smoke_cost_report :: proc(s: ^Effect_Smoke) {
	if len(s.costs) == 0 { return }
	sorted := slice.clone(s.costs[:])
	defer delete(sorted)
	slice.sort(sorted)
	sum: f64
	slow := 0
	for cost in sorted {
		sum += cost
		if cost > EFFECT_SMOKE_FRAME_MS { slow += 1 }
	}
	at :: proc(sorted: []f64, part: f64) -> f64 { return sorted[min(len(sorted)-1, int(f64(len(sorted))*part))] }
	fmt.printf("effect window films: %d frames uncapped, %.2f ms mean, %.2f ms at the 95th hundredth, %.2f at the 99th, worst %.2f ms (%v +%d at %.2f s); %d over %.1f ms; the longest opening %.2f ms (%v +%d)\n",
		len(sorted), sum/f64(len(sorted)), at(sorted, 0.95), at(sorted, 0.99), s.worst, s.worst_card, s.worst_level, s.worst_at, slow, EFFECT_SMOKE_FRAME_MS,
		s.opening, s.opening_card, s.opening_level)
}

run_effect_window_smoke :: proc(rs: ^Roguelike_Session) -> bool {
	if rs == nil || rs.window == nil || !rs.options.tactical.enabled { return false }
	s := Effect_Smoke{rs = rs}
	defer delete(s.costs)
	window := rs.window
	width, height := f32(window.config.canvas_width), f32(window.config.canvas_height)
	r := &rs.iso_renderer
	render.set_living_cards(r, rs.options.scene_3d)
	if game.run_has_relic_choice(&rs.run_state) { game.skip_run_relic(&rs.run_state) }
	if rs.run_state.phase != .In_Room || rs.room.phase != .Combat { fmt.eprintln("effect window smoke: no fight to start in"); return false }

	// The first room: its foes held, a deck of many cards and levels.
	effect_smoke_hold_foes(&rs.room)
	deck := &rs.run_state.player.deck
	game.finish_deck_combat(deck)
	extra := [?]struct{id: game.Card_Id, level: i32}{{.Pinball, 2}, {.Lasso, 1}, {.Poison_Pool, 0}, {.Wildfire, 1}, {.Deflect, 0},
		{.Coffin, 2}, {.Fate_Dice, 1}, {.First_Person, 0}, {.Fishing_Rod, 1}}
	for card in extra {
		if _, added := game.add_owned_card(deck, card.id, card.level); !added { fmt.eprintln("effect window smoke: could not add", card.id); return false }
	}
	if !game.begin_deck_combat(deck) || deck.hand_count < 2 { fmt.eprintln("effect window smoke: no hand"); return false }
	render.clear_event_animations(r)
	render.reset_tactical_orbit(&r.tactical.world_orbit)
	render.frame_level(r, &rs.level_data)
	effect_smoke_frames(&s, 6, false)
	effect_smoke_cost(&s)

	// The inspector: a card under the mouse (the key's hint), I.
	hovered := deck.hand[0]
	rs.card_interaction = {hovered_card_id = hovered.id}
	s.pointer = effect_smoke_center(render.tactical_hand_card_bounds(r, 0, deck.hand_count))
	effect_smoke_frames(&s, 3, false)
	rl.TakeScreenshot("odin_pp_effect_entry_inspector_hover.png")
	if _, effect := render.tactical_inspector_effect(r, &rs.room, hovered.id, 0, 0); effect != .Hint {
		effect_smoke_fail(&s, "inspector: a card under the mouse shows %v", effect)
	}
	effect_smoke_m8(&s, s.pointer, true, false)
	if rs.effect_window.open { effect_smoke_fail(&s, "inspector: a click on the hovered card opened the window") }
	rs.card_interaction = {hovered_card_id = hovered.id}
	effect_smoke_m8(&s, s.pointer, false, true)
	if rs.effect_window.card.id != hovered.id { effect_smoke_fail(&s, "inspector: I showed %v, not the card under the mouse", rs.effect_window.card) }
	effect_smoke_film(&s, "inspector_key", .Escape)

	// A card chosen: its button, lit under the mouse, clicked.
	chosen := deck.hand[1]
	rs.card_interaction = {selected_card_id = chosen.id}
	button := render.tactical_inspector_effect_bounds()
	s.pointer = effect_smoke_center(button)
	effect_smoke_frames(&s, 3, false)
	rl.TakeScreenshot("odin_pp_effect_entry_inspector_chosen.png")
	if !render.tactical_inspector_effect_contains(r, &rs.room, 0, chosen.id, 0, s.pointer) { effect_smoke_fail(&s, "inspector: the button is not there") }
	effect_smoke_m8(&s, s.pointer, true, false)
	if rs.effect_window.card != chosen { effect_smoke_fail(&s, "inspector: the button showed %v, not the card chosen", rs.effect_window.card) }
	effect_smoke_film(&s, "inspector_button", .Chiudi)
	// Movimento Ombra holds the board: the button dimmed, its click and its
	// key asking for nothing.
	phase := rs.run_state.player.tactical.phase
	rs.run_state.player.tactical.phase = .Shadow
	rs.card_interaction = {selected_card_id = chosen.id}
	effect_smoke_frames(&s, 3, false)
	rl.TakeScreenshot("odin_pp_effect_entry_inspector_busy.png")
	effect_smoke_m8(&s, s.pointer, true, false)
	effect_smoke_m8(&s, s.pointer, false, true)
	if rs.effect_window.open { effect_smoke_fail(&s, "inspector: the window opened in Movimento Ombra") }
	rs.run_state.player.tactical.phase = phase
	rs.card_interaction = {}

	// The sheet's MAZZO: its second page, a line chosen, MOSTRA EFFETTO.
	rs.m8_session.character_open, rs.m8_session.sheet = true, {}
	layout := render.character_sheet_deck_layout(r, &rs.room, 0)
	fmt.printf("effect window sheet: %d lines, %d a page, %d pages\n", layout.row_count, layout.per_page, layout.pages)
	if layout.pages < 2 { effect_smoke_fail(&s, "sheet: one page only") }
	effect_smoke_m8(&s, effect_smoke_center(layout.next), true, false)
	layout = render.character_sheet_deck_layout(r, &rs.room, rs.m8_session.sheet.deck_page)
	effect_smoke_m8(&s, effect_smoke_center(render.character_sheet_deck_row_bounds(&layout, 1)), true, false)
	line := layout.rows[rs.m8_session.sheet.deck_selected]
	s.pointer = effect_smoke_center(layout.button)
	effect_smoke_frames(&s, 3, false)
	rl.TakeScreenshot("odin_pp_effect_entry_sheet.png")
	if rs.m8_session.sheet.deck_page != 1 || rs.m8_session.sheet.deck_selected != layout.per_page+1 {
		effect_smoke_fail(&s, "sheet: page %d, line %d chosen", rs.m8_session.sheet.deck_page, rs.m8_session.sheet.deck_selected)
	}
	effect_smoke_m8(&s, s.pointer, true, false)
	if rs.effect_window.card != line.card { effect_smoke_fail(&s, "sheet: showed %v, not the line chosen %v", rs.effect_window.card, line.card) }
	effect_smoke_film(&s, "sheet", .Escape)
	if !rs.m8_session.character_open { effect_smoke_fail(&s, "sheet: Esc closed the sheet as well as the window") }
	effect_smoke_frames(&s, 2, false)
	rl.TakeScreenshot("odin_pp_effect_entry_sheet_after.png")
	rs.m8_session.character_open = false

	// The room cleared: the Canna da Pesca in its slot.
	game.destroy_room(&rs.room)
	room, cleared := game.create_room(&rs.level_data, &rs.run_state.player, {})
	if !cleared { fmt.eprintln("effect window smoke: no cleared room"); return false }
	rs.room = room
	if !game.configure_tactical_room(&rs.room, rs.options.tactical) || !game.fishing_room_open(&rs.room) {
		fmt.eprintln("effect window smoke: the rod's slot is not open"); return false
	}
	render.clear_event_animations(r)
	rod, _ := game.fishing_rod(deck)
	rs.card_interaction = {hovered_card_id = rod.id}
	s.pointer = effect_smoke_center(render.fishing_slot_bounds(r))
	effect_smoke_frames(&s, 4, false)
	rl.TakeScreenshot("odin_pp_effect_entry_rod_hover.png")
	rs.card_interaction = {selected_card_id = rod.id}
	s.pointer = effect_smoke_center(render.tactical_inspector_effect_bounds())
	effect_smoke_frames(&s, 3, false)
	rl.TakeScreenshot("odin_pp_effect_entry_rod_chosen.png")
	effect_smoke_m8(&s, s.pointer, true, false)
	if rs.effect_window.card != rod { effect_smoke_fail(&s, "rod: showed %v", rs.effect_window.card) }
	effect_smoke_film(&s, "rod", .Right_Click)

	// The reward: a button under each card, the second one's lit.
	rs.room.phase = .Complete
	if game.finish_room(&rs.run_state, rs.room.phase) != .Reward { fmt.eprintln("effect window smoke: no reward"); return false }
	choices := game.available_card_rewards(&rs.run_state)
	s.pointer = effect_smoke_center(render.reward_effect_bounds(width, height, 1, len(choices)))
	effect_smoke_frames(&s, 3)
	rl.TakeScreenshot("odin_pp_effect_entry_reward.png")
	if !roguelike_effect_entry(rs, true, s.pointer, false) || rs.effect_window.card.definition_id != choices[1] || rs.effect_window.card.upgrade_level != 0 {
		effect_smoke_fail(&s, "reward: the button showed %v, not %v", rs.effect_window.card, choices[1])
	}
	// RICOMINCIA, then the window at other sizes: the stage follows the canvas.
	s.pointer = effect_smoke_center(effect_window_restart_bounds(width, height))
	effect_smoke_frames(&s, 30)
	step_effect_window_in_run(rs, {focused = true, inside = true, pressed = true, mouse = s.pointer}, 1.0/60.0)
	if rs.effect_window.film_time > 0.02 || !rs.effect_window.open { effect_smoke_fail(&s, "reward: RICOMINCIA did not start the film again") }
	effect_smoke_frames(&s, 2)
	rl.TakeScreenshot("odin_pp_effect_window_reward_restart.png")
	for size in ([?][2]i32{{1600, 900}, {960, 540}, {1280, 720}}) {
		rl.SetWindowSize(size.x, size.y)
		for _ in 0..<8 { effect_smoke_frame(&s) }
		destination := effect_window_stage_destination(window.viewport, effect_window_stage_bounds(width, height))
		fmt.printf("effect window: %dx%d window, the stage at %v\n", rl.GetScreenWidth(), rl.GetScreenHeight(), destination)
		rl.TakeScreenshot(fmt.ctprintf("odin_pp_effect_scale_%dx%d.png", rl.GetScreenWidth(), rl.GetScreenHeight()))
		if rl.GetScreenWidth() == 1280 && rl.GetScreenHeight() == 720 && destination != (rl.Rectangle{160, 116, 960, 540}) {
			effect_smoke_fail(&s, "at 1280x720 the stage is at %v, not 1:1 at {{160, 116, 960, 540}}", destination)
		}
	}
	effect_smoke_film(&s, "reward", .Right_Click)

	// The shop: a button under each offer; the owned card chosen, its own.
	if game.skip_card_reward(&rs.run_state) != .Skipped { fmt.eprintln("effect window smoke: the reward stays"); return false }
	shop := available_node_of_kind(&rs.run_state, .Shop)
	if shop == game.INVALID_NODE_ID || !enter_demo_node(&rs.level_data, &rs.run_state, &rs.room, shop, rs.procedural_rooms) ||
	   rs.run_state.phase != .Shop { fmt.eprintln("effect window smoke: no shop"); return false }
	rs.run_state.player.gold = 40
	rs.shop_render_state = {hovered_offer_index = -1}
	s.pointer = effect_smoke_center(render.shop_offer_effect_bounds(width, height, 1))
	effect_smoke_frames(&s, 3)
	rl.TakeScreenshot("odin_pp_effect_entry_shop_offer.png")
	label := fmt.ctprintf("OWNED DECK    PAGE %d/%d", 1, render.shop_deck_page_count(&rs.run_state.player.deck))
	if label_end := 45+f32(render.menu_measure_text(r, label, 13)); label_end >= render.shop_offer_effect_bounds(width, height, 0).x {
		effect_smoke_fail(&s, "shop: the owned deck's label ends at %.0f, under the first offer's button", label_end)
	}
	offer := rs.run_state.shop.offers[1].definition_id
	if !roguelike_effect_entry(rs, true, s.pointer, false) || rs.effect_window.card.definition_id != offer { effect_smoke_fail(&s, "shop: the offer's button") }
	effect_smoke_film(&s, "shop_offer", .Chiudi)
	owned := rs.run_state.player.deck.owned[2]
	rs.shop_render_state.selected_card_id = owned.id
	s.pointer = effect_smoke_center(render.owned_card_effect_bounds(width, height))
	effect_smoke_frames(&s, 3)
	rl.TakeScreenshot("odin_pp_effect_entry_shop_owned.png")
	if !roguelike_effect_entry(rs, true, s.pointer, false) || rs.effect_window.card != owned { effect_smoke_fail(&s, "shop: the owned card's button") }
	effect_smoke_film(&s, "shop_owned", .Escape)
	if rs.run_state.phase != .Shop || rs.run_state.player.gold != 40 { effect_smoke_fail(&s, "shop: left or paid") }

	// The rest, on a run of its own whose first stop is one.
	rest_seed, rest_found := demo_seed_with_first_special(rs.run_seed+1, .Rest)
	rest_run, rest_created := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, rest_seed)
	if !rest_found || !rest_created || !configure_demo_tactical_player(&rest_run.player, rs.options.tactical) {
		fmt.eprintln("effect window smoke: no rest run"); return false
	}
	saved := rs.run_state
	rs.run_state = rest_run
	rested := false
	if game.finish_room(&rs.run_state, .Complete) == .Reward && game.skip_card_reward(&rs.run_state) == .Skipped {
		if node := available_node_of_kind(&rs.run_state, .Rest); node != game.INVALID_NODE_ID && game.enter_node(&rs.run_state, node) != .Invalid {
			rested = rs.run_state.phase == .Rest
		}
	}
	if rested {
		rs.special_render_state = {selected_card_id = rs.run_state.player.deck.owned[1].id}
		s.pointer = effect_smoke_center(render.owned_card_effect_bounds(width, height))
		effect_smoke_frames(&s, 3)
		rl.TakeScreenshot("odin_pp_effect_entry_rest.png")
		if !roguelike_effect_entry(rs, true, s.pointer, false) || rs.effect_window.card != rs.run_state.player.deck.owned[1] {
			effect_smoke_fail(&s, "rest: the owned card's button")
		}
		effect_smoke_film(&s, "rest", .Chiudi)
		if rs.run_state.rest.resolved { effect_smoke_fail(&s, "rest: resolved by MOSTRA EFFETTO") }
	} else { effect_smoke_fail(&s, "rest: not reached") }
	rest_run = rs.run_state
	rs.run_state = saved
	game.destroy_run(&rest_run)
	rs.special_render_state = {}
	// The shop again under the window.
	s.pointer = {}
	effect_smoke_frames(&s, 2)

	// Every card's film, over the shop: a whole take at its first upgrade and
	// at its last; one in PROVA MECCANICHE first, its sounds.
	{
		rl.SetTargetFPS(0)
		rl.ClearWindowState({.VSYNC_HINT})
		defer {
			rl.SetWindowState({.VSYNC_HINT})
			rl.SetTargetFPS(i32(window.config.target_fps))
		}
		effect_smoke_lab_sounds(&s)
		for id in game.Card_Id {
			if id == .Count || (EFFECT_SMOKE_CARDS != "" && !strings.contains(EFFECT_SMOKE_CARDS, fmt.tprintf(",%v,", id))) { continue }
			effect_smoke_take(&s, id, 0)
			if top := game.card_max_upgrade_level(id); top > 0 { effect_smoke_take(&s, id, top) }
		}
	}

	effect_smoke_words(&s)
	effect_smoke_cost_report(&s)
	fmt.printf("effect window smoke: %d card films, %d stills, %d failures\n", s.films, s.stills, s.failures)
	return s.failures == 0
}
