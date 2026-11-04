package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"

#assert(world.MAX_SITES==24)

// Authored circulation follows the actual workshop entrances and the clear
// working sides of its benches. These are pigment strokes, never geometry.
// Four coordinates per route are uploaded once when a floor program loads.
CYBER_FLOOR_ROUTES :: [?]rl.Vector4{
	{0,11,0,2}, {0,-11,0,-2}, {-12,0,-2,0},
	{0,2,-2,0}, {-2,0,0,-2},
	{0,3.1,6,4}, {0,-3.1,6,-4},
	{-4,0,-5.8,6.5}, {-4,0,-5.8,-6.5},
}
#assert(len(CYBER_FLOOR_ROUTES)==9)
CYBER_FLOOR_BENDS :: [9]f32{.24,-.25,-.22,0,0,.33,-.28,.36,-.34}

// One record per real, visible workshop: world centre and its local X axis.
// Fixed storage, no game RNG, actor positions, transient state or allocations.
@(private)
cyber_floor_workshops :: proc(w:^world.World)->(sites:[world.MAX_SITES]rl.Vector4,count:int) {
	if w==nil || (w.biome!=.Cyber && w.biome!=.West) {return}
	axes:=[4]rl.Vector2{{1,0},{0,1},{-1,0},{0,-1}}
	for site in w.sites[:clamp(world.visible_sites(w),0,world.MAX_SITES)] {
		if site.kind!=.Workshop || site.layout_version!=world.SITE_LAYOUT_VERSION {continue}
		axis:=axes[site.orientation%4]
		sites[count]={f32(site.position.x)+.5,f32(site.position.y)+.5,axis.x,axis.y}
		count+=1
	}
	return
}

// The route painting is evaluated only while building the immutable stock.
// GPU filtering and mipmaps handle the screen footprint after this point.
// Crisp floor markings in the manner of a real workshop: red guide lines from
// the entrances with ring nodes at their ends, a yellow double frame round the
// machine's working area, a few blue service sockets and dashed bench lanes.
// Only a faint warm wear remains where traffic sweeps; no broad grey wash.
@(private)
cyber_workshop_ground_sample :: proc(q:rl.Vector2,aa:f32)->rl.Vector3 {
	edge:=min(12.5-abs(q.x),11.5-abs(q.y))
	fade:=workshop_ground_smooth(.05,1.1,edge)
	swept,guide,dashes,nodes:=f32(0),f32(0),f32(0),f32(0)
	routes:=CYBER_FLOOR_ROUTES;bends:=CYBER_FLOOR_BENDS
	line :: proc(d,width,aa:f32)->f32 {return 1-workshop_ground_smooth(width,width+aa,abs(d))}
	for route,i in routes {
		a,b:=rl.Vector2{route.x,route.y},rl.Vector2{route.z,route.w}
		direction:=b-a;span:=rl.Vector2Length(direction)
		t:=clamp(rl.Vector2DotProduct(q-a,direction)/rl.Vector2LengthSqr(direction),0,1)
		across_axis:=rl.Vector2{-direction.y,direction.x}/span
		center:=a+(b-a)*t+across_axis*bends[i]*math.sin(t*math.PI)
		delta:=q-center;along:=t*span
		width:=f32(1.35) if i<3 else .85
		swept=max(swept,1-workshop_ground_smooth(width*.5,width+.45,rl.Vector2Length(delta)))
		if i<3 {
			// The entrance guide: one continuous line, a ring node where it starts and where it meets the machine's frame.
			ends:=workshop_ground_smooth(.55,.75,along)*(1-workshop_ground_smooth(span-.75,span-.55,along))
			guide=max(guide,line(rl.Vector2Length(delta),.045,aa)*ends)
			for node in ([2]rl.Vector2{a+(b-a)*(.62/span),b-(b-a)*(.62/span)}) {
				r:=rl.Vector2Length(q-node)
				nodes=max(nodes,line(r-.17,.04,aa))
			}
		} else if i>=5 {
			// Bench lanes: short dashes, broken where the lane bends away.
			ends:=workshop_ground_smooth(.9,1.3,along)*(1-workshop_ground_smooth(span-1.3,span-.9,along))
			phase:=along*1.6+f32(i)*.37
			dash:=1-workshop_ground_smooth(.45,.5,phase-math.floor(phase))
			dashes=max(dashes,line(rl.Vector2Length(delta),.04,aa)*ends*dash)
		}
	}
	base:=rl.Vector3{1,.925,.78}
	base+=(rl.Vector3{.94,.85,.69}-base)*(swept*fade*.32)
	// The machine's working area: a yellow double frame, open where the guides come in.
	frame:=f32(0)
	for half in ([2]f32{1.62,1.86}) {
		d:=max(abs(q.x)-half,abs(q.y)-half)
		frame=max(frame,line(d,.035,aa))
	}
	opening:=min(abs(q.x),abs(q.y))
	frame*=workshop_ground_smooth(.32,.42,opening)
	// Corner ticks just outside the frame.
	for sx in ([2]f32{-1,1}) {for sy in ([2]f32{-1,1}) {
		c:=rl.Vector2{sx*2.12,sy*2.12};d:=q-c
		tick:=max(line(d.y,.035,aa)*(1-workshop_ground_smooth(.18,.2,abs(d.x+sx*.1))),line(d.x,.035,aa)*(1-workshop_ground_smooth(.18,.2,abs(d.y+sy*.1))))
		frame=max(frame,tick)
	}}
	// Blue service sockets set into the floor, clear of every route.
	socket:=f32(0)
	for c in ([4]rl.Vector2{{3.4,-1.9},{-2.6,3.6},{-3.1,-3.3},{8.4,1.6}}) {
		d:=q-c
		box:=max(abs(d.x),abs(d.y))
		socket=max(socket,1-workshop_ground_smooth(.20,.20+aa,box))
		base+=(rl.Vector3{.62,.78,.93}-base)*((1-workshop_ground_smooth(.27,.27+aa,box))*fade*.55)
	}
	base+=(rl.Vector3{.30,.58,.88}-base)*(socket*fade)
	base+=(rl.Vector3{.98,.73,.19}-base)*(frame*fade*.92)
	base+=(rl.Vector3{.86,.27,.24}-base)*(max(guide,nodes)*fade*.95)
	base+=(rl.Vector3{.86,.27,.24}-base)*(dashes*fade*.75)
	return base
}

