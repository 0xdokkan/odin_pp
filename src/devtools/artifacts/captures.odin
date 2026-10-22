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
	// raylib 6's TakeScreenshot multiplies the already-physical render size
	// by the Retina scale again. Read the measured framebuffer directly, so
	// captures retain native pixels without three black overflow quadrants.
	image:=rl.LoadImageFromScreen()
	if !rl.IsImageValid(image) {fmt.eprintln("Cannot read screenshot framebuffer");return}
	defer rl.UnloadImage(image)
	if !rl.ExportImage(image,fmt.ctprintf("%s/%s",DIRECTORY,name)) {
		fmt.eprintln("Cannot write screenshot:",name)
	}
}

write_report :: proc(name: string, bytes: []u8) -> bool {
	if !ensure_directory() { return false }
	return os.write_entire_file(fmt.tprintf("%s/%s", DIRECTORY, name), bytes) == nil
}
