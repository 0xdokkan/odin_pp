package integration

import "core:fmt"
import "core:testing"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"
import run_session "../run"

@(private = "file")
COMPLEX_PLAY_BIOMES :: [9]campaign.Biome{.Cyber, .West, .Jungle, .City, .Egypt, .Vietnam, .Snow, .Inferno, .Gothic}

// Each biome's complex (Fase 7 of docs/piano-profondita.md) lives a minute of play as an expedition
// has it: the robot still on the complex's bridge, its guards woken and free, the controller and the world ticking. Nothing
// breaks the foes' beat across the layers and the lifts (a foe off a lift with no intent once stopped the game).
@(test)
test_the_complexes_live_a_minute_of_play_with_their_guards_free :: proc(t: ^testing.T) {
	for biome in COMPLEX_PLAY_BIOMES {
		w: world.World
		data: level.Level
		testing.expect(t, world.generate(&w, &data, biome, 21))
		player, created := game.create_player({max_health = 400, attack = 2, defense = 1})
		testing.expect(t, created)
		room, made := game.create_room(&data, &player, {room_seed = 21})
		testing.expect(t, made)
		testing.expect(t, game.configure_expedition_combat(&room))
		game.end_expedition_encounter(&room)
		room.phase = .Loot
		player.tactical.config.expedition_biome = u8(biome)
		testing.expect(t, w.complex_count > 0)
		// On the complex's bridge; on the top with its secret where it has none (the Egitto's pyramids).
		c := w.complexes[0]
		player.position = world.complex_bridge_middle(c)
		if player.position == c.origin {
			layout := world.complex_layout(c.kind)
			for row, y in layout.rows { for x in 0..<len(row) { if row[x] == '$' { player.position = world.complex_cell(c, {x = x, y = y}) } } }
		}
		guards := -1
		for group, i in w.groups[:w.group_count] {
			if index, _ := world.complex_at(&w, group.anchor); index > 0 { guards = i }
		}
		testing.expectf(t, guards >= 0, "%v: no guards on the complex", biome)
		testing.expectf(t, world.engage(&w, &room, guards), "%v: the guards did not wake", biome)
		renderer := new(render.Renderer)
		controller := run_session.Tactical_Controller{was_focused = true}
		cards: run_session.Card_Interaction_State
		buffer: run_session.Buffered_Gameplay_Command
		rode, moved := false, false
		start := player.health
		before: [game.MAX_ENEMIES_PER_ROOM]game.Enemy
		count := copy(before[:], room.enemies[:])
		for frame in 0..<60*60 {
			_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, {focused = true})
			for foe in room.enemies {
				if _, riding := game.lift_riding(&room, game.enemy_entity(foe.id)); riding { rode = true }
				for old in before[:count] { if old.id == foe.id && old.position != foe.position { moved = true } }
			}
			_ = world.sync(&w, &room)
			world.tick(&w, &room, 1.0/60)
			if room.phase != .Combat { break }
			// Between the foes' beats (during one, those already resolved wait with none).
			if frame%30 == 0 && !room.tactical_pulse.pending && !game.validate_enemy_intents(&room) {
				testing.expectf(t, false, "%v: the foes' intents broke", biome)
				break
			}
		}
		testing.expectf(t, room.phase == .Combat || room.phase == .Loot, "%v: the fight ended in %v", biome, room.phase)
		testing.expectf(t, moved, "%v: the guards never moved", biome)
		fmt.printfln("%v: foes %d, rode a lift %v, the robot's health %d to %d", biome, len(room.enemies), rode, start, player.health)
		render.destroy_renderer_world_playback(renderer)
		free(renderer)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}

// The walkable cell beside `cell` within a step of its height (a lift's landing's way off it), none: `cell`.
@(private = "file")
complex_beside :: proc(room: ^game.Room, cell: grid.Position) -> grid.Position {
	for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
		next, _ := game.layer_step(room, cell, step)
		if next == cell || game.cell_blocks_movement(room, next) || abs(game.cell_height(room, next)-game.cell_height(room, cell)) > 1 { continue }
		if _, _, landing := level.lift_at(room.level_data, next); landing { continue }
		return next
	}
	return cell
}

// The complex's lift with its gate open: a foe free at its foot goes for the robot by its top, calls the platform, rides it
// up out of play and fights on; nothing breaks the foes' beat.
@(test)
test_a_foe_rides_a_complexs_lift_up_after_the_robot :: proc(t: ^testing.T) {
	for biome in COMPLEX_PLAY_BIOMES {
		w: world.World
		data: level.Level
		testing.expect(t, world.generate(&w, &data, biome, 33))
		player, created := game.create_player({max_health = 400, attack = 2, defense = 1})
		testing.expect(t, created)
		room, made := game.create_room(&data, &player, {room_seed = 33})
		testing.expect(t, made)
		testing.expect(t, game.configure_expedition_combat(&room))
		player.tactical.config.expedition_biome = u8(biome)
		for gate in data.gates { _ = game.gate_opens(&room, gate.lever, gate.cell) }
		lift := data.lifts[0]
		player.position = complex_beside(&room, lift.ends[1])
		testing.expectf(t, player.position != lift.ends[1], "%v: no way off the lift's top", biome)
		foot := complex_beside(&room, lift.ends[0])
		testing.expect(t, game.begin_expedition_encounter(&room) || room.phase == .Combat)
		id, spawned := game.spawn_enemy(&room, {position = foot, health = 30, attack = 1, archetype = .Chaser})
		testing.expectf(t, spawned, "%v: no foe at the lift's foot", biome)
		game.plan_enemy_intents(&room)
		renderer := new(render.Renderer)
		controller := run_session.Tactical_Controller{was_focused = true}
		cards: run_session.Card_Interaction_State
		buffer: run_session.Buffered_Gameplay_Command
		rode, up := false, false
		for frame in 0..<60*40 {
			_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, {focused = true})
			if room.phase != .Combat { break }
			if _, riding := game.lift_riding(&room, game.enemy_entity(id)); riding { rode = true }
			if index, found := game.enemy_index_by_id(&room, id); found && rode && room.enemies[index].position == lift.ends[1] { up = true }
			if frame%30 == 0 && !room.tactical_pulse.pending && !game.validate_enemy_intents(&room) {
				testing.expectf(t, false, "%v: the foes' intents broke", biome)
				break
			}
		}
		testing.expectf(t, rode && up, "%v: the foe did not ride the lift up (rode %v, up %v)", biome, rode, up)
		render.destroy_renderer_world_playback(renderer)
		free(renderer)
		game.destroy_room(&room)
		level.destroy(&data)
	}
}
