package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import view "../view"

draw_tactical_legend :: proc(renderer: ^Renderer) {
	x := c.int(renderer.canvas_width)-288
	rl.DrawRectangle(x, 38, 274, 75, rl.Color{12, 15, 18, 230})
	rl.DrawText("PURPLE: NEXT BOMB LANDING", x+10, 46, 10, rl.Color{214, 145, 235, 255})
	rl.DrawText("2 ACTIONS LEFT", x+10, 62, 10, rl.Color{255, 197, 85, 255})
	rl.DrawText("1 ACTION LEFT", x+145, 62, 10, rl.Color{255, 106, 83, 255})
	rl.DrawText("BLAST: 4 DAMAGE / 3X3 / HITS ALL", x+10, 78, 10, rl.Color{213, 217, 208, 255})
	rl.DrawText("RECOVER: ENEMY RESTS THIS PULSE", x+10, 94, 10, rl.Color{105, 215, 183, 255})
}

draw_explosive_body :: proc(renderer: ^Renderer, kind: game.Grid_Object_Kind, center: view.Vec2, opacity: f32) {
	radius := max(f32(8), 12*renderer.camera.zoom)
	dark := color_with_opacity(rl.Color{44, 32, 32, 255}, opacity)
	gold := color_with_opacity(rl.Color{245, 179, 75, 255}, opacity)
	if kind == .Barrel {
		rect := rl.Rectangle{center.x-radius, center.y-radius*1.7, radius*2, radius*2}
		rl.DrawRectangleRounded(rect, 0.28, 6, color_with_opacity(rl.Color{158, 65, 43, 255}, opacity))
		rl.DrawRectangleLinesEx(rect, 2, dark)
		bands := [?]f32{-1.2, -0.1}
		for offset in bands {
			rl.DrawLineEx({center.x-radius, center.y+radius*offset},
				{center.x+radius, center.y+radius*offset}, max(f32(2), radius*0.23), gold)
		}
	} else {
		rl.DrawCircleV({center.x, center.y-radius*0.35}, radius, dark)
		rl.DrawCircleLinesV({center.x, center.y-radius*0.35}, radius, gold)
	}
	rl.DrawLineEx({center.x, center.y-radius*1.5}, {center.x+radius*0.5, center.y-radius*2.1}, 2, gold)
}

draw_blast_area :: proc(renderer: ^Renderer, room: ^game.Room, center: grid.Position, color: rl.Color, fill_alpha: u8) {
	fill := color
	fill.a = fill_alpha
	for y in center.y-1..=center.y+1 {
		for x in center.x-1..=center.x+1 {
			position := grid.Position{x, y}
			if game.explosion_contains_cell(room, center, position) {
				draw_diamond(inset_vertices(tile_vertices(renderer, position), 0.91), fill, color)
			}
		}
	}
}

draw_armed_blast_area :: proc(renderer: ^Renderer, room: ^game.Room, position: grid.Position, deadline, pulse: u64) {
	if deadline == 0 {
		return
	}
	color := rl.Color{238, 169, 62, 195}
	if game.explosive_pulses_remaining(deadline, pulse) <= 1 {
		color = {255, 88, 65, 235}
	}
	draw_blast_area(renderer, room, position, color, 42)
}

draw_explosive_ground :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		presentation := &renderer.timeline.view
		for object in presentation.objects[:presentation.object_count] {
			if object.visible {
				draw_armed_blast_area(renderer, room, {int(object.position.x), int(object.position.y)},
					object.detonation_pulse, presentation.pulse_count)
			}
		}
		if cue, found := active_presentation_cue(&renderer.timeline); found && cue.kind == .Explosion && cue.started {
			alpha := u8(150*(1-presentation_cue_progress(cue)))
			draw_blast_area(renderer, room, cue.event.from_position, rl.Color{255, 202, 91, 255}, alpha)
		}
	} else {
		for enemy in room.enemies {
			if enemy.intent.kind == .Bombard {
				draw_blast_area(renderer, room, enemy.intent.destination, rl.Color{199, 126, 224, 160}, 15)
			}
		}
		for object in room.objects {
			draw_armed_blast_area(renderer, room, object.position, object.detonation_pulse, room.pulse_count)
		}
	}
}

draw_fuse_label :: proc(renderer: ^Renderer, center: view.Vec2, deadline, pulse: u64) {
	if deadline == 0 {
		return
	}
	remaining := game.explosive_pulses_remaining(deadline, pulse)
	label := fmt.ctprintf("%d", remaining)
	color := rl.Color{255, 197, 85, 255} if remaining > 1 else rl.Color{255, 106, 83, 255}
	x := c.int(center.x)-8
	y := c.int(center.y-max(f32(29), 34*renderer.camera.zoom))
	rl.DrawRectangle(x-3, y-2, 22, 21, rl.Color{21, 20, 26, 245})
	rl.DrawRectangleLines(x-3, y-2, 22, 21, color)
	rl.DrawText(label, x+3, y, 17, color)
}

draw_explosive_countdowns :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		presentation := &renderer.timeline.view
		for &object in presentation.objects[:presentation.object_count] {
			if object.visible {
				draw_fuse_label(renderer, presentation_grid_object_center(renderer, &object),
					object.detonation_pulse, presentation.pulse_count)
			}
		}
	} else {
		for object in room.objects {
			draw_fuse_label(renderer, cell_center(renderer, object.position), object.detonation_pulse, room.pulse_count)
		}
	}
}
