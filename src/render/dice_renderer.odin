package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

DICE_MAX_TEXTURE_EDGE :: 2048
DICE_MAX_TEXTURE_PIXELS :: 4*1024*1024

Dice_Renderer :: struct {
	theme: ^Renderer,
	texture: rl.RenderTexture2D,
	ready, has_throw, has_frame: bool,
	requested_width, requested_height: int,
	mesh: Dice_Bevel_Mesh,
	polyhedra: [Polyhedral_Die_Kind.Count]Polyhedral_Die,
	polyhedra_ready: bool,
	frame_kind: Polyhedral_Die_Kind,
	throw_state: Dice_Throw,
	numbering: [3]Dice_Numbering,
	roll: game.Dice_Roll,
	seed: u64,
	frame: Dice_Physics_Frame,
}

Dice_Pool_Layout :: struct {
	valid: bool,
	window_width, window_height, scale, pixels_per_world, release_height: f32,
	ground: rl.Vector2,
	game_area: rl.Rectangle,
	camera: rl.Camera3D,
}

Dice_Total_State :: struct {
	revealed: int,
	visible_total: i32,
	visible_successes, visible_highest: i32,
	visible_pair: bool,
	pulse: f32,
	transfer_progress: [3]f32,
	complete: bool,
}

dice_progress :: proc(progress: f32) -> f32 {
	if math.is_nan(progress) {return 0}
	return clamp(progress, f32(0), f32(1))
}

dice_pool_roll_valid :: proc(roll: game.Dice_Roll) -> bool {
	copy := roll
	return game.validate_dice_roll(&copy)
}

dice_pool_layout :: proc(window_width, window_height: f32, game_area: rl.Rectangle = {}) -> (result: Dice_Pool_Layout) {
	if math.is_nan(window_width) || math.is_nan(window_height) || math.is_inf(window_width) ||
	   math.is_inf(window_height) || window_width <= 0 || window_height <= 0 {return}
	area := game_area
	if area == (rl.Rectangle{}) {area = {0, 0, window_width, window_height}}
	for value in ([4]f32{area.x, area.y, area.width, area.height}) {
		if math.is_nan(value) || math.is_inf(value) {return}
	}
	if area.width <= 0 || area.height <= 0 {return}
	right, bottom := min(window_width, area.x+area.width), min(window_height, area.y+area.height)
	area.x, area.y = max(f32(0), area.x), max(f32(0), area.y)
	area.width, area.height = right-area.x, bottom-area.y
	if area.width <= 0 || area.height <= 0 {return}
	result.game_area = area
	result.window_width, result.window_height = window_width, window_height
	result.scale = min(area.width/960, area.height/540)
	result.pixels_per_world = 88*result.scale
	result.ground = {area.x+area.width*0.5, area.y+area.height*0.55}
	// Tall letterboxes need a larger scene to keep the real release above the
	// window without exceeding the solver's height limit. Keep all three dice
	// inside the horizontal viewport even at their largest rotated extent.
	minimum_drop_scale := result.ground.y/(24*DICE_SCREEN_UP.y-2.2)
	horizontal_limit := min(result.ground.x, window_width-result.ground.x)/(2.4+math.sqrt(f32(3))*0.5+0.1)
	result.pixels_per_world = max(result.pixels_per_world, min(minimum_drop_scale, horizontal_limit))
	vertical_offset := (result.ground.y-window_height*0.5)/result.pixels_per_world
	target := DICE_SCREEN_UP*vertical_offset
	target.x = (window_width*0.5-result.ground.x)/result.pixels_per_world
	result.camera = {position = target+DICE_VIEW_DIRECTION*30, target = target, up = DICE_SCREEN_UP,
		fovy = window_height/result.pixels_per_world, projection = .ORTHOGRAPHIC}
	result.release_height = clamp((result.ground.y/result.pixels_per_world+2.2)/DICE_SCREEN_UP.y, f32(7), f32(24))
	result.valid = true
	return
}

dice_world_to_window :: proc(layout: Dice_Pool_Layout, point: rl.Vector3) -> rl.Vector2 {
	return {layout.ground.x+point.x*layout.pixels_per_world,
		layout.ground.y-rl.Vector3DotProduct(point, DICE_SCREEN_UP)*layout.pixels_per_world}
}

dice_texture_dimensions :: proc(width, height: f32) -> (w, h: int) {
	if width <= 0 || height <= 0 || math.is_nan(width) || math.is_nan(height) ||
	   math.is_inf(width) || math.is_inf(height) {return}
	scale := min(f32(1), f32(DICE_MAX_TEXTURE_EDGE)/max(width, height))
	scale = min(scale, math.sqrt(f32(DICE_MAX_TEXTURE_PIXELS)/(width*height)))
	return max(1, int(width*scale)), max(1, int(height*scale))
}

