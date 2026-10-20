package render

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

RESIN_BACKGROUND :: rl.Color{5, 7, 11, 255}
RESIN_DARK :: rl.Color{13, 20, 31, 255}
RESIN_WALL :: rl.Color{21, 30, 43, 255}
RESIN_CAP :: rl.Color{65, 83, 107, 255}

// Values of the shared shader's `hologram` uniform. Model mode samples the
// numeral atlas and omits the board's fog, clear-room light and accents.
Resin_Light_Mode :: enum c.int {Board = 0, Hologram = 1, Model = 2}

Resin_Lighting :: struct {
	eye, lantern: rl.Vector3,
	mode: Resin_Light_Mode,
	clear: f32,
	accents: [4]rl.Vector4,
}

// Bind one resin pass. Callers keep their shader-availability guards and pair
// this with EndShaderMode after their geometry. Scene presets stay with the
// scene; the uniform contract belongs to the material.
@(private)
begin_resin_lighting :: proc(renderer: ^Renderer, lighting: Resin_Lighting) {
	v := &renderer.tactical
	values := lighting
	mode := c.int(values.mode)
	rl.SetShaderValue(v.light_shader, v.light_position_location, &values.lantern, .VEC3)
	rl.SetShaderValue(v.light_shader, v.light_eye_location, &values.eye, .VEC3)
	rl.SetShaderValue(v.light_shader, v.light_hologram_location, &mode, .INT)
	// Preserve the model pass's three-uniform contract: these board values
	// are neither read nor replaced while drawing dice or model previews.
	if values.mode != .Model {
		rl.SetShaderValue(v.light_shader, v.light_clear_location, &values.clear, .FLOAT)
		rl.SetShaderValueV(v.light_shader, v.light_accents_location, raw_data(values.accents[:]), .VEC4, 4)
	}
	rl.BeginShaderMode(v.light_shader)
}

