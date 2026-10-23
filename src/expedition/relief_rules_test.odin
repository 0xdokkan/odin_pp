package expedition

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE RELIEF IN THE RULES OF EXPLORATION (Fase 3): the free walker, the cell step, the sleeping groups and
// their patrols, and what they can see, all follow the same height rules as a fight (game/height.odin):
// a step of height is climbed, a cliff is a wall, a hill hides what is behind it.

@(test)
test_the_free_walker_climbs_a_step_but_is_stopped_by_a_cliff_on_foot_and_mounted :: proc(t: ^testing.T) {
	for mounted in ([2]bool{false, true}) {
		w: World
		data: level.Level
		p: game.Player
		room := roam_test_room(t, &w, &data, &p)
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		w.mounted = mounted
		// A cliff of three steps across the way east.
		for y in 18..=42 { _ = level.set_height(&data, {25, y}, 3) }
		p.position = {22, 30}
		r: Roam
		roam_walk(&w, &room, &r, {1, 0}, 2)
		testing.expect(t, r.position.x <= 25-ROAM_RADIUS+0.001, "stopped by the cliff")
		testing.expect_value(t, p.position, grid.Position{24, 30})
		// The same cells as a stair, one step each, can be climbed.
		for y in 18..=42 {
			_ = level.set_height(&data, {25, y}, 1)
			_ = level.set_height(&data, {26, y}, 2)
			_ = level.set_height(&data, {27, y}, 3)
		}
		roam_walk(&w, &room, &r, {1, 0}, 2)
		testing.expect(t, r.position.x > 27.5, "up the stair")
		testing.expect_value(t, game.cell_height(&room, p.position), i32(3))
	}
}

@(test)
test_the_cell_step_of_exploration_and_the_sleeping_groups_respect_the_cliff :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := roam_test_room(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	_ = level.set_height(&data, {31, 30}, 3)
	p.position = {30, 30}
	testing.expect(t, !walk(&w, &room, {1, 0}), "a cliff is not stepped onto")
	testing.expect_value(t, p.position, grid.Position{30, 30})
	_ = level.set_height(&data, {31, 30}, 1)
	testing.expect(t, walk(&w, &room, {1, 0}), "a step is")
	testing.expect_value(t, p.position, grid.Position{31, 30})
	// A sleeping group does not walk off a cliff or up one.
	g: Group
	g.count = 1
	g.members[0] = Member{enemy = game.Enemy{position = {35, 35}, health = 5}, alive = true}
	_ = level.set_height(&data, {36, 35}, 4)
	move_sleeping_group(&w, &g, &room, {1, 0})
	testing.expect_value(t, g.members[0].enemy.position, grid.Position{35, 35})
	move_sleeping_group(&w, &g, &room, {0, 1})
	testing.expect_value(t, g.members[0].enemy.position, grid.Position{35, 36})
}

@(test)
test_a_hill_hides_what_is_behind_it_from_the_sleeping_groups_eyes :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := roam_test_room(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	testing.expect(t, can_see(&room, {22, 30}, {30, 30}), "open ground")
	// A tall hill across the line: eye six steps over its floor, target four, the hill nine.
	for dy in -2..=2 { _ = level.set_height(&data, {26, 30+dy}, 9) }
	testing.expect(t, !can_see(&room, {22, 30}, {30, 30}), "behind the hill")
	// A low one does not.
	for dy in -2..=2 { _ = level.set_height(&data, {26, 30+dy}, 1) }
	testing.expect(t, can_see(&room, {22, 30}, {30, 30}), "over a low rise")
}
