package artifacts

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

DIRECTORY :: "build/captures"

ensure_directory :: proc(path: string = DIRECTORY) -> bool {
	err := os.make_directory_all(path)
	return err == nil || (err == .Exist && os.is_directory(path))
}

// Native captures share one ignored output directory. Names stay compatible
// with existing comparisons; no process-wide current-directory changes.
screenshot :: proc(name: cstring) {
	if !ensure_directory() {
		fmt.eprintln("Cannot create capture directory:", DIRECTORY)
		return
	}
	rl.TakeScreenshot(fmt.ctprintf("%s/%s", DIRECTORY, name))
}

write_report :: proc(name: string, bytes: []u8) -> bool {
	if !ensure_directory() { return false }
	return os.write_entire_file(fmt.tprintf("%s/%s", DIRECTORY, name), bytes) == nil
}