// The level and dice share a fine moulded grain and a clear glossy coat.
// Dice provide local face UVs so the grain stays attached while they tumble.
TACTICAL_LIGHT_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec3 worldPosition;
out vec3 normal;
out vec2 surfaceUV;
out vec4 color;
void main() {
    worldPosition = vertexPosition;
    normal = vertexNormal;
    surfaceUV = vertexTexCoord;
    color = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}`

TACTICAL_LIGHT_FRAGMENT :: `#version 330
in vec3 worldPosition;
in vec3 normal;
in vec2 surfaceUV;
in vec4 color;
uniform vec3 lantern;
uniform vec3 eye;
uniform int hologram;
uniform float roomClear;
uniform vec4 accentLights[4];
uniform sampler2D texture0;
out vec4 finalColor;
float grain(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
void main() {
    vec3 n = normalize(normal);
    vec4 material = color;
    // Model numerals share the resin shader with the body. Their font atlas
    // needs real alpha sampling: ignoring it paints the entire glyph quad.
    if (hologram == 2) {
        material *= texture(texture0, surfaceUV);
        if (material.a < 0.01) discard;
    }
    vec3 base = material.rgb;
    vec3 l = normalize(vec3(-0.35, 1.0, -0.65));
    float sun = max(dot(n, l), 0.0);
    if (hologram == 1) {
        finalColor = vec4(base*(0.48+sun*0.58), color.a);
        return;
    }
    vec2 uv = abs(n.y) > 0.5 ? worldPosition.xz :
              (abs(n.z) > 0.5 ? worldPosition.xy : worldPosition.zy);
    if (hologram == 2) uv = surfaceUV;
    float noise = grain(floor(uv*28.0));
    base *= 0.985 + floor(noise*4.0)*0.01;
    vec3 v = normalize(eye-worldPosition);
    vec3 h = normalize(l+v);
    float roughness = hologram == 2 ? 96.0 : mix(52.0,88.0,grain(floor(worldPosition.xz)));
    float spec = pow(max(dot(n,h),0.0), roughness)*0.48;
    spec += pow(max(dot(n,h),0.0), 12.0)*0.065;
    vec3 toLight = lantern-worldPosition;
    float local = max(dot(n,normalize(toLight)),0.0)/(1.0+dot(toLight,toLight)*0.055);
    vec3 localHalf = normalize(normalize(toLight)+v);
    spec += pow(max(dot(n,localHalf),0.0), 80.0)*0.30/(1.0+dot(toLight,toLight)*0.025);
    float rim = pow(1.0-max(dot(n,v),0.0), 4.0)*0.16;
    float clear = hologram == 2 ? 0.0 : roomClear*roomClear*(3.0-2.0*roomClear);
    // Narrow grooves and vertical falloff anchor the moulded blocks in depth.
    vec2 edge = abs(fract(worldPosition.xz)-0.5);
    float seam = smoothstep(0.37,0.49,max(edge.x,edge.y));
    float contact = abs(n.y) > 0.8 ? 1.0-seam*0.16 : mix(0.78,1.0,clamp(worldPosition.y,0.0,1.0));
    if (hologram == 2) contact = 1.0;
    vec3 ambient = mix(vec3(0.28,0.34,0.43),vec3(0.67,0.73,0.82),clear);
    vec3 lit = base*(ambient+vec3(0.67,0.75,0.90)*sun+local*mix(0.36,0.20,clear))*contact;
    lit += vec3(0.59,0.77,1.0)*(spec+rim);
    // A restrained blue bounce on side faces separates stacked mouldings.
    if (hologram == 0) lit += base*vec3(0.10,0.18,0.29)*(1.0-abs(n.y))*0.28;
    if (hologram == 0) {
        for (int i=0; i<4; ++i) {
            if (accentLights[i].w <= 0.0) continue;
            vec3 delta = accentLights[i].xyz-worldPosition;
            float reach = accentLights[i].w/(1.0+dot(delta,delta)*1.6);
            float diffuse = max(dot(n,normalize(delta)),0.0);
            float shine = pow(max(dot(n,normalize(normalize(delta)+v)),0.0),42.0);
            lit += vec3(0.22,0.65,1.0)*(base*diffuse*1.25+shine*0.11)*reach;
        }
    }
    if (hologram == 2) {
        // Ivory inlays keep their readable value on a shaded face while the
        // blue resin still receives the complete directional glossy lighting.
        float ink = smoothstep(0.60,0.85,min(color.r,min(color.g,color.b)));
        lit = mix(lit,base*(0.83+sun*0.20),ink);
    }
    float mist = hologram == 2 ? 0.0 : smoothstep(5.0,10.0,length(worldPosition.xz-lantern.xz))*mix(0.55,0.08,clear);
    finalColor = vec4(mix(lit,vec3(0.02,0.03,0.055),mist),material.a);
}`

@(private)
draw_resin_cube_v :: proc(renderer: ^Renderer, position, size: rl.Vector3, color: rl.Color) {
	mesh := &renderer.tactical.block_mesh
	bevel := min(f32(0.055), min(size.x, min(size.y, size.z))*0.22)
	bevel_scale := bevel/DICE_BEVEL
	corner := size*0.5-rl.Vector3{bevel_scale*0.5, bevel_scale*0.5, bevel_scale*0.5}
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for triangle in mesh.triangles[:mesh.count] {
		// Equal world-space chamfers retain their 45-degree normals on thin
		// slabs and tall pillars alike; scaling a die stretched these bevels.
		n := rl.Vector3Normalize(triangle.normal)
		rlgl.Normal3f(n.x, n.y, n.z)
		for point in triangle.points {
			p := position+point*bevel_scale+rl.Vector3{
				corner.x if point.x > 0 else -corner.x,
				corner.y if point.y > 0 else -corner.y,
				corner.z if point.z > 0 else -corner.z}
			rlgl.TexCoord2f(point.x+0.5, point.z+0.5)
			rlgl.Vertex3f(p.x, p.y, p.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

@(private)
draw_resin_cube :: proc(renderer: ^Renderer, position: rl.Vector3, width, height, length: f32, color: rl.Color) {
	draw_resin_cube_v(renderer, position, {width, height, length}, color)
}
