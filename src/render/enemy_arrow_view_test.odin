package render

import "core:testing"
import game "../game"
import level "../level"
import view "../engine/view"

// The board of the bolts' tests: a walled 9×4 room, the player at (2,2), an
// archer at (6,2).
@(private = "file")
Bolt_Test_Board :: struct {
	data: level.Level,
	player: game.Player,
	enemies: [1]game.Enemy,
	room: game.Room,
	snapshot: Room_Presentation,
	renderer: ^Renderer,
}

@(private = "file")
bolt_test_board :: proc(t: ^testing.T, b: ^Bolt_Test_Board) {
	rows := [?]string{"#########", "#@......#", "#......>#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	b.data = data
	b.player = game.Player{position = {x = 2, y = 2}, health = 10, stats = {max_health = 10}}
	b.enemies = {{id = 1, archetype = .Archer, position = {x = 6, y = 2}, health = 9, max_health = 9}}
	b.room = make_presentation_timeline_test_room(&b.player, b.enemies[:], nil)
	b.room.level_data = &b.data
	b.snapshot = capture_room_presentation(&b.room)
	b.renderer = attack_test_renderer(&b.snapshot)
	b.renderer.sprite_assets.elapsed = 10
	b.renderer.tactical.mechanics_lab = true
	b.renderer.tactical.lab_sounds = new(Lab_Sounds)
}

@(private = "file")
bolt_test_free :: proc(b: ^Bolt_Test_Board) {
	attack_test_free(b.renderer)
	game.destroy_room(&b.room)
	level.destroy(&b.data)
}

// One started cue at the timeline's head (and whatever follows it).
@(private = "file")
bolt_test_cues :: proc(renderer: ^Renderer, cues: ..Presentation_Cue) {
	renderer.timeline.head, renderer.timeline.count = 0, len(cues)
	for cue, index in cues { renderer.timeline.cues[index] = cue }
	renderer.timeline.cues[0].started = true
}

// The archer's bolt landing in `to`, on `target`.
@(private = "file")
bolt_test_landed :: proc(to: [2]int, target := game.SYSTEM_ENTITY) -> game.Game_Event {
	return {kind = .Arrow_Landed, source = game.enemy_entity(1), target = target, from_position = {x = 6, y = 2}, to_position = {x = to.x, y = to.y}}
}

// Ahead of a flying bolt its cells are lit stronger than the far ones, and
// the light runs.
@(test)
test_a_flying_bolts_course_pulses_stronger_as_it_comes :: proc(t: ^testing.T) {
	far := enemy_bolt_course_alpha(8, 2, 0)
	testing.expect(t, abs(far-0.35) < 1e-5)
	for now in ([?]f32{0, 0.05, 0.1, 0.2}) {
		testing.expect(t, enemy_bolt_course_alpha(3, 2, now) > far+0.2)
	}
	testing.expect(t, abs(enemy_bolt_course_alpha(3, 2, 0)-enemy_bolt_course_alpha(3, 2, 0.08)) > 0.05)
}

// The whistle: louder near the Viandante (never silent far away), higher as
// the bolt comes toward him, lower as it goes.
@(test)
test_a_bolts_whistle_is_louder_near_and_bends_as_it_passes :: proc(t: ^testing.T) {
	ear := view.Vec2{0, 0}
	far, coming := enemy_bolt_whistle({6, 1}, {-1, 0}, ear)
	near, _ := enemy_bolt_whistle({0.5, 1}, {-1, 0}, ear)
	_, going := enemy_bolt_whistle({-4, 1}, {-1, 0}, ear)
	testing.expect(t, far >= ENEMY_BOLT_FAR && far < near && near <= 1)
	testing.expect(t, coming > 1.1 && going < 0.9)
}

// Where it stays: in the wall's face at its height, nose down in the floor at
// its range's end, in the card it reached.
@(test)
test_a_landed_bolt_stays_in_the_wall_the_floor_or_the_card :: proc(t: ^testing.T) {
	b: Bolt_Test_Board
	bolt_test_board(t, &b)
	defer bolt_test_free(&b)
	wall, ok := enemy_bolt_landing(&b.room, bolt_test_landed({0, 2}))
	testing.expect(t, ok)
	testing.expect_value(t, wall.rest, Enemy_Bolt_Rest.Wall)
	testing.expect(t, wall.cell.x == 1 && wall.cell.y == 2)
	testing.expect(t, abs(wall.tip.x-(1-ENEMY_BOLT_BITE)) < 1e-5 && abs(wall.tip.z-2.5) < 1e-5 && wall.way.x == -1)
	floor, _ := enemy_bolt_landing(&b.room, bolt_test_landed({3, 2}))
	testing.expect_value(t, floor.rest, Enemy_Bolt_Rest.Floor)
	testing.expect(t, floor.tip.y < point_ground({3, 2}))
	card, _ := enemy_bolt_landing(&b.room, bolt_test_landed({2, 2}, game.PLAYER_ENTITY))
	testing.expect_value(t, card.rest, Enemy_Bolt_Rest.Card)
	// Not along a line: nothing.
	odd := bolt_test_landed({3, 3})
	_, ok = enemy_bolt_landing(&b.room, odd)
	testing.expect(t, !ok)
	// Stone in the crypt; wood in the Far West, the Giungla and the Vietnam.
	testing.expect(t, !enemy_bolt_in_wood(&b.room))
	b.player.tactical.config.expedition = true
	for biome in 0..<u8(12) {
		b.player.tactical.config.expedition_biome = biome
		testing.expect_value(t, enemy_bolt_in_wood(&b.room), biome == 1 || biome == 2 || biome == 5)
	}
}

// A missed bolt sticks in the wall, once, with its crack of stone; it
// quivers, fades and is gone after ENEMY_BOLT_STUCK_SECONDS.
@(test)
test_a_missed_bolt_sticks_quivers_and_is_gone :: proc(t: ^testing.T) {
	b: Bolt_Test_Board
	bolt_test_board(t, &b)
	defer bolt_test_free(&b)
	bolt_test_cues(b.renderer, {kind = .Arrow_Landed, event = bolt_test_landed({0, 2}), duration = 0.2, batch = 1})
	observe_enemy_bolts(b.renderer, &b.room)
	observe_enemy_bolts(b.renderer, &b.room)
	bolts := &b.renderer.tactical.enemy_bolts
	testing.expect_value(t, bolts.landed[.Wall], 1)
	s := b.renderer.tactical.lab_sounds
	testing.expect_value(t, s.count, 1)
	testing.expect_value(t, s.queue[0].sfx, LAB_BOLT_STONE)
	bolt := bolts.stuck[0]
	_, _, opacity, shown := enemy_bolt_stuck_pose(bolt, bolt.at+0.05)
	testing.expect(t, shown && opacity == 1)
	// The tail swings, less and less.
	early, _, _, _ := enemy_bolt_stuck_pose(bolt, bolt.at+0.02)
	late, _, _, _ := enemy_bolt_stuck_pose(bolt, bolt.at+0.9+0.02)
	still := bolt.tip-bolt.way*ENEMY_BOLT_LENGTH
	testing.expect(t, abs(early.y-still.y) > abs(late.y-still.y) && abs(early.y-still.y) > 0.01)
	_, _, opacity, shown = enemy_bolt_stuck_pose(bolt, bolt.at+ENEMY_BOLT_STUCK_SECONDS-0.1)
	testing.expect(t, shown && opacity < 0.5)
	_, _, _, shown = enemy_bolt_stuck_pose(bolt, bolt.at+ENEMY_BOLT_STUCK_SECONDS)
	testing.expect(t, !shown)
}

// A bolt sticks in the card only when it wounded: one turned back by a guard
// leaves nothing; the lab's own blows sound for the card, not the bolt.
@(test)
test_a_bolt_stays_in_the_card_only_if_it_wounded :: proc(t: ^testing.T) {
	b: Bolt_Test_Board
	bolt_test_board(t, &b)
	defer bolt_test_free(&b)
	landed := bolt_test_landed({2, 2}, game.PLAYER_ENTITY)
	bolt_test_cues(b.renderer, {kind = .Arrow_Landed, event = landed, duration = 0.2, batch = 1})
	observe_enemy_bolts(b.renderer, &b.room)
	testing.expect_value(t, b.renderer.tactical.enemy_bolts.landed[.Card], 0)
	wound := game.Game_Event{kind = .Damaged, source = game.enemy_entity(1), target = game.PLAYER_ENTITY, amount = 3}
	bolt_test_cues(b.renderer, {kind = .Arrow_Landed, event = landed, duration = 0.2, batch = 2}, {kind = .Damage, event = wound, duration = 0.2, batch = 2})
	observe_enemy_bolts(b.renderer, &b.room)
	bolts := &b.renderer.tactical.enemy_bolts
	testing.expect_value(t, bolts.landed[.Card], 1)
	testing.expect_value(t, b.renderer.tactical.lab_sounds.count, 0)
	bolt := bolts.stuck[0]
	_, _, _, shown := enemy_bolt_stuck_pose(bolt, bolt.at+ENEMY_BOLT_PINNED_SECONDS*0.5)
	testing.expect(t, shown)
	_, _, _, shown = enemy_bolt_stuck_pose(bolt, bolt.at+ENEMY_BOLT_PINNED_SECONDS+ENEMY_BOLT_DROP_SECONDS)
	testing.expect(t, !shown)
}

// A flying bolt takes a voice (played once), whistles while it flies, holds
// when the world stands still, flies on, and lets its voice go as it lands.
@(test)
test_a_flying_bolt_whistles_holds_and_lets_go :: proc(t: ^testing.T) {
	b: Bolt_Test_Board
	bolt_test_board(t, &b)
	defer bolt_test_free(&b)
	s := b.renderer.tactical.lab_sounds
	b.room.arrows.items[0] = {origin = {6, 2, 0}, step = {-1, 0}, shooter = 1, damage = 3, flown = 1}
	b.room.arrows.count = 1
	lab_bolt_flights(b.renderer, &b.room, s)
	flight := s.flights[0]
	testing.expect(t, flight.key != 0 && flight.running && flight.pitch > 1)
	testing.expect_value(t, s.played[LAB_BOLT_FLIGHT], 1)
	for _ in 0..<int(ENEMY_BOLT_STILL_FRAMES) { lab_bolt_flights(b.renderer, &b.room, s) }
	testing.expect(t, !s.flights[0].running && s.flights[0].key == flight.key)
	b.room.arrows.items[0].flown = 2
	lab_bolt_flights(b.renderer, &b.room, s)
	testing.expect(t, s.flights[0].running && s.flights[0].volume > flight.volume)
	testing.expect_value(t, s.played[LAB_BOLT_FLIGHT], 1)
	b.room.arrows.count = 0
	lab_bolt_flights(b.renderer, &b.room, s)
	testing.expect_value(t, s.flights[0].key, u32(0))
}
