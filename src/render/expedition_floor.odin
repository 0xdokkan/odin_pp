package render

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import level "../level"

// One plane and one exact integer map texture replace thousands of floor
// boxes. Only map mutations upload texels; all animation stays in uniforms.
// A floor program and where its uniforms are. There are two of one source: the plain one, and one that also thins out
// the terraces of a tall mountain in front of an actor (a discard, which costs the early depth test, so it is
// only used where such a mountain is in view).
Expedition_Floor_Program :: struct {
	shader: rl.Shader,
	map_data, map_size, tint, time, beat, lane, lane_warning, biome: c.int,
	focus, focus_count, grid_amount, surface: c.int,
	cyber_workshops, cyber_workshop_count, workshop_stock: c.int,
	reveal_eye, reveal_forward, reveal_viewport, reveal_points, reveal_count, reveal_floor: c.int,
	// The pass (0 the ground, 1 the rooms under it: expedition_layers.odin, 2 the decks over it: expedition_decks.odin) and
	// the fade over the robot.
	layer, cover: c.int,
	lights: Expedition_Light_Uniforms,
	reflection: Expedition_Reflection_Uniforms,
}

Expedition_Floor :: struct {
	data: Expedition_Floor_Data,
	texture: rl.Texture2D,
	workshop_stock:[2]rl.Texture2D,
	workshop_failed:[2]bool,
	active_stock:rl.Texture2D,
	plain, tall: Expedition_Floor_Program,
	failed: bool,
	// The terraces of the map's relief, over the plane (expedition_terrain.odin).
	terrain: Expedition_Terrain_Cache,
	// The caves' rooms under the ground (expedition_layers.odin).
	under: Expedition_Under_Cache,
	// The complexes' decks over it (expedition_decks.odin).
	decks: Expedition_Under_Cache,
	// The program bound while the floor draws (nil out of it): the blocks on the video card draw with it
	// (expedition_terrain.odin, draw_terrain_chunk).
	bound: ^Expedition_Floor_Program,
}

