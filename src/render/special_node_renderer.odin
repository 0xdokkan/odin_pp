package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

SPECIAL_NODE_MIN_CANVAS_WIDTH  :: f32(900)
SPECIAL_NODE_MIN_CANVAS_HEIGHT :: f32(520)

SPECIAL_NODE_HEADER_HEIGHT :: f32(74)

SPECIAL_NODE_ACTION_TOP    :: f32(154)
SPECIAL_NODE_ACTION_WIDTH  :: f32(240)
SPECIAL_NODE_ACTION_HEIGHT :: f32(88)
SPECIAL_NODE_ACTION_GAP    :: f32(20)

SPECIAL_NODE_RESULT_WIDTH  :: f32(620)
SPECIAL_NODE_RESULT_HEIGHT :: f32(142)
SPECIAL_NODE_RESULT_TOP    :: f32(146)

Special_Node_Hit_Kind :: enum {
	None,
	Primary,
	Secondary,
	Leave,
	Owned_Card,
	Previous_Page,
	Next_Page,
	Continue,
}

Special_Node_Hit :: struct {
	kind:    Special_Node_Hit_Kind,
	card_id: u32,
}

Special_Node_Render_State :: struct {
	page:                  int,
	hovered_card_id:       u32,
	selected_card_id:      u32,
	previous_page_hovered: bool,
	next_page_hovered:     bool,
	primary_hovered:       bool,
	secondary_hovered:     bool,
	leave_hovered:         bool,
	continue_hovered:      bool,
}

@(private = "file")
special_node_phase_is_supported :: proc(phase: game.Run_Phase) -> bool {
	return phase == .Rest || phase == .Event || phase == .Treasure
}

@(private)
special_node_canvas_is_supported :: proc(canvas_width, canvas_height: f32) -> bool {
	return canvas_width >= SPECIAL_NODE_MIN_CANVAS_WIDTH &&
	       canvas_height >= SPECIAL_NODE_MIN_CANVAS_HEIGHT
}

@(private = "file")
special_node_point_in_bounds :: proc(point: view.Vec2, bounds: rl.Rectangle) -> bool {
	return bounds.width > 0 && bounds.height > 0 && point_in_rectangle(point, bounds)
}

@(private)
special_node_action_count :: proc(run: ^game.Run_State) -> int {
	if run == nil || game.special_node_is_resolved(run) {
		return 0
	}
	switch run.phase {
	case .Rest, .Event:
		return 3
	case .Treasure:
		return 2
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return 0
}

@(private)
special_node_action_bounds :: proc(
	canvas_width, canvas_height: f32,
	action_index, action_count: int,
) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) ||
	   action_count <= 0 || action_count > 3 ||
	   action_index < 0 || action_index >= action_count {
		return {}
	}
	total_width := SPECIAL_NODE_ACTION_WIDTH*f32(action_count)+
	               SPECIAL_NODE_ACTION_GAP*f32(action_count-1)
	return {
		x = (canvas_width-total_width)*0.5+
		    f32(action_index)*(SPECIAL_NODE_ACTION_WIDTH+SPECIAL_NODE_ACTION_GAP),
		y = SPECIAL_NODE_ACTION_TOP,
		width = SPECIAL_NODE_ACTION_WIDTH,
		height = SPECIAL_NODE_ACTION_HEIGHT,
	}
}

@(private)
special_node_result_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return {
		x = (canvas_width-SPECIAL_NODE_RESULT_WIDTH)*0.5,
		y = SPECIAL_NODE_RESULT_TOP,
		width = SPECIAL_NODE_RESULT_WIDTH,
		height = SPECIAL_NODE_RESULT_HEIGHT,
	}
}

@(private)
special_node_continue_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_continue_bounds(canvas_width, canvas_height)
}

@(private)
special_node_previous_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_previous_page_bounds(canvas_width, canvas_height)
}

@(private)
special_node_next_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_next_page_bounds(canvas_width, canvas_height)
}

@(private)
special_node_owned_card_bounds :: proc(
	canvas_width, canvas_height: f32,
	page_slot: int,
	raised: bool = false,
) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_owned_card_bounds(canvas_width, canvas_height, page_slot, raised)
}

@(private)
special_node_deck_page_count :: proc(deck: ^game.Deck_State) -> int {
	return shop_deck_page_count(deck)
}

special_node_clamp_deck_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	return shop_clamp_deck_page(deck, page)
}

@(private)
special_node_deck_page_start :: proc(deck: ^game.Deck_State, page: int) -> (int, bool) {
	return shop_deck_page_start(deck, page)
}

@(private)
special_node_deck_cards_on_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	return shop_deck_cards_on_page(deck, page)
}

