// The inventory menu only consumes the host's captured input. Its result tells
// the world about time costs, dropped loot and card-preview requests.
package campaignui

import "core:fmt"
import rl "vendor:raylib"
import campaign "../campaign"
import game "../game"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

Panel :: enum { Inventory, Character, Archive }
Source :: enum { None, Backpack, Depot, Pending, Relic, Weapon }
Item_Ref :: struct { source: Source, index, page: int }
Destination :: struct { source: Source, index, page, x, y: int }
State :: struct {
	panel: Panel,
	selected: Item_Ref,
	dragging, drag_moved: bool,
	dragged: Item_Ref,
	drag_start: [2]f32,
	rotation: u8,
	page, card_page, selected_card: int,
	close_warning: bool,
	notice: string,
	notice_time: f32,
	last_frame: u64,
	frame_seen: bool,
}
Output :: struct {
	closed, changed: bool,
	drops: [campaign.PENDING_ITEMS]campaign.Item,
	drop_count: int,
	decoy: bool,
	action_seconds: f32,
	show_effect: bool,
	effect_card: game.Card_Id,
}
Layout :: struct {
	window, content, bag_grid, depot_grid, detail: ui.Rect,
	bag_cell, depot_cell: f32,
	relics: [3]ui.Rect,
	weapon: ui.Rect,
	pending: [3]ui.Rect,
	depot_header: ui.Rect,
}

item_at_ref :: proc(c: ^campaign.Campaign, ref: Item_Ref) -> (campaign.Item, bool) {
	if c == nil { return {}, false }
	switch ref.source {
	case .None:
	case .Backpack:
		if ref.index >= 0 && ref.index < c.backpack.grid.count { return c.backpack.grid.entries[ref.index].item, true }
	case .Depot:
		if ref.page >= 0 && ref.page < len(c.depot) && ref.index >= 0 && ref.index < c.depot[ref.page].count { return c.depot[ref.page].entries[ref.index].item, true }
	case .Pending:
		if ref.index >= 0 && ref.index < c.backpack.pending_count { return c.backpack.pending[ref.index], true }
	case .Relic:
		if ref.index >= 0 && ref.index < 3 && c.backpack.relics[ref.index].kind != .None { return c.backpack.relics[ref.index], true }
	case .Weapon:
		if c.backpack.weapon.kind != .None { return c.backpack.weapon, true }
	}
	return {}, false
}
@(private)
remove_ref :: proc(c: ^campaign.Campaign, ref: Item_Ref) {
	switch ref.source {
	case .None:
	case .Backpack: campaign.grid_remove(&c.backpack.grid, ref.index)
	case .Depot: campaign.grid_remove(&c.depot[ref.page], ref.index)
	case .Pending: campaign.pending_remove(&c.backpack, ref.index)
	case .Relic: c.backpack.relics[ref.index] = {}
	case .Weapon: c.backpack.weapon = {}
	}
}
@(private)
place_or_merge :: proc(grid: ^campaign.Inventory_Grid, item: campaign.Item, x, y: int) -> bool {
	index := campaign.grid_item_at(grid, x, y)
	if index < 0 { return campaign.grid_place(grid, item, x, y) }
	target := &grid.entries[index].item
	if target.kind != item.kind || target.variant != item.variant || target.uses != item.uses ||
	   campaign.stack_limit(item.kind) <= 1 || target.quantity+item.quantity > campaign.stack_limit(item.kind) { return false }
	target.quantity += item.quantity
	return true
}

