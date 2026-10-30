package render

import "core:testing"
import gfx "../engine/gfx"
import game "../game"

// The board's actions at the player's pace (action_pace.odin): the game as it
// is played (timed actions) shows them in half their first times; behind the
// eyes and under the bare rules they keep the first ones.
@(test)
test_the_action_scale_follows_the_players_pace :: proc(t: ^testing.T) {
	testing.expect_value(t, action_scale(nil), f64(1))
	testing.expect_value(t, action_scale(&Room_Presentation{}), f64(1))
	testing.expect_value(t, action_scale(&Room_Presentation{pace = 1}), f64(1))
	testing.expect_value(t, action_scale(&Room_Presentation{pace = 2}), f64(0.5))
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	bare := capture_room_presentation(&room)
	testing.expect_value(t, action_scale(&bare), f64(1))
	player.tactical.config.timed_actions = true
	played := capture_room_presentation(&room)
	testing.expect_value(t, played.pace, game.TACTICAL_PLAYER_PACE)
	testing.expect_value(t, action_scale(&played), f64(1/game.TACTICAL_PLAYER_PACE))
	room.first_person.active = true
	eyes := capture_room_presentation(&room)
	testing.expect_value(t, action_scale(&eyes), f64(1))
}

@(test)
test_cues_play_at_the_rooms_pace :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	testing.expect(t, game.initialize_starter_deck(&player.deck, 123))
	testing.expect(t, game.begin_deck_combat(&player.deck))
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	card := before.deck.hand[0]
	events: game.Event_Log
	game.record_event(&events, {kind = .Card_Played, target = game.PLAYER_ENTITY, card_id = card.id,
		card_definition = card.definition_id, from_card_zone = .Hand, to_card_zone = .Resolving})
	for pace in ([2]f32{1, 2}) {
		after := before
		after.pace = pace
		timeline: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&timeline, before, &events, &after))
		cue, found := active_presentation_cue(&timeline)
		testing.expect(t, found)
		testing.expectf(t, abs(cue.duration-PRESENTATION_CARD_PLAY_DURATION/pace) < 1e-6, "at pace %v the card's cue lasts %v", pace, cue.duration)
	}
}

@(test)
test_one_shot_clips_play_at_their_scale_and_loops_keep_theirs :: proc(t: ^testing.T) {
	sheet := &gfx.LIVING_SHEETS[.Pilgrim]
	attack := &sheet.clips[gfx.living_resolve(.Pilgrim, .Attack)]
	idle := &sheet.clips[.Idle]
	testing.expect(t, !attack.loop && idle.loop)
	testing.expect_value(t, living_played_seconds(attack, 0.5), gfx.living_clip_seconds(attack)*0.5)
	testing.expect_value(t, living_played_hit(attack, 0.5), gfx.living_hit_seconds(attack)*0.5)
	testing.expect_value(t, living_played_seconds(attack, 0), gfx.living_clip_seconds(attack))
	testing.expect_value(t, living_played_seconds(idle, 0.5), gfx.living_clip_seconds(idle))
	for elapsed in ([4]f64{0.05, 0.2, 0.6, 2}) {
		quick, quick_done := living_played_frame(attack, elapsed*0.5, 0.5)
		first, first_done := gfx.living_frame(attack, elapsed)
		testing.expectf(t, quick == first && quick_done == first_done, "%v s in: %v against %v", elapsed, quick, first)
		loop, _ := living_played_frame(idle, elapsed, 0.5)
		same, _ := gfx.living_frame(idle, elapsed)
		testing.expect_value(t, loop, same)
	}
	move := &sheet.clips[gfx.living_resolve(.Pilgrim, .Move_Side)]
	start, length := living_played_travel(move, 0.5)
	testing.expect_value(t, start, f64(move.travel_start)/1000*0.5)
	testing.expect_value(t, length, f64(move.travel_ms)/1000*0.5)
}

// A blow the board begins at the player's pace lands in half its first time.
@(test)
test_a_blow_at_the_players_pace_lands_in_half_the_time :: proc(t: ^testing.T) {
	for pace in ([2]f32{1, 2}) {
		snapshot := Room_Presentation{valid = true, pace = pace}
		renderer := attack_test_renderer(&snapshot)
		defer attack_test_free(renderer)
		id, ok := play_attack_swing(renderer, game.PLAYER_ENTITY, game.enemy_entity(1), .Lantern, {x = 3, y = 2})
		testing.expect(t, ok)
		fx := attack_fx_by_id(renderer, id)
		if !testing.expect(t, fx != nil) { continue }
		testing.expect_value(t, fx.scale, f64(1/pace))
		testing.expectf(t, abs(fx.contact-fx.start-attack_fx_impact_seconds(.Pilgrim)/f64(pace)) < 1e-9,
			"at pace %v the swing lands %v s on", pace, fx.contact-fx.start)
	}
}
