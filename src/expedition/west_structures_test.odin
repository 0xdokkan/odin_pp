package expedition

import "core:os"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Exercise the real slot serializer, loader and restore path. The checkpoint
// is taken inside the new hut, so restored plan ownership must agree with
// saved player position as well as the world's structure list.
@(test)
test_west_buildings_survive_slot_save_load_and_restore_inside_the_hut :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player
	room:=test_world(t,&w,&data,&p,.West)
	defer level.destroy(&data);defer game.destroy_room(&room)
	testing.expect_value(t,w.structure_count,2)
	if w.structure_count!=2 {return}
	inside:=false
	for y in 0..<data.structure_plans[0].height {for x in 0..<data.structure_plans[0].width {
		if level.plan_at(&data.structure_plans[0],x,y)==.Floor && !inside {
			p.position=grid.offset(data.structures[0].origin,x,y);inside=true
		}
	}}
	testing.expect(t,inside)
	checkpoint:=new(Snapshot);defer { snapshot_destroy(checkpoint); free(checkpoint) }
	testing.expect(t,capture(&w,&room,checkpoint) && valid_snapshot(checkpoint))
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	c.unlocked[int(campaign.Biome.West)]=true;testing.expect(t,campaign.begin_run(&c,.West,w.seed))
	path:=scratch_path("odin-pp-west-buildings-checkpoint.json");defer os.remove(path)
	testing.expect(t,campaign.save_slot_from(path,&c,checkpoint))
	loaded:campaign.Campaign;defer campaign.destroy(&loaded)
	read_back:=new(Snapshot);defer { snapshot_destroy(read_back); free(read_back) }
	testing.expect_value(t,campaign.load_slot_into(path,&loaded,read_back),campaign.Load_Status.Loaded)
	testing.expect(t,valid_snapshot(read_back))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(read_back,&w2,&data2,&p2,&room2))
	defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect_value(t,w2.structure_count,2)
	testing.expect_value(t,level.structure_count(&data2),2)
	testing.expect_value(t,p2.position,p.position)
	for placed,i in data.structures {
		testing.expect_value(t,data2.structures[i],placed)
		testing.expect_value(t,data2.structure_plans[i],data.structure_plans[i])
	}
	for tile,i in data.tiles.cells {testing.expect_value(t,data2.tiles.cells[i],tile)}
	for height,i in data.heights {testing.expect_value(t,data2.heights[i],height)}
	owner,owned:=level.structure_index_at(&data2,p2.position)
	testing.expect(t,owned && data2.structures[owner].id==.Hut)
	visibility:=game.structure_visibility(&data2,owner,{f32(p2.position.x)+.5,f32(p2.position.y)+.5})
	testing.expect(t,visibility.inside && !visibility.roof)
}
