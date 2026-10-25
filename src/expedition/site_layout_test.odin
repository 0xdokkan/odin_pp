package expedition

import "core:testing"
import "core:fmt"
import campaign "../campaign"
import grid "../engine/grid"
import level "../level"

@(test)
test_authored_sites_have_reachable_wide_entrances_cover_and_safe_spawns :: proc(t:^testing.T) {
	for kind in Site_Kind {for orientation in u8(0)..<4 {
		// A cave's arch is a few cells of rock, not a courtyard (cave_test.odin).
		if kind==.Cave {continue}
		site:=Site{kind=kind,position={x = 40, y = 40},orientation=orientation,layout_version=SITE_LAYOUT_VERSION}
		d:=site_layout(kind);minimum,maximum:=site_bounds(&site)
		testing.expect(t,d.half_extent.x>=10 && d.half_extent.y>=10 && d.half_extent.x<=14 && d.half_extent.y<=14)
		start:=site_world(&site,{x = -1, y = 0})
		seen:[81*81]bool;queue:[81*81]grid.Position;head,tail:=0,1;queue[0]=start;seen[start.y*81+start.x]=true
		for head<tail {
			p:=queue[head];head+=1
			for offset in ([4]grid.Position{{x = 0, y = -1},{x = 1, y = 0},{x = 0, y = 1},{x = -1, y = 0}}) {
				q:=grid.offset(p, offset.x, offset.y);c:=site_cell(&site,q)
				if !c.inside || c.wall || seen[q.y*81+q.x] {continue}
				seen[q.y*81+q.x]=true;queue[tail]=q;tail+=1
			}
		}
		walls:=0;walkable:=0
		for y in minimum.y..=maximum.y {for x in minimum.x..=maximum.x {
			c:=site_cell(&site,{x = x, y = y});if c.wall {walls+=1}else {walkable+=1;testing.expect(t,seen[y*81+x])}
		}}
		testing.expect(t,walls>=12 && walls<walkable/2)
		for entrance in d.entrances[:d.entrance_count] {
			for shift in -1..=1 {
				local:=grid.offset(entrance, 0, shift) if abs(entrance.x)>abs(entrance.y) else grid.offset(entrance, shift, 0)
				p:=site_world(&site,local);testing.expect(t,seen[p.y*81+p.x] && !site_cell(&site,p).wall)
			}
		}
		for wave in 0..<d.spawn_count {for member in 0..<MAX_MEMBERS {
			p:=site_spawn_position(&site,wave,member);c:=site_cell(&site,p)
			testing.expect(t,c.inside && !c.wall && seen[p.y*81+p.x])
		}}
		decor:=site_decor_anchors(&site)
		for anchor in decor.items[:decor.count] {if anchor.kind==.Gatepost {testing.expect(t,site_cell(&site,anchor.position).wall)}}
	}}
}

@(test)
test_authored_geometry_matches_semantics_in_all_biomes_and_preserves_spawn :: proc(t:^testing.T) {
	for biome in campaign.Biome {
		if biome==.Count {continue}
		w:World;data:level.Level;testing.expect(t,generate(&w,&data,biome,123));defer level.destroy(&data)
		testing.expect_value(t,size(&w),legacy_map_size(biome)*2)
		spawn,_:=level.tile_at(&data,data.player_spawn);testing.expect_value(t,spawn.kind,level.Tile_Kind.Player_Spawn)
		for &site in w.sites[:w.site_count] {
			minimum,maximum:=site_bounds(&site)
			testing.expect(t,minimum.x>=2 && minimum.y>=2 && maximum.x<size(&w)-2 && maximum.y<size(&w)-2)
			for y in minimum.y..=maximum.y {for x in minimum.x..=maximum.x {
				p:=grid.Position{x = x, y = y};cell:=site_cell(&site,p);tile,_:=level.tile_at(&data,p)
				testing.expect(t,(tile.kind==.Wall)==cell.wall,fmt.tprintf("Biome %v site %v at %v: wall query %v but tile %v",biome,site.kind,p,cell.wall,tile.kind))
			}}
		}
		for &group in w.groups[:w.group_count] {for member in group.members[:group.count] {
			// A cave's foes stand where its plan is stamped when the cave is entered, not on the open map.
			if group.cave>0 {continue}
			tile,present:=level.tile_at(&data,member.enemy.position);testing.expect(t,present && tile.kind!=.Wall && tile.kind!=.Void)
		}}
	}
}
