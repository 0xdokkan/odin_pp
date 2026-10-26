package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import campaign "../campaign"
import game "../game"
import world "../expedition"

EXPEDITION_LIGHTS :: 32
EXPEDITION_TILED_LIGHTS :: #config(EXPEDITION_TILED_LIGHTS,true)
EXPEDITION_LIGHT_TILE_SIDE :: 8
EXPEDITION_LIGHT_TILE_SIZE :: f32(8)
EXPEDITION_LIGHT_TILE_COUNT :: EXPEDITION_LIGHT_TILE_SIDE*EXPEDITION_LIGHT_TILE_SIDE
#assert(EXPEDITION_LIGHTS==32 && size_of(c.int)==size_of(u32))
Expedition_Light_Uniforms :: struct {eye,mirror,count,start,end,color,tiles,tile_origin,dim_box,dim_amount,sky_shade:c.int}
Expedition_Lights :: struct {
	start,end,color:[EXPEDITION_LIGHTS]rl.Vector4,
	count:c.int,
	tile_origin:rl.Vector2,
	// glUniform1iv takes signed integers; the shader's uint(int) preserves
	// the complete bit pattern, including light31 in the signed high bit.
	tiles:[EXPEDITION_LIGHT_TILE_COUNT]c.int,
}
Expedition_Surface_Profile :: struct {roughness,reflection,exposure:f32}

expedition_biome_surface :: proc(b:campaign.Biome)->Expedition_Surface_Profile {
	switch b {
	case .Cyber:return {.23,.52,1.10}
	case .West:return {.66,.20,1.18}
	case .Jungle:return {.56,.28,1.12}
	case .City:return {.29,.49,1.10}
	case .Egypt:return {.39,.40,1.16}
	case .Vietnam:return {.32,.46,1.10}
	case .Snow:return {.19,.60,1.02}
	case .Inferno:return {.31,.48,1.00}
	case .Gothic:return {.35,.44,1.12}
	case .Sky:return {.26,.51,1.08}
	case .Space:return {.20,.58,1.06}
	case .Secret:return {.16,.65,1.10}
	case .Count:return {.5,.3,1.1}
	}
	return {.5,.3,1.1}
}