// Pure transaction shared by drag/drop and tests. Failed placements restore
// both inventories, including active slots; no held object can be orphaned.
relocate :: proc(c: ^campaign.Campaign, source: Item_Ref, target: Destination, rotation: u8,
	in_combat, in_hub: bool) -> bool {
	item, ok := item_at_ref(c, source)
	if !ok || rotation > 3 || target.source == .None { return false }
	if in_hub && c.run.active { return false }
	if (source.source == .Depot || target.source == .Depot) && !in_hub { return false }
	if in_combat && (source.source == .Relic || source.source == .Weapon || target.source == .Relic || target.source == .Weapon) { return false }
	if target.source == .Depot && (target.page < 0 || target.page >= len(c.depot)) { return false }
	if target.source == .Relic && (item.kind != .Relic || target.index < 0 || target.index >= 3) { return false }
	if target.source == .Weapon && item.kind != .Weapon { return false }
	if source.source == target.source && (source.source == .Relic || source.source == .Weapon) && source.index == target.index { return false }
	old_bag := c.backpack
	old_source_page, old_target_page: campaign.Inventory_Grid
	if source.source == .Depot { old_source_page = c.depot[source.page] }
	if target.source == .Depot { old_target_page = c.depot[target.page] }
	remove_ref(c, source)
	item.rotation = rotation
	placed := false
	displaced: campaign.Item
	switch target.source {
	case .None:
	case .Backpack: placed = place_or_merge(&c.backpack.grid, item, target.x, target.y)
	case .Depot: placed = place_or_merge(&c.depot[target.page], item, target.x, target.y)
	case .Pending:
		if c.backpack.pending_count < campaign.PENDING_ITEMS {
			c.backpack.pending[c.backpack.pending_count] = item; c.backpack.pending_count += 1; placed = true
		}
	case .Relic:
		duplicate := false
		for active, i in c.backpack.relics { if i != target.index && active.kind == .Relic && active.variant == item.variant { duplicate = true } }
		if !duplicate { displaced = c.backpack.relics[target.index]; c.backpack.relics[target.index] = item; placed = true }
	case .Weapon: displaced = c.backpack.weapon; c.backpack.weapon = item; placed = true
	}
	if placed && displaced.kind != .None {
		switch source.source {
		case .None: placed = false
		case .Backpack: placed = campaign.grid_add(&c.backpack.grid, displaced)
		case .Depot: placed = campaign.grid_add(&c.depot[source.page], displaced)
		case .Pending:
			placed = c.backpack.pending_count < campaign.PENDING_ITEMS
			if placed { c.backpack.pending[c.backpack.pending_count] = displaced; c.backpack.pending_count += 1 }
		case .Relic: c.backpack.relics[source.index] = displaced
		case .Weapon: c.backpack.weapon = displaced
		}
	}
	if !placed {
		c.backpack = old_bag
		if source.source == .Depot { c.depot[source.page] = old_source_page }
		if target.source == .Depot { c.depot[target.page] = old_target_page }
		return false
	}
	c.revision += 1
	return true
}

make_layout :: proc(canvas: ui.Rect, bag_width: int, in_hub: bool) -> (out: Layout) {
	out.window = ui.center(canvas, min(1232, canvas.width-40), min(740, canvas.height-32))
	out.content = ui.shrink(out.window, 24); out.content.y += 104; out.content.height -= 140
	left_width := out.content.width*0.48 if in_hub else out.content.width*0.64
	left := ui.Rect{out.content.x, out.content.y, left_width, out.content.height}
	out.bag_cell = min(54, (left.width-12)/f32(max(8, bag_width)))
	out.bag_cell = min(out.bag_cell, max(20, (left.height-182)/5))
	for i in 0..<3 { out.relics[i] = {left.x+f32(i)*72, left.y+22, 62, 48} }
	out.weapon = {left.x+left.width-82, left.y+22, 72, 48}
	out.bag_grid = {left.x, left.y+104, out.bag_cell*f32(bag_width), out.bag_cell*5}
	pending_y := out.bag_grid.y+out.bag_grid.height+26
	for i in 0..<3 { out.pending[i] = {left.x+f32(i)*88, pending_y, 78, 46} }
	right := ui.Rect{left.x+left.width+24, left.y, out.content.width-left.width-24, left.height}
	if in_hub {
		out.depot_header = {right.x, right.y, right.width, 32}
		out.depot_cell = min(right.width/12, max(20, (right.height-156)/8))
		out.depot_grid = {right.x, right.y+44, out.depot_cell*12, out.depot_cell*8}
		out.detail = {right.x, out.depot_grid.y+out.depot_grid.height+14, right.width, right.height-out.depot_grid.height-58}
	} else { out.detail = right }
	return
}
cell_at :: proc(rect: ui.Rect, cell: f32, position: [2]f32) -> (int, int, bool) {
	if cell <= 0 || !ui.contains(rect, position) { return 0, 0, false }
	return int((position.x-rect.x)/cell), int((position.y-rect.y)/cell), true
}
@(private)
ref_at :: proc(c: ^campaign.Campaign, layout: Layout, position: [2]f32, page: int, in_hub: bool) -> Item_Ref {
	if x, y, inside := cell_at(layout.bag_grid, layout.bag_cell, position); inside {
		index := campaign.grid_item_at(&c.backpack.grid, x, y)
		if index >= 0 { return {.Backpack, index, 0} }
	}
	if in_hub {
		if x, y, inside := cell_at(layout.depot_grid, layout.depot_cell, position); inside {
			index := campaign.grid_item_at(&c.depot[page], x, y)
			if index >= 0 { return {.Depot, index, page} }
		}
	}
	for rect, i in layout.relics { if ui.contains(rect, position) && c.backpack.relics[i].kind != .None { return {.Relic, i, 0} } }
	if ui.contains(layout.weapon, position) && c.backpack.weapon.kind != .None { return {.Weapon, 0, 0} }
	for rect, i in layout.pending { if ui.contains(rect, position) && i < c.backpack.pending_count { return {.Pending, i, 0} } }
	return {}
}
@(private)
target_at :: proc(layout: Layout, position: [2]f32, page: int, in_hub: bool) -> Destination {
	if x, y, inside := cell_at(layout.bag_grid, layout.bag_cell, position); inside { return {source = .Backpack, x = x, y = y} }
	if in_hub { if x, y, inside := cell_at(layout.depot_grid, layout.depot_cell, position); inside { return {source = .Depot, page = page, x = x, y = y} } }
	for rect, i in layout.relics { if ui.contains(rect, position) { return {source = .Relic, index = i} } }
	if ui.contains(layout.weapon, position) { return {source = .Weapon} }
	for rect in layout.pending { if ui.contains(rect, position) { return {source = .Pending} } }
	return {}
}

