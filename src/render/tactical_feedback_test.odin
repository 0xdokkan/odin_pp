package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"
import grid "../engine/grid"
import level "../level"

@(test)
test_tactical_feedback_targets_one_actor_and_never_advances_presentation :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical = {}
	renderer.timeline.view.valid = true
	renderer.timeline.view.enemy_count = 2
	for &enemy, index in renderer.timeline.view.enemies[:2] {
		enemy = {entity = game.enemy_entity(u32(index+1)), archetype = .Chaser,
			position = {f32(index+2), 3}, visible = true, opacity = 1, health = 5}
	}
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Damage, started = true, duration = 1, elapsed = 0.5,
		event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = game.enemy_entity(1), amount = 3}}
	before := renderer.timeline
	for _ in 0..<3 {
		pose := tactical_feedback_pose(renderer, sprite_key_for_enemy(.Chaser), {2, 3})
		other := tactical_feedback_pose(renderer, sprite_key_for_enemy(.Chaser), {3, 3})
		testing.expect(t, pose.tint != rl.WHITE)
		testing.expect_value(t, other.tint, rl.WHITE)
		testing.expect_value(t, other.scale_y, f32(1))
	}
	testing.expect_value(t, renderer.timeline, before)

}

@(test)
test_tactical_feedback_follows_actor_object_and_fallback_height :: proc(t: ^testing.T) {
	data, made := level.create(8, 8, level.Tile{kind = .Floor})
	testing.expect(t, made)
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_actors(nil)
	defer clear(&board_actors)
	renderer := new(Renderer)
	defer free(renderer)
	snapshot := Room_Presentation{valid = true}
	renderer.tactical.snapshot = &snapshot
	snapshot.player = {entity = game.PLAYER_ENTITY, position = {3, 3}, visible = true}
	snapshot.object_count = 1
	object := game.object_entity(5)
	snapshot.objects[0] = {entity = object, position = {4, 3}, visible = true}
	for height in ([2]i32{0, 20}) {
		for y in 0..<8 { for x in 0..<8 { level.set_height(&data, {x = x, y = y}, height) } }
		set_board_level(&data)
		for entity in ([3]game.Entity_Ref{game.PLAYER_ENTITY, object, game.SYSTEM_ENTITY}) {
			point := tactical_feedback_position(renderer, entity, {x = 2, y = 3})
			testing.expect(t, abs(point.y-(0.055+f32(height)*game.HEIGHT_STEP_DRAWN)) < .00001)
		}
	}
	// Ground marks stay above a one-step slope, rather than disappearing on
	// its upper side; the damage spark remains exactly at the figure's feet.
	for y in 0..<8 { for x in 0..<8 { level.set_height(&data, {x = x, y = y}, i32(x)) } }
	set_board_level(&data)
	point := tactical_feedback_position(renderer, game.PLAYER_ENTITY, {})
	ring := tactical_feedback_rune_position(renderer, game.PLAYER_ENTITY, {}, .34)
	testing.expect(t, ring.y > point.y)
	for offset in ([4]view.Vec2{{.34, 0}, {-.34, 0}, {0, .34}, {0, -.34}}) {
		testing.expect(t, ring.y >= .055+point_ground(snapshot.player.position+offset)-.00001)
	}
}

