package campaign

import "base:runtime"
import "core:mem"
import "core:reflect"

// Only serialization data crosses the save worker boundary. Containers are
// copied recursively; executable pointers, maps and opaque ownership are refused.
@(private)
Save_Ownership :: enum { Plain, Owned, Unsupported }

MAX_SAVED_OWNED_BYTES :: 256*mem.Megabyte

@(private)
save_owned_heap_fits :: proc(data: rawptr, info: ^reflect.Type_Info, remaining: ^int) -> bool {
	if save_ownership(info) == .Plain { return true }
	ti := reflect.type_info_base(info)
	#partial switch v in ti.variant {
	case reflect.Type_Info_Struct:
		for field, i in v.types[:v.field_count] {
			if !save_owned_heap_fits(rawptr(uintptr(data)+v.offsets[i]), field, remaining) { return false }
		}
	case reflect.Type_Info_Array:
		for i in 0..<v.count { if !save_owned_heap_fits(rawptr(uintptr(data)+uintptr(i*v.elem_size)), v.elem, remaining) { return false } }
	case reflect.Type_Info_Enumerated_Array:
		for i in 0..<v.count { if !save_owned_heap_fits(rawptr(uintptr(data)+uintptr(i*v.elem_size)), v.elem, remaining) { return false } }
	case reflect.Type_Info_Dynamic_Array:
		a := cast(^runtime.Raw_Dynamic_Array)data
		if !save_owned_array_fits(a.data, a.len, v.elem, remaining) { return false }
	case reflect.Type_Info_Slice:
		a := cast(^runtime.Raw_Slice)data
		if !save_owned_array_fits(a.data, a.len, v.elem, remaining) { return false }
	case reflect.Type_Info_String:
		a := cast(^runtime.Raw_String)data
		if a.len < 0 || a.len > remaining^ { return false }; remaining^ -= a.len
	case: return false
	}
	return true
}

@(private)
save_owned_array_fits :: proc(data: rawptr, count: int, elem: ^reflect.Type_Info, remaining: ^int) -> bool {
	if count < 0 || count > remaining^/max(elem.size, 1) { return false }
	remaining^ -= count*elem.size
	if save_ownership(elem) == .Plain { return true }
	for i in 0..<count { if !save_owned_heap_fits(rawptr(uintptr(data)+uintptr(i*elem.size)), elem, remaining) { return false } }
	return true
}

@(private)
save_owned_fits :: proc(value: ^$T, limit: int = MAX_SAVED_OWNED_BYTES) -> bool {
	if limit < size_of(T) || save_ownership(type_info_of(T)) == .Unsupported { return false }
	remaining := limit-size_of(T)
	return save_owned_heap_fits(value, type_info_of(T), &remaining)
}

@(private)
save_ownership :: proc(info: ^reflect.Type_Info, depth: int = 0) -> Save_Ownership {
	if depth > 64 { return .Unsupported }
	ti := reflect.type_info_base(info)
	#partial switch v in ti.variant {
	case reflect.Type_Info_Pointer, reflect.Type_Info_Multi_Pointer, reflect.Type_Info_Procedure,
		reflect.Type_Info_Any, reflect.Type_Info_Map, reflect.Type_Info_Type_Id: return .Unsupported
	case reflect.Type_Info_String:
		return .Owned if !v.is_cstring && v.encoding == .UTF_8 else .Unsupported
	case reflect.Type_Info_Dynamic_Array:
		return .Owned if save_ownership(v.elem, depth+1) != .Unsupported else .Unsupported
	case reflect.Type_Info_Slice:
		return .Owned if save_ownership(v.elem, depth+1) != .Unsupported else .Unsupported
	case reflect.Type_Info_Array:
		return save_ownership(v.elem, depth+1)
	case reflect.Type_Info_Enumerated_Array:
		return save_ownership(v.elem, depth+1)
	case reflect.Type_Info_Struct:
		if .raw_union in v.flags || v.soa_kind != .None { return .Unsupported }
		result := Save_Ownership.Plain
		for field in v.types[:v.field_count] {
			kind := save_ownership(field, depth+1)
			if kind == .Unsupported { return kind }
			if kind == .Owned { result = .Owned }
		}
		return result
	case reflect.Type_Info_Union:
		for variant in v.variants { if save_ownership(variant, depth+1) != .Plain { return .Unsupported } }
		return .Plain
	case: return .Plain
	}
}

@(private)
save_clone_elements :: proc(dst, src: rawptr, count: int, elem: ^reflect.Type_Info, allocator: mem.Allocator) -> bool {
	if save_ownership(elem) == .Plain { mem.copy(dst, src, count*elem.size); return true }
	for i in 0..<count {
		if !save_clone_value(rawptr(uintptr(dst)+uintptr(i*elem.size)), rawptr(uintptr(src)+uintptr(i*elem.size)), elem, allocator) { return false }
	}
	return true
}

