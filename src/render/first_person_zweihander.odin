package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// FIRST PERSON FENCER's sword (Fase 5, the user's choice: «zweihänder versione
// cibernetica e maestosa»): a two-handed great sword in the gloves' Neon style,
// a 3D model made from code and drawn on the gloves' small canvas, so it gets
// their few flat tones, their ink and their paper. A long steel blade of a
// diamond section, cyan light along its edges and a cyan neon fuller down its
// middle; the parrying hooks (Parierhaken) where the ricasso ends, the ricasso
// wrapped in carbon with magenta rings; a broad cross guard (a real one is up
// to 35 cm across) with a magenta core, its quillons swept and lit at the
// ends; a long wrapped grip and a heavy pommel; both neon gloves on the grip,
// the right under the guard, the left near the pommel. The blade lies on the
// rules' line from the hilt (game.SWORD_HILT) to the point on the screen: the
// guard FIRST_PERSON_ZWEIHANDER_ALONG of the way along it, the point exactly on
// the point, the 3D blade between them, so it leans into the view as the
// point comes in toward the hilt. Its flat faces the eye.

// The guard's place on the hilt-to-point line, and how far it is from the eye (metres).
FIRST_PERSON_ZWEIHANDER_ALONG :: f32(0.26)
FIRST_PERSON_ZWEIHANDER_DEPTH :: f32(0.74)
// From the guard to the point (metres).
FIRST_PERSON_ZWEIHANDER_BLADE :: f32(1.30)
// Where along the grip the hands hold it, down from the guard (metres).
FIRST_PERSON_ZWEIHANDER_HANDS :: [2]f32{0.07, 0.205}
// The gloves' size on the sword (the fists' own is FIRST_PERSON_GLOVE_SCALE).
FIRST_PERSON_ZWEIHANDER_GLOVE :: f32(0.56)
// The shoulders the forearms go back to, in the gloves' camera (right, left).
FIRST_PERSON_ZWEIHANDER_SHOULDERS :: [2]rl.Vector3{{0.26, -0.48, 0.10}, {0.06, -0.56, 0.14}}

// The blade's sections up from the guard (metres): height, half width, half
// thickness (its spine); then the point.
@(rodata)
FIRST_PERSON_ZWEIHANDER_SECTIONS := [?][3]f32{
	{0.00, 0.019, 0.010}, {0.20, 0.019, 0.010},
	// The shoulder where the ricasso ends and the edge begins.
	{0.20, 0.042, 0.012}, {0.92, 0.036, 0.011}, {1.14, 0.027, 0.009},
}

First_Person_Zweihander_Shape :: enum u8 {Sphere, Cylinder, Cube, Blade}

// One piece of the sword in its frame (+Y up the blade from the guard's middle,
// +X its width, +Z the flat facing the eye): `at` its centre (a cylinder's
// foot: it stands up +Y), `size` (half sizes of a sphere, a cylinder's radii
// and height, a cube's full sizes), `roll` turned round Z.
First_Person_Zweihander_Part :: struct {
	shape: First_Person_Zweihander_Shape,
	stuff: First_Person_Glove_Stuff,
	at, size: rl.Vector3,
	roll: f32,
}

