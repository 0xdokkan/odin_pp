package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import hubworld "../hubworld"
import ui "../engine/ui"

// INSIDE THE DEPOT (hubworld/depot.odin has the rules): the same octagonal hall as the
// casino's, in blue. The backpack lies on its mat; the mannequin on its plinth wears
// the weapon and relics the backpack really holds; the card archive is a terminal whose
// screen is a shelf of card spines that light up as cards are discovered; the crates
// pile up with what the depot holds; and the way out to the plaza is in the wall.

HUB_DEPOT_WALL :: rl.Color{76, 164, 232, 255}

hub_depot_color :: proc(s: hubworld.Depot_Station) -> rl.Color {
	switch s {
	case .Backpack: return {242, 150, 70, 255}
	case .Character: return {120, 220, 255, 255}
	case .Archive: return {190, 130, 255, 255}
	case .Plaza: return {76, 164, 232, 255}
	case .Crates: return {120, 190, 240, 255}
	}
	return rl.WHITE
}

// A colour for a variant of a weapon or relic: the same variant is always the same colour.
@(private="file")
hub_variant_color :: proc(variant: i32, salt: i32) -> rl.Color {
	hue := f32((variant*67+salt*131)%360)
	return rl.ColorFromHSV(hue, 0.6, 1.0)
}

@(private="file")
hub_depot_backpack :: proc(s: hubworld.Station, color: rl.Color) {
	// The mat it lies on: the door's patch is its front edge.
	rl.DrawCubeV({0, 0.025, 0.55}, {2.6, 0.05, 2.5}, HUB_SOLID_DARK)
	rl.DrawCubeWiresV({0, 0.03, 0.55}, {2.6, 0.05, 2.5}, color)
	body := rl.Color{196, 118, 58, 255}
	hub_box({0, 0.6, 0}, {1.1, 1.0, 0.8}, body, color)
	hub_box({0, 1.15, 0.08}, {1.1, 0.25, 0.9}, {170, 96, 44, 255}, color)
	hub_box({0, 0.5, 0.45}, {0.7, 0.5, 0.15}, {170, 96, 44, 255}, color)
	for sx in ([2]f32{-1, 1}) { hub_box({sx*0.6, 0.6, 0.05}, {0.1, 0.8, 0.5}, {60, 50, 44, 255}, color) }
	_ = s
}

// A mannequin on its plinth, wearing `gear`.
@(private="file")
hub_depot_mannequin :: proc(s: hubworld.Station, color: rl.Color, gear: hubworld.Gear, time: f32) {
	hub_prism({0, 0, 0}, 1.3, 1.3, 0.35, 8, HUB_SOLID, color)
	for k in 0..<2 { rl.DrawCircle3D({0, 0.37, 0}, 1.45-f32(k)*0.15, {1, 0, 0}, 90, hub_fade(color, 0.8)) }
	wood := rl.Color{232, 224, 205, 255}
	base := f32(0.35)
	for sx in ([2]f32{-1, 1}) { hub_box({sx*0.17, base+0.55, 0}, {0.2, 1.1, 0.2}, wood, color) }
	hub_box({0, base+1.5, 0}, {0.62, 0.9, 0.3}, wood, color)
	for sx in ([2]f32{-1, 1}) { hub_box({sx*0.45, base+1.45, 0}, {0.15, 0.85, 0.15}, wood, color) }
	hub_box({0, base+2.05, 0}, {0.12, 0.15, 0.12}, wood, color)
	rl.DrawSphere({0, base+2.3, 0}, 0.25, wood)
	// The weapon, in the right hand (to the viewer's left): a spear for the Storm Pike, a blade otherwise.
	if gear.has_weapon {
		tint := hub_variant_color(gear.weapon, 1)
		if gear.weapon == i32(game.Weapon_Id.Storm_Pike) {
			hub_box({-0.6, base+1.55, 0.12}, {0.07, 2.9, 0.07}, {150, 116, 80, 255}, color)
			hub_box({-0.6, base+3.1, 0.12}, {0.2, 0.34, 0.05}, tint, color)
		} else {
			hub_box({-0.6, base+1.0, 0.12}, {0.12, 0.95, 0.05}, tint, color)
			hub_box({-0.6, base+0.48, 0.12}, {0.4, 0.08, 0.08}, {150, 116, 80, 255}, color)
		}
	}
	// The relics hang in the air round the head, turning.
	for relic in 0..<hubworld.MANNEQUIN_RELICS {
		if !gear.has_relic[relic] { continue }
		a := time*0.8+f32(relic)*math.TAU/f32(hubworld.MANNEQUIN_RELICS)
		bob := 0.1*math.sin(time*1.7+f32(relic))
		at := rl.Vector3{math.cos(a)*0.95, base+2.7+bob, math.sin(a)*0.95}
		tint := hub_variant_color(gear.relic[relic], 2)
		rl.DrawCubeV(at, {0.2, 0.2, 0.2}, tint)
		rl.DrawCubeWiresV(at, {0.2, 0.2, 0.2}, rl.WHITE)
	}
	_ = s
}

