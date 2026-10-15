package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import level "../level"

effect_entry_inside :: proc(bounds: rl.Rectangle, width, height: f32) -> bool {
	return bounds.width > 0 && bounds.height > 0 && bounds.x >= 0 && bounds.y >= 0 && bounds.x+bounds.width <= width && bounds.y+bounds.height <= height
}

// MOSTRA EFFETTO's buttons on the reward and the shop stand on the canvas,
// clear of every card (raised too), price, label and control, so that a click
// on one never picks, buys or turns a page; the shop's and the rest's for the
// owned card chosen sits in their controls row, clear of its buttons and of
// the upgrade's preview line; the hit tests find each one.
@(test)
test_effect_buttons_stand_clear_of_cards_prices_and_controls :: proc(t: ^testing.T) {
	for count in 1..=game.CARD_REWARD_CHOICE_COUNT {
		for index in 0..<count {
			b := reward_effect_bounds(960, 540, index, count)
			testing.expect(t, effect_entry_inside(b, 960, 540))
			for other in 0..<count {
				testing.expect(t, !rectangles_overlap(b, reward_card_bounds(960, 540, other, count)))
				testing.expect(t, !rectangles_overlap(b, reward_card_bounds(960, 540, other, count, true)))
				if other != index { testing.expect(t, !rectangles_overlap(b, reward_effect_bounds(960, 540, other, count))) }
			}
			testing.expect(t, !rectangles_overlap(b, reward_skip_bounds(960, 540)))
		}
	}
	run := create_shop_render_test_run(t)
	defer game.destroy_run(&run)
	// The owned deck's label "OWNED DECK    PAGE n/m" at (45, 292): 166 px
	// wide in the game's font at 13 (the smoke measures it again).
	label := rl.Rectangle{45, 292, 170, 18}
	owned := owned_card_effect_bounds(960, 540)
	controls := [?]rl.Rectangle{shop_previous_page_bounds(960, 540), shop_next_page_bounds(960, 540), shop_upgrade_bounds(960, 540),
		shop_remove_bounds(960, 540), shop_continue_bounds(960, 540)}
	for index in 0..<game.SHOP_CARD_OFFER_COUNT {
		b := shop_offer_effect_bounds(960, 540, index)
		testing.expect(t, effect_entry_inside(b, 960, 540))
		testing.expect(t, !rectangles_overlap(b, label))
		for other in 0..<game.SHOP_CARD_OFFER_COUNT {
			for raised in ([2]bool{false, true}) {
				testing.expect(t, !rectangles_overlap(b, shop_offer_bounds(960, 540, other, raised)))
				testing.expect(t, !rectangles_overlap(b, shop_offer_price_bounds(960, 540, other, raised)))
			}
			if other != index { testing.expect(t, !rectangles_overlap(b, shop_offer_effect_bounds(960, 540, other))) }
		}
		for slot in 0..<SHOP_DECK_CARDS_PER_PAGE {
			for raised in ([2]bool{false, true}) { testing.expect(t, !rectangles_overlap(b, shop_owned_card_bounds(960, 540, slot, raised))) }
		}
		for control in controls { testing.expect(t, !rectangles_overlap(b, control)) }
		found, hit := shop_offer_effect_at_point(&run, 960, 540, rectangle_center(b))
		testing.expect(t, hit && found == index)
		// The shop's own hit test sees nothing there: the click is the window's alone.
		testing.expect_value(t, shop_hit_test(&run, 960, 540, 0, rectangle_center(b)).kind, Shop_Hit_Kind.None)
	}
	testing.expect(t, effect_entry_inside(owned, 960, 540))
	for control in controls { testing.expect(t, !rectangles_overlap(owned, control)) }
	for slot in 0..<SHOP_DECK_CARDS_PER_PAGE {
		for raised in ([2]bool{false, true}) { testing.expect(t, !rectangles_overlap(owned, shop_owned_card_bounds(960, 540, slot, raised))) }
	}
	// The preview line of the card chosen (45, 454, 12 px).
	testing.expect(t, !rectangles_overlap(owned, {45, 454, 400, 16}))
	testing.expect_value(t, shop_hit_test(&run, 960, 540, 0, rectangle_center(owned)).kind, Shop_Hit_Kind.None)
	// The rest's controls row: its page buttons, the same.
	rest := create_special_node_render_test_run(t, .Rest)
	defer game.destroy_run(&rest)
	testing.expect_value(t, special_node_hit_test(&rest, 960, 540, 0, rectangle_center(owned)).kind, Special_Node_Hit_Kind.None)
	for action in 0..<special_node_action_count(&rest) {
		testing.expect(t, !rectangles_overlap(owned, special_node_action_bounds(960, 540, action, special_node_action_count(&rest))))
	}
}

