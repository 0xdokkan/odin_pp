package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

relic_color :: proc(id: game.Relic_Id) -> rl.Color {
	switch id {
	case .Iron_Knuckle: return {107, 217, 192, 255}
	case .Ash_Bookmark: return {219, 160, 117, 255}
	case .Swift_Soles: return {122, 204, 235, 255}
	case .Venom_Vial: return {164, 212, 109, 255}
	case .Guard_Sigil: return {151, 172, 245, 255}
	case .Mending_Thread: return {235, 141, 170, 255}
	case .None, .Count: return {190, 190, 190, 255}
	}
	return {}
}

relic_mark :: proc(id: game.Relic_Id) -> cstring {
	switch id {
	case .Iron_Knuckle: return "K"
	case .Ash_Bookmark: return "A"
	case .Swift_Soles: return "S"
	case .Venom_Vial: return "V"
	case .Guard_Sigil: return "G"
	case .Mending_Thread: return "M"
	case .None, .Count: return "?"
	}
	return "?"
}

draw_relic_text :: proc(value: string, x, y, width, size: c.int, color: rl.Color, theme: ^Renderer = nil) {
	start, last_space := 0, -1
	line_y := y
	for index in 0..<len(value) {
		if value[index] == ' ' { last_space = index }
		if menu_measure_text(theme, fmt.ctprintf("%s", value[start:index+1]), size) <= width || last_space < start { continue }
		menu_text(theme, fmt.ctprintf("%s", value[start:last_space]), x, line_y, size, color)
		line_y += size+5
		start = last_space+1
		last_space = -1
	}
	if start < len(value) { menu_text(theme, fmt.ctprintf("%s", value[start:]), x, line_y, size, color) }
}

relic_choice_bounds :: proc(width, height: f32, index, count: int) -> rl.Rectangle {
	if count < 1 || count > game.RELIC_OFFER_COUNT || index < 0 || index >= count || width <= 0 || height <= 0 { return {} }
	gap: f32 = 22
	card_width := min(f32(260), (width-64-gap*f32(count-1))/f32(count))
	return {(width-card_width*f32(count)-gap*f32(count-1))*0.5+f32(index)*(card_width+gap),
		140, card_width, max(f32(180), min(f32(282), height-232))}
}

relic_choice_at_point :: proc(run: ^game.Run_State, width, height: f32, point: view.Vec2) -> int {
	if !game.run_has_relic_choice(run) { return -1 }
	for index in 0..<run.relic_reward.offers.count {
		if point_in_rectangle(point, relic_choice_bounds(width, height, index, run.relic_reward.offers.count)) { return index }
	}
	return -1
}

draw_relic_reward_screen :: proc(run: ^game.Run_State, width, height: f32, hovered: int, skip_hovered: bool, theme: ^Renderer = nil) {
	if !game.run_has_relic_choice(run) { return }
	menu_rectangle(theme, 0, 0, c.int(width), c.int(height), CANVAS_BACKGROUND)
	menu_rectangle(theme, 0, 0, c.int(width), 92, rl.Color{15, 18, 21, 255})
	menu_text(theme, "CHOOSE A RELIC", 28, 20, 25, rl.Color{239, 222, 165, 255})
	subtitle: cstring = "START YOUR RUN WITH A DIFFERENT TACTIC"
	if run.relic_reward.origin == .Elite { subtitle = "ELITE CLEARED / YOUR CARD REWARD FOLLOWS" }
	if run.relic_reward.origin == .Treasure { subtitle = "TREASURE OPENED / KEEP ONE RELIC FOR THIS RUN" }
	menu_text(theme, subtitle, 28, 57, 13, rl.Color{170, 185, 181, 255})
	menu_text(theme, "PASSIVE EFFECTS / NO ENERGY COST", 28, 110, 12, rl.Color{180, 184, 174, 255})
	for id, index in run.relic_reward.offers.choices[:run.relic_reward.offers.count] {
		definition, valid := game.relic_definition(id)
		if !valid { continue }
		bounds := relic_choice_bounds(width, height, index, run.relic_reward.offers.count)
		color := relic_color(id)
		menu_rectangle_rec(theme, bounds, rl.Color{28, 33, 39, 255})
		menu_outline(theme, bounds, 3 if index == hovered else 1, color)
		x, y := c.int(bounds.x), c.int(bounds.y)
		menu_text(theme, fmt.ctprintf("%d", index+1), x+16, y+15, 18, color)
		center := rl.Vector2{bounds.x+bounds.width/2, bounds.y+80}
		if menu_themed(theme) {
			icon := 1
			switch id {
			case .Iron_Knuckle: icon = 12
			case .Ash_Bookmark: icon = 9
			case .Swift_Soles: icon = 5
			case .Venom_Vial: icon = 2
			case .Guard_Sigil: icon = 1
			case .Mending_Thread: icon = 15
			case .None, .Count:
			}
			gothic_atlas_icon(theme.tactical.art.icons, theme.tactical.art.icon_sources[icon], {center.x-35, center.y-35, 70, 70})
		} else {
			menu_poly(theme, center, 6, 34, 30, rl.Color{17, 21, 25, 255})
			menu_poly_lines(theme, center, 6, 34, 30, 2, color)
			mark := relic_mark(id)
			menu_text(theme, mark, c.int(center.x)-menu_measure_text(theme, mark, 32)/2, c.int(center.y)-16, 32, color)
		}
		menu_text(theme, fmt.ctprintf("%s", definition.name), x+18, y+130, 18, color)
		draw_relic_text(definition.description, x+18, y+165, c.int(bounds.width)-36, 14,
			rl.Color{220, 224, 220, 255}, theme = theme)
		menu_text(theme, "KEPT UNTIL THE END OF THE RUN", x+18, y+c.int(bounds.height)-28, 10,
			rl.Color{148, 162, 159, 255})
	}
	bounds := reward_skip_bounds(width, height)
	menu_rectangle_rec(theme, bounds, rl.Color{44, 49, 52, 255})
	menu_outline(theme, bounds, 2 if skip_hovered else 1, rl.Color{169, 180, 177, 255})
	menu_text(theme, "S  SKIP", c.int(bounds.x)+18, c.int(bounds.y)+12, 16, rl.Color{216, 221, 216, 255})
	menu_text(theme, "1-3 OR CLICK TO CHOOSE", 28, c.int(height)-32, 12, rl.Color{166, 179, 176, 255})
	menu_text(theme, fmt.ctprintf("OWNED %d/%d", run.player.relics.count, game.MAX_RUN_RELICS),
		c.int(width)-130, c.int(height)-32, 12, rl.Color{166, 179, 176, 255})
}

