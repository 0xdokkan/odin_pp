package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas "../engine/canvas"
import world "../expedition"
import game "../game"
import level "../level"

// THE SUN AND THE SKY OVER THE EXPEDITIONS. Two small passes before the world, over the
// same cached solids the camera draws:
//
// - the sun: a depth map seen from the key light, so walls, props, relief and buildings cast
//   real shadows on the floor and on each other (a cool tint, never black);
// - the sky: the height of everything, seen from straight above and blurred, so the floor
//   and the feet of the walls darken where solids crowd them (ambient occlusion shaped by
//   the actual footprints: round under a tree, a band along a wall, nothing on open ground).
//
// Both follow the camera's target, snapped to their texels so nothing shimmers while
// walking. Paper actors keep their printed colours; their feathered contact shadows remain.
// Caves and the rooms under the rock keep only their lamps (skyShade).

// Off only to measure the passes' cost against the same build (-define:EXPEDITION_SUN=false).
EXPEDITION_SUN :: #config(EXPEDITION_SUN,true)
EXPEDITION_SUN_SIZE :: c.int(2048)
EXPEDITION_SKY_SIZE :: c.int(512)
// The square of ground both maps cover, centred on the camera's target.
EXPEDITION_SUN_SPAN :: f32(60)
// Texture units outside raylib's batch slots (1..4) and material maps (0..11).
EXPEDITION_SUN_UNIT :: c.int(14)
EXPEDITION_SKY_UNIT :: c.int(15)
// Toward the light: from the viewer's left, a little in front of them, 55° high.
EXPEDITION_SUN_TOWARD :: rl.Vector3{-.56,1,.36}

// The maps are drawn again only when what casts or where it is seen changes: the target moved
// this far from where they were drawn, a block was built or uploaded, a roof lifted or came
// back, or the camera turned (the paper faces it). Standing still or strolling costs nothing.
EXPEDITION_SUN_REUSE :: f32(5)
Expedition_Sun_Key :: struct {
	center, right: rl.Vector3,
	geometry_rebuilds, geometry_uploads, terrain_rebuilds: u64,
	roofs: u64,
	biome: u8,
}

Expedition_Sun :: struct {
	key: Expedition_Sun_Key,
	actor_shader: rl.Shader,
	actor_uniforms: Expedition_Sun_Uniforms,
	actor_amount: c.int,
	actor_failed: bool,
	drawn: bool,
	// Depth only (a colour channel too where a driver needs one).
	shadow: rl.RenderTexture2D,
	// Heights in red, and its blurred copy.
	sky: [2]rl.RenderTexture2D,
	depth_shader, height_shader, cutout_shader: rl.Shader,
	sun_matrix, sky_matrix: rl.Matrix,
	ready, failed, active, sky_active: bool,
	// How many times the maps were drawn (the benchmark and the tests read it).
	renders: u64,
}

// Whether the maps drawn for `old` still serve `now`.
@(private)
expedition_sun_reusable :: proc(old,now:Expedition_Sun_Key)->bool {
	d:=rl.Vector2{now.center.x-old.center.x,now.center.z-old.center.z}
	if d.x*d.x+d.y*d.y>EXPEDITION_SUN_REUSE*EXPEDITION_SUN_REUSE {return false}
	if rl.Vector3DotProduct(now.right,old.right)<.9999 {return false}
	return now.geometry_rebuilds==old.geometry_rebuilds && now.geometry_uploads==old.geometry_uploads &&
		now.terrain_rebuilds==old.terrain_rebuilds && now.roofs==old.roofs && now.biome==old.biome
}

EXPEDITION_SUN_DEPTH_FRAGMENT :: `#version 330
out vec4 finalColor;
void main() { finalColor=vec4(1.); }`

// Paper casts the shadow of its cut, not of its quad.
EXPEDITION_SUN_CUTOUT_FRAGMENT :: `#version 330
in vec2 surfaceUV;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
    if(texture(texture0,surfaceUV).a<.5) discard;
    finalColor=vec4(1.);
}`

EXPEDITION_SUN_HEIGHT_FRAGMENT :: `#version 330
in vec3 worldPosition;
out vec4 finalColor;
void main() { finalColor=vec4(worldPosition.y,0.,0.,1.); }`

