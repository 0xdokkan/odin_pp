package render

import "core:c"
import "core:encoding/endian"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The gothic wall kit modelled in Blender (tools/art/build_walls.py). Pieces
// are world-scale triangle lists with vertex colours, authored facing +Z and
// turned toward each side here, then submitted through the same resin shader
// as every other board block. Parsing needs no GL, so tests use it too.

DIORAMA_KIT_BYTES := #load("../../assets/models/gothic-walls.odm")

Diorama_Piece :: enum u8 {
	Core, Link, Post, Pilaster,
	Face_Lancet, Face_Buttress, Face_Rose, Face_Ashlar,
	Merlons, Cap, Cut_Cap, Sconce,
}

DIORAMA_PIECE_NAMES := [Diorama_Piece]string{
	.Core = "core", .Link = "link", .Post = "post", .Pilaster = "pilaster",
	.Face_Lancet = "face_lancet", .Face_Buttress = "face_buttress", .Face_Rose = "face_rose",
	.Face_Ashlar = "face_ashlar", .Merlons = "merlons", .Cap = "cap", .Cut_Cap = "cut_cap", .Sconce = "sconce",
}

// Grid +y, +x, -y, -x: the order of the board's neighbour scans.
@(rodata)
DIORAMA_SIDES := [4]grid.Position{{x = 0, y = 1}, {x = 1, y = 0}, {x = 0, y = -1}, {x = -1, y = 0}}

Diorama_Vertex :: struct {
	position, normal: rl.Vector3,
	color: [4]u8,
}

Diorama_Kit :: struct {
	vertices: []Diorama_Vertex,
	pieces: [Diorama_Piece][]Diorama_Vertex,
	loaded: bool,
}

DIORAMA_ODM_VERTEX_SIZE :: 20

// Every vertex of an ODM file (see tools/art/build_walls.py), unsplit.
@(private)
load_odm_vertices :: proc(bytes: []u8) -> (vertices: []Diorama_Vertex, ok: bool) {
	if len(bytes) < 8 || string(bytes[:4]) != "ODM1" { return }
	piece_count, _ := endian.get_u32(bytes[4:], .Little)
	vertex_header := 8+int(piece_count)*32
	if vertex_header+4 > len(bytes) { return }
	total, _ := endian.get_u32(bytes[vertex_header:], .Little)
	data := vertex_header+4
	if data+int(total)*DIORAMA_ODM_VERTEX_SIZE > len(bytes) { return }
	vertices = make([]Diorama_Vertex, int(total))
	for &vertex, index in vertices {
		at := data+index*DIORAMA_ODM_VERTEX_SIZE
		x, _ := endian.get_f32(bytes[at:], .Little)
		y, _ := endian.get_f32(bytes[at+4:], .Little)
		z, _ := endian.get_f32(bytes[at+8:], .Little)
		vertex.position = {x, y, z}
		vertex.normal = rl.Vector3Normalize({f32(i8(bytes[at+12])), f32(i8(bytes[at+13])), f32(i8(bytes[at+14]))})
		vertex.color = {bytes[at+16], bytes[at+17], bytes[at+18], bytes[at+19]}
	}
	return vertices, true
}

@(private)
load_diorama_kit :: proc(kit: ^Diorama_Kit, bytes: []u8) -> bool {
	destroy_diorama_kit(kit)
	vertices, ok := load_odm_vertices(bytes)
	if !ok { return false }
	kit.vertices = vertices
	piece_count, _ := endian.get_u32(bytes[4:], .Little)
	table := 8
	total := len(vertices)
	found := 0
	for entry in 0..<int(piece_count) {
		at := table+entry*32
		name_end := at
		for name_end < at+24 && bytes[name_end] != 0 { name_end += 1 }
		name := string(bytes[at:name_end])
		first, _ := endian.get_u32(bytes[at+24:], .Little)
		count, _ := endian.get_u32(bytes[at+28:], .Little)
		if int(first)+int(count) > total || count%3 != 0 { continue }
		for piece in Diorama_Piece {
			if DIORAMA_PIECE_NAMES[piece] == name {
				kit.pieces[piece] = kit.vertices[int(first):int(first+count)]
				found += 1
			}
		}
	}
	kit.loaded = found == len(Diorama_Piece)
	return kit.loaded
}

@(private)
destroy_diorama_kit :: proc(kit: ^Diorama_Kit) {
	delete(kit.vertices)
	kit^ = {}
}

// Quarter turns taking the authored +Z face to the given side.
@(private)
diorama_turn :: proc(v: rl.Vector3, side: int) -> rl.Vector3 {
	switch side & 3 {
	case 1: return {v.z, v.y, -v.x}
	case 2: return {-v.x, v.y, -v.z}
	case 3: return {-v.z, v.y, v.x}
	}
	return v
}

