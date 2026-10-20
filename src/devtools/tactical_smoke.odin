package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:encoding/json"
import "core:fmt"
import game "../game"
import grid "../engine/grid"
import level "../level"

Tactical_Smoke_Sample :: struct {
	timer, vision: int,
	pulses: u64,
	health: i32,
	metrics: game.Tactical_Metrics,
}

Tactical_Route_Sample :: struct {
	seed: u64,
	outcome: string,
	nodes, commands: int,
	metrics: game.Tactical_Metrics,
}

// BFS policy uses only topology to approach the nearest opponent, or the exit
// after combat. It deliberately makes no claim to approximate a skilled player.
tactical_route_move :: proc(room: ^game.Room) -> (game.Move_Direction, bool) {
	w, h := room.level_data.tiles.width, room.level_data.tiles.height
	queue := make([]grid.Position, w*h)
	seen := make([]bool, w*h)
	first := make([]game.Move_Direction, w*h)
	defer delete(queue)
	defer delete(seen)
	defer delete(first)
	origin := room.player.position
	queue[0] = origin
	seen[origin.y*w+origin.x] = true
	head, count := 0, 1
	for head < count {
		cell := queue[head]
		head += 1
		if cell != origin {
			_, enemy := game.enemy_index_at(room, cell)
			if (room.phase == .Loot && cell == room.exit_position) || (room.phase == .Combat && enemy) {
				return first[cell.y*w+cell.x], true
			}
		}
		for index in 0..<4 {
			direction := game.Move_Direction(index)
			destination := game.add_position(cell, game.direction_offset(direction))
			if !grid.contains(&room.level_data.tiles, destination) { continue }
			at := destination.y*w+destination.x
			if seen[at] || !game.base_cell_is_walkable(room, destination) || game.obstacle_at(room, destination) { continue }
			if room.phase == .Combat && game.cell_blocks_movement(room, destination) { continue }
			seen[at] = true
			first[at] = direction if cell == origin else first[cell.y*w+cell.x]
			queue[count] = destination
			count += 1
		}
	}
	return .North, false
}

tactical_route_sample :: proc(seed: u64) -> (sample: Tactical_Route_Sample, ok: bool) {
	run, created := game.create_run(run_session.DEMO_PLAYER_STATS, run_session.DEMO_RUN_CONFIG, seed)
	if !created { return }
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !run_session.configure_demo_tactical_player(&run.player, game.DEFAULT_TACTICAL_CONFIG) { return }
	if !run_session.replace_current_demo_room(&data, &run, &room, true) { return }
	sample.seed, sample.nodes = seed, 1
	for _ in 0..<10000 {
		switch run.phase {
		case .Victory, .Defeat:
			sample.outcome = game.run_phase_name(run.phase)
			sample.metrics = run.player.tactical.metrics
			return sample, true
		case .Reward:
			if game.skip_card_reward(&run) != .Skipped { return }
		case .Choose_Path:
			nodes := game.available_nodes(&run)
			if len(nodes) == 0 || !run_session.enter_demo_node(&data, &run, &room, nodes[0], true) { return }
			sample.nodes += 1
		case .Shop:
			game.leave_shop(&run)
		case .Rest, .Event, .Treasure:
			game.leave_special_node(&run)
			game.continue_special_node(&run)
		case .In_Room:
			if room.phase == .Complete || room.phase == .Defeat { game.finish_room(&run, room.phase); continue }
			command := run_session.Gameplay_Command{origin_phase = room.phase}
			if room.qte.kind != .None {
				if !room.qte.selected {
					command.kind = .Defense
					command.defense = .Parry if .Parry in room.qte.defenses else (.Deflect if .Deflect in room.qte.defenses else .Dodge)
				} else { command.kind = .QTE_Key; command.direction = room.qte.keys[room.qte.progress] }
			} else if game.tactical_is_casting(&room) {
				// Headless routes have no rendered frames. Advance the real cast
				// clock to its deadline, as below for recovery; counting 60 ticks
				// per second exhausted the route budget in larger encounters.
				game.tactical_tick(&room, run.player.tactical.cast_remaining, true, false)
				continue
			} else if game.tactical_shadow_active(&room) {
				// The shadow stays put: its four seconds pass, then it rises.
				if !game.tactical_shadow_due(&room) {
					game.tactical_tick(&room, run.player.tactical.shadow_remaining, true, false)
					continue
				}
				command.kind = .Shadow_Emerge
			} else if room.tactical_pulse.pending {
				command.kind = .Continue_Pulse
			} else if room.phase == .Combat && run.player.tactical.phase == .Recovery {
				game.tactical_tick(&room, game.TACTICAL_RECOVERY_SECONDS, true, false)
				if room.tactical_pulse.pending { command.kind = .Continue_Pulse } else { continue }
			} else if room.phase == .Combat && run.player.tactical.remaining <= 0 {
				command.kind = .Timeout
			} else {
				if room.phase == .Combat {
					for card in run.player.deck.hand[:run.player.deck.hand_count] {
						definition, _ := game.card_definition_by_id(card.definition_id)
						if definition.cost > run.player.deck.energy { continue }
						target := game.entity_target(game.PLAYER_ENTITY)
						if definition.targeting.shape != .None {
							if len(room.enemies) == 0 { continue }
							var_target, found := game.card_drop_target(&room, card, room.enemies[0].position)
							if !found { continue }
							target = var_target
						}
						if !game.tactical_target_visible(&room, target) { continue }
						_, error := game.compile_card_action(&room, card, target)
						if error != .None { continue }
						command.kind, command.card_id, command.target = .Play_Card, card.id, target
						break
					}
				}
				if command.kind == .None {
					direction, found := tactical_route_move(&room)
					if !found { command.kind = .Wait } else { command.kind = .Move; command.direction = direction }
				}
			}
			execution := run_session.execute_gameplay_command(&room, command)
			if !execution.committed || room.recent_events.dropped_count != 0 {
				fmt.eprintf("M7 route command rejected: seed=%d room=%v phase=%v remaining=%.3f command=%v pulse=%d\n",
					seed, room.phase, run.player.tactical.phase, run.player.tactical.remaining, command.kind, room.pulse_count)
				return
			}
			sample.commands += 1
		}
	}
	fmt.eprintf("M7 route iteration budget exhausted: seed=%d nodes=%d commands=%d room=%v enemies=%d pulse=%d cast=%.3f remaining=%.3f position=%v\n",
		seed, sample.nodes, sample.commands, room.phase, len(room.enemies), room.pulse_count,
		run.player.tactical.cast_remaining, run.player.tactical.remaining, run.player.position)
	return
}