@(private = "file")
special_node_owned_card_at_point :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	page: int,
	point: view.Vec2,
	raised_card_id: u32 = 0,
) -> (card_id: u32, found: bool) {
	if run == nil || run.phase != .Rest || run.rest.resolved ||
	   !game.validate_special_node_state(run) ||
	   !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return 0, false
	}
	return owned_deck_card_at_point(&run.player.deck, canvas_width, canvas_height, page, point, raised_card_id)
}

special_node_hit_test :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	page: int,
	point: view.Vec2,
	raised_card_id: u32 = 0,
	selected_card_id: u32 = 0,
) -> Special_Node_Hit {
	if run == nil || !special_node_phase_is_supported(run.phase) ||
	   !game.validate_special_node_state(run) ||
	   !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	if game.special_node_is_resolved(run) {
		if special_node_point_in_bounds(
			point,
			special_node_continue_bounds(canvas_width, canvas_height),
		) {
			return {kind = .Continue}
		}
		return {}
	}

	clamped_page := special_node_clamp_deck_page(&run.player.deck, page)
	if run.phase == .Rest {
		if card_id, found := special_node_owned_card_at_point(
			run,
			canvas_width,
			canvas_height,
			clamped_page,
			point,
			raised_card_id,
		); found {
			return {kind = .Owned_Card, card_id = card_id}
		}
		if clamped_page > 0 && special_node_point_in_bounds(
			point,
			special_node_previous_page_bounds(canvas_width, canvas_height),
		) {
			return {kind = .Previous_Page}
		}
		if clamped_page+1 < special_node_deck_page_count(&run.player.deck) &&
		   special_node_point_in_bounds(
			point,
			special_node_next_page_bounds(canvas_width, canvas_height),
		) {
			return {kind = .Next_Page}
		}
	}

	action_count := special_node_action_count(run)
	if game.special_node_primary_is_enabled(run) && special_node_point_in_bounds(
		point,
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
	) {
		return {kind = .Primary}
	}
	if action_count == 3 && game.special_node_secondary_is_enabled(run, selected_card_id) &&
	   special_node_point_in_bounds(
		point,
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
	) {
		return {kind = .Secondary}
	}
	leave_index := action_count-1
	if special_node_point_in_bounds(
		point,
		special_node_action_bounds(canvas_width, canvas_height, leave_index, action_count),
	) {
		return {kind = .Leave}
	}
	return {}
}

@(private = "file")
special_node_accent :: proc(phase: game.Run_Phase) -> rl.Color {
	switch phase {
	case .Rest:
		return rl.Color{91, 204, 195, 255}
	case .Event:
		return rl.Color{224, 99, 86, 255}
	case .Treasure:
		return rl.Color{246, 207, 92, 255}
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return rl.Color{151, 163, 158, 255}
}

@(private = "file")
draw_special_node_action :: proc(
	bounds: rl.Rectangle,
	title, detail: cstring,
	hovered, enabled: bool,
	accent: rl.Color, theme: ^Renderer = nil,
) {
	fill := rl.Color{27, 32, 35, 255}
	outline := rl.Color{96, 107, 107, 255}
	title_color := rl.Color{225, 229, 224, 255}
	detail_color := rl.Color{151, 163, 158, 255}
	if !enabled {
		fill = rl.Color{23, 26, 28, 255}
		outline = rl.Color{58, 64, 65, 255}
		title_color = rl.Color{93, 101, 100, 255}
		detail_color = rl.Color{73, 80, 79, 255}
	} else if hovered {
		fill = rl.Color{43, 49, 51, 255}
		outline = accent
		title_color = accent
	}
	menu_rectangle_rec(theme, bounds, fill)
	menu_outline(theme, bounds, 2, outline)
	title_size: c.int = 17
	title_width := menu_measure_text(theme, title, title_size)
	menu_text(theme,
		title,
		c.int(bounds.x+bounds.width*0.5)-title_width/2,
		c.int(bounds.y+20),
		title_size,
		title_color,
	)
	detail_size: c.int = 12
	detail_width := menu_measure_text(theme, detail, detail_size)
	menu_text(theme,
		detail,
		c.int(bounds.x+bounds.width*0.5)-detail_width/2,
		c.int(bounds.y+52),
		detail_size,
		detail_color,
	)
}

@(private = "file")
draw_special_node_header :: proc(
	run: ^game.Run_State,
	canvas_width: f32, theme: ^Renderer = nil,
) {
	title: cstring
	subtitle: cstring
	switch run.phase {
	case .Rest:
		title = "REST SITE"
		subtitle = "A QUIET MOMENT BETWEEN ROOMS"
	case .Event:
		title = "ROUTE EVENT"
		subtitle = fmt.ctprintf("%s", game.route_event_kind_name(run.route_event.kind))
	case .Treasure:
		title = "TREASURE"
		subtitle = "AN UNGUARDED CACHE"
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		return
	}
	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(SPECIAL_NODE_HEADER_HEIGHT), rl.Color{15, 18, 21, 255})
	menu_text(theme, title, 28, 13, 23, rl.Color{225, 229, 224, 255})
	menu_text(theme, subtitle, 28, 43, 13, special_node_accent(run.phase))
	stats_label := fmt.ctprintf(
			"HP %d/%d    GOLD %d    DECK %d/%d",
			run.player.health,
			run.player.stats.max_health,
			run.player.gold,
			run.player.deck.owned_count,
			game.MAX_OWNED_CARDS,
		)
	stats_size: c.int = 13
	stats_width := menu_measure_text(theme, stats_label, stats_size)
	menu_text(theme,
		stats_label,
		c.int(canvas_width)-116-stats_width,
		29,
		stats_size,
		rl.Color{151, 163, 158, 255},
	)
}

