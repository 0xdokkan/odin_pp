package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// BENVENUTI A NAPOLI's 3D paper models (docs/piano-napoli.md, Fase 5, the
// user's choices of 2026-11-03), made from code as the Brawler's gloves are
// (first_person_gloves.odin): spheres, cylinders and boxes, each in three flat
// tones of its colour under a key light from the upper left, the board's ink
// round every part (its shell a little fuller, drawn inside out first), on the
// board itself rather than on a canvas of their own:
//   - the ace of clubs of the Neapolitan deck: a knotty club, its round head
//     green, its handle red wound with yellow acanthus leaves and one green,
//     its cut end showing the wood's green rings;
//   - the Viandante seen from behind: his card's hooded pilgrim, the cream
//     cloak and hood, the brown pack and bedroll, both hands on the club;
//   - the grandpa at the seaside: straw hat with a red band, white moustache, a
//     white vest over his belly, blue shorts, white socks in brown sandals,
//     stooping a little.
// A model fades through an ordered dither (a 4x4 Bayer pattern), as pixel art
// fades, with no sorting of its parts.

NAPOLI_MODEL_INK :: f32(0.012)
NAPOLI_MODEL_PARTS :: 96

NAPOLI_MODEL_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matNormal;
out vec3 fragNormal;
void main() {
    fragNormal = normalize(mat3(matNormal)*vertexNormal);
    gl_Position = mvp*vec4(vertexPosition, 1.0);
}
`

NAPOLI_MODEL_FRAGMENT :: `#version 330
in vec3 fragNormal;
uniform vec3 base;
uniform float ink;
uniform float alpha;
out vec4 finalColor;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void main() {
    ivec2 p = ivec2(gl_FragCoord.xy) % 4;
    if (alpha < 0.999 && (BAYER[p.y*4+p.x]+0.5)/16.0 > alpha) discard;
    if (ink > 0.5) { finalColor = vec4(13.0, 20.0, 30.0, 255.0)/255.0; return; }
    vec3 n = normalize(fragNormal);
    float wrap = dot(n, normalize(vec3(-0.45, 0.80, 0.45)))*0.5+0.5;
    vec3 c = wrap < 0.42 ? base*0.62 : (wrap < 0.80 ? base : min(base*1.18+vec3(0.04), vec3(1.0)));
    finalColor = vec4(c, 1.0);
}
`

Napoli_Shape :: enum u8 {Sphere, Cylinder, Cube}

// A part: its shape's unit (a sphere of radius 1, a cylinder of radius 1 from
// 0 to 1 up its Y, a cube of side 1 about its centre) placed by `frame`.
Napoli_Part :: struct {
	shape: Napoli_Shape,
	color: rl.Color,
	frame: rl.Matrix,
	// Its size (the scale in `frame`), for the ink's fuller shell.
	size: rl.Vector3,
}

Napoli_Model :: struct {
	parts: [NAPOLI_MODEL_PARTS]Napoli_Part,
	count: int,
}

// The models' GPU handles, made the first time one is drawn, freed with the view.
Napoli_Model_Kit :: struct {
	sphere, cylinder, cube: rl.Mesh,
	shader: rl.Shader,
	base_location, ink_location, alpha_location: i32,
	ready, failed: bool,
}

@(private)
napoli_model_kit :: proc(kit: ^Napoli_Model_Kit) -> bool {
	if kit.ready { return true }
	if kit.failed { return false }
	shader := rl.LoadShaderFromMemory(NAPOLI_MODEL_VERTEX, NAPOLI_MODEL_FRAGMENT)
	if shader.id == 0 || shader.id == rlgl.GetShaderIdDefault() {
		kit.failed = true
		return false
	}
	kit.shader = shader
	kit.base_location = rl.GetShaderLocation(shader, "base")
	kit.ink_location = rl.GetShaderLocation(shader, "ink")
	kit.alpha_location = rl.GetShaderLocation(shader, "alpha")
	kit.sphere = rl.GenMeshSphere(1, 14, 18)
	kit.cylinder = rl.GenMeshCylinder(1, 1, 16)
	kit.cube = rl.GenMeshCube(1, 1, 1)
	kit.ready = true
	return true
}

@(private)
destroy_napoli_model_kit :: proc(kit: ^Napoli_Model_Kit) {
	if kit.sphere.vaoId != 0 { rl.UnloadMesh(kit.sphere) }
	if kit.cylinder.vaoId != 0 { rl.UnloadMesh(kit.cylinder) }
	if kit.cube.vaoId != 0 { rl.UnloadMesh(kit.cube) }
	if kit.shader.id != 0 { rl.UnloadShader(kit.shader) }
	kit^ = {}
}

// A model's frame on the board: its feet at `feet`, facing `forward` (on the
// floor), X its right, Y up, Z its front (a mirrored frame: draw_napoli_model
// turns the culling for it).
napoli_model_frame :: proc(feet, forward: rl.Vector3) -> rl.Matrix {
	f := rl.Vector3Normalize({forward.x, 0, forward.z})
	r := rl.Vector3{-f.z, 0, f.x}
	return napoli_basis(r, {0, 1, 0}, f, feet)
}

// The matrix whose columns are `x`, `y`, `z` and the point `at`.
napoli_basis :: proc(x, y, z, at: rl.Vector3) -> rl.Matrix {
	return rl.Matrix{
		x.x, y.x, z.x, at.x,
		x.y, y.y, z.y, at.y,
		x.z, y.z, z.z, at.z,
		0, 0, 0, 1,
	}
}

// A point of the model's own frame on the board.
napoli_model_point :: proc(frame: rl.Matrix, local: rl.Vector3) -> rl.Vector3 {
	return rl.Vector3Transform(local, frame)
}

@(private = "file")
napoli_add :: proc(model: ^Napoli_Model, part: Napoli_Part) {
	if model.count >= NAPOLI_MODEL_PARTS { return }
	model.parts[model.count] = part
	model.count += 1
}

// An ellipsoid of `radii` at `at` in `frame`, turned by `turn`.
napoli_ball :: proc(model: ^Napoli_Model, frame: rl.Matrix, at, radii: rl.Vector3, color: rl.Color, turn := rl.Matrix(1)) {
	napoli_add(model, {shape = .Sphere, color = color, size = radii,
		frame = frame*rl.MatrixTranslate(at.x, at.y, at.z)*turn*rl.MatrixScale(radii.x, radii.y, radii.z)})
}

// A box of `size` centred at `at` in `frame`, turned by `turn`.
napoli_box :: proc(model: ^Napoli_Model, frame: rl.Matrix, at, size: rl.Vector3, color: rl.Color, turn := rl.Matrix(1)) {
	napoli_add(model, {shape = .Cube, color = color, size = size,
		frame = frame*rl.MatrixTranslate(at.x, at.y, at.z)*turn*rl.MatrixScale(size.x, size.y, size.z)})
}

// A rod of `radius` from `a` to `b` (board points), its ends rounded by balls.
napoli_rod :: proc(model: ^Napoli_Model, a, b: rl.Vector3, radius: f32, color: rl.Color, ends := true) {
	d := b-a
	length := rl.Vector3Length(d)
	if length < 1e-4 { return }
	y := d/length
	ref := rl.Vector3{1, 0, 0} if abs(y.x) < 0.9 else rl.Vector3{0, 0, 1}
	x := rl.Vector3Normalize(rl.Vector3CrossProduct(y, ref))
	z := rl.Vector3CrossProduct(x, y)
	napoli_add(model, {shape = .Cylinder, color = color, size = {radius, length, radius},
		frame = napoli_basis(x, y, z, a)*rl.MatrixScale(radius, length, radius)})
	if ends {
		napoli_ball(model, rl.Matrix(1), a, {radius, radius, radius}, color)
		napoli_ball(model, rl.Matrix(1), b, {radius, radius, radius}, color)
	}
}

// A disc (a short cylinder) of `radius` and `height` standing at `at` in `frame`.
napoli_disc :: proc(model: ^Napoli_Model, frame: rl.Matrix, at: rl.Vector3, radius, height: f32, color: rl.Color, turn := rl.Matrix(1)) {
	napoli_add(model, {shape = .Cylinder, color = color, size = {radius, height, radius},
		frame = frame*rl.MatrixTranslate(at.x, at.y, at.z)*turn*rl.MatrixScale(radius, height, radius)})
}

// Two bones from `shoulder` to `hand` (each `bone` long), the elbow bent toward
// `bend`: where the elbow is.
napoli_elbow :: proc(shoulder, hand, bend: rl.Vector3, bone: f32) -> rl.Vector3 {
	d := hand-shoulder
	length := rl.Vector3Length(d)
	mid := shoulder+d*0.5
	if length >= bone*2 || length < 1e-4 { return mid }
	out := bend-d*(rl.Vector3DotProduct(bend, d)/(length*length))
	if rl.Vector3Length(out) < 1e-4 { return mid }
	return mid+rl.Vector3Normalize(out)*math.sqrt(bone*bone-length*length*0.25)
}

// An arm from `shoulder` to `hand`: its sleeve, its forearm, its hand.
@(private = "file")
napoli_arm :: proc(model: ^Napoli_Model, shoulder, hand, bend: rl.Vector3, upper, lower, palm: rl.Color, radius: f32) {
	elbow := napoli_elbow(shoulder, hand, bend, 0.3)
	napoli_rod(model, shoulder, elbow, radius, upper)
	napoli_rod(model, elbow, hand, radius*0.85, lower)
	napoli_ball(model, rl.Matrix(1), hand, {radius*1.25, radius*1.25, radius*1.25}, palm)
}

NAPOLI_CLUB_RED :: rl.Color{178, 40, 40, 255}
NAPOLI_CLUB_RED_DARK :: rl.Color{118, 26, 30, 255}
NAPOLI_CLUB_GREEN :: rl.Color{58, 142, 70, 255}
NAPOLI_CLUB_GREEN_DARK :: rl.Color{34, 96, 48, 255}
NAPOLI_CLUB_LEAF :: rl.Color{232, 190, 60, 255}
NAPOLI_CLUB_CUT :: rl.Color{236, 224, 196, 255}

// The ace of clubs from `grip` along `along` (unit), `length` long, its flat
// side across `side`: the cut end under the hands, the red handle wound with
// leaves, the green head.
napoli_club_model :: proc(model: ^Napoli_Model, grip, along, side: rl.Vector3, length: f32) {
	y := rl.Vector3Normalize(along)
	x := rl.Vector3Normalize(side-y*rl.Vector3DotProduct(side, y))
	if rl.Vector3Length(x) < 1e-4 { x = rl.Vector3Normalize(rl.Vector3CrossProduct(y, {0, 1, 0.01})) }
	z := rl.Vector3CrossProduct(x, y)
	s := length/0.95
	frame := napoli_basis(x, y, z, grip)*rl.MatrixScale(s, s, s)
	at :: proc(frame: rl.Matrix, p: rl.Vector3) -> rl.Vector3 { return rl.Vector3Transform(p, frame) }
	// The handle, a little bent: three red lengths and their knots.
	napoli_rod(model, at(frame, {0, -0.06, 0}), at(frame, {0.012, 0.28, 0}), 0.05*s, NAPOLI_CLUB_RED)
	napoli_rod(model, at(frame, {0.012, 0.28, 0}), at(frame, {0.03, 0.55, 0.01}), 0.058*s, NAPOLI_CLUB_RED)
	napoli_rod(model, at(frame, {0.03, 0.55, 0.01}), at(frame, {0.02, 0.72, 0}), 0.068*s, NAPOLI_CLUB_RED)
	napoli_ball(model, frame, {0.05, 0.18, 0.01}, {0.035, 0.03, 0.035}, NAPOLI_CLUB_RED_DARK)
	napoli_ball(model, frame, {-0.04, 0.42, -0.02}, {0.036, 0.03, 0.036}, NAPOLI_CLUB_RED_DARK)
	// The cut end: the cream wood and its green rings.
	napoli_disc(model, frame, {0, -0.085, 0}, 0.07, 0.03, NAPOLI_CLUB_CUT)
	napoli_disc(model, frame, {0, -0.09, 0}, 0.045, 0.03, NAPOLI_CLUB_GREEN)
	napoli_disc(model, frame, {0, -0.095, 0}, 0.02, 0.03, NAPOLI_CLUB_CUT)
	// The acanthus leaves round the handle, two rings of three, and the green one.
	for ring in 0..<2 {
		h := f32(0.24) if ring == 0 else f32(0.5)
		for k in 0..<3 {
			a := f32(k)*math.TAU/3+f32(ring)*0.9
			out := rl.Vector3{math.cos(a), 0, math.sin(a)}
			turn := rl.MatrixRotateY(-a)*rl.MatrixRotateZ(-0.5)
			napoli_ball(model, frame, out*0.065+{0, h, 0}, {0.022, 0.1, 0.05}, NAPOLI_CLUB_LEAF, turn)
		}
	}
	napoli_ball(model, frame, {0.075, 0.4, 0.02}, {0.02, 0.09, 0.045}, NAPOLI_CLUB_GREEN, rl.MatrixRotateZ(-0.6))
	// The head: round, green, knotty.
	napoli_ball(model, frame, {0.02, 0.84, 0}, {0.15, 0.17, 0.15}, NAPOLI_CLUB_GREEN)
	knobs := [6]rl.Vector3{{0.14, 0.86, 0.04}, {-0.11, 0.9, 0.07}, {0.06, 0.98, -0.1}, {-0.06, 0.78, -0.12}, {0.1, 0.74, 0.1}, {0.02, 1.01, 0.05}}
	for knob in knobs { napoli_ball(model, frame, knob, {0.05, 0.05, 0.05}, NAPOLI_CLUB_GREEN_DARK) }
}

// Where a two-handed grip puts the other hand: a little up the handle.
napoli_club_second_hand :: proc(grip, along: rl.Vector3, length: f32) -> rl.Vector3 {
	return grip+rl.Vector3Normalize(along)*(0.14*length/0.95)
}

NAPOLI_PILGRIM_CLOAK :: rl.Color{232, 220, 190, 255}
NAPOLI_PILGRIM_CAPE :: rl.Color{210, 196, 164, 255}
NAPOLI_PILGRIM_PACK :: rl.Color{112, 72, 42, 255}
NAPOLI_PILGRIM_ROLL :: rl.Color{156, 112, 70, 255}
NAPOLI_PILGRIM_BELT :: rl.Color{88, 56, 32, 255}
NAPOLI_PILGRIM_LEGS :: rl.Color{70, 52, 44, 255}
NAPOLI_PILGRIM_GLOVE :: rl.Color{104, 72, 50, 255}

// The Viandante seen from behind, his feet at `frame`'s origin, his hands at
// `right_hand` and `left_hand` (board points), his legs `walk` into a stride
// (-1..1).
napoli_pilgrim_model :: proc(model: ^Napoli_Model, frame: rl.Matrix, right_hand, left_hand: rl.Vector3, walk: f32) {
	for side in 0..<2 {
		x := f32(0.1) if side == 0 else f32(-0.1)
		stride := walk*(0.13 if side == 0 else -0.13)
		foot := rl.Vector3{x, 0.06, 0.03+stride}
		napoli_ball(model, frame, foot, {0.065, 0.055, 0.1}, NAPOLI_PILGRIM_LEGS)
		napoli_rod(model, napoli_model_point(frame, foot+{0, 0.04, -0.02}), napoli_model_point(frame, {x*0.9, 0.5, stride*0.3}), 0.055, NAPOLI_PILGRIM_LEGS)
	}
	// The cloak: its skirt, its body, the belt.
	napoli_ball(model, frame, {0, 0.5, 0}, {0.25, 0.16, 0.21}, NAPOLI_PILGRIM_CLOAK)
	napoli_disc(model, frame, {0, 0.42, 0}, 0.2, 0.55, NAPOLI_PILGRIM_CLOAK)
	napoli_ball(model, frame, {0, 1.0, 0}, {0.22, 0.25, 0.17}, NAPOLI_PILGRIM_CLOAK)
	napoli_disc(model, frame, {0, 0.76, 0}, 0.212, 0.05, NAPOLI_PILGRIM_BELT)
	// The cape on his back, the pack and its bedroll.
	napoli_ball(model, frame, {0, 1.02, -0.11}, {0.24, 0.28, 0.1}, NAPOLI_PILGRIM_CAPE)
	napoli_box(model, frame, {0, 0.96, -0.21}, {0.3, 0.34, 0.13}, NAPOLI_PILGRIM_PACK)
	napoli_box(model, frame, {0, 0.9, -0.285}, {0.2, 0.12, 0.03}, NAPOLI_PILGRIM_BELT)
	napoli_disc(model, frame, {-0.18, 1.18, -0.21}, 0.06, 0.36, NAPOLI_PILGRIM_ROLL, rl.MatrixRotateZ(-math.PI/2))
	// The hood, its point falling back.
	napoli_ball(model, frame, {0, 1.3, 0}, {0.17, 0.18, 0.17}, NAPOLI_PILGRIM_CLOAK)
	napoli_ball(model, frame, {0, 1.37, -0.13}, {0.08, 0.08, 0.1}, NAPOLI_PILGRIM_CLOAK)
	// The arms to the club.
	down := napoli_model_point(frame, {0, 0, 0})
	for side in 0..<2 {
		x := f32(0.22) if side == 0 else f32(-0.22)
		shoulder := napoli_model_point(frame, {x, 1.12, 0})
		bend := napoli_model_point(frame, {x*3, 0.6, -0.2})-down
		napoli_arm(model, shoulder, right_hand if side == 0 else left_hand, bend, NAPOLI_PILGRIM_CLOAK, NAPOLI_PILGRIM_CLOAK, NAPOLI_PILGRIM_GLOVE, 0.052)
	}
}

NAPOLI_NONNO_SKIN :: rl.Color{222, 170, 130, 255}
NAPOLI_NONNO_VEST :: rl.Color{244, 242, 232, 255}
NAPOLI_NONNO_SHORTS :: rl.Color{64, 104, 170, 255}
NAPOLI_NONNO_SOCK :: rl.Color{240, 240, 236, 255}
NAPOLI_NONNO_SANDAL :: rl.Color{126, 82, 48, 255}
NAPOLI_NONNO_STRAW :: rl.Color{226, 196, 120, 255}
NAPOLI_NONNO_BAND :: rl.Color{178, 40, 40, 255}
NAPOLI_NONNO_HAIR :: rl.Color{246, 244, 236, 255}

// The grandpa at the seaside, his feet at `frame`'s origin, stooping a little,
// his hands at `right_hand` and `left_hand`, his legs `walk` into a stride;
// `gasp` his mouth open (the club coming out of his pocket).
napoli_nonno_model :: proc(model: ^Napoli_Model, frame: rl.Matrix, right_hand, left_hand: rl.Vector3, walk: f32, gasp: bool) {
	for side in 0..<2 {
		x := f32(0.1) if side == 0 else f32(-0.1)
		stride := walk*(0.11 if side == 0 else -0.11)
		napoli_box(model, frame, {x, 0.02, 0.04+stride}, {0.1, 0.04, 0.21}, NAPOLI_NONNO_SANDAL)
		napoli_rod(model, napoli_model_point(frame, {x, 0.05, stride}), napoli_model_point(frame, {x, 0.2, stride*0.7}), 0.05, NAPOLI_NONNO_SOCK)
		napoli_rod(model, napoli_model_point(frame, {x, 0.2, stride*0.7}), napoli_model_point(frame, {x*0.95, 0.5, stride*0.2}), 0.05, NAPOLI_NONNO_SKIN)
		napoli_disc(model, frame, {x*0.95, 0.42, stride*0.25}, 0.075, 0.13, NAPOLI_NONNO_SHORTS)
	}
	// The shorts, the belly under the vest, the chest; all stooped forward.
	stoop := rl.MatrixRotateX(0.16)
	torso := frame*rl.MatrixTranslate(0, 0.5, 0)*stoop
	napoli_ball(model, frame, {0, 0.58, 0}, {0.22, 0.13, 0.18}, NAPOLI_NONNO_SHORTS)
	napoli_ball(model, torso, {0, 0.28, 0.07}, {0.24, 0.24, 0.24}, NAPOLI_NONNO_VEST)
	napoli_ball(model, torso, {0, 0.48, 0}, {0.2, 0.17, 0.15}, NAPOLI_NONNO_VEST)
	// The head: his neck, the head, the ears, the moustache and his nose, the hat.
	napoli_ball(model, torso, {0, 0.62, 0.02}, {0.07, 0.06, 0.07}, NAPOLI_NONNO_SKIN)
	napoli_ball(model, torso, {0, 0.74, 0.03}, {0.13, 0.14, 0.13}, NAPOLI_NONNO_SKIN)
	napoli_ball(model, torso, {0.125, 0.74, 0.02}, {0.025, 0.04, 0.03}, NAPOLI_NONNO_SKIN)
	napoli_ball(model, torso, {-0.125, 0.74, 0.02}, {0.025, 0.04, 0.03}, NAPOLI_NONNO_SKIN)
	napoli_ball(model, torso, {0, 0.73, 0.15}, {0.035, 0.035, 0.035}, NAPOLI_NONNO_SKIN)
	napoli_ball(model, torso, {0.045, 0.69, 0.13}, {0.05, 0.022, 0.03}, NAPOLI_NONNO_HAIR)
	napoli_ball(model, torso, {-0.045, 0.69, 0.13}, {0.05, 0.022, 0.03}, NAPOLI_NONNO_HAIR)
	if gasp { napoli_ball(model, torso, {0, 0.645, 0.125}, {0.025, 0.03, 0.02}, {40, 20, 20, 255}) }
	hat := rl.MatrixRotateZ(0.08)
	napoli_disc(model, torso, {0, 0.83, 0.03}, 0.25, 0.02, NAPOLI_NONNO_STRAW, hat)
	napoli_disc(model, torso, {0, 0.84, 0.03}, 0.13, 0.11, NAPOLI_NONNO_STRAW, hat)
	napoli_disc(model, torso, {0, 0.85, 0.03}, 0.136, 0.035, NAPOLI_NONNO_BAND, hat)
	// The arms, bare from his vest's straps to the club.
	down := napoli_model_point(frame, {0, 0, 0})
	for side in 0..<2 {
		x := f32(0.19) if side == 0 else f32(-0.19)
		shoulder := napoli_model_point(torso, {x, 0.55, 0})
		napoli_ball(model, torso, {x, 0.55, 0}, {0.065, 0.06, 0.065}, NAPOLI_NONNO_SKIN)
		bend := napoli_model_point(frame, {x*3, 0.5, -0.2})-down
		napoli_arm(model, shoulder, right_hand if side == 0 else left_hand, bend, NAPOLI_NONNO_SKIN, NAPOLI_NONNO_SKIN, NAPOLI_NONNO_SKIN, 0.048)
	}
}

// The parts drawn on the board (in its 3D pass): their ink, then their tones,
// `alpha` of them through the dither.
@(private)
draw_napoli_model :: proc(kit: ^Napoli_Model_Kit, model: ^Napoli_Model, alpha: f32) {
	if model.count == 0 || alpha <= 0.01 || !napoli_model_kit(kit) { return }
	maps: [12]rl.MaterialMap
	material := rl.Material{shader = kit.shader, maps = raw_data(maps[:])}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
	defer {
		rlgl.SetCullFace(.BACK)
		rlgl.DrawRenderBatchActive()
	}
	shown := clamp(alpha, 0, 1)
	rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.alpha_location), &shown, .FLOAT)
	for pass in 0..<2 {
		ink := f32(1 if pass == 0 else 0)
		rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.ink_location), &ink, .FLOAT)
		for &part in model.parts[:model.count] {
			// A mirrored frame (a model's own, X right, Y up, Z its front: a left
			// hand) turns its faces' winding: the faces culled turn with it.
			mirrored := rl.MatrixDeterminant(part.frame) < 0
			rlgl.DrawRenderBatchActive()
			rlgl.SetCullFace(.FRONT if (pass == 0) != mirrored else .BACK)
			base := [3]f32{f32(part.color.r)/255, f32(part.color.g)/255, f32(part.color.b)/255}
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.base_location), &base, .VEC3)
			frame := part.frame
			mesh := kit.sphere
			switch part.shape {
			case .Sphere:
			case .Cylinder: mesh = kit.cylinder
			case .Cube: mesh = kit.cube
			}
			if pass == 0 {
				// The ink's shell: the part a little fuller on every side.
				grow := rl.Vector3{1+NAPOLI_MODEL_INK/max(part.size.x, 0.005), 1+NAPOLI_MODEL_INK/max(part.size.y, 0.005), 1+NAPOLI_MODEL_INK/max(part.size.z, 0.005)}
				centre := rl.Vector3{0, 0.5, 0} if part.shape == .Cylinder else rl.Vector3{}
				frame = frame*rl.MatrixTranslate(centre.x, centre.y, centre.z)*rl.MatrixScale(grow.x, grow.y, grow.z)*
					rl.MatrixTranslate(-centre.x, -centre.y, -centre.z)
			}
			rl.DrawMesh(mesh, material, frame)
		}
	}
}
