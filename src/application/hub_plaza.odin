package application

import "core:fmt"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import hubworld "../hubworld"
import render "../render"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

// THE PLAZA (Fase 8 of docs/piano-griglia.md): the hub's first page after the slots.
// The robot walks among the buildings (hubworld has the rules, render/hub_world.odin
// the drawing); each building's door opens one of the hub's pages, and "Torna in
// piazza" brings the robot back in front of the door it went through.

@(private = "file")
HUB_CANVAS_WIDTH :: 960
@(private = "file")
HUB_CANVAS_HEIGHT :: 540
// The top-right "Slot / Salva" button: a click on it is not a click on the plaza.
@(private = "file")
HUB_SLOT_BUTTON :: rl.Rectangle{798, 24, 132, 32}

// The page a building's door opens (the Uscita has none: it leaves the memory).
@(private = "file")
hub_page_of_building :: proc(b: hubworld.Building) -> Hub_Page {
	switch b {
	case .Portal:   return .Galaxy
	case .Storage:  return .Storage
	case .Progress: return .Progress
	case .Arcade:   return .Arcade
	case .Casino:   return .Casino_Hall
	case .Memories: return .Memories
	case .Exit:     return .Slots
	}
	return .World
}

// Where the camera's middle goes for a robot at `at`: it follows the robot part of the
// way, so the Portal stays in view from the back of the plaza and the robot from the front.
@(private = "file")
hub_world_camera_goal :: proc(at: hubworld.Vec2) -> [2]f32 {
	return {at.x * 0.5, at.y * 0.6}
}

@(private)
hub_world_camera :: proc(h: ^Campaign_Hub) -> rl.Camera3D {
	target := rl.Vector3{h.plaza_camera.x, 2, h.plaza_camera.y + 4}
	return {position = target + rl.Vector3{0, 21, 28}, target = target, up = {0, 1, 0}, fovy = 46, projection = .PERSPECTIVE}
}

// Back on the plaza, the robot just outside the door of `b`.
@(private)
hub_world_return_to :: proc(h: ^Campaign_Hub, b: hubworld.Building) {
	h.page = .World
	h.plaza_from = b
	hubworld.place_before_building(&h.plaza, b)
	h.plaza_camera = hub_world_camera_goal(h.plaza.position)
}

@(private = "file")
hub_world_enter :: proc(h: ^Campaign_Hub, b: hubworld.Building, frame: ^host.Frame) {
	h.plaza_from = b
	ui.cancel_interaction(frame.ui)
	if b == .Casino {
		hub_fade_to(h, .Casino_Hall)
		return
	}
	if b == .Exit {
		_ = hub_save(h)
		if hub_flush(h) { h.page = .Slots; hub_scan_slots(h) } else { hub_notice(h, "Salvataggio non riuscito. Riprova prima di cambiare memoria.") }
		return
	}
	h.page = hub_page_of_building(b)
}

// The building under the pointer: the one whose wall the ray from the camera enters
// first, else the one on the ground where the ray lands.
@(private = "file")
hub_world_pick :: proc(frame: ^host.Frame, camera: rl.Camera3D) -> (b: hubworld.Building, found: bool) {
	if rl.CheckCollisionPointRec(frame.mouse, HUB_SLOT_BUTTON) { return }
	ray := rl.GetScreenToWorldRayEx(frame.mouse, camera, HUB_CANVAS_WIDTH, HUB_CANVAS_HEIGHT)
	origin, direction := [3]f32{ray.position.x, ray.position.y, ray.position.z}, [3]f32{ray.direction.x, ray.direction.y, ray.direction.z}
	nearest := f32(1e9)
	for candidate in hubworld.Building {
		if distance, hit := hubworld.ray_hits_building(candidate, origin, direction); hit && distance < nearest { b, found, nearest = candidate, true, distance }
	}
	if found || direction.y > -0.0001 { return }
	ground := -origin.y / direction.y
	return hubworld.building_at({origin.x + direction.x * ground, origin.z + direction.z * ground}, 0.8)
}

// The way the keys ask the robot to go (screen-aligned: W is away from the camera).
@(private)
hub_walk_wish :: proc(frame: ^host.Frame) -> (wish: hubworld.Vec2) {
	if input.key_down(frame.devices, .W) || input.key_down(frame.devices, .UP) { wish.y -= 1 }
	if input.key_down(frame.devices, .S) || input.key_down(frame.devices, .DOWN) { wish.y += 1 }
	if input.key_down(frame.devices, .A) || input.key_down(frame.devices, .LEFT) { wish.x -= 1 }
	if input.key_down(frame.devices, .D) || input.key_down(frame.devices, .RIGHT) { wish.x += 1 }
	return
}

