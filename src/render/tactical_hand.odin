package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../view"

TACTICAL_HAND_HEIGHT :: f32(184)

tactical_hand_card_bounds :: proc(renderer: ^Renderer, index, count: int) -> rl.Rectangle {
	if count <= 0 || count > game.MAX_HAND_CARDS || index < 0 || index >= count { return {} }
	gap: f32 = 8
	width := min(f32(166), (renderer.canvas_width-32-gap*f32(count-1))/f32(count))
	left := (renderer.canvas_width-width*f32(count)-gap*f32(count-1))*0.5
	return {left+f32(index)*(width+gap), renderer.canvas_height-160, width, 154}
}

gothic_card_accent :: proc(id: game.Card_Id) -> rl.Color {
	if game.card_is_board_device(id) || id == .Storm_Crown { return {42, 93, 125, 255} }
	switch gothic_card_icon(id) {
	case 2, 7, 17, 22: return {72, 92, 42, 255}
	case 4, 14, 16, 21: return {98, 57, 122, 255}
	case 1, 5, 15, 19: return {60, 84, 93, 255}
	case 3, 10, 11, 20: return {122, 88, 34, 255}
	case: return {130, 43, 45, 255}
	}
}

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
tactical_card_time_badge :: proc(id: game.Card_Id) -> cstring {
	cost := game.tactical_card_time_cost(id)
	if cost <= 0 { return "0s" }
	return fmt.ctprintf("-%.0fs", cost)
}

SCOPA_CARD_SIZE :: rl.Vector2{60, 96}

// The source rectangle of a Scopa card in its sheet.
scopa_card_source :: proc(id: game.Card_Id) -> rl.Rectangle {
	return {0 if id == .Sei_Denari else SCOPA_CARD_SIZE.x+2, 0, SCOPA_CARD_SIZE.x, SCOPA_CARD_SIZE.y}
}

// Draws a Scopa card face into `dest` (pixel-exact when the scale is whole).
draw_scopa_face :: proc(renderer: ^Renderer, id: game.Card_Id, dest: rl.Rectangle, rotation: f32 = 0, tint: rl.Color = rl.WHITE) {
	texture := renderer.tactical.art.scopa
	if texture.id == 0 { return }
	rl.DrawTexturePro(texture, scopa_card_source(id), dest, {dest.width*0.5, dest.height*0.5}, rotation, tint)
}

// The Scopa pair is a real playing card on green felt rather than a gothic
// crest: the Neapolitan face fills the height, cost and time sit at the corners.
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

draw_tactical_card :: proc(renderer: ^Renderer, bounds: rl.Rectangle, card: game.Card_Instance, definition: game.Card_Definition,
	slot: int, affordable, selected, hovered, available: bool) {
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
	// No animated raise changes the card's pointer target or masks its neighbor.
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
	name := fmt.ctprintf("%s", definition.name)
	if card.upgrade_level > 0 { name = fmt.ctprintf("%s +%d", definition.name, card.upgrade_level) }
	gothic_text_fit(renderer, name, {x+37, y+13, width-45, 21}, 16, ink)
	// A smaller recessed crest leaves room for both effect lines in an eight-card hand.
	center_x := x+width*0.5+12
	rl.DrawRectangleRec({center_x-23, y+43, 46, 32}, {99, 105, 111, 19})
	rl.DrawRectangleRec({center_x-15, y+36, 30, 7}, {99, 105, 111, 19})
	rl.DrawLineEx({center_x-25, y+44}, {center_x-25, y+75}, 1, {114, 102, 83, 75})
	rl.DrawLineEx({center_x+25, y+44}, {center_x+25, y+75}, 1, {114, 102, 83, 75})
	for mark in 0..=int(definition.rarity) { gothic_inlay(x+width-14, y+43+f32(mark)*8, 2, rarity) }
	icon := gothic_card_icon(card.definition_id)
	icon_bounds := rl.Rectangle{x+40, y+36, width-56, 44}
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
	first, second := gothic_card_lines(card, definition.tactical)
	if width < CARD_NARROW_WIDTH {
		if short_first, short_second, short := gothic_card_narrow_lines(card, definition.tactical); short { first, second = short_first, short_second }
	}
	gothic_text_fit(renderer, first, {x+10, y+90, width-20, 18}, 14, ink)
	gothic_text_fit(renderer, second, {x+10, y+109, width-20, 17}, 12, ink)
	rl.DrawRectangleRec({x+9, y+130, width-18, 17}, {41, 42, 45, 24})
	gothic_rule(x+10, y+128, width-20, rarity)
	gothic_text_fit(renderer, tactical_card_target_label(definition), {x+10, y+132, width-32, 17}, 12, accent)
	gothic_text(renderer, fmt.ctprintf("%d", slot+1), x+width-18, y+132, 12, ink)
}

