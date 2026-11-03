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

// BENVENUTI A NAPOLI's views (Fasi 2 and 4) stay in an expedition's save as
// they stood: the club's blow and memory, the grandpa's body, health and keys.
@(test)
test_expedition_snapshot_keeps_the_club_and_the_grandpa :: proc(t:^testing.T) {
	for weapon in ([2]game.First_Person_Weapon{.Club, .Nonno}) {
		w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
		p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
		testing.expect(t,game.tactical_begin_first_person(&room,30,weapon))
		if weapon == .Club {
			room.first_person.club.blow={active = true, way = {1, 0}, from = room.player.position, at = 0.1}
			room.first_person.club.memory[0]={enemy_id = 3, count = 1, quiet = 0.5}
		} else {
			room.first_person.nonno.health,room.first_person.nonno.healed=11,true
		}
		snapshot:=new(Snapshot)
		testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
		w2:World;data2:level.Level;p2:game.Player;room2:game.Room
		testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2))
		testing.expect(t,room2.first_person.active && room2.first_person.weapon == weapon)
		if weapon == .Club { testing.expect(t,room2.first_person.club == room.first_person.club) }
		else { testing.expect(t,room2.first_person.nonno == room.first_person.nonno && room2.first_person.fists.body == room.first_person.fists.body) }
		free(snapshot)
		level.destroy(&data2);game.destroy_room(&room2)
		level.destroy(&data);game.destroy_room(&room)
	}
}
