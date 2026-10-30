package level

// THE CATALOG OF STRUCTURES (Fase 6 of docs/piano-griglia.md): three buildings, five
// complex objects and a pen, each a plan of characters (see structure.odin for the
// legend). Every plan is checked in every turn it allows by the tests.

Structure_Id :: enum u8 {
	Cottage,
	Hut,
	Temple,
	Cart,
	Fountain,
	Statue,
	Machine,
	Ruin,
	Pen,
	Count,
}

Structure_Definition :: struct {
	id:        Structure_Id,
	name:      string,
	kind:      Structure_Kind,
	rows:      []string,
	// The quarter turns and the mirror it may be placed in.
	rotations: Rotation_Set,
	mirror:    bool,
}

ALL_ROTATIONS :: Rotation_Set{.Quarter_0, .Quarter_1, .Quarter_2, .Quarter_3}

// The plans live in globals so the definitions' rows stay valid after the call returns.
@(rodata) COTTAGE_ROWS := [?]string{"####", "#..#", "##+#"}
@(rodata) HUT_ROWS := [?]string{"#####", "#...#", "#...#", "##+##"}
@(rodata) TEMPLE_ROWS := [?]string{"#=====#", "=.....=", "=.#*#.=", "=.....=", "=.....=", "=.....=", "###+###"}
@(rodata) CART_ROWS := [?]string{"=="}
@(rodata) FOUNTAIN_ROWS := [?]string{"==", "=="}
@(rodata) STATUE_ROWS := [?]string{"##", "##"}
@(rodata) MACHINE_ROWS := [?]string{"###", "###"}
@(rodata) RUIN_ROWS := [?]string{"#  ", "#= ", "###"}
@(rodata) PEN_ROWS := [?]string{"=====", "=...=", "=...=", "==+=="}

structure_definition :: proc(id: Structure_Id) -> Structure_Definition {
	switch id {
	case .Cottage:
		// 4 by 3: a cottage with one room.
		return {id, "Casetta", .Building, COTTAGE_ROWS[:], ALL_ROTATIONS, true}
	case .Hut:
		// 5 by 4: a hut with a bigger room.
		return {id, "Capanna", .Building, HUT_ROWS[:], ALL_ROTATIONS, true}
	case .Temple:
		// 7 by 7: a colonnade round a courtyard, an altar in the middle, a gate.
		return {id, "Tempietto", .Building, TEMPLE_ROWS[:], ALL_ROTATIONS, true}
	case .Cart:
		// 2 by 1: low enough to see over, too wide to step over.
		return {id, "Carro", .Object, CART_ROWS[:], ALL_ROTATIONS, true}
	case .Fountain:
		// 2 by 2: its rim stops the step, not the sight.
		return {id, "Fontana", .Object, FOUNTAIN_ROWS[:], ALL_ROTATIONS, false}
	case .Statue:
		// 2 by 2: the plinth stops both.
		return {id, "Statua", .Object, STATUE_ROWS[:], ALL_ROTATIONS, false}
	case .Machine:
		// 3 by 2.
		return {id, "Macchinario", .Object, MACHINE_ROWS[:], ALL_ROTATIONS, true}
	case .Ruin:
		// An L in a 3 by 3: two arms of wall, a broken low piece between them.
		return {id, "Rovina", .Object, RUIN_ROWS[:], ALL_ROTATIONS, true}
	case .Pen:
		// 5 by 4: a fence round a yard, a gate in one side.
		return {id, "Recinto", .Object, PEN_ROWS[:], ALL_ROTATIONS, true}
	case .Count:
	}
	return {}
}

// The structures that are buildings: the ones that fade as the robot comes near.
structure_is_building :: proc(id: Structure_Id) -> bool {
	return structure_definition(id).kind == .Building
}
