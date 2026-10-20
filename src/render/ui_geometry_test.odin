package render

import rl "vendor:raylib"
import view "../engine/view"

// Independent test geometry shared by menus; do not use production hit-tests
// as the oracle for their own bounds and overlap checks.
rectangle_center :: proc(bounds: rl.Rectangle) -> view.Vec2 {
	return {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
}

rectangles_overlap :: proc(first, second: rl.Rectangle) -> bool {
	return first.x < second.x+second.width && first.x+first.width > second.x &&
	       first.y < second.y+second.height && first.y+first.height > second.y
}
