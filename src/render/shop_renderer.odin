package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

SHOP_DECK_CARDS_PER_PAGE :: 8

SHOP_MIN_CANVAS_WIDTH  :: f32(900)
SHOP_MIN_CANVAS_HEIGHT :: f32(520)

SHOP_HEADER_HEIGHT :: f32(64)

SHOP_OFFER_CARD_WIDTH  :: f32(160)
SHOP_OFFER_CARD_HEIGHT :: f32(166)
SHOP_OFFER_CARD_GAP    :: f32(34)
SHOP_OFFER_CARD_TOP    :: f32(78)
SHOP_OFFER_HOVER_RAISE :: f32(8)
SHOP_OFFER_PRICE_GAP   :: f32(4)
SHOP_OFFER_PRICE_HEIGHT :: f32(26)

SHOP_OWNED_CARD_WIDTH  :: f32(100)
SHOP_OWNED_CARD_HEIGHT :: f32(134)
SHOP_OWNED_CARD_GAP    :: f32(10)
SHOP_OWNED_CARD_TOP    :: f32(316)
SHOP_OWNED_HOVER_RAISE :: f32(6)

SHOP_CONTROL_HEIGHT :: f32(36)
SHOP_CONTROL_BOTTOM :: f32(16)
SHOP_PAGE_BUTTON_SIZE :: f32(36)
SHOP_ACTION_BUTTON_WIDTH :: f32(116)
SHOP_CONTINUE_BUTTON_WIDTH :: f32(152)
SHOP_CONTROL_GAP :: f32(12)

Shop_Hit_Kind :: enum {
	None,
	Offer,
	Owned_Card,
	Previous_Page,
	Next_Page,
	Upgrade,
	Remove,
	Continue,
}

Shop_Hit :: struct {
	kind:        Shop_Hit_Kind,
	offer_index: int,
	card_id:     u32,
}

Shop_Render_State :: struct {
	page:                  int,
	has_hovered_offer:     bool,
	hovered_offer_index:   int,
	hovered_card_id:       u32,
	selected_card_id:      u32,
	previous_page_hovered: bool,
	next_page_hovered:     bool,
	upgrade_hovered:       bool,
	remove_hovered:        bool,
	continue_hovered:      bool,
}

shop_canvas_is_supported :: proc(canvas_width, canvas_height: f32) -> bool {
	return canvas_width >= SHOP_MIN_CANVAS_WIDTH && canvas_height >= SHOP_MIN_CANVAS_HEIGHT
}

shop_point_in_bounds :: proc(point: view.Vec2, bounds: rl.Rectangle) -> bool {
	return bounds.width > 0 && bounds.height > 0 && point_in_rectangle(point, bounds)
}

shop_offer_bounds :: proc(
	canvas_width, canvas_height: f32,
	offer_index: int,
	raised: bool = false,
) -> rl.Rectangle {
	if !shop_canvas_is_supported(canvas_width, canvas_height) ||
	   offer_index < 0 || offer_index >= game.SHOP_CARD_OFFER_COUNT {
		return {}
	}
	total_width := SHOP_OFFER_CARD_WIDTH*f32(game.SHOP_CARD_OFFER_COUNT)+
	               SHOP_OFFER_CARD_GAP*f32(game.SHOP_CARD_OFFER_COUNT-1)
	y := SHOP_OFFER_CARD_TOP
	if raised {
		y -= SHOP_OFFER_HOVER_RAISE
	}
	return {
		x = (canvas_width-total_width)*0.5+
		    f32(offer_index)*(SHOP_OFFER_CARD_WIDTH+SHOP_OFFER_CARD_GAP),
		y = y,
		width = SHOP_OFFER_CARD_WIDTH,
		height = SHOP_OFFER_CARD_HEIGHT,
	}
}

shop_offer_price_bounds :: proc(
	canvas_width, canvas_height: f32,
	offer_index: int,
	raised: bool = false,
) -> rl.Rectangle {
	card := shop_offer_bounds(canvas_width, canvas_height, offer_index, raised)
	if card.width <= 0 || card.height <= 0 {
		return {}
	}
	return {
		x = card.x,
		y = card.y+card.height+SHOP_OFFER_PRICE_GAP,
		width = card.width,
		height = SHOP_OFFER_PRICE_HEIGHT,
	}
}