// The sheet's MAZZO: a line for each card and level of the deck in the order
// the deck holds them, a page at a time, its button in the section's head
// clear of the title, of the sheet's CHIUDI and of every line; the pager's
// arrows only with more than a page.
@(test)
test_character_sheet_deck_lines_group_by_card_and_level_and_page :: proc(t: ^testing.T) {
	rows := [?]string{"#####", "#@.>#", "#####"}
	data, error, _ := level.from_ascii(rows[:])
	testing.expect_value(t, error, level.Parse_Error.None)
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 10, attack = 2, defense = 1})
	testing.expect(t, created)
	testing.expect(t, game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 7))
	cards := [?]struct{id: game.Card_Id, level: i32}{{.Strike, 0}, {.Guard, 0}, {.Strike, 0}, {.Strike, 1}, {.Pinball, 2}, {.Guard, 0},
		{.Lasso, 0}, {.Deflect, 0}, {.Coffin, 1}}
	for card in cards {
		_, added := game.add_owned_card(&player.deck, card.id, card.level)
		testing.expect(t, added)
	}
	room := game.Room{player = &player, level_data = &data}
	renderer := Renderer{canvas_width = 960, canvas_height = 540}
	renderer.tactical.enabled = true
	layout := character_sheet_deck_layout(&renderer, &room, 0)
	testing.expect_value(t, layout.row_count, 7)
	expected := [?]struct{id: game.Card_Id, level: i32, count: int}{{.Strike, 0, 2}, {.Guard, 0, 2}, {.Strike, 1, 1}, {.Pinball, 2, 1},
		{.Lasso, 0, 1}, {.Deflect, 0, 1}, {.Coffin, 1, 1}}
	for row, index in expected {
		testing.expect(t, layout.rows[index].card.definition_id == row.id && layout.rows[index].card.upgrade_level == row.level &&
			layout.rows[index].count == row.count)
	}
	testing.expect_value(t, character_sheet_deck_row_text(layout.rows[3]), cstring("1x Pinball +2"))
	testing.expect(t, layout.pages > 1 && layout.per_page >= 3)
	last := character_sheet_deck_layout(&renderer, &room, 99)
	testing.expect_value(t, last.page, last.pages-1)
	first, count := character_sheet_deck_page_rows(&last)
	testing.expect(t, first+count == last.row_count && count > 0)
	s := layout.section
	testing.expect(t, effect_entry_inside(layout.button, 960, 540) && layout.button.x >= s.x && layout.button.x+layout.button.width <= s.x+s.width)
	testing.expect(t, layout.button.x > s.x+90, "clear of the section's title")
	testing.expect(t, !rectangles_overlap(layout.button, m8_modal_control_bounds(&renderer, .Close_Character)))
	for slot in 0..<layout.per_page {
		row := character_sheet_deck_row_bounds(&layout, slot)
		testing.expect(t, row.y >= layout.button.y+layout.button.height && row.y+row.height <= layout.previous.y)
		testing.expect(t, !rectangles_overlap(row, layout.previous) && !rectangles_overlap(row, layout.next))
		found, hit := character_sheet_deck_row_at(&layout, rectangle_center(row))
		testing.expect(t, hit && found == slot)
	}
	testing.expect(t, !rectangles_overlap(layout.previous, layout.next))
	relics := character_sheet_frame(&renderer).relics
	testing.expect(t, !rectangles_overlap(relics, s) && relics.width > 200 && s.width > 200)
	// One page: no pager, every line shown.
	small := game.Room{player = &player, level_data = &data}
	game.finish_deck_combat(&player.deck)
	testing.expect(t, game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 7))
	_, added := game.add_owned_card(&player.deck, .Strike)
	testing.expect(t, added)
	one := character_sheet_deck_layout(&renderer, &small, 3)
	testing.expect(t, one.row_count == 1 && one.pages == 1 && one.page == 0)
}