ensure_dice_texture :: proc(renderer: ^Dice_Renderer, width, height: f32) -> bool {
	w, h := dice_texture_dimensions(width, height)
	if w <= 0 || h <= 0 {return false}
	if renderer.requested_width == w && renderer.requested_height == h {return renderer.ready}
	if renderer.texture.id != 0 {rl.UnloadRenderTexture(renderer.texture)}
	renderer.texture, renderer.ready, renderer.has_frame = {}, false, false
	renderer.requested_width, renderer.requested_height = w, h
	renderer.texture = rl.LoadRenderTexture(c.int(w), c.int(h))
	if !rl.IsRenderTextureValid(renderer.texture) {
		if renderer.texture.id != 0 {rl.UnloadRenderTexture(renderer.texture)}
		renderer.texture = {}
		return false
	}
	rl.SetTextureFilter(renderer.texture.texture, .POINT if menu_themed(renderer.theme) else .BILINEAR)
	renderer.ready = true
	return true
}

prepare_polyhedral_models :: proc(renderer: ^Dice_Renderer) {
	if renderer == nil || renderer.polyhedra_ready { return }
	for kind in Polyhedral_Die_Kind {
		if kind != .Count { renderer.polyhedra[kind] = build_polyhedral_die(kind) }
	}
	renderer.polyhedra_ready = true
}

