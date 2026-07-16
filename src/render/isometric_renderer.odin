package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import level "../level"
import view "../view"

CANVAS_BACKGROUND :: rl.Color{24, 27, 31, 255}
LETTERBOX_COLOR   :: rl.Color{10, 12, 15, 255}

MAX_LOOT_ANIMATIONS          :: 32
LOOT_ANIMATION_DURATION      :: f32(0.32)
MAX_ENEMY_MOVE_ANIMATIONS    :: game.MAX_ENEMIES_PER_ROOM
ENEMY_MOVE_ANIMATION_DURATION :: f32(0.42)
HAND_RESERVED_HEIGHT         :: f32(66)
HAND_CARD_WIDTH              :: f32(132)
HAND_CARD_HEIGHT             :: f32(166)
HAND_CARD_STEP               :: f32(86)
HAND_CARD_VISIBLE_HEIGHT     :: f32(72)
HAND_CARD_ARC_DROP           :: f32(3)
HAND_RAISED_CARD_WIDTH       :: f32(144)
HAND_RAISED_CARD_HEIGHT      :: f32(180)
HAND_RAISED_CARD_MARGIN      :: f32(8)
REFOCUS_BUTTON_X             :: f32(360)
REFOCUS_BUTTON_Y             :: f32(20)
REFOCUS_BUTTON_WIDTH         :: f32(102)
REFOCUS_BUTTON_HEIGHT        :: f32(30)
MAX_CARD_KEYWORD_TAGS        :: 3

INTENT_MOVE_FILL       :: rl.Color{238, 174, 73, 38}
INTENT_MOVE_OUTLINE    :: rl.Color{246, 207, 92, 210}
INTENT_THREAT_FILL     :: rl.Color{190, 68, 70, 46}
INTENT_THREAT_OUTLINE  :: rl.Color{235, 91, 91, 225}
INTENT_WAIT_OUTLINE    :: rl.Color{147, 158, 158, 220}
INTENT_FOCUS_OUTLINE   :: rl.Color{255, 247, 237, 255}

Loot_Animation :: struct {
	kind:          game.Loot_Kind,
	amount:        i32,
	from_position: grid.Position,
	to_position:   grid.Position,
	target:        game.Entity_Ref,
	elapsed:       f32,
	duration:      f32,
}

Enemy_Move_Animation :: struct {
	target:    game.Entity_Ref,
	from_grid: view.Vec2,
	to_grid:   view.Vec2,
	elapsed:   f32,
	duration:  f32,
}

Renderer :: struct {
	projection:       view.Isometric_Projection,
	camera:           view.Isometric_Camera,
	canvas_width:     f32,
	canvas_height:    f32,
	hovered_cell:     grid.Position,
	has_hovered_cell: bool,
	loot_animations:         [MAX_LOOT_ANIMATIONS]Loot_Animation,
	loot_animation_count:    int,
	loot_animations_dropped: int,
	enemy_move_animations:         [MAX_ENEMY_MOVE_ANIMATIONS]Enemy_Move_Animation,
	enemy_move_animation_count:    int,
	enemy_move_animations_dropped: int,
	timeline: Presentation_Timeline,
}

Tile_Vertices :: struct {
	top, right, bottom, left: view.Vec2,
}

create :: proc(canvas_width, canvas_height: int, level_data: ^level.Level) -> Renderer {
	assert(level_data != nil)
	result := Renderer{
		projection = {tile_width = 64, tile_height = 32},
		camera = view.make_camera(),
		canvas_width = cast(f32)canvas_width,
		canvas_height = cast(f32)canvas_height,
	}
	frame_level(&result, level_data)
	return result
}

frame_level :: proc(renderer: ^Renderer, level_data: ^level.Level) {
	assert(renderer != nil && level_data != nil)
	gameplay_height := max(renderer.canvas_height-HAND_RESERVED_HEIGHT, f32(1))
	view.frame_grid(
		&renderer.camera,
		&renderer.projection,
		level_data.tiles.width,
		level_data.tiles.height,
		renderer.canvas_width,
		gameplay_height,
		64,
	)
}

hand_card_step :: proc(renderer: ^Renderer, card_count: int) -> f32 {
	if renderer == nil || card_count <= 1 {
		return 0
	}
	horizontal_padding: f32 = 24
	maximum_step := (renderer.canvas_width-horizontal_padding*2-HAND_CARD_WIDTH)/f32(card_count-1)
	return min(HAND_CARD_STEP, max(f32(42), maximum_step))
}

hand_card_bounds :: proc(renderer: ^Renderer, card_index, card_count: int) -> rl.Rectangle {
	if renderer == nil || card_count <= 0 || card_count > game.MAX_HAND_CARDS ||
	   card_index < 0 || card_index >= card_count {
		return {}
	}
	step := hand_card_step(renderer, card_count)
	total_width := HAND_CARD_WIDTH+step*f32(card_count-1)
	start_x := (renderer.canvas_width-total_width)*0.5
	center_index := f32(card_count-1)*0.5
	distance_from_center := abs(f32(card_index)-center_index)
	return {
		x = start_x+f32(card_index)*step,
		y = renderer.canvas_height-HAND_CARD_VISIBLE_HEIGHT+distance_from_center*HAND_CARD_ARC_DROP,
		width = HAND_CARD_WIDTH,
		height = HAND_CARD_HEIGHT,
	}
}

hand_raised_card_bounds :: proc(renderer: ^Renderer, card_index, card_count: int) -> rl.Rectangle {
	resting := hand_card_bounds(renderer, card_index, card_count)
	if resting.width <= 0 {
		return {}
	}
	center_x := resting.x+resting.width*0.5
	return {
		x = clamp(
			center_x-HAND_RAISED_CARD_WIDTH*0.5,
			HAND_RAISED_CARD_MARGIN,
			renderer.canvas_width-HAND_RAISED_CARD_WIDTH-HAND_RAISED_CARD_MARGIN,
		),
		y = renderer.canvas_height-HAND_RAISED_CARD_HEIGHT-HAND_RAISED_CARD_MARGIN,
		width = HAND_RAISED_CARD_WIDTH,
		height = HAND_RAISED_CARD_HEIGHT,
	}
}

dragged_card_bounds :: proc(renderer: ^Renderer, point: view.Vec2) -> rl.Rectangle {
	if renderer == nil {
		return {}
	}
	desired_x := point.x-HAND_RAISED_CARD_WIDTH*0.5
	desired_y := point.y-HAND_RAISED_CARD_HEIGHT*0.5
	return {
		x = clamp(
			desired_x,
			HAND_RAISED_CARD_MARGIN,
			renderer.canvas_width-HAND_RAISED_CARD_WIDTH-HAND_RAISED_CARD_MARGIN,
		),
		y = clamp(
			desired_y,
			f32(108),
			renderer.canvas_height-HAND_RAISED_CARD_HEIGHT-HAND_RAISED_CARD_MARGIN,
		),
		width = HAND_RAISED_CARD_WIDTH,
		height = HAND_RAISED_CARD_HEIGHT,
	}
}

point_in_rectangle :: proc(point: view.Vec2, bounds: rl.Rectangle) -> bool {
	return point.x >= bounds.x && point.x <= bounds.x+bounds.width &&
	       point.y >= bounds.y && point.y <= bounds.y+bounds.height
}

refocus_button_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	if renderer == nil {
		return {}
	}
	return {
		x = REFOCUS_BUTTON_X,
		y = REFOCUS_BUTTON_Y,
		width = REFOCUS_BUTTON_WIDTH,
		height = REFOCUS_BUTTON_HEIGHT,
	}
}

refocus_button_at_point :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	return renderer != nil && point_in_rectangle(point, refocus_button_bounds(renderer))
}

refocus_button_is_enabled :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && !renderer_timeline_is_busy(renderer)
}

card_drop_area_contains :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	return renderer != nil && point.x >= 0 && point.x <= renderer.canvas_width &&
	       point.y >= 0 && point.y < renderer.canvas_height-HAND_RESERVED_HEIGHT &&
	       !refocus_button_at_point(renderer, point)
}

dragged_card_is_over_grid :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	return renderer != nil && renderer.has_hovered_cell && card_drop_area_contains(renderer, point)
}

hand_card_at_point :: proc(
	renderer: ^Renderer,
	deck: ^game.Deck_State,
	point: view.Vec2,
	raised_card_id: u32 = 0,
) -> (card_index: int, found: bool) {
	if renderer == nil || deck == nil || !deck.combat_active {
		return 0, false
	}
	if raised_card_id != 0 {
		if raised_index, raised_found := game.hand_card_index_by_id(deck, raised_card_id); raised_found {
			bounds := hand_raised_card_bounds(renderer, raised_index, deck.hand_count)
			if point_in_rectangle(point, bounds) {
				return raised_index, true
			}
		}
	}
	index := deck.hand_count-1
	for index >= 0 {
		bounds := hand_card_bounds(renderer, index, deck.hand_count)
		if point_in_rectangle(point, bounds) {
			return index, true
		}
		index -= 1
	}
	return 0, false
}

