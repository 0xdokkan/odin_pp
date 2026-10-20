package integration
import run_session "../run"

import "core:testing"
import combatdebug "../combatdebug"
import game "../game"
import render "../render"

Encounter_Replay_Coverage :: struct {
	rooms: int,
	commands: int,
	furnace_triggers: int,
	bombs_spawned: int,
	explosions: int,
	protection_events: int,
	encounters: [5]bool,
}

encounter_regression_command :: proc(
	room: ^game.Room,
	policy: ^combatdebug.Max_Distance_Policy_State,
	step, scenario: int,
) -> run_session.Gameplay_Command {
	// Alternate standing ground with evasion; adjacent enemies also receive real bump attacks.
	if step%3 == 0 {
		for direction in game.Move_Direction {
			cell := game.add_position(room.player.position, game.direction_offset(direction))
			if _, found := game.enemy_index_at(room, cell); found {
				return {kind = .Move, origin_phase = .Combat, direction = direction}
			}
		}
	}
	if (step+scenario)%3 != 0 {
		decision := combatdebug.choose_max_distance_command(room, policy)
		if decision.valid && decision.kind == .Move {
			return {kind = .Move, origin_phase = .Combat, direction = decision.direction}
		}
	}
	return {kind = .Wait, origin_phase = .Combat}
}

expect_encounter_replay_matches_room :: proc(
	t: ^testing.T,
	room: ^game.Room,
	timeline: ^render.Presentation_Timeline,
	scenario, step: int,
) {
	testing.expectf(t, timeline.update_failures == 0 && timeline.dropped_count == 0,
		"scenario=%v step=%v update_failures=%v dropped=%v", scenario, step,
		timeline.update_failures, timeline.dropped_count)
	testing.expect_value(t, timeline.view.player.health, room.player.health)
	testing.expect_value(t, timeline.view.player.position, render.presentation_position(room.player.position))
	testing.expect_value(t, timeline.view.phase, room.phase)
	testing.expect_value(t, timeline.view.pulse_count, room.pulse_count)
	testing.expect_value(t, timeline.view.modifier, room.modifier)
	testing.expect_value(t, timeline.view.encounter_kind, room.encounter_kind)
	for enemy in room.enemies {
		visual, found := render.presentation_actor(timeline, game.enemy_entity(enemy.id))
		testing.expectf(t, found && visual.visible, "scenario=%v step=%v enemy=%v missing", scenario, step, enemy.id)
		if !found { continue }
		testing.expect_value(t, visual.health, enemy.health)
		testing.expect_value(t, visual.position, render.presentation_position(enemy.position))
		testing.expect_value(t, visual.boss_phase, enemy.boss_phase)
	}
	for object in room.objects {
		visual, found := render.presentation_grid_object(timeline, game.object_entity(object.id))
		testing.expectf(t, found && visual.visible, "scenario=%v step=%v object=%v missing", scenario, step, object.id)
		if !found { continue }
		testing.expect_value(t, visual.health, object.health)
		testing.expect_value(t, visual.position, render.presentation_position(object.position))
		testing.expect_value(t, visual.detonation_pulse, object.detonation_pulse)
	}
	for visual in timeline.view.enemies[:timeline.view.enemy_count] {
		if visual.visible {
			_, found := game.enemy_index_by_id(room, visual.entity.id)
			testing.expect(t, found)
		}
	}
	for visual in timeline.view.objects[:timeline.view.object_count] {
		if visual.visible {
			_, found := game.object_index_by_id(room, visual.entity.id)
			testing.expect(t, found)
		}
	}
}

