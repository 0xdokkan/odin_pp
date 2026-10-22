package campaign

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

SLOT_VERSION :: 2
MAX_SAVE_BYTES :: 128*1024*1024
Load_Status :: enum { Loaded, Missing, Unreadable, Too_Large, Malformed, Wrong_Version, Checksum_Mismatch, Invalid_State }
Saved_State :: struct($T: typeid) { campaign: Campaign, snapshot: T }
@(private)
Slot_Envelope :: struct($T: typeid) { version: int, checksum: u64, state: Saved_State(T) }

// The caller owns the returned string. No slot lives in the working directory.
slot_path :: proc(index: int, allocator := context.allocator) -> string {
	if index < 0 || index >= SLOT_COUNT { return "" }
	base, base_err := os.user_data_dir(context.temp_allocator)
	if base_err != nil || base == "" { return "" }
	directory, directory_err := os.join_path({base, "OdinPP"}, context.temp_allocator)
	if directory_err != nil { return "" }
	if !os.exists(directory) && os.make_directory(directory) != nil { return "" }
	path, path_err := os.join_path({directory, fmt.tprintf("campaign-slot-%d.json", index+1)}, allocator)
	return path if path_err == nil else ""
}
@(private)
checksum :: proc(bytes: []u8) -> (hash: u64) {
	hash = 14695981039346656037
	for byte in bytes { hash = (hash ~ u64(byte))*1099511628211 }
	return
}

// T is an owning, pointer-free snapshot supplied by the game runtime. Pointer
// relationships (Room.player, world chunks, etc.) must be rebuilt after load;
// serializing live addresses would make a save unusable after process restart.
save_slot :: proc(path: string, c: ^Campaign, snapshot: $T) -> bool {
	copy := new(T)
	defer free(copy)
	copy^ = snapshot
	return save_slot_from(path, c, copy)
}

// Pointer form avoids copying a large world snapshot onto a caller's stack.
save_slot_from :: proc(path: string, c: ^Campaign, snapshot: ^$T) -> bool {
	if path == "" || !campaign_valid(c) { return false }
	if snapshot == nil { return false }
	now := time.to_unix_seconds(time.now())
	scratch: mem.Dynamic_Arena
	mem.dynamic_arena_init(&scratch)
	defer mem.dynamic_arena_destroy(&scratch)
	allocator := mem.dynamic_arena_allocator(&scratch)
	state := new(Saved_State(T), allocator)
	state.campaign = c^
	state.snapshot = snapshot^
	state.campaign.saved_unix_seconds = now
	payload, payload_err := json.marshal(state^, allocator = allocator)
	if payload_err != nil { return false }
	// The state is already canonical JSON. Embed those exact bytes so hashing
	// does not require a second reflective traversal of the complete world.
	header := fmt.tprintf("%s\"version\":%d,\"checksum\":%d,\"state\":", "{", SLOT_VERSION, checksum(payload))
	if len(header)+len(payload)+1 > MAX_SAVE_BYTES { return false }
	bytes := make([]u8, len(header)+len(payload)+1, allocator)
	copy(bytes, transmute([]u8)header)
	copy(bytes[len(header):], payload)
	bytes[len(bytes)-1] = '}'
	temporary := fmt.tprintf("%s.tmp", path)
	file, open_err := os.open(temporary, {.Write, .Create, .Trunc})
	if open_err != nil { return false }
	written, write_err := os.write(file, bytes)
	flush_err := os.sync(file)
	os.close(file)
	if write_err != nil || written != len(bytes) || flush_err != nil {
		os.remove(temporary); return false
	}
	if os.rename(temporary, path) != nil { os.remove(temporary); return false }
	c.saved_unix_seconds = now
	return true
}

// A corrupt slot is deliberately left intact. The launcher shows the error;
// only the explicitly confirmed delete action may remove that evidence.
// Decoding into an arena first also prevents leaks from truncated JSON or
// duplicate object keys. Successful results own allocations in `allocator`.
load_slot :: proc(path: string, $T: typeid, allocator := context.allocator) -> (Campaign, T, Load_Status) {
	c: Campaign
	snapshot: T
	status := load_slot_into(path, &c, &snapshot, allocator)
	return c, snapshot, status
}