// Deterministic stress arena: large health budgets deliberately exercise late
// recovery cycles. These samples are regression evidence, not balance scores.
tactical_stress_sample :: proc(timer, vision: int) -> (sample: Tactical_Smoke_Sample, ok: bool) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#...>...#", "#.......#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 10000, attack = 2, defense = 1})
	if !created { return }
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = timer
	config.vision_size = vision
	if !game.configure_tactical(&player, config) { return }
	enemies := [?]game.Enemy_Spawn{{position = {2, 1}, health = 10000, attack = 2},
		{position = {6, 1}, health = 10000, attack = 2, archetype = .Archer}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	if !built { return }
	defer game.destroy_room(&room)
	for _ in 0..<10000 {
		command := run_session.Gameplay_Command{origin_phase = .Combat}
		if room.phase != .Combat { return }
		if room.qte.kind != .None {
			command.kind = .QTE_Fail
		} else if room.tactical_pulse.pending {
			command.kind = .Continue_Pulse
		} else if player.tactical.phase == .Recovery {
			game.tactical_tick(&room, game.TACTICAL_RECOVERY_SECONDS, true, false)
			if room.tactical_pulse.pending { command.kind = .Continue_Pulse } else { continue }
		} else {
			if player.tactical.cycle == 8 {
				sample = {timer, vision, room.pulse_count, player.health, player.tactical.metrics}
				return sample, room.pulse_count == u64(timer*8+8) && player.tactical.metrics.forced_pulses == 8
			}
			expired := game.tactical_tick(&room, f32(timer), true, true)
			if room.tactical_pulse.pending { command.kind = .Continue_Pulse }
			else if expired { command.kind = .Timeout }
			else { return }
		}
		result := run_session.execute_gameplay_command(&room, command)
		if !result.committed || room.recent_events.dropped_count != 0 || !game.validate_deck_state(&player.deck) { return }
	}
	return
}

run_tactical_headless_smoke :: proc() -> bool {
	samples: [10]Tactical_Smoke_Sample
	index := 0
	timers := [?]int{15, 20}
	visions := [?]int{0, 2, 3, 5, 7}
	for timer in timers {
		for vision in visions {
			first, ok := tactical_stress_sample(timer, vision)
			second, repeated := tactical_stress_sample(timer, vision)
			if !ok || !repeated || first != second { fmt.eprintln("M7 deterministic stress failed", timer, vision); return false }
			samples[index] = first
			index += 1
		}
	}
	routes: [2]Tactical_Route_Sample
	seeds := [?]u64{1, 0xC0FFEE}
	for seed, seed_index in seeds {
		first, ok := tactical_route_sample(seed)
		second, repeated := tactical_route_sample(seed)
		if !ok || !repeated || first != second { fmt.eprintln("M7 full route regression failed", seed); return false }
		routes[seed_index] = first
	}
	report := struct {schema_version: int, scenario: string, samples: [10]Tactical_Smoke_Sample, routes: [2]Tactical_Route_Sample}{
		3, "M7 fixed-recovery stress and terminal runs; not a balance benchmark", samples, routes}
	data, err := json.marshal(report)
	if err != nil { return false }
	defer delete(data)
	if !artifacts.write_report("odin_pp_m7_stress.json", data) { return false }
	fmt.println("M7: 10 presets + 2 terminal runs replayed twice; 8 stress cycles; 8 fixed recovery beats per preset; no overflow")
	return true
}
