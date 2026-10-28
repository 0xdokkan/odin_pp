package render

import "core:testing"
import game "../game"
import level "../level"

// Each weapon's look (docs/piano-prima-persona.md, Fase 1): the AK's as ever,
// the others a tag as wide as its, the bare line, an empty hand.

@(test)
test_first_person_each_weapon_has_its_look :: proc(t: ^testing.T) {
	look := FIRST_PERSON_LOOKS[.AK]
	testing.expect(t, look.tag == "FPS" && look.status == FIRST_PERSON_HUD_STATUS && look.hand == .AK)
	tags := [game.First_Person_Weapon]string{.AK = "FPS", .Fists = "FPB", .Sword = "FPF", .Bow = "FPA"}
	for weapon in game.First_Person_Weapon {
		look = FIRST_PERSON_LOOKS[weapon]
		testing.expect_value(t, look.tag, tags[weapon])
		testing.expect_value(t, len(look.tag), len("FPS"))
		if weapon == .AK { continue }
		testing.expect(t, look.status == FIRST_PERSON_HUD_STATUS_BARE && look.hand == .Empty)
	}
	testing.expect_value(t, string(first_person_countdown_text(20, .Fists)), "FPB 20s")
	testing.expect_value(t, string(first_person_countdown_text(13.2, .Sword)), "FPF 14s")
	testing.expect_value(t, string(first_person_countdown_text(0.4, .Bow)), "FPA 1s")
	testing.expect_value(t, string(first_person_countdown_text(30, .AK)), "FPS 30s")
	testing.expect_value(t, string(FIRST_PERSON_HUD_STATUS_BARE), "MIRA COL MOUSE / WASD: PASSI")
	// No renderer: the AK's.
	testing.expect_value(t, first_person_shown_weapon(nil), game.First_Person_Weapon.AK)
}

// The board shows the room's weapon while the view is on and keeps it through
// the rise; another weapon's bytes fly no tracer, whatever the room's counts.
@(test)
test_first_person_board_follows_the_weapon :: proc(t: ^testing.T) {
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
	testing.expect(t, first_person_shown_weapon(renderer) == .AK && first_person_hud_status(renderer) == FIRST_PERSON_HUD_STATUS)
	testing.expect(t, game.tactical_begin_first_person(&room, 20, .Fists))
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		if f.amount >= 1 { break }
	}
	testing.expect(t, f.engaged && f.amount == 1)
	testing.expect_value(t, first_person_shown_weapon(renderer), game.First_Person_Weapon.Fists)
	testing.expect(t, first_person_hud_status(renderer) == FIRST_PERSON_HUD_STATUS_BARE)
	// The room counts a blow of its own: the board takes it as no shot.
	room.first_person.shots += 1
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, f.shots == 0 && f.seen_shots == room.first_person.shots && f.kick_at == 0)
	for tracer in f.tracers { testing.expect(t, !tracer.used) }
	// Out: the rise keeps the fists in hand.
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, !f.engaged && f.amount > 0)
	testing.expect_value(t, first_person_shown_weapon(renderer), game.First_Person_Weapon.Fists)
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		if f.amount <= 0 { break }
	}
	testing.expect_value(t, f.amount, f32(0))
	// The AK again: its look.
	testing.expect(t, game.tactical_begin_first_person(&room, 20))
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, first_person_shown_weapon(renderer) == .AK && first_person_hud_status(renderer) == FIRST_PERSON_HUD_STATUS)
}