EXPEDITION_FLOOR_HEADER_BODY :: `in vec3 worldPosition;
in vec3 normal;
in vec2 surfaceUV;
in vec4 color;
out vec4 finalColor;
`
EXPEDITION_FLOOR_HEADER :: "#version 330\n"+EXPEDITION_FLOOR_HEADER_BODY
EXPEDITION_FLOOR_BODY :: `
uniform sampler2D floorMap;
uniform vec2 mapSize;
uniform vec3 biomeTint;
uniform float worldClock;
uniform int worldBeat;
uniform int floorBiome;
uniform vec4 warningLane;
uniform int laneWarning;
uniform vec4 gridFocus[9];
uniform int gridFocusCount;
uniform float gridAmount;
uniform vec2 floorSurface;
// 0: the ground and its relief; 1: the rooms under it (expedition_layers.odin); 2: the decks over it (expedition_decks.odin).
uniform int floorLayer;
#ifdef TERRACE_REVEAL
uniform vec3 eye;
uniform vec3 viewForward;
uniform vec2 viewport;
uniform vec4 reveal[9];
uniform int revealCount;
// The height of the ground the robot stands on: only what is above it can be in its way.
uniform float revealFloor;
// The robot's point (x, z), the height of his eyes (y), and whether what is over them fades (w): the ground in a cave,
// the decks always.
uniform vec4 coverPoint;
#endif
const float BAYER[16]=float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);

ivec4 mapCell(ivec2 p) {
    if(any(lessThan(p,ivec2(0))) || any(greaterThanEqual(p,ivec2(mapSize)))) return ivec4(0);
    return ivec4(round(texelFetch(floorMap,p,0)*255.));
}
float inkLine(float d,float width,float aa) {
    return 1.-smoothstep(width,width+aa,abs(d));
}
float borderMask(int bits,vec2 uv,float width,float aa) {
    float d=2.;
    if((bits&1)!=0) d=min(d,uv.x);
    if((bits&2)!=0) d=min(d,1.-uv.x);
    if((bits&4)!=0) d=min(d,uv.y);
    if((bits&8)!=0) d=min(d,1.-uv.y);
    return 1.-smoothstep(width,width+aa,d);
}
// Rounded outer banks follow actual terrain connectivity. Shared cell edges
// have no border, and world-registered bends never become a tiled texture.
float terrainCoverage(int edges,vec2 uv,vec2 p,float aa) {
    float d=2.;
    if((edges&1)!=0) d=min(d,uv.x);
    if((edges&2)!=0) d=min(d,1.-uv.x);
    if((edges&4)!=0) d=min(d,uv.y);
    if((edges&8)!=0) d=min(d,1.-uv.y);
    float r=.22;
    if((edges&5)==5 && uv.x<r && uv.y<r) d=min(d,r-length(uv-vec2(r)));
    if((edges&6)==6 && uv.x>1.-r && uv.y<r) d=min(d,r-length(uv-vec2(1.-r,r)));
    if((edges&9)==9 && uv.x<r && uv.y>1.-r) d=min(d,r-length(uv-vec2(r,1.-r)));
    if((edges&10)==10 && uv.x>1.-r && uv.y>1.-r) d=min(d,r-length(uv-vec2(1.-r)));
    float bend=.018*sin(p.x*5.1+p.y*3.7)+.012*sin(p.y*8.-p.x*2.);
    return smoothstep(.015,.17+aa,d+bend);
}
float hash21(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
// Warm paper pigments are authored per biome, rather than brightening an
// old black/grey material. No tile hash, joints or squares modulate them.
vec3 paperGround(bool indoor) {
    vec3 outside=vec3(1.,.925,.78),inside=vec3(.65,.85,.88);
    if(floorBiome==1) {outside=vec3(.96,.76,.48);inside=vec3(.91,.64,.38);}
    else if(floorBiome==2) {outside=vec3(.73,.83,.43);inside=vec3(.86,.87,.62);}
    else if(floorBiome==3) {outside=vec3(.79,.67,.76);inside=vec3(.94,.80,.78);}
    else if(floorBiome==4) {outside=vec3(1.,.84,.54);inside=vec3(.98,.91,.70);}
    else if(floorBiome==5) {outside=vec3(.74,.79,.45);inside=vec3(.88,.81,.56);}
    else if(floorBiome==6) {outside=vec3(.91,.95,.91);inside=vec3(.76,.87,.89);}
    else if(floorBiome==7) {outside=vec3(.79,.47,.41);inside=vec3(.91,.66,.48);}
    else if(floorBiome==8) {outside=vec3(.66,.61,.72);inside=vec3(.81,.74,.78);}
    else if(floorBiome==9) {outside=vec3(.99,.91,.78);inside=vec3(.92,.83,.92);}
    else if(floorBiome==10) {outside=vec3(.70,.62,.82);inside=vec3(.84,.76,.90);}
    else if(floorBiome==11) {outside=vec3(.70,.59,.69);inside=vec3(.88,.77,.62);}
    return indoor?inside:outside;
}
float valueNoise(vec2 p) {
    vec2 i=floor(p),f=fract(p);
    f=f*f*(3.-2.*f);
    return mix(mix(hash21(i),hash21(i+vec2(1.,0.)),f.x),mix(hash21(i+vec2(0.,1.)),hash21(i+vec2(1.)),f.x),f.y);
}
// The ground is one sheet of coloured card: a slow wash of pigment across
// several cells and, close enough to resolve it, the card's own fibre.
vec3 paperStock(vec2 p,vec3 base,float aa) {
    float wash=valueNoise(p*.13)*.65+valueNoise(p*.31+vec2(7.3,2.1))*.35;
    base*=1.+(wash-.5)*.13;
    if(aa>=.09) return base;
    float fibre=valueNoise(p*vec2(6.,11.)+vec2(3.,9.))*.6+valueNoise(p*vec2(17.,9.)+vec2(1.7,4.4))*.4;
    return base*(1.+(fibre-.5)*.06*(1.-smoothstep(.03,.09,aa)));
}
float drawnSegment(vec2 p,vec2 a,vec2 b,float width,float aa) {
    vec2 d=b-a;
    return 1.-smoothstep(width,width+aa,length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.,1.)));
}
`+EXPEDITION_CYBER_FLOOR_GLSL+`
// A few small pen drawings, scattered away from cell centres. Hashing only
// places each motif; it never makes a noisy or tiled colour field.
vec3 paperDetails(vec2 p,vec3 base,float aa,bool indoor,float detailWeight) {
    vec2 field=p/3.1,seed=floor(field);
    float h=hash21(seed+vec2(13.,7.));
    vec2 center=vec2(.22)+vec2(hash21(seed),hash21(seed+37.))*.56;
    vec2 q=(fract(field)-center)*3.1;
    float visible=step(.66,h)*(1.-smoothstep(.04,.09,aa));
    visible*=detailWeight;
    if(visible==0.) return base;
    float mark=0.,paint=0.;
    vec3 ink=base*vec3(.56,.55,.60),pigment=min(base+vec3(.12,.07,.02),1.);
    if(!indoor && (floorBiome==2 || floorBiome==5 || floorBiome==8)) {
        // A fallen pointed leaf and two short stems. Dark underside and
        // one broad painted half give the ground the same hand as foliage.
        vec2 leaf=(q-vec2(-.06,.02))*vec2(1.,.55);
        float shape=abs(leaf.x)+abs(leaf.y);
        mark=inkLine(shape-.13,.014,aa);
        paint=(1.-smoothstep(.10,.13+aa,shape))*step(0.,leaf.x);
        mark=max(mark,drawnSegment(q,vec2(-.16,.17),vec2(.06,-.14),.010,aa));
        mark=max(mark,drawnSegment(q,vec2(.17,.08),vec2(.24,-.04),.012,aa));
        ink=vec3(.25,.42,.24);pigment=vec3(.68,.71,.31);
    } else if(!indoor && (floorBiome==1 || floorBiome==4 || floorBiome==7)) {
        // A deliberate three-armed crack; broken ends leave quiet space.
        mark=drawnSegment(q,vec2(-.22,.06),vec2(.01,-.02),.012,aa);
        mark=max(mark,drawnSegment(q,vec2(.01,-.02),vec2(.18,.09),.012,aa));
        mark=max(mark,drawnSegment(q,vec2(.01,-.02),vec2(.05,-.14),.010,aa));
        paint=drawnSegment(q,vec2(-.20,.09),vec2(-.03,.03),.018,aa);
    } else if(floorBiome==6) {
        // Wind-combed snow: two low arcs rather than printed snowflake icons.
        float ridge=length((q-vec2(.04,.17))*vec2(.7,1.));
        mark=inkLine(ridge-.22,.012,aa)*step(q.y,.10)*step(-.17,q.x)*step(q.x,.24);
        paint=drawnSegment(q,vec2(-.07,-.03),vec2(.15,-.03),.025,aa);
        ink=vec3(.43,.63,.70);pigment=vec3(1.,.99,.91);
    } else {
        // A compact stone group with a painted top and short contact mark.
        float pebble=length((q-vec2(-.08,0.))*vec2(1.,1.65));
        mark=inkLine(pebble-.105,.014,aa)*step(-.055,q.y);
        mark=max(mark,drawnSegment(q,vec2(.10,.025),vec2(.22,-.005),.014,aa));
        paint=(1.-smoothstep(.065,.09+aa,pebble))*step(q.y,.01);
    }
    base=mix(base,pigment,paint*visible*.65);
    return mix(base,ink,mark*visible*.60);
}

// Broad deposits collect beside real solids. Their paper-cut edge follows the blurred
// height field, with a world-space wobble instead of a repeated mark per map cell.
vec3 paperAccumulation(vec2 p,vec3 base,float aa,float crowd) {
    if(crowd<.015) return base;
    float noise=valueNoise(p*.93+vec2(2.7,8.9));
    float field=crowd-(.055+.12*noise);
    float edge=max(.012,aa*.28);
    float cover=smoothstep(-edge,edge,field);
    float cut=1.-smoothstep(0.,edge*1.8,abs(field));
    vec3 pigment=vec3(.70,.68,.60);
    float amount=.50;
    if(floorBiome==1) pigment=vec3(.77,.57,.34);
    else if(floorBiome==2) {pigment=vec3(.44,.58,.24);amount=.65;}
    else if(floorBiome==3) pigment=vec3(.58,.51,.48);
    else if(floorBiome==4) {pigment=vec3(.96,.75,.41);amount=.70;}
    else if(floorBiome==5) {pigment=vec3(.43,.49,.23);amount=.60;}
    else if(floorBiome==6) {pigment=vec3(1.,.99,.92);amount=.82;}
    else if(floorBiome==7) {pigment=vec3(.43,.38,.42);amount=.65;}
    else if(floorBiome==8) {pigment=vec3(.42,.49,.31);amount=.60;}
    else if(floorBiome==9) {pigment=vec3(.98,.89,.91);amount=.70;}
    else if(floorBiome==10) pigment=vec3(.51,.48,.61);
    else if(floorBiome==11) {pigment=vec3(.74,.61,.80);amount=.65;}
    base=mix(base,pigment,cover*amount);
    return mix(base,base*vec3(.88,.87,.91),cut*.18);
}

// Continuous permission around hazards, using the floor's existing four
// samples. The old any-hazard boolean exposed a 2x2 square round each cell.
float paperDepositPermission(ivec4 near4[4],vec2 f,float aa) {
    // Terrain paint starts at .5-.03-aa, with at most +.13 of bank wobble.
    // At very coarse footprints it can reach every nonzero hazard weight.
    if(aa>=.34) return 0.;
    float distant=1.-smoothstep(.25,.34,aa);
    bool allSafe=true;
    float hazard[4];
    for(int i=0;i<4;i++) {
        int terrain=near4[i].g&15;
        bool safe=terrain==0 || terrain==2 || terrain==3 || terrain==6;
        hazard[i]=safe?0.:1.;allSafe=allSafe && safe;
    }
    if(allSafe) return distant;
    float field=mix(mix(hazard[0],hazard[1],f.x),mix(hazard[2],hazard[3],f.x),f.y);
    // A cell's own bilinear weight is >=.25 throughout its square, so this
    // also keeps Electric/Wind/Gravity glyph cells wholly free of deposits.
    // The other bound ends the fade before any interpolated hazard bank.
    float clearAt=min(.25,.34-aa);
    return distant*(1.-smoothstep(0.,clearAt,field));
}

void floorMain();
void caveMain();
void deckMain();
void main() {
    float rim=0.;
    float cover=1.;
#ifdef TERRACE_REVEAL
    // A hill or a mountain between the camera and the robot is cut away in a round window round the robot,
    // with a thin bright edge: no stipple. Only what stands above the robot's feet can be in its way (the ledge it
    // stands on is never cut), and only the robot has a window: whoever is behind the mountain stays hidden.
    if(revealCount>0 && worldPosition.y>revealFloor+.05) {
        vec2 uv=gl_FragCoord.xy/viewport;
        float depth=dot(worldPosition-eye,viewForward);
        // Up to half a cell behind the robot's middle too: its paper is as thick as that, and a cliff beside it
        // would otherwise cut it in two.
        if(depth<=reveal[0].w+.9) {
            vec2 d=(uv-reveal[0].xy)*vec2(viewport.x/viewport.y,1.);
            d.y*=.78;
            float r=length(d)/reveal[0].z;
            if(r<1.) discard;
            rim=1.-smoothstep(1.,1.12,r);
        }
    }
    // In a cave the ground over the robot's eyes opens round him (Fase 4's rule, game/layer_view.odin), and so does a deck
    // over them: within six cells, down to fifteen percent beside him, as a stipple; what is left of it is darker.
    if(floorLayer!=1 && coverPoint.w>0. && worldPosition.y>coverPoint.y) {
        float far=max(length(worldPosition.xz-coverPoint.xz)-.5,0.);
        if(far<6.) {
            float k=clamp((6.-far)/5.,0.,1.);
            cover=1.-.85*k*k*(3.-2.*k);
            ivec2 f=ivec2(gl_FragCoord.xy)&3;
            if(cover<=(BAYER[f.y*4+f.x]+.5)/16.) discard;
        }
    }
#endif
    if(floorLayer==1) caveMain(); else if(floorLayer==2) deckMain(); else floorMain();
    finalColor.rgb=mix(finalColor.rgb,vec3(.62,.92,1.),rim*.85);
    finalColor.rgb*=mix(.35,1.,cover);
#ifdef TERRACE_REVEAL
    // In a cave the ground is off the robot's layer: darker all of it, outside the cave as over it (dimBox, Fase 4).
    if(floorLayer==0 && coverPoint.w>0. && worldPosition.x>=dimBox.x && worldPosition.x<=dimBox.z && worldPosition.z>=dimBox.y && worldPosition.z<=dimBox.w) finalColor.rgb*=1.-dimAmount;
#endif
}
// A cave's rooms (expedition_layers.odin): dark worn slabs of the biome's stone, darker by the rock round them (the
// vertices' green); the walls and the cut of the rock (the vertices' red at 0) dark rock, lit facet by facet. The lamps
// do the rest (expedition_lighting.odin).
void caveMain() {
    vec3 n=normalize(normal);
    if(normal.y<.5 || color.r<.5) {
        vec3 rock=mix(vec3(.45,.43,.40),biomeTint*.45,.25);
        if(color.r<.5) rock*=.66;
        finalColor=vec4(expedition_lit(worldPosition,n,rock,.9,.05),1.);
        return;
    }
    vec2 p=worldPosition.xz;
    vec2 footprint=max(fwidth(p),vec2(.0001));
    float aa=max(footprint.x,footprint.y);
    ivec2 cell=ivec2(floor(p));
    vec2 uv=fract(p),q=uv-.5;
    vec3 base=mix(paperGround(false),vec3(.57,.48,.53),.42);
    base=paperDetails(p,base,aa,true,1.)*mix(.62,1.,color.g);
    vec3 emission=vec3(0.);
    if(gridAmount>0.) {
        float focus=0.;
        for(int i=0;i<gridFocusCount;i++) {
            float d=length(vec2(cell)+.5-gridFocus[i].xy);
            focus=max(focus,1.-smoothstep(gridFocus[i].z,gridFocus[i].w,d));
        }
        focus*=gridAmount;
        float edge=max(abs(q.x),abs(q.y));
        float inset=1.-smoothstep(.44,.45+aa,edge);
        float line=inkLine(edge-.45,.008,aa);
        base=mix(base,vec3(.62,.83,.86),focus*inset*.22);
        base=mix(base,vec3(.15,.39,.48),line*focus*.65);
        emission+=expedition_linear(biomeTint)*line*focus*.22;
    }
    finalColor=vec4(expedition_lit(worldPosition,n,base,.72,.05)+emission,1.);
}
// A complex's decks (expedition_decks.odin): the biome's bridge, its top in its own material, its frame (the edges, the
// underside, the trestles: the vertices' red at 0) darker. The vertices' green says the way it runs (along x at 1), their
// blue whether the cell is in its middle (1) or on its edge, their alpha how near an open side a point is (0 on it), where
// the biome's railing runs: the data walkway's neon, the train bridge's beam, the vine bridge's vines, the overpass's
// kerb, the bamboo bridge's rope, the rope bridge's ropes, the bones' ends, the gallery's balustrade, the floating island's
// gold fillet; the station's walkways are the data walkway's, in the Spazio's neon.
void deckMain() {
    vec3 n=normalize(normal);
    vec2 p=worldPosition.xz;
    vec2 footprint=max(fwidth(p),vec2(.0001));
    float aa=max(footprint.x,footprint.y);
    if(normal.y<.5 || color.r<.5) {
        vec3 frame=floorBiome==1?vec3(.165,.105,.062):(floorBiome==2?vec3(.105,.082,.048):vec3(.062,.070,.088));
        if(floorBiome==6) frame=vec3(.16,.13,.10);
        if(floorBiome==7) frame=vec3(.40,.35,.28);
        if(floorBiome==8) frame=vec3(.08,.065,.05);
        if(floorBiome==9) frame=vec3(.30,.31,.34);
        frame=mix(vec3(.90,.85,.72),clamp(frame*2.5,0.,1.),.62);
        if(normal.y<-.5) frame*=.6;
        finalColor=vec4(expedition_lit(worldPosition,n,frame,.8,floorBiome==0?.35:.04),1.);
        return;
    }
    // Along the bridge (q.x) and across it (q.y).
    vec2 q=color.g>.5?p:p.yx;
    float rim=1.-smoothstep(.04,.14,color.a);
    vec3 base,emission=vec3(0.);
    float roughness=.75,metallic=.04;
    if(floorBiome==1) {
        // The train's bridge: sleepers of dark wood across it on gravel, and in its middle two iron rails along it.
        float sleeper=1.-smoothstep(.30,.30+aa,abs(fract(q.x*2.)-.5));
        float grain=abs(fract(q.y*3.1+q.x*.4)-.5)*2.;
        base=mix(vec3(.105,.092,.080),mix(vec3(.205,.128,.070),vec3(.245,.160,.090),grain),sleeper);
        if(color.b>.5) {
            float across=fract(q.y);
            float rail=max(inkLine(across-.28,.022,aa),inkLine(across-.72,.022,aa));
            base=mix(base,vec3(.30,.30,.32),rail);
            metallic=mix(metallic,.7,rail);roughness=mix(roughness,.3,rail);
        }
        base=mix(base,vec3(.30,.19,.10),rim);
    } else if(floorBiome==3) {
        // A continuous painted road, with its actual bridge kerb and lane.
        base=vec3(.18,.14,.19);
        float dash=step(.5,fract(q.x*.5))*(1.-smoothstep(.04,.04+aa,abs(fract(q.y)-.5)));
        if(color.b>.5 || color.g>.5) base=mix(base,vec3(.42,.38,.20),dash*.8);
        base=mix(base,vec3(.30,.30,.32),rim);
        roughness=.6;
    } else if(floorBiome==5) {
        // The Vietnam's bamboo bridge: poles along it, bound across every half cell, a rope on its open sides.
        float pole=abs(fract(q.y*5.)-.5)*2.;
        float bind=1.-smoothstep(.05,.05+aa,abs(fract(q.x*2.)-.5));
        base=mix(vec3(.20,.17,.07),vec3(.36,.31,.13),smoothstep(.2,.9,pole));
        base=mix(base,vec3(.12,.09,.05),bind*.7);
        base=mix(base,vec3(.30,.25,.15),rim);
        roughness=.7;
    } else if(floorBiome==2) {
        // The vine bridge: planks across it with gaps between, lashed with green vines along its open sides.
        float plank=1.-smoothstep(.40,.40+aa,abs(fract(q.x*2.6)-.5));
        float grain=abs(fract(q.y*4.+q.x*.3)-.5)*2.;
        base=mix(vec3(.030,.034,.022),mix(vec3(.150,.105,.058),vec3(.185,.135,.075),grain),plank);
        float vine=rim*(.6+.4*sin(q.x*9.));
        base=mix(base,vec3(.09,.20,.05),clamp(vine,0.,1.));
        roughness=.85;
    } else if(floorBiome==6) {
        // The Neve's rope bridge: planks across it with dark gaps, frost on some, ropes along its open sides.
        float plank=1.-smoothstep(.36,.36+aa,abs(fract(q.x*3.)-.5));
        float grain=abs(fract(q.y*5.+q.x*.5)-.5)*2.;
        base=mix(vec3(.025,.030,.040),mix(vec3(.30,.25,.20),vec3(.38,.33,.27),grain),plank);
        float frost=step(.65,.5+.5*sin(q.x*.8+sin(q.y*.5)));
        base=mix(base,vec3(.80,.86,.92),frost*.35*plank);
        base=mix(base,vec3(.42,.36,.26),rim);
        roughness=.85;
    } else if(floorBiome==7) {
        // The Inferno's bridge of bones: pale ribs across it on a spine along its middle, embers glowing between them.
        float rib=1.-smoothstep(.28,.28+aa,abs(fract(q.x*2.5)-.5));
        float spine=1.-smoothstep(.10,.10+aa,abs(fract(q.y)-.5));
        float bone=max(rib,spine*.8);
        base=mix(vec3(.05,.02,.015),vec3(.44,.39,.31),bone);
        emission+=expedition_linear(vec3(1.,.32,.08))*(1.-bone)*.45;
        base=mix(base,vec3(.52,.46,.36),rim);
        roughness=.6;
    } else if(floorBiome==8) {
        // The Gotico's gallery: weathered boards along it with dark seams, a pale balustrade on its open sides.
        float board=1.-smoothstep(.42,.42+aa,abs(fract(q.y*4.)-.5));
        float grain=abs(fract(q.x*1.7+q.y*.3)-.5)*2.;
        base=mix(vec3(.03,.025,.02),mix(vec3(.15,.13,.11),vec3(.20,.18,.15),grain),board);
        base=mix(base,vec3(.52,.50,.44),rim);
        roughness=.9;
    } else if(floorBiome==9) {
        // The Cielo's floating island: pearl paper with sparse veins and a gold fillet along its
        // open sides.
        float vein=inkLine(fract(p.x*.16+p.y*.09+abs(fract(p.y*.11)-.5)*.22)-.5,.004,aa*.3);
        base=mix(vec3(.236,.246,.262),vec3(.123,.144,.173),vein*.14);
        base=mix(base,vec3(.42,.33,.16),rim);
        emission+=expedition_linear(vec3(.95,.74,.36))*rim*.22;
        roughness=mix(.34,.30,rim);metallic=mix(.04,.55,rim);
    } else {
        // Continuous printed walkway; the structural rim still identifies
        // the open edge, without a decorative checkerboard or grating.
        base=vec3(.16,.22,.27);
        metallic=.55;roughness=.42;
        emission+=expedition_linear(biomeTint)*rim*1.6;
    }
    // The same matte stock as the ground, retaining each bridge's motif.
    base=mix(paperGround(true),clamp(base*3.3,0.,1.),.32);
    base=paperDetails(p,base,aa,true,1.);
    roughness=max(roughness,.8);metallic*=.07;emission*=.15;
    // Lighter the higher it stands, as the ground (floorMain).
    base*=1.+clamp(worldPosition.y,0.,.72)*.10;
    finalColor=vec4(expedition_lit(worldPosition,n,base,roughness,metallic)+emission,1.);
}
void floorMain() {
    // The walls of a cliff are dark rock, tinted a little by the biome, lit facet by facet.
    if(normal.y<.5) {
        vec3 rock=mix(vec3(.60,.57,.49),biomeTint*.55,.22);
        if(floorBiome==0) rock=cyberCliffPigment(worldPosition,normalize(normal),(1.-color.g)*2.);
        // Under the board's plane, in a pit dug under a raised map's base, the biome's rock is lighter at the rim and
        // darker toward the bottom, so that the pit reads as a hollow and not as a slot of black.
        if(worldPosition.y<-.02) rock=mix(mix(vec3(.15,.16,.18),biomeTint*.42,.45),rock,smoothstep(0.,1.7,-worldPosition.y)*.75);
        finalColor=vec4(expedition_lit(worldPosition,normalize(normal),rock,.85,.1),1.);
        return;
    }
    vec2 p=worldPosition.xz;
    vec2 footprint=max(fwidth(p),vec2(.0001));
    float aa=max(footprint.x,footprint.y);
    ivec2 cell=ivec2(floor(p));
    ivec4 tile=mapCell(cell);
    int kind=tile.r&7,site=tile.b&15;
    if(kind==0) discard;
    vec2 uv=fract(p),q=uv-.5;
    bool cyber=floorBiome==0;
    bool indoor=site==2 || site==3 || site==4 || site==6 || site==7;
    float crowd=expedition_sky_crowd(worldPosition);
    float detailWeight=indoor?1.:smoothstep(.025,.22,crowd);
    // A site's paved ground meets the open ground along the half level of its cells' membership, as the terrain
    // patches do: built biomes keep straight edges, the others a gentle wobble and a cut line.
    // The four cells whose centres frame the point, read once for the paved ground and the terrain patches.
    vec2 around=p-.5;
    ivec2 c0=ivec2(floor(around));
    vec2 f=fract(around);
    ivec4 near4[4]=ivec4[4](mapCell(c0),mapCell(c0+ivec2(1,0)),mapCell(c0+ivec2(0,1)),mapCell(c0+ivec2(1,1)));
    vec3 base;
    {
        bool built=floorBiome==0 || floorBiome==3 || floorBiome==10;
        if(built) base=paperGround(indoor);
        else {
        float m[4];
        for(int i=0;i<4;i++) {
            int k=near4[i].b&15;
            m[i]=(k==2 || k==3 || k==4 || k==6 || k==7)?1.:0.;
        }
        float field=mix(mix(m[0],m[1],f.x),mix(m[2],m[3],f.x),f.y);
        if(field>0. && field<1.) field+=(valueNoise(p*1.7+vec2(2.3,8.1))-.5)*.24*smoothstep(0.,.25,field)*(1.-smoothstep(.75,1.,field));
        float paved=smoothstep(.5-.03-aa,.5+.03+aa,field);
        base=mix(paperGround(false),paperGround(true),paved);
        base=mix(base,base*vec3(.86,.84,.88),(1.-smoothstep(0.,.04+aa,abs(field-.5)))*.5);
        }
    }
    if(site==15) base=mix(paperGround(false),vec3(.55,.46,.49),.45);
    // Continue under props as well: clipping to walkable tiles exposes square
    // collision footprints around narrow trunks and rocks. Solids hide their
    // own centre; actual hazards and their banks still take precedence below.
    float deposit=indoor?0.:paperDepositPermission(near4,f,aa);
    if(deposit>0.) base=mix(base,paperAccumulation(p,base,aa,crowd),deposit);
    base=paperDetails(p,base,aa,indoor,detailWeight);
    if((cyber || floorBiome==1) && (tile.r&128)!=0) base=cyberWorkshopGround(p,base,aa);
    if(cyber) base=cyberGroundContact(p,uv,(tile.b>>4)&15,base,aa);
    base=paperStock(p,base,aa);
    float roughness=.9;
    float reflectionMask=.025;
    vec3 emission=vec3(0.);
    // A soft contact under the object, never the rectangular footprint of
    // its collision cell. The same ground pigment continues underneath it.
    float contact=1.-(kind==2?(1.-smoothstep(.13,.48,length(q*vec2(1.,1.25))))*.10:0.);
    base=mix(base,cyber?vec3(.88,.27,.24):biomeTint*.65,borderMask(tile.a&15,uv,.026,aa)*.85);
    {
        // Terrain patches are cut paper laid on the ground: their outline is the half level of their membership
        // interpolated between the four cell centres round the point, with a gentle wobble. A staircase of cells
        // becomes one slanted cut, every cell's centre keeps exactly its own terrain, and only corners are shared.
        int own=tile.g&15;
        int terrain=(own>=2 && own<=8)?0:own;
        float coverage=1.,cut=0.;
        {
            int t[4]=int[4](near4[0].g&15,near4[1].g&15,near4[2].g&15,near4[3].g&15);
            float best=0.;
            int bestTerrain=0;
            bool uniformTerrain=t[0]==t[1] && t[0]==t[2] && t[0]==t[3];
            if(uniformTerrain) {
                if(t[0]>=2 && t[0]<=8) {best=1.;bestTerrain=t[0];}
            } else for(int i=0;i<4;i++) {
                int k=t[i];
                if(k<2 || k>8) continue;
                float v=mix(mix(float(t[0]==k),float(t[1]==k),f.x),mix(float(t[2]==k),float(t[3]==k),f.x),f.y);
                if(v>best || (v==best && k==own)) {best=v;bestTerrain=k;}
            }
            if(bestTerrain!=0) {
                float wobble=0.;
                if(best>0. && best<1.) wobble=(valueNoise(p*2.1+vec2(4.7,1.3))-.5)*.26;
                float field=best+wobble*smoothstep(0.,.25,best)*(1.-smoothstep(.75,1.,best));
                float edge=smoothstep(.5-.03-aa,.5+.03+aa,field);
                if(edge>.001) {terrain=bestTerrain;coverage=edge;cut=1.-smoothstep(.0,.045+aa,abs(field-.5));}
            }
        }
        // Cached boundaries replace four neighbouring texture fetches.
        int patchEdges=tile.g>>4;
        if(terrain>=2 && terrain<=8) base=mix(base,base*vec3(.80,.78,.84),cut*.55);
        if(terrain==1) {
            // A small drawn bolt identifies the real electric cell. No blue
            // square, plate or bezel under it; its pulse follows the beat.
            float bolt=max(drawnSegment(q,vec2(.045,-.16),vec2(-.065,.015),.018,aa),
                drawnSegment(q,vec2(-.065,.015),vec2(.065,-.015),.018,aa));
            bolt=max(bolt,drawnSegment(q,vec2(.065,-.015),vec2(-.045,.16),.018,aa));
            float energized=worldBeat==0?1.:.18;
            base=mix(base,mix(vec3(.67,.43,.22),vec3(1.,.64,.13),energized),bolt*.8);
            emission+=expedition_linear(vec3(1.,.55,.10))*bolt*energized*.13;
        } else if(terrain==2) {
            base=mix(base,vec3(.68,.44,.27),coverage*.38);
            roughness=max(roughness,.65);
        } else if(terrain==3) {
            base=mix(base,vec3(.49,.68,.30),coverage*.22);
            base=paperDetails(p+vec2(.83,1.41),base,aa,false,detailWeight);
            roughness=max(roughness,.55);
        } else if(terrain==4 || terrain==8) {
            vec3 wet=terrain==4?vec3(.31,.65,.67):vec3(.49,.60,.29);
            vec3 glint=terrain==4?vec3(.71,.90,.81):vec3(.85,.80,.41);
            float ripple=inkLine(sin(p.x*2.2+p.y*3.+worldClock*.7),.04,aa*3.);
            // Bank highlights follow only the patch's cut, so adjacent wet
            // cells still read as one continuous slow region.
            float bank=cut;
            base=mix(base,wet,coverage*(.72+.06*ripple));
            roughness=mix(roughness,.12,coverage);
            emission+=expedition_linear(glint)*(bank*.16+ripple*coverage*.10);
        } else if(terrain==5) {
            float vein=inkLine(sin(p.x*2.+sin(p.y*1.7)*1.4),.025,aa*3.);
            base=mix(base,vec3(.54,.78,.85),coverage*(.42+.12*vein));
            emission+=expedition_linear(vec3(.25,.56,.72))*vein*coverage*.13;
            roughness=mix(roughness,.1,coverage);
        } else if(terrain==6) {
            base=mix(base,vec3(.61,.54,.53),coverage*.26);
            base=paperDetails(p+vec2(1.71,.74),base,aa,true,detailWeight);
            roughness=max(roughness,.68);
        } else if(terrain==7) {
            float flow=.5+.5*sin(p.x*3.7+sin(p.y*3.1+worldClock*.35)+worldClock*.9);
            float crack=inkLine(q.x+.07*sin(q.y*21.+float(cell.y)),.025,aa);
            float magma=kind==3?crack:(.14+.38*flow)*coverage;
            base=mix(base,vec3(.15,.035,.018),coverage*.55);
            emission+=expedition_linear(mix(vec3(1.,.16,.025),vec3(1.,.51,.08),flow))*magma*1.7;
            roughness=mix(roughness,.3,coverage);
        } else if(terrain==9) {
            float opened=worldBeat<2?1.:.08;
            // Two short drawn gusts show the phase of the actual wind cell.
            // They replace the old repeated square lattice.
            float gust=drawnSegment(q,vec2(-.18,.055),vec2(.11,.055),.012,aa);
            gust=max(gust,inkLine(length(q-vec2(.11,-.015))-.07,.012,aa)*step(.10,q.x));
            gust=max(gust,drawnSegment(q,vec2(-.10,-.09),vec2(.04,-.09),.010,aa));
            base=mix(base,vec3(.69,.47,.24),gust*opened*.6);
            emission+=expedition_linear(biomeTint)*gust*opened*.20;
            roughness=.16;
        } else if(terrain==10) {
            float r=length(q),ring=inkLine(r-.34,.018,aa);
            float orbit=inkLine(r-(.15+.1*sin(worldClock*2.)),.012,aa);
            float spoke=.6+.4*sin(atan(q.y,q.x)*3.-worldClock*2.);
            emission+=expedition_linear(vec3(.48,.26,1.))*(ring+orbit*.5)*spoke*(floorBiome==10?.5:.85);
        }
    }
    if(kind!=2) {
        // Uniform branch: exploration spends no fragment work on up to
        // nine actor-distance/smoothstep evaluations for an invisible grid.
        if(gridAmount>0.) {
            float focus=0.;
            for(int i=0;i<gridFocusCount;i++) {
                float d=length(vec2(cell)+.5-gridFocus[i].xy);
                focus=max(focus,1.-smoothstep(gridFocus[i].z,gridFocus[i].w,d));
            }
            focus*=gridAmount;
            float edge=max(abs(q.x),abs(q.y));
            float inset=1.-smoothstep(.44,.45+aa,edge);
            float rim=inkLine(edge-.45,.008,aa);
            base=mix(base,vec3(.62,.83,.86),focus*inset*.22);
            base=mix(base,vec3(.15,.39,.48),rim*focus*.65);
            emission+=expedition_linear(biomeTint)*rim*focus*.22;
        }
        bool vertical=warningLane.y>.5;
        float coordinate=vertical?float(cell.x):float(cell.y);
        float along=vertical?float(cell.y)-warningLane.w:float(cell.x)-warningLane.z;
        if(laneWarning!=0 && abs(coordinate-warningLane.x)<.1 && abs(along)<=12.) {
            float pulse=.7+.3*sin(worldClock*10.);
            float hatch=inkLine(fract((p.x+p.y)*2.)-.5,.07,aa*2.);
            base=mix(base,vec3(.24,.055,.018),.32);
            emission+=expedition_linear(vec3(1.,.25,.035))*(.16+hatch*.4)*pulse;
        }
    }
    // Height adds only a small value change to the light stock, capped at six steps so the print does not wash out.
    // Under the board's plane, in a pit dug under a raised
    // map's base (a stair's, a crevasse), the darker the deeper.
    base*=1.+clamp(worldPosition.y,0.,.72)*.10;
    base*=1.-smoothstep(0.,1.7,-worldPosition.y)*.45;
    // The sculpted ground's own normal, smoothed across ramps and hills: a slope turned to the light is lighter.
    vec3 n=normalize(normal);
    vec3 lit=expedition_lit_with_crowd(worldPosition,n,base,roughness,.3,crowd)*contact;
    lit+=expedition_reflection(worldPosition,n,roughness)*reflectionMask*contact;
    // The top edge of a cliff glows faintly in the biome's colour: the relief's vertices carry in their alpha how
    // near such an edge a point is (0 on it, 1 away from it; the plane is always 1).
    float cliff=1.-smoothstep(0.,.08,color.a);
    if(cyber) {
        if(cliff>0.) lit=mix(lit,expedition_lit_with_crowd(worldPosition,n,vec3(.77,.60,.42),.9,.02,crowd),cliff*.58);
    } else emission+=expedition_linear(biomeTint)*cliff*.45;
    finalColor=vec4(lit+emission,1.);
}
`
EXPEDITION_FLOOR_FRAGMENT :: EXPEDITION_FLOOR_HEADER+EXPEDITION_LIGHT_GLSL+EXPEDITION_REFLECTION_GLSL+EXPEDITION_FLOOR_BODY
// The same, with the thinning of tall terraces: the define goes in after the version line.
EXPEDITION_FLOOR_TALL_FRAGMENT :: `#version 330
#define TERRACE_REVEAL
`+EXPEDITION_FLOOR_HEADER_BODY+EXPEDITION_LIGHT_GLSL+EXPEDITION_REFLECTION_GLSL+EXPEDITION_FLOOR_BODY

