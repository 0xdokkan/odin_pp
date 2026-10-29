package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import tween "../engine/tween"
import game "../game"

// FIRST PERSON BRAWLER's gloves (the user's choices of 2026-10-29): two neon
// gloves (Fase 3's style, the user's pick of three: blue-black carbon, magenta
// bands and neon tubes, a cyan rim of light), made from code as a 3D model but
// drawn as paper pixel art, held up in a boxer's guard at the bottom middle of the view
// as a person's own hands sit: the left (the lead) a little forward and higher,
// the right at the chin, both knuckles up and turned in, their cuffs cut by the
// bottom edge, the crosshair left clear. The model draws with a camera of its
// own (a first person viewmodel: it never goes into a wall) on a small canvas,
// FIRST_PERSON_GLOVE_PIXEL logical units to its pixel, in a few flat tones of
// each colour as a pixel artist shades (no smooth light), with the board's ink
// on every part's edge; that canvas is then cut out as a card is: an ink line
// round it, a band of the cards' paper, the card's thickness below and to the
// right; and laid on the view pixel for pixel. Each punch throws its own: the
// jab the left and the cross the right straight at the crosshair, turning palm
// down on the way (a corkscrew); the hooks round from their side, the arm level,
// the knuckles in. The other waits at the chin.

// The gloves' camera: at the origin looking down -Z (+X its right, +Y up).
FIRST_PERSON_GLOVE_FOV :: f32(55)
// The whole glove's size (1: about a real glove's, in metres) and its ink, in metres.
FIRST_PERSON_GLOVE_SCALE :: f32(0.78)
FIRST_PERSON_GLOVE_INK :: f32(0.0024)
// Logical units of the canvas to one pixel of the gloves (about the AK's print).
FIRST_PERSON_GLOVE_PIXEL :: f32(3)
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

// What a part is made of: each its own tones (FIRST_PERSON_GLOVE_FRAGMENT);
// the sword's steel and cyan light (first_person_zweihander.odin), and white
// (a perfect parry's flash).
First_Person_Glove_Stuff :: enum i32 {Carbon, Neon, Wrap, Steel, Cyan, White}

// One glove's shapes in its own frame (X right, Y the back of the hand, -Z the
// knuckles), for the left hand: the right mirrors X. A sphere or a cylinder
// (along +Z, from `at` toward the wrist), stretched by `size`.
First_Person_Glove_Part :: struct {
	cylinder: bool,
	stuff: First_Person_Glove_Stuff,
	at, size: rl.Vector3,
}

@(rodata)
FIRST_PERSON_GLOVE_PARTS := [?]First_Person_Glove_Part{
	// The mitt and its full knuckle roll, which squares its front.
	{at = {0, 0, -0.008}, size = {0.058, 0.052, 0.080}},
	{at = {0, 0.004, -0.046}, size = {0.056, 0.049, 0.046}},
	// The thumb along the inner side, toward the palm.
	{at = {0.046, -0.004, -0.018}, size = {0.023, 0.028, 0.050}},
	// The cuff and its two neon bands.
	{cylinder = true, at = {0, -0.004, 0.050}, size = {0.050, 0.110, 0.045}},
	{cylinder = true, stuff = .Neon, at = {0, -0.004, 0.046}, size = {0.0535, 0.018, 0.0485}},
	{cylinder = true, stuff = .Neon, at = {0, -0.004, 0.128}, size = {0.0525, 0.012, 0.0475}},
	// The wrapped forearm out of the cuff, on past the view's edge (never its end).
	{cylinder = true, stuff = .Wrap, at = {0, -0.004, 0.100}, size = {0.036, 0.420, 0.033}},
	// The neon stripe down the back of the hand.
	{stuff = .Neon, at = {0, 0.050, -0.014}, size = {0.013, 0.0060, 0.050}},
}

