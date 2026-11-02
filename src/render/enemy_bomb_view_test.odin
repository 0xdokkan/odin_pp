package render

import "core:testing"
import game "../game"
import grid "../engine/grid"

// The arc leaves the bomber's hand, rises over both ends and comes down on the
// landed bomb's own place.
@(test)
test_a_bombs_arc_rises_and_comes_down_on_its_cell :: proc(t: ^testing.T) {
	from, to := grid.Position{x = 7, y = 4}, grid.Position{x = 4, y = 4}
	start, _, way := enemy_bomb_arc(from, to, 0)
	middle, high, _ := enemy_bomb_arc(from, to, 0.5)
	end, low, _ := enemy_bomb_arc(from, to, 1)
	testing.expect(t, abs(start.x-7.5) < 1e-5 && abs(start.z-4.5) < 1e-5)
	testing.expect(t, abs(end.x-4.5) < 1e-5 && abs(end.z-4.5) < 1e-5)
	testing.expect(t, middle.y > start.y+0.5 && middle.y > end.y+0.5 && high > low)
	testing.expect(t, abs(way.x+1) < 1e-5 && abs(way.z) < 1e-5)
	_, size := game.grid_object_size(.Bomb)
	testing.expect(t, abs(end.y-(0.035+point_ground({4, 4})+size*0.5)) < 1e-5)
}

// The ring closes in from around the 3×3 cells to the bomb as its fuse burns,
// and turns red in its last second.
@(test)
test_a_bombs_ring_closes_in_as_its_fuse_burns :: proc(t: ^testing.T) {
	full, early := enemy_bomb_ring(2.4, 2.4)
	half, _ := enemy_bomb_ring(1.2, 2.4)
	none, late := enemy_bomb_ring(0, 2.4)
	testing.expect(t, abs(full-ENEMY_BOMB_RING_OUTER) < 1e-5 && abs(none-ENEMY_BOMB_RING_INNER) < 1e-5)
	testing.expect(t, half < full && half > none && !early && late)
	// Never wider than the cells before its landing.
	wide, _ := enemy_bomb_ring(3, 2.4)
	testing.expect(t, abs(wide-ENEMY_BOMB_RING_OUTER) < 1e-5)
}

// The seconds to its blast: it bursts on the beat one short of its
// detonation_pulse (game.resolve_due_explosives).
@(test)
test_a_bombs_seconds_left_count_to_its_beat :: proc(t: ^testing.T) {
	player: game.Player
	room := game.Room{player = &player, pulse_count = 5}
	player.tactical.clock_fraction = 0.6
	testing.expect(t, abs(enemy_bomb_seconds_left(&room, 8)-2.4) < 1e-5)
	testing.expect_value(t, enemy_bomb_seconds_left(&room, 5), f32(0))
}

// The bomber throws (its clip); the bomb landing starts none.
@(test)
test_a_bombers_throw_plays_its_clip_and_the_landing_none :: proc(t: ^testing.T) {
	bomber := game.enemy_entity(1)
	thrown := Presentation_Cue{kind = .Bomb_Thrown, event = {kind = .Bomb_Thrown, source = bomber, target = game.SYSTEM_ENTITY}}
	action, matched := living_cue_action(&thrown, bomber)
	testing.expect(t, matched && action == .Cast)
	landed := Presentation_Cue{kind = .Object_Spawned, event = {kind = .Object_Spawned, source = bomber, target = game.object_entity(3), object_kind = .Bomb}}
	_, matched = living_cue_action(&landed, bomber)
	testing.expect(t, !matched)
}
