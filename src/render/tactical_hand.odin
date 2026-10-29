package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

TACTICAL_HAND_HEIGHT :: f32(184)
// How far the card under the mouse rises over an overlapping hand's others
// (it stops short of the energy and the hint over the hand).
TACTICAL_HAND_RAISE :: f32(8)

// The game's hand (five to eight cards, game.MAX_HAND_CARDS) lies side by
// side, as wide as it lets each card be. PROVA MECCANICHE deals its whole
// deck, ten cards (game.deck_hand_limit): narrower than an eight-card hand's,
// their words would shrink or be cut (tactical_card_text_misfit), so there
// they keep that width and overlap across the canvas, each over the right
// edge of the one before, every one showing all its words, its icon and its
// key: each shows as much of itself as they need (tactical_hand_reveal), the
// width to spare shared out among them, and the next covers only paper. The
// card under the mouse (or aimed, or chosen) rises over them all, whole
// (tactical_hand_raised_card). Behind the player's eyes the hand slides down
// off the canvas (first_person_hand_drop).
tactical_hand_card_bounds :: proc(renderer: ^Renderer, index, count: int) -> rl.Rectangle {
	if count <= 0 || count > game.MAX_HAND_CAPACITY || index < 0 || index >= count { return {} }
	gap: f32 = 8
	y := renderer.canvas_height-160+first_person_hand_drop(renderer)
	if tactical_hand_overlaps(count) {
		width := tactical_hand_overlap_card_width(renderer)
		span := renderer.canvas_width-TACTICAL_HAND_OVERLAP_GUTTER*2
		x := (renderer.canvas_width-span)*0.5
		reveal := &renderer.tactical.hand_reveal
		if reveal.count == count {
			for shown in reveal.shown[:index] { x += shown }
		} else {
			// Not yet measured (no board frame since the hand changed):
			// evenly.
			x += f32(index)*(span-width)/f32(count-1)
		}
		return {x, y, width, 154}
	}
	width := min(f32(166), (renderer.canvas_width-32-gap*f32(count-1))/f32(count))
	left := (renderer.canvas_width-width*f32(count)-gap*f32(count-1))*0.5
	return {left+f32(index)*(width+gap), y, width, 154}
}

// More cards than the game's hand ever holds: they overlap (PROVA MECCANICHE).
tactical_hand_overlaps :: proc(count: int) -> bool {
	return count > game.MAX_HAND_CARDS
}

// An overlapping hand spans the canvas but for this much at either side; its
// cards are as wide as a full hand of the game's.
TACTICAL_HAND_OVERLAP_GUTTER :: f32(8)
@(private = "file")
tactical_hand_overlap_card_width :: proc(renderer: ^Renderer) -> f32 {
	full, gap := game.MAX_HAND_CARDS, f32(8)
	return min(f32(166), (renderer.canvas_width-32-gap*f32(full-1))/f32(full))
}

// How much of each card of an overlapping hand shows (all of the last), for
// the hand of `count` it was measured for (update_tactical_hand_reveal).
Tactical_Hand_Reveal :: struct {
	shown: [game.MAX_HAND_CAPACITY]f32,
	count: int,
}

// A covered card shows at least its icon, whole (draw_tactical_card), and
// its words end this far before the card over it.
TACTICAL_HAND_REVEAL_ICON :: f32(86)
TACTICAL_HAND_REVEAL_GAP :: f32(2)

// How much of a hand card `width` wide must show for every word of its face
// to end before the card over it, as the face sets it (tactical_card_text_misfit
// with `shown`), and its icon to show whole.
tactical_hand_reveal_need :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, width: f32) -> f32 {
	need := TACTICAL_HAND_REVEAL_ICON
	for words in tactical_card_face_words(renderer, card, definition, width) {
		if words.text == "" { continue }
		size, spacing, label, _ := gothic_text_fit_plan(renderer, words.text, words.room, words.size)
		need = max(need, words.start+gothic_text_width(renderer, label, size, spacing)+words.after)
	}
	return min(need, width)
}

// Once a board frame, from the hand it shows: each covered card of an
// overlapping hand shows what it needs (tactical_hand_reveal_need), the width
// the hand has to spare shared out evenly among them; when they need more than
// the hand has, each gives up its share.
@(private)
update_tactical_hand_reveal :: proc(renderer: ^Renderer, deck: ^game.Deck_State) {
	reveal := &renderer.tactical.hand_reveal
	reveal^ = {}
	if deck == nil || !tactical_hand_overlaps(deck.hand_count) || deck.hand_count > game.MAX_HAND_CAPACITY { return }
	count := deck.hand_count
	width := tactical_hand_overlap_card_width(renderer)
	needed := f32(0)
	for card, index in deck.hand[:count-1] {
		definition, found := game.card_definition_by_id(card.definition_id)
		reveal.shown[index] = tactical_hand_reveal_need(renderer, card, definition, width) if found else width
		needed += reveal.shown[index]
	}
	reveal.shown[count-1] = width
	room := renderer.canvas_width-TACTICAL_HAND_OVERLAP_GUTTER*2-width
	for &shown in reveal.shown[:count-1] {
		if needed <= room { shown += (room-needed)/f32(count-1) } else { shown *= room/max(needed, 1) }
	}
	reveal.count = count
}

