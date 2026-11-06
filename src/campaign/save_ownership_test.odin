package campaign

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
Owned_Save_Test :: struct {
	values: [dynamic]u32,
	children: [2]struct { label: string, bytes: []u8 },
}

@(test)
test_save_queue_detaches_dynamic_arrays_slices_and_strings_before_source_dies :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-save-owned-queue.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	source: Owned_Save_Test
	append(&source.values, 4, 8, 15)
	source.children[0].label = strings.clone("before enqueue")
	source.children[0].bytes = make([]u8, 3)
	source.children[0].bytes[2] = 91
	queue: Save_Queue
	testing.expect(t, save_queue_enqueue(&queue, path, &c, &source))
	source.values[0] = 999; source.children[0].bytes[2] = 0
	save_destroy_owned(&source)
	testing.expect(t, save_queue_flush(&queue))
	loaded, restored, status := load_slot(path, Owned_Save_Test)
	defer destroy(&loaded); defer save_destroy_owned(&restored)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect(t, len(restored.values) == 3 && restored.values[0] == 4)
	testing.expect(t, restored.children[0].label == "before enqueue" && restored.children[0].bytes[2] == 91)
}

@(test)
test_save_clone_and_repeated_load_release_all_owned_buffers :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	context.allocator = mem.tracking_allocator(&tracker)
	path := scratch_path("odin-pp-save-owned-reuse.json"); defer os.remove(path)
	c: Campaign; initialize(&c)
	source, cloned: Owned_Save_Test
	append(&source.values, 17, 29)
	source.children[1].label = strings.clone("owned")
	source.children[1].bytes = make([]u8, 12)
	testing.expect(t, save_clone_owned(&cloned, &source))
	testing.expect(t, raw_data(source.values) != raw_data(cloned.values))
	testing.expect(t, save_slot_from(path, &c, &source))
	for _ in 0..<3 { testing.expect_value(t, load_slot_into(path, &c, &cloned), Load_Status.Loaded) }
	save_destroy_owned(&source); save_destroy_owned(&cloned); destroy(&c)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}

@(test)
test_save_clone_rejects_live_addresses_and_rolls_back_allocation_failure :: proc(t: ^testing.T) {
	address := struct { pointer: ^int }{}
	copy_address: type_of(address)
	testing.expect(t, !save_clone_owned(&copy_address, &address), "Even a nil live pointer is outside the serialization contract")
	source, destination: Owned_Save_Test
	append(&source.values, 3)
	defer save_destroy_owned(&source)
	testing.expect(t, !save_clone_owned(&destination, &source, mem.nil_allocator()))
	testing.expect(t, len(destination.values) == 0 && len(source.values) == 1)
}

@(test)
test_bounded_save_decode_rejects_small_json_with_large_typed_allocation :: proc(t: ^testing.T) {
	Budget_Snapshot :: struct { values: [dynamic]struct { padding: [65536]u8 } }
	path := scratch_path("odin-pp-save-decode-budget.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_credit(&c, 73)
	progress, err := json.marshal(c, allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	payload := fmt.tprintf("%s\"campaign\":%s,\"snapshot\":%s%s", "{", string(progress), `{"values":[{},{},{},{},{},{},{},{},{},{}]}`, "}")
	envelope := fmt.tprintf("%s\"version\":2,\"checksum\":%d,\"state\":%s%s", "{", checksum(transmute([]u8)payload), payload, "}")
	testing.expect(t, json.is_valid(transmute([]u8)envelope), "The allocation test must start with syntactically valid JSON")
	testing.expect(t, os.write_entire_file(path, envelope) == nil)
	snapshot: Budget_Snapshot
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	budget := size_of(Saved_State(Budget_Snapshot))*2+len(envelope)+64*1024
	status := load_slot_into(path, &c, &snapshot, mem.tracking_allocator(&tracker), budget)
	testing.expect_value(t, status, Load_Status.Too_Large)
	testing.expect(t, depot_credits(&c) == 73 && len(snapshot.values) == 0 && os.exists(path))
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
	// Also exercise failure before a root Saved_State allocation can succeed.
	testing.expect_value(t, load_slot_into(path, &c, &snapshot, mem.tracking_allocator(&tracker), 1), Load_Status.Too_Large)
}

@(test)
test_save_loader_checks_file_size_before_payload_allocation :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-save-oversized-sparse.json"); defer os.remove(path)
	file, err := os.create(path)
	if !testing.expect(t, err == nil) { return }
	// A sparse file exercises the stat guard without a 128 MiB test allocation.
	truncated := os.truncate(file, MAX_SAVE_BYTES+1)
	os.close(file)
	if !testing.expect(t, truncated == nil) { return }
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_credit(&c, 41)
	snapshot := u32(17)
	testing.expect_value(t, load_slot_into(path, &c, &snapshot, mem.nil_allocator()), Load_Status.Too_Large)
	testing.expect(t, depot_credits(&c) == 41 && snapshot == 17 && os.exists(path))
}