// The gloves' GPU handles: a sphere and a cylinder of radius and height 1, the
// model's tones, the small canvas it draws on (`low`) and the card cut from it
// (`paper`, by `paper_shader`). Made the first time the gloves are drawn, freed
// with the view. `ready`: `paper` holds this frame's gloves. The sword's own
// shapes the first time it is drawn: a cube, its blade and the blade's ink
// shell (first_person_zweihander.odin).
First_Person_Glove_Kit :: struct {
	sphere, cylinder: rl.Mesh,
	cube, blade, blade_ink: rl.Mesh,
	shader, paper_shader: rl.Shader,
	stuff_location, ink_location, texel_location, part_location: i32,
	low, paper: rl.RenderTexture2D,
	ready, failed: bool,
}

FIRST_PERSON_GLOVE_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;
out vec3 fragPos;
out vec3 fragNormal;
out vec3 fragLocal;
void main() {
    fragLocal = vertexPosition;
    fragPos = vec3(matModel*vec4(vertexPosition, 1.0));
    fragNormal = mat3(matNormal)*vertexNormal;
    gl_Position = mvp*vec4(vertexPosition, 1.0);
}
`

// A pixel artist's shading: a key light from the upper left makes three flat
// tones of the carbon (shade, base, light), a sharp gloss one more spot, a rim
// of cyan light along its edge; the neon bands and tubes are lit, flat (only
// their shaded side a darker magenta). `ink` draws the board's ink (the
// outline's shell). `part` names the piece (FIRST_PERSON_GLOVE_PARTS' order);
// the tubes sit on the piece's own unit shape (`fragLocal`).
FIRST_PERSON_GLOVE_FRAGMENT :: `#version 330
in vec3 fragPos;
in vec3 fragNormal;
in vec3 fragLocal;
uniform float stuff;
uniform float ink;
uniform float part;
out vec4 finalColor;
const vec3 CARBON[4] = vec3[](vec3(10, 8, 24), vec3(24, 18, 48), vec3(44, 34, 84), vec3(126, 112, 210));
const vec3 MAGENTA = vec3(255, 64, 206);
const vec3 MAGENTA_DIM = vec3(150, 22, 120);
const vec3 CYAN = vec3(60, 240, 255);
const vec3 CYAN_DIM = vec3(18, 128, 168);
const vec3 STEEL[4] = vec3[](vec3(52, 62, 88), vec3(118, 134, 166), vec3(192, 206, 228), vec3(250, 252, 255));
void main() {
    if (ink > 0.5) { finalColor = vec4(13.0, 20.0, 30.0, 255.0)/255.0; return; }
    if (stuff > 4.5) { finalColor = vec4(1.0); return; }
    vec3 n = normalize(fragNormal);
    vec3 v = normalize(-fragPos);
    vec3 key = normalize(vec3(-0.45, 0.80, 0.45));
    float wrap = dot(n, key)*0.5+0.5;
    float gloss = pow(max(dot(n, normalize(key+v)), 0.0), 40.0);
    float rim = 1.0-max(dot(n, v), 0.0);
    int tone = wrap < 0.50 ? 0 : (wrap < 0.82 ? 1 : 2);
    vec3 l = fragLocal;
    int p = int(part+0.5);
    vec3 c;
    if (stuff > 3.5) { c = tone == 0 ? CYAN_DIM : CYAN; }
    else if (stuff > 2.5) {
        c = STEEL[gloss > 0.5 ? 3 : tone];
        if (rim > 0.74) { c = CYAN; }
    }
    else if (stuff > 1.5) { c = CARBON[gloss > 0.55 ? 3 : tone]*0.8; }
    else if (stuff > 0.5) { c = tone == 0 ? MAGENTA_DIM : MAGENTA; }
    else {
        c = CARBON[gloss > 0.55 ? 3 : tone];
        if (rim > 0.68) { c = CYAN; }
    }
    // The neon tubes: a seam across the knuckles, two along the back of the
    // hand, a ring round the cuff and one along its top, rings round the wraps
    // near the cuff.
    bool tube = p == 1 && abs(l.y-0.30) < 0.08 && l.z < 0.25;
    tube = tube || (p == 0 && l.y > 0.25 && abs(abs(l.x)-0.42) < 0.06 && l.z > -0.70 && l.z < 0.75);
    tube = tube || (p == 3 && abs(l.y-0.55) < 0.05);
    tube = tube || (p == 3 && l.z < -0.75 && abs(l.x) < 0.07 && l.y > 0.15 && l.y < 0.95);
    tube = tube || (p == 6 && l.y < 0.5 && abs(fract(l.y*6.0)-0.5) < 0.035);
    if (tube) { c = MAGENTA; }
    finalColor = vec4(c/255.0, 1.0);
}
`

// The card cut from the small canvas, pixel by pixel: the gloves as drawn; an
// ink line round them; a band of the cards' paper with its grain; the card's
// thickness one pixel below and to the right of the paper; nothing else.
FIRST_PERSON_GLOVE_PAPER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 texel;
out vec4 finalColor;
bool near(vec2 uv, float r) {
    for (int y = -3; y <= 3; y++) {
        for (int x = -3; x <= 3; x++) {
            if (float(x*x+y*y) > r*r+0.25) continue;
            if (texture(texture0, uv+vec2(x, y)*texel).a > 0.5) return true;
        }
    }
    return false;
}
void main() {
    vec2 uv = fragTexCoord;
    vec4 c = texture(texture0, uv);
    if (c.a > 0.5) { finalColor = c; return; }
    if (near(uv, 1.0)) { finalColor = vec4(13.0, 20.0, 30.0, 255.0)/255.0; return; }
    vec2 cell = floor(uv/texel);
    float grain = fract(sin(dot(cell, vec2(12.9898, 78.233)))*43758.5453);
    if (near(uv, 2.6)) { finalColor = vec4(vec3(241.0, 239.0, 230.0)/255.0*(0.965+0.035*grain), 1.0); return; }
    if (near(uv+vec2(-1.0, 1.0)*texel, 2.6)) { finalColor = vec4(164.0, 152.0, 131.0, 255.0)/255.0; return; }
    finalColor = vec4(0.0);
}
`

