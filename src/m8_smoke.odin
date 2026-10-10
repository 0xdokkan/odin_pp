package main

import "core:fmt"
import rl "vendor:raylib"
import app "app"
import game "game"
import grid "grid"
import level "level"
import render "render"

m8_smoke_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer,
	room: ^game.Room, controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, dt: f32 = 1.0/60.0) {
	render.update_renderer_frame_timeline(renderer, dt)
	step_tactical_controller(controller, room, renderer, cards, buffer, dt, true, {focused = true})
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, dt)
	cue, found := render.active_presentation_cue(&renderer.timeline)
	dice_state: Dice_Window_Overlay
	overlay: app.Window_Overlay
	if found && cue.kind == .Dice_Rolled {
		dice_state = {renderer = dice, roll = cue.event.dice_roll,
			progress = render.presentation_cue_progress(cue), seed = dice_event_visual_seed(cue.event), card = cue.event.card_definition}
		update_window_dice_overlay(window, &dice_state)
		overlay = draw_window_dice_overlay
	}
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_tactical_status(renderer, room)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	app.present(window, render.LETTERBOX_COLOR, overlay, &dice_state)
}

m8_smoke_settle :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer,
	room: ^game.Room, controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, capture_d4: bool = false) -> bool {
	captured := false
	for _ in 0..<900 {
		if !render.renderer_timeline_is_busy(renderer) && !game.tactical_is_casting(room) && !room.tactical_pulse.pending {
			valid := renderer.timeline.update_failures == 0 && renderer.timeline.dropped_count == 0 &&
			       room.recent_events.dropped_count == 0 &&
			       (renderer.world_playback == nil || renderer.world_playback.rejected_batches == 0)
			if !valid { fmt.eprintf("M8 presentation: updates=%d dropped=%d events=%d rejected=%d\n",
				renderer.timeline.update_failures, renderer.timeline.dropped_count, room.recent_events.dropped_count,
				renderer.world_playback.rejected_batches if renderer.world_playback != nil else 0) }
			return valid
		}
		if room.qte.kind != .None { if !commit_gameplay_command(room, renderer, cards, {kind = .QTE_Fail, origin_phase = .Combat}) { return false } }
		// Outside casts this helper drains committed presentation, not idle time.
		dt := min(f32(1.0/60.0), room.player.tactical.cast_remaining) if game.tactical_is_casting(room) else f32(0)
		render.update_renderer_frame_timeline(renderer, 1.0/60.0)
		step_tactical_controller(controller, room, renderer, cards, buffer, dt, true, {focused = true})
		// Render without a second simulation update.
		render.update_tactical_view(renderer, room, {}, false, true)
		render.update_tactical_atmosphere(renderer, 1.0/60.0)
		cue, found := render.active_presentation_cue(&renderer.timeline)
		dice_state: Dice_Window_Overlay
		overlay: app.Window_Overlay
		if found && cue.kind == .Dice_Rolled {
			dice_state = {renderer = dice, roll = cue.event.dice_roll, progress = render.presentation_cue_progress(cue), seed = dice_event_visual_seed(cue.event), card = cue.event.card_definition}
			update_window_dice_overlay(window, &dice_state)
			overlay = draw_window_dice_overlay
		}
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, 0)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		app.present(window, render.LETTERBOX_COLOR, overlay, &dice_state)
		if capture_d4 && !captured && found && cue.kind == .Dice_Rolled && render.presentation_cue_progress(cue) > 0.86 {
			rl.TakeScreenshot("odin_pp_m8_d4.png")
			captured = true
		}
	}
	return false
}