replay_generated_encounter_commands :: proc(
	t: ^testing.T,
	node: ^game.Run_Node,
	scenario: int,
	coverage: ^Encounter_Replay_Coverage,
) {
	blueprint, err := game.generate_room_blueprint(node)
	testing.expectf(t, err == .None, "scenario=%v seed=%v generation_error=%v", scenario, node.room_seed, err)
	if err != .None { return }
	defer game.destroy_room_blueprint(&blueprint)
	player, player_ok := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, player_ok)
	if !player_ok { return }
	room, room_ok := game.create_room(&blueprint.level_data, &player, game.room_blueprint_content(&blueprint))
	testing.expect(t, room_ok)
	if !room_ok { return }
	defer game.destroy_room(&room)
	coverage.rooms += 1
	coverage.encounters[int(room.encounter_kind)] = true
	policy: combatdebug.Max_Distance_Policy_State
	timeline: render.Presentation_Timeline
	for step in 0..<192 {
		if room.phase != .Combat { break }
		// World beats and QTE continue independently of accepted player commands.
		// Untimed action costs queue elapsed time; recovery uses the same clock.
		if game.tactical_is_recovering(&room) || game.tactical_is_stunned(&room) {
			_ = game.tactical_tick(&room, 1, true, false)
		}
		command := encounter_regression_command(&room, &policy, step, scenario)
		if room.qte.kind != .None { command.kind = .QTE_Fail }
		else if room.tactical_pulse.pending { command.kind = .Continue_Pulse }
		else if player.tactical.remaining <= 0 { command.kind = .Timeout }
		before := render.capture_room_presentation(&room)
		old_position := player.position
		execution := run_session.execute_gameplay_command(&room, command)
		testing.expectf(t, execution.committed, "scenario=%v step=%v command rejected: %v", scenario, step, command)
		if !execution.committed { break }
		coverage.commands += 1
		if command.kind == .Move && player.position != old_position {
			policy.has_last_direction = true
			policy.last_direction = command.direction
		}
		after := render.capture_room_presentation(&room)
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		if render.begin_event_timeline(&timeline, before, room.recent_events, &after) {
			testing.expect(t, render.update_event_timeline(&timeline, 1000))
		} else {
			testing.expect_value(t, room.recent_events.count, 0)
			timeline.view = after
		}
		expect_encounter_replay_matches_room(t, &room, &timeline, scenario, step)
		// Replay must only mutate presentation; the entire current snapshot stays unchanged.
		testing.expect_value(t, render.capture_room_presentation(&room), after)
		for event in room.recent_events.events[:room.recent_events.count] {
			#partial switch event.kind {
			case .Room_Hazard_Triggered: coverage.furnace_triggers += 1
			case .Object_Spawned: coverage.bombs_spawned += 1
			case .Explosion: coverage.explosions += 1
			case .Status_Applied:
				if event.status == .Shield && event.source.kind == .Enemy {
					coverage.protection_events += 1
				}
			}
		}
	}
}

@(test)
test_generated_encounters_replay_committed_commands_without_dropped_state :: proc(t: ^testing.T) {
	kinds := [?]game.Node_Kind{.Combat, .Elite, .Boss}
	recipes := [?]game.Encounter_Kind{.Powder_Keg, .Escort, .Assault}
	coverage: Encounter_Replay_Coverage
	for scenario in 0..<24 {
		kind := kinds[scenario%len(kinds)]
		depth := 2+scenario%6
		node_id := game.Node_Id(scenario)
		run_seed := u64(scenario+1)*0x9E3779B97F4A7C15~u64(0xC0FFEE)
		node := game.Run_Node{id = node_id, kind = kind, depth = depth,
			room_seed = game.derive_node_room_seed(run_seed, node_id, kind, depth)}
		if kind != .Boss {
			wanted := recipes[(scenario/3+scenario%3)%len(recipes)]
			// Select seed fixtures by recipe so all formations remain covered after generator changes.
			for attempt in 0..<64 {
				candidate_seed := run_seed+u64(attempt)*0xD1B54A32D192ED03
				node.room_seed = game.derive_node_room_seed(candidate_seed, node_id, kind, depth)
				if game.encounter_kind_for_node(&node) == wanted { break }
			}
			testing.expect_value(t, game.encounter_kind_for_node(&node), wanted)
		}
		replay_generated_encounter_commands(t, &node, scenario, &coverage)
	}
	testing.expect_value(t, coverage.rooms, 24)
	testing.expect(t, coverage.commands >= 24*8)
	testing.expect(t, coverage.furnace_triggers > 0 && coverage.bombs_spawned > 0 &&
		coverage.explosions > 0 && coverage.protection_events > 0)
	encounters := [?]game.Encounter_Kind{.Powder_Keg, .Escort, .Assault, .Demolitionist}
	for encounter in encounters {
		testing.expectf(t, coverage.encounters[int(encounter)], "missing generated encounter=%v", encounter)
	}
}
