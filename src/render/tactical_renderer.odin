package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../grid"
import level "../level"
import view "../view"

Tactical_View :: struct {
	art: Gothic_Art,
	enabled, scene_3d, perspective, no_fog: bool,
	refocus_enabled: bool,
	camera: rl.Camera3D,
	draw_frustum: Tactical_Draw_Frustum,
	zoom: f32,
	visible: [game.MAX_TACTICAL_VISION*game.MAX_TACTICAL_VISION]grid.Position,
	world_orbit, hologram_orbit: Tactical_Orbit,
	light_shader: rl.Shader,
	outline_shader: rl.Shader,
	outline_mode: Comic_Outline_Mode,
	outline_bounds_location, outline_texel_location, outline_radius_location: c.int,
	light_position_location, light_hologram_location, light_eye_location: c.int,
	light_clear_location, light_accents_location: c.int,
	clear_light: f32,
	translucents: ^Tactical_Alpha_Buffer,
	labels: ^Tactical_Label_Layout,
	surface: ^Tactical_Surface,
	block_mesh: Dice_Bevel_Mesh,
	visible_count: int,
	snapshot: ^Room_Presentation,
	fallback: [11]rl.Texture2D,
	flipbook: Flipbook_Assets,
	flipbook_state: ^Flipbook_State,
}

create_tactical_assets :: proc(renderer: ^Renderer, parent: rl.RenderTexture2D = {}) {
	renderer.tactical.snapshot = new(Room_Presentation)
	renderer.tactical.labels = new(Tactical_Label_Layout)
	renderer.tactical.block_mesh = build_dice_bevel_mesh()
	create_tactical_lighting(renderer)
	create_comic_outline(renderer)
	create_gothic_art(&renderer.tactical.art)
	create_flipbook_assets(&renderer.tactical.flipbook)
	renderer.tactical.flipbook_state = new(Flipbook_State)
	create_tactical_surface(renderer, parent)
	for &texture, index in renderer.tactical.fallback {
		img := rl.GenImageColor(48, 64, rl.BLANK)
		color := rl.Color{239, 105, 100, 255}
		if index == 0 { color = {80, 225, 217, 255} }
		if index == 2 { color = {239, 189, 105, 255} }
		if index == 3 { color = {204, 116, 92, 255} }
		if index == 5 || index == 6 { color = {182, 131, 239, 255} }
		if index >= 7 { color = {172, 177, 218, 255} }
		if index == 8 { color = {255, 161, 65, 255} }
		rl.ImageDrawRectangle(&img, 10, 27, 28, 25, rl.Color{25, 37, 52, 255})
		rl.ImageDrawRectangle(&img, 14, 29, 20, 21, color)
		rl.ImageDrawCircle(&img, 24, 20, 11, rl.Color{25, 37, 52, 255})
		rl.ImageDrawCircle(&img, 24, 19, 8, color)
		rl.ImageDrawRectangle(&img, 16, 51, 6, 10, color)
		rl.ImageDrawRectangle(&img, 27, 51, 6, 10, color)
		rl.ImageDrawRectangle(&img, 20, 18, 3, 3, rl.WHITE)
		rl.ImageDrawRectangle(&img, 27, 18, 3, 3, rl.WHITE)
		if index == 0 {
			rl.ImageDrawRectangle(&img, 14, 29, 20, 7, rl.Color{192, 255, 246, 255})
			rl.ImageDrawRectangle(&img, 22, 37, 5, 14, rl.Color{38, 90, 112, 255})
		}
		if index == 2 { rl.ImageDrawCircleLines(&img, 36, 35, 13, rl.Color{242, 208, 163, 255}) }
		if index == 5 || index == 6 {
			rl.ImageDrawRectangle(&img, 7, 27, 10, 11, color)
			rl.ImageDrawRectangle(&img, 31, 27, 10, 11, color)
			rl.ImageDrawRectangle(&img, 17, 10, 14, 4, rl.GOLD)
		}
		texture = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
	}
}

