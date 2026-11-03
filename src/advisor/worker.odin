package advisor

import "base:runtime"
import "core:sync"
import "core:thread"
import "core:time"
import game "../game"

// THE WORKER (docs/piano-ia.md, Fase 4): the search on a thread of its own, on another core, so that the game never
// waits for it.
//
// - The game's thread photographs the real room (snapshot_take, a few microseconds) into a slot of a TRIPLE BUFFER and
//   hands it over with one atomic exchange; the worker takes the newest one, leaves the search it was doing (between
//   two nodes) and starts again from it.
// - The worker hands back what it found (the advice, and the best reply to every first move for thinking ahead) through
//   a second triple buffer; the game reads the newest at every frame, never waiting.
// - With nothing to do (the search over, or no root yet) the worker sleeps on a semaphore until the next snapshot.
//
// A triple buffer has three slots: the writer's, the reader's, and the one in the middle, swapped atomically with a
// flag that says it is fresh (Unreal's TTripleBuffer). Neither side ever stops the other.

// The work of a root at most: every round of the search ends well before (the whole search of the IA's arena, cards
// in hand, is about a thousand).
WORKER_WORK_CAP :: 20_000

@(private)
TRIPLE_FRESH :: u32(4)

Triple :: struct($T: typeid) {
	slots: [3]T,
	// The middle slot's index, and TRIPLE_FRESH when the writer has put something new there.
	middle: u32,
	// The writer's slot and the reader's (each touched by its own side only).
	write, read: u32,
}

@(private)
triple_init :: proc(t: ^Triple($T)) { t.write, t.middle, t.read = 0, 1, 2 }

// The writer's slot made the middle one, fresh; the writer goes on in the old middle.
@(private)
triple_publish :: proc(t: ^Triple($T)) { t.write = sync.atomic_exchange(&t.middle, t.write|TRIPLE_FRESH) & 3 }

// The newest the writer published, if there is one the reader has not taken: it becomes the reader's slot.
@(private)
triple_take :: proc(t: ^Triple($T)) -> bool {
	if sync.atomic_load(&t.middle) & TRIPLE_FRESH == 0 { return false }
	t.read = sync.atomic_exchange(&t.middle, t.read) & 3
	return true
}

@(private)
triple_fresh :: proc(t: ^Triple($T)) -> bool { return sync.atomic_load(&t.middle) & TRIPLE_FRESH != 0 }

// What the worker found for a root.
Packet :: struct {
	// The root it is for (its discrete fingerprint), and which snapshot of the game's (the game numbers them).
	root, generation: u64,
	advice: Advice,
	ponder: [MAX_CANDIDATES]Ponder,
	ponder_count: int,
	nodes, round: int,
	// The search of this root is over: every round, or the cap.
	done: bool,
}

Worker :: struct {
	snapshots: Triple(Snapshot),
	packets: Triple(Packet),
	// The game's numbers for its snapshots, the one in each slot.
	generations: [3]u64,
	generation: u64,
	search: Search,
	searching: u64,
	// The work of a root at most (WORKER_WORK_CAP; the tests set less, before the first snapshot).
	cap: int,
	sema: sync.Sema,
	thread: ^thread.Thread,
	stop: bool,
	// TESTS ONLY: while set the worker does no work (the game must go on as if it were slow).
	hold: bool,
	// The newest packet the game has read (the game's side only).
	latest: Packet,
}

worker_start :: proc() -> ^Worker {
	w := new(Worker, runtime.heap_allocator())
	if w == nil { return nil }
	triple_init(&w.snapshots)
	triple_init(&w.packets)
	w.cap = WORKER_WORK_CAP
	ok := search_init(&w.search)
	for &slot in w.snapshots.slots { ok = ok && snapshot_init(&slot) }
	if ok {
		// The worker's own memory is the process's (a test's tracking allocator belongs to the test's thread).
		worker_context := context
		worker_context.allocator = runtime.heap_allocator()
		w.thread = thread.create_and_start_with_poly_data(w, worker_run, worker_context)
		ok = w.thread != nil
	}
	if !ok { worker_free(w); return nil }
	return w
}

// The worker told to stop, waited for (it stops between two nodes), and its memory given back.
worker_stop :: proc(w: ^Worker) {
	if w == nil { return }
	sync.atomic_store(&w.stop, true)
	sync.sema_post(&w.sema)
	if w.thread != nil { thread.join(w.thread); thread.destroy(w.thread) }
	worker_free(w)
}

@(private)
worker_free :: proc(w: ^Worker) {
	search_destroy(&w.search)
	for &slot in w.snapshots.slots { snapshot_destroy(&slot) }
	free(w, runtime.heap_allocator())
}

// TESTS ONLY: the worker held, or let go.
worker_hold :: proc(w: ^Worker, held: bool) { sync.atomic_store(&w.hold, held) }

// THE GAME'S SIDE. A new root: the real room photographed into the game's slot (only read) and handed over. Its number.
worker_offer :: proc(w: ^Worker, real: ^game.Room) -> u64 {
	slot := w.snapshots.write
	if !snapshot_take(&w.snapshots.slots[slot], real) { return 0 }
	w.generation += 1
	w.generations[slot] = w.generation
	triple_publish(&w.snapshots)
	sync.sema_post(&w.sema)
	return w.generation
}

// The newest packet into `latest`, when there is one. Never waits.
worker_poll :: proc(w: ^Worker) -> bool {
	if !triple_take(&w.packets) { return false }
	w.latest = w.packets.slots[w.packets.read]
	return true
}

// THE WORKER'S SIDE.
@(private)
worker_run :: proc(w: ^Worker) {
	for !sync.atomic_load(&w.stop) {
		if triple_take(&w.snapshots) {
			slot := w.snapshots.read
			w.searching = w.generations[slot]
			search_root_from(&w.search, &w.snapshots.slots[slot])
			worker_publish(w)
			continue
		}
		if sync.atomic_load(&w.hold) { time.sleep(time.Millisecond); continue }
		s := &w.search
		if s.rooted && !s.done && s.work < w.cap {
			round := s.round
			search_step(s, 1)
			if s.round != round || s.done || s.work >= w.cap { worker_publish(w) }
			continue
		}
		// Nothing left to do: asleep until the next snapshot (or the stop).
		if !triple_fresh(&w.snapshots) { sync.sema_wait(&w.sema) }
	}
}

@(private)
worker_publish :: proc(w: ^Worker) {
	s := &w.search
	packet := &w.packets.slots[w.packets.write]
	packet.root, packet.generation = s.advice.root, w.searching
	packet.advice = s.advice
	packet.ponder_count = s.ponder_count
	copy(packet.ponder[:], s.ponder[:s.ponder_count])
	packet.nodes, packet.round, packet.done = s.nodes, s.round, s.done || s.work >= w.cap
	triple_publish(&w.packets)
}
