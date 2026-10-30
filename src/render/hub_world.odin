package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import hubworld "../hubworld"
import ui "../engine/ui"

// THE HUB'S PLAZA (hubworld/hubworld.odin has the rules): night-blue solids with
// neon edges on a dark tiled floor, the paper robot of the expeditions walking among
// seven buildings. Drawn with raylib's own shapes, like the hub's islands.
//
// A building has a shell (walls, roof, signs), an inside (a few simple things) and
// an outline on the ground. As the robot comes near the shell fades (hubworld.
// building_opacity) and the inside shows through; at the door the shell is gone;
// the outline and the door's patch stay.

HUB_FLOOR :: rl.Color{27, 31, 40, 255}
HUB_GROUT :: rl.Color{44, 52, 70, 255}
HUB_SOLID :: rl.Color{30, 35, 46, 255}
HUB_SOLID_DARK :: rl.Color{20, 24, 33, 255}
HUB_CYAN :: rl.Color{83, 242, 238, 255}

hub_building_color :: proc(b: hubworld.Building) -> rl.Color {
	switch b {
	case .Portal: return {166, 106, 255, 255}
	case .Storage: return {76, 164, 232, 255}
	case .Progress: return {242, 183, 85, 255}
	case .Exit: return {242, 91, 100, 255}
	case .Memories: return {245, 225, 163, 255}
	case .Arcade: return {148, 239, 61, 255}
	case .Casino: return {245, 69, 207, 255}
	}
	return rl.WHITE
}

@(private)
hub_fade :: proc(color: rl.Color, k: f32) -> rl.Color {
	return {color.r, color.g, color.b, u8(clamp(f32(color.a)*k, 0, 255))}
}

// A solid with a neon edge, `opacity` of the way there (the shell fading out).
@(private)
hub_box :: proc(center, size: rl.Vector3, fill, edge: rl.Color, opacity: f32 = 1) {
	if opacity <= 0.01 { return }
	rl.DrawCubeV(center, size, hub_fade(fill, opacity))
	rl.DrawCubeWiresV(center, size, hub_fade(edge, opacity))
}

@(private)
hub_prism :: proc(base: rl.Vector3, radius_bottom, radius_top, height: f32, sides: i32, fill, edge: rl.Color, opacity: f32 = 1) {
	if opacity <= 0.01 { return }
	rl.DrawCylinder(base, radius_top, radius_bottom, height, sides, hub_fade(fill, opacity))
	rl.DrawCylinderWires(base, radius_top, radius_bottom, height, sides, hub_fade(edge, opacity))
}

// A frame whose origin is `center` on the floor and whose z looks along `yaw`: each
// thing is drawn in its own frame, x across, z to its front.
@(private)
hub_frame_at :: proc(center: hubworld.Vec2, yaw: f32) {
	rlgl.PushMatrix()
	rlgl.Translatef(center.x, 0, center.y)
	rlgl.Rotatef(yaw*math.DEG_PER_RAD, 0, 1, 0)
}

@(private="file")
hub_frame_begin :: proc(b: hubworld.Building) {
	hub_frame_at(hubworld.building_center(b), hubworld.building_yaw(b))
}

@(private)
hub_frame_end :: proc() { rlgl.PopMatrix() }

// What stands inside, seen through the fading shell (and what stays when it is gone).
@(private="file")
hub_draw_inside :: proc(b: hubworld.Building, color: rl.Color, time: f32) {
	info := hubworld.building_info(b)
	rl.DrawCubeV({0, 0.04, 0}, {info.half.x*2-0.3, 0.06, info.half.y*2-0.3}, hub_fade(HUB_SOLID_DARK, 1))
	switch b {
	case .Casino:
		for i in 0..<3 {
			x := f32(i-1)*1.5
			hub_box({x, 0.8, -1.0}, {0.9, 1.5, 0.7}, HUB_SOLID, color)
			hub_box({x, 1.15, -0.62}, {0.6, 0.35, 0.04}, hub_fade(color, 0.7), color)
		}
		rl.DrawCylinder({1.2, 0.1, 0.6}, 0.8, 0.8, 0.7, 12, HUB_SOLID)
		rl.DrawCylinderWires({1.2, 0.1, 0.6}, 0.8, 0.8, 0.7, 12, color)
		rl.DrawCylinder({1.2, 0.8, 0.6}, 0.55, 0.55, 0.06, 24, {180, 32, 40, 255})
	case .Storage:
		for i in 0..<5 {
			hub_box({f32(i%3-1)*1.2, 0.45+f32(i/3)*0.9, -0.8+f32(i/3)*0.3}, {0.9, 0.9, 0.9}, {40, 46, 58, 255}, color)
		}
	case .Progress:
		for i in 0..<6 {
			hub_box({math.cos(f32(i))*0.7, 0.35+f32(i)*0.6, math.sin(f32(i))*0.7}, {0.9, 0.2, 0.5}, HUB_SOLID, color)
		}
	case .Memories:
		for i in 0..<5 {
			a := time*0.5+f32(i)*math.TAU/5
			hub_box({math.cos(a)*1.0, 1.2+0.25*math.sin(time*1.3+f32(i)), math.sin(a)*1.0}, {0.28, 0.5, 0.28}, hub_fade(color, 0.8), color)
		}
	case .Arcade:
		for i in 0..<4 {
			x := f32(i)*1.1-1.65
			hub_box({x, 0.9, -0.9}, {0.8, 1.8, 0.7}, HUB_SOLID, color)
			hub_box({x, 1.25, -0.52}, {0.55, 0.45, 0.04}, hub_fade({83, 242, 238, 255}, 0.8), color)
		}
	case .Portal, .Exit:
	}
}

