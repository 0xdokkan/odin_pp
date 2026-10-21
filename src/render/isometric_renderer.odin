package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"
import tween "../engine/tween"

CANVAS_BACKGROUND :: rl.Color{24, 27, 31, 255}
LETTERBOX_COLOR   :: rl.Color{10, 12, 15, 255}

MAX_CARD_KEYWORD_TAGS        :: 3

Renderer :: struct {
	tactical: Tactical_View,
	// Screen-space feedback follows the 3D camera's distance.
	overlay_scale: f32,
	canvas_width:     f32,
	canvas_height:    f32,
	hovered_cell:     grid.Position,
	has_hovered_cell: bool,
	timeline: Presentation_Timeline,
	world_playback: ^World_Playback,
	playback_speed: f32,
	frame_simulation_dt: f32,
	frame_clock_valid: bool,
	frame_had_cinematic: bool,
	sprite_assets: Sprite_Assets,
	// Every command's presentation gets the next number (Presentation_Cue.batch).
	cue_batches: u32,
	// Every kind of game event the board was handed to show, since its owner
	// last cleared this (MOSTRA EFFETTO's takes: main/card_demo.odin).
	shown_events: bit_set[game.Game_Event_Kind],
}

Tile_Vertices :: struct {
	top, right, bottom, left: view.Vec2,
}

create :: proc(canvas_width, canvas_height: int) -> Renderer {
	return {canvas_width = f32(canvas_width), canvas_height = f32(canvas_height), overlay_scale = 1}
}

hand_card_bounds :: proc(renderer: ^Renderer, card_index, card_count: int) -> rl.Rectangle {
	if renderer == nil || card_count <= 0 || card_count > game.MAX_HAND_CAPACITY || card_index < 0 || card_index >= card_count { return {} }
	return tactical_hand_card_bounds(renderer, card_index, card_count)
}

hand_raised_card_bounds :: proc(renderer: ^Renderer, card_index, card_count: int) -> rl.Rectangle {
	if renderer == nil { return {} }
	// Picking spans the resting card and its lifted pose, keeping hover stable.
	resting := tactical_hand_card_bounds(renderer, card_index, card_count)
	raised := tactical_hand_raised_card_bounds(renderer, card_index, card_count)
	return {resting.x, raised.y, resting.width, resting.y+resting.height-raised.y}
}

point_in_rectangle :: proc(point: view.Vec2, bounds: rl.Rectangle) -> bool {
	return point.x >= bounds.x && point.x <= bounds.x+bounds.width &&
	       point.y >= bounds.y && point.y <= bounds.y+bounds.height
}

@(private)
refocus_button_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	if renderer == nil { return {} }
	return tactical_refocus_bounds(renderer)
}

refocus_button_at_point :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	return renderer != nil && point_in_rectangle(point, refocus_button_bounds(renderer))
}

@(private)
refocus_button_is_enabled :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && !renderer_blocks_player_input(renderer) && renderer.tactical.refocus_enabled
}

card_drop_area_contains :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	return renderer != nil && point_in_rectangle(point, tactical_world_bounds(renderer))
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

Card_Keyword_Tag :: enum {
	Retain,
	Ethereal,
	Temporary,
}

@(private)
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

@(private)
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

renderer_hand_deck :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
) -> (^game.Deck_State, game.Room_Phase) {
	assert(renderer != nil && room != nil && room.player != nil)
	if renderer.tactical.snapshot != nil {
		return &renderer.tactical.snapshot.deck, renderer.tactical.snapshot.phase
	}
	if renderer_blocks_player_input(renderer) && renderer.timeline.view.valid {
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
	draw_tactical_hand(renderer, room, hovered_card_id, selected_card_id, dragged_card_id, mouse_position)
}

clear_event_animations :: proc(renderer: ^Renderer) {
	if renderer != nil {
		clear_event_timeline(&renderer.timeline)
		clear_renderer_world_playback(renderer)
		forget_flipbook_actors(renderer)
	}
}

renderer_timeline_is_busy :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && (event_timeline_is_busy(&renderer.timeline) || renderer_world_is_busy(renderer))
}