card_colors :: proc(id: game.Card_Id, affordable: bool) -> (fill, outline: rl.Color) {
	switch id {
	case .Strike:
		fill, outline = rl.Color{74, 39, 42, 245}, rl.Color{224, 99, 86, 255}
	case .Arc_Bolt:
		fill, outline = rl.Color{31, 52, 67, 245}, rl.Color{90, 204, 227, 255}
	case .Piercing_Ray:
		fill, outline = rl.Color{28, 57, 61, 245}, rl.Color{91, 214, 204, 255}
	case .Cross_Slash:
		fill, outline = rl.Color{66, 39, 51, 245}, rl.Color{232, 119, 162, 255}
	case .Firebomb:
		fill, outline = rl.Color{75, 43, 27, 245}, rl.Color{246, 146, 72, 255}
	case .Guard:
		fill, outline = rl.Color{34, 55, 69, 245}, rl.Color{101, 174, 218, 255}
	case .Toxic_Wave:
		fill, outline = rl.Color{35, 62, 43, 245}, rl.Color{113, 190, 91, 255}
	case .Thorn_Coat:
		fill, outline = rl.Color{67, 50, 29, 245}, rl.Color{238, 174, 73, 255}
	case .Afterimage:
		fill, outline = rl.Color{53, 46, 70, 245}, rl.Color{194, 184, 226, 255}
	case .Counter_Rune:
		fill, outline = rl.Color{68, 59, 30, 245}, rl.Color{246, 207, 92, 255}
	case .Battle_Focus:
		fill, outline = rl.Color{31, 61, 56, 245}, rl.Color{91, 214, 176, 255}
	case .Calculated_Risk:
		fill, outline = rl.Color{67, 43, 34, 245}, rl.Color{238, 174, 73, 255}
	case .Spark_Forge:
		fill, outline = rl.Color{55, 45, 66, 245}, rl.Color{209, 151, 236, 255}
	case .Spark:
		fill, outline = rl.Color{57, 54, 31, 245}, rl.Color{246, 207, 92, 255}
	case .Count:
		fill, outline = rl.Color{45, 49, 52, 245}, rl.Color{105, 116, 116, 255}
	}
	if !affordable {
		fill = rl.Color{39, 42, 45, 245}
		outline = rl.Color{91, 96, 98, 255}
	}
	return
}

card_detail_lines :: proc(card: game.Card_Instance) -> (first, second: cstring) {
	upgrade := card.upgrade_level
	switch card.definition_id {
	case .Strike:
		return fmt.ctprintf("DEAL %d DAMAGE", 2+upgrade), "RANGE 1"
	case .Arc_Bolt:
		return fmt.ctprintf("DEAL %d DAMAGE", 3+upgrade), "RANGE 1-3"
	case .Piercing_Ray:
		return fmt.ctprintf("DEAL %d IN LINE", 2+upgrade), "RANGE 1-5"
	case .Cross_Slash:
		return fmt.ctprintf("DEAL %d IN CROSS", 2+upgrade), "RANGE 1-3"
	case .Firebomb:
		return fmt.ctprintf("DEAL %d IN 3X3", 2+upgrade), "RANGE 1-3"
	case .Guard:
		return fmt.ctprintf("GAIN %d SHIELD", 3+upgrade), "LASTS 3 PULSES"
	case .Toxic_Wave:
		return fmt.ctprintf("APPLY %d POISON", 1+upgrade), "TO EVERY ENEMY"
	case .Thorn_Coat:
		return fmt.ctprintf("GAIN %d THORNS", 1+upgrade), "LASTS 3 PULSES"
	case .Afterimage:
		return fmt.ctprintf("GAIN %d AFTERIMAGE", 1+upgrade), "LASTS 4 PULSES"
	case .Counter_Rune:
		return fmt.ctprintf("COUNTER FOR %d", 2+upgrade), "2 CHARGES"
	case .Battle_Focus:
		return "DRAW 2", "EXHAUST"
	case .Calculated_Risk:
		return "DRAW 2", "DISCARD 1"
	case .Spark_Forge:
		return "CREATE 1 SPARK", "TEMPORARY"
	case .Spark:
		return fmt.ctprintf("DEAL %d DAMAGE", 2+upgrade), "TEMP - RANGE 1-2"
	case .Count:
	}
	return "", ""
}

card_short_name :: proc(id: game.Card_Id) -> cstring {
	switch id {
	case .Strike:
		return "STRIKE"
	case .Arc_Bolt:
		return "ARC"
	case .Piercing_Ray:
		return "RAY"
	case .Cross_Slash:
		return "CROSS"
	case .Firebomb:
		return "BOMB"
	case .Guard:
		return "GUARD"
	case .Toxic_Wave:
		return "TOXIC"
	case .Thorn_Coat:
		return "THORNS"
	case .Afterimage:
		return "AFTER"
	case .Counter_Rune:
		return "RUNE"
	case .Battle_Focus:
		return "FOCUS"
	case .Calculated_Risk:
		return "RISK"
	case .Spark_Forge:
		return "FORGE"
	case .Spark:
		return "SPARK"
	case .Count:
	}
	return ""
}

draw_card_sigil :: proc(bounds: rl.Rectangle, id: game.Card_Id, color: rl.Color) {
	panel := rl.Rectangle{
		x = bounds.x+10,
		y = bounds.y+42,
		width = bounds.width-20,
		height = 61,
	}
	rl.DrawRectangleRec(panel, rl.Color{15, 19, 22, 150})
	rl.DrawRectangleLinesEx(panel, 1, rl.Color{92, 102, 102, 170})
	center := rl.Vector2{panel.x+panel.width*0.5, panel.y+panel.height*0.5}
	radius := f32(17)
	switch id {
	case .Strike:
		rl.DrawLineEx({center.x-radius, center.y+radius}, {center.x+radius, center.y-radius}, 5, color)
		rl.DrawLineEx({center.x-9, center.y-radius}, {center.x+radius, center.y+9}, 3, color)
	case .Arc_Bolt:
		points := [?]rl.Vector2{
			{center.x-16, center.y-18},
			{center.x+1, center.y-5},
			{center.x-7, center.y+1},
			{center.x+17, center.y+18},
		}
		for index in 0..<len(points)-1 {
			rl.DrawLineEx(points[index], points[index+1], 5, color)
		}
	case .Piercing_Ray:
		rl.DrawLineEx({center.x-radius, center.y}, {center.x+radius, center.y}, 5, color)
		rl.DrawCircleV({center.x-radius, center.y}, 4, color)
		rl.DrawCircleV({center.x+radius, center.y}, 4, color)
	case .Cross_Slash:
		rl.DrawLineEx({center.x-radius, center.y}, {center.x+radius, center.y}, 5, color)
		rl.DrawLineEx({center.x, center.y-radius}, {center.x, center.y+radius}, 5, color)
	case .Firebomb:
		rl.DrawCircleV(center, 10, color)
		directions := [?]rl.Vector2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
		for direction in directions {
			rl.DrawLineEx(
				{center.x+direction.x*12, center.y+direction.y*12},
				{center.x+direction.x*radius, center.y+direction.y*radius},
				3,
				color,
			)
		}
	case .Guard:
		rl.DrawCircleV(center, radius, color)
		rl.DrawCircleV(center, radius-5, rl.Color{24, 37, 45, 255})
	case .Toxic_Wave:
		for offset in -1..=1 {
			rl.DrawCircleV({center.x+f32(offset)*15, center.y+f32(abs(offset))*5}, 8, color)
		}
	case .Thorn_Coat:
		for offset in -1..=1 {
			x := center.x+f32(offset)*13
			rl.DrawLineEx({x-6, center.y+15}, {x, center.y-15}, 4, color)
			rl.DrawLineEx({x, center.y-15}, {x+6, center.y+15}, 4, color)
		}
	case .Afterimage:
		for offset in 0..<3 {
			rl.DrawCircleLinesV({center.x-f32(offset)*7, center.y}, radius-f32(offset)*3, color)
		}
	case .Counter_Rune:
		points := [?]rl.Vector2{
			{center.x, center.y-radius},
			{center.x+radius, center.y},
			{center.x, center.y+radius},
			{center.x-radius, center.y},
			{center.x, center.y-radius},
		}
		for index in 0..<len(points)-1 {
			rl.DrawLineEx(points[index], points[index+1], 4, color)
		}
	case .Battle_Focus:
		rl.DrawCircleLinesV(center, radius, color)
		rl.DrawCircleV(center, 4, color)
		rl.DrawLineEx({center.x-radius, center.y}, {center.x-6, center.y}, 3, color)
		rl.DrawLineEx({center.x+6, center.y}, {center.x+radius, center.y}, 3, color)
	case .Calculated_Risk:
		rl.DrawLineEx({center.x-radius, center.y-12}, {center.x+radius, center.y+12}, 4, color)
		rl.DrawLineEx({center.x-radius, center.y+12}, {center.x+radius, center.y-12}, 2, color)
	case .Spark_Forge:
		rl.DrawRectangleLines(
			c.int(center.x-12),
			c.int(center.y-12),
			24,
			24,
			color,
		)
		rl.DrawCircleV(center, 6, color)
	case .Spark:
		points := [?]rl.Vector2{
			{center.x-14, center.y-17},
			{center.x+2, center.y-4},
			{center.x-5, center.y+2},
			{center.x+14, center.y+17},
		}
		for index in 0..<len(points)-1 {
			rl.DrawLineEx(points[index], points[index+1], 4, color)
		}
	case .Count:
	}
}

Card_Keyword_Tag :: enum {
	Retain,
	Ethereal,
	Temporary,
}

card_keyword_tags :: proc(
	card: game.Card_Instance,
	definition: game.Card_Definition,
) -> (result: [MAX_CARD_KEYWORD_TAGS]Card_Keyword_Tag, count: int) {
	if definition.retain_on_refocus {
		result[count] = .Retain
		count += 1
	}
	if definition.ethereal {
		result[count] = .Ethereal
		count += 1
	}
	if card.lifetime == .Combat {
		result[count] = .Temporary
		count += 1
	}
	return
}

card_keyword_tag_label :: proc(tag: Card_Keyword_Tag, expanded: bool) -> cstring {
	switch tag {
	case .Retain:
		return "RETAIN" if expanded else "RET"
	case .Ethereal:
		return "ETHEREAL" if expanded else "ETH"
	case .Temporary:
		return "TEMPORARY" if expanded else "TEMP"
	}
	unreachable()
}

card_keyword_tag_color :: proc(tag: Card_Keyword_Tag) -> rl.Color {
	switch tag {
	case .Retain:
		return rl.Color{91, 214, 176, 255}
	case .Ethereal:
		return rl.Color{194, 184, 226, 255}
	case .Temporary:
		return rl.Color{246, 207, 92, 255}
	}
	unreachable()
}