// Shared by architecture and the one-quad floor. All light transport is
// linear; only the world resolve converts back to the display's sRGB.
when EXPEDITION_TILED_LIGHTS {
	EXPEDITION_LIGHT_DEFINE :: "\n#define EXPEDITION_TILED_LIGHTS 1\n"
} else {
	EXPEDITION_LIGHT_DEFINE :: "\n#define EXPEDITION_TILED_LIGHTS 0\n"
}
EXPEDITION_LIGHT_GLSL :: EXPEDITION_LIGHT_DEFINE+`
uniform vec3 lightEye;
uniform float lightMirror;
uniform int lightCount;
uniform vec4 lightStart[32];
uniform vec4 lightEnd[32];
uniform vec4 lightColor[32];
#if EXPEDITION_TILED_LIGHTS
uniform int lightTiles[64];
uniform vec2 lightTileOrigin;
uint expedition_light_mask(vec2 p) {
    vec2 tile=floor((p-lightTileOrigin)*.125);
    // Distant floor, reflected geometry and future camera extents retain
    // the full source list outside the finite grid.
    if(any(lessThan(tile,vec2(0.))) || any(greaterThanEqual(tile,vec2(8.)))) return 0xffffffffu;
    ivec2 cell=ivec2(tile);
    return uint(lightTiles[cell.y*8+cell.x]);
}
#endif
vec3 expedition_linear(vec3 c) { return pow(max(c,vec3(0.)),vec3(2.2)); }
uniform vec4 dimBox;
uniform float dimAmount;
// How much of the sky's light the rock takes away (Fase 4's rule: under it the sky's light falls, the lamps stay): 0 in
// the open, which every program has unless it sets it (the floor program's caves' pass does).
uniform float skyShade;
vec3 expedition_lit_open(vec3 p,vec3 normal,vec3 srgbBase,float roughness,float metallic) {
    if(lightMirror>.5) {p.y=-p.y;normal.y=-normal.y;}
    vec3 n=normalize(normal);
    vec3 base=expedition_linear(srgbBase);
    vec3 key=normalize(vec3(-.45,1.,.3));
    vec3 result=base*(.65+max(dot(n,key),0.)*1.65)*(1.-skyShade);
#if EXPEDITION_TILED_LIGHTS
    uint candidates=expedition_light_mask(p.xz);
    if(candidates==0u) return result;
#endif
    vec3 v=normalize(lightEye-p);
    vec3 f0=mix(vec3(.045),base,metallic);
    float power=mix(180.,5.,roughness*roughness);
    for(int i=0;i<lightCount;i++) {
#if EXPEDITION_TILED_LIGHTS
        if((candidates&(1u<<uint(i)))==0u) continue;
#endif
        vec3 a=lightStart[i].xyz,b=lightEnd[i].xyz,ab=b-a;
        // Segment and radius reciprocals are prepared once per source, not
        // recomputed for every fragment in both world and reflection passes.
        vec3 closest=a+ab*clamp(dot(p-a,ab)*lightEnd[i].w,0.,1.);
        vec3 delta=closest-p;
        float distance2=dot(delta,delta);
        float radial=distance2*lightColor[i].w;
        if(radial>=1.) continue;
        vec3 l=delta*inversesqrt(max(distance2,.0001));
        float edge=1.-radial;
        float falloff=edge*edge/(1.+distance2*.8);
        float diffuse=max(dot(n,l),0.);
        vec3 response=base*(.5+diffuse*2.);
        if(diffuse>0.) {
            vec3 h=normalize(l+v);
            float spec=pow(max(dot(n,h),0.),power)*(1.-roughness*.6);
            float facing=1.-max(dot(v,h),0.);
            float facing2=facing*facing;
            vec3 fresnel=f0+(1.-f0)*(facing2*facing2*facing);
            response+=fresnel*spec*.8;
        }
        result+=lightColor[i].rgb*falloff*response;
    }
    return result;
}
// Inside a building everything outside its footprint is darker (dimBox is x0,z0,x1,z1).
vec3 expedition_lit(vec3 p,vec3 normal,vec3 srgbBase,float roughness,float metallic) {
    vec3 lit=expedition_lit_open(p,normal,srgbBase,roughness,metallic);
    if(dimAmount>0.) {
        bool within=p.x>=dimBox.x && p.x<=dimBox.z && p.z>=dimBox.y && p.z<=dimBox.w;
        if(!within) lit*=1.-dimAmount;
    }
    return lit;
}
`

expedition_light_uniforms :: proc(shader:rl.Shader)->Expedition_Light_Uniforms {
	return {rl.GetShaderLocation(shader,"lightEye"),rl.GetShaderLocation(shader,"lightMirror"),
		rl.GetShaderLocation(shader,"lightCount"),rl.GetShaderLocation(shader,"lightStart[0]"),
		rl.GetShaderLocation(shader,"lightEnd[0]"),rl.GetShaderLocation(shader,"lightColor[0]"),
		rl.GetShaderLocation(shader,"lightTiles[0]"),rl.GetShaderLocation(shader,"lightTileOrigin"),
		rl.GetShaderLocation(shader,"dimBox"),rl.GetShaderLocation(shader,"dimAmount"),rl.GetShaderLocation(shader,"skyShade")}
}

set_expedition_lights :: proc(renderer:^Renderer,shader:rl.Shader,u:Expedition_Light_Uniforms) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	eye:=renderer.tactical.camera.position;mirror:=f32(0)
	if m.reflection_pass {mirror=1;eye.y=-eye.y}
	rl.SetShaderValue(shader,u.eye,&eye,.VEC3);rl.SetShaderValue(shader,u.mirror,&mirror,.FLOAT)
	l:=&m.lights;rl.SetShaderValue(shader,u.count,&l.count,.INT)
	rl.SetShaderValue(shader,u.dim_box,&m.dim_box,.VEC4);rl.SetShaderValue(shader,u.dim_amount,&m.dim_amount,.FLOAT)
	when EXPEDITION_TILED_LIGHTS {
		rl.SetShaderValueV(shader,u.tiles,&l.tiles[0],.INT,EXPEDITION_LIGHT_TILE_COUNT)
		rl.SetShaderValue(shader,u.tile_origin,&l.tile_origin,.VEC2)
	}
	if l.count>0 {
		rl.SetShaderValueV(shader,u.start,&l.start[0],.VEC4,l.count)
		rl.SetShaderValueV(shader,u.end,&l.end[0],.VEC4,l.count)
		rl.SetShaderValueV(shader,u.color,&l.color[0],.VEC4,l.count)
	}
}

