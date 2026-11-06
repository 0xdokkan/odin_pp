package expedition

import "core:slice"
import "core:testing"
import game "../game"
import level "../level"

// NIDO DI RAGNI (game/spider_nest.odin, docs/piano-ia.md, Fase 9) stays in an expedition's save as it stood: the nest
// with its seconds and its bite, the spiderlings on their way.
@(test)
test_expedition_snapshot_keeps_the_nest_and_its_spiders :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	nest:=game.Grid_Object{id = room.next_object_id, kind = .Spider_Nest, position = {x = p.position.x, y = p.position.y-1}, power = 3, life = 14}
	room.next_object_id+=1;append(&room.objects,nest)
	p.tactical.spiders.items[0]={position = nest.position, from = nest.position, travelled = 0.5, age = 1.5, bite = 3, nest = nest.id}
	p.tactical.spiders.count,p.tactical.spiders.pending=1,0.25
	snapshot:=new(Snapshot);defer { snapshot_destroy(snapshot); free(snapshot) }
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect(t,slice.equal(room2.objects[:],room.objects[:]))
	testing.expect(t,p2.tactical.spiders == p.tactical.spiders)
}