// How much of a hand card shows before the next one covers it: all of it,
// but in an overlapping hand where the card is not the last one.
tactical_hand_card_visible_width :: proc(renderer: ^Renderer, index, count: int) -> f32 {
	bounds := tactical_hand_card_bounds(renderer, index, count)
	if !tactical_hand_overlaps(count) || index >= count-1 { return bounds.width }
	return tactical_hand_card_bounds(renderer, index+1, count).x-bounds.x
}

// Where a hand card is drawn when it rises over the others: an overlapping
// hand lifts it, whole, the game's hand never moves it.
tactical_hand_raised_card_bounds :: proc(renderer: ^Renderer, index, count: int) -> rl.Rectangle {
	bounds := tactical_hand_card_bounds(renderer, index, count)
	if tactical_hand_overlaps(count) && bounds.width > 0 { bounds.y -= TACTICAL_HAND_RAISE }
	return bounds
}

// The card that rises over an overlapping hand: the one under the mouse, the
// one aimed or the one chosen; none in the game's hand.
@(private)
tactical_hand_raised_card :: proc(deck: ^game.Deck_State, hovered, selected, dragged: u32) -> u32 {
	if deck == nil || !tactical_hand_overlaps(deck.hand_count) { return 0 }
	for id in ([3]u32{hovered, dragged, selected}) {
		if _, found := game.hand_card_index_by_id(deck, id); found && id != 0 { return id }
	}
	return 0
}

@(private = "file")
gothic_rarity_accent :: proc(rarity: game.Card_Rarity) -> rl.Color {
	switch rarity {
	case .Uncommon: return {77, 108, 129, 255}
	case .Rare: return {143, 112, 58, 255}
	case .Common, .Count: return {115, 106, 92, 255}
	}
	return GOTHIC_MUTED
}

// The time a card takes from the window: "-2s", or "0s" for one that takes
// none (Movimento Ombra stands outside it).
@(private)
tactical_card_time_badge :: proc(id: game.Card_Id) -> cstring {
	cost := game.tactical_card_time_cost(id)
	if cost <= 0 { return "0s" }
	return fmt.ctprintf("-%.0fs", cost)
}

SCOPA_CARD_SIZE :: rl.Vector2{60, 96}

// The source rectangle of a Scopa card in its sheet.
@(private = "file")
scopa_card_source :: proc(id: game.Card_Id) -> rl.Rectangle {
	return {0 if id == .Sei_Denari else SCOPA_CARD_SIZE.x+2, 0, SCOPA_CARD_SIZE.x, SCOPA_CARD_SIZE.y}
}

// Draws a Scopa card face into `dest` (pixel-exact when the scale is whole).
@(private)
draw_scopa_face :: proc(renderer: ^Renderer, id: game.Card_Id, dest: rl.Rectangle, rotation: f32 = 0, tint: rl.Color = rl.WHITE) {
	texture := renderer.tactical.art.scopa
	if texture.id == 0 { return }
	rl.DrawTexturePro(texture, scopa_card_source(id), dest, {dest.width*0.5, dest.height*0.5}, rotation, tint)
}

// The Scopa pair is a real playing card on green felt rather than a gothic
// crest: the Neapolitan face fills the height, cost and time sit at the corners.
@(private = "file")
draw_scopa_tactical_card :: proc(renderer: ^Renderer, bounds: rl.Rectangle, card: game.Card_Instance, definition: game.Card_Definition,
	slot: int, affordable, selected, hovered, available: bool) {
	x, y, width, height := bounds.x, bounds.y, bounds.width, bounds.height
	edge := GOTHIC_BLUE if selected || hovered else GOTHIC_STEEL
	gothic_frame({x+2, y+3, width, height}, GOTHIC_INK, GOTHIC_INK)
	gothic_frame(bounds, {26, 62, 44, 255}, edge)
	for stripe in 0..<int(height/6) {
		rl.DrawRectangleRec({x+5, y+5+f32(stripe)*6, width-10, 1}, {34, 76, 54, 255})
	}
	scale := max(f32(0.5), f32(int((height-12)/SCOPA_CARD_SIZE.y*2))*0.5)
	face := rl.Rectangle{x+width*0.5, y+height*0.5, SCOPA_CARD_SIZE.x*scale, SCOPA_CARD_SIZE.y*scale}
	draw_scopa_face(renderer, card.definition_id, {face.x+2, face.y+3, face.width, face.height}, 0, {0, 0, 0, 90})
	draw_scopa_face(renderer, card.definition_id, face, 0, rl.WHITE if available else rl.Color{150, 140, 130, 255})
	if selected || hovered {
		light := f32(0.72)+f32(math.sin(renderer.sprite_assets.elapsed*3))*0.12
		rl.DrawRectangleLinesEx({face.x-face.width*0.5-2, face.y-face.height*0.5-2, face.width+4, face.height+4}, 2, rl.Fade(edge, light))
	}
	rl.DrawRectangleRec({x+7, y+8, 22, 24}, GOTHIC_STEEL)
	rl.DrawRectangleRec({x+8, y+9, 20, 22}, GOTHIC_INK)
	gothic_text(renderer, fmt.ctprintf("%d", definition.cost), x+13, y+8, 18, GOTHIC_BLUE if affordable else GOTHIC_RED)
	rl.DrawRectangleRec({x+7, y+36, 30, 17}, {22, 41, 54, 240})
	gothic_text_fit(renderer, tactical_card_time_badge(card.definition_id), {x+10, y+37, 25, 15}, 12, GOTHIC_BLUE)
	gold := game.card_effect_amount(definition.effects[0], card.upgrade_level)
	ribbon := rl.Rectangle{x+width*0.5-36, y+height-27, 72, 19}
	rl.DrawRectangleRec(ribbon, {72, 54, 24, 240})
	rl.DrawRectangleLinesEx(ribbon, 1, {236, 196, 96, 255})
	label := fmt.ctprintf("+%d ORO", gold)
	gothic_text(renderer, label, ribbon.x+(ribbon.width-gothic_text_width(renderer, label, 14))*0.5, ribbon.y+1, 14, {252, 226, 132, 255})
	gothic_text(renderer, fmt.ctprintf("%d", slot+1), x+width-16, y+8, 12, GOTHIC_PAPER)
}

