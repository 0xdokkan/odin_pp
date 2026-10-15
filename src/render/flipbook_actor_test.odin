package render

import "core:strings"
import "core:testing"
import game "../game"
import gfx "../engine/gfx"

@(test)
test_flipbook_frames_follow_their_durations :: proc(t: ^testing.T) {
	for character in gfx.Flipbook_Character {
		for action in gfx.Flipbook_Action {
			clip := &gfx.FLIPBOOK_SHEETS[character].clips[action]
			if clip.count == 0 { continue }
			testing.expect(t, clip.count <= gfx.FLIPBOOK_MAX_FRAMES)
			first, finished := gfx.flipbook_frame(clip, 0)
			testing.expect_value(t, first, i32(0))
			testing.expect(t, !finished)
			length := gfx.flipbook_clip_seconds(clip)
			testing.expect(t, length > 0)
			last, _ := gfx.flipbook_frame(clip, length-0.001)
			testing.expect_value(t, last, clip.count-1)
			after, done := gfx.flipbook_frame(clip, length+0.5)
			if clip.loop {
				testing.expect(t, !done)
				testing.expect(t, after >= 0 && after < clip.count)
			} else {
				testing.expect(t, done)
				testing.expect_value(t, after, clip.count-1)
				testing.expect(t, clip.hit < clip.count)
			}
		}
	}
	// Unequal durations and a zero-length tail: boundaries advance, while a
	// one-shot holds its last drawing even if that drawing has no duration.
	Case :: struct {count: i32, loop: bool, elapsed: f64, first, frame: i32, finished: bool}
	for c in ([12]Case{
		{0, false, 0, 0, 0, true}, {-1, true, 1, 2, 0, true},
		{3, false, -1, -2, 0, false}, {3, false, 0.125, 0, 1, false},
		{3, false, 0.375, 0, 2, true}, {3, false, 0, 1, 1, false},
		{3, false, 0.25, 1, 2, true}, {2, false, 0, 99, 1, false},
		{2, false, 0.25, 99, 1, true}, {3, true, 0, 2, 0, false},
		{3, true, 0.375, 2, 0, false}, {3, true, 0.5, -1, 1, false},
	}) {
		clip := gfx.Flipbook_Clip{count = c.count, loop = c.loop}
		clip.durations[0], clip.durations[1] = 125, 250
		frame, finished := gfx.flipbook_frame(&clip, c.elapsed, c.first)
		testing.expectf(t, frame == c.frame && finished == c.finished, "clip edge %v: got %v/%v", c, frame, finished)
	}
	zero := gfx.Flipbook_Clip{count = 3, loop = true}
	frame, finished := gfx.flipbook_frame(&zero, 5, 2)
	testing.expect(t, frame == 0 && !finished)
	zero.loop = false
	frame, finished = gfx.flipbook_frame(&zero, 0)
	testing.expect(t, frame == 2 && finished)
	clip := gfx.Flipbook_Clip{count = 3}
	clip.durations[0], clip.durations[1] = 125, 250
	testing.expect_value(t, gfx.flipbook_clip_seconds(&clip, -1), f64(0.375))
	testing.expect_value(t, gfx.flipbook_clip_seconds(&clip, 1), f64(0.25))
	testing.expect_value(t, gfx.flipbook_clip_seconds(&clip, 99), f64(0))
}

@(test)
test_flipbook_every_action_resolves_to_a_drawn_clip :: proc(t: ^testing.T) {
	for character in gfx.Flipbook_Character {
		sheet := &gfx.FLIPBOOK_SHEETS[character]
		testing.expect(t, sheet.clips[.Idle].count > 0 && sheet.clips[.Idle].loop)
		testing.expect(t, sheet.clips[.Walk].count > 0 && sheet.clips[.Walk].loop)
		testing.expect(t, sheet.clips[.Death].count > 0 && !sheet.clips[.Death].loop)
		for action in gfx.Flipbook_Action {
			testing.expect(t, sheet.clips[gfx.flipbook_resolve(character, action)].count > 0)
		}
		testing.expect(t, sheet.feet.x > 0 && sheet.feet.x < f32(sheet.cell.x))
		testing.expect(t, sheet.feet.y > 0 && sheet.feet.y <= f32(sheet.cell.y))
	}
}

