package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private)
CARD_RANGE_SIDE :: game.MAX_TARGETING_RANGE*2+1

// One bounded, frame-local query feeds both the floor material and its light.
// Rebuilt from current visibility: neither movement nor card changes leave trails.
@(private)
Card_Range_Preview :: struct {
	active, affordable, has_hover: bool,
	card: game.Card_Instance,
	origin: grid.Position,
	cells: [CARD_RANGE_SIDE*CARD_RANGE_SIDE]bool,
	hover: game.Card_Target_Evaluation,
}

@(private)
card_range_contains :: proc(preview: ^Card_Range_Preview, cell: grid.Position) -> bool {
	if preview == nil || !preview.active { return false }
	x, y := cell.x-preview.origin.x, cell.y-preview.origin.y
	return x >= 0 && y >= 0 && x < CARD_RANGE_SIDE && y < CARD_RANGE_SIDE && preview.cells[y*CARD_RANGE_SIDE+x]
}

@(private="file")
card_range_include :: proc(preview: ^Card_Range_Preview, cell: grid.Position) {
	x, y := cell.x-preview.origin.x, cell.y-preview.origin.y
	if x >= 0 && y >= 0 && x < CARD_RANGE_SIDE && y < CARD_RANGE_SIDE { preview.cells[y*CARD_RANGE_SIDE+x] = true }
}

@(private)
prepare_card_range_preview :: proc(renderer: ^Renderer, room: ^game.Room, card_id: u32, preview: ^Card_Range_Preview) {
	preview^ = {}
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil ||
	   room.phase != .Combat || card_id == 0 || renderer_blocks_player_input(renderer) { return }
	index, found := game.hand_card_index_by_id(&room.player.deck, card_id)
	if !found { return }
	card := room.player.deck.hand[index]
	definition, defined := game.card_definition_by_id(card.definition_id)
	if !defined { return }
	preview.active, preview.card = true, card
	preview.affordable = room.player.deck.energy >= game.card_energy_cost(room, card.definition_id)
	at := room.player.position
	preview.origin = {at.x-game.MAX_TARGETING_RANGE, at.y-game.MAX_TARGETING_RANGE}
	if definition.targeting.shape != .None {
		radius := min(definition.targeting.cast_range.maximum, game.MAX_TARGETING_RANGE)
		for y in max(0, at.y-radius)..=min(room.level_data.tiles.height-1, at.y+radius) {
			for x in max(0, at.x-radius)..=min(room.level_data.tiles.width-1, at.x+radius) {
				cell := grid.Position{x, y}
				if !tactical_render_visible(renderer, cell) { continue }
				evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, cell))
				// Reach is not validity: empty enemy slots and blocked movement
				// destinations still belong to the cast range. Cell anchors may
				// deliberately accept static terrain.
				if evaluation.query.anchor_reachable || evaluation.error == .None { card_range_include(preview, cell) }
			}
		}
	} else {
		evaluation := game.evaluate_card_targeting(room, card, {})
		if (evaluation.query.anchor_reachable || evaluation.error == .None) && tactical_render_visible(renderer, evaluation.query.anchor) {
			card_range_include(preview, evaluation.query.anchor)
		}
	}
	if card.definition_id == .Toxic_Wave {
		for enemy in room.enemies {
			if tactical_render_visible(renderer, enemy.position) && game.tactical_card_enemy_in_area(room, card.definition_id, enemy.position) {
				card_range_include(preview, enemy.position)
			}
		}
	}
	if !renderer.has_hovered_cell { return }
	// Hidden anchors fail before the game constructs a query: do not draw
	// that empty query at (0,0). Self cards always anchor on the player.
	if definition.targeting.shape != .None && (!tactical_render_visible(renderer, renderer.hovered_cell) ||
	   !game.tactical_cell_visible(room, renderer.hovered_cell)) { return }
	preview.has_hover = true
	preview.hover = game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, renderer.hovered_cell))
}

@(private="file")
CARD_LIGHT_REACH :: rl.Color{76, 164, 232, 255}
@(private="file")
CARD_LIGHT_EFFECT :: rl.Color{242, 183, 85, 255}
@(private="file")
CARD_LIGHT_TARGET :: rl.Color{130, 245, 213, 255}
@(private="file")
CARD_LIGHT_INVALID :: rl.Color{242, 91, 100, 255}

