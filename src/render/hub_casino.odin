package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import hubworld "../hubworld"
import ui "../engine/ui"

// INSIDE THE CASINO (hubworld/zone.odin has the rules): an octagonal hall with neon
// walls, the arrival ring at the middle and four stations, each the door of a game:
// the saloon of 6 Ranch 7 with its cardboard horse and cowboy, the track of Tre in
// fuga with its three runners, the roulette's wheel turning slowly, the table of the
// d20 duel with two big dice; and the way out to the plaza at the right. A sign at
// the back shows the depot's credits. Same look and helpers as the plaza.

HUB_CASINO_WALL :: rl.Color{245, 69, 207, 255}
HUB_CASINO_SIGN :: rl.Color{255, 214, 120, 255}

hub_casino_color :: proc(s: hubworld.Casino_Station) -> rl.Color {
	switch s {
	case .Ranch: return {255, 176, 48, 255}
	case .Run: return {83, 242, 238, 255}
	case .Roulette: return {70, 230, 120, 255}
	case .Dice: return {255, 90, 100, 255}
	case .Plaza: return {76, 164, 232, 255}
	}
	return rl.WHITE
}

// The outside radius of the octagon whose inscribed circle has radius `r`.
@(private="file")
hub_octagon_vertex_radius :: proc(r: f32) -> f32 {
	return r/math.cos(f32(math.PI/8))
}

@(private="file")
hub_casino_floor :: proc(room: ^hubworld.Room, time: f32) {
	r := room.radius
	vr := hub_octagon_vertex_radius(r)
	// Turned an eighth of a turn so a wall (not a corner) faces right, where the way out is.
	rlgl.PushMatrix()
	rlgl.Rotatef(22.5, 0, 1, 0)
	rl.DrawCylinder({0, -0.5, 0}, vr, vr, 0.5, 8, HUB_FLOOR)
	rl.DrawCylinder({0, -3, 0}, vr*0.96, vr, 2.5, 8, HUB_SOLID_DARK)
	rlgl.PopMatrix()
	// Tiles, cut by the octagon: |x| and |z| within r, |x|+|z| within r*sqrt(2).
	diagonal := r*math.SQRT_TWO
	for k := -r; k <= r; k += 1 {
		reach := min(r, diagonal-abs(k))
		if reach <= 0 { continue }
		rl.DrawLine3D({-reach, 0.005, k}, {reach, 0.005, k}, HUB_GROUT)
		rl.DrawLine3D({k, 0.005, -reach}, {k, 0.005, reach}, HUB_GROUT)
	}
	pulse := 0.5+0.5*math.sin(time*2)
	for k in 0..<2 { rl.DrawCircle3D({0, 0.03, 0}, 1.25-f32(k)*0.3, {1, 0, 0}, 90, hub_fade(HUB_CYAN, 0.6+0.4*pulse)) }
	for k in 0..<room.count {
		to := hubworld.station_door_center(room.stations[k])
		length := math.sqrt(to.x*to.x+to.y*to.y)
		for s := f32(2.0); s < length-1.4; s += 1.25 {
			p := to*(s/length)
			rl.DrawCubeV({p.x, 0.02, p.y}, {0.36, 0.03, 0.36}, hub_fade(HUB_CYAN, 0.8))
		}
	}
}

// The eight neon walls: the ones at the back are high (the camera looks over the
// others), and the credits sign hangs on the middle one.
@(private="file")
hub_casino_walls :: proc(room: ^hubworld.Room, credits_glow: f32) {
	r := room.radius
	length := 2*r*math.tan(f32(math.PI/8))
	for i in 0..<8 {
		phi := f32(i)*math.PI/4
		direction := hubworld.Vec2{math.cos(phi), math.sin(phi)}
		front := -direction
		high := direction.y < -0.3
		height := f32(3.6) if high else 0.9
		hub_frame_at(direction*r, math.atan2(front.x, front.y))
		hub_box({0, height*0.5, -0.18}, {length+0.35, height, 0.36}, HUB_SOLID_DARK, HUB_CASINO_WALL)
		if i == 6 {
			// The sign for the credits, on the back wall's middle.
			hub_box({0, 2.3, 0.06}, {5.6, 1.1, 0.14}, {26, 20, 8, 255}, hub_fade(HUB_CASINO_SIGN, 0.6+0.4*credits_glow))
		}
		hub_frame_end()
	}
}