card_keyword_tag_bounds :: proc(
	bounds: rl.Rectangle,
	tag_index: int,
	expanded: bool,
) -> rl.Rectangle {
	if tag_index < 0 || tag_index >= MAX_CARD_KEYWORD_TAGS || bounds.width <= 0 || bounds.height <= 0 {
		return {}
	}
	width: f32 = 31
	if expanded {
		width = 52
	}
	x := bounds.x+34
	if expanded {
		x = bounds.x+bounds.width-width-7
	}
	return {
		x = x,
		y = bounds.y+29+f32(tag_index)*15,
		width = width,
		height = 12,
	}
}

draw_card_keyword_tags :: proc(
	bounds: rl.Rectangle,
	card: game.Card_Instance,
	definition: game.Card_Definition,
	expanded: bool,
) {
	tags, count := card_keyword_tags(card, definition)
	for index in 0..<count {
		tag := tags[index]
		tag_bounds := card_keyword_tag_bounds(bounds, index, expanded)
		color := card_keyword_tag_color(tag)
		label := card_keyword_tag_label(tag, expanded)
		label_width := rl.MeasureText(label, 8)
		rl.DrawRectangleRec(tag_bounds, rl.Color{12, 16, 19, 235})
		rl.DrawRectangleLinesEx(tag_bounds, 1, color)
		rl.DrawText(
			label,
			c.int(tag_bounds.x+(tag_bounds.width-f32(label_width))*0.5),
			c.int(tag_bounds.y+2),
			8,
			color,
		)
	}
}

draw_card_face :: proc(
	bounds: rl.Rectangle,
	card: game.Card_Instance,
	definition: game.Card_Definition,
	slot: int,
	affordable, expanded, highlighted, selected: bool,
) {
	fill, outline := card_colors(card.definition_id, affordable)
	rl.DrawRectangleRec({bounds.x+4, bounds.y+5, bounds.width, bounds.height}, rl.Color{5, 7, 9, 150})
	rl.DrawRectangleRec(bounds, fill)
	rl.DrawRectangleLinesEx(bounds, 2, outline)
	if highlighted || selected {
		highlight_bounds := rl.Rectangle{bounds.x-2, bounds.y-2, bounds.width+4, bounds.height+4}
		highlight_color := rl.Color{247, 239, 213, 255} if highlighted else rl.Color{169, 210, 216, 255}
		rl.DrawRectangleLinesEx(highlight_bounds, 2, highlight_color)
	}

	label_color := rl.Color{237, 239, 232, 255} if affordable else rl.Color{129, 134, 134, 255}
	badge_center := rl.Vector2{bounds.x+17, bounds.y+17}
	rl.DrawCircleV(badge_center, 12, rl.Color{12, 16, 19, 245})
	rl.DrawCircleLinesV(badge_center, 12, outline)
	cost_text := fmt.ctprintf("%d", definition.cost)
	cost_width := rl.MeasureText(cost_text, 15)
	rl.DrawText(cost_text, c.int(badge_center.x)-cost_width/2, c.int(badge_center.y)-8, 15, outline)

	name_text := fmt.ctprintf("%s", definition.name) if expanded else card_short_name(card.definition_id)
	name_width := rl.MeasureText(name_text, 14)
	name_x := c.int(bounds.x+(bounds.width-f32(name_width))*0.5)
	rl.DrawText(name_text, name_x, c.int(bounds.y+11), 14, label_color)
	if expanded {
		rl.DrawText(fmt.ctprintf("%d", slot+1), c.int(bounds.x+bounds.width-17), c.int(bounds.y+11), 11, outline)
	} else {
		rl.DrawText(fmt.ctprintf("%d", slot+1), c.int(bounds.x+7), c.int(bounds.y+34), 10, outline)
	}
	draw_card_sigil(bounds, card.definition_id, outline)

	if expanded {
		first, second := card_detail_lines(card)
		first_width := rl.MeasureText(fmt.ctprintf("%s", first), 12)
		second_width := rl.MeasureText(fmt.ctprintf("%s", second), 11)
		rl.DrawText(
			fmt.ctprintf("%s", first),
			c.int(bounds.x+(bounds.width-f32(first_width))*0.5),
			c.int(bounds.y+114),
			12,
			label_color,
		)
		rl.DrawText(
			fmt.ctprintf("%s", second),
			c.int(bounds.x+(bounds.width-f32(second_width))*0.5),
			c.int(bounds.y+134),
			11,
			outline,
		)
	}
	draw_card_keyword_tags(bounds, card, definition, expanded)
	if card.upgrade_level > 0 {
		rl.DrawText(
			fmt.ctprintf("+%d", card.upgrade_level),
			c.int(bounds.x+8),
			c.int(bounds.y+bounds.height-18),
			11,
			outline,
		)
	}
}

draw_hand_counters :: proc(renderer: ^Renderer, deck: ^game.Deck_State) {
	assert(renderer != nil && deck != nil)
	bottom := renderer.canvas_height-12
	rl.DrawRectangle(12, c.int(bottom-48), 82, 48, rl.Color{12, 16, 19, 225})
	rl.DrawRectangleLines(12, c.int(bottom-48), 82, 48, rl.Color{75, 86, 87, 255})
	rl.DrawText("ENERGY", 21, c.int(bottom-41), 10, rl.Color{163, 174, 169, 255})
	rl.DrawText(
		fmt.ctprintf("%d/%d", deck.energy, deck.rules.max_energy),
		27,
		c.int(bottom-25),
		19,
		rl.Color{246, 207, 92, 255},
	)

	right := c.int(renderer.canvas_width)-12
	rl.DrawRectangle(right-116, c.int(bottom-48), 116, 48, rl.Color{12, 16, 19, 225})
	rl.DrawRectangleLines(right-116, c.int(bottom-48), 116, 48, rl.Color{75, 86, 87, 255})
	labels := [?]cstring{"DRAW", "DISC", "EXH"}
	counts := [?]int{deck.draw_count, deck.discard_count, deck.exhaust_count}
	column_width: f32 = 116.0/3.0
	for label, index in labels {
		center_x := f32(right-116)+column_width*(f32(index)+0.5)
		label_width := rl.MeasureText(label, 9)
		value_text := fmt.ctprintf("%d", counts[index])
		value_width := rl.MeasureText(value_text, 17)
		rl.DrawText(
			label,
			c.int(center_x)-label_width/2,
			c.int(bottom-41),
			9,
			rl.Color{163, 174, 169, 255},
		)
		rl.DrawText(
			value_text,
			c.int(center_x)-value_width/2,
			c.int(bottom-24),
			17,
			rl.Color{225, 229, 224, 255},
		)
	}
}

draw_refocus_button :: proc(renderer: ^Renderer, mouse_position: view.Vec2) {
	assert(renderer != nil)
	bounds := refocus_button_bounds(renderer)
	enabled := refocus_button_is_enabled(renderer)
	hovered := enabled && refocus_button_at_point(renderer, mouse_position)
	fill := rl.Color{17, 25, 28, 235}
	outline := rl.Color{91, 174, 168, 255}
	label_color := rl.Color{225, 229, 224, 255}
	if hovered {
		fill = rl.Color{28, 50, 51, 245}
		outline = rl.Color{91, 226, 213, 255}
	} else if !enabled {
		fill = rl.Color{27, 30, 33, 225}
		outline = rl.Color{75, 86, 87, 255}
		label_color = rl.Color{112, 120, 119, 255}
	}

	rl.DrawRectangleRec(bounds, fill)
	rl.DrawRectangleLinesEx(bounds, 1, outline)
	key_bounds := rl.Rectangle{x = bounds.x+6, y = bounds.y+6, width = 18, height = 18}
	rl.DrawRectangleRec(key_bounds, rl.Color{10, 14, 16, 210})
	rl.DrawRectangleLinesEx(key_bounds, 1, outline)
	key_width := rl.MeasureText("F", 11)
	rl.DrawText(
		"F",
		c.int(key_bounds.x+(key_bounds.width-f32(key_width))*0.5),
		c.int(key_bounds.y+4),
		11,
		label_color,
	)
	rl.DrawText("REFOCUS", c.int(bounds.x+31), c.int(bounds.y+9), 11, label_color)
}

renderer_hand_deck :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
) -> (^game.Deck_State, game.Room_Phase) {
	assert(renderer != nil && room != nil && room.player != nil)
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		return &renderer.timeline.view.deck, renderer.timeline.view.phase
	}
	return &room.player.deck, room.phase
}

draw_hand :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
	hovered_card_id, selected_card_id, dragged_card_id: u32,
	mouse_position: view.Vec2,
) {
	assert(renderer != nil && room != nil && room.player != nil)
	deck, phase := renderer_hand_deck(renderer, room)
	if phase != .Combat || !deck.combat_active {
		return
	}
	draw_hand_counters(renderer, deck)
	draw_refocus_button(renderer, mouse_position)
	raised_card_id := hovered_card_id
	if raised_card_id == 0 {
		raised_card_id = selected_card_id
	}
	for index in 0..<deck.hand_count {
		card := deck.hand[index]
		if card.id == dragged_card_id || card.id == raised_card_id {
			continue
		}
		definition, found := game.card_definition_by_id(card.definition_id)
		assert(found)
		bounds := hand_card_bounds(renderer, index, deck.hand_count)
		affordable := deck.energy >= definition.cost
		draw_card_face(bounds, card, definition, index, affordable, false, false, card.id == selected_card_id)
	}
	if raised_card_id != 0 {
		if index, found := game.hand_card_index_by_id(deck, raised_card_id); found {
			card := deck.hand[index]
			definition, definition_found := game.card_definition_by_id(card.definition_id)
			assert(definition_found)
			bounds := hand_raised_card_bounds(renderer, index, deck.hand_count)
			draw_card_face(
				bounds,
				card,
				definition,
				index,
				deck.energy >= definition.cost,
				true,
				card.id == hovered_card_id,
				card.id == selected_card_id,
			)
		}
	}
	if dragged_card_id != 0 && !dragged_card_is_over_grid(renderer, mouse_position) {
		if index, found := game.hand_card_index_by_id(deck, dragged_card_id); found {
			card := deck.hand[index]
			definition, definition_found := game.card_definition_by_id(card.definition_id)
			assert(definition_found)
			draw_card_face(
				dragged_card_bounds(renderer, mouse_position),
				card,
				definition,
				index,
				deck.energy >= definition.cost,
				true,
				true,
				false,
			)
		}
	}
}

