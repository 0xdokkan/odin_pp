package application

import "core:testing"
import "core:os"
import campaign "../campaign"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

@(test)
test_storage_tabs_cannot_activate_covered_hub_navigation :: proc(t: ^testing.T) {
	h := new(Campaign_Hub)
	defer free(h)
	campaign.initialize(&h.progress); defer campaign.destroy(&h.progress)
	h.page = .Storage; h.slot = -1; h.delete_slot = -1
	theme := ui.default_theme(); ctx := ui.create(&theme); defer ui.destroy(ctx)
	devices: input.Device_Snapshot
	commands: host.Commands
	frame := host.Frame{canvas = {0, 0, 960, 540}, ui = ctx, devices = &devices,
		commands = &commands, focused = true, window_focused = true, visible = true}
	// The first inventory tab overlaps the covered Galassia navigation button.
	ui.begin(ctx, {position = {80, 110}, inside = true, pressed = true, down = true}, {}, 0)
	hub_update(h, &frame); ui.end(ctx)
	frame.index += 1
	ui.begin(ctx, {position = {80, 110}, inside = true, released = true}, {}, 0)
	hub_update(h, &frame); ui.end(ctx)
	testing.expect_value(t, h.page, Hub_Page.Storage)
	testing.expect_value(t, commands.count, 0)
	for command in ctx.commands[:ctx.command_count] {
		testing.expect(t, command.text != "Slot / Salva")
	}
}

@(test)
test_slot_delete_modal_blocks_underlying_menu_button :: proc(t: ^testing.T) {
	h := new(Campaign_Hub)
	defer free(h)
	h.page = .Slots; h.slot = -1; h.delete_slot = 0; h.delete_stage = 1
	for &status in h.slot_status { status = .Unreadable }
	theme := ui.default_theme(); ctx := ui.create(&theme); defer ui.destroy(ctx)
	commands: host.Commands
	frame := host.Frame{canvas = {0, 0, 960, 540}, ui = ctx, commands = &commands, focused = true, visible = true}
	ui.begin(ctx, {position = {90, 482}, inside = true, pressed = true, down = true}, {}, 0)
	hub_slots(h, &frame); ui.end(ctx)
	ui.begin(ctx, {position = {90, 482}, inside = true, released = true}, {}, 0)
	hub_slots(h, &frame); ui.end(ctx)
	testing.expect_value(t, commands.count, 0)
	testing.expect_value(t, h.delete_slot, 0)
	testing.expect_value(t, h.delete_stage, 1)
}

@(test)
test_window_focus_loss_flushes_latest_hub_state :: proc(t: ^testing.T) {
	path := "/private/tmp/odin-pp-hub-focus-save.json"; defer os.remove(path)
	h := new(Campaign_Hub)
	defer free(h)
	campaign.initialize(&h.progress); defer campaign.destroy(&h.progress)
	h.slot = 0; h.path = path; h.page = .Galaxy; h.window_active = true
	campaign.depot_credit(&h.progress, 12)
	testing.expect(t, hub_save(h))
	campaign.depot_credit(&h.progress, 1)
	// Host marks focused=false as well as window_focused=false on OS blur.
	frame := host.Frame{focused = false, window_focused = false}
	hub_update(h, &frame)
	testing.expect(t, !campaign.save_queue_busy(&h.save_queue) && !h.save_failed)
	loaded: campaign.Campaign
	snapshot := new(Campaign_Save); defer free(snapshot)
	status := campaign.load_slot_into(path, &loaded, snapshot)
	defer campaign.destroy(&loaded)
	testing.expect_value(t, status, campaign.Load_Status.Loaded)
	testing.expect_value(t, campaign.depot_credits(&loaded), i64(13))
	hub_update(h, &frame)
	testing.expect(t, !campaign.save_queue_busy(&h.save_queue))
}

@(test)
test_missing_slot_directory_is_not_a_successful_save :: proc(t: ^testing.T) {
	h := new(Campaign_Hub); defer free(h)
	campaign.initialize(&h.progress); defer campaign.destroy(&h.progress)
	h.slot = 0
	testing.expect(t, !hub_save(h) && h.save_failed)
	testing.expect(t, !hub_flush(h) && h.save_failed)
	testing.expect(t, !hub_wallet_commit(h) && h.save_failed)
	h.smoke = true
	testing.expect(t, hub_save(h))
}