EXPEDITION_CYBER_FLOOR_GLSL :: `
uniform vec4 cyberWorkshops[24];
uniform int cyberWorkshopCount;
uniform sampler2D workshopStock;

vec3 cyberWorkshopGround(vec2 p,vec3 original,float aa) {
    for(int i=0;i<cyberWorkshopCount;i++) {
        vec2 d=p-cyberWorkshops[i].xy,axis=cyberWorkshops[i].zw;
        vec2 q=vec2(dot(d,axis),dot(d,vec2(-axis.y,axis.x)));
        if(abs(q.x)<=12.5 && abs(q.y)<=11.5) {
            return texture(workshopStock,(q+vec2(12.5,11.5))/vec2(25.,23.)).rgb;
        }
    }
    return original;
}

// Sparse sediment accumulates against real solid neighbours only. A dark
// short stroke and broad quiet pigment connect wall and ground without an
// individual cell frame or an object-shaped base.
vec3 cyberGroundContact(vec2 p,vec2 uv,int continuous,vec3 base,float aa) {
    // The exact three-wall adjacency is cached with map geometry.
    float edge=borderMask(continuous,uv,.075,aa);
    float along=abs(sin(p.x*.47+p.y*.63));
    float pigment=borderMask(continuous,uv,.23,aa)*smoothstep(.35,.72,along);
    base=mix(base,vec3(.75,.69,.54),pigment*.13);
    return mix(base,vec3(.40,.49,.46),edge*.23*smoothstep(.42,.68,along));
}

vec3 cyberCliffPigment(vec3 p,vec3 n,float capDepth) {
    float along=abs(n.x)>.5?p.z:p.x;
    // Broad strata cross cell joins; their height is registered in the world.
    float layer=p.y*1.6+.045*sin(along*.63)+.018*sin(along*1.71);
    float band=smoothstep(.43,.46,fract(layer));
    vec3 rock=mix(vec3(.61,.48,.40),vec3(.73,.59,.46),band);
    rock=mix(rock,vec3(.88,.76,.55),1.-smoothstep(.015,.075,capDepth));
    float seam=inkLine(fract(layer)-.43,.012,max(fwidth(layer),.001));
    return mix(rock,vec3(.40,.40,.40),seam*.34*smoothstep(.06,.14,capDepth));
}
`
