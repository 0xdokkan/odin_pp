package campaignui

import "core:fmt"
import campaign "../campaign"
import game "../game"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

@(private)
inventory_panel :: proc(c: ^campaign.Campaign, player: ^game.Player, state: ^State, frame: ^host.Frame,
	layout: Layout, in_combat, in_hub, can_use: bool, out: ^Output) {
	ctx := frame.ui
	interactive := frame.focused && !state.close_warning && !ctx.noninteractive
	if interactive && input.mouse_pressed(frame.devices, .LEFT) && frame.mouse_inside {
		ref := ref_at(c, layout, frame.mouse, state.page, in_hub)
		if item, ok := item_at_ref(c, ref); ok {
			state.selected = ref; state.dragged = ref; state.dragging = true; state.drag_moved = false
			state.drag_start = frame.mouse; state.rotation = item.rotation
		}
	}
	if interactive && state.dragging {
		delta := frame.mouse-state.drag_start
		if delta.x*delta.x+delta.y*delta.y > 36 { state.drag_moved = true }
		if (frame.devices != nil && frame.devices.wheel != 0) || input.key_pressed(frame.devices, .R) {
			step := 1 if frame.devices == nil || frame.devices.wheel >= 0 else 3
			state.rotation = u8((int(state.rotation)+step)%4); state.drag_moved = true
		}
		if input.mouse_pressed(frame.devices, .RIGHT) { state.dragging = false }
		if input.mouse_released(frame.devices, .LEFT) {
			if state.drag_moved {
				target := target_at(layout, frame.mouse, state.page, in_hub)
				if relocate(c, state.dragged, target, state.rotation, in_combat, in_hub) {
					out.changed = true; state.selected = {}; notice(state, "Equipaggiamento sistemato.")
				} else { notice(state, "Non c'e spazio qui, oppure il posto e bloccato dallo scontro.") }
			}
			state.dragging = false
		}
	}
	ui.text_at(ctx, {layout.content.x, layout.content.y}, "RELIQUIE ATTIVE / 3", .Small, {167, 157, 212, 255})
	ui.text_at(ctx, {layout.weapon.x, layout.content.y}, "ARMA", .Small, {226, 162, 141, 255})
	for rect, i in layout.relics { draw_slot(ctx, rect, c.backpack.relics[i], state.selected == Item_Ref{.Relic, i, 0}, in_combat) }
	draw_slot(ctx, layout.weapon, c.backpack.weapon, state.selected.source == .Weapon, in_combat)
	ui.text_at(ctx, {layout.bag_grid.x, layout.bag_grid.y-26},
		fmt.tprintf("ZAINO %d x %d   /   %d CREDITI", c.backpack.grid.width, c.backpack.grid.height, campaign.backpack_credits(&c.backpack)), .Small, {142, 184, 198, 255})
	draw_grid(ctx, &c.backpack.grid, layout.bag_grid, layout.bag_cell, state, .Backpack, 0)
	ui.text_at(ctx, {layout.pending[0].x, layout.pending[0].y-24}, "SOSPESO / LASCIA SPAZIO ALLE SCELTE", .Small, {220, 187, 116, 255})
	for rect, i in layout.pending {
		item := c.backpack.pending[i] if i < c.backpack.pending_count else campaign.Item{}
		draw_slot(ctx, rect, item, state.selected == Item_Ref{.Pending, i, 0}, false)
	}
	if in_hub {
		ui.text_at(ctx, {layout.depot_header.x, layout.depot_header.y}, fmt.tprintf("DEPOSITO / %d CREDITI", campaign.depot_credits(c)), .Small, {229, 200, 142, 255})
		if ui.button(ctx, {layout.depot_header.x+layout.depot_header.width-108, layout.depot_header.y-4, 30, 30}, "<", state.page > 0, false, .Small) { state.page -= 1; state.selected = {} }
		ui.label(ctx, {layout.depot_header.x+layout.depot_header.width-78, layout.depot_header.y-4, 48, 30}, fmt.tprintf("%d/%d", state.page+1, len(c.depot)), .Small, nil, .Center)
		if ui.button(ctx, {layout.depot_header.x+layout.depot_header.width-30, layout.depot_header.y-4, 30, 30}, ">", state.page < len(c.depot)-1, false, .Small) { state.page += 1; state.selected = {} }
		draw_grid(ctx, &c.depot[state.page], layout.depot_grid, layout.depot_cell, state, .Depot, state.page)
		// Every previously extracted size stays selectable, while a smaller
		// choice is refused if any existing item would protrude from its edge.
		width := c.backpack.grid.width
		if c.backpack_width > campaign.BACKPACK_WIDTH {
				r := ui.Rect{layout.pending[2].x+90, layout.pending[2].y+4, 112, 36}
			if ui.button(ctx, r, fmt.tprintf("ZAINO %d >", width), !c.run.active, false, .Small) {
				next := width+1
				if next > c.backpack_width { next = campaign.BACKPACK_WIDTH }
				old := c.backpack.grid.width; c.backpack.grid.width = next
				if campaign.grid_valid(&c.backpack.grid) { c.revision += 1; out.changed = true } else {
					c.backpack.grid.width = old; notice(state, "Sposta gli oggetti prima di scegliere uno zaino piu piccolo.")
				}
			}
		}
	}
	item_detail(c, player, state, frame, layout.detail, in_combat, in_hub, can_use, out)
	ui.text_at(ctx, {layout.window.x+24, layout.window.y+layout.window.height-54}, "TRASCINA per spostare   ROTELLA / R per ruotare   CLIC per i dettagli", .Small, {118, 151, 173, 255})
	if state.dragging && state.drag_moved {
		if item, ok := item_at_ref(c, state.dragged); ok {
			item.rotation = state.rotation
			target := target_at(layout, frame.mouse, state.page, in_hub)
			origin, cell := frame.mouse+[2]f32{12, 12}, layout.bag_cell
			if target.source == .Backpack { origin = {layout.bag_grid.x+f32(target.x)*cell, layout.bag_grid.y+f32(target.y)*cell} }
			if target.source == .Depot { cell = layout.depot_cell; origin = {layout.depot_grid.x+f32(target.x)*cell, layout.depot_grid.y+f32(target.y)*cell} }
			draw_item(ctx, item, origin, cell, true, 0.85)
			fits := false
			switch target.source {
			case .Backpack, .Depot:
				grid := &c.backpack.grid if target.source == .Backpack else &c.depot[target.page]
				ignore := state.dragged.index if state.dragged.source == target.source && (target.source != .Depot || state.dragged.page == target.page) else -1
				fits = campaign.grid_can_place(grid, item, target.x, target.y, ignore)
				if index := campaign.grid_item_at(grid, target.x, target.y, ignore); index >= 0 {
					other := grid.entries[index].item
					fits = other.kind == item.kind && other.variant == item.variant && other.uses == item.uses && campaign.stack_limit(item.kind) > 1 && other.quantity+item.quantity <= campaign.stack_limit(item.kind)
				}
			case .Relic: fits = item.kind == .Relic && !in_combat
			case .Weapon: fits = item.kind == .Weapon && !in_combat
			case .Pending: fits = c.backpack.pending_count < 3 || state.dragged.source == .Pending
			case .None:
			}
			if in_hub && c.run.active { fits = false }
			shape := campaign.item_shape(item)
			ui.outline(ctx, {origin.x-1, origin.y-1, cell*f32(shape.width)+2, cell*f32(shape.height)+2}, {113, 222, 177, 255} if fits else {242, 109, 116, 255}, 2)
		}
	}
}

