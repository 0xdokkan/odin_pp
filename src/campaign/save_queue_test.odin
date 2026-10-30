package campaign

import "core:os"
import "core:testing"

@(private)
Queue_Test_Snapshot :: struct { tick: u64, cells: [64]u8 }

@(test)
test_save_queue_owns_immutable_depot_and_snapshot :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-queue-isolation.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	depot_credit(&c, 12)
	snapshot := Queue_Test_Snapshot{tick = 1}
	snapshot.cells[7] = 51
	queue: Save_Queue
	testing.expect(t, save_queue_enqueue(&queue, path, &c, &snapshot))
	depot_credit(&c, 87); snapshot.tick = 2; snapshot.cells[7] = 99
	testing.expect(t, save_queue_flush(&queue))
	testing.expect(t, !save_queue_busy(&queue))
	loaded, restored, status := load_slot(path, Queue_Test_Snapshot)
	defer destroy(&loaded)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, depot_credits(&loaded), i64(12))
	testing.expect_value(t, restored.tick, u64(1))
	testing.expect_value(t, restored.cells[7], u8(51))
}

@(test)
test_save_queue_coalesces_and_flushes_latest_checkpoint :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-queue-latest.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	queue: Save_Queue
	snapshot: Queue_Test_Snapshot
	for i in 1..<21 {
		depot_credit(&c, 1); c.revision = u64(i); snapshot.tick = u64(i)
		testing.expect(t, save_queue_enqueue(&queue, path, &c, &snapshot))
	}
	testing.expect(t, save_queue_flush(&queue))
	loaded, restored, status := load_slot(path, Queue_Test_Snapshot)
	defer destroy(&loaded)
	testing.expect_value(t, status, Load_Status.Loaded)
	testing.expect_value(t, depot_credits(&loaded), i64(20))
	testing.expect_value(t, restored.tick, u64(20))
	testing.expect_value(t, queue.completed_revision, u64(20))
}

@(test)
test_save_queue_reports_failure_and_recovers_on_retry :: proc(t: ^testing.T) {
	path := scratch_path("odin-pp-queue-retry.json"); defer os.remove(path)
	c: Campaign; initialize(&c); defer destroy(&c)
	queue: Save_Queue
	snapshot: Queue_Test_Snapshot
	testing.expect(t, save_queue_enqueue(&queue, scratch_path("odin-pp-no-such-directory/slot.json"), &c, &snapshot))
	testing.expect(t, !save_queue_flush(&queue) && queue.failed)
	testing.expect(t, save_queue_enqueue(&queue, path, &c, &snapshot))
	testing.expect(t, save_queue_flush(&queue) && !queue.failed)
	testing.expect(t, os.exists(path))
}

@(test)
test_save_queue_slot_transition_preserves_both_slots :: proc(t: ^testing.T) {
	first := scratch_path("odin-pp-queue-slot-one.json"); defer os.remove(first)
	second := scratch_path("odin-pp-queue-slot-two.json"); defer os.remove(second)
	c: Campaign; initialize(&c); defer destroy(&c)
	queue: Save_Queue
	snapshot := Queue_Test_Snapshot{tick = 1}
	testing.expect(t, save_queue_enqueue(&queue, first, &c, &snapshot))
	snapshot.tick = 2
	testing.expect(t, save_queue_enqueue(&queue, second, &c, &snapshot))
	testing.expect(t, save_queue_flush(&queue))
	for path, i in ([2]string{first, second}) {
		loaded, restored, status := load_slot(path, Queue_Test_Snapshot)
		defer destroy(&loaded)
		testing.expect_value(t, status, Load_Status.Loaded)
		testing.expect_value(t, restored.tick, u64(i+1))
	}
}
