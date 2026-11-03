package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import level "../level"

// BENVENUTI A NAPOLI's blow on the board (club_juice.odin; docs/piano-napoli.md, Fase 3).

// The user's stronger squash: down to 30% in 0.06 s as wide as 1/sqrt of its
// height (the same volume), flat 0.08 s, up past its height to 112% and
// settled by 0.6 s; a pancake stays flat, no wider than JUICE_SQUASH_WIDEST.
@(test)
test_club_squash_keeps_its_volume_and_springs_back :: proc(t: ^testing.T) {
	h, w := juice_squash_shape(0, false)
	testing.expect(t, h == 1 && w == 1)
	h, w = juice_squash_shape(JUICE_SQUASH_DOWN, false)
	testing.expect(t, abs(h-JUICE_SQUASH_LOW) < 1e-4 && abs(w-1/math.sqrt(JUICE_SQUASH_LOW)) < 1e-4)
	h, _ = juice_squash_shape(JUICE_SQUASH_DOWN+JUICE_SQUASH_HOLD*0.9, false)
	testing.expect_value(t, h, JUICE_SQUASH_LOW)
	low, high := f32(10), f32(0)
	for k in 0..<600 {
		at := f32(k)*0.001
		h, w = juice_squash_shape(at, false)
		low, high = min(low, h), max(high, h)
		if w < JUICE_SQUASH_WIDEST { testing.expectf(t, abs(h*w*w-1) < 1e-3, "at %v the volume is %v", at, h*w*w) }
	}
	testing.expect(t, abs(low-JUICE_SQUASH_LOW) < 1e-4)
	testing.expectf(t, abs(high-JUICE_SQUASH_OVERSHOOT) < 0.005, "the spring rose to %v", high)
	peak, _ := juice_squash_shape(JUICE_SQUASH_DOWN+JUICE_SQUASH_HOLD+JUICE_SQUASH_PEAK, false)
	testing.expect(t, abs(peak-JUICE_SQUASH_OVERSHOOT) < 0.005)
	// Settled at its end: no jump.
	end, _ := juice_squash_shape(JUICE_SQUASH_SECONDS-0.001, false)
	testing.expect(t, abs(end-1) < 0.01)
	h, w = juice_squash_shape(JUICE_SQUASH_SECONDS, false)
	testing.expect(t, h == 1 && w == 1)
	// The pancake.
	h, w = juice_squash_shape(JUICE_SQUASH_DOWN, true)
	testing.expect(t, abs(h-JUICE_PANCAKE) < 1e-4 && w == JUICE_SQUASH_WIDEST)
	h, _ = juice_squash_shape(10, true)
	testing.expect(t, abs(h-JUICE_PANCAKE) < 1e-4)
}

// The corners squash about the feet: what stands on the floor stays there,
// the top comes down, the sides go out along the card.
@(test)
test_club_squash_keeps_the_feet_on_the_floor :: proc(t: ^testing.T) {
	anchor := rl.Vector3{3.5, 0.05, 4.5}
	right := rl.Vector3{1, 0, 0}
	points := [4]rl.Vector3{anchor+{-0.5, 1.5, 0}, anchor+{-0.5, 0, 0}, anchor+{0.5, 0, 0}, anchor+{0.5, 1.5, 0}}
	juice_squash_points(&points, anchor, right, 0.3, 1.8)
	testing.expect(t, rl.Vector3Distance(points[1], anchor+{-0.9, 0, 0}) < 1e-4)
	testing.expect(t, rl.Vector3Distance(points[2], anchor+{0.9, 0, 0}) < 1e-4)
	testing.expect(t, rl.Vector3Distance(points[0], anchor+{-0.9, 0.45, 0}) < 1e-4)
	testing.expect(t, rl.Vector3Distance(points[3], anchor+{0.9, 0.45, 0}) < 1e-4)
}

