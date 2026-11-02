package expedition

import "core:slice"
import "core:testing"
import game "../game"
import level "../level"

// BENVENUTI A NAPOLI's table (game/napoli.odin, docs/piano-napoli.md, Fase 1)
// stays in an expedition's save as it stood: where, its cure, and the meal's
// beats left if the player sat at it.
@(test)
test_expedition_snapshot_keeps_the_grandpas_table :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	table:=game.Grid_Object{id = room.next_object_id, kind = .Napoli_Table, position = {x = p.position.x, y = p.position.y-1}, power = 16, life = 1}
	room.next_object_id+=1;append(&room.objects,table)
	snapshot:=new(Snapshot);defer free(snapshot)
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect(t,slice.equal(room2.objects[:],room.objects[:]))
	index,found:=game.napoli_table_index(&room2)
	testing.expect(t,found && room2.objects[index].power==16 && game.napoli_seated(&room2))
}