@(private="file")
flipbook_test_renderer :: proc() -> ^Renderer {
	renderer := new(Renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled, renderer.tactical.scene_3d, renderer.tactical.no_fog = true, true, true
	renderer.tactical.camera = tactical_orbit_camera({yaw = 0.78, pitch = 0.68, distance = 12.5}, {3.5, 0, 3.5}, true)
	renderer.tactical.flipbook.loaded = true
	renderer.tactical.flipbook_state = new(Flipbook_State)
	renderer.tactical.snapshot = new(Room_Presentation)
	renderer.tactical.snapshot^ = {valid = true, enemy_count = 1}
	renderer.tactical.snapshot.player = {entity = game.PLAYER_ENTITY, position = {2, 3}, visible = true, opacity = 1}
	renderer.tactical.snapshot.enemies[0] = {entity = game.enemy_entity(4), archetype = .Brute, position = {3, 3}, visible = true, opacity = 1}
	return renderer
}

@(private="file")
flipbook_test_free :: proc(renderer: ^Renderer) {
	free(renderer.tactical.flipbook_state)
	free(renderer.tactical.snapshot)
	free(renderer)
}

@(test)
test_flipbook_hit_plays_hurt_then_returns_to_breathing :: proc(t: ^testing.T) {
	renderer := flipbook_test_renderer()
	defer flipbook_test_free(renderer)
	enemy := game.enemy_entity(4)
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Damage, started = true, elapsed = 0.05, duration = 0.24,
		event = {source = game.PLAYER_ENTITY, target = enemy}}
	update_flipbook_actors(renderer, nil)
	brute := flipbook_find(renderer, enemy, .Brute, {3, 3})
	player := flipbook_find(renderer, game.PLAYER_ENTITY, .Pilgrim, {2, 3})
	testing.expect(t, brute != nil && player != nil)
	if brute == nil || player == nil { return }
	testing.expect_value(t, brute.action, gfx.Flipbook_Action.Hurt)
	// The attacker strikes from its impact drawing: the cue is the impact.
	testing.expect_value(t, player.action, gfx.Flipbook_Action.Attack)
	testing.expect_value(t, player.first_frame, gfx.FLIPBOOK_SHEETS[.Pilgrim].clips[.Attack].hit)
	// The same cue on the next frame is not a new trigger.
	started := brute.started
	renderer.sprite_assets.elapsed = 0.05
	update_flipbook_actors(renderer, nil)
	testing.expect_value(t, brute.started, started)
	// Gameplay moves on: the cue is gone, the clip finishes on its own clock.
	renderer.timeline.count = 0
	renderer.sprite_assets.elapsed = 0.1
	update_flipbook_actors(renderer, nil)
	action, _ := flipbook_drawing(brute, renderer.sprite_assets.elapsed)
	testing.expect_value(t, action, gfx.Flipbook_Action.Hurt)
	renderer.sprite_assets.elapsed = 5
	update_flipbook_actors(renderer, nil)
	action, _ = flipbook_drawing(brute, renderer.sprite_assets.elapsed)
	testing.expect_value(t, action, gfx.Flipbook_Action.Idle)
}

@(test)
test_flipbook_defeated_standee_topples_after_leaving_the_board :: proc(t: ^testing.T) {
	renderer := flipbook_test_renderer()
	defer flipbook_test_free(renderer)
	enemy := game.enemy_entity(4)
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Defeat, started = true, elapsed = 0, duration = 0.3, event = {target = enemy}}
	update_flipbook_actors(renderer, nil)
	brute := flipbook_find(renderer, enemy, .Brute, {3, 3})
	testing.expect(t, brute != nil && brute.action == .Death)
	if brute == nil { return }
	// Removed from the snapshot while still dying: kept as a ghost.
	renderer.timeline.count = 0
	renderer.tactical.snapshot.enemy_count = 0
	renderer.sprite_assets.elapsed = 0.2
	update_flipbook_actors(renderer, nil)
	testing.expect(t, brute.used && brute.ghost)
	testing.expect(t, flipbook_opacity(renderer, enemy, .Brute, {3, 3}, 0) > 0.99)
	entries := collect_tactical_translucents(renderer)
	ghosts := 0
	for entry in entries { if entry.entity == enemy { ghosts += 1 } }
	testing.expect_value(t, ghosts, 1)
	destroy_tactical_translucents(renderer)
	renderer.sprite_assets.elapsed = 5
	update_flipbook_actors(renderer, nil)
	testing.expect(t, !brute.used)
}

@(test)
test_flipbook_card_stands_on_the_floor_and_turns_with_the_walk :: proc(t: ^testing.T) {
	renderer := flipbook_test_renderer()
	defer flipbook_test_free(renderer)
	update_flipbook_actors(renderer, nil)
	for character in gfx.Flipbook_Character {
		sheet := &gfx.FLIPBOOK_SHEETS[character]
		quad := flipbook_billboard_geometry(renderer, character, flipbook_key(character), {2, 3}, false, game.SYSTEM_ENTITY)
		// The paper under the feet stands in the base's slot, just above the floor.
		scale := sheet.world_height/sheet.rest_height
		feet := quad.points[1].y+(f32(sheet.cell.y)-sheet.feet.y)*scale
		testing.expect(t, abs(feet-(0.02+(gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*scale+0.03)) < 0.002)
		top := (quad.points[0].y+quad.points[3].y)*0.5
		testing.expect(t, top > sheet.world_height*0.9)
		// Without an actor there is nothing to morph from.
		testing.expect_value(t, quad.card_a, quad.card_b)
		testing.expect_value(t, quad.card_morph, f32(1))
	}
	// Walking toward the screen's left turns the card over.
	right := flipbook_camera_right(renderer)
	step := [2]int{-1, 0} if right.x > 0 else [2]int{1, 0}
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Move, started = true, elapsed = 0.01, duration = 0.24,
		event = {target = game.PLAYER_ENTITY, from_position = {2, 3}, to_position = {2+step.x, 3+step.y}}}
	update_flipbook_actors(renderer, nil)
	player := flipbook_find(renderer, game.PLAYER_ENTITY, .Pilgrim, {2, 3})
	testing.expect(t, player != nil && player.facing_left && player.base == .Walk)
}

@(test)
test_flipbook_paper_shader_source_is_fully_formatted :: proc(t: ^testing.T) {
	source := string(gfx.flipbook_paper_source())
	testing.expectf(t, !strings.contains(source, "%"), "unformatted shader:\n%s", source)
}
