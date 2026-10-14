package render

import "core:testing"
import game "../game"

// The icon atlas grew a fifth row (tools/art/build_card_icons.py): Movimento
// Ombra has its own icon there, every other card keeps its painted one, and
// the painted cells are cut where they always were.
@(test)
test_card_icons_add_a_row_without_moving_the_painted_cells :: proc(t: ^testing.T) {
	testing.expect_value(t, gothic_card_icon(.Shadow_Step), 16)
	for id in game.Card_Id {
		if id == .Count || id == .Shadow_Step { continue }
		testing.expect(t, gothic_card_icon(id) >= 0 && gothic_card_icon(id) < 16)
	}
	art: Gothic_Art
	testing.expect(t, 16 < CARD_ICON_CELLS && CARD_ICON_CELLS == len(art.icon_sources))
	// The atlas as embedded: its PNG header gives its size.
	png := #load("../../assets/gothic/card-icons-pixel.png")
	be32 :: proc(b: []u8) -> int { return int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3]) }
	testing.expect(t, len(png) > 24 && string(png[12:16]) == "IHDR")
	width, height := be32(png[16:20]), be32(png[20:24])
	painted := width
	testing.expect_value(t, height, (painted*CARD_ICON_ROWS+3)/4)
	for cell in 0..<16 {
		left, top, right, bottom := gothic_atlas_cell(cell, CARD_ICON_ROWS, width, height)
		old_left, old_top, old_right, old_bottom := gothic_atlas_cell(cell, 4, width, painted)
		testing.expect(t, left == old_left && top == old_top && right == old_right && bottom == old_bottom)
	}
	// The added cell sits wholly under the painted sheet.
	_, top, _, bottom := gothic_atlas_cell(16, CARD_ICON_ROWS, width, height)
	testing.expect(t, top == painted && bottom == height)
}
