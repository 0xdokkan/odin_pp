package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_ground_snapshot_preserves_pools_across_the_largest_expedition :: proc(t: ^testing.T) {
	// In a 224-wide map the former 128*128 capacity ended partway through
	// row 73. Exercise both sides of that boundary and the final map cell.
	SIDE :: 224
	data, ok := level.create(SIDE, SIDE, {.Floor})
	testing.expect(t, ok)
	defer level.destroy(&data)
	player: game.Player
	room := game.Room{level_data = &data, player = &player}
	room.ground.pool = make([]i32, SIDE*SIDE)
	defer delete(room.ground.pool)
	before := capture_room_presentation(&room)
	cells := [?]grid.Position{{x = 0, y = 0}, {x = 31, y = 73}, {x = 32, y = 73}, {x = 100, y = 180}, {x = 223, y = 223}}
	for cell in cells { room.ground.pool[cell.y*SIDE+cell.x] = 3 }
	room.ground.fires[0] = {center = {x = 220, y = 222}, burn = 2}
	room.ground.fire_count = 1
	room.fishing.water[0] = {x = 222, y = 221}
	room.fishing.water_count = 1
	after := capture_room_presentation(&room)
	testing.expect(t, before.valid && after.valid)
	testing.expect_value(t, after.dropped, 0)
	testing.expect_value(t, after.ground.width, SIDE)
	for cell in cells {
		testing.expect(t, !presentation_ground_pool(&before.ground, cell))
		testing.expectf(t, presentation_ground_pool(&after.ground, cell), "pool at %v lost from the expedition snapshot", cell)
	}
	for cell in ([?]grid.Position{{x = 30, y = 73}, {x = 33, y = 73}, {x = 222, y = 223}, {x = 223, y = 222}, {x = -1, y = 0}, {x = 224, y = 0}, {x = 0, y = 224}}) {
		testing.expectf(t, !presentation_ground_pool(&after.ground, cell), "dry or off-map cell %v aliased a pool", cell)
	}
	testing.expect_value(t, after.ground.fire_count, 1)
	testing.expect(t, after.ground.fires[0] == room.ground.fires[0])
	testing.expect(t, presentation_ground_water(&after.ground, {x = 222, y = 221}))
	// Mutating the live map and then copying a historical snapshot must not
	// alter either earlier value held by playback.
	for &value in room.ground.pool { value = 0 }
	cleared := capture_room_presentation(&room)
	copy_of_after := after
	for cell in cells {
		testing.expect(t, !presentation_ground_pool(&cleared.ground, cell))
		testing.expect(t, presentation_ground_pool(&after.ground, cell) && presentation_ground_pool(&copy_of_after.ground, cell))
	}
}
