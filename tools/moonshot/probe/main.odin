// Fase 0: diagnostic only. The runner changes map_size in a disposable copy;
// this executable uses the game snapshot limits and never edits the game.
package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import advisor "../../../src/advisor"
import campaign "../../../src/campaign"
import expedition "../../../src/expedition"
import game "../../../src/game"
import grid "../../../src/engine/grid"
import level "../../../src/level"
import run "../../../src/run"

SCALE :: #config(MOONSHOT_SCALE, 1)
#assert(SCALE == 1 || SCALE == 2 || SCALE == 4 || SCALE == 8)

Options :: struct {
	biome: campaign.Biome,
	all, scale_set: bool,
	samples: int,
	seed: u64,
	advisor_work: int,
	advisor_ms: f64,
	skip_advisor: bool,
}

Arena_Memory :: struct {
	used_bytes, reserved_bytes, committed_bytes: u64,
}

Record :: struct {
	schema: int,
	fixture: string,
	scale: int,
	biome: campaign.Biome,
	sample: int,
	seed: u64,
	error: string,
	retouched: bool,
	side, cells, sites, groups: int,
	generated, room_created: bool,
	generation_ms, room_ms, prepare_ms, capture_ms: f64,
	generation_heap_bytes, generation_temp_bytes: i64,
	heap_peak_bytes, temp_peak_bytes, heap_remaining_bytes, temp_remaining_bytes: i64,
	heap_bad_free, temp_bad_free: int,
	snapshot_bytes, snapshot_struct_bytes: int,
	capture, snapshot_valid: bool,
	advisor_skipped, encounter, advisor_context_known: bool,
	enemies, enemy_health_total, hand_count: int,
	player_cell: grid.Position,
	advisor_init_ms, advisor_snapshot_ms, advisor_root_ms, advisor_search_ms: f64,
	first_advice_ms: f64,
	advisor_rooted, advice_valid, advice_possible, advisor_done, advisor_budget_exhausted: bool,
	advice_kind: advisor.Advice_Kind,
	advice_cell: grid.Position,
	advice_depth, nodes, work, work_limit: int,
	time_limit_ms: f64,
	level_recopies, pool_recopies: int,
	advisor_snapshot_memory, advisor_rehearsal_memory, advisor_try_memory, temporary_memory: Arena_Memory,
	advisor_direct_heap_payload_bytes: int,
}

@(private)
usage :: proc() {
	fmt.println("Moonshot: probe headless, output JSONL; nessun salvataggio su disco.")
	fmt.println("--biome=Cyber|Snow|Space|scale-set|all (accetta tutti i nomi Biome), --samples=3, --seed=42")
	fmt.println("--advisor-work=128 --advisor-ms=5000 --skip-advisor; scala compile-time MOONSHOT_SCALE=1|2|4|8.")
	fmt.println("Il tempo limita fra nodi; un singolo nodo non e interrompibile. Il runner deve imporre un timeout esterno.")
}

@(private)
parse_options :: proc() -> (options: Options, ok, help: bool) {
	options = {biome = .Cyber, samples = 3, seed = 42, advisor_work = 128, advisor_ms = 5000}
	for arg in os.args[1:] {
		if arg == "--help" || arg == "-h" { return options, true, true }
		if arg == "--skip-advisor" { options.skip_advisor = true; continue }
		if strings.has_prefix(arg, "--biome=") {
			value := arg[len("--biome="):]
			options.all = value == "all"
			options.scale_set = value == "scale-set"
			found := options.all || options.scale_set
			for biome in campaign.Biome {
				if biome != .Count && value == fmt.tprintf("%v", biome) { options.biome = biome; found = true }
			}
			if !found { return options, false, false }
		} else if strings.has_prefix(arg, "--samples=") {
			options.samples, ok = strconv.parse_int(arg[len("--samples="):])
			if !ok || options.samples < 1 || options.samples > 100 { return options, false, false }
		} else if strings.has_prefix(arg, "--seed=") {
			options.seed, ok = strconv.parse_u64(arg[len("--seed="):])
			if !ok { return options, false, false }
		} else if strings.has_prefix(arg, "--advisor-work=") {
			options.advisor_work, ok = strconv.parse_int(arg[len("--advisor-work="):])
			if !ok || options.advisor_work < 1 || options.advisor_work > 100000 { return options, false, false }
		} else if strings.has_prefix(arg, "--advisor-ms=") {
			options.advisor_ms, ok = strconv.parse_f64(arg[len("--advisor-ms="):])
			if !ok || !(options.advisor_ms > 0 && options.advisor_ms <= 300000) { return options, false, false }
		} else { return options, false, false }
	}
	return options, true, false
}