// Shared by every program with EXPEDITION_LIGHT_GLSL.
EXPEDITION_SUN_GLSL :: `
uniform sampler2DShadow sunShadow;
uniform sampler2D skyHeight;
uniform mat4 sunMatrix;
uniform mat4 skyMatrix;
uniform vec2 sunOn;
// 1 in the sun, 0 in a shadow: four filtered comparisons (each a bilinear 2x2 in hardware)
// round a 1.5-texel square, a soft paper-cut edge a few pixels wide.
float expedition_sun(vec3 p,vec3 n) {
    if(sunOn.x<.5 || lightMirror>.5) return 1.;
    vec4 clip=sunMatrix*vec4(p+n*.04,1.);
    vec3 s=clip.xyz*.5+.5;
    if(s.x<=0. || s.y<=0. || s.x>=1. || s.y>=1. || s.z>=1.) return 1.;
    vec2 t=.75/vec2(textureSize(sunShadow,0));
    float z=s.z-.00035;
    float lit=texture(sunShadow,vec3(s.xy+vec2(-t.x,-t.y),z))+texture(sunShadow,vec3(s.xy+vec2(t.x,-t.y),z))
        +texture(sunShadow,vec3(s.xy+vec2(-t.x,t.y),z))+texture(sunShadow,vec3(s.xy+vec2(t.x,t.y),z));
    // The map's rim fades out instead of cutting a straight line across the ground.
    vec2 rim=min(s.xy,1.-s.xy);
    return mix(1.,lit*.25,smoothstep(0.,.04,min(rim.x,rim.y)));
}
// Height above a point, shared by ground pigments and sky occlusion. A caller shading
// the same point twice can retain this value instead of sampling the map twice.
float expedition_sky_crowd(vec3 p) {
    if(sunOn.y<.5 || lightMirror>.5) return 0.;
    vec4 clip=skyMatrix*vec4(p,1.);
    vec2 uv=clip.xy*.5+.5;
    if(uv.x<=0. || uv.y<=0. || uv.x>=1. || uv.y>=1.) return 0.;
    return max(texture(skyHeight,uv).r-p.y,0.);
}
float expedition_sky_from_crowd(float crowd) {
    float occlusion=clamp(crowd/.75,0.,1.);
    return 1.-.42*occlusion*(2.-occlusion);
}
float expedition_sky(vec3 p) {
    return expedition_sky_from_crowd(expedition_sky_crowd(p));
}
`

Expedition_Sun_Uniforms :: struct {shadow,sky,sun_matrix,sky_matrix,on:c.int}

@(private)
expedition_sun_uniforms :: proc(shader:rl.Shader)->Expedition_Sun_Uniforms {
	return {rl.GetShaderLocation(shader,"sunShadow"),rl.GetShaderLocation(shader,"skyHeight"),
		rl.GetShaderLocation(shader,"sunMatrix"),rl.GetShaderLocation(shader,"skyMatrix"),rl.GetShaderLocation(shader,"sunOn")}
}

@(private)
set_expedition_sun :: proc(renderer:^Renderer,shader:rl.Shader,u:Expedition_Sun_Uniforms) {
	on:=rl.Vector2{}
	if m:=renderer.tactical.expedition_material;m!=nil && m.sun.ready {
		sun:=&m.sun
		if sun.active {on.x=1}
		if sun.sky_active {on.y=1}
		if on.x>0 {rl.SetShaderValueMatrix(shader,u.sun_matrix,sun.sun_matrix)}
		if on.y>0 {rl.SetShaderValueMatrix(shader,u.sky_matrix,sun.sky_matrix)}
	}
	units:=[2]c.int{EXPEDITION_SUN_UNIT,EXPEDITION_SKY_UNIT}
	rl.SetShaderValue(shader,u.shadow,&units[0],.INT);rl.SetShaderValue(shader,u.sky,&units[1],.INT)
	rl.SetShaderValue(shader,u.on,&on,.VEC2)
}

@(private="file")
GL_Tex_Parameteri :: #type proc "c" (target,name:u32,value:i32)