clear_loot_animations :: proc(renderer: ^Renderer) {
	if renderer == nil {
		return
	}
	renderer.loot_animations = {}
	renderer.loot_animation_count = 0
	renderer.loot_animations_dropped = 0
}

clear_enemy_move_animations :: proc(renderer: ^Renderer) {
	if renderer == nil {
		return
	}
	renderer.enemy_move_animations = {}
	renderer.enemy_move_animation_count = 0
	renderer.enemy_move_animations_dropped = 0
}

clear_event_animations :: proc(renderer: ^Renderer) {
	clear_loot_animations(renderer)
	clear_enemy_move_animations(renderer)
	if renderer != nil {
		clear_event_timeline(&renderer.timeline)
	}
}

renderer_timeline_is_busy :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && event_timeline_is_busy(&renderer.timeline)
}

begin_renderer_event_timeline :: proc(
	renderer: ^Renderer,
	before: Room_Presentation,
	events: ^game.Event_Log,
	after: ^Room_Presentation = nil,
) -> bool {
	if renderer == nil || renderer_timeline_is_busy(renderer) {
		return false
	}
	clear_loot_animations(renderer)
	clear_enemy_move_animations(renderer)
	return begin_event_timeline(&renderer.timeline, before, events, after)
}

update_renderer_event_timeline :: proc(renderer: ^Renderer, dt: f32) -> bool {
	if renderer == nil {
		return false
	}
	return update_event_timeline(&renderer.timeline, dt)
}

enemy_move_animation_index :: proc(
	renderer: ^Renderer,
	target: game.Entity_Ref,
) -> (int, bool) {
	if renderer == nil || target.kind != .Enemy {
		return 0, false
	}
	for index in 0..<renderer.enemy_move_animation_count {
		if renderer.enemy_move_animations[index].target == target {
			return index, true
		}
	}
	return 0, false
}

enemy_move_animation_grid_position :: proc(animation: ^Enemy_Move_Animation) -> view.Vec2 {
	if animation == nil {
		return {}
	}
	if animation.duration <= 0 {
		return animation.to_grid
	}
	linear := clamp(animation.elapsed/animation.duration, f32(0), f32(1))
	progress := linear*linear*(3-2*linear)
	return {
		x = animation.from_grid.x+(animation.to_grid.x-animation.from_grid.x)*progress,
		y = animation.from_grid.y+(animation.to_grid.y-animation.from_grid.y)*progress,
	}
}

enqueue_enemy_move_animation :: proc(renderer: ^Renderer, event: game.Game_Event) {
	if renderer == nil || event.kind != .Moved || event.target.kind != .Enemy ||
	   event.from_position == event.to_position {
		return
	}
	from_grid := view.Vec2{x = f32(event.from_position.x), y = f32(event.from_position.y)}
	if index, found := enemy_move_animation_index(renderer, event.target); found {
		from_grid = enemy_move_animation_grid_position(&renderer.enemy_move_animations[index])
		renderer.enemy_move_animations[index] = {
			target = event.target,
			from_grid = from_grid,
			to_grid = {x = f32(event.to_position.x), y = f32(event.to_position.y)},
			duration = ENEMY_MOVE_ANIMATION_DURATION,
		}
		return
	}
	if renderer.enemy_move_animation_count >= MAX_ENEMY_MOVE_ANIMATIONS {
		renderer.enemy_move_animations_dropped += 1
		return
	}
	renderer.enemy_move_animations[renderer.enemy_move_animation_count] = {
		target = event.target,
		from_grid = from_grid,
		to_grid = {x = f32(event.to_position.x), y = f32(event.to_position.y)},
		duration = ENEMY_MOVE_ANIMATION_DURATION,
	}
	renderer.enemy_move_animation_count += 1
}

enqueue_event_animations :: proc(renderer: ^Renderer, events: ^game.Event_Log) {
	if renderer == nil || events == nil {
		return
	}
	for index in 0..<events.count {
		event := events.events[index]
		if event.kind == .Moved && event.target.kind == .Enemy {
			enqueue_enemy_move_animation(renderer, event)
			continue
		}
		if event.kind != .Loot_Collected {
			continue
		}
		if renderer.loot_animation_count >= MAX_LOOT_ANIMATIONS {
			renderer.loot_animations_dropped += 1
			continue
		}
		renderer.loot_animations[renderer.loot_animation_count] = {
			kind = event.loot_kind,
			amount = event.amount,
			from_position = event.from_position,
			to_position = event.to_position,
			target = event.target,
			duration = LOOT_ANIMATION_DURATION,
		}
		renderer.loot_animation_count += 1
	}
}

update_enemy_move_animations :: proc(renderer: ^Renderer, dt: f32) {
	if renderer == nil || dt <= 0 {
		return
	}
	index := 0
	for index < renderer.enemy_move_animation_count {
		animation := &renderer.enemy_move_animations[index]
		animation.elapsed += dt
		if animation.elapsed < animation.duration {
			index += 1
			continue
		}
		for current in index..<renderer.enemy_move_animation_count-1 {
			renderer.enemy_move_animations[current] = renderer.enemy_move_animations[current+1]
		}
		renderer.enemy_move_animation_count -= 1
		renderer.enemy_move_animations[renderer.enemy_move_animation_count] = {}
	}
}

update_loot_animations :: proc(renderer: ^Renderer, dt: f32) {
	if renderer == nil || dt <= 0 {
		return
	}
	index := 0
	for index < renderer.loot_animation_count {
		animation := &renderer.loot_animations[index]
		animation.elapsed += dt
		if animation.elapsed < animation.duration {
			index += 1
			continue
		}
		for current in index..<renderer.loot_animation_count-1 {
			renderer.loot_animations[current] = renderer.loot_animations[current+1]
		}
		renderer.loot_animation_count -= 1
		renderer.loot_animations[renderer.loot_animation_count] = {}
	}
}

update_camera :: proc(
	renderer: ^Renderer,
	level_data: ^level.Level,
	mouse_canvas: view.Vec2,
	mouse_inside: bool,
	mouse_delta: view.Vec2,
	dt: f32,
) {
	assert(renderer != nil && level_data != nil)

	pan_speed := 420 * dt
	pan := view.Vec2{}
	if rl.IsKeyDown(.LEFT) {
		pan.x += pan_speed
	}
	if rl.IsKeyDown(.RIGHT) {
		pan.x -= pan_speed
	}
	if rl.IsKeyDown(.UP) {
		pan.y += pan_speed
	}
	if rl.IsKeyDown(.DOWN) {
		pan.y -= pan_speed
	}
	if rl.IsMouseButtonDown(.MIDDLE) {
		pan.x += mouse_delta.x
		pan.y += mouse_delta.y
	}
	view.pan_camera(&renderer.camera, pan)

	if mouse_inside {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			zoom_factor := 1.0 + wheel*0.12
			view.set_zoom_around(&renderer.camera, mouse_canvas, renderer.camera.zoom*zoom_factor)
		}
	}

	if rl.IsKeyPressed(.R) {
		frame_level(renderer, level_data)
	}

	renderer.has_hovered_cell = false
	if mouse_inside {
		cell := view.canvas_to_cell(&renderer.camera, &renderer.projection, mouse_canvas)
		if grid.contains(&level_data.tiles, cell) {
			renderer.hovered_cell = cell
			renderer.has_hovered_cell = true
		}
	}
}

to_raylib :: proc(value: view.Vec2) -> rl.Vector2 {
	return rl.Vector2{value.x, value.y}
}

color_with_opacity :: proc(color: rl.Color, opacity: f32) -> rl.Color {
	result := color
	result.a = u8(f32(color.a)*clamp(opacity, f32(0), f32(1)))
	return result
}

tile_vertices :: proc(renderer: ^Renderer, position: grid.Position) -> Tile_Vertices {
	x := cast(f32)position.x
	y := cast(f32)position.y
	return Tile_Vertices{
		top = view.grid_point_to_canvas(&renderer.camera, &renderer.projection, {x = x, y = y}),
		right = view.grid_point_to_canvas(&renderer.camera, &renderer.projection, {x = x+1, y = y}),
		bottom = view.grid_point_to_canvas(&renderer.camera, &renderer.projection, {x = x+1, y = y+1}),
		left = view.grid_point_to_canvas(&renderer.camera, &renderer.projection, {x = x, y = y+1}),
	}
}

draw_diamond :: proc(vertices: Tile_Vertices, color, outline: rl.Color) {
	rl.DrawTriangle(to_raylib(vertices.top), to_raylib(vertices.left), to_raylib(vertices.bottom), color)
	rl.DrawTriangle(to_raylib(vertices.top), to_raylib(vertices.bottom), to_raylib(vertices.right), color)
	rl.DrawLineV(to_raylib(vertices.top), to_raylib(vertices.right), outline)
	rl.DrawLineV(to_raylib(vertices.right), to_raylib(vertices.bottom), outline)
	rl.DrawLineV(to_raylib(vertices.bottom), to_raylib(vertices.left), outline)
	rl.DrawLineV(to_raylib(vertices.left), to_raylib(vertices.top), outline)
}

cell_center :: proc(renderer: ^Renderer, position: grid.Position) -> view.Vec2 {
	vertices := tile_vertices(renderer, position)
	return {
		x = (vertices.left.x+vertices.right.x)*0.5,
		y = (vertices.top.y+vertices.bottom.y)*0.5,
	}
}

