package devtools
import run_session "../run"

import "core:fmt"
import "core:math"
import "core:strings"
import app "../engine/app"
import artifacts "artifacts"
import game "../game"
import level "../level"
import grid "../engine/grid"
import render "../render"

// BENVENUTI A NAPOLI (game/napoli.odin, docs/piano-napoli.md, Fase 0), in the
// real window, in the first person arena with its own deck: the card in hand
// (odin_pp_mechanics_lab_card_Napoli.png) and the banner's F12; then, for each
// face of the d4 fixed as F12 fixes it (run_session.mechanics_lab_fix_napoli_face),
// the card played afresh: the die rolls over the window and lands on that face,
// the panel names the branch and its number (odin_pp_napoli_dice_<face>.png, the
// roll as it settles), then the board over the player, until its word is gone
// (odin_pp_napoli_said_<face>.png; reels odin_pp_living_napoli_<face>_NN.png).
// Then the grandpa's visits (Fase 1, mechanics_lab_napoli_visits) and the club
// behind his back (Fase 2, mechanics_lab_napoli_club). Its foes are held, so
// every run sees the same.
mechanics_lab_napoli :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	// The arena afresh, the card back in hand.
	arena :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
		player := room.player
		game.destroy_room(room)
		player.health = player.stats.max_health
		rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
		if !built { fmt.eprintln("mechanics lab: the first person arena was not built for Benvenuti a Napoli"); return false }
		room^ = rebuilt
		render.clear_event_animations(renderer)
		controller^ = {was_focused = true}
		for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
		for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		_, held := mechanics_lab_hand_card(player, .Napoli)
		if !held { fmt.eprintln("mechanics lab: no Benvenuti a Napoli in the first person arena's hand"); return false }
		return true
	}
	if !arena(window, renderer, room, data, controller, cards, buffer) { return false }
	id, _ := mechanics_lab_hand_card(player, .Napoli)
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Napoli.png")
	// With the card in hand the banner names F12 and the face it fixed.
	renderer.tactical.mechanics_lab_napoli_face = 0
	if !strings.contains(string(render.mechanics_lab_banner_detail(renderer, room)), "F12 D4: A CASO") {
		fmt.eprintln("mechanics lab: the banner does not name F12:", render.mechanics_lab_banner_detail(renderer, room)); return false
	}
	// F12's turn: at random, 1, 2, 3, 4, at random again.
	turn := i32(0)
	for expected in ([5]i32{1, 2, 3, 4, 0}) {
		turn = run_session.mechanics_lab_next_napoli_face(turn)
		if turn != expected { fmt.eprintln("mechanics lab: F12 went to", turn, "instead of", expected); return false }
	}
	most := player.stats.max_health
	said: [4]i32
	for face in i32(1)..=4 {
		if !arena(window, renderer, room, data, controller, cards, buffer) { return false }
		renderer.tactical.mechanics_lab_napoli_face = face
		run_session.mechanics_lab_fix_napoli_face(room, face)
		failures := renderer.timeline.update_failures
		if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Napoli, game.entity_target(game.PLAYER_ENTITY)) {
			fmt.eprintln("mechanics lab: Benvenuti a Napoli was not played for the face", face); return false
		}
		branch := game.napoli_for_face(face)
		expected := game.napoli_face_amount(branch, 0, most)
		begun := false
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind != .Napoli_Begun { continue }
			begun = event.duration == face && event.amount == expected
			said[face-1] = event.amount
		}
		if !begun { fmt.eprintln("mechanics lab: the d4 fixed on", face, "did not open", game.napoli_face_name(branch), expected); return false }
		// The roll over the window, its panel naming the branch as it settles; then
		// the branch's word over the player, until the board is done showing.
		frame, rolled, named, said_shown := 0, false, false, false
		for _ in 0..<720 {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
			if frame%6 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_napoli_%d_%02d.png", face, frame/6)) }
			frame += 1
			cue, showing := render.active_presentation_cue(&renderer.timeline)
			if !rolled && showing && cue.kind == .Dice_Rolled && render.presentation_cue_progress(cue) > 0.86 {
				outcome := render.dice_presentation_outcome(&renderer.timeline)
				named = outcome.valid && outcome.napoli_face == face && outcome.napoli_amount == expected
				artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_dice_%d.png", face))
				rolled = true
			}
			for offset in 0..<render.renderer_active_cue_count(renderer) {
				said, active := render.renderer_active_cue_at(renderer, offset)
				if !active || said_shown || said.kind != .Napoli_Begun || !said.started || render.presentation_cue_progress(said) < 0.4 { continue }
				said_shown = string(render.napoli_begun_label(said.event)) == string(render.napoli_begun_label(game.Game_Event{duration = face, amount = expected}))
				artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_said_%d.png", face))
			}
			if rolled && !render.renderer_timeline_is_busy(renderer) && !render.renderer_blocks_player_input(renderer) { break }
		}
		if !rolled || !named || !said_shown {
			fmt.eprintln("mechanics lab: the face", face, "was not shown (rolled", rolled, "panel", named, "word over the player", said_shown, ")"); return false
		}
		if renderer.timeline.update_failures != failures { fmt.eprintln("mechanics lab: Benvenuti a Napoli's events failed the timeline"); return false }
	}
	fmt.eprintf("mechanics lab napoli: the card in hand, F12's turn; the d4 on 1 BASTONE %ds, 2 TAVOLATA +%d, 3 BORSELLINO +%d, 4 NONNO %d, each rolled and named\n",
		said[0], said[1], said[2], said[3])
	if !mechanics_lab_napoli_visits(window, renderer, dice, room, data, controller, cards, buffer, arena) { return false }
	if !mechanics_lab_napoli_club(window, renderer, dice, room, data, controller, cards, buffer, arena) { return false }
	return true
}