destroy_tactical_assets :: proc(renderer: ^Renderer) {
	destroy_renderer_world_playback(renderer)
	destroy_tactical_translucents(renderer)
	destroy_tactical_surface(renderer)
	destroy_gothic_art(&renderer.tactical.art)
	destroy_flipbook_assets(&renderer.tactical.flipbook)
	if renderer.tactical.flipbook_state != nil { free(renderer.tactical.flipbook_state); renderer.tactical.flipbook_state = nil }
	if renderer.tactical.outline_shader.id != 0 { rl.UnloadShader(renderer.tactical.outline_shader); renderer.tactical.outline_shader = {} }
	if renderer.tactical.labels != nil { free(renderer.tactical.labels); renderer.tactical.labels = nil }
	if renderer.tactical.light_shader.id != 0 { rl.UnloadShader(renderer.tactical.light_shader); renderer.tactical.light_shader = {} }
	if renderer.tactical.snapshot != nil { free(renderer.tactical.snapshot); renderer.tactical.snapshot = nil }
	for &texture in renderer.tactical.fallback {
		if texture.id != 0 { rl.UnloadTexture(texture); texture = {} }
	}
}

tactical_render_visible :: proc(renderer: ^Renderer, position: grid.Position) -> bool {
	if !renderer.tactical.enabled || renderer.tactical.no_fog { return true }
	for cell in renderer.tactical.visible[:renderer.tactical.visible_count] {
		if cell == position { return true }
	}
	return false
}

tactical_presentation_opaque :: proc(renderer: ^Renderer, room: ^game.Room, position: grid.Position) -> bool {
	tile, found := level.tile_at(room.level_data, position)
	if !found || tile.kind == .Wall || tile.kind == .Void { return true }
	for obstacle in room.obstacles { if obstacle.position == position { return true } }
	for object in renderer.tactical.snapshot.objects[:renderer.tactical.snapshot.object_count] {
		if object.visible && int(math.round(object.position.x)) == position.x && int(math.round(object.position.y)) == position.y {
			definition, ok := game.grid_object_definition(object.kind)
			if ok && definition.blocks_line_of_sight { return true }
		}
	}
	return false
}

