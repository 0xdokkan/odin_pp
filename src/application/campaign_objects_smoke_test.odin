package application

import "core:testing"
import game "../game"
import level "../level"
import run "../run"

// Validate the exact gallery setups without opening a window or touching GL.
// Both pre-redesign and proposed renderers use the same native fixture file.
@(test)
test_objects_smoke_places_every_gallery_fixture_and_keeps_actor_probe_legal :: proc(t:^testing.T) {
	e:=new(run.Expedition_Session);e.rs=new(run.Roguelike_Session)
	defer {
		game.destroy_room(&e.rs.room);level.destroy(&e.rs.level_data)
		free(e.rs);free(e)
	}
	e.rs.run_seed=20261103
	for actors in ([2]bool{false,true}) {
		for stage in 0..<(6 if actors else 60) {
			s:=Objects_Capture{stage=stage,actor_shadow=actors}
			objects_smoke_prepare(&s,e)
			testing.expect_value(t,len(e.rs.level_data.structures),0 if actors else 1)
			testing.expect(t,!game.cell_blocks_movement(&e.rs.room,e.rs.room.player.position))
			testing.expect_value(t,e.rs.room.phase,game.Room_Phase.Loot)
			testing.expect_value(t,len(e.rs.room.enemies),6 if actors else 0)
			if actors {
				testing.expect(t,s.walker.x>=23.3 && s.walker.y>18 && s.walker.y<22)
				for enemy in e.rs.room.enemies {testing.expect(t,enemy.health==20)}
				for y in 16..=24 {testing.expect(t,game.cell_blocks_movement(&e.rs.room,{x=22,y=y}))}
			}
		}
	}
}