// Fase 1: the grandpa's visits. The player hurt (6 of 22), face 2: the grandpa
// comes while the world stands still (the board's clock held all his visit) and
// sets the table on the free cell farthest from the foes (reel
// odin_pp_napoli_table_NN.png); a step into it sits the player down, the cure
// coming in two halves on two beats, then the table is cleared (reel
// odin_pp_napoli_feast_NN.png). Face 3: the purse's gold, the world still for it
// too (reel odin_pp_napoli_purse_NN.png).
@(private = "file")
mechanics_lab_napoli_visits :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
	arena: proc(^app.Window, ^render.Renderer, ^game.Room, ^level.Level, ^run_session.Tactical_Controller, ^run_session.Card_Interaction_State,
		^run_session.Buffered_Gameplay_Command) -> bool) -> bool {
	player := room.player
		// The card played on `face`, filmed until the board is done; whether the
	// grandpa's visit showed, for its two seconds (the user's choice: 120
	// frames), with the world held all through it.
	visit :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room,
		controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
		face: i32, name: string) -> (seen, held: bool, frames: int) {
		renderer.tactical.mechanics_lab_napoli_face = face
		run_session.mechanics_lab_fix_napoli_face(room, face)
		if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Napoli, game.entity_target(game.PLAYER_ENTITY)) { return }
		held = true
		frame := 0
		clock := room.player.tactical.clock_fraction
		for _ in 0..<900 {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
			if _, visiting := render.napoli_visit_cue(renderer); visiting {
				if !seen { clock = room.player.tactical.clock_fraction }
				seen = true
				held = held && render.presentation_time_policy(&renderer.timeline) == .Cinematic && room.player.tactical.clock_fraction == clock
				if frame%6 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_%s_%02d.png", name, frame/6)) }
				frame += 1
			}
			if seen && !render.renderer_timeline_is_busy(renderer) && !render.renderer_blocks_player_input(renderer) { break }
		}
		frames = frame
		return
	}
	// The table.
	if !arena(window, renderer, room, data, controller, cards, buffer) { return false }
	player.health = 6
	seen, held, frames := visit(window, renderer, dice, room, controller, cards, buffer, 2, "table")
	index, laid := game.napoli_table_index(room)
	if !seen || !held || !laid || frames < 114 || frames > 126 {
		fmt.eprintln("mechanics lab: the grandpa's table visit (seen", seen, "world held", held, "table laid", laid, "frames", frames, ")"); return false
	}
	cell := room.objects[index].position
	way := cell
	way.x -= player.position.x
	way.y -= player.position.y
	if way.x != 0 && way.y != 0 { fmt.eprintln("mechanics lab: the table is set on a corner,", cell); return false }
	direction: game.Move_Direction = .North if way.y < 0 else .South if way.y > 0 else .West if way.x < 0 else .East
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = direction}) ||
	   !game.napoli_seated(room) {
		fmt.eprintln("mechanics lab: the step into the table did not sit the player down"); return false
	}
	frame := 0
	for _ in 0..<600 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
		if frame%6 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_feast_%02d.png", frame/6)) }
		frame += 1
		if !game.napoli_seated(room) && !render.renderer_timeline_is_busy(renderer) { break }
	}
	cure := game.napoli_face_amount(.Table, 0, player.stats.max_health)
	_, standing := game.napoli_table_index(room)
	if game.napoli_seated(room) || standing || player.health != 6+cure {
		fmt.eprintln("mechanics lab: the meal gave", player.health-6, "of", cure, "life; table still there", standing); return false
	}
	// The purse.
	if !arena(window, renderer, room, data, controller, cards, buffer) { return false }
	gold := player.gold
	seen, held, frames = visit(window, renderer, dice, room, controller, cards, buffer, 3, "purse")
	if !seen || !held || frames < 114 || frames > 126 || player.gold-gold != game.NAPOLI_PURSE_GOLD {
		fmt.eprintln("mechanics lab: the grandpa's purse (seen", seen, "world held", held, "frames", frames, "gold", player.gold-gold, ")"); return false
	}
	fmt.eprintf("mechanics lab napoli visits: the world held for the grandpa; the table on %v eaten for %d life in two beats; the purse %d gold\n",
		cell, cure, game.NAPOLI_PURSE_GOLD)
	return true
}

