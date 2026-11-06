package expedition

import "core:slice"
import "core:testing"
import game "../game"
import level "../level"

// REGINA (game/queen.odin, docs/piano-ia.md, Fase 11) stays in an expedition's save as she stood: where, her blow, her
// seconds, and her wait before the next blow.
@(test)
test_expedition_snapshot_keeps_the_queen :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	queen:=game.Grid_Object{id = room.next_object_id, kind = .Queen, position = {x = p.position.x, y = p.position.y-1}, power = 5, life = 11}
	room.next_object_id+=1;append(&room.objects,queen)
	p.tactical.queen_wait=1.25
	snapshot:=new(Snapshot);defer { snapshot_destroy(snapshot); free(snapshot) }
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect(t,slice.equal(room2.objects[:],room.objects[:]))
	testing.expect_value(t,p2.tactical.queen_wait,f32(1.25))
}