shop_offer_contains :: proc(
	canvas_width, canvas_height: f32,
	offer_index: int,
	point: view.Vec2,
	raised: bool = false,
) -> bool {
	return shop_point_in_bounds(
		point,
		shop_offer_bounds(canvas_width, canvas_height, offer_index, raised),
	) || shop_point_in_bounds(
		point,
		shop_offer_price_bounds(canvas_width, canvas_height, offer_index, raised),
	)
}

shop_offer_at_point :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	point: view.Vec2,
	raised_offer_index: int = -1,
) -> (offer_index: int, found: bool) {
	offers := game.available_shop_offers(run)
	if len(offers) != game.SHOP_CARD_OFFER_COUNT ||
	   !shop_canvas_is_supported(canvas_width, canvas_height) {
		return 0, false
	}
	if raised_offer_index >= 0 && raised_offer_index < len(offers) &&
	   shop_offer_contains(canvas_width, canvas_height, raised_offer_index, point, true) {
		return raised_offer_index, true
	}
	for index in 0..<len(offers) {
		if shop_offer_contains(canvas_width, canvas_height, index, point) {
			return index, true
		}
	}
	return 0, false
}

shop_deck_page_count :: proc(deck: ^game.Deck_State) -> int {
	if deck == nil || deck.owned_count <= 0 || deck.owned_count > game.MAX_OWNED_CARDS {
		return 0
	}
	return (deck.owned_count+SHOP_DECK_CARDS_PER_PAGE-1)/SHOP_DECK_CARDS_PER_PAGE
}

shop_deck_page_is_valid :: proc(deck: ^game.Deck_State, page: int) -> bool {
	return page >= 0 && page < shop_deck_page_count(deck)
}

shop_clamp_deck_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	page_count := shop_deck_page_count(deck)
	if page_count <= 0 {
		return 0
	}
	return clamp(page, 0, page_count-1)
}

shop_deck_page_start :: proc(deck: ^game.Deck_State, page: int) -> (int, bool) {
	if !shop_deck_page_is_valid(deck, page) {
		return 0, false
	}
	return page*SHOP_DECK_CARDS_PER_PAGE, true
}

shop_deck_cards_on_page :: proc(deck: ^game.Deck_State, page: int) -> int {
	start, ok := shop_deck_page_start(deck, page)
	if !ok {
		return 0
	}
	return min(SHOP_DECK_CARDS_PER_PAGE, deck.owned_count-start)
}

shop_owned_card_bounds :: proc(
	canvas_width, canvas_height: f32,
	page_slot: int,
	raised: bool = false,
) -> rl.Rectangle {
	if !shop_canvas_is_supported(canvas_width, canvas_height) ||
	   page_slot < 0 || page_slot >= SHOP_DECK_CARDS_PER_PAGE {
		return {}
	}
	total_width := SHOP_OWNED_CARD_WIDTH*f32(SHOP_DECK_CARDS_PER_PAGE)+
	               SHOP_OWNED_CARD_GAP*f32(SHOP_DECK_CARDS_PER_PAGE-1)
	y := SHOP_OWNED_CARD_TOP
	if raised {
		y -= SHOP_OWNED_HOVER_RAISE
	}
	return {
		x = (canvas_width-total_width)*0.5+
		    f32(page_slot)*(SHOP_OWNED_CARD_WIDTH+SHOP_OWNED_CARD_GAP),
		y = y,
		width = SHOP_OWNED_CARD_WIDTH,
		height = SHOP_OWNED_CARD_HEIGHT,
	}
}

shop_owned_card_at_point :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	page: int,
	point: view.Vec2,
	raised_card_id: u32 = 0,
) -> (card_id: u32, found: bool) {
	if run == nil || run.phase != .Shop || !game.validate_shop_state(run) ||
	   !shop_canvas_is_supported(canvas_width, canvas_height) {
		return 0, false
	}
	deck := &run.player.deck
	start, valid_page := shop_deck_page_start(deck, page)
	if !valid_page {
		return 0, false
	}
	visible_count := shop_deck_cards_on_page(deck, page)
	if raised_card_id != 0 {
		if raised_index, raised_found := game.owned_card_index_by_id(deck, raised_card_id);
		   raised_found && raised_index >= start && raised_index < start+visible_count {
			slot := raised_index-start
			if point_in_rectangle(point, shop_owned_card_bounds(canvas_width, canvas_height, slot, true)) {
				return raised_card_id, true
			}
		}
	}
	for slot := visible_count-1; slot >= 0; slot -= 1 {
		if point_in_rectangle(point, shop_owned_card_bounds(canvas_width, canvas_height, slot)) {
			return deck.owned[start+slot].id, true
		}
	}
	return 0, false
}

