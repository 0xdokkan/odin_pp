package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// FIRST PERSON ARCHER's bow (Fase 7, the user's choice: a compound bow with
// its pulleys), in the gloves' Neon style: a 3D model made from code, drawn on
// the gloves' small canvas so it gets their few flat tones, their ink and
// their paper. A carbon riser with a magenta neon stripe, its grip in the left
// glove; short stiff limbs back toward the eye from its ends to two cyan cams
// (the pulleys) with white hubs; the steel string between the cams' backs and
// a steel cable across; a sight box with a cyan pin over the grip and a
// stabiliser forward from under it, lit magenta at its end; the arrow on the
// string, a steel shaft with cyan fletching and a head the nocked arrow's
// colour, its point ahead past the riser; the right glove on the string. As
// the bow is drawn the string comes back toward the eye with the right hand,
// and the cams turn. The bow stands left of the crosshair, turned so that its
// arrow points at the crosshair's place far ahead, canted a little the way an
// archer holds it. FIRST_PERSON_COMPOUND_RIGHT (the user's choice, 2026-10-29)
// mirrors all of it across the view: the bow right of the crosshair, near
// where the right arm is, in the right glove, the left one on the string.

// How the bow is held (2026-10-29, the user: the hand drawing it did not feel
// right): `anchor` where a full draw brings the nock (the gloves' camera,
// metres; the real anchor is under the aiming eye, at the mouth's corner or
// the cheek), the riser on the arrow's line from it to the crosshair's place
// far ahead; the cant (radians) round that line, the size against the
// pieces' metres; the string's travel from BRACE and the arrow's length (the
// bow's units); lowered `rest_drop` metres and canted `rest_cant` more while
// not drawn, raised as it is drawn.
First_Person_Compound_Pose :: struct {
	anchor: rl.Vector3,
	cant, scale, draw, arrow, rest_drop, rest_cant: f32,
}
// The user's choice of three (2026-10-29): to the face, the bow canted beside
// the crosshair; drawn, the hand goes out of sight low by the cheek. (The
// first one, Fase 7, drew the string by the bow, far from the face: anchor
// {-0.196, -0.072, -0.38}, draw 0.24, arrow 0.62; the other, the bow nearly
// upright: anchor {-0.17, -0.10, -0.10}, cant -0.2.)
FIRST_PERSON_COMPOUND_POSE :: First_Person_Compound_Pose{
	anchor = {-0.14, -0.13, -0.10}, cant = -0.55, scale = 0.6, draw = 0.67, arrow = 0.95, rest_drop = 0.04, rest_cant = -0.25,
}
// Turned round its riser so the eye sees its side three quarters on (its limbs' and cams' profile).
FIRST_PERSON_COMPOUND_TURN :: f32(0)
FIRST_PERSON_COMPOUND_AIM :: f32(8)
FIRST_PERSON_COMPOUND_GLOVE :: f32(0.5)
// The string at rest, back from the riser (the bow's units, toward the eye).
FIRST_PERSON_COMPOUND_BRACE :: f32(0.16)
// The cams' place (up, back) and radius.
FIRST_PERSON_COMPOUND_CAM :: [2]f32{0.33, 0.14}
FIRST_PERSON_COMPOUND_CAM_RADIUS :: f32(0.042)

// The pose the bow is held in.
first_person_compound_pose :: proc() -> First_Person_Compound_Pose {
	return FIRST_PERSON_COMPOUND_POSE
}
// Held on the right: everything mirrored across the view.
FIRST_PERSON_COMPOUND_RIGHT :: true

First_Person_Compound_Shape :: enum u8 {Sphere, Cylinder, Cube}

// One piece of the bow in its frame (+Y up the riser, +Z back toward the eye,
// +X to its right): `at` its centre (a cylinder's foot), `size` (as the
// zweihänder's), turned `pitch` round X then `roll` round Z.
First_Person_Compound_Part :: struct {
	shape: First_Person_Compound_Shape,
	stuff: First_Person_Glove_Stuff,
	at, size: rl.Vector3,
	pitch, roll: f32,
}