// `clip` flattens everything above it onto the cut (a retracted near wall);
// triangles wholly above it are skipped. `brighten` lifts the dark resin for
// the translucent shells, whose `alpha` replaces the opaque vertex alpha.
@(private)
draw_diorama_piece :: proc(kit: ^Diorama_Kit, piece: Diorama_Piece, origin: rl.Vector3, side: int,
	clip: f32 = 1e9, brighten: f32 = 1, alpha: u8 = 255) {
	vertices := kit.pieces[piece]
	if len(vertices) == 0 { return }
	rlgl.CheckRenderBatchLimit(c.int(len(vertices)))
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for first := 0; first+2 < len(vertices); first += 3 {
		triangle := vertices[first:first+3]
		if origin.y+triangle[0].position.y >= clip && origin.y+triangle[1].position.y >= clip &&
		   origin.y+triangle[2].position.y >= clip { continue }
		for vertex in triangle {
			p := diorama_turn(vertex.position, side)
			n := diorama_turn(vertex.normal, side)
			color := vertex.color
			if brighten != 1 {
				for channel in 0..<3 { color[channel] = u8(min(f32(255), f32(color[channel])*brighten)) }
			}
			rlgl.Color4ub(color[0], color[1], color[2], alpha)
			rlgl.Normal3f(n.x, n.y, n.z)
			rlgl.TexCoord2f(0, 0)
			rlgl.Vertex3f(origin.x+p.x, min(origin.y+p.y, clip), origin.z+p.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

@(private = "file")
diorama_neighbour_is_wall :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	tile, found := level.tile_at(room.level_data, cell)
	// Beyond the border the mass simply continues: no carved outer faces.
	return !found || tile.kind == .Wall || tile.kind == .Void
}

// A deterministic face per wall side, weighted toward plain coursed stone.
@(private = "file")
diorama_face_piece :: proc(cell: grid.Position, side: int) -> Diorama_Piece {
	switch gothic_hash(cell.x*4+side, cell.y*3+side)%20 {
	case 0..=7: return .Face_Ashlar
	case 8..=12: return .Face_Lancet
	case 13..=16: return .Face_Buttress
	}
	return .Face_Rose
}

// Mirrors diorama_lamp: the side its sconce hangs on, or -1.
@(private = "file")
diorama_lamp_side :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) -> int {
	if _, found := diorama_lamp(renderer, room, cell); !found { return -1 }
	for offset, side in DIORAMA_SIDES {
		if tactical_render_visible(renderer, grid.offset(cell, offset.x, offset.y)) && diorama_wall_face(room, cell, offset) { return side }
	}
	return -1
}

@(private)
draw_diorama_kit_wall :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) {
	kit := &renderer.tactical.kit
	origin := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	h := diorama_wall_height(renderer, room, cell)
	// Behind the player's eyes an inner wall thickens over the dive, then is
	// opaque, drawn with the floor (first_person.odin).
	transparent := diorama_interior_wall(room, cell) && !first_person_solid_walls(renderer)
	brighten, alpha := f32(1), u8(255)
	if transparent {
		ramp := first_person_wall_ramp(renderer)
		brighten, alpha = 2.2+(1-2.2)*ramp, u8(52+(255-52)*ramp)
	}
	cut := h < DIORAMA_WALL_HEIGHT-0.001
	lamp_side := diorama_lamp_side(renderer, room, cell)
	exposed: [4]bool
	to_camera := renderer.tactical.camera.position-origin
	for offset, side in DIORAMA_SIDES {
		neighbour := grid.offset(cell, offset.x, offset.y)
		exposed[side] = !diorama_neighbour_is_wall(room, neighbour)
		normal := rl.Vector3{f32(offset.x), 0, f32(offset.y)}
		// A translucent shell shows only its camera-facing relief: stacked
		// back layers would darken it.
		facing := rl.Vector3DotProduct(normal, to_camera-normal*0.45) > 0
		if transparent && !facing { continue }
		piece := Diorama_Piece.Link
		if exposed[side] && tactical_render_visible(renderer, neighbour) && diorama_wall_face(room, cell, offset) {
			piece = .Face_Ashlar if side == lamp_side else diorama_face_piece(cell, side)
		}
		draw_diorama_piece(kit, piece, origin, side, h, brighten, alpha)
		if exposed[side] && !cut && !transparent { draw_diorama_piece(kit, .Merlons, origin, side) }
	}
	for side in 0..<4 {
		corner := Diorama_Piece.Pilaster if exposed[side] && exposed[(side+1)%4] else Diorama_Piece.Post
		draw_diorama_piece(kit, corner, origin, side, h, brighten, alpha)
	}
	draw_diorama_piece(kit, .Core, origin, 0, h, brighten, alpha)
	top := Diorama_Piece.Cut_Cap if cut else Diorama_Piece.Cap
	draw_diorama_piece(kit, top, origin+rl.Vector3{0, h, 0}, 0, 1e9, 1.5 if transparent else 1, alpha)
	if lamp_side >= 0 {
		if lamp, found := diorama_lamp(renderer, room, cell); found {
			draw_diorama_piece(kit, .Sconce, lamp, lamp_side, 1e9, brighten, alpha)
			if transparent { draw_diorama_lamp_glow(renderer, lamp, cell, 0.25) }
		}
	}
}