draw_tactical_card_inspector :: proc(renderer: ^Renderer, card: game.Card_Instance, definition: game.Card_Definition, selected: bool) {
	x, y := f32(25), TACTICAL_HUD_HEIGHT+f32(26)
	gothic_frame({x-11, y-8, 218, 172}, GOTHIC_RECESS, GOTHIC_STEEL)
	name := fmt.ctprintf("%s", definition.name)
	if card.upgrade_level > 0 { name = fmt.ctprintf("%s +%d", definition.name, card.upgrade_level) }
	gothic_text_fit(renderer, name, {x, y, 195, 25}, 18, GOTHIC_PAPER)
	gothic_rule(x, y+29, 190, gothic_rarity_accent(definition.rarity))
	gothic_text_fit(renderer, fmt.ctprintf("ENERGIA %d / TEMPO %s", definition.cost, tactical_card_time_badge(card.definition_id)), {x, y+35, 193, 18}, 14, GOTHIC_BLUE)
	gothic_text_fit(renderer, tactical_card_target_label(definition), {x, y+54, 193, 17}, 12, GOTHIC_MUTED)
	first, second := gothic_card_lines(card, definition.tactical)
	gothic_text_fit(renderer, first, {x, y+76, 192, 20}, 16, GOTHIC_PAPER)
	gothic_text_fit(renderer, second, {x, y+97, 192, 18}, 14, GOTHIC_PAPER)
	reaction: cstring = ""
	// A second rule line, where the keyword tags go when the card has none.
	rule: cstring = ""
	if card.definition_id == .Shadow_Step { reaction, rule = "NEMICI E TIMER FERMI", "DIAGONALE SUL BATTITO" }
	if card.definition_id == .Poison_Pool { reaction, rule = "AREE CHIUSE: SI RIEMPIONO", "OGNI CELLA ENTRATA AVVELENA" }
	if card.definition_id == .Wildfire { reaction, rule = "CRESCE A OGNI NUOVA FINESTRA", "SI SPEGNE ALLA QUINTA" }
	if card.definition_id == .Deflect { reaction, rule = "IL NEMICO PRENDE IL COLPO", "NO BOMBE, TRAPPOLE, STATUS" }
	if card.definition_id == .Coffin { reaction, rule = "+ VEL 2 O BRU 1 O RAL 1", "LINEA DI TIRO / 1s L'UNA" }
	if card.definition_id == .Fate_Dice { reaction, rule = "1 VEL 2 BRU 3 RAL 4 VITA", "5 CRITICO / 6+ LETALE" }
	if card.definition_id == .Venom_Blade { reaction, rule = "IL DADO DECIDE I COLPI", "LE CARICHE SI SOMMANO" }
	if card.definition_id == .Guard || card.definition_id == .Purifying_Guard { reaction = "QTE: BLOCK / PARRY" }
	if card.definition_id == .Thorn_Coat { reaction = "QTE: DEVIAZIONE (FRECCE)" }
	if card.definition_id == .Afterimage { reaction = "IGNORA RECUPERO SCHIVA" }
	if card.definition_id == .Prismatic_Barrage { reaction = "SCUDO PRIMA / 2s" }
	if card.definition_id == .Twin_Venom { reaction = "VELENO: A OGNI SUA AZIONE" }
	if game.card_is_board_device(card.definition_id) { reaction = "USA IL PULSANTE ATTIVA" }
	if card.definition_id == .Shock_Floor { reaction = "TRAPPOLA: INGRESSO NEMICO" }
	if card.definition_id == .Tesla_Coil { reaction = "ATTIVA / 2-3 TESLA RESTANO" }
	if definition.tactical {
		if card.definition_id == .Heavy_Blow { reaction = "SALTA AZIONE / RECUPERA 1s" }
		if card.definition_id == .Strike { reaction = "PREMIA IL CONTRATTACCO" }
		if card.definition_id == .Shove || card.definition_id == .Grappling_Hook { reaction = "SPOSTARE INTERROMPE LA MIRA" }
		if card.definition_id == .Battle_Focus { reaction = "OLTRE I MURI RESTA LA FOG" }
		if card.definition_id == .Dash { reaction = "NON USA IL RECUPERO SCHIVA" }
		if card.definition_id == .Toxic_Wave { reaction = "AREA 5X5 / RISPETTA I MURI" }
	}
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
	if selected { rl.DrawRectangle(c.int(x-11), c.int(y-8), 3, 172, GOTHIC_RED) }
}