run_m8_view_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	rows := [?]string{"###########", "#.........#", "#.........#", "#.........#", "#....@....#", "#.........#", "#.........#", "#........>#", "###########"}
	data, error, _ := level.from_ascii(rows[:])
	if error != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	if !created || !game.configure_tactical(&player, config) || !game.initialize_empty_deck(&player.deck, {5, 12, 1}, 812) { return false }
	for id in ([8]game.Card_Id{.Shock_Floor, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Strike, .Guard, .Heavy_Blow}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	enemies := [?]game.Enemy_Spawn{{position = {4,3},health = 30,attack = 1}, {position = {6,5},health = 30,attack = 1,archetype = .Brute}, {position = {8,4},health = 30,attack = 1,archetype = .Archer}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	positions := [5]grid.Position{{3,2},{7,2},{7,6},{3,6},{4,2}}
	for position, index in positions {
		id: u32
		definition: game.Card_Id = .Shock_Floor if index == 4 else .Tesla_Coil
		for card in player.deck.hand[:player.deck.hand_count] { if card.definition_id == definition { id = card.id; break } }
		if id == 0 { id = prepare_smoke_card_drag(&room, definition) }
		if id == 0 || !commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat, card_id = id, target = game.cell_target(position)}) { fmt.eprintf("M8 deployment %d failed\n", index); return false }
		if !m8_smoke_settle(window, renderer, dice, &room, &controller, &cards, &buffer, index == 4) {
			fmt.eprintf("M8 deployment presentation %d failed\n", index); return false
		}
	}
	if abs(player.tactical.remaining-9) > 0.01 || room.pulse_count != 0 || game.board_tesla_count(&room) != 4 { fmt.eprintln("M8 cast/world invariant failed"); return false }
	floor_index, floor_found := game.object_index_at(&room, positions[4])
	if !floor_found || room.objects[floor_index].device_armed || room.objects[floor_index].device_charges < 1 {
		fmt.eprintln("M8 dormant trap advanced during cast/cinematic"); return false
	}
	floor_id, floor_charges := room.objects[floor_index].id, room.objects[floor_index].device_charges
	// Show the anchored four-node network before its consuming mega combo.
	for _ in 0..<3 { m8_smoke_frame(window, renderer, dice, &room, &controller, &cards, &buffer, 0) }
	rl.TakeScreenshot("odin_pp_m8_devices.png")
	game.collect_weapon(&player, .Iron_Cleaver, 4)
	equip_button := render.m8_control_bounds(renderer, .Equip, &room)
	equip_command, equip_clicked := m8_pointer_gameplay_command(&room, renderer,
		{equip_button.x+equip_button.width/2,equip_button.y+equip_button.height/2}, true, true, true)
	if !equip_clicked || !commit_gameplay_command(&room, renderer, &cards, equip_command) { return false }
	// Equip advances a world beat. The enemy in the trap area trips it without an
	// active-item command. The controller drains the queued beat first, then
	// the committed floor state proves one discharge (or its final removal).
	if !m8_smoke_settle(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	floor_index, floor_found = game.object_index_by_id(&room, floor_id)
	if room.pulse_count != 1 || (floor_charges == 1 && floor_found) ||
	   (floor_charges > 1 && (!floor_found || !room.objects[floor_index].device_armed ||
	                         room.objects[floor_index].device_charges != floor_charges-1)) {
		fmt.eprintln("M8 passive trap did not trigger on the world beat"); return false
	}
	before_health := player.health
	active_button := render.m8_control_bounds(renderer, .Activate, &room)
	active_command, active_clicked := m8_pointer_gameplay_command(&room, renderer,
		{active_button.x+active_button.width/2,active_button.y+active_button.height/2}, true, true, true)
	if !active_clicked || !commit_gameplay_command(&room, renderer, &cards, active_command) { return false }
	if player.health >= before_health { fmt.eprintln("M8 field friendly fire missing"); return false }
	if game.board_tesla_count(&room) != 0 { fmt.eprintln("M8 mega combo did not consume its four coils"); return false }
	if !m8_smoke_settle(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	// Finish the independent world fades before the final-state capture, with
	// no additional gameplay time. Normal play remains free during these cues.
	for _ in 0..<60 {
		render.update_renderer_frame_timeline(renderer, 1.0/60.0)
		m8_smoke_frame(window, renderer, dice, &room, &controller, &cards, &buffer, 0)
	}
	rl.TakeScreenshot("odin_pp_m8_mega_combo.png")
	// Character model rendered in the same real native window.
	for _ in 0..<3 {
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_m8_character_panel(renderer, &room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	rl.TakeScreenshot("odin_pp_m8_character.png")
	// A scripted finisher uses the ordinary action resolver and phase epilogue.
	action := game.Action{kind = .Ability, source = game.PLAYER_ENTITY}
	for enemy in room.enemies { action.effects[action.effect_count] = {kind = .Damage, target = game.enemy_entity(enemy.id), amount = 100}; action.effect_count += 1 }
	if !game.resolve_action(&room, &action).accepted { return false }
	_, _ = game.finish_player_combat_command(&room, 0)
	if room.phase != .Loot || game.board_tesla_count(&room) != 0 { return false }
	render.clear_event_animations(renderer)
	for _ in 0..<90 { m8_smoke_frame(window, renderer, dice, &room, &controller, &cards, &buffer) }
	rl.TakeScreenshot("odin_pp_m8_loot.png")
	ring, entered := game.begin_ring_challenge(&room)
	if !entered { return false }
	// Exercise actual controls against the deterministic opponent, including all
	// four grab poses. The arena remains untouched while this modal runs.
	room_clock, room_pulse := player.tactical.remaining, room.pulse_count
    duel := Ring_Minigame{}
    ring_minigame_reset(&duel,{})
    defer destroy_m9_session(&duel.session)
    for tick in 0..<1800 {
        if duel.session.ring.result != .Active {break}
        ring_minigame_advance(&duel,1.0/60.0,true,ring_minigame_bot(&duel.session.ring))
        if tick%6==0 {
            app.begin_canvas(window,render.RESIN_BACKGROUND)
            v:=m9_view(&duel.session); v.hosted=true; v.alpha=1
            render.draw_m9_fight(renderer,&duel.session.ring,v)
            app.present(window,render.LETTERBOX_COLOR)
        }
    }
    ring.phase=.Won if duel.session.ring.result==.Won else .Lost
    if ring.phase != .Won || !game.settle_ring_challenge(&room,&ring).has_unlock || player.tactical.remaining != room_clock || room.pulse_count != room_pulse {
        fmt.eprintln("M8 canonical ring return failed"); return false
    }
	for _ in 0..<30 {
		if room.phase == .Complete { break }
		direction, found := m7_route_move(&room)
		if !found || !commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Loot, direction = direction}) { return false }
		if !m8_smoke_settle(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	}
	if room.phase != .Complete { return false }
	game.destroy_room(&room)
	room, built = game.create_room(&data, &player, {enemies = enemies[:]})
	if !built || player.tactical.cast_remaining != 0 || player.tactical.cycle != 0 || player.tactical.remaining != 20 { return false }
	render.clear_event_animations(renderer)
	for _ in 0..<2 { m8_smoke_frame(window, renderer, dice, &room, &controller, &cards, &buffer) }
	rl.TakeScreenshot("odin_pp_m8_next_room.png")
	fmt.println("M8 native: 5 casts, canonical d4 cinematic, passive trap, 4-Tesla field/consumption/friendlyfire, equip, loot, canonical ring/unlock, nextroom passed")
	return true
}