begin_renderer_event_timeline :: proc(
	renderer: ^Renderer,
	before: Room_Presentation,
	events: ^game.Event_Log,
	after: ^Room_Presentation = nil,
) -> bool {
	if renderer == nil || renderer_blocks_player_input(renderer) {
		return false
	}
	started := begin_event_timeline(&renderer.timeline, before, events, after)
	if started && events != nil {
		for event in events.events[:clamp(events.count, 0, len(events.events))] { renderer.shown_events += {event.kind} }
	}
	renderer.cue_batches += 1
	for offset in 0..<renderer.timeline.count {
		renderer.timeline.cues[(renderer.timeline.head+offset)%MAX_PRESENTATION_CUES].batch = renderer.cue_batches
	}
	return started
}

renderer_playback_speed :: proc(renderer: ^Renderer) -> f32 {
	if renderer == nil || renderer.playback_speed == 0 {
		return 1
	}
	return renderer.playback_speed
}

set_renderer_playback_speed :: proc(renderer: ^Renderer, speed: f32) -> bool {
	// Questo confronto rifiuta anche NaN e infinito.
	if renderer == nil || !(speed >= 0.25 && speed <= 4) {
		return false
	}
	renderer.playback_speed = speed
	return true
}

update_renderer_event_timeline :: proc(renderer: ^Renderer, dt: f32) -> bool {
	if renderer == nil {
		return false
	}
	was_busy := renderer_timeline_is_busy(renderer)
	step := dt*renderer_playback_speed(renderer)
	update_event_timeline(&renderer.timeline, step)
	// The world's cues hold while the player is in his shadow.
	if !renderer.tactical.shadow.active { update_renderer_world_playback(renderer, step) }
	return was_busy && !renderer_timeline_is_busy(renderer)
}

@(private)
to_raylib :: proc(value: view.Vec2) -> rl.Vector2 {
	return rl.Vector2{value.x, value.y}
}

@(private)
color_with_opacity :: proc(color: rl.Color, opacity: f32) -> rl.Color {
	result := color
	result.a = u8(f32(color.a)*clamp(opacity, f32(0), f32(1)))
	return result
}

@(private = "file")
tile_vertices :: proc(renderer: ^Renderer, position: grid.Position) -> Tile_Vertices {
	x, y := f32(position.x), f32(position.y)
	return {top = tactical_project(renderer, {x, y}), right = tactical_project(renderer, {x+1, y}),
		bottom = tactical_project(renderer, {x+1, y+1}), left = tactical_project(renderer, {x, y+1})}
}

@(private = "file")
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
		(vertices.left.x+vertices.right.x)*0.5,
		(vertices.top.y+vertices.bottom.y)*0.5,
	}
}

@(private = "file")
loot_colors :: proc(kind: game.Loot_Kind) -> (fill, outline: rl.Color) {
	if kind == .Weapon { return GOTHIC_BLUE, GOTHIC_STEEL }
	if kind == .Healing {
		return rl.Color{74, 196, 133, 255}, rl.Color{27, 91, 61, 255}
	}
	return rl.Color{246, 207, 92, 255}, rl.Color{104, 77, 24, 255}
}

@(private = "file")
inset_vertices :: proc(vertices: Tile_Vertices, amount: f32) -> Tile_Vertices {
	center := view.Vec2{
		(vertices.left.x+vertices.right.x)*0.5,
		(vertices.top.y+vertices.bottom.y)*0.5,
	}
	return {
		top = {center.x+(vertices.top.x-center.x)*amount, center.y+(vertices.top.y-center.y)*amount},
		right = {center.x+(vertices.right.x-center.x)*amount, center.y+(vertices.right.y-center.y)*amount},
		bottom = {center.x+(vertices.bottom.x-center.x)*amount, center.y+(vertices.bottom.y-center.y)*amount},
		left = {center.x+(vertices.left.x-center.x)*amount, center.y+(vertices.left.y-center.y)*amount},
	}
}