@(private)
first_person_glove_kit :: proc(f: ^First_Person_View) -> ^First_Person_Glove_Kit {
	kit := &f.gloves
	if kit.shader.id != 0 || kit.failed { return kit }
	shader := rl.LoadShaderFromMemory(FIRST_PERSON_GLOVE_VERTEX, FIRST_PERSON_GLOVE_FRAGMENT)
	paper := rl.LoadShaderFromMemory(nil, FIRST_PERSON_GLOVE_PAPER)
	if shader.id == 0 || shader.id == rlgl.GetShaderIdDefault() || paper.id == 0 || paper.id == rlgl.GetShaderIdDefault() {
		if shader.id != 0 && shader.id != rlgl.GetShaderIdDefault() { rl.UnloadShader(shader) }
		if paper.id != 0 && paper.id != rlgl.GetShaderIdDefault() { rl.UnloadShader(paper) }
		kit.failed = true
		return kit
	}
	kit.shader, kit.paper_shader = shader, paper
	kit.stuff_location = rl.GetShaderLocation(shader, "stuff")
	kit.ink_location = rl.GetShaderLocation(shader, "ink")
	kit.texel_location = rl.GetShaderLocation(paper, "texel")
	kit.part_location = rl.GetShaderLocation(shader, "part")
	kit.sphere = rl.GenMeshSphere(1, 24, 32)
	kit.cylinder = rl.GenMeshCylinder(1, 1, 32)
	return kit
}

@(private)
destroy_first_person_glove_kit :: proc(kit: ^First_Person_Glove_Kit) {
	if kit.sphere.vaoId != 0 { rl.UnloadMesh(kit.sphere) }
	if kit.cylinder.vaoId != 0 { rl.UnloadMesh(kit.cylinder) }
	if kit.cube.vaoId != 0 { rl.UnloadMesh(kit.cube) }
	if kit.blade.vaoId != 0 { rl.UnloadMesh(kit.blade) }
	if kit.blade_ink.vaoId != 0 { rl.UnloadMesh(kit.blade_ink) }
	if kit.shader.id != 0 { rl.UnloadShader(kit.shader) }
	if kit.paper_shader.id != 0 { rl.UnloadShader(kit.paper_shader) }
	if kit.low.id != 0 { rl.UnloadRenderTexture(kit.low) }
	if kit.paper.id != 0 { rl.UnloadRenderTexture(kit.paper) }
	kit^ = {}
}