draw_tactical_hand :: proc(renderer: ^Renderer, room: ^game.Room,
	hovered, selected, dragged: u32, mouse: view.Vec2) {
	deck, phase := renderer_hand_deck(renderer, room)
	if phase != .Combat || !deck.combat_active { return }
	available := !renderer_blocks_player_input(renderer) && game.tactical_allows_cards(room)
	recovering := game.tactical_is_recovering(room)
	top := renderer.canvas_height-TACTICAL_HAND_HEIGHT
	first_bounds := tactical_hand_card_bounds(renderer, 0, deck.hand_count)
	last_bounds := tactical_hand_card_bounds(renderer, max(0, deck.hand_count-1), deck.hand_count)
	left := first_bounds.x if deck.hand_count > 0 else f32(24)
	right := last_bounds.x+last_bounds.width if deck.hand_count > 0 else renderer.canvas_width-24
	if right-left < 640 { left = (renderer.canvas_width-640)*0.5; right = left+640 }
	rl.DrawRectangleGradientV(0, c.int(top-14), c.int(renderer.canvas_width), c.int(TACTICAL_HAND_HEIGHT+14), {8, 13, 21, 0}, {8, 13, 21, 245})
	gothic_text(renderer, fmt.ctprintf("ENERGIA %d/%d", deck.energy, deck.rules.max_energy), left+2, top+3, 14, GOTHIC_PAPER)
	spacing := min(f32(15), f32(60)/f32(max(i32(1), deck.rules.max_energy)))
	for energy in 0..<int(deck.rules.max_energy) {
		gothic_inlay(left+110+f32(energy)*spacing, top+11, min(f32(4),spacing*0.35), GOTHIC_BLUE if energy < int(deck.energy) else GOTHIC_STEEL)
	}
	gothic_text_fit(renderer, fmt.ctprintf("MAZZO %d / SCARTI %d / ESAURITE %d", deck.draw_count, deck.discard_count, deck.exhaust_count), {right-205, top+5, 205, 17}, 10, GOTHIC_MUTED)
	hint: cstring = ""
	if selected != 0 {
		if index, found := game.hand_card_index_by_id(deck, selected); found {
			definition, _ := game.card_definition_by_id(deck.hand[index].definition_id, true)
			hint = "SCEGLI BERSAGLIO / DESTRO: ANNULLA" if game.card_requires_spatial_target(definition) else "CLIC DI NUOVO: GIOCA"
		}
	}
	// FERETRO: how its arrows are loosed, and while Ctrl is held, where.
	if arrows := game.player_charges(room, .Arrows); arrows > 0 && selected == 0 {
		hint = fmt.ctprintf("CTRL+CLIC SU UN NEMICO: FRECCIA (%d)", arrows)
	}
	if renderer.tactical.arrow_aim { hint = "CLIC SU UN NEMICO EVIDENZIATO: FRECCIA" }
	if recovering { hint = "RECUPERO / PUOI MUOVERTI" }
	if game.tactical_is_stunned(room) { hint = "STORDITO / SOLO CARTE" }
	if game.tactical_shadow_active(room) { hint = "OMBRA / SOLO PASSI" }
	if right-left > 580 { gothic_text_fit(renderer, hint, {left+180, top+5, right-left-398, 17}, 10, GOTHIC_BLUE) }
	for card, index in deck.hand[:deck.hand_count] {
		definition, found := game.card_definition_by_id(card.definition_id, true)
		if !found { continue }
		draw_tactical_card(renderer, tactical_hand_card_bounds(renderer, index, deck.hand_count), card, definition, index,
			deck.energy >= definition.cost, card.id == selected || card.id == dragged, card.id == hovered, available)
	}
	active := dragged if dragged != 0 else (hovered if hovered != 0 else selected)
	if index, found := game.hand_card_index_by_id(deck, active); found {
		card := deck.hand[index]
		definition, _ := game.card_definition_by_id(card.definition_id, true)
		draw_tactical_card_inspector(renderer, card, definition, selected == active)
		if dragged != 0 { gothic_text(renderer, fmt.ctprintf("%s", definition.name), mouse.x+14, mouse.y-18, 16, GOTHIC_PAPER) }
	}
	if active == 0 { draw_tactical_enemy_inspector(renderer, room) }
}
