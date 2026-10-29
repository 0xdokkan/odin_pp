package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import tween "../engine/tween"
import game "../game"

// FIRST PERSON BRAWLER's gloves (the user's choice of 2026-10-29): two real 3D
// gloves of black leather with gold bands, made from code, held up in a
// boxer's guard at the bottom middle of the view as a person's own hands sit:
// the left (the lead) a little forward and higher, the right at the chin, both
// knuckles up and turned in, their cuffs cut by the bottom edge, the crosshair
// left clear. They are drawn over the board with a camera of their own (a first
// person viewmodel: the board's depth is cleared before the HUD, so they never
// go into a wall), in a light of their own, with the board's ink round them.
// Each punch throws its own: the jab the left and the cross the right straight
// at the crosshair, turning palm down on the way (a corkscrew); the hooks round
// from their side, the arm level, the knuckles in. The other waits at the chin.

// The gloves' camera: at the origin looking down -Z (+X its right, +Y up).
FIRST_PERSON_GLOVE_FOV :: f32(55)
// The whole glove's size (1: about a real glove's, in metres) and its ink, in metres.
FIRST_PERSON_GLOVE_SCALE :: f32(0.78)
FIRST_PERSON_GLOVE_INK :: f32(0.0022)
FIRST_PERSON_GLOVE_LEATHER :: rl.Color{20, 18, 22, 255}
FIRST_PERSON_GLOVE_GOLD :: rl.Color{236, 178, 66, 255}
FIRST_PERSON_GLOVE_WRAP :: rl.Color{58, 54, 62, 255}
// The marks' height on a foe's card, as a part of its outline's top (its chest).
FIRST_PERSON_MARK_HEIGHT :: f32(0.6)

// Where a glove is and how it is turned in the gloves' camera: `pitch` lifts its
// knuckles (its -Z), `yaw` turns them right (negative) or left, `roll` turns it
// round its own length, the thumb's side up.
First_Person_Glove_Pose :: struct {
	at: rl.Vector3,
	pitch, yaw, roll: f32,
}

// The guard: the left (lead) glove forward and higher, the right at the chin.
// Each glove's thumb is on its inner side; the right's numbers are the left's
// mirrored except where its place differs.
@(rodata)
FIRST_PERSON_GLOVE_GUARD := [2]First_Person_Glove_Pose{
	{at = {-0.068, -0.092, -0.38}, pitch = 0.62, yaw = -0.16, roll = 0.22},
	{at = {0.074, -0.098, -0.32}, pitch = 0.70, yaw = 0.20, roll = -0.26},
}
// A straight punch landed: at the crosshair, the knuckles forward, palm down.
@(rodata)
FIRST_PERSON_GLOVE_STRAIGHT := [2]First_Person_Glove_Pose{
	{at = {-0.025, -0.040, -0.64}, pitch = 0.06, yaw = -0.06, roll = 0.02},
	{at = {0.025, -0.040, -0.64}, pitch = 0.06, yaw = 0.06, roll = -0.02},
}
// A hook: out wide of its side, then landed just past the middle, the arm level
// and the knuckles turned in.
@(rodata)
FIRST_PERSON_GLOVE_HOOK_WIDE := [2]rl.Vector3{{-0.30, -0.05, -0.40}, {0.30, -0.05, -0.40}}
@(rodata)
FIRST_PERSON_GLOVE_HOOK := [2]First_Person_Glove_Pose{
	{at = {0.04, -0.045, -0.52}, pitch = 0.10, yaw = -1.25, roll = 1.30},
	{at = {-0.04, -0.045, -0.52}, pitch = 0.10, yaw = 1.25, roll = -1.30},
}

// One glove's shapes in its own frame (X right, Y the back of the hand, -Z the
// knuckles), for the left hand: the right mirrors X. A sphere or a cylinder
// (along +Z, from `at` toward the wrist), stretched by `size`, of leather, gold
// or the wraps of the forearm.
First_Person_Glove_Part :: struct {
	cylinder, gold, wrap: bool,
	at, size: rl.Vector3,
}

@(rodata)
FIRST_PERSON_GLOVE_PARTS := [?]First_Person_Glove_Part{
	// The mitt and its full knuckle roll, which squares its front.
	{at = {0, 0, -0.008}, size = {0.058, 0.052, 0.080}},
	{at = {0, 0.004, -0.046}, size = {0.056, 0.049, 0.046}},
	// The thumb along the inner side, toward the palm.
	{at = {0.046, -0.004, -0.018}, size = {0.023, 0.028, 0.050}},
	// The cuff and its two gold bands.
	{cylinder = true, at = {0, -0.004, 0.050}, size = {0.050, 0.110, 0.045}},
	{cylinder = true, gold = true, at = {0, -0.004, 0.046}, size = {0.0535, 0.018, 0.0485}},
	{cylinder = true, gold = true, at = {0, -0.004, 0.128}, size = {0.0525, 0.012, 0.0475}},
	// The wrapped forearm out of the cuff, on past the view's edge (never its end).
	{cylinder = true, wrap = true, at = {0, -0.004, 0.100}, size = {0.036, 0.420, 0.033}},
	// The gold stripe down the back of the hand.
	{gold = true, at = {0, 0.050, -0.014}, size = {0.013, 0.0060, 0.050}},
}

