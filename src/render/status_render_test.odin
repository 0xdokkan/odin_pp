package render

import "core:testing"
import rl "vendor:raylib"
import audio "../engine/audio"
import game "../game"

// Bruciatura and Rallentamento have their Italian names and colours; a stack
// status's chip shows its stacks, never seconds.
@(test)
test_status_labels_and_chips_show_stacks_without_seconds :: proc(t: ^testing.T) {
	burn, ember := tactical_status_label(.Burn, false)
	slow, frost := tactical_status_label(.Slow, false)
	testing.expect_value(t, burn, "BRUCIATURA")
	testing.expect_value(t, slow, "RALLENTAMENTO")
	testing.expect(t, ember == HUD_EMBER && frost == HUD_FROST)
	short, _ := tactical_status_label(.Slow, true)
	testing.expect_value(t, short, "RAL")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Burn, potency = 2}, false)), "BRUCIATURA 2")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Poison, potency = 3}, true)), "VEL 3")
	testing.expect_value(t, string(tactical_status_chip_text({kind = .Shield, potency = 2, remaining_pulses = 3}, false)), "SCUDO 2 / 3s")
	for kind in game.Status_Kind {
		label, _ := tactical_status_label(kind, false)
		testing.expectf(t, len(label) > 0, "%v has no name", kind)
	}
}

// Every status but the view's own has a lab sound, each one its own.
@(test)
test_lab_sounds_cover_every_status :: proc(t: ^testing.T) {
	seen: [audio.Lab_Sfx]bool
	for kind in game.Status_Kind {
		sfx, ok := lab_status_sfx(kind)
		testing.expectf(t, ok == (kind != .Survey), "%v", kind)
		if !ok { continue }
		testing.expectf(t, !seen[sfx] && !audio.LAB_SFX_LOOP[sfx], "%v shares or loops %v", kind, sfx)
		seen[sfx] = true
	}
	burn, _ := lab_status_sfx(.Burn)
	slow, _ := lab_status_sfx(.Slow)
	testing.expect_value(t, burn, audio.Lab_Sfx.Ui_Status_Burn)
	testing.expect_value(t, slow, audio.Lab_Sfx.Ui_Status_Slow)
}

// A stack arrives with no duration; every other status still needs one.
@(test)
test_presentation_applies_stacks_without_a_duration :: proc(t: ^testing.T) {
	statuses: game.Status_Set
	testing.expect(t, apply_presentation_status(&statuses, .Poison, 2, 0))
	testing.expect(t, apply_presentation_status(&statuses, .Burn, 3, 0))
	testing.expect(t, apply_presentation_status(&statuses, .Poison, 5, 0))
	testing.expect(t, !apply_presentation_status(&statuses, .Shield, 2, 0))
	testing.expect(t, apply_presentation_status(&statuses, .Shield, 2, 1))
	testing.expect_value(t, statuses.count, 3)
	index, found := game.status_index(&statuses, .Poison)
	testing.expect(t, found && statuses.items[index].potency == 5)
}

// The player's poison wears a stack at his own action's bite: the snapshot
// shows the final stacks at the bite, and a last stack that ends goes with
// its expiry.
@(test)
test_presentation_poison_wears_at_its_bite :: proc(t: ^testing.T) {
	for last in ([2]bool{false, true}) {
		player := game.Player{stats = {max_health = 10}, health = 10}
		player.statuses.items[0] = {kind = .Poison, potency = 1 if last else 3}
		player.statuses.count = 1
		room := make_presentation_timeline_test_room(&player, nil, nil)
		before := capture_room_presentation(&room)
		events: game.Event_Log
		game.record_event(&events, {kind = .Damaged, source = game.SYSTEM_ENTITY, target = game.PLAYER_ENTITY,
			amount = player.statuses.items[0].potency, has_status_cause = true, status_cause = .Poison})
		player.health -= player.statuses.items[0].potency
		if last {
			game.record_event(&events, {kind = .Status_Expired, source = game.SYSTEM_ENTITY, target = game.PLAYER_ENTITY,
				amount = 0, status = .Poison})
			player.statuses = {}
		} else {
			player.statuses.items[0].potency = 2
		}
		after := capture_room_presentation(&room)
		timeline: Presentation_Timeline
		testing.expect(t, begin_event_timeline(&timeline, before, &events, &after))
		// The bite's cue starts.
		testing.expect(t, !update_event_timeline(&timeline, 0.01))
		index, poisoned := game.status_index(&timeline.view.player.statuses, .Poison)
		testing.expect(t, poisoned)
		if poisoned { testing.expect_value(t, timeline.view.player.statuses.items[index].potency, i32(1) if last else i32(2)) }
		testing.expect_value(t, timeline.view.player.health, player.health)
		if last {
			testing.expect(t, update_event_timeline(&timeline, 5))
			_, poisoned = game.status_index(&timeline.view.player.statuses, .Poison)
			testing.expect(t, !poisoned)
		}
		testing.expect_value(t, timeline.update_failures, 0)
		game.destroy_room(&room)
	}
}

// Rallentamento's seconds are part of the ground threat's whole countdown.
@(test)
test_intent_timing_counts_the_slowed_seconds :: proc(t: ^testing.T) {
	player: game.Player

	room := game.Room{player = &player, phase = .Combat}
	enemy := game.Enemy{archetype = .Chaser, intent = {kind = .Move, slowed = 2}, tactical_cooldown = 3}
	left, total, progress := intent_timing(&room, &enemy)
	testing.expect_value(t, total, f32(5))
	testing.expect_value(t, left, f32(3))
	testing.expect(t, abs(progress-0.4) < 1e-5)
}

// The tags' lane keeps the round markers' square and the row under it.
@(test)
test_status_tags_lane_and_sizes :: proc(t: ^testing.T) {
	w, h := status_tag_size("2")
	heart_w, heart_h := living_heart_size("2")
	testing.expect(t, w == heart_w && h == heart_h && h == 14)
	testing.expect_value(t, status_tag_text({kind = .Burn, potency = 12}), "12")
	lane := tactical_status_lane({100, 100}, {})
	testing.expect_value(t, lane, rl.Rectangle{70, 82, 60, 36})
	lane = tactical_status_lane({100, 100}, {80, 115, 43, 14})
	testing.expect_value(t, lane, rl.Rectangle{70, 82, 60, 47})
	lane = tactical_status_lane({100, 100}, {60, 115, 90, 28})
	testing.expect_value(t, lane, rl.Rectangle{60, 82, 90, 61})
}