// A room for the club's blows: the view's test room, the club taken up, the
// foe of (6, 3) brought next to him, north, with `health`.
@(private = "file")
club_juice_test_setup :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, health: i32) -> (room: game.Room, foe: game.Entity_Ref) {
	room = first_person_view_test_room(t, data, player)
	room.enemies[0].position = {x = 6, y = 5}
	room.enemies[0].health = health
	testing.expect(t, game.tactical_begin_first_person(&room, 30, .Club))
	return room, game.enemy_entity(room.enemies[0].id)
}

// A frame of the board, its blows' juice read as its drawing reads it.
@(private = "file")
club_juice_test_frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
	shadow_view_test_frame(renderer, room, dt)
	observe_juice_blows(renderer)
}

// One blow along `yaw`, its events on the board's world lane.
@(private = "file")
club_juice_test_blow :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room, yaw: f32) {
	s := &room.player.tactical
	s.phase, s.remaining, s.action_remaining, s.queued_beats = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	before := capture_room_presentation(room)
	testing.expect_value(t, game.first_person_club_move(room, {swing = true, yaw = yaw}), game.Action_Result.Moved)
	after := capture_room_presentation(room)
	if room.recent_events.count > 0 { testing.expect(t, begin_renderer_world_timeline(renderer, before, room.recent_events, &after)) }
}

// The blow on a foe: the pictures held, the camera shaken behind his back, the
// card squashed (and back by 0.6 s), its stars while it is staggered; a blow
// on the floor shakes a little and throws its dust.
@(test)
test_club_blow_squashes_shakes_and_dazes :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room, foe := club_juice_test_setup(t, &data, &player, 60)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	b := &renderer.tactical.juice_blows
	for _ in 0..<60 { shadow_view_test_frame(renderer, &room, 0.02) }
	club_juice_test_blow(t, renderer, &room, -math.PI/2)
	squashed, held, shaken := false, false, false
	lowest := f32(1)
	for _ in 0..<60 {
		club_juice_test_frame(renderer, &room, 0.01)
		h, _ := juice_squash(renderer, foe)
		lowest = min(lowest, h)
		squashed = squashed || h < 1
		held = held || renderer_hit_stopped(renderer)
		shaken = shaken || renderer.juice.trauma > 0
		if b.clubs > 0 && h == 1 && squashed { break }
	}
	testing.expect_value(t, b.clubs, 1)
	testing.expectf(t, squashed && lowest < 0.35, "the card went down to %v", lowest)
	testing.expect(t, held && shaken)
	testing.expect_value(t, b.kills, 0)
	// Staggered: its stars.
	index := -1
	for &actor, k in renderer.tactical.snapshot.enemies[:renderer.tactical.snapshot.enemy_count] { if actor.entity == foe { index = k } }
	testing.expect(t, index >= 0 && juice_club_dazed(renderer, &renderer.tactical.snapshot.enemies[index]))
	// On the floor (west, nobody there): dust and a little shake, no squash.
	for _ in 0..<60 { shadow_view_test_frame(renderer, &room, 0.02) }
	renderer.juice.trauma = 0
	clubs := b.clubs
	club_juice_test_blow(t, renderer, &room, math.PI)
	club_juice_test_frame(renderer, &room, 0.0)
	testing.expect(t, renderer.juice.trauma > 0 && b.clubs == clubs)
	dusted := false
	for burst in b.bursts { dusted = dusted || (burst.start > 0 && burst.color == JUICE_DUST && burst.at.x < 6.5) }
	testing.expect(t, dusted)
}

// The killing blow: a pancake, flat as it falls.
@(test)
test_club_killing_blow_leaves_a_pancake :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room, foe := club_juice_test_setup(t, &data, &player, 5)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	for _ in 0..<60 { shadow_view_test_frame(renderer, &room, 0.02) }
	club_juice_test_blow(t, renderer, &room, -math.PI/2)
	for _ in 0..<80 { club_juice_test_frame(renderer, &room, 0.01) }
	b := &renderer.tactical.juice_blows
	testing.expect(t, b.clubs == 1 && b.kills == 1)
	h, w := juice_squash(renderer, foe)
	testing.expectf(t, abs(h-JUICE_PANCAKE) < 1e-3 && w == JUICE_SQUASH_WIDEST, "the pancake is %v by %v", h, w)
}