// `slot` is the hand's key for it (none: -1, the Canna da Pesca's own slot),
// `key` its label when the hand names it (tactical_hand_slot_key). A card of
// an overlapping hand shows only `visible` of its width (0: all of it): its
// key, its icon and its crest move left into what shows, and its rarity's
// marks go under its time (the next card covers its right margin; its words
// end before it: tactical_hand_reveal).
@(private)
draw_tactical_card :: proc(renderer: ^Renderer, bounds: rl.Rectangle, card: game.Card_Instance, definition: game.Card_Definition,
	slot: int, affordable, selected, hovered, available: bool, visible: f32 = 0, key: cstring = "") {
	if game.card_is_scopa(card.definition_id) && renderer.tactical.art.scopa.id != 0 {
		draw_scopa_tactical_card(renderer, bounds, card, definition, slot, affordable, selected, hovered, available)
		return
	}
	art := &renderer.tactical.art
	accent := gothic_card_accent(card.definition_id)
	rarity := gothic_rarity_accent(definition.rarity)
	edge := GOTHIC_BLUE if selected || hovered else GOTHIC_STEEL
	x, y, width := bounds.x, bounds.y, bounds.width
	gothic_frame({x+2, y+3, width, bounds.height}, GOTHIC_INK, GOTHIC_INK)
	gothic_frame(bounds, GOTHIC_INK, edge, true, art)
	ink := GOTHIC_INK if affordable && available else rl.Color{111, 102, 92, 255}
	// The cost, name and action stay in fixed bounds while the inlay lights up.
	// No animated raise changes the card's pointer target or masks its neighbor
	// (an overlapping hand lifts the card under the mouse whole, still under
	// it: tactical_hand_raised_card_bounds).
	rl.DrawRectangleRec({x+10, y+4, width-20, 2}, rarity)
	if selected || hovered {
		light := f32(0.72)+f32(math.sin(renderer.sprite_assets.elapsed*3))*0.12
		rl.DrawRectangleRec({x+10, y+4, width-20, 2}, rl.Fade(edge, light))
		rl.DrawRectangleRec({x+3, y+14, 2, bounds.height-28}, edge)
		rl.DrawRectangleRec({x+width-5, y+14, 2, bounds.height-28}, edge)
	}
	rl.DrawRectangleRec({x+9, y+10, 22, 24}, GOTHIC_STEEL)
	rl.DrawRectangleRec({x+10, y+11, 20, 22}, GOTHIC_INK)
	rl.DrawRectangleRec({x+12, y+11, 16, 1}, GOTHIC_BLUE if affordable else GOTHIC_RED)
	gothic_text(renderer, fmt.ctprintf("%d", definition.cost), x+15, y+10, 18, GOTHIC_BLUE if affordable else GOTHIC_RED)
	gothic_text_fit(renderer, tactical_card_face_title(renderer, card, definition, width), {x+37, y+13, tactical_card_name_room(width), 21},
		TACTICAL_CARD_NAME_SIZE, ink)
	// A smaller recessed crest leaves room for both effect lines in an eight-card hand.
	covered := visible > 0 && visible < width
	icon_bounds := rl.Rectangle{x+40, y+36, width-56, 44}
	if covered { icon_bounds.width = clamp(visible-42, 0, width-56) }
	center_x := icon_bounds.x+icon_bounds.width*0.5
	rl.DrawRectangleRec({center_x-23, y+43, 46, 32}, {99, 105, 111, 19})
	rl.DrawRectangleRec({center_x-15, y+36, 30, 7}, {99, 105, 111, 19})
	rl.DrawLineEx({center_x-25, y+44}, {center_x-25, y+75}, 1, {114, 102, 83, 75})
	rl.DrawLineEx({center_x+25, y+44}, {center_x+25, y+75}, 1, {114, 102, 83, 75})
	if covered {
		marks_y := y+79 if game.card_is_board_device(card.definition_id) else y+70
		for mark in 0..=int(definition.rarity) { gothic_inlay(x+15+f32(mark)*8, marks_y, 2, rarity) }
	} else {
		for mark in 0..=int(definition.rarity) { gothic_inlay(x+width-14, y+43+f32(mark)*8, 2, rarity) }
	}
	icon := gothic_card_icon(card.definition_id)
	shadow_bounds := icon_bounds
	shadow_bounds.y += 2
	if game.card_is_board_device(card.definition_id) {
		draw_device_card_icon(card.definition_id, icon_bounds, accent)
	} else {
		gothic_atlas_icon(art.icons, art.icon_sources[icon], shadow_bounds, {37, 33, 29, 60})
		gothic_atlas_icon(art.icons, art.icon_sources[icon], icon_bounds, rl.WHITE if available else rl.Color{135, 125, 118, 255})
	}
	// Time has a distinct blue badge, separated from the black energy socket.
	// The crest stays clear even with the narrowest eight-card hand.
	rl.DrawRectangleRec({x+8, y+42, 30, 17}, {22, 41, 54, 240})
	gothic_text_fit(renderer, tactical_card_time_badge(card.definition_id), {x+11, y+43, 25, 15}, 12, GOTHIC_BLUE)
	if game.card_is_board_device(card.definition_id) {
		gothic_text_fit(renderer,"PASSIVA" if card.definition_id == .Shock_Floor else "ATTIVO",{x+8,y+63,32,12},9,accent)
	}
	rl.DrawRectangleRec({x+10, y+83, width-20, 2}, accent)
	rl.DrawRectangleRec({x+10, y+85, width-20, 1}, {251, 244, 223, 170})
	first, second := tactical_card_face_lines(card, definition, width)
	gothic_text_fit(renderer, first, {x+10, y+90, width-20, 18}, 14, ink)
	gothic_text_fit(renderer, second, {x+10, y+109, width-20, 17}, 12, ink)
	rl.DrawRectangleRec({x+9, y+130, width-18, 17}, {41, 42, 45, 24})
	gothic_rule(x+10, y+128, width-20, rarity)
	gothic_text_fit(renderer, tactical_card_target_label(definition), {x+10, y+132, width-32, 17}, 12, accent)
	if slot >= 0 {
		shown := visible if visible > 0 else width
		gothic_text(renderer, key if key != "" else fmt.ctprintf("%d", slot+1), x+shown-18, y+132, 12, ink)
	}
}

