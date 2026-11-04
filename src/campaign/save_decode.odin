package campaign

import "core:encoding/json"
import "core:mem"
import "core:reflect"
import "core:strings"

// The pinned JSON decoder allocates sizeof(struct)/8 bytes on the stack for
// every object key, retaining them until the object is complete. A layered
// expedition snapshot exceeds the default 8 MiB stack despite living on the
// heap. Walk large structs one field at a time; keep the library's decoding of
// scalars, arrays, small structs and schema defaults, without global hooks.
@(private)
decode_save :: proc(bytes: []u8, value: ^$T, allocator: mem.Allocator) -> json.Unmarshal_Error {
	if !json.is_valid(bytes, parse_integers = true) { return .Invalid_Data }
	p := json.make_parser(bytes, parse_integers = true, allocator = allocator)
	context.allocator = allocator
	return decode_save_value(&p, any{value, typeid_of(T)})
}

@(private)
decode_save_value :: proc(p: ^json.Parser, value: any) -> json.Unmarshal_Error {
	ti := reflect.type_info_base(type_info_of(value.id))
	structure, is_struct := ti.variant.(reflect.Type_Info_Struct)
	if !is_struct || ti.size < 64*1024 || .raw_union in structure.flags || p.curr_token.kind != .Open_Brace {
		return json.unmarshal_value(p, value)
	}
	if err := json.expect_token(p, .Open_Brace); err != nil { return err }
	seen := make(map[uintptr]bool, allocator = p.allocator)
	defer delete(seen)
	for p.curr_token.kind != .Close_Brace {
		key, key_err := json.parse_object_key(p, p.allocator)
		if key_err != nil { return key_err }
		defer delete(key, p.allocator)
		if err := json.expect_token(p, .Colon); err != nil { return err }
		if field := save_json_field(value, key); field != nil {
			offset := uintptr(field.data)-uintptr(value.data)
			if seen[offset] { return .Multiple_Use_Field }
			seen[offset] = true
			if err := decode_save_value(p, field); err != nil { return err }
		} else {
			// Match the library's unknown-field handling without retaining its
			// strings or building a second tree for a future schema's payload.
			allocator := p.allocator
			skip := p^
			skip.allocator = mem.nil_allocator()
			_, err := json.parse_value(&skip)
			if err != nil { return err }
			p^ = skip
			p.allocator = allocator
		}
		if json.parse_comma(p) { break }
	}
	if err := json.expect_token(p, .Close_Brace); err != nil { return err }
	return nil
}

@(private)
save_json_field :: proc(value: any, key: string) -> any {
	fields := reflect.struct_fields_zipped(value.id)
	for field in fields {
		name := reflect.struct_tag_get(field.tag, "json")
		if comma := strings.index_byte(name, ','); comma >= 0 { name = name[:comma] }
		if name == "" { name = field.name }
		if name == key { return reflect.struct_field_value(value, field) }
	}
	for field in fields {
		if field.is_using && field.name == "_" {
			if nested := save_json_field(reflect.struct_field_value(value, field), key); nested != nil {
				return nested
			}
		}
	}
	return nil
}