// Tint the actual moulded floor, including its bevel. Its resin, engraving
// and directional shading remain visible under the soft light drawn later.
@(private)
card_range_floor_color :: proc(preview: ^Card_Range_Preview, cell: grid.Position, base: rl.Color) -> rl.Color {
	if preview == nil || !preview.active { return base }
	amount := (f32(0.30) if preview.affordable else f32(0.10)) if card_range_contains(preview, cell) else f32(0)
	light := CARD_LIGHT_REACH
	if preview.has_hover {
		evaluation := &preview.hover
		valid := evaluation.error == .None && preview.affordable
		if game.target_cell_set_contains(&evaluation.query.affected, cell) {
			light = CARD_LIGHT_EFFECT if valid else CARD_LIGHT_INVALID
			amount = 0.42
		}
		if cell == evaluation.query.anchor {
			light = CARD_LIGHT_TARGET if valid else CARD_LIGHT_INVALID
			amount = 0.38
		}
		if evaluation.has_movement && cell == evaluation.movement.destination {
			light = CARD_LIGHT_TARGET if game.movement_query_is_clear(&evaluation.movement) && preview.affordable else CARD_LIGHT_INVALID
			amount = 0.38
		}
		if (evaluation.query.has_blocker && cell == evaluation.query.blocker) ||
		   (evaluation.has_movement && evaluation.movement.has_blocker && cell == evaluation.movement.blocker) {
			light, amount = CARD_LIGHT_INVALID, 0.42
		}
	}
	if amount == 0 { return base }
	return {u8(f32(base.r)+(f32(light.r)-f32(base.r))*amount),
	        u8(f32(base.g)+(f32(light.g)-f32(base.g))*amount),
	        u8(f32(base.b)+(f32(light.b)-f32(base.b))*amount), base.a}
}

@(private="file")
Card_Light_Edge :: enum {North, East, South, West}
@(private="file")
CARD_LIGHT_NEIGHBORS :: [Card_Light_Edge]grid.Position{.North = {0,-1}, .East = {1,0}, .South = {0,1}, .West = {-1,0}}

// Vertex alpha provides the falloff: no render target, shader, texture upload,
// per-cell draw-call flush or light allocation. All these triangles batch.
@(private="file")
card_light_vertex :: proc(p: rl.Vector3, color: rl.Color, opacity: f32) {
	rlgl.Color4ub(color.r, color.g, color.b, u8(clamp(opacity, f32(0), f32(255))))
	rlgl.Vertex3f(p.x, p.y, p.z)
}

@(private="file")
card_light_strip :: proc(a, b: rl.Vector3, inward: rl.Vector3, width: f32, color: rl.Color, alpha: f32) {
	c, d := b+inward*width, a+inward*width
	card_light_vertex(a, color, alpha); card_light_vertex(b, color, alpha); card_light_vertex(c, color, 0)
	card_light_vertex(a, color, alpha); card_light_vertex(c, color, 0); card_light_vertex(d, color, 0)
}

@(private="file")
draw_card_light_cell :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position, color: rl.Color,
	strength: f32, edges: bit_set[Card_Light_Edge], corners := false) {
	if !tactical_render_visible(renderer, cell) || !tactical_cell_on_screen(renderer, cell) { return }
	tile, exists := level.tile_at(room.level_data, cell)
	if !exists || tile.kind == .Void { return }
	y := f32(0.034)
	if tile.kind == .Exit { y = 0.112 }
	if tile.kind == .Wall { y = 0.186 }
	center := rl.Vector3{f32(cell.x)+0.5, y, f32(cell.y)+0.5}
	neighbors := CARD_LIGHT_NEIGHBORS
	points := [4]rl.Vector3{center+{-0.465,0,-0.465}, center+{0.465,0,-0.465}, center+{0.465,0,0.465}, center+{-0.465,0,0.465}}
	rlgl.Begin(rlgl.TRIANGLES)
	for a, i in points {
		b := points[(i+1)%4]
		card_light_vertex(center, color, 36*strength)
		card_light_vertex(b, color, 4*strength)
		card_light_vertex(a, color, 4*strength)
		edge := Card_Light_Edge(i)
		offset := neighbors[edge]
		inward := rl.Vector3{-f32(offset.x), 0, -f32(offset.y)}
		if edge in edges {
			// Continuous range perimeter, with a feathered glow towards the
			// centre; the narrow core keeps the exact cell boundary readable.
			card_light_strip(b, a, inward, 0.17, color, 115*strength)
			card_light_strip(b, a, inward, 0.026, color, 210*strength)
		}
		if corners {
			end := a+(b-a)*0.23
			start := b+(a-b)*0.23
			card_light_strip(end, a, inward, 0.042, color, 255*strength)
			card_light_strip(b, start, inward, 0.042, color, 255*strength)
		}
	}
	rlgl.End()
}

@(private="file")
card_effect_edges :: proc(renderer: ^Renderer, cells: ^game.Target_Cell_Set, cell: grid.Position) -> bit_set[Card_Light_Edge] {
	edges: bit_set[Card_Light_Edge]
	for offset, edge in CARD_LIGHT_NEIGHBORS {
		next := grid.Position{cell.x+offset.x, cell.y+offset.y}
		if !tactical_render_visible(renderer, next) || !game.target_cell_set_contains(cells, next) { edges += {edge} }
	}
	return edges
}

