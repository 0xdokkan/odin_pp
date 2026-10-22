package campaignui

import "core:testing"
import campaign "../campaign"
import game "../game"

@(test)
test_drag_rotation_and_depot_transfer :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	item := campaign.make_item(.Weapon, 1, i32(game.Weapon_Id.Storm_Pike))
	campaign.grid_place(&c.backpack.grid, item, 0, 0)
	testing.expect(t, relocate(&c, {.Backpack, 0, 0}, {source = .Backpack, x = 7, y = 2}, 1, false, false))
	testing.expect_value(t, c.backpack.grid.entries[0].item.rotation, u8(1))
	testing.expect(t, relocate(&c, {.Backpack, 0, 0}, {source = .Depot, page = 0, x = 10, y = 4}, 1, false, true))
	testing.expect_value(t, c.backpack.grid.count, 0)
	testing.expect_value(t, c.depot[0].count, 1)
	testing.expect(t, !relocate(&c, {.Depot, 0, 0}, {source = .Backpack, x = 0, y = 0}, 0, false, false))
	testing.expect(t, relocate(&c, {.Depot, 0, 0}, {source = .Weapon}, 0, false, true))
	testing.expect_value(t, c.backpack.weapon.kind, campaign.Item_Kind.Weapon)
	testing.expect_value(t, c.depot[0].count, 0)
}

@(test)
test_failed_active_swap_restores_both_items :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	c.backpack.grid = campaign.make_grid(1, 1)
	campaign.grid_add(&c.backpack.grid, campaign.make_item(.Relic, 1, i32(game.Relic_Id.Iron_Knuckle)))
	c.backpack.relics[0] = campaign.make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil))
	before := c.backpack
	testing.expect(t, !relocate(&c, {.Backpack, 0, 0}, {source = .Relic, index = 0}, 0, false, false))
	testing.expect_value(t, c.backpack, before)
	testing.expect(t, !relocate(&c, {.Relic, 0, 0}, {source = .Pending}, 0, true, false))
	testing.expect_value(t, c.backpack, before)
}

@(test)
test_stack_merge_and_invalid_target_preserve_items :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	campaign.grid_place(&c.backpack.grid, campaign.make_item(.Healing, 2), 0, 0)
	campaign.grid_place(&c.backpack.grid, campaign.make_item(.Healing, 3), 1, 0)
	testing.expect(t, relocate(&c, {.Backpack, 1, 0}, {source = .Backpack, x = 0, y = 0}, 0, true, false))
	testing.expect_value(t, c.backpack.grid.count, 1)
	testing.expect_value(t, c.backpack.grid.entries[0].item.quantity, i32(5))
	before := c.backpack
	testing.expect(t, !relocate(&c, {.Backpack, 0, 0}, {source = .Backpack, x = 8, y = 0}, 0, false, false))
	testing.expect_value(t, c.backpack, before)
}

@(test)
test_closing_pending_requires_explicit_confirmation :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	c.backpack.pending[0] = campaign.make_item(.Energy); c.backpack.pending_count = 1
	state: State
	first := request_close(&c, &state, false, false)
	testing.expect(t, !first.closed && state.close_warning)
	testing.expect_value(t, c.backpack.pending_count, 1)
	confirmed := request_close(&c, &state, true, false)
	testing.expect(t, confirmed.closed); testing.expect_value(t, confirmed.drop_count, 1)
	testing.expect_value(t, confirmed.drops[0].kind, campaign.Item_Kind.Energy)
	testing.expect_value(t, c.backpack.pending_count, 0)
}

@(test)
test_hub_closing_safely_returns_pending_to_depot :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	c.backpack.pending[0] = campaign.make_item(.Energy); c.backpack.pending_count = 1
	state: State
	result := request_close(&c, &state, false, true)
	testing.expect(t, result.closed); testing.expect_value(t, result.drop_count, 0)
	testing.expect_value(t, c.depot[0].count, 1)
}

@(test)
test_suspended_run_cannot_extract_pending_or_equip_from_hub :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	campaign.begin_run(&c, .Cyber, 1)
	c.backpack.pending[0] = campaign.make_item(.Energy); c.backpack.pending_count = 1
	campaign.grid_add(&c.backpack.grid, campaign.make_item(.Weapon, 1, i32(game.Weapon_Id.Iron_Cleaver)))
	state: State
	testing.expect(t, !relocate(&c, {.Backpack, 0, 0}, {source = .Weapon}, 0, false, true))
	result := request_close(&c, &state, false, true)
	testing.expect(t, result.closed && !result.changed)
	testing.expect_value(t, c.backpack.pending_count, 1)
	testing.expect_value(t, c.depot[0].count, 0)
	testing.expect_value(t, c.backpack.weapon.kind, campaign.Item_Kind.None)
}

@(test)
test_full_health_does_not_waste_consumable :: proc(t: ^testing.T) {
	c: campaign.Campaign; campaign.initialize(&c); defer campaign.destroy(&c)
	campaign.begin_run(&c, .Cyber, 1)
	campaign.grid_add(&c.backpack.grid, campaign.make_item(.Healing, 2))
	player, ok := game.create_player({max_health = 30, attack = 3, defense = 0})
	testing.expect(t, ok)
	state := State{selected = {.Backpack, 0, 0}}
	full := use_selected(&c, &player, &state, true)
	testing.expect(t, !full.changed); testing.expect_value(t, c.backpack.grid.entries[0].item.quantity, i32(2))
	player.health = 10
	used := use_selected(&c, &player, &state, true)
	testing.expect(t, used.changed); testing.expect_value(t, used.action_seconds, f32(1))
	testing.expect_value(t, player.health, i32(22)); testing.expect_value(t, c.backpack.grid.entries[0].item.quantity, i32(1))
}

@(test)
test_grid_mapping_uses_exclusive_outer_edge :: proc(t: ^testing.T) {
	_, _, inside := cell_at({20, 30, 160, 100}, 20, {180, 35})
	testing.expect(t, !inside)
	x, y, valid := cell_at({20, 30, 160, 100}, 20, {179, 129})
	testing.expect(t, valid); testing.expect_value(t, x, 7); testing.expect_value(t, y, 4)
}

@(test)
test_inventory_layout_reserves_footer_at_native_canvas_size :: proc(t: ^testing.T) {
	for width in 8..=12 {
		layout := make_layout({0, 0, 960, 540}, width, true)
		footer := layout.window.y+layout.window.height-54
		testing.expect(t, layout.pending[0].y+layout.pending[0].height < footer)
		testing.expect(t, layout.detail.y+62+34 < footer)
		testing.expect(t, layout.bag_grid.x+layout.bag_grid.width < layout.depot_grid.x)
		testing.expect(t, layout.depot_grid.x+layout.depot_grid.width <= layout.window.x+layout.window.width-24)
	}
}
