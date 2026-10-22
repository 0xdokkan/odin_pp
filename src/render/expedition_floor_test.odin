package render

import "core:testing"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_expedition_floor_cache_all_biomes_preserve_gameplay_tiles_and_terrain :: proc(t:^testing.T) {
	for biome in campaign.Biome {
		if biome==.Count {continue}
		w:world.World;data:level.Level
		testing.expect(t,world.generate(&w,&data,biome,77))
		room:=game.Room{level_data=&data};cache:Expedition_Floor_Data
		testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
		testing.expect_value(t,cache.width,world.map_size(biome))
		for tile,i in data.tiles.cells {
			p:=grid.Position{i%cache.width,i/cache.width}
			testing.expect_value(t,cache.pixels[i].r&7,u8(tile.kind))
			testing.expect_value(t,cache.pixels[i].g&15,u8(game.expedition_terrain(u8(biome),p)))
			// Compare packed adjacency against independent gameplay queries;
			// in particular a neighbouring Void retains its terrain enum.
			if tile.kind!=.Void && i%97==0 {
				walls,boundary:u8
				for d,direction in ([4]grid.Position{{-1,0},{1,0},{0,-1},{0,1}}) {
					q:=grid.Position{p.x+d.x,p.y+d.y};adjacent,inside:=level.tile_at(&data,q)
					if inside && adjacent.kind==.Wall {walls|=u8(1<<uint(direction))}
					terrain:=game.expedition_terrain(u8(biome),q) if inside else game.Expedition_Terrain.Plain
					if terrain!=game.expedition_terrain(u8(biome),p) {boundary|=u8(1<<uint(direction))}
				}
				testing.expect_value(t,(cache.pixels[i].r>>3)&15,walls)
				testing.expect_value(t,cache.pixels[i].g>>4,boundary)
			}
		}
		for &site in w.sites[:w.site_count] {
			minimum,maximum:=world.site_bounds(&site)
			for p in ([3]grid.Position{minimum,site.position,maximum}) {
				_,design:=world.site_at(&w,p)
				testing.expect_value(t,cache.pixels[p.y*cache.width+p.x].b&15,u8(design.surface))
			}
		}
		testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
		destroy_expedition_floor_data(&cache);level.destroy(&data)
	}
}

@(test)
test_expedition_floor_contact_shadows_follow_actual_walls_and_stable_slabs :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=world.World{biome=.Cyber,site_count=1}
	w.sites[0]={kind=.Archive,position={16,16},layout_version=world.SITE_LAYOUT_VERSION}
	room:=game.Room{level_data=&data};cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	_=level.set_tile(&data,{7,8},{.Wall});_=level.set_tile(&data,{8,7},{.Wall})
	_=level.set_tile(&data,{9,8},{.Door});_=level.set_tile(&data,{8,9},{.Void})
	_=level.set_tile(&data,{16,16},{.Wall}) // Actual solid terminal fixture.
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,(cache.pixels[8*32+8].r>>3)&15,u8(5))
	testing.expect_value(t,(cache.pixels[16*32+15].r>>3)&15,u8(2))
	testing.expect_value(t,(cache.pixels[0].r>>3)&15,u8(0))
	testing.expect_value(t,cache.pixels[8*32+8].b>>4,cache.pixels[11*32+11].b>>4)
	variation:[16]bool
	for y in 0..<8 {for x in 0..<8 {variation[cache.pixels[y*4*32+x*4].b>>4]=true}}
	variants:=0;for used in variation {if used {variants+=1}}
	testing.expect(t,variants>=8)
	pixels:=raw_data(cache.pixels);w.seed=991
	testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,raw_data(cache.pixels),pixels)
	_=level.set_tile(&data,{7,8},{.Floor});_=level.set_tile(&data,{16,16},{.Floor})
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,(cache.pixels[8*32+8].r>>3)&15,u8(4))
	// An authored fixture descriptor alone must not cast a collision shadow.
	testing.expect_value(t,(cache.pixels[16*32+15].r>>3)&15,u8(0))
}

