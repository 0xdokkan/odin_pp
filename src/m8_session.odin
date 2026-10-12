package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import fight "fight"
import game "game"
import host "engine/host"
import render "render"
import view "view"
import western "western"
import rl "vendor:raylib"

M8_PROFILE_PATH :: "odin_pp_profile.json"
M8_Profile_File :: struct { version: int, progress: game.M8_Profile }
M8_Session :: struct {
	character_open, save_enabled: bool,
	// A Tesla ring handed to the ring scene; the live duel belongs to fight.
	ring_pending: bool,
	ring_link: Ring_Run_Link,
	report: game.Tesla_Ring_Report,
	status: string,
	ranch: Ranch_Session,
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

M8_Session_Input :: struct {
	focused, inside, pressed, escape: bool,
	// The ranch's press edge: Space, Enter or a click inside the canvas.
	ranch_press: bool,
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
	game.clear_event_log(&room.recent_events)
	at := room.player.position
	if ranch.reward.healed > 0 {
		game.record_event(&room.recent_events, {kind = .Healed, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
			amount = ranch.reward.healed, from_position = at, to_position = at})
	}
	game.record_event(&room.recent_events, {kind = .Gold_Gained, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY,
		amount = ranch.reward.gold, from_position = at, to_position = at})
	after := render.capture_room_presentation(room)
	_ = render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after)
}

// Board health becomes ring health, so the duel keeps how hurt everyone is.
tesla_ring_link :: proc(room: ^game.Room) -> (link: Ring_Run_Link) {
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
tesla_ring_outcome :: proc(link: ^Ring_Run_Link, won: bool) -> (outcome: game.Tesla_Ring_Outcome) {
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
update_m8_session :: proc(session: ^M8_Session, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, mouse: view.Vec2, inside: bool) -> bool {
	input := M8_Session_Input{focused = rl.IsWindowFocused(), inside = inside, mouse = mouse,
		pressed = rl.IsMouseButtonPressed(.LEFT), escape = rl.IsKeyPressed(.ESCAPE)}
	input.ranch_press = rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) || (input.pressed && inside)
	consumed := step_m8_session(session, room, renderer, controller, cards, buffer, available, dt, input)
	return consumed
}

step_m8_session :: proc(session: ^M8_Session, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, input: M8_Session_Input) -> bool {
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
		if input.escape || left_click && render.point_in_rectangle(input.mouse, render.m8_modal_control_bounds(renderer, .Close_Character)) { session.character_open = false }
		return true
	}
	if controller.paused || controller.hologram || room.qte.kind != .None ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   game.tactical_is_casting(room) || render.renderer_timeline_is_busy(renderer) { return false }
	clicked: render.M8_Control
	if left_click { clicked = render.m8_control_at_point(renderer, room, input.mouse) }
	if clicked == .Character { session.character_open = true }
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

// Accept only the outstanding Tesla ring. Standalone victories and foreign
// results cannot touch the run, and a second return cannot settle twice.
// Leaving the duel early counts as a loss.
settle_m8_host_activity :: proc(session: ^M8_Session, room: ^game.Room, from: string, result: Maybe(host.Result)) -> bool {
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
