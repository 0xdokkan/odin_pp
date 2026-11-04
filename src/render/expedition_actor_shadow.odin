package render

import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

// Approved after native Cyber/West comparisons. Paper and ink keep their
// authored values; this is a gentle attenuation of the coloured print.
EXPEDITION_ACTOR_SHADOW :: #config(EXPEDITION_ACTOR_SHADOW, true)
EXPEDITION_ACTOR_SHADOW_STRENGTH :: f32(.15)

@(private)
EXPEDITION_ACTOR_SHADOW_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec3 worldPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
void main() {
    worldPosition=vertexPosition;
    fragTexCoord=vertexTexCoord;
    fragColor=vertexColor;
    gl_Position=mvp*vec4(vertexPosition,1.);
}`

@(private)
EXPEDITION_ACTOR_SHADOW_FRAGMENT :: `#version 330
in vec3 worldPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform float shadowAmount;
const float lightMirror=0.;
out vec4 finalColor;
`+EXPEDITION_SUN_GLSL+`
void main() {
    vec4 print=texture(texture0,fragTexCoord)*fragColor;
    // The shared ink peaks at 43/255: the entire ink pigment remains untouched.
    float pigment=smoothstep(.18,.36,max(print.r,max(print.g,print.b)));
    float shade=(1.-expedition_sun(worldPosition,vec3(0.,1.,0.)))*shadowAmount*pigment;
    print.rgb*=vec3(1.)-vec3(1.,.90,.70)*shade;
    finalColor=print;
}`

@(private)
begin_expedition_actor_shadow :: proc(renderer: ^Renderer, quad: Tactical_Billboard) -> bool {
    when !EXPEDITION_ACTOR_SHADOW { return false }
    v := &renderer.tactical
    m := v.expedition_material
    if !v.expedition || m == nil || m.reflection_pass || !m.sun.active { return false }
    // The recursive cartoon back and non-actor quads never enter this program.
    // The caller explicitly excludes feedback tints and flashes.
    if !quad.cartoon && quad.card.id == 0 { return false }
    s := &m.sun
    if s.actor_failed { return false }
    if s.actor_shader.id == 0 {
        s.actor_shader = rl.LoadShaderFromMemory(EXPEDITION_ACTOR_SHADOW_VERTEX, EXPEDITION_ACTOR_SHADOW_FRAGMENT)
        if !rl.IsShaderValid(s.actor_shader) { s.actor_failed = true; return false }
        s.actor_uniforms = expedition_sun_uniforms(s.actor_shader)
        s.actor_amount = rl.GetShaderLocation(s.actor_shader, "shadowAmount")
    }
    set_expedition_sun(renderer, s.actor_shader, s.actor_uniforms)
    amount := EXPEDITION_ACTOR_SHADOW_STRENGTH
    rl.SetShaderValue(s.actor_shader, s.actor_amount, &amount, .FLOAT)
    rl.BeginShaderMode(s.actor_shader)
    return true
}

// Actor eligibility is decided before adding the biome's permanent print tint.
// A cave is an actor property: a foe under rock stays unlit even while the
// player is outside. Non-actor direct quads keep shadow_allowed=false.
@(private)
expedition_actor_sun_visible :: proc(renderer: ^Renderer, entity: game.Entity_Ref, position: view.Vec2) -> bool {
    when !EXPEDITION_ACTOR_SHADOW { return false }
    if !renderer.tactical.expedition { return false }
    if cell, found := board_actor_cell(entity); found {
        point := position
        if actor, visible := presentation_actor_in_view(renderer.tactical.snapshot, entity); visible { point = actor.position }
        m := board_layer_map()
        return !game.layer_viewer_in_vault(&m, {point = {point.x+.5, point.y+.5}, cell = cell})
    }
    return !renderer.tactical.expedition_in_cave
}