@(private = "file")
load_expedition_floor_program :: proc(p:^Expedition_Floor_Program,source:cstring)->bool {
	p.shader=rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX,source)
	if !rl.IsShaderValid(p.shader) {
		if p.shader.id!=0 {rl.UnloadShader(p.shader)}
		p.shader={}
		return false
	}
	shader:=p.shader
	p.map_data=rl.GetShaderLocation(shader,"floorMap");p.map_size=rl.GetShaderLocation(shader,"mapSize")
	p.tint=rl.GetShaderLocation(shader,"biomeTint");p.time=rl.GetShaderLocation(shader,"worldClock")
	p.biome=rl.GetShaderLocation(shader,"floorBiome");p.beat=rl.GetShaderLocation(shader,"worldBeat");p.lane=rl.GetShaderLocation(shader,"warningLane")
	p.lane_warning=rl.GetShaderLocation(shader,"laneWarning")
	p.focus=rl.GetShaderLocation(shader,"gridFocus[0]");p.focus_count=rl.GetShaderLocation(shader,"gridFocusCount")
	p.grid_amount=rl.GetShaderLocation(shader,"gridAmount");p.surface=rl.GetShaderLocation(shader,"floorSurface")
	p.cyber_workshops=rl.GetShaderLocation(shader,"cyberWorkshops[0]")
	p.cyber_workshop_count=rl.GetShaderLocation(shader,"cyberWorkshopCount")
	p.workshop_stock=rl.GetShaderLocation(shader,"workshopStock")
	p.reveal_eye=rl.GetShaderLocation(shader,"eye");p.reveal_forward=rl.GetShaderLocation(shader,"viewForward")
	p.reveal_viewport=rl.GetShaderLocation(shader,"viewport")
	p.reveal_points=rl.GetShaderLocation(shader,"reveal[0]");p.reveal_count=rl.GetShaderLocation(shader,"revealCount")
	p.reveal_floor=rl.GetShaderLocation(shader,"revealFloor")
	p.layer=rl.GetShaderLocation(shader,"floorLayer");p.cover=rl.GetShaderLocation(shader,"coverPoint")
	p.lights=expedition_light_uniforms(shader);p.reflection=expedition_reflection_uniforms(shader)
	// A block drawn from the video card binds the floor's map as its material's second map (draw_terrain_chunk).
	p.shader.locs[rl.ShaderLocationIndex.MAP_METALNESS]=p.map_data
	// Batch texture units are floorMap=1, stock=2, reflectionSharp=3.
	// Mesh maps must preserve those slots; ROUGHNESS=3 would replace a reflection.
	p.shader.locs[rl.ShaderLocationIndex.MAP_NORMAL]=p.workshop_stock
	return true
}

