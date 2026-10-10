package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// The character sheet: the Viandante modelled in Blender
// (tools/art/build_pilgrim.py) stands on a plinth in a small chapel built
// from the board's wall kit, lit by its own lantern, beside the run's stats.

PILGRIM_MODEL_BYTES := #load("../../assets/models/pilgrim.odm")
// The lantern's flame in the model (game space), from build_pilgrim.py.
PILGRIM_LANTERN :: rl.Vector3{0.46, 0.98, 0.36}
SHEET_PLINTH :: f32(0.14)

load_pilgrim_model :: proc(model: ^[]Diorama_Vertex) -> bool {
	delete(model^)
	vertices, ok := load_odm_vertices(PILGRIM_MODEL_BYTES)
	model^ = vertices
	return ok
}

sheet_turn :: proc(v: rl.Vector3, angle: f32) -> rl.Vector3 {
	c, s := math.cos(angle), math.sin(angle)
	return {v.x*c+v.z*s, v.y, -v.x*s+v.z*c}
}

draw_sheet_model :: proc(vertices: []Diorama_Vertex, origin: rl.Vector3, angle: f32) {
	if len(vertices) == 0 { return }
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	for first := 0; first+2 < len(vertices); first += 3 {
		// Keep each submission well inside one render batch.
		if first%3000 == 0 { rlgl.CheckRenderBatchLimit(3000) }
		rlgl.Begin(rlgl.TRIANGLES)
		for vertex in vertices[first:first+3] {
			p := sheet_turn(vertex.position, angle)+origin
			n := sheet_turn(vertex.normal, angle)
			rlgl.Color4ub(vertex.color[0], vertex.color[1], vertex.color[2], vertex.color[3])
			rlgl.Normal3f(n.x, n.y, n.z)
			rlgl.TexCoord2f(0, 0)
			rlgl.Vertex3f(p.x, p.y, p.z)
		}
		rlgl.End()
	}
	rlgl.SetTexture(0)
}

// BeginMode3D centres the camera on the whole canvas. An off-centre frustum
// moves the principal point to the stage, keeping its own field of view and
// aspect, so the figure is framed by the camera rather than by target hacks.
sheet_stage_projection :: proc(renderer: ^Renderer, stage: rl.Rectangle, fovy: f32) {
	w, h := renderer.canvas_width, renderer.canvas_height
	near, far := f64(0.05), f64(60)
	half := math.tan(f64(fovy)*0.5*math.RAD_PER_DEG)*f64(h/stage.height)
	top := near*half
	right := top*f64(w/h)
	ax := f64(2*(stage.x+stage.width*0.5)/w-1)
	ay := f64(1-2*(stage.y+stage.height*0.5)/h)
	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.LoadIdentity()
	rlgl.Frustum(-right*(1+ax), right*(1-ax), -top*(1+ay), top*(1-ay), near, far)
	rlgl.MatrixMode(rlgl.MODELVIEW)
}

begin_sheet_lighting :: proc(renderer: ^Renderer, camera: rl.Camera3D, lantern: rl.Vector3) -> bool {
	v := &renderer.tactical
	if v.light_shader.id == 0 { return false }
	eye := camera.position
	local := lantern+rl.Vector3{0, 0.4, 0.3}
	mode: c.int = 0
	clear := f32(0.12)
	lights := [4]rl.Vector4{
		{lantern.x, lantern.y, lantern.z, 1.3},
		{-1.6, 2.2, -0.9, 0.55},
		{1.1, 1.1, -1.25, 0.7},
		{},
	}
	rl.SetShaderValue(v.light_shader, v.light_position_location, &local, .VEC3)
	rl.SetShaderValue(v.light_shader, v.light_eye_location, &eye, .VEC3)
	rl.SetShaderValue(v.light_shader, v.light_hologram_location, &mode, .INT)
	rl.SetShaderValue(v.light_shader, v.light_clear_location, &clear, .FLOAT)
	rl.SetShaderValueV(v.light_shader, v.light_accents_location, raw_data(lights[:]), .VEC4, 4)
	rl.BeginShaderMode(v.light_shader)
	return true
}

