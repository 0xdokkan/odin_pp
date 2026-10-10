package save

import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

@(private = "file")
Scores :: struct {
	best:   [4]i64,
	played: int,
	name:   string,
}

@(private = "file")
temp_path :: proc(t: ^testing.T, name: string) -> string {
	dir, err := os.temp_directory(context.temp_allocator)
	testing.expect(t, err == nil)
	path, join_err := os.join_path({dir, name}, context.temp_allocator)
	testing.expect(t, join_err == nil)
	return path
}

@(test)
test_round_trip_and_overwrite :: proc(t: ^testing.T) {
	path := temp_path(t, "odin-pp-save-roundtrip.json")
	defer os.remove(path)
	testing.expect(t, write(path, 2, Scores{best = {10, 0, 3, 0}, played = 4}))
	testing.expect(t, write(path, 2, Scores{best = {12, 0, 3, 0}, played = 5}))
	value, status := read(path, 2, Scores, allocator = context.temp_allocator)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, value.best[0], i64(12))
	testing.expect_value(t, value.played, 5)
	testing.expect(t, !os.exists(fmt.tprintf("%s.tmp", path)))
}

@(test)
test_missing_malformed_and_version_mismatch :: proc(t: ^testing.T) {
	path := temp_path(t, "odin-pp-save-bad.json")
	defer os.remove(path)
	_, missing := read(path, 1, Scores)
	testing.expect_value(t, missing, Load_Status.Missing)
	testing.expect(t, os.write_entire_file(path, "{not json") == nil)
	_, malformed := read(path, 1, Scores, allocator = context.temp_allocator)
	testing.expect_value(t, malformed, Load_Status.Malformed)
	testing.expect(t, write(path, 3, Scores{}))
	_, wrong := read(path, 1, Scores, allocator = context.temp_allocator)
	testing.expect_value(t, wrong, Load_Status.Wrong_Version)
	_, large := read(path, 3, Scores, max_bytes = 4, allocator = context.temp_allocator)
	testing.expect_value(t, large, Load_Status.Too_Large)
}

@(test)
test_rejected_nested_data_leaves_no_caller_allocations :: proc(t: ^testing.T) {
	Nested :: struct { records: map[string][]string, count: int }
	path := temp_path(t, "odin-pp-save-nested-rejected.json")
	defer os.remove(path)
	sources := [?]string{
		`{"version":2,"data":{"records":{"ring":["first","second"]},"count":1}}`,
		`{"version":1,"data":{"records":{"ring":["first","second"]},"count":"bad"}}`,
	}
	for source, index in sources {
		testing.expect(t, os.write_entire_file(path, source) == nil)
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		_, status := read(path, 1, Nested, allocator = mem.tracking_allocator(&tracker))
		testing.expect_value(t, status, Load_Status.Wrong_Version if index == 0 else Load_Status.Malformed)
		testing.expect_value(t, tracker.current_memory_allocated, i64(0))
		// Keep this failure reproducer leak-free even before the implementation is fixed.
		for address in tracker.allocation_map { free(address) }
		mem.tracking_allocator_destroy(&tracker)
	}
}

@(test)
test_nested_values_are_owned_and_duplicate_keys_do_not_leak :: proc(t: ^testing.T) {
	Nested :: struct { records: map[string][]string }
	path := temp_path(t, "odin-pp-save-nested-owned.json")
	defer os.remove(path)
	testing.expect(t, os.write_entire_file(path,
		`{"version":1,"data":{"records":{"ring":["old"],"ring":["new","best"]}}}`) == nil)
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	allocator := mem.tracking_allocator(&tracker)
	value, status := read(path, 1, Nested, allocator = allocator)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, value.records["ring"][0], "new")
	testing.expect_value(t, value.records["ring"][1], "best")
	for key, values in value.records {
		for item in values { delete(item, allocator) }
		delete(values, allocator)
		delete(key, allocator)
	}
	delete(value.records)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}
