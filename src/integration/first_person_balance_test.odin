package integration

import "core:log"
import "core:math"
import "core:testing"
import run_session "../run"
import game "../game"
import level "../level"
import render "../render"

// THE FOUR WEAPONS SIDE BY SIDE (docs/piano-prima-persona.md, Fase 8, passo 1;
// the user's choice: a fixed scene for each, played by a bot, then the user's
// own try). Each weapon a minute in the first person arena, the same foes free
// and arriving (the same sandbox seed), its view taken up again as it ends,
// played as a fair player would with the controller's own buttons:
// - the AK: the view on the nearest foe, the trigger held;
// - the fists: the view on the nearest foe, W held up to it, a punch every
//   third of a second (jab, cross, a hook every third);
// - the sword: Q or E toward the nearest foe, a step up to it, the blade swept
//   back and forth across it with the button held, the guard up as a blow on
//   him is due;
// - the bow: the view on the nearest foe, drawn a second and let go; and
//   spammed (2026-10-29), a click every other frame: quick shots only.
// It counts the damage dealt (every foe's health lost, a fallen one's last)
// and taken, a second of the view; the numbers go to the plan's Esito.

@(private = "file")
BALANCE_TOUGH :: i32(9999)

@(private = "file")
Balance_Result :: struct {
	dealt, taken: i32,
	seconds: f32,
}

@(private = "file")
balance_run :: proc(t: ^testing.T, weapon: game.First_Person_Weapon, spam := false) -> (result: Balance_Result) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	player.stats.max_health, player.health = 999, 999
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(21)
	// Each foe's health as last seen, to count what it lost (and its last when it falls).
	seen: [64]struct{id: u32, health: i32}
	seen_count := 0
	for frame in 0..<60*60 {
		if !game.tactical_first_person_active(&room) { _ = game.tactical_begin_first_person(&room, 12, weapon) }
		view := &renderer.tactical.first_person
		view.engaged, view.amount, view.pitch = true, 1, 0
		p := room.player.position
		nearest: ^game.Enemy
		best := max(int)
		for &foe in room.enemies {
			if game.enemy_is_out_of_play(&room, foe.id) { continue }
			d := (foe.position.x-p.x)*(foe.position.x-p.x)+(foe.position.y-p.y)*(foe.position.y-p.y)
			if d < best { best, nearest = d, &foe }
		}
		input := run_session.Tactical_Controller_Input{focused = true}
		if nearest != nil {
			dx, dy := f32(nearest.position.x-p.x), f32(nearest.position.y-p.y)
			yaw := math.atan2(dy, dx)
			switch weapon {
			case .AK:
				// Let go a frame now and then: a press held from before the view took the mouse fires nothing.
				view.yaw, input.fire = yaw, frame%30 != 0
			case .Fists:
				view.yaw = yaw
				input.walk[0] = best > 1
				input.fire, input.fire_right = frame%40 == 0, frame%40 == 20
				input.shift = frame%60 == 0
			case .Sword:
				s := &room.first_person.sword
				view.yaw = game.first_person_yaw(s.facing)
				// The grid way toward the foe, turned to with Q or E.
				way := game.Move_Direction.East if abs(dx) >= abs(dy) && dx > 0 else (game.Move_Direction.West if abs(dx) >= abs(dy) else
					(game.Move_Direction.South if dy > 0 else game.Move_Direction.North))
				if s.facing != way && frame%12 == 0 {
					right := game.Move_Direction((int(s.facing)+1)%4)
					if right == way { input.diagonals[1] = true } else { input.diagonals[0] = true }
				}
				input.look = {(40 if (frame/24)%2 == 0 else -40), 0}
				input.fire = frame%30 != 0
				// The guard as a blow on him is due.
				left := game.tactical_enemy_seconds(&room, nearest)
				_, _, _, coming := game.sword_coming_blow(&room, nearest)
				if coming && left < game.SWORD_PERFECT_PARRY { input.fire, input.fire_right = false, true }
				if s.facing == way && best > 1 && frame%20 == 0 && !game.tactical_player_busy(&room) && room.qte.kind == .None {
					_ = run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Combat, direction = way})
				}
			case .Bow:
				view.yaw = yaw
				input.fire_right = frame%2 == 0 if spam else frame%70 < 62
			}
		}
		_, _ = game.sandbox_tick(&room, &sandbox, 1.0/60)
		_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, input)
		if game.tactical_first_person_active(&room) { result.seconds += 1.0/60 }
		// What the foes lost this frame; the fallen, their last health.
		for k := 0; k < seen_count; k += 1 {
			index, alive := game.enemy_index_by_id(&room, seen[k].id)
			now := room.enemies[index].health if alive else 0
			if now < seen[k].health { result.dealt += seen[k].health-now }
			seen[k].health = now
		}
		// Each foe made tough as it comes, so that no weapon runs out of them (the
		// first bench, 2026-10-29, ran out at about 210: the AK, the fists and
		// the spammed bow all dealt what the arena had).
		for &foe in room.enemies {
			known := false
			for k in 0..<seen_count { known = known || seen[k].id == foe.id }
			if !known && seen_count < len(seen) {
				foe.health = BALANCE_TOUGH
				seen[seen_count] = {id = foe.id, health = foe.health}
				seen_count += 1
			}
		}
		if room.phase != .Combat { break }
	}
	result.taken = 999-player.health
	return
}

@(test)
test_first_person_weapons_side_by_side :: proc(t: ^testing.T) {
	names := [game.First_Person_Weapon]string{.AK = "AK", .Fists = "pugni", .Sword = "spada", .Bow = "arco"}
	for weapon in game.First_Person_Weapon {
		r := balance_run(t, weapon)
		dps := f32(r.dealt)/max(r.seconds, 1)
		taken := f32(r.taken)/max(r.seconds, 1)
		log.infof("BALANCE %s: %d dealt, %d taken in %.1f s of the view: %.2f a second dealt, %.2f taken",
			names[weapon], r.dealt, r.taken, r.seconds, dps, taken)
		testing.expectf(t, r.dealt > 0, "%s dealt nothing in a minute", names[weapon])
	}
	r := balance_run(t, .Bow, spam = true)
	log.infof("BALANCE arco a raffica: %d dealt, %d taken in %.1f s of the view: %.2f a second dealt, %.2f taken",
		r.dealt, r.taken, r.seconds, f32(r.dealt)/max(r.seconds, 1), f32(r.taken)/max(r.seconds, 1))
	testing.expect(t, r.dealt > 0, "the spammed bow dealt nothing in a minute")
}
