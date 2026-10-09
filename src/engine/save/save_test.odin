package save

import "core:fmt"
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
