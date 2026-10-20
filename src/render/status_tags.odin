package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

// Bruciatura and Rallentamento at a fighter's feet: little paper tags cut and
// inked like the hearts and the damage tokens (draw_paper_tag), each with its
// pixel pictogram and its stacks in the same pixel figures, in a row under
// the round markers of the older statuses (draw_status_set).

// 7 pixels wide, rows top to bottom, bit 6 the leftmost column: a flame and
// its bright core; an hourglass and the sand running through it.
@(rodata)
STATUS_TAG_FLAME := [7]u8{0b0001000, 0b0011000, 0b0011100, 0b0111110, 0b0111110, 0b0111110, 0b0011100}
@(rodata)
STATUS_TAG_FLAME_CORE := [7]u8{0b0000000, 0b0000000, 0b0001000, 0b0001000, 0b0011100, 0b0011100, 0b0001000}
@(rodata)
STATUS_TAG_HOURGLASS := [7]u8{0b1111111, 0b0100010, 0b0010100, 0b0001000, 0b0010100, 0b0100010, 0b1111111}
@(rodata)
STATUS_TAG_SAND := [7]u8{0b0000000, 0b0001000, 0b0001000, 0b0000000, 0b0001000, 0b0011100, 0b0000000}
STATUS_TAG_WIDTH :: 7
STATUS_TAG_EMBER :: rl.Color{198, 58, 34, 255}
STATUS_TAG_EMBER_CORE :: rl.Color{238, 168, 56, 255}
STATUS_TAG_FROST :: rl.Color{38, 88, 140, 255}
STATUS_TAG_FROST_SAND :: rl.Color{104, 164, 212, 255}
// Screen pixels between two tags of a row.
STATUS_TAG_GAP :: f32(3)
// The statuses shown as tags, in the row's order.
STATUS_TAG_KINDS :: [2]game.Status_Kind{.Burn, .Slow}

@(private)
status_tag_text :: proc(status: game.Status) -> string {
	return fmt.tprintf("%d", max(status.potency, 0))
}

// In tag pixels, as a heart's tag: the pictogram, a pixel of paper, the figures.
@(private)
status_tag_size :: proc(text: string) -> (width, height: int) {
	return living_heart_size(text)
}

// The tag with its top left at `at` (whole screen pixels), `pixel` screen
// pixels to a tag pixel. Its two colours never overlap, so a fading tag stays even.
@(private = "file")
draw_status_tag :: proc(at: rl.Vector2, kind: game.Status_Kind, text: string, pixel: f32, alpha: f32 = 1) {
	w, h := status_tag_size(text)
	ink := draw_paper_tag(at, w, h, pixel, alpha)
	shape, core := STATUS_TAG_HOURGLASS, STATUS_TAG_SAND
	dark, light := STATUS_TAG_FROST, STATUS_TAG_FROST_SAND
	if kind == .Burn {
		shape, core = STATUS_TAG_FLAME, STATUS_TAG_FLAME_CORE
		dark, light = STATUS_TAG_EMBER, STATUS_TAG_EMBER_CORE
	}
	for row in 0..<7 {
		y := at.y+f32(3+row)*pixel
		draw_pixel_row(shape[row]&~core[row], STATUS_TAG_WIDTH, at.x+3*pixel, y, pixel, color_with_opacity(dark, alpha))
		draw_pixel_row(core[row], STATUS_TAG_WIDTH, at.x+3*pixel, y, pixel, color_with_opacity(light, alpha))
	}
	draw_paper_tag_text(at, f32(3+STATUS_TAG_WIDTH+1), text, pixel, ink)
}

// The row of tags centred on `center` (the cell's centre on screen) with its
// top at `top`; its bounds, empty when the fighter has none of these statuses.
@(private)
draw_status_tags :: proc(statuses: ^game.Status_Set, center: rl.Vector2, top: f32, opacity: f32, pixel: f32 = 1) -> (bounds: rl.Rectangle) {
	shown: [len(STATUS_TAG_KINDS)]game.Status
	count := 0
	width := f32(0)
	for kind in STATUS_TAG_KINDS {
		index, found := game.status_index(statuses, kind)
		if !found { continue }
		shown[count] = statuses.items[index]
		w, _ := status_tag_size(status_tag_text(shown[count]))
		width += f32(w)*pixel+(STATUS_TAG_GAP if count > 0 else 0)
		count += 1
	}
	if count == 0 { return }
	_, h := status_tag_size("0")
	x := math.round(center.x-width*0.5)
	y := math.round(top)
	bounds = {x, y, width, f32(h)*pixel}
	for status in shown[:count] {
		text := status_tag_text(status)
		w, _ := status_tag_size(text)
		draw_status_tag({x, y}, status.kind, text, pixel, opacity)
		x += f32(w)*pixel+STATUS_TAG_GAP
	}
	return
}

// The ground lane a fighter's status glyphs keep at `feet` on screen: the
// round markers' square and the row of tags under it.
@(private)
tactical_status_lane :: proc(feet: view.Vec2, tags: rl.Rectangle) -> rl.Rectangle {
	lane := rl.Rectangle{feet.x-30, feet.y-18, 60, 36}
	if tags.width <= 0 { return lane }
	left, top := min(lane.x, tags.x), min(lane.y, tags.y)
	right, bottom := max(lane.x+lane.width, tags.x+tags.width), max(lane.y+lane.height, tags.y+tags.height)
	return {left, top, right-left, bottom-top}
}

// The tags' pixel at a figure's feet on the 3D board: doubled with the hearts
// (tactical_enemy_head), once a world unit there is LIVING_HEART_DOUBLE wide.
@(private)
tactical_status_tag_pixel :: proc(renderer: ^Renderer, position: view.Vec2) -> f32 {

	right := flipbook_camera_right(renderer)*0.5
	feet := view.Vec2{position.x+0.5, position.y+0.5}
	a := tactical_project(renderer, {feet.x-right.x, feet.y-right.z})
	b := tactical_project(renderer, {feet.x+right.x, feet.y+right.z})
	return 2 if math.hypot(b.x-a.x, b.y-a.y) >= LIVING_HEART_DOUBLE else 1
}