// The inspector's MOSTRA EFFETTO follows what it shows: the key's hint for a
// card under the mouse, the button for the card chosen (the hovered one wins,
// as in the drawing), none for a card dragged, behind the player's eyes, on a
// showcase board or outside a fight; once the room is cleared the Canna da
// Pesca in its slot. Only the button is no cell of the board.
@(test)
test_inspector_effect_follows_the_inspector :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#@....#", "#..>..#", "#.....#", "#######"}
	data, error, _ := level.from_ascii(rows[:])
	testing.expect_value(t, error, level.Parse_Error.None)
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 10, attack = 2, defense = 1})
	testing.expect(t, created && game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 2, max_energy = 3, energy_regen_per_pulse = 1}, 9))
	for id in ([3]game.Card_Id{.Strike, .Guard, .Fishing_Rod}) {
		_, added := game.add_owned_card(&player.deck, id)
		testing.expect(t, added)
	}
	spawns := [?]game.Enemy_Spawn{{position = {5, 3}, health = 30, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled = true
	testing.expect_value(t, player.deck.hand_count, 2)
	first, second := player.deck.hand[0], player.deck.hand[1]
	button := tactical_inspector_effect_bounds()
	at := rectangle_center(button)
	card, effect := tactical_inspector_effect(renderer, &room, first.id, 0, 0)
	testing.expect(t, effect == .Hint && card == first)
	testing.expect(t, !tactical_inspector_effect_contains(renderer, &room, first.id, 0, 0, at), "a hint is no button")
	card, effect = tactical_inspector_effect(renderer, &room, 0, second.id, 0)
	testing.expect(t, effect == .Button && card == second)
	testing.expect(t, tactical_inspector_effect_contains(renderer, &room, 0, second.id, 0, at))
	testing.expect(t, !tactical_inspector_effect_contains(renderer, &room, 0, second.id, 0, {at.x, at.y+40}))
	card, effect = tactical_inspector_effect(renderer, &room, first.id, second.id, 0)
	testing.expect(t, effect == .Hint && card == first, "the card under the mouse is the one shown")
	card, effect = tactical_inspector_effect(renderer, &room, second.id, second.id, 0)
	testing.expect(t, effect == .Button && card == second)
	_, effect = tactical_inspector_effect(renderer, &room, 0, second.id, second.id)
	testing.expect_value(t, effect, Inspector_Effect.None)
	renderer.tactical.showcase = true
	_, effect = tactical_inspector_effect(renderer, &room, 0, second.id, 0)
	testing.expect_value(t, effect, Inspector_Effect.None)
	renderer.tactical.showcase = false
	room.first_person.active = true
	_, effect = tactical_inspector_effect(renderer, &room, 0, second.id, 0)
	testing.expect_value(t, effect, Inspector_Effect.None)
	room.first_person.active = false
	// The button stands dimmed while the board is busy: a defence, a cast,
	// Movimento Ombra, an action still showing.
	testing.expect(t, tactical_inspector_effect_ready(renderer, &room))
	room.qte.kind = .Defense
	testing.expect(t, !tactical_inspector_effect_ready(renderer, &room))
	room.qte.kind = .None
	player.tactical.cast_remaining = 1
	testing.expect(t, !tactical_inspector_effect_ready(renderer, &room))
	player.tactical.cast_remaining = 0
	phase := player.tactical.phase
	player.tactical.phase = .Shadow
	testing.expect(t, !tactical_inspector_effect_ready(renderer, &room))
	player.tactical.phase = phase
	renderer.timeline.cues[0] = {kind = .Move, duration = 1}
	renderer.timeline.head, renderer.timeline.count = 0, 1
	testing.expect(t, !tactical_inspector_effect_ready(renderer, &room))
	renderer.timeline = {}
	testing.expect(t, tactical_inspector_effect_ready(renderer, &room))
	// The inspector's frame holds the button inside its inner plate (its edge
	// 4 px all round), under its last line (the tags' row, at 156); the button
	// keeps clear of the relic bar and of the hand, and the whole frame of the
	// board's bar, of the traps' line over it and of the weapon's plate (shown
	// with the inspector once a floor is laid or a weapon held).
	frame := tactical_card_inspector_bounds(.Button)
	testing.expect(t, frame == rl.Rectangle{14, TACTICAL_HUD_HEIGHT+18, 218, 172+TACTICAL_INSPECTOR_EFFECT_ROOM})
	testing.expect(t, button.x >= frame.x+4 && button.y >= frame.y+4 && button.x+button.width <= frame.x+frame.width-4 &&
		button.y+button.height <= frame.y+frame.height-4)
	testing.expect(t, button.y >= TACTICAL_HUD_HEIGHT+26+156+4, "under the tags' row")
	testing.expect(t, !rectangles_overlap(button, relic_bar_bounds(renderer, game.MAX_RUN_RELICS)))
	testing.expect(t, !rectangles_overlap(button, tactical_hand_card_bounds(renderer, 0, game.MAX_HAND_CARDS)))
	for bounds in ([?]rl.Rectangle{m8_bar_bounds(renderer, false), m8_trap_status_bounds(renderer, &room), m8_weapon_bounds(renderer, &room),
		m8_control_bounds(renderer, .Activate, &room), m8_control_bounds(renderer, .Equip, &room)}) {
		testing.expectf(t, !rectangles_overlap(frame, bounds), "the inspector %v meets %v", frame, bounds)
	}
	// The room cleared: the rod, in its slot.
	room.enemies[0].health = 0
	clear(&room.enemies)
	room.phase = .Loot
	game.finish_deck_combat(&player.deck)
	rod, held := game.fishing_rod(&player.deck)
	testing.expect(t, held && game.fishing_room_open(&room))
	card, effect = tactical_inspector_effect(renderer, &room, rod.id, 0, 0)
	testing.expect(t, effect == .Hint && card == rod)
	card, effect = tactical_inspector_effect(renderer, &room, 0, rod.id, 0)
	testing.expect(t, effect == .Button && card == rod)
	_, effect = tactical_inspector_effect(renderer, &room, first.id, 0, 0)
	testing.expect_value(t, effect, Inspector_Effect.None)
}
