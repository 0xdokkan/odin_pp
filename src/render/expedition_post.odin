package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas "../engine/canvas"
import game "../game"
import world "../expedition"

Expedition_Blur_Kernel :: struct {
	center:f32,
	// Each pair stores a subtexel offset and the combined normalized weight
	// of two adjacent samples. GL_LINEAR supplies their exact weighted sum.
	pairs:[4]rl.Vector2,
}

@(private)
expedition_blur_kernel :: proc(sigma:f32)->(kernel:Expedition_Blur_Kernel) {
	width:=clamp(sigma,.6,3)
	weights:[9]f32;weights[0]=1
	total:=f32(1)
	for i in 1..<len(weights) {weights[i]=math.exp(-f32(i*i)/(2*width*width));total+=2*weights[i]}
	kernel.center=1/total
	for &pair,i in kernel.pairs {
		a:=i*2+1;b:=a+1;combined:=weights[a]+weights[b]
		pair={f32(a)+weights[b]/combined,combined/total}
	}
	return
}

// CPU submission timings only; no GPU fences/readbacks enter normal frames.
Expedition_Post_Timing :: struct {reflection_ms,reflection_blur_ms,bloom_ms,resolve_ms:f64}

// The HDR world borrows the LDR board's depth. Tone mapping changes colour
// only, so paper actors drawn afterwards still meet the exact same walls.
Expedition_Post :: struct {
	world:rl.RenderTexture2D,
	bloom:[2]rl.RenderTexture2D,
	reflection:[3]rl.RenderTexture2D,
	extract,blur,resolve,backdrop:rl.Shader,
	blur_direction,blur_center,blur_pairs,extract_threshold,resolve_bloom,resolve_exposure:c.int,
	bloom_kernel,reflection_kernel:Expedition_Blur_Kernel,
	reflection_sigma:f32,
	profile:Expedition_Surface_Profile,
	reflection_ready:bool,
	timing:Expedition_Post_Timing,
}

EXPEDITION_HDR_BACKDROP :: `#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
void main() {
    vec3 c=mix(vec3(5.,9.,16.),vec3(8.,14.,23.),fragTexCoord.y)/255.;
    float pool=1.-smoothstep(0.,.65,length((fragTexCoord-vec2(.51,.6))*vec2(1.78,1.)));
    c=mix(c,vec3(25.,45.,66.)/255.,pool*.3);
    finalColor=vec4(pow(c,vec3(2.2)),1.);
}`

EXPEDITION_BLOOM_EXTRACT :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float threshold;
out vec4 finalColor;
void main() {
    vec2 t=1./vec2(textureSize(texture0,0));
    vec3 c=vec3(0.);
    // A footprint, not one subsample: even a one-pixel neon enters bloom.
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec3 s=texture(texture0,fragTexCoord+vec2(x,y)*t).rgb;
        float peak=max(s.r,max(s.g,s.b));
        float soft=clamp(peak-threshold+.5,0.,1.);
        float contribution=max(peak-threshold,soft*soft*.5)/max(peak,.0001);
        c+=s*contribution/9.;
    }
    finalColor=vec4(c,1.);
}`
EXPEDITION_GAUSSIAN_BLUR :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec2 direction;
uniform float centerWeight;
uniform vec2 pairedTaps[4];
out vec4 finalColor;
void main() {
    vec2 d=direction/vec2(textureSize(texture0,0));
    vec3 c=texture(texture0,fragTexCoord).rgb*centerWeight;
    // Nine reads reproduce all seventeen consecutive Gaussian taps.
    // Offsets stay between adjacent texels: thin neon never repeats.
    for(int i=0;i<4;i++) {
        vec2 offset=d*pairedTaps[i].x;
        c+=(texture(texture0,fragTexCoord+offset).rgb+
            texture(texture0,fragTexCoord-offset).rgb)*pairedTaps[i].y;
    }
    finalColor=vec4(c,1.);
}`
EXPEDITION_HDR_RESOLVE :: `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform sampler2D bloomTexture;
uniform float exposure;
out vec4 finalColor;
vec3 aces(vec3 v) {return clamp((v*(2.51*v+.03))/(v*(2.43*v+.59)+.14),0.,1.);}
void main() {
    vec3 c=texture(texture0,fragTexCoord).rgb;
    c+=texture(bloomTexture,fragTexCoord).rgb*.38;
    finalColor=vec4(pow(aces(c*exposure),vec3(1./2.2)),1.);
}`