// Each tile receives every capsule whose XZ AABB overlaps it. Dropping Y is
// deliberately conservative for walls, floors and reflected geometry alike.
// Build only after dynamic sorting has finalized slot identities for this frame.
@(private)
expedition_build_light_tiles :: proc(l:^Expedition_Lights,focus:rl.Vector3) {
	l.tiles={}
	l.tile_origin={math.floor(focus.x/EXPEDITION_LIGHT_TILE_SIZE)*EXPEDITION_LIGHT_TILE_SIZE-32,
		math.floor(focus.z/EXPEDITION_LIGHT_TILE_SIZE)*EXPEDITION_LIGHT_TILE_SIZE-32}
	for i in 0..<int(l.count) {
		a,b:=l.start[i],l.end[i]
		// The small pad includes both sides of exact tile-boundary contact,
		// and covers float rounding in the fragment's capsule distance test.
		radius:=a.w+.001
		x0:=int(math.floor((min(a.x,b.x)-radius-l.tile_origin.x)/EXPEDITION_LIGHT_TILE_SIZE))
		x1:=int(math.floor((max(a.x,b.x)+radius-l.tile_origin.x)/EXPEDITION_LIGHT_TILE_SIZE))
		z0:=int(math.floor((min(a.z,b.z)-radius-l.tile_origin.y)/EXPEDITION_LIGHT_TILE_SIZE))
		z1:=int(math.floor((max(a.z,b.z)+radius-l.tile_origin.y)/EXPEDITION_LIGHT_TILE_SIZE))
		if x1<0 || z1<0 || x0>=EXPEDITION_LIGHT_TILE_SIDE || z0>=EXPEDITION_LIGHT_TILE_SIDE {continue}
		bit:=c.int(u32(1)<<u32(i))
		for z in max(z0,0)..=min(z1,EXPEDITION_LIGHT_TILE_SIDE-1) {
			for x in max(x0,0)..=min(x1,EXPEDITION_LIGHT_TILE_SIDE-1) {l.tiles[z*EXPEDITION_LIGHT_TILE_SIDE+x]|=bit}
		}
	}
}

// CPU counterpart of the shader lookup, also useful for headless spatial
// correctness checks. Outside the grid must always mean all32 candidates.
@(private)
expedition_light_mask_at :: proc(l:^Expedition_Lights,p:rl.Vector3)->u32 {
	x:=math.floor((p.x-l.tile_origin.x)/EXPEDITION_LIGHT_TILE_SIZE)
	z:=math.floor((p.z-l.tile_origin.y)/EXPEDITION_LIGHT_TILE_SIZE)
	if x<0 || z<0 || x>=EXPEDITION_LIGHT_TILE_SIDE || z>=EXPEDITION_LIGHT_TILE_SIDE {return 0xffffffff}
	return u32(l.tiles[int(z)*EXPEDITION_LIGHT_TILE_SIDE+int(x)])
}

@(private)
expedition_add_light :: proc(l:^Expedition_Lights,a,b,color:rl.Vector3,radius:f32) {
	if l.count>=EXPEDITION_LIGHTS || radius<=0 {return}
	i:=l.count;l.start[i]={a.x,a.y,a.z,radius}
	l.end[i]={b.x,b.y,b.z,1/max(rl.Vector3DistanceSqr(a,b),.0001)}
	l.color[i]={color.x,color.y,color.z,1/(radius*radius)};l.count+=1
}