// The key of a hand's slot, as the keyboard plays it: 1 to 9, then 0.
@(private)
tactical_hand_slot_key :: proc(index: int) -> cstring {
	return fmt.ctprintf("%d", (index+1)%10)
}

// A hand card's two lines as a card `width` wide shows them: a narrow card
// (a hand of seven or eight) says them shorter where it has a short form.
@(private = "file")
tactical_card_face_lines :: proc(card: game.Card_Instance, definition: game.Card_Definition, width: f32) -> (first, second: cstring) {
	first, second = gothic_card_lines(card)
	if width < CARD_NARROW_WIDTH {
		if short_first, short_second, short := gothic_card_narrow_lines(card); short { first, second = short_first, short_second }
	}
	return
}

// The inspector's name of a card: its upgrades after it.
tactical_card_title :: proc(card: game.Card_Instance, definition: game.Card_Definition) -> cstring {
	if card.upgrade_level > 0 { return fmt.ctprintf("%s +%d", definition.name, card.upgrade_level) }
	return fmt.ctprintf("%s", definition.name)
}

// The name on a hand card `width` wide (a menu's too): a card with a short
// name says it on a narrow card, and on a wider one wherever the whole name,
// its upgrade after it, would not hold there as it is, at the face's size
// (smaller, closed up or cut: First Person Shooter on every face of the game's
// hands, the rewards and the shop).
@(private)
tactical_card_face_title :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, width: f32) -> cstring {
	whole := tactical_card_title(card, definition)
	short, found := gothic_card_narrow_name(card.definition_id)
	if !found { return whole }
	if width >= CARD_NARROW_WIDTH {
		if renderer == nil { return whole }
		if _, _, _, fit := gothic_text_fit_plan(renderer, whole, tactical_card_name_room(width), TACTICAL_CARD_NAME_SIZE); fit == .Fits { return whole }
	}
	if card.upgrade_level > 0 { return fmt.ctprintf("%s +%d", short, card.upgrade_level) }
	return short
}

// A hand card's name: its size, and the width it has on a card `width` wide.
TACTICAL_CARD_NAME_SIZE :: 16
@(private = "file")
tactical_card_name_room :: proc(width: f32) -> f32 {
	return width-45
}

// A hand card's words as its face sets them (draw_tactical_card): from
// `start`, in `room` on a card `width` wide, at `size`; covered by the next
// card of an overlapping hand, they end `after` before it (the reach before
// the key).
Tactical_Card_Words :: struct {
	what: string,
	text: cstring,
	start, room, after: f32,
	size: int,
	name: bool,
}

@(private = "file")
tactical_card_face_words :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, width: f32) -> [4]Tactical_Card_Words {
	first, second := tactical_card_face_lines(card, definition, width)
	gap := TACTICAL_HAND_REVEAL_GAP
	return {
		{"name", tactical_card_face_title(renderer, card, definition, width), 37, tactical_card_name_room(width), gap, TACTICAL_CARD_NAME_SIZE, true},
		{"first line", first, 10, width-20, gap, 14, false},
		{"second line", second, 10, width-20, gap, 12, false},
		{"reach", tactical_card_target_label(definition), 10, width-32, 22, 12, false},
	}
}