@(private)
draw_card_range_cell :: proc(
	renderer: ^Renderer,
	position: grid.Position,
	fill, outline: rl.Color,
) {
	if !tactical_render_visible(renderer, position) { return }
	vertices := inset_vertices(tile_vertices(renderer, position), 0.88)
	draw_diamond(vertices, fill, outline)
}

// The statuses at a fighter's feet; the bounds of their paper tags (empty when
// it has none). `tag_pixel` 0 sizes the tags by the board's zoom.
@(private)
draw_status_set :: proc(
	renderer: ^Renderer,
	statuses: ^game.Status_Set,
	center: view.Vec2,
	entity_radius: f32,
	opacity: f32 = 1,
	tag_pixel: f32 = 0,
) -> (tags: rl.Rectangle) {
	assert(renderer != nil && statuses != nil)
	if index, found := game.status_index(statuses, .Shield); found {
		shield := &statuses.items[index]
		ring_radius := entity_radius+max(f32(3), 3*renderer.overlay_scale)
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
			center.x+entity_radius*0.78,
			center.y+entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.overlay_scale)
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
			center.x+entity_radius*0.78,
			center.y-entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.overlay_scale)
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
			center.x-entity_radius*0.78,
			center.y+entity_radius*0.62,
		}
		marker_radius := max(f32(4), 5*renderer.overlay_scale)
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
	// Bruciatura and Rallentamento: paper tags in a row under the feet, below
	// the lower round markers.
	pixel := tag_pixel if tag_pixel > 0 else (f32(2) if renderer.overlay_scale >= 2 else f32(1))
	below := center.y+entity_radius*0.62+max(f32(4), 5*renderer.overlay_scale)+2
	return draw_status_tags(statuses, to_raylib(center), below, opacity, pixel)
}

Renderer_Status_View :: struct {
	phase:       game.Room_Phase,
	health:      i32,
	max_health:  i32,
	enemy_count: int,
	gold:        i32,
	pulse_count: u64,
	statuses:    game.Status_Set,
	// The die DESTINO's bumps roll (its chip names it).
	fate_sides:  i32,
}

renderer_status_view :: proc(renderer: ^Renderer, room: ^game.Room) -> (result: Renderer_Status_View) {
	if room == nil || room.player == nil {
		return
	}
	if (renderer.tactical.snapshot != nil) || (renderer_blocks_player_input(renderer) && renderer.timeline.view.valid) {
		presentation := renderer.tactical.snapshot if renderer.tactical.snapshot != nil else &renderer.timeline.view
		result.phase = presentation.phase
		result.health = presentation.player.health
		result.max_health = presentation.player.max_health
		result.enemy_count = visible_presentation_enemy_count(presentation)
		result.gold = presentation.gold
		result.pulse_count = presentation.pulse_count
		result.statuses = presentation.player.statuses
		result.fate_sides = presentation.fate_sides
		return
	}
	result.phase = room.phase
	result.health = room.player.health
	result.max_health = room.player.stats.max_health
	result.enemy_count = len(room.enemies)
	result.gold = room.player.gold
	result.pulse_count = room.pulse_count
	result.statuses = room.player.statuses
	result.fate_sides = game.player_fate_sides(room)
	return
}

@(private)
presentation_actor_center :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> view.Vec2 {
	return tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
}

@(private = "file")
presentation_grid_object_center :: proc(
	renderer: ^Renderer,
	object: ^Presentation_Grid_Object,
) -> view.Vec2 {
	return tactical_project(renderer, {object.position.x+0.5, object.position.y+0.5})
}