@(private)
load_expedition_hdr_target :: proc(width,height:c.int,shared_depth:c.uint=0,own_depth:bool=false)->(t:rl.RenderTexture2D,ok:bool) {
	if width<=0 || height<=0 {return}
	t.id=rlgl.LoadFramebuffer();if t.id==0 {return}
	format:=rl.PixelFormat.UNCOMPRESSED_R16G16B16A16
	t.texture={id=rlgl.LoadTexture(nil,width,height,c.int(format),1),width=width,height=height,mipmaps=1,format=format}
	depth:=shared_depth
	if own_depth {depth=rlgl.LoadTextureDepth(width,height,true)}
	t.depth={id=depth,width=width,height=height,mipmaps=1}
	rlgl.FramebufferAttach(t.id,t.texture.id,c.int(rlgl.FramebufferAttachType.COLOR_CHANNEL0),c.int(rlgl.FramebufferAttachTextureType.TEXTURE2D),0)
	if depth!=0 {rlgl.FramebufferAttach(t.id,depth,c.int(rlgl.FramebufferAttachType.DEPTH),c.int(rlgl.FramebufferAttachTextureType.RENDERBUFFER),0)}
	ok=t.texture.id!=0 && (!own_depth || depth!=0) && rlgl.FramebufferComplete(t.id)
	if !ok {unload_expedition_hdr_target(&t,borrowed_depth=depth!=0 && !own_depth);return}
	rl.SetTextureFilter(t.texture,.BILINEAR);rl.SetTextureWrap(t.texture,.CLAMP)
	return
}

@(private)
unload_expedition_hdr_target :: proc(t:^rl.RenderTexture2D,borrowed_depth:bool=false) {
	if t.id==0 {return}
	// rlUnloadFramebuffer deletes its attached depth automatically. Detach
	// the board's borrowed renderbuffer before releasing the HDR framebuffer.
	if borrowed_depth && t.depth.id!=0 {
		rlgl.FramebufferAttach(t.id,0,c.int(rlgl.FramebufferAttachType.DEPTH),c.int(rlgl.FramebufferAttachTextureType.RENDERBUFFER),0)
	}
	rl.UnloadRenderTexture(t^);t^={}
}

@(private)
destroy_expedition_post :: proc(p:^^Expedition_Post) {
	if p^==nil {return}
	f:=p^;unload_expedition_hdr_target(&f.world,borrowed_depth=true)
	for &t in f.bloom {unload_expedition_hdr_target(&t)}
	for &t in f.reflection {unload_expedition_hdr_target(&t)}
	for shader in ([4]rl.Shader{f.extract,f.blur,f.resolve,f.backdrop}) {if shader.id!=0 {rl.UnloadShader(shader)}}
	free(f);p^=nil
}

@(private)
create_expedition_post :: proc(s:^Tactical_Surface)->bool {
	if s.post!=nil {return true}
	p:=new(Expedition_Post);s.post=p
	w,h:=s.target.texture.width,s.target.texture.height
	ok:bool;p.world,ok=load_expedition_hdr_target(w,h,s.target.depth.id)
	if !ok {destroy_expedition_post(&s.post);return false}
	for &t in p.bloom {t,ok=load_expedition_hdr_target(max(w/4,1),max(h/4,1));if !ok {destroy_expedition_post(&s.post);return false}}
	for &t,i in p.reflection {t,ok=load_expedition_hdr_target(max(w/2,1),max(h/2,1),own_depth=i==0);if !ok {destroy_expedition_post(&s.post);return false}}
	p.extract=rl.LoadShaderFromMemory(nil,EXPEDITION_BLOOM_EXTRACT)
	p.blur=rl.LoadShaderFromMemory(nil,EXPEDITION_GAUSSIAN_BLUR)
	p.resolve=rl.LoadShaderFromMemory(nil,EXPEDITION_HDR_RESOLVE)
	p.backdrop=rl.LoadShaderFromMemory(nil,EXPEDITION_HDR_BACKDROP)
	if !rl.IsShaderValid(p.extract) || !rl.IsShaderValid(p.blur) || !rl.IsShaderValid(p.resolve) || !rl.IsShaderValid(p.backdrop) {destroy_expedition_post(&s.post);return false}
	p.blur_direction=rl.GetShaderLocation(p.blur,"direction")
	p.blur_center=rl.GetShaderLocation(p.blur,"centerWeight");p.blur_pairs=rl.GetShaderLocation(p.blur,"pairedTaps[0]")
	p.bloom_kernel=expedition_blur_kernel(1.6)
	p.extract_threshold=rl.GetShaderLocation(p.extract,"threshold")
	p.resolve_bloom=rl.GetShaderLocation(p.resolve,"bloomTexture");p.resolve_exposure=rl.GetShaderLocation(p.resolve,"exposure")
	return true
}