// The words of `card` that would not hold on a hand card `width` wide or in
// the inspector, said one by one (the lab's smoke measures its deck with it):
// a line, the reach or the inspector's words that would not fit as they are
// (closed up, the pixel font's letters touch: CTRL+CLIC reads CTRL+CUC), or
// a name that would not, but for an upgrade's figures after it (then it may
// close up or take a smaller size, never be cut); and on a card of which only
// `shown` shows (an overlapping hand's, 0: all of it), a word of its face that
// would end under the card over it. Empty when every one holds.
tactical_card_text_misfit :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, width: f32, shown: f32 = 0) -> string {
	whole_first, whole_second := gothic_card_lines(card)
	reaction, rule := tactical_card_inspector_rules(card, definition)
	face := tactical_card_face_words(renderer, card, definition, width)
	inspector := [?]Tactical_Card_Words{
		{"inspector name", tactical_card_title(card, definition), 0, 195, 0, 18, true},
		{"inspector cost", tactical_card_cost_line(card, definition), 0, 193, 0, 14, false},
		{"inspector first line", whole_first, 0, 192, 0, 16, false},
		{"inspector second line", whole_second, 0, 192, 0, 14, false},
		{"inspector reaction", reaction, 0, 192, 0, 12, false},
		{"inspector rule", rule, 0, 192, 0, 12, false},
	}
	said := ""
	for group, index in ([2][]Tactical_Card_Words{face[:], inspector[:]}) {
		for words in group {
			if words.text == "" { continue }
			size, spacing, label, fit := gothic_text_fit_plan(renderer, words.text, words.room, words.size)
			if !(fit == .Fits || (words.name && card.upgrade_level > 0 && fit != .Cut)) {
				said = fmt.tprintf("%s%s%s \"%s\" (%v in %.0f px at %d)", said, "; " if said != "" else "", words.what, words.text, fit, words.room, words.size)
				continue
			}
			if index != 0 || !(shown > 0 && shown < width) { continue }
			if end := words.start+gothic_text_width(renderer, label, size, spacing); end+words.after > shown {
				said = fmt.tprintf("%s%s%s \"%s\" (ends at %.0f px, %.0f of %.0f showing)", said, "; " if said != "" else "", words.what, words.text,
					end, shown, width)
			}
		}
	}
	return said
}

// MOSTRA EFFETTO in the card inspector (src/effect_window.odin): a button once
// the card is chosen (the inspector then stays while the mouse goes to it), its
// key I while the mouse is only over the card (a click there picks the card
// up); none while it is dragged, behind the player's eyes or on MOSTRA
// EFFETTO's own board.
Inspector_Effect :: enum u8 {None, Hint, Button}
// How much taller the inspector stands with its MOSTRA EFFETTO row: its frame
// then ends over the board's bar and the traps' line above it
// (m8_trap_status_bounds), clear of both.
TACTICAL_INSPECTOR_EFFECT_ROOM :: f32(26)

// The row under the inspector's last line (its tags, at 156), as far from it
// as the HUD's commands are from one another.
tactical_inspector_effect_bounds :: proc() -> rl.Rectangle {
	x, y := f32(25), TACTICAL_HUD_HEIGHT+f32(26)
	return {x-4, y+160, 204, 24}
}

// The card inspector's frame, its MOSTRA EFFETTO row too when it shows one.
tactical_card_inspector_bounds :: proc(effect := Inspector_Effect.None) -> rl.Rectangle {
	x, y := f32(25), TACTICAL_HUD_HEIGHT+f32(26)
	return {x-11, y-8, 218, f32(172)+(TACTICAL_INSPECTOR_EFFECT_ROOM if effect != .None else 0)}
}

// The card the inspector shows now (draw_tactical_hand, draw_fishing_slot: the
// same choice as their drawing) and what its MOSTRA EFFETTO is.
tactical_inspector_effect :: proc(renderer: ^Renderer, room: ^game.Room, hovered, selected, dragged: u32) -> (card: game.Card_Instance, effect: Inspector_Effect) {
	if renderer == nil || room == nil || room.player == nil || renderer.tactical.showcase || dragged != 0 { return }
	deck, phase := renderer_hand_deck(renderer, room)
	if phase == .Loot {
		// The room cleared: the Canna da Pesca, in its slot.
		rod, held := game.fishing_rod(&room.player.deck)
		if !held || !game.fishing_room_open(room) { return }
		if rod.id == hovered { return rod, .Button if rod.id == selected else .Hint }
		if rod.id == selected { return rod, .Button }
		return
	}
	if phase != .Combat || !deck.combat_active || game.tactical_first_person_active(room) || first_person_hand_drop(renderer) > 0 { return }
	active := hovered if hovered != 0 else selected
	index, found := game.hand_card_index_by_id(deck, active)
	if !found { return }
	return deck.hand[index], .Button if active == selected else .Hint
}

// The inspector's button is the board's no more: the cell under it is never
// aimed at (poll_gameplay_command, and the scene's hover).
tactical_inspector_effect_contains :: proc(renderer: ^Renderer, room: ^game.Room, hovered, selected, dragged: u32, point: view.Vec2) -> bool {
	_, effect := tactical_inspector_effect(renderer, room, hovered, selected, dragged)
	return effect == .Button && point_in_rectangle(point, tactical_inspector_effect_bounds())
}

// Whether the board lets the window open now (src/effect_window.odin refuses
// it while a defence, a cast, Movimento Ombra or an action still showing,
// a fishing too, holds the board): the button stands dimmed meanwhile, as
// PERSONAGGIO does.
tactical_inspector_effect_ready :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return renderer != nil && room != nil && room.qte.kind == .None && !game.tactical_is_casting(room) &&
		!game.tactical_shadow_active(room) && !renderer_timeline_is_busy(renderer)
}

// The inspector's MOSTRA EFFETTO row: the button (dimmed while the board is
// busy), or the key alone.
@(private = "file")
draw_tactical_inspector_effect :: proc(renderer: ^Renderer, effect: Inspector_Effect, ready := true) {
	bounds := tactical_inspector_effect_bounds()
	switch effect {
	case .None:
	case .Button:
		hud_button(renderer, bounds, EFFECT_ENTRY_KEY, EFFECT_ENTRY_LABEL, ready)
	case .Hint:
		// No button to click (the mouse is on the card): its key, dimmed.
		cap := effect_entry_key_bounds(bounds)
		rl.DrawRectangleRec(cap, GOTHIC_STEEL)
		gothic_text_fit(renderer, EFFECT_ENTRY_KEY, {cap.x+4, cap.y+(cap.height-15)*0.5, cap.width-6, 16}, 12, GOTHIC_INK)
		gothic_text_fit(renderer, EFFECT_ENTRY_LABEL, effect_entry_label_bounds(bounds, true), 14, GOTHIC_MUTED)
	}
}

