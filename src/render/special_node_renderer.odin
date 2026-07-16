package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

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

special_node_phase_is_supported :: proc(phase: game.Run_Phase) -> bool {
	return phase == .Rest || phase == .Event || phase == .Treasure
}

special_node_canvas_is_supported :: proc(canvas_width, canvas_height: f32) -> bool {
	return canvas_width >= SPECIAL_NODE_MIN_CANVAS_WIDTH &&
	       canvas_height >= SPECIAL_NODE_MIN_CANVAS_HEIGHT
}

special_node_point_in_bounds :: proc(point: view.Vec2, bounds: rl.Rectangle) -> bool {
	return bounds.width > 0 && bounds.height > 0 && point_in_rectangle(point, bounds)
}

special_node_is_resolved :: proc(run: ^game.Run_State) -> bool {
	if run == nil {
		return false
	}
	switch run.phase {
	case .Rest:
		return run.rest.resolved
	case .Event:
		return run.route_event.resolved
	case .Treasure:
		return run.treasure.resolved
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

special_node_action_count :: proc(run: ^game.Run_State) -> int {
	if run == nil || special_node_is_resolved(run) {
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

special_node_continue_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_continue_bounds(canvas_width, canvas_height)
}

special_node_previous_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_previous_page_bounds(canvas_width, canvas_height)
}

special_node_next_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !special_node_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return shop_next_page_bounds(canvas_width, canvas_height)
}

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

special_node_deck_page_count :: proc(deck: ^game.Deck_State) -> int {
	return shop_deck_page_count(deck)
}

special_node_clamp_deck_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	return shop_clamp_deck_page(deck, page)
}

special_node_deck_page_start :: proc(deck: ^game.Deck_State, page: int) -> (int, bool) {
	return shop_deck_page_start(deck, page)
}

special_node_deck_cards_on_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	return shop_deck_cards_on_page(deck, page)
}

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
	deck := &run.player.deck
	start, valid_page := special_node_deck_page_start(deck, page)
	if !valid_page {
		return 0, false
	}
	visible_count := special_node_deck_cards_on_page(deck, page)
	if raised_card_id != 0 {
		if raised_index, raised_found := game.owned_card_index_by_id(deck, raised_card_id);
		   raised_found && raised_index >= start && raised_index < start+visible_count {
			slot := raised_index-start
			if special_node_point_in_bounds(
				point,
				special_node_owned_card_bounds(canvas_width, canvas_height, slot, true),
			) {
				return raised_card_id, true
			}
		}
	}
	for slot := visible_count-1; slot >= 0; slot -= 1 {
		bounds := special_node_owned_card_bounds(canvas_width, canvas_height, slot)
		if special_node_point_in_bounds(point, bounds) {
			return deck.owned[start+slot].id, true
		}
	}
	return 0, false
}

