package expedition

import "core:testing"
import game "../game"
import level "../level"

// LANCIAFIAMME (game/first_person_flame.odin, docs/piano-ia.md, Fase 13) stays in an expedition's save as it stood: its
// seconds, its aim, its pieces of flame and whom it touched.
@(test)
test_expedition_snapshot_keeps_the_flame :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	testing.expect(t,game.tactical_begin_first_person(&room,12,.Flamethrower))
	f:=&room.first_person.flame
	f.yaw,f.head,f.hits=1.25,7,2
	f.pieces[7]={x = 3.5, y = 4.5, way = 1.25, alive = true}
	f.memory[0]={enemy_id = 3, wait = 1.5}
	snapshot:=new(Snapshot);defer { snapshot_destroy(snapshot); free(snapshot) }
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect(t,game.first_person_flame_active(&room2))
	testing.expect(t,room2.first_person.flame==room.first_person.flame)
}