shop_previous_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !shop_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return {
		x = 32,
		y = canvas_height-SHOP_CONTROL_BOTTOM-SHOP_PAGE_BUTTON_SIZE,
		width = SHOP_PAGE_BUTTON_SIZE,
		height = SHOP_PAGE_BUTTON_SIZE,
	}
}

shop_next_page_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	previous := shop_previous_page_bounds(canvas_width, canvas_height)
	if previous.width <= 0 {
		return {}
	}
	return {
		x = previous.x+previous.width+8,
		y = previous.y,
		width = previous.width,
		height = previous.height,
	}
}

shop_continue_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if !shop_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	return {
		x = canvas_width-32-SHOP_CONTINUE_BUTTON_WIDTH,
		y = canvas_height-SHOP_CONTROL_BOTTOM-SHOP_CONTROL_HEIGHT,
		width = SHOP_CONTINUE_BUTTON_WIDTH,
		height = SHOP_CONTROL_HEIGHT,
	}
}

shop_remove_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	continue_bounds := shop_continue_bounds(canvas_width, canvas_height)
	if continue_bounds.width <= 0 {
		return {}
	}
	return {
		x = continue_bounds.x-SHOP_CONTROL_GAP-SHOP_ACTION_BUTTON_WIDTH,
		y = continue_bounds.y,
		width = SHOP_ACTION_BUTTON_WIDTH,
		height = SHOP_CONTROL_HEIGHT,
	}
}

shop_upgrade_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	remove_bounds := shop_remove_bounds(canvas_width, canvas_height)
	if remove_bounds.width <= 0 {
		return {}
	}
	return {
		x = remove_bounds.x-SHOP_CONTROL_GAP-SHOP_ACTION_BUTTON_WIDTH,
		y = remove_bounds.y,
		width = SHOP_ACTION_BUTTON_WIDTH,
		height = SHOP_CONTROL_HEIGHT,
	}
}

shop_previous_page_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return shop_point_in_bounds(point, shop_previous_page_bounds(canvas_width, canvas_height))
}

shop_next_page_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return shop_point_in_bounds(point, shop_next_page_bounds(canvas_width, canvas_height))
}

shop_upgrade_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return shop_point_in_bounds(point, shop_upgrade_bounds(canvas_width, canvas_height))
}

shop_remove_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return shop_point_in_bounds(point, shop_remove_bounds(canvas_width, canvas_height))
}

shop_continue_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return shop_point_in_bounds(point, shop_continue_bounds(canvas_width, canvas_height))
}

shop_hit_test :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	page: int,
	point: view.Vec2,
	raised_offer_index: int = -1,
	raised_card_id: u32 = 0,
) -> Shop_Hit {
	if run == nil || run.phase != .Shop || !game.validate_shop_state(run) {
		return {}
	}
	if !shop_canvas_is_supported(canvas_width, canvas_height) {
		return {}
	}
	clamped_page := shop_clamp_deck_page(&run.player.deck, page)
	if offer_index, found := shop_offer_at_point(
		run,
		canvas_width,
		canvas_height,
		point,
		raised_offer_index,
	); found {
		return {kind = .Offer, offer_index = offer_index}
	}
	if card_id, found := shop_owned_card_at_point(
		run,
		canvas_width,
		canvas_height,
		clamped_page,
		point,
		raised_card_id,
	); found {
		return {kind = .Owned_Card, card_id = card_id}
	}
	if clamped_page > 0 && shop_previous_page_at_point(canvas_width, canvas_height, point) {
		return {kind = .Previous_Page}
	}
	if clamped_page+1 < shop_deck_page_count(&run.player.deck) &&
	   shop_next_page_at_point(canvas_width, canvas_height, point) {
		return {kind = .Next_Page}
	}
	if shop_upgrade_at_point(canvas_width, canvas_height, point) {
		return {kind = .Upgrade}
	}
	if shop_remove_at_point(canvas_width, canvas_height, point) {
		return {kind = .Remove}
	}
	if shop_continue_at_point(canvas_width, canvas_height, point) {
		return {kind = .Continue}
	}
	return {}
}