@(private)
draw_tactical_card_inspector :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, selected: bool,
	effect := Inspector_Effect.None, effect_ready := true) {
	x, y := f32(25), TACTICAL_HUD_HEIGHT+f32(26)
	frame := tactical_card_inspector_bounds(effect)
	gothic_frame(frame, GOTHIC_RECESS, GOTHIC_STEEL)
	gothic_text_fit(renderer, tactical_card_title(card, definition), {x, y, 195, 25}, 18, GOTHIC_PAPER)
	gothic_rule(x, y+29, 190, gothic_rarity_accent(definition.rarity))
	gothic_text_fit(renderer, tactical_card_cost_line(card, definition), {x, y+35, 193, 18}, 14, GOTHIC_BLUE)
	gothic_text_fit(renderer, tactical_card_target_label(definition), {x, y+54, 193, 17}, 12, GOTHIC_MUTED)
	first, second := gothic_card_lines(card)
	gothic_text_fit(renderer, first, {x, y+76, 192, 20}, 16, GOTHIC_PAPER)
	gothic_text_fit(renderer, second, {x, y+97, 192, 18}, 14, GOTHIC_PAPER)
	reaction, rule := tactical_card_inspector_rules(card, definition)
	gothic_text_fit(renderer, reaction, {x, y+117, 192, 17}, 12, GOTHIC_RED)
	tags, count := card_keyword_tags(card, definition)
	tag_count := count+(1 if definition.exhaust_on_play else 0)
	if tag_count == 0 && rule != "" { gothic_text_fit(renderer, rule, {x, y+139, 192, 17}, 12, GOTHIC_RED) }
	tag_width := f32(192)/f32(max(1, tag_count))
	for index in 0..<tag_count {
		label := "EXHAUST" if index == count else card_keyword_tag_label(tags[index], true)
		bounds := rl.Rectangle{x+f32(index)*tag_width, y+138, tag_width-3, 18}
		rl.DrawRectangleRec(bounds, GOTHIC_INK)
		rl.DrawRectangleRec({bounds.x, bounds.y, 1, bounds.height}, GOTHIC_STEEL)
		gothic_text_fit(renderer, label, {bounds.x+4, bounds.y+1, bounds.width-7, 17}, 12, GOTHIC_MUTED)
	}
	draw_tactical_inspector_effect(renderer, effect, effect_ready)
	if selected { rl.DrawRectangle(c.int(frame.x), c.int(frame.y), 3, c.int(frame.height), GOTHIC_RED) }
}

// The inspector's energy and time: "ENERGIA 2 / TEMPO -2s".
@(private = "file")
tactical_card_cost_line :: proc(card: game.Card_Instance, definition: game.Card_Definition) -> cstring {
	return fmt.ctprintf("ENERGIA %d / TEMPO %s", definition.cost, tactical_card_time_badge(card.definition_id))
}

