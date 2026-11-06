package run

import "core:testing"
import "core:time"
import advisor "../advisor"
import campaign "../campaign"
import campaignui "../campaignui"
import game "../game"
import level "../level"

@(test)
test_expedition_consumable_releases_held_advice_but_input_boundaries_do_not :: proc(t: ^testing.T) {
	// The existing real game-room fixture, with expedition combat rules. No
	// window, map generation, alternative simulation or fabricated advice.
	e := new(Expedition_Session)
	defer free(e)
	e.rs = new(Roguelike_Session)
	defer free(e.rs)
	e.progress = new(campaign.Campaign)
	defer free(e.progress)
	campaign.initialize(e.progress)
	defer campaign.destroy(e.progress)
	e.site = -1
	rs := e.rs
	defer level.destroy(&rs.level_data)
	player, created := game.create_player(DEMO_PLAYER_STATS)
	if !testing.expect(t, created) { return }
	rs.run_state.player = player
	room, built := create_mechanics_lab_room(&rs.level_data, &rs.run_state.player, game.EXPEDITION_TACTICAL_CONFIG, .IA)
	if !testing.expect(t, built) { return }
	rs.room = room
	defer game.destroy_room(&rs.room)
	// Release and join the worker before freeing the source room/session.
	defer advisor_pilot_release()
	previous_context := advisor_game_context
	defer advisor_set_context(previous_context)
	player_at := rs.room.player
	player_at.health = 7
	player_at.tactical.ia_remaining = 999
	testing.expect(t, campaign.grid_add(&e.progress.backpack.grid, campaign.make_item(.Healing, 2)))
	advisor_set_context(advisor_context_expedition(&e.world, &e.progress.backpack, &rs.room))
	started := time.tick_now()
	for !advisor_current_advice().valid && time.duration_seconds(time.tick_since(started)) < 10 {
		drive_advisor(&rs.room, &rs.iso_renderer, 0)
		time.sleep(time.Millisecond)
	}
	held := advisor_current_advice()
	if !testing.expect(t, held.valid) { return }
	advisor_pilot_hold(true)
	testing.expect(t, advisor.advice_possible(&rs.room, held, player_at.position))
	before := player_at^
	root := advisor.discrete_fingerprint(&rs.room)
	generation := advisor_pilot_generation()

	// Input ownership may change while the same decision remains valid.
	expedition_set_inventory_open(e, true)
	expedition_set_inventory_open(e, false)
	expedition_set_map_open(e, true)
	expedition_set_map_open(e, false)
	expedition_toggle_pause(e)
	expedition_toggle_pause(e)
	roguelike_suspend_input(rs)
	testing.expect_value(t, player_at^, before)
	testing.expect_value(t, advisor_current_advice(), held)
	// A rejected inventory use owns no game time and is not a player action.
	e.inventory.selected = {.Backpack, 0, 0}
	rejected := campaignui.use_selected(e.progress, player_at, &e.inventory, true, false)
	testing.expect(t, !rejected.changed && rejected.action_seconds == 0)
	expedition_finish_inventory_action(e, rejected.action_seconds)
	drive_advisor(&rs.room, &rs.iso_renderer, 0)
	testing.expect_value(t, advisor_current_advice(), held)
	testing.expect_value(t, advisor_pilot_generation(), generation)
	testing.expect_value(t, advisor.discrete_fingerprint(&rs.room), root)

	// Consume through the same inventory function used by its button; healing
	// alone leaves the previous move executable, so only the action boundary
	// may release it. A fresh root must not keep showing the old recommendation.
	used := campaignui.use_selected(e.progress, player_at, &e.inventory, true, true)
	testing.expect(t, used.changed && used.action_seconds == 1 && player_at.health == 19)
	testing.expect_value(t, e.progress.backpack.grid.entries[0].item.quantity, i32(1))
	testing.expect(t, advisor.advice_possible(&rs.room, held, player_at.position))
	expedition_finish_inventory_action(e, used.action_seconds)
	advisor_set_context(advisor_context_expedition(&e.world, &e.progress.backpack, &rs.room))
	drive_advisor(&rs.room, &rs.iso_renderer, 0)
	after := advisor_current_advice()
	testing.expect(t, !after.valid || after.root != held.root,
		"the consumed item left the previous recommendation held")
	testing.expect(t, advisor_pilot_generation() > generation)
	testing.expect(t, advisor.discrete_fingerprint(&rs.room) != root)
	// Re-enable the worker and verify that the next usable advice describes
	// the actual healed room, not merely that the old marker disappeared.
	advisor_pilot_hold(false)
	new_root := advisor.discrete_fingerprint(&rs.room)
	started = time.tick_now()
	for time.duration_seconds(time.tick_since(started)) < 10 {
		drive_advisor(&rs.room, &rs.iso_renderer, 0)
		after = advisor_current_advice()
		if after.valid && after.root == new_root { break }
		time.sleep(time.Millisecond)
	}
	testing.expect(t, after.valid && after.root == new_root)
}
