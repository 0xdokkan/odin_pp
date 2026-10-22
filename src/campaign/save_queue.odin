package campaign

import "core:strings"
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
	path: string,
	progress: Campaign,
	snapshot: rawptr,
	write: proc(string, ^Campaign, rawptr) -> bool,
	success: bool,
}

@(private)
save_job_destroy :: proc(job: ^Save_Job) {
	if job == nil { return }
	destroy(&job.progress); delete(job.path); free(job.snapshot); free(job)
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

// Copies everything the worker needs. T has the same pointer-free snapshot
// contract as save_slot_from. No live gameplay allocation crosses threads.
save_queue_enqueue :: proc(queue: ^Save_Queue, path: string, c: ^Campaign, snapshot: ^$T) -> bool {
	if queue == nil || path == "" || snapshot == nil || !campaign_valid(c) { return false }
	save_queue_poll(queue)
	if queue.active != nil && queue.active.path != path {
		// Accidental cross-slot reuse must never let a late checkpoint recreate
		// a deleted slot or race a synchronous transaction in another slot.
		if !save_queue_flush(queue) { return false }
	}
	job := new(Save_Job)
	job.path = strings.clone(path)
	job.progress = c^
	job.progress.depot = make([dynamic]Inventory_Grid, len(c.depot))
	copy(job.progress.depot[:], c.depot[:])
	copy_snapshot := new(T); copy_snapshot^ = snapshot^
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
