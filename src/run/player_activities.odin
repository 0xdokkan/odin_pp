package run
import activities "../activities"

import "core:encoding/json"
import "core:fmt"
import "core:os"
import fight "../fight"
import game "../game"
import host "../engine/host"
import render "../render"
import view "../engine/view"
import western "../western"
import rl "vendor:raylib"

M8_PROFILE_PATH :: "odin_pp_profile.json"
M8_Profile_File :: struct { version: int, progress: game.M8_Profile }
Player_Activities :: struct {
	character_open, save_enabled: bool,
	// A Tesla ring handed to the ring scene; the live duel belongs to fight.
	ring_pending: bool,
	ring_link: activities.Ring_Run_Link,
	report: game.Tesla_Ring_Report,
	status: string,
	ranch: Ranch_Session,
	// The sheet's MAZZO: its page and the line chosen.
	sheet: render.Character_Sheet_State,
	// MOSTRA EFFETTO asked for this frame, from the sheet or the card
	// inspector: the scene opens the window (roguelike_take_effect_request).
	effect_request: game.Card_Instance,
	effect_source: Effect_Window_Source,
	has_effect_request: bool,
}

// 6 RANCH 7 plays in a bubble over the frozen board, inside the run scene.
Ranch_Session :: struct {
	active: bool,
	state: western.State,
	// Where the 6 and the 7 sat in the hand when they left for the sign.
	card_from: [2]rl.Rectangle,
	// Settled during this step; the scene reports it once.
	finished: bool,
	reward: game.Western_Ranch_Reward,
}

Player_Activities_Input :: struct {
	focused, inside, pressed, escape: bool,
	// The ranch's press edge: Space, Enter or a click inside the canvas.
	ranch_press: bool,
	// I: MOSTRA EFFETTO of the card the inspector shows, or of the sheet's
	// line chosen.
	inspect: bool,
	mouse: view.Vec2,
}

// Object controls have one input path: an enabled button's left-click edge.
m8_pointer_gameplay_command :: proc(room: ^game.Room, renderer: ^render.Renderer,
	mouse: view.Vec2, inside, pressed, available: bool) -> (Gameplay_Command, bool) {
	if !inside || !pressed || !available { return {}, false }
	switch render.m8_control_at_point(renderer, room, mouse) {
	case .Activate: return {kind = .Activate, origin_phase = room.phase}, true
	case .Equip: return {kind = .Equip, origin_phase = room.phase}, true
	case .None, .Character:
	}
	return {}, false
}

begin_ranch_session :: proc(ranch: ^Ranch_Session, room: ^game.Room, renderer: ^render.Renderer) -> bool {
	if ranch.active || room.phase != .Combat || !game.tactical_allows_action(room) || !game.western_ranch_can_start(room) { return false }
	six, seven, _ := game.western_ranch_hand(room)
	count := room.player.deck.hand_count
	from := [2]rl.Rectangle{render.tactical_hand_card_bounds(renderer, six, count), render.tactical_hand_card_bounds(renderer, seven, count)}
	if !game.begin_western_ranch(room) { return false }
	seed := (u64(room.pulse_count)+1)*0x9E37_79B9_7F4A_7C15 ~ u64(room.player.gold)<<20 ~ u64(room.next_object_id)
	ranch^ = {active = true, state = western.begin(seed), card_from = from}
	return true
}

// A won duel refills health and pays the purse, shown as ordinary feedback.
step_ranch_session :: proc(ranch: ^Ranch_Session, room: ^game.Room, renderer: ^render.Renderer, dt: f32, press: bool) {
	western.step(&ranch.state, dt, press)
	if ranch.state.phase != .Done { return }
	before := render.capture_room_presentation(room)
	ranch.reward = game.settle_western_ranch(room, ranch.state.won)
	ranch.active = false
	ranch.finished = true
	if !ranch.reward.won { return }
	game.clear_event_log(room.recent_events)
	at := room.player.position
	if ranch.reward.healed > 0 {
		game.record_event(room.recent_events, {kind = .Healed, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
			amount = ranch.reward.healed, from_position = at, to_position = at})
	}
	game.record_event(room.recent_events, {kind = .Gold_Gained, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
		amount = ranch.reward.gold, from_position = at, to_position = at})
	after := render.capture_room_presentation(room)
	_ = render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after)
}