@(private="file")
hub_casino_ground_marks :: proc(s: hubworld.Station, color: rl.Color, hovered: bool, time: f32, phase: f32) {
	hub_frame_at(s.center, hubworld.station_yaw(s))
	defer hub_frame_end()
	glow := 0.55+0.25*math.sin(time*3+phase)+(0.3 if hovered else 0)
	patch := rl.Vector3{hubworld.DOOR_HALF_WIDTH*2, 0.03, hubworld.DOOR_DEPTH}
	at := rl.Vector3{0, 0.03, s.half.y+hubworld.DOOR_DEPTH*0.5}
	rl.DrawCubeV(at, patch, hub_fade(color, clamp(glow*0.55, 0, 1)))
	rl.DrawCubeWiresV(at, patch, color)
	outline := rl.Vector3{s.half.x*2, 0.03, s.half.y*2}
	rl.DrawCubeWiresV({0, 0.03, 0}, outline, hub_fade(color, 0.95 if hovered else 0.7))
}

// A thin flat figure, as the cardboard ones of the saloon.
@(private="file")
hub_card :: proc(center: rl.Vector3, size: rl.Vector2, fill, edge: rl.Color) {
	hub_box(center, {size.x, size.y, 0.06}, fill, edge)
}

@(private="file")
hub_casino_ranch :: proc(s: hubworld.Station, color: rl.Color, time: f32) {
	hx, hz, h := s.half.x, s.half.y, s.height
	hub_box({0, h*0.5-0.3, -0.2}, {hx*2, h-0.6, hz*2-0.4}, HUB_SOLID, color)
	hub_box({0, h+0.35, hz-0.4}, {hx*2, 1.0, 0.25}, HUB_SOLID_DARK, color)
	hub_box({0, h-0.2, hz+0.45}, {hx*2+0.3, 0.14, 1.1}, HUB_SOLID_DARK, color)
	for sx in ([2]f32{-1, 1}) { hub_box({sx*(hx-0.15), 1.2, hz+0.9}, {0.2, 2.4, 0.2}, HUB_SOLID, color) }
	// The three reels: a window each, the symbol in it flickers.
	for i in 0..<3 {
		x := f32(i-1)*0.95
		hub_box({x, 2.05, hz-0.15}, {0.75, 0.95, 0.08}, {255, 236, 190, 255}, color)
		lit := 0.5+0.5*math.sin(time*5+f32(i)*2.1)
		hub_box({x, 2.05, hz-0.1}, {0.4, 0.5, 0.06}, {200+u8(lit*55), 50, 50, 255}, color)
	}
	for sx in ([2]f32{-1, 1}) { hub_box({sx*0.45, 0.65, hz-0.05}, {0.8, 1.2, 0.06}, {70, 46, 24, 255}, color) }
	// The cardboard horse and cowboy stand before the saloon.
	hub_frame_at({0, 0}, 0)
	rlgl.Translatef(-hx*0.5, 0, hz+1.8)
	brown := rl.Color{160, 108, 64, 255}
	hub_card({0, 0.85, 0}, {1.3, 0.5}, brown, color)
	for lx in ([4]f32{-0.55, -0.3, 0.3, 0.55}) { hub_card({lx, 0.3, 0}, {0.12, 0.6}, brown, color) }
	hub_card({0.7, 1.25, 0}, {0.25, 0.55}, brown, color)
	hub_card({0.95, 1.5, 0}, {0.4, 0.22}, brown, color)
	hub_card({-0.75, 0.95, 0}, {0.1, 0.45}, brown, color)
	hub_frame_end()
	hub_frame_at({0, 0}, 0)
	rlgl.Translatef(hx*0.45, 0, hz+1.8)
	hub_card({0, 0.4, 0}, {0.35, 0.8}, {50, 60, 90, 255}, color)
	hub_card({0, 1.15, 0}, {0.45, 0.7}, {60, 110, 200, 255}, color)
	hub_card({0, 1.65, 0}, {0.3, 0.3}, {240, 200, 160, 255}, color)
	hub_card({0, 1.86, 0}, {0.6, 0.07}, {110, 72, 40, 255}, color)
	hub_card({0, 1.98, 0}, {0.3, 0.2}, {110, 72, 40, 255}, color)
	hub_frame_end()
}

