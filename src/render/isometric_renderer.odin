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
	tactical: Tactical_View,
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
	world_playback: ^World_Playback,
	playback_speed: f32,
	frame_simulation_dt: f32,
	frame_clock_valid: bool,
	frame_had_cinematic: bool,
	sprite_assets: Sprite_Assets,
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
	if renderer.tactical.enabled { return tactical_hand_card_bounds(renderer, card_index, card_count) }
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
	if renderer != nil && renderer.tactical.enabled { return tactical_hand_card_bounds(renderer, card_index, card_count) }
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
	if renderer != nil && renderer.tactical.enabled { return tactical_refocus_bounds(renderer) }
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
	return renderer != nil && !renderer_blocks_player_input(renderer) && (!renderer.tactical.enabled || renderer.tactical.refocus_enabled)
}

card_drop_area_contains :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	if renderer != nil && renderer.tactical.enabled { return point_in_rectangle(point, tactical_world_bounds(renderer)) }
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
	case .Shove:
		fill, outline = rl.Color{66, 42, 35, 245}, rl.Color{236, 137, 91, 255}
	case .Dash:
		fill, outline = rl.Color{27, 58, 65, 245}, rl.Color{80, 206, 213, 255}
	case .Grappling_Hook:
		fill, outline = rl.Color{48, 48, 54, 245}, rl.Color{187, 190, 197, 255}
	case .Heavy_Blow, .Titan_Grip:
		fill, outline = rl.Color{70, 36, 31, 245}, rl.Color{244, 126, 75, 255}
	case .Venom_Needle:
		fill, outline = rl.Color{27, 56, 50, 245}, rl.Color{126, 218, 132, 255}
	case .Caustic_Bloom:
		fill, outline = rl.Color{56, 59, 27, 245}, rl.Color{205, 220, 83, 255}
	case .Purifying_Guard:
		fill, outline = rl.Color{33, 53, 60, 245}, rl.Color{151, 222, 215, 255}
	case .Volatile_Study:
		fill, outline = rl.Color{62, 36, 63, 245}, rl.Color{238, 133, 201, 255}
	case .Fate_Strike:
		fill, outline = rl.Color{61, 42, 77, 245}, rl.Color{230, 180, 255, 255}
	case .Chain_Lightning, .Shock_Floor, .Tesla_Coil, .Storm_Crown:
		fill, outline = rl.Color{25, 52, 73, 245}, rl.Color{119, 224, 255, 255}
	case .Sundering_Blow:
		fill, outline = rl.Color{74, 29, 34, 245}, rl.Color{245, 94, 100, 255}
	case .Prismatic_Barrage:
		fill, outline = rl.Color{65, 48, 75, 245}, rl.Color{247, 198, 112, 255}
	case .Twin_Venom:
		fill, outline = rl.Color{40, 58, 31, 245}, rl.Color{179, 237, 111, 255}
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
		return fmt.ctprintf("DEAL %d DAMAGE", 3+upgrade), "RANGE 1"
	case .Arc_Bolt:
		return fmt.ctprintf("DEAL %d DAMAGE", 3+upgrade), "RANGE 1-3"
	case .Piercing_Ray:
		return fmt.ctprintf("DEAL %d IN LINE", 2+upgrade), "RANGE 1-5"
	case .Cross_Slash:
		return fmt.ctprintf("DEAL %d IN CROSS", 2+upgrade), "RANGE 1-3"
	case .Firebomb:
		return fmt.ctprintf("DEAL %d IN 3X3", 2+upgrade), "IGNITES BARRELS"
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
	case .Shove:
		return fmt.ctprintf("DEAL %d DAMAGE", 1+upgrade), "RANGE 1 / PUSH 1"
	case .Dash:
		return "MOVE 1-3 CELLS", "TRAVERSE HAZARDS"
	case .Grappling_Hook:
		return fmt.ctprintf("DEAL %d DAMAGE", 1+upgrade), "PULL ADJACENT"
	case .Heavy_Blow:
		return fmt.ctprintf("DEAL %d DAMAGE", 5+upgrade), "RANGE 1"
	case .Venom_Needle:
		return fmt.ctprintf("%d DMG + 1 POISON", 1+upgrade), "LASTS 3 PULSES"
	case .Caustic_Bloom:
		return fmt.ctprintf("APPLY %d POISON", 2+upgrade), "3X3 - 2 PULSES"
	case .Purifying_Guard:
		return fmt.ctprintf("GAIN %d SHIELD", 2+upgrade), "3 PULSES + CLEANSE"
	case .Volatile_Study:
		return "CREATE 1 SPARK", fmt.ctprintf("DRAW %d - EXHAUST", 1+upgrade)
	case .Fate_Strike:
		return fmt.ctprintf("%d + D6 DAMAGE", 2+upgrade), fmt.ctprintf("6: BOUNCE FOR %d", 3+upgrade)
	case .Chain_Lightning:
		return fmt.ctprintf("%d DAMAGE EACH", 3+upgrade), "UP TO 3 / HOP 3"
	case .Sundering_Blow:
		if upgrade == 0 { return "2D6 DAMAGE", "ROLL 8+: PUSH 1" }
		return fmt.ctprintf("2D6 + %d DAMAGE", upgrade), "ROLL 8+: PUSH 1"
	case .Prismatic_Barrage:
		return fmt.ctprintf("3D6: 4+ = %d DMG", 3+upgrade), "1-3: 1 SHIELD EACH"
	case .Twin_Venom:
		return fmt.ctprintf("HIGHER D6 +%d DMG", 1+upgrade), "2D6 / PAIR: POISON 2"
	case .Shock_Floor: return "D4 SHOCKS / D4 TARGETS", "1 DMG / 3X3 / ACTIVE"
	case .Tesla_Coil: return "8 / DISTANCE DAMAGE", "MAX 4 / ACTIVE DEVICE"
	case .Titan_Grip: return fmt.ctprintf("%d DAMAGE / THROW 2", 3+upgrade), "INTERRUPT / STAGGER 1"
	case .Storm_Crown: return fmt.ctprintf("%d DAMAGE EACH", 5+upgrade), "LEGENDARY / CHAIN 3"
	case .Count:
	}
	return "", ""
}

