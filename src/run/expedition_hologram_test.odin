package run

import "core:testing"
import "core:time"
import "core:fmt"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import level "../level"

@(test)
test_hologram_preserves_actual_walls_gates_and_void_in_whole_large_maps :: proc(t:^testing.T) {
	g:=new(Hologram_Geometry);defer free(g)
	for biome in ([3]campaign.Biome{.Cyber,.Sky,.Secret}) {
		w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,biome,291));defer level.destroy(&data)
		hologram_geometry(&w,&data,g)
		testing.expect_value(t,g.width,world.size(&w));testing.expect_value(t,g.height,world.size(&w))
		for y in 0..<g.height {for x in 0..<g.width {
			tile:=data.tiles.cells[y*data.tiles.width+x];cell:=g.cells[y*HOLO_SIDE+x]
			testing.expect(t,(cell.ground==0)==(tile.kind==.Void))
			testing.expect(t,(cell.wall>0)==(tile.kind==.Wall))
		}}
		// The miniature must follow mutations in the current level, rather than
		// regenerating walls from an authored court or a remembered seed.
		site:=&w.sites[0];changed:=world.site_world(site,{-11,4})
		level.set_tile(&data,changed,{.Floor});hologram_geometry(&w,&data,g)
		testing.expect_value(t,g.cells[changed.y*HOLO_SIDE+changed.x].wall,u8(0))
		if #config(EXPEDITION_HOLOGRAM_BENCHMARK,false) && biome==.Secret {
			total,peak:=f64(0),f64(0)
			for _ in 0..<100 {
				started:=time.tick_now();hologram_geometry(&w,&data,g)
				elapsed:=time.duration_milliseconds(time.tick_since(started));total+=elapsed;peak=max(peak,elapsed)
			}
			ground_runs,wall_runs:=0,0
			for y in 0..<g.height {
				last_ground,last_wall:=u8(0),u8(0)
				for x in 0..<g.width {
					cell:=g.cells[y*HOLO_SIDE+x]
					if cell.ground>0 && cell.ground!=last_ground {ground_runs+=1}
					if cell.wall>0 && cell.wall!=last_wall {wall_runs+=1}
					last_ground,last_wall=cell.ground,cell.wall
				}
			}
			fmt.printf("HOLOGRAM 224x224: 100 samples, mean %.3f ms, peak %.3f ms, %d ground runs + %d wall runs, %d-byte local geometry\n",total/100,peak,ground_runs,wall_runs,size_of(Hologram_Geometry))
		}
	}
}

@(test)
test_hologram_site_knowledge_never_reveals_exact_pins_or_hidden_secrets :: proc(t:^testing.T) {
	for kind in world.Site_Kind {for y in 0..<32 {for x in 0..<32 {
		site:=world.Site{kind=kind,active=true,position={x,y}}
		area:=hologram_area(&site);testing.expect(t,area.visible)
		dx,dz:=area.center.x-(f32(x)+.5),area.center.z-(f32(y)+.5)
		testing.expect(t,dx*dx+dz*dz>0 && dx*dx+dz*dz<area.radius*area.radius)
		site.state=.Discovered;testing.expect_value(t,hologram_area(&site),area)
		site.state=.Resolved;testing.expect_value(t,hologram_area(&site),area)
		site.secret=true;site.state=.Unvisited;testing.expect(t,!hologram_area(&site).visible)
		site.state=.Discovered;testing.expect(t,hologram_area(&site).visible)
	}}}
}

@(test)
test_hologram_whole_map_and_marker_layout_fit_native_viewport :: proc(t:^testing.T) {
	for side in ([6]int{80,96,112,160,192,224}) {
		camera:=hologram_camera(side,side)
		for x in ([2]f32{0,f32(side)}) {for z in ([2]f32{0,f32(side)}) {for h in ([2]f32{-5,f32(side)/160*12}) {
			p:=rl.GetWorldToScreenEx({x,h,z},camera,960,540)
			testing.expect(t,p.x>=18 && p.x<=676 && p.y>=110 && p.y<=475)
		}}}
	}
	w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,.Secret,493));defer level.destroy(&data)
	camera:=hologram_camera(world.size(&w),world.size(&w))
	used:[world.MAX_SITES]rl.Vector2;count:=0
	for &site in w.sites[:w.site_count] {
		site.state=.Discovered;area:=hologram_area(&site)
		p:=hologram_label_position(rl.GetWorldToScreenEx(area.center+{0,2,0},camera,960,540),used[:count])
		for other in used[:count] {testing.expect(t,rl.Vector2DistanceSqr(p,other)>=26*26)}
		testing.expect(t,p.x>=36 && p.x<=654 && p.y>=109 && p.y<=455)
		used[count]=p;count+=1
	}
}