// Board health becomes ring health, so the duel keeps how hurt everyone is.
tesla_ring_link :: proc(room: ^game.Room) -> (link: activities.Ring_Run_Link) {
	ring := room.tesla_ring
	player := room.player
	roster := &link.entered
	roster.player_max = fight.RING_PLAYER_HEALTH
	roster.player_health = ring_health_share(fight.RING_PLAYER_HEALTH, player.health, player.stats.max_health)
	opponent := fight.ring_opponent_health(ring.count)
	for slot in 0..<min(ring.count, fight.MAX_RING_ROSTER) {
		entry := fight.Roster_Entry{kind = -1, enemy_id = ring.enemy_ids[slot], health = opponent, max_health = opponent}
		if index, found := game.enemy_index_by_id(room, entry.enemy_id); found {
			enemy := room.enemies[index]
			entry.kind = int(enemy.archetype)
			entry.health = ring_health_share(opponent, enemy.health, enemy.max_health)
		}
		roster.entries[slot] = entry
		roster.count += 1
	}
	return
}

ring_health_share :: proc(scale, health, max_health: i32) -> i32 {
	if max_health <= 0 { return scale }
	return clamp((scale*health+max_health-1)/max_health, 1, scale)
}

// What the duel left of each opponent, in thousandths of its entry health.
tesla_ring_outcome :: proc(link: ^activities.Ring_Run_Link, won: bool) -> (outcome: game.Tesla_Ring_Outcome) {
	outcome.won = won
	for slot in 0..<min(link.entered.count, game.MAX_TESLA_RING_ROSTER) {
		entered := max(i32(1), link.entered.entries[slot].health)
		left := entered
		if link.reported {
			final := link.final.entries[slot]
			left = 0 if final.ko else final.health
		}
		outcome.remaining[slot] = clamp(left*1000/entered, 0, 1000)
	}
	return
}

load_m8_profile :: proc(path: string) -> (game.M8_Profile, bool) {
	if !os.exists(path) { return {}, true }
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil { return {}, false }
	defer delete(data)
	if len(data) > 4096 { return {}, false }
	file: M8_Profile_File
	if json.unmarshal(data, &file) != nil || file.version != game.M8_PROFILE_VERSION ||
	   !game.m8_profile_valid(file.progress) { return {}, false }
	return file.progress, true
}

save_m8_profile :: proc(path: string, profile: game.M8_Profile) -> bool {
	if !game.m8_profile_valid(profile) { return false }
	data, error := json.marshal(M8_Profile_File{game.M8_PROFILE_VERSION, profile})
	if error != nil { return false }
	defer delete(data)
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, data) != nil { return false }
	return os.rename(temporary, path) == nil
}

// Modals own input, arena clocks and presentation until explicitly closed.
update_player_activities :: proc(session: ^Player_Activities, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, mouse: view.Vec2, inside: bool, controls: Run_Input) -> bool {
	input := Player_Activities_Input{focused = controls.focused, inside = inside, mouse = mouse,
		pressed = controls.left_pressed, escape = run_pressed(controls, .Cancel), inspect = run_pressed(controls, .Inspect)}
	input.ranch_press = run_pressed(controls, .Wait) || run_pressed(controls, .Confirm) || (input.pressed && inside)
	consumed := step_player_activities(session, room, renderer, controller, cards, buffer, available, dt, input)
	return consumed
}

