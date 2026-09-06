package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

draw_cooperative_enemy_body :: proc(renderer: ^Renderer, enemy: game.Enemy, center: view.Vec2, opacity: f32) {
	radius := enemy_draw_radius(renderer, enemy)
	if enemy.archetype == .Custodian {
		color := color_with_opacity(rl.Color{89, 199, 181, 255}, opacity)
		dark := color_with_opacity(rl.Color{29, 64, 66, 255}, opacity)
		rl.DrawCircleV(to_raylib(center), radius, dark)
		rl.DrawCircleV(to_raylib(center), radius-2, color)
		shield := Tile_Vertices{
			top = {center.x, center.y-radius*1.25},
			left = {center.x-radius*0.8, center.y-radius*0.4},
			bottom = {center.x, center.y+radius*0.9},
			right = {center.x+radius*0.8, center.y-radius*0.4},
		}
		draw_diamond(shield, dark, color)
		return
	}
	color := rl.Color{220, 154, 63, 255} if enemy.boss_phase < 2 else rl.Color{240, 84, 71, 255}
	color = color_with_opacity(color, opacity)
	dark := color_with_opacity(rl.Color{43, 31, 46, 255}, opacity)
	rect := rl.Rectangle{center.x-radius, center.y-radius, radius*2, radius*2}
	rl.DrawRectangleRounded(rect, 0.15, 4, dark)
	rl.DrawRectangleLinesEx(rect, max(f32(2), 3*renderer.camera.zoom), color)
	for side in -1..=1 {
		if side == 0 {
			continue
		}
		rl.DrawCircleV({center.x+f32(side)*radius*0.85, center.y-radius*0.65}, radius*0.43, color)
		rl.DrawCircleV({center.x+f32(side)*radius*0.85, center.y-radius*0.65}, radius*0.24, dark)
	}
}

draw_encounter_ground :: proc(renderer: ^Renderer, room: ^game.Room) {
	busy := renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid
	modifier := &room.modifier
	pulse := room.pulse_count
	phase := room.phase
	if busy {
		modifier = &renderer.timeline.view.modifier
		pulse = renderer.timeline.view.pulse_count
		phase = renderer.timeline.view.phase
	}
	if phase != .Combat {
		return
	}
	flashing := false
	progress: f32
	if busy {
		if cue, found := active_presentation_cue(&renderer.timeline); found && cue.started && cue.kind == .Room_Hazard_Triggered {
			flashing = true
			progress = presentation_cue_progress(cue)
		}
	}
	if flashing || game.room_modifier_warning_active(modifier, pulse) {
		remaining := game.room_modifier_pulses_remaining(modifier, pulse)
		color := rl.Color{239, 143, 49, 200}
		if remaining <= 1 {
			color = {255, 72, 59, 235}
		}
		fill := color
		fill.a = 35
		if flashing {
			color = {255, 216, 105, 255}
			fill = {255, 132, 41, u8(160*(1-progress))}
		}
		for cell in modifier.cells[:modifier.cell_count] {
			draw_diamond(inset_vertices(tile_vertices(renderer, cell), 0.65), fill, color)
			center := cell_center(renderer, cell)
			radius := max(f32(3), 4*renderer.camera.zoom)
			rl.DrawTriangle({center.x, center.y-radius}, {center.x-radius, center.y+radius},
				{center.x+radius, center.y+radius}, color)
		}
	}
	if !busy {
		for enemy in room.enemies {
			if enemy.intent.kind != .Protect {
				continue
			}
			from := cell_center(renderer, enemy.intent.origin)
			to := cell_center(renderer, enemy.intent.destination)
			color := rl.Color{102, 216, 218, 215}
			rl.DrawLineEx(to_raylib(from), to_raylib(to), max(f32(1.5), 2*renderer.camera.zoom), color)
			draw_diamond(inset_vertices(tile_vertices(renderer, enemy.intent.destination), 0.7),
				rl.Color{59, 194, 183, 35}, color)
		}
	}
}

encounter_boss_status :: proc(renderer: ^Renderer, room: ^game.Room) -> (health, maximum, phase: i32, found: bool) {
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		for enemy in renderer.timeline.view.enemies[:renderer.timeline.view.enemy_count] {
			if enemy.visible && enemy.archetype == .Demolitionist {
				return enemy.health, enemy.max_health, enemy.boss_phase, true
			}
		}
	} else {
		for enemy in room.enemies {
			if enemy.archetype == .Demolitionist {
				return enemy.health, enemy.max_health, enemy.boss_phase, true
			}
		}
	}
	return
}

draw_encounter_status :: proc(renderer: ^Renderer, room: ^game.Room) {
	modifier := &room.modifier
	pulse := room.pulse_count
	if renderer_timeline_is_busy(renderer) && renderer.timeline.view.valid {
		modifier = &renderer.timeline.view.modifier
		pulse = renderer.timeline.view.pulse_count
	}
	x := c.int(renderer.canvas_width)-288
	if modifier.kind != .None {
		rl.DrawRectangle(x, 118, 274, 51, rl.Color{12, 15, 18, 235})
		remaining := game.room_modifier_pulses_remaining(modifier, pulse)
		label := fmt.ctprintf("FURNACE: FIRE IN %d ACTIONS", remaining)
		color := rl.Color{255, 187, 91, 255}
		if !game.room_modifier_warning_active(modifier, pulse) {
			label = "FURNACE: COOLING"
			color = rl.Color{152, 177, 185, 255}
		}
		if cue, active := active_presentation_cue(&renderer.timeline); active && cue.started && cue.kind == .Room_Hazard_Triggered {
			label = "FURNACE: FIRING"
			color = {255, 216, 105, 255}
		}
		rl.DrawText(label, x+10, 128, 10, color)
		rl.DrawText(fmt.ctprintf("MARKED LANE / %d DAMAGE TO ALL", modifier.damage), x+10, 145, 10,
			rl.Color{200, 205, 197, 255})
	} else if room.encounter_kind == .Escort {
		rl.DrawRectangle(x, 118, 274, 51, rl.Color{12, 15, 18, 235})
		rl.DrawText("CUSTODIAN: SHIELDS ITS MARKED ALLY", x+10, 128, 10, rl.Color{102, 216, 218, 255})
		rl.DrawText("SHOVE EITHER ONE TO BREAK THE PLAN", x+10, 145, 10, rl.Color{200, 205, 197, 255})
	}
	if health, maximum, phase, found := encounter_boss_status(renderer, room); found {
		color := rl.Color{240, 186, 81, 255} if phase < 2 else rl.Color{250, 101, 85, 255}
		rl.DrawRectangle(14, 123, 266, 63, rl.Color{12, 15, 18, 240})
		rl.DrawText(fmt.ctprintf("DEMOLITIONIST / PHASE %d", phase), 24, 132, 12, color)
		rl.DrawRectangle(24, 153, 190, 8, rl.Color{67, 43, 49, 255})
		if maximum > 0 {
			rl.DrawRectangle(24, 153, c.int(190*f32(health)/f32(maximum)), 8, color)
		}
		rl.DrawText(fmt.ctprintf("%d/%d", health, maximum), 222, 151, 10, color)
		rhythm: cstring = "BOMB > REST 1 > CHARGE > REST 2"
		if phase >= 2 { rhythm = "BOMB > BOMB > CHARGE > REST 2" }
		rl.DrawText(rhythm, 24, 169, 10, rl.Color{184, 190, 184, 255})
	}
}
