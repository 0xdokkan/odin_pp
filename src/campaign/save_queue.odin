package campaign

import "core:strings"
import "core:mem"
import "core:fmt"
import "core:thread"

// The main thread owns this queue. The worker touches only its immutable job.
// At most one job writes a slot, and only the latest waiting checkpoint is
// retained. A slot transition must flush before reusing the queue.
Save_Queue :: struct {
	worker: ^thread.Thread,
	active, pending: ^Save_Job,
	failed: bool,
	completed_revision: u64,
	completed_at: i64,
}
@(private)
Save_Job :: struct {
	arena: mem.Dynamic_Arena,
	path: string,
	progress: Campaign,
	snapshot: rawptr,
	write: proc(string, ^Campaign, rawptr) -> bool,
	success: bool,
}

@(private)
save_job_destroy :: proc(job: ^Save_Job) {
	if job == nil { return }
	mem.dynamic_arena_destroy(&job.arena); free(job)
}

@(private)
save_worker :: proc(worker: ^thread.Thread) {
	job := cast(^Save_Job)worker.data
	job.success = job.write(job.path, &job.progress, job.snapshot)
}

@(private)
save_queue_start :: proc(queue: ^Save_Queue, job: ^Save_Job) -> bool {
	worker := thread.create(save_worker, .Low, "campaign-save")
	if worker == nil { save_job_destroy(job); queue.failed = true; return false }
	queue.worker = worker; queue.active = job
	worker.data = job
	thread.start(worker)
	return true
}

@(private)
save_queue_complete :: proc(queue: ^Save_Queue) {
	thread.join(queue.worker)
	job := queue.active
	queue.failed = !job.success
	if job.success { queue.completed_revision = job.progress.revision; queue.completed_at = job.progress.saved_unix_seconds }
	thread.destroy(queue.worker)
	save_job_destroy(job)
	queue.worker = nil; queue.active = nil
}

// Cheap main-thread poll. Never waits for an in-flight disk operation.
save_queue_poll :: proc(queue: ^Save_Queue) {
	if queue == nil { return }
	if queue.worker != nil && thread.is_done(queue.worker) { save_queue_complete(queue) }
	if queue.worker == nil && queue.pending != nil {
		job := queue.pending; queue.pending = nil
		save_queue_start(queue, job)
	}
}

save_queue_busy :: proc(queue: ^Save_Queue) -> bool {
	return queue != nil && (queue.worker != nil || queue.pending != nil)
}

// Deep-copies all serialization data into the job arena before enqueueing.
// The source may change or be destroyed immediately; no gameplay buffer is borrowed.
save_queue_enqueue :: proc(queue: ^Save_Queue, path: string, c: ^Campaign, snapshot: ^$T) -> bool {
	if queue == nil || path == "" || snapshot == nil || !campaign_valid(c) { return false }
	save_queue_poll(queue)
	if queue.active != nil && queue.active.path != path {
		// Accidental cross-slot reuse must never let a late checkpoint recreate
		// a deleted slot or race a synchronous transaction in another slot.
		if !save_queue_flush(queue) { return false }
	}
	job := new(Save_Job)
	mem.dynamic_arena_init(&job.arena)
	allocator := mem.dynamic_arena_allocator(&job.arena)
	job.path = strings.clone(path, allocator)
	copy_snapshot := new(T, allocator)
	if !save_clone_owned(&job.progress, c, allocator) || !save_clone_owned(copy_snapshot, snapshot, allocator) {
		fmt.eprintln("campaign save: unsupported snapshot ownership or allocation failure")
		save_job_destroy(job); queue.failed = true; return false
	}
	job.snapshot = copy_snapshot
	job.write = proc(path: string, progress: ^Campaign, value: rawptr) -> bool {
		return save_slot_from(path, progress, cast(^T)value)
	}
	if queue.worker == nil { return save_queue_start(queue, job) }
	save_job_destroy(queue.pending)
	queue.pending = job
	return true
}

// Durability boundary for slot changes, casino transactions, and shutdown.
// Flush waits only at these explicit boundaries, never on a combat beat.
save_queue_flush :: proc(queue: ^Save_Queue) -> bool {
	if queue == nil { return true }
	for queue.worker != nil || queue.pending != nil {
		if queue.worker != nil { save_queue_complete(queue) }
		if queue.pending != nil { job := queue.pending; queue.pending = nil; save_queue_start(queue, job) }
	}
	return !queue.failed
}
