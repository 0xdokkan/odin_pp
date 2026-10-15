package render

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// A GPU handle, a pointer or a slice (a string, a dynamic array or a map too)
// under a renderer's view or its sprites, by its path ("tactical.art.icons",
// "sprite_assets.textures[3].alpha"); Unknown: a field the walk cannot see
// into (a union that may hold one of them, an any).
Effect_Stage_Field_Kind :: enum u8 {Handle, Pointer, Slice, Unknown}

Effect_Stage_Field :: struct {
	path: string,
	kind: Effect_Stage_Field_Kind,
	data: rawptr,
	size: int,
	elem: ^runtime.Type_Info,
}

// The kinds of GPU object raylib hands out.
EFFECT_STAGE_HANDLES :: [?]typeid{rl.Texture, rl.RenderTexture, rl.Shader, rl.Font, rl.Model, rl.Mesh, rl.Material}

// The borrowed renderer's pointers that are the main renderer's, not its own.
EFFECT_STAGE_SHARED_POINTERS :: [?]string{"sprite_assets.allocator.data"}

effect_stage_is_handle :: proc(id: typeid) -> bool {
	for handle in EFFECT_STAGE_HANDLES { if id == handle { return true } }
	return false
}

// Whether a type holds a handle, a pointer or a slice anywhere inline (the
// walk goes down only where one may be): a union if a variant does, an any
// always.
effect_stage_interesting :: proc(info: ^runtime.Type_Info, seen: ^map[typeid]bool) -> bool {
	if cached, found := seen[info.id]; found { return cached }
	seen[info.id] = false
	result := effect_stage_is_handle(info.id)
	if !result {
		base := reflect.type_info_base(info)
		#partial switch v in base.variant {
		case runtime.Type_Info_Struct:
			for field in reflect.struct_fields_zipped(info.id) { result = effect_stage_interesting(field.type, seen) || result }
		case runtime.Type_Info_Array: result = effect_stage_interesting(v.elem, seen)
		case runtime.Type_Info_Enumerated_Array: result = effect_stage_interesting(v.elem, seen)
		case runtime.Type_Info_Union:
			for variant in v.variants { result = effect_stage_interesting(variant, seen) || result }
		case runtime.Type_Info_Pointer, runtime.Type_Info_Multi_Pointer, runtime.Type_Info_Slice, runtime.Type_Info_String,
		     runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Map, runtime.Type_Info_Any, runtime.Type_Info_Soa_Pointer:
			result = true
		}
	}
	seen[info.id] = result
	return result
}

// Every handle, pointer and slice under `data` (of `info`), its path after
// `path`, through core:reflect's view of each struct; a handle is a whole
// (its own pointers are its own), a pointer is not followed.
effect_stage_walk :: proc(data: rawptr, info: ^runtime.Type_Info, path: ^[dynamic]u8, fields: ^[dynamic]Effect_Stage_Field, seen: ^map[typeid]bool) {
	if !effect_stage_interesting(info, seen) { return }
	record :: proc(fields: ^[dynamic]Effect_Stage_Field, path: ^[dynamic]u8, kind: Effect_Stage_Field_Kind, data: rawptr, size: int,
		elem: ^runtime.Type_Info = nil) {
		append(fields, Effect_Stage_Field{path = strings.clone(string(path[:])), kind = kind, data = data, size = size, elem = elem})
	}
	if effect_stage_is_handle(info.id) {
		record(fields, path, .Handle, data, info.size)
		return
	}
	mark := len(path)
	defer resize(path, mark)
	base := reflect.type_info_base(info)
	#partial switch v in base.variant {
	case runtime.Type_Info_Struct:
		for field in reflect.struct_fields_zipped(info.id) {
			resize(path, mark)
			if mark > 0 { append(path, ".") }
			append(path, field.name)
			effect_stage_walk(rawptr(uintptr(data)+field.offset), field.type, path, fields, seen)
		}
	case runtime.Type_Info_Array:
		for index in 0..<v.count {
			resize(path, mark)
			append(path, fmt.tprintf("[%d]", index))
			effect_stage_walk(rawptr(uintptr(data)+uintptr(index*v.elem_size)), v.elem, path, fields, seen)
		}
	case runtime.Type_Info_Enumerated_Array:
		for index in 0..<v.count {
			resize(path, mark)
			append(path, fmt.tprintf("[%d]", index))
			effect_stage_walk(rawptr(uintptr(data)+uintptr(index*v.elem_size)), v.elem, path, fields, seen)
		}
	case runtime.Type_Info_Pointer:
		record(fields, path, .Pointer, data, size_of(rawptr), v.elem)
	case runtime.Type_Info_Multi_Pointer:
		record(fields, path, .Pointer, data, size_of(rawptr), v.elem)
	case runtime.Type_Info_Slice, runtime.Type_Info_String, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Map:
		record(fields, path, .Slice, data, base.size)
	case runtime.Type_Info_Union, runtime.Type_Info_Any, runtime.Type_Info_Soa_Pointer:
		record(fields, path, .Unknown, data, base.size, info)
	}
}

