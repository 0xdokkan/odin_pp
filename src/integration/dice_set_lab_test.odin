package integration
import devtools "../devtools"

import "core:testing"
import render "../render"

@(test)
test_dice_lab_cosmetic_results_keep_real_die_ranges_and_replay_locally :: proc(t: ^testing.T) {
	first := render.Dice_Cosmetic_Random{0xABC123}
	second := first
	for _ in 0..<32 {
		for kind in devtools.DICE_SET_LAB_KINDS {
			value := devtools.dice_set_lab_result(&first,kind)
			testing.expect_value(t,value,devtools.dice_set_lab_result(&second,kind))
			maximum: i32
			switch kind {
			case .D4: maximum=4
			case .D6: maximum=6
			case .D8: maximum=8
			case .D10: maximum=10
			case .D12: maximum=12
			case .D20: maximum=20
			case .D100:
				testing.expect(t,value >= 0 && value <= 90 && value%10 == 0)
				continue
			case .Count: testing.expect(t,false); continue
			}
			testing.expect(t,value >= 1 && value <= maximum)
		}
	}
}

@(test)
test_dice_lab_mouse_controls_do_not_overlap_specimens :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width,renderer.canvas_height=960,540
	for index in 0..<len(devtools.DICE_SET_LAB_KINDS) {
		card := devtools.dice_set_lab_card_bounds(renderer,index)
		testing.expect(t,card.x >= 0 && card.x+card.width <= renderer.canvas_width)
		testing.expect(t,card.y > 48 && card.y+card.height <= renderer.canvas_height-38)
		point := [2]f32{card.x+card.width/2,card.y+card.height/2}
		testing.expect_value(t,devtools.dice_set_lab_control_at_point(renderer,-1,{point[0],point[1]}),devtools.Dice_Set_Lab_Control.None)
	}
	for control in ([4]devtools.Dice_Set_Lab_Control{.Roll,.Rotate,.Overview,.Close}) {
		button := devtools.dice_set_lab_control_bounds(renderer,control)
		point := [2]f32{button.x+button.width/2,button.y+button.height/2}
		testing.expect_value(t,devtools.dice_set_lab_control_at_point(renderer,1,{point[0],point[1]}),control)
		if control == .Overview {
			testing.expect_value(t,devtools.dice_set_lab_control_at_point(renderer,-1,{point[0],point[1]}),devtools.Dice_Set_Lab_Control.None)
		}
	}
}
