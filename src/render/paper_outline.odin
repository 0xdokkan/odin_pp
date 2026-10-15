package render

@(private)
Paper_Outline_Layer :: enum u8 {Clear, Print, Ink, Paper, Cut}

// Grow one ring from the previous mask, never from texels added in this pass.
// Callers supply reusable stack scratch space; palettes and print formats stay
// with each drawing. Diagonal ink/cut rings and alternating paper rings share
// this same dilation.
@(private)
paper_outline_grow :: proc(layers, staged: []Paper_Outline_Layer, w, h: int, into: Paper_Outline_Layer, diagonal: bool) {
	copy(staged, layers)
	for y in 0..<h {
		for x in 0..<w {
			if layers[y*w+x] != .Clear { continue }
			near: for dy in -1..=1 {
				for dx in -1..=1 {
					if (dx == 0 && dy == 0) || (!diagonal && dx != 0 && dy != 0) { continue }
					xx, yy := x+dx, y+dy
					if xx < 0 || yy < 0 || xx >= w || yy >= h || layers[yy*w+xx] == .Clear { continue }
					staged[y*w+x] = into
					break near
				}
			}
		}
	}
	copy(layers, staged)
}
