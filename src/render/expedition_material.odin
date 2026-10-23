package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"

EXPEDITION_GRID_FOCUS :: 9
EXPEDITION_REVEAL_POINTS :: 9

// One view owns the lit environment shaders and neon emitters. Only solids
// standing in front of an actor use the reveal program; paper actors are
// drawn after HDR resolve and keep their original printed colours.
Expedition_Material :: struct {
	geometry: Expedition_Architecture_Cache,
	edges: Expedition_Edges,
	reflection_pass: bool,
	lights: Expedition_Lights,
	light_uniforms, reveal_light_uniforms: Expedition_Light_Uniforms,
	shader, reveal_shader: rl.Shader,
	tint, floor, cyber, reveal_cyber: c.int,
	reveal_eye, reveal_forward, reveal_viewport, reveal_points, reveal_count: c.int,
	grid_amount: f32,
	// Inside a building the rest of the world is darker: the building's footprint (x0, z0,
	// x1, z1) and how dark the outside is (structure_expedition.odin).
	dim_box: rl.Vector4,
	dim_amount: f32,
	// The envelope's opacity in the reveal program, per structure drawn.
	reveal_envelope: c.int,
	focus_points: [EXPEDITION_GRID_FOCUS]rl.Vector4,
	focus_point_count: int,
	// Screen uv, radius in screen heights, view depth beyond which nothing thins.
	reveal: [EXPEDITION_REVEAL_POINTS]rl.Vector4,
	// The same actors on the ground (x, z): a cheap screen for the occluders.
	actors: [EXPEDITION_REVEAL_POINTS]rl.Vector2,
	reveal_point_count: c.int,
	toward_camera: rl.Vector2,
}

// Edges are printed with alpha 254: the reveal program keeps them crisp even
// where it dissolves the body of a wall standing in front of an actor.
EXPEDITION_EDGE_ALPHA :: u8(254)

// A soft cool fill makes the Cyber's unlit faces read as solid charcoal.
// It belongs to the architectural material, not to emissive ribbons, the
// one-quad floor, or the paper pass that follows HDR tone mapping.
EXPEDITION_BODY_GLSL :: `
uniform float cyberBody;
vec3 expedition_body(vec3 p,vec3 normal,vec3 base) {
    vec3 lit=expedition_lit(p,normal,base,.38,.3);
    if(cyberBody<=0.) return lit;
    vec3 n=normalize(normal);
    if(lightMirror>.5) n.y=-n.y;
    float fill=.3+.7*max(dot(n,vec3(.7785,.3892,-.4927)),0.);
    return lit+cyberBody*vec3(.006,.012,.022)*fill;
}
`

EXPEDITION_MATERIAL_FRAGMENT :: `#version 330
` + EXPEDITION_LIGHT_GLSL + EXPEDITION_BODY_GLSL + `
in vec3 worldPosition;
in vec3 normal;
in vec4 color;
uniform vec3 neonTint;
uniform float floorPass;
out vec4 finalColor;
float lineGrid(vec2 p,float width) {
    vec2 a=abs(fract(p-.5)-.5)/max(fwidth(p),vec2(.0001));
    return 1.0-smoothstep(width,width+1.0,min(a.x,a.y));
}
void main() {
    vec3 base=color.rgb;
    float alpha=color.a;
    if(alpha>.99) alpha=1.;
    // The night floor's faint biome threads, every four cells.
    if(floorPass>.5 && worldPosition.y<.0 && normal.y>.5 && max(base.r,max(base.g,base.b))<.12)
        base=mix(base,neonTint,.1*lineGrid(worldPosition.xz/4.,.35));
    vec3 lit=expedition_body(worldPosition,normal,base);
    finalColor=vec4(lit,alpha);
}`

EXPEDITION_REVEAL_FRAGMENT :: `#version 330
` + EXPEDITION_LIGHT_GLSL + EXPEDITION_BODY_GLSL + `
in vec3 worldPosition;
in vec3 normal;
in vec4 color;
uniform vec3 eye;
uniform vec3 viewForward;
uniform vec2 viewport;
uniform vec4 reveal[9];
uniform int revealCount;
// A building's envelope: below 1 it is dithered away (1 for everything else).
uniform float envelope;
out vec4 finalColor;
const float BAYER[16]=float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
void main() {
    vec3 p=worldPosition;
    // Ordered dither, not blending: no sorting, and the actor shows through
    // the holes because discarded fragments write no depth. Edges (alpha
    // 254) and the solids' feet stay whole.
    if(color.a>.999 && p.y>.1) {
        vec2 uv=gl_FragCoord.xy/viewport;
        float depth=dot(p-eye,viewForward);
        float cut=0.;
        for(int i=0;i<revealCount;i++) {
            if(depth>reveal[i].w) continue;
            vec2 d=(uv-reveal[i].xy)*vec2(viewport.x/viewport.y,1.);
            d.y*=.78;
            cut=max(cut,1.-smoothstep(.55,1.,length(d)/reveal[i].z));
        }
        ivec2 q=ivec2(mod(gl_FragCoord.xy,4.));
        // The actor's centre is fully clear; only the rim is stippled.
        // Leaving wall pixels there would break the printed paper silhouette.
        if(cut>0. && (BAYER[q.x+q.y*4]+.5)/16.<cut) discard;
    }
    if(envelope<.999) {
        ivec2 e=ivec2(mod(gl_FragCoord.xy,4.));
        if((BAYER[e.x+e.y*4]+.5)/16.>envelope) discard;
    }
    finalColor=vec4(expedition_body(worldPosition,normal,color.rgb),1.);
}`

