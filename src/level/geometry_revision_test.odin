package level

import "core:testing"

@(test)
test_level_geometry_revision_tracks_mutations_and_lifetime :: proc(t:^testing.T) {
	data,ok:=create(4,4,{.Floor});testing.expect(t,ok)
	defer destroy(&data)
	initial:=data.geometry_revision;identity:=data.geometry_id
	testing.expect(t,identity!=0 && initial!=0)
	testing.expect(t,set_tile(&data,{1,1},{.Floor}))
	testing.expect_value(t,data.geometry_revision,initial)
	testing.expect(t,!set_tile(&data,{-1,1},{.Wall}))
	testing.expect_value(t,data.geometry_revision,initial)
	testing.expect(t,set_tile(&data,{1,1},{.Wall}))
	testing.expect_value(t,data.geometry_revision,initial+1)
	data.tiles.cells[0]={.Door};mark_geometry_changed(&data)
	testing.expect_value(t,data.geometry_revision,initial+2)
	destroy(&data)
	data,ok=create(4,4,{.Floor});testing.expect(t,ok)
	testing.expect(t,data.geometry_id!=identity)
	testing.expect_value(t,data.geometry_revision,u64(1))
}