enemy_draw_center :: proc(renderer: ^Renderer, enemy: game.Enemy) -> view.Vec2 {
	target := game.enemy_entity(enemy.id)
	if index, found := enemy_move_animation_index(renderer, target); found {
		grid_position := enemy_move_animation_grid_position(&renderer.enemy_move_animations[index])
		return view.grid_point_to_canvas(
			&renderer.camera,
			&renderer.projection,
			{x = grid_position.x+0.5, y = grid_position.y+0.5},
		)
	}
	return cell_center(renderer, enemy.position)
}

enemy_draw_radius :: proc(renderer: ^Renderer, enemy: game.Enemy) -> f32 {
	assert(renderer != nil)
	if enemy.archetype == .Brute {
		return max(f32(9), 14*renderer.camera.zoom)
	}
	return max(f32(7), 12*renderer.camera.zoom)
}

draw_enemy_body :: proc(
	renderer: ^Renderer,
	enemy: game.Enemy,
	center: view.Vec2,
	opacity: f32 = 1,
) {
	assert(renderer != nil)
	radius := enemy_draw_radius(renderer, enemy)
	switch enemy.archetype {
	case .Chaser:
		rl.DrawCircleV(to_raylib(center), radius, color_with_opacity(rl.Color{51, 36, 38, 255}, opacity))
		rl.DrawCircleV(to_raylib(center), radius-2, color_with_opacity(rl.Color{224, 99, 86, 255}, opacity))
	case .Archer:
		rl.DrawCircleV(to_raylib(center), radius, color_with_opacity(rl.Color{31, 43, 56, 255}, opacity))
		rl.DrawCircleV(to_raylib(center), radius-2, color_with_opacity(rl.Color{92, 154, 215, 255}, opacity))
		rl.DrawLineEx(
			rl.Vector2{center.x-radius*0.62, center.y},
			rl.Vector2{center.x+radius*0.62, center.y},
			max(f32(1), 1.4*renderer.camera.zoom),
			color_with_opacity(rl.Color{226, 240, 248, 220}, opacity),
		)
	case .Brute:
		rl.DrawRectangle(
			c.int(center.x-radius),
			c.int(center.y-radius),
			c.int(radius*2),
			c.int(radius*2),
			color_with_opacity(rl.Color{58, 43, 28, 255}, opacity),
		)
		rl.DrawRectangle(
			c.int(center.x-radius+2),
			c.int(center.y-radius+2),
			c.int(radius*2-4),
			c.int(radius*2-4),
			color_with_opacity(rl.Color{213, 142, 66, 255}, opacity),
		)
	case .Count:
		unreachable()
	}
}

loot_colors :: proc(kind: game.Loot_Kind) -> (fill, outline: rl.Color) {
	if kind == .Healing {
		return rl.Color{74, 196, 133, 255}, rl.Color{27, 91, 61, 255}
	}
	return rl.Color{246, 207, 92, 255}, rl.Color{104, 77, 24, 255}
}

draw_loot_animations :: proc(renderer: ^Renderer, room: ^game.Room) {
	assert(renderer != nil && room != nil && room.player != nil)
	for index in 0..<renderer.loot_animation_count {
		animation := &renderer.loot_animations[index]
		linear := clamp(animation.elapsed/animation.duration, f32(0), f32(1))
		progress := linear*linear*(3-2*linear)
		from := cell_center(renderer, animation.from_position)
		to_position := animation.to_position
		if animation.target == game.PLAYER_ENTITY {
			to_position = room.player.position
		}
		to := cell_center(renderer, to_position)
		center := view.Vec2{
			x = from.x+(to.x-from.x)*progress,
			y = from.y+(to.y-from.y)*progress,
		}
		center.y -= 4*linear*(1-linear)*max(f32(8), 14*renderer.camera.zoom)
		radius := max(f32(3), (7-2*progress)*renderer.camera.zoom)
		fill, outline := loot_colors(animation.kind)
		rl.DrawCircleV(to_raylib(center), radius, fill)
		rl.DrawCircleLinesV(to_raylib(center), radius, outline)
	}
}

inset_vertices :: proc(vertices: Tile_Vertices, amount: f32) -> Tile_Vertices {
	center := view.Vec2{
		x = (vertices.left.x+vertices.right.x)*0.5,
		y = (vertices.top.y+vertices.bottom.y)*0.5,
	}
	return {
		top = {x = center.x+(vertices.top.x-center.x)*amount, y = center.y+(vertices.top.y-center.y)*amount},
		right = {x = center.x+(vertices.right.x-center.x)*amount, y = center.y+(vertices.right.y-center.y)*amount},
		bottom = {x = center.x+(vertices.bottom.x-center.x)*amount, y = center.y+(vertices.bottom.y-center.y)*amount},
		left = {x = center.x+(vertices.left.x-center.x)*amount, y = center.y+(vertices.left.y-center.y)*amount},
	}
}

floor_color :: proc(position: grid.Position) -> rl.Color {
	if (position.x+position.y)%2 == 0 {
		return rl.Color{72, 94, 82, 255}
	}
	return rl.Color{65, 84, 74, 255}
}

draw_tile :: proc(renderer: ^Renderer, tile: level.Tile, position: grid.Position) {
	base := tile_vertices(renderer, position)
	outline := rl.Color{38, 51, 47, 255}

	switch tile.kind {
	case .Void:
		return
	case .Floor:
		draw_diamond(base, floor_color(position), outline)
	case .Door:
		draw_diamond(base, rl.Color{186, 137, 63, 255}, rl.Color{89, 61, 30, 255})
	case .Player_Spawn:
		draw_diamond(base, floor_color(position), outline)
	case .Exit:
		draw_diamond(base, floor_color(position), outline)
	case .Wall:
		draw_diamond(base, rl.Color{145, 153, 158, 255}, rl.Color{65, 71, 77, 255})
	}
}

draw_level :: proc(renderer: ^Renderer, level_data: ^level.Level) {
	assert(renderer != nil && level_data != nil)

	diagonal_count := level_data.tiles.width + level_data.tiles.height - 1
	for diagonal in 0..<diagonal_count {
		first_x := max(0, diagonal-(level_data.tiles.height-1))
		last_x := min(level_data.tiles.width-1, diagonal)
		for x := first_x; x <= last_x; x += 1 {
			y := diagonal - x
			position := grid.Position{x = x, y = y}
			tile, ok := level.tile_at(level_data, position)
			assert(ok)
			draw_tile(renderer, tile, position)
		}
	}

	if renderer.has_hovered_cell {
		vertices := tile_vertices(renderer, renderer.hovered_cell)
		highlight := rl.Color{246, 207, 92, 255}
		rl.DrawLineV(to_raylib(vertices.top), to_raylib(vertices.right), highlight)
		rl.DrawLineV(to_raylib(vertices.right), to_raylib(vertices.bottom), highlight)
		rl.DrawLineV(to_raylib(vertices.bottom), to_raylib(vertices.left), highlight)
		rl.DrawLineV(to_raylib(vertices.left), to_raylib(vertices.top), highlight)
	}
}

draw_card_range_cell :: proc(
	renderer: ^Renderer,
	position: grid.Position,
	fill, outline: rl.Color,
) {
	vertices := inset_vertices(tile_vertices(renderer, position), 0.88)
	draw_diamond(vertices, fill, outline)
}

focused_enemy_intent_id :: proc(renderer: ^Renderer, room: ^game.Room) -> u32 {
	if renderer == nil || room == nil || room.phase != .Combat ||
	   !renderer.has_hovered_cell {
		return 0
	}
	if enemy_index, found := game.enemy_index_at(room, renderer.hovered_cell); found {
		enemy := room.enemies[enemy_index]
		if enemy.intent.kind != .None {
			return enemy.id
		}
	}
	return 0
}

enemy_intent_path_contains :: proc(intent: ^game.Enemy_Intent, position: grid.Position) -> bool {
	if intent == nil {
		return false
	}
	for index in 0..<intent.path_count {
		if intent.path[index] == position {
			return true
		}
	}
	return false
}

enemy_intent_cell_counts :: proc(
	room: ^game.Room,
	position: grid.Position,
	focused_enemy_id: u32,
) -> (
	move_count, threat_count: int,
	move_focused, threat_focused: bool,
) {
	if room == nil {
		return
	}
	for &enemy in room.enemies {
		if enemy_intent_path_contains(&enemy.intent, position) {
			move_count += 1
			move_focused = move_focused || enemy.id == focused_enemy_id
		}
		if game.enemy_intent_cell_is_threatened(&enemy.intent, position) {
			threat_count += 1
			threat_focused = threat_focused || enemy.id == focused_enemy_id
		}
	}
	return
}

draw_enemy_intent_ground :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
	card_targeting_active: bool,
) {
	if renderer == nil || room == nil || room.level_data == nil || room.phase != .Combat {
		return
	}
	focused_enemy_id := focused_enemy_intent_id(renderer, room)
	move_line := INTENT_MOVE_OUTLINE
	if card_targeting_active {
		move_line.a = 120
	}
	for &enemy in room.enemies {
		intent := &enemy.intent
		if (intent.kind != .Move && intent.kind != .Charge) || intent.path_count <= 0 {
			continue
		}
		line_color := move_line
		if focused_enemy_id != 0 && enemy.id != focused_enemy_id {
			line_color.a = min(line_color.a, u8(105))
		}
		from := cell_center(renderer, intent.origin)
		for index in 0..<intent.path_count {
			to := cell_center(renderer, intent.path[index])
			rl.DrawLineEx(
				to_raylib(from),
				to_raylib(to),
				max(f32(1.5), 2.2*renderer.camera.zoom),
				line_color,
			)
			rl.DrawCircleV(
				to_raylib(to),
				max(f32(2.5), 3.5*renderer.camera.zoom),
				line_color,
			)
			from = to
		}
	}

	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			position := grid.Position{x = x, y = y}
			move_count, threat_count, move_focused, threat_focused :=
				enemy_intent_cell_counts(room, position, focused_enemy_id)
			if move_count > 0 {
				fill := INTENT_MOVE_FILL
				outline := INTENT_MOVE_OUTLINE
				if card_targeting_active {
					fill.a = 18
					outline.a = 125
				}
				if move_focused {
					outline = INTENT_FOCUS_OUTLINE
				}
				draw_diamond(inset_vertices(tile_vertices(renderer, position), 0.72), fill, outline)
			}
			if threat_count <= 0 {
				continue
			}
			fill := INTENT_THREAT_FILL
			outline := INTENT_THREAT_OUTLINE
			if card_targeting_active {
				fill.a = 22
				outline.a = 145
			}
			if threat_focused {
				outline = INTENT_FOCUS_OUTLINE
			}
			draw_diamond(inset_vertices(tile_vertices(renderer, position), 0.84), fill, outline)
			center := cell_center(renderer, position)
			marker_radius := max(f32(3), 4.5*renderer.camera.zoom)
			rl.DrawCircleLinesV(to_raylib(center), marker_radius, outline)
			if threat_count > 1 {
				label := fmt.ctprintf("%d", threat_count)
				font_size: c.int = 9
				text_width := rl.MeasureText(label, font_size)
				rl.DrawText(
					label,
					c.int(center.x+marker_radius+2)-text_width/2,
					c.int(center.y-marker_radius)-font_size/2,
					font_size,
					outline,
				)
			}
		}
	}
}

