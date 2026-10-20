package render

import "core:math"
import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import view "../engine/view"

COMIC_OUTLINE_OUTER :: f32(8)
COMIC_OUTLINE_INNER :: f32(6)
COMIC_WORLD_OUTER_PIXELS :: f32(4)
COMIC_WORLD_INNER_PIXELS :: f32(3)
Comic_Outline_Mode :: enum {World, Hologram, Ring}

// One bounded alpha-dilation pass per actor. Atlas bounds prevent a neighboring
// figure from bleeding into the cutout; the rectangular quad remains invisible.
COMIC_OUTLINE_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 sourceBounds;
uniform vec2 texel;
uniform vec2 outlineRadius;
out vec4 finalColor;
float ink(vec2 p) {
    if (p.x < sourceBounds.x || p.y < sourceBounds.y || p.x > sourceBounds.z || p.y > sourceBounds.w) return 0.0;
    return step(0.25, texture(texture0, p).a);
}
void main() {
    float outer = ink(fragTexCoord);
    float inner = outer;
    for (int i=0; i<12; ++i) {
        float a = float(i)*0.523598776;
        vec2 d = vec2(cos(a), sin(a))*texel;
        outer = max(outer, ink(fragTexCoord+d*outlineRadius.x));
        inner = max(inner, ink(fragTexCoord+d*outlineRadius.y));
        outer = max(outer, ink(fragTexCoord+d*outlineRadius.x*0.5));
        inner = max(inner, ink(fragTexCoord+d*outlineRadius.y*0.5));
    }
    outer = max(outer, inner);
    if (outer < 0.1) discard;
    finalColor = vec4(mix(vec3(0.025,0.036,0.05), fragColor.rgb, inner), outer*fragColor.a);
}`

@(private)
comic_pose_frame :: proc(elapsed: f64) -> int {
    if math.is_nan(elapsed) || math.is_inf(elapsed) { return 0 }
    return int(max(f64(0), elapsed)*5)%4
}

@(private)
comic_clip_progress :: proc(progress: f32) -> f32 {
    return f32(clamp(int(progress*4), 0, 3))/3
}

@(private)
create_comic_outline :: proc(renderer: ^Renderer) {
    v := &renderer.tactical
    v.outline_shader = rl.LoadShaderFromMemory(nil, COMIC_OUTLINE_FRAGMENT)
    if v.outline_shader.id != 0 {
        v.outline_bounds_location = rl.GetShaderLocation(v.outline_shader, "sourceBounds")
        v.outline_texel_location = rl.GetShaderLocation(v.outline_shader, "texel")
        v.outline_radius_location = rl.GetShaderLocation(v.outline_shader,"outlineRadius")
    }
}

// Source texels are not screen pixels: the same atlas figure is much smaller
// in a room than in the ring. Measure the actual projected quad, including its
// current pose and camera zoom, before choosing the source-space dilation.
@(private)
comic_source_pixel_scale :: proc(renderer: ^Renderer, quad: Tactical_Billboard) -> f32 {
    if quad.source.width <= 0 || quad.source.height <= 0 || renderer.canvas_width <= 0 || renderer.canvas_height <= 0 { return 1 }
    camera := renderer.tactical.camera
    if camera.fovy <= 0 || rl.Vector3LengthSqr(camera.target-camera.position) < 0.0001 { return 1 }
    projected: [4]rl.Vector2
    for point, i in quad.points {
        projected[i] = rl.GetWorldToScreenEx(point, camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
    }
    horizontal := min(rl.Vector2Distance(projected[2],projected[1]), rl.Vector2Distance(projected[3],projected[0]))/quad.source.width
    vertical := min(rl.Vector2Distance(projected[0],projected[1]), rl.Vector2Distance(projected[3],projected[2]))/quad.source.height
    return max(f32(0.01), min(horizontal, vertical))
}

@(private)
comic_outline_radii :: proc(renderer: ^Renderer, quad: Tactical_Billboard) -> rl.Vector2 {
    if renderer.tactical.outline_mode == .Ring { return {COMIC_OUTLINE_OUTER, COMIC_OUTLINE_INNER} }
    scale := comic_source_pixel_scale(renderer, quad)
    if renderer.tactical.outline_mode == .Hologram {
        // Map figures are compact markers; a world-sized paper fringe would
        // overlap neighboring cells and hide formations in a large arena.
        return {1.25/scale, 0.85/scale}
    }
    return {max(COMIC_OUTLINE_OUTER, COMIC_WORLD_OUTER_PIXELS/scale),
        max(COMIC_OUTLINE_INNER, COMIC_WORLD_INNER_PIXELS/scale)}
}

@(private)
comic_world_ground_clearance :: proc(renderer: ^Renderer, original: Tactical_Billboard) -> (result: Tactical_Billboard) {
    result = original
    if renderer.tactical.outline_mode != .World ||
        original.source.width <= 0 || original.source.height <= 0 { return }
    radii := comic_outline_radii(renderer, original)
    right := (original.points[2]-original.points[1])/original.source.width
    up := (original.points[0]-original.points[1])/original.source.height
    // The paper edge rests on the floor. Raising only the fringe would move
    // its registration away from the feet; both layers share this small lift,
    // including picking and labels, while the actor's shadow stays grounded.
    clearance := (abs(right.y)+abs(up.y))*(radii.x+1.2)+0.005
    for &point in result.points { point.y += clearance }
    return
}

@(private)
comic_cutout_geometry :: proc(quad: Tactical_Billboard, position: view.Vec2, elapsed: f64,
    radius: f32 = COMIC_OUTLINE_OUTER) -> (result: Tactical_Billboard) {
    result = quad
    if quad.source.width <= 0 || quad.source.height <= 0 { return }
    right := (quad.points[2]-quad.points[1])/quad.source.width
    up := (quad.points[0]-quad.points[1])/quad.source.height
    // A separate four-step paper registration wobble, independent of the
    // sprite's action clip. Both remain anchored to the same moving actor.
    phase := comic_pose_frame(elapsed+f64(position.x+position.y)*0.17)
    shifts := [4]rl.Vector2{{-1.2, 0}, {0.6, 1.1}, {1.2, -0.4}, {-0.5, -0.9}}
    shift := right*shifts[phase].x+up*shifts[phase].y
    result.source = {quad.source.x-radius, quad.source.y-radius, quad.source.width+radius*2, quad.source.height+radius*2}
    result.points[0] += (-right+up)*radius+shift
    result.points[1] += (-right-up)*radius+shift
    result.points[2] += (right-up)*radius+shift
    result.points[3] += (right+up)*radius+shift
    return
}

@(private)
draw_comic_cutout :: proc(renderer: ^Renderer, quad: Tactical_Billboard, position: view.Vec2, opacity: f32) {
    v := &renderer.tactical
    if v.outline_shader.id == 0 || quad.source.width <= 0 || quad.source.height <= 0 { return }
    texel := rl.Vector2{1/f32(quad.texture.width), 1/f32(quad.texture.height)}
    bounds := rl.Vector4{quad.source.x*texel.x, quad.source.y*texel.y,
        (quad.source.x+quad.source.width)*texel.x, (quad.source.y+quad.source.height)*texel.y}
    rl.SetShaderValue(v.outline_shader, v.outline_bounds_location, &bounds, .VEC4)
    rl.SetShaderValue(v.outline_shader, v.outline_texel_location, &texel, .VEC2)
    radii := comic_outline_radii(renderer, quad)
    rl.SetShaderValue(v.outline_shader,v.outline_radius_location,&radii,.VEC2)
    cutout := comic_cutout_geometry(quad, position, renderer.sprite_assets.elapsed, radii.x)
    rl.BeginShaderMode(v.outline_shader)
    rlgl.SetTexture(quad.texture.id)
    rlgl.Begin(rlgl.QUADS)
    tint := rl.Color{205, 193, 170, u8(clamp(opacity, f32(0), f32(1))*255)}
    if quad.key == .Player || quad.key == .Player_Cast || quad.key == .Player_Hit { tint.r, tint.g, tint.b = 224, 229, 213 }
    rlgl.Color4ub(tint.r, tint.g, tint.b, tint.a)
    uv := [4]rl.Vector2{{0,0}, {0,1}, {1,1}, {1,0}}
    for p, i in cutout.points {
        rlgl.TexCoord2f((cutout.source.x+uv[i].x*cutout.source.width)*texel.x, (cutout.source.y+uv[i].y*cutout.source.height)*texel.y)
        rlgl.Vertex3f(p.x, p.y, p.z)
    }
    rlgl.End()
    rlgl.SetTexture(0)
    rl.EndShaderMode()
}
