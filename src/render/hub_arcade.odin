package render

import "core:math"
import rl "vendor:raylib"
import hubworld "../hubworld"
import ui "../engine/ui"

// INSIDE THE ARCADE HALL (hubworld/arcade.odin has the rules): the same octagonal hall
// as the other rooms, in lime. Twelve places in a half circle: a lit cabinet, in the
// colours of its game, with its best stars on the marquee, for each unlocked game;
// a cabinet under a plain cloth, with no sign, for each one not yet unlocked.

HUB_ARCADE_WALL :: rl.Color{148, 239, 61, 255}

@(private="file")
hub_arcade_color :: proc(game: int) -> rl.Color {
	return rl.ColorFromHSV(hubworld.arcade_hue(game), 0.7, 1.0)
}

// A lit cabinet: base, control panel with buttons, a screen that shows moving blocks in
// the game's colour, a glowing marquee and, over it, the stars of the record.
@(private="file")
hub_arcade_cabinet :: proc(color: rl.Color, stars: u8, time: f32, phase: f32) {
	body := rl.Color{30, 35, 46, 255}
	hub_box({0, 0.6, 0}, {1.8, 1.2, 1.5}, body, color)
	hub_box({0, 1.25, 0.5}, {1.8, 0.14, 0.75}, HUB_SOLID_DARK, color)
	for i in 0..<3 {
		rl.DrawSphere({-0.45+f32(i)*0.45, 1.36, 0.6}, 0.07, color if i != 1 else rl.Color{240, 240, 240, 255})
	}
	hub_box({0, 2.0, 0.05}, {1.8, 1.6, 1.3}, body, color)
	hub_box({0, 1.95, 0.7}, {1.5, 1.05, 0.06}, {6, 8, 16, 255}, color)
	// The game on the screen: a few blocks sliding about, as in any cabinet.
	for i in 0..<4 {
		x := 0.6*math.sin(time*(0.9+f32(i)*0.35)+phase+f32(i)*1.7)
		y := 1.95+0.35*math.sin(time*(1.3+f32(i)*0.4)+f32(i)*2.3+phase)
		rl.DrawCubeV({x, y, 0.74}, {0.2, 0.14, 0.03}, hub_fade(color, 0.85))
	}
	hub_box({0, 2.75, 0.45}, {1.8, 0.4, 0.5}, hub_fade(color, 0.35), color)
	for i in 0..<3 {
		lit := i < int(stars)
		fill := rl.Color{255, 214, 90, 255} if lit else rl.Color{50, 54, 70, 255}
		hub_box({-0.4+f32(i)*0.4, 3.15, 0.45}, {0.22, 0.22, 0.22}, fill, rl.Color{255, 240, 190, 255} if lit else rl.Color{80, 86, 108, 255})
	}
}

// A cabinet not yet unlocked: only a cloth over a shape, with no sign and no colour
// that could say which game it is.
@(private="file")
hub_arcade_covered :: proc(s: hubworld.Station) {
	hx, hz, h := s.half.x, s.half.y, s.height
	cloth := rl.Color{62, 68, 90, 255}
	edge := rl.Color{110, 118, 150, 255}
	hub_box({0, h*0.5-0.1, 0}, {hx*2+0.2, h-0.2, hz*2+0.2}, cloth, edge)
	hub_box({0, h-0.1, 0.1}, {hx*2+0.3, 0.25, hz*2+0.1}, cloth, edge)
	for i in 0..<5 {
		x := (f32(i)-2)*0.35
		hub_box({x, h*0.5-0.2, hz+0.12}, {0.08, h-0.7+0.2*f32(i%2), 0.05}, {80, 88, 114, 255}, edge)
	}
}

// The hall, in 3D from `camera`. `hovered` is the station under the pointer.
draw_hub_arcade :: proc(room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, hovered: Maybe(int), view: hubworld.Arcade_View) {
	rl.BeginMode3D(camera)
	defer rl.EndMode3D()
	hub_room_floor(room, w.time)
	hub_room_walls(room, HUB_ARCADE_WALL, false, 0)
	for k in 0..<room.count {
		s := room.stations[k]
		is_hovered := false
		if h, ok := hovered.?; ok && h == k { is_hovered = true }
		if s.decor {
			// A covered place has only its outline.
			hub_frame_at(s.center, hubworld.station_yaw(s))
			rl.DrawCubeWiresV({0, 0.03, 0}, {s.half.x*2, 0.03, s.half.y*2}, rl.Color{70, 78, 100, 255})
			hub_frame_end()
			continue
		}
		color := HUB_CYAN if k == room.exit else hub_arcade_color(view.game[k])
		hub_room_ground_marks(s, color, is_hovered, w.time, f32(k))
	}
	for k in 0..<room.count {
		s := room.stations[k]
		hub_frame_at(s.center, hubworld.station_yaw(s))
		switch {
		case k == room.exit: hub_casino_plaza_door(s, HUB_CYAN)
		case s.decor: hub_arcade_covered(s)
		case: hub_arcade_cabinet(hub_arcade_color(view.game[k]), view.stars[k], w.time, f32(k))
		}
		hub_frame_end()
	}
	hub_draw_robot_at(w.position, w.facing_left, w.moving, w.stride, w.time, camera)
}

// The name plates over the lit cabinets (the record while the robot is near or the
// pointer is on one) and the way out; the covered ones have none.
draw_hub_arcade_labels :: proc(theme: ^ui.Theme, room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, canvas_width, canvas_height: f32,
	hovered: Maybe(int), view: hubworld.Arcade_View) {
	// Twelve plates side by side would cover each other: they stand at three heights in turn,
	// and the one the robot is near, or the pointer is on, is drawn last, on top.
	for pass in 0..<2 {
		for k in 0..<room.count {
			s := room.stations[k]
			if s.decor { continue }
			is_hovered := false
			if h, ok := hovered.?; ok && h == k { is_hovered = true }
			expanded := is_hovered || hubworld.station_distance(s, w.position) < 4
			if (pass == 1) != expanded { continue }
			name, subtitle, color := s.name, s.subtitle, HUB_CYAN
			if k != room.exit { name, subtitle, color = view.title[k], view.record[k], hub_arcade_color(view.game[k]) }
			at := rl.GetWorldToScreenEx({s.center.x, s.height+1.2, s.center.y}, camera, i32(canvas_width), i32(canvas_height))
			if k != room.exit { at.y -= f32(k%3)*30 }
			hub_draw_plate(theme, at, name, subtitle, color, expanded, is_hovered)
		}
	}
}