@(private)
expedition_fullscreen :: proc(renderer:^Renderer,texture:rl.Texture2D) {
	rl.DrawTexturePro(texture,{0,0,f32(texture.width),-f32(texture.height)},{0,0,renderer.canvas_width,renderer.canvas_height},{},0,rl.WHITE)
}

@(private)
expedition_blur :: proc(renderer:^Renderer,p:^Expedition_Post,source:rl.Texture2D,target:rl.RenderTexture2D,direction:rl.Vector2,kernel:^Expedition_Blur_Kernel) {
	canvas.begin(target,renderer.canvas_width,renderer.canvas_height)
	d:=direction;rl.SetShaderValue(p.blur,p.blur_direction,&d,.VEC2)
	rl.SetShaderValue(p.blur,p.blur_center,&kernel.center,.FLOAT)
	rl.SetShaderValueV(p.blur,p.blur_pairs,&kernel.pairs[0],.VEC2,len(kernel.pairs))
	rl.BeginShaderMode(p.blur);expedition_fullscreen(renderer,source);rl.EndShaderMode();rl.EndTextureMode()
}

@(private)
prepare_expedition_reflection :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	s:=renderer.tactical.surface;m:=renderer.tactical.expedition_material
	if s==nil || s.post==nil || m==nil || !s.hdr_active {return}
	p:=s.post;p.profile=expedition_biome_surface(w.biome)
	started:=rl.GetTime()
	rl.EndTextureMode()
	canvas.begin(p.reflection[0],renderer.canvas_width,renderer.canvas_height)
	rl.ClearBackground(rl.BLACK)
	rl.BeginMode3D(renderer.tactical.camera)
	m.reflection_pass=true
	rlgl.PushMatrix();rlgl.Scalef(1,-1,1)
	draw_expedition_architecture(renderer,room,w)
	rlgl.DrawRenderBatchActive();rlgl.PopMatrix()
	m.reflection_pass=false
	rl.EndMode3D();rl.EndTextureMode()
	blur_started:=rl.GetTime();p.timing.reflection_ms=(blur_started-started)*1000
	// Reflection blur is in scene pixels, so resizing keeps material scale.
	radius:=.6+p.profile.roughness*3.5
	if radius!=p.reflection_sigma {p.reflection_sigma=radius;p.reflection_kernel=expedition_blur_kernel(radius)}
	expedition_blur(renderer,p,p.reflection[0].texture,p.reflection[1],{1,0},&p.reflection_kernel)
	expedition_blur(renderer,p,p.reflection[1].texture,p.reflection[2],{0,1},&p.reflection_kernel)
	p.timing.reflection_blur_ms=(rl.GetTime()-blur_started)*1000
	p.reflection_ready=true
	canvas.begin(p.world,renderer.canvas_width,renderer.canvas_height)
}

// Called between environment and paper. A colour-only resolve retains the
// shared depth renderbuffer; ClearBackground here would erase occlusion.
@(private)
resolve_expedition_world :: proc(renderer:^Renderer) {
	s:=renderer.tactical.surface;if s==nil || !s.hdr_active || s.post==nil {return}
	p:=s.post;started:=rl.GetTime();rl.EndTextureMode()
	canvas.begin(p.bloom[0],renderer.canvas_width,renderer.canvas_height)
	threshold:=f32(.9);rl.SetShaderValue(p.extract,p.extract_threshold,&threshold,.FLOAT)
	rl.BeginShaderMode(p.extract);expedition_fullscreen(renderer,p.world.texture);rl.EndShaderMode();rl.EndTextureMode()
	expedition_blur(renderer,p,p.bloom[0].texture,p.bloom[1],{1,0},&p.bloom_kernel)
	expedition_blur(renderer,p,p.bloom[1].texture,p.bloom[0],{0,1},&p.bloom_kernel)
	resolve_started:=rl.GetTime();p.timing.bloom_ms=(resolve_started-started)*1000
	canvas.begin(s.target,renderer.canvas_width,renderer.canvas_height)
	rlgl.DisableDepthTest();rlgl.DisableDepthMask()
	rl.SetShaderValue(p.resolve,p.resolve_exposure,&p.profile.exposure,.FLOAT)
	rl.BeginShaderMode(p.resolve);rl.SetShaderValueTexture(p.resolve,p.resolve_bloom,p.bloom[0].texture)
	expedition_fullscreen(renderer,p.world.texture);rl.EndShaderMode();rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()
	p.timing.resolve_ms=(rl.GetTime()-resolve_started)*1000
	s.hdr_active=false
}