@(rodata)
FIRST_PERSON_ZWEIHANDER_PARTS := [?]First_Person_Zweihander_Part{
	{shape = .Blade, stuff = .Steel, size = {1, 1, 1}},
	// The fuller: a cyan neon groove down both faces.
	{shape = .Cube, stuff = .Cyan, at = {0, 0.60, 0}, size = {0.010, 0.66, 0.0252}},
	// The ricasso's wrap and its two rings.
	{shape = .Cylinder, stuff = .Wrap, at = {0, 0.025, 0}, size = {0.024, 0.15, 0.015}},
	{shape = .Cylinder, stuff = .Neon, at = {0, 0.050, 0}, size = {0.026, 0.010, 0.017}},
	{shape = .Cylinder, stuff = .Neon, at = {0, 0.150, 0}, size = {0.026, 0.010, 0.017}},
	// The parrying hooks, swept back toward the guard, lit at their ends.
	{shape = .Cube, stuff = .Carbon, at = {0.052, 0.198, 0}, size = {0.052, 0.014, 0.016}, roll = -0.45},
	{shape = .Cube, stuff = .Carbon, at = {-0.052, 0.198, 0}, size = {0.052, 0.014, 0.016}, roll = 0.45},
	{shape = .Sphere, stuff = .Cyan, at = {0.078, 0.185, 0}, size = {0.009, 0.009, 0.009}},
	{shape = .Sphere, stuff = .Cyan, at = {-0.078, 0.185, 0}, size = {0.009, 0.009, 0.009}},
	// The cross guard, its magenta tube and its swept quillons with their lights.
	{shape = .Cube, stuff = .Carbon, at = {0, 0, 0}, size = {0.30, 0.034, 0.036}},
	{shape = .Cube, stuff = .Neon, at = {0, 0, 0}, size = {0.25, 0.009, 0.040}},
	{shape = .Cube, stuff = .Carbon, at = {0.168, 0.028, 0}, size = {0.030, 0.085, 0.032}, roll = -0.55},
	{shape = .Cube, stuff = .Carbon, at = {-0.168, 0.028, 0}, size = {0.030, 0.085, 0.032}, roll = 0.55},
	{shape = .Sphere, stuff = .Cyan, at = {0.192, 0.066, 0}, size = {0.017, 0.017, 0.017}},
	{shape = .Sphere, stuff = .Cyan, at = {-0.192, 0.066, 0}, size = {0.017, 0.017, 0.017}},
	// The side rings' plates under the guard.
	{shape = .Sphere, stuff = .Carbon, at = {0.062, -0.030, 0}, size = {0.034, 0.024, 0.012}},
	{shape = .Sphere, stuff = .Carbon, at = {-0.062, -0.030, 0}, size = {0.034, 0.024, 0.012}},
	// Its core: a magenta light at the cross.
	{shape = .Sphere, stuff = .Neon, at = {0, 0.002, 0}, size = {0.030, 0.030, 0.028}},
	// The grip, its neon rings, the pommel and its cyan band.
	{shape = .Cylinder, stuff = .Wrap, at = {0, -0.300, 0}, size = {0.017, 0.300, 0.017}},
	{shape = .Cylinder, stuff = .Neon, at = {0, -0.140, 0}, size = {0.0185, 0.009, 0.0185}},
	{shape = .Cylinder, stuff = .Neon, at = {0, -0.265, 0}, size = {0.0185, 0.009, 0.0185}},
	{shape = .Sphere, stuff = .Carbon, at = {0, -0.333, 0}, size = {0.038, 0.046, 0.038}},
	{shape = .Cylinder, stuff = .Cyan, at = {0, -0.339, 0}, size = {0.0395, 0.010, 0.0395}},
}