// The gloves' GPU handles: a sphere and a cylinder of radius and height 1, and
// their light. Made the first time the gloves are drawn, freed with the view.
First_Person_Glove_Kit :: struct {
	sphere, cylinder: rl.Mesh,
	shader: rl.Shader,
	metal_location, ink_location: i32,
	failed: bool,
}

FIRST_PERSON_GLOVE_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;
out vec3 fragPos;
out vec3 fragNormal;
void main() {
    fragPos = vec3(matModel*vec4(vertexPosition, 1.0));
    fragNormal = mat3(matNormal)*vertexNormal;
    gl_Position = mvp*vec4(vertexPosition, 1.0);
}
`

// Leather: a warm key light from the upper left, a cool fill from below on the
// right, a sharp gloss and a broad sheen, a gold rim from the arena behind;
// gold: a metal that mirrors a warm sky above and a dark floor below. `ink`
// draws the colour flat (the outline's shell).
FIRST_PERSON_GLOVE_FRAGMENT :: `#version 330
in vec3 fragPos;
in vec3 fragNormal;
uniform vec4 colDiffuse;
uniform float metal;
uniform float ink;
out vec4 finalColor;
void main() {
    if (ink > 0.5) { finalColor = vec4(colDiffuse.rgb, 1.0); return; }
    vec3 n = normalize(fragNormal);
    vec3 v = normalize(-fragPos);
    vec3 key = normalize(vec3(-0.45, 0.80, 0.45));
    vec3 fill = normalize(vec3(0.60, -0.35, 0.40));
    float wrap = pow(dot(n, key)*0.5+0.5, 2.0);
    float under = max(dot(n, fill), 0.0);
    float facing = max(dot(n, v), 0.0);
    float rim = pow(1.0-facing, 3.0);
    vec3 h = normalize(key+v);
    float gloss = pow(max(dot(n, h), 0.0), 56.0);
    float sheen = pow(max(dot(n, h), 0.0), 7.0);
    vec3 base = colDiffuse.rgb;
    vec3 c;
    if (metal > 0.5) {
        vec3 sky = mix(vec3(0.22, 0.13, 0.05), vec3(1.15, 1.0, 0.78), smoothstep(-0.6, 0.8, reflect(-v, n).y));
        c = base*(0.18+0.55*wrap)+base*sky*0.55+mix(base, vec3(1.0), 0.4)*gloss*1.1+base*rim*0.35;
    } else {
        c = base*(0.55+1.6*wrap)+vec3(0.32, 0.38, 0.55)*under*0.10;
        c += vec3(1.0, 0.95, 0.88)*(gloss*0.55+sheen*0.05);
        c += vec3(0.95, 0.70, 0.30)*rim*0.30;
    }
    finalColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
`

@(private = "file")
first_person_glove_kit :: proc(f: ^First_Person_View) -> ^First_Person_Glove_Kit {
	kit := &f.gloves
	if kit.shader.id != 0 || kit.failed { return kit }
	shader := rl.LoadShaderFromMemory(FIRST_PERSON_GLOVE_VERTEX, FIRST_PERSON_GLOVE_FRAGMENT)
	if shader.id == 0 || shader.id == rlgl.GetShaderIdDefault() {
		kit.failed = true
		return kit
	}
	kit.shader = shader
	kit.metal_location = rl.GetShaderLocation(shader, "metal")
	kit.ink_location = rl.GetShaderLocation(shader, "ink")
	kit.sphere = rl.GenMeshSphere(1, 24, 32)
	kit.cylinder = rl.GenMeshCylinder(1, 1, 32)
	return kit
}

@(private)
destroy_first_person_glove_kit :: proc(kit: ^First_Person_Glove_Kit) {
	if kit.sphere.vaoId != 0 { rl.UnloadMesh(kit.sphere) }
	if kit.cylinder.vaoId != 0 { rl.UnloadMesh(kit.cylinder) }
	if kit.shader.id != 0 { rl.UnloadShader(kit.shader) }
	kit^ = {}
}

@(private = "file")
first_person_glove_mix :: proc(a, b: First_Person_Glove_Pose, u: f32) -> First_Person_Glove_Pose {
	return {at = a.at+(b.at-a.at)*u, pitch = a.pitch+(b.pitch-a.pitch)*u, yaw = a.yaw+(b.yaw-a.yaw)*u, roll = a.roll+(b.roll-a.roll)*u}
}

// A glove's pose (`side` 0 the left, 1 the right) with `punch` out `clock`
// seconds; `ready` 0..1 raises the guard from under the view as it comes in,
// `run` 0..1 rocks it at the running pace, on the sprite clock `now`.
first_person_glove_pose :: proc(side: int, punch: game.First_Person_Punch, clock, ready, run: f32, now: f64) -> First_Person_Glove_Pose {
	left := side == 0
	pose := FIRST_PERSON_GLOVE_GUARD[side]
	mine := (punch == .Jab || punch == .Left_Hook) if left else (punch == .Cross || punch == .Right_Hook)
	if mine {
		u := first_person_glove_reach(punch, clock)
		if punch == .Left_Hook || punch == .Right_Hook {
			// Round from its side: a curve through a point out wide of it.
			landed := FIRST_PERSON_GLOVE_HOOK[side]
			wide := FIRST_PERSON_GLOVE_HOOK_WIDE[side]
			a := pose.at+(wide-pose.at)*u
			b := wide+(landed.at-wide)*u
			turned := first_person_glove_mix(pose, landed, u)
			pose = turned
			pose.at = a+(b-a)*u
		} else {
			pose = first_person_glove_mix(pose, FIRST_PERSON_GLOVE_STRAIGHT[side], u)
		}
	} else if punch != .None {
		// The other hand tucks in to the chin while one is out.
		u := first_person_glove_reach(punch, clock)
		pose.at += {(0.012 if left else -0.012)*u, 0.010*u, 0.025*u}
	}
	// Breathing at rest, rocking as he runs (the two hands opposite), rising in.
	sway := f32(math.sin(now*11))*run
	breath := f32(math.sin(now*2.1))*0.0025*(1-run)
	pose.at.y += breath+sway*(0.010 if left else -0.010)-(1-ready)*0.28
	pose.at.x += f32(math.sin(now*5.5))*0.005*run
	return pose
}

// The glove's frame in the gloves' camera: turned round its length, lifted,
// turned, then placed.
@(private = "file")
first_person_glove_frame :: proc(pose: First_Person_Glove_Pose) -> rl.Matrix {
	return rl.MatrixTranslate(pose.at.x, pose.at.y, pose.at.z)*rl.MatrixRotateY(pose.yaw)*rl.MatrixRotateX(pose.pitch)*
		rl.MatrixRotateZ(pose.roll)*rl.MatrixScale(FIRST_PERSON_GLOVE_SCALE, FIRST_PERSON_GLOVE_SCALE, FIRST_PERSON_GLOVE_SCALE)
}

// A part's matrix in the glove's frame, `grow` metres fuller on every side (the ink's shell).
@(private = "file")
first_person_glove_part_frame :: proc(part: First_Person_Glove_Part, left: bool, grow: f32) -> rl.Matrix {
	at := part.at
	if !left { at.x = -at.x }
	if part.cylinder {
		// Its height along +Z (the cylinder stands on +Y), the ink's shell also longer at both ends.
		return rl.MatrixTranslate(at.x, at.y, at.z-grow)*rl.MatrixRotateX(math.PI/2)*
			rl.MatrixScale(part.size.x+grow, part.size.y+grow*2, part.size.z+grow)
	}
	return rl.MatrixTranslate(at.x, at.y, at.z)*rl.MatrixScale(part.size.x+grow, part.size.y+grow, part.size.z+grow)
}

// The two gloves, over the board, in their own camera.
@(private)
draw_first_person_gloves :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	if room == nil { return }
	f := &renderer.tactical.first_person
	kit := first_person_glove_kit(f)
	if kit.shader.id == 0 { return }
	fists := &room.first_person.fists
	ready := tween.smoothstep(clamp((first_person_amount(renderer)-FIRST_PERSON_AK_FROM)/(1-FIRST_PERSON_AK_FROM), 0, 1))
	speed := math.sqrt(fists.velocity.x*fists.velocity.x+fists.velocity.y*fists.velocity.y)
	run := clamp(speed/game.FISTS_SPEED, 0, 1)
	camera := rl.Camera3D{position = {0, 0, 0}, target = {0, 0, -1}, up = {0, 1, 0}, fovy = FIRST_PERSON_GLOVE_FOV, projection = .PERSPECTIVE}
	maps: [12]rl.MaterialMap
	material := rl.Material{shader = kit.shader, maps = raw_data(maps[:])}
	rl.BeginMode3D(camera)
	rlgl.EnableBackfaceCulling()
	for side in 0..<2 {
		left := side == 0
		glove := first_person_glove_frame(first_person_glove_pose(side, fists.punch, fists.punch_clock, ready, run, now))
		// First the ink: each part's shell a little fuller, its inside only;
		// then the parts, which cover it but at their edges.
		for pass in 0..<2 {
			ink := f32(1 if pass == 0 else 0)
			rlgl.SetCullFace(.FRONT if pass == 0 else .BACK)
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.ink_location), &ink, .FLOAT)
			for part in FIRST_PERSON_GLOVE_PARTS {
				metal := f32(1 if part.gold else 0)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.metal_location), &metal, .FLOAT)
				maps[0].color = LIVING_TOKEN_INK if pass == 0 else (FIRST_PERSON_GLOVE_GOLD if part.gold else (FIRST_PERSON_GLOVE_WRAP if part.wrap else FIRST_PERSON_GLOVE_LEATHER))
				grow := FIRST_PERSON_GLOVE_INK if pass == 0 else 0
				rl.DrawMesh(kit.cylinder if part.cylinder else kit.sphere, material, glove*first_person_glove_part_frame(part, left, grow))
			}
		}
	}
	rlgl.SetCullFace(.BACK)
	rl.EndMode3D()
}