// The small canvases, `w` by `h` pixels (made again when the view's size changes).
@(private = "file")
first_person_glove_canvases :: proc(kit: ^First_Person_Glove_Kit, w, h: c.int) -> bool {
	if kit.low.id != 0 && kit.low.texture.width == w && kit.low.texture.height == h { return true }
	if kit.low.id != 0 { rl.UnloadRenderTexture(kit.low) }
	if kit.paper.id != 0 { rl.UnloadRenderTexture(kit.paper) }
	kit.low, kit.paper = rl.LoadRenderTexture(w, h), rl.LoadRenderTexture(w, h)
	if !rl.IsRenderTextureValid(kit.low) || !rl.IsRenderTextureValid(kit.paper) {
		if kit.low.id != 0 { rl.UnloadRenderTexture(kit.low) }
		if kit.paper.id != 0 { rl.UnloadRenderTexture(kit.paper) }
		kit.low, kit.paper = {}, {}
		return false
	}
	rl.SetTextureFilter(kit.low.texture, .POINT)
	rl.SetTextureFilter(kit.paper.texture, .POINT)
	// The cut never wraps round to the canvas's other edge.
	rl.SetTextureWrap(kit.low.texture, .CLAMP)
	rl.SetTextureWrap(kit.paper.texture, .CLAMP)
	return true
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
@(private)
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

// Whether the view shows the gloves now, and how far up they have come (0..1).
@(private = "file")
first_person_gloves_shown :: proc(renderer: ^Renderer) -> (ready: f32, shown: bool) {
	f := &renderer.tactical.first_person
	hand := FIRST_PERSON_LOOKS[f.weapon].hand
	// The sword's blade draws on the same small canvas (first_person_sword.odin).
	if f.amount <= 0 || (hand != .Fists && hand != .Sword) { return }
	amount := first_person_amount(renderer)
	if amount <= FIRST_PERSON_AK_FROM { return }
	return tween.smoothstep(clamp((amount-FIRST_PERSON_AK_FROM)/(1-FIRST_PERSON_AK_FROM), 0, 1)), true
}

// The model of both gloves, in their camera, on the target bound now.
@(private = "file")
draw_first_person_glove_models :: proc(renderer: ^Renderer, kit: ^First_Person_Glove_Kit, ready: f32) {
	f := &renderer.tactical.first_person
	now := renderer.sprite_assets.elapsed
	camera := first_person_glove_camera()
	maps: [12]rl.MaterialMap
	material := rl.Material{shader = kit.shader, maps = raw_data(maps[:])}
	rl.BeginMode3D(camera)
	rlgl.EnableBackfaceCulling()
	for side in 0..<2 {
		left := side == 0
		glove := first_person_glove_frame(first_person_glove_pose(side, f.fists_punch, f.fists_clock, ready, f.fists_run, now))
		// First the ink: each part's shell a little fuller, its inside only;
		// then the parts, which cover it but at their edges.
		for pass in 0..<2 {
			ink := f32(1 if pass == 0 else 0)
			rlgl.SetCullFace(.FRONT if pass == 0 else .BACK)
			rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.ink_location), &ink, .FLOAT)
			for part, index in FIRST_PERSON_GLOVE_PARTS {
				stuff, piece := f32(part.stuff), f32(index)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.stuff_location), &stuff, .FLOAT)
				rl.SetShaderValue(kit.shader, rl.ShaderLocationIndex(kit.part_location), &piece, .FLOAT)
				grow := FIRST_PERSON_GLOVE_INK if pass == 0 else 0
				rl.DrawMesh(kit.cylinder if part.cylinder else kit.sphere, material, glove*first_person_glove_part_frame(part, left, grow))
			}
		}
	}
	rlgl.SetCullFace(.BACK)
	rl.EndMode3D()
}

