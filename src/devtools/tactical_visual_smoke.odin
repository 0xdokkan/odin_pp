package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import rl "vendor:raylib"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"

Tactical_Visual_Capture :: enum { Cast, Move, Enemy_Damage, Player_Damage, Shield, Absorb, Interrupt, Spell_Flight, Spell_Impact }

Tactical_Visual_Probe :: struct {
	captured: bit_set[Tactical_Visual_Capture],
	frames, measured_frames: int,
	update_seconds, draw_seconds, draw_peak_seconds: f64,
}

tactical_visual_capture_path :: proc(capture: Tactical_Visual_Capture) -> cstring {
	switch capture {
	case .Cast:          return "odin_pp_m7_visual_cast.png"
	case .Move:          return "odin_pp_m7_visual_move.png"
	case .Enemy_Damage:  return "odin_pp_m7_visual_impact.png"
	case .Player_Damage: return "odin_pp_m7_visual_enemy_attack.png"
	case .Shield:        return "odin_pp_m7_visual_shield.png"
	case .Absorb:        return "odin_pp_m7_visual_absorb.png"
	case .Interrupt:     return "odin_pp_m7_visual_interrupt.png"
	case .Spell_Flight:  return "odin_pp_m7_visual_projectile.png"
	case .Spell_Impact:  return "odin_pp_m7_visual_spell_impact.png"
	}
	unreachable()
}

tactical_visual_capture_for_cue :: proc(cue: ^render.Presentation_Cue) -> (Tactical_Visual_Capture, bool) {
	if !cue.started || cue.duration <= 0 || cue.elapsed/cue.duration < 0.4 { return {}, false }
	#partial switch cue.kind {
	case .Card_Played:
		return .Cast, true
	case .Move:
		return .Move, cue.event.target == game.PLAYER_ENTITY || cue.event.source == game.PLAYER_ENTITY
	case .Damage:
		if cue.event.target == game.PLAYER_ENTITY { return .Player_Damage, true }
		return .Enemy_Damage, cue.event.target.kind == .Enemy
	case .Damage_Absorbed:
		return .Absorb, cue.event.target == game.PLAYER_ENTITY
	case .Spell_Launched:
		return .Spell_Flight, true
	case .Spell_Impact:
		return .Spell_Impact, true
	case .Status_Applied:
		if cue.event.status == .Shield { return .Shield, cue.event.target == game.PLAYER_ENTITY }
		return .Interrupt, cue.event.status == .Stagger
	}
	return {}, false
}

// Run the same cue progression headlessly or through the actual 3D canvas.
// Timing covers update + CPU draw submission only: present/vsync and PNG writes
// are outside the sample. It is deliberately not described as GPU frame time.
tactical_visual_frame :: proc(probe: ^Tactical_Visual_Probe, window: ^app.Window,
	renderer: ^render.Renderer, room: ^game.Room, selected: u32 = 0, dt: f32 = 1.0/60.0) -> bool {
	deck_random, dice_random := room.player.deck.random_state, room.player.dice.random_state
	started := f64(0)
	if window != nil { started = rl.GetTime() }
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_renderer_frame_timeline(renderer, dt)
	if window != nil {
		render.update_tactical_view(renderer, room, {}, false, true)
		render.update_tactical_atmosphere(renderer, dt)
		updated := rl.GetTime()
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, selected)
		render.draw_status(renderer, room, window.scale_mode)
		render.draw_tactical_hand(renderer, room, 0, selected, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		drawn := rl.GetTime()
		if probe.frames >= 3 {
			probe.measured_frames += 1
			probe.update_seconds += updated-started
			probe.draw_seconds += drawn-updated
			probe.draw_peak_seconds = max(probe.draw_peak_seconds, drawn-updated)
		}
		app.present(window, render.LETTERBOX_COLOR)
	}
	probe.frames += 1
	if !tactical_polish_check(renderer.timeline.update_failures == 0 && renderer.timeline.dropped_count == 0,
		"visual probe dropped or failed presentation cues") { return false }
	if !tactical_polish_check(deck_random == room.player.deck.random_state && dice_random == room.player.dice.random_state,
		"visual frame consumed authoritative gameplay RNG") { return false }
	for offset in 0..<render.renderer_active_cue_count(renderer) {
		cue, found := render.renderer_active_cue_at(renderer, offset)
		if !found { continue }
		capture, relevant := tactical_visual_capture_for_cue(cue)
		if !relevant || capture in probe.captured { continue }
		probe.captured += {capture}
		if window != nil { artifacts.screenshot(tactical_visual_capture_path(capture)) }
	}
	return true
}