shop_rarity_color :: proc(rarity: game.Card_Rarity) -> rl.Color {
	switch rarity {
	case .Common:
		return rl.Color{178, 189, 185, 255}
	case .Uncommon:
		return rl.Color{91, 204, 195, 255}
	case .Rare:
		return rl.Color{246, 207, 92, 255}
	case .Count:
	}
	return rl.Color{105, 116, 116, 255}
}

draw_shop_offer :: proc(
	run: ^game.Run_State,
	offer_index: int,
	canvas_width, canvas_height: f32,
	raised: bool, theme: ^Renderer = nil,
) {
	assert(run != nil && offer_index >= 0 && offer_index < run.shop.offer_count)
	offer := run.shop.offers[offer_index]
	definition, found := game.card_definition_by_id(offer.definition_id, menu_themed(theme))
	assert(found)
	enabled := game.shop_offer_can_be_bought(run, offer_index)
	preview := game.Card_Instance{definition_id = offer.definition_id}
	menu_card_face(theme,
		shop_offer_bounds(canvas_width, canvas_height, offer_index, raised),
		preview,
		definition,
		offer_index,
		enabled,
		true,
		raised,
		false,
	)

	price_bounds := shop_offer_price_bounds(canvas_width, canvas_height, offer_index, raised)
	price_fill := rl.Color{24, 29, 31, 255}
	price_outline := shop_rarity_color(definition.rarity)
	if !enabled {
		price_fill = rl.Color{31, 33, 35, 255}
		price_outline = rl.Color{88, 94, 95, 255}
	}
	menu_rectangle_rec(theme, price_bounds, price_fill)
	menu_outline(theme, price_bounds, 1, price_outline)
	price_label := fmt.ctprintf("%s   %d GOLD", game.card_rarity_name(definition.rarity), offer.price)
	if offer.sold {
		price_label = "SOLD"
	}
	font_size: c.int = 12
	label_width := menu_measure_text(theme, price_label, font_size)
	menu_text(theme,
		price_label,
		c.int(price_bounds.x+price_bounds.width*0.5)-label_width/2,
		c.int(price_bounds.y+7),
		font_size,
		price_outline,
	)
	if offer.sold {
		card_bounds := shop_offer_bounds(canvas_width, canvas_height, offer_index, raised)
		overlay := rl.Rectangle{
			x = card_bounds.x,
			y = card_bounds.y+card_bounds.height*0.42,
			width = card_bounds.width,
			height = 36,
		}
		menu_rectangle_rec(theme, overlay, rl.Color{12, 15, 18, 225})
		sold_width := menu_measure_text(theme, "SOLD", 18)
		menu_text(theme,
			"SOLD",
			c.int(overlay.x+overlay.width*0.5)-sold_width/2,
			c.int(overlay.y+9),
			18,
			rl.Color{224, 99, 86, 255},
		)
	}
}

