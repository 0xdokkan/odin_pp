package run

import "core:math"
import rl "vendor:raylib"
import app "../engine/app"
import audio "../engine/audio"
import host "../engine/host"
import game "../game"
import render "../render"
import view "../engine/view"

// MOSTRA EFFETTO: a window over the run that shows what a card does. Its
// stage is a board of its own, the card's film (card_demo.odin: the card
// taken from a little hand by a paper glove and played by the game's own
// rules in a room of its own), drawn by a renderer of its own that borrows the
// run renderer's assets (render/effect_stage.odin) into a 960x540 render
// target. The target is shown on the window's own pixels, after the canvas:
// 1:1 at the default 1280x720, scaled with the canvas at any other size.
//
// It is a modal of the run scene, not a scene of the host (no fade, no
// resume): while it is open the run is frozen. roguelike_update hands it the
// whole frame, so that no key or click reaches the run and none of its clocks
// runs, and roguelike_draw shows the run as it was last drawn, under the
// window's veil. Esc, a right click or CHIUDI close it, and no click reaches
// the run; R or RICOMINCIA start the film again. It opens from the reward's
// cards, the shop's offers and the owned card chosen there, the rest's owned
// card, the sheet's MAZZO and the card inspector (the Canna da Pesca's slot
// too), never while the board is busy
// (effect_window_refusal).
//
// The film is driven through card_demo_open/step/restart/prepare/draw/close/
// caption alone: the window owns its memory (new and free), the panel, CHIUDI
// and RICOMINCIA; the film owns everything inside the stage.

EFFECT_STAGE_WIDTH :: 960
EFFECT_STAGE_HEIGHT :: 540
// The stage on the canvas, at three quarters of its pixels: at 1280x720 (the
// canvas at 4/3) each of its pixels is one of the window's. Its corner sits
// on a multiple of 3 canvas pixels, a whole window pixel at 4/3.
EFFECT_STAGE_SCALE :: f32(0.75)
// The panel's head (title, subtitle, RICOMINCIA, CHIUDI) over the stage, and
// its margin around the rest.
EFFECT_WINDOW_HEAD :: f32(53)
EFFECT_WINDOW_MARGIN :: f32(16)
EFFECT_WINDOW_VEIL :: rl.Color{3, 7, 13, 225}
EFFECT_WINDOW_SUBTITLE : cstring : "MOSTRA EFFETTO / LE REGOLE DEL GIOCO IN UNA STANZA DI PROVA / TEMPO SOSPESO"
EFFECT_WINDOW_NO_FILM : cstring : "NESSUNA PROVA PER QUESTA CARTA"