// Fase 2: the club behind his back. Face 1 played: the camera flies behind his
// right shoulder, BAN in the plate and the club's line; the brute three cells
// along a free way; the view turned to it, two steps of W, then three blows
// from above with the button: 8 each at least, staggered 2 beats, then 1, then
// none (reel odin_pp_napoli_club_NN.png, the floor's mark and the blow); then
// by a wall, looking away from it: the arm pressed short, the camera never in
// it (odin_pp_napoli_club_muro.png); the view ended, the camera back.
@(private = "file")
mechanics_lab_napoli_club :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
	arena: proc(^app.Window, ^render.Renderer, ^game.Room, ^level.Level, ^run_session.Tactical_Controller, ^run_session.Card_Interaction_State,
		^run_session.Buffered_Gameplay_Command) -> bool) -> bool {
	fp := &renderer.tactical.first_person
	reel := 0
	// A frame with `fire` held, a reel capture every sixth.
	frame :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, reel: ^int, fire := false) {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice, {focused = true, fire = fire})
		if reel^%6 == 0 && reel^/6 < 60 { artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_club_%02d.png", reel^/6)) }
		reel^ += 1
	}
	if !arena(window, renderer, room, data, controller, cards, buffer) { return false }
	renderer.tactical.mechanics_lab_napoli_face = 1
	run_session.mechanics_lab_fix_napoli_face(room, 1)
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Napoli, game.entity_target(game.PLAYER_ENTITY)) ||
	   !game.first_person_club_active(room) {
		fmt.eprintln("mechanics lab: face 1 did not take the club up"); return false
	}
	for _ in 0..<300 {
		if render.first_person_amount(renderer) >= 1 && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
	}
	if render.first_person_amount(renderer) < 1 || !render.first_person_third_person(renderer) ||
	   render.first_person_hud_status(renderer) != render.FIRST_PERSON_HUD_STATUS_CLUB || render.first_person_hides_player(renderer) {
		fmt.eprintln("mechanics lab: the camera did not come behind his back with the club"); return false
	}
	// The brute three cells along the first free way.
	brute := -1
	for foe, index in room.enemies { if foe.archetype == .Brute { brute = index } }
	if brute < 0 { fmt.eprintln("mechanics lab: no brute in the arena for the club"); return false }
	p := room.player.position
	way, found := game.Move_Direction.North, false
	for candidate in game.Move_Direction {
		d := game.direction_offset(candidate)
		free := true
		for k in 1..=3 {
			cell := game.add_position(p, {x = d.x*k, y = d.y*k})
			_, foe := game.enemy_index_at(room, cell)
			free = free && game.base_cell_is_walkable(room, cell) && !game.cell_blocks_movement(room, cell) && !foe
		}
		if free { way, found = candidate, true; break }
	}
	if !found { fmt.eprintln("mechanics lab: no free way three cells long for the club"); return false }
	d := game.direction_offset(way)
	room.enemies[brute].position = game.add_position(p, {x = d.x*3, y = d.y*3})
	room.enemies[brute].health = 60
	brute_id := room.enemies[brute].id
	mechanics_lab_hold(room, brute_id)
	// The view turned to it, a little at a time.
	from := fp.yaw
	turn := render.first_person_wrap(game.first_person_yaw(way)-from)
	for k in 1..=20 {
		fp.yaw = from+turn*f32(k)/20
		frame(window, renderer, dice, room, controller, cards, buffer, &reel)
	}
	// Two steps of W, the way the view looks.
	for _ in 0..<2 {
		keys := render.first_person_keys(renderer)
		if keys[0] != way { fmt.eprintln("mechanics lab: W does not step the way the view looks:", keys[0], way); return false }
		if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = keys[0]}) {
			fmt.eprintln("mechanics lab: the club's step was not taken"); return false
		}
		for _ in 0..<30 { frame(window, renderer, dice, room, controller, cards, buffer, &reel) }
	}
	if room.player.position != game.add_position(p, {x = d.x*2, y = d.y*2}) {
		fmt.eprintln("mechanics lab: two steps did not bring him next to the brute:", room.player.position); return false
	}
	index, _ := game.enemy_index_by_id(room, brute_id)
	if fp.club.aimed != room.enemies[index].position || !fp.club.reaches {
		fmt.eprintln("mechanics lab: the floor's mark is not on the brute:", fp.club.aimed); return false
	}
	// Three blows: 8 the first, staggered 2, 1, then none.
	club := &room.first_person.club
	wanted := [3]i32{2, 1, 0}
	brute_entity := game.enemy_entity(brute_id)
	// Fase 3: the first blow's squash, filmed (odin_pp_napoli_squash_NN.png): its
	// lowest height and its end; then the brute's stars.
	lowest, squash_shots := f32(1), 0
	squash :: proc(renderer: ^render.Renderer, entity: game.Entity_Ref, lowest: ^f32, shots: ^int) {
		height, _ := render.juice_squash(renderer, entity)
		lowest^ = min(lowest^, height)
		if height != 1 && shots^ < 40 {
			artifacts.screenshot(fmt.ctprintf("odin_pp_napoli_squash_%02d.png", shots^))
			shots^ += 1
		}
	}
	for beats, k in wanted {
		frame(window, renderer, dice, room, controller, cards, buffer, &reel)
		index, _ = game.enemy_index_by_id(room, brute_id)
		health := room.enemies[index].health
		impacts := club.impacts
		for _ in 0..<90 {
			frame(window, renderer, dice, room, controller, cards, buffer, &reel, club.impacts == impacts)
			if k == 0 { squash(renderer, brute_entity, &lowest, &squash_shots) }
			if club.impacts > impacts && !club.blow.active { break }
		}
		if k == 0 {
			for _ in 0..<60 {
				height, _ := render.juice_squash(renderer, brute_entity)
				if height == 1 && lowest < 1 { break }
				frame(window, renderer, dice, room, controller, cards, buffer, &reel)
				squash(renderer, brute_entity, &lowest, &squash_shots)
			}
			height, width := render.juice_squash(renderer, brute_entity)
			if lowest > render.JUICE_SQUASH_LOW+0.05 || height != 1 || width != 1 {
				fmt.eprintln("mechanics lab: the brute's card squashed to", lowest, "and ended at", height, width); return false
			}
			if !render.juice_club_shows_stars(renderer, brute_entity) {
				fmt.eprintln("mechanics lab: no stars over the staggered brute"); return false
			}
			artifacts.screenshot("odin_pp_napoli_stelline.png")
		}
		index, _ = game.enemy_index_by_id(room, brute_id)
		lost := health-room.enemies[index].health
		if club.impacts != impacts+1 || club.last.hit != .Foe || club.last.stagger != beats || lost != club.last.damage || lost < game.NAPOLI_CLUB_DAMAGE ||
		   (k == 0 && lost != game.NAPOLI_CLUB_DAMAGE) {
			fmt.eprintln("mechanics lab: blow", k+1, "took", lost, "staggered", club.last.stagger, "not", beats, "(impacts", club.impacts, ")"); return false
		}
		for _ in 0..<12 { frame(window, renderer, dice, room, controller, cards, buffer, &reel) }
	}
	// The killing blow: a pancake (odin_pp_napoli_frittella.png).
	index, _ = game.enemy_index_by_id(room, brute_id)
	room.enemies[index].health = 5
	for _ in 0..<40 { frame(window, renderer, dice, room, controller, cards, buffer, &reel) }
	kills := renderer.tactical.juice_blows.kills
	impacts := club.impacts
	for _ in 0..<90 {
		frame(window, renderer, dice, room, controller, cards, buffer, &reel, club.impacts == impacts)
		if club.impacts > impacts && !club.blow.active { break }
	}
	for _ in 0..<10 { frame(window, renderer, dice, room, controller, cards, buffer, &reel) }
	artifacts.screenshot("odin_pp_napoli_frittella.png")
	flat, _ := render.juice_squash(renderer, brute_entity)
	if _, alive := game.enemy_index_by_id(room, brute_id); alive || renderer.tactical.juice_blows.kills != kills+1 || abs(flat-render.JUICE_PANCAKE) > 0.01 {
		fmt.eprintln("mechanics lab: the killing blow left no pancake (alive", alive, "height", flat, ")"); return false
	}
	// By a wall, looking away from it: a free cell with a wall to its west.
	walled: grid.Position
	wall_found := false
	search: for y in 1..<data.tiles.height-1 {
		for x in 2..<data.tiles.width-1 {
			cell := grid.Position{x = x, y = y}
			_, foe := game.enemy_index_at(room, cell)
			if game.base_cell_is_walkable(room, cell) && !game.cell_blocks_movement(room, cell) && !foe &&
			   !game.base_cell_is_walkable(room, {x = x-1, y = y}) {
				walled, wall_found = cell, true
				break search
			}
		}
	}
	if !wall_found { fmt.eprintln("mechanics lab: no cell by a wall for the club's camera"); return false }
	room.player.position = walled
	fp.yaw, fp.pitch = 0, 0
	for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice) }
	camera := renderer.tactical.camera.position
	behind := grid.Position{x = int(math.floor(camera.x)), y = int(math.floor(camera.z))}
	artifacts.screenshot("odin_pp_napoli_club_muro.png")
	if fp.club.arm > 0.7 || !game.base_cell_is_walkable(room, behind) {
		fmt.eprintln("mechanics lab: by the wall the arm is", fp.club.arm, "and the camera in", behind); return false
	}
	arm := fp.club.arm
	// The view over: the camera back to the board.
	room.first_person.remaining = 0.01
	for _ in 0..<120 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
		if render.first_person_amount(renderer) <= 0 { break }
	}
	if game.tactical_first_person_active(room) || render.first_person_amount(renderer) > 0 {
		fmt.eprintln("mechanics lab: the club's view did not end"); return false
	}
	fmt.eprintf("mechanics lab napoli club: behind his back, two steps of W, three blows of %d staggering 2, 1, 0, squashed to %.2f, stars; a pancake; the arm by the wall %.2f\n",
		game.NAPOLI_CLUB_DAMAGE, lowest, arm)
	return true
}