// The inspector's red lines under a card's two: how it answers (a reaction)
// and a second rule, shown where the keyword tags go when the card has none.
@(private)
tactical_card_inspector_rules :: proc(card: game.Card_Instance, definition: game.Card_Definition) -> (reaction, rule: cstring) {
	if card.definition_id == .Shadow_Step { reaction, rule = "NEMICI E TIMER FERMI", "DIAGONALE SUL BATTITO" }
	if card.definition_id == .Poison_Pool { reaction, rule = "AREE CHIUSE: SI RIEMPIONO", "OGNI CELLA ENTRATA AVVELENA" }
	if card.definition_id == .Wildfire { reaction, rule = "CRESCE A OGNI NUOVA FINESTRA", "SI SPEGNE ALLA QUINTA" }
	if card.definition_id == .Deflect { reaction, rule = "IL NEMICO PRENDE IL COLPO", "NO BOMBE, TRAPPOLE, STATUS" }
	if card.definition_id == .Coffin { reaction, rule = "+ VEL 2 O BRU 1 O RAL 1", "LINEA DI TIRO / 1s L'UNA" }
	if card.definition_id == .Fate_Dice { reaction, rule = "1 VEL 2 BRU 3 RAL 4 VITA", "5 CRITICO / 6+ LETALE" }
	if card.definition_id == .Venom_Blade { reaction, rule = "IL DADO DECIDE I COLPI", "LE CARICHE SI SOMMANO" }
	if card.definition_id == .Lasso { reaction, rule = "DENTRO IL RAGGIO: SOLO SPINTA", "SCHIVA O SPINTA: LO MOLLI" }
	if card.definition_id == .Fishing_Rod { reaction, rule = "SOLO A STANZA LIBERATA", "MAI IN MANO / UNA PER RUN" }
	if card.definition_id == .Pinball { reaction, rule = "BOSS E MINIBOSS: TROPPO PESANTI", fmt.ctprintf("DOPO %ds SCOPPIA E CADE", int(game.PINBALL_SECONDS)) }
	if card.definition_id == .First_Person { reaction, rule = "NIENTE CARTE: SOLO L'AK", "WASD SECONDO LA VISTA" }
	// The fists' keys (Fase 3, the user's choice: the punches' keys too).
	if card.definition_id == .First_Person_Brawler { reaction, rule = "SX JAB / DX CROSS / SHIFT GANCI", "WASD LIBERO / SPAZIO SALTA" }
	if card.definition_id == .Marley_Party { reaction, rule = "SOLO SULLE CASELLE LUCI", fmt.ctprintf("+%ds A UCCISIONE / MAX %ds", game.MARLEY_KILL_SECONDS, game.MARLEY_MAX_SECONDS) }
	if card.definition_id == .Flood_Wave { reaction, rule = "UNA CASELLA PER NEMICO", "ROTELLA: GIRA LA FRECCIA" }
	if card.definition_id == .Field_Cannon { reaction, rule = "ROTELLA: GIRA LA CANNA", "AL 2o UPGRADE: LASER" }
	if card.definition_id == .Laser_Cannon { reaction, rule = "COLPISCE TUTTA LA LINEA", "NON SI OFFRE: EVOLUZIONE" }
	if card.definition_id == .Devouring_Hole { reaction, rule = "TIRA IL 5X5, COLPISCE IL 3X3", "BOSS E MINIBOSS: SOLO DANNO" }
	if card.definition_id == .Dino_Ride { reaction, rule = "1 RAPTOR 2 STEGO 3 DILO 4 GIGA", "UN DINO ALLA VOLTA" }
	if card.definition_id == .Guard || card.definition_id == .Purifying_Guard { reaction = "QTE: BLOCK / PARRY" }
	if card.definition_id == .Thorn_Coat { reaction = "QTE: DEVIAZIONE (FRECCE)" }
	if card.definition_id == .Afterimage { reaction = "IGNORA RECUPERO SCHIVA" }
	if card.definition_id == .Prismatic_Barrage { reaction = "SCUDO PRIMA / 2s" }
	if card.definition_id == .Twin_Venom { reaction = "VELENO: A OGNI SUA AZIONE" }
	if game.card_is_board_device(card.definition_id) { reaction = "USA IL PULSANTE ATTIVA" }
	if card.definition_id == .Shock_Floor { reaction = "TRAPPOLA: INGRESSO NEMICO" }
	if card.definition_id == .Tesla_Coil { reaction = "ATTIVA / 2-3 TESLA RESTANO" }
	if card.definition_id == .Heavy_Blow { reaction = "SALTA AZIONE / RECUPERA 1s" }
	if card.definition_id == .Strike { reaction = "PREMIA IL CONTRATTACCO" }
	if card.definition_id == .Shove || card.definition_id == .Grappling_Hook { reaction = "SPOSTARE INTERROMPE LA MIRA" }
	if card.definition_id == .Battle_Focus { reaction = "OLTRE I MURI RESTA LA FOG" }
	if card.definition_id == .Dash { reaction = "NON USA IL RECUPERO SCHIVA" }
	if card.definition_id == .Toxic_Wave { reaction = "AREA 5X5 / RISPETTA I MURI" }
	return
}