@(private)
item_detail :: proc(c: ^campaign.Campaign, player: ^game.Player, state: ^State, frame: ^host.Frame,
	bounds: ui.Rect, in_combat, in_hub, can_use: bool, out: ^Output) {
	ctx := frame.ui
	can_change := !in_hub || !c.run.active
	item, valid := item_at_ref(c, state.selected)
	if !valid {
		ui.text_at(ctx, {bounds.x, bounds.y+4}, "SPAZIO PER CIO CHE CONTA", .Small, {195, 220, 224, 255})
		ui.paragraph(ctx, {bounds.x, bounds.y+32, bounds.width, bounds.height-32},
			"Seleziona un oggetto per leggerlo. Le reliquie funzionano solo nei tre posti attivi. Trascina tra zaino, sospeso e deposito.", .Small, {135, 165, 184, 255})
		return
	}
	ui.text_at(ctx, {bounds.x, bounds.y}, ui.ellipsize(ctx.theme, campaign.item_name(item), bounds.width, .Body), .Body, item_color(item))
	desc := campaign.item_description(item)
	ui.clip_begin(ctx, {bounds.x, bounds.y+25, bounds.width, 32 if in_hub else 84})
	ui.paragraph(ctx, {bounds.x, bounds.y+28, bounds.width, 100}, desc, .Small, {162, 183, 197, 255})
	ui.clip_end(ctx)
	y := bounds.y+62 if in_hub else bounds.y+112
	width := min(210, (bounds.width-10)/2)
	primary := ui.Rect{bounds.x, y, width, 34}
	secondary := ui.Rect{bounds.x+width+10, y, width, 34}
	if state.selected.source == .Depot {
		if ui.button(ctx, primary, "PREPARA NELLO ZAINO", can_change, true, .Small) {
			if campaign.depot_take(c, state.selected.page, state.selected.index) { out.changed = true; state.selected = {} } else { notice(state, "Lo zaino non ha spazio per questo oggetto.") }
		}
		return
	}
	if state.selected.source == .Backpack && (item.kind <= .Upgrade || item.kind == .Structure_Kit) {
		if ui.button(ctx, primary, "POSA" if item.kind == .Structure_Kit else "USA", player != nil && can_use, true, .Small) {
			used := use_selected(c, player, state, in_combat, can_use)
			out.changed = out.changed || used.changed; out.decoy = used.decoy; out.action_seconds += used.action_seconds
			out.place_structure, out.structure = used.place_structure, used.structure
			if used.place_structure { out.closed = true }
		}
	} else if state.selected.source == .Pending {
		if ui.button(ctx, primary, "SISTEMA", can_change, true, .Small) {
			if campaign.grid_add(&c.backpack.grid, item) {
				campaign.pending_remove(&c.backpack, state.selected.index); c.revision += 1; out.changed = true; state.selected = {}
			} else { notice(state, "Non c'e ancora spazio: sposta o ruota gli altri oggetti.") }
		}
	} else if state.selected.source == .Relic || state.selected.source == .Weapon {
		if ui.button(ctx, primary, "RIPONI", !in_combat && can_change, true, .Small) {
			if campaign.unequip(&c.backpack, state.selected.index, state.selected.source == .Weapon, in_combat) {
				c.revision += 1; out.changed = true; state.selected = {}
			} else { notice(state, "Lo zaino non ha spazio.") }
		}
	} else if state.selected.source == .Backpack && (item.kind == .Relic || item.kind == .Weapon) {
		if ui.button(ctx, primary, "EQUIPAGGIA", !in_combat && can_change, true, .Small) {
			slot := 0
			for active, i in c.backpack.relics { if active.kind == .None { slot = i; break } }
			if campaign.equip(&c.backpack, state.selected.index, slot, in_combat) { c.revision += 1; out.changed = true; state.selected = {} } else { notice(state, "Trascina la reliquia sul posto da sostituire.") }
		}
	} else { ui.label(ctx, primary, fmt.tprintf("QUANTITA %d", item.quantity), .Small) }
	// Re-read selection after an action. Indices may have shifted.
	if _, still_selected := item_at_ref(c, state.selected); !still_selected { return }
	if in_hub {
		if state.selected.source == .Backpack && ui.button(ctx, secondary, "NEL DEPOSITO", can_change, false, .Small) {
			if campaign.depot_store(c, state.selected.index) { out.changed = true; state.selected = {} }
		}
	} else {
		can_drop := !in_combat || (state.selected.source != .Relic && state.selected.source != .Weapon)
		if ui.button(ctx, secondary, "LASCIA A TERRA", can_drop, false, .Small) {
			out.drops[0] = item; out.drop_count = 1; remove_ref(c, state.selected); c.revision += 1; out.changed = true; state.selected = {}
		}
	}
	if !in_hub && state.selected.source == .Backpack && ui.button(ctx, {bounds.x, y+48, width, 34}, "SPOSTA NEL SOSPESO", c.backpack.pending_count < 3, false, .Small) {
		if campaign.hold_item(&c.backpack, state.selected.index) { c.revision += 1; out.changed = true; state.selected = {} }
	}
	if !in_hub {
		shape := campaign.item_shape(item)
		ui.text_at(ctx, {bounds.x, y+108}, fmt.tprintf("%d celle  /  pila %d/%d", shape.count, item.quantity, campaign.stack_limit(item.kind)), .Small, {139, 165, 180, 255})
		ui.paragraph(ctx, {bounds.x, y+138, bounds.width, 100}, "Morendo perdi lo zaino, le reliquie attive e l'arma. Estraendo, tutto torna al deposito.", .Small, {208, 166, 141, 255})
	}
}

