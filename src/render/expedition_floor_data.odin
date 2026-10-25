package render

import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Exact packed integer texels (one texture fetch per floor fragment):
// R: tile in bits 0..2, neighbouring solid walls in bits 3..6.
// G: terrain in bits 0..3, terrain-patch boundaries in bits 4..7.
// B: authored surface in bits 0..3, stable slab variation in bits 4..7.
// A: void boundaries in bits 0..3, platform boundaries in bits 4..7.
// Boundary directions are west, east, north, south. Dynamic state stays
// in uniforms; all adjacency is computed only after a geometry change.
Expedition_Floor_Site_Key :: struct {
	position: grid.Position,
	kind: world.Site_Kind,
	orientation, version: u8,
}
Expedition_Floor_Data :: struct {
	pixels: []rl.Color,
	level_data: ^level.Level,
	cells: rawptr,
	geometry_id, revision: u64,
	width, height: int,
	biome: u8,
	sites: [world.MAX_SITES]Expedition_Floor_Site_Key,
	site_count: int,
	ready: bool,
	rebuilds: u64,
}

@(private)
expedition_floor_site_keys :: proc(w:^world.World)->(keys:[world.MAX_SITES]Expedition_Floor_Site_Key) {
	for s,i in w.sites[:clamp(world.visible_sites(w),0,world.MAX_SITES)] {
		keys[i]={s.position,s.kind,s.orientation,s.layout_version}
	}
	return
}

@(private)
expedition_floor_slab_variant :: proc(p:grid.Position)->u8 {
	h:=u32(p.x/4+1499)*0x9e3779b9 ~ u32(p.y/4+617)*0x85ebca6b
	h~=h>>16;h*=0x2c1b3c6d;h~=h>>15
	return u8(h&15)
}

// Returns true only when CPU pixels changed and a GPU upload is needed.
// Checking the key examines at most 24 site descriptors, never map cells.
refresh_expedition_floor_data :: proc(cache:^Expedition_Floor_Data,room:^game.Room,w:^world.World)->bool {
	if cache==nil {return false}
	if room==nil || room.level_data==nil || w==nil {cache.ready=false;return false}
	data:=room.level_data;width,height:=data.tiles.width,data.tiles.height
	if width<=0 || height<=0 || len(data.tiles.cells)!=width*height {cache.ready=false;return false}
	keys:=expedition_floor_site_keys(w);count:=clamp(world.visible_sites(w),0,world.MAX_SITES)
	// In a cave none of the biome's terrain is painted on the floor (biome 255 has none).
	biome:=u8(w.biome) if w.in_cave==0 else u8(255)
	if cache.ready && cache.level_data==data && cache.cells==raw_data(data.tiles.cells) &&
		cache.geometry_id==data.geometry_id && cache.revision==data.geometry_revision &&
		cache.width==width && cache.height==height && cache.biome==biome &&
		cache.site_count==count && cache.sites==keys {return false}
	if len(cache.pixels)!=width*height {
		delete(cache.pixels);cache.pixels=make([]rl.Color,width*height)
	}
	cache.level_data=data;cache.cells=raw_data(data.tiles.cells)
	cache.geometry_id=data.geometry_id;cache.revision=data.geometry_revision
	cache.width=width;cache.height=height;cache.biome=biome
	cache.sites=keys;cache.site_count=count
	for tile,i in data.tiles.cells {
		p:=grid.Position{x = i%width, y = i/width};ground:=game.expedition_terrain(biome,p)
		if w.biome==.Inferno && w.in_cave==0 && tile.kind==.Door {ground=.Lava}
		cache.pixels[i]={u8(tile.kind),u8(ground),0,0}
	}
	// Earlier overlapping sites have the same precedence as world.site_at.
	for i:=count-1;i>=0;i-=1 {
		site:=&w.sites[i];minimum,maximum:=world.site_bounds(site)
		for y in max(0,minimum.y)..=min(height-1,maximum.y) {
			for x in max(0,minimum.x)..=min(width-1,maximum.x) {
				design:=world.site_cell(site,{x = x, y = y})
				if design.inside {cache.pixels[y*width+x].b=u8(design.surface)}
			}
		}
	}
	offsets:=[4]grid.Position{{x = -1, y = 0},{x = 1, y = 0},{x = 0, y = -1},{x = 0, y = 1}}
	for y in 0..<height {for x in 0..<width {
		pixel:=&cache.pixels[y*width+x]
		if pixel.r&7==u8(level.Tile_Kind.Void) {continue}
		for d,i in offsets {
			nx,ny:=x+d.x,y+d.y;outside:=nx<0 || ny<0 || nx>=width || ny>=height
			adjacent:=rl.Color{} if outside else cache.pixels[ny*width+nx]
			if outside || adjacent.r&7==u8(level.Tile_Kind.Void) {pixel.a|=u8(1<<uint(i))}
			if adjacent.r&7==u8(level.Tile_Kind.Wall) {pixel.r|=u8(8<<uint(i))}
			if pixel.g&15!=adjacent.g&15 {pixel.g|=u8(16<<uint(i))}
			if pixel.b&15==u8(world.Site_Surface.Platform) &&
				(outside || adjacent.b&15!=u8(world.Site_Surface.Platform)) {pixel.a|=u8(16<<uint(i))}
		}
		pixel.b|=expedition_floor_slab_variant({x = x, y = y})<<4
	}}
	cache.ready=true;cache.rebuilds+=1
	return true
}

@(private)
destroy_expedition_floor_data :: proc(cache:^Expedition_Floor_Data) {
	if cache==nil {return}
	delete(cache.pixels);cache^={}
}
