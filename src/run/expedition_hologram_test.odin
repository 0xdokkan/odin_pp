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
		site:=&w.sites[0];changed:=world.site_world(site,{x = -11, y = 4})
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

// A mountain of ninety steps is a few bands on the map, and the low relief is shown as it is; a pit under a raised map's
// base (Fase 8) is below zero.
@(test)
test_hologram_heights_are_shown_as_they_are_and_the_tall_ones_in_bands :: proc(t:^testing.T) {
	for steps in i32(0)..=HOLO_FLAT_STEPS {testing.expect_value(t,hologram_band(steps),i16(steps))}
	testing.expect_value(t,hologram_band(-3),i16(-3))
	testing.expect_value(t,hologram_band(-14),i16(-14))
	testing.expect(t,hologram_band(HOLO_FLAT_STEPS+1)==HOLO_FLAT_STEPS)
	testing.expect(t,hologram_band(HOLO_FLAT_STEPS+HOLO_BAND_STEPS)==HOLO_FLAT_STEPS+1)
	top:=hologram_band(i32(level.MOUNTAIN_TOP))
	testing.expect(t,top>HOLO_FLAT_STEPS && top<=HOLO_FLAT_STEPS+16,"the mountain is a few bands")
	for steps in i32(1)..<i32(level.MOUNTAIN_TOP) {testing.expect(t,hologram_band(steps+1)>=hologram_band(steps))}
}

// The stacked map (Fase 8 of docs/piano-profondita.md): a plate for every layer with a cell, W and S going from one to the
// next that has one. City pop has its overpasses over the ground and its metro on the deep layer, and nothing between;
// the Memoria has the boulder's hall under the ground; the Spazio's craters are pits under the base, on the ground's plate.
@(test)
test_hologram_stacks_a_plate_for_each_layer_with_cells :: proc(t:^testing.T) {
	g:=new(Hologram_Geometry);defer free(g)
	{
		w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,.City,7));defer level.destroy(&data)
		plates:=hologram_plates(&data)
		testing.expect(t,plates[level.layer_slot(1)] && plates[level.layer_slot(0)] && !plates[level.layer_slot(-1)] && plates[level.layer_slot(-2)])
		testing.expect_value(t,hologram_next_plate(&data,0,1),i8(1))
		testing.expect_value(t,hologram_next_plate(&data,1,1),i8(1))
		testing.expect_value(t,hologram_next_plate(&data,0,-1),i8(-2))
		testing.expect_value(t,hologram_next_plate(&data,-2,-1),i8(-2))
		hologram_plate(&w,&data,world.NETWORK_LAYER,g)
		cells:=0
		for y in 0..<g.height {for x in 0..<g.width {
			cell:=g.cells[y*HOLO_SIDE+x]
			tile,_:=level.tile_at(&data,{x = x, y = y, layer = world.NETWORK_LAYER})
			walked:=level.kind_has_floor(tile.kind) || tile.kind==.Fence
			testing.expect(t,(cell.ground>0)==walked)
			if walked {cells+=1;testing.expect_value(t,cell.ground,u8(18))}
		}}
		testing.expect(t,g.present && cells>=60,"the metro's plate")
	}
	{
		w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,.Secret,7));defer level.destroy(&data)
		plates:=hologram_plates(&data)
		testing.expect(t,plates[level.layer_slot(-1)] && !plates[level.layer_slot(-2)] && !plates[level.layer_slot(1)])
		hologram_plate(&w,&data,world.COMPLEX_TUNNEL,g)
		testing.expect(t,g.present)
		for y in 0..<g.height {for x in 0..<g.width {if g.cells[y*HOLO_SIDE+x].ground>0 {testing.expect_value(t,g.cells[y*HOLO_SIDE+x].ground,u8(17))}}}
	}
	{
		w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,.Space,7));defer level.destroy(&data)
		hologram_geometry(&w,&data,g)
		testing.expect_value(t,g.lowest,hologram_band(-world.COMPLEX_TOP))
	}
}

// The map kept between frames (Hologram_Cache): built once, built again only when the map's geometry or the plate shown
// changes. Without a window, as here, the triangles stay in the lists sent vertex by vertex.
@(test)
test_hologram_is_kept_until_the_map_or_the_plate_shown_changes :: proc(t:^testing.T) {
	w:world.World;data:level.Level;testing.expect(t,world.generate(&w,&data,.City,7));defer level.destroy(&data)
	cache:Hologram_Cache;defer hologram_release(&cache)
	tint:=rl.Color{90,200,240,255}
	ground,over,deep:=level.layer_slot(0),level.layer_slot(1),level.layer_slot(-2)
	// City pop has no cell under its ground: asked for, the ground is shown.
	testing.expect_value(t,hologram_prepare(&cache,&w,&data,-1,tint),i8(0))
	testing.expect(t,cache.ready && cache.drawn && len(cache.lines)>0)
	testing.expect(t,len(cache.triangles[ground])>0 && len(cache.triangles[over])>0 && len(cache.triangles[deep])>0)
	testing.expect_value(t,len(cache.triangles[level.layer_slot(-1)]),0)
	whole:=len(cache.triangles[ground])
	// Kept: a mark put in a plate and in the lines is still there the next frame.
	cache.plates[ground].cells[0].height=777
	append(&cache.lines,Hologram_Vertex{})
	testing.expect_value(t,hologram_prepare(&cache,&w,&data,0,tint),i8(0))
	testing.expect_value(t,cache.plates[ground].cells[0].height,i16(777))
	testing.expect_value(t,cache.lines[len(cache.lines)-1],Hologram_Vertex{})
	// Another plate shown: its drawing is made again, the plates are kept; the ground is only its faint tops now.
	testing.expect_value(t,hologram_prepare(&cache,&w,&data,1,tint),i8(1))
	testing.expect_value(t,cache.plates[ground].cells[0].height,i16(777))
	testing.expect(t,cache.lines[len(cache.lines)-1]!=Hologram_Vertex{})
	testing.expect(t,len(cache.triangles[ground])>0 && len(cache.triangles[ground])<whole)
	// The map changes (a gate opens, a structure is set down): the plates are made again.
	level.mark_geometry_changed(&data)
	testing.expect_value(t,hologram_prepare(&cache,&w,&data,1,tint),i8(1))
	testing.expect(t,cache.plates[ground].cells[0].height!=777)
}

@(test)
test_hologram_site_knowledge_never_reveals_exact_pins_or_hidden_secrets :: proc(t:^testing.T) {
	for kind in world.Site_Kind {for y in 0..<32 {for x in 0..<32 {
		site:=world.Site{kind=kind,active=true,position={x = x, y = y}}
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