@(test)
test_tactical_feedback_and_protection_keep_the_bridge_layer :: proc(t: ^testing.T) {
	data, made := level.create(8, 8, level.Tile{kind = .Floor})
	testing.expect(t, made)
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_actors(nil)
	defer clear(&board_actors)
	for y in 0..<8 { for x in 2..=4 {
		cell := grid.Position{x = x, y = y, layer = 1}
		level.set_tile(&data, cell, {kind = .Floor})
		level.set_height(&data, cell, level.LAYER_SPACING)
	} }
	set_board_level(&data)
	upper := game.enemy_entity(1)
	lower := game.enemy_entity(2)
	append(&board_actors, Board_Actor{upper, {x = 3, y = 3, layer = 1}}, Board_Actor{lower, {x = 3, y = 3}})
	renderer := new(Renderer)
	defer free(renderer)
	snapshot := Room_Presentation{valid = true}
	renderer.tactical.snapshot = &snapshot
	snapshot.enemy_count = 2
	snapshot.enemies[0] = {entity = upper, position = {3.25, 3}, visible = true}
	snapshot.enemies[1] = {entity = lower, position = {3.25, 3}, visible = true}
	height := f32(level.LAYER_SPACING)*game.HEIGHT_STEP_DRAWN
	testing.expect(t, abs(tactical_feedback_position(renderer, upper, {}).y-(.055+height)) < .00001)
	testing.expect_value(t, tactical_feedback_position(renderer, lower, {}).y, f32(.055))
	testing.expect(t, abs(tactical_feedback_rune_position(renderer, upper, {}, .34).y-(.055+height)) < .00001)
	for id in 1..=2 {
		enemy := game.Enemy{id = u32(id), position = {x = 3, y = 3, layer = 1 if id == 1 else 0}}
		end := intent_protection_endpoint(renderer, &enemy)
		testing.expect(t, end.x == 3.75, "the tether follows the displayed slide, not the integer destination")
		testing.expect(t, abs(end.y-(.7+(height if id == 1 else 0))) < .00001)
	}
	// Captured spell endpoints retain their own layer even after the actor
	// has moved elsewhere; an untracked impact uses the same captured floor.
	event := game.Game_Event{from_position = {x = 3, y = 3, layer = 1}, to_position = {x = 5, y = 3}}
	from, to := tactical_feedback_spell_ends(event)
	testing.expect(t, abs(from.y-(.65+height)) < .00001)
	testing.expect_value(t, to.y, f32(.6))
	impact := tactical_feedback_position(renderer, game.SYSTEM_ENTITY, event.from_position)
	testing.expect(t, abs(impact.y-(.055+height)) < .00001)
}

@(test)
test_tactical_feedback_untracked_runes_keep_the_captured_cave_and_bridge :: proc(t: ^testing.T) {
	data, made := level.create(8, 8, level.Tile{kind = .Floor})
	testing.expect(t, made)
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_actors(nil)
	defer clear(&board_actors)
	data.base = level.LAYER_SPACING
	for y in 0..<8 { for x in 0..<8 {
		level.set_height(&data, {x = x, y = y}, level.LAYER_SPACING)
		level.set_tile(&data, {x = x, y = y, layer = -1}, {kind = .Floor})
		level.set_tile(&data, {x = x, y = y, layer = 1}, {kind = .Floor})
		level.set_height(&data, {x = x, y = y, layer = 1}, 2*level.LAYER_SPACING)
	} }
	set_board_level(&data)
	renderer := new(Renderer)
	defer free(renderer)
	snapshot := Room_Presentation{valid = true}
	renderer.tactical.snapshot = &snapshot
	// System effects and subjects removed before their cue ends have no
	// actor/object in the current view. Neither may jump to the upper ground.
	for entity in ([3]game.Entity_Ref{game.SYSTEM_ENTITY, game.enemy_entity(73), game.object_entity(81)}) {
		for layer in ([2]i8{-1, 1}) {
			cell := grid.Position{x = 3, y = 3, layer = layer}
			point := tactical_feedback_rune_position(renderer, entity, cell, .64)
			expected := .055+f32(layer)*f32(level.LAYER_SPACING)*game.HEIGHT_STEP_DRAWN
			testing.expect(t, abs(point.y-expected) < .00001)
			testing.expect_value(t, point.x, f32(3.5))
			testing.expect_value(t, point.z, f32(3.5))
		}
	}
}

@(test)
test_tactical_move_feedback_returns_to_ground_without_an_extra_timeline :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical = {}
	renderer.timeline.view.valid = true
	renderer.timeline.view.player = {entity = game.PLAYER_ENTITY, position = {2, 3}, visible = true}
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Move, started = true, duration = 1,
		event = {kind = .Moved, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, from_position = {x = 2, y = 3}, to_position = {x = 3, y = 3}}}
	testing.expect_value(t, tactical_feedback_pose(renderer, .Player, {2, 3}).lift, f32(0))
	update_event_timeline(&renderer.timeline, 0.5)
	position := renderer.timeline.view.player.position
	pose := tactical_feedback_pose(renderer, .Player, position)
	testing.expect(t, pose.lift > 0 && pose.lift < 0.12)
	testing.expect_value(t, renderer.timeline.view.player.position, view.Vec2{2.5, 3})
	// Feedback disappears as soon as its authoritative presentation cue ends;
	// there is no residual animation counter that could keep controls waiting.
	update_event_timeline(&renderer.timeline, 0.5)
	testing.expect(t, !event_timeline_is_busy(&renderer.timeline))
	testing.expect_value(t, tactical_feedback_pose(renderer, .Player, renderer.timeline.view.player.position).lift, f32(0))
}