// A three-bay chapel wall with a lancet in the middle, two rose windows and
// a lantern sconce, over a few floor slabs: the board's own masonry.
draw_sheet_chapel :: proc(renderer: ^Renderer) {
	kit := &renderer.tactical.kit
	for z in -2..=1 { for x in -2..=2 {
		p := rl.Vector3{f32(x), 0, f32(z)+0.5}
		shade := u8(gothic_hash(x+7, z+3)%9)
		draw_resin_cube(renderer, p+rl.Vector3{0, -0.155, 0}, 0.99, 0.31, 0.99, RESIN_DARK)
		draw_resin_cube(renderer, p+rl.Vector3{0, -0.05, 0}, 0.945, 0.135, 0.945, {40+shade, 49+shade, 62+shade, 255})
	} }
	if !kit.loaded { return }
	faces := [3]Diorama_Piece{.Face_Rose, .Face_Lancet, .Face_Rose}
	for face, index in faces {
		origin := rl.Vector3{f32(index-1), 0, -1.5}
		draw_diorama_piece(kit, .Core, origin, 0)
		draw_diorama_piece(kit, face, origin, 0)
		draw_diorama_piece(kit, .Merlons, origin, 0)
		draw_diorama_piece(kit, .Cap, origin+rl.Vector3{0, DIORAMA_WALL_HEIGHT, 0}, 0)
		for side in 1..=3 { draw_diorama_piece(kit, .Link, origin, side) }
		for corner in 0..<4 { draw_diorama_piece(kit, .Pilaster if corner == 0 || corner == 3 else .Post, origin, corner) }
	}
	draw_diorama_piece(kit, .Sconce, {1.12, DIORAMA_WALL_HEIGHT*0.58, -1.03}, 0)
}

draw_character_stage :: proc(renderer: ^Renderer, stage: rl.Rectangle) {
	rl.BeginScissorMode(c.int(stage.x), c.int(stage.y), c.int(stage.width), c.int(stage.height))
	defer rl.EndScissorMode()
	rl.DrawRectangleGradientV(c.int(stage.x), c.int(stage.y), c.int(stage.width), c.int(stage.height), {6, 11, 19, 255}, {2, 4, 8, 255})
	camera := rl.Camera3D{position = {0.4, 1.3, 5.3}, target = {0, 0.9, -0.2}, up = {0, 1, 0}, fovy = 33, projection = .PERSPECTIVE}
	angle := f32(math.sin(renderer.sprite_assets.elapsed*0.4))*0.62-0.28
	lantern := sheet_turn(PILGRIM_LANTERN, angle)+rl.Vector3{0, SHEET_PLINTH, 0}
	rl.BeginMode3D(camera)
	sheet_stage_projection(renderer, stage, camera.fovy)
	lit := begin_sheet_lighting(renderer, camera, lantern)
	draw_sheet_chapel(renderer)
	draw_resin_cube(renderer, {0, SHEET_PLINTH*0.5, 0}, 1.05, SHEET_PLINTH, 1.05, RESIN_DARK)
	draw_resin_cube(renderer, {0, SHEET_PLINTH-0.01, 0}, 0.86, 0.04, 0.86, RESIN_CAP)
	draw_sheet_model(renderer.tactical.pilgrim, {0, SHEET_PLINTH+0.01, 0}, angle)
	if lit { rl.EndShaderMode() }
	draw_diorama_lamp_glow(renderer, lantern, {0, 0}, 0.9)
	draw_diorama_lamp_glow(renderer, {1.12, DIORAMA_WALL_HEIGHT*0.58, -1.03}, {1, 0}, 0.6)
	rl.EndMode3D()
	// A cold vignette folds the chapel into the frame.
	for edge in 0..<6 {
		inset := f32(edge)*3
		rl.DrawRectangleLinesEx({stage.x+inset, stage.y+inset, stage.width-inset*2, stage.height-inset*2}, 3, {2, 4, 8, u8(120-edge*18)})
	}
}

