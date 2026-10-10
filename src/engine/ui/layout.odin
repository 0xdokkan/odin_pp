// Immediate-mode interface shared by menus, HUDs and minigames.
//
// Widgets are called every frame; they read pointer and navigation input,
// return what happened, and append draw commands. `render` executes the
// commands with raylib. Interaction and layout never touch the GPU, so menus
// can be driven in tests.
package ui

import "core:math"
import rl "vendor:raylib"

Rect :: rl.Rectangle

HUD_MARGIN :: 14
HUD_GAP :: 10
HUD_TOP_HEIGHT :: 66

// Shared dock: vitals, current objective, then score/progress. Keeping the
// positions stable makes switching between the game's activities predictable.
hud_columns :: proc(canvas: Rect) -> [3]Rect {
	width := max(canvas.width - 2*HUD_MARGIN - 2*HUD_GAP, 0)
	left := math.floor(width*0.32)
	middle := math.floor(width*0.36)
	x, y := canvas.x + HUD_MARGIN, canvas.y + HUD_MARGIN
	return {
		{x, y, left, HUD_TOP_HEIGHT},
		{x + left + HUD_GAP, y, middle, HUD_TOP_HEIGHT},
		{x + left + middle + 2*HUD_GAP, y, width-left-middle, HUD_TOP_HEIGHT},
	}
}

// Rect-cut layout: each cut removes a strip from `r` and returns it.
cut_top :: proc(r: ^Rect, amount: f32) -> Rect {
	a := min(amount, r.height)
	out := Rect{r.x, r.y, r.width, a}
	r.y += a
	r.height -= a
	return out
}

cut_bottom :: proc(r: ^Rect, amount: f32) -> Rect {
	a := min(amount, r.height)
	r.height -= a
	return Rect{r.x, r.y + r.height, r.width, a}
}

cut_left :: proc(r: ^Rect, amount: f32) -> Rect {
	a := min(amount, r.width)
	out := Rect{r.x, r.y, a, r.height}
	r.x += a
	r.width -= a
	return out
}

cut_right :: proc(r: ^Rect, amount: f32) -> Rect {
	a := min(amount, r.width)
	r.width -= a
	return Rect{r.x + r.width, r.y, a, r.height}
}

shrink :: proc(r: Rect, amount: f32) -> Rect {
	return Rect{r.x + amount, r.y + amount, max(r.width-2*amount, 0), max(r.height-2*amount, 0)}
}

shrink_xy :: proc(r: Rect, dx, dy: f32) -> Rect {
	return Rect{r.x + dx, r.y + dy, max(r.width-2*dx, 0), max(r.height-2*dy, 0)}
}

// Rectangle of the given size centred inside `r`.
center :: proc(r: Rect, width, height: f32) -> Rect {
	return Rect{r.x + (r.width-width)*0.5, r.y + (r.height-height)*0.5, width, height}
}

// Cell `index` of `count` equal columns separated by `gap`.
column :: proc(r: Rect, count, index: int, gap: f32 = 0) -> Rect {
	if count <= 0 {
		return r
	}
	w := (r.width - gap*f32(count-1)) / f32(count)
	return Rect{r.x + f32(index)*(w+gap), r.y, w, r.height}
}

// Row `index` of `count` equal rows separated by `gap`.
row :: proc(r: Rect, count, index: int, gap: f32 = 0) -> Rect {
	if count <= 0 {
		return r
	}
	h := (r.height - gap*f32(count-1)) / f32(count)
	return Rect{r.x, r.y + f32(index)*(h+gap), r.width, h}
}

// Grid cell, row-major; `columns` cells per row.
cell :: proc(r: Rect, columns, rows, index: int, gap: f32 = 0) -> Rect {
	if columns <= 0 || rows <= 0 {
		return r
	}
	return column(row(r, rows, index/columns, gap), columns, index%columns, gap)
}

// `count` items of fixed width centred in a row, as menus and card hands use.
centered_item :: proc(r: Rect, count, index: int, item_width, gap: f32) -> Rect {
	total := f32(count)*item_width + f32(max(count-1, 0))*gap
	x := r.x + (r.width-total)*0.5 + f32(index)*(item_width+gap)
	return Rect{x, r.y, item_width, r.height}
}

contains :: proc(r: Rect, p: [2]f32) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x+r.width && p.y < r.y+r.height
}