@(private)
arena_memory :: proc(arena: ^virtual.Arena) -> (result: Arena_Memory) {
	result.used_bytes = u64(arena.total_used)
	result.reserved_bytes = u64(arena.total_reserved)
	for block := arena.curr_block; block != nil; block = block.prev { result.committed_bytes += u64(block.committed) }
	return
}

// Use one of the real generated groups, with its real statistics and the normal
// encounter setup. The nearby geography and health can differ between scales;
// this is not a claim of identical combat complexity.
@(private)
prepare_advisor_encounter :: proc(w: ^expedition.World, room: ^game.Room) -> bool {
	if w.group_count == 0 { return false }
	g := &w.groups[0]
	for radius in 2..=6 {
		for dy in -radius..=radius { for dx in -radius..=radius {
			if max(abs(dx), abs(dy)) != radius { continue }
			p := grid.offset(g.anchor, dx, dy)
			tile, found := level.tile_at(room.level_data, p)
			if !found || !level.is_walkable(tile.kind) { continue }
			occupied := false
			for member in g.members[:g.count] { if member.alive && member.enemy.position == p { occupied = true } }
			if occupied { continue }
			room.player.position = p
			game.end_expedition_encounter(room)
			return expedition.engage(w, room, 0)
		} }
	}
	return false
}

@(private)
measure_advisor :: proc(record: ^Record, w: ^expedition.World, room: ^game.Room, options: Options) {
	record.encounter = prepare_advisor_encounter(w, room)
	if !record.encounter { record.error = "advisor_encounter_failed"; return }
	record.player_cell = room.player.position
	record.enemies = len(room.enemies)
	for enemy in room.enemies { record.enemy_health_total += int(enemy.health) }
	record.hand_count = room.player.deck.hand_count
	game_context := run.advisor_context_expedition(w, nil, room)
	record.advisor_context_known = game_context.known
	search := new(advisor.Search)
	defer free(search)
	stamp := time.tick_now()
	if !advisor.search_init(search) { record.error = "advisor_init_failed"; return }
	record.advisor_init_ms = time.duration_milliseconds(time.tick_since(stamp))
	defer advisor.search_destroy(search)
	record.advisor_direct_heap_payload_bytes = len(search.table)*size_of(search.table[0]) +
		len(search.reply_values)*size_of(search.reply_values[0]) + len(search.reply_described)*size_of(search.reply_described[0])
	stamp = time.tick_now()
	if !advisor.snapshot_take(&search.snapshot, room, game_context) { record.error = "advisor_snapshot_failed"; return }
	record.advisor_snapshot_ms = time.duration_milliseconds(time.tick_since(stamp))
	record.advisor_snapshot_memory = arena_memory(&search.snapshot.arena)
	stamp = time.tick_now()
	record.advisor_rooted = advisor.search_root_from(search, &search.snapshot)
	record.advisor_root_ms = time.duration_milliseconds(time.tick_since(stamp))
	if !record.advisor_rooted { record.error = "advisor_root_failed"; return }
	stamp = time.tick_now()
	for !search.done && !search.advice.valid && search.work < options.advisor_work {
		if time.duration_milliseconds(time.tick_since(stamp)) >= options.advisor_ms { break }
		_ = advisor.search_step(search, 1)
	}
	record.advisor_search_ms = time.duration_milliseconds(time.tick_since(stamp))
	record.advice_valid = search.advice.valid
	if record.advice_valid {
		record.first_advice_ms = record.advisor_snapshot_ms + record.advisor_root_ms + record.advisor_search_ms
		record.advice_possible = advisor.advice_possible(room, search.advice, room.player.position)
	}
	record.advice_kind, record.advice_cell, record.advice_depth = search.advice.kind, search.advice.cell, search.advice.depth
	record.nodes, record.work, record.advisor_done = search.nodes, search.work, search.done
	record.advisor_budget_exhausted = !search.done && !search.advice.valid
	record.level_recopies, record.pool_recopies = search.rehearsal.level_copies, search.rehearsal.pool_copies
	record.advisor_rehearsal_memory = arena_memory(&search.rehearsal.root)
	record.advisor_try_memory = arena_memory(&search.rehearsal.try)
}

