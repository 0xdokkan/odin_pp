package render

import "core:testing"
import audio "../engine/audio"
import gfx "../engine/gfx"
import game "../game"

// Every card has its own sound, and every character sounds its steps, hurts
// and fall.
@(test)
test_lab_sounds_cover_every_card_and_character :: proc(t: ^testing.T) {
	seen: [audio.Lab_Sfx]bool
	for card in game.Card_Id {
		if card == .Count { continue }
		sfx, ok := lab_card_sfx(card)
		testing.expectf(t, ok, "%v has no sound", card)
		testing.expectf(t, !seen[sfx], "%v shares its sound", card)
		seen[sfx] = true
	}
	for character in gfx.Flipbook_Character {
		for action in ([?]gfx.Living_Action{.Move_Side, .Move_Up, .Move_Down, .Hurt, .Hurt_Back, .Death}) {
			_, ok := lab_actor_sfx(character, action, .Damage, 1)
			testing.expectf(t, ok, "%v %v has no sound", character, action)
		}
		_, ok := lab_actor_sfx(character, gfx.living_resolve(character, .Attack), .Damage, 0)
		testing.expectf(t, ok, "%v's attack has no sound", character)
	}
	// The pilgrim's own steps differ by direction; a brute's long run charges.
	side, _ := lab_actor_sfx(.Pilgrim, .Move_Side, .Move, 1)
	up, _ := lab_actor_sfx(.Pilgrim, .Move_Up, .Move, 1)
	testing.expect(t, side != up)
	walk, _ := lab_actor_sfx(.Brute, .Move_Side, .Move, 1)
	charge, _ := lab_actor_sfx(.Brute, .Move_Side, .Move, 3)
	testing.expect(t, walk == .Brute_Move && charge == .Brute_Charge)
	// A blocked step only bumps; a blow stopped by the ward is the block.
	_, bumped := lab_actor_sfx(.Pilgrim, .Block, .Move_Blocked, 0)
	ward, blocked := lab_actor_sfx(.Pilgrim, .Block, .Damage_Absorbed, 0)
	testing.expect(t, !bumped && blocked && ward == .Pilgrim_Block)
	// The telegraphs and the daze have their loops' sounds.
	aim, aims := lab_base_sfx(.Archer, .Windup)
	daze, dazed := lab_base_sfx(.Pilgrim, .Stunned)
	testing.expect(t, aims && aim == .Archer_Aim && dazed && daze == .Pilgrim_Stunned)
	_, idle := lab_base_sfx(.Ghoul, .Idle)
	testing.expect(t, !idle)
	// The ambience is the one loop.
	for sfx in audio.Lab_Sfx { testing.expect(t, audio.LAB_SFX_LOOP[sfx] == (sfx == .Amb_Crypt_Loop)) }
}

// A cue showing for many frames sounds once; the same effect twice at once
// is one sound; what is due waits for its moment.
@(test)
test_lab_sounds_play_each_event_once_and_on_time :: proc(t: ^testing.T) {
	s: Lab_Sounds
	event := game.Game_Event{kind = .Card_Played, source = game.PLAYER_ENTITY, card_definition = .Tesla_Coil, card_id = 4}
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, event, 10))
	testing.expect(t, lab_sound_heard(&s, .Card_Played, event, 10.5))
	other := event
	other.card_id = 5
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, other, 10.5))
	testing.expect(t, !lab_sound_heard(&s, .Card_Played, event, 10+LAB_SOUND_HEARD_SECONDS+0.1))
	lab_sound_queue(&s, .Ui_Gold, 1)
	lab_sound_queue(&s, .Ui_Gold, 1.01)
	lab_sound_queue(&s, .Ui_Energy, 1.01)
	lab_sound_queue(&s, .Ui_Gold, 1.2)
	testing.expect_value(t, s.count, 3)
	renderer: Renderer
	renderer.tactical.lab_sounds = &s
	renderer.sprite_assets.elapsed = 1.1
	play_lab_sounds(&renderer, nil, 0)
	testing.expect_value(t, s.count, 1)
	testing.expect(t, s.played[.Ui_Gold] == 1 && s.played[.Ui_Energy] == 1)
	renderer.sprite_assets.elapsed = 1.3
	play_lab_sounds(&renderer, nil, 0)
	testing.expect(t, s.count == 0 && s.played[.Ui_Gold] == 2)
}

