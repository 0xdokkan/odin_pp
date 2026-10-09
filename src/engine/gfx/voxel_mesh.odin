package gfx

import "core:c"
import rl "vendor:raylib"
import physics "../physics"

// Colour of each voxel material id (index 0 is never drawn).
Voxel_Palette :: [256]rl.Color

@(private)
FACE_SHADE :: [6]f32{0.82, 0.82, 1.0, 0.55, 0.9, 0.72} // +x -x +y -y +z -z

@(private)
FACE_AXES :: [6][3]int{{0, 1, 2}, {0, 1, 2}, {1, 0, 2}, {1, 0, 2}, {2, 0, 1}, {2, 0, 1}}

Voxel_Face_Count :: struct {
	faces:    int,
	vertices: int,
}

// Counts faces between a solid voxel and an empty neighbour; the cell values
// outside the map follow Voxel_Map.outside, so closed rooms skip their shell.
count_voxel_faces :: proc(m: ^physics.Voxel_Map) -> Voxel_Face_Count {
	n := 0
	for y in 0..<m.height {
		for z in 0..<m.depth {
			for x in 0..<m.width {
				if physics.voxel_get(m, x, y, z) == 0 {
					continue
				}
				for face in 0..<6 {
					d := face_offset(face)
					if physics.voxel_get(m, x+d.x, y+d.y, z+d.z) == 0 {
						n += 1
					}
				}
			}
		}
	}
	return Voxel_Face_Count{faces = n, vertices = n * 6}
}

@(private)
face_offset :: proc "contextless" (face: int) -> [3]int {
	axis := face / 2
	d: [3]int
	d[axis] = 1 if face%2 == 0 else -1
	return d
}

// Small per-voxel brightness variation so flat walls read as stone blocks.
@(private)
voxel_jitter :: proc "contextless" (x, y, z: int) -> f32 {
	h := u32(x*73856093) ~ u32(y*19349663) ~ u32(z*83492791)
	h = (h ~ (h >> 13)) * 0x5bd1e995
	return 0.92 + f32(h % 17) / 200
}

// Builds and uploads a mesh of the visible voxel faces. The returned model
// owns the GPU buffers; release it with rl.UnloadModel. Faces get directional
// shading baked into vertex colours, so even unlit drawing reads as 3D.
build_voxel_model :: proc(m: ^physics.Voxel_Map, palette: ^Voxel_Palette) -> (rl.Model, bool) {
	count := count_voxel_faces(m)
	if count.faces == 0 {
		return {}, false
	}
	vertex_count := count.vertices
	mesh: rl.Mesh
	mesh.vertexCount = c.int(vertex_count)
	mesh.triangleCount = c.int(count.faces * 2)
	mesh.vertices = cast([^]f32)rl.MemAlloc(c.uint(vertex_count * 3 * size_of(f32)))
	mesh.normals = cast([^]f32)rl.MemAlloc(c.uint(vertex_count * 3 * size_of(f32)))
	mesh.texcoords = cast([^]f32)rl.MemAlloc(c.uint(vertex_count * 2 * size_of(f32)))
	mesh.colors = cast([^]u8)rl.MemAlloc(c.uint(vertex_count * 4))
	s := m.voxel_size
	shades := FACE_SHADE
	v := 0
	for y in 0..<m.height {
		for z in 0..<m.depth {
			for x in 0..<m.width {
				value := physics.voxel_get(m, x, y, z)
				if value == 0 {
					continue
				}
				base := palette[value]
				jitter := voxel_jitter(x, y, z)
				for face in 0..<6 {
					d := face_offset(face)
					if physics.voxel_get(m, x+d.x, y+d.y, z+d.z) != 0 {
						continue
					}
					corners := face_corners(face, Vec3{f32(x), f32(y), f32(z)} * s, s)
					normal := Vec3{f32(d.x), f32(d.y), f32(d.z)}
					k := shades[face] * jitter
					color := rl.Color{
						u8(min(f32(base.r)*k, 255)), u8(min(f32(base.g)*k, 255)),
						u8(min(f32(base.b)*k, 255)), base.a,
					}
					order := [6]int{0, 1, 2, 0, 2, 3}
					origin := Vec3{f32(x), f32(y), f32(z)} * s
					for corner in order {
						p := corners[corner]
						uv := face_uv(face, (p - origin) / s)
						mesh.vertices[v*3+0] = p.x
						mesh.vertices[v*3+1] = p.y
						mesh.vertices[v*3+2] = p.z
						mesh.normals[v*3+0] = normal.x
						mesh.normals[v*3+1] = normal.y
						mesh.normals[v*3+2] = normal.z
						mesh.texcoords[v*2+0] = uv[0]
						mesh.texcoords[v*2+1] = uv[1]
						mesh.colors[v*4+0] = color.r
						mesh.colors[v*4+1] = color.g
						mesh.colors[v*4+2] = color.b
						mesh.colors[v*4+3] = color.a
						v += 1
					}
				}
			}
		}
	}
	rl.UploadMesh(&mesh, false)
	model := rl.LoadModelFromMesh(mesh)
	return model, model.meshCount > 0
}

// Texture coordinates from a corner's position inside its voxel (0 or 1 per
// axis): walls run u along the ground and v downward, so textures stand upright
// on every side; floors and ceilings map u = x, v = z.
@(private)
face_uv :: proc "contextless" (face: int, local: Vec3) -> [2]f32 {
	switch face / 2 {
	case 0:
		return {local.z, 1 - local.y}
	case 2:
		return {local.x, 1 - local.y}
	}
	return {local.x, local.z}
}

// Four corners of a unit face, counter-clockwise when seen from outside.
@(private)
face_corners :: proc "contextless" (face: int, origin: Vec3, s: f32) -> [4]Vec3 {
	axes := FACE_AXES
	a := axes[face]
	axis, u, w := a[0], a[1], a[2]
	positive := face%2 == 0
	quad: [4][2]f32 = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	out: [4]Vec3
	for q, i in quad {
		p := origin
		p[axis] += s if positive else 0
		p[u] += q[0] * s
		p[w] += q[1] * s
		out[i] = p
	}
	// Fix the winding so the triangle normal points along the face normal.
	e1 := out[1] - out[0]
	e2 := out[2] - out[0]
	cross := Vec3{e1.y*e2.z - e1.z*e2.y, e1.z*e2.x - e1.x*e2.z, e1.x*e2.y - e1.y*e2.x}
	sign := cross[axis]
	if (positive && sign < 0) || (!positive && sign > 0) {
		out[1], out[3] = out[3], out[1]
	}
	return out
}
