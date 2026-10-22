package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas "../engine/canvas"

EXPEDITION_LINE_EMITTERS :: 32
EXPEDITION_EDGE_EMISSION :: f32(5)
EXPEDITION_EDGE_WIDTH :: f32(1.35)

Expedition_Line_Emitter :: struct { a,b,radiance:rl.Vector3 }
Expedition_Edge_Frame :: struct {
	eye,right,up,forward:rl.Vector3,
	pixels:rl.Vector2,
	pixel_focal,ortho_units_per_pixel,width_pixels:f32,
	perspective,reflection:bool,
}
Expedition_Ribbon :: struct { vertices:[4]rl.Vector3,uv:[4]rl.Vector2 }
Expedition_Edges :: struct {
	shader:rl.Shader,
	radius_location,emission_location:c.int,
	initialized,shader_active:bool,
	frame:Expedition_Edge_Frame,
	// Zero selects the defaults; the HDR material can tune these per view.
	width_pixels,emission:f32,
	emitters:[EXPEDITION_LINE_EMITTERS]Expedition_Line_Emitter,
	emitter_distances:[EXPEDITION_LINE_EMITTERS]f32,
	emitter_count:int,
	light_focus:rl.Vector3,
}

EXPEDITION_EDGE_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
noperspective out vec2 ribbonCoord;
out vec4 color;
void main() {
    gl_Position=mvp*vec4(vertexPosition,1.);
    ribbonCoord=vertexTexCoord;
    color=vertexColor;
}`

EXPEDITION_EDGE_FRAGMENT :: `#version 330
noperspective in vec2 ribbonCoord;
in vec4 color;
uniform float radiusPixels;
uniform float emission;
out vec4 finalColor;
void main() {
    // x runs from 0 to 1 between the segment endpoints. Its screen-space
    // derivative recovers length without a uniform update for every line.
    float inverseLength=length(vec2(dFdx(ribbonCoord.x),dFdy(ribbonCoord.x)));
    float cap=(ribbonCoord.x-clamp(ribbonCoord.x,0.,1.))/max(inverseLength,.000001);
    float distanceToEdge=length(vec2(cap,ribbonCoord.y))-radiusPixels;
    float aa=max(fwidth(distanceToEdge),.7);
    float coverage=1.-smoothstep(-aa*.5,aa*.5,distanceToEdge);
    if(coverage<.001) discard;
    vec3 radiance=pow(color.rgb,vec3(2.2))*emission;
    finalColor=vec4(radiance,coverage);
}`

@(private)
expedition_edge_frame :: proc(camera:rl.Camera3D,pixels:rl.Vector2,width:f32=EXPEDITION_EDGE_WIDTH,reflection:bool=false)->(f:Expedition_Edge_Frame) {
	f.eye=camera.position;f.forward=rl.Vector3Normalize(camera.target-camera.position)
	f.right=rl.Vector3Normalize(rl.Vector3CrossProduct(f.forward,camera.up));f.up=rl.Vector3CrossProduct(f.right,f.forward)
	f.pixels={max(pixels.x,1),max(pixels.y,1)};f.width_pixels=max(width,.1);f.reflection=reflection
	f.perspective=camera.projection==.PERSPECTIVE
	f.pixel_focal=f.pixels.y/(2*math.tan(clamp(camera.fovy,1,175)*math.PI/360))
	f.ortho_units_per_pixel=max(camera.fovy,.001)/f.pixels.y
	return
}

// Geometry is pure and headlessly testable. Extrusion happens in the current
// render target's physical pixels, including perspective and mirrored passes.
@(private)
expedition_ribbon :: proc(f:^Expedition_Edge_Frame,source_a,source_b:rl.Vector3)->(q:Expedition_Ribbon,ok:bool) {
	a,b:=source_a,source_b
	if f.reflection {a.y=-a.y;b.y=-b.y}
	za,zb:=rl.Vector3DotProduct(a-f.eye,f.forward),rl.Vector3DotProduct(b-f.eye,f.forward)
	near:=f32(.05)
	if za<=near && zb<=near {return}
	if za<near {a+=(b-a)*((near-za)/(zb-za));za=near}
	if zb<near {b+=(a-b)*((near-zb)/(za-zb));zb=near}
	pa:=rl.Vector2{rl.Vector3DotProduct(a-f.eye,f.right),rl.Vector3DotProduct(a-f.eye,f.up)}
	pb:=rl.Vector2{rl.Vector3DotProduct(b-f.eye,f.right),rl.Vector3DotProduct(b-f.eye,f.up)}
	if f.perspective {pa*=f.pixel_focal/za;pb*=f.pixel_focal/zb}
	else {pa/=f.ortho_units_per_pixel;pb/=f.ortho_units_per_pixel}
	d:=pb-pa;length:=rl.Vector2Length(d);if length<.01 {return}
	d/=length
	tangent:=f.right*d.x+f.up*d.y;side:=f.right*(-d.y)+f.up*d.x
	pad:=f.width_pixels*.5+1.25
	// Move toward the eye along the same projection ray: surface seams cannot
	// z-fight, and the submillimetre bias never turns edges into an X-ray pass.
	bias_a,bias_b:=clamp(za*.00005,.0005,.003),clamp(zb*.00005,.0005,.003)
	units_a,units_b:=f.ortho_units_per_pixel,f.ortho_units_per_pixel
	if f.perspective {
		a-=(a-f.eye)*(bias_a/za);b-=(b-f.eye)*(bias_b/zb)
		units_a=(za-bias_a)/f.pixel_focal;units_b=(zb-bias_b)/f.pixel_focal
	} else {a-=f.forward*bias_a;b-=f.forward*bias_b}
	q.vertices={a-(tangent+side)*(pad*units_a),b+(tangent-side)*(pad*units_b),b+(tangent+side)*(pad*units_b),a+(-tangent+side)*(pad*units_a)}
	q.uv={{-pad/length,-pad},{1+pad/length,-pad},{1+pad/length,pad},{-pad/length,pad}}
	if f.reflection {for &p in q.vertices {p.y=-p.y}}
	return q,true
}

@(private)
destroy_expedition_edges :: proc(e:^Expedition_Edges) {
	if e.shader.id!=0 {rl.UnloadShader(e.shader)}
	e^={}
}

@(private)
begin_expedition_edges :: proc(renderer:^Renderer) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	e:=&m.edges
	if !e.initialized && rl.IsWindowReady() {
		e.initialized=true;e.shader=rl.LoadShaderFromMemory(EXPEDITION_EDGE_VERTEX,EXPEDITION_EDGE_FRAGMENT)
		if rl.IsShaderValid(e.shader) {
			e.radius_location=rl.GetShaderLocation(e.shader,"radiusPixels");e.emission_location=rl.GetShaderLocation(e.shader,"emission")
		} else {if e.shader.id!=0 {rl.UnloadShader(e.shader)};e.shader={}}
	}
	pixels:=rl.Vector2{renderer.canvas_width,renderer.canvas_height}*canvas.scale()
	width:=e.width_pixels if e.width_pixels>0 else EXPEDITION_EDGE_WIDTH
	e.frame=expedition_edge_frame(renderer.tactical.camera,pixels,width,m.reflection_pass)
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	e.shader_active=rl.IsShaderValid(e.shader)
	if e.shader_active {
		radius:=width*.5;emission:=e.emission if e.emission>0 else EXPEDITION_EDGE_EMISSION
		rl.SetShaderValue(e.shader,e.radius_location,&radius,.FLOAT);rl.SetShaderValue(e.shader,e.emission_location,&emission,.FLOAT)
		rl.BeginShaderMode(e.shader)
	}
}

@(private)
end_expedition_edges :: proc(renderer:^Renderer) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	rlgl.DrawRenderBatchActive()
	if m.edges.shader_active {rl.EndShaderMode()}
	rlgl.EnableDepthMask()
}

@(private)
draw_expedition_ribbon :: proc(e:^Expedition_Edges,a,b:rl.Vector3,color:rl.Color) {
	if e==nil {return}
	q,ok:=expedition_ribbon(&e.frame,a,b);if !ok {return}
	_=rlgl.CheckRenderBatchLimit(4)
	rlgl.Begin(rlgl.QUADS);rlgl.Color4ub(color.r,color.g,color.b,255)
	for p,i in q.vertices {rlgl.TexCoord2f(q.uv[i].x,q.uv[i].y);rlgl.Vertex3f(p.x,p.y,p.z)}
	rlgl.End()
}

@(private)
expedition_collect_edge :: proc(e:^Expedition_Edges,a,b:rl.Vector3,color:rl.Color) {
	if e==nil || max(color.r,max(color.g,color.b))<72 {return}
	d:=b-a;length2:=rl.Vector3LengthSqr(d);if length2<.00001 {return}
	t:=clamp(rl.Vector3DotProduct(e.light_focus-a,d)/length2,0,1)
	distance:=rl.Vector3DistanceSqr(e.light_focus,a+d*t)
	if e.emitter_count>=EXPEDITION_LINE_EMITTERS && distance>=e.emitter_distances[EXPEDITION_LINE_EMITTERS-1] {return}
	for emitter in e.emitters[:e.emitter_count] {
		if (rl.Vector3DistanceSqr(a,emitter.a)<.000001 && rl.Vector3DistanceSqr(b,emitter.b)<.000001) ||
		   (rl.Vector3DistanceSqr(a,emitter.b)<.000001 && rl.Vector3DistanceSqr(b,emitter.a)<.000001) {return}
	}
	index:=min(e.emitter_count,EXPEDITION_LINE_EMITTERS-1)
	for index>0 && distance<e.emitter_distances[index-1] {e.emitters[index]=e.emitters[index-1];e.emitter_distances[index]=e.emitter_distances[index-1];index-=1}
	emission:=e.emission if e.emission>0 else EXPEDITION_EDGE_EMISSION
	radiance:=rl.Vector3{math.pow(f32(color.r)/255,2.2),math.pow(f32(color.g)/255,2.2),math.pow(f32(color.b)/255,2.2)}*emission
	e.emitters[index]={a,b,radiance};e.emitter_distances[index]=distance;e.emitter_count=min(e.emitter_count+1,EXPEDITION_LINE_EMITTERS)
}