// A mesh of flat faced triangles (each its own normal), from the blade's
// sections grown `grow` metres on every side (its ink's shell). raylib frees
// it, so its arrays come from raylib's allocator.
@(private = "file")
first_person_zweihander_blade_mesh :: proc(grow: f32) -> rl.Mesh {
	sections := FIRST_PERSON_ZWEIHANDER_SECTIONS
	tris: [dynamic][3]rl.Vector3
	defer delete(tris)
	ring :: proc(s: [3]f32, grow: f32) -> [4]rl.Vector3 {
		w, t := s[1]+grow, s[2]+grow
		return {{w, s[0], 0}, {0, s[0], t}, {-w, s[0], 0}, {0, s[0], -t}}
	}
	// Faces turned out: away from the blade's middle (a face across it, the
	// shoulder or the foot, down toward the guard).
	face :: proc(tris: ^[dynamic][3]rl.Vector3, a, b, c: rl.Vector3) {
		n := rl.Vector3CrossProduct(b-a, c-a)
		if rl.Vector3Length(n) < 1e-9 { return }
		centre := (a+b+c)/3
		out := centre-rl.Vector3{0, centre.y, 0}
		if rl.Vector3Length(out) < 1e-4 || abs(rl.Vector3DotProduct(rl.Vector3Normalize(n), rl.Vector3Normalize(out))) < 0.05 { out = {0, -1, 0} }
		if rl.Vector3DotProduct(n, out) < 0 { append(tris, [3]rl.Vector3{a, c, b}) } else { append(tris, [3]rl.Vector3{a, b, c}) }
	}
	foot := ring(sections[0], grow)
	foot.x.y -= grow; foot.y.y -= grow; foot.z.y -= grow; foot.w.y -= grow
	face(&tris, foot[0], foot[1], foot[2])
	face(&tris, foot[0], foot[2], foot[3])
	lower := foot
	for k in 1..<len(sections) {
		upper := ring(sections[k], grow)
		for side in 0..<4 {
			next := (side+1)%4
			face(&tris, lower[side], lower[next], upper[next])
			face(&tris, lower[side], upper[next], upper[side])
		}
		lower = upper
	}
	apex := rl.Vector3{0, FIRST_PERSON_ZWEIHANDER_BLADE+grow*2, 0}
	for side in 0..<4 { face(&tris, lower[side], lower[(side+1)%4], apex) }
	mesh: rl.Mesh
	mesh.vertexCount = c.int(len(tris)*3)
	mesh.triangleCount = c.int(len(tris))
	mesh.vertices = cast([^]f32)rl.MemAlloc(c.uint(len(tris)*9*size_of(f32)))
	mesh.normals = cast([^]f32)rl.MemAlloc(c.uint(len(tris)*9*size_of(f32)))
	for tri, k in tris {
		n := rl.Vector3Normalize(rl.Vector3CrossProduct(tri[1]-tri[0], tri[2]-tri[0]))
		for corner, j in tri {
			at := (k*3+j)*3
			mesh.vertices[at], mesh.vertices[at+1], mesh.vertices[at+2] = corner.x, corner.y, corner.z
			mesh.normals[at], mesh.normals[at+1], mesh.normals[at+2] = n.x, n.y, n.z
		}
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

// The sword's shapes, the first time it is drawn.
@(private = "file")
first_person_zweihander_kit :: proc(kit: ^First_Person_Glove_Kit) -> bool {
	if kit.shader.id == 0 { return false }
	if kit.blade.vaoId != 0 { return true }
	kit.cube = rl.GenMeshCube(1, 1, 1)
	kit.blade = first_person_zweihander_blade_mesh(0)
	kit.blade_ink = first_person_zweihander_blade_mesh(FIRST_PERSON_GLOVE_INK)
	return kit.blade.vaoId != 0
}

// A point on the screen (heights from the middle, up) as a way out of the
// gloves' camera.
first_person_zweihander_ray :: proc(p: [2]f32) -> rl.Vector3 {
	k := 2*f32(math.tan(f64(FIRST_PERSON_GLOVE_FOV)*math.PI/360))
	return rl.Vector3Normalize({p.x*k, p.y*k, -1})
}

// Where the sword is in the gloves' camera with its point at `tip` on the
// screen (both lifted `lift` heights down as it comes in): the guard's middle
// and the way up the blade.
first_person_zweihander_place :: proc(tip: [2]f32, lift: f32) -> (guard, axis: rl.Vector3) {
	hilt := game.SWORD_HILT
	point := tip-{0, lift}
	on := hilt+(tip-hilt)*FIRST_PERSON_ZWEIHANDER_ALONG-{0, lift}
	guard = first_person_zweihander_ray(on)*FIRST_PERSON_ZWEIHANDER_DEPTH
	d := first_person_zweihander_ray(point)
	// The far point on d's way a blade's length from the guard (the guard is
	// always nearer than that, so there is one).
	b := rl.Vector3DotProduct(d, guard)
	cc := rl.Vector3DotProduct(guard, guard)-FIRST_PERSON_ZWEIHANDER_BLADE*FIRST_PERSON_ZWEIHANDER_BLADE
	t := b+math.sqrt(max(b*b-cc, 0))
	axis = rl.Vector3Normalize(d*t-guard)
	return
}

// A frame of axes `x`, `y`, `z` at `at`.
@(private = "file")
first_person_zweihander_frame :: proc(x, y, z, at: rl.Vector3) -> rl.Matrix {
	return rl.Matrix{
		x.x, y.x, z.x, at.x,
		x.y, y.y, z.y, at.y,
		x.z, y.z, z.z, at.z,
		0, 0, 0, 1,
	}
}

// The sword's frame (+Y up the blade, +Z its flat toward the eye).
first_person_zweihander_matrix :: proc(guard, axis: rl.Vector3) -> rl.Matrix {
	toward := rl.Vector3Normalize(-guard)
	width := rl.Vector3Normalize(rl.Vector3CrossProduct(axis, toward))
	flat := rl.Vector3CrossProduct(width, axis)
	return first_person_zweihander_frame(width, axis, flat, guard)
}

// A glove on the grip `down` metres under the guard (`side` 0 the right, 1
// the left): its fist round the grip, its forearm back to its shoulder (the
// wrist bent: the grip runs through the fist as near its length as that lets it).
first_person_zweihander_glove :: proc(guard, axis: rl.Vector3, side: int) -> rl.Matrix {
	hands := FIRST_PERSON_ZWEIHANDER_HANDS
	shoulders := FIRST_PERSON_ZWEIHANDER_SHOULDERS
	grip := guard-axis*hands[side]
	back := rl.Vector3Normalize(shoulders[side]-grip)
	// The thumb's side (the left's +X, the right's -X) up the grip, toward the blade.
	along := rl.Vector3Normalize(axis-back*rl.Vector3DotProduct(axis, back))
	x := along if side == 1 else -along
	y := rl.Vector3CrossProduct(back, x)
	// The grip runs through the fist a little in front of the hand's middle.
	s := FIRST_PERSON_ZWEIHANDER_GLOVE
	at := grip-(y*-0.004+back*-0.022)*s
	return first_person_zweihander_frame(x, y, back, at)*rl.MatrixScale(s, s, s)
}

// A piece's matrix in the sword's frame, `grow` metres fuller on every side.
@(private = "file")
first_person_zweihander_part_frame :: proc(part: First_Person_Zweihander_Part, grow: f32) -> rl.Matrix {
	place := rl.MatrixTranslate(part.at.x, part.at.y, part.at.z)*rl.MatrixRotateZ(part.roll)
	switch part.shape {
	case .Blade: return place
	case .Cylinder:
		return place*rl.MatrixTranslate(0, -grow, 0)*rl.MatrixScale(part.size.x+grow, part.size.y+grow*2, part.size.z+grow)
	case .Cube:
		return place*rl.MatrixScale(part.size.x+grow*2, part.size.y+grow*2, part.size.z+grow*2)
	case .Sphere:
	}
	return place*rl.MatrixScale(part.size.x+grow, part.size.y+grow, part.size.z+grow)
}

// The sword and the two gloves on it, in the gloves' camera, on the small
// canvas bound now; white for a perfect parry's flash.
@(private)
draw_first_person_zweihander :: proc(renderer: ^Renderer, kit: ^First_Person_Glove_Kit, ready: f32) {
	if !first_person_zweihander_kit(kit) { return }
	v := &renderer.tactical.first_person.sword
	now := renderer.sprite_assets.elapsed
	guard, axis := first_person_zweihander_place(first_person_sword_shown_tip(v, now), (1-ready)*0.6)
	sword := first_person_zweihander_matrix(guard, axis)
	white := first_person_sword_parry_flash(v, now)
	camera := first_person_glove_camera()
	maps: [12]rl.MaterialMap
	material := rl.Material{shader = kit.shader, maps = raw_data(maps[:])}
	none := f32(99)
	rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &none, .FLOAT)
	rl.BeginMode3D(camera)
	rlgl.EnableBackfaceCulling()
	for pass in 0..<2 {
		ink := f32(1 if pass == 0 else 0)
		rlgl.SetCullFace(.FRONT if pass == 0 else .BACK)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.ink_location), &ink, .FLOAT)
		grow := FIRST_PERSON_GLOVE_INK if pass == 0 else 0
		for part in FIRST_PERSON_ZWEIHANDER_PARTS {
			stuff := f32(part.stuff)
			if white && (part.stuff == .Steel || part.stuff == .Cyan) { stuff = f32(First_Person_Glove_Stuff.White) }
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.stuff_location), &stuff, .FLOAT)
			mesh: rl.Mesh
			switch part.shape {
			case .Sphere: mesh = kit.sphere
			case .Cylinder: mesh = kit.cylinder
			case .Cube: mesh = kit.cube
			case .Blade: mesh = kit.blade_ink if pass == 0 else kit.blade
			}
			rl.DrawMesh(mesh, material, sword*first_person_zweihander_part_frame(part, grow))
		}
		// The gloves on the grip (the right under the guard, the left lower).
		for side in 0..<2 {
			glove := first_person_zweihander_glove(guard, axis, side)
			for part, index in FIRST_PERSON_GLOVE_PARTS {
				stuff, piece := f32(part.stuff), f32(index)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.stuff_location), &stuff, .FLOAT)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &piece, .FLOAT)
				rl.DrawMesh(kit.cylinder if part.cylinder else kit.sphere, material, glove*first_person_glove_part_frame(part, side == 1, grow))
			}
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &none, .FLOAT)
		}
	}
	rlgl.SetCullFace(.BACK)
	rl.EndMode3D()
}