sheet_section :: proc(renderer: ^Renderer, bounds: rl.Rectangle, title: cstring, accent: rl.Color) {
	hud_frame(bounds, accent)
	gothic_text(renderer, title, bounds.x+12, bounds.y+6, 12, accent)
	gothic_rule(bounds.x+12, bounds.y+24, bounds.width-24, {34, 46, 62, 255})
}

sheet_stat :: proc(renderer: ^Renderer, bounds: rl.Rectangle, label, value: cstring, accent: rl.Color, detail: cstring = nil) {
	gothic_text(renderer, label, bounds.x, bounds.y, 10, GOTHIC_MUTED)
	gothic_text_fit(renderer, value, {bounds.x, bounds.y+11, bounds.width, 24}, 24, accent)
	if detail != nil { gothic_text_fit(renderer, detail, {bounds.x, bounds.y+36, bounds.width, 14}, 10, GOTHIC_MUTED) }
}

draw_character_sheet :: proc(renderer: ^Renderer, room: ^game.Room) {
	width, height := renderer.canvas_width, renderer.canvas_height
	player := room.player
	rl.DrawRectangleRec({0, 0, width, height}, {3, 7, 13, 225})
	panel := rl.Rectangle{36, 38, width-72, height-76}
	hud_frame(panel, GOTHIC_PAPER)
	gothic_text(renderer, "IL VIANDANTE", panel.x+22, panel.y+12, 32, GOTHIC_PAPER)
	gothic_text(renderer, "SCHEDA DEL PELLEGRINO / TEMPO SOSPESO", panel.x+24, panel.y+48, 12, GOTHIC_MUTED)
	hud_button(renderer, m8_modal_control_bounds(renderer, .Close_Character), "ESC", "CHIUDI", true, GOTHIC_PAPER)
	stage := rl.Rectangle{panel.x+14, panel.y+72, panel.width*0.40, panel.height-86}
	draw_character_stage(renderer, stage)
	rl.DrawRectangleLinesEx(stage, 1, HUD_EDGE)
	gothic_text(renderer, "LANTERNA DEL PELLEGRINO", stage.x+12, stage.y+stage.height-22, 10, {120, 200, 236, 255})

	x := stage.x+stage.width+14
	right := panel.x+panel.width-14
	w := right-x
	// STATISTICHE: six tiles.
	stats := rl.Rectangle{x, stage.y, w, 140}
	sheet_section(renderer, stats, "STATISTICHE", GOTHIC_BLUE)
	tile_w := (w-24)/3
	base_attack := player.stats.attack
	attack := game.player_basic_attack_damage(player)
	tiles := [6]struct{label, value, detail: cstring, accent: rl.Color}{
		{"VITA", fmt.ctprintf("%d/%d", player.health, player.stats.max_health), nil, GOTHIC_RED},
		{"ATTACCO", fmt.ctprintf("%d", attack), fmt.ctprintf("BASE %d + ARMA %d", base_attack, attack-base_attack), GOTHIC_PAPER},
		{"DIFESA", fmt.ctprintf("%d", player.stats.defense), nil, GOTHIC_PAPER},
		{"ENERGIA", fmt.ctprintf("%d/%d", player.deck.energy, player.deck.rules.max_energy), nil, GOTHIC_BLUE},
		{"ORO", fmt.ctprintf("%d", player.gold), nil, HUD_AMBER},
		{"RING", fmt.ctprintf("%d", player.m8_profile.ring_wins), fmt.ctprintf("LEGGENDA %d / 3", min(u32(3), player.m8_profile.ring_wins)), GOTHIC_BLUE},
	}
	for tile, index in tiles {
		bounds := rl.Rectangle{x+12+f32(index%3)*tile_w, stats.y+32+f32(index/3)*54, tile_w-8, 50}
		sheet_stat(renderer, bounds, tile.label, tile.value, tile.accent, tile.detail)
	}
	hud_bar({x+12+tile_w*0.62, stats.y+46, tile_w*0.38-14, 8}, f32(player.health)/f32(max(i32(1), player.stats.max_health)), GOTHIC_RED)

	// EQUIPAGGIAMENTO: weapon and reserve, uses as pips.
	gear := rl.Rectangle{x, stats.y+stats.height+10, w, 86}
	sheet_section(renderer, gear, "EQUIPAGGIAMENTO", HUD_AMBER)
	slots := [2]game.Weapon_Slot{player.equipment.weapon, player.equipment.reserve}
	names := [2]cstring{"ARMA", "RISERVA"}
	for slot, index in slots {
		bounds := rl.Rectangle{x+12+f32(index)*(w-24)*0.5, gear.y+32, (w-24)*0.5-8, 46}
		gothic_text(renderer, names[index], bounds.x, bounds.y, 10, GOTHIC_MUTED)
		if definition, found := game.weapon_definition(slot.id); found {
			gothic_text_fit(renderer, fmt.ctprintf("%s +%d", definition.name, definition.bonus_damage), {bounds.x, bounds.y+12, bounds.width, 18}, 14, GOTHIC_PAPER)
			for use in 0..<int(definition.max_uses) {
				gothic_inlay(bounds.x+6+f32(use)*13, bounds.y+38, 4, HUD_AMBER if use < int(slot.uses_remaining) else GOTHIC_STEEL)
			}
		} else {
			gothic_text_fit(renderer, "MANI NUDE" if index == 0 else "VUOTA", {bounds.x, bounds.y+12, bounds.width, 18}, 14, GOTHIC_MUTED)
		}
	}

	// PASSIVE and MAZZO share the last row.
	row_y := gear.y+gear.height+10
	row_h := stage.y+stage.height-row_y
	relics := rl.Rectangle{x, row_y, w*0.56-5, row_h}
	sheet_section(renderer, relics, fmt.ctprintf("PASSIVE / %d", player.relics.count), {164, 144, 183, 255})
	if player.relics.count == 0 {
		gothic_text(renderer, "NESSUNA RELIQUIA", relics.x+12, relics.y+34, 12, GOTHIC_MUTED)
	}
	capacity := max(0, int((relics.height-34)/22))*2
	for id, index in player.relics.owned[:min(player.relics.count, capacity)] {
		definition, found := game.relic_definition(id)
		if !found { continue }
		cell_w := (relics.width-24)*0.5
		bounds := rl.Rectangle{relics.x+12+f32(index%2)*cell_w, relics.y+32+f32(index/2)*22, cell_w-6, 19}
		hud_chip(renderer, bounds, fmt.ctprintf("%s %s", relic_mark(id), definition.name), relic_color(id))
	}
	deck := rl.Rectangle{relics.x+relics.width+10, row_y, right-(relics.x+relics.width+10), row_h}
	sheet_section(renderer, deck, fmt.ctprintf("MAZZO / %d", player.deck.owned_count), GOTHIC_PAPER)
	// Count each card once, in the order the deck first holds it.
	seen: [16]game.Card_Id
	counts: [16]int
	kinds := 0
	for card in player.deck.owned[:player.deck.owned_count] {
		found := false
		for kind in 0..<kinds {
			if seen[kind] == card.definition_id { counts[kind] += 1; found = true; break }
		}
		if !found && kinds < len(seen) { seen[kinds] = card.definition_id; counts[kinds] = 1; kinds += 1 }
	}
	lines := max(0, int((deck.height-34)/17))
	for kind in 0..<min(kinds, lines) {
		definition, found := game.card_definition_by_id(seen[kind], true)
		if !found { continue }
		gothic_text_fit(renderer, fmt.ctprintf("%dx %s", counts[kind], definition.name), {deck.x+12, deck.y+32+f32(kind)*17, deck.width-24, 16}, 12, GOTHIC_PAPER)
	}
	if kinds > lines && lines > 0 {
		gothic_text(renderer, fmt.ctprintf("+%d", kinds-lines), deck.x+deck.width-34, deck.y+6, 12, GOTHIC_MUTED)
	}
}
