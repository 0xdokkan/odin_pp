package gfx

import rl "vendor:raylib"

// Directional sun, ambient, one dynamic point light and distance fog. Works
// for meshes (DrawModel) and for immediate-mode shapes drawn between
// lighting_begin/lighting_end, because it relies on vertex colours and the
// model matrix instead of material uniforms.
LIT_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
uniform mat4 mvp;
uniform mat4 matModel;
out vec3 fragPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragTexCoord;
void main() {
    fragPos = vec3(matModel * vec4(vertexPosition, 1.0));
    fragNormal = mat3(matModel) * vertexNormal;
    fragColor = vertexColor;
    fragTexCoord = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

LIT_FRAGMENT :: `#version 330
in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec3 sunDir;
uniform vec3 sunColor;
uniform vec3 ambient;
uniform vec3 viewPos;
uniform vec4 fogColor;
uniform vec2 fogRange;
uniform vec3 pointPos;
uniform vec3 pointColor;
uniform float pointRadius;
out vec4 finalColor;
void main() {
    vec4 base = texture(texture0, fragTexCoord) * fragColor;
    if (base.a < 0.02) discard;
    vec3 n = length(fragNormal) > 0.001 ? normalize(fragNormal) : vec3(0.0, 1.0, 0.0);
    vec3 light = ambient + sunColor * max(dot(n, -normalize(sunDir)), 0.0);
    if (pointRadius > 0.0) {
        vec3 d = pointPos - fragPos;
        float dist = length(d);
        float att = clamp(1.0 - dist / pointRadius, 0.0, 1.0);
        light += pointColor * att * att * max(dot(n, d / max(dist, 0.0001)), 0.0);
    }
    vec3 color = base.rgb * light;
    float viewDist = length(viewPos - fragPos);
    float fog = clamp((viewDist - fogRange.x) / max(fogRange.y - fogRange.x, 0.001), 0.0, 1.0);
    finalColor = vec4(mix(color, fogColor.rgb, fog * fogColor.a), base.a);
}
`

Lighting :: struct {
	shader:       rl.Shader,
	ok:           bool,
	sun_dir:      Vec3,
	sun_color:    Vec3,
	ambient:      Vec3,
	fog_color:    rl.Color,
	fog_near:     f32,
	fog_far:      f32,
	point_pos:    Vec3,
	point_color:  Vec3,
	point_radius: f32,
	loc_sun_dir, loc_sun_color, loc_ambient, loc_view, loc_fog_color, loc_fog_range: i32,
	loc_point_pos, loc_point_color, loc_point_radius, loc_model: i32,
}

lighting_create :: proc() -> Lighting {
	l := Lighting{
		sun_dir   = {-0.4, -1, -0.3},
		sun_color = {0.85, 0.8, 0.72},
		ambient   = {0.35, 0.38, 0.45},
		fog_color = {20, 22, 30, 255},
		fog_near  = 12,
		fog_far   = 45,
	}
	l.shader = rl.LoadShaderFromMemory(LIT_VERTEX, LIT_FRAGMENT)
	l.ok = rl.IsShaderValid(l.shader)
	if !l.ok {
		return l
	}
	l.loc_sun_dir = rl.GetShaderLocation(l.shader, "sunDir")
	l.loc_sun_color = rl.GetShaderLocation(l.shader, "sunColor")
	l.loc_ambient = rl.GetShaderLocation(l.shader, "ambient")
	l.loc_view = rl.GetShaderLocation(l.shader, "viewPos")
	l.loc_fog_color = rl.GetShaderLocation(l.shader, "fogColor")
	l.loc_fog_range = rl.GetShaderLocation(l.shader, "fogRange")
	l.loc_point_pos = rl.GetShaderLocation(l.shader, "pointPos")
	l.loc_point_color = rl.GetShaderLocation(l.shader, "pointColor")
	l.loc_point_radius = rl.GetShaderLocation(l.shader, "pointRadius")
	l.loc_model = rl.GetShaderLocation(l.shader, "matModel")
	return l
}

lighting_destroy :: proc(l: ^Lighting) {
	if l.ok {
		rl.UnloadShader(l.shader)
	}
	l^ = {}
}

// Uploads the uniforms; call once per frame inside BeginMode3D.
lighting_update :: proc(l: ^Lighting, camera_position: Vec3) {
	if !l.ok {
		return
	}
	set3 :: proc(shader: rl.Shader, loc: i32, v: Vec3) {
		value := v
		rl.SetShaderValue(shader, loc, &value, .VEC3)
	}
	set3(l.shader, l.loc_sun_dir, l.sun_dir)
	set3(l.shader, l.loc_sun_color, l.sun_color)
	set3(l.shader, l.loc_ambient, l.ambient)
	set3(l.shader, l.loc_view, camera_position)
	set3(l.shader, l.loc_point_pos, l.point_pos)
	set3(l.shader, l.loc_point_color, l.point_color)
	fog := [4]f32{f32(l.fog_color.r) / 255, f32(l.fog_color.g) / 255, f32(l.fog_color.b) / 255, f32(l.fog_color.a) / 255}
	rl.SetShaderValue(l.shader, l.loc_fog_color, &fog, .VEC4)
	fog_range := [2]f32{l.fog_near, l.fog_far}
	rl.SetShaderValue(l.shader, l.loc_fog_range, &fog_range, .VEC2)
	radius := l.point_radius
	rl.SetShaderValue(l.shader, l.loc_point_radius, &radius, .FLOAT)
	// Immediate-mode vertices are already in world space.
	rl.SetShaderValueMatrix(l.shader, l.loc_model, rl.Matrix(1))
}

// Immediate shapes (DrawCube, DrawPlane...) drawn in between are lit.
lighting_begin :: proc(l: ^Lighting) {
	if l.ok {
		rl.BeginShaderMode(l.shader)
	}
}

lighting_end :: proc(l: ^Lighting) {
	if l.ok {
		rl.EndShaderMode()
	}
}

// Gives a model the lit material, e.g. a voxel mesh built below.
lighting_apply_to_model :: proc(l: ^Lighting, model: ^rl.Model) {
	if !l.ok {
		return
	}
	for i in 0..<model.materialCount {
		model.materials[i].shader = l.shader
	}
}

// Soft dark disc under an object, keeps 3D jumps readable.
draw_blob_shadow :: proc(position: Vec3, radius: f32, alpha: f32 = 0.45) {
	rl.DrawCylinder(position + {0, 0.02, 0}, radius, radius, 0.01, 14, rl.Color{0, 0, 0, u8(255 * clamp(alpha, 0, 1))})
}