@(private)
hub_world_update :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	ctx := frame.ui
	p := ctx.theme.palette
	ui.label(ctx, {28, 18, 650, 40}, "LA PIAZZA DELLA MEMORIA", .Title, p.text)
	ui.label(ctx, {30, 61, 670, 24}, "Cammina fino a una porta per entrare.", .Small, p.text_dim)
	if ui.button(ctx, {798, 24, 132, 32}, "Slot / Salva") {
		_ = hub_save(h)
		if hub_flush(h) { h.page = .Slots; hub_scan_slots(h) }
		return
	}
	camera := hub_world_camera(h)
	h.plaza_hover = nil
	if hovered, found := hub_world_pick(frame, camera); found {
		h.plaza_hover = hovered
		if input.mouse_pressed(frame.devices, .LEFT) { hubworld.walk_to_building(&h.plaza, hovered) }
	}
	// A frame that lasted long (a drag of the window) is not one long step.
	dt := min(frame.dt, 0.05)
	entered, did_enter := hubworld.step(&h.plaza, hub_walk_wish(frame), dt)
	goal := hub_world_camera_goal(h.plaza.position)
	h.plaza_camera += (goal - h.plaza_camera) * min(dt * 4, 1)
	if did_enter { hub_world_enter(h, entered, frame); return }
	ui.label(ctx, {33, 508, 800, 24}, "WASD o frecce per muoverti. Clic su un edificio per andarci.", .Small, p.text_dim)
	if h.notice_time > 0 { ui.label(ctx, {32, 483, 890, 28}, h.notice, .Small, p.warning) }
	if h.save_failed { ui.label(ctx, {32, 460, 890, 22}, "Salvataggio non riuscito. Il progresso resta in memoria; riprova prima di uscire.", .Small, p.warning) }
}

@(private)
hub_world_draw :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	camera := hub_world_camera(h)
	render.draw_hub_world(&h.plaza, camera, h.plaza_hover)
	render.draw_hub_world_labels(frame.theme, &h.plaza, camera, HUB_CANVAS_WIDTH, HUB_CANVAS_HEIGHT, h.plaza_hover)
}

// THE SMOKE (--smoke-hub-world): the robot walks to every door by itself, each opens
// the page it should (the Uscita leaves for the slots), and the robot comes back in
// front of it. Stills odin_pp_hub_world_*.png.
@(private = "file")
HUB_WORLD_SMOKE_ORDER :: [hubworld.BUILDING_COUNT]hubworld.Building{.Portal, .Storage, .Progress, .Arcade, .Memories, .Exit, .Casino}

@(private)
hub_world_smoke :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	h.smoke_frame += 1
	if h.smoke_frame == 30 { artifacts.screenshot("odin_pp_hub_world_centro.png") }
	if h.smoke_frame <= 30 { return }
	// The casino's hall is the last walk: its own sequence (hub_hall_smoke).
	if h.smoke_phase >= 10 {
		if hub_hall_smoke(h) { host.quit(frame) }
		return
	}
	order := HUB_WORLD_SMOKE_ORDER
	if h.smoke_stage >= len(order) { host.quit(frame); return }
	b := order[h.smoke_stage]
	switch h.smoke_phase {
	case 0:
		hubworld.walk_to_building(&h.plaza, b)
		h.smoke_phase, h.smoke_wait = 1, 0
	case 1:
		// Walking: the first two buildings are shown as the robot arrives.
		h.smoke_wait += 1
		assert(h.smoke_wait < 1200, "the plaza smoke: the robot did not reach a door")
		if !h.smoke_shot && (b == .Casino || b == .Portal) && hubworld.distance_to_building(b, h.plaza.position) < 2.4 {
			artifacts.screenshot(fmt.ctprintf("odin_pp_hub_world_vicino_%s.png", "casino" if b == .Casino else "portale"))
			h.smoke_shot = true
		}
		if h.page != .World {
			assert(h.page == hub_page_of_building(b), "the plaza smoke: a door opened the wrong page")
			h.smoke_phase, h.smoke_wait, h.smoke_shot = 10 if b == .Casino else 2, 0, false
		}
	case 2:
		// The page is up for a few frames, then the robot comes back in front of the door.
		h.smoke_wait += 1
		if h.smoke_wait == 4 && b == .Portal { artifacts.screenshot("odin_pp_hub_world_pagina_portale.png") }
		if h.smoke_wait >= 5 {
			hub_world_return_to(h, b)
			h.smoke_phase, h.smoke_wait = 3, 0
		}
	case 3:
		h.smoke_wait += 1
		if h.smoke_wait == 4 && b == .Casino { artifacts.screenshot("odin_pp_hub_world_ritorno.png") }
		if h.smoke_wait >= 5 {
			assert(h.page == .World, "the plaza smoke: the robot is not back on the plaza")
			assert(!hubworld.in_door(b, h.plaza.position, hubworld.DOOR_REARM_MARGIN), "the plaza smoke: the robot came back on its door")
			h.smoke_stage += 1
			h.smoke_phase = 0
		}
	}
}
