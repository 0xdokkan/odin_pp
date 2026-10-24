package campaign

import "core:testing"
import level "../level"

// A structure's kit is an item of its own: named for the structure, valid for every structure of the catalog and no other, a building's
// two cells and an object's one, and spent from the backpack when it is set down.
@(test)
test_a_structure_kit_is_an_item_named_for_its_structure_and_spent_once :: proc(t: ^testing.T) {
	for id in level.Structure_Id {
		if id == .Count { continue }
		item := make_item(.Structure_Kit, 1, i32(id))
		testing.expect(t, item_valid(item))
		testing.expect_value(t, item_name(item), level.structure_definition(id).name)
		testing.expect(t, len(item_description(item)) > 0)
		shape := item_shape(item)
		testing.expect_value(t, shape.count, 2 if level.structure_definition(id).kind == .Building else 1)
	}
	testing.expect(t, !item_valid(make_item(.Structure_Kit, 1, i32(level.Structure_Id.Count))))
	testing.expect(t, !item_valid(make_item(.Structure_Kit, 1, -1)))
	testing.expect(t, !item_valid(make_item(.Structure_Kit, 2, 0)), "one kit to a cell")
	// The object's kit says the enemies break it; the building's, that it stays.
	testing.expect(t, item_description(make_item(.Structure_Kit, 1, i32(level.Structure_Id.Cart))) != item_description(make_item(.Structure_Kit, 1, i32(level.Structure_Id.Cottage))))
	bag := make_backpack()
	testing.expect(t, grid_add(&bag.grid, make_item(.Structure_Kit, 1, i32(level.Structure_Id.Statue))))
	testing.expect(t, grid_add(&bag.grid, make_item(.Structure_Kit, 1, i32(level.Structure_Id.Cart))))
	testing.expect(t, !spend_structure_kit(&bag, i32(level.Structure_Id.Fountain)), "no such kit")
	testing.expect(t, spend_structure_kit(&bag, i32(level.Structure_Id.Cart)))
	testing.expect_value(t, bag.grid.count, 1)
	testing.expect(t, !spend_structure_kit(&bag, i32(level.Structure_Id.Cart)), "spent once")
	testing.expect(t, spend_structure_kit(&bag, i32(level.Structure_Id.Statue)))
	testing.expect(t, !spend_structure_kit(nil, 0))
}
