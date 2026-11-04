package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"

// The flame goes from white at the nozzle to red at the tip.
@(test)
test_flame_colour_from_nozzle_to_tip :: proc(t: ^testing.T) {
	near, tip := flame_color(0), flame_color(1)
	testing.expect(t, near.b > 200 && near.g > 200)
	testing.expect(t, tip.r > 150 && tip.g < 80 && tip.b < 50)
	testing.expect(t, flame_color(0.5).g < near.g && flame_color(0.5).g > tip.g)
}

// The paper model fits the kit's parts, and its nozzle points exactly the way the rules turn him, whichever way that is.
@(test)
test_flame_model_points_where_he_turns :: proc(t: ^testing.T) {
	feet := rl.Vector3{5.5, 0.1, 7.5}
	model: Napoli_Model
	flame_model(&model, feet, 0, 0)
	testing.expect(t, model.count > 20 && model.count < NAPOLI_MODEL_PARTS)
	for yaw in ([4]f32{0, 1, -2.2, math.PI}) {
		nozzle := flame_nozzle(feet, yaw)
		grip := napoli_model_point(napoli_model_frame(feet, flame_way(yaw)), {FLAME_GRIP_SIDE, FLAME_GRIP_HEIGHT+0.015, 0})
		way := rl.Vector3Normalize(nozzle-grip)
		testing.expect(t, abs(way.x-math.cos(yaw)) < 0.001 && abs(way.z-math.sin(yaw)) < 0.001)
	}
}

// Every card of the view's family has a place in the rules: this one stays on the board.
@(test)
test_flame_keeps_the_board_camera :: proc(t: ^testing.T) {
	testing.expect(t, game.FIRST_PERSON_WEAPONS[.Flamethrower].on_board)
	testing.expect(t, !game.FIRST_PERSON_WEAPONS[.Flamethrower].third_person)
}