// The archive: a terminal whose screen is a shelf of card spines, `lit` of them on.
@(private="file")
hub_depot_archive :: proc(s: hubworld.Station, color: rl.Color, lit: int, time: f32) {
	hx, hz, h := s.half.x, s.half.y, s.height
	hub_box({0, h*0.5-0.2, 0}, {hx*2, h-0.4, hz*2}, HUB_SOLID, color)
	hub_box({0, 0.5, hz+0.4}, {hx*2-0.6, 0.12, 0.6}, HUB_SOLID_DARK, color)
	screen := rl.Vector3{hx*2-0.5, h-1.3, 0.05}
	columns, rows := 12, 5
	cell_width, cell_height := (screen.x-0.3)/f32(columns), (screen.y-0.3)/f32(rows)
	// The screen is on both faces: the terminal stands between the robot and the camera.
	for side in ([2]f32{1, -1}) {
		at_screen := rl.Vector3{0, h*0.5+0.1, side*(hz+0.03)}
		hub_box(at_screen, screen, {8, 10, 22, 255}, color)
		for index in 0..<columns*rows {
			column, row := index%columns, index/columns
			x := side*(-screen.x*0.5+0.15+cell_width*(f32(column)+0.5))
			y := at_screen.y+screen.y*0.5-0.15-cell_height*(f32(row)+0.5)
			fill := rl.Color{38, 42, 60, 255}
			if index < lit {
				shimmer := 0.75+0.25*math.sin(time*2.2+f32(index)*0.7)
				fill = hub_fade(rl.ColorFromHSV(f32((index*37)%360), 0.65, 1.0), shimmer)
			}
			rl.DrawCubeV({x, y, at_screen.z+side*0.04}, {cell_width*0.7, cell_height*0.8, 0.03}, fill)
		}
	}
}

@(private="file")
hub_depot_crates :: proc(s: hubworld.Station, color: rl.Color, count: int) {
	// Six on the floor, four on them, two on top: as many as the depot has earned.
	layers := [3]struct{ columns, rows: int, y: f32 }{{3, 2, 0.4}, {2, 2, 1.2}, {2, 1, 2.0}}
	shown := 0
	for layer in layers {
		for r in 0..<layer.rows {
			for c in 0..<layer.columns {
				if shown >= count { return }
				x := (f32(c)-f32(layer.columns-1)*0.5)*0.9
				z := (f32(r)-f32(layer.rows-1)*0.5)*1.4
				hub_box({x, layer.y, z}, {0.8, 0.8, 0.8}, {36, 44, 60, 255}, color)
				shown += 1
			}
		}
	}
	_ = s
}

// The depot, in 3D from `camera`. `hovered` is the station under the pointer.
draw_hub_depot :: proc(room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, hovered: Maybe(int), view: hubworld.Depot_View) {
	rl.BeginMode3D(camera)
	defer rl.EndMode3D()
	hub_room_floor(room, w.time)
	hub_room_walls(room, HUB_DEPOT_WALL, false, 0)
	for k in 0..<room.count {
		if room.stations[k].decor { continue }
		is_hovered := false
		if h, ok := hovered.?; ok && h == k { is_hovered = true }
		hub_room_ground_marks(room.stations[k], hub_depot_color(hubworld.Depot_Station(k)), is_hovered, w.time, f32(k))
	}
	for k in 0..<room.count {
		s := room.stations[k]
		which := hubworld.Depot_Station(k)
		color := hub_depot_color(which)
		hub_frame_at(s.center, hubworld.station_yaw(s))
		switch which {
		case .Backpack: hub_depot_backpack(s, color)
		case .Character: hub_depot_mannequin(s, color, view.gear, w.time)
		case .Archive: hub_depot_archive(s, color, hubworld.shelf_lit(view.discovered, view.total, 60), w.time)
		case .Plaza: hub_casino_plaza_door(s, color)
		case .Crates: hub_depot_crates(s, color, hubworld.crate_count(view.stored))
		}
		hub_frame_end()
	}
	hub_draw_robot_at(w.position, w.facing_left, w.moving, w.stride, w.time, camera)
}

// The name plates over the stations, in screen space.
draw_hub_depot_labels :: proc(theme: ^ui.Theme, room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, canvas_width, canvas_height: f32,
	hovered: Maybe(int)) {
	for k in 0..<room.count {
		s := room.stations[k]
		color := hub_depot_color(hubworld.Depot_Station(k))
		at := rl.GetWorldToScreenEx({s.center.x, s.height+1.0, s.center.y}, camera, i32(canvas_width), i32(canvas_height))
		is_hovered := false
		if h, ok := hovered.?; ok && h == k { is_hovered = true }
		near := hubworld.station_distance(s, w.position) < 6
		hub_draw_plate(theme, at, s.name, s.subtitle, color, near || is_hovered, is_hovered)
	}
}
