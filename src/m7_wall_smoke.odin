package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import app "app"
import game "game"
import grid "grid"
import level "level"
import render "render"

// The four diagonal pillars cross the player's billboard from every camera
// corner. A separate real empty encounter exposes the whole room in Loot;
// combat keeps its regular occlusion and must not reveal the hidden archer.
run_m7_wall_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{
		"#########", "#.......#", "#.......#", "#..#.#..#", "#...@...#",
		"#..#.#..#", "#.......#", "#......>#", "#########",
	}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player(DEMO_PLAYER_STATS)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 9
	if !created || !game.configure_tactical(&player, config) { return false }
	previous_orbit := renderer.tactical.world_orbit
	defer { renderer.tactical.world_orbit = previous_orbit }
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	probe: M7_Visual_Probe
	// These captures belong to wall QA, not to the action/VFX image sequence.
	for capture in M7_Visual_Capture { probe.captured += {capture} }
	pillars := [?]grid.Position{{3, 3}, {5, 3}, {3, 5}, {5, 5}}
	{
		spawns := [?]game.Enemy_Spawn{
			{position = {6, 4}, health = 8, attack = 2, archetype = .Archer},
			{position = {6, 6}, health = 8, attack = 2, archetype = .Archer},
		}
		room, built := game.create_room(&data, &player, {enemies = spawns[:]})
		if !built { return false }
		defer game.destroy_room(&room)
		render.clear_event_animations(renderer)
		for _ in 0..<4 { if !m7_visual_frame(&probe, window, renderer, &room) { return false } }
		if !m7_polish_check(room.phase == .Combat && game.tactical_cell_visible(&room, {6, 4}) &&
			!game.tactical_cell_visible(&room, {6, 6}), "wall fixture lost its occluded combat enemy") { return false }
		if window != nil {
			if !m7_polish_check(!renderer.tactical.no_fog &&
				!render.tactical_render_visible(renderer, {6, 6}),
				"transparent wall revealed an enemy hidden by combat fog") { return false }
			rl.TakeScreenshot("odin_pp_m7_walls_combat.png")
		}
	}
	room, built := game.create_room(&data, &player, {})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	if !m7_polish_check(room.phase == .Loot, "empty wall fixture did not enter Loot") { return false }
	for _ in 0..<75 { if !m7_visual_frame(&probe, window, renderer, &room) { return false } }
	for corner in 0..<4 {
		renderer.tactical.world_orbit.yaw = f32(math.PI/4)+f32(corner)*f32(math.PI/2)
		for _ in 0..<4 { if !m7_visual_frame(&probe, window, renderer, &room) { return false } }
		for pillar in pillars {
			if !m7_polish_check(game.cell_blocks_movement(&room, pillar) &&
				game.cell_blocks_line_of_sight(&room, pillar),
				"wall presentation changed authoritative collision or line of sight") { return false }
		}
		if window != nil {
			if !m7_polish_check(renderer.tactical.no_fog && renderer.tactical.clear_light >= 0.999,
				"wall overview did not preserve cleared-room lighting") { return false }
			rl.TakeScreenshot(fmt.ctprintf("odin_pp_m7_walls_corner_%d.png", corner))
		}
	}
	fmt.printf("M7 walls: four camera corners; interior pillars preserve collision/LOS; hidden combat enemy stays hidden; Loot lighting; timeline_errors=%d\n",
		renderer.timeline.update_failures)
	return true
}
