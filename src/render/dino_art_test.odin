package render

import "core:testing"
import rl "vendor:raylib"

dino_art_opaque :: proc(pixels: ^[DINO_ART_W*DINO_ART_H]rl.Color) -> (count: int) {
	for pixel in pixels { if pixel.a > 0 { count += 1 } }
	return
}

// Every dinosaur of both frames is drawn on the shared canvas: its rows are
// whole, every letter is a colour of the palette, every pixel is opaque or
// transparent (never half), the dinosaur stands on the bottom rows and keeps
// the ink outline's room (a pixel's width) on the top row.
@(test)
test_dino_art_fills_the_shared_canvas :: proc(t: ^testing.T) {
	for kind in Dino_Art {
		for frame in 0..<DINO_ART_FRAMES {
			for row, y in DINO_ART_ROWS[kind][frame] {
				testing.expectf(t, len(row) == DINO_ART_W, "%v frame %d row %d is %d wide", kind, frame, y, len(row))
				for letter in transmute([]u8)row {
					testing.expectf(t, letter == '.' || dino_art_color(letter).a == 255, "%v frame %d row %d: letter %c", kind, frame, y, letter)
				}
			}
			pixels := dino_art_pixels(kind, frame)
			opaque := dino_art_opaque(&pixels)
			testing.expectf(t, opaque > 300, "%v frame %d has %d opaque pixels", kind, frame, opaque)
			for pixel in pixels { testing.expect(t, pixel.a == 0 || pixel.a == 255) }
			feet, top := 0, 0
			for x in 0..<DINO_ART_W {
				if pixels[(DINO_ART_H-2)*DINO_ART_W+x].a > 0 { feet += 1 }
				if pixels[x].a > 0 { top += 1 }
			}
			testing.expectf(t, feet > 0, "%v frame %d does not stand on the bottom rows", kind, frame)
			testing.expectf(t, top == 0, "%v frame %d touches the top edge", kind, frame)
		}
	}
}

// The rider's seat is on the saddle: opaque (or the pixel below it is) on both
// frames, once the back has risen by the frame's bob.
@(test)
test_dino_art_seat_is_on_the_back :: proc(t: ^testing.T) {
	for kind in Dino_Art {
		seat := DINO_ART_SEAT[kind]
		testing.expectf(t, seat.x >= 0 && seat.x < DINO_ART_W && seat.y >= 0 && seat.y+1 < DINO_ART_H, "%v: seat %v is off the canvas", kind, seat)
		for frame in 0..<DINO_ART_FRAMES {
			pixels := dino_art_pixels(kind, frame)
			bob := DINO_ART_BOB[kind][frame]
			testing.expectf(t, bob >= 0 && bob <= 2, "%v frame %d bobs %d rows", kind, frame, bob)
			at := (seat.y-bob)*DINO_ART_W + seat.x
			testing.expectf(t, pixels[at].a > 0 || pixels[at+DINO_ART_W].a > 0, "%v frame %d: nothing under the seat %v", kind, frame, seat)
			// The saddle is its leather: reddish and darker than the body's top.
			testing.expectf(t, pixels[at].a > 0 && pixels[at].r > pixels[at].b, "%v frame %d: the seat is not on the saddle", kind, frame)
		}
	}
}

// The walk cycle: the two frames of a dinosaur differ (legs and tail), and
// the four dinosaurs differ from one another.
@(test)
test_dino_art_frames_and_kinds_differ :: proc(t: ^testing.T) {
	for kind in Dino_Art {
		a, b := dino_art_pixels(kind, 0), dino_art_pixels(kind, 1)
		differing := 0
		for i in 0..<len(a) { if a[i] != b[i] { differing += 1 } }
		testing.expectf(t, differing > 30, "%v: the two frames differ by %d pixels", kind, differing)
	}
	for first in Dino_Art {
		for second in Dino_Art {
			if first >= second { continue }
			a, b := dino_art_pixels(first, 0), dino_art_pixels(second, 0)
			differing := 0
			for i in 0..<len(a) { if a[i] != b[i] { differing += 1 } }
			testing.expectf(t, differing > 300, "%v and %v differ by %d pixels", first, second, differing)
		}
	}
}

// The giant is the biggest of them.
@(test)
test_dino_art_giga_is_the_biggest :: proc(t: ^testing.T) {
	counts: [Dino_Art]int
	for kind in Dino_Art {
		pixels := dino_art_pixels(kind, 0)
		counts[kind] = dino_art_opaque(&pixels)
	}
	for kind in Dino_Art {
		if kind == .Giga { continue }
		testing.expectf(t, counts[.Giga] > counts[kind], "Giga has %d opaque pixels, %v has %d", counts[.Giga], kind, counts[kind])
	}
}