draw_tactical_hand :: proc(renderer: ^Renderer, room: ^game.Room,
	hovered, selected, dragged: u32, mouse: view.Vec2) {
	deck, phase := renderer_hand_deck(renderer, room)
	// The room cleared: no hand, the Canna da Pesca's slot (fishing.odin).
	if phase == .Loot { draw_fishing_slot(renderer, room, hovered, selected, dragged, mouse) }
	if phase != .Combat || !deck.combat_active { return }
	// Behind the player's eyes the hand is put away: it slides off the canvas.
	drop := first_person_hand_drop(renderer)
	if drop >= TACTICAL_HAND_HEIGHT+20 { return }
	available := !renderer_blocks_player_input(renderer) && game.tactical_allows_cards(room)
	recovering := game.tactical_is_recovering(room)
	top := renderer.canvas_height-TACTICAL_HAND_HEIGHT+drop
	first_bounds := tactical_hand_card_bounds(renderer, 0, deck.hand_count)
	last_bounds := tactical_hand_card_bounds(renderer, max(0, deck.hand_count-1), deck.hand_count)
	left := first_bounds.x if deck.hand_count > 0 else f32(24)
	right := last_bounds.x+last_bounds.width if deck.hand_count > 0 else renderer.canvas_width-24
	if right-left < 640 { left = (renderer.canvas_width-640)*0.5; right = left+640 }
	rl.DrawRectangleGradientV(0, c.int(top-14), c.int(renderer.canvas_width), c.int(TACTICAL_HAND_HEIGHT+14), {8, 13, 21, 0}, {8, 13, 21, 245})
	gothic_text(renderer, fmt.ctprintf("ENERGIA %d/%d", deck.energy, deck.rules.max_energy), left+2, top+3, 14, GOTHIC_PAPER)
	if room.player.tactical.config.expedition {
		bar := rl.Rectangle{left+126, top+7, 118, 10}
		hud_bar(bar, f32(deck.energy)/f32(deck.rules.max_energy), {55, 150, 255, 255})
		if index, found := game.hand_card_index_by_id(deck, selected); found {
			cost := game.card_energy_cost(room, deck.hand[index].definition_id)
			spent := min(cost, deck.energy)
			portion := bar.width*f32(spent)/f32(deck.rules.max_energy)
			rl.DrawRectangleRec({bar.x+bar.width*f32(deck.energy-spent)/f32(deck.rules.max_energy), bar.y, portion, bar.height},
				rl.Color{144, 220, 255, 255} if cost <= deck.energy else rl.Color{240, 86, 100, 255})
		}
	} else {
		spacing := min(f32(15), f32(60)/f32(max(i32(1), deck.rules.max_energy)))
		for energy in 0..<int(deck.rules.max_energy) {
			gothic_inlay(left+110+f32(energy)*spacing, top+11, min(f32(4),spacing*0.35), GOTHIC_BLUE if energy < int(deck.energy) else GOTHIC_STEEL)
		}
	}
	// The Canna da Pesca waiting in Exhaust was never played.
	gothic_text_fit(renderer, fmt.ctprintf("MAZZO %d / SCARTI %d / ESAURITE %d", deck.draw_count, deck.discard_count, game.deck_exhausted_count(deck)), {right-205, top+5, 205, 17}, 10, GOTHIC_MUTED)
	hint: cstring = "ROTELLA: CARTA / CLIC: GIOCA" if room.player.tactical.config.expedition else ""
	if selected != 0 {
		if index, found := game.hand_card_index_by_id(deck, selected); found {
			definition, _ := game.card_definition_by_id(deck.hand[index].definition_id)
			hint = "SCEGLI BERSAGLIO / DESTRO: ANNULLA" if game.card_requires_spatial_target(definition) else "CLIC DI NUOVO: GIOCA"
		}
	}
	// FERETRO: how its arrows are loosed, and while Ctrl is held, where.
	if arrows := game.player_charges(room, .Arrows); arrows > 0 && selected == 0 {
		hint = fmt.ctprintf("CTRL+CLIC SU UN NEMICO: FRECCIA (%d)", arrows)
	}
	if renderer.tactical.arrow_aim { hint = "CLIC SU UN NEMICO EVIDENZIATO: FRECCIA" }
	// PINBALL: bosses are too heavy, and only one ball can roll at a time.
	if aimed := dragged if dragged != 0 else selected; aimed != 0 && renderer.has_hovered_cell {
		if index, found := game.hand_card_index_by_id(deck, aimed); found && deck.hand[index].definition_id == .Pinball {
			id := deck.hand[index].definition_id
			definition, _ := game.card_definition_by_id(id)
			evaluation := game.evaluate_card_targeting(room, deck.hand[index], game.card_target_request_at(definition, renderer.hovered_cell))
			if said := pinball_aim_hint(room, evaluation.error); said != "" { hint = said }
		}
	}
	if renderer.tactical.expedition_placement { hint = "ROTELLA: GIRA / CLIC: PIAZZA / DESTRO: TORNA" }
	if room.player.tactical.dinosaur_remaining > 0 { hint = fmt.ctprintf("DINOSAURO %.0fs / URTO +%d E SPINTA", room.player.tactical.dinosaur_remaining, room.player.tactical.dinosaur_power) }
	if recovering { hint = "RECUPERO / PUOI MUOVERTI" }
	if game.tactical_is_stunned(room) { hint = "STORDITO / SOLO CARTE" }
	if game.tactical_shadow_active(room) { hint = "OMBRA / SOLO PASSI" }
	// The pivot holds the rope: only a dodge lets go, when one can be made.
	if game.tactical_lasso_active(room) && !game.tactical_is_casting(room) { hint = lasso_hand_hint(room) }
	hint_offset := f32(254) if room.player.tactical.config.expedition else 180
	if right-left > 580 { gothic_text_fit(renderer, hint, {left+hint_offset, top+5, right-left-hint_offset-218, 17}, 10, GOTHIC_BLUE) }
	// Left to right, each over the edge of the one before in an overlapping
	// hand; the raised card last, over them all.
	raised := tactical_hand_raised_card(deck, hovered, selected, dragged)
	for pass in 0..<2 {
		for card, index in deck.hand[:deck.hand_count] {
			if (card.id == raised) != (pass == 1) { continue }
			definition, found := game.card_definition_by_id(card.definition_id)
			if !found { continue }
			definition.cost = game.card_energy_cost(room, card.definition_id)
			bounds := tactical_hand_card_bounds(renderer, index, deck.hand_count)
			visible := tactical_hand_card_visible_width(renderer, index, deck.hand_count)
			if card.id == raised { bounds, visible = tactical_hand_raised_card_bounds(renderer, index, deck.hand_count), bounds.width }
			draw_tactical_card(renderer, bounds, card, definition, index, deck.energy >= definition.cost,
				card.id == selected || card.id == dragged, card.id == hovered, available, visible, tactical_hand_slot_key(index))
		}
	}
	active := dragged if dragged != 0 else (hovered if hovered != 0 else selected)
	if drop > 0 { return }
	if index, found := game.hand_card_index_by_id(deck, active); found {
		card := deck.hand[index]
		definition, _ := game.card_definition_by_id(card.definition_id)
		definition.cost = game.card_energy_cost(room, card.definition_id)
		_, effect := tactical_inspector_effect(renderer, room, hovered, selected, dragged)
		draw_tactical_card_inspector(renderer, card, definition, selected == active, effect, tactical_inspector_effect_ready(renderer, room))
		if dragged != 0 { gothic_text(renderer, fmt.ctprintf("%s", definition.name), mouse.x+14, mouse.y-18, 16, GOTHIC_PAPER) }
	}
	// MOSTRA EFFETTO's film has its own pointer: the enemy inspector follows
	// the real mouse.
	if active == 0 && !renderer.tactical.showcase { draw_tactical_enemy_inspector(renderer, room) }
}