draw_shop_owned_card :: proc(
	run: ^game.Run_State,
	card_index, page_slot: int,
	canvas_width, canvas_height: f32,
	raised, selected: bool, theme: ^Renderer = nil,
) {
	assert(run != nil && card_index >= 0 && card_index < run.player.deck.owned_count)
	card := run.player.deck.owned[card_index]
	definition, found := game.card_definition_by_id(card.definition_id, menu_themed(theme))
	assert(found)
	bounds := shop_owned_card_bounds(canvas_width, canvas_height, page_slot, raised)
	fill, outline := card_colors(card.definition_id, true)
	menu_rectangle_rec(theme, {bounds.x+3, bounds.y+4, bounds.width, bounds.height}, rl.Color{5, 7, 9, 150})
	menu_rectangle_rec(theme, bounds, fill)
	menu_outline(theme, bounds, 2, outline)
	if raised || selected {
		highlight_bounds := rl.Rectangle{bounds.x-2, bounds.y-2, bounds.width+4, bounds.height+4}
		highlight_color := rl.Color{247, 239, 213, 255} if raised else rl.Color{169, 210, 216, 255}
		menu_outline(theme, highlight_bounds, 2, highlight_color)
	}

	badge_center := rl.Vector2{bounds.x+14, bounds.y+15}
	menu_circle(theme, badge_center, 9, rl.Color{12, 16, 19, 245})
	menu_circle_lines(theme, badge_center, 9, outline)
	cost_text := fmt.ctprintf("%d", definition.cost)
	cost_width := menu_measure_text(theme, cost_text, 11)
	menu_text(theme, cost_text, c.int(badge_center.x)-cost_width/2, c.int(badge_center.y)-6, 11, outline)

	name := card_short_name(card.definition_id)
	name_width := menu_measure_text(theme, name, 11)
	name_x := c.int(bounds.x+31)
	maximum_name_x := c.int(bounds.x+bounds.width-7)-name_width
	menu_text(theme, name, min(name_x, maximum_name_x), c.int(bounds.y+9), 11, rl.Color{237, 239, 232, 255})
	if menu_themed(theme) {
		icon := gothic_card_icon(card.definition_id)
		gothic_atlas_icon(theme.tactical.art.icons, theme.tactical.art.icon_sources[icon],
			{bounds.x+18, bounds.y+37, bounds.width-36, 66})
	} else { draw_card_sigil(bounds, card.definition_id, outline) }
	if card.upgrade_level > 0 {
		menu_text(theme,
			fmt.ctprintf("+%d", card.upgrade_level),
			c.int(bounds.x+7),
			c.int(bounds.y+bounds.height-17),
			11,
			outline,
		)
	}
}

draw_shop_button :: proc(
	bounds: rl.Rectangle,
	label: cstring,
	hovered, enabled: bool,
	accent: rl.Color, theme: ^Renderer = nil,
) {
	fill := rl.Color{31, 36, 39, 255}
	outline := rl.Color{105, 116, 116, 255}
	label_color := rl.Color{225, 229, 224, 255}
	if !enabled {
		fill = rl.Color{25, 28, 30, 255}
		outline = rl.Color{67, 73, 74, 255}
		label_color = rl.Color{101, 108, 107, 255}
	} else if hovered {
		fill = rl.Color{50, 56, 58, 255}
		outline = accent
		label_color = accent
	}
	menu_rectangle_rec(theme, bounds, fill)
	menu_outline(theme, bounds, 2, outline)
	font_size: c.int = 13
	label_width := menu_measure_text(theme, label, font_size)
	menu_text(theme,
		label,
		c.int(bounds.x+bounds.width*0.5)-label_width/2,
		c.int(bounds.y+bounds.height*0.5)-font_size/2,
		font_size,
		label_color,
	)
}

draw_shop_page_button :: proc(bounds: rl.Rectangle, previous, hovered, enabled: bool, theme: ^Renderer = nil) {
	fill := rl.Color{31, 36, 39, 255}
	outline := rl.Color{105, 116, 116, 255}
	icon := rl.Color{225, 229, 224, 255}
	if !enabled {
		fill = rl.Color{25, 28, 30, 255}
		outline = rl.Color{67, 73, 74, 255}
		icon = rl.Color{91, 98, 98, 255}
	} else if hovered {
		outline = rl.Color{246, 207, 92, 255}
		icon = outline
	}
	menu_rectangle_rec(theme, bounds, fill)
	menu_outline(theme, bounds, 2, outline)
	center := rl.Vector2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
	direction: f32 = 1
	if previous {
		direction = -1
	}
	menu_triangle(theme,
		{center.x+direction*6, center.y},
		{center.x-direction*4, center.y-7},
		{center.x-direction*4, center.y+7},
		icon,
	)
}