@(private)
item_color :: proc(item: campaign.Item) -> rl.Color {
	switch item.kind {
	case .None: return {62, 77, 94, 255}
	case .Healing: return {102, 218, 164, 255}
	case .Energy: return {79, 178, 255, 255}
	case .Temporary_Card: return {177, 134, 255, 255}
	case .Decoy: return {100, 220, 224, 255}
	case .Upgrade: return {241, 186, 107, 255}
	case .Weapon: return {238, 137, 117, 255}
	case .Relic: return {192, 144, 244, 255}
	case .Credits: return {238, 200, 107, 255}
	case .Memory: return {237, 160, 217, 255}
	case .Backpack: return {147, 205, 187, 255}
	}
	return rl.WHITE
}
@(private)
item_glyph :: proc(item: campaign.Item) -> string {
	switch item.kind {
	case .None: return "+"
	case .Healing: return "+"
	case .Energy: return "E"
	case .Temporary_Card: return "C"
	case .Decoy: return "~"
	case .Upgrade: return "UP"
	case .Weapon: return "W"
	case .Relic: return "R"
	case .Credits: return "$"
	case .Memory: return "M"
	case .Backpack: return "B"
	}
	return "?"
}
@(private)
draw_item :: proc(ctx: ^ui.Context, item: campaign.Item, origin: [2]f32, cell: f32, selected := false, alpha: f32 = 1) {
	shape := campaign.item_shape(item)
	color := item_color(item)
	for square in shape.cells[:shape.count] {
		r := ui.Rect{origin.x+f32(square.x)*cell+2, origin.y+f32(square.y)*cell+2, cell-4, cell-4}
		ui.fill(ctx, {r.x+2, r.y+3, r.width, r.height}, ui.with_alpha(rl.BLACK, 0.35*alpha))
		ui.fill(ctx, r, ui.with_alpha(ui.mix_color(color, {13, 22, 33, 255}, 0.68), alpha))
		ui.outline(ctx, r, ui.with_alpha(color, alpha), 2 if selected else 1)
		ui.fill(ctx, {r.x+3, r.y+3, r.width-6, 2}, ui.with_alpha(color, 0.5*alpha))
	}
	first := shape.cells[0]
	icon := ui.Rect{origin.x+f32(first.x)*cell, origin.y+f32(first.y)*cell, cell, cell}
	if item.quantity > 1 {
		// Small depot cells cannot fit a glyph and a two-digit quantity without
		// overlap. The item's tint/frame identify its family; selection explains it.
		ui.label(ctx, icon, fmt.tprintf("%d", item.quantity), .Small, ui.with_alpha(rl.WHITE, alpha), .Center)
	} else { ui.label(ctx, icon, item_glyph(item), .Small, ui.with_alpha(color, alpha), .Center) }
}
@(private)
draw_grid :: proc(ctx: ^ui.Context, grid: ^campaign.Inventory_Grid, rect: ui.Rect, cell: f32,
	state: ^State, source: Source, page: int) {
	ui.fill(ctx, {rect.x-4, rect.y-4, rect.width+8, rect.height+8}, {8, 17, 28, 245})
	for y in 0..<grid.height { for x in 0..<grid.width {
		r := ui.Rect{rect.x+f32(x)*cell+1, rect.y+f32(y)*cell+1, cell-2, cell-2}
		ui.fill(ctx, r, {17, 30, 44, 240}); ui.outline(ctx, r, {35, 53, 68, 255}, 1)
	} }
	for entry, i in grid.entries[:grid.count] {
		ref := Item_Ref{source, i, page}
		alpha: f32 = 0.28 if state.dragging && state.drag_moved && state.dragged == ref else 1
		draw_item(ctx, entry.item, {rect.x+f32(entry.x)*cell, rect.y+f32(entry.y)*cell}, cell, state.selected == ref, alpha)
	}
}
@(private)
draw_slot :: proc(ctx: ^ui.Context, rect: ui.Rect, item: campaign.Item, selected, locked: bool) {
	ui.fill(ctx, rect, {19, 28, 42, 255}, 0.08)
	ui.outline(ctx, rect, item_color(item) if item.kind != .None else rl.Color{65, 82, 99, 255}, 2 if selected else 1, 0.08)
	if item.kind != .None {
		shape := campaign.item_shape(item)
		cell := min((rect.width-12)/f32(shape.width), (rect.height-10)/f32(shape.height))
		cell = min(cell, 30)
		draw_item(ctx, item, {rect.x+(rect.width-cell*f32(shape.width))*0.5, rect.y+(rect.height-cell*f32(shape.height))*0.5}, cell)
	} else { ui.label(ctx, rect, "-", .Large, {81, 101, 119, 255}, .Center) }
	if locked { ui.fill(ctx, {rect.x, rect.y+rect.height-3, rect.width, 3}, {217, 105, 104, 255}) }
}

