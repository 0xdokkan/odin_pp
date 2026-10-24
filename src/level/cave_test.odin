package level

import "core:testing"
import grid "../engine/grid"

// Every cell of the plan that is floor, reached by a walk of four-way steps from the arrival.
@(private = "file")
cave_reach :: proc(plan: ^Cave_Plan) -> (seen: [CAVE_HEIGHT][CAVE_WIDTH]bool) {
	queue: [CAVE_WIDTH*CAVE_HEIGHT]grid.Position
	tail := 1
	queue[0] = plan.arrival
	seen[plan.arrival.y][plan.arrival.x] = true
	for head := 0; head < tail; head += 1 {
		for offset in ([4]grid.Position{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			q := grid.Position{queue[head].x+offset.x, queue[head].y+offset.y}
			if cave_plan_at(plan, q.x, q.y) != '.' || seen[q.y][q.x] { continue }
			seen[q.y][q.x] = true
			queue[tail] = q
			tail += 1
		}
	}
	return
}

// Every seed gives a cave of two or three rooms with rock all round, whose every floor cell can be walked to from the
// arrival, with the secret at the far end and the foes' groups in the rooms.
@(test)
test_every_cave_is_one_connected_set_of_rooms_with_rock_all_round :: proc(t: ^testing.T) {
	two, three := 0, 0
	for seed in u64(0)..<300 {
		plan := cave_plan(seed*7919+13)
		if plan.rooms == 2 { two += 1 } else { three += 1 }
		testing.expect(t, plan.rooms == 2 || plan.rooms == 3)
		for x in 0..<CAVE_WIDTH { testing.expect(t, plan.rows[0][x] == '#' && plan.rows[CAVE_HEIGHT-1][x] == '#') }
		for y in 0..<CAVE_HEIGHT { testing.expect(t, plan.rows[y][0] == '#' && plan.rows[y][CAVE_WIDTH-1] == '#') }
		seen := cave_reach(&plan)
		floors, unreached := 0, 0
		for y in 0..<CAVE_HEIGHT { for x in 0..<CAVE_WIDTH {
			if plan.rows[y][x] == '.' { floors += 1; if !seen[y][x] { unreached += 1 } }
		}}
		testing.expectf(t, unreached == 0, "seed %d: %d of %d floor cells cannot be walked to", seed, unreached, floors)
		testing.expectf(t, floors >= 150 && floors <= 400, "seed %d: %d floor cells", seed, floors)
		testing.expect(t, seen[plan.secret.y][plan.secret.x], "the secret can be walked to")
		testing.expect_value(t, cave_plan_at(&plan, plan.arrival.x, plan.arrival.y), u8('.'))
		// The secret is at the far end, the arrival at the near end.
		testing.expectf(t, plan.secret.x >= CAVE_WIDTH-4 && plan.arrival.x <= 4, "seed %d: arrival %v secret %v", seed, plan.arrival, plan.secret)
		testing.expect(t, plan.groups >= 1 && plan.groups <= 3)
		for g in 0..<plan.groups {
			a := plan.anchors[g]
			testing.expectf(t, cave_plan_at(&plan, a.x, a.y) == '.' && seen[a.y][a.x], "seed %d: group %d is not on floor", seed, g)
			testing.expect(t, abs(a.x-plan.arrival.x) >= 6, "a group is not at the arrival")
			testing.expect(t, plan.foes[g] >= 2 && plan.foes[g] <= 4)
		}
	}
	testing.expect(t, two >= 60 && three >= 60, "both sizes of cave come up")
}

@(test)
test_a_cave_is_the_same_every_time_and_differs_between_seeds :: proc(t: ^testing.T) {
	a, b := cave_plan(77), cave_plan(77)
	testing.expect(t, a.rows == b.rows && a.arrival == b.arrival && a.secret == b.secret)
	different := 0
	for seed in u64(1)..<20 { if cave_plan(seed).rows != a.rows { different += 1 } }
	testing.expect(t, different >= 15, "the caves vary")
}

@(test)
test_a_cave_is_stamped_whole_and_only_where_asked :: proc(t: ^testing.T) {
	data, _ := create(60, 40, Tile{kind = .Floor})
	defer destroy(&data)
	plan := cave_plan(5)
	testing.expect(t, cave_stamp(&data, {10, 8}, &plan))
	for y in 0..<CAVE_HEIGHT { for x in 0..<CAVE_WIDTH {
		tile, _ := tile_at(&data, {10+x, 8+y})
		testing.expect_value(t, tile.kind, Tile_Kind.Wall if plan.rows[y][x] == '#' else Tile_Kind.Floor)
	}}
	outside, _ := tile_at(&data, {9, 8})
	testing.expect_value(t, outside.kind, Tile_Kind.Floor)
	testing.expect(t, !cave_stamp(&data, {40, 8}, &plan), "it does not fit at the east edge")
	testing.expect(t, !cave_stamp(&data, {-1, 0}, &plan))
}