// The gloves' camera (at the origin, looking down -Z).
@(private)
first_person_glove_camera :: proc() -> rl.Camera3D {
	return {position = {0, 0, 0}, target = {0, 0, -1}, up = {0, 1, 0}, fovy = FIRST_PERSON_GLOVE_FOV, projection = .PERSPECTIVE}
}

// Speed lines of a punch on its way out (every punch, the user's choice), as a
// comic draws them, on the small canvas `w` by `h` (stored upside down, as
// `paper` is read): the glove's front flies at the crosshair, so short rays of
// magenta and cyan burst round it, away from its arm, longer the faster it
// goes; a hook also trails three lines along the curve it swept in the last
// FIRST_PERSON_GLOVE_STREAK_STEPS steps of FIRST_PERSON_GLOVE_STREAK_SECONDS.
FIRST_PERSON_GLOVE_STREAK_STEPS :: 5
FIRST_PERSON_GLOVE_STREAK_SECONDS :: f32(0.025)
FIRST_PERSON_GLOVE_RAYS :: 9
@(private = "file")
draw_first_person_glove_streaks :: proc(renderer: ^Renderer, w, h: c.int, ready: f32) {
	f := &renderer.tactical.first_person
	punch := f.fists_punch
	if punch == .None || f.fists_clock > game.FISTS_PUNCHES[punch].land+0.01 { return }
	u := first_person_glove_reach(punch, f.fists_clock)
	if u < 0.12 { return }
	side := 0 if punch == .Jab || punch == .Left_Hook else 1
	now := renderer.sprite_assets.elapsed
	camera := first_person_glove_camera()
	// On the canvas: the glove's front (its knuckles) and its cuff.
	shown :: proc(camera: rl.Camera3D, point: rl.Vector3, w, h: c.int) -> rl.Vector2 {
		screen := rl.GetWorldToScreenEx(point, camera, w, h)
		return {screen.x, f32(h)-screen.y}
	}
	ends :: proc(pose: First_Person_Glove_Pose) -> (front, cuff: rl.Vector3) {
		frame := first_person_glove_frame(pose)
		front4 := frame*[4]f32{0, 0.004, -0.09, 1}
		cuff4 := frame*[4]f32{0, -0.004, 0.10, 1}
		return front4.xyz, cuff4.xyz
	}
	pose := first_person_glove_pose(side, punch, f.fists_clock, ready, f.fists_run, now)
	front3, cuff3 := ends(pose)
	front, cuff := shown(camera, front3, w, h), shown(camera, cuff3, w, h)
	// The glove's half width on the canvas at its front's depth.
	half := 0.058*FIRST_PERSON_GLOVE_SCALE/(max(-front3.z, 0.05)*math.tan(FIRST_PERSON_GLOVE_FOV*math.PI/360))*f32(h)*0.5
	colors := [2]rl.Color{{255, 64, 206, 255}, {60, 240, 255, 255}}
	// Faster early on: the reach climbs steepest in the middle of its way out.
	speed := clamp(1-abs(u-0.5)*1.4, 0.3, 1)
	arm := cuff-front
	arm_angle := math.atan2(arm.y, arm.x)
	for k in 0..<FIRST_PERSON_GLOVE_RAYS {
		angle := arm_angle+math.PI*0.35+f32(k)*(math.PI*1.3)/f32(FIRST_PERSON_GLOVE_RAYS-1)
		way := rl.Vector2{math.cos(angle), math.sin(angle)}
		inner := half*(1.15+0.12*f32(k%2))
		outer := inner+half*(0.5+0.3*f32((k*7)%3))*speed
		a, b := front+way*inner, front+way*outer
		// Two pixels thick, so a ray reads at a glance.
		rl.DrawLineEx({math.round(a.x), math.round(a.y)}, {math.round(b.x), math.round(b.y)}, 2, colors[k%2])
	}
	if punch != .Left_Hook && punch != .Right_Hook { return }
	points: [FIRST_PERSON_GLOVE_STREAK_STEPS]rl.Vector2
	for &point, k in points {
		clock := max(0, f.fists_clock-f32(k)*FIRST_PERSON_GLOVE_STREAK_SECONDS)
		earlier, _ := ends(first_person_glove_pose(side, punch, clock, ready, f.fists_run, now))
		point = shown(camera, earlier, w, h)
	}
	for lane in 0..<3 {
		offset := f32(lane-1)*half*0.7
		for k in 0..<FIRST_PERSON_GLOVE_STREAK_STEPS-1 {
			// The outer lanes a step shorter, so the lines taper.
			if lane != 1 && k == FIRST_PERSON_GLOVE_STREAK_STEPS-2 { continue }
			a, b := points[k], points[k+1]
			way := b-a
			length := math.sqrt(way.x*way.x+way.y*way.y)
			if length < 0.5 { continue }
			across := rl.Vector2{-way.y, way.x}/length*offset
			rl.DrawLineV({math.round(a.x+across.x), math.round(a.y+across.y)}, {math.round(b.x+across.x), math.round(b.y+across.y)}, colors[lane%2])
		}
	}
}