@(private)
notice :: proc(state: ^State, text: string) { state.notice = text; state.notice_time = 3.5 }

// Consume only after checking the effect can happen; full health, full energy,
// a full hand or a locked action never wastes the selected item.
use_selected :: proc(c: ^campaign.Campaign, player: ^game.Player, state: ^State, in_combat: bool, can_use := true) -> (out: Output) {
	item, valid := item_at_ref(c, state.selected)
	if !valid || state.selected.source != .Backpack || player == nil || !can_use { return }
	allowed := true
	#partial switch item.kind {
	case .Healing: allowed = player.health < player.stats.max_health
	case .Energy: allowed = in_combat && player.deck.energy < player.deck.rules.max_energy
	case .Temporary_Card: staged := player.deck; _, created := game.create_temporary_card(&staged, game.Card_Id(item.variant)); allowed = in_combat && created
	case .Decoy: allowed = !in_combat && c.run.active
	case .Upgrade: allowed = c.run.active
	case: allowed = false
	}
	if !allowed { notice(state, "Questo oggetto non puo essere usato adesso."); return }
	effect, ok := campaign.consume(&c.backpack, state.selected.index, in_combat)
	if !ok { return }
	player.health = min(player.stats.max_health, player.health+effect.heal)
	player.deck.energy = min(player.deck.rules.max_energy, player.deck.energy+effect.energy)
	if effect.has_card { game.create_temporary_card(&player.deck, effect.card) }
	c.run.points += effect.upgrade_points; c.revision += 1
	state.selected = {}; out.changed = true; out.decoy = effect.decoy; out.action_seconds = effect.action_seconds
	notice(state, "Oggetto utilizzato.")
	return
}

request_close :: proc(c: ^campaign.Campaign, state: ^State, confirmed, in_hub: bool) -> (out: Output) {
	if state.dragging { state.dragging = false; return }
	if in_hub && c.run.active {
		state.close_warning = false; state.frame_seen = false; out.closed = true
		return
	}
	if c.backpack.pending_count > 0 && !in_hub && !confirmed { state.close_warning = true; return }
	had_pending := c.backpack.pending_count > 0
	if in_hub {
		for item in c.backpack.pending[:c.backpack.pending_count] { campaign.depot_add(c, item) }
		c.backpack.pending = {}; c.backpack.pending_count = 0
	} else { out.drops, out.drop_count = campaign.drop_pending(&c.backpack, confirmed) }
	if had_pending { c.revision += 1 }
	state.close_warning = false; state.frame_seen = false; out.closed = true; out.changed = had_pending
	return
}