@(private)
expedition_material_ready :: proc(renderer:^Renderer)->bool {
	if renderer.tactical.expedition_material!=nil {return true}
	if !rl.IsWindowReady() {return false}
	m:=new(Expedition_Material)
	m.shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,EXPEDITION_MATERIAL_FRAGMENT)
	m.reveal_shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,EXPEDITION_REVEAL_FRAGMENT)
	if !rl.IsShaderValid(m.shader) || !rl.IsShaderValid(m.reveal_shader) {
		if m.shader.id!=0 {rl.UnloadShader(m.shader)}
		if m.reveal_shader.id!=0 {rl.UnloadShader(m.reveal_shader)}
		free(m);return false
	}
	m.tint=rl.GetShaderLocation(m.shader,"neonTint");m.floor=rl.GetShaderLocation(m.shader,"floorPass")
	m.cyber=rl.GetShaderLocation(m.shader,"cyberBody");m.reveal_cyber=rl.GetShaderLocation(m.reveal_shader,"cyberBody")
	m.light_uniforms=expedition_light_uniforms(m.shader)
	m.reveal_light_uniforms=expedition_light_uniforms(m.reveal_shader)
	r:=m.reveal_shader
	m.reveal_eye=rl.GetShaderLocation(r,"eye");m.reveal_forward=rl.GetShaderLocation(r,"viewForward")
	m.reveal_viewport=rl.GetShaderLocation(r,"viewport")
	m.reveal_points=rl.GetShaderLocation(r,"reveal[0]");m.reveal_count=rl.GetShaderLocation(r,"revealCount")
	m.reveal_envelope=rl.GetShaderLocation(r,"envelope")
	whole:=f32(1);rl.SetShaderValue(r,m.reveal_envelope,&whole,.FLOAT)
	renderer.tactical.expedition_material=m
	return true
}

@(private)
destroy_expedition_material :: proc(renderer:^Renderer) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	destroy_expedition_geometry(&m.geometry)
	destroy_expedition_edges(&m.edges)
	rl.UnloadShader(m.shader);rl.UnloadShader(m.reveal_shader);free(m);renderer.tactical.expedition_material=nil
}

// Once per frame, before the board: the encounter grid's fade and focus, and
// the actors whose occluders thin out. Positions are those actually drawn.
@(private)
prepare_expedition_material :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	if !expedition_material_ready(renderer) {return}
	m:=renderer.tactical.expedition_material;v:=&renderer.tactical
	dt:=expedition_frame_dt(renderer)
	goal:=f32(1) if room.phase==.Combat else 0
	m.grid_amount+=(goal-m.grid_amount)*(1-math.exp(-7*dt))
	if goal==0 && m.grid_amount<.01 {m.grid_amount=0}
	m.focus_point_count=0;m.reveal_point_count=0
	update_structure_dim(renderer,m)
	camera:=v.camera
	toward:=rl.Vector2{camera.position.x-camera.target.x,camera.position.z-camera.target.z}
	if l:=rl.Vector2Length(toward);l>.0001 {m.toward_camera=toward/l}
	snapshot:=v.snapshot
	if snapshot.player.visible {
		at,_:=living_card_position(renderer,game.PLAYER_ENTITY,.Player,snapshot.player.position)
		m.focus_points[0]={at.x+.5,at.y+.5,4.5,8.5};m.focus_point_count=1
		expedition_add_reveal(renderer,m,{at.x+.5,.75 if !v.expedition_mounted else .9,at.y+.5},1.05 if !v.expedition_mounted else 1.45)
	}
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		if !actor.visible || actor.health<=0 {continue}
		at,_:=living_card_position(renderer,actor.entity,sprite_key_for_enemy(actor.archetype),actor.position)
		if m.focus_point_count<EXPEDITION_GRID_FOCUS {m.focus_points[m.focus_point_count]={at.x+.5,at.y+.5,1.5,3.6};m.focus_point_count+=1}
		expedition_add_reveal(renderer,m,{at.x+.5,.7,at.y+.5},.85)
	}
}