// The depth texture answers comparisons, filtered: one read is a bilinear 2x2 test.
@(private="file")
expedition_sun_compare :: proc(depth:c.uint)->bool {
	set:=cast(GL_Tex_Parameteri)rlgl.GetProcAddress("glTexParameteri")
	if set==nil {return false}
	GL_TEXTURE_2D,GL_MIN,GL_MAG,GL_LINEAR::u32(0x0DE1),u32(0x2801),u32(0x2800),i32(0x2601)
	GL_COMPARE_MODE,GL_COMPARE_FUNC,GL_REF_TO_TEXTURE,GL_LEQUAL::u32(0x884C),u32(0x884D),i32(0x884E),i32(0x0203)
	rlgl.ActiveTextureSlot(EXPEDITION_SUN_UNIT);rlgl.EnableTexture(depth)
	set(GL_TEXTURE_2D,GL_COMPARE_MODE,GL_REF_TO_TEXTURE);set(GL_TEXTURE_2D,GL_COMPARE_FUNC,GL_LEQUAL)
	set(GL_TEXTURE_2D,GL_MIN,GL_LINEAR);set(GL_TEXTURE_2D,GL_MAG,GL_LINEAR)
	rlgl.DisableTexture();rlgl.ActiveTextureSlot(0)
	return true
}

@(private="file")
load_expedition_sun_shadow :: proc(size:c.int)->(t:rl.RenderTexture2D,ok:bool) {
	t.id=rlgl.LoadFramebuffer();if t.id==0 {return}
	t.texture={width=size,height=size,mipmaps=1}
	t.depth={id=rlgl.LoadTextureDepth(size,size,false),width=size,height=size,mipmaps=1}
	if t.depth.id==0 {rlgl.UnloadFramebuffer(t.id);t={};return}
	rlgl.FramebufferAttach(t.id,t.depth.id,c.int(rlgl.FramebufferAttachType.DEPTH),c.int(rlgl.FramebufferAttachTextureType.TEXTURE2D),0)
	if !rlgl.FramebufferComplete(t.id) {
		// Some drivers want a colour attachment even for a depth-only pass.
		t.texture.id=rlgl.LoadTexture(nil,size,size,c.int(rl.PixelFormat.UNCOMPRESSED_GRAYSCALE),1)
		t.texture.format=.UNCOMPRESSED_GRAYSCALE
		rlgl.FramebufferAttach(t.id,t.texture.id,c.int(rlgl.FramebufferAttachType.COLOR_CHANNEL0),c.int(rlgl.FramebufferAttachTextureType.TEXTURE2D),0)
	}
	ok=rlgl.FramebufferComplete(t.id) && expedition_sun_compare(t.depth.id)
	if !ok {rl.UnloadRenderTexture(t);t={}}
	return
}

@(private)
expedition_sun_ready :: proc(sun:^Expedition_Sun)->bool {
	if sun.ready {return true}
	if sun.failed || !rl.IsWindowReady() {return false}
	ok:bool
	sun.shadow,ok=load_expedition_sun_shadow(EXPEDITION_SUN_SIZE)
	if ok {
		for &t in sun.sky {
			t,ok=load_expedition_hdr_target(EXPEDITION_SKY_SIZE,EXPEDITION_SKY_SIZE,own_depth=true)
			if !ok {break}
		}
	}
	if ok {
		sun.depth_shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,EXPEDITION_SUN_DEPTH_FRAGMENT)
		sun.height_shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,EXPEDITION_SUN_HEIGHT_FRAGMENT)
		sun.cutout_shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,EXPEDITION_SUN_CUTOUT_FRAGMENT)
		ok=rl.IsShaderValid(sun.depth_shader) && rl.IsShaderValid(sun.height_shader) && rl.IsShaderValid(sun.cutout_shader)
	}
	if !ok {
		destroy_expedition_sun(sun);sun.failed=true
		rl.TraceLog(.WARNING,"Expedition sun unavailable; drawing without cast shadows")
		return false
	}
	sun.ready=true
	return true
}