tactical_visual_command :: proc(probe: ^Tactical_Visual_Probe, window: ^app.Window,
	renderer: ^render.Renderer, room: ^game.Room, cards: ^run_session.Card_Interaction_State,
	command: run_session.Gameplay_Command) -> bool {
	if !tactical_polish_check(run_session.commit_gameplay_command(room, renderer, cards, command),
		"visual probe command rejected") { return false }
	controller := run_session.Tactical_Controller{was_focused = true}
	buffer: run_session.Buffered_Gameplay_Command
	for _ in 0..<1200 {
		cast_dt := min(f32(1.0/60.0), room.player.tactical.cast_remaining)
		if !tactical_visual_frame(probe, window, renderer, room) { return false }
		if cast_dt > 0 {
			run_session.step_tactical_controller(&controller, room, renderer, cards, &buffer, cast_dt, true, {focused = true})
		}
		if render.renderer_timeline_is_busy(renderer) || game.tactical_is_casting(room) { continue }
		if room.qte.kind != .None {
			// An intentional failed defense exercises the enemy impact and shield
			// pipeline. No direct health/status or presentation-event fabrication.
			if !run_session.commit_gameplay_command(room, renderer, cards,
				{kind = .QTE_Fail, origin_phase = .Combat}) { return false }
		} else if room.tactical_pulse.pending {
			if !run_session.commit_gameplay_command(room, renderer, cards,
				{kind = .Continue_Pulse, origin_phase = .Combat}) { return false }
		} else if room.phase == .Combat && room.player.tactical.phase == .Decision &&
		          room.player.tactical.remaining <= 0 {
			// The controller delivers the deadline after all time charged by the
			// last action has resolved, never in the middle of its enemy beat.
			if !run_session.commit_gameplay_command(room, renderer, cards,
				{kind = .Timeout, origin_phase = .Combat}) { return false }
		} else { return true }
	}
	return tactical_polish_check(false, "visual probe timeline did not settle within 1200 frames")
}

tactical_visual_firebomb :: proc(probe: ^Tactical_Visual_Probe, window: ^app.Window,
	renderer: ^render.Renderer, data: ^level.Level) -> bool {
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 9
	if !created || !game.configure_tactical(&player, config) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 72) { return false }
	for id in ([?]game.Card_Id{.Firebomb, .Guard, .Dash, .Battle_Focus, .Strike}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{{position = {x = 8, y = 4}, health = 20, attack = 2, archetype = .Archer}}
	room, built := game.create_room(data, &player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	firebomb: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Firebomb { firebomb = card.id }
	}
	if firebomb == 0 { return false }
	cards: run_session.Card_Interaction_State
	if !tactical_visual_command(probe, window, renderer, &room, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = firebomb,
		 target = game.cell_target({x = 8, y = 4})}) { return false }
	return tactical_polish_check(.Spell_Flight in probe.captured && .Spell_Impact in probe.captured &&
		room.enemies[0].health < 20 && room.phase == .Combat &&
		room.pulse_count == 0 &&
		abs(player.tactical.remaining-(f32(config.timer_seconds)-game.tactical_card_time_cost(.Firebomb))) < 0.0001 &&
		room.qte.kind == .None && !room.tactical_pulse.pending,
		"visual Firebomb did not render its real flight and impact")
}