draw_shop_screen :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	state: Shop_Render_State = {}, theme: ^Renderer = nil,
) {
	assert(run != nil && run.phase == .Shop && game.validate_shop_state(run))
	assert(shop_canvas_is_supported(canvas_width, canvas_height))
	page_count := shop_deck_page_count(&run.player.deck)
	page := shop_clamp_deck_page(&run.player.deck, state.page)

	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(canvas_height), CANVAS_BACKGROUND)
	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(SHOP_HEADER_HEIGHT), rl.Color{15, 18, 21, 255})
	menu_text(theme, "SHOP", 28, 13, 23, rl.Color{225, 229, 224, 255})
	menu_text(theme,
		fmt.ctprintf(
			"GOLD %d    DECK %d/%d",
			run.player.gold,
			run.player.deck.owned_count,
			game.MAX_OWNED_CARDS,
		),
		28,
		40,
		14,
		rl.Color{151, 163, 158, 255},
	)
	menu_text(theme, "CARD OFFERS", 206, 48, 12, rl.Color{137, 148, 145, 255})

	for index in 0..<run.shop.offer_count {
		if !state.has_hovered_offer || index != state.hovered_offer_index {
			draw_shop_offer(run, index, canvas_width, canvas_height, false, theme = theme)
		}
	}
	if state.has_hovered_offer && state.hovered_offer_index >= 0 &&
	   state.hovered_offer_index < run.shop.offer_count {
		draw_shop_offer(run, state.hovered_offer_index, canvas_width, canvas_height, true, theme = theme)
	}

	deck_label := fmt.ctprintf("OWNED DECK    PAGE %d/%d", page+1, page_count)
	menu_text(theme, deck_label, 45, 292, 13, rl.Color{151, 163, 158, 255})
	start, valid_page := shop_deck_page_start(&run.player.deck, page)
	assert(valid_page)
	visible_count := shop_deck_cards_on_page(&run.player.deck, page)
	for slot in 0..<visible_count {
		card_index := start+slot
		card := run.player.deck.owned[card_index]
		if card.id != state.hovered_card_id {
			draw_shop_owned_card(
				run,
				card_index,
				slot,
				canvas_width,
				canvas_height,
				false,
				card.id == state.selected_card_id,
			 theme = theme)
		}
	}
	if hovered_index, found := game.owned_card_index_by_id(
		&run.player.deck,
		state.hovered_card_id,
	); found && hovered_index >= start && hovered_index < start+visible_count {
		draw_shop_owned_card(
			run,
			hovered_index,
			hovered_index-start,
			canvas_width,
			canvas_height,
			true,
			state.hovered_card_id == state.selected_card_id,
		 theme = theme)
	}

	previous_enabled := page > 0
	next_enabled := page+1 < page_count
	draw_shop_page_button(
		shop_previous_page_bounds(canvas_width, canvas_height),
		true,
		state.previous_page_hovered,
		previous_enabled,
		theme = theme,
	)
	draw_shop_page_button(
		shop_next_page_bounds(canvas_width, canvas_height),
		false,
		state.next_page_hovered,
		next_enabled,
		theme = theme,
	)

	selected_id := state.selected_card_id
	selected_index, selected_found := game.owned_card_index_by_id(&run.player.deck, selected_id)
	if selected_found {
		menu_text(theme, card_upgrade_preview(run.player.deck.owned[selected_index], menu_themed(theme)), 45, 454, 12,
			rl.Color{169, 183, 177, 255})
	}
	upgrade_label: cstring = "UPGRADE"
	upgrade_enabled := false
	if run.shop.upgrade_used {
		upgrade_label = "UPGRADE USED"
	} else if selected_found {
		if price, found := game.shop_upgrade_price(run, selected_id); found {
			upgrade_label = fmt.ctprintf("UPGRADE %dG", price)
			upgrade_enabled = game.shop_upgrade_can_be_bought(run, selected_id)
		} else {
			upgrade_label = "UNAVAILABLE"
		}
	}
	remove_label: cstring = "REMOVE"
	remove_enabled := false
	if run.shop.removal_used {
		remove_label = "REMOVE USED"
	} else if selected_found {
		if price, found := game.shop_removal_price(run); found {
			remove_label = fmt.ctprintf("REMOVE %dG", price)
			remove_enabled = game.shop_removal_can_be_bought(run, selected_id)
		}
	}
	draw_shop_button(
		shop_upgrade_bounds(canvas_width, canvas_height),
		upgrade_label,
		state.upgrade_hovered,
		upgrade_enabled,
		rl.Color{91, 204, 195, 255},
		theme = theme,
	)
	draw_shop_button(
		shop_remove_bounds(canvas_width, canvas_height),
		remove_label,
		state.remove_hovered,
		remove_enabled,
		rl.Color{224, 99, 86, 255},
		theme = theme,
	)
	draw_shop_button(
		shop_continue_bounds(canvas_width, canvas_height),
		"CONTINUE",
		state.continue_hovered,
		true,
		rl.Color{246, 207, 92, 255},
		theme = theme,
	)

}