// The stage's blit: its colour, opaque (the HUD's translucent draws lower a
// render target's alpha).
EFFECT_OPAQUE_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
out vec4 finalColor;
void main() { finalColor = vec4(texture(texture0, fragTexCoord).rgb, 1.0); }
`

Effect_Window_Control :: enum u8 {None, Close, Restart}

// Where the window was opened from.
Effect_Window_Source :: enum u8 {None, Reward, Shop_Offer, Shop_Owned, Rest, Sheet, Inspector}

Effect_Window_Input :: struct {
	focused, inside, pressed, right_pressed, escape, restart: bool,
	mouse: view.Vec2,
}

Effect_Window :: struct {
	open: bool,
	card: game.Card_Instance,
	source: Effect_Window_Source,
	hovered: Effect_Window_Control,
	// The film (heap: its room points into it), and whether it was built.
	film: ^Card_Demo,
	film_ready: bool,
	// Seconds of film the window has run since it opened or started again.
	film_time: f32,
	renderer: ^render.Renderer,
	// GPU, with a window only: made on the first opening, kept for the
	// session, freed by destroy_effect_window (roguelike_destroy).
	stage, backdrop: rl.RenderTexture2D,
	opaque: rl.Shader,
	stage_filter: rl.TextureFilter,
	// This opening's: the run as it was last drawn, and a stage drawn.
	backdrop_ready, stage_drawn: bool,
}

// Why the window does not open now (None: it does).
Effect_Window_Refusal :: enum u8 {
	None,
	Open,
	Paused,
	Map,
	// 6 RANCH 7 or the ring's duel, or a square of coils about to open it.
	Duel,
	Defense,
	Cast,
	Dice,
	First_Person,
	Shadow,
	// The board still shows an action (the sheet's own rule: PERSONAGGIO waits too).
	Busy,
}

effect_window_refusal :: proc(rs: ^Roguelike_Session) -> Effect_Window_Refusal {
	room := &rs.room
	switch {
	case rs.effect_window.open: return .Open
	}
	// The run's screens (the reward, the shop, the rest) show no board: what
	// the last room left behind (its view still rising from the player's eyes,
	// say) never keeps them from opening it.
	if rs.run_state.phase != .In_Room { return .None }
	switch {
	case rs.tactical_controller.paused: return .Paused
	case rs.tactical_controller.hologram: return .Map
	case rs.player_activities.ranch.active || rs.player_activities.ring_pending || room.tesla_ring.pending: return .Duel
	case room.qte.kind != .None: return .Defense
	case game.tactical_is_casting(room): return .Cast
	case render.presentation_time_policy(&rs.iso_renderer.timeline) == .Cinematic: return .Dice
	case game.tactical_first_person_active(room) || render.first_person_amount(&rs.iso_renderer) > 0: return .First_Person
	case game.tactical_shadow_active(room): return .Shadow
	case render.renderer_timeline_is_busy(&rs.iso_renderer): return .Busy
	}
	return .None
}

// ---------------------------------------------------------------------------
// Layout, on the canvas.

// The stage's corner, on the nearest multiple of 3 canvas pixels.
effect_window_whole :: proc(value: f32) -> f32 {
	return math.round(value/3)*3
}

effect_window_stage_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	width, height := f32(EFFECT_STAGE_WIDTH)*EFFECT_STAGE_SCALE, f32(EFFECT_STAGE_HEIGHT)*EFFECT_STAGE_SCALE
	panel_height := height+EFFECT_WINDOW_HEAD+EFFECT_WINDOW_MARGIN
	return {effect_window_whole(0.5*(canvas_width-width)), effect_window_whole(0.5*(canvas_height-panel_height)+EFFECT_WINDOW_HEAD), width, height}
}

effect_window_panel_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	stage := effect_window_stage_bounds(canvas_width, canvas_height)
	return {stage.x-EFFECT_WINDOW_MARGIN, stage.y-EFFECT_WINDOW_HEAD, stage.width+2*EFFECT_WINDOW_MARGIN, stage.height+EFFECT_WINDOW_HEAD+EFFECT_WINDOW_MARGIN}
}

effect_window_close_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	stage := effect_window_stage_bounds(canvas_width, canvas_height)
	return {stage.x+stage.width-136, stage.y-EFFECT_WINDOW_HEAD+10, 136, 28}
}

effect_window_restart_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	close := effect_window_close_bounds(canvas_width, canvas_height)
	return {close.x-12-close.width, close.y, close.width, close.height}
}

effect_window_title_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	panel := effect_window_panel_bounds(canvas_width, canvas_height)
	restart := effect_window_restart_bounds(canvas_width, canvas_height)
	return {panel.x+18, panel.y+4, restart.x-12-(panel.x+18), 34}
}

effect_window_subtitle_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	title := effect_window_title_bounds(canvas_width, canvas_height)
	stage := effect_window_stage_bounds(canvas_width, canvas_height)
	return {title.x+2, stage.y-16, title.width-2, 14}
}

// The stage on the window, on whole pixels.
effect_window_stage_destination :: proc(viewport: view.Viewport, stage: rl.Rectangle) -> rl.Rectangle {
	d := viewport.destination
	x := math.round(d.x+stage.x*viewport.scale_x)
	y := math.round(d.y+stage.y*viewport.scale_y)
	return {x, y, math.round(d.x+(stage.x+stage.width)*viewport.scale_x)-x, math.round(d.y+(stage.y+stage.height)*viewport.scale_y)-y}
}

// ---------------------------------------------------------------------------
// The window's own input and its film.

// Pure: Esc and a right click close it anywhere, a click on CHIUDI or
// RICOMINCIA does what it says, R starts the film again; a click elsewhere
// (the stage too) does nothing, and without focus nothing does anything.
step_effect_window :: proc(w: ^Effect_Window, input: Effect_Window_Input, canvas_width, canvas_height: f32) -> Effect_Window_Control {
	w.hovered = .None
	if !input.focused { return .None }
	if input.inside {
		if render.point_in_rectangle(input.mouse, effect_window_close_bounds(canvas_width, canvas_height)) { w.hovered = .Close }
		else if render.point_in_rectangle(input.mouse, effect_window_restart_bounds(canvas_width, canvas_height)) { w.hovered = .Restart }
	}
	if input.escape || input.right_pressed { return .Close }
	if input.pressed && w.hovered != .None { return w.hovered }
	if input.restart { return .Restart }
	return .None
}

// The film from its start: a film that could not be built is tried afresh.
restart_effect_window_film :: proc(w: ^Effect_Window) {
	if w.film == nil || w.renderer == nil { return }
	if w.film_ready {
		card_demo_restart(w.film, w.renderer)
	} else {
		card_demo_close(w.film)
		w.film_ready = card_demo_open(w.film, w.renderer, w.card)
	}
	w.film_time = 0
}

// The film's frame into the stage, in the update (raylib's render targets do
// not nest: never inside the canvas's pass). Its dice first, outside any.
render_effect_stage :: proc(w: ^Effect_Window) {
	if !w.open || w.stage.id == 0 || w.renderer == nil { return }
	if w.film_ready { card_demo_prepare(w.film, w.renderer) }
	rl.BeginTextureMode(w.stage)
	rl.ClearBackground(render.RESIN_BACKGROUND)
	if w.film_ready {
		card_demo_draw(w.film, w.renderer)
	} else {
		r := w.renderer
		width := render.gothic_text_width(r, EFFECT_WINDOW_NO_FILM, 18)
		render.gothic_text(r, EFFECT_WINDOW_NO_FILM, math.round(0.5*(r.canvas_width-width)), math.round(0.5*r.canvas_height-12), 18, render.GOTHIC_MUTED)
	}
	rl.EndTextureMode()
	w.stage_drawn = true
}

// What the window says the film shows now (for the smoke and the tests).
effect_window_caption :: proc(w: ^Effect_Window) -> string {
	if !w.open { return "" }
	if !w.film_ready { return string(EFFECT_WINDOW_NO_FILM) }
	return card_demo_caption(w.film)
}

// The render targets and the blit's shader, made once a session. The
// backdrop fails quietly (the run is then drawn under the veil as it is).
effect_window_make_targets :: proc(w: ^Effect_Window, window: ^app.Window) -> bool {
	if w.stage.id == 0 {
		w.stage = rl.LoadRenderTexture(EFFECT_STAGE_WIDTH, EFFECT_STAGE_HEIGHT)
		if !rl.IsRenderTextureValid(w.stage) {
			if w.stage.id != 0 { rl.UnloadRenderTexture(w.stage) }
			w.stage = {}
			return false
		}
		rl.SetTextureWrap(w.stage.texture, .CLAMP)
		rl.SetTextureFilter(w.stage.texture, .POINT)
		w.stage_filter = .POINT
	}
	if w.backdrop.id == 0 && window != nil {
		w.backdrop = rl.LoadRenderTexture(i32(window.config.canvas_width), i32(window.config.canvas_height))
		if !rl.IsRenderTextureValid(w.backdrop) {
			if w.backdrop.id != 0 { rl.UnloadRenderTexture(w.backdrop) }
			w.backdrop = {}
		} else {
			rl.SetTextureFilter(w.backdrop.texture, .POINT)
		}
	}
	if w.opaque.id == 0 { w.opaque = rl.LoadShaderFromMemory(nil, EFFECT_OPAQUE_FRAGMENT) }
	return true
}

// The run as the canvas last showed it (the frame before the opening one):
// what the frozen run would draw, drawn once.
effect_window_capture_backdrop :: proc(w: ^Effect_Window, window: ^app.Window) {
	w.backdrop_ready = false
	if window == nil || w.backdrop.id == 0 || window.canvas.id == 0 { return }
	source := window.canvas.texture
	rl.BeginTextureMode(w.backdrop)
	rl.ClearBackground(render.CANVAS_BACKGROUND)
	rl.DrawTexturePro(source, {0, 0, f32(source.width), -f32(source.height)},
		{0, 0, f32(w.backdrop.texture.width), f32(w.backdrop.texture.height)}, {}, 0, rl.WHITE)
	rl.EndTextureMode()
	w.backdrop_ready = true
}

// Frees this opening's film and board (the render targets stay).
close_effect_window :: proc(w: ^Effect_Window) {
	if w.film != nil {
		card_demo_close(w.film)
		free(w.film)
		w.film = nil
	}
	if w.renderer != nil {
		render.destroy_borrowed_renderer(w.renderer)
		w.renderer = nil
	}
	w.open, w.film_ready, w.film_time = false, false, 0
	w.card, w.source, w.hovered = {}, .None, .None
	w.backdrop_ready, w.stage_drawn = false, false
}

// The session's end: the film borrows the run renderer's assets, so it goes
// before them (roguelike_destroy).
destroy_effect_window :: proc(w: ^Effect_Window) {
	close_effect_window(w)
	if w.opaque.id != 0 { rl.UnloadShader(w.opaque) }
	if w.backdrop.id != 0 { rl.UnloadRenderTexture(w.backdrop) }
	if w.stage.id != 0 { rl.UnloadRenderTexture(w.stage) }
	w^ = {}
}

// ---------------------------------------------------------------------------
// In the run (roguelike_scene.odin).

// A card the window shows as it is offered (a reward's, a ware's): no one's,
// at no upgrade.
effect_window_offered_card :: proc(id: game.Card_Id) -> game.Card_Instance {
	definition, _ := game.card_definition_by_id(id)
	return {id = 1, definition_id = id, lifetime = .Combat if definition.temporary_only else .Permanent}
}

// The MOSTRA EFFETTO button of the run's screens under `point` (the reward's,
// the shop's and the rest's: their drawing's layout) and the card it shows: an
// offer as it is offered, an owned card as it is. The sheet's and the
// inspector's are step_player_activities's.
effect_window_entry_at :: proc(rs: ^Roguelike_Session, point: view.Vec2) -> (card: game.Card_Instance, source: Effect_Window_Source, found: bool) {
	run := &rs.run_state
	if game.run_has_relic_choice(run) { return }
	width, height := rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height
	#partial switch run.phase {
	case .Reward:
		if index, hit := render.reward_effect_at_point(run, width, height, point); hit {
			return effect_window_offered_card(game.available_card_rewards(run)[index]), .Reward, true
		}
	case .Shop:
		if index, hit := render.shop_offer_effect_at_point(run, width, height, point); hit {
			return effect_window_offered_card(run.shop.offers[index].definition_id), .Shop_Offer, true
		}
		if render.point_in_rectangle(point, render.owned_card_effect_bounds(width, height)) {
			if index, owned := game.owned_card_index_by_id(&run.player.deck, rs.shop_render_state.selected_card_id); owned {
				return run.player.deck.owned[index], .Shop_Owned, true
			}
		}
	case .Rest:
		if !run.rest.resolved && render.point_in_rectangle(point, render.owned_card_effect_bounds(width, height)) {
			if index, owned := game.owned_card_index_by_id(&run.player.deck, rs.special_render_state.selected_card_id); owned {
				return run.player.deck.owned[index], .Rest, true
			}
		}
	}
	return
}

// The I key on the run's screens: the reward card under the mouse, the shop's
// offer under the mouse or else its owned card chosen, the rest's owned card
// chosen.
effect_window_key_entry :: proc(rs: ^Roguelike_Session) -> (card: game.Card_Instance, source: Effect_Window_Source, found: bool) {
	run := &rs.run_state
	if game.run_has_relic_choice(run) { return }
	#partial switch run.phase {
	case .Reward:
		choices := game.available_card_rewards(run)
		if rs.reward_hovered_index >= 0 && rs.reward_hovered_index < len(choices) {
			return effect_window_offered_card(choices[rs.reward_hovered_index]), .Reward, true
		}
	case .Shop:
		state := &rs.shop_render_state
		if state.has_hovered_offer && state.hovered_offer_index >= 0 && state.hovered_offer_index < run.shop.offer_count {
			return effect_window_offered_card(run.shop.offers[state.hovered_offer_index].definition_id), .Shop_Offer, true
		}
		if index, owned := game.owned_card_index_by_id(&run.player.deck, state.selected_card_id); owned {
			return run.player.deck.owned[index], .Shop_Owned, true
		}
	case .Rest:
		if index, owned := game.owned_card_index_by_id(&run.player.deck, rs.special_render_state.selected_card_id); owned && !run.rest.resolved {
			return run.player.deck.owned[index], .Rest, true
		}
	}
	return
}

// The screens' MOSTRA EFFETTO this frame: a press on one of their buttons, or
// the I key. Such a press or key is the window's alone, whether it opens or
// is refused: the screen sees none of the frame.
roguelike_effect_entry :: proc(rs: ^Roguelike_Session, pressed: bool, point: view.Vec2, inspect: bool) -> (taken: bool) {
	card: game.Card_Instance
	source: Effect_Window_Source
	if pressed { card, source, taken = effect_window_entry_at(rs, point) }
	if !taken && inspect { card, source, taken = effect_window_key_entry(rs) }
	if taken { _ = open_effect_window_in_run(rs, card, source) }
	return
}

// Where the mouse reaches this frame (roguelike_update): the board's view
// (its hovered cell, its orbit) as ever, never over the HUD's controls or the
// inspector's MOSTRA EFFETTO button; the HUD's hover (hud_hovered) wherever
// the view does, and also where MOSTRA EFFETTO's buttons stand beyond it: the
// inspector's, the open sheet's MAZZO (its lines, its pager, its button), and
// the run's screens, which show no board (the last room's HUD keeps no part
// of the reward's, the shop's or the rest's buttons from lighting).
roguelike_pointer_inside :: proc(rs: ^Roguelike_Session, focused: bool) -> (view, hud: bool) {
	if !rs.mouse_inside || !focused || rs.tactical_controller.hologram || rs.tactical_controller.paused { return }
	cards := rs.card_interaction
	effect := render.tactical_inspector_effect_contains(&rs.iso_renderer, &rs.room, cards.hovered_card_id, cards.selected_card_id,
		cards.dragged_card_id, rs.mouse_canvas)
	view = !rs.activity_modal && !render.m8_hud_contains_point(&rs.iso_renderer, &rs.room, rs.mouse_canvas) && !effect
	switch {
	case rs.run_state.phase != .In_Room: hud = !rs.activity_modal
	case rs.player_activities.character_open: hud = true
	case: hud = view || (!rs.activity_modal && effect)
	}
	return
}

// MOSTRA EFFETTO asked from the sheet's MAZZO or the card inspector
// (step_player_activities): the frame is the window's.
roguelike_take_effect_request :: proc(rs: ^Roguelike_Session) -> bool {
	session := &rs.player_activities
	if !session.has_effect_request { return false }
	card, source := session.effect_request, session.effect_source
	session.effect_request, session.effect_source, session.has_effect_request = {}, .None, false
	_ = open_effect_window_in_run(rs, card, source)
	return true
}

// Opens the window on `card`, unless the board is busy. The run gives up what
// it held, as when the game's window loses its focus (roguelike_suspend_input:
// its card in hand, the press it buffered, the board's drag, the mouse behind
// the player's eyes, the room's ambience), and the dice over the window.
open_effect_window_in_run :: proc(rs: ^Roguelike_Session, card: game.Card_Instance, source: Effect_Window_Source) -> bool {
	if effect_window_refusal(rs) != .None { return false }
	w := &rs.effect_window
	gpu := rs.attached && rs.window != nil && rl.IsWindowReady()
	if gpu && !effect_window_make_targets(w, rs.window) { return false }
	w.renderer = render.create_borrowed_renderer(&rs.iso_renderer, EFFECT_STAGE_WIDTH, EFFECT_STAGE_HEIGHT, w.stage)
	if w.renderer == nil { return false }
	w.film = new(Card_Demo)
	w.open, w.card, w.source, w.hovered = true, card, source, .None
	w.film_time, w.stage_drawn = 0, false
	w.film_ready = card_demo_open(w.film, w.renderer, card)
	if gpu {
		effect_window_capture_backdrop(w, rs.window)
		// Its first frame now: the opening frame shows the film, never an
		// older one.
		render_effect_stage(w)
	}
	roguelike_suspend_input(rs)
	rs.overlay, rs.overlay_data = nil, {}
	return true
}

// Back to the run as from a window given its focus back: nothing pressed
// meanwhile acts, and the run's first frame sets the keys as they are and
// charges no time (the controller's resume, the renderer's clock).
close_effect_window_in_run :: proc(rs: ^Roguelike_Session) {
	close_effect_window(&rs.effect_window)
	roguelike_suspend_input(rs)
}

// One frame of the open window, its input given (the tests and the smoke
// drive it; update_effect_window_in_run samples raylib's).
step_effect_window_in_run :: proc(rs: ^Roguelike_Session, input: Effect_Window_Input, dt: f32, bank: ^audio.Bank = nil) {
	w := &rs.effect_window
	if !w.open { return }
	width, height := rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height
	// RICOMINCIA and CHIUDI light up under the mouse (hud_button reads the
	// pointer of the renderer that draws them, the run's).
	render.tactical_hud_pointer(&rs.iso_renderer, input.mouse, input.inside && input.focused)
	restarted := false
	switch step_effect_window(w, input, width, height) {
	case .Close:
		close_effect_window_in_run(rs)
		return
	case .Restart:
		restart_effect_window_film(w)
		restarted = true
	case .None:
	}
	// The frame RICOMINCIA starts the film again shows its first moment, as
	// the opening frame does.
	if input.focused && dt > 0 && !restarted {
		if w.film_ready { card_demo_step(w.film, w.renderer, dt) }
		w.film_time += dt
	}
	effect_window_film_sounds(rs, bank)
	render_effect_stage(w)
}

update_effect_window_in_run :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) {
	input := Effect_Window_Input{focused = hf.focused && hf.window_focused, inside = hf.mouse_inside, mouse = {hf.mouse.x, hf.mouse.y},
		pressed = rs.frame_input.left_pressed, right_pressed = rs.frame_input.right_pressed,
		escape = run_pressed(rs.frame_input, .Cancel), restart = run_pressed(rs.frame_input, .Recenter)}
	step_effect_window_in_run(rs, input, hf.dt, hf.audio)
}

// The film's board queues PROVA MECCANICHE's sounds in the lab only (its
// renderer is the lab's, as the run's is): they play there as the run's do,
// at the effects volume; elsewhere the film is silent.
effect_window_film_sounds :: proc(rs: ^Roguelike_Session, bank: ^audio.Bank) {
	w := &rs.effect_window
	if w.renderer == nil { return }
	if !rs.options.mechanics_lab || bank == nil || !bank.ready || bank.muted || !audio.lab_bank_load(&rs.lab_bank) {
		render.play_lab_sounds(w.renderer, nil, 0)
		return
	}
	render.play_lab_sounds(w.renderer, &rs.lab_bank, bank.sfx_volume)
}

// ---------------------------------------------------------------------------
// Drawing.

// The run as it was last drawn, the whole canvas (roguelike_draw).
draw_effect_window_backdrop :: proc(w: ^Effect_Window, canvas_width, canvas_height: f32) {
	texture := w.backdrop.texture
	rl.DrawTexturePro(texture, {0, 0, f32(texture.width), -f32(texture.height)}, {0, 0, canvas_width, canvas_height}, {}, 0, rl.WHITE)
}

// The canvas's part: the veil, the panel, its head and the stage's frame (the
// stage itself comes after the canvas, draw_window_effect_stage).
draw_effect_window :: proc(w: ^Effect_Window, theme: ^render.Renderer, canvas_width, canvas_height: f32) {
	if !w.open { return }
	rl.DrawRectangleRec({0, 0, canvas_width, canvas_height}, EFFECT_WINDOW_VEIL)
	render.hud_frame(effect_window_panel_bounds(canvas_width, canvas_height), render.GOTHIC_PAPER)
	definition, _ := game.card_definition_by_id(w.card.definition_id)
	render.gothic_text_fit(theme, render.tactical_card_title(w.card, definition), effect_window_title_bounds(canvas_width, canvas_height), 24,
		render.GOTHIC_PAPER)
	render.gothic_text_fit(theme, EFFECT_WINDOW_SUBTITLE, effect_window_subtitle_bounds(canvas_width, canvas_height), 10, render.GOTHIC_MUTED)
	render.hud_button(theme, effect_window_restart_bounds(canvas_width, canvas_height), "R", "RICOMINCIA", true, render.GOTHIC_BLUE)
	render.hud_button(theme, effect_window_close_bounds(canvas_width, canvas_height), "ESC", "CHIUDI", true, render.GOTHIC_PAPER)
	stage := effect_window_stage_bounds(canvas_width, canvas_height)
	rl.DrawRectangleLinesEx({stage.x-1, stage.y-1, stage.width+2, stage.height+2}, 1, render.HUD_EDGE)
	rl.DrawRectangleRec(stage, render.RESIN_BACKGROUND)
}

// The window's part, after the canvas: the stage's own pixels, opaque; whole
// pixels from 1:1 up, filtered when the window is smaller (no row of its
// print is dropped).
draw_window_effect_stage :: proc(window: ^app.Window, w: ^Effect_Window) {
	if window == nil || !w.open || w.stage.id == 0 || !w.stage_drawn { return }
	stage := effect_window_stage_bounds(f32(window.config.canvas_width), f32(window.config.canvas_height))
	destination := effect_window_stage_destination(window.viewport, stage)
	filter: rl.TextureFilter = .POINT if destination.width >= f32(w.stage.texture.width) else .BILINEAR
	if filter != w.stage_filter {
		rl.SetTextureFilter(w.stage.texture, filter)
		w.stage_filter = filter
	}
	if w.opaque.id != 0 { rl.BeginShaderMode(w.opaque) }
	rl.DrawTexturePro(w.stage.texture, {0, 0, f32(w.stage.texture.width), -f32(w.stage.texture.height)}, destination, {}, 0, rl.WHITE)
	if w.opaque.id != 0 { rl.EndShaderMode() }
}
