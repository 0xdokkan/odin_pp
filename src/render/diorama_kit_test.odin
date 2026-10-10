package render

import "core:testing"
import rl "vendor:raylib"

@(test)
test_diorama_kit_pieces_fit_their_cell :: proc(t: ^testing.T) {
	kit: Diorama_Kit
	defer destroy_diorama_kit(&kit)
	testing.expect(t, load_diorama_kit(&kit, DIORAMA_KIT_BYTES))
	for piece in Diorama_Piece {
		vertices := kit.pieces[piece]
		testing.expect(t, len(vertices) > 0 && len(vertices)%3 == 0)
		for vertex in vertices {
			p := vertex.position
			testing.expect(t, abs(rl.Vector3Length(vertex.normal)-1) < 0.01)
			if piece == .Sconce {
				// Hung from the face, around the lamp light it marks.
				testing.expect(t, rl.Vector3Length(p) < 0.4)
				continue
			}
			// Decoration stays inside the tile volume and the 1.8 cull radius.
			testing.expect(t, abs(p.x) <= 0.5001 && abs(p.z) <= 0.5001)
			testing.expect(t, p.y >= -0.0001 && p.y <= 1.8)
		}
	}
	// Faces are authored toward +Z, between the core and the cell edge.
	for piece in ([4]Diorama_Piece{.Face_Lancet, .Face_Buttress, .Face_Rose, .Face_Ashlar}) {
		for vertex in kit.pieces[piece] { testing.expect(t, vertex.position.z >= 0.399) }
	}
	testing.expect(t, !load_diorama_kit(&kit, []u8{'O', 'D', 'M', '0', 0, 0, 0, 0}))
}

@(test)
test_diorama_turns_map_the_authored_face_to_each_side :: proc(t: ^testing.T) {
	for offset, side in DIORAMA_SIDES {
		turned := diorama_turn({0, 0.5, 1}, side)
		testing.expect_value(t, turned, rl.Vector3{f32(offset.x), 0.5, f32(offset.y)})
	}
}