draw_enemy_intent_badges :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer == nil || room == nil || room.phase != .Combat {
		return
	}
	focused_enemy_id := focused_enemy_intent_id(renderer, room)
	for enemy in room.enemies {
		label: cstring = ""
		color := INTENT_WAIT_OUTLINE
		switch enemy.intent.kind {
		case .None:
			continue
		case .Wait:
			label = "WAIT"
		case .Move:
			label = "MOVE"
			color = INTENT_MOVE_OUTLINE
		case .Attack:
			label = fmt.ctprintf("ATK %d", enemy.intent.damage)
			color = INTENT_THREAT_OUTLINE
		case .Charge:
			label = fmt.ctprintf("CHG %d", enemy.intent.damage)
			color = rl.Color{246, 146, 72, 255}
		}
		font_size: c.int = 10
		padding: c.int = 4
		width := rl.MeasureText(label, font_size)+padding*2
		height: c.int = 16
		center := enemy_draw_center(renderer, enemy)
		radius := enemy_draw_radius(renderer, enemy)
		x := c.int(center.x)-width/2
		y := c.int(center.y-radius)-height-5
		rl.DrawRectangle(x, y, width, height, rl.Color{14, 16, 19, 235})
		border := color
		if enemy.id == focused_enemy_id {
			border = INTENT_FOCUS_OUTLINE
		}
		rl.DrawRectangleLines(x, y, width, height, border)
		rl.DrawText(label, x+padding, y+3, font_size, color)
	}
}

draw_card_target_cell_set :: proc(
	renderer: ^Renderer,
	set: ^game.Target_Cell_Set,
	fill, outline: rl.Color,
) {
	if renderer == nil || set == nil {
		return
	}
	for index in 0..<set.count {
		draw_card_range_cell(renderer, set.cells[index], fill, outline)
	}
}

draw_card_target_range :: proc(renderer: ^Renderer, room: ^game.Room, card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil ||
	   room.phase != .Combat || card_id == 0 {
		return
	}
	deck := &room.player.deck
	card_index, card_found := game.hand_card_index_by_id(deck, card_id)
	if !card_found {
		return
	}
	card := deck.hand[card_index]
	definition, definition_found := game.card_definition_by_id(card.definition_id)
	if !definition_found {
		return
	}
	affordable := deck.energy >= definition.cost
	range_fill := rl.Color{50, 184, 178, 66}
	range_outline := rl.Color{91, 226, 213, 190}
	if !affordable {
		range_fill.a = 34
		range_outline.a = 110
	}

	if definition.targeting.shape != .None {
		for y in 0..<room.level_data.tiles.height {
			for x in 0..<room.level_data.tiles.width {
				position := grid.Position{x = x, y = y}
				request := game.card_target_request_at(definition, position)
				evaluation := game.evaluate_card_targeting(room, card, request)
				// Target_Rule.Cell may intentionally accept a static anchor.
				if evaluation.query.anchor_reachable || evaluation.error == .None {
					draw_card_range_cell(renderer, position, range_fill, range_outline)
				}
			}
		}
	} else {
		request := game.card_target_request_at(definition, room.player.position)
		evaluation := game.evaluate_card_targeting(room, card, request)
		if evaluation.query.anchor_reachable || evaluation.error == .None {
			draw_card_range_cell(renderer, evaluation.query.anchor, range_fill, range_outline)
		}
	}

	if !renderer.has_hovered_cell {
		return
	}

	request := game.card_target_request_at(definition, renderer.hovered_cell)
	evaluation := game.evaluate_card_targeting(room, card, request)
	valid_target := evaluation.error == .None && affordable
	path_fill := rl.Color{238, 174, 73, 24}
	path_outline := rl.Color{238, 174, 73, 140}
	affected_fill := rl.Color{238, 174, 73, 74}
	affected_outline := rl.Color{246, 207, 92, 230}
	anchor_fill := rl.Color{74, 196, 133, 68}
	anchor_outline := rl.Color{123, 235, 169, 255}
	if !valid_target {
		path_fill = rl.Color{190, 68, 70, 28}
		path_outline = rl.Color{213, 81, 78, 155}
		affected_fill = rl.Color{190, 68, 70, 60}
		affected_outline = rl.Color{235, 91, 91, 225}
		anchor_fill = rl.Color{190, 68, 70, 76}
		anchor_outline = rl.Color{235, 91, 91, 255}
	}

	for index in 0..<evaluation.query.path_count {
		draw_card_range_cell(
			renderer,
			evaluation.query.path[index],
			path_fill,
			path_outline,
		)
	}
	draw_card_target_cell_set(
		renderer,
		&evaluation.query.affected,
		affected_fill,
		affected_outline,
	)
	if evaluation.query.has_blocker {
		draw_card_range_cell(
			renderer,
			evaluation.query.blocker,
			rl.Color{190, 68, 70, 105},
			rl.Color{255, 112, 102, 255},
		)
	}

	// The anchor is drawn last so the intended drop cell remains unambiguous.
	draw_card_range_cell(
		renderer,
		evaluation.query.anchor,
		anchor_fill,
		anchor_outline,
	)
}

draw_status_set :: proc(
	renderer: ^Renderer,
	statuses: ^game.Status_Set,
	center: view.Vec2,
	entity_radius: f32,
	opacity: f32 = 1,
) {
	assert(renderer != nil && statuses != nil)
	if index, found := game.status_index(statuses, .Shield); found {
		shield := &statuses.items[index]
		ring_radius := entity_radius+max(f32(3), 3*renderer.camera.zoom)
		color := color_with_opacity(rl.Color{101, 174, 218, 255}, opacity)
		rl.DrawCircleLinesV(to_raylib(center), ring_radius, color)
		rl.DrawCircleLinesV(to_raylib(center), ring_radius+1, color)
		label := fmt.ctprintf("%d", shield.potency)
		font_size: c.int = 10
		rl.DrawText(
			label,
			c.int(center.x-ring_radius-2),
			c.int(center.y-ring_radius-4),
			font_size,
			color,
		)
	}
	if index, found := game.status_index(statuses, .Poison); found {
		poison := &statuses.items[index]
		marker_center := view.Vec2{
			x = center.x+entity_radius*0.78,
			y = center.y+entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.camera.zoom)
		color := color_with_opacity(rl.Color{113, 190, 91, 255}, opacity)
		rl.DrawCircleV(
			to_raylib(marker_center),
			marker_radius,
			color_with_opacity(rl.Color{28, 54, 35, 255}, opacity),
		)
		rl.DrawCircleLinesV(to_raylib(marker_center), marker_radius, color)
		label := fmt.ctprintf("%d", poison.potency)
		font_size: c.int = 9
		text_width := rl.MeasureText(label, font_size)
		rl.DrawText(
			label,
			c.int(marker_center.x)-text_width/2,
			c.int(marker_center.y)-font_size/2,
			font_size,
			color,
		)
	}
	if index, found := game.status_index(statuses, .Thorns); found {
		thorns := &statuses.items[index]
		marker_center := view.Vec2{
			x = center.x+entity_radius*0.78,
			y = center.y-entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.camera.zoom)
		color := color_with_opacity(rl.Color{238, 174, 73, 255}, opacity)
		rl.DrawCircleV(
			to_raylib(marker_center),
			marker_radius,
			color_with_opacity(rl.Color{61, 45, 25, 255}, opacity),
		)
		rl.DrawCircleLinesV(to_raylib(marker_center), marker_radius, color)
		label := fmt.ctprintf("%d", thorns.potency)
		font_size: c.int = 9
		text_width := rl.MeasureText(label, font_size)
		rl.DrawText(
			label,
			c.int(marker_center.x)-text_width/2,
			c.int(marker_center.y)-font_size/2,
			font_size,
			color,
		)
	}
	if index, found := game.status_index(statuses, .Afterimage); found {
		afterimage := &statuses.items[index]
		marker_center := view.Vec2{
			x = center.x-entity_radius*0.78,
			y = center.y+entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.camera.zoom)
		color := color_with_opacity(rl.Color{194, 184, 226, 255}, opacity)
		rl.DrawCircleV(
			to_raylib(marker_center),
			marker_radius,
			color_with_opacity(rl.Color{48, 43, 64, 255}, opacity),
		)
		rl.DrawCircleLinesV(to_raylib(marker_center), marker_radius, color)
		label := fmt.ctprintf("%d", afterimage.potency)
		font_size: c.int = 9
		text_width := rl.MeasureText(label, font_size)
		rl.DrawText(
			label,
			c.int(marker_center.x)-text_width/2,
			c.int(marker_center.y)-font_size/2,
			font_size,
			color,
		)
	}
}