// The building's shell: the part that fades.
@(private="file")
hub_draw_shell :: proc(b: hubworld.Building, color: rl.Color, o: f32, time: f32) {
	if o <= 0.01 { return }
	info := hubworld.building_info(b)
	hx, hz, h := info.half.x, info.half.y, info.height
	switch b {
	case .Portal:
		hub_prism({0, 0, 0}, 3.5, 3.5, 0.4, 6, HUB_SOLID, color, o)
		for sx in ([2]f32{-1, 1}) { hub_box({sx*3.0, 2.5, 0}, {0.8, 4.4, 0.8}, HUB_SOLID, color, o) }
		for k in 0..<4 { rl.DrawCircle3D({0, 3.6, 0}, 2.2+f32(k)*0.1, {1, 0, 0}, 90, hub_fade(HUB_CYAN, o)) }
		rl.DrawCylinderEx({0, 3.6, 0.05}, {0, 3.6, 0.14}, 2.1, 2.1, 36, hub_fade({60, 28, 110, 255}, o))
		for i in 0..<16 {
			a := time*0.4+f32(i)*math.TAU/16*3.1
			r := 0.25+1.8*f32(i)/16
			hub_box({math.cos(a)*r, 3.6+math.sin(a)*r, 0.2}, {0.1, 0.1, 0.05}, hub_fade({210, 190, 255, 255}, 0.9), color, o)
		}
	case .Storage:
		hub_box({0, h*0.5, 0}, {hx*2, h, hz*2}, HUB_SOLID, color, o)
		hub_box({0, h+0.15, 0}, {hx*2+0.5, 0.3, hz*2+0.5}, HUB_SOLID_DARK, color, o)
		hub_box({0, 1.25, hz+0.06}, {3, 2.5, 0.12}, {58, 66, 82, 255}, color, o)
		for i in 0..<8 { hub_box({0, 0.25+f32(i)*0.3, hz+0.14}, {2.9, 0.04, 0.04}, {88, 98, 118, 255}, color, o*0.6) }
		for c in ([3]rl.Vector3{{-hx-0.8, 0.45, 0.4}, {-hx-0.9, 0.35, 1.5}, {hx+0.8, 0.5, 0.8}}) { hub_box(c, {0.9, c.y*2, 0.9}, {40, 46, 58, 255}, color, o) }
	case .Progress:
		hub_prism({0, 0, 0}, 1.7, 0.9, h-1.6, 6, HUB_SOLID, color, o)
		rl.DrawSphere({0, h-0.5, 0}, 0.38, hub_fade(color, o))
		hub_box({0, 3.0, hz+0.1}, {3.2, 2.2, 0.2}, HUB_SOLID_DARK, color, o)
		for r in 0..<2 { for c in 0..<3 { hub_box({f32(c-1)*0.9, 3.45-f32(r)*0.9, hz+0.22}, {0.4, 0.4, 0.06}, hub_fade(color, 0.9 if (r*3+c) < 4 else 0.25), color, o) } }
	case .Exit:
		for sx in ([2]f32{-1, 1}) { hub_box({sx*1.7, h*0.5-0.2, 0}, {0.8, h-0.4, 0.8}, HUB_SOLID, color, o) }
		hub_box({0, h-0.35, 0}, {hx*2, 0.7, 0.9}, HUB_SOLID, color, o)
		hub_box({0, h*0.5-0.3, -0.1}, {2.7, h-1.0, 0.05}, hub_fade({10, 4, 10, 255}, 1), color, o)
	case .Memories:
		hub_prism({0, 0, 0}, 3.1, 3.1, 0.3, 6, HUB_SOLID, color, o)
		hub_prism({0, 0.3, 0}, 2.7, 2.7, 0.3, 6, HUB_SOLID, color, o)
		for i in 0..<6 {
			a := math.PI/6+f32(i)*math.PI/3
			hub_prism({math.cos(a)*2.1, 0.6, math.sin(a)*2.1}, 0.26, 0.26, 2.5, 6, HUB_SOLID, color, o)
		}
		hub_prism({0, 3.1, 0}, 3.0, 0.3, 1.1, 6, HUB_SOLID, color, o)
		for i in 0..<3 { hub_box({math.cos(time*0.7+f32(i)*2.1)*0.8, 4.4+0.2*math.sin(time*1.5+f32(i)), math.sin(time*0.7+f32(i)*2.1)*0.8}, {0.3, 0.3, 0.3}, hub_fade(color, 0.9), color, o) }
	case .Arcade:
		hub_box({0, h*0.5, 0}, {hx*2, h, hz*2}, HUB_SOLID, color, o)
		hub_box({0, h+0.1, hz-0.1}, {hx*2+0.4, 0.5, 0.5}, HUB_SOLID_DARK, color, o)
		for sx in ([2]f32{-1, 1}) {
			hub_box({sx*1.5, 1.5, hz+0.06}, {1.5, 1.5, 0.1}, {10, 14, 20, 255}, color, o)
			for k in 0..<3 { hub_box({sx*1.5-0.45+f32(k)*0.45, 1.3, hz+0.14}, {0.3, 0.7, 0.1}, HUB_SOLID, color, o) }
		}
	case .Casino:
		hub_box({0, h*0.5, 0}, {hx*2, h, hz*2}, HUB_SOLID, color, o)
		hub_box({0, 2.7, hz+0.7}, {hx*2+0.4, 0.25, 1.4}, HUB_SOLID_DARK, color, o)
		for i in 0..<13 { rl.DrawSphere({-2.85+f32(i)*0.475, 2.62, hz+1.4}, 0.09, hub_fade({255, 214, 140, 255}, o)) }
		for d in ([2]rl.Vector3{{-1, h+0.6, 0}, {1.1, h+0.55, 0.2}}) { hub_box(d, {1.15, 1.15, 1.15}, {235, 230, 220, 255}, color, o) }
	}
}