// Outside the lab the board is silent.
@(test)
test_lab_sounds_only_in_the_lab :: proc(t: ^testing.T) {
	player: game.Player
	room := game.Room{player = &player, phase = .Combat}
	state: Living_State
	renderer: Renderer
	renderer.tactical.living_state = &state
	update_lab_sounds(&renderer, &room, 1)
	testing.expect(t, renderer.tactical.lab_sounds == nil)
	renderer.tactical.mechanics_lab = true
	snapshot: Room_Presentation
	renderer.tactical.snapshot = &snapshot
	update_lab_sounds(&renderer, &room, 1)
	testing.expect(t, renderer.tactical.lab_sounds != nil)
	destroy_lab_sounds(&renderer)
	testing.expect(t, renderer.tactical.lab_sounds == nil)
}

// The room's moments: the clock's beat, the window running out, the stun and
// the defence prompt.
@(test)
test_lab_sounds_hear_the_room :: proc(t: ^testing.T) {
	player: game.Player
	player.tactical.config.enabled = true
	room := game.Room{player = &player, phase = .Combat}
	s: Lab_Sounds
	lab_watch_room(&s, &room, 0)
	testing.expect_value(t, s.count, 0)
	player.tactical.beat_index = 1
	lab_watch_room(&s, &room, 1)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Ui_Beat_Tick)
	player.tactical.phase, player.tactical.remaining = .Recovery, 2
	lab_watch_room(&s, &room, 2)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Window_End)
	player.tactical.phase = .Stunned
	lab_watch_room(&s, &room, 3)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Stun)
	room.qte.kind = .Defense
	lab_watch_room(&s, &room, 4)
	testing.expect(t, s.queue[s.count-1].sfx == .Ui_Defense_Prompt)
}

// A card played sounds as that card, and the coil it sets down is not heard
// twice; a coil's discharge zaps once however many links it strikes.
@(test)
test_lab_sounds_of_cards_and_devices :: proc(t: ^testing.T) {
	renderer: Renderer
	snapshot: Room_Presentation
	renderer.tactical.snapshot = &snapshot
	s: Lab_Sounds
	impacts := 0
	played := Presentation_Cue{kind = .Card_Played, started = true,
		event = {kind = .Card_Played, source = game.PLAYER_ENTITY, card_definition = .Tesla_Coil}}
	lab_cue_sounds(&renderer, &s, &played, 1, &impacts)
	testing.expect(t, s.count == 1 && s.queue[0].sfx == .Card_Tesla_Coil)
	coil := Presentation_Cue{kind = .Object_Spawned, started = true, event = {kind = .Object_Spawned, object_kind = .Tesla_Coil}}
	lab_cue_sounds(&renderer, &s, &coil, 1.2, &impacts)
	testing.expect_value(t, s.count, 1)
	lab_cue_sounds(&renderer, &s, &coil, 3, &impacts)
	testing.expect(t, s.count == 2 && s.queue[1].sfx == .World_Tesla_Deploy)
	zap := Presentation_Cue{kind = .Spell_Impact, started = true, event = {kind = .Spell_Impact, card_definition = .Tesla_Coil}}
	for _ in 0..<2 { lab_cue_sounds(&renderer, &s, &zap, 1, &impacts) }
	testing.expect_value(t, impacts, 2)
	boom := Presentation_Cue{kind = .Explosion, started = true, event = {kind = .Explosion, object_kind = .Barrel}}
	lab_cue_sounds(&renderer, &s, &boom, 1, &impacts)
	testing.expect(t, s.queue[s.count-1].sfx == .World_Barrel_Explosion)
	// Drawn cards are dealt one after the other.
	draw := Presentation_Cue{kind = .Card_Drawn, started = true, event = {kind = .Card_Drawn}}
	for _ in 0..<3 { lab_cue_sounds(&renderer, &s, &draw, 2, &impacts) }
	deals := 0
	for sound in s.queue[:s.count] { if sound.sfx == .Ui_Card_Draw { deals += 1 } }
	testing.expect_value(t, deals, 3)
	testing.expect(t, s.queue[s.count-1].at > s.queue[s.count-2].at)
}
