package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// A fresh arena for an act of the party: the player in the middle, nothing on
// him and no window about to run out, no loot, no fire, no foe.
mechanics_lab_party_arena :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, name: string) -> bool {
	player := room.player
	// A free board and a window the card and what follows will not run out of.
	for _ in 0..<1200 {
		if player.tactical.phase == .Decision && player.tactical.remaining > 8 && !render.renderer_blocks_player_input(renderer) &&
		   !game.tactical_player_busy(room) && !game.tactical_is_casting(room) && !room.tactical_pulse.pending && room.qte.kind == .None { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if player.tactical.phase != .Decision || player.tactical.remaining <= 8 { fmt.eprintln("mechanics lab: no window for", name); return false }
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	clear(&room.loot)
	room.marley = {}
	room.ride = {}
	clear(&room.objects)
	player.tactical.config.shrinking_window = false
	player.health = player.stats.max_health
	player.position = {run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	player.equipment = {}
	for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	player.tactical.facing = .East
	player.tactical.dodge_recovery = 0
	return true
}

// INONDAZIONE (game/flood.odin), the deck's own copy dropped east of the
// player as the lane plays it. Four foes held about the arena, one beside the
// player to the west (the player stands in its way), one against the east
// wall, and two fires (the player's Incendio). The wave
// (odin_pp_living_flood_NN.png) crosses the arena from the west wall to the
// east, each of the two free foes pushed a cell as the front reaches it; the
// foe against the player and the one against the wall stay, nobody loses
// life, the player does not move, and both fires are out. Its sounds are
// counted by mechanics_lab_sounds_heard.
mechanics_lab_flood :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	foe :: mechanics_lab_enemy
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the Inondazione") { return false }
	free_a := grid.Position{center.x-6, center.y-3}
	free_b := grid.Position{center.x+3, center.y+3}
	wall := grid.Position{run_session.MECHANICS_LAB_WIDTH-2, center.y-2}
	beside := grid.Position{center.x-1, center.y}
	ids := [4]u32{spawn(room, free_a, 40), spawn(room, free_b, 40), spawn(room, wall, 40), spawn(room, beside, 40)}
	for id in ids { if id == 0 { fmt.eprintln("mechanics lab: no room for the Inondazione's foes"); return false } }
	for cell in ([2]grid.Position{{center.x+5, center.y-1}, {center.x-3, center.y+2}}) {
		action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
		if !game.add_effect(&action, game.place_ground_effect(cell, .Burn, 1)) || !game.resolve_action(room, &action).accepted {
			fmt.eprintln("mechanics lab: the fire at", cell, "was refused"); return false
		}
	}
	if room.ground.fire_count != 2 { fmt.eprintln("mechanics lab: no fires lit"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_flood_before.png")
	id, held := mechanics_lab_hand_card(player, .Flood_Wave)
	if !held { fmt.eprintln("mechanics lab: no Inondazione in hand"); return false }
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Flood.png")
	// The card held over the board: the arrow of its way from the mouse's cell
	// (east), and the way the wheel turned it to (north).
	render.set_flood_aim(renderer, true, false, .East)
	mechanics_lab_capture_aim(window, renderer, room, id, {center.x+2, center.y}, "odin_pp_mechanics_lab_flood_aim_east.png")
	render.set_flood_aim(renderer, true, true, .North)
	mechanics_lab_capture_aim(window, renderer, room, id, {center.x+2, center.y}, "odin_pp_mechanics_lab_flood_aim_north.png")
	render.set_flood_aim(renderer, false, false, .East)
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Flood_Wave, game.cell_target({center.x+2, center.y})) {
		fmt.eprintln("mechanics lab: the Inondazione was not played"); return false
	}
	frame := 0
	for _ in 0..<150 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "flood", 5, &frame)
		if frame > 20 && !render.renderer_blocks_player_input(renderer) && !game.tactical_is_casting(room) { break }
	}
	moved_a, moved_b := foe(room, ids[0]), foe(room, ids[1])
	stayed_wall, stayed_beside := foe(room, ids[2]), foe(room, ids[3])
	if moved_a == nil || moved_b == nil || stayed_wall == nil || stayed_beside == nil { fmt.eprintln("mechanics lab: a foe fell to the wave"); return false }
	if moved_a.position != (grid.Position{free_a.x+1, free_a.y}) || moved_b.position != (grid.Position{free_b.x+1, free_b.y}) {
		fmt.eprintln("mechanics lab: the wave pushed the free foes to", moved_a.position, moved_b.position); return false
	}
	if stayed_wall.position != wall || stayed_beside.position != beside { fmt.eprintln("mechanics lab: a foe against a blocker moved"); return false }
	for foe_id in ids { if enemy := foe(room, foe_id); enemy != nil && enemy.health != 40 { fmt.eprintln("mechanics lab: the wave hurt a foe"); return false } }
	if player.position != center || room.ground.fire_count != 0 { fmt.eprintln("mechanics lab: the player moved or a fire still burns"); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_flood_after.png")
	fmt.eprintf("mechanics lab flood: two foes pushed a cell, two held, both fires out, %d frames\n", frame)
	return true
}

// BOMB MARLEY (game/marley.odin), the deck's own copy played from the hand as
// the lane plays it. The player in the middle (his life made large for the
// act: the party's random bombs would end it), three foes held in one column
// four cells east, the first in a light, the second with one life, the third
// not, and two more elsewhere. The ball comes down over the cast
// (odin_pp_living_marley_NN.png, every sixth frame); then the lights and the
// column are set by the smoke (as the fishing act sets its catches) so that
// the bomb lands: it spares the foe in the light, kills the one with one life
// (and adds five seconds) and hurts the third; a second of the party later
// the lights turn on a schedule shown ahead, columns are warned two beats
// before they land; then the time is cut to one second and the party ends.
// Its sounds are counted by mechanics_lab_sounds_heard.
mechanics_lab_marley :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	foe :: mechanics_lab_enemy
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "Bomb Marley") { return false }
	// The party's random bombs would end the player: his life is made large
	// for the act and given back.
	stats_life := player.stats.max_health
	defer { player.stats.max_health = stats_life; player.health = min(player.health, stats_life); room.marley = {} }
	player.stats.max_health, player.health = 400, 400
	column := center.x+4
	lit := grid.Position{column, center.y-3}
	doomed := grid.Position{column, center.y+2}
	hurt := grid.Position{column, center.y+5}
	lit_id, doomed_id, hurt_id := spawn(room, lit, 99), spawn(room, doomed, 1), spawn(room, hurt, 99)
	other_a, other_b := spawn(room, {center.x-6, center.y-2}, 99), spawn(room, {center.x-7, center.y+4}, 99)
	for id in ([5]u32{lit_id, doomed_id, hurt_id, other_a, other_b}) { if id == 0 { fmt.eprintln("mechanics lab: no room for the party's foes"); return false } }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	id, held := mechanics_lab_hand_card(player, .Marley_Party)
	if !held { fmt.eprintln("mechanics lab: no Bomb Marley in hand"); return false }
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Bomb_Marley.png")
	// The film's script (as Mostra effetto's) fixes the first lights and the
	// first column, so that the bomb lands where this act wants it; the script
	// is dropped once it has landed and the party runs on its own.
	room.marley_demo = {scripted = true, lights = {lit, {}, {}}, light_count = 1,
		next_lights = {{center.x-5, center.y+1}, {center.x+7, center.y-6}, {}}, next_count = 2, column = column}
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Marley_Party, game.entity_target(game.PLAYER_ENTITY)) {
		fmt.eprintln("mechanics lab: Bomb Marley was not played"); return false
	}
	m := &room.marley
	if !m.active || m.remaining != game.MARLEY_SECONDS || m.damage != game.MARLEY_BASE_DAMAGE || m.light_count != 1 || m.next_count != 2 || !m.has_next {
		fmt.eprintln("mechanics lab: the party began with", m.remaining, "s,", m.damage, "damage and", m.light_count, "lights"); return false
	}
	frame := 0
	// The ball comes down and the cast ends.
	for _ in 0..<240 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "marley", 6, &frame)
		if frame > 30 && !game.tactical_is_casting(room) && !render.renderer_blocks_player_input(renderer) { break }
	}
	// The column is warned at the first beat and its bomb lands two beats on:
	// the foe in the light is spared.
	before := m.earned
	flights := 0
	for _ in 0..<420 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "marley", 6, &frame)
		// The bomb in flight, bouncing down its column: two stills of it.
		for offset in 0..<render.renderer_active_cue_count(renderer) {
			cue, showing := render.renderer_active_cue_at(renderer, offset)
			if !showing || !cue.started || cue.kind != .Marley_Bomb { continue }
			progress := render.presentation_cue_progress(cue)
			if flights == 0 && progress > 0.45 { artifacts.screenshot("odin_pp_mechanics_lab_marley_flight_a.png"); flights = 1 }
			if flights == 1 && progress > 0.72 { artifacts.screenshot("odin_pp_mechanics_lab_marley_flight_b.png"); flights = 2 }
		}
		// The party's earning is the beat's; its cues play after it.
		if m.earned > before && (flights == 2 || frame > 600) && !render.renderer_blocks_player_input(renderer) { break }
	}
	room.marley_demo = {}
	script_dropped := m.elapsed
	spared, killed, wounded := foe(room, lit_id), foe(room, doomed_id), foe(room, hurt_id)
	if spared == nil || spared.health != 99 { fmt.eprintln("mechanics lab: the foe in the light was hurt"); return false }
	if killed != nil { fmt.eprintln("mechanics lab: the foe with one life stood through the bomb"); return false }
	if wounded == nil || wounded.health != 99-game.MARLEY_BASE_DAMAGE { fmt.eprintln("mechanics lab: the third foe was not hurt"); return false }
	if m.earned != game.MARLEY_KILL_SECONDS || m.kills != 1 { fmt.eprintln("mechanics lab: the kill earned", m.earned, "seconds"); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_marley_bomb.png")
	// A few more seconds: the lights turn (shown ahead) and columns are warned.
	warned, ahead := false, false
	for _ in 0..<900 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "marley", 12, &frame)
		if m.column_count > 0 { warned = true }
		if m.has_next { ahead = true }
		if m.elapsed >= 9 && warned && ahead { break }
	}
	if !warned || !ahead { fmt.eprintln("mechanics lab: no column warned or no light shown ahead"); return false }
	// Once on its own the party lights many cells, and as many are on show.
	for _ in 0..<600 {
		// Two turns after the script's: the first lights the script's own next ones.
		if m.elapsed%game.MARLEY_LIGHT_CYCLE == 0 && m.elapsed >= script_dropped+2*game.MARLEY_LIGHT_CYCLE { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "marley", 12, &frame)
	}
	if m.light_count < 5 || m.next_count < 5 { fmt.eprintln("mechanics lab: the lights are few:", m.light_count, "and", m.next_count); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_marley_party.png")
	// The chip of the HUD holds whole beside the bites.
	chips := render.tactical_status_chip_layout(renderer, room)
	if chips.shown < 1 { fmt.eprintln("mechanics lab: no chip for the party"); return false }
	for index in 0..<chips.shown {
		if _, _, _, fit := render.gothic_text_fit_plan(renderer, chips.texts[index], chips.bounds[index].width-render.HUD_CHIP_TEXT_MARGIN, 12); fit != .Fits {
			fmt.eprintln("mechanics lab: the HUD chip", chips.texts[index], "does not hold in", chips.bounds[index].width, "px:", fit); return false
		}
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_marley_chip.png")
	// The end.
	m.remaining = 1
	for _ in 0..<300 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "marley_end", 6, &frame)
		if !m.active && !render.renderer_blocks_player_input(renderer) { break }
	}
	if m.active { fmt.eprintln("mechanics lab: the party did not end"); return false }
	for _ in 0..<60 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	fmt.eprintf("mechanics lab party: a bomb spared a foe in a light, killed one (+%d s) and hurt another, lights ahead, columns warned, %d frames\n",
		game.MARLEY_KILL_SECONDS, frame)
	return true
}