// The ground: tiles, rim, the arrival ring and the road dots to each door.
@(private="file")
hub_draw_floor :: proc(time: f32) {
	R := hubworld.PLAZA_RADIUS
	rl.DrawCylinder({0, -0.5, 0}, R, R, 0.5, 64, HUB_FLOOR)
	rl.DrawCylinder({0, -3, 0}, R*0.96, R, 2.5, 64, HUB_SOLID_DARK)
	for z := -R; z <= R; z += 1 {
		chord := math.sqrt(max(R*R-z*z, 0))
		rl.DrawLine3D({-chord, 0.005, z}, {chord, 0.005, z}, HUB_GROUT)
	}
	for x := -R; x <= R; x += 1 {
		chord := math.sqrt(max(R*R-x*x, 0))
		rl.DrawLine3D({x, 0.005, -chord}, {x, 0.005, chord}, HUB_GROUT)
	}
	for k in 0..<3 { rl.DrawCircle3D({0, 0.02, 0}, R-0.05-f32(k)*0.05, {1, 0, 0}, 90, HUB_CYAN) }
	pulse := 0.5+0.5*math.sin(time*2)
	for k in 0..<2 { rl.DrawCircle3D({0, 0.03, 0}, 1.25-f32(k)*0.3, {1, 0, 0}, 90, hub_fade(HUB_CYAN, 0.6+0.4*pulse)) }
	for b in hubworld.Building {
		from := hubworld.Vec2{}
		to := hubworld.door_center(b)
		d := to-from
		length := math.sqrt(d.x*d.x+d.y*d.y)
		for s := f32(2.0); s < length-1.4; s += 1.25 {
			p := from+d*(s/length)
			rl.DrawCubeV({p.x, 0.02, p.y}, {0.36, 0.03, 0.36}, hub_fade(HUB_CYAN, 0.8))
		}
	}
}

// The door's patch and the building's outline on the ground: always there.
@(private="file")
hub_draw_ground_marks :: proc(b: hubworld.Building, color: rl.Color, hovered: bool, time: f32) {
	info := hubworld.building_info(b)
	hub_frame_begin(b)
	defer hub_frame_end()
	glow := 0.55+0.25*math.sin(time*3+f32(b))+(0.3 if hovered else 0)
	patch := rl.Vector3{hubworld.DOOR_HALF_WIDTH*2, 0.03, hubworld.DOOR_DEPTH}
	at := rl.Vector3{0, 0.03, info.half.y+hubworld.DOOR_DEPTH*0.5}
	rl.DrawCubeV(at, patch, hub_fade(color, clamp(glow*0.55, 0, 1)))
	rl.DrawCubeWiresV(at, patch, color)
	outline := rl.Vector3{info.half.x*2, 0.03, info.half.y*2}
	rl.DrawCubeWiresV({0, 0.03, 0}, outline, hub_fade(color, 0.95 if hovered else 0.7))
}