@(private)
draw_card_range_light :: proc(renderer: ^Renderer, room: ^game.Room, preview: ^Card_Range_Preview) {
	if !preview.active { return }
	// Keep depth testing for cover and walls, but do not let translucent light
	// occlude ground telegraphs, the enemy's stand or its paper sprite.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	breath := f32(0.92+0.08*math.sin(renderer.sprite_assets.elapsed*2.4))
	strength := breath*(f32(1) if preview.affordable else f32(0.36))
	for lit, i in preview.cells {
		if !lit { continue }
		cell := grid.Position{preview.origin.x+i%CARD_RANGE_SIDE, preview.origin.y+i/CARD_RANGE_SIDE}
		edges: bit_set[Card_Light_Edge]
		for offset, edge in CARD_LIGHT_NEIGHBORS {
			if !card_range_contains(preview, {cell.x+offset.x, cell.y+offset.y}) { edges += {edge} }
		}
		draw_card_light_cell(renderer, room, cell, CARD_LIGHT_REACH, strength, edges)
	}
	if !preview.has_hover { return }
	evaluation := &preview.hover
	valid := evaluation.error == .None && preview.affordable
	effect := CARD_LIGHT_EFFECT if valid else CARD_LIGHT_INVALID
	anchor := CARD_LIGHT_TARGET if valid else CARD_LIGHT_INVALID
	for cell in evaluation.query.path[:evaluation.query.path_count] {
		draw_card_light_cell(renderer, room, cell, effect, 0.40, {}, true)
	}
	for cell in evaluation.query.affected.cells[:evaluation.query.affected.count] {
		draw_card_light_cell(renderer, room, cell, effect, breath, card_effect_edges(renderer, &evaluation.query.affected, cell))
	}
	if evaluation.has_movement {
		clear := game.movement_query_is_clear(&evaluation.movement)
		color := CARD_LIGHT_TARGET if clear && preview.affordable else CARD_LIGHT_INVALID
		for cell in evaluation.movement.cells[:evaluation.movement.count] {
			draw_card_light_cell(renderer, room, cell, color, 0.65, {}, true)
		}
		if evaluation.movement.has_blocker {
			draw_card_light_cell(renderer, room, evaluation.movement.blocker, CARD_LIGHT_INVALID, 1, { .North, .East, .South, .West }, true)
		}
		draw_card_light_cell(renderer, room, evaluation.movement.destination, color, 1, { .North, .East, .South, .West }, true)
	}
	if evaluation.query.has_blocker {
		draw_card_light_cell(renderer, room, evaluation.query.blocker, CARD_LIGHT_INVALID, 1, { .North, .East, .South, .West }, true)
	}
	draw_card_light_cell(renderer, room, evaluation.query.anchor, anchor, 1, { .North, .East, .South, .West }, true)
}

// Mechanic-specific guides stay above the board (rope, ricochets, pools).
// The general range/effect light is in 3D, under threats and sprites.
@(private)
draw_card_target_details :: proc(renderer: ^Renderer, room: ^game.Room, preview: ^Card_Range_Preview) {
	if !preview.active { return }
	card := preview.card
	if card.definition_id == .Lasso { draw_lasso_preview(renderer, room, card) }
	if card.definition_id == .Pinball { draw_pinball_preview(renderer, room, card) }
	if card.definition_id == .Flood_Wave { draw_flood_preview(renderer, room) }
	if !preview.has_hover { return }
	evaluation := &preview.hover
	// CANNONE and BUCO NERO: the line of fire and the two areas.
	if game.card_is_wheel_aimed(card.definition_id) {
		draw_cannon_preview(renderer, room, card, evaluation.query.anchor, evaluation.error == .None && preview.affordable)
	}
	if card.definition_id == .Devouring_Hole {
		draw_black_hole_preview(renderer, room, card, evaluation.query.anchor, evaluation.error == .None && preview.affordable)
	}
	if game.card_places_ground(card.definition_id) {
		draw_ground_preview(renderer, room, card.definition_id, evaluation.query.anchor, evaluation.error == .None && preview.affordable)
	}
	if evaluation.has_movement && card.definition_id == .Sundering_Blow && tactical_render_visible(renderer, evaluation.movement.destination) {
		center := cell_center(renderer, evaluation.movement.destination)
		color := CARD_LIGHT_TARGET if game.movement_query_is_clear(&evaluation.movement) && preview.affordable else CARD_LIGHT_INVALID
		rl.DrawText("8+", i32(center.x)-7, i32(center.y)-5, 11, color)
	}
}