@(private)
destroy_expedition_sun :: proc(sun:^Expedition_Sun) {
	if sun.actor_shader.id!=0 {rl.UnloadShader(sun.actor_shader)}
	if sun.shadow.id!=0 {rl.UnloadRenderTexture(sun.shadow)}
	for &t in sun.sky {unload_expedition_hdr_target(&t)}
	if sun.depth_shader.id!=0 {rl.UnloadShader(sun.depth_shader)}
	if sun.height_shader.id!=0 {rl.UnloadShader(sun.height_shader)}
	if sun.cutout_shader.id!=0 {rl.UnloadShader(sun.cutout_shader)}
	sun^={}
}

// An orthographic view of the square round `center` from `toward` (its eye that far along it),
// moved so that `center` lands on a texel corner: the map slides by whole texels only.
@(private="file")
expedition_sun_view :: proc(center,toward,up:rl.Vector3,size:c.int)->(view,projection:rl.Matrix) {
	half:=EXPEDITION_SUN_SPAN*.5
	look:=rl.Vector3Normalize(toward)
	right:=rl.Vector3Normalize(rl.Vector3CrossProduct(-look,up))
	above:=rl.Vector3CrossProduct(right,-look)
	texel:=EXPEDITION_SUN_SPAN/f32(size)
	x,y:=rl.Vector3DotProduct(center,right),rl.Vector3DotProduct(center,above)
	snapped:=center+right*(math.round(x/texel)*texel-x)+above*(math.round(y/texel)*texel-y)
	view=rl.MatrixLookAt(snapped+look*60,snapped,up)
	projection=rl.MatrixOrtho(-half,half,-half,half,1,140)
	return
}

// The solids that block the sky: the cached architecture, the relief and the buildings as they
// stand now (a roof lifted off while the robot is inside lets the sun in).
@(private="file")
draw_expedition_sun_casters :: proc(renderer:^Renderer,room:^game.Room,w:^world.World,shader:rl.Shader,cutouts:rl.Shader={}) {
	m:=renderer.tactical.expedition_material
	maps:[12]rl.MaterialMap;maps[0].color=rl.WHITE
	material:=rl.Material{shader=shader,maps=raw_data(maps[:])}
	if m.geometry.ready {
		cache:=&m.geometry
		for y in cache.lo.y..=cache.hi.y {for x in cache.lo.x..=cache.hi.x {
			chunk:=&cache.chunks[y*cache.columns+x]
			if chunk.ready && chunk.mesh.vertexCount>0 {rl.DrawMesh(chunk.mesh,material,rl.Matrix(1))}
		}}
		for site,i in w.sites[:cache.key.site_count] {
			if !site.active || world.distance(site.position,room.player.position)>30 {continue}
			chunk:=&cache.sites[i]
			if chunk.ready && chunk.mesh.vertexCount>0 {rl.DrawMesh(chunk.mesh,material,rl.Matrix(1))}
		}
		for placed,i in room.level_data.structures {
			if level.structure_is_building(placed.id) || !expedition_structure_near(room.level_data,i,room.player.position) {continue}
			chunk:=&cache.structures[i]
			if chunk.ready && chunk.mesh.vertexCount>0 {rl.DrawMesh(chunk.mesh,material,rl.Matrix(1))}
		}
	}
	rl.BeginShaderMode(shader)
	draw_expedition_terrain_casters(renderer,room,material)
	draw_expedition_deck_casters(renderer,room,material)
	draw_expedition_structure_casters(renderer,room,w)
	rlgl.DrawRenderBatchActive()
	rl.EndShaderMode()
	if cutouts.id!=0 {
		rl.BeginShaderMode(cutouts)
		draw_expedition_fixture_casters(renderer,room,w)
		rlgl.DrawRenderBatchActive()
		rl.EndShaderMode()
	}
}

// Prepare CPU surface geometry before taking the shadow key, including on the first frame
// and after a map edit. The floor normally builds these later in the frame, which would leave
// the first sun map without relief and force another render on the following frame.
@(private)
prepare_expedition_sun_surfaces :: proc(f: ^Expedition_Floor, data: ^level.Level, trestles: bool) {
	if f == nil || data == nil { return }
	if level.has_heights(data) { prepare_expedition_terrain(&f.terrain, data) }
	if expedition_has_decks(data) { prepare_expedition_decks(&f.decks, data, trestles) }
}