// The paper robot, as in the expeditions (expedition_robot.odin), on the plaza or in a room.
@(private)
hub_draw_robot_at :: proc(position: hubworld.Vec2, facing_left, moving: bool, stride, time: f32, camera: rl.Camera3D) {
	right := rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, camera.position-camera.target))
	action := gfx.Living_Action.Move_Side if moving else gfx.Living_Action.Idle
	progress := stride*1.8-math.floor(stride*1.8)
	art := expedition_robot_art(time, action, progress, false)
	draw_expedition_paper_facing(right, &art, {position.x, 0.035, position.y}, 1.7, facing_left, 1, 1)
}

@(private="file")
hub_draw_robot :: proc(w: ^hubworld.World, camera: rl.Camera3D) {
	hub_draw_robot_at(w.position, w.facing_left, w.moving, w.stride, w.time, camera)
}

// The plaza, in 3D from `camera`. `hovered` is the building under the pointer.
draw_hub_world :: proc(w: ^hubworld.World, camera: rl.Camera3D, hovered: Maybe(hubworld.Building)) {
	rl.BeginMode3D(camera)
	defer rl.EndMode3D()
	hub_draw_floor(w.time)
	for b in hubworld.Building {
		is_hovered := false
		if h, ok := hovered.?; ok && h == b { is_hovered = true }
		hub_draw_ground_marks(b, hub_building_color(b), is_hovered, w.time)
	}
	// The insides, then the robot, then the shells far to near: a fading shell blends
	// over the robot and the insides instead of hiding them behind its depth.
	for b in hubworld.Building {
		hub_frame_begin(b)
		hub_draw_inside(b, hub_building_color(b), w.time)
		hub_frame_end()
	}
	hub_draw_robot(w, camera)
	order: [hubworld.BUILDING_COUNT]hubworld.Building
	for b, i in hubworld.Building { order[i] = b }
	for i in 1..<len(order) {
		// Far (smaller z) first.
		for j := i; j > 0 && hubworld.building_center(order[j]).y < hubworld.building_center(order[j-1]).y; j -= 1 {
			order[j], order[j-1] = order[j-1], order[j]
		}
	}
	for b in order {
		hub_frame_begin(b)
		hub_draw_shell(b, hub_building_color(b), hubworld.building_opacity(b, w.position), w.time)
		hub_frame_end()
	}
}

// A name plate at `at` (its lower middle), in screen space: the name, and under it
// the subtitle when `expanded`.
@(private)
hub_draw_plate :: proc(theme: ^ui.Theme, at: rl.Vector2, name, subtitle: string, color: rl.Color, expanded, hovered: bool) {
	size := ui.measure(theme, name, .Small)
	sub := ui.measure(theme, subtitle, .Small)
	width := max(size.x, sub.x if expanded else 0)+16
	height := size.y+(sub.y+2 if expanded else 0)+8
	plate := rl.Rectangle{at.x-width*0.5, at.y-height, width, height}
	rl.DrawRectangleRec(plate, {13, 16, 25, 225})
	rl.DrawRectangleLinesEx(plate, 1.5 if !hovered else 2.5, color)
	ui.draw_text_centered(theme, name, {at.x, plate.y+4+size.y*0.5}, .Small, color)
	if expanded {
		ui.draw_text_centered(theme, subtitle, {at.x, plate.y+6+size.y+sub.y*0.5}, .Small, {200, 208, 226, 255})
	}
}

// The name plates over the buildings, in screen space (after the 3D): the name of
// each, and what it holds while the robot is near it or the pointer is on it.
draw_hub_world_labels :: proc(theme: ^ui.Theme, w: ^hubworld.World, camera: rl.Camera3D, canvas_width, canvas_height: f32,
	hovered: Maybe(hubworld.Building)) {
	for b in hubworld.Building {
		info := hubworld.building_info(b)
		centre := hubworld.building_center(b)
		color := hub_building_color(b)
		at := rl.GetWorldToScreenEx({centre.x, info.height+1.0, centre.y}, camera, i32(canvas_width), i32(canvas_height))
		name := info.name if b != .Casino else "CASINÒ"
		is_hovered := false
		if h, ok := hovered.?; ok && h == b { is_hovered = true }
		near := hubworld.distance_to_building(b, w.position) < 7
		hub_draw_plate(theme, at, name, info.subtitle, color, near || is_hovered, is_hovered)
	}
}