special_node_primary_is_enabled :: proc(run: ^game.Run_State) -> bool {
	if run == nil || special_node_is_resolved(run) {
		return false
	}
	switch run.phase {
	case .Rest:
		return true
	case .Event:
		switch run.route_event.kind {
		case .Blood_Offering:
			return run.player.health > run.route_event.health_cost &&
			       i64(run.player.gold)+i64(run.route_event.primary_gold) <= i64(max(i32))
		case .Healing_Spring:
			return true
		case .Forgotten_Armory:
			return run.player.deck.owned_count < game.MAX_OWNED_CARDS &&
			       run.player.deck.next_card_id < max(u32)
		case .Count:
		}
	case .Treasure:
		return i64(run.player.gold)+i64(run.treasure.gold_amount) <= i64(max(i32))
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

special_node_secondary_is_enabled :: proc(
	run: ^game.Run_State,
	selected_card_id: u32,
) -> bool {
	if run == nil || special_node_is_resolved(run) {
		return false
	}
	switch run.phase {
	case .Rest:
		card_index, found := game.owned_card_index_by_id(&run.player.deck, selected_card_id)
		return found &&
		       run.player.deck.owned[card_index].upgrade_level < game.MAX_CARD_UPGRADE_LEVEL
	case .Event:
		if run.route_event.kind == .Blood_Offering {
			return true
		}
		return i64(run.player.gold)+i64(run.route_event.secondary_gold) <= i64(max(i32))
	case .Treasure, .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
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
	if special_node_is_resolved(run) {
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
	if special_node_primary_is_enabled(run) && special_node_point_in_bounds(
		point,
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
	) {
		return {kind = .Primary}
	}
	if action_count == 3 && special_node_secondary_is_enabled(run, selected_card_id) &&
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

draw_special_node_action :: proc(
	bounds: rl.Rectangle,
	title, detail: cstring,
	hovered, enabled: bool,
	accent: rl.Color,
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
	rl.DrawRectangleRec(bounds, fill)
	rl.DrawRectangleLinesEx(bounds, 2, outline)
	title_size: c.int = 17
	title_width := rl.MeasureText(title, title_size)
	rl.DrawText(
		title,
		c.int(bounds.x+bounds.width*0.5)-title_width/2,
		c.int(bounds.y+20),
		title_size,
		title_color,
	)
	detail_size: c.int = 12
	detail_width := rl.MeasureText(detail, detail_size)
	rl.DrawText(
		detail,
		c.int(bounds.x+bounds.width*0.5)-detail_width/2,
		c.int(bounds.y+52),
		detail_size,
		detail_color,
	)
}

draw_special_node_header :: proc(
	run: ^game.Run_State,
	canvas_width: f32,
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
	rl.DrawRectangle(0, 0, c.int(canvas_width), c.int(SPECIAL_NODE_HEADER_HEIGHT), rl.Color{15, 18, 21, 255})
	rl.DrawText(title, 28, 13, 23, rl.Color{225, 229, 224, 255})
	rl.DrawText(subtitle, 28, 43, 13, special_node_accent(run.phase))
	stats_label := fmt.ctprintf(
			"HP %d/%d    GOLD %d    DECK %d/%d",
			run.player.health,
			run.player.stats.max_health,
			run.player.gold,
			run.player.deck.owned_count,
			game.MAX_OWNED_CARDS,
		)
	stats_size: c.int = 13
	stats_width := rl.MeasureText(stats_label, stats_size)
	rl.DrawText(
		stats_label,
		c.int(canvas_width)-116-stats_width,
		29,
		stats_size,
		rl.Color{151, 163, 158, 255},
	)
}

draw_special_node_result :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
) {
	bounds := special_node_result_bounds(canvas_width, canvas_height)
	accent := special_node_accent(run.phase)
	rl.DrawRectangleRec(bounds, rl.Color{24, 29, 31, 255})
	rl.DrawRectangleLinesEx(bounds, 2, accent)
	rl.DrawText("RESULT", c.int(bounds.x+24), c.int(bounds.y+20), 13, rl.Color{151, 163, 158, 255})

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
				definition, definition_found := game.card_definition_by_id(
					run.player.deck.owned[card_index].definition_id,
				)
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
	result_width := rl.MeasureText(result, result_size)
	rl.DrawText(
		result,
		c.int(bounds.x+bounds.width*0.5)-result_width/2,
		c.int(bounds.y+55),
		result_size,
		accent,
	)
	detail_size: c.int = 14
	detail_width := rl.MeasureText(detail, detail_size)
	rl.DrawText(
		detail,
		c.int(bounds.x+bounds.width*0.5)-detail_width/2,
		c.int(bounds.y+98),
		detail_size,
		rl.Color{225, 229, 224, 255},
	)
}

draw_rest_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State,
) {
	action_count := special_node_action_count(run)
	accent := special_node_accent(run.phase)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
		"RECOVER",
		fmt.ctprintf("UP TO %d HP", run.rest.heal_amount),
		state.primary_hovered,
		special_node_primary_is_enabled(run),
		accent,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		"UPGRADE",
		"SELECTED CARD",
		state.secondary_hovered,
		special_node_secondary_is_enabled(run, state.selected_card_id),
		accent,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 2, action_count),
		"LEAVE",
		"KEEP MOVING",
		state.leave_hovered,
		true,
		accent,
	)

	deck := &run.player.deck
	page_count := special_node_deck_page_count(deck)
	page := special_node_clamp_deck_page(deck, state.page)
	rl.DrawText(
		fmt.ctprintf("OWNED DECK    PAGE %d/%d", page+1, page_count),
		45,
		292,
		13,
		rl.Color{151, 163, 158, 255},
	)
	start, valid_page := special_node_deck_page_start(deck, page)
	assert(valid_page)
	visible_count := special_node_deck_cards_on_page(deck, page)
	for slot in 0..<visible_count {
		card_index := start+slot
		card := deck.owned[card_index]
		if card.id != state.hovered_card_id {
			draw_shop_owned_card(
				run,
				card_index,
				slot,
				canvas_width,
				canvas_height,
				false,
				card.id == state.selected_card_id,
			)
		}
	}
	if hovered_index, found := game.owned_card_index_by_id(deck, state.hovered_card_id);
	   found && hovered_index >= start && hovered_index < start+visible_count {
		draw_shop_owned_card(
			run,
			hovered_index,
			hovered_index-start,
			canvas_width,
			canvas_height,
			true,
			state.hovered_card_id == state.selected_card_id,
		)
	}
	draw_shop_page_button(
		special_node_previous_page_bounds(canvas_width, canvas_height),
		true,
		state.previous_page_hovered,
		page > 0,
	)
	draw_shop_page_button(
		special_node_next_page_bounds(canvas_width, canvas_height),
		false,
		state.next_page_hovered,
		page+1 < page_count,
	)
}

draw_event_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State,
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
		special_node_primary_is_enabled(run),
		accent,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		secondary_title,
		secondary_detail,
		state.secondary_hovered,
		special_node_secondary_is_enabled(run, state.selected_card_id),
		accent,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 2, action_count),
		"LEAVE",
		"WALK AWAY",
		state.leave_hovered,
		true,
		accent,
	)
}

