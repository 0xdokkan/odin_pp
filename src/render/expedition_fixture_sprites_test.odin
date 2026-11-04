package render

import "core:testing"
import rl "vendor:raylib"
import world "../expedition"
import grid "../engine/grid"
import game "../game"

@(test)
expedition_paper_workshop_covers_every_skipped_solid_and_no_walkway :: proc(t:^testing.T) {
	for orientation in u8(0)..<4 {
		site:=world.Site{kind=.Workshop,position={x=30,y=45},orientation=orientation,layout_version=world.SITE_LAYOUT_VERSION,active=true}
		cells,count:=expedition_workshop_sprite_cells(&site)
		testing.expect(t,count>0)
		lo,hi:=world.site_bounds(&site)
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			cell:=grid.Position{x=x,y=y}
			design:=world.site_cell(&site,cell)
			drawn:=false
			for candidate in cells[:count] {if candidate==cell {drawn=true;break}}
			testing.expect_value(t,drawn,expedition_workshop_is_sprite(&site,design))
			if drawn {testing.expect(t,design.wall && !design.fixture,"sprite must occupy real cover, never a walkway or main interaction")}
		}}
	}
}

@(test)
expedition_fixture_reveal_requires_visible_overlap_not_a_nearby_cell :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	s:=new(Room_Presentation);defer free(s)
	r.canvas_width=960;r.canvas_height=540;r.tactical.no_fog=true;r.tactical.snapshot=s;r.tactical.perspective=true
	r.tactical.camera=tactical_orbit_camera({yaw=.7,pitch=.65,distance=15},{.5,0,.5},true)
	s.player={entity=game.PLAYER_ENTITY,visible=true,opacity=1,position={0,0}}
	right:=flipbook_camera_right(r)
	mask:[FIXTURE_CELL*FIXTURE_CELL]u8
	for y in 10..<94 {for x in 22..<74 {mask[y*FIXTURE_CELL+x]=2}}
	ink:=expedition_fixture_mask_bounds(&mask)
	near:=expedition_fixture_quad(right,{.5,.008,.5})
	beside:=expedition_fixture_quad(right,rl.Vector3{.5,.008,.5}+right*2)
	testing.expect(t,expedition_fixture_overlaps_actor(r,near,ink))
	testing.expect(t,!expedition_fixture_overlaps_actor(r,beside,ink),"adjacent machinery with no projected overlap must stay opaque")
	testing.expect(t,!expedition_fixture_overlaps_actor(r,near,{}),"a clear atlas region must not hide the actor")
}

@(test)
expedition_fixture_paper_sole_stays_on_its_ground_in_every_camera_direction :: proc(t:^testing.T) {
	for right in ([4]rl.Vector3{{1,0,0},{0,0,1},{-.7071068,0,.7071068},{.7071068,0,-.7071068}}) {
		for ground in ([3]f32{-3,0,2.5}) {
			base:=rl.Vector3{4.5,ground+.008,6.5}
			q:=expedition_fixture_quad(right,base)
			left:=q[0]+(q[1]-q[0])*(CARTOON_FEET/f32(FIXTURE_CELL))
			right_foot:=q[3]+(q[2]-q[3])*(CARTOON_FEET/f32(FIXTURE_CELL))
			testing.expect(t,abs(left.y-base.y)<.00001 && abs(right_foot.y-base.y)<.00001)
			testing.expect(t,rl.Vector3Distance((left+right_foot)*.5,base)<.00001)
		}
	}
}