@(private)
expedition_add_reveal :: proc(renderer:^Renderer,m:^Expedition_Material,center:rl.Vector3,radius:f32) {
	if m.reveal_point_count>=EXPEDITION_REVEAL_POINTS {return}
	v:=&renderer.tactical;camera:=v.camera
	width,height:=renderer.canvas_width,renderer.canvas_height
	if width<=0 || height<=0 {return}
	forward:=rl.Vector3Normalize(camera.target-camera.position)
	depth:=rl.Vector3DotProduct(center-camera.position,forward)
	if depth<=.1 {return}
	right:=flipbook_camera_right(renderer)
	a:=rl.GetWorldToScreenEx(center,camera,c.int(width),c.int(height))
	b:=rl.GetWorldToScreenEx(center+right*radius,camera,c.int(width),c.int(height))
	reach:=rl.Vector2Distance(a,b)/height
	if reach<=0 {return}
	// The surface's uv runs bottom up; the margin spares the actor's own row.
	m.reveal[m.reveal_point_count]={a.x/width,1-a.y/height,reach,depth-.4}
	m.actors[m.reveal_point_count]={center.x,center.z}
	m.reveal_point_count+=1
}

// How strongly a cell belongs to the encounter's tiled floor: per tile, so
// the grid dissolves tile by tile away from the fighters.
@(private)
expedition_grid_weight :: proc(m:^Expedition_Material,cell:grid.Position)->f32 {
	if m==nil || m.grid_amount<=0 {return 0}
	p:=rl.Vector2{f32(cell.x)+.5,f32(cell.y)+.5};near:f32
	for focus in m.focus_points[:m.focus_point_count] {
		d:=rl.Vector2Distance(p,{focus.x,focus.y})
		if d>=focus.w {continue}
		t:=clamp((d-focus.z)/(focus.w-focus.z),0,1)
		near=max(near,1-t*t*(3-2*t))
	}
	return near*m.grid_amount
}

// A cheap world-space screen: a solid within reach in front of a revealed
// actor and close to its sight line. The reveal program makes the exact cut.
@(private)
expedition_occludes :: proc(m:^Expedition_Material,center:rl.Vector2,half_width:f32=.5,reach:f32=5)->bool {
	if m==nil {return false}
	for actor in m.actors[:m.reveal_point_count] {
		d:=center-actor
		along:=d.x*m.toward_camera.x+d.y*m.toward_camera.y
		side:=abs(d.x*m.toward_camera.y-d.y*m.toward_camera.x)
		if along>-.6 && along<reach && side<1.3+half_width {return true}
	}
	return false
}

@(private)
begin_expedition_material :: proc(renderer:^Renderer,w:^world.World,floor:bool=false,reveal:bool=false) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	cyber:=f32(1) if w.biome==.Cyber && !floor else 0
	if reveal {
		camera:=renderer.tactical.camera
		forward:=rl.Vector3Normalize(camera.target-camera.position)
		viewport:=rl.Vector2{renderer.canvas_width,renderer.canvas_height}
		if s:=renderer.tactical.surface;s!=nil {viewport={f32(s.target.texture.width),f32(s.target.texture.height)}}
		r:=m.reveal_shader
		rl.SetShaderValue(r,m.reveal_eye,&camera.position,.VEC3);rl.SetShaderValue(r,m.reveal_forward,&forward,.VEC3)
		rl.SetShaderValue(r,m.reveal_viewport,&viewport,.VEC2)
		rl.SetShaderValue(r,m.reveal_count,&m.reveal_point_count,.INT)
		if m.reveal_point_count>0 {rl.SetShaderValueV(r,m.reveal_points,&m.reveal[0],.VEC4,m.reveal_point_count)}
		set_expedition_lights(renderer,r,m.reveal_light_uniforms)
		rl.SetShaderValue(r,m.reveal_cyber,&cyber,.FLOAT)
		rl.BeginShaderMode(r)
		return
	}
	color:=expedition_color(w.biome);tint:=rl.Vector3{f32(color.r)/255,f32(color.g)/255,f32(color.b)/255}
	f:=f32(1) if floor else 0
	rl.SetShaderValue(m.shader,m.tint,&tint,.VEC3);rl.SetShaderValue(m.shader,m.floor,&f,.FLOAT)
	rl.SetShaderValue(m.shader,m.cyber,&cyber,.FLOAT)
	set_expedition_lights(renderer,m.shader,m.light_uniforms)
	rl.BeginShaderMode(m.shader)
}