update_tactical_view :: proc(renderer: ^Renderer, room: ^game.Room, mouse: view.Vec2, inside: bool, refresh_only: bool = false) {
	v := &renderer.tactical
	if !v.enabled { return }
	v.snapshot^ = renderer_presentation_snapshot(renderer, room)
	v.no_fog = room.player.tactical.config.vision_size == 0 || tactical_room_is_clear(v.snapshot.phase)
	if !tactical_room_is_clear(v.snapshot.phase) { v.clear_light = 0 }
	v.refocus_enabled = room.phase == .Combat && game.tactical_allows_action(room)
	p := v.snapshot.player.position
	origin := grid.Position{int(math.round(p.x)), int(math.round(p.y))}
	v.visible_count = 0
	size := game.tactical_vision_size(room.player.tactical.config, &v.snapshot.player.statuses)
	visibility := Tactical_Visibility_Context{renderer, room}
	for dy in -size/2..=size/2 {
		for dx in -size/2..=size/2 {
			cell := grid.Position{origin.x+dx, origin.y+dy}
			if !grid.contains(&room.level_data.tiles, cell) ||
			   !game.tactical_in_footprint(size, room.player.tactical.facing, origin, cell) ||
			   !game.tactical_line_visible(origin, cell, tactical_snapshot_opaque, &visibility) { continue }
			v.visible[v.visible_count] = cell
			v.visible_count += 1
		}
	}
	if !v.world_orbit.initialized { reset_tactical_orbit(&v.world_orbit) }
	if inside && !refresh_only {
		update_tactical_orbit_input(&v.world_orbit, mouse, point_in_rectangle(mouse, tactical_world_bounds(renderer)), .MIDDLE)
	}
	// Aim slightly in front of the player to reserve the bottom for a full hand.
	forward := rl.Vector3{math.cos(v.world_orbit.yaw), 0, math.sin(v.world_orbit.yaw)}
	footprint_scale := 1.1+f32(max(0, size-5))*0.065
	target := rl.Vector3{p.x+0.5, 0, p.y+0.5}+forward*(1.10*footprint_scale)
	framed_orbit := v.world_orbit
	framed_orbit.distance *= footprint_scale
	v.zoom = framed_orbit.distance*0.65
	v.camera = tactical_orbit_camera(framed_orbit, target, v.perspective)
	v.draw_frustum = tactical_draw_frustum(v.camera, renderer.canvas_width, renderer.canvas_height)
	renderer.camera.zoom = 1.1/footprint_scale*12.5/v.world_orbit.distance
	renderer.camera.origin = {renderer.canvas_width*0.5, renderer.canvas_height*0.44}
	center := view.grid_point_to_world(&renderer.projection, {p.x+0.5, p.y+0.5})
	renderer.camera.origin.x -= center.x*renderer.camera.zoom
	renderer.camera.origin.y -= center.y*renderer.camera.zoom
	if refresh_only { return }
	renderer.has_hovered_cell = false
	if !inside || !point_in_rectangle(mouse, tactical_world_bounds(renderer)) || renderer_blocks_player_input(renderer) { return }
	cell: grid.Position
	if v.scene_3d {
		ray := rl.GetScreenToWorldRayEx(to_raylib(mouse), v.camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
		if abs(ray.direction.y) < 0.0001 { return }
		t := -ray.position.y/ray.direction.y
		if t <= 0 { return }
		point := ray.position+ray.direction*t
		cell = {int(math.floor(point.x)), int(math.floor(point.z))}
	} else { cell = view.canvas_to_cell(&renderer.camera, &renderer.projection, mouse) }
	if grid.contains(&room.level_data.tiles, cell) && tactical_render_visible(renderer, cell) {
		renderer.has_hovered_cell = true
		renderer.hovered_cell = cell
	}
	update_tactical_body_hover(renderer, mouse)
}

tactical_project :: proc(renderer: ^Renderer, position: view.Vec2, height: f32 = 0) -> view.Vec2 {
	if !renderer.tactical.scene_3d { return view.grid_point_to_canvas(&renderer.camera, &renderer.projection, position) }
	p := rl.GetWorldToScreenEx({position.x, height, position.y}, renderer.tactical.camera,
		c.int(renderer.canvas_width), c.int(renderer.canvas_height))
	return {p.x, p.y}
}

Tactical_Billboard :: struct {
	points: [4]rl.Vector3,
	texture: rl.Texture2D,
	source: rl.Rectangle,
	key: Sprite_Key,
	// Flipbook standees: the rigid paper card behind the print, the paper
	// margin around the print in its own pixels, and a left-facing mirror.
	flipbook, mirror: bool,
	card: rl.Texture2D,
	card_margin: f32,
}

// Rendering and picking share this world-space quad, including custom anchors.
tactical_billboard_geometry :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, feedback: bool = true,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) -> Tactical_Billboard {
	if character, ok := flipbook_character(key); ok && renderer.tactical.flipbook.loaded &&
	   !renderer.sprite_assets.sprites[int(key)].configured {
		return flipbook_billboard_geometry(renderer, character, key, position, feedback, entity)
	}
	effective_key := key
	clip_progress := f32(-1)
	if feedback && key == .Player {
		for offset in 0..<renderer_active_cue_count(renderer) {
			cue, found := renderer_active_cue_at(renderer, offset)
			if !found || !cue.started { continue }
			candidate := Sprite_Key.Player
			if cue.kind == .Card_Played { candidate = .Player_Cast }
			if cue.kind == .Damage && cue.event.target == game.PLAYER_ENTITY { candidate = .Player_Hit }
			if candidate != .Player && (renderer.sprite_assets.sprites[int(candidate)].configured || renderer.tactical.art.figures.id != 0) {
				effective_key = candidate
				clip_progress = comic_clip_progress(presentation_cue_progress(cue))
				break
			}
		}
	}
	asset := &renderer.sprite_assets.sprites[int(effective_key)]
	source := rl.Rectangle{0, 0, 48, 64}
	texture := renderer.tactical.fallback[min(int(key), 10)]
	size := rl.Vector2{0.65, 0.9}
	anchor := rl.Vector2{0.5, 1}
	if renderer.tactical.art.figures.id != 0 {
		texture = renderer.tactical.art.figures
		source = renderer.tactical.art.figure_sources[gothic_figure_index(effective_key)]
		height := f32(1.35)
		#partial switch effective_key {
		case .Chaser: height = 1.19
		case .Brute: height = 1.56
		case .Demolitionist: height = 1.65
		case .Player_Cast: height = 1.49
		}
		size = {height*source.width/max(f32(1), source.height), height}
		if key >= .Ice_Block && key <= .Bomb { size *= 0.7 }
	}
	if asset.configured {
		source, _ = sprite_asset_rectangles(asset, renderer.sprite_assets.elapsed, {}, 1)
		if clip_progress >= 0 { source, _ = sprite_clip_rectangles(asset, clip_progress, {}, 1) }
		texture = renderer.sprite_assets.textures[asset.texture_index].texture
		size = {asset.width/64, asset.height/64}
		anchor = {asset.anchor.x, asset.anchor.y}
	}
	pose := Tactical_Feedback_Pose{scale_y=1,tint=rl.WHITE}
	if feedback {pose=tactical_feedback_pose(renderer,key,position)}
	size.y *= pose.scale_y
	up := rl.Vector3{0, 1, 0}
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(up, renderer.tactical.camera.position-renderer.tactical.camera.target))
	base := rl.Vector3{position.x+0.5, 0.02+pose.lift, position.y+0.5}
	bl := base-right*(size.x*anchor.x)-up*(size.y*(1-anchor.y))
	quad := Tactical_Billboard{points = {bl+up*size.y+right*pose.lean, bl, bl+right*size.x, bl+right*size.x+up*size.y+right*pose.lean},
		texture = texture, source = source, key = effective_key}
	return comic_world_ground_clearance(renderer, quad)
}