@(private="file")
hub_casino_runner :: proc(kind: int, color: rl.Color) {
	switch kind {
	case 0:
		// The dinosaur.
		green := rl.Color{110, 200, 90, 255}
		hub_box({0, 0.6, 0}, {1.0, 0.5, 0.45}, green, color)
		hub_box({-0.7, 0.5, 0}, {0.6, 0.2, 0.25}, green, color)
		hub_box({0.45, 1.0, 0}, {0.25, 0.5, 0.25}, green, color)
		hub_box({0.65, 1.25, 0}, {0.4, 0.25, 0.25}, green, color)
		for lz in ([2]f32{-0.15, 0.15}) { hub_box({0.1, 0.18, lz}, {0.18, 0.36, 0.14}, green, color) }
	case 1:
		// The Panda 4x4.
		hub_box({0, 0.5, 0}, {1.3, 0.5, 0.7}, {220, 60, 60, 255}, color)
		hub_box({-0.1, 0.95, 0}, {0.7, 0.4, 0.62}, {240, 240, 240, 255}, color)
		for wx in ([2]f32{-0.45, 0.45}) { for wz in ([2]f32{-0.38, 0.38}) { hub_box({wx, 0.22, wz}, {0.4, 0.4, 0.14}, {20, 22, 28, 255}, color) } }
	case:
		// The futuristic bike.
		hub_box({0, 0.5, 0}, {1.0, 0.25, 0.2}, {70, 120, 240, 255}, color)
		for wx in ([2]f32{-0.5, 0.5}) { hub_box({wx, 0.3, 0}, {0.45, 0.45, 0.1}, {20, 22, 28, 255}, HUB_CYAN) }
		hub_box({0.15, 0.82, 0}, {0.3, 0.4, 0.2}, {200, 210, 240, 255}, color)
	}
}

@(private="file")
hub_casino_run :: proc(s: hubworld.Station, color: rl.Color, time: f32) {
	hx, hz, h := s.half.x, s.half.y, s.height
	rl.DrawCubeV({0, 0.03, 0}, {hx*2, 0.04, hz*2}, HUB_SOLID_DARK)
	for scale in ([2]f32{0.92, 0.62}) {
		previous := rl.Vector3{(hx-0.3)*scale, 0.06, 0}
		for step in 1..=48 {
			a := f32(step)*math.TAU/48
			next := rl.Vector3{math.cos(a)*(hx-0.3)*scale, 0.06, math.sin(a)*(hz-0.25)*scale}
			rl.DrawLine3D(previous, next, color)
			previous = next
		}
	}
	// The gate: two posts, a lintel, a chequered start line.
	for sx in ([2]f32{-1, 1}) { hub_box({sx*(hx-0.45), h*0.45, hz-0.2}, {0.3, h*0.9, 0.3}, HUB_SOLID, color) }
	hub_box({0, h*0.9+0.15, hz-0.2}, {(hx-0.45)*2+0.3, 0.3, 0.3}, HUB_SOLID, color)
	for i in 0..<10 {
		cell := ((hx-0.45)*2-0.2)/10
		hub_box({-(hx-0.45)+0.1+cell*(f32(i)+0.5), h*0.9-0.1, hz-0.2}, {cell, 0.18, 0.06}, rl.WHITE if i%2 == 0 else rl.Color{20, 22, 28, 255}, color)
	}
	// The three runners go round the track, each looking where it goes.
	for kind in 0..<3 {
		a := time*0.55+f32(kind)*math.TAU/3
		position := rl.Vector3{math.cos(a)*(hx-0.9)*0.92, 0.05, math.sin(a)*(hz-0.6)*0.92}
		velocity := rl.Vector2{-math.sin(a)*(hx-0.9), math.cos(a)*(hz-0.6)}
		rlgl.PushMatrix()
		rlgl.Translatef(position.x, position.y, position.z)
		rlgl.Rotatef(math.atan2(-velocity.y, velocity.x)*math.DEG_PER_RAD, 0, 1, 0)
		hub_casino_runner(kind, color)
		rlgl.PopMatrix()
	}
}