// Every field of `renderer` the walk records, in a fixed order: a handle
// anywhere, and the slices, strings and pointers of its view and its sprites
// (where the assets are) and of the rest of it (its own state: the timeline's,
// the world playback).
effect_stage_fields :: proc(renderer: ^Renderer, fields: ^[dynamic]Effect_Stage_Field, seen: ^map[typeid]bool) {
	path: [dynamic]u8
	defer delete(path)
	effect_stage_walk(renderer, type_info_of(Renderer), &path, fields, seen)
}

// The view and the sprites hold the assets; a slice there is one of them.
effect_stage_asset_part :: proc(path: string) -> bool {
	return strings.has_prefix(path, "tactical.") || strings.has_prefix(path, "sprite_assets.")
}

effect_stage_bytes :: proc(field: Effect_Stage_Field) -> []u8 {
	return slice.bytes_from_ptr(field.data, field.size)
}

effect_stage_zero :: proc(field: Effect_Stage_Field) -> bool {
	for value in effect_stage_bytes(field) { if value != 0 { return false } }
	return true
}

effect_stage_listed :: proc(path: string, list: []string) -> bool {
	for listed in list { if listed == path { return true } }
	return false
}

// MOSTRA EFFETTO's board draws with the main renderer's assets and shows a
// state of its own. The test walks the whole main renderer through
// core:reflect and fills every GPU handle (texture, render texture, shader,
// font, model, mesh, material), every slice, string and map and every pointer
// with a value of its own, then makes a borrowed renderer: each handle, and
// each slice of the view and the sprites, must be the main one's, but for
// those it makes itself (BORROWED_RENDERER_OWN_HANDLES, which must start
// empty); no other slice and no pointer may be the main one's (the state is
// its own), but for EFFECT_STAGE_SHARED_POINTERS. A new asset field forgotten
// by borrow_renderer_assets, wherever it is in the renderer, fails here, and so
// does a kind of field the walk cannot see into. Destroying it leaves the main
// renderer as it was and frees all it made.
@(test)
test_borrowed_renderer_borrows_every_asset_and_owns_its_view :: proc(t: ^testing.T) {
	main := new(Renderer)
	defer free(main)
	main.canvas_width, main.canvas_height = 960, 540
	main.tactical.enabled, main.tactical.scene_3d, main.tactical.perspective = true, true, true
	seen: map[typeid]bool
	defer delete(seen)
	fields: [dynamic]Effect_Stage_Field
	defer {
		for field in fields { delete(field.path) }
		delete(fields)
	}
	effect_stage_fields(main, &fields, &seen)
	handles := 0
	for field in fields { if field.kind == .Handle { handles += 1 } }
	testing.expectf(t, handles > 40 && len(fields) > handles, "%d handles among %d fields: the walk missed the view", handles, len(fields))
	// The main renderer's own values: a distinct id in each handle's first
	// word, a distinct address in each slice, a block of its own for each
	// pointer.
	fake_bytes: [64]u8
	blocks: [dynamic]rawptr
	defer {
		for block in blocks { free(block) }
		delete(blocks)
	}
	for field, index in fields {
		switch field.kind {
		case .Handle:
			(cast(^u32)field.data)^ = u32(1000+index)
		case .Slice:
			(cast(^rawptr)field.data)^ = &fake_bytes[index%len(fake_bytes)]
			if field.size > size_of(rawptr) { (cast(^int)(uintptr(field.data)+size_of(rawptr)))^ = 1 }
		case .Pointer:
			size := 16
			if field.elem != nil { size = max(size, field.elem.size) }
			block, _ := mem.alloc(size)
			append(&blocks, block)
			(cast(^rawptr)field.data)^ = block
		case .Unknown:
			testing.expectf(t, false, "%s (%v) may hold a handle or a pointer the walk cannot see: teach effect_stage_walk this kind of field",
				field.path, field.elem.id)
		}
	}
	before := make([][]u8, len(fields))
	defer {
		for copy in before { delete(copy) }
		delete(before)
	}
	for field, index in fields { before[index] = slice.clone(effect_stage_bytes(field)) }

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	{
		context.allocator = mem.tracking_allocator(&track)
		borrowed := create_borrowed_renderer(main, 960, 540, {})
		testing.expect(t, borrowed != nil)
		if borrowed == nil { return }
		borrowed_fields: [dynamic]Effect_Stage_Field
		effect_stage_fields(borrowed, &borrowed_fields, &seen)
		testing.expect_value(t, len(borrowed_fields), len(fields))
		own := BORROWED_RENDERER_OWN_HANDLES
		shared := EFFECT_STAGE_SHARED_POINTERS
		for field, index in borrowed_fields[:min(len(borrowed_fields), len(fields))] {
			main_field := fields[index]
			testing.expect_value(t, field.path, main_field.path)
			same := slice.equal(effect_stage_bytes(field), effect_stage_bytes(main_field))
			switch field.kind {
			case .Handle, .Slice:
				if field.kind == .Slice && !effect_stage_asset_part(field.path) {
					testing.expectf(t, !same, "%s is the main renderer's state: the borrowed renderer needs its own", field.path)
					if same { mem.zero(field.data, field.size) }
				} else if effect_stage_listed(field.path, own[:]) {
					testing.expectf(t, effect_stage_zero(field), "%s is the borrowed renderer's own: it must start empty, not as the main one's", field.path)
					// Never unloaded headless (destroy_borrowed_renderer frees its own).
					mem.zero(field.data, field.size)
				} else {
					testing.expectf(t, same, "%s is not borrowed: borrow_renderer_assets must copy it from the main renderer, or, made by the view itself, it belongs in BORROWED_RENDERER_OWN_HANDLES and in destroy_borrowed_renderer",
						field.path)
				}
			case .Pointer:
				if effect_stage_listed(field.path, shared[:]) {
					testing.expectf(t, same, "%s is the main renderer's: it must be shared", field.path)
				} else {
					value := (cast(^rawptr)field.data)^
					testing.expectf(t, !same || value == nil, "%s is the main renderer's state: the borrowed view needs its own", field.path)
					if same { (cast(^rawptr)field.data)^ = nil }
				}
			case .Unknown:
				// Failed above, on the main renderer's.
			}
		}
		v := &borrowed.tactical
		testing.expect(t, v.showcase && v.enabled && v.scene_3d == main.tactical.scene_3d && v.perspective == main.tactical.perspective)
		testing.expect(t, borrowed.projection.tile_width == 64 && borrowed.projection.tile_height == 32)
		testing.expect(t, borrowed.canvas_width == 960 && borrowed.canvas_height == 540 && borrowed.playback_speed == 1)
		testing.expect(t, v.snapshot != nil && v.labels != nil && v.flipbook_state != nil, "the view's own state is made")
		testing.expect(t, v.surface == nil, "no render target headless")
		testing.expect(t, v.living_assets.failed, "a living print the main renderer has not got is never made by the borrowed one")
		testing.expect(t, borrowed.world_playback == nil && borrowed.sprite_assets.elapsed == 0)
		for field in borrowed_fields { delete(field.path) }
		delete(borrowed_fields)
		destroy_borrowed_renderer(borrowed)
	}
	testing.expectf(t, len(track.allocation_map) == 0, "%d allocations of the borrowed renderer left", len(track.allocation_map))
	testing.expectf(t, len(track.bad_free_array) == 0, "%d frees of what the borrowed renderer never made", len(track.bad_free_array))
	for field, index in fields {
		testing.expectf(t, slice.equal(effect_stage_bytes(field), before[index]), "%s of the main renderer changed", field.path)
	}
}
