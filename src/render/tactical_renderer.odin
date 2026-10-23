package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import campaign "../campaign"
import expedition "../expedition"
import grid "../engine/grid"
import level "../level"
import view "../engine/view"

EXPEDITION_BENCHMARK :: #config(EXPEDITION_BENCHMARK,false)

// CPU wall time spent preparing/submitting each section; driver stalls may
// be included. These are deliberately not labelled as GPU execution times.
Expedition_Draw_Timing :: struct {
	prepare_ms,cache_lights_ms,reflection_ms,floor_ms,architecture_resolve_ms:f64,
	objects_ms,ground_ms,target_details_ms,paper_ms,surface_labels_ms:f64,
}

@(private)
expedition_benchmark_elapsed :: proc(stamp:^f64)->f64 {
	when EXPEDITION_BENCHMARK {
		now:=rl.GetTime();elapsed:=(now-stamp^)*1000;stamp^=now;return elapsed
	} else {return 0}
}

Tactical_View :: struct {
	art: Gothic_Art,
	perspective, no_fog: bool,
	refocus_enabled: bool,
	camera: rl.Camera3D,
	draw_frustum: Tactical_Draw_Frustum,
	draw_timing: Expedition_Draw_Timing,
	zoom: f32,
	visible: [game.MAX_TACTICAL_VISION*game.MAX_TACTICAL_VISION]grid.Position,
	world_orbit, hologram_orbit: Tactical_Orbit,
	expedition_placement: bool,
	expedition: bool,
	expedition_biome: u8,
	expedition_mounted: bool,
	expedition_clock: f32,
	expedition_material: ^Expedition_Material,
	expedition_floor: ^Expedition_Floor,
	expedition_direction: game.Move_Direction,
	expedition_follow: rl.Vector3,
	expedition_follow_ready: bool,
	// Exploration's free walker (expedition_walker.odin): set by the scene
	// each frame; encounters hand the robot back to its cells.
	expedition_free, expedition_was_free, expedition_player_drawn: bool,
	expedition_free_position, expedition_free_velocity: view.Vec2,
	expedition_player_shown, expedition_player_offset: view.Vec2,
	expedition_stride, expedition_dt: f32,
	// Sleeping patrols glide between the cells they step to.
	expedition_patrols: Expedition_Patrol_Glide,
	// The sites whose floor plans reach this frame's drawn region.
	expedition_sites: Expedition_Near_Sites,
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
	flipbook: gfx.Flipbook_Assets,
	flipbook_state: ^Flipbook_State,
	// Living cards (living_card.odin): on wherever the board is 3D.
	living: bool,
	living_assets: gfx.Living_Assets,
	living_state: ^Living_State,
	// The paper props of the board's blows and the blows showing (attack_fx.odin).
	attack_props: gfx.Attack_Props,
	attack_fx: Attack_Fx_State,
	// The inspector of a living board keeps the enemy last hovered, and the
	// mouse then.
	inspected: u32,
	inspected_mouse: rl.Vector2,
	pointer_window: rl.Vector2,
	// The mechanics lab is running: its banner sits over the board and its
	// trial extras show (the enemies' action rings); opened from the menu, the
	// banner names F10 too (mechanics_lab_hud.odin).
	mechanics_lab, mechanics_lab_menu: bool,
	// The pause menu: the button under the mouse, and whether there is a main
	// menu to go back to.
	pause_hovered: Pause_Choice,
	pause_menu: bool,
	// The mechanics lab's enemy intent displays on trial (intent_display.odin).
	intent_display: Intent_Display,
	intent_traces: [game.MAX_ENEMIES_PER_ROOM*2]Intent_Trace,
	// The mechanics lab's sounds waiting to play (lab_sounds.odin).
	lab_sounds: ^Lab_Sounds,
	kit: Diorama_Kit,
	pilgrim: []Diorama_Vertex,
	// MOVIMENTO OMBRA: the player's pool and the world held still (shadow_step.odin).
	shadow: Shadow_View,
	// The pools and fires on the floor (ground_fx.odin).
	ground: ^Ground_Fx,
	// FERETRO: the player holds Ctrl with arrows to loose; the board marks the
	// foes they reach (player_charges.odin). The scene sets it every frame.
	arrow_aim: bool,
	// LAZZO: the rope, the swung card and the ring on the floor (lasso.odin).
	lasso: Lasso_View,
	// CANNA DA PESCA: the rod, its line, the bobber and the catch (fishing.odin).
	fishing: Fishing_View,
	// PINBALL: the steel ball, its contacts and its burst (pinball.odin).
	pinball: Pinball_View,
	// BOMB MARLEY: the ball, the beams, the bomb and the figure (marley.odin).
	marley: Marley_View,
	// CANNONE, BUCO NERO and DINOSAURO: the prints, the climb and the walk (arsenal.odin).
	arsenal: Arsenal_View,
	// INONDAZIONE: the way of its wave while the card is held over the board.
	flood_aim: Flood_Aim,
	// FIRST PERSON SHOOTER: the camera in the player's eyes, the AK and its
	// shots (first_person.odin).
	first_person: First_Person_View,
	// PROVA MECCANICHE's overlapping hand: how much of each card shows
	// (tactical_hand.odin).
	hand_reveal: Tactical_Hand_Reveal,
	// The last pointer seen by the view, for HUD hover states only.
	pointer: view.Vec2,
	pointer_inside: bool,
	// MOSTRA EFFETTO's board (effect_stage.odin): a film, not a game. Its HUD
	// keeps its plates and leaves the run's commands out (COMANDI), and its
	// inspectors follow the film alone: no enemy inspector (it reads the real
	// mouse) and no MOSTRA EFFETTO of its own; in the lab its labels keep clear
	// of no banner (it draws none). Its camera aims nearer the player
	// (TACTICAL_SHOWCASE_AIM).
	showcase: bool,
}