tactical_billboard :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, opacity: f32,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) {
	quad := tactical_billboard_geometry(renderer, key, position, true, entity)
	pose := tactical_feedback_pose(renderer, key, position)
	draw_tactical_billboard_quad(renderer, quad, position, opacity, pose.tint)
}

draw_tactical_billboard_quad :: proc(renderer: ^Renderer, quad: Tactical_Billboard, position: view.Vec2, opacity: f32, tint: rl.Color = rl.WHITE) {
	if quad.texture.id == 0 { return }
	uv := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	if quad.mirror { uv = {{1, 0}, {1, 1}, {0, 1}, {0, 0}} }
	if quad.flipbook {
		if quad.card.id != 0 {
			// The card takes the scene's light tint but never the hit flash:
			// paper stays paper while the print reacts.
			points := flipbook_card_points(quad)
			rlgl.SetTexture(quad.card.id)
			rlgl.Begin(rlgl.QUADS)
			rlgl.Color4ub(255, 255, 255, u8(clamp(opacity, f32(0), f32(1))*255))
			for point, index in points {
				rlgl.TexCoord2f(uv[index].x, uv[index].y)
				rlgl.Vertex3f(point.x, point.y, point.z)
			}
			rlgl.End()
		}
	} else { draw_comic_cutout(renderer, quad, position, opacity) }
	rlgl.SetTexture(quad.texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(tint.r, tint.g, tint.b, u8(clamp(opacity, f32(0), f32(1))*255))
	for point, index in quad.points {
		rlgl.TexCoord2f((quad.source.x+uv[index].x*quad.source.width)/f32(quad.texture.width),
			(quad.source.y+uv[index].y*quad.source.height)/f32(quad.texture.height))
		rlgl.Vertex3f(point.x, point.y, point.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

tactical_billboard_hit :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, ray: rl.Ray,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) -> (distance: f32, hit: bool) {
	quad := tactical_billboard_geometry(renderer, key, position, true, entity)
	if quad.flipbook && quad.card.id != 0 { return flipbook_card_hit(renderer, quad, ray) }
	collision := rl.GetRayCollisionQuad(ray, quad.points[0], quad.points[1], quad.points[2], quad.points[3])
	if !collision.hit { return }
	asset := &renderer.sprite_assets.sprites[int(quad.key)]
	alpha: []u8
	width := int(quad.texture.width)
	if asset.configured { alpha = renderer.sprite_assets.textures[asset.texture_index].alpha }
	else if quad.texture.id == renderer.tactical.art.figures.id { alpha = renderer.tactical.art.figure_alpha }
	if len(alpha) > 0 {
		u := quad.points[3]-quad.points[0]
		v := quad.points[1]-quad.points[0]
		delta := collision.point-quad.points[0]
		fx := rl.Vector3DotProduct(delta, u)/rl.Vector3DotProduct(u, u)
		fy := rl.Vector3DotProduct(delta, v)/rl.Vector3DotProduct(v, v)
		x := int(quad.source.x+clamp(fx, f32(0), f32(0.9999))*quad.source.width)
		y := int(quad.source.y+clamp(fy, f32(0), f32(0.9999))*quad.source.height)
		index := y*width+x
		if index < 0 || index >= len(alpha) || alpha[index] <= 16 { return }
	}
	return collision.distance, true
}

tactical_cue_visible :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	snapshot := renderer.tactical.snapshot
	position := cue.event.to_position
	if target, ok := presentation_actor_in_view(snapshot, cue.event.target); ok {
		position = {int(math.round(target.position.x)), int(math.round(target.position.y))}
	} else if cue.event.target.kind == .Object {
		for object in snapshot.objects[:snapshot.object_count] {
			if object.entity == cue.event.target { position = {int(math.round(object.position.x)), int(math.round(object.position.y))}; break }
		}
	}
	if !tactical_render_visible(renderer, position) { return false }
	if cue.kind == .Spell_Launched || cue.kind == .Spell_Impact || cue.kind == .Loot {
		return tactical_render_visible(renderer, cue.event.from_position)
	}
	return true
}

update_tactical_body_hover :: proc(renderer: ^Renderer, mouse: view.Vec2) {
	v := &renderer.tactical
	if !v.scene_3d { return }
	ray := rl.GetScreenToWorldRayEx(to_raylib(mouse), v.camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
	closest := f32(1.0e20)
	for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || !tactical_render_visible(renderer, cell) { continue }
		if distance, hit := tactical_billboard_hit(renderer, sprite_key_for_enemy(actor.archetype), actor.position, ray, actor.entity); hit && distance < closest {
			closest = distance
			renderer.hovered_cell = cell
			renderer.has_hovered_cell = true
		}
	}
	for object in v.snapshot.objects[:v.snapshot.object_count] {
		cell := grid.Position{int(math.round(object.position.x)), int(math.round(object.position.y))}
		if !object.visible || !tactical_render_visible(renderer, cell) { continue }
		collision := rl.GetRayCollisionBox(ray, voxel_object_bounds(object.kind, object.position))
		if collision.hit && collision.distance < closest {
			closest = collision.distance
			renderer.hovered_cell = cell
			renderer.has_hovered_cell = true
		}
	}
}

draw_tactical_world :: proc(renderer: ^Renderer, room: ^game.Room, active_card: u32) {
	v := &renderer.tactical
	v.draw_frustum = tactical_draw_frustum(v.camera, renderer.canvas_width, renderer.canvas_height)
	snapshot := v.snapshot
	lights: [4]rl.Vector4
	surface := begin_tactical_surface(renderer)
	if surface { rl.BeginMode2D({zoom = 2}) }
	draw_tactical_backdrop(renderer)
	if surface { rl.EndMode2D() }
	if v.scene_3d {
		lights = prepare_diorama_lights(renderer, room)
		rl.BeginMode3D(v.camera)
		draw_voxel_fog(renderer, room)
		begin_tactical_lighting(renderer, accents = lights)
	}
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			cell := grid.Position{x, y}
			if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
			tile, _ := level.tile_at(room.level_data, cell)
			if v.scene_3d {
				draw_tactical_tile(renderer, room, tile, cell)
			} else { draw_tile(renderer, tile, cell) }
		}
	}
	for obstacle in room.obstacles {
		if !tactical_cell_on_screen(renderer, obstacle.position) || !tactical_render_visible(renderer, obstacle.position) { continue }
		if v.scene_3d { draw_voxel_cover(renderer, obstacle.position) }
		else { draw_diamond(inset_vertices(tile_vertices(renderer, obstacle.position), 0.7), rl.GRAY, rl.LIGHTGRAY) }
	}
	for trap in snapshot.traps[:snapshot.trap_count] {
		if !trap.armed || !tactical_cell_on_screen(renderer, trap.position) || !tactical_render_visible(renderer, trap.position) { continue }
		if v.scene_3d { draw_voxel_trap(renderer, trap) }
		else { draw_room_trap(renderer, trap) }
	}
	for object in snapshot.objects[:snapshot.object_count] {
		cell := grid.Position{int(math.round(object.position.x)), int(math.round(object.position.y))}
		if !object.visible || !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
		if v.scene_3d { draw_voxel_object(renderer, object) }
		else { draw_grid_object_body(renderer, object.kind, tactical_project(renderer, {object.position.x+0.5, object.position.y+0.5}), object.health, object.max_health, object.opacity) }
	}
	for item in snapshot.loot[:snapshot.loot_count] {
		if !item.visible || !tactical_cell_on_screen(renderer, item.position) || !tactical_render_visible(renderer, item.position) { continue }
		if v.scene_3d { draw_tactical_loot(renderer, item) }
		else { rl.DrawCircleV(to_raylib(cell_center(renderer, item.position)), 5, rl.GOLD) }
	}
	for &actor in snapshot.enemies[:snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || !tactical_render_visible(renderer, cell) { continue }
		if !v.scene_3d { draw_enemy_body(renderer, {archetype = actor.archetype, health = actor.health}, tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5}), actor.opacity) }
	}
	if snapshot.player.visible {
		if !v.scene_3d { draw_player_body(renderer, tactical_project(renderer, {snapshot.player.position.x+0.5, snapshot.player.position.y+0.5}), snapshot.player.opacity) }
	}
	if v.scene_3d {
		rl.EndShaderMode()
		draw_tactical_ground_shadows(renderer, room)
		draw_diorama_accents(renderer, room)
		draw_tactical_clear_markers(renderer, room)
		draw_voxel_threats(renderer, room)
		draw_m8_device_network(renderer, room)
		rl.EndMode3D()
	}
	if tactical_telegraphs_are_visible(renderer, room) {
		if surface { rl.BeginMode2D({zoom = 2}) }
		if !renderer_blocks_player_input(renderer) { draw_card_target_range(renderer, room, active_card) }
		if !v.scene_3d { for &enemy in room.enemies {
			for cell in enemy.intent.threatened_cells[:enemy.intent.threatened_cell_count] {
				if tactical_render_visible(renderer, cell) { draw_card_range_cell(renderer, cell, {232, 95, 83, 45}, {232, 95, 83, 190}) }
			}
		} }
		if surface { rl.EndMode2D() }
	}
	// Ground feedback precedes the sorted walls/sprites. Opaque terrain keeps
	// its depth while the translucent wall bodies reveal visible actors.
	if v.scene_3d {
		rl.BeginMode3D(v.camera)
		draw_tactical_actor_bases(renderer)
		draw_tactical_feedback(renderer, .Ground)
		draw_tactical_billboards(renderer, room, lights)
		draw_tactical_feedback(renderer, .Accent)
		rl.EndMode3D()
	}
	end_tactical_surface(renderer, surface)
	draw_tactical_annotations(renderer, room)
	// Filter each member of simultaneous impacts, not only the first event.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if found && cue.started && tactical_cue_visible(renderer, cue) {
			if !draw_tactical_feedback_overlay(renderer, cue) { draw_presentation_cue(renderer, cue) }
		}
	}
}