@(private)
presentation_event_center :: proc(
	renderer: ^Renderer,
	event: game.Game_Event,
) -> (view.Vec2, bool) {
	if renderer == nil {
		return {}, false
	}
	presentation := renderer.tactical.snapshot if renderer.tactical.snapshot != nil else &renderer.timeline.view
	// The player sunk in his shadow keeps the held world's cues on his body,
	// not on the gliding pool (tactical_cue_actor_position).
	shown_center :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> view.Vec2 {
		shown := actor^
		if actor.entity == game.PLAYER_ENTITY && renderer.tactical.shadow.active { shown.position = renderer.tactical.shadow.body }
		return presentation_actor_center(renderer, &shown)
	}
	if actor, found := presentation_actor_in_view(presentation, event.target); found {
		return shown_center(renderer, actor), true
	}
	if object, found := presentation_grid_object_in_view(presentation, event.target); found {
		return presentation_grid_object_center(renderer, object), true
	}
	if actor, found := presentation_actor_in_view(presentation, event.source); found {
		return shown_center(renderer, actor), true
	}
	if object, found := presentation_grid_object_in_view(presentation, event.source); found {
		return presentation_grid_object_center(renderer, object), true
	}
	return cell_center(renderer, event.to_position), true
}

@(private = "file")
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
	eased := tween.smoothstep(progress)
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

@(private)
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
	case .Move, .Trap_Triggered, .Hazard_Triggered, .Damage, .Damage_Absorbed, .Heal,
	     .Status_Applied, .Status_Removed, .Status_Expired, .Defeat, .Loot_Dropped, .Loot,
	     .Attack_Missed, .Move_Blocked,
	     .Gold_Gained, .Energy_Gained, .Binding_Added, .Binding_Exhausted, .Binding_Expired,
	     .Pulse_Advanced, .Refocus, .Object_Spawned, .Explosive_Armed, .Explosion, .Explosive_Disarmed, .Room_Hazard_Triggered,
	     .Dice_Rolled, .Spell_Launched, .Spell_Impact, .Shadow_Entered, .Shadow_Emerged, .Attack_Deflected, .Fate_Rolled,
	     .Lasso_Caught, .Lasso_Struck, .Lasso_Released, .Fish_Cast, .Fish_Bite, .Fish_Caught,
	     .Pinball_Made, .Pinball_Launched, .Pinball_Bounced, .Pinball_Bumped, .Pinball_Burst, .First_Person_Begun,
	     .Marley_Begun, .Marley_Lights, .Marley_Warned, .Marley_Bomb, .Marley_Saved, .Marley_Bonus, .Marley_Ended,
	     .Flood_Swept, .Fire_Extinguished, .Cannon_Fired, .Cannon_Broken, .Black_Hole_Tick, .Black_Hole_Swallowed, .Black_Hole_Closed,
	     .Ride_Begun, .Ride_Ended, .Dino_Stomp, .Bleed_Bite:
	}
	return nil
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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
		from.x+(to.x-from.x)*progress,
		from.y+(to.y-from.y)*progress,
	}
	center.y -= 4*linear*(1-linear)*max(f32(8), 14*renderer.overlay_scale)
	radius := max(f32(3), (7-2*progress)*renderer.overlay_scale)
	fill, outline := loot_colors(cue.event.loot_kind)
	rl.DrawCircleV(to_raylib(center), radius, fill)
	rl.DrawCircleLinesV(to_raylib(center), radius, outline)
}

@(private = "file")
draw_timeline_loot_drop_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	assert(renderer != nil && cue != nil)
	progress := presentation_cue_eased_progress(cue)
	center := cell_center(renderer, cue.event.from_position)
	radius := max(f32(5), (7+progress*9)*renderer.overlay_scale)
	_, outline := loot_colors(cue.event.loot_kind)
	rl.DrawCircleLinesV(
		to_raylib(center),
		radius,
		color_with_opacity(outline, 1-progress),
	)
}

