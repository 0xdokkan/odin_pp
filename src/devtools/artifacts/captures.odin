package artifacts

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"

DIRECTORY :: "build/captures"

ensure_directory :: proc(path: string = DIRECTORY) -> bool {
	err := os.make_directory_all(path)
	return err == nil || (err == .Exist && os.is_directory(path))
}

// Native captures share one ignored output directory. Names stay compatible
// with existing comparisons; no process-wide current-directory changes.
screenshot :: proc(name: cstring, crop: rl.Rectangle = {}) {
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
	// Optional normalized crop, still native framebuffer pixels: no scaling,
	// resampling, or substitute artwork in actor-detail captures.
	if crop.width>0 && crop.height>0 {
		x,y:=clamp(crop.x,0,1),clamp(crop.y,0,1)
		// Whole pixels: raylib's crop with a fraction of a row runs past the image, and on Windows that ends the process.
		left,top:=math.floor(x*f32(image.width)),math.floor(y*f32(image.height))
		wide:=min(math.floor(min(crop.width,1-x)*f32(image.width)),f32(image.width)-left)
		high:=min(math.floor(min(crop.height,1-y)*f32(image.height)),f32(image.height)-top)
		if wide>=1 && high>=1 {rl.ImageCrop(&image,{left,top,wide,high})}
	}
	if !rl.ExportImage(image,fmt.ctprintf("%s/%s",DIRECTORY,name)) {
		fmt.eprintln("Cannot write screenshot:",name)
	}
}

write_report :: proc(name: string, bytes: []u8) -> bool {
	if !ensure_directory() { return false }
	return os.write_entire_file(fmt.tprintf("%s/%s", DIRECTORY, name), bytes) == nil
}