// A fixed real encounter gives repeatable mid-action screenshots. Heavy Blow
// interrupts a prepared attack, Guard absorbs an attack, later waits expose a
// normal enemy hit, and a final walk exercises the movement trail.
run_tactical_visual_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{
		"#############", "#...........#", "#..##.......#", "#..#........#",
		"#....@......#", "#...........#", "#...........#", "#.........>.#", "#############",
	}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 9
	if !created || !game.configure_tactical(&player, config) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 71) { return false }
	for id in ([?]game.Card_Id{.Heavy_Blow, .Guard, .Dash, .Battle_Focus, .Strike}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{{position = {x = 6, y = 4}, health = 20, attack = 3}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	previous_speed := render.renderer_playback_speed(renderer)
	if !render.set_renderer_playback_speed(renderer, 1) { return false }
	defer render.set_renderer_playback_speed(renderer, previous_speed)
	heavy, guard: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Heavy_Blow { heavy = card.id }
		if card.definition_id == .Guard { guard = card.id }
	}
	if heavy == 0 || guard == 0 { return false }
	probe: Tactical_Visual_Probe
	cards: run_session.Card_Interaction_State
	for _ in 0..<4 { if !tactical_visual_frame(&probe, window, renderer, &room, heavy) { return false } }
	if window != nil { artifacts.screenshot("odin_pp_m7_visual_arena.png") }
	if !tactical_visual_command(&probe, window, renderer, &room, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = heavy,
		 target = game.entity_target(game.enemy_entity(1))}) { return false }
	if !tactical_polish_check(room.enemies[0].health == 16 && .Interrupt in probe.captured &&
		player.health == player.stats.max_health, "visual Heavy Blow did not interrupt the real attack") { return false }
	// The cast freezes world beats: the first Wait now resolves the interrupt.
	if !tactical_visual_command(&probe, window, renderer, &room, &cards,
		{kind = .Wait, origin_phase = .Combat}) { return false }
	// Guard lasts two world seconds. Wait for the interrupted chaser to commit
	// its next attack and enter that shield window, rather than shielding its
	// recovery or the earlier part of the slower telegraph.
	for _ in 0..<8 {
		if room.enemies[0].intent.kind != .Recover &&
		   game.tactical_enemy_seconds(&room, &room.enemies[0]) <= 2 { break }
		if !tactical_visual_command(&probe, window, renderer, &room, &cards,
			{kind = .Wait, origin_phase = .Combat}) { return false }
	}
	if !tactical_visual_command(&probe, window, renderer, &room, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = guard,
		 target = game.entity_target(game.PLAYER_ENTITY)}) { return false }
	for _ in 0..<6 {
		if .Player_Damage in probe.captured { break }
		if !tactical_visual_command(&probe, window, renderer, &room, &cards,
			{kind = .Wait, origin_phase = .Combat}) { return false }
	}
	origin := player.position
	if !tactical_visual_command(&probe, window, renderer, &room, &cards,
		{kind = .Move, origin_phase = .Combat, direction = .West}) { return false }
	required := bit_set[Tactical_Visual_Capture]{.Cast, .Move, .Enemy_Damage, .Player_Damage, .Shield, .Absorb, .Interrupt}
	if !tactical_polish_check(probe.captured == required && player.position == game.add_position(origin, {x = -1, y = 0}) &&
		player.health < player.stats.max_health && room.phase == .Combat && room.qte.kind == .None &&
		!room.tactical_pulse.pending && !render.renderer_timeline_is_busy(renderer),
		"visual probe did not cover every feedback or leave a settled combat") {
		fmt.eprintf("M7 visual coverage: %v; health=%d; pulse=%d\n", probe.captured, player.health, room.pulse_count)
		return false
	}
	if !tactical_visual_firebomb(&probe, window, renderer, &data) { return false }
	if window != nil && probe.measured_frames > 0 {
		fmt.printf("M7 visual: %v; frames=%d; update_avg_ms=%.3f; draw_submit_avg_ms=%.3f; draw_submit_peak_ms=%.3f; excludes present/vsync, screenshots, GPU completion; timeline_errors=%d\n",
			probe.captured, probe.measured_frames, 1000*probe.update_seconds/f64(probe.measured_frames),
			1000*probe.draw_seconds/f64(probe.measured_frames), 1000*probe.draw_peak_seconds,
			renderer.timeline.update_failures)
	}
	return true
}
