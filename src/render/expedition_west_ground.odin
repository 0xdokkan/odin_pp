package render

import "core:math"
import rl "vendor:raylib"

// The texture owner samples this pure pigment model once. Coordinates are
// site-local, centred on the actual Workshop fixture, before its quarter turn.
// RGB is sRGB numeric pigment, not lighting, height, collision or hazard data.
WEST_GROUND_BASE :: rl.Vector3{.96,.76,.48}
WEST_GROUND_ROUTES :: [?]rl.Vector4{
	{0,11,0,2}, {0,-11,0,-2}, {-12,0,-2,0},
	{0,2,-2,0}, {-2,0,0,-2},
	{0,3.1,6,4}, {0,-3.1,6,-4},
	{-4,0,-5.8,6.5}, {-4,0,-5.8,-6.5},
}
WEST_GROUND_BENDS :: [9]f32{.28,-.31,-.26,0,0,.38,-.35,.31,-.29}

@(private)
west_ground_smooth :: proc(a,b,x:f32)->f32 {
	t:=clamp((x-a)/(b-a),0,1)
	return t*t*(3-2*t)
}

@(private)
west_ground_mix :: proc(a,b:rl.Vector3,t:f32)->rl.Vector3 {return a+(b-a)*t}

@(private)
west_workshop_ground_sample :: proc(local:rl.Vector2,footprint:f32=25.0/1024)->rl.Vector3 {
	q:=local
	if abs(q.x)>=12.5 || abs(q.y)>=11.5 {return WEST_GROUND_BASE}
	aa:=max(footprint,.001)
	fade:=west_ground_smooth(.05,1.15,min(12.5-abs(q.x),11.5-abs(q.y)))
	swept,ruts:=f32(0),f32(0)
	bends:=WEST_GROUND_BENDS
	for segment,i in WEST_GROUND_ROUTES {
		a,b:=rl.Vector2{segment.x,segment.y},rl.Vector2{segment.z,segment.w}
		direction:=b-a;length_sq:=rl.Vector2LengthSqr(direction)
		t:=clamp(rl.Vector2DotProduct(q-a,direction)/length_sq,0,1)
		width:=f32(1.48) if i<3 else f32(.88)
		delta_straight:=q-(a+direction*t)
		reach:=max(width+.5,width*.39+.05+.035+aa)+abs(bends[i])
		if rl.Vector2LengthSqr(delta_straight)>reach*reach {continue}
		span:=math.sqrt(length_sq)
		across_axis:=rl.Vector2{-direction.y,direction.x}/span
		center:=a+direction*t+across_axis*bends[i]*math.sin(t*math.PI)
		delta:=q-center
		along:=t*span
		across:=rl.Vector2DotProduct(delta,across_axis)
		swept=max(swept,1-west_ground_smooth(width*.48,width+.5,rl.Vector2Length(delta)))
		if i==3 || i==4 {continue}
		ends:=west_ground_smooth(.8,1.7,along)*(1-west_ground_smooth(span-1.9,span-.7,along))
		// Wagon wear is incomplete and offset on the two wheels, never a
		// pair of painted rails. The broad light dust carries the route.
		phase:=along*.46+f32(i)*.31+(f32(.37) if across<0 else 0)
		broken:=1-west_ground_smooth(.25,.45,phase-math.floor(phase))
		wav:=.045*math.sin(along*1.18+f32(i))
		line:=1-west_ground_smooth(.03,.03+aa,abs(abs(across+wav)-width*.39))
		ruts=max(ruts,line*ends*broken*.20)
	}
	color:=west_ground_mix(WEST_GROUND_BASE,{.96,.85,.64},swept*fade*.26)
	color=west_ground_mix(color,{.54,.35,.20},ruts*fade)
	// A few individually drawn shavings on the working sides of the banks.
	// These are small loose marks; no underlying patch or cell-shaped shadow.
	chips:=[8]rl.Vector4{{5.5,3.55,.11,.035},{5.84,3.38,.065,.08},{6.22,3.72,.14,.038},
		{5.72,-3.43,.075,.08},{6.18,-3.65,.13,.04},
		{-5.5,5.85,.12,.04},{-5.35,6.15,.065,.085},{-5.48,-5.92,.12,.04}}
	for chip in chips {
		p:=q-rl.Vector2{chip.x,chip.y}
		if abs(p.x)>chip.z+aa || abs(p.y)>chip.w+aa {continue}
		shape:=abs(p.x)/chip.z+abs(p.y)/chip.w
		mark:=1-west_ground_smooth(.68,1+aa/min(chip.z,chip.w),shape)
		color=west_ground_mix(color,{.65,.40,.20},mark*.45)
	}
	return color
}