@(rodata)
FIRST_PERSON_COMPOUND_PARTS := [?]First_Person_Compound_Part{
	// The riser: the grip, and its arms up and down, swept forward at their ends.
	{shape = .Cube, stuff = .Carbon, at = {0, 0, 0}, size = {0.034, 0.13, 0.044}},
	{shape = .Cube, stuff = .Carbon, at = {0, 0.17, -0.018}, size = {0.026, 0.24, 0.034}, pitch = 0.18},
	{shape = .Cube, stuff = .Carbon, at = {0, -0.17, -0.018}, size = {0.026, 0.24, 0.034}, pitch = -0.18},
	// Its magenta neon stripe down the front, and the grip's wrap.
	{shape = .Cube, stuff = .Neon, at = {0, 0.17, -0.037}, size = {0.012, 0.20, 0.006}, pitch = 0.18},
	{shape = .Cube, stuff = .Neon, at = {0, -0.17, -0.037}, size = {0.012, 0.20, 0.006}, pitch = -0.18},
	{shape = .Cube, stuff = .Wrap, at = {0, 0, 0.004}, size = {0.038, 0.10, 0.040}},
	// The limbs, back toward the eye to the cams.
	{shape = .Cube, stuff = .Carbon, at = {0, 0.31, 0.05}, size = {0.030, 0.022, 0.20}, pitch = -0.55},
	{shape = .Cube, stuff = .Carbon, at = {0, -0.31, 0.05}, size = {0.030, 0.022, 0.20}, pitch = 0.55},
	// The cams (their axles across), and their hubs.
	{shape = .Cylinder, stuff = .Cyan, at = {-0.010, 0.33, 0.14}, size = {0.042, 0.020, 0.042}, roll = math.PI/2},
	{shape = .Cylinder, stuff = .Cyan, at = {-0.010, -0.33, 0.14}, size = {0.042, 0.020, 0.042}, roll = math.PI/2},
	{shape = .Sphere, stuff = .White, at = {0, 0.33, 0.14}, size = {0.012, 0.012, 0.012}},
	{shape = .Sphere, stuff = .White, at = {0, -0.33, 0.14}, size = {0.012, 0.012, 0.012}},
	// The sight box over the grip, its cyan pin; the stabiliser forward from under it.
	{shape = .Cube, stuff = .Carbon, at = {0.032, 0.11, -0.01}, size = {0.012, 0.06, 0.05}},
	{shape = .Sphere, stuff = .Cyan, at = {0.040, 0.11, -0.01}, size = {0.007, 0.007, 0.007}},
	{shape = .Cylinder, stuff = .Carbon, at = {0, -0.075, -0.02}, size = {0.011, 0.26, 0.011}, pitch = -math.PI/2},
	{shape = .Sphere, stuff = .Neon, at = {0, -0.075, -0.28}, size = {0.02, 0.02, 0.02}},
}

// A cube from `a` to `b` (in a frame), `thick` across.
@(private = "file")
first_person_compound_rod :: proc(a, b: rl.Vector3, thick: f32) -> rl.Matrix {
	d := b-a
	length := rl.Vector3Length(d)
	if length < 1e-5 { return rl.MatrixScale(0, 0, 0) }
	y := d/length
	helper := rl.Vector3{1, 0, 0} if abs(y.x) < 0.9 else rl.Vector3{0, 0, 1}
	x := rl.Vector3Normalize(rl.Vector3CrossProduct(helper, y))
	z := rl.Vector3CrossProduct(x, y)
	mid := (a+b)*0.5
	frame := rl.Matrix{
		x.x, y.x, z.x, mid.x,
		x.y, y.y, z.y, mid.y,
		x.z, y.z, z.z, mid.z,
		0, 0, 0, 1,
	}
	return frame*rl.MatrixScale(thick, length, thick)
}