// Keep nearby active effects when many devices are on the board. The fixed
// architectural lights and robot occupy the prefix; only the tail competes.
@(private)
expedition_add_near_light :: proc(l:^Expedition_Lights,first:int,focus,a,color:rl.Vector3,radius:f32) {
	if first>=EXPEDITION_LIGHTS || radius<=0 {return}
	distance:=rl.Vector3DistanceSqr(focus,a)
	index:=min(int(l.count),EXPEDITION_LIGHTS-1)
	if int(l.count)>=EXPEDITION_LIGHTS {
		last:=l.start[index]
		if distance>=rl.Vector3DistanceSqr(focus,{last.x,last.y,last.z}) {return}
	}
	for index>first {
		previous:=l.start[index-1]
		if distance>=rl.Vector3DistanceSqr(focus,{previous.x,previous.y,previous.z}) {break}
		l.start[index]=previous;l.end[index]=l.end[index-1];l.color[index]=l.color[index-1];index-=1
	}
	l.start[index]={a.x,a.y,a.z,radius};l.end[index]={a.x,a.y,a.z,10000};l.color[index]={color.x,color.y,color.z,1/(radius*radius)}
	l.count=min(l.count+1,EXPEDITION_LIGHTS)
}

@(private)
prepare_expedition_lights :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	l:=&m.lights;l.count=0
	focus:=renderer.tactical.camera.target
	defer {when EXPEDITION_TILED_LIGHTS {expedition_build_light_tiles(l,focus)}}
	// Reserve slots for light sources that move or appear during combat.
	for e in m.edges.emitters[:min(m.edges.emitter_count,24)] {expedition_add_light(l,e.a,e.b,e.radiance,5.5)}
	s:=renderer.tactical.snapshot;if s==nil {return}
	if s.player.visible {
		p,_:=living_card_position(renderer,game.PLAYER_ENTITY,.Player,s.player.position)
		a:=rl.Vector3{p.x+.5,.65+entity_point_ground(game.PLAYER_ENTITY,p),p.y+.5}
		// In a cave the robot's lamp is the light there is (Fase 4: darker, with the characters' lights).
		if renderer.tactical.expedition_in_cave {expedition_add_light(l,a,a,{1.9,1.62,1.15},5.5)}
		else {expedition_add_light(l,a,a,{.10,.42,.55},3)}
	}
	dynamic_start:=int(l.count)
	// In a cave the foes awake carry a faint light of their own.
	if renderer.tactical.expedition_in_cave {
		for actor in s.enemies[:s.enemy_count] {
			if !actor.visible || actor.health<=0 {continue}
			p,_:=living_card_position(renderer,actor.entity,sprite_key_for_enemy(actor.archetype),actor.position)
			a:=rl.Vector3{p.x+.5,.6+entity_point_ground(actor.entity,p),p.y+.5}
			expedition_add_near_light(l,dynamic_start,focus,a,{.55,.16,.10},2.6)
		}
	}
	for object in s.objects[:s.object_count] {
		if !object.visible {continue}
		a:=rl.Vector3{object.position.x+.5,.65+entity_point_ground(object.entity,object.position),object.position.y+.5};color:rl.Vector3
		#partial switch object.kind {
		case .Tesla_Coil,.Shock_Floor:color={.2,.8,3.5}
		case .Fire:color={3.2,.65,.08}
		case .Bomb,.Bomb_Marley:color={2.2,.18,.04}
		case .Black_Hole:color={1.2,.15,2.4}
		}
		if color!={} && rl.Vector3DistanceSqr(a,focus)<18*18 {
			pulse:=.9+.1*math.sin(w.clock*5+a.x);expedition_add_near_light(l,dynamic_start,focus,a,color*pulse,4)
		}
	}
	for fire in s.ground.fires[:s.ground.fire_count] {
		a:=rl.Vector3{f32(fire.center.x)+.5,.45+cell_ground(fire.center),f32(fire.center.y)+.5}
		if rl.Vector3DistanceSqr(a,focus)<18*18 {expedition_add_near_light(l,dynamic_start,focus,a,{3.5,.7,.06},4.5)}
	}
}