create_tactical_assets :: proc(renderer: ^Renderer, parent: rl.RenderTexture2D = {}) {
	renderer.tactical.snapshot = new(Room_Presentation)
	renderer.tactical.labels = new(Tactical_Label_Layout)
	renderer.tactical.block_mesh = build_dice_bevel_mesh()
	create_tactical_lighting(renderer)
	create_comic_outline(renderer)
	create_gothic_art(&renderer.tactical.art)
	gfx.create_flipbook_assets(&renderer.tactical.flipbook)
	gfx.create_attack_props(&renderer.tactical.attack_props)
	load_diorama_kit(&renderer.tactical.kit, DIORAMA_KIT_BYTES)
	load_pilgrim_model(&renderer.tactical.pilgrim)
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

// A board's own state goes with its assets here; a borrowed renderer frees the
// same own state and none of the assets (destroy_borrowed_renderer, and
// BORROWED_RENDERER_OWN_HANDLES for a view's lazily made textures): a new asset
// or a new piece of a board's state belongs in both.
destroy_tactical_assets :: proc(renderer: ^Renderer) {
	destroy_renderer_world_playback(renderer)
	destroy_tactical_translucents(renderer)
	destroy_tactical_surface(renderer)
	destroy_expedition_material(renderer)
	destroy_expedition_floor(renderer)
	destroy_gothic_art(&renderer.tactical.art)
	gfx.destroy_flipbook_assets(&renderer.tactical.flipbook)
	gfx.destroy_attack_props(&renderer.tactical.attack_props)
	forget_attack_fx(renderer)
	destroy_diorama_kit(&renderer.tactical.kit)
	delete(renderer.tactical.pilgrim)
	renderer.tactical.pilgrim = nil
	if renderer.tactical.flipbook_state != nil { free(renderer.tactical.flipbook_state); renderer.tactical.flipbook_state = nil }
	destroy_living_cards(renderer)
	destroy_lab_sounds(renderer)
	destroy_ground_fx(renderer)
	destroy_lasso_view(renderer)
	destroy_fishing_view(renderer)
	destroy_pinball_view(renderer)
	destroy_marley_view(renderer)
	destroy_arsenal_view(renderer)
	destroy_first_person_view(renderer)
	if renderer.tactical.outline_shader.id != 0 { rl.UnloadShader(renderer.tactical.outline_shader); renderer.tactical.outline_shader = {} }
	if renderer.tactical.labels != nil { free(renderer.tactical.labels); renderer.tactical.labels = nil }
	if renderer.tactical.light_shader.id != 0 { rl.UnloadShader(renderer.tactical.light_shader); renderer.tactical.light_shader = {} }
	if renderer.tactical.snapshot != nil { free(renderer.tactical.snapshot); renderer.tactical.snapshot = nil }
	for &texture in renderer.tactical.fallback {
		if texture.id != 0 { rl.UnloadTexture(texture); texture = {} }
	}
}

tactical_render_visible :: proc(renderer: ^Renderer, position: grid.Position) -> bool {
	if renderer.tactical.no_fog { return true }
	for cell in renderer.tactical.visible[:renderer.tactical.visible_count] {
		if cell == position { return true }
	}
	return false
}

@(private)
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

// How far in front of the player the board's camera aims, in cells (scaled
// with its footprint): the game's leaves the bottom to a full hand; MOSTRA
// EFFETTO's film (Tactical_View.showcase) aims nearer him.
TACTICAL_HAND_AIM :: f32(1.10)
TACTICAL_SHOWCASE_AIM :: f32(0.30)

Tactical_View_Input :: struct {
	orbit_pressed, orbit_down: bool,
	wheel: f32,
	window_mouse: rl.Vector2,
}

update_tactical_view :: proc(renderer: ^Renderer, room: ^game.Room, mouse: view.Vec2, inside: bool, refresh_only: bool = false,
	input: Tactical_View_Input = {}) {
	v := &renderer.tactical
	v.expedition = room.player.tactical.config.expedition
	v.expedition_biome = room.player.tactical.config.expedition_biome
	if !refresh_only { v.pointer_window = input.window_mouse }
	tactical_hud_pointer(renderer, mouse, inside)
	v.snapshot^ = renderer_presentation_snapshot(renderer, room)
	update_expedition_walker_view(renderer, refresh_only)
	update_tactical_hand_reveal(renderer, &v.snapshot.deck)
	// Before the vision and the camera: in the shadow they follow the pool;
	// the Lazzo's foe flies where the room's rope swings it, the Pinball's
	// ball rolls where the room says it is.
	update_tactical_shadow(renderer, room)
	update_tactical_lasso(renderer, room)
	update_tactical_pinball(renderer, room)
	update_tactical_marley(renderer, room)
	update_tactical_arsenal(renderer, room)
	update_tactical_fishing(renderer)
	update_tactical_first_person(renderer, room)
	v.no_fog = room.player.tactical.config.vision_size == 0 || tactical_room_is_clear(v.snapshot.phase)
	if !tactical_room_is_clear(v.snapshot.phase) { v.clear_light = 0 }
	// Behind the player's eyes his hand is put away: no refocus.
	v.refocus_enabled = game.tactical_control_allowed(room, .Board_Action)
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
	lasso_extend_vision(renderer, room)
	if !v.world_orbit.initialized { reset_tactical_orbit(&v.world_orbit) }
	if room.player.tactical.config.expedition {
		reset_tactical_orbit(&v.world_orbit)
		v.world_orbit.distance = 25
	}
	if inside && !refresh_only && !room.player.tactical.config.expedition {
		update_tactical_orbit_pointer(&v.world_orbit, mouse, point_in_rectangle(mouse, tactical_world_bounds(renderer)),
			input.orbit_pressed, input.orbit_down, input.wheel)
	}
	// Aim slightly in front of the player to reserve the bottom for a full hand
	// (while the Lazzo spins a wide ring: farther back and nearer him, so all
	// of it shows between the HUD and the hand). MOSTRA EFFETTO's film holds a
	// card or a few: it aims nearer him, so that what stands beyond him in its
	// room shows under the HUD's plates.
	pull := lasso_camera_pull(renderer)
	forward := rl.Vector3{math.cos(v.world_orbit.yaw), 0, math.sin(v.world_orbit.yaw)}
	footprint_scale := 1.1+f32(max(0, size-5))*0.065
	aim := TACTICAL_SHOWCASE_AIM if v.showcase else TACTICAL_HAND_AIM
	target := rl.Vector3{p.x+0.5, 0, p.y+0.5}+forward*(aim*footprint_scale*(1-LASSO_CAMERA_AIM*pull))
	if room.player.tactical.config.expedition {
		combat_orbit := v.world_orbit
		combat_orbit.distance *= footprint_scale*(1+LASSO_CAMERA_BACK*pull)
		target = expedition_combat_camera_target(renderer, combat_orbit, target)
		if !v.expedition_follow_ready || rl.Vector3Distance(v.expedition_follow, target) > 8 {
			v.expedition_follow = target
			v.expedition_follow_ready = true
		} else if !refresh_only {
			// Frame-rate independent: a glide reads the same at any refresh.
			v.expedition_follow = v.expedition_follow+(target-v.expedition_follow)*(1-math.exp(-10*expedition_frame_dt(renderer)))
		}
		target = v.expedition_follow
	}
	framed_orbit := v.world_orbit
	framed_orbit.distance *= footprint_scale*(1+LASSO_CAMERA_BACK*pull)
	v.zoom = framed_orbit.distance*0.65
	v.camera = tactical_orbit_camera(framed_orbit, target, v.perspective)
	// FIRST PERSON SHOOTER: as far into the player's eyes as the dive has gone.
	frame_first_person_camera(renderer, room)
	v.draw_frustum = tactical_draw_frustum(v.camera, renderer.canvas_width, renderer.canvas_height)
	renderer.overlay_scale = 1.1/footprint_scale*12.5/v.world_orbit.distance/(1+LASSO_CAMERA_BACK*pull)
	if refresh_only { return }
	renderer.has_hovered_cell = false
	if !inside || !point_in_rectangle(mouse, tactical_world_bounds(renderer)) || renderer_blocks_player_input(renderer) { return }
	ray := rl.GetScreenToWorldRayEx(to_raylib(mouse), v.camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
	if abs(ray.direction.y) < 0.0001 { return }
	t := -ray.position.y/ray.direction.y
	if t <= 0 { return }
	point := ray.position+ray.direction*t
	cell := grid.Position{int(math.floor(point.x)), int(math.floor(point.z))}

	if grid.contains(&room.level_data.tiles, cell) && tactical_render_visible(renderer, cell) {
		renderer.has_hovered_cell = true
		renderer.hovered_cell = cell
	}
	update_tactical_body_hover(renderer, mouse)
}

tactical_project :: proc(renderer: ^Renderer, position: view.Vec2, height: f32 = 0) -> view.Vec2 {
	camera := renderer.tactical.camera
	// Behind the player's eyes a point behind the eye is off the canvas (the
	// projection would mirror it in front).
	if renderer.tactical.first_person.amount > 0 {
		forward := rl.Vector3Normalize(camera.target-camera.position)
		if rl.Vector3DotProduct(rl.Vector3{position.x, height, position.y}-camera.position, forward) < 0.05 { return {-100000, -100000} }
	}
	p := rl.GetWorldToScreenEx({position.x, height, position.y}, camera,
		c.int(renderer.canvas_width), c.int(renderer.canvas_height))
	return {p.x, p.y}
}

Tactical_Billboard :: struct {
	points: [4]rl.Vector3,
	texture: rl.Texture2D,
	source: rl.Rectangle,
	key: Sprite_Key,
	// Flipbook standees: the paper fields behind the print, the paper margin
	// around the print in its own pixels, a left-facing mirror, and the two
	// drawings (uv rects in the field atlas) the cut is morphing between.
	flipbook, mirror: bool,
	card: rl.Texture2D,
	card_margin: f32,
	card_a, card_b: rl.Rectangle,
	card_morph: f32,
	// A living card's paper keeps its own quad: the print may narrow or
	// mirror inside it while the card stays as it is.
	living: bool,
	card_points: [4]rl.Vector3,
}

// Rendering and picking share this world-space quad, including custom anchors.
@(private)
tactical_billboard_geometry :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, feedback: bool = true,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) -> Tactical_Billboard {
	if character, ok := flipbook_character(key); ok && renderer.tactical.flipbook.loaded &&
	   !renderer.sprite_assets.sprites[int(key)].configured {
		if renderer.tactical.living && renderer.tactical.living_assets.loaded {
			return living_billboard_geometry(renderer, character, key, position, feedback, entity)
		}
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

@(private)
tactical_billboard :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, opacity: f32,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) {
	if renderer.tactical.expedition && entity == game.PLAYER_ENTITY && key == .Player {
		draw_expedition_robot(renderer, position, opacity)
		return
	}
	quad := tactical_billboard_geometry(renderer, key, position, true, entity)
	pose := tactical_feedback_pose(renderer, key, position)
	// Sunk in its shadow the player's card is dark, paper and print alike.
	shade, seen := tactical_shadow_tint(renderer, entity)
	if shade != rl.WHITE { pose.tint = shade }
	if renderer.tactical.expedition && key >= .Chaser && key <= .Demolitionist && pose.tint == rl.WHITE {
		pose.tint = expedition_enemy_tint(campaign.Biome(renderer.tactical.expedition_biome))
	}
	draw_tactical_billboard_quad(renderer, quad, position, opacity*seen, pose.tint, shade)
}

@(private)
draw_tactical_billboard_quad :: proc(renderer: ^Renderer, quad: Tactical_Billboard, position: view.Vec2, opacity: f32,
	tint: rl.Color = rl.WHITE, paper: rl.Color = rl.WHITE) {
	if quad.texture.id == 0 { return }
	uv := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	if quad.mirror { uv = {{1, 0}, {1, 1}, {0, 1}, {0, 0}} }
	if quad.flipbook {
		// Paper stays paper while the print reacts: no hit flash on the card.
		if quad.card.id != 0 { draw_flipbook_card(renderer, quad, uv, opacity, paper) }
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

@(private)
tactical_billboard_hit :: proc(renderer: ^Renderer, key: Sprite_Key, position: view.Vec2, ray: rl.Ray,
	entity: game.Entity_Ref = game.SYSTEM_ENTITY) -> (distance: f32, hit: bool) {
	quad := tactical_billboard_geometry(renderer, key, position, true, entity)
	if quad.living && quad.card.id != 0 { return living_card_hit(renderer, quad, ray) }
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

@(private)
tactical_cue_visible :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) -> bool {
	snapshot := renderer.tactical.snapshot
	position := cue.event.to_position
	if target, ok := tactical_cue_actor_position(renderer, cue.event.target); ok {
		position = {int(math.round(target.x)), int(math.round(target.y))}
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

@(private)
update_tactical_body_hover :: proc(renderer: ^Renderer, mouse: view.Vec2) {
	v := &renderer.tactical
	ray := rl.GetScreenToWorldRayEx(to_raylib(mouse), v.camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
	closest := f32(1.0e20)
	for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		// The Pinball's ball is no card under the mouse (pinball.odin).
		if !actor.visible || !tactical_render_visible(renderer, cell) || tactical_pinball_holds(renderer, actor.entity) { continue }
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

draw_tactical_world :: proc(renderer: ^Renderer, room: ^game.Room, active_card: u32, expedition_world: ^expedition.World = nil) {
	v := &renderer.tactical
	when EXPEDITION_BENCHMARK {v.draw_timing={};stamp:=rl.GetTime()}
	v.draw_frustum = tactical_draw_frustum(v.camera, renderer.canvas_width, renderer.canvas_height)
	snapshot := v.snapshot
	preview: Card_Range_Preview
	prepare_card_range_preview(renderer, room, active_card, &preview)
	update_ground_fx(renderer, room)
	lights: [4]rl.Vector4
	// The surface draws in logical units at its own resolution.
	surface := begin_tactical_surface(renderer)
	min_x, min_y := 0, 0
	max_x, max_y := room.level_data.tiles.width, room.level_data.tiles.height
	when EXPEDITION_BENCHMARK {v.draw_timing.prepare_ms=expedition_benchmark_elapsed(&stamp)}
	if expedition_world != nil {
		p := room.player.position
		min_x, min_y = max(0, (p.x/16-2)*16), max(0, (p.y/16-2)*16)
		max_x, max_y = min(max_x, (p.x/16+3)*16), min(max_y, (p.y/16+3)*16)
		expedition_gather_sites(renderer, expedition_world, {min_x, min_y}, {max_x, max_y})
		prepare_expedition_material(renderer,room,expedition_world)
		collect_expedition_edges(renderer,room,expedition_world)
		prepare_expedition_lights(renderer,room,expedition_world)
		when EXPEDITION_BENCHMARK {v.draw_timing.cache_lights_ms=expedition_benchmark_elapsed(&stamp)}
		prepare_expedition_reflection(renderer,room,expedition_world)
		when EXPEDITION_BENCHMARK {v.draw_timing.reflection_ms=expedition_benchmark_elapsed(&stamp)}
	}
	draw_tactical_backdrop(renderer)
	if expedition_world == nil { lights = prepare_diorama_lights(renderer, room) }
	rl.BeginMode3D(v.camera)
	if expedition_world == nil {draw_voxel_fog(renderer, room)}
	floor_drawn:=false
	if expedition_world!=nil {floor_drawn=draw_expedition_floor(renderer,room,expedition_world)}
	if !floor_drawn {
		if expedition_world == nil { begin_tactical_lighting(renderer, accents = lights) }
		else {begin_expedition_material(renderer,expedition_world,floor=true)}
		for y in min_y..<max_y {
		for x in min_x..<max_x {
			cell := grid.Position{x, y}
			if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
			tile, _ := level.tile_at(room.level_data, cell)
			if expedition_world != nil { draw_expedition_tile(renderer, room, expedition_world, cell, &preview) }
			else { draw_tactical_tile(renderer, room, tile, cell, &preview) }
		}
	}
		if expedition_world!=nil {rl.EndShaderMode()}
	}
	when EXPEDITION_BENCHMARK {v.draw_timing.floor_ms=expedition_benchmark_elapsed(&stamp)}
	if expedition_world != nil {
		// Binds its own ink and reveal programs, layer by layer.
		draw_expedition_architecture(renderer,room,expedition_world)
		rl.EndMode3D()
		resolve_expedition_world(renderer)
		rl.BeginMode3D(v.camera)
		// Devices, cover and loot placed by cards keep the board's resin light.
		begin_tactical_lighting(renderer)
	}
	when EXPEDITION_BENCHMARK {v.draw_timing.architecture_resolve_ms=expedition_benchmark_elapsed(&stamp)}
	for obstacle in room.obstacles {
		if !tactical_cell_on_screen(renderer, obstacle.position) || !tactical_render_visible(renderer, obstacle.position) { continue }
		draw_voxel_cover(renderer, obstacle.position)
	}

	for trap in snapshot.traps[:snapshot.trap_count] {
		if expedition_world != nil && expedition_world.biome == .Vietnam && expedition.distance(room.player.position, trap.position) > 2 { continue }
		if !trap.armed || !tactical_cell_on_screen(renderer, trap.position) || !tactical_render_visible(renderer, trap.position) { continue }
		draw_voxel_trap(renderer, trap)
	}
	for object in snapshot.objects[:snapshot.object_count] {
		cell := grid.Position{int(math.round(object.position.x)), int(math.round(object.position.y))}
		if !object.visible || !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
		draw_voxel_object(renderer, object)
	}
	for item in snapshot.loot[:snapshot.loot_count] {
		if !item.visible || !tactical_cell_on_screen(renderer, item.position) || !tactical_render_visible(renderer, item.position) { continue }
		draw_tactical_loot(renderer, item)
	}
	rl.EndShaderMode()
	when EXPEDITION_BENCHMARK {v.draw_timing.objects_ms=expedition_benchmark_elapsed(&stamp)}
	draw_ground_decal(renderer, room)
	draw_fishing_ripples(renderer)
	draw_lasso_ring(renderer, room)
	// Static architecture contact shading is cached in the floor map; paper
	// only needs a small feathered footprint for each visible actor.
	if expedition_world == nil { draw_tactical_ground_shadows(renderer, room) }
	else {draw_expedition_contact_shadows(renderer,room,expedition_world)}
	if expedition_world == nil { draw_diorama_accents(renderer, room) }
	draw_tactical_clear_markers(renderer, room)
	draw_card_range_light(renderer, room, &preview)
	draw_voxel_threats(renderer, room)
	draw_intent_ground(renderer, room)
	draw_marley_floor(renderer, room)
	draw_arsenal_floor(renderer, room)
	draw_m8_device_network(renderer, room)
	draw_memory_device_ranges(renderer, room, active_card)
	rl.EndMode3D()
	when EXPEDITION_BENCHMARK {v.draw_timing.ground_ms=expedition_benchmark_elapsed(&stamp)}

	if tactical_telegraphs_are_visible(renderer, room) && !renderer_blocks_player_input(renderer) {
		draw_card_target_details(renderer, room, &preview)
		draw_fishing_target_range(renderer, room, active_card)
		draw_arrow_aim(renderer, room)
	}
	when EXPEDITION_BENCHMARK {v.draw_timing.target_details_ms=expedition_benchmark_elapsed(&stamp)}
	// Ground feedback precedes the sorted walls/sprites. Opaque terrain keeps
	// its depth while the translucent wall bodies reveal visible actors.
	rl.BeginMode3D(v.camera)
	if expedition_world != nil { draw_expedition_props(renderer, room, expedition_world) }
	draw_tactical_actor_bases(renderer)
	draw_tactical_feedback(renderer, .Ground)
	draw_tactical_billboards(renderer, room, lights)
	draw_marley_sky(renderer, room)
	draw_flood_wave(renderer, room)
	draw_arsenal_sky(renderer, room)
	draw_tactical_feedback(renderer, .Accent)
	rl.EndMode3D()
	when EXPEDITION_BENCHMARK {v.draw_timing.paper_ms=expedition_benchmark_elapsed(&stamp)}

	end_tactical_surface(renderer, surface)
	// The world stands still: without the resolve shader's grade, a cold veil
	// over the whole canvas, as the board is drawn (the HUD and the hand come
	// after it, clear).
	if !surface && v.shadow.frozen > 0 {
		rl.DrawRectangleRec({0, 0, renderer.canvas_width, renderer.canvas_height}, color_with_opacity({8, 12, 28, 255}, 0.4*v.shadow.frozen))
	}
	draw_tactical_annotations(renderer, room)
	if expedition_world != nil { draw_expedition_labels(renderer, room, expedition_world) }
	// Keep the Pinball's targeting warning above enemy health tags.
	draw_pinball_heavy_labels(renderer, room, active_card)
	draw_tactical_shadow_overlay(renderer)
	draw_lasso_release_badge(renderer)
	// Filter each member of simultaneous impacts, not only the first event.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if found && cue.started && tactical_cue_visible(renderer, cue) {
			if !draw_tactical_feedback_overlay(renderer, cue) { draw_presentation_cue(renderer, cue) }
		}
	}
	// The mechanics lab's paper tokens outlive their cues.
	draw_living_tokens(renderer)
	draw_fate_tokens(renderer)
	when EXPEDITION_BENCHMARK {v.draw_timing.surface_labels_ms=expedition_benchmark_elapsed(&stamp)}
}