// Before the world: the sun's depth and the sky's heights. The target the world draws into
// is resumed afterwards, as the reflection pass does.
@(private)
prepare_expedition_sun :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material;s:=renderer.tactical.surface
	if m==nil {return}
	sun:=&m.sun;sun.active,sun.sky_active=false,false
	when !EXPEDITION_SUN {return}
	if s==nil || !expedition_sun_ready(sun) {return}
	if expedition_floor_ready(renderer) {
		prepare_expedition_sun_surfaces(renderer.tactical.expedition_floor,room.level_data,w.biome==.West)
	}
	key:=Expedition_Sun_Key{center=renderer.tactical.camera.target,right=flipbook_camera_right(renderer),
		geometry_rebuilds=m.geometry.rebuilds,geometry_uploads=m.geometry.uploads,biome=u8(w.biome)}
	if f:=renderer.tactical.expedition_floor;f!=nil {key.terrain_rebuilds=f.terrain.rebuilds}
	views:=&renderer.tactical.structures
	for roof,i in views.roof[:min(views.count,64)] {if roof {key.roofs|=u64(1)<<u64(i)}}
	if sun.drawn && expedition_sun_reusable(sun.key,key) {
		sun.active=true;sun.sky_active=s.post!=nil
		bind_expedition_sun(renderer)
		return
	}
	sun.key=key;sun.drawn=true;sun.renders+=1
	resume:=s.post.world if s.hdr_active && s.post!=nil else s.target
	rl.EndTextureMode()
	// Neither map may be read while it is drawn into.
	unbind_expedition_sun()
	center:=key.center
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()

	view,projection:=expedition_sun_view(center,EXPEDITION_SUN_TOWARD,{0,1,0},EXPEDITION_SUN_SIZE)
	rl.BeginTextureMode(sun.shadow)
	rlgl.EnableDepthMask()
	rlgl.ClearScreenBuffers()
	rlgl.DrawRenderBatchActive()
	rlgl.SetMatrixProjection(projection);rlgl.SetMatrixModelview(view)
	rlgl.EnableDepthTest()
	draw_expedition_sun_casters(renderer,room,w,sun.depth_shader,sun.cutout_shader)
	rl.EndTextureMode()
	sun.sun_matrix=projection*view;sun.active=true

	view,projection=expedition_sun_view(center,{0,1,0},{0,0,-1},EXPEDITION_SKY_SIZE)
	rl.BeginTextureMode(sun.sky[0])
	rlgl.EnableDepthMask()
	rl.ClearBackground(rl.BLACK)
	rlgl.DrawRenderBatchActive()
	rlgl.SetMatrixProjection(projection);rlgl.SetMatrixModelview(view)
	rlgl.EnableDepthTest()
	draw_expedition_sun_casters(renderer,room,w,sun.height_shader)
	rl.EndTextureMode()
	sun.sky_matrix=projection*view
	if s.post!=nil {
		// Two rounds of the post's separable blur: the heights spread about half a cell.
		kernel:=expedition_blur_kernel(3)
		for _ in 0..<2 {
			expedition_blur(renderer,s.post,sun.sky[0].texture,sun.sky[1],{1,0},&kernel)
			expedition_blur(renderer,s.post,sun.sky[1].texture,sun.sky[0],{0,1},&kernel)
		}
		sun.sky_active=true
	}
	canvas.begin(resume,renderer.canvas_width,renderer.canvas_height)
	bind_expedition_sun(renderer)
}

@(private)
bind_expedition_sun :: proc(renderer:^Renderer) {
	m:=renderer.tactical.expedition_material
	if m==nil || !m.sun.ready {return}
	rlgl.DrawRenderBatchActive()
	rlgl.ActiveTextureSlot(EXPEDITION_SUN_UNIT);rlgl.EnableTexture(m.sun.shadow.depth.id)
	rlgl.ActiveTextureSlot(EXPEDITION_SKY_UNIT);rlgl.EnableTexture(m.sun.sky[0].texture.id)
	rlgl.ActiveTextureSlot(0)
}

@(private)
unbind_expedition_sun :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.ActiveTextureSlot(EXPEDITION_SUN_UNIT);rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(EXPEDITION_SKY_UNIT);rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(0)
}
