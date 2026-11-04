package render

// Authored wall illustrations. These are vector drawings evaluated only on
// tagged architecture, never on foliage, equipment, caps or actor paper.
// A composition spans several cells; derivatives precede wrapping so it
// stays registered and antialiased while the camera moves.
@(private)
EXPEDITION_PRINT_GLSL :: `
float printBox(vec2 p,vec2 c,vec2 h,float aa) {
    vec2 d=abs(p-c)-h;
    return 1.-smoothstep(0.,aa,max(d.x,d.y));
}
float printHash(vec2 p) {return fract(sin(dot(p,vec2(91.7,47.3)))*28461.37);}
// The way each biome's walls are built, under the authored motifs: courses
// of panels, planks, blocks, bricks or stems at their real size, with dark
// joints, a lit upper bevel and a shaded lower one, a little value change
// from block to block. Joints fade before they could shimmer.
vec3 paperCourses(vec2 plane,vec2 printUV,vec3 base) {
    float aa=max(.0015,max(fwidth(plane.x),fwidth(plane.y)));
    float readable=1.-smoothstep(.02,.06,aa);
    if(readable<=0.) return base;
    vec2 size=vec2(.5);float shift=.5,joint=.012,bevel=.035;
    vec3 jointInk=base*vec3(.42,.46,.58);
    vec2 q=plane;
    if(paperBiome==1.) {size=vec2(.5,.46);shift=0.;joint=.014;bevel=.05;jointInk=vec3(.06,.10,.22);}
    else if(paperBiome==2.) {size=vec2(2.7,.21);shift=.37;joint=.010;bevel=.02;jointInk=base*vec3(.40,.30,.24);}
    else if(paperBiome==3.) {size=vec2(.74,.35);joint=.016;bevel=.045;}
    else if(paperBiome==4.) {size=vec2(.26,.115);joint=.009;bevel=.012;jointInk=base*vec3(.55,.50,.55);}
    else if(paperBiome==5.) {size=vec2(.92,.33);joint=.012;bevel=.04;jointInk=base*vec3(.62,.52,.42);}
    else if(paperBiome==6.) {q=plane.yx;size=vec2(.52,.15);shift=.31;joint=.011;bevel=.03;jointInk=base*vec3(.40,.42,.24);}
    else if(paperBiome==7.) {size=vec2(1.05,.44);joint=.010;bevel=.06;jointInk=base*vec3(.62,.74,.90);}
    else if(paperBiome==8.) {q=plane.yx;size=vec2(.58,.31);shift=.33;joint=.016;bevel=.04;jointInk=base*vec3(.30,.22,.22);}
    else if(paperBiome==9.) {size=vec2(.44,.19);joint=.011;bevel=.025;}
    else if(paperBiome==10.) {size=vec2(1.2,.62);shift=0.;joint=.008;bevel=.05;jointInk=base*vec3(.70,.70,.78);}
    else if(paperBiome==11.) {size=vec2(.62,.42);shift=0.;joint=.010;bevel=.035;jointInk=base*vec3(.38,.42,.52);}
    else if(paperBiome==12.) {size=vec2(.8,.5);shift=.25;joint=.012;bevel=.05;}
    float row=floor(q.y/size.y);
    float along=q.x/size.x+row*shift;
    vec2 id=vec2(floor(along),row);
    vec2 f=vec2(fract(along),fract(q.y/size.y));
    vec2 edge=min(f,1.-f)*size;
    float mortar=1.-smoothstep(joint,joint+aa,min(edge.x,edge.y));
    bool upright=paperBiome==6. || paperBiome==8.;
    // Light from above: the upper bevel (or the stem's left side) is lit, the lower one shaded.
    float lit=upright?f.y:f.y,shade=1.-lit;
    float top=1.-smoothstep(bevel,bevel+aa,(1.-(upright?f.x:f.y))*(upright?size.x:size.y));
    float low=1.-smoothstep(bevel,bevel+aa,(upright?f.x:f.y)*(upright?size.x:size.y));
    float h=printHash(id+vec2(paperBiome*7.,3.));
    vec3 block=base*(1.+(h-.5)*.10);
    block=mix(block,min(block*1.14+vec3(.02),1.),top*.55);
    block=mix(block,block*vec3(.80,.84,.92),low*.6);
    if(paperBiome==1.) {
        // A red light slot in one panel of seven, the mockup's signature.
        vec2 c=(f-.5)*size;
        float slot=1.-smoothstep(0.,aa,max(abs(c.x)-.13,abs(c.y)-.028));
        if(h>.86) block=mix(block,vec3(1.,.32,.27),slot);
    } else if(paperBiome==11.) {
        vec2 c=min(f,1.-f)*size;
        float rivet=1.-smoothstep(.022,.022+aa,length(c-vec2(.05)));
        block=mix(block,block*1.25,rivet*.8);
    }
    vec3 built=mix(block,jointInk,mortar*.85);
    // A darker footing course along the ground.
    float footing=1.-smoothstep(.085,.085+aa*4.,printUV.y);
    built=mix(built,built*vec3(.72,.76,.86),footing*.6);
    return mix(base,built,readable);
}
vec3 paperMotif(vec2 plane,vec3 base) {
    float aa=max(.001,max(fwidth(plane.x),fwidth(plane.y)));
    float readable=1.-smoothstep(.035,.10,aa);
    vec2 drawn=floor(plane*48.)/48.;
    vec2 q=vec2(mod(drawn.x,3.6),mod(drawn.y,2.8));
    float line=0.,paint=0.,shade=0.;
    vec3 ink=base*vec3(.48,.52,.65),pigment=min(base*1.22+vec3(.10,.07,.025),1.);
    if(paperBiome==1.) {
        // One inset service door and a painted diagonal reflection per bay.
        shade=printBox(q,vec2(1.20,.69),vec2(.44,.45),aa)*.35;
        line=paperStroke(q,vec2(.76,.24),vec2(.76,1.14),.013,aa);
        line=max(line,paperStroke(q,vec2(.76,.24),vec2(1.64,.24),.013,aa));
        paint=paperStroke(q,vec2(1.00,.88),vec2(1.30,1.04),.055,aa)*.3;
        paint=max(paint,printBox(q,vec2(1.48,.64),vec2(.025,.09),aa));
        pigment=vec3(.53,.87,.91);
    } else if(paperBiome==2.) {
        // Long tapering wood grain with one eccentric knot, not a plank grid.
        line=paperLine(q.x-.55-.055*sin(q.y*3.),.014,aa)*smoothstep(.08,.3,q.y)*(1.-smoothstep(1.8,2.2,q.y));
        line=max(line,paperLine(q.x-2.65-.035*sin(q.y*5.),.011,aa)*step(.45,q.y)*step(q.y,1.7));
        float knot=length((q-vec2(1.72,.68))*vec2(1.,.6));
        line=max(line,paperLine(knot-.12,.016,aa));
        paint=paperStroke(q,vec2(.63,.21),vec2(.69,1.0),.045,aa)*.4;
    } else if(paperBiome==3. || paperBiome==5.) {
        // Large masonry masses with offset joints and a single carved seal.
        line=paperStroke(q,vec2(.12,.48),vec2(2.90,.48),.015,aa);
        line=max(line,paperStroke(q,vec2(2.25,.48),vec2(2.25,1.30),.015,aa));
        shade=printBox(q,vec2(1.1,.34),vec2(.75,.11),aa)*.15;
        vec2 seal=q-vec2(.86,1.02);
        if(paperBiome==3.) {
            line=max(line,paperLine(length(seal)-.24,.025,aa));
            paint=paperStroke(seal,vec2(-.1,0),vec2(.1,0),.025,aa);
            pigment=vec3(.75,.85,.39);
        } else {
            line=max(line,paperLine(abs(seal.x)+abs(seal.y)-.27,.022,aa));
            paint=paperStroke(seal,vec2(0,-.14),vec2(0,.14),.045,aa);
            pigment=vec3(.20,.65,.61);
        }
    } else if(paperBiome==4.) {
        // Paired shop windows, deep blue glass and a broad coral awning.
        float window=printBox(q,vec2(1.65,.85),vec2(.66,.42),aa);
        base=mix(base,vec3(.20,.30,.43),window*.83*readable);
        paint=paperStroke(q,vec2(1.08,1.10),vec2(1.40,.87),.045,aa)*.6;
        line=paperStroke(q,vec2(1.65,.45),vec2(1.65,1.25),.025,aa);
        base=mix(base,vec3(.95,.57,.46),printBox(q,vec2(1.65,1.32),vec2(.76,.08),aa)*readable);
    } else if(paperBiome==6.) {
        // Bamboo has widely spaced stems and collars, not stone symbols.
        line=paperStroke(q,vec2(.65,.12),vec2(.70,2.5),.018,aa);
        line=max(line,paperStroke(q,vec2(2.6,.1),vec2(2.55,2.5),.014,aa));
        paint=paperStroke(q,vec2(.49,.65),vec2(.86,.65),.035,aa);
        paint=max(paint,paperStroke(q,vec2(2.38,1.35),vec2(2.73,1.35),.035,aa));
    } else if(paperBiome==7.) {
        // Two broad reflected brush shapes within large quiet ice planes.
        paint=paperStroke(q,vec2(.55,.57),vec2(1.10,1.15),.070,aa);
        paint=max(paint,paperStroke(q,vec2(.92,.53),vec2(1.23,.86),.035,aa));
        pigment=vec3(.94,.97,.91);
        shade=printBox(q,vec2(2.5,.12),vec2(.6,.12),aa)*.16;
    } else if(paperBiome==8.) {
        line=paperStroke(q,vec2(1.1,.1),vec2(1.3,.47),.030,aa);
        line=max(line,paperStroke(q,vec2(1.3,.47),vec2(1.05,.78),.025,aa));
        paint=paperStroke(q,vec2(1.12,.11),vec2(1.32,.45),.014,aa);
        pigment=vec3(1.,.57,.24);
    } else if(paperBiome==9.) {
        vec2 a=q-vec2(1.8,.68);
        float arch=max(abs(a.x)-.36,a.y-.63+abs(a.x)*.85);
        shade=(1.-smoothstep(0.,aa,arch))*step(-.43,a.y)*.6;
        paint=paperStroke(q,vec2(1.8,.40),vec2(1.8,.94),.024,aa);
        pigment=vec3(.96,.76,.48);
    } else if(paperBiome==10.) {
        vec2 a=(q-vec2(1.8,.70))*vec2(1.,1.7);
        line=paperLine(length(a)-.46,.024,aa)*step(0.,a.y);
        paint=paperStroke(q,vec2(1.25,.63),vec2(2.35,.63),.035,aa);
        pigment=vec3(1.,.85,.52);
    } else if(paperBiome==11.) {
        vec2 a=q-vec2(1.7,.72);
        line=paperLine(length(a)-.30,.030,aa);
        base=mix(base,vec3(.17,.18,.36),(1.-smoothstep(.20,.22+aa,length(a)))*readable);
        paint=paperStroke(q,vec2(2.3,.43),vec2(2.72,.43),.040,aa);
        pigment=vec3(.46,.88,.88);
    } else if(paperBiome==12.) {
        vec2 a=q-vec2(1.8,.75);
        line=paperLine(abs(a.x)+abs(a.y)-.36,.026,aa);
        paint=paperStroke(q,vec2(1.8,.54),vec2(1.8,.96),.045,aa);
        pigment=vec3(1.,.76,.46);
    }
    base=mix(base,ink,clamp(line*.65+shade,0.,.85)*readable);
    return mix(base,pigment,paint*readable*.65);
}
// Broad roof folds and a short painted seam. No raised strips, duplicate
// coplanar caps or cell-sized outlines. The print is quantized in world space.
vec3 paperRoof(vec2 plane,vec3 base) {
    float aa=max(.001,max(fwidth(plane.x),fwidth(plane.y)));
    vec2 q=mod(floor(plane*48.)/48.,vec2(4.8,3.2));
    float fold=smoothstep(.15,.20,q.y)*(1.-smoothstep(1.45,1.5,q.y));
    base=mix(base,base*vec3(.79,.85,.93),fold*.38);
    float seam=paperStroke(q,vec2(.45,1.5),vec2(4.25,1.5),.018,aa);
    float reflection=paperStroke(q,vec2(.85,2.15),vec2(1.9,2.65),.09,aa);
    base=mix(base,base*vec3(.58,.62,.74),seam*.55);
    return mix(base,min(base+vec3(.08,.06,.02),1.),reflection*.6);
}
`