draw_treasure_actions :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State,
) {
	action_count := special_node_action_count(run)
	accent := special_node_accent(run.phase)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 0, action_count),
		"CLAIM",
		fmt.ctprintf("+%d GOLD", run.treasure.gold_amount),
		state.primary_hovered,
		special_node_primary_is_enabled(run),
		accent,
	)
	draw_special_node_action(
		special_node_action_bounds(canvas_width, canvas_height, 1, action_count),
		"LEAVE",
		"DO NOT OPEN",
		state.leave_hovered,
		true,
		accent,
	)
}

draw_special_node_screen :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Special_Node_Render_State = {},
) {
	assert(run != nil && special_node_phase_is_supported(run.phase))
	assert(game.validate_special_node_state(run))
	assert(special_node_canvas_is_supported(canvas_width, canvas_height))
	rl.DrawRectangle(0, 0, c.int(canvas_width), c.int(canvas_height), CANVAS_BACKGROUND)
	draw_special_node_header(run, canvas_width)

	if special_node_is_resolved(run) {
		draw_special_node_result(run, canvas_width, canvas_height)
		draw_shop_button(
			special_node_continue_bounds(canvas_width, canvas_height),
			"CONTINUE",
			state.continue_hovered,
			true,
			special_node_accent(run.phase),
		)
	} else {
		switch run.phase {
		case .Rest:
			draw_rest_actions(run, canvas_width, canvas_height, state)
		case .Event:
			draw_event_actions(run, canvas_width, canvas_height, state)
		case .Treasure:
			draw_treasure_actions(run, canvas_width, canvas_height, state)
		case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		}
	}
	rl.DrawFPS(c.int(canvas_width)-96, 18)
}