relic_bar_contains_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2,
	raised_card_id: u32 = 0) -> bool {
	if renderer == nil || room == nil || room.player == nil { return false }
	relics := &room.player.relics
	if renderer.tactical.enabled && renderer.tactical.snapshot != nil && renderer.tactical.snapshot.valid {
		relics = &renderer.tactical.snapshot.relics
	} else if renderer_blocks_player_input(renderer) && renderer.timeline.view.valid {
		relics = &renderer.timeline.view.relics
	}
	if relics.count <= 0 { return false }
	// The hand is drawn above this bar, including the enlarged hovered card.
	deck, _ := renderer_hand_deck(renderer, room)
	if _, over_card := hand_card_at_point(renderer, deck, point, raised_card_id); over_card { return false }
	return point_in_rectangle(point, relic_bar_bounds(renderer, relics.count))
}

relic_bar_bounds :: proc(renderer: ^Renderer, count: int) -> rl.Rectangle {
	if renderer.tactical.enabled { return {18, TACTICAL_HUD_HEIGHT+3, f32(count)*25, 20} }
	return {14, renderer.canvas_height-HAND_RESERVED_HEIGHT-34, f32(count)*32, 27}
}

draw_relic_bar :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2, mouse_inside: bool,
	raised_card_id: u32 = 0) {
	relics := &room.player.relics
	if renderer.tactical.enabled && renderer.tactical.snapshot != nil && renderer.tactical.snapshot.valid {
		relics = &renderer.tactical.snapshot.relics
	} else if renderer_blocks_player_input(renderer) && renderer.timeline.view.valid {
		relics = &renderer.timeline.view.relics
	}
	if relics.count == 0 { return }
	can_hover := mouse_inside && relic_bar_contains_point(renderer, room, point, raised_card_id)
	if renderer.tactical.enabled {
		bar := relic_bar_bounds(renderer, relics.count)
		gothic_text(renderer,"PASSIVE",bar.x+bar.width+7,bar.y+4,10,GOTHIC_MUTED)
		hovered: game.Relic_Id
		for id, index in relics.owned[:relics.count] {
			bounds := rl.Rectangle{bar.x+f32(index)*25, bar.y, 20, 20}
			rl.DrawRectangleRec(bounds, GOTHIC_INK)
			rl.DrawRectangleLinesEx(bounds, 1, GOTHIC_MUTED)
			gothic_text(renderer, relic_mark(id), bounds.x+5, bounds.y+1, 14, GOTHIC_PAPER)
			if can_hover && point_in_rectangle(point, bounds) { hovered = id }
		}
		if definition, found := game.relic_definition(hovered); found {
			gothic_frame({14, 137, 310, 105}, GOTHIC_INK, GOTHIC_PAPER)
			gothic_text(renderer, fmt.ctprintf("%s", definition.name), 25, 145, 18, GOTHIC_PAPER)
			gothic_wrapped_text(renderer, definition.description, 25, 171, 286, GOTHIC_MUTED)
		}
		return
	}
	y := renderer.canvas_height-HAND_RESERVED_HEIGHT-34
	rl.DrawText("RELICS", 14, c.int(y)-14, 10, rl.Color{178, 182, 166, 255})
	hovered: game.Relic_Id
	for id, index in relics.owned[:relics.count] {
		bounds := rl.Rectangle{14+f32(index)*32, y, 27, 27}
		color := relic_color(id)
		rl.DrawRectangleRec(bounds, rl.Color{16, 20, 24, 245})
		rl.DrawRectangleLinesEx(bounds, 1, color)
		rl.DrawText(relic_mark(id), c.int(bounds.x)+8, c.int(bounds.y)+6, 15, color)
		if can_hover && point_in_rectangle(point, bounds) { hovered = id }
	}
	if definition, found := game.relic_definition(hovered); found {
		rl.DrawRectangle(14, c.int(y)-109, 324, 91, rl.Color{12, 15, 18, 245})
		rl.DrawRectangleLines(14, c.int(y)-109, 324, 91, relic_color(hovered))
		rl.DrawText(fmt.ctprintf("%s", definition.name), 24, c.int(y)-99, 15, relic_color(hovered))
		draw_relic_text(definition.description, 24, c.int(y)-74, 302, 12, rl.Color{216, 223, 215, 255})
	}
}