draw_entity_statuses :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
	entity: game.Entity_Ref,
	center: view.Vec2,
	entity_radius: f32,
) {
	assert(renderer != nil && room != nil)
	if statuses, found := game.status_set_for_entity(room, entity); found {
		draw_status_set(renderer, statuses, center, entity_radius)
	}
}

Renderer_Status_View :: struct {
	phase:       game.Room_Phase,
	health:      i32,
	max_health:  i32,
	enemy_count: int,
	gold:        i32,
	pulse_count: u64,
	statuses:    game.Status_Set,
}

renderer_status_view :: proc(renderer: ^Renderer, room: ^game.Room) -> (result: Renderer_Status_View) {
	if room == nil || room.player == nil {
		return
	}
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		presentation := &renderer.timeline.view
		result.phase = presentation.phase
		result.health = presentation.player.health
		result.max_health = presentation.player.max_health
		result.enemy_count = visible_presentation_enemy_count(presentation)
		result.gold = presentation.gold
		result.pulse_count = presentation.pulse_count
		result.statuses = presentation.player.statuses
		return
	}
	result.phase = room.phase
	result.health = room.player.health
	result.max_health = room.player.stats.max_health
	result.enemy_count = len(room.enemies)
	result.gold = room.player.gold
	result.pulse_count = room.pulse_count
	result.statuses = room.player.statuses
	return
}

presentation_actor_center :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> view.Vec2 {
	assert(renderer != nil && actor != nil)
	return view.grid_point_to_canvas(
		&renderer.camera,
		&renderer.projection,
		{x = actor.position.x+0.5, y = actor.position.y+0.5},
	)
}

draw_player_body :: proc(renderer: ^Renderer, center: view.Vec2, opacity: f32 = 1) -> f32 {
	assert(renderer != nil)
	radius := max(f32(8), 13*renderer.camera.zoom)
	rl.DrawCircleV(
		to_raylib(center),
		radius,
		color_with_opacity(rl.Color{28, 48, 51, 255}, opacity),
	)
	rl.DrawCircleV(
		to_raylib(center),
		radius-2,
		color_with_opacity(rl.Color{71, 188, 184, 255}, opacity),
	)
	rl.DrawCircleV(
		rl.Vector2{center.x-radius*0.28, center.y-radius*0.28},
		max(f32(2), radius*0.18),
		color_with_opacity(rl.Color{205, 244, 235, 255}, opacity),
	)
	return radius
}

draw_enemy_health :: proc(center: view.Vec2, health: i32, font_size: c.int, opacity: f32 = 1) {
	health_text := fmt.ctprintf("%d", health)
	text_width := rl.MeasureText(health_text, font_size)
	rl.DrawText(
		health_text,
		c.int(center.x)-text_width/2,
		c.int(center.y)-font_size/2,
		font_size,
		color_with_opacity(rl.Color{255, 247, 237, 255}, opacity),
	)
}

draw_presentation_loot :: proc(renderer: ^Renderer, presentation: ^Room_Presentation) {
	assert(renderer != nil && presentation != nil)
	if presentation.loot_count < 0 || presentation.loot_count > len(presentation.loot) {
		return
	}
	for index in 0..<presentation.loot_count {
		item := &presentation.loot[index]
		if !item.visible {
			continue
		}
		center := cell_center(renderer, item.position)
		radius := max(f32(4), 7*renderer.camera.zoom)
		fill, outline := loot_colors(item.kind)
		rl.DrawCircleV(to_raylib(center), radius, fill)
		rl.DrawCircleLinesV(to_raylib(center), radius, outline)
	}
}

draw_presentation_actors :: proc(renderer: ^Renderer) {
	assert(renderer != nil && renderer_timeline_is_busy(renderer))
	presentation := &renderer.timeline.view
	if presentation.enemy_count >= 0 && presentation.enemy_count <= len(presentation.enemies) {
		for index in 0..<presentation.enemy_count {
			actor := &presentation.enemies[index]
			if !actor.visible {
				continue
			}
			enemy := game.Enemy{archetype = actor.archetype}
			center := presentation_actor_center(renderer, actor)
			radius := enemy_draw_radius(renderer, enemy)
			draw_enemy_body(renderer, enemy, center, actor.opacity)
			font_size := c.int(max(f32(10), 13*renderer.camera.zoom))
			draw_enemy_health(center, actor.health, font_size, actor.opacity)
			draw_status_set(renderer, &actor.statuses, center, radius, actor.opacity)
		}
	}
	player := &presentation.player
	if player.visible {
		center := presentation_actor_center(renderer, player)
		radius := draw_player_body(renderer, center, player.opacity)
		draw_status_set(renderer, &player.statuses, center, radius, player.opacity)
	}
}

presentation_event_center :: proc(
	renderer: ^Renderer,
	event: game.Game_Event,
) -> (view.Vec2, bool) {
	if renderer == nil {
		return {}, false
	}
	if actor, found := presentation_actor(&renderer.timeline, event.target); found {
		return presentation_actor_center(renderer, actor), true
	}
	if actor, found := presentation_actor(&renderer.timeline, event.source); found {
		return presentation_actor_center(renderer, actor), true
	}
	return cell_center(renderer, event.to_position), true
}

draw_timeline_popup :: proc(
	renderer: ^Renderer,
	label: cstring,
	color: rl.Color,
	center: view.Vec2,
	progress: f32,
) {
	assert(renderer != nil)
	font_size: c.int = 16
	text_width := rl.MeasureText(label, font_size)
	eased := progress*progress*(3-2*progress)
	opacity := clamp((1-progress)*3, f32(0), f32(1))
	x := c.int(center.x)-text_width/2
	y := c.int(center.y-26-eased*18)
	rl.DrawRectangle(
		x-5,
		y-3,
		text_width+10,
		font_size+6,
		color_with_opacity(rl.Color{8, 11, 13, 210}, opacity),
	)
	rl.DrawText(label, x, y, font_size, color_with_opacity(color, opacity))
}

timeline_card_cue_verb :: proc(cue: ^Presentation_Cue) -> cstring {
	if cue == nil {
		return nil
	}
	switch cue.kind {
	case .Card_Played:
		return "PLAY"
	case .Card_Drawn:
		return "DRAW"
	case .Card_Created:
		return "CREATE"
	case .Card_Refocused:
		switch cue.event.to_card_zone {
		case .Hand:
			return "RETAIN"
		case .Exhaust:
			return "ETHEREAL"
		case .Discard:
			return "DISCARD"
		case .Draw, .Resolving, .Count:
		}
	case .Card_Moved:
		if cue.event.to_card_zone == .Exhaust {
			return "EXHAUST"
		} else if cue.event.to_card_zone == .Discard {
			return "DISCARD"
		}
	case .Move, .Damage, .Damage_Absorbed, .Heal, .Status_Applied, .Status_Removed,
	     .Status_Expired, .Defeat, .Loot_Dropped, .Loot, .Attack_Missed, .Move_Blocked,
	     .Gold_Gained, .Binding_Added, .Binding_Exhausted, .Binding_Expired,
	     .Pulse_Advanced, .Refocus:
	}
	return nil
}

draw_timeline_banner :: proc(
	renderer: ^Renderer,
	cue: ^Presentation_Cue,
	label: cstring,
	fill, outline: rl.Color,
) {
	assert(renderer != nil && cue != nil)
	progress := presentation_cue_progress(cue)
	opacity := clamp((1-progress)*4, f32(0), f32(1))
	font_size: c.int = 16
	text_width := rl.MeasureText(label, font_size)
	width := clamp(f32(text_width+44), f32(250), renderer.canvas_width-32)
	height: f32 = 42
	x := (renderer.canvas_width-width)*0.5
	y := f32(108)+(1-presentation_cue_eased_progress(cue))*-12
	rl.DrawRectangleRec({x, y, width, height}, color_with_opacity(fill, opacity))
	rl.DrawRectangleLinesEx({x, y, width, height}, 2, color_with_opacity(outline, opacity))
	rl.DrawText(
		label,
		c.int(x+(width-f32(text_width))*0.5),
		c.int(y+12),
		font_size,
		color_with_opacity(rl.Color{247, 239, 213, 255}, opacity),
	)
}

draw_timeline_card_banner :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	assert(renderer != nil && cue != nil)
	definition, found := game.card_definition_by_id(cue.event.card_definition)
	verb := timeline_card_cue_verb(cue)
	if !found || verb == nil {
		return
	}
	label := fmt.ctprintf("%s  %s", verb, definition.name)
	fill, outline := card_colors(cue.event.card_definition, true)
	draw_timeline_banner(renderer, cue, label, fill, outline)
}

draw_timeline_refocus_banner :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	assert(renderer != nil && cue != nil)
	draw_timeline_banner(
		renderer,
		cue,
		"REFOCUS",
		rl.Color{28, 50, 51, 245},
		rl.Color{91, 226, 213, 255},
	)
}

draw_timeline_loot_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	assert(renderer != nil && cue != nil)
	linear := presentation_cue_progress(cue)
	progress := presentation_cue_eased_progress(cue)
	from := cell_center(renderer, cue.event.from_position)
	to := cell_center(renderer, cue.event.to_position)
	if actor, found := presentation_actor(&renderer.timeline, cue.event.target); found {
		to = presentation_actor_center(renderer, actor)
	}
	center := view.Vec2{
		x = from.x+(to.x-from.x)*progress,
		y = from.y+(to.y-from.y)*progress,
	}
	center.y -= 4*linear*(1-linear)*max(f32(8), 14*renderer.camera.zoom)
	radius := max(f32(3), (7-2*progress)*renderer.camera.zoom)
	fill, outline := loot_colors(cue.event.loot_kind)
	rl.DrawCircleV(to_raylib(center), radius, fill)
	rl.DrawCircleLinesV(to_raylib(center), radius, outline)
}

draw_timeline_loot_drop_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	assert(renderer != nil && cue != nil)
	progress := presentation_cue_eased_progress(cue)
	center := cell_center(renderer, cue.event.from_position)
	radius := max(f32(5), (7+progress*9)*renderer.camera.zoom)
	_, outline := loot_colors(cue.event.loot_kind)
	rl.DrawCircleLinesV(
		to_raylib(center),
		radius,
		color_with_opacity(outline, 1-progress),
	)
}