@(private)
expedition_floor_ready :: proc(renderer:^Renderer)->bool {
	if renderer.tactical.expedition_floor!=nil {return !renderer.tactical.expedition_floor.failed}
	if !rl.IsWindowReady() {return false}
	f:=new(Expedition_Floor)
	if !load_expedition_floor_program(&f.plain,EXPEDITION_FLOOR_FRAGMENT) {
		f.failed=true;renderer.tactical.expedition_floor=f
		return false
	}
	// Without the tall program the floor still draws, only without the thinning.
	if !load_expedition_floor_program(&f.tall,EXPEDITION_FLOOR_TALL_FRAGMENT) {f.tall=f.plain}
	renderer.tactical.expedition_floor=f
	return true
}

destroy_expedition_floor :: proc(renderer:^Renderer) {
	if renderer==nil || renderer.tactical.expedition_floor==nil {return}
	f:=renderer.tactical.expedition_floor
	if f.texture.id!=0 {rl.UnloadTexture(f.texture)}
	for stock in f.workshop_stock {if stock.id!=0 {rl.UnloadTexture(stock)}}
	if f.plain.shader.id!=0 {rl.UnloadShader(f.plain.shader)}
	if f.tall.shader.id!=0 && f.tall.shader.id!=f.plain.shader.id {rl.UnloadShader(f.tall.shader)}
	destroy_expedition_terrain(&f.terrain)
	destroy_expedition_under(&f.under)
	destroy_expedition_under(&f.decks)
	destroy_expedition_floor_data(&f.data);free(f);renderer.tactical.expedition_floor=nil
}

