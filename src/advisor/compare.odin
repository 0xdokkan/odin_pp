package advisor

import "base:runtime"
import "core:fmt"
import "core:mem"
import game "../game"

// Whether two rooms hold the same game, field by field (core reflection over the types): the room's own fields, its
// player and level through their pointers, its lists element by element. Left out: the event log and its allocator
// (a copy's log is its own), and the foes' distance field (a scratch table the planning rewrites before reading it).
// `where_` names the first field that differs. The tests of the copy and of the simulator use it.
rooms_equal :: proc(a, b: ^game.Room) -> (equal: bool, where_: string) {
	if a == nil || b == nil { return a == b, "a room is nil" }
	return values_equal(a, b, type_info_of(game.Room), "room")
}

@(private)
skipped_field :: proc(name: string) -> bool {
	return name == "recent_events" || name == "event_allocator" || name == "enemy_path_distances"
}

@(private)
values_equal :: proc(a, b: rawptr, info: ^runtime.Type_Info, path: string) -> (bool, string) {
	base := runtime.type_info_base(info)
	switch v in base.variant {
	case runtime.Type_Info_Struct:
		if .raw_union in v.flags { return mem.compare_byte_ptrs((^byte)(a), (^byte)(b), base.size) == 0, path }
		for i in 0..<v.field_count {
			name := v.names[i]
			if skipped_field(name) { continue }
			offset := v.offsets[i]
			field_a := rawptr(uintptr(a)+offset)
			field_b := rawptr(uintptr(b)+offset)
			if equal, at := values_equal(field_a, field_b, v.types[i], fmt.tprintf("%s.%s", path, name)); !equal { return false, at }
		}
		return true, ""
	case runtime.Type_Info_Array:
		for i in 0..<v.count {
			offset := uintptr(i*v.elem_size)
			if equal, at := values_equal(rawptr(uintptr(a)+offset), rawptr(uintptr(b)+offset), v.elem, fmt.tprintf("%s[%d]", path, i)); !equal { return false, at }
		}
		return true, ""
	case runtime.Type_Info_Enumerated_Array:
		for i in 0..<v.count {
			offset := uintptr(i*v.elem_size)
			if equal, at := values_equal(rawptr(uintptr(a)+offset), rawptr(uintptr(b)+offset), v.elem, fmt.tprintf("%s[%d]", path, i)); !equal { return false, at }
		}
		return true, ""
	case runtime.Type_Info_Dynamic_Array:
		da, db := (^runtime.Raw_Dynamic_Array)(a), (^runtime.Raw_Dynamic_Array)(b)
		if da.len != db.len { return false, fmt.tprintf("%s (len %d, %d)", path, da.len, db.len) }
		for i in 0..<da.len {
			offset := uintptr(i*v.elem_size)
			if equal, at := values_equal(rawptr(uintptr(da.data)+offset), rawptr(uintptr(db.data)+offset), v.elem, fmt.tprintf("%s[%d]", path, i)); !equal { return false, at }
		}
		return true, ""
	case runtime.Type_Info_Slice:
		sa, sb := (^runtime.Raw_Slice)(a), (^runtime.Raw_Slice)(b)
		if sa.len != sb.len { return false, fmt.tprintf("%s (len %d, %d)", path, sa.len, sb.len) }
		size := sa.len*v.elem_size
		if size > 0 && mem.compare_byte_ptrs((^byte)(sa.data), (^byte)(sb.data), size) != 0 { return false, path }
		return true, ""
	case runtime.Type_Info_Pointer:
		// The player's and the level's: followed (both are structs); none other is left once the log is skipped.
		pa, pb := (^rawptr)(a)^, (^rawptr)(b)^
		if _, is_struct := runtime.type_info_base(v.elem).variant.(runtime.Type_Info_Struct); is_struct {
			if pa == nil || pb == nil { return pa == pb, path }
			return values_equal(pa, pb, v.elem, fmt.tprintf("%s^", path))
		}
		return true, ""
	case runtime.Type_Info_String:
		return (^string)(a)^ == (^string)(b)^, path
	case runtime.Type_Info_Named, runtime.Type_Info_Integer, runtime.Type_Info_Rune, runtime.Type_Info_Float, runtime.Type_Info_Complex,
	     runtime.Type_Info_Quaternion, runtime.Type_Info_Boolean, runtime.Type_Info_Enum, runtime.Type_Info_Bit_Set, runtime.Type_Info_Bit_Field,
	     runtime.Type_Info_Matrix, runtime.Type_Info_Simd_Vector:
		return mem.compare_byte_ptrs((^byte)(a), (^byte)(b), base.size) == 0, path
	case runtime.Type_Info_Union:
		return mem.compare_byte_ptrs((^byte)(a), (^byte)(b), base.size) == 0, path
	case runtime.Type_Info_Any, runtime.Type_Info_Type_Id, runtime.Type_Info_Multi_Pointer, runtime.Type_Info_Procedure, runtime.Type_Info_Parameters,
	     runtime.Type_Info_Map, runtime.Type_Info_Soa_Pointer, runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
		return true, ""
	}
	return true, ""
}