@(private = "file")
draw_special_node_result :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32, theme: ^Renderer = nil,
) {
	bounds := special_node_result_bounds(canvas_width, canvas_height)
	accent := special_node_accent(run.phase)
	menu_rectangle_rec(theme, bounds, rl.Color{24, 29, 31, 255})
	menu_outline(theme, bounds, 2, accent)
	menu_text(theme, "RESULT", c.int(bounds.x+24), c.int(bounds.y+20), 13, rl.Color{151, 163, 158, 255})

	result: cstring = "RESOLVED"
	detail: cstring = "THE PATH AHEAD IS OPEN"
	switch run.phase {
	case .Rest:
		switch run.rest.outcome {
		case .Recovered:
			result = "RECOVERED"
			detail = fmt.ctprintf("+%d HP", run.rest.applied_amount)
		case .Upgraded:
			result = "CARD UPGRADED"
			if card_index, found := game.owned_card_index_by_id(
				&run.player.deck,
				run.rest.target_card_id,
			); found {
				definition, definition_found := game.card_definition_by_id(run.player.deck.owned[card_index].definition_id)
				if definition_found {
					detail = fmt.ctprintf("%s +%d", definition.name, run.player.deck.owned[card_index].upgrade_level)
				}
			}
		case .Left:
			result = "LEFT UNTOUCHED"
			detail = "NO RECOVERY OR UPGRADE"
		case .None, .Event_Primary, .Event_Secondary, .Treasure_Claimed:
		}
	case .Event:
		switch run.route_event.outcome {
		case .Event_Primary:
			result = "FIRST CHOICE RESOLVED"
		case .Event_Secondary:
			result = "SECOND CHOICE RESOLVED"
		case .Left:
			result = "EVENT LEFT BEHIND"
		case .None, .Recovered, .Upgraded, .Treasure_Claimed:
		}
		if run.route_event.added_card_id != 0 {
			definition, found := game.card_definition_by_id(run.route_event.offered_card)
			if found {
				detail = fmt.ctprintf("ADDED %s", definition.name)
			}
		} else if run.route_event.applied_amount > 0 {
			detail = fmt.ctprintf("APPLIED %d", run.route_event.applied_amount)
		} else if run.route_event.outcome == .Left {
			detail = "NO BARGAIN WAS MADE"
		}
	case .Treasure:
		if run.treasure.outcome == .Treasure_Claimed {
			result = "TREASURE CLAIMED"
			detail = fmt.ctprintf("+%d GOLD", run.treasure.applied_amount)
		} else if run.treasure.outcome == .Left {
			result = "CACHE LEFT UNTOUCHED"
			detail = "NO GOLD TAKEN"
		}
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	result_size: c.int = 25
	result_width := menu_measure_text(theme, result, result_size)
	menu_text(theme,
		result,
		c.int(bounds.x+bounds.width*0.5)-result_width/2,
		c.int(bounds.y+55),
		result_size,
		accent,
	)
	detail_size: c.int = 14
	detail_width := menu_measure_text(theme, detail, detail_size)
	menu_text(theme,
		detail,
		c.int(bounds.x+bounds.width*0.5)-detail_width/2,
		c.int(bounds.y+98),
		detail_size,
		rl.Color{225, 229, 224, 255},
	)
}

@(private = "file")
draw_rest_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State, theme: ^Renderer = nil,
) {
	action_count := special_node_action_count(run)
	accent := special_node_accent(run.phase)
	if index, found := game.owned_card_index_by_id(&run.player.deck, state.selected_card_id); found {
		menu_text(theme, card_upgrade_preview(run.player.deck.owned[index]), 45, 454, 12,
			rl.Color{169, 183, 177, 255})
	}
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
		"RECOVER",
		fmt.ctprintf("UP TO %d HP", run.rest.heal_amount),
		state.primary_hovered,
		game.special_node_primary_is_enabled(run),
		accent,
		theme = theme,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		"UPGRADE",
		"SELECTED CARD",
		state.secondary_hovered,
		game.special_node_secondary_is_enabled(run, state.selected_card_id),
		accent,
		theme = theme,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 2, action_count),
		"LEAVE",
		"KEEP MOVING",
		state.leave_hovered,
		true,
		accent,
		theme = theme,
	)

	draw_owned_deck_page(run, canvas_width, canvas_height, state.page,
		state.hovered_card_id, state.selected_card_id,
		state.previous_page_hovered, state.next_page_hovered, theme)
	// MOSTRA EFFETTO of the owned card chosen for the upgrade.
	_, chosen := game.owned_card_index_by_id(&run.player.deck, state.selected_card_id)
	draw_owned_card_effect_button(theme, canvas_width, canvas_height, chosen)
}