@(private)
measure_world :: proc(record: ^Record, options: Options, heap, temporary: ^mem.Tracking_Allocator) {
	w: expedition.World
	data: level.Level
	stamp := time.tick_now()
	record.generated = expedition.generate(&w, &data, record.biome, options.seed, false)
	record.generation_ms = time.duration_milliseconds(time.tick_since(stamp))
	if !record.generated { record.error = "generation_failed"; return }
	defer level.destroy(&data)
	record.side, record.cells, record.sites, record.groups = data.tiles.width, len(data.tiles.cells), w.site_count, w.group_count
	record.generation_heap_bytes, record.generation_temp_bytes = heap.current_memory_allocated, temporary.current_memory_allocated
	if record.side != campaign.biome_size(record.biome)*SCALE { record.error = "scale_patch_missing_or_inconsistent"; return }
	player, player_ok := game.create_player({100, 5, 0})
	if !player_ok { record.error = "player_failed"; return }
	stamp = time.tick_now()
	room, created := game.create_room(&data, &player, {room_seed = options.seed})
	record.room_created = created
	record.room_ms = time.duration_milliseconds(time.tick_since(stamp))
	if !created { record.error = "room_failed"; return }
	defer game.destroy_room(&room)
	stamp = time.tick_now()
	if !game.configure_expedition_combat(&room) { record.error = "combat_configuration_failed"; return }
	player.tactical.config.expedition_biome = u8(record.biome)
	player.tactical.config.low_gravity = record.biome == .Space
	expedition.prepare_room(&w, &room)
	record.prepare_ms = time.duration_milliseconds(time.tick_since(stamp))
	snapshot := new(expedition.Snapshot)
	defer { expedition.snapshot_destroy(snapshot); free(snapshot) }
	stamp = time.tick_now()
	record.capture = expedition.capture(&w, &room, snapshot)
	record.capture_ms = time.duration_milliseconds(time.tick_since(stamp))
	record.snapshot_struct_bytes = size_of(expedition.Snapshot)
	record.snapshot_bytes = expedition.snapshot_storage_bytes(snapshot)
	if record.capture { record.snapshot_valid = expedition.valid_snapshot(snapshot) }
	// A failed capture remains an observed result; the harness never bypasses validation.
	if !options.skip_advisor { measure_advisor(record, &w, &room, options) }
}

@(private)
measure_sample :: proc(options: Options, biome: campaign.Biome, sample: int) -> (record: Record) {
	record = {schema = 2, scale = SCALE, biome = biome, sample = sample, seed = options.seed,
		fixture = "generated_group_0_player_100_5_0_no_backpack",
		advisor_skipped = options.skip_advisor, work_limit = options.advisor_work, time_limit_ms = options.advisor_ms}
	heap, temporary: mem.Tracking_Allocator
	mem.tracking_allocator_init(&heap, context.allocator)
	defer mem.tracking_allocator_destroy(&heap)
	heap.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	temp_arena: virtual.Arena
	if virtual.arena_init_growing(&temp_arena, mem.Megabyte) != nil { record.error = "temporary_arena_failed"; return }
	defer virtual.arena_destroy(&temp_arena)
	mem.tracking_allocator_init(&temporary, virtual.arena_allocator(&temp_arena))
	defer mem.tracking_allocator_destroy(&temporary)
	temporary.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	{
		context.allocator = mem.tracking_allocator(&heap)
		context.temp_allocator = mem.tracking_allocator(&temporary)
		measure_world(&record, options, &heap, &temporary)
		record.temporary_memory = arena_memory(&temp_arena)
		free_all(context.temp_allocator)
	}
	record.heap_peak_bytes, record.temp_peak_bytes = heap.peak_memory_allocated, temporary.peak_memory_allocated
	record.heap_remaining_bytes, record.temp_remaining_bytes = heap.current_memory_allocated, temporary.current_memory_allocated
	record.heap_bad_free, record.temp_bad_free = len(heap.bad_free_array), len(temporary.bad_free_array)
	if record.heap_remaining_bytes != 0 || record.temp_remaining_bytes != 0 || record.heap_bad_free != 0 || record.temp_bad_free != 0 {
		record.error = "allocator_cleanup_failed"
	}
	return
}

main :: proc() {
	options, ok, help := parse_options()
	if help { usage(); return }
	if !ok { usage(); os.exit(2) }
	failed := false
	for biome in campaign.Biome {
		if biome == .Count { continue }
		if options.scale_set {
			if biome != .Cyber && biome != .Snow && biome != .Space { continue }
		} else if !options.all && biome != options.biome { continue }
		for sample in 0..<options.samples {
			record := measure_sample(options, biome, sample)
			bytes, err := json.marshal(record, {use_enum_names = true})
			if err != nil { fmt.eprintln("moonshot: JSON encoding failed", err); os.exit(2) }
			fmt.println(string(bytes))
			delete(bytes)
			failed = failed || record.error != ""
			free_all(context.temp_allocator)
		}
	}
	if failed { os.exit(1) }
}