// Between the board and the HUD, no target bound (end_tactical_surface): the
// model on the small canvas, then the card cut from it.
@(private)
prepare_first_person_gloves :: proc(renderer: ^Renderer) {
	f := &renderer.tactical.first_person
	f.gloves.ready = false
	ready, shown := first_person_gloves_shown(renderer)
	if !shown { return }
	kit := first_person_glove_kit(f)
	if kit.shader.id == 0 { return }
	w := c.int(max(math.round(renderer.canvas_width/FIRST_PERSON_GLOVE_PIXEL), 1))
	h := c.int(max(math.round(renderer.canvas_height/FIRST_PERSON_GLOVE_PIXEL), 1))
	if !first_person_glove_canvases(kit, w, h) { return }
	rl.BeginTextureMode(kit.low)
	rl.ClearBackground(rl.BLANK)
	// The marks first, on the board behind the gloves, the star over them; the cut gives them ink and paper too.
	if FIRST_PERSON_LOOKS[f.weapon].hand == .Sword {
		draw_first_person_sword_pixel(renderer, w, h, ready)
		draw_first_person_zweihander(renderer, kit, ready)
	} else {
		draw_first_person_marks_pixel(renderer, w, h)
		draw_first_person_glove_models(renderer, kit, ready)
		draw_first_person_marks_pixel(renderer, w, h, star = true)
	}
	rl.EndTextureMode()
	rl.BeginTextureMode(kit.paper)
	rl.ClearBackground(rl.BLANK)
	// The speed lines and the star's sparks first: the card's gloves and paper cover them where they lie.
	draw_first_person_glove_streaks(renderer, w, h, ready)
	draw_first_person_star_sparks(renderer, w, h)
	texel := [2]f32{1/f32(w), 1/f32(h)}
	rl.SetShaderValue(kit.paper_shader, rl.ShaderLocationIndex(kit.texel_location), &texel, .VEC2)
	rl.BeginShaderMode(kit.paper_shader)
	rl.DrawTextureRec(kit.low.texture, {0, 0, f32(w), f32(h)}, {}, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
	kit.ready = true
}

// The two gloves over the board: the card prepare_first_person_gloves cut this
// frame, pixel for pixel; without it (no board surface) the model straight on
// the view.
@(private)
draw_first_person_gloves :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	if room == nil { return }
	f := &renderer.tactical.first_person
	kit := &f.gloves
	if kit.ready {
		kit.ready = false
		paper := kit.paper.texture
		// Drawn once into `paper` from `low`, it stands the right way up already.
		rl.DrawTexturePro(paper, {0, 0, f32(paper.width), f32(paper.height)}, {0, 0, renderer.canvas_width, renderer.canvas_height}, {}, 0, rl.WHITE)
		return
	}
	ready, shown := first_person_gloves_shown(renderer)
	if !shown || FIRST_PERSON_LOOKS[f.weapon].hand != .Fists { return }
	kit = first_person_glove_kit(f)
	if kit.shader.id == 0 { return }
	draw_first_person_glove_models(renderer, kit, ready)
}