@(test)
test_expedition_floor_cache_ignores_animation_but_invalidates_geography :: proc(t:^testing.T) {
	data,ok:=level.create(40,40,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=world.World{biome=.Inferno,site_count=1}
	w.sites[0]={kind=.Nest,position={20,20},layout_version=world.SITE_LAYOUT_VERSION}
	room:=game.Room{level_data=&data};cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	w.clock=18;w.beat=9;w.lane_warning=true;w.lane=15;w.lane_vertical=true
	w.sites[0].active=true;w.sites[0].state=.Resolved;w.sites[0].wave=2
	room.phase=.Combat
	testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.rebuilds,u64(1))
	p:=grid.Position{14,14};testing.expect(t,game.expedition_terrain(7,p)!=.Lava)
	testing.expect(t,level.set_tile(&data,p,{.Door}))
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.pixels[p.y*40+p.x].g&15,u8(game.Expedition_Terrain.Lava))
	testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
	w.sites[0].orientation=1;testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	w.sites[0].position.x+=1;testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	w.sites[0].layout_version=0;testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	w.biome=.Snow;testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	id:=data.geometry_id;level.destroy(&data);data,ok=level.create(40,40,{.Floor});testing.expect(t,ok)
	testing.expect(t,data.geometry_id!=id)
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.pixels[p.y*40+p.x].r&7,u8(level.Tile_Kind.Floor))
}

@(test)
test_expedition_floor_cache_exact_void_and_platform_boundaries :: proc(t:^testing.T) {
	data,ok:=level.create(24,24,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=world.World{biome=.Sky,site_count=1}
	w.sites[0]={kind=.Nest,position={12,12},layout_version=world.SITE_LAYOUT_VERSION}
	room:=game.Room{level_data=&data};cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	_=level.set_tile(&data,{5,6},{.Void});_=level.set_tile(&data,{7,6},{.Void})
	_=level.set_tile(&data,{6,5},{.Void});_=level.set_tile(&data,{6,7},{.Void})
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.pixels[6*24+6].a&15,u8(15))
	testing.expect_value(t,cache.pixels[0].a&15,u8(5))
	testing.expect_value(t,cache.pixels[12*24+12].a>>4,u8(0))
	testing.expect_value(t,cache.pixels[9*24+9].a>>4,u8(5))
	testing.expect_value(t,cache.pixels[15*24+15].a>>4,u8(10))
	_=level.set_tile(&data,{7,6},{.Floor})
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.pixels[6*24+6].a&15,u8(13))
	// A bulk restore has an explicit invalidation hook.
	data.tiles.cells[6*24+7]={.Void};level.mark_geometry_changed(&data)
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.pixels[6*24+6].a&15,u8(15))
}

@(test)
test_expedition_floor_cache_resizes_and_preserves_site_overlap_precedence :: proc(t:^testing.T) {
	data,ok:=level.create(40,40,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=world.World{biome=.Cyber,site_count=2}
	w.sites[0]={kind=.Spring,position={20,20},layout_version=world.SITE_LAYOUT_VERSION}
	w.sites[1]={kind=.Nest,position={20,20},layout_version=world.SITE_LAYOUT_VERSION}
	room:=game.Room{level_data=&data};cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	_,expected:=world.site_at(&w,{20,20})
	testing.expect_value(t,cache.pixels[20*40+20].b&15,u8(expected.surface))
	testing.expect_value(t,expected.surface,world.Site_Surface.Pool)
	level.destroy(&data)
	// Never keep drawing the previous world during a destroyed/invalid level.
	testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect(t,!cache.ready)
	data,ok=level.create(224,224,{.Floor});testing.expect(t,ok)
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	testing.expect_value(t,cache.width,224);testing.expect_value(t,len(cache.pixels),224*224)
	testing.expect_value(t,cache.pixels[223*224+223].a&15,u8(10))
	pixels:=raw_data(cache.pixels)
	for i in 0..<120 {
		w.clock=f32(i);w.beat=u64(i);w.lane_warning=i%2==0
		testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
		testing.expect_value(t,raw_data(cache.pixels),pixels)
	}
	testing.expect_value(t,cache.rebuilds,u64(2))
}