// Where the string holds the arrow's nock at `charge` (in the bow's frame): back toward the eye as it is drawn.
first_person_compound_nock :: proc(charge: f32) -> rl.Vector3 {
	return {0.012, 0, FIRST_PERSON_COMPOUND_BRACE+first_person_compound_pose().draw*clamp(charge, 0, 1)}
}

// The arrow's head on the string at `charge` (in the bow's frame).
first_person_compound_head :: proc(charge: f32) -> rl.Vector3 {
	return first_person_compound_nock(charge)+{0, 0, -first_person_compound_pose().arrow}
}

// The bow's frame in the gloves' camera, `lift` metres down as it comes in,
// `raise` (0..1) from its rest to its aim.
first_person_compound_matrix :: proc(lift: f32, raise := f32(1)) -> rl.Matrix {
	pose := first_person_compound_pose()
	r := clamp(raise, 0, 1)
	anchor := pose.anchor-{0, lift+pose.rest_drop*(1-r), 0}
	forward := rl.Vector3Normalize(rl.Vector3{0, 0, -FIRST_PERSON_COMPOUND_AIM}-anchor)
	// The riser on the arrow's line, a full draw ahead of the anchor.
	grip := anchor+forward*(FIRST_PERSON_COMPOUND_BRACE+pose.draw)*pose.scale
	back := -forward
	up := rl.Vector3Normalize(rl.Vector3{0, 1, 0}-back*rl.Vector3DotProduct({0, 1, 0}, back))
	right := rl.Vector3CrossProduct(up, back)
	// The cant: up turned round the arrow's line.
	cant := pose.cant+pose.rest_cant*(1-r)
	c, s := math.cos(cant), math.sin(cant)
	up, right = up*c+right*s, right*c-up*s
	// Three quarters on: the bow turned round its riser, its arrow kept on the crosshair's line.
	ct, st := math.cos(FIRST_PERSON_COMPOUND_TURN), math.sin(FIRST_PERSON_COMPOUND_TURN)
	back, right = back*ct+right*st, right*ct-back*st
	frame := rl.Matrix{
		right.x, up.x, back.x, grip.x,
		right.y, up.y, back.y, grip.y,
		right.z, up.z, back.z, grip.z,
		0, 0, 0, 1,
	}
	k := pose.scale
	when FIRST_PERSON_COMPOUND_RIGHT { return rl.MatrixScale(-1, 1, 1)*frame*rl.MatrixScale(k, k, k) }
	return frame*rl.MatrixScale(k, k, k)
}

// A piece's matrix in the bow's frame, `grow` metres fuller on every side.
@(private = "file")
first_person_compound_part_frame :: proc(part: First_Person_Compound_Part, grow: f32) -> rl.Matrix {
	place := rl.MatrixTranslate(part.at.x, part.at.y, part.at.z)*rl.MatrixRotateX(part.pitch)*rl.MatrixRotateZ(part.roll)
	switch part.shape {
	case .Cylinder:
		return place*rl.MatrixTranslate(0, -grow, 0)*rl.MatrixScale(part.size.x+grow, part.size.y+grow*2, part.size.z+grow)
	case .Cube:
		return place*rl.MatrixScale(part.size.x+grow*2, part.size.y+grow*2, part.size.z+grow*2)
	case .Sphere:
	}
	return place*rl.MatrixScale(part.size.x+grow, part.size.y+grow, part.size.z+grow)
}

