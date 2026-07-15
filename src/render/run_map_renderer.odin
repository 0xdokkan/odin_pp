package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

RUN_NODE_RADIUS :: f32(18)

run_node_center :: proc(run: ^game.Run_State, node: ^game.Run_Node, canvas_width, canvas_height: f32) -> view.Vec2 {
	assert(run != nil && node != nil)
	layer_count := len(run.route_map.layer_starts)
	horizontal_padding: f32 = 78
	vertical_padding: f32 = 126
	usable_width := canvas_width-horizontal_padding*2
	usable_height := canvas_height-vertical_padding-70
	x_ratio := f32(node.depth)/f32(layer_count-1)

	y := vertical_padding+usable_height*0.5
	if node.lane_count > 1 {
		y_ratio := f32(node.lane)/f32(node.lane_count-1)
		y = vertical_padding+y_ratio*usable_height
	}
	return {x = horizontal_padding+x_ratio*usable_width, y = y}
}

run_node_at_point :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	point: view.Vec2,
) -> (game.Node_Id, bool) {
	if run == nil {
		return game.INVALID_NODE_ID, false
	}
	for &node in run.route_map.nodes {
		center := run_node_center(run, &node, canvas_width, canvas_height)
		delta_x := point.x-center.x
		delta_y := point.y-center.y
		if delta_x*delta_x+delta_y*delta_y <= RUN_NODE_RADIUS*RUN_NODE_RADIUS {
			return node.id, true
		}
	}
	return game.INVALID_NODE_ID, false
}

node_is_available :: proc(run: ^game.Run_State, id: game.Node_Id) -> bool {
	return game.can_choose_node(run, id)
}

edge_color :: proc(run: ^game.Run_State, source, target: ^game.Run_Node) -> rl.Color {
	assert(run != nil && source != nil && target != nil)
	if source.cleared && target.entered {
		return rl.Color{74, 196, 133, 255}
	}
	if source.id == run.current_node && node_is_available(run, target.id) {
		return rl.Color{246, 207, 92, 255}
	}
	if source.cleared {
		return rl.Color{72, 82, 79, 255}
	}
	return rl.Color{48, 55, 58, 255}
}

node_colors :: proc(run: ^game.Run_State, node: ^game.Run_Node) -> (fill, outline: rl.Color) {
	assert(run != nil && node != nil)
	fill = rl.Color{48, 55, 58, 255}
	outline = rl.Color{105, 116, 116, 255}

	if node.cleared {
		fill = rl.Color{43, 105, 78, 255}
		outline = rl.Color{74, 196, 133, 255}
	}
	if node.id == run.current_node && run.phase == .In_Room {
		fill = rl.Color{38, 112, 111, 255}
		outline = rl.Color{71, 188, 184, 255}
	}
	if node_is_available(run, node.id) {
		fill = rl.Color{120, 91, 38, 255}
		outline = rl.Color{246, 207, 92, 255}
	}
	if node.kind == .Boss && !node.entered {
		fill = rl.Color{91, 48, 50, 255}
		outline = rl.Color{190, 78, 75, 255}
	}
	return
}

node_symbol :: proc(kind: game.Node_Kind) -> cstring {
	switch kind {
	case .Combat:
		return "C"
	case .Elite:
		return "E"
	case .Boss:
		return "B"
	}
	return "?"
}

draw_run_map :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	hovered_node: game.Node_Id = game.INVALID_NODE_ID,
) {
	assert(run != nil)
	room_number := min(run.cleared_count+1, len(run.route_map.layer_starts))

	rl.DrawRectangle(0, 0, c.int(canvas_width), 92, rl.Color{15, 18, 21, 255})
	rl.DrawText("ROUTE", 28, 22, 24, rl.Color{225, 229, 224, 255})
	rl.DrawText(
		fmt.ctprintf("%s    ROOM %d/%d    HP %d/%d    GOLD %d",
			game.run_phase_name(run.phase),
			room_number,
			len(run.route_map.layer_starts),
			run.player.health,
			run.player.stats.max_health,
			run.player.gold,
		),
		28,
		56,
		16,
		rl.Color{151, 163, 158, 255},
	)

	for &source in run.route_map.nodes {
		source_center := run_node_center(run, &source, canvas_width, canvas_height)
		for outgoing_index in 0..<source.outgoing_count {
			target, ok := game.node_at(run, source.outgoing[outgoing_index])
			assert(ok)
			target_center := run_node_center(run, target, canvas_width, canvas_height)
			color := edge_color(run, &source, target)
			rl.DrawLineEx(to_raylib(source_center), to_raylib(target_center), 3, color)
		}
	}

	for &node in run.route_map.nodes {
		center := run_node_center(run, &node, canvas_width, canvas_height)
		fill, outline := node_colors(run, &node)
		rl.DrawCircleV(to_raylib(center), RUN_NODE_RADIUS+3, rl.Color{19, 23, 26, 255})
		rl.DrawCircleV(to_raylib(center), RUN_NODE_RADIUS, fill)
		rl.DrawCircleLinesV(to_raylib(center), RUN_NODE_RADIUS, outline)
		if node.id == hovered_node {
			rl.DrawCircleLinesV(to_raylib(center), RUN_NODE_RADIUS+5, rl.Color{245, 238, 216, 255})
		}

		symbol := node_symbol(node.kind)
		font_size: c.int = 16
		text_width := rl.MeasureText(symbol, font_size)
		rl.DrawText(
			symbol,
			c.int(center.x)-text_width/2,
			c.int(center.y)-font_size/2,
			font_size,
			rl.Color{245, 238, 216, 255},
		)
		label := fmt.ctprintf("%s", game.node_kind_name(node.kind))
		label_width := rl.MeasureText(label, 12)
		rl.DrawText(label, c.int(center.x)-label_width/2, c.int(center.y)+26, 12, rl.Color{137, 148, 145, 255})
	}
	rl.DrawFPS(c.int(canvas_width)-96, 18)
}
