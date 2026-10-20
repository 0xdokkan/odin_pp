package render

import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

// MOSTRA EFFETTO's buttons on the run's screens (src/effect_window.odin opens
// the window from them): one under each card of the reward and of the shop,
// and one in the controls row of the shop and of the rest for the owned card
// chosen there; the sheet's MAZZO and the card inspector have their own
// (character_sheet.odin, tactical_hand.odin). Each stands clear of every card
// (raised too), price, label and control, so that a click on it never picks,
// buys or turns a page. A renderer must be available to open the film;
// text-only resource fallbacks do not draw effect buttons.

EFFECT_ENTRY_LABEL : cstring : "MOSTRA EFFETTO"
// The key that shows the card a screen has chosen: the inspector's, the
// sheet's line, the owned card chosen in the shop or at the rest, the reward
// under the mouse.
EFFECT_ENTRY_KEY : cstring : "I"

REWARD_EFFECT_GAP :: f32(10)
REWARD_EFFECT_HEIGHT :: f32(26)

// Under each reward card: clear of the card, raised too, and of PASSA.
reward_effect_bounds :: proc(canvas_width, canvas_height: f32, card_index, card_count: int) -> rl.Rectangle {
	card := reward_card_bounds(canvas_width, canvas_height, card_index, card_count)
	if card.width <= 0 { return {} }
	return {card.x, card.y+card.height+REWARD_EFFECT_GAP, card.width, REWARD_EFFECT_HEIGHT}
}

reward_effect_at_point :: proc(run: ^game.Run_State, canvas_width, canvas_height: f32, point: view.Vec2) -> (card_index: int, found: bool) {
	choices := game.available_card_rewards(run)
	for index in 0..<len(choices) {
		if point_in_rectangle(point, reward_effect_bounds(canvas_width, canvas_height, index, len(choices))) { return index, true }
	}
	return
}

SHOP_OFFER_EFFECT_INSET :: f32(20)
SHOP_OFFER_EFFECT_GAP :: f32(4)
SHOP_OFFER_EFFECT_HEIGHT :: f32(20)

// Under each offer's price and narrower: clear of the card (raised too), of
// the price and of the owned deck's label at the left (draw_shop_screen).
shop_offer_effect_bounds :: proc(canvas_width, canvas_height: f32, offer_index: int) -> rl.Rectangle {
	price := shop_offer_price_bounds(canvas_width, canvas_height, offer_index)
	if price.width <= 0 { return {} }
	return {price.x+SHOP_OFFER_EFFECT_INSET, price.y+price.height+SHOP_OFFER_EFFECT_GAP, price.width-2*SHOP_OFFER_EFFECT_INSET,
		SHOP_OFFER_EFFECT_HEIGHT}
}

shop_offer_effect_at_point :: proc(run: ^game.Run_State, canvas_width, canvas_height: f32, point: view.Vec2) -> (offer_index: int, found: bool) {
	if run == nil || run.phase != .Shop || !game.validate_shop_state(run) { return }
	for index in 0..<run.shop.offer_count {
		if shop_point_in_bounds(point, shop_offer_effect_bounds(canvas_width, canvas_height, index)) { return index, true }
	}
	return
}

OWNED_CARD_EFFECT_WIDTH :: f32(152)

// The chosen owned card's, in the controls row of the shop and of the rest: at
// the left of UPGRADE, as far from it as the row's buttons are from one
// another, well clear of the page buttons.
owned_card_effect_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	upgrade := shop_upgrade_bounds(canvas_width, canvas_height)
	if upgrade.width <= 0 { return {} }
	return {upgrade.x-SHOP_CONTROL_GAP-OWNED_CARD_EFFECT_WIDTH, upgrade.y, OWNED_CARD_EFFECT_WIDTH, upgrade.height}
}

// A MOSTRA EFFETTO button under a card of the run's screens, on the game's
// board only.
@(private)
draw_effect_entry_button :: proc(theme: ^Renderer, bounds: rl.Rectangle, enabled: bool = true) {
	if !menu_themed(theme) || bounds.width <= 0 { return }
	hud_button(theme, bounds, nil, EFFECT_ENTRY_LABEL, enabled)
}

// The owned card's, in the controls row of the shop and of the rest: one of
// the row's own buttons, its key in its words (as the relic choice's S  PASSA).
EFFECT_ENTRY_OWNED_LABEL : cstring : "I  MOSTRA EFFETTO"
@(private)
draw_owned_card_effect_button :: proc(theme: ^Renderer, canvas_width, canvas_height: f32, enabled: bool) {
	bounds := owned_card_effect_bounds(canvas_width, canvas_height)
	if !menu_themed(theme) || bounds.width <= 0 { return }
	draw_shop_button(bounds, EFFECT_ENTRY_OWNED_LABEL, enabled && hud_hovered(theme, bounds), enabled, {172, 219, 222, 255}, theme = theme)
}

// hud_button's own layout for a one-letter key: its cap, and the room its
// label has with a key or without (the fit checks and the inspector's hint).
@(private)
effect_entry_key_bounds :: proc(bounds: rl.Rectangle) -> rl.Rectangle {
	return {bounds.x+4, bounds.y+4, 20, bounds.height-8}
}

effect_entry_label_bounds :: proc(bounds: rl.Rectangle, key: bool) -> rl.Rectangle {
	left := bounds.x+7
	if key { cap := effect_entry_key_bounds(bounds); left = cap.x+cap.width+7 }
	return {left, bounds.y+(bounds.height-17)*0.5, bounds.x+bounds.width-left-6, 18}
}