// The bow's fixed pieces baked into one mesh in its frame (`grow` metres fuller
// on every side: the ink's shell), each vertex's stuff in its colour's red, so
// that they draw at once (first_person_compound_kit). raylib frees it: its
// arrays come from raylib's allocator.
@(private = "file")
first_person_compound_bake :: proc(kit: ^First_Person_Glove_Kit, grow: f32) -> rl.Mesh {
	total := 0
	shapes := [First_Person_Compound_Shape]rl.Mesh{.Sphere = kit.sphere, .Cylinder = kit.cylinder, .Cube = kit.cube}
	count :: proc(m: rl.Mesh) -> int { return int(m.triangleCount)*3 }
	for part in FIRST_PERSON_COMPOUND_PARTS { total += count(shapes[part.shape]) }
	mesh: rl.Mesh
	mesh.vertexCount, mesh.triangleCount = c.int(total), c.int(total/3)
	mesh.vertices = cast([^]f32)rl.MemAlloc(c.uint(total*3*size_of(f32)))
	mesh.normals = cast([^]f32)rl.MemAlloc(c.uint(total*3*size_of(f32)))
	mesh.colors = cast([^]u8)rl.MemAlloc(c.uint(total*4))
	at := 0
	for part in FIRST_PERSON_COMPOUND_PARTS {
		source := shapes[part.shape]
		m := first_person_compound_part_frame(part, grow)
		n := rl.MatrixTranspose(rl.MatrixInvert(m))
		for k in 0..<count(source) {
			index := int(source.indices[k]) if source.indices != nil else k
			p := m*[4]f32{source.vertices[index*3], source.vertices[index*3+1], source.vertices[index*3+2], 1}
			q := n*[4]f32{source.normals[index*3], source.normals[index*3+1], source.normals[index*3+2], 0}
			normal := rl.Vector3Normalize(q.xyz)
			mesh.vertices[at*3], mesh.vertices[at*3+1], mesh.vertices[at*3+2] = p.x, p.y, p.z
			mesh.normals[at*3], mesh.normals[at*3+1], mesh.normals[at*3+2] = normal.x, normal.y, normal.z
			mesh.colors[at*4], mesh.colors[at*4+1], mesh.colors[at*4+2], mesh.colors[at*4+3] = u8(part.stuff), 0, 0, 255
			at += 1
		}
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

// The bow's shapes, the first time it is drawn.
@(private = "file")
first_person_compound_kit :: proc(kit: ^First_Person_Glove_Kit) -> bool {
	if kit.shader.id == 0 { return false }
	if kit.cube.vaoId == 0 { kit.cube = rl.GenMeshCube(1, 1, 1) }
	if kit.compound.vaoId == 0 {
		kit.compound = first_person_compound_bake(kit, 0)
		kit.compound_ink = first_person_compound_bake(kit, FIRST_PERSON_GLOVE_INK)
	}
	return kit.compound.vaoId != 0 && kit.compound_ink.vaoId != 0
}

// A glove in the bow's frame at `at` with its forearm back along `back` and
// its fist's way through it along `along`, mirrored for the right.
@(private = "file")
first_person_compound_glove :: proc(bow: rl.Matrix, at, along, back: rl.Vector3, left: bool) -> rl.Matrix {
	b := rl.Vector3Normalize(back)
	a := rl.Vector3Normalize(along-b*rl.Vector3DotProduct(along, b))
	x := a if left else -a
	y := rl.Vector3CrossProduct(b, x)
	s := FIRST_PERSON_COMPOUND_GLOVE
	local := rl.Matrix{
		x.x, y.x, b.x, at.x,
		x.y, y.y, b.y, at.y,
		x.z, y.z, b.z, at.z,
		0, 0, 0, 1,
	}
	return bow*local*rl.MatrixScale(s, s, s)
}

// The bow, its string, arrow and both gloves, in the gloves' camera, on the
// small canvas bound now.
@(private)
draw_first_person_compound :: proc(renderer: ^Renderer, kit: ^First_Person_Glove_Kit, ready: f32) {
	if !first_person_compound_kit(kit) { return }
	v := &renderer.tactical.first_person.bow
	bow := first_person_compound_matrix((1-ready)*0.32, v.raise)
	charge := clamp(v.charge, 0, 1) if v.drawing else 0
	nock := first_person_compound_nock(charge)
	cam_back := FIRST_PERSON_COMPOUND_CAM.y+FIRST_PERSON_COMPOUND_CAM_RADIUS
	top := rl.Vector3{0, FIRST_PERSON_COMPOUND_CAM.x, cam_back}
	bottom := rl.Vector3{0, -FIRST_PERSON_COMPOUND_CAM.x, cam_back}
	// The arrow from the string forward along the riser's side.
	tail := nock
	head := first_person_compound_head(charge)
	tint := FIRST_PERSON_BOW_COLORS[v.queue[0]]
	tint_value := [3]f32{f32(tint.r)/255, f32(tint.g)/255, f32(tint.b)/255}
	camera := first_person_glove_camera()
	maps: [12]rl.MaterialMap
	material := rl.Material{shader = kit.shader, maps = raw_data(maps[:])}
	none := f32(99)
	rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.tint_location), &tint_value, .VEC3)
	rl.BeginMode3D(camera)
	rlgl.EnableBackfaceCulling()
	put :: proc(kit: ^First_Person_Glove_Kit, material: rl.Material, mesh: rl.Mesh, stuff: First_Person_Glove_Stuff, at: rl.Matrix) {
		value := f32(stuff)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.stuff_location), &value, .FLOAT)
		rl.DrawMesh(mesh, material, at)
	}
	// Mirrored, the faces turn the other way round.
	ink_face, face := rlgl.CullMode.FRONT, rlgl.CullMode.BACK
	when FIRST_PERSON_COMPOUND_RIGHT { ink_face, face = .BACK, .FRONT }
	for pass in 0..<2 {
		ink := f32(1 if pass == 0 else 0)
		rlgl.SetCullFace(ink_face if pass == 0 else face)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.ink_location), &ink, .FLOAT)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &none, .FLOAT)
		grow := FIRST_PERSON_GLOVE_INK if pass == 0 else 0
		// The fixed pieces at once, each vertex with its own stuff (a stuff below zero).
		baked := f32(-1)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.stuff_location), &baked, .FLOAT)
		rl.DrawMesh(kit.compound_ink if pass == 0 else kit.compound, material, bow)
		// The string from the cams to the nock, and a cable across.
		put(kit, material, kit.cube, .Steel, bow*first_person_compound_rod(top, nock, 0.004+grow*2))
		put(kit, material, kit.cube, .Steel, bow*first_person_compound_rod(nock, bottom, 0.004+grow*2))
		put(kit, material, kit.cube, .Steel, bow*first_person_compound_rod({0, 0.31, 0.10}, {0.008, -0.30, 0.12}, 0.003+grow*2))
		// The arrow: its shaft, fletching and head.
		put(kit, material, kit.cube, .Steel, bow*first_person_compound_rod(tail, head, 0.008+grow*2))
		put(kit, material, kit.cube, .Cyan, bow*first_person_compound_rod(tail+{0, 0, -0.02}, tail+{0, 0, -0.09}, 0.02+grow*2))
		put(kit, material, kit.cube, .Tint, bow*first_person_compound_rod(head+{0, 0, 0.035}, head, 0.022+grow*2))
		// The gloves: the left round the grip, its forearm back to the left
		// shoulder; the right on the string, back to the right (mirrored when
		// held on the right: the right round the grip).
		gloves := [2]rl.Matrix{
			first_person_compound_glove(bow, {-0.004, 0.0, 0.03}, {0, 1, 0}, {-0.30, -0.25, 1}, true),
			first_person_compound_glove(bow, nock+{0.03, -0.01, 0.02}, {0, 1, 0}, {0.6, -0.35, 1}, false),
		}
		for side in 0..<2 {
			for part, index in FIRST_PERSON_GLOVE_PARTS {
				piece := f32(index)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &piece, .FLOAT)
				put(kit, material, kit.cylinder if part.cylinder else kit.sphere, part.stuff, gloves[side]*first_person_glove_part_frame(part, side == 0, grow))
			}
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &none, .FLOAT)
		}
	}
	rlgl.SetCullFace(.BACK)
	rl.EndMode3D()
}