step_player_activities :: proc(session: ^Player_Activities, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, input: Player_Activities_Input) -> bool {
	if session.ring_pending {return true}
	session.ranch.finished = false
	if session.ranch.active {
		// Losing focus pauses the duel; it never counts as a press.
		step_ranch_session(&session.ranch, room, renderer, dt if input.focused else 0, input.focused && input.ranch_press)
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		return true
	}
	if !available || !input.focused { return session.character_open }
	left_click := input.inside && input.pressed
	if session.character_open {
		if input.escape || left_click && render.point_in_rectangle(input.mouse, render.m8_modal_control_bounds(renderer, .Close_Character)) {
			session.character_open = false
			return true
		}
		step_character_sheet_deck(session, room, renderer, input, left_click)
		return true
	}
	if controller.paused || controller.hologram || room.qte.kind != .None ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   game.tactical_is_casting(room) || render.renderer_timeline_is_busy(renderer) { return false }
	clicked: render.M8_Control
	if left_click { clicked = render.m8_control_at_point(renderer, room, input.mouse) }
	if clicked == .Character { session.character_open, session.sheet = true, {} }
	// MOSTRA EFFETTO of the card the inspector shows: its key, or a click on
	// its button once the card is chosen; never a step or a play as well.
	// Movimento Ombra keeps it dimmed too (tactical_inspector_effect_ready).
	if !session.character_open && render.tactical_inspector_effect_ready(renderer, room) {
		if card, effect := render.tactical_inspector_effect(renderer, room, cards.hovered_card_id, cards.selected_card_id, cards.dragged_card_id);
		   effect != .None && (input.inspect || effect == .Button && left_click &&
		   render.point_in_rectangle(input.mouse, render.tactical_inspector_effect_bounds())) {
			m8_request_effect(session, card, .Inspector)
			return true
		}
	}
	// Holding the 6 and the 7 together opens the ranch at once.
	if !session.character_open && begin_ranch_session(&session.ranch, room, renderer) {
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		return true
	}
	if session.character_open {
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		return true
	}
	return false
}

m8_request_effect :: proc(session: ^Player_Activities, card: game.Card_Instance, source: Effect_Window_Source) {
	session.effect_request, session.effect_source, session.has_effect_request = card, source, true
}

// The sheet's MAZZO (render.character_sheet_deck_layout): a click chooses a
// line, or turns the page (to its first line); MOSTRA EFFETTO, or I, asks for
// the window on the line chosen, as the deck holds it (its upgrade too).
step_character_sheet_deck :: proc(session: ^Player_Activities, room: ^game.Room, renderer: ^render.Renderer, input: Player_Activities_Input, left_click: bool) {
	layout := render.character_sheet_deck_layout(renderer, room, session.sheet.deck_page)
	sheet := &session.sheet
	sheet.deck_page = layout.page
	if layout.row_count == 0 {
		sheet.deck_selected = 0
		return
	}
	sheet.deck_selected = clamp(sheet.deck_selected, 0, layout.row_count-1)
	ask := input.inspect
	if left_click {
		switch {
		case render.point_in_rectangle(input.mouse, layout.button):
			ask = true
		case layout.pages > 1 && layout.page > 0 && render.point_in_rectangle(input.mouse, layout.previous):
			sheet.deck_page = layout.page-1
			sheet.deck_selected = sheet.deck_page*layout.per_page
		case layout.pages > 1 && layout.page+1 < layout.pages && render.point_in_rectangle(input.mouse, layout.next):
			sheet.deck_page = layout.page+1
			sheet.deck_selected = sheet.deck_page*layout.per_page
		case:
			if row, found := render.character_sheet_deck_row_at(&layout, input.mouse); found { sheet.deck_selected = row }
		}
	}
	if ask { m8_request_effect(session, layout.rows[sheet.deck_selected].card, .Sheet) }
}

// Accept only the outstanding Tesla ring. Standalone victories and foreign
// results cannot touch the run, and a second return cannot settle twice.
// Leaving the duel early counts as a loss.
settle_m8_host_activity :: proc(session: ^Player_Activities, room: ^game.Room, from: string, result: Maybe(host.Result)) -> bool {
	if !session.ring_pending || from != "ring" {return false}
	r, has := result.?
	if has && r.minigame != "ring" {return false}
	session.ring_pending=false
	session.report=game.settle_tesla_ring(room,tesla_ring_outcome(&session.ring_link,has && r.outcome==.Won))
	session.ring_link={}
	session.status=""
	if session.report.reward.won && session.save_enabled && !save_m8_profile(M8_PROFILE_PATH,room.player.m8_profile) {
		session.status="Salvataggio non riuscito: progressi validi per questa sessione."
	}
	return true
}