// dst starts zero. On failure it contains only zeroes, plain fields and owned
// allocations, so the caller can destroy a partial clone without touching src.
@(private)
save_clone_value :: proc(dst, src: rawptr, info: ^reflect.Type_Info, allocator: mem.Allocator) -> bool {
	ti := reflect.type_info_base(info)
	if save_ownership(ti) == .Plain { mem.copy(dst, src, ti.size); return true }
	#partial switch v in ti.variant {
	case reflect.Type_Info_Struct:
		for field, i in v.types[:v.field_count] {
			if !save_clone_value(rawptr(uintptr(dst)+v.offsets[i]), rawptr(uintptr(src)+v.offsets[i]), field, allocator) { return false }
		}
	case reflect.Type_Info_Array:
		return save_clone_elements(dst, src, v.count, v.elem, allocator)
	case reflect.Type_Info_Enumerated_Array:
		return save_clone_elements(dst, src, v.count, v.elem, allocator)
	case reflect.Type_Info_Dynamic_Array:
		s, d := cast(^runtime.Raw_Dynamic_Array)src, cast(^runtime.Raw_Dynamic_Array)dst
		if s.len < 0 || s.len > max(int)/max(v.elem_size, 1) { return false }
		if s.len == 0 { return true }
		data, err := mem.alloc(s.len*v.elem_size, v.elem.align, allocator)
		if err != nil || data == nil { return false }
		d^ = {data = data, len = s.len, cap = s.len, allocator = allocator}
		return save_clone_elements(data, s.data, s.len, v.elem, allocator)
	case reflect.Type_Info_Slice:
		s, d := cast(^runtime.Raw_Slice)src, cast(^runtime.Raw_Slice)dst
		if s.len < 0 || s.len > max(int)/max(v.elem_size, 1) { return false }
		if s.len == 0 { return true }
		data, err := mem.alloc(s.len*v.elem_size, v.elem.align, allocator)
		if err != nil || data == nil { return false }
		d^ = {data = data, len = s.len}
		return save_clone_elements(data, s.data, s.len, v.elem, allocator)
	case reflect.Type_Info_String:
		s, d := cast(^runtime.Raw_String)src, cast(^runtime.Raw_String)dst
		if s.len == 0 { return true }
		data, err := mem.alloc(s.len, 1, allocator)
		if err != nil || data == nil { return false }
		mem.copy(data, s.data, s.len); d^ = {cast([^]u8)data, s.len}
	case: return false
	}
	return true
}

@(private)
save_destroy_elements :: proc(data: rawptr, count: int, elem: ^reflect.Type_Info, allocator: mem.Allocator) {
	if save_ownership(elem) != .Owned { return }
	for i in 0..<count { save_destroy_value(rawptr(uintptr(data)+uintptr(i*elem.size)), elem, allocator) }
}

@(private)
save_destroy_value :: proc(data: rawptr, info: ^reflect.Type_Info, allocator: mem.Allocator) {
	ti := reflect.type_info_base(info)
	if save_ownership(ti) != .Owned { return }
	#partial switch v in ti.variant {
	case reflect.Type_Info_Struct:
		for field, i in v.types[:v.field_count] { save_destroy_value(rawptr(uintptr(data)+v.offsets[i]), field, allocator) }
	case reflect.Type_Info_Array:
		save_destroy_elements(data, v.count, v.elem, allocator)
	case reflect.Type_Info_Enumerated_Array:
		save_destroy_elements(data, v.count, v.elem, allocator)
	case reflect.Type_Info_Dynamic_Array:
		a := cast(^runtime.Raw_Dynamic_Array)data
		save_destroy_elements(a.data, a.len, v.elem, a.allocator)
		mem.free(a.data, a.allocator); a^ = {}
	case reflect.Type_Info_Slice:
		a := cast(^runtime.Raw_Slice)data
		save_destroy_elements(a.data, a.len, v.elem, allocator)
		mem.free(a.data, allocator); a^ = {}
	case reflect.Type_Info_String:
		a := cast(^runtime.Raw_String)data
		mem.free(a.data, allocator); a^ = {}
	case:
	}
}

// A destination for cloning must be empty. Slices/strings passed to destroy
// must come from allocator; dynamic arrays retain their own allocator.
@(private)
save_clone_owned :: proc(dst, src: ^$T, allocator := context.allocator) -> bool {
	if !save_owned_fits(src) { return false }
	dst^ = {}
	if save_clone_value(dst, src, type_info_of(T), allocator) { return true }
	save_destroy_value(dst, type_info_of(T), allocator); dst^ = {}
	return false
}

@(private)
save_destroy_owned :: proc(value: ^$T, allocator := context.allocator) {
	save_destroy_value(value, type_info_of(T), allocator)
	value^ = {}
}
