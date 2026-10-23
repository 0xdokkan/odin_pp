package expedition

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private)
roam_test_room :: proc(t:^testing.T,w:^World,data:^level.Level,p:^game.Player)->game.Room {
	room:=test_world(t,w,data,p,.Secret)
	for y in 18..=42 {for x in 18..=42 {_=level.set_tile(data,{x,y},{.Floor});_=level.set_height(data,{x,y},0)}}
	return room
}

@(private)
roam_walk :: proc(w:^World,room:^game.Room,r:^Roam,wish:[2]f32,seconds:f32) {
	for _ in 0..<int(seconds*60) {roam_step(w,room,r,wish,1.0/60)}
}

@(test)
test_roam_stops_at_walls_and_slides_along_their_seams :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=roam_test_room(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	for y in 18..=42 {_=level.set_tile(&data,{25,y},{.Wall})}
	p.position={22,30};r:Roam
	roam_walk(&w,&room,&r,{1,0},2)
	testing.expect(t,r.position.x<=25-ROAM_RADIUS+.001 && r.position.x>24.5)
	testing.expect_value(t,p.position,grid.Position{24,30})
	// Pressing diagonally into a wall of separate cells glides past every seam.
	roam_walk(&w,&room,&r,{.7071,.7071},2)
	testing.expect(t,r.position.y>34)
	testing.expect(t,r.position.x<=25-ROAM_RADIUS+.001)
	testing.expect_value(t,p.position,roam_cell(r.position))
}

@(test)
test_roam_cannot_squeeze_between_diagonal_blockers :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=roam_test_room(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	_=level.set_tile(&data,{30,30},{.Wall});_=level.set_tile(&data,{31,31},{.Wall})
	p.position={30,31};r:Roam
	roam_walk(&w,&room,&r,{.7071,-.7071},1)
	testing.expect_value(t,p.position,grid.Position{30,31})
	testing.expect(t,!game.cell_blocks_movement(&room,p.position))
}

@(test)
test_roam_enters_cells_through_the_trap_pipeline :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=roam_test_room(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	append(&room.traps,game.Trap{id=room.next_trap_id,position={27,30},damage=4,armed=true});room.next_trap_id+=1
	p.position={24,30};w.mounted=true;before:=p.health;r:Roam
	roam_walk(&w,&room,&r,{1,0},1.5)
	testing.expect(t,!room.traps[0].armed)
	testing.expect_value(t,p.health,before-4)
	testing.expect(t,!w.mounted)
}

@(test)
test_roam_adopts_external_moves_and_waits_during_encounters :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=roam_test_room(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={24,30};r:Roam
	roam_walk(&w,&room,&r,{0,1},.25)
	p.position={25,30}
	roam_step(&w,&room,&r,{},1.0/60)
	testing.expect_value(t,r.cell,grid.Position{25,30})
	testing.expect_value(t,roam_cell(r.position),grid.Position{25,30})
	testing.expect(t,r.offset!=[2]f32{})
	room.phase=.Combat
	roam_walk(&w,&room,&r,{1,0},.5)
	testing.expect_value(t,p.position,grid.Position{25,30})
	testing.expect_value(t,r.position,roam_center({25,30}))
}

@(test)
test_roam_mount_outpaces_walking :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=roam_test_room(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={19,22};r:Roam
	roam_walk(&w,&room,&r,{1,0},1)
	walked:=r.position.x
	p.position={19,26};w.mounted=true;mounted:Roam
	roam_walk(&w,&room,&mounted,{1,0},1)
	testing.expect(t,mounted.position.x>walked+1.5)
	testing.expect(t,walked>19.5+ROAM_WALK_SPEED*.8)
}