// Outputs are changed only after schema, checksum and campaign validation.
// Callers with large world snapshots can allocate these outputs on the heap.
load_slot_into :: proc(path: string, c: ^Campaign, snapshot: ^$T, allocator := context.allocator) -> Load_Status {
	if c == nil || snapshot == nil { return .Invalid_State }
	if !os.exists(path) { return .Missing }
	scratch: mem.Dynamic_Arena
	mem.dynamic_arena_init(&scratch)
	defer mem.dynamic_arena_destroy(&scratch)
	staging := mem.dynamic_arena_allocator(&scratch)
	bytes, read_err := os.read_entire_file(path, staging)
	if read_err != nil { return .Unreadable }
	if len(bytes) > MAX_SAVE_BYTES { return .Too_Large }
	header: struct { version: int, checksum: u64 }
	if json.unmarshal(bytes, &header, allocator = staging) != nil { return .Malformed }
	if header.version < 1 || header.version > SLOT_VERSION { return .Wrong_Version }
	payload, found := slot_payload(bytes)
	if !found { return .Malformed }
	// Check the original state bytes, before defaults or larger fixed arrays
	// are introduced by decoding. Version 1 used this same canonical payload.
	// Re-marshaling into today's type would reject every valid older schema.
	if checksum(payload) != header.checksum { return .Checksum_Mismatch }
	staged := new(Saved_State(T), staging)
	if json.unmarshal(payload, staged, allocator = staging) != nil { return .Malformed }
	if !campaign_valid(&staged.campaign) { return .Invalid_State }
	owned := new(Saved_State(T), staging)
	if json.unmarshal(payload, owned, allocator = allocator) != nil { return .Malformed }
	c^ = owned.campaign; snapshot^ = owned.snapshot
	return .Loaded
}

// The envelope is already JSON-validated by unmarshal. Token boundaries keep
// braces inside strings harmless, and reject ambiguous duplicate state keys.
@(private)
slot_payload :: proc(bytes: []u8) -> (payload: []u8, found: bool) {
	tokens := json.make_tokenizer(string(bytes))
	depth := 0
	for {
		token, err := json.get_token(&tokens)
		if token.kind == .EOF { break }
		if err != nil { return nil, false }
		if depth == 1 && token.kind == .String && token.text == "\"state\"" {
			if found { return nil, false }
			colon, colon_err := json.get_token(&tokens)
			first, first_err := json.get_token(&tokens)
			if colon_err != nil || first_err != nil || colon.kind != .Colon || first.kind != .Open_Brace { return nil, false }
			nested := 1
			for nested > 0 {
				last, last_err := json.get_token(&tokens)
				if last_err != nil || last.kind == .EOF { return nil, false }
				if last.kind == .Open_Brace || last.kind == .Open_Bracket { nested += 1 }
				if last.kind == .Close_Brace || last.kind == .Close_Bracket { nested -= 1 }
				if nested == 0 { payload = bytes[first.offset:last.offset+1]; found = true }
			}
			continue
		}
		if token.kind == .Open_Brace || token.kind == .Open_Bracket { depth += 1 }
		if token.kind == .Close_Brace || token.kind == .Close_Bracket { depth -= 1 }
	}
	return payload, found
}
delete_slot :: proc(path: string, first_confirmation, second_confirmation: bool) -> bool {
	if path == "" || !first_confirmation || !second_confirmation { return false }
	if !os.exists(path) { return true }
	return os.remove(path) == nil
}
load_status_text :: proc(status: Load_Status) -> string {
	switch status {
	case .Loaded: return "Pronto"
	case .Missing: return "Nuova memoria"
	case .Unreadable: return "Impossibile leggere il salvataggio"
	case .Too_Large: return "Salvataggio troppo grande"
	case .Malformed: return "Salvataggio danneggiato: file conservato"
	case .Wrong_Version: return "Versione del salvataggio non compatibile"
	case .Checksum_Mismatch: return "Salvataggio alterato: file conservato"
	case .Invalid_State: return "Stato del salvataggio non valido: file conservato"
	}
	return ""
}
