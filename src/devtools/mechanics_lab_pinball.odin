package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import "core:math"
import "core:strings"
import app "../engine/app"
import audio "../engine/audio"
import game "../game"
import grid "../engine/grid"
import render "../render"

// PINBALL (game/pinball.odin), the deck's own copy played from the hand as
// the lane plays it, after the Lazzo. The player in the middle of a fresh
// arena, an archer poisoned beside him to the east (the only archer: its
// card's voice must never sound), the Custodian beside him to the south-west,
// a brute two cells off, three chasers set in a row for the ball and chasers
// and brutes about the arena, all held; the room's stream set to turn the
// launch thirty degrees to the left (smoke state, as the fishing act sets its
// catches), so the row stands on the runs it takes. Its words hold on the
// hand's cards at every level; the card under the mouse
// (odin_pp_mechanics_lab_card_Pinball.png), its aim on the archer
// (odin_pp_mechanics_lab_pinball_preview.png) and on the Custodian, too heavy
// for the rule and for the drop (odin_pp_mechanics_lab_pinball_heavy.png); the
// brute is out of reach. The strike (odin_pp_living_pinball_strike_NN.png):
// energy -3, the poison's tag gone, the world still through the cast and the
// ball with it, the player's swing set to land as the cast ends, the launch
// turned the stream's thirty degrees off the line from him to the archer. The
// roll (odin_pp_living_pinball_NN.png, the camera standing back, its middle
// run fast with no captures):
// at every frame the ball's disc clear of every solid cell, its way a unit,
// its foe's life untouched, and a blow, a status, an arrow or a card's anchor
// on it refused; the row struck for 2, 3 and 4, each chaser knocked a cell
// away, then the north wall puts 5 back to 2; every foe it strikes takes the
// value, one more each time, every solid thing it touches puts it back to the
// card's, each push one cell away from it, a star on the board for each; it
// rolls over the player and he loses nothing; the HUD's chip holds whole
// beside the bites and the charges (odin_pp_mechanics_lab_pinball_chip.png); a
// step of the player's mid-roll and the world's beats all along, one a second.
// At twenty seconds of the ball's own (the world's) time it bursts
// (odin_pp_living_pinball_burst_NN.png, the camera further back): the archer
// falls there, its loot dropped there, no ghost of its card, and the room
// fights on. Its sounds all played, the player's lantern and the archer's
// voice never.
mechanics_lab_pinball :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{x = run_session.MECHANICS_LAB_WIDTH/2, y = run_session.MECHANICS_LAB_HEIGHT/2}
	foe :: mechanics_lab_enemy
	spawn :: mechanics_lab_spawn_enemy
	// The aim as the board shows it with the mouse on `cell`.
	aim :: mechanics_lab_capture_aim
	// A free board and a window the strike and a step after it will not run out of.
	for _ in 0..<1200 {
		if player.tactical.phase == .Decision && player.tactical.remaining > 8 && !render.renderer_blocks_player_input(renderer) &&
		   !game.tactical_player_busy(room) && !game.tactical_is_casting(room) && !room.tactical_pulse.pending && room.qte.kind == .None { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if player.tactical.phase != .Decision || player.tactical.remaining <= 8 { fmt.eprintln("mechanics lab: no window for the Pinball"); return false }
	// A fresh arena, the player in the middle facing east, nothing on him.
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	clear(&room.loot)
	player.health = player.stats.max_health
	player.position = center
	player.equipment = {}
	for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	player.tactical.facing = .East
	player.tactical.dodge_recovery = 0
	target := grid.offset(center, 1, 0)
	BALL_HEALTH :: i32(30)
	BUMPER_HEALTH :: i32(99)
	target_id := spawn(room, target, BALL_HEALTH, .Archer)
	custodian := grid.offset(center, -1, 1)
	custodian_id := spawn(room, custodian, BUMPER_HEALTH, .Custodian)
	far := grid.offset(center, 2, -2)
	far_id := spawn(room, far, BUMPER_HEALTH, .Brute)
	if target_id == 0 || custodian_id == 0 || far_id == 0 { fmt.eprintln("mechanics lab: no room for the Pinball's foes"); return false }
	_, _ = game.apply_status(room, game.enemy_entity(target_id), .Poison, 2, 0)
	// The room's stream set to turn the launch thirty degrees to the left: the
	// first of the row on the strike's first run, four cells out; the ball
	// comes off it onto the second (two cells south of the player and two
	// east) and off that onto the third (four north, one west), then the north
	// wall.
	LAUNCH_TURN :: i32(-30)
	stream := u64(0)
	for seed in u64(1)..<10_000 {
		random := seed
		if game.pinball_launch_turn(&random) == LAUNCH_TURN { stream = seed; break }
	}
	if stream == 0 { fmt.eprintln("mechanics lab: no stream for the Pinball's launch"); return false }
	room.pinball_random = stream
	heading, turn := game.pinball_next_launch(room, target)
	if turn != LAUNCH_TURN { fmt.eprintln("mechanics lab: the Pinball's stream turns its launch", turn, "degrees"); return false }
	row := [3]grid.Position{grid.offset(target, int(math.round(heading.x*4)), int(math.round(heading.y*4))), grid.offset(center, 2, 2), grid.offset(center, -1, -4)}
	row_ids: [3]u32
	for cell, index in row {
		row_ids[index] = spawn(room, cell, BUMPER_HEALTH, .Chaser)
		if row_ids[index] == 0 { fmt.eprintln("mechanics lab: no room for the Pinball's row on", cell); return false }
	}
	for cell in ([4]grid.Position{{x = 4, y = 4}, {x = 5, y = 12}, {x = 18, y = 12}, {x = 17, y = 3}}) {
		_ = spawn(room, cell, BUMPER_HEALTH, .Brute if cell.y > center.y else .Chaser)
	}
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	card, held := mechanics_lab_hand_card(player, .Pinball)
	if !held { fmt.eprintln("mechanics lab: no Pinball in hand"); return false }
	slot, _ := game.hand_card_index_by_id(&player.deck, card)
	instance := player.deck.hand[slot]
	definition, _ := game.card_definition_by_id(.Pinball)
	// Its words hold on the hand's own cards at every level, and in the inspector.
	width := render.tactical_hand_card_bounds(renderer, 0, player.deck.hand_count).width
	words := instance
	for {
		if misfit := render.tactical_card_text_misfit(renderer, words, definition, width); misfit != "" {
			fmt.eprintf("mechanics lab: Pinball +%d on a %.0f px card: %s\n", words.upgrade_level, width, misfit); return false
		}
		if !game.card_can_upgrade(words) { break }
		words.upgrade_level += 1
	}
	mechanics_lab_still(window, renderer, room, card, "odin_pp_mechanics_lab_card_Pinball.png")
	aim(window, renderer, room, card, target, "odin_pp_mechanics_lab_pinball_preview.png")
	// The Custodian is a miniboss: too heavy for the rule and for the drop; the
	// brute two cells off is out of reach.
	_, takes := game.card_drop_target(room, instance, custodian)
	if takes || game.pinball_target_error(room, game.entity_target(game.enemy_entity(custodian_id))) != .Target_Too_Heavy {
		fmt.eprintln("mechanics lab: the Pinball took the Custodian"); return false
	}
	if refusal := game.evaluate_card_targeting(room, instance, game.card_target_request_at(definition, far)).error; refusal != .Target_Out_Of_Range {
		fmt.eprintln("mechanics lab: the Pinball reached two cells off:", refusal); return false
	}
	aim(window, renderer, room, card, custodian, "odin_pp_mechanics_lab_pinball_heavy.png")
	// The strike: the card's cast, the world still.
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds before the Pinball"); return false }
	heard := sounds.played
	view := &renderer.tactical.pinball
	makes, strikes, bursts := view.makes, view.strikes, view.bursts
	stars_bumps, stars_bounces := view.bumps, view.bounces
	pulses, health := room.pulse_count, player.health
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Pinball, game.entity_target(game.enemy_entity(target_id))) ||
	   !room.pinball.active || room.pinball.enemy_id != target_id || room.pinball.turn != turn {
		fmt.eprintln("mechanics lab: the Pinball did not take the archer"); return false
	}
	ball := foe(room, target_id)
	if player.deck.energy != player.deck.rules.max_energy-definition.cost || ball == nil || ball.statuses.count != 0 || room.pinball.value != 2 {
		fmt.eprintln("mechanics lab: the strike left energy", player.deck.energy, "and the ball's statuses"); return false
	}
	// Struck away from him: the line from him to the archer, turned its
	// fifteen to thirty-five degrees (the stream's thirty, to the left).
	launch := game.pinball_launch_heading(center, target, turn)
	if abs(room.pinball.heading.x-launch.x) > 1e-12 || abs(room.pinball.heading.y-launch.y) > 1e-12 ||
	   abs(turn) < game.PINBALL_MIN_TURN || abs(turn) > game.PINBALL_MAX_TURN {
		fmt.eprintln("mechanics lab: the ball left along", room.pinball.heading, "for", launch, "at", turn, "degrees"); return false
	}
	frame := 0
	cast_end := f64(-1)
	roll_pulses := room.pulse_count
	for _ in 0..<300 {
		if !game.tactical_is_casting(room) && !render.renderer_blocks_player_input(renderer) { break }
		casting := game.tactical_is_casting(room)
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "pinball_strike", 4, &frame)
		if casting && !game.tactical_is_casting(room) && cast_end < 0 { cast_end, roll_pulses = renderer.sprite_assets.elapsed, room.pulse_count }
		if game.tactical_is_casting(room) && (room.pulse_count != pulses || room.pinball.run != 0 || room.pinball.before != 0) {
			fmt.eprintln("mechanics lab: the world moved in the Pinball's strike"); return false
		}
	}
	if view.makes != makes+1 || view.strikes != strikes+1 || cast_end < 0 || abs(view.contact-cast_end) > 1.5/60.0 {
		fmt.eprintln("mechanics lab: the strike was not shown: made", view.makes-makes, "struck", view.strikes-strikes, "contact", view.contact, "cast end", cast_end); return false
	}
	// The roll: twenty seconds of the world's own time, the contacts read off
	// the world's cues in order.
	value, base := room.pinball.base, room.pinball.base
	bumps, bounces, pushes, resets, top := 0, 0, 0, 0, i32(0)
	taken: [game.MAX_ENEMIES_PER_ROOM]struct{id: u32, amount: i32}
	taken_count := 0
	// The first four contacts (the row's three and the wall after them).
	Contact :: struct {
		bump, pushed: bool,
		id: u32,
		value: i32,
	}
	opening: [4]Contact
	contacts := 0
	order := strings.builder_make(context.temp_allocator)
	last_bumped: game.Entity_Ref
	last_ball_cell: grid.Position
	seen_batch := renderer.cue_batches
	burst_cell := room.pinball.cell
	burst_seen, loot_seen := false, false
	stepped, chip_shot, refused := false, false, false
	stepped_from: grid.Position
	shot, burst_shot, rolled_frames := 0, 0, 0
	passes, over := 0, false
	last_rolled := f64(0)
	// The camera stands back for the roll, so the row and the north wall stay
	// in sight, and further for the burst, which may come anywhere in the arena.
	distance := renderer.tactical.world_orbit.distance
	renderer.tactical.world_orbit.distance = 18
	for _ in 0..<4000 {
		if !room.pinball.active { break }
		rolled := game.pinball_rolled(&room.pinball)
		last_rolled = rolled
		dt := f32(1.0/60.0)
		// Its middle runs fast with nothing saved: the roll is the same at any
		// frame rate.
		fast := rolled >= 3 && rolled < 19.5
		if fast { dt = 0.1 }
		if rolled >= 19.3 { renderer.tactical.world_orbit.distance = 24 }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, dt, true)
		if !fast {
			if rolled < 19.5 && rolled_frames%(3 if rolled < 2.6 else 20) == 0 {
				artifacts.screenshot(fmt.ctprintf("odin_pp_living_pinball_%02d.png", shot)); shot += 1
			} else if rolled >= 19.5 && rolled_frames%2 == 0 {
				artifacts.screenshot(fmt.ctprintf("odin_pp_living_pinball_burst_%02d.png", burst_shot)); burst_shot += 1
			}
		}
		rolled_frames += 1
		if room.pinball.active {
			s := &room.pinball
			p := game.pinball_position(s)
			for dy in -1..=1 {
				for dx in -1..=1 {
					cell := grid.offset(s.cell, dx, dy)
					if !game.lasso_cell_is_solid(room, cell) { continue }
					closest := [2]f64{clamp(p.x, f64(cell.x)-0.5, f64(cell.x)+0.5), clamp(p.y, f64(cell.y)-0.5, f64(cell.y)+0.5)}
					if math.hypot(p.x-closest.x, p.y-closest.y) < game.PINBALL_RADIUS-1e-6 {
						fmt.eprintln("mechanics lab: the ball at", p, "sinks into", cell); return false
					}
				}
			}
			if abs(math.hypot(s.heading.x, s.heading.y)-1) > 1e-9 { fmt.eprintln("mechanics lab: the ball's way is no unit:", s.heading); return false }
			if ball = foe(room, target_id); ball == nil || ball.health != BALL_HEALTH { fmt.eprintln("mechanics lab: the ball was hurt"); return false }
			// It rolls over the player: its disc on his cell.
			at := player.position
			near := [2]f64{clamp(p.x, f64(at.x)-0.5, f64(at.x)+0.5), clamp(p.y, f64(at.y)-0.5, f64(at.y)+0.5)}
			now_over := math.hypot(p.x-near.x, p.y-near.y) < game.PINBALL_RADIUS
			if now_over && !over { passes += 1 }
			over = now_over
			// Nothing reaches the ball: a blow is refused, no status takes, no
			// arrow aims at it and no card finds it on its cell.
			if !refused && rolled >= 0.5 {
				refused = true
				ball_entity := game.enemy_entity(target_id)
				blow := game.make_action(.Attack, game.PLAYER_ENTITY)
				if !game.add_effect(&blow, game.damage_effect(ball_entity, 5)) { fmt.eprintln("mechanics lab: no blow for the ball"); return false }
				index, standing := game.enemy_index_at(room, s.cell)
				if game.resolve_action(room, &blow).accepted || game.can_apply_status(room, ball_entity, .Poison) ||
				   game.player_arrow_target_is_valid(room, ball_entity) || (standing && room.enemies[index].id == target_id) {
					fmt.eprintln("mechanics lab: a blow, a status, an arrow or a card reached the ball"); return false
				}
			}
		}
		// The contacts of every batch the world gave this frame, in order.
		newest := seen_batch
		if world := renderer.world_playback; world != nil {
			for &entry in world.cues[:world.count] {
				cue := &entry.cue
				if cue.batch <= seen_batch { continue }
				newest = max(newest, cue.batch)
				event := cue.event
				#partial switch cue.kind {
				case .Pinball_Bumped:
					if event.amount != value {
						fmt.eprintln("mechanics lab: a foe took", event.amount, "where the ball's value was", value); return false
					}
					if contacts < len(opening) { opening[contacts] = {bump = true, id = event.target.id, value = event.amount} }
					contacts += 1
					fmt.sbprintf(&order, "%d ", event.amount)
					top = max(top, event.amount)
					value += 1
					bumps += 1
					last_bumped, last_ball_cell = event.target, event.from_position
					found := false
					for &bumper in taken[:taken_count] {
						if bumper.id == event.target.id { bumper.amount += event.amount; found = true }
					}
					if !found && taken_count < len(taken) { taken[taken_count] = {event.target.id, event.amount}; taken_count += 1 }
				case .Pinball_Bounced:
					if event.duration != value || event.amount != base || !game.lasso_cell_is_solid(room, event.to_position) {
						fmt.eprintln("mechanics lab: a wall found the value", event.duration, "for", value, "and put it back to", event.amount,
							"off", event.to_position); return false
					}
					if contacts < len(opening) { opening[contacts] = {value = event.duration} }
					contacts += 1
					fmt.sbprintf(&order, "W%d ", event.duration)
					if event.duration > base { resets += 1 }
					value = base
					bounces += 1
				case .Move:
					// The foe just struck pushed one cell, away from the ball.
					if event.kind != .Moved || event.target != last_bumped || event.source != game.PLAYER_ENTITY { continue }
					d := grid.offset(event.to_position, -event.from_position.x, -event.from_position.y)
					away := grid.offset(event.from_position, -last_ball_cell.x, -last_ball_cell.y)
					if max(abs(d.x), abs(d.y)) != 1 || d.x*away.x+d.y*away.y <= 0 {
						fmt.eprintln("mechanics lab: a foe struck from", last_ball_cell, "was pushed from", event.from_position, "to", event.to_position); return false
					}
					if contacts > 0 && contacts <= len(opening) && opening[contacts-1].bump && opening[contacts-1].id == event.target.id {
						opening[contacts-1].pushed = true
					}
					pushes += 1
					last_bumped = {}
				case .Pinball_Burst:
					// Where it burst: the cell under it then.
					burst_seen = event.target == game.enemy_entity(target_id) && event.from_position == event.to_position
					burst_cell = event.to_position
				case .Loot_Dropped:
					if burst_seen && event.source == game.enemy_entity(target_id) && event.from_position == burst_cell { loot_seen = true }
				}
			}
		}
		seen_batch = newest
		// A step of the player's while it rolls, a second into it.
		if !stepped && room.pinball.active && rolled > 1 && game.tactical_allows_action(room) && !render.renderer_blocks_player_input(renderer) {
			for direction in ([4]game.Move_Direction{.North, .South, .West, .East}) {
				destination := game.add_position(player.position, game.direction_offset(direction))
				if _, occupied := game.enemy_index_at(room, destination); occupied || game.lasso_cell_is_solid(room, destination) { continue }
				stepped_from = player.position
				if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = direction}) ||
				   player.position != destination {
					fmt.eprintln("mechanics lab: the step while the ball rolls was refused"); return false
				}
				stepped = true
				break
			}
		}
		// A still of the HUD's chip beside the bites and the charges, the row
		// struck (its value 5). Then its words
		// hold in its chip with two figures of value, beside them (short) and
		// alone (whole).
		if !chip_shot && rolled >= 1.7 && room.pinball.active {
			chip_shot = true
			_, _ = game.apply_status(room, game.PLAYER_ENTITY, .Poison, 2, 0)
			_, _ = game.apply_status(room, game.PLAYER_ENTITY, .Burn, 1, 0)
			_, _ = game.apply_status(room, game.PLAYER_ENTITY, .Deflect, 1, 0)
			_, _ = game.apply_status(room, game.PLAYER_ENTITY, .Arrows, 2, 0)
			mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_pinball_chip.png")
			now_value := room.pinball.value
			room.pinball.value = 99
			for alone in ([2]bool{false, true}) {
				if alone {
					for kind in ([4]game.Status_Kind{.Poison, .Burn, .Deflect, .Arrows}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
				}
				// The board shows him as he is first.
				render.update_tactical_view(renderer, room, {}, false, true)
				chips := render.tactical_status_chip_layout(renderer, room)
				if chips.shown != (1 if alone else 3) || chips.more != (0 if alone else 2) || string(chips.texts[0 if alone else 2])[:3] != "PIN" {
					fmt.eprintln("mechanics lab: the ball's chip is not after the bites, or not alone"); return false
				}
				for index in 0..<chips.shown {
					text := chips.texts[index]
					if _, _, _, fit := render.gothic_text_fit_plan(renderer, text, chips.bounds[index].width-render.HUD_CHIP_TEXT_MARGIN, 12); fit != .Fits {
						fmt.eprintln("mechanics lab: the HUD's chip", text, "does not hold in", chips.bounds[index].width, "px:", fit); return false
					}
				}
			}
			room.pinball.value = now_value
			render.update_tactical_view(renderer, room, {}, false, true)
		}
	}
	if room.pinball.active { fmt.eprintln("mechanics lab: the ball never burst"); return false }
	// It burst in the frame that took it to twenty seconds of its own, the
	// world's: as many beats ran meanwhile, one a second.
	beats := room.pulse_count-roll_pulses
	if last_rolled >= game.PINBALL_SECONDS || last_rolled < game.PINBALL_SECONDS-1.0/60.0-1e-6 || beats < 19 || beats > 21 {
		fmt.eprintln("mechanics lab: the ball burst after", last_rolled, "s of its own and", beats, "beats"); return false
	}
	// The burst on the board, its paper and its confetti.
	for after in 0..<50 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if after%2 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_pinball_burst_%02d.png", burst_shot)); burst_shot += 1 }
		if render.living_find_dying(renderer, game.enemy_entity(target_id)) != nil { fmt.eprintln("mechanics lab: the ball's card fell as a ghost"); return false }
	}
	renderer.tactical.world_orbit.distance = distance
	if foe(room, target_id) != nil || room.phase != .Combat || !burst_seen || !loot_seen || view.bursts != bursts+1 {
		fmt.eprintln("mechanics lab: the ball did not burst on", burst_cell, "foe", foe(room, target_id) != nil, "burst", burst_seen, "loot", loot_seen); return false
	}
	if bumps < 3 || bounces < 3 || pushes < 3 || !stepped || player.position == stepped_from || player.health != health || passes < 1 || !refused {
		fmt.eprintln("mechanics lab: the roll made", bumps, "bumps,", bounces, "bounces,", pushes, "pushes, stepped", stepped, "health", player.health,
			"of", health, "over the player", passes, "refused", refused); return false
	}
	// The row: struck for 2, 3 and 4 in turn, each knocked a cell away; then a
	// wall put 5 back to 2. Later on the value climbed again and walls put it
	// back as often.
	for index in 0..<3 {
		o := opening[index]
		if !o.bump || o.id != row_ids[index] || o.value != base+i32(index) || !o.pushed {
			fmt.eprintln("mechanics lab: contact", index, "was not the row's", index, "struck for", base+i32(index), "and pushed:", o); return false
		}
	}
	if opening[3].bump || opening[3].value != base+3 || top < base+2 || resets < 1 {
		fmt.eprintln("mechanics lab: after the row", opening[3], "top", top, "resets", resets); return false
	}
	// A star on the board for every contact.
	if view.bumps-stars_bumps != bumps || view.bounces-stars_bounces != bounces {
		fmt.eprintln("mechanics lab: the board showed", view.bumps-stars_bumps, "red stars for", bumps, "foes and", view.bounces-stars_bounces,
			"grey for", bounces, "walls"); return false
	}
	// Each foe it struck took what the ball's value was then, no more.
	for bumper in taken[:taken_count] {
		struck := foe(room, bumper.id)
		if struck == nil || struck.health != BUMPER_HEALTH-bumper.amount {
			fmt.eprintln("mechanics lab: a foe struck for", bumper.amount, "has", struck.health if struck != nil else -1, "hp"); return false
		}
	}
	// Its sounds: the card, the strike, a ding, a bong for each of the row,
	// the burst; the lantern's swing never (the ball's thwack is the blow),
	// nor the archer.
	played := sounds.played
	for sfx in ([?]audio.Lab_Sfx{render.LAB_PINBALL_CARD, render.LAB_PINBALL_LAUNCH, render.LAB_PINBALL_DING, render.LAB_PINBALL_BONG, render.LAB_PINBALL_BURST}) {
		if played[sfx] <= heard[sfx] { fmt.eprintln("mechanics lab: no sound for the Pinball", sfx); return false }
	}
	if played[render.LAB_PINBALL_BONG]-heard[render.LAB_PINBALL_BONG] < 3 { fmt.eprintln("mechanics lab: the row's three bongs were not heard"); return false }
	for sfx in ([?]audio.Lab_Sfx{.Pilgrim_Attack, .Archer_Hurt, .Archer_Death, .Archer_Shoot, .Archer_Aim}) {
		if played[sfx] != heard[sfx] { fmt.eprintln("mechanics lab: the Pinball sounded", sfx); return false }
	}
	fmt.eprintf("mechanics lab pinball: launched %d degrees off the line, %d bumps (%d pushes) and %d bounces (%s), over the player %d time%s, " +
		"burst on %v after %d beats\n", turn, bumps, pushes, bounces, strings.trim_space(strings.to_string(order)), passes, "" if passes == 1 else "s",
		burst_cell, beats)
	return true
}