@(private)
cards_panel :: proc(c: ^campaign.Campaign, player: ^game.Player, state: ^State, frame: ^host.Frame,
	bounds: ui.Rect, in_combat: bool, out: ^Output) {
	ctx := frame.ui
	archive := state.panel == .Archive
	if !archive && player == nil {
		ui.text_at(ctx, {bounds.x, bounds.y+8}, "IL MAZZO RINASCE A OGNI SPEDIZIONE", .Large, {188, 219, 226, 255})
		ui.paragraph(ctx, {bounds.x, bounds.y+60, bounds.width*0.65, 180}, "Ogni run riparte dal mazzo base e dal livello 1. I frammenti di esperienza diventano punti: un punto potenzia una carta, fuori dagli scontri. Le carte scoperte restano nell'archivio anche quando perdi tutto.", .Body, {148, 178, 198, 255})
		return
	}
	list: [int(game.Card_Id.Count)+game.MAX_OWNED_CARDS]game.Card_Id
	indices: [int(game.Card_Id.Count)+game.MAX_OWNED_CARDS]int
	count := 0
	if archive {
		for id in game.Card_Id.Strike..<game.Card_Id.Count {
			if c.discovered[id] { list[count] = id; count += 1 }
		}
		ui.text_at(ctx, {bounds.x, bounds.y}, fmt.tprintf("ARCHIVIO / %d CARTE NELLA MEMORIA", count), .Large, {190, 179, 237, 255})
		ui.text_at(ctx, {bounds.x, bounds.y+38}, "Le nuove scoperte entrano nel pool della prossima spedizione.", .Small, {144, 173, 194, 255})
	} else {
		for card, i in player.deck.owned[:player.deck.owned_count] { list[count] = card.definition_id; indices[count] = i; count += 1 }
		ui.text_at(ctx, {bounds.x, bounds.y}, fmt.tprintf("LIVELLO %d   /   %d PUNTI POTENZIAMENTO", c.run.level, c.run.points), .Large, {144, 225, 212, 255})
		ui.text_at(ctx, {bounds.x, bounds.y+38}, "I potenziamenti richiedono esperienza e si spendono fuori dagli scontri.", .Small, {144, 173, 194, 255})
		ui.progress(ctx, {bounds.x+bounds.width-260, bounds.y+8, 250, 16}, f32(c.run.xp)/f32(campaign.xp_for_level(c.run.level)), {96, 201, 210, 255})
		ui.label(ctx, {bounds.x+bounds.width-260, bounds.y+30, 250, 22}, fmt.tprintf("%d / %d XP", c.run.xp, campaign.xp_for_level(c.run.level)), .Small, nil, .Right)
	}
	per_page := 4 if bounds.height < 380 else 6
	pages := max(1, (count+per_page-1)/per_page)
	state.card_page = clamp(state.card_page, 0, pages-1)
	row_height := min(96, (bounds.height-132)/f32(per_page/2))
	column_width := (bounds.width-20)/2
	for offset in 0..<per_page {
		index := state.card_page*per_page+offset
		if index >= count { break }
		id := list[index]
		definition, _ := game.card_definition_by_id(id)
		r := ui.Rect{bounds.x+f32(offset%2)*(column_width+20), bounds.y+76+f32(offset/2)*(row_height+8), column_width, row_height}
		ui.fill(ctx, r, {22, 34, 49, 250}, 0.04)
		ui.outline(ctx, r, {52, 82, 104, 255}, 1, 0.04)
		ui.fill(ctx, {r.x, r.y, 3, r.height}, {171, 134, 219, 255} if archive else {95, 204, 199, 255})
		ui.text_at(ctx, {r.x+14, r.y+8}, ui.ellipsize(ctx.theme, definition.name, r.width-180, .Body), .Body)
		card := player.deck.owned[indices[index]] if !archive else game.Card_Instance{}
		subtitle := fmt.tprintf("%s / scoperta", game.card_rarity_name(definition.rarity)) if archive else
			fmt.tprintf("Potenziamento %d / %d", card.upgrade_level, game.card_max_upgrade_level(id))
		ui.text_at(ctx, {r.x+14, r.y+37}, subtitle, .Small, {139, 171, 192, 255})
		if ui.button(ctx, {r.x+r.width-158, r.y+r.height-34, 144, 26}, "MOSTRA EFFETTO", true, false, .Small) {
			out.show_effect = true; out.effect_card = id
		}
		if !archive {
			can_upgrade := !in_combat && c.run.points > 0 && card.upgrade_level < game.card_max_upgrade_level(id)
			if ui.button(ctx, {r.x+r.width-144, r.y+7, 130, 24}, "+ POTENZIA", can_upgrade, true, .Small) {
				if campaign.upgrade_card(c, &player.deck, card.id, in_combat) { out.changed = true; notice(state, "Carta potenziata. Il costo energetico resta invariato.") }
			}
		}
	}
	y := bounds.y+bounds.height-30
	if ui.button(ctx, {bounds.x, y, 100, 28}, "<", state.card_page > 0, false, .Small) { state.card_page -= 1 }
	ui.label(ctx, {bounds.x+112, y, 160, 28}, fmt.tprintf("PAGINA %d / %d", state.card_page+1, pages), .Small)
	if ui.button(ctx, {bounds.x+280, y, 100, 28}, ">", state.card_page < pages-1, false, .Small) { state.card_page += 1 }
}
