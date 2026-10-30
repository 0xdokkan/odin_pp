package render

import "core:testing"
import game "../game"
import grid "../engine/grid"

// FIRST PERSON FENCER (foresee_first_person_blows): in the sword's view a blow
// at the player lands on screen on its beat. The brute's cleaver starts as
// soon as its countdown is as short as its swing, its contact exactly when
// the countdown runs out; the cues of the resolved blow find it and show no
// second one. A blow that will not come is taken back; the AK's view never
// begins one early.
@(test)
test_first_person_sword_blows_land_on_their_beat :: proc(t: ^testing.T) {
	player := game.Player{position = {x = 2, y = 2}, health = 10, stats = {max_health = 10}}
	enemies := [?]game.Enemy{{id = 1, archetype = .Brute, position = {x = 3, y = 2}, health = 5, max_health = 5}}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	room.first_person.active, room.first_person.weapon = true, .Sword
	brute := &room.enemies[0]
	brute.intent = {kind = .Attack, origin = brute.position, damage = 2, planned_pulse = 5}
	brute.intent.threatened_cells[0] = player.position
	brute.intent.threatened_cell_count = 1
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer attack_test_free(renderer)
	snapshot = renderer_presentation_snapshot(renderer, &room)
	impact := attack_fx_impact_seconds(.Brute)
	// Too far off yet.
	brute.tactical_cooldown = f32(impact)+0.5
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 0)
	// As short as its swing: the cleaver comes, landing on the beat.
	left := impact*0.8
	brute.tactical_cooldown = f32(left)
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 1)
	fx := &renderer.tactical.attack_fx.items[0]
	testing.expect(t, fx.foreseen && fx.victim == game.PLAYER_ENTITY && fx.kind == .Swing)
	clock := living_clock(renderer, game.enemy_entity(1))
	testing.expectf(t, abs(fx.landing-clock-left) < 1e-5, "lands %v s on, the beat %v", fx.landing-clock, left)
	// Once only.
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 1)
	// The beat resolves it: its cues find it on the board.
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, attack_test_blow(.Damaged, game.enemy_entity(1), game.PLAYER_ENTITY, brute.position, player.position, []grid.Position{player.position}))
	testing.expect(t, begin_renderer_world_timeline(renderer, before, &events, &before))
	for _ in 0..<3 {
		snapshot = renderer_presentation_snapshot(renderer, &room)
		observe_attack_cues(renderer)
		renderer.sprite_assets.elapsed += 1.0/60
	}
	testing.expect_value(t, attack_test_used(renderer), 1)
	testing.expect(t, fx.batch != 0 && fx.outcome == .Hit && fx.damage == 2)
	testing.expect_value(t, renderer.tactical.attack_fx.spawned[.Cleaver], 1)
	// A blow that will not come: taken back.
	forget_attack_fx(renderer)
	brute.intent.planned_pulse = 6
	brute.tactical_cooldown = f32(impact)
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 1)
	brute.intent.kind = .Move
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 0)
	// The AK's view shows it after its beat, as ever.
	brute.intent.kind, brute.intent.planned_pulse = .Attack, 7
	room.first_person.weapon = .AK
	foresee_first_person_blows(renderer, &room)
	testing.expect_value(t, attack_test_used(renderer), 0)
}
