package campaign

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

@(private)
Decode_Test_Snapshot :: struct {
	padding: [64*1024]u8,
	label: string `json:"title,omitempty"`,
	count: i32,
	seed: u64,
	child: struct { label: string, values: [4]i32 },
}

@(test)
test_large_save_decode_keeps_tags_defaults_and_future_fields :: proc(t: ^testing.T) {
	snapshot := new(Decode_Test_Snapshot)
	defer free(snapshot)
	payload := `{"title":"mem\u006fry","seed":18446744073709551615,"count":7,"child":{"label":"nested","values":[3,5]},"future":{"items":["ignored",{"value":42}]}}`
	bytes := transmute([]u8)payload
	err := decode_save(bytes, snapshot, context.allocator)
	defer delete(snapshot.label)
	defer delete(snapshot.child.label)
	testing.expect(t, err == nil)
	testing.expect_value(t, snapshot.label, "memory")
	testing.expect_value(t, snapshot.count, i32(7))
	testing.expect_value(t, snapshot.seed, max(u64))
	testing.expect_value(t, snapshot.child.label, "nested")
	testing.expect_value(t, snapshot.child.values, [4]i32{3, 5, 0, 0})
	testing.expect_value(t, snapshot.padding[0], u8(0))
	testing.expect_value(t, snapshot.padding[len(snapshot.padding)-1], u8(0))
}

@(test)
test_large_save_decode_rejects_duplicate_fields :: proc(t: ^testing.T) {
	snapshot := new(Decode_Test_Snapshot)
	defer free(snapshot)
	payload := `{"count":1,"count":2}`
	err := decode_save(transmute([]u8)payload, snapshot, context.allocator)
	testing.expect(t, err != nil)
}

@(test)
test_large_save_decode_failure_preserves_outputs_and_ownership :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-large-save-corrupt.json")
	defer os.remove(path)
	c: Campaign
	initialize(&c)
	defer destroy(&c)
	depot_credit(&c, 13)
	campaign_bytes, encoded := json.marshal(c, allocator = context.temp_allocator)
	testing.expect(t, encoded == nil)
	payload := fmt.tprintf("{\"campaign\":%s,\"snapshot\":{\"title\":\"staged allocation\",\"count\":\"invalid\"}}", string(campaign_bytes))
	bytes := fmt.tprintf("{\"version\":%d,\"checksum\":%d,\"state\":%s}", SLOT_VERSION, checksum(transmute([]u8)payload), payload)
	testing.expect(t, os.write_entire_file(path, bytes) == nil)
	snapshot := new(Decode_Test_Snapshot)
	defer free(snapshot)
	snapshot.count = 99
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	status := load_slot_into(path, &c, snapshot, mem.tracking_allocator(&tracker))
	testing.expect_value(t, status, Load_Status.Malformed)
	testing.expect_value(t, depot_credits(&c), i64(13))
	testing.expect_value(t, snapshot.count, i32(99))
	testing.expect_value(t, snapshot.label, "")
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
	testing.expect(t, os.exists(path))
}