@(private="file")
hub_casino_roulette :: proc(s: hubworld.Station, color: rl.Color, time: f32) {
	hub_prism({0, 0, 0}, 2.2, 2.2, 0.9, 12, HUB_SOLID, color)
	rl.DrawCylinder({0, 0.9, 0}, 1.7, 1.7, 0.12, 24, {170, 30, 40, 255})
	for i in 0..<24 {
		a := time*0.45+f32(i)*math.TAU/24
		at := rl.Vector3{math.cos(a)*1.45, 1.05, math.sin(a)*1.45}
		rl.DrawCubeV(at, {0.2, 0.06, 0.2}, rl.Color{16, 16, 20, 255} if i%2 == 0 else rl.Color{200, 40, 50, 255})
		rl.DrawLine3D({math.cos(a)*0.4, 1.03, math.sin(a)*0.4}, {at.x, 1.03, at.z}, {16, 16, 20, 255})
	}
	rl.DrawCylinder({0, 0.9, 0}, 0.35, 0.35, 0.3, 12, {230, 190, 90, 255})
	// The ball goes the other way.
	b := -time*1.7
	rl.DrawSphere({math.cos(b)*1.25, 1.12, math.sin(b)*1.25}, 0.08, rl.WHITE)
	for chip, i in ([3]rl.Color{{80, 140, 240, 255}, {250, 210, 80, 255}, {230, 70, 80, 255}}) {
		for k in 0..<3 { hub_box({1.6+f32(i)*0.5-0.3, 0.95+f32(k)*0.13, 1.5}, {0.34, 0.12, 0.34}, chip, color) }
	}
}

// A die: the twenty-sided one's twelve corners and thirty edges, turning.
@(private="file")
hub_draw_icosahedron :: proc(center: rl.Vector3, scale, angle, tilt: f32, color: rl.Color) {
	phi := f32(1.618034)
	base := [12][3]f32{
		{0, 1, phi}, {0, -1, phi}, {0, 1, -phi}, {0, -1, -phi},
		{1, phi, 0}, {-1, phi, 0}, {1, -phi, 0}, {-1, -phi, 0},
		{phi, 0, 1}, {phi, 0, -1}, {-phi, 0, 1}, {-phi, 0, -1},
	}
	points: [12]rl.Vector3
	for v, i in base {
		// Turn about the up axis, then lean.
		x, z := v.x*math.cos(angle)+v.z*math.sin(angle), -v.x*math.sin(angle)+v.z*math.cos(angle)
		y := v.y
		y, z = y*math.cos(tilt)-z*math.sin(tilt), y*math.sin(tilt)+z*math.cos(tilt)
		points[i] = center+rl.Vector3{x, y, z}*scale
	}
	for i in 0..<12 {
		for j in i+1..<12 {
			d := base[i]-base[j]
			if abs(d.x*d.x+d.y*d.y+d.z*d.z-4) < 0.05 { rl.DrawLine3D(points[i], points[j], color) }
		}
	}
}