draw_active_presentation_cue :: proc(renderer: ^Renderer) {
	assert(renderer != nil)
	cue, found := active_presentation_cue(&renderer.timeline)
	if !found || !cue.started {
		return
	}
	if cue.kind == .Refocus {
		draw_timeline_refocus_banner(renderer, cue)
		return
	}
	if cue.kind == .Card_Played || cue.kind == .Card_Drawn || cue.kind == .Card_Moved ||
	   cue.kind == .Card_Created || cue.kind == .Card_Refocused {
		draw_timeline_card_banner(renderer, cue)
		return
	}
	if cue.kind == .Loot {
		draw_timeline_loot_cue(renderer, cue)
		return
	}
	if cue.kind == .Loot_Dropped {
		draw_timeline_loot_drop_cue(renderer, cue)
		return
	}
	if cue.kind == .Move || cue.kind == .Defeat || cue.kind == .Pulse_Advanced {
		return
	}
	center, has_center := presentation_event_center(renderer, cue.event)
	if !has_center {
		return
	}
	label: cstring
	color := rl.Color{225, 229, 224, 255}
	switch cue.kind {
	case .Damage:
		label = fmt.ctprintf("-%d", cue.event.amount)
		color = rl.Color{255, 112, 102, 255}
	case .Damage_Absorbed:
		label = fmt.ctprintf("BLOCK %d", cue.event.amount)
		color = rl.Color{101, 174, 218, 255}
	case .Heal:
		label = fmt.ctprintf("+%d", cue.event.amount)
		color = rl.Color{92, 220, 151, 255}
	case .Status_Applied:
		label = fmt.ctprintf("+%s %d", game.status_kind_name(cue.event.status), cue.event.amount)
		color = rl.Color{169, 210, 216, 255}
	case .Status_Removed:
		label = fmt.ctprintf("-%s", game.status_kind_name(cue.event.status))
		color = rl.Color{169, 183, 177, 255}
	case .Status_Expired:
		label = fmt.ctprintf("%s END", game.status_kind_name(cue.event.status))
		color = rl.Color{169, 183, 177, 255}
	case .Attack_Missed:
		label = "MISS"
		color = rl.Color{247, 239, 213, 255}
	case .Move_Blocked:
		label = "BLOCKED"
		color = rl.Color{238, 174, 73, 255}
	case .Gold_Gained:
		label = fmt.ctprintf("+%d GOLD", cue.event.amount)
		color = rl.Color{246, 207, 92, 255}
	case .Binding_Added:
		label = "BINDING +"
		color = rl.Color{194, 184, 226, 255}
	case .Binding_Exhausted:
		label = "BINDING USED"
		color = rl.Color{194, 184, 226, 255}
	case .Binding_Expired:
		label = "BINDING END"
		color = rl.Color{169, 183, 177, 255}
	case .Move, .Card_Played, .Card_Drawn, .Card_Moved, .Card_Created, .Refocus,
	     .Card_Refocused, .Defeat,
	     .Loot_Dropped, .Loot, .Pulse_Advanced:
		unreachable()
	}
	draw_timeline_popup(renderer, label, color, center, presentation_cue_progress(cue))
}

draw_room_trap :: proc(renderer: ^Renderer, trap: game.Trap) {
	assert(renderer != nil)
	center := cell_center(renderer, trap.position)
	radius := max(f32(4), 8*renderer.camera.zoom)
	color := rl.Color{189, 78, 62, 255} if trap.armed else rl.Color{91, 82, 78, 255}
	rl.DrawLineEx(
		rl.Vector2{center.x-radius, center.y-radius*0.55},
		rl.Vector2{center.x+radius, center.y+radius*0.55},
		max(f32(1.5), 2*renderer.camera.zoom),
		color,
	)
	rl.DrawLineEx(
		rl.Vector2{center.x+radius, center.y-radius*0.55},
		rl.Vector2{center.x-radius, center.y+radius*0.55},
		max(f32(1.5), 2*renderer.camera.zoom),
		color,
	)
}

draw_room :: proc(renderer: ^Renderer, room: ^game.Room) {
	assert(renderer != nil && room != nil && room.player != nil)

	status_view := renderer_status_view(renderer, room)
	timeline_busy := renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid
	exit_color := rl.Color{91, 101, 105, 255}
	if status_view.phase == .Loot {
		exit_color = rl.Color{74, 196, 133, 255}
	} else if status_view.phase == .Complete {
		exit_color = rl.Color{246, 207, 92, 255}
	}
	exit_vertices := inset_vertices(tile_vertices(renderer, room.exit_position), 0.48)
	draw_diamond(exit_vertices, exit_color, rl.Color{28, 42, 39, 255})

	if timeline_busy {
		for index in 0..<renderer.timeline.view.trap_count {
			draw_room_trap(renderer, renderer.timeline.view.traps[index])
		}
	} else {
		for trap in room.traps {
			draw_room_trap(renderer, trap)
		}
	}

	for obstacle in room.obstacles {
		vertices := inset_vertices(tile_vertices(renderer, obstacle.position), 0.58)
		draw_diamond(vertices, rl.Color{48, 53, 58, 255}, rl.Color{180, 187, 188, 255})
	}

	if timeline_busy {
		draw_presentation_loot(renderer, &renderer.timeline.view)
		draw_presentation_actors(renderer)
		draw_active_presentation_cue(renderer)
	} else {
		for item in room.loot {
			center := cell_center(renderer, item.position)
			radius := max(f32(4), 7*renderer.camera.zoom)
			fill, outline := loot_colors(item.kind)
			rl.DrawCircleV(to_raylib(center), radius, fill)
			rl.DrawCircleLinesV(to_raylib(center), radius, outline)
		}

		for enemy in room.enemies {
			center := enemy_draw_center(renderer, enemy)
			radius := enemy_draw_radius(renderer, enemy)
			draw_enemy_body(renderer, enemy, center)
			font_size := c.int(max(f32(10), 13*renderer.camera.zoom))
			draw_enemy_health(center, enemy.health, font_size)
			draw_entity_statuses(renderer, room, game.enemy_entity(enemy.id), center, radius)
		}

		if room.player.health > 0 {
			center := cell_center(renderer, room.player.position)
			radius := draw_player_body(renderer, center)
			draw_entity_statuses(renderer, room, game.PLAYER_ENTITY, center, radius)
		}
		draw_loot_animations(renderer, room)
	}
}

draw_status :: proc(renderer: ^Renderer, room: ^game.Room, scale_mode: view.Scale_Mode) {
	assert(renderer != nil && room != nil && room.player != nil)

	status_view := renderer_status_view(renderer, room)
	phase_color := rl.Color{224, 99, 86, 255}
	switch status_view.phase {
	case .Loot:
		phase_color = rl.Color{74, 196, 133, 255}
	case .Complete:
		phase_color = rl.Color{246, 207, 92, 255}
	case .Defeat:
		phase_color = rl.Color{190, 68, 70, 255}
	case .Combat:
	}

	rl.DrawRectangle(14, 14, 460, 84, rl.Color{12, 15, 18, 220})
	rl.DrawText(
		fmt.ctprintf(
			"%s  |  %s",
			game.room_phase_name(status_view.phase),
			view.scale_mode_name(scale_mode),
		),
		26,
		24,
		20,
		phase_color,
	)
	stats_text := fmt.ctprintf("HP %d/%d    ENEMIES %d    GOLD %d",
		status_view.health,
		status_view.max_health,
		status_view.enemy_count,
		status_view.gold,
	)
	rl.DrawText(
		stats_text,
		26,
		51,
		16,
		rl.Color{225, 229, 224, 255},
	)
	pulse_text := fmt.ctprintf("PULSE %d", status_view.pulse_count)
	status_font_size: c.int = 12
	status_gap: c.int = 16
	status_x: c.int = 26
	rl.DrawText(pulse_text, status_x, 74, status_font_size, rl.Color{169, 183, 177, 255})
	status_x += rl.MeasureText(pulse_text, status_font_size)+status_gap

	shield_index, has_shield := game.status_index(&status_view.statuses, .Shield)
	poison_index, has_poison := game.status_index(&status_view.statuses, .Poison)
	thorns_index, has_thorns := game.status_index(&status_view.statuses, .Thorns)
	afterimage_index, has_afterimage := game.status_index(&status_view.statuses, .Afterimage)
	if has_shield {
		shield := &status_view.statuses.items[shield_index]
		label := fmt.ctprintf("SHIELD %d:%d", shield.potency, shield.remaining_pulses)
		rl.DrawText(label, status_x, 74, status_font_size, rl.Color{101, 174, 218, 255})
		status_x += rl.MeasureText(label, status_font_size)+status_gap
	}
	if has_poison {
		poison := &status_view.statuses.items[poison_index]
		label := fmt.ctprintf("POISON %d:%d", poison.potency, poison.remaining_pulses)
		rl.DrawText(label, status_x, 74, status_font_size, rl.Color{113, 190, 91, 255})
		status_x += rl.MeasureText(label, status_font_size)+status_gap
	}
	if has_thorns {
		thorns := &status_view.statuses.items[thorns_index]
		label := fmt.ctprintf("THORNS %d:%d", thorns.potency, thorns.remaining_pulses)
		rl.DrawText(label, status_x, 74, status_font_size, rl.Color{238, 174, 73, 255})
		status_x += rl.MeasureText(label, status_font_size)+status_gap
	}
	if has_afterimage {
		afterimage := &status_view.statuses.items[afterimage_index]
		label := fmt.ctprintf("AFTERIMAGE %d:%d", afterimage.potency, afterimage.remaining_pulses)
		rl.DrawText(label, status_x, 74, status_font_size, rl.Color{194, 184, 226, 255})
	}
	rl.DrawFPS(c.int(renderer.canvas_width)-96, 18)
}
