package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

REWARD_CARD_WIDTH       :: f32(156)
REWARD_CARD_HEIGHT      :: f32(190)
REWARD_CARD_GAP         :: f32(32)
REWARD_CARD_TOP         :: f32(142)
REWARD_CARD_HOVER_RAISE :: f32(12)
REWARD_SKIP_WIDTH       :: f32(128)
REWARD_SKIP_HEIGHT      :: f32(38)

reward_card_bounds :: proc(
	canvas_width, canvas_height: f32,
	card_index, card_count: int,
	raised: bool = false,
) -> rl.Rectangle {
	if canvas_width <= 0 || canvas_height <= 0 || card_count <= 0 ||
	   card_index < 0 || card_index >= card_count {
		return {}
	}
	horizontal_padding: f32 = 32
	available_width := canvas_width-horizontal_padding*2-REWARD_CARD_GAP*f32(card_count-1)
	card_width := min(REWARD_CARD_WIDTH, available_width/f32(card_count))
	if card_width <= 0 {
		return {}
	}
	total_width := card_width*f32(card_count)+REWARD_CARD_GAP*f32(card_count-1)
	y := min(REWARD_CARD_TOP, canvas_height-REWARD_CARD_HEIGHT-94)
	if raised {
		y -= REWARD_CARD_HOVER_RAISE
	}
	return {
		x = (canvas_width-total_width)*0.5+f32(card_index)*(card_width+REWARD_CARD_GAP),
		y = max(f32(104), y),
		width = card_width,
		height = REWARD_CARD_HEIGHT,
	}
}

reward_skip_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	if canvas_width <= 0 || canvas_height <= 0 {
		return {}
	}
	return {
		x = (canvas_width-REWARD_SKIP_WIDTH)*0.5,
		y = canvas_height-76,
		width = REWARD_SKIP_WIDTH,
		height = REWARD_SKIP_HEIGHT,
	}
}

reward_card_at_point :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	point: view.Vec2,
	raised_index: int = -1,
) -> (card_index: int, found: bool) {
	choices := game.available_card_rewards(run)
	if len(choices) == 0 {
		return 0, false
	}
	if raised_index >= 0 && raised_index < len(choices) {
		bounds := reward_card_bounds(canvas_width, canvas_height, raised_index, len(choices), true)
		if point_in_rectangle(point, bounds) {
			return raised_index, true
		}
	}
	for index in 0..<len(choices) {
		bounds := reward_card_bounds(canvas_width, canvas_height, index, len(choices))
		if point_in_rectangle(point, bounds) {
			return index, true
		}
	}
	return 0, false
}

reward_skip_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2) -> bool {
	return point_in_rectangle(point, reward_skip_bounds(canvas_width, canvas_height))
}

draw_reward_card :: proc(
	choice: game.Card_Id,
	choice_index, choice_count: int,
	canvas_width, canvas_height: f32,
	raised, enabled: bool, theme: ^Renderer = nil,
) {
	definition, found := game.card_definition_by_id(choice, menu_themed(theme))
	assert(found)
	preview := game.Card_Instance{definition_id = choice}
	menu_card_face(theme,
		reward_card_bounds(canvas_width, canvas_height, choice_index, choice_count, raised),
		preview,
		definition,
		choice_index,
		enabled,
		true,
		raised,
		false,
	)
}

draw_reward_screen :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	hovered_card_index: int = -1,
	skip_hovered: bool = false, theme: ^Renderer = nil,
) {
	assert(run != nil && run.phase == .Reward)
	choices := game.available_card_rewards(run)
	assert(len(choices) == game.CARD_REWARD_CHOICE_COUNT)
	can_add := game.card_reward_can_be_added(run)
	node, node_found := game.current_run_node(run)
	assert(node_found)

	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(canvas_height), CANVAS_BACKGROUND)
	menu_rectangle(theme, 0, 0, c.int(canvas_width), 92, rl.Color{15, 18, 21, 255})
	menu_text(theme, "CARD REWARD", 28, 20, 24, rl.Color{225, 229, 224, 255})
	menu_text(theme,
		fmt.ctprintf("%s CLEARED    DECK %d/%d", game.node_kind_name(node.kind), run.player.deck.owned_count, game.MAX_OWNED_CARDS),
		28,
		55,
		15,
		rl.Color{151, 163, 158, 255},
	)
	command: cstring = "CHOOSE ONE"
	command_color := rl.Color{246, 207, 92, 255}
	if !can_add {
		command = "DECK FULL"
		command_color = rl.Color{224, 99, 86, 255}
	}
	command_width := menu_measure_text(theme, command, 16)
	menu_text(theme, command, c.int(canvas_width)*1/2-command_width/2, 108, 16, command_color)

	for index in 0..<len(choices) {
		if index == hovered_card_index {
			continue
		}
		draw_reward_card(choices[index], index, len(choices), canvas_width, canvas_height, false, can_add, theme = theme)
	}
	if hovered_card_index >= 0 && hovered_card_index < len(choices) {
		draw_reward_card(
			choices[hovered_card_index],
			hovered_card_index,
			len(choices),
			canvas_width,
			canvas_height,
			true,
			can_add,
		 theme = theme)
	}

	skip_bounds := reward_skip_bounds(canvas_width, canvas_height)
	skip_fill := rl.Color{31, 36, 39, 255}
	skip_outline := rl.Color{105, 116, 116, 255}
	if skip_hovered {
		skip_fill = rl.Color{67, 55, 31, 255}
		skip_outline = rl.Color{246, 207, 92, 255}
	}
	menu_rectangle_rec(theme, skip_bounds, skip_fill)
	menu_outline(theme, skip_bounds, 2, skip_outline)
	skip_width := menu_measure_text(theme, "SKIP", 16)
	menu_text(theme,
		"SKIP",
		c.int(skip_bounds.x+skip_bounds.width*0.5)-skip_width/2,
		c.int(skip_bounds.y+10),
		16,
		rl.Color{225, 229, 224, 255},
	)

}