@(private)
draw_presentation_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	if cue.kind == .Spell_Launched || cue.kind == .Spell_Impact {
		draw_spell_cue(renderer, cue)
		return
	}
	if cue.kind == .Dice_Rolled { return }
	if cue.kind == .Refocus {
		draw_timeline_refocus_banner(renderer, cue)
		return
	}
	if cue.kind == .Card_Played || cue.kind == .Card_Drawn || cue.kind == .Card_Moved ||
	   cue.kind == .Card_Created || cue.kind == .Card_Refocused {
		if cue.kind == .Card_Played { draw_spell_cast(renderer, cue) }
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
	// The Lazzo's MOLLATO shows with its foe's fall (draw_lasso_release_badge);
	// the Pinball's strike is the player's swing, and its ball touching a solid
	// thing says nothing (it rings off it); the dive into the player's eyes is
	// the camera's (first_person.odin).
	if cue.kind == .Move || cue.kind == .Defeat || cue.kind == .Pulse_Advanced ||
	   cue.kind == .Shadow_Entered || cue.kind == .Shadow_Emerged || cue.kind == .Lasso_Released ||
	   cue.kind == .Pinball_Launched || cue.kind == .Pinball_Bounced || cue.kind == .First_Person_Begun ||
	   cue.kind == .Marley_Lights || cue.kind == .Marley_Warned || cue.kind == .Marley_Bomb || cue.kind == .Marley_Ended ||
	   cue.kind == .Flood_Swept || cue.kind == .Fire_Extinguished ||
	   cue.kind == .Cannon_Fired || cue.kind == .Cannon_Broken || cue.kind == .Black_Hole_Tick || cue.kind == .Black_Hole_Swallowed ||
	   cue.kind == .Black_Hole_Closed || cue.kind == .Dino_Stomp {
		return
	}
	center, has_center := presentation_event_center(renderer, cue.event)
	if cue.kind == .Trap_Triggered {
		center = cell_center(renderer, cue.event.to_position)
		has_center = true
	}
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
		name, _ := tactical_status_label(cue.event.status, false)
		label = fmt.ctprintf("+%s %d", name, cue.event.amount)
		color = rl.Color{169, 210, 216, 255}
	case .Status_Removed:
		name, _ := tactical_status_label(cue.event.status, false)
		label = fmt.ctprintf("-%s", name)
		color = rl.Color{169, 183, 177, 255}
	case .Status_Expired:
		name, _ := tactical_status_label(cue.event.status, false)
		label = fmt.ctprintf("FINE %s", name)
		color = rl.Color{169, 183, 177, 255}
	case .Attack_Missed:
		label = "MISS"
		color = rl.Color{247, 239, 213, 255}
	case .Move_Blocked:
		label = "BLOCKED"
		color = rl.Color{238, 174, 73, 255}
	case .Trap_Triggered:
		label = "TRAP"
		color = rl.Color{246, 146, 72, 255}
	case .Hazard_Triggered:
		label = "BURN"
		color = rl.Color{255, 151, 55, 255}
	case .Object_Spawned:
		label = "BOMB"
		color = rl.Color{214, 145, 235, 255}
	case .Explosive_Armed:
		label = "FUSE 2"
		color = rl.Color{255, 194, 85, 255}
	case .Explosive_Disarmed:
		label = "SAFE"
		color = rl.Color{105, 215, 183, 255}
	case .Explosion:
		label = "BOOM"
		color = rl.Color{255, 169, 65, 255}
	case .Room_Hazard_Triggered:
		label = "FURNACE"
		color = rl.Color{255, 169, 65, 255}
	case .Gold_Gained:
		label = fmt.ctprintf("+%d GOLD", cue.event.amount)
		color = rl.Color{246, 207, 92, 255}
	case .Energy_Gained:
		label = fmt.ctprintf("+%d ENERGY", cue.event.amount)
		color = rl.Color{130, 222, 239, 255}
	case .Binding_Added:
		label = "BINDING +"
		color = rl.Color{194, 184, 226, 255}
	case .Binding_Exhausted:
		label = "BINDING USED"
		color = rl.Color{194, 184, 226, 255}
	case .Binding_Expired:
		label = "BINDING END"
		color = rl.Color{169, 183, 177, 255}
	case .Attack_Deflected:
		label = "RIFLESSO"
		color = rl.Color{101, 174, 218, 255}
	case .Fate_Rolled:
		label, color = fate_outcome_label(cue.event, true)
	// LAZZO (lasso.odin): the throw, a hit or a smash.
	case .Lasso_Caught:
		label = "LAZZO"
		color = LASSO_ROPE_LIGHT
	case .Lasso_Struck:
		label = fmt.ctprintf("SCHIANTO %d", cue.event.amount) if cue.event.target == game.SYSTEM_ENTITY else fmt.ctprintf("COLPO %d", cue.event.amount)
		color = rl.Color{255, 112, 102, 255}
	// CANNA DA PESCA (fishing.odin): the cast, the bite, the catch.
	case .Fish_Cast:
		label = "PESCA"
		color = FISHING_WATER_LIGHT
	case .Fish_Bite:
		label = "!"
		color = FISHING_BITE_RED
	case .Fish_Caught:
		label = fishing_catch_label(cue.event)
		color = FISHING_WATER_LIGHT
	// PINBALL (pinball.odin): the ball made, a foe struck and its value, the
	// burst.
	case .Pinball_Made:
		label = "PINBALL"
		color = PINBALL_STEEL_LIGHT
	case .Pinball_Bumped:
		label = fmt.ctprintf("COLPO %d", cue.event.amount)
		color = rl.Color{255, 112, 102, 255}
	case .Pinball_Burst:
		label = "POP!"
		color = PINBALL_STEEL_LIGHT
	// BOMB MARLEY (marley.odin): the party, a character the lights saved, the
	// seconds a kill earned. The rest is the board's own drawing.
	case .Marley_Begun:
		label = "BOMB MARLEY"
		color = rl.Color{240, 196, 64, 255}
	case .Marley_Saved:
		label = "SALVO"
		color = rl.Color{150, 226, 110, 255}
	case .Marley_Bonus:
		label = fmt.ctprintf("+%ds", cue.event.amount)
		color = rl.Color{240, 196, 64, 255}
	// DINOSAURO: which one the die gave; SANGUINAMENTO's extra bite.
	case .Ride_Begun:
		label = fmt.ctprintf("%s %ds", game.dino_name(game.Dino_Kind(cue.event.duration)), cue.event.amount)
		color = rl.Color{124, 206, 96, 255}
	case .Ride_Ended:
		label = "SMONTA"
		color = rl.Color{169, 183, 177, 255}
	case .Bleed_Bite:
		label = fmt.ctprintf("SANGUE +%d", cue.event.amount)
		color = rl.Color{255, 82, 82, 255}
	case .Marley_Lights, .Marley_Warned, .Marley_Bomb, .Marley_Ended, .Flood_Swept, .Fire_Extinguished,
	     .Cannon_Fired, .Cannon_Broken, .Black_Hole_Tick, .Black_Hole_Swallowed, .Black_Hole_Closed, .Dino_Stomp:
		unreachable()
	case .Move, .Card_Played, .Card_Drawn, .Card_Moved, .Card_Created, .Refocus,
	     .Card_Refocused, .Defeat,
	     .Loot_Dropped, .Loot, .Pulse_Advanced, .Dice_Rolled, .Spell_Launched, .Spell_Impact,
	     .Shadow_Entered, .Shadow_Emerged, .Lasso_Released, .Pinball_Launched, .Pinball_Bounced, .First_Person_Begun:
		unreachable()
	}
	draw_timeline_popup(renderer, label, color, center, presentation_cue_progress(cue))
}

draw_status :: proc(renderer: ^Renderer, room: ^game.Room, scale_mode: view.Scale_Mode) {
	draw_gothic_status(renderer, room)
}
