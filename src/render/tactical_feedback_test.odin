package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

@(test)
test_tactical_feedback_targets_one_actor_and_never_advances_presentation :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical = {enabled = true, scene_3d = true}
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
	// Identical cue state must not alter classic rendering or the M7 2D view.
	renderer.tactical.scene_3d = false
	testing.expect_value(t, tactical_feedback_pose(renderer, sprite_key_for_enemy(.Chaser), {2, 3}).tint, rl.WHITE)
	renderer.tactical.scene_3d = true
	renderer.tactical.enabled = false
	testing.expect_value(t, tactical_feedback_pose(renderer, sprite_key_for_enemy(.Chaser), {2, 3}).tint, rl.WHITE)
}

@(test)
test_tactical_move_feedback_returns_to_ground_without_an_extra_timeline :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical = {enabled = true, scene_3d = true}
	renderer.timeline.view.valid = true
	renderer.timeline.view.player = {entity = game.PLAYER_ENTITY, position = {2, 3}, visible = true}
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Move, started = true, duration = 1,
		event = {kind = .Moved, source = game.PLAYER_ENTITY, target = game.PLAYER_ENTITY, from_position = {2, 3}, to_position = {3, 3}}}
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
