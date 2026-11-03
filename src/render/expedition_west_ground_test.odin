package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import world "../expedition"
import grid "../engine/grid"

@(test)
test_west_ground_routes_keep_actual_workshop_entrances_and_banks_clear :: proc(t:^testing.T) {
	bends:=WEST_GROUND_BENDS
	for turn in 0..<4 {
		site:=world.Site{kind=.Workshop,position={x = 40,y = 40},orientation=u8(turn),layout_version=world.SITE_LAYOUT_VERSION}
		for segment,i in WEST_GROUND_ROUTES {
			a,b:=rl.Vector2{segment.x,segment.y},rl.Vector2{segment.z,segment.w}
			direction:=b-a;across:=rl.Vector2{-direction.y,direction.x}/rl.Vector2Length(direction)
			for sample in 0..=80 {
				time:=f32(sample)/80
				q:=a+direction*time+across*bends[i]*math.sin(time*math.PI)
				local:=grid.Position{x = int(math.floor(q.x+.5)),y = int(math.floor(q.y+.5))}
				p:=world.site_world(&site,local);design:=world.site_cell(&site,p)
				testing.expect(t,design.inside && !design.wall && !design.fixture,"The illustrated traffic must lead through existing clear cells")
			}
		}
	}
}

@(test)
test_west_ground_pigment_is_bounded_continuous_and_quiet_at_site_edge :: proc(t:^testing.T) {
	changed:=0
	for z in 0..<49 {for x in 0..<53 {
		q:=rl.Vector2{f32(x)*.5-13,f32(z)*.5-12}
		pigment:=west_workshop_ground_sample(q)
		testing.expect_value(t,pigment,west_workshop_ground_sample(q))
		for channel in pigment {testing.expect(t,channel>=0 && channel<=1)}
		if pigment!=WEST_GROUND_BASE {changed+=1}
		if abs(q.x)>=12.5 || abs(q.y)>=11.5 {testing.expect_value(t,pigment,WEST_GROUND_BASE)}
	}}
	testing.expect(t,changed>100 && changed<1000,"Circulation uses part of the floor; it must not become a new full-site mat")
	// No jump across a tile seam or the bounded texture perimeter. Wider
	// footprint filters remain finite when viewed at reduced game scales.
	for q in ([5]rl.Vector2{{0,11.49},{-12.49,0},{6,4},{-.5,4.5},{3.5,-3.5}}) {
		a:=west_workshop_ground_sample(q);b:=west_workshop_ground_sample(q+{.001,.001})
		testing.expect(t,rl.Vector3Distance(a,b)<.025)
		coarse:=west_workshop_ground_sample(q,.10)
		for channel in coarse {testing.expect(t,channel>=0 && channel<=1)}
	}
	// A quiet corner remains the same dusty stock as outside the workshop.
	testing.expect_value(t,west_workshop_ground_sample({8,7}),WEST_GROUND_BASE)
	testing.expect(t,west_workshop_ground_sample({0,7}).y>WEST_GROUND_BASE.y)
}