dice_card_detail_lines :: proc(card: game.Card_Instance) -> (lines: [4]cstring) {
	lines[0], lines[1] = card_detail_lines(card)
	lines[2] = "SHIELD FIRST / 2P" if card.definition_id == .Prismatic_Barrage else "2 PULSES / IF ALIVE"
	lines[3] = "RANGE 1-3 / LOS"
	return
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
	case .Shove:
		return "SHOVE"
	case .Dash:
		return "DASH"
	case .Grappling_Hook:
		return "HOOK"
	case .Heavy_Blow:
		return "HEAVY"
	case .Venom_Needle:
		return "NEEDLE"
	case .Caustic_Bloom:
		return "BLOOM"
	case .Purifying_Guard:
		return "PURIFY"
	case .Volatile_Study:
		return "STUDY"
	case .Fate_Strike:
		return "FATE"
	case .Chain_Lightning:
		return "CHAIN"
	case .Sundering_Blow:
		return "SUNDER"
	case .Prismatic_Barrage:
		return "BARRAGE"
	case .Twin_Venom:
		return "VENOM"
	case .Shock_Floor: return "FLOOR"
	case .Tesla_Coil: return "TESLA"
	case .Titan_Grip: return "TITAN"
	case .Storm_Crown: return "CROWN"
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
	case .Shock_Floor, .Tesla_Coil:
		draw_device_card_icon(id, panel, color)
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
	case .Shove:
		rl.DrawLineEx({center.x-radius, center.y}, {center.x+radius, center.y}, 5, color)
		rl.DrawLineEx({center.x+radius, center.y}, {center.x+6, center.y-10}, 4, color)
		rl.DrawLineEx({center.x+radius, center.y}, {center.x+6, center.y+10}, 4, color)
	case .Dash:
		for offset in -1..=1 {
			y := center.y+f32(offset)*10
			rl.DrawLineEx({center.x-radius, y}, {center.x+radius, y}, 3, color)
		}
	case .Grappling_Hook:
		rl.DrawCircleLinesV({center.x+10, center.y-9}, 8, color)
		rl.DrawLineEx({center.x+5, center.y-3}, {center.x-13, center.y+15}, 4, color)
	case .Heavy_Blow, .Titan_Grip:
		rl.DrawRectangle(
			c.int(center.x-15),
			c.int(center.y-14),
			27,
			10,
			color,
		)
		rl.DrawLineEx({center.x+6, center.y-5}, {center.x-10, center.y+17}, 5, color)
	case .Venom_Needle:
		rl.DrawLineEx({center.x-17, center.y+15}, {center.x+12, center.y-14}, 3, color)
		rl.DrawCircleV({center.x+13, center.y-15}, 3, color)
		rl.DrawCircleLinesV({center.x+12, center.y+12}, 5, color)
	case .Caustic_Bloom:
		rl.DrawCircleV(center, 6, color)
		petal_offsets := [?]rl.Vector2{{-11, 0}, {11, 0}, {0, -11}, {0, 11}}
		for offset in petal_offsets {
			rl.DrawCircleLinesV({center.x+offset.x, center.y+offset.y}, 7, color)
		}
	case .Purifying_Guard:
		points := [?]rl.Vector2{
			{center.x, center.y-radius},
			{center.x+radius-3, center.y-8},
			{center.x+11, center.y+13},
			{center.x, center.y+radius},
			{center.x-11, center.y+13},
			{center.x-radius+3, center.y-8},
			{center.x, center.y-radius},
		}
		for index in 0..<len(points)-1 {
			rl.DrawLineEx(points[index], points[index+1], 3, color)
		}
		rl.DrawLineEx({center.x-7, center.y}, {center.x+7, center.y}, 3, color)
		rl.DrawLineEx({center.x, center.y-7}, {center.x, center.y+7}, 3, color)
	case .Volatile_Study:
		rl.DrawRectangleLines(
			c.int(center.x-17),
			c.int(center.y-10),
			34,
			24,
			color,
		)
		rl.DrawLineEx({center.x, center.y-10}, {center.x, center.y+14}, 2, color)
		rl.DrawLineEx({center.x-6, center.y-17}, {center.x-2, center.y-12}, 3, color)
		rl.DrawLineEx({center.x+6, center.y-17}, {center.x+2, center.y-12}, 3, color)
	case .Fate_Strike:
		rl.DrawRectangleLinesEx({center.x-17, center.y-17, 34, 34}, 2, color)
		for delta in ([?]rl.Vector2{{-9, -9}, {9, -9}, {0, 0}, {-9, 9}, {9, 9}}) {
			rl.DrawCircleV(center+delta, 3, color)
		}
	case .Chain_Lightning, .Storm_Crown:
		points := [?]rl.Vector2{{center.x-25, center.y+10}, {center.x, center.y-12}, {center.x+25, center.y+6}}
		for index in 0..<len(points) {
			rl.DrawCircleLinesV(points[index], 6, color)
			if index > 0 { rl.DrawLineEx(points[index-1], points[index], 2, color) }
		}
	case .Sundering_Blow:
		for offset in ([2]rl.Vector2{{-13, -7}, {12, 9}}) {
			position := center+offset
			rl.DrawRectangleRoundedLinesEx({position.x-13, position.y-13, 26, 26}, 0.22, 4, 2, color)
			for pip in ([3]rl.Vector2{{-6, -6}, {0, 0}, {6, 6}}) {
				rl.DrawCircleV(position+pip, 2, color)
			}
		}
	case .Prismatic_Barrage:
		for index in 0..<3 {
			x := center.x+f32(index-1)*20
			ray_color := color
			if color == (rl.Color{247, 198, 112, 255}) {ray_color = prismatic_ray_color(index)}
			rl.DrawLineEx({x, center.y-18}, {center.x, center.y+12}, 3, ray_color)
			rl.DrawTriangle({x, center.y-24}, {x-5, center.y-15}, {x+5, center.y-15}, ray_color)
		}
		rl.DrawCircleLinesV({center.x, center.y+12}, 7, color)
	case .Twin_Venom:
		for sign in ([2]f32{-1, 1}) {
			x := center.x+sign*10
			rl.DrawLineEx({x, center.y-19}, {x+sign*5, center.y-5}, 4, color)
			rl.DrawLineEx({x+sign*5, center.y-5}, {x-sign*3, center.y+12}, 3, color)
			rl.DrawCircleV({x-sign*3, center.y+18}, 3, color)
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
	if expanded && (card.definition_id == .Sundering_Blow || card.definition_id == .Prismatic_Barrage || card.definition_id == .Twin_Venom) {
		// Keep the two-word title clear of the cost badge and the shortcut.
		title_center := c.int(bounds.x+35+(bounds.width-57)*0.5)
		first: cstring = "Sundering"
		second: cstring = "Blow"
		if card.definition_id == .Prismatic_Barrage {first, second = "Prismatic", "Barrage"}
		if card.definition_id == .Twin_Venom {first, second = "Twin", "Venom"}
		rl.DrawText(first, title_center-rl.MeasureText(first, 12)/2, c.int(bounds.y+7), 12, label_color)
		rl.DrawText(second, title_center-rl.MeasureText(second, 12)/2, c.int(bounds.y+23), 12, label_color)
	} else {
		rl.DrawText(name_text, name_x, c.int(bounds.y+11), 14, label_color)
	}
	if expanded {
		rl.DrawText(fmt.ctprintf("%d", slot+1), c.int(bounds.x+bounds.width-17), c.int(bounds.y+11), 11, outline)
	} else {
		rl.DrawText(fmt.ctprintf("%d", slot+1), c.int(bounds.x+7), c.int(bounds.y+34), 10, outline)
	}
	draw_card_sigil(bounds, card.definition_id, outline)

	if expanded && (card.definition_id == .Prismatic_Barrage || card.definition_id == .Twin_Venom) {
		lines := dice_card_detail_lines(card)
		for line, index in lines {
			font: c.int = 10 // DrawText's default font never renders below 10 px.
			rl.DrawText(line, c.int(bounds.x+(bounds.width-f32(rl.MeasureText(line, font)))*0.5),
				c.int(bounds.y+110+f32(index)*12), font, label_color if index == 0 else outline)
		}
	} else if expanded {
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
		upgrade_position := rl.Vector2{bounds.x+8, bounds.y+bounds.height-18}
		if expanded && (card.definition_id == .Prismatic_Barrage || card.definition_id == .Twin_Venom) {
			upgrade_position = {bounds.x+bounds.width-28, bounds.y+87}
		}
		rl.DrawText(
			fmt.ctprintf("+%d", card.upgrade_level),
			c.int(upgrade_position.x),
			c.int(upgrade_position.y),
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
	if renderer.tactical.enabled { gothic_button(renderer, refocus_button_bounds(renderer), "F", "REFOCUS", refocus_button_is_enabled(renderer)); return }
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
	if renderer.tactical.enabled && renderer.tactical.snapshot != nil {
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
	assert(renderer != nil && room != nil && room.player != nil)
	if renderer.tactical.enabled {
		draw_tactical_hand(renderer, room, hovered_card_id, selected_card_id, dragged_card_id, mouse_position)
		return
	}
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
		definition, found := game.card_definition_by_id(card.definition_id, game.tactical_enabled(room))
		assert(found)
		bounds := hand_card_bounds(renderer, index, deck.hand_count)
		affordable := deck.energy >= definition.cost
		draw_card_face(bounds, card, definition, index, affordable, false, false, card.id == selected_card_id)
	}
	if raised_card_id != 0 {
		if index, found := game.hand_card_index_by_id(deck, raised_card_id); found {
			card := deck.hand[index]
			definition, definition_found := game.card_definition_by_id(card.definition_id, game.tactical_enabled(room))
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
			definition, definition_found := game.card_definition_by_id(card.definition_id, game.tactical_enabled(room))
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
		clear_renderer_world_playback(renderer)
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
	clear_loot_animations(renderer)
	clear_enemy_move_animations(renderer)
	return begin_event_timeline(&renderer.timeline, before, events, after)
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
	update_renderer_world_playback(renderer, step)
	return was_busy && !renderer_timeline_is_busy(renderer)
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
	if renderer.tactical.enabled && renderer.tactical.scene_3d {
		x, y := f32(position.x), f32(position.y)
		return {tactical_project(renderer, {x, y}), tactical_project(renderer, {x+1, y}),
			tactical_project(renderer, {x+1, y+1}), tactical_project(renderer, {x, y+1})}
	}
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

draw_quad :: proc(a, b, c, d: view.Vec2, color, outline: rl.Color) {
	rl.DrawTriangle(to_raylib(a), to_raylib(c), to_raylib(b), color)
	rl.DrawTriangle(to_raylib(a), to_raylib(d), to_raylib(c), color)
	rl.DrawLineV(to_raylib(a), to_raylib(b), outline)
	rl.DrawLineV(to_raylib(b), to_raylib(c), outline)
	rl.DrawLineV(to_raylib(c), to_raylib(d), outline)
	rl.DrawLineV(to_raylib(d), to_raylib(a), outline)
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
	if enemy.archetype == .Demolitionist {
		return max(f32(12), 18*renderer.camera.zoom)
	}
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
	if draw_sprite_asset(&renderer.sprite_assets, sprite_key_for_enemy(enemy.archetype), center, renderer.camera.zoom, opacity) {
		return
	}
	switch enemy.archetype {
	case .Custodian, .Demolitionist:
		draw_cooperative_enemy_body(renderer, enemy, center, opacity)
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
	case .Bomber:
		rl.DrawCircleV(to_raylib(center), radius, color_with_opacity(rl.Color{57, 28, 57, 255}, opacity))
		rl.DrawCircleV(to_raylib(center), radius-2, color_with_opacity(rl.Color{191, 113, 212, 255}, opacity))
		rl.DrawCircleV(to_raylib({center.x+radius*0.55, center.y-radius*0.5}), radius*0.45,
			color_with_opacity(rl.Color{32, 32, 39, 255}, opacity))
		rl.DrawCircleV(to_raylib({center.x+radius*0.75, center.y-radius}), max(f32(2), radius*0.18),
			color_with_opacity(rl.Color{255, 204, 85, 255}, opacity))
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
	if kind == .Weapon { return GOTHIC_BLUE, GOTHIC_STEEL }
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
	if !tactical_render_visible(renderer, position) { return }
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
		if enemy.intent.kind != .Bombard && game.enemy_intent_cell_is_threatened(&enemy.intent, position) {
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
		case .Recover:
			label = fmt.ctprintf("RECOVER %d", enemy.recovery_pulses)
			color = rl.Color{105, 215, 183, 255}
		case .Protect:
			label = "SHIELD 3"
			color = rl.Color{102, 216, 218, 255}
		case .Bombard:
			label = "BOMB 2"
			color = rl.Color{214, 145, 235, 255}
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
	definition, definition_found := game.card_definition_by_id(card.definition_id, game.tactical_enabled(room))
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

	if definition.tactical && definition.id == .Toxic_Wave {
		for enemy in room.enemies {
			if game.tactical_card_enemy_in_area(room, definition.id, enemy.position) {
				draw_card_range_cell(renderer, enemy.position, range_fill, range_outline)
			}
		}
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
	if evaluation.has_movement {
		movement_clear := game.movement_query_is_clear(&evaluation.movement)
		movement_fill := rl.Color{80, 206, 213, 52}
		movement_outline := rl.Color{111, 231, 225, 235}
		if !movement_clear {
			movement_fill = rl.Color{190, 68, 70, 42}
			movement_outline = rl.Color{235, 91, 91, 215}
		}
		for index in 0..<evaluation.movement.count {
			draw_card_range_cell(
				renderer,
				evaluation.movement.cells[index],
				movement_fill,
				movement_outline,
			)
		}
		if evaluation.movement.has_blocker {
			draw_card_range_cell(
				renderer,
				evaluation.movement.blocker,
				rl.Color{190, 68, 70, 105},
				rl.Color{255, 112, 102, 255},
			)
		}
	}
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
	if evaluation.has_movement {
		landing_clear := game.movement_query_is_clear(&evaluation.movement)
		landing_fill := rl.Color{65, 192, 180, 96}
		landing_outline := rl.Color{135, 245, 226, 255}
		if !landing_clear {
			landing_fill = rl.Color{190, 68, 70, 96}
			landing_outline = rl.Color{255, 112, 102, 255}
		}
		draw_card_range_cell(
			renderer,
			evaluation.movement.destination,
			landing_fill,
			landing_outline,
		)
		if card.definition_id == .Sundering_Blow && tactical_render_visible(renderer, evaluation.movement.destination) {
			center := cell_center(renderer, evaluation.movement.destination)
			rl.DrawText("8+", c.int(center.x)-7, c.int(center.y)-5, 11, landing_outline)
		}
	}
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
	if (renderer.tactical.enabled && renderer.tactical.snapshot != nil) || (renderer_blocks_player_input(renderer) && renderer.timeline.view.valid) {
		presentation := renderer.tactical.snapshot if renderer.tactical.enabled && renderer.tactical.snapshot != nil else &renderer.timeline.view
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
	if renderer.tactical.enabled { return tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5}) }
	return view.grid_point_to_canvas(
		&renderer.camera,
		&renderer.projection,
		{x = actor.position.x+0.5, y = actor.position.y+0.5},
	)
}

presentation_grid_object_center :: proc(
	renderer: ^Renderer,
	object: ^Presentation_Grid_Object,
) -> view.Vec2 {
	assert(renderer != nil && object != nil)
	if renderer.tactical.enabled { return tactical_project(renderer, {object.position.x+0.5, object.position.y+0.5}) }
	return view.grid_point_to_canvas(
		&renderer.camera,
		&renderer.projection,
		{x = object.position.x+0.5, y = object.position.y+0.5},
	)
}

draw_grid_object_body :: proc(
	renderer: ^Renderer,
	kind: game.Grid_Object_Kind,
	center: view.Vec2,
	health, max_health: i32,
	opacity: f32 = 1,
) {
	assert(renderer != nil)
	defer draw_grid_object_health(renderer, kind, center, health, max_health, opacity)
	if game.board_device_kind(kind) { draw_device_card_icon(.Tesla_Coil if kind == .Tesla_Coil else .Shock_Floor, {center.x-18, center.y-36, 36, 40}, color_with_opacity(GOTHIC_BLUE, opacity)); return }
	if kind == .Barrel || kind == .Bomb {
		if draw_sprite_asset(&renderer.sprite_assets, sprite_key_for_object(kind), center, renderer.camera.zoom, opacity) { return }
		draw_explosive_body(renderer, kind, center, opacity)
		return
	}
	if draw_sprite_asset(&renderer.sprite_assets, sprite_key_for_object(kind), center, renderer.camera.zoom, opacity) { return }
	if kind == .Fire {
		scale := renderer.camera.zoom
		half_width := max(f32(7), 11*scale)
		base_y := center.y+max(f32(2), 3*scale)
		outer_height := max(f32(16), 27*scale)
		inner_height := max(f32(9), 15*scale)

		// Small embers keep Fire readable as a persistent cell hazard without
		// making it look like a solid, movement-blocking tile.
		ember_color := color_with_opacity(rl.Color{181, 54, 36, 235}, opacity)
		rl.DrawCircleV(
			to_raylib({x = center.x-half_width*0.9, y = base_y-half_width*0.25}),
			max(f32(1.5), 2.2*scale),
			ember_color,
		)
		rl.DrawCircleV(
			to_raylib({x = center.x+half_width*0.95, y = base_y-half_width*0.45}),
			max(f32(1), 1.7*scale),
			ember_color,
		)

		outer_color := color_with_opacity(rl.Color{221, 62, 34, 255}, opacity)
		rl.DrawTriangle(
			to_raylib({x = center.x, y = base_y-outer_height}),
			to_raylib({x = center.x-half_width, y = base_y}),
			to_raylib({x = center.x+half_width, y = base_y}),
			outer_color,
		)
		rl.DrawTriangle(
			to_raylib({x = center.x-half_width*0.38, y = base_y-outer_height*0.64}),
			to_raylib({x = center.x-half_width*1.22, y = base_y}),
			to_raylib({x = center.x-half_width*0.05, y = base_y}),
			color_with_opacity(rl.Color{241, 103, 33, 255}, opacity),
		)
		rl.DrawTriangle(
			to_raylib({x = center.x+half_width*0.45, y = base_y-outer_height*0.72}),
			to_raylib({x = center.x+half_width*0.02, y = base_y}),
			to_raylib({x = center.x+half_width*1.15, y = base_y}),
			color_with_opacity(rl.Color{241, 103, 33, 255}, opacity),
		)
		rl.DrawCircleV(
			to_raylib({x = center.x, y = base_y-half_width*0.38}),
			half_width,
			color_with_opacity(rl.Color{247, 126, 35, 255}, opacity),
		)
		rl.DrawTriangle(
			to_raylib({x = center.x+half_width*0.12, y = base_y-inner_height}),
			to_raylib({x = center.x-half_width*0.55, y = base_y}),
			to_raylib({x = center.x+half_width*0.58, y = base_y}),
			color_with_opacity(rl.Color{255, 218, 84, 255}, opacity),
		)
		rl.DrawCircleV(
			to_raylib({x = center.x, y = base_y-half_width*0.25}),
			half_width*0.52,
			color_with_opacity(rl.Color{255, 235, 145, 255}, opacity),
		)
		return
	}
	if kind != .Ice_Block {
		return
	}

	half_width := max(f32(9), 17*renderer.camera.zoom)
	half_depth := max(f32(4.5), 8*renderer.camera.zoom)
	height := max(f32(13), 23*renderer.camera.zoom)
	base := Tile_Vertices{
		top = {x = center.x, y = center.y-half_depth},
		right = {x = center.x+half_width, y = center.y},
		bottom = {x = center.x, y = center.y+half_depth},
		left = {x = center.x-half_width, y = center.y},
	}
	top := base
	top.top.y -= height
	top.right.y -= height
	top.bottom.y -= height
	top.left.y -= height
	outline := color_with_opacity(rl.Color{210, 248, 252, 255}, opacity)
	draw_quad(
		top.left,
		top.bottom,
		base.bottom,
		base.left,
		color_with_opacity(rl.Color{57, 145, 174, 255}, opacity),
		outline,
	)
	draw_quad(
		top.bottom,
		top.right,
		base.right,
		base.bottom,
		color_with_opacity(rl.Color{39, 111, 151, 255}, opacity),
		outline,
	)
	draw_diamond(
		top,
		color_with_opacity(rl.Color{137, 224, 236, 255}, opacity),
		outline,
	)
	rl.DrawLineEx(
		to_raylib({x = top.top.x, y = top.top.y+half_depth*0.6}),
		to_raylib({x = top.bottom.x-half_width*0.25, y = top.bottom.y-half_depth*0.25}),
		max(f32(1), 1.2*renderer.camera.zoom),
		color_with_opacity(rl.Color{238, 255, 255, 225}, opacity),
	)
	rl.DrawLineEx(
		to_raylib({x = top.bottom.x-half_width*0.25, y = top.bottom.y-half_depth*0.25}),
		to_raylib({x = top.right.x-half_width*0.2, y = top.right.y-half_depth*0.15}),
		max(f32(1), 1.2*renderer.camera.zoom),
		color_with_opacity(rl.Color{238, 255, 255, 225}, opacity),
	)
}

draw_grid_object_health :: proc(renderer: ^Renderer, kind: game.Grid_Object_Kind, center: view.Vec2,
	health, max_health: i32, opacity: f32) {
	if kind == .Ice_Block && max_health > 0 && health < max_health {
		bar_width := max(f32(9), 17*renderer.camera.zoom)*1.6
		bar_height := max(f32(2), 3*renderer.camera.zoom)
		bar_center_x := center.x
		bar_y := center.y-max(f32(13), 23*renderer.camera.zoom)-max(f32(4.5), 8*renderer.camera.zoom)-max(f32(5), 7*renderer.camera.zoom)
		asset := &renderer.sprite_assets.sprites[int(sprite_key_for_object(kind))]
		if asset.configured {
			_, bounds := sprite_asset_rectangles(asset, renderer.sprite_assets.elapsed, center, renderer.camera.zoom)
			bar_width = bounds.width*0.8
			bar_center_x = bounds.x+bounds.width*0.5
			bar_y = bounds.y-max(f32(5), 7*renderer.camera.zoom)
		}
		bar_x := bar_center_x-bar_width*0.5
		ratio := clamp(f32(max(health, i32(0)))/f32(max_health), f32(0), f32(1))
		rl.DrawRectangleRec(
			{bar_x, bar_y, bar_width, bar_height},
			color_with_opacity(rl.Color{17, 31, 38, 220}, opacity),
		)
		rl.DrawRectangleRec(
			{bar_x, bar_y, bar_width*ratio, bar_height},
			color_with_opacity(rl.Color{101, 218, 230, 255}, opacity),
		)
	}
}

draw_player_body :: proc(renderer: ^Renderer, center: view.Vec2, opacity: f32 = 1) -> f32 {
	assert(renderer != nil)
	radius := max(f32(8), 13*renderer.camera.zoom)
	if draw_player_event_clip(renderer, center, opacity) { return radius }
	if draw_sprite_asset(&renderer.sprite_assets, .Player, center, renderer.camera.zoom, opacity) { return radius }
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

draw_presentation_grid_objects :: proc(renderer: ^Renderer, presentation: ^Room_Presentation) {
	assert(renderer != nil && presentation != nil)
	if presentation.object_count < 0 || presentation.object_count > len(presentation.objects) {
		return
	}
	for index in 0..<presentation.object_count {
		object := &presentation.objects[index]
		if !object.visible {
			continue
		}
		draw_grid_object_body(
			renderer,
			object.kind,
			presentation_grid_object_center(renderer, object),
			object.health,
			object.max_health,
			object.opacity,
		)
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
			enemy := game.Enemy{archetype = actor.archetype, boss_phase = actor.boss_phase}
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
	presentation := renderer.tactical.snapshot if renderer.tactical.enabled && renderer.tactical.snapshot != nil else &renderer.timeline.view
	if actor, found := presentation_actor_in_view(presentation, event.target); found {
		return presentation_actor_center(renderer, actor), true
	}
	if object, found := presentation_grid_object_in_view(presentation, event.target); found {
		return presentation_grid_object_center(renderer, object), true
	}
	if actor, found := presentation_actor_in_view(presentation, event.source); found {
		return presentation_actor_center(renderer, actor), true
	}
	if object, found := presentation_grid_object_in_view(presentation, event.source); found {
		return presentation_grid_object_center(renderer, object), true
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
	case .Move, .Trap_Triggered, .Hazard_Triggered, .Damage, .Damage_Absorbed, .Heal,
	     .Status_Applied, .Status_Removed, .Status_Expired, .Defeat, .Loot_Dropped, .Loot,
	     .Attack_Missed, .Move_Blocked,
	     .Gold_Gained, .Energy_Gained, .Binding_Added, .Binding_Exhausted, .Binding_Expired,
	     .Pulse_Advanced, .Refocus, .Object_Spawned, .Explosive_Armed, .Explosion, .Explosive_Disarmed, .Room_Hazard_Triggered,
	     .Dice_Rolled, .Spell_Launched, .Spell_Impact:
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
	for offset in 0..<presentation_group_size(&renderer.timeline) {
		cue, found := presentation_cue_at(&renderer.timeline, offset)
		if found && cue.started { draw_presentation_cue(renderer, cue) }
	}
}

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
	if cue.kind == .Move || cue.kind == .Defeat || cue.kind == .Pulse_Advanced {
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
	case .Move, .Card_Played, .Card_Drawn, .Card_Moved, .Card_Created, .Refocus,
	     .Card_Refocused, .Defeat,
	     .Loot_Dropped, .Loot, .Pulse_Advanced, .Dice_Rolled, .Spell_Launched, .Spell_Impact:
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
	draw_explosive_ground(renderer, room)
	draw_encounter_ground(renderer, room)

	if timeline_busy {
		draw_presentation_grid_objects(renderer, &renderer.timeline.view)
		draw_presentation_loot(renderer, &renderer.timeline.view)
		draw_presentation_actors(renderer)
		draw_explosive_countdowns(renderer, room)
		draw_active_presentation_cue(renderer)
	} else {
		for object in room.objects {
			draw_grid_object_body(
				renderer,
				object.kind,
				cell_center(renderer, object.position),
				object.health,
				object.max_health,
			)
		}

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
		draw_explosive_countdowns(renderer, room)
	}
}

draw_status :: proc(renderer: ^Renderer, room: ^game.Room, scale_mode: view.Scale_Mode) {
	if renderer.tactical.enabled { draw_gothic_status(renderer, room); return }
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
		fmt.ctprintf("ANIMATION %.2gx  [F4]", renderer_playback_speed(renderer)),
		26, 104, 12, rl.Color{169, 183, 177, 255},
	)
	family := room.family
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid { family = renderer.timeline.view.family }
	if family != .Scattered {
		rl.DrawText(fmt.ctprintf("%s", level.room_family_name(family)), 265, 104, 12, rl.Color{197, 185, 151, 255})
	}
	if status_view.phase == .Combat {
		if !renderer.tactical.enabled {
			draw_tactical_legend(renderer)
			draw_encounter_status(renderer, room)
		}
	} else if status_view.phase == .Loot {
		rl.DrawText("MOVE INTO BLOCKS TO BREAK THEM AND CLEAR YOUR WAY", 26, 122, 10, rl.Color{169, 183, 177, 255})
	}
	rl.DrawText(
		fmt.ctprintf(
			"%s  |  %s",
			game.room_phase_name(status_view.phase),
			game.encounter_kind_name(room.encounter_kind),
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
