package application

import "core:testing"
import campaign "../campaign"
import game "../game"
import run "../run"

@(test)
test_archive_preview_is_isolated_from_campaign :: proc(t: ^testing.T) {
	progress: campaign.Campaign
	campaign.initialize(&progress)
	defer campaign.destroy(&progress)
	campaign.depot_credit(&progress, 49)
	campaign.discover(&progress, .Storm_Crown)
	revision := progress.revision
	rs, ready := hub_card_preview_prepare(.Storm_Crown)
	if !testing.expect(t, ready) { return }
	defer run.roguelike_destroy(rs)
	testing.expect(t, rs.effect_window.open && rs.effect_window.film_ready)
	testing.expect_value(t, rs.effect_window.card.definition_id, game.Card_Id.Storm_Crown)
	testing.expect(t, !rs.options.persist_profile)
	// A film can change every practice resource without touching extracted loot.
	rs.run_state.player.gold = 99999
	run.step_effect_window_in_run(rs, {focused = true}, 0.1)
	testing.expect_value(t, progress.revision, revision)
	testing.expect_value(t, campaign.depot_credits(&progress), i64(49))
	testing.expect(t, progress.discovered[game.Card_Id.Storm_Crown])
}

@(test)
test_archive_preview_rejects_invalid_or_undiscovered_card :: proc(t: ^testing.T) {
	progress: campaign.Campaign
	campaign.initialize(&progress)
	defer campaign.destroy(&progress)
	testing.expect(t, !hub_open_archive_preview(&progress, .Storm_Crown, nil))
	testing.expect(t, !hub_open_archive_preview(&progress, .Count, nil))
	rs, ready := hub_card_preview_prepare(.Count)
	testing.expect(t, !ready && rs == nil)
}
