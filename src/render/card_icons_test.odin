package render

import "core:c"
import "core:testing"
import rl "vendor:raylib"
import game "../game"

// The icon atlas grew five rows (tools/art/build_card_icons.py): Movimento
// Ombra, the cards of Phase 2, the Lazzo, the Canna da Pesca, the Pinball, the
// First Person Shooter, Bomb Marley, Inondazione, the Cannone, the Cannone
// laser, the Buco nero and the Dinosauro have their own icons there, every
// other card keeps its painted one, and the painted cells are cut where they
// always were.
@(test)
test_card_icons_add_rows_without_moving_the_painted_cells :: proc(t: ^testing.T) {
	added := [?]game.Card_Id{.Shadow_Step, .Poison_Pool, .Wildfire, .Deflect, .Coffin, .Fate_Dice, .Venom_Blade, .Lasso, .Fishing_Rod,
		.Pinball, .First_Person, .Marley_Party, .Flood_Wave, .Field_Cannon, .Laser_Cannon, .Devouring_Hole, .Dino_Ride,
		.First_Person_Brawler}
	for id, index in added { testing.expect_value(t, gothic_card_icon(id), 16+index) }
	for id in game.Card_Id {
		own := id == .Count
		for card in added { own = own || card == id }
		if own { continue }
		testing.expect(t, gothic_card_icon(id) >= 0 && gothic_card_icon(id) < 16)
	}
	art: Gothic_Art
	testing.expect(t, 16+len(added) <= CARD_ICON_CELLS && CARD_ICON_CELLS == len(art.icon_sources))
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
	// The added cells sit wholly under the painted sheet, the first right
	// under it and the last row down to the atlas's bottom.
	for cell in 16..<CARD_ICON_CELLS {
		_, top, _, bottom := gothic_atlas_cell(cell, CARD_ICON_ROWS, width, height)
		testing.expect(t, top >= painted && bottom <= height && bottom-top >= 313)
	}
	_, first, _, _ := gothic_atlas_cell(16, CARD_ICON_ROWS, width, height)
	_, _, _, last := gothic_atlas_cell(CARD_ICON_CELLS-1, CARD_ICON_ROWS, width, height)
	testing.expect(t, first == painted && last == height)
	// Every added icon is painted in its cell (the loader cuts it from what
	// is opaque there); the cell after the last stays empty.
	image := rl.LoadImageFromMemory(".png", raw_data(png), c.int(len(png)))
	defer rl.UnloadImage(image)
	if !testing.expect(t, image.data != nil && int(image.width) == width && int(image.height) == height) { return }
	colors := rl.LoadImageColors(image)
	defer rl.UnloadImageColors(colors)
	for cell in 16..<CARD_ICON_CELLS {
		left, top, right, bottom := gothic_atlas_cell(cell, CARD_ICON_ROWS, width, height)
		opaque := 0
		for y in top..<bottom { for x in left..<right { if colors[y*width+x].a > 32 { opaque += 1 } } }
		testing.expectf(t, (opaque > 0) == (cell < 16+len(added)), "cell %d: %d opaque pixels", cell, opaque)
	}
}
