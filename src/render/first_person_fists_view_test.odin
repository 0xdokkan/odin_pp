package render

import "core:math"
import "core:testing"
import game "../game"
import level "../level"

// FIRST PERSON BRAWLER on the board (first_person_fists.odin): the eye rides the
// free body a little behind it, never inside a wall, with the fists' wider view;
// as the view ends it settles back on his cell; a glove goes out over its
// punch's landing time and comes back.
@(test)
test_first_person_fists_eye_rides_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	f := &renderer.tactical.first_person
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, game.tactical_begin_first_person(&room, 20, .Fists))
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		if f.amount >= 1 { break }
	}
	testing.expect(t, f.engaged && f.amount == 1)
	// The body moved free off his cell's centre: the eye over it, a little behind.
	room.first_person.fists.body = {6.8, 6.3}
	shadow_view_test_frame(renderer, &room, 0.02)
	back := [2]f32{-math.cos(f.yaw), -math.sin(f.yaw)}
	want := [2]f32{6.8, 6.3}+back*FIRST_PERSON_FISTS_EYE_BACK
	testing.expectf(t, abs(f.eye.x-want.x) < 1e-3 && abs(f.eye.z-want.y) < 1e-3, "eye %v, want %v", f.eye, want)
	testing.expect(t, abs(renderer.tactical.camera.fovy-FIRST_PERSON_FISTS_FOV) < 1e-3, "not the fists' view")
	// Backed up to the room's edge, the eye never goes into the wall.
	f.yaw = 0
	room.first_person.fists.body = {1.35, 6.5}
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, f.eye.x >= 1, "the eye went into the wall")
	// The view over: the eye settles on his cell's centre.
	room.first_person.fists.body = {6.8, 6.3}
	shadow_view_test_frame(renderer, &room, 0.02)
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	for _ in 0..<10 { shadow_view_test_frame(renderer, &room, 0.02) }
	testing.expect(t, !f.engaged)
	testing.expect(t, abs(f.eye.x-6.5) < 1e-3 && abs(f.eye.z-6.5) < 1e-3, "the eye did not settle on his cell")
}

@(test)
test_first_person_glove_goes_out_and_back :: proc(t: ^testing.T) {
	for punch in ([4]game.First_Person_Punch{.Jab, .Cross, .Left_Hook, .Right_Hook}) {
		rules := game.FISTS_PUNCHES[punch]
		testing.expect_value(t, first_person_glove_reach(punch, 0), f32(0))
		testing.expect_value(t, first_person_glove_reach(punch, rules.land), f32(1))
		testing.expect(t, first_person_glove_reach(punch, rules.land*0.5) > 0 && first_person_glove_reach(punch, rules.land*0.5) < 1)
		testing.expect_value(t, first_person_glove_reach(punch, rules.recover), f32(0))
	}
	testing.expect_value(t, first_person_glove_reach(.None, 0.1), f32(0))
}

// The 3D gloves' guard (first_person_gloves.odin): both up in the middle of the
// view's bottom, below the crosshair and clear of it, the left (the lead)
// farther out than the right; the jab takes the left out to the crosshair, the
// right staying at the chin; a hook swings out wide of its side and lands past
// the middle.
@(test)
test_first_person_gloves_guard_and_punches :: proc(t: ^testing.T) {
	// Where a glove's centre shows across and up the view (-1..1), 16:9.
	shown :: proc(at: [3]f32) -> [2]f32 {
		tan := f32(math.tan(f64(FIRST_PERSON_GLOVE_FOV)*math.PI/360))
		return {at.x/(-at.z*tan*16.0/9.0), at.y/(-at.z*tan)}
	}
	left := first_person_glove_pose(0, .None, 0, 1, 0, 0)
	right := first_person_glove_pose(1, .None, 0, 1, 0, 0)
	for pose in ([2]First_Person_Glove_Pose{left, right}) {
		p := shown(pose.at)
		testing.expectf(t, abs(p.x) > 0.12 && abs(p.x) < 0.45, "a glove at %v across, not beside the middle", p.x)
		testing.expectf(t, p.y < -0.35 && p.y > -0.9, "a glove at %v up, not low in the view", p.y)
	}
	testing.expect(t, shown(left.at).x < 0 && shown(right.at).x > 0, "the gloves on the wrong sides")
	testing.expect(t, left.at.z < right.at.z, "the lead is not the left")
	// The jab landed: the left at the crosshair, farther out; the right still at the chin.
	land := game.FISTS_PUNCHES[.Jab].land
	jab := first_person_glove_pose(0, .Jab, land, 1, 0, 0)
	testing.expect(t, abs(shown(jab.at).x) < 0.12 && jab.at.z < left.at.z-0.15, "the jab did not go out to the crosshair")
	held := first_person_glove_pose(1, .Jab, land, 1, 0, 0)
	testing.expect(t, abs(held.at.x-right.at.x) < 0.02 && held.at.z > right.at.z, "the right left the chin")
	// The left hook: out wide of the left on its way, then past the middle.
	hook := game.FISTS_PUNCHES[.Left_Hook].land
	out := first_person_glove_pose(0, .Left_Hook, hook*0.5, 1, 0, 0)
	landed := first_person_glove_pose(0, .Left_Hook, hook, 1, 0, 0)
	testing.expect(t, out.at.x < left.at.x-0.05, "the hook did not swing out wide")
	testing.expect(t, landed.at.x > 0 && abs(landed.yaw) > 1, "the hook did not land past the middle, the knuckles in")
	// Coming in, the guard rises from under the view.
	testing.expect(t, first_person_glove_pose(0, .None, 0, 0, 0, 0).at.y < left.at.y-0.2)
}