@(private="file")
hub_casino_dice :: proc(s: hubworld.Station, color: rl.Color, time: f32) {
	hx, hz := s.half.x, s.half.y
	hub_box({0, 0.45, 0}, {hx*2, 0.9, hz*2}, HUB_SOLID, color)
	hub_box({0, 0.93, 0}, {hx*2-0.3, 0.06, hz*2-0.3}, {70, 20, 28, 255}, color)
	for side in 0..<2 {
		x := f32(side*2-1)*1.0
		bob := 0.12*math.sin(time*1.6+f32(side)*2)
		hub_draw_icosahedron({x, 1.7+bob, 0}, 0.6, time*0.8+f32(side)*1.7, 0.55, color if side == 0 else HUB_CYAN)
	}
}

@(private="file")
hub_casino_plaza_door :: proc(s: hubworld.Station, color: rl.Color) {
	hx, h := s.half.x, s.height
	for sx in ([2]f32{-1, 1}) { hub_box({sx*(hx-0.15), h*0.5, 0}, {0.4, h, 0.6}, HUB_SOLID, color) }
	hub_box({0, h-0.35, 0}, {hx*2, 0.7, 0.6}, HUB_SOLID, color)
	hub_box({0, h*0.5-0.35, -0.1}, {hx*2-0.6, h-0.9, 0.05}, {10, 24, 40, 255}, color)
}

// The hall, in 3D from `camera`. `hovered` is the station under the pointer; `credits`
// is what the sign shows (only its glow is drawn here: the digits are in the labels).
draw_hub_casino :: proc(room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, hovered: Maybe(int)) {
	rl.BeginMode3D(camera)
	defer rl.EndMode3D()
	hub_casino_floor(room, w.time)
	hub_casino_walls(room, 0.5+0.5*math.sin(w.time*2.4))
	for k in 0..<room.count {
		is_hovered := false
		if h, ok := hovered.?; ok && h == k { is_hovered = true }
		hub_casino_ground_marks(room.stations[k], hub_casino_color(hubworld.Casino_Station(k)), is_hovered, w.time, f32(k))
	}
	for k in 0..<room.count {
		s := room.stations[k]
		which := hubworld.Casino_Station(k)
		color := hub_casino_color(which)
		hub_frame_at(s.center, hubworld.station_yaw(s))
		switch which {
		case .Ranch: hub_casino_ranch(s, color, w.time)
		case .Run: hub_casino_run(s, color, w.time)
		case .Roulette: hub_casino_roulette(s, color, w.time)
		case .Dice: hub_casino_dice(s, color, w.time)
		case .Plaza: hub_casino_plaza_door(s, color)
		}
		hub_frame_end()
	}
	hub_draw_robot_at(w.position, w.facing_left, w.moving, w.stride, w.time, camera)
}

// The name plates over the stations, and the credits on the back sign, in screen space.
draw_hub_casino_labels :: proc(theme: ^ui.Theme, room: ^hubworld.Room, w: ^hubworld.Room_World, camera: rl.Camera3D, canvas_width, canvas_height: f32,
	credits: i64, hovered: Maybe(int)) {
	for k in 0..<room.count {
		s := room.stations[k]
		color := hub_casino_color(hubworld.Casino_Station(k))
		at := rl.GetWorldToScreenEx({s.center.x, s.height+1.0, s.center.y}, camera, i32(canvas_width), i32(canvas_height))
		is_hovered := false
		if h, ok := hovered.?; ok && h == k { is_hovered = true }
		near := hubworld.station_distance(s, w.position) < 6
		hub_draw_plate(theme, at, s.name, s.subtitle, color, near || is_hovered, is_hovered)
	}
	sign := rl.GetWorldToScreenEx({0, 2.3, -room.radius+0.3}, camera, i32(canvas_width), i32(canvas_height))
	ui.draw_text_centered(theme, fmt.tprintf("CREDITI  %d", credits), sign, .Body, HUB_CASINO_SIGN)
}