@(private = "file")
draw_event_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State, theme: ^Renderer = nil,
) {
	primary_title: cstring
	primary_detail: cstring
	secondary_title: cstring
	secondary_detail: cstring
	switch run.route_event.kind {
	case .Blood_Offering:
		primary_title = "MAKE OFFER"
		primary_detail = fmt.ctprintf("-%d HP  +%d GOLD", run.route_event.health_cost, run.route_event.primary_gold)
		secondary_title = "REFUSE"
		secondary_detail = "TAKE NOTHING"
	case .Healing_Spring:
		primary_title = "DRINK"
		primary_detail = fmt.ctprintf("UP TO +%d HP", run.route_event.heal_amount)
		secondary_title = "BOTTLE"
		secondary_detail = fmt.ctprintf("+%d GOLD", run.route_event.secondary_gold)
	case .Forgotten_Armory:
		definition, found := game.card_definition_by_id(run.route_event.offered_card)
		assert(found)
		primary_title = "TAKE CARD"
		primary_detail = fmt.ctprintf("%s", definition.name)
		secondary_title = "SALVAGE"
		secondary_detail = fmt.ctprintf("+%d GOLD", run.route_event.secondary_gold)
	case .Count:
		return
	}
	action_count := special_node_action_count(run)
	accent := special_node_accent(run.phase)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
		primary_title,
		primary_detail,
		state.primary_hovered,
		game.special_node_primary_is_enabled(run),
		accent,
		theme = theme,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		secondary_title,
		secondary_detail,
		state.secondary_hovered,
		game.special_node_secondary_is_enabled(run, state.selected_card_id),
		accent,
		theme = theme,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 2, action_count),
		"LEAVE",
		"WALK AWAY",
		state.leave_hovered,
		true,
		accent,
		theme = theme,
	)
}

@(private = "file")
draw_treasure_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State, theme: ^Renderer = nil,
) {
	action_count := special_node_action_count(run)
	accent := special_node_accent(run.phase)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
		"CLAIM",
		fmt.ctprintf("+%d GOLD", run.treasure.gold_amount),
		state.primary_hovered,
		game.special_node_primary_is_enabled(run),
		accent,
		theme = theme,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		"LEAVE",
		"DO NOT OPEN",
		state.leave_hovered,
		true,
		accent,
		theme = theme,
	)
}

draw_special_node_screen :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State = {}, theme: ^Renderer = nil,
) {
	assert(run != nil && special_node_phase_is_supported(run.phase))
	assert(game.validate_special_node_state(run))
	assert(special_node_canvas_is_supported(canvas_width, canvas_height))
	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(canvas_height), CANVAS_BACKGROUND)
	draw_special_node_header(run, canvas_width, theme = theme)

	if game.special_node_is_resolved(run) {
		draw_special_node_result(run, canvas_width, canvas_height, theme = theme)
		draw_shop_button(
			special_node_continue_bounds(canvas_width, canvas_height),
			"CONTINUE",
			state.continue_hovered,
			true,
			special_node_accent(run.phase),
		 theme = theme)
	} else {
		switch run.phase {
		case .Rest:
			draw_rest_actions(run, canvas_width, canvas_height, state, theme = theme)
		case .Event:
			draw_event_actions(run, canvas_width, canvas_height, state, theme = theme)
		case .Treasure:
			draw_treasure_actions(run, canvas_width, canvas_height, state, theme = theme)
		case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		}
	}

}
