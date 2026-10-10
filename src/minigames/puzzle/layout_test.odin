package puzzle

import "core:testing"
import rl "vendor:raylib"
import ui "../../engine/ui"

@(test)
test_all_crypts_leave_room_for_hud_and_commands :: proc(t: ^testing.T) {
	// Check real boards, including the largest late crypts. The board's upper
	// wall extrusion must not hide the HUD or its short status message.
	canvases := [2]rl.Rectangle{{0, 0, 960, 540}, {0, 0, 1280, 720}}
	for canvas in canvases {
		for level in LEVELS {
			board, _, err := parse_level(level.rows)
			testing.expect_value(t, err, Parse_Error.None)
			layout := compute_layout(&board, canvas)
			testing.expect(t, layout.origin.x >= 16)
			testing.expect(t, layout.origin.x + f32(board.width)*layout.tile <= canvas.width - 16)
			testing.expect(t, layout.origin.y - f32(WALL_FRONT_PX)*layout.scale >= f32(ui.HUD_MARGIN + ui.HUD_TOP_HEIGHT + 30))
			testing.expect(t, layout.origin.y + f32(board.height)*layout.tile <= canvas.height - 32)
		}
	}
}
