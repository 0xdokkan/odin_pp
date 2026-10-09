// Versioned JSON files written atomically (temporary file, then rename), so
// a crash mid-save never leaves a truncated file. Generalises the M8 profile
// persistence for every game mode.
package save

import "core:encoding/json"
import "core:fmt"
import "core:os"

Load_Status :: enum u8 {
	Loaded,
	Missing,      // no file yet: start from defaults
	Too_Large,
	Unreadable,
	Malformed,
	Wrong_Version,
}

@(private)
Envelope :: struct($T: typeid) {
	version: int,
	data:    T,
}

// Serialises `value` with its schema version and replaces `path` atomically.
write :: proc(path: string, version: int, value: $T) -> bool {
	bytes, err := json.marshal(Envelope(T){version = version, data = value}, {pretty = true})
	if err != nil {
		return false
	}
	defer delete(bytes)
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, bytes) != nil {
		return false
	}
	if os.rename(temporary, path) != nil {
		os.remove(temporary)
		return false
	}
	return true
}

// Reads a file written by `write`. On any failure the file is left untouched
// and `value` stays zero, so callers can fall back to defaults and decide
// whether to overwrite a corrupt file.
read :: proc(path: string, version: int, $T: typeid, max_bytes := 64 * 1024,
	allocator := context.allocator) -> (value: T, status: Load_Status) {
	if !os.exists(path) {
		return {}, .Missing
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return {}, .Unreadable
	}
	if len(data) > max_bytes {
		return {}, .Too_Large
	}
	envelope: Envelope(T)
	if json.unmarshal(data, &envelope, allocator = allocator) != nil {
		return {}, .Malformed
	}
	if envelope.version != version {
		return {}, .Wrong_Version
	}
	return envelope.data, .Loaded
}

// Per-user writable location for an application, created on demand. Falls
// back to the working directory when the platform reports no data folder.
user_file :: proc(app_name, file_name: string, allocator := context.allocator) -> string {
	base, err := os.user_data_dir(context.temp_allocator)
	if err != nil || base == "" {
		return fmt.aprintf("%s", file_name, allocator = allocator)
	}
	dir, join_err := os.join_path({base, app_name}, context.temp_allocator)
	if join_err != nil {
		return fmt.aprintf("%s", file_name, allocator = allocator)
	}
	if !os.exists(dir) {
		os.make_directory(dir)
	}
	path, path_err := os.join_path({dir, file_name}, allocator)
	if path_err != nil {
		return fmt.aprintf("%s", file_name, allocator = allocator)
	}
	return path
}