// Return false only when the legacy floor fallback is needed.
draw_expedition_floor :: proc(renderer:^Renderer,room:^game.Room,w:^world.World)->bool {
	if renderer==nil || room==nil || room.level_data==nil || w==nil || !expedition_floor_ready(renderer) {return false}
	f:=renderer.tactical.expedition_floor
	changed:=refresh_expedition_floor_data(&f.data,room,w)
	if !f.data.ready {return false}
	if f.texture.id==0 || int(f.texture.width)!=f.data.width || int(f.texture.height)!=f.data.height {
		if f.texture.id!=0 {rl.UnloadTexture(f.texture)}
		image:=rl.Image{data=raw_data(f.data.pixels),width=c.int(f.data.width),height=c.int(f.data.height),mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
		f.texture=rl.LoadTextureFromImage(image)
		rl.SetTextureFilter(f.texture,.POINT);rl.SetTextureWrap(f.texture,.CLAMP)
	} else if changed {rl.UpdateTexture(f.texture,raw_data(f.data.pixels))}
	if f.texture.id==0 {return false}
	// The program that thins out a tall mountain is used only where one is in view, or round the robot in a cave, or where
	// a deck is in view (its fade over the robot is that program's).
	p:=&f.tall if board_view.vault || expedition_terrain_tall_in_view(renderer,room) || expedition_decks_in_view(renderer,room,w) else &f.plain
	shader:=p.shader
	dimensions:=rl.Vector2{f32(f.data.width),f32(f.data.height)}
	metadata:=world.METADATA;c3:=metadata[w.biome].color;tint:=[3]f32{f32(c3[0])/255,f32(c3[1])/255,f32(c3[2])/255}
	biome:=c.int(w.biome);beat:=c.int(w.beat%4);warning:=c.int(1) if w.lane_warning else 0
	lane:=rl.Vector4{f32(w.lane),1 if w.lane_vertical else 0,f32(w.lane_center.x),f32(w.lane_center.y)}
	finish:=expedition_biome_surface(w.biome);surface:=rl.Vector2{finish.roughness,finish.reflection}
	rl.SetShaderValue(shader,p.map_size,&dimensions,.VEC2);rl.SetShaderValue(shader,p.tint,&tint,.VEC3)
	rl.SetShaderValue(shader,p.time,&w.clock,.FLOAT);rl.SetShaderValue(shader,p.beat,&beat,.INT)
	rl.SetShaderValue(shader,p.biome,&biome,.INT)
	rl.SetShaderValue(shader,p.lane,&lane,.VEC4);rl.SetShaderValue(shader,p.lane_warning,&warning,.INT)
	rl.SetShaderValue(shader,p.surface,&surface,.VEC2)
	f.active_stock=ensure_workshop_stock(f,w.biome)
	workshops,workshop_count:=cyber_floor_workshops(w)
	if f.active_stock.id==0 {workshop_count=0}
	workshop_uniform_count:=c.int(workshop_count)
	rl.SetShaderValue(shader,p.cyber_workshop_count,&workshop_uniform_count,.INT)
	if workshop_count>0 {rl.SetShaderValueV(shader,p.cyber_workshops,&workshops[0],.VEC4,workshop_uniform_count)}
	count:c.int;amount:f32
	if m:=renderer.tactical.expedition_material;m!=nil {
		count=c.int(m.focus_point_count);amount=m.grid_amount
		if count>0 {rl.SetShaderValueV(shader,p.focus,&m.focus_points[0],.VEC4,count)}
	}
	rl.SetShaderValue(shader,p.focus_count,&count,.INT);rl.SetShaderValue(shader,p.grid_amount,&amount,.FLOAT)
	// Only the robot's window, and only where the robot has one.
	set_expedition_reveal(renderer,shader,p.reveal_eye,p.reveal_forward,p.reveal_viewport,p.reveal_points,p.reveal_count,1 if (renderer.tactical.expedition_material!=nil && renderer.tactical.expedition_material.player_reveal) else 0)
	// The top of the robot's own cell: a slope it stands on is never cut.
	floor_steps:=cell_overlay_ground(room.player.position);rl.SetShaderValue(shader,p.reveal_floor,&floor_steps,.FLOAT)
	// In a cave the ground over the robot's eyes fades round him (Fase 4's rule).
	cover:=rl.Vector4{}
	if board_view.vault {
		viewer:=board_view.viewer
		cover={viewer.point.x,cell_ground(viewer.cell)+f32(game.HEIGHT_EYE_STEPS)*game.HEIGHT_STEP_DRAWN,viewer.point.y,1}
	}
	rl.SetShaderValue(shader,p.cover,&cover,.VEC4)
	ground_pass,under_pass,deck_pass:=c.int(0),c.int(1),c.int(2)
	open_sky,under_rock:=f32(0),f32(.65)
	rl.SetShaderValue(shader,p.layer,&ground_pass,.INT)
	rl.SetShaderValue(shader,p.lights.sky_shade,&open_sky,.FLOAT)
	set_expedition_lights(renderer,shader,p.lights)
	rl.BeginShaderMode(shader)
	f.bound=p
	defer f.bound=nil
	rl.SetShaderValueTexture(shader,p.map_data,f.texture)
	if f.active_stock.id!=0 {rl.SetShaderValueTexture(shader,p.workshop_stock,f.active_stock)}
	set_expedition_reflection(renderer,shader,p.reflection)
	draw_expedition_floor_plane(renderer,room,dimensions)
	draw_expedition_terrain(renderer,room)
	// The caves' rooms under the ground, the same program in their own pass.
	if level.has_layers(room.level_data) {
		rlgl.DrawRenderBatchActive()
		rl.SetShaderValue(shader,p.layer,&under_pass,.INT)
		rl.SetShaderValue(shader,p.lights.sky_shade,&under_rock,.FLOAT)
		draw_expedition_under(renderer,room)
		rlgl.DrawRenderBatchActive()
		rl.SetShaderValue(shader,p.layer,&ground_pass,.INT)
		rl.SetShaderValue(shader,p.lights.sky_shade,&open_sky,.FLOAT)
	}
	// The complexes' decks over it, the same program in their own pass: one over the robot's eyes fades round him.
	if expedition_has_decks(room.level_data) {
		rlgl.DrawRenderBatchActive()
		viewer:=board_view.viewer
		over:=rl.Vector4{viewer.point.x,cell_ground(viewer.cell)+f32(game.HEIGHT_EYE_STEPS)*game.HEIGHT_STEP_DRAWN,viewer.point.y,1}
		rl.SetShaderValue(shader,p.cover,&over,.VEC4)
		rl.SetShaderValue(shader,p.layer,&deck_pass,.INT)
		draw_expedition_decks(renderer,room,w)
		rlgl.DrawRenderBatchActive()
		rl.SetShaderValue(shader,p.layer,&ground_pass,.INT)
		rl.SetShaderValue(shader,p.cover,&cover,.VEC4)
	}
	rl.EndShaderMode()
	return true
}
