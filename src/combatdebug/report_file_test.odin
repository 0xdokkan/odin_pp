package combatdebug

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:testing"

@(test)
test_interactive_reports_preserve_previous_samples_and_deterministic_json :: proc(t: ^testing.T) {
	directory, dir_error := os.make_directory_temp("", "odin_pp_reports.*", context.allocator)
	testing.expect(t, dir_error == nil)
	if dir_error != nil {
		return
	}
	defer delete(directory)
	defer os.remove(directory)
	base_path := fmt.aprintf("%s/sample.json", directory)
	defer delete(base_path)
	room, player := playtest_test_room(t)
	room.player = &player
	session: Playtest_Session
	defer destroy_playtest_session(&session)
	testing.expect(t, begin_playtest_session(&session, 0xC0FFEE))
	testing.expect(t, begin_playtest_room(&session, {
		node_id = 0, node_kind = .Combat, depth = 0, room_seed = 101,
	}, &room))
	testing.expect(t, finish_playtest_session(&session, .Abandoned, &room))
	expected, marshalled := marshal_playtest_report(&session)
	testing.expect(t, marshalled)
	defer delete(expected)
	first, first_ok := write_unique_playtest_report(&session, base_path)
	testing.expect(t, first_ok)
	defer delete(first)
	defer os.remove(first)
	second, second_ok := write_unique_playtest_report(&session, base_path)
	testing.expect(t, second_ok)
	defer delete(second)
	defer os.remove(second)
	testing.expect_value(t, first, base_path)
	testing.expect_value(t, second, fmt.tprintf("%s/sample_1.json", directory))
	paths := [?]string{first, second}
	for path in paths {
		data, read_error := os.read_entire_file(path, context.allocator)
		testing.expect(t, read_error == nil)
		testing.expect(t, bytes.equal(data, expected))
		delete(data)
	}
}