Expedition_Reflection_Uniforms :: struct {sharp,blur,viewport,amount,eye:c.int}
EXPEDITION_REFLECTION_GLSL :: `
uniform sampler2D reflectionSharp;
uniform sampler2D reflectionBlur;
uniform vec2 reflectionViewport;
uniform float reflectionAmount;
uniform vec3 reflectionEye;
vec3 expedition_reflection(vec3 p,vec3 normal,float roughness) {
    if(reflectionAmount<=0.) return vec3(0.);
    vec2 uv=gl_FragCoord.xy/reflectionViewport;
    // Subtle brushed surface distortion, bounded to avoid swimming edges.
    uv+=vec2(sin(p.z*19.+p.x*3.),cos(p.x*17.))*roughness*.0006;
    vec3 sharp=texture(reflectionSharp,uv).rgb;
    vec3 blurred=texture(reflectionBlur,uv).rgb;
    float grazing=1.-max(dot(normalize(reflectionEye-p),normal),0.);
    float fresnel=.06+.94*pow(grazing,3.);
    float softness=.65+.35*smoothstep(.08,.65,roughness);
    return mix(sharp,blurred,softness)*reflectionAmount*fresnel;
}
`
expedition_reflection_uniforms :: proc(shader:rl.Shader)->Expedition_Reflection_Uniforms {
	return {rl.GetShaderLocation(shader,"reflectionSharp"),rl.GetShaderLocation(shader,"reflectionBlur"),
		rl.GetShaderLocation(shader,"reflectionViewport"),rl.GetShaderLocation(shader,"reflectionAmount"),rl.GetShaderLocation(shader,"reflectionEye")}
}
set_expedition_reflection :: proc(renderer:^Renderer,shader:rl.Shader,u:Expedition_Reflection_Uniforms) {
	s:=renderer.tactical.surface;amount:=f32(0)
	if s!=nil && s.post!=nil && s.post.reflection_ready && s.hdr_active {
		p:=s.post;amount=p.profile.reflection
		rl.SetShaderValueTexture(shader,u.sharp,p.reflection[0].texture);rl.SetShaderValueTexture(shader,u.blur,p.reflection[2].texture)
	}
	viewport:=rl.Vector2{renderer.canvas_width,renderer.canvas_height}*canvas.scale()
	rl.SetShaderValue(shader,u.viewport,&viewport,.VEC2);rl.SetShaderValue(shader,u.amount,&amount,.FLOAT)
	rl.SetShaderValue(shader,u.eye,&renderer.tactical.camera.position,.VEC3)
}

// Explicit native smoke only: prove that HDR energy survived the real GPU
// buffers (a screenshot alone cannot distinguish HDR from a bright LDR tint).
expedition_render_smoke_check :: proc(renderer:^Renderer)->bool {
	s:=renderer.tactical.surface;f:=renderer.tactical.expedition_floor
	if s==nil || s.post==nil || f==nil || !f.data.ready || f.failed {return false}
	p:=s.post
	if p.world.depth.id==0 || p.world.depth.id!=s.target.depth.id {return false}
	peaks:[3]f32
	for texture,i in ([3]rl.Texture2D{p.world.texture,p.bloom[0].texture,p.reflection[0].texture}) {
		if texture.format!=.UNCOMPRESSED_R16G16B16A16 {return false}
		data:=rlgl.ReadTexturePixels(texture.id,texture.width,texture.height,c.int(texture.format))
		if data==nil {return false}
		pixels:=cast([^]f16)data
		valid:=true
		for j in 0..<int(texture.width)*int(texture.height)*4 {
			if j%4==3 {continue}
			v:=f32(pixels[j])
			if math.is_nan(v) || math.is_inf(v) || v<0 {valid=false;break}
			peaks[i]=max(peaks[i],v)
		}
		rl.MemFree(data)
		if !valid {return false}
	}
	fmt.printf("RENDER CHECK: HDR %dx%d, scene peak %.3f, bloom %.3f, reflection %.3f, lights %d, floor builds %d\n",
		p.world.texture.width,p.world.texture.height,peaks[0],peaks[1],peaks[2],renderer.tactical.expedition_material.lights.count,f.data.rebuilds)
	return peaks[0]>1.1 && peaks[1]>.001 && peaks[2]>1.1
}
