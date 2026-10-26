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
	reveal_eye, reveal_forward, reveal_viewport, reveal_points, reveal_count, reveal_floor: c.int,
	// The pass (0 the ground, 1 the rooms under it: expedition_layers.odin) and the fade over the robot in a cave.
	layer, cover: c.int,
	lights: Expedition_Light_Uniforms,
	reflection: Expedition_Reflection_Uniforms,
}

Expedition_Floor :: struct {
	data: Expedition_Floor_Data,
	texture: rl.Texture2D,
	plain, tall: Expedition_Floor_Program,
	failed: bool,
	// The terraces of the map's relief, over the plane (expedition_terrain.odin).
	terrain: Expedition_Terrain_Cache,
	// The caves' rooms under the ground (expedition_layers.odin).
	under: Expedition_Under_Cache,
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
// 0: the ground and its relief; 1: the rooms under it (expedition_layers.odin).
uniform int floorLayer;
#ifdef TERRACE_REVEAL
uniform vec3 eye;
uniform vec3 viewForward;
uniform vec2 viewport;
uniform vec4 reveal[9];
uniform int revealCount;
// The height of the ground the robot stands on: only what is above it can be in its way.
uniform float revealFloor;
// In a cave: the robot's point (x, z), the height of his eyes (y), and whether the ground over him fades (w).
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
float hash21(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
// Analytic staggered joints in world units: no noise or adjacent texel reads.
// Their derivative width is computed before any per-cell material branch.
float floorJoint(vec2 p,vec2 size,float stagger,float width,float aa) {
    float row=floor(p.y/size.y);
    vec2 uv=fract((p+vec2(mod(row,2.)*stagger,0.))/size);
    vec2 edge=min(uv,1.-uv)*size;
    return inkLine(min(edge.x,edge.y),width,aa);
}
void floorMain();
void caveMain();
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
    // In a cave the ground over the robot's eyes opens round him (Fase 4's rule, game/layer_view.odin): within six
    // cells, down to fifteen percent beside him, as a stipple; what is left of it is darker.
    if(floorLayer==0 && coverPoint.w>0. && worldPosition.y>coverPoint.y) {
        float far=max(length(worldPosition.xz-coverPoint.xz)-.5,0.);
        if(far<6.) {
            float k=clamp((6.-far)/5.,0.,1.);
            cover=1.-.85*k*k*(3.-2.*k);
            ivec2 f=ivec2(gl_FragCoord.xy)&3;
            if(cover<=(BAYER[f.y*4+f.x]+.5)/16.) discard;
        }
    }
#endif
    if(floorLayer==1) caveMain(); else floorMain();
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
        vec3 rock=mix(vec3(.115,.118,.132),biomeTint*.20,.30);
        if(color.r<.5) rock*=.66;
        finalColor=vec4(expedition_lit(worldPosition,n,rock,.9,.05),1.);
        return;
    }
    vec2 p=worldPosition.xz;
    vec2 footprint=max(fwidth(p),vec2(.0001));
    float aa=max(footprint.x,footprint.y);
    ivec2 cell=ivec2(floor(p));
    vec2 uv=fract(p),q=uv-.5;
    float joint=floorJoint(p,vec2(1.3,.9),.65,.012,aa);
    float slab=hash21(vec2(cell)*.37+vec2(floor(p.y/.9)));
    vec3 base=mix(vec3(.150,.145,.158),vec3(.198,.190,.205),slab);
    base=mix(base,biomeTint*.24,.22);
    base*=(1.-joint*.30)*mix(.55,1.,color.g);
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
        base=mix(base,base*1.28+biomeTint*.012,focus*inset);
        emission+=expedition_linear(biomeTint)*line*focus*.22;
    }
    finalColor=vec4(expedition_lit(worldPosition,n,base,.72,.05)+emission,1.);
}
void floorMain() {
    // The walls of a cliff are dark rock, tinted a little by the biome, lit facet by facet.
    if(normal.y<.5) {
        vec3 rock=mix(vec3(.05,.055,.07),biomeTint*.12,.5);
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
    vec3 base=vec3(9.,11.,18.)/255.;
    if(site==3) base=vec3(14.,17.,27.)/255.;
    else if(site==1 || site==9 || site==7) base=vec3(10.,12.,20.)/255.;
    else if(site==4) base=vec3(10.,12.,19.)/255.;
    else if(site==5 || site==8) base=vec3(9.,14.,18.)/255.;
    float roughness=floorSurface.x;
    vec3 emission=vec3(0.);
    float contact=1.,reflectionMask=1.;
    bool cyber=floorBiome==0;
    // Fine continuous four-cell threads are subdued at oblique/minified views.
    vec2 thread=abs(fract(p*.25-.5)-.5)*4.;
    float threads=inkLine(min(thread.x,thread.y),.009,aa);
    if(cyber) {
        // Broad charcoal panels use cached variation instead of fragment
        // noise. A very slight diagonal facet breaks the perfectly flat ink.
        float slab=float(tile.b>>4)/15.;
        vec2 panelUV=fract(p*.25);
        float facet=smoothstep(-.025,.025,panelUV.x-panelUV.y);
        vec3 charcoal=mix(vec3(.078,.087,.106),vec3(.108,.117,.136),slab);
        float authored=site==3?1.09:1.;
        base=charcoal*mix(.96,1.035,facet)*authored;
        float fineJoint=inkLine(min(min(uv.x,1.-uv.x),min(uv.y,1.-uv.y)),.008,aa);
        base*=1.-fineJoint*.09-threads*.18;
        // Contact darkening is localized at real wall/fixture footprints.
        contact=1.-borderMask((tile.r>>3)&15,uv,.025,.7)*.32;
        float wear=smoothstep(.12,.85,panelUV.x*.65+panelUV.y*.35);
        roughness=clamp(floorSurface.x+.09+slab*.17+wear*.07,.22,.66);
        reflectionMask=(.66+.26*(1.-slab))*(1.-wear*.12)*(1.-threads*.62);
        emission+=expedition_linear(biomeTint)*threads*.018;
    } else {
        // The low-frequency variation is already packed in each four-cell
        // slab. Broad, continuous folds add shape without fragment noise.
        float slab=float(tile.b>>4)/15.;
        vec2 panelUV=fract(p*.25);
        float facet=smoothstep(-aa*.25,aa*.25,panelUV.x-panelUV.y);
        float drift=abs(fract(p.x*.071+p.y*.043)-.5)*2.;
        float wallFoot=borderMask((tile.r>>3)&15,uv,.025,.7);
        bool paved=site==2 || site==3 || site==4 || site==6 || site==7 || site==9;
        contact=1.-wallFoot*.30;
        emission+=expedition_linear(biomeTint)*threads*.008;
        if(floorBiome==1) {
            // West: warm, matte sand outside; long wooden boardwalks in
            // authored courts. The arena remains an open dusty corral.
            float dune=smoothstep(.15,.9,drift);
            base=mix(vec3(.145,.112,.078),vec3(.195,.155,.106),dune);
            base*=.96+slab*.06;
            roughness=.86;reflectionMask=.10;
            if(paved && site!=6) {
                float joint=floorJoint(p,vec2(.5,3.),1.5,.009,aa);
                float grain=abs(fract(p.x*2.+p.y*.035)-.5)*2.;
                base=mix(vec3(.125,.087,.058),vec3(.18,.128,.081),slab*.5+grain*.35);
                base*=1.-joint*.26;
                roughness=.72+slab*.09;reflectionMask=.24*(1.-joint*.7);
            }
        } else if(floorBiome==2) {
            // Jungle soil stays earthy; only the ruins and courts become
            // weathered stone. Actual tall-grass patches are overlaid below.
            base=mix(vec3(.075,.091,.059),vec3(.115,.119,.076),drift);
            roughness=.79;reflectionMask=.19;
            if(paved) {
                float joint=floorJoint(p,vec2(1.4,1.),.7,.013,aa);
                base=mix(vec3(.115,.131,.111),vec3(.15,.16,.13),slab);
                base*=1.-joint*.23;
                roughness=.64;reflectionMask=.32*(1.-joint*.65);
            }
            base=mix(base,vec3(.066,.091,.052),wallFoot*.14);
        } else if(floorBiome==3) {
            // City: asphalt with soft interrupted wet reflections, bordered
            // by quiet concrete sidewalks and inset courtyard panels.
            float damp=smoothstep(.32,.85,drift);
            base=mix(vec3(.065,.070,.087),vec3(.086,.091,.111),facet*.28+slab*.36);
            roughness=mix(.48,.22,damp);
            reflectionMask=.36+.40*damp;
            if(paved || site==1) {
                float joint=floorJoint(p,vec2(1.,2.),1.,.010,aa);
                base=mix(vec3(.139,.148,.162),vec3(.172,.179,.192),slab);
                base*=1.-joint*.23;
                roughness=.47+slab*.12;
                reflectionMask=(.36+damp*.15)*(1.-joint*.7);
            }
        } else if(floorBiome==4) {
            // Egypt: sandstone blocks and fine turquoise seams within the
            // temple courts, surrounded by muted wind-shaped sand.
            base=mix(vec3(.163,.132,.087),vec3(.204,.171,.116),drift);
            roughness=.84;reflectionMask=.13;
            if(paved) {
                float joint=floorJoint(p,vec2(1.6,.9),.8,.011,aa);
                base=mix(vec3(.205,.179,.131),vec3(.259,.226,.164),slab);
                base*=1.-joint*.24;
                roughness=.64+slab*.10;reflectionMask=.27*(1.-joint*.65);
                if(site==3 || site==7) {
                    base=mix(base,vec3(.10,.22,.21),threads*.19);
                    emission+=expedition_linear(vec3(.12,.48,.43))*threads*.012;
                }
            }
        } else if(floorBiome==5) {
            // Vietnam: compacted mud with damp depressions; pale, worn
            // stepping stones identify bunkers and village courtyards.
            float damp=smoothstep(.40,.82,drift);
            base=mix(vec3(.083,.086,.060),vec3(.114,.117,.081),slab*.22+drift*.48);
            roughness=mix(.78,.46,damp);reflectionMask=.15+damp*.29;
            if(paved) {
                float joint=floorJoint(p,vec2(1.2,.8),.6,.014,aa);
                base=mix(vec3(.125,.135,.112),vec3(.159,.165,.135),slab);
                base*=1.-joint*.25;
                roughness=.65;reflectionMask=.29*(1.-joint*.65);
            }
        } else if(floorBiome==6) {
            // Snow: dark blue stone under restrained windblown frost.
            // Slow snow and slippery ice retain their distinct live overlays.
            float frost=smoothstep(.55,.88,drift);
            base=mix(vec3(.119,.155,.184),vec3(.266,.302,.328),frost*.55);
            base*=.97+slab*.05;
            roughness=.78;reflectionMask=.48;
            if(paved) {
                float joint=floorJoint(p,vec2(1.5,1.),.75,.012,aa);
                base=mix(vec3(.170,.211,.240),vec3(.215,.253,.276),slab);
                base*=1.-joint*.19;
                roughness=.63;reflectionMask=.50*(1.-joint*.55);
            }
        } else if(floorBiome==7) {
            // Basalt is cool, dark and angular. Orange cracks appear only
            // through actual lava terrain or the eruption warning below.
            float joint=floorJoint(p,vec2(1.5,1.3),.75,.013,aa);
            base=mix(vec3(.065,.058,.065),vec3(.095,.081,.087),slab);
            base*=mix(.94,1.045,facet)*(1.-joint*.21);
            roughness=.48+slab*.18;
            reflectionMask=(.37-facet*.06)*(1.-joint*.7);
            if(site==3) {base*=1.10;roughness-=.08;reflectionMask+=.10;}
        } else if(floorBiome==8) {
            // Gothic: rain-dark stone with moss around real structures;
            // the swamp remains a separately readable gameplay material.
            float joint=floorJoint(p,vec2(.9,1.4),.45,.013,aa);
            float damp=smoothstep(.20,.80,drift);
            base=mix(vec3(.088,.101,.098),vec3(.125,.139,.133),slab);
            base*=1.-joint*.22;
            base=mix(base,vec3(.068,.086,.051),wallFoot*.23);
            roughness=.60-damp*.22;
            reflectionMask=(.40+damp*.26)*(1.-joint*.7);
        } else if(floorBiome==9) {
            // Sky marble: broad pearl slabs and sparse angular veins. Gold
            // belongs to the inset platform fillets, never a luminous wash.
            float joint=floorJoint(p,vec2(2.,2.),0.,.009,aa);
            float fold=abs(fract(p.y*.11)-.5)*.22;
            float vein=inkLine(fract(p.x*.16+p.y*.09+fold)-.5,.004,aa*.3);
            base=mix(vec3(.207,.221,.241),vec3(.250,.260,.273),slab);
            base=mix(base,vec3(.123,.144,.173),vein*.14);
            base*=1.-joint*.16;
            roughness=.32+slab*.14;
            reflectionMask=(.52-vein*.12)*(1.-joint*.6);
            if(site==3 || site==9) {base=mix(base,vec3(.29,.235,.142),threads*.30);}
        } else if(floorBiome==10) {
            // Space: dry, faceted asteroid dust surrounds brushed orbital
            // decking. Fine panel joints interrupt the metallic reflections.
            base=mix(vec3(.084,.094,.121),vec3(.119,.128,.151),facet*.35+slab*.4);
            roughness=.84;reflectionMask=.16;
            if(paved || site==1) {
                float joint=floorJoint(p,vec2(2.,1.),1.,.010,aa);
                base=mix(vec3(.105,.123,.157),vec3(.145,.160,.186),slab);
                base*=1.-joint*.25;
                roughness=.35+slab*.17;
                reflectionMask=(.62-facet*.11)*(1.-joint*.7);
            }
        } else if(floorBiome==11) {
            // Secret: quiet obsidian mirrors with gold inlay at authored
            // platforms. The creator's archive keeps the visual emphasis.
            float joint=floorJoint(p,vec2(4.,4.),0.,.010,aa);
            base=mix(vec3(.054,.051,.068),vec3(.085,.078,.101),slab);
            base*=mix(.94,1.045,facet)*(1.-joint*.17);
            roughness=.19+slab*.15;
            reflectionMask=(.73-facet*.12)*(1.-joint*.65);
            if(paved) {
                base=mix(base,vec3(.33,.258,.125),threads*.44);
                emission+=expedition_linear(vec3(.65,.46,.18))*threads*.010;
            }
        }
    }
    if(site==15) {
        // A cave's massif (expedition_floor_data.odin): bare rock, faintly of the biome, split by long cracks.
        float slab=float(tile.b>>4)/15.;
        // Few thin cracks, broken where a slow wave runs under them: no net of lines from afar.
        float crack=inkLine(fract(p.x*.13+p.y*.07+sin(p.y*.29+p.x*.11)*.45)-.5,.005,aa)*step(.35,fract(p.y*.09+p.x*.05));
        float seam=inkLine(fract(p.y*.11-p.x*.05+sin(p.x*.23)*.4)-.5,.004,aa)*step(.5,fract(p.x*.07-p.y*.03));
        float grain=mix(.5,hash21(floor(p*3.)),clamp(1.-aa*4.,0.,1.));
        base=mix(vec3(.112,.110,.118),vec3(.128,.125,.134),slab*.6+grain*.4);
        base=mix(base,biomeTint*.30,.20);
        base*=1.-max(crack,seam)*.24;
        roughness=.88;reflectionMask=.06;contact=1.;
    }
    emission+=expedition_linear(biomeTint)*borderMask(tile.a&15,uv,.026,aa)*1.25;
    emission+=expedition_linear(biomeTint)*borderMask(tile.a>>4,uv,.018,aa)*.44;
    if(kind!=2) {
        int terrain=tile.g&15;
        // Cached boundaries replace four neighbouring texture fetches.
        int patchEdges=tile.g>>4;
        float coverage=1.-borderMask(patchEdges,uv,.015,.16+aa);
        if(terrain==1) {
            // The same electric cell now reads as a cyan panel inset into a
            // dark metal bezel. Its bright pulse still matches the live beat.
            float square=max(abs(q.x),abs(q.y));
            float bezel=1.-smoothstep(.29,.29+aa,square);
            float panel=1.-smoothstep(.22,.22+aa,square);
            float rim=inkLine(square-.26,.009,aa);
            float energized=worldBeat==0?1.:.18;
            base=mix(base,vec3(.018,.028,.043),bezel);
            base=mix(base,vec3(.025,.10,.15),panel);
            emission+=expedition_linear(vec3(.12,.62,1.))*(panel*(.17+energized*.66)+rim*.045);
            roughness=mix(roughness,.18,bezel);
            reflectionMask*=1.-panel*.82;
        } else if(terrain==2) {
            float ripple=.5+.5*sin(p.x*3.+sin(p.y*1.3)*.7);
            base=mix(base,vec3(.14,.105,.055),coverage*(.25+.13*ripple));
            roughness=max(roughness,.65);
        } else if(terrain==3) {
            float blade=inkLine(fract(p.x*2.8+p.y*.65)-.5,.026,aa*2.8);
            base=mix(base,vec3(.05,.12,.035),coverage*(.3+blade*.2));
            roughness=max(roughness,.55);
        } else if(terrain==4 || terrain==8) {
            vec3 wet=terrain==4?vec3(.045,.18,.22):vec3(.11,.17,.075);
            vec3 glint=terrain==4?vec3(.18,.40,.44):vec3(.25,.34,.16);
            float ripple=inkLine(sin(p.x*2.2+p.y*3.+worldClock*.7),.04,aa*3.);
            // Bank highlights follow only the outer terrain boundary, so
            // adjacent wet cells still read as one continuous slow region.
            float bank=borderMask(patchEdges,uv,.035,aa);
            base=mix(base,wet,coverage*(.72+.06*ripple));
            roughness=mix(roughness,.12,coverage);
            emission+=expedition_linear(glint)*(bank*.16+ripple*coverage*.10);
        } else if(terrain==5) {
            float vein=inkLine(sin(p.x*2.+sin(p.y*1.7)*1.4),.025,aa*3.);
            base=mix(base,vec3(.12,.22,.29),coverage*(.5+.12*vein));
            emission+=expedition_linear(vec3(.25,.56,.72))*vein*coverage*.13;
            roughness=mix(roughness,.1,coverage);
        } else if(terrain==6) {
            float grain=mix(.5,hash21(floor(p*5.)),clamp(1.-aa*5.,0.,1.));
            base=mix(base,vec3(.22,.27,.31),coverage*(.42+grain*.12));
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
            float rails=max(inkLine(abs(q.x)-.33,.018,aa),inkLine(abs(q.y)-.33,.018,aa));
            float crossbar=inkLine(q.x+q.y,.014,aa);
            base=mix(base,biomeTint*.14,opened*.3);
            emission+=expedition_linear(biomeTint)*(rails+crossbar*.35)*opened*(floorBiome==9?.42:.75);
            roughness=.16;
        } else if(terrain==10) {
            float r=length(q),ring=inkLine(r-.34,.018,aa);
            float orbit=inkLine(r-(.15+.1*sin(worldClock*2.)),.012,aa);
            float spoke=.6+.4*sin(atan(q.y,q.x)*3.-worldClock*2.);
            emission+=expedition_linear(vec3(.48,.26,1.))*(ring+orbit*.5)*spoke*(floorBiome==10?.5:.85);
        }
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
            base=mix(base,base*1.28+biomeTint*.012,focus*inset);
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
    // The higher the ground, the lighter: ten percent a step, so that hills and dunes read from above; no more
    // than six steps' worth, so that a mountain's top is not white.
    base*=1.+clamp(worldPosition.y,0.,.72)*.9;
    // The sculpted ground's own normal, smoothed across ramps and hills: a slope turned to the light is lighter.
    vec3 n=normalize(normal);
    vec3 lit=expedition_lit(worldPosition,n,base,roughness,.3)*contact;
    lit+=expedition_reflection(worldPosition,n,roughness)*reflectionMask*contact;
    // The top edge of a cliff glows faintly in the biome's colour: the relief's vertices carry in their alpha how
    // near such an edge a point is (0 on it, 1 away from it; the plane is always 1).
    float cliff=1.-smoothstep(0.,.08,color.a);
    emission+=expedition_linear(biomeTint)*cliff*.45;
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
	p.reveal_eye=rl.GetShaderLocation(shader,"eye");p.reveal_forward=rl.GetShaderLocation(shader,"viewForward")
	p.reveal_viewport=rl.GetShaderLocation(shader,"viewport")
	p.reveal_points=rl.GetShaderLocation(shader,"reveal[0]");p.reveal_count=rl.GetShaderLocation(shader,"revealCount")
	p.reveal_floor=rl.GetShaderLocation(shader,"revealFloor")
	p.layer=rl.GetShaderLocation(shader,"floorLayer");p.cover=rl.GetShaderLocation(shader,"coverPoint")
	p.lights=expedition_light_uniforms(shader);p.reflection=expedition_reflection_uniforms(shader)
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
	if f.plain.shader.id!=0 {rl.UnloadShader(f.plain.shader)}
	if f.tall.shader.id!=0 && f.tall.shader.id!=f.plain.shader.id {rl.UnloadShader(f.tall.shader)}
	destroy_expedition_terrain(&f.terrain)
	destroy_expedition_under(&f.under)
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
	// The program that thins out a tall mountain is used only where one is in view, or round the robot in a cave.
	p:=&f.tall if board_view.vault || expedition_terrain_tall_in_view(renderer,room) else &f.plain
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
	ground_pass,under_pass:=c.int(0),c.int(1)
	open_sky,under_rock:=f32(0),f32(.65)
	rl.SetShaderValue(shader,p.layer,&ground_pass,.INT)
	rl.SetShaderValue(shader,p.lights.sky_shade,&open_sky,.FLOAT)
	set_expedition_lights(renderer,shader,p.lights)
	rl.BeginShaderMode(shader)
	rl.SetShaderValueTexture(shader,p.map_data,f.texture)
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
	rl.EndShaderMode()
	return true
}