create_dice_renderer :: proc(renderer: ^Dice_Renderer) -> bool {
	if renderer == nil {return false}
	prepare_polyhedral_models(renderer)
	if renderer.mesh.count == 0 {renderer.mesh = build_dice_bevel_mesh()}
	if !rl.IsWindowReady() {return false}
	return ensure_dice_texture(renderer, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
}

destroy_dice_renderer :: proc(renderer: ^Dice_Renderer) {
	if renderer == nil {return}
	if renderer.texture.id != 0 {rl.UnloadRenderTexture(renderer.texture)}
	renderer^ = {}
}

prepare_dice_pool :: proc(renderer: ^Dice_Renderer, roll: game.Dice_Roll, seed: u64, layout: Dice_Pool_Layout) {
	prepare_polyhedral_models(renderer)
	if renderer.has_throw && renderer.seed == seed && renderer.roll == roll {return}
	build_dice_throw(&renderer.throw_state, roll.count, seed, layout.release_height)
	renderer.roll, renderer.seed, renderer.has_throw = roll, seed, true
	final := sample_dice_throw(&renderer.throw_state, 1)
	for index in 0..<roll.count {renderer.numbering[index] = dice_numbering_for_result(final.orientations[index], roll.faces[index])}
	if renderer.mesh.count == 0 {renderer.mesh = build_dice_bevel_mesh()}
}

draw_dice_shadow :: proc(position: rl.Vector3) {
	height := max(f32(0), position.y-0.5)
	fade := clamp((7-height)/3, f32(0), f32(1))
	if fade <= 0 {return}
	peak := 0.46*fade/(1+height*0.24+height*height*0.055)
	radius := 0.95+min(height, f32(5))*0.12
	// Height changes the softness, never the shadow's anchor on the floor.
	center := rl.Vector3{position.x+0.08, 0.006, position.z+0.04}
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for band in 0..<6 {
		inner, outer := f32(band)/6, f32(band+1)/6
		inner_alpha := u8(255*peak*(1-inner*inner)*(1-inner*inner))
		outer_alpha := u8(255*peak*(1-outer*outer)*(1-outer*outer))
		for segment in 0..<40 {
			a, b := f32(segment)*2*math.PI/40, f32(segment+1)*2*math.PI/40
			va, vb := rl.Vector3{math.cos(a)*radius, 0, math.sin(a)*radius}, rl.Vector3{math.cos(b)*radius, 0, math.sin(b)*radius}
			points := [6]rl.Vector3{center+va*inner, center+vb*outer, center+va*outer,
				center+va*inner, center+vb*inner, center+vb*outer}
			alphas := [6]u8{inner_alpha, outer_alpha, outer_alpha, inner_alpha, inner_alpha, outer_alpha}
			for index in 0..<(3 if band == 0 else 6) {
				rlgl.Color4ub(0, 0, 0, alphas[index])
				rlgl.Vertex3f(points[index].x, points[index].y, points[index].z)
			}
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// One transparent scene for the complete pool. Call before drawing app canvas.
update_dice_pool_texture :: proc(renderer: ^Dice_Renderer, roll: game.Dice_Roll, progress: f32,
	window_width, window_height: f32, game_area: rl.Rectangle = {}, seed: u64 = 1, card: game.Card_Id = .Count) {
	if renderer == nil || !dice_pool_roll_valid(roll) {return}
	layout := dice_pool_layout(window_width, window_height, game_area)
	if !layout.valid {return}
	prepare_dice_pool(renderer, roll, seed, layout)
	renderer.frame = sample_dice_throw(&renderer.throw_state, dice_progress(progress))
	if !ensure_dice_texture(renderer, window_width, window_height) {return}
	rl.BeginTextureMode(renderer.texture)
	rl.ClearBackground(rl.BLANK)
	// Accumulate alpha once. RGB is stored premultiplied by the source alpha,
	// including filtered edges, and must use a matching composite below.
	rlgl.SetBlendFactorsSeparate(rlgl.SRC_ALPHA, rlgl.ONE_MINUS_SRC_ALPHA,
		rlgl.ONE, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	rl.BeginMode3D(layout.camera)
	rlgl.DisableDepthMask()
	for index in 0..<roll.count {draw_dice_shadow(renderer.frame.positions[index])}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	resin := menu_themed(renderer.theme) && renderer.theme.tactical.light_shader.id != 0
	if resin {
		v := &renderer.theme.tactical
		eye, light := layout.camera.position, rl.Vector3{-3, 5, 4}
		mode: c.int = 2
		rl.SetShaderValue(v.light_shader, v.light_eye_location, &eye, .VEC3)
		rl.SetShaderValue(v.light_shader, v.light_position_location, &light, .VEC3)
		rl.SetShaderValue(v.light_shader, v.light_hologram_location, &mode, .INT)
		rl.BeginShaderMode(v.light_shader)
	}
	kind := polyhedral_die_for_sides(int(game.card_dice_sides(card)))
	font := rl.GetFontDefault()
	if menu_themed(renderer.theme) { font, _ = gothic_font(renderer.theme, 32) }
	for index in 0..<roll.count {
		if kind == .D4 || menu_themed(renderer.theme) {
			model := &renderer.polyhedra[kind]
			position, orientation := polyhedral_dice_pose(model, &renderer.throw_state, index, progress, roll.faces[index])
			draw_polyhedral_die(model, position, orientation, font, resin)
		} else { draw_dice_mesh(&renderer.mesh, renderer.frame.positions[index], renderer.frame.orientations[index], &renderer.numbering[index], resin) }
	}
	renderer.frame_kind = kind
	if resin { rl.EndShaderMode() }
	rl.EndMode3D()
	rl.EndBlendMode()
	rl.EndTextureMode()
	renderer.has_frame = true
}

dice_total_state :: proc(roll: game.Dice_Roll, progress: f32) -> (state: Dice_Total_State) {
	if !dice_pool_roll_valid(roll) || roll.count <= 1 {return}
	p := dice_progress(progress)
	reveal_times := DICE_POOL_REVEAL_TIMES
	for index in 0..<roll.count {
		reveal := reveal_times[index]
		if p < reveal {continue}
		state.revealed += 1
		state.visible_total += roll.faces[index]
		if roll.faces[index] >= 4 {state.visible_successes += 1}
		state.visible_highest = max(state.visible_highest, roll.faces[index])
		age := (p-reveal)/DICE_POOL_REVEAL_STEP
		state.transfer_progress[index] = clamp(age, f32(0), f32(1))
		state.pulse = max(state.pulse, max(f32(0), 1-age))
	}
	state.visible_pair = roll.count == 2 && state.revealed == 2 && roll.faces[0] == roll.faces[1]
	state.complete = p >= DICE_POOL_COMPLETE_PROGRESS
	return
}

dice_total_bounds :: proc(center: rl.Vector2, scale: f32, extended: bool = false) -> rl.Rectangle {
	if extended {return {center.x-76*scale, center.y-32*scale, 152*scale, 90*scale}}
	return {center.x-44*scale, center.y-32*scale, 88*scale, 72*scale}
}

dice_final_projected_bounds :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, index: int) -> (bounds: rl.Rectangle) {
	final := sample_dice_throw(&renderer.throw_state, 1)
	left, top, right, bottom := f32(1e9), f32(1e9), f32(-1e9), f32(-1e9)
	for corner in 0..<8 {
		point := rl.Vector3{0.5 if corner&1 != 0 else -0.5,
			0.5 if corner&2 != 0 else -0.5, 0.5 if corner&4 != 0 else -0.5}
		world := final.positions[index]+rl.Vector3RotateByQuaternion(point, final.orientations[index])
		pixel := dice_world_to_window(layout, world)
		left, right = min(left, pixel.x), max(right, pixel.x)
		top, bottom = min(top, pixel.y), max(bottom, pixel.y)
	}
	margin := 10*layout.scale
	return {left-margin, top-margin, right-left+margin*2, bottom-top+margin*2}
}

// Resolve once from the final physical poses, so partial sums never jump around.
dice_total_target :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, extended: bool = false) -> rl.Vector2 {
	area := layout.game_area
	preferred := rl.Vector2{layout.ground.x, area.y+area.height*0.76}
	if renderer != nil && menu_themed(renderer.theme) {
		// Keep the result beside the board, clear of both the dice and the hand.
		return {area.x+area.width*0.85, area.y+area.height*0.30}
	}
	margin := f32(68) if extended else f32(54)
	preferred.y = min(preferred.y, area.y+area.height*0.865-margin*layout.scale)
	if renderer == nil || !renderer.has_throw {return preferred}
	bounds: [3]rl.Rectangle
	for index in 0..<renderer.roll.count {bounds[index] = dice_final_projected_bounds(renderer, layout, index)}
	best, least_overlap := preferred, f32(1e20)
	for row in 0..<2 {
		for offset in ([7]f32{0, -0.1, 0.1, -0.2, 0.2, -0.3, 0.3}) {
			candidate := preferred+rl.Vector2{offset*area.width, -f32(row)*area.height*0.07}
			label_bounds := dice_total_bounds(candidate, layout.scale, extended)
			overlap: f32
			for die in bounds[:renderer.roll.count] {
				width := min(label_bounds.x+label_bounds.width, die.x+die.width)-max(label_bounds.x, die.x)
				height := min(label_bounds.y+label_bounds.height, die.y+die.height)-max(label_bounds.y, die.y)
				overlap += max(f32(0), width)*max(f32(0), height)
			}
			if overlap == 0 {return candidate}
			if overlap < least_overlap {best, least_overlap = candidate, overlap}
		}
	}
	return best
}

draw_dice_pool_total :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, roll: game.Dice_Roll, progress: f32,
	card: game.Card_Id = .Count) {
	theme: ^Renderer
	if renderer != nil { theme = renderer.theme }
	state := dice_total_state(roll, progress)
	if state.revealed == 0 {return}
	successes, highest := card == .Prismatic_Barrage, card == .Twin_Venom
	extended := successes || highest
	target := dice_total_target(renderer, layout, extended)
	if menu_themed(theme) {
		bounds := dice_total_bounds(target, layout.scale, extended)
		gothic_frame(bounds, RESIN_BACKGROUND, RESIN_CAP)
	}
	font := c.int(max(f32(20), (44+8*state.pulse)*layout.scale))
	label := fmt.ctprintf("%d", state.visible_total)
	if successes {label = fmt.ctprintf("%d/3", state.visible_successes)}
	if highest {label = fmt.ctprintf("%d", state.visible_highest)}
	x := c.int(target.x)-menu_measure_text(theme, label, font)/2
	y := c.int(target.y)-font/2
	menu_text(theme, label, x+3, y+4, font, {0, 0, 0, 190})
	menu_text(theme, label, x+1, y+2, font, {171, 24, 32, 230})
	menu_text(theme, label, x, y, font, {255, 243, 225, 255})
	caption_font := c.int(max(f32(8), 10*layout.scale))
	caption: cstring = "TOTAL"
	if successes {caption = "4+ SUCCESSES"}
	if highest {caption = "HIGHEST / PAIR!" if state.visible_pair else "HIGHEST DIE"}
	if menu_themed(theme) {
		caption = "TOTALE"
		if successes { caption = "4+ SUCCESSI" }
		if highest { caption = "MASSIMO / COPPIA!" if state.visible_pair else "DADO MAGGIORE" }
	}
	caption_x := c.int(target.x)-menu_measure_text(theme, caption, caption_font)/2
	caption_y := c.int(target.y+29*layout.scale)
	menu_text(theme, caption, caption_x+1, caption_y+1, caption_font, {0, 0, 0, 180})
	caption_color := rl.Color{235, 119, 117, 255}
	if successes {caption_color = {255, 205, 116, 255}}
	if highest {caption_color = {163, 232, 128, 255}}
	menu_text(theme, caption, caption_x, caption_y, caption_font, caption_color)
	if extended {
		total := fmt.ctprintf("TOTAL %d", state.visible_total)
		total_x := c.int(target.x)-menu_measure_text(theme, total, caption_font)/2
		total_y := c.int(target.y+43*layout.scale)
		menu_text(theme, total, total_x+1, total_y+1, caption_font, {0, 0, 0, 180})
		menu_text(theme, total, total_x, total_y, caption_font, {221, 214, 209, 255})
	}
	if renderer == nil || !renderer.has_throw {return}
	for index in 0..<state.revealed {
		p := state.transfer_progress[index]
		if p >= 1 {continue}
		from := dice_world_to_window(layout, renderer.frame.positions[index])
		from.y -= layout.pixels_per_world*0.70
		eased := p*p*(3-2*p)
		center := from+(target-from)*eased
		center.y -= math.sin(p*math.PI)*25*layout.scale
		small_font := c.int(max(f32(11), 20*layout.scale))
		text := fmt.ctprintf("+%d", roll.faces[index])
		if successes {text = "+1" if roll.faces[index] >= 4 else "+1 SHIELD"}
		if highest {text = fmt.ctprintf("%d", roll.faces[index])}
		color := rl.Color{255, 235, 204, u8(255*(1-p))}
		menu_text(theme, text, c.int(center.x)-menu_measure_text(theme, text, small_font)/2, c.int(center.y), small_font, color)
	}
}

draw_dice_pool_fallback :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, roll: game.Dice_Roll, card: game.Card_Id = .Count) {
	for index in 0..<roll.count {
		position := rl.Vector3{(f32(index)-f32(roll.count-1)*0.5)*1.25, 0.5, 0}
		if renderer != nil && renderer.has_throw {position = renderer.frame.positions[index]}
		center := dice_world_to_window(layout, position)
		side := layout.pixels_per_world
		bounds := rl.Rectangle{center.x-side*0.5, center.y-side*0.5, side, side}
		if game.card_dice_sides(card) == 4 {
			rl.DrawTriangle(center+rl.Vector2{0,-side*0.6}, center+rl.Vector2{-side*0.55,side*0.35}, center+rl.Vector2{side*0.55,side*0.35}, DICE_BODY_COLOR)
		} else { rl.DrawRectangleRounded(bounds, 0.18, 6, DICE_BODY_COLOR) }
		if game.card_dice_sides(card) == 4 || (renderer != nil && menu_themed(renderer.theme)) {
			label := fmt.ctprintf("%d", roll.faces[index])
			theme := renderer.theme if renderer != nil else nil
			size := c.int(side*0.45)
			menu_text(theme, label, c.int(center.x)-menu_measure_text(theme,label,size)/2, c.int(center.y-side*0.22), size, GOTHIC_PAPER)
		} else {
			pips, count := dice_pip_positions(roll.faces[index])
			for pip in pips[:count] {rl.DrawCircleV(center+pip*side, side*0.068, DICE_PIP_COLOR)}
		}
	}
}

// Composite after app canvas in window coordinates, including letterbox.
draw_dice_pool_overlay :: proc(renderer: ^Dice_Renderer, roll: game.Dice_Roll, progress: f32,
	window_width, window_height: f32, game_area: rl.Rectangle = {}, seed: u64 = 1, card: game.Card_Id = .Count) {
	if !dice_pool_roll_valid(roll) {return}
	layout := dice_pool_layout(window_width, window_height, game_area)
	if !layout.valid {return}
	if renderer != nil && renderer.ready && renderer.has_frame && renderer.seed == seed && renderer.roll == roll &&
	   renderer.frame_kind == polyhedral_die_for_sides(int(game.card_dice_sides(card))) {
		rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
		rl.DrawTexturePro(renderer.texture.texture,
			{0, 0, f32(renderer.texture.texture.width), -f32(renderer.texture.texture.height)},
			{0, 0, window_width, window_height}, {}, 0, rl.WHITE)
		rl.EndBlendMode()
	} else {draw_dice_pool_fallback(renderer, layout, roll, card)}
	if roll.count > 1 {draw_dice_pool_total(renderer, layout, roll, progress, card)}
	if game.card_dice_sides(card) == 4 { draw_d4_result_label(renderer,layout,progress,roll.total) }
}

update_dice_texture :: proc(renderer: ^Dice_Renderer, face: i32, progress: f32) {
	value := clamp(face, i32(1), i32(6))
	update_dice_pool_texture(renderer, {faces = {value, 0, 0}, count = 1, total = value}, progress,
		f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
}

draw_dice_overlay :: proc(renderer: ^Dice_Renderer, window_width, window_height: f32, face: i32,
	progress: f32, game_area: rl.Rectangle = {}) {
	value := clamp(face, i32(1), i32(6))
	draw_dice_pool_overlay(renderer, {faces = {value, 0, 0}, count = 1, total = value}, progress, window_width, window_height, game_area)
}