update_inventory :: proc(c: ^campaign.Campaign, player: ^game.Player, state: ^State, frame: ^host.Frame,
	in_combat, in_hub: bool, can_use := true) -> (out: Output) {
	if c == nil || state == nil || frame == nil || frame.ui == nil || !frame.visible { return }
	ctx := frame.ui
	opening_frame := !state.frame_seen || frame.index != state.last_frame+1
	state.frame_seen = true; state.last_frame = frame.index
	state.notice_time = max(0, state.notice_time-frame.dt)
	state.page = clamp(state.page, 0, max(0, len(c.depot)-1))
	layout := make_layout(frame.canvas, c.backpack.grid.width, in_hub)
	ui.dim(ctx, frame.canvas, 0.82)
	ui.fill(ctx, layout.window, {12, 22, 35, 250}, 0.025)
	ui.outline(ctx, layout.window, {62, 125, 155, 255}, 1, 0.025)
	ui.fill(ctx, {layout.window.x, layout.window.y, layout.window.width, 3}, {88, 211, 224, 255})
	ui.text_at(ctx, {layout.window.x+24, layout.window.y+18}, "MEMORIA / EQUIPAGGIAMENTO", .Large, {227, 236, 235, 255})
	ui.text_at(ctx, {layout.window.x+24, layout.window.y+52},
		"Il tempo continua. Ogni consumabile richiede un'azione." if in_combat && state.panel == .Inventory else
		("Consultazione in pausa. I potenziamenti richiedono la fine dello scontro." if in_combat else
		("Prepara cio che vuoi rischiare nella prossima spedizione." if in_hub else "Tutto cio che porti e in gioco finche non estrai.")), .Small, {139, 172, 191, 255})
	blocked := state.close_warning
	previous := ui.set_interactive(ctx, frame.focused && !blocked)
	defer ui.set_interactive(ctx, previous)
	tab_names := [3]string{"ZAINO", "PERSONAGGIO", "ARCHIVIO"}
	for name, index in tab_names {
		if ui.button(ctx, {layout.window.x+24+f32(index)*162, layout.window.y+84, 152, 32}, name, true, state.panel == Panel(index), .Small) {
			state.panel = Panel(index); state.selected = {}; state.dragging = false; state.card_page = 0
		}
	}
	close_clicked := ui.button(ctx, {layout.window.x+layout.window.width-154, layout.window.y+24, 130, 34}, "CHIUDI [Z]", true, false, .Small)
	if frame.focused && !blocked && (close_clicked || input.key_pressed(frame.devices, .ESCAPE) || (!opening_frame && input.key_pressed(frame.devices, .Z))) {
		out = request_close(c, state, false, in_hub)
		if out.closed { return }
	}
	if state.panel == .Inventory {
		inventory_panel(c, player, state, frame, layout, in_combat, in_hub, can_use, &out)
	} else { cards_panel(c, player, state, frame, layout.content, in_combat, &out) }
	if out.changed && player != nil { campaign.apply_equipment(&c.backpack, player) }
	if state.notice_time > 0 {
		ui.fill(ctx, {layout.window.x+24, layout.window.y+layout.window.height-32, layout.window.width-48, 24}, {24, 48, 63, 255})
		ui.label(ctx, {layout.window.x+32, layout.window.y+layout.window.height-32, layout.window.width-64, 24}, state.notice, .Small, {185, 231, 230, 255})
	}
	if state.close_warning {
		ui.set_interactive(ctx, frame.focused)
		ui.dim(ctx, frame.canvas, 0.65)
		modal := ui.center(frame.canvas, 520, 214)
		inner := ui.panel(ctx, modal, "Oggetti ancora sospesi")
		ui.paragraph(ctx, {inner.x, inner.y, inner.width, 70}, "Gli oggetti sospesi torneranno a terra, dove si trova il robot. Puoi ancora sistemarli prima di chiudere.", .Body)
		if ui.button(ctx, {inner.x, modal.y+modal.height-56, 218, 36}, "CONTINUA A SISTEMARE", true, true, .Small) { state.close_warning = false }
		if ui.button(ctx, {inner.x+232, modal.y+modal.height-56, 218, 36}, "LASCIA A TERRA E CHIUDI", true, false, .Small) { out = request_close(c, state, true, in_hub) }
	}
	return
}
