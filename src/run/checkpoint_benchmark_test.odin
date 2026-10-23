package run

import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"
import campaign "../campaign"
import world "../expedition"

// Explicit diagnostic, not a timing assertion: slow machines must still pass.
@(test)
test_checkpoint_save_benchmark :: proc(t: ^testing.T) {
	if #config(CAMPAIGN_SAVE_BENCHMARK, false) {
		path := scratch_path("odin-pp-checkpoint-benchmark.json")
		defer os.remove(path)
		e := flow_fixture(t, .Space); defer flow_destroy(e)
		testing.expect(t, world.capture(&e.world, &e.rs.room, e.checkpoint))
		total, peak := f64(0), f64(0)
		for i in 0..<10 {
			e.world.clock = f32(i)
			started := time.tick_now()
			testing.expect(t, world.capture(&e.world, &e.rs.room, e.checkpoint))
			elapsed := time.duration_milliseconds(time.tick_since(started))
			total += elapsed; peak = max(peak, elapsed)
		}
		fmt.printf("CHECKPOINT CAPTURE: %dx%d, %d-byte heap snapshot, 10 samples, mean %.3f ms, peak %.3f ms\n", world.size(&e.world), world.size(&e.world), size_of(world.Snapshot), total/10, peak)
		total, peak = 0, 0
		for i in 0..<10 {
			e.checkpoint.world.clock = f32(i)
			started := time.tick_now()
			testing.expect(t, campaign.save_slot_from(path, e.progress, e.checkpoint))
			elapsed := time.duration_milliseconds(time.tick_since(started))
			total += elapsed; peak = max(peak, elapsed)
		}
		bytes, err := os.read_entire_file(path, context.allocator)
		defer delete(bytes)
		testing.expect(t, err == nil)
		fmt.printf("CHECKPOINT SAVE: 10 samples, mean %.2f ms, peak %.2f ms, %d bytes\n", total/10, peak, len(bytes))
		queue: campaign.Save_Queue
		total, peak = 0, 0
		for i in 0..<10 {
			e.checkpoint.world.clock = f32(i)
			started := time.tick_now()
			testing.expect(t, campaign.save_queue_enqueue(&queue, path, e.progress, e.checkpoint))
			elapsed := time.duration_milliseconds(time.tick_since(started))
			total += elapsed; peak = max(peak, elapsed)
		}
		testing.expect(t, campaign.save_queue_flush(&queue))
		fmt.printf("CHECKPOINT ENQUEUE: 10 samples, mean %.3f ms, peak %.3f ms\n", total/10, peak)
	}
}