// A landed punch (Fase 3): the gloves hold for the stop, then catch up with the
// rules; the look jolts, twice as hard on a critical, and settles; only the
// struck foe's print goes white, for the stop, then fades.
@(test)
test_first_person_punch_impact :: proc(t: ^testing.T) {
	testing.expect_value(t, first_person_glove_display_clock(0.2, 0.03), f32(0.2)-0.03)
	testing.expect_value(t, first_person_glove_display_clock(0.2, FIRST_PERSON_HITSTOP), f32(0.2)-FIRST_PERSON_HITSTOP)
	caught := first_person_glove_display_clock(0.3, FIRST_PERSON_HITSTOP+FIRST_PERSON_HITSTOP_CATCH*0.5)
	testing.expect(t, caught > 0.3-FIRST_PERSON_HITSTOP && caught < 0.3, "the gloves did not catch up")
	testing.expect_value(t, first_person_glove_display_clock(0.3, 1), f32(0.3))
	testing.expect_value(t, first_person_glove_display_clock(0.01, 0.05), f32(0))
	testing.expect_value(t, first_person_punch_shake(0, false), FIRST_PERSON_PUNCH_JOLT)
	testing.expect_value(t, first_person_punch_shake(0, true), FIRST_PERSON_PUNCH_JOLT*2)
	testing.expect(t, first_person_punch_shake(0.08, true) < first_person_punch_shake(0.02, true), "the jolt does not settle")
	testing.expect_value(t, first_person_punch_shake(FIRST_PERSON_PUNCH_JOLT_SECONDS, true), f32(0))
	renderer := new(Renderer)
	defer free(renderer)
	f := &renderer.tactical.first_person
	f.weapon, f.amount, f.fists_struck, f.fists_hit_at = .Fists, 1, 7, 10
	renderer.sprite_assets.elapsed = 10.05
	testing.expect_value(t, first_person_struck_flash(renderer, game.enemy_entity(7)), f32(1))
	testing.expect_value(t, first_person_struck_flash(renderer, game.enemy_entity(8)), f32(0))
	renderer.sprite_assets.elapsed = 10+f64(FIRST_PERSON_HITSTOP+FIRST_PERSON_STRUCK_FADE*0.5)
	flash := first_person_struck_flash(renderer, game.enemy_entity(7))
	testing.expect(t, flash > 0.4 && flash < 0.6, "the flash does not fade")
	renderer.sprite_assets.elapsed = 11
	testing.expect_value(t, first_person_struck_flash(renderer, game.enemy_entity(7)), f32(0))
	f.weapon = .AK
	renderer.sprite_assets.elapsed = 10.05
	testing.expect_value(t, first_person_struck_flash(renderer, game.enemy_entity(7)), f32(0))
}

// The critical's gold star (Fase 3): it bursts past its size, settles, then
// shrinks away in half a second, turning; its sparks fly out and are gone.
@(test)
test_first_person_critical_star :: proc(t: ^testing.T) {
	scale, _, sparks := first_person_star(0)
	testing.expect(t, scale == 0 && sparks == 0)
	burst, _, _ := first_person_star(0.12)
	testing.expect(t, burst > 1.2, "the star does not burst")
	held, turn, _ := first_person_star(0.25)
	testing.expect(t, held == 1 && turn > 0)
	late, _, flown := first_person_star(0.45)
	testing.expect(t, late > 0 && late < 0.5 && flown == 1)
	gone, _, _ := first_person_star(FIRST_PERSON_STAR_SECONDS)
	testing.expect_value(t, gone, f32(0))
}

// The lab hears the fists (Fase 3): a punch's air as it leaves, its blow by
// punch or the critical's ding as it lands, a mark's tick as it lights; the
// music only once the gloves are up and the bell has rung, in the lab.
@(test)
test_first_person_fists_lab_sounds :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	renderer.tactical.mechanics_lab = true
	renderer.tactical.living_state = new(Living_State)
	defer free(renderer.tactical.living_state)
	defer destroy_lab_sounds(renderer)
	frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
		shadow_view_test_frame(renderer, room, dt)
		update_lab_sounds(renderer, room, renderer.sprite_assets.elapsed)
		play_lab_sounds(renderer, nil, 0)
	}
	frame(renderer, &room, 0.01)
	sounds := renderer.tactical.lab_sounds
	if !testing.expect(t, sounds != nil) { return }
	testing.expect(t, game.tactical_begin_first_person(&room, 20, .Fists))
	f := &renderer.tactical.first_person
	for _ in 0..<60 {
		frame(renderer, &room, 0.02)
		if f.amount >= 1 { break }
	}
	testing.expect(t, f.engaged && f.amount >= 1)
	testing.expect(t, !first_person_music_wanted(renderer), "the music before the bell")
	// A jab thrown: its air; landed: its blow; a hook landed as a critical: the ding.
	before := sounds.played
	room.first_person.shots += 1
	room.first_person.fists.punch = .Jab
	frame(renderer, &room, 0.02)
	testing.expect_value(t, sounds.played[LAB_FISTS_WHOOSH]-before[LAB_FISTS_WHOOSH], 1)
	room.first_person.hits += 1
	frame(renderer, &room, 0.02)
	testing.expect_value(t, sounds.played[LAB_FISTS_HIT[.Jab]]-before[LAB_FISTS_HIT[.Jab]], 1)
	room.first_person.fists.punch = .Left_Hook
	room.first_person.hits += 1
	room.first_person.fists.crits += 1
	frame(renderer, &room, 0.02)
	testing.expect_value(t, sounds.played[LAB_FISTS_CRIT]-before[LAB_FISTS_CRIT], 1)
	testing.expect_value(t, sounds.played[LAB_FISTS_HIT[.Left_Hook]]-before[LAB_FISTS_HIT[.Left_Hook]], 0)
	// A mark lighting: one tick, not one a frame.
	ticks := sounds.played[LAB_FISTS_MARK]
	for &mark in room.first_person.fists.marks {
		if mark.enemy_id != 0 { mark.lit, mark.wait, mark.zone = 1, 0, 2; break }
	}
	lit := false
	for mark in room.first_person.fists.marks { lit = lit || (mark.enemy_id != 0 && mark.lit > 0) }
	if lit {
		for _ in 0..<3 { frame(renderer, &room, 0.01) }
		testing.expect_value(t, sounds.played[LAB_FISTS_MARK]-ticks, 1)
	}
	// The bell rung: the music, in the lab only.
	for _ in 0..<60 { frame(renderer, &room, 0.02) }
	testing.expect(t, first_person_music_wanted(renderer), "no music once the gloves are up")
	renderer.tactical.mechanics_lab = false
	testing.expect(t, !first_person_music_wanted(renderer), "music outside the lab")
}

// A sword's cut on the board (Fase 4, after the user's try): the blade held at
// the cut a moment, then back to the mouse; the blood opens at once, thins away
// in half a second, its drops flying out and gone.
@(test)
test_first_person_sword_cut_feedback :: proc(t: ^testing.T) {
	v := First_Person_Sword_View{tip = {0.3, 0.1}, cut_at = 10, cut_tip = {-0.1, 0.05}}
	testing.expect_value(t, first_person_sword_shown_tip(&v, 10.03), [2]f32{-0.1, 0.05})
	back := first_person_sword_shown_tip(&v, 10+FIRST_PERSON_SWORD_STOP*1.5)
	testing.expect(t, back.x > -0.1 && back.x < 0.3, "the blade did not come back")
	testing.expect_value(t, first_person_sword_shown_tip(&v, 11), [2]f32{0.3, 0.1})
	streak, flown := first_person_sword_blood(0.06)
	testing.expect(t, streak > 0.9 && flown < 0.2)
	streak, flown = first_person_sword_blood(0.4)
	testing.expect(t, streak > 0 && streak < 0.5 && flown > 0.7)
	streak, flown = first_person_sword_blood(FIRST_PERSON_SWORD_BLOOD)
	testing.expect(t, streak == 0 && flown == 1)
}

// The words of what made a cut stronger (the user could not tell a spinning
// cut from another): spin, lunge, perfect; none for a plain cut.
@(test)
test_first_person_sword_words :: proc(t: ^testing.T) {
	testing.expect(t, first_person_sword_words({}) == nil)
	testing.expect_value(t, string(first_person_sword_words({spin = true})), "COLPO ROTEANTE x1,5")
	testing.expect_value(t, string(first_person_sword_words({lunge = true})), "AFFONDO x1,25")
	testing.expect_value(t, string(first_person_sword_words({perfect = true})), "TAGLIO PERFETTO")
	testing.expect_value(t, string(first_person_sword_words({spin = true, lunge = true})), "ROTEANTE x1,5 + AFFONDO")
}
