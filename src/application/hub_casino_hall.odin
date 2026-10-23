package application

import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import audio "../engine/audio"
import hubworld "../hubworld"
import render "../render"
import arcade "../memoryarcade"
import campaign "../campaign"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

// INSIDE THE CASINO (Fase 9 of docs/piano-griglia.md): entering the Casinò from the plaza
// dissolves into the hall, where the robot walks up to a station to open its game
// exactly as the old page did, with the depot's wallet, and the door at the right
// dissolves back to the plaza. The dissolve is the way between zones that the depot
// and the arcade hall (Fasi 10 and 11) use too.

// Where a dissolve of the hub ends up.
Hub_Fade_Target :: enum u8 { Casino_Hall, Plaza_From_Casino }

@(private)
hub_fade_to :: proc(h: ^Campaign_Hub, target: Hub_Fade_Target) {
	h.fade_to = target
	hubworld.fade_begin(&h.fade)
}

// The zone changes at the darkest moment of the dissolve.
@(private)
hub_fade_switch :: proc(h: ^Campaign_Hub) {
	switch h.fade_to {
	case .Casino_Hall:
		h.page = .Casino_Hall
		hubworld.room_place_at_centre(&h.hall)
		h.hall_camera = {}
		h.ambience = hubworld.ambience_start(u32(h.options.seed))
	case .Plaza_From_Casino:
		hub_world_return_to(h, .Casino)
	}
}

// Runs a dissolve; true while one is on (the hub waits for it: nothing is clickable).
@(private)
hub_fade_update :: proc(h: ^Campaign_Hub, frame: ^host.Frame) -> bool {
	if !h.fade.active { return false }
	if hubworld.fade_step(&h.fade, frame.dt) { hub_fade_switch(h) }
	return h.fade.active
}

@(private)
hub_fade_draw :: proc(h: ^Campaign_Hub) {
	if alpha := hubworld.fade_alpha(h.fade); alpha > 0 { rl.DrawRectangle(0, 0, 960, 540, {0, 0, 0, u8(alpha*255)}) }
}

@(private = "file")
hub_hall_camera_goal :: proc(at: hubworld.Vec2) -> [2]f32 {
	return {at.x * 0.35, at.y * 0.4}
}

@(private)
hub_hall_camera :: proc(h: ^Campaign_Hub) -> rl.Camera3D {
	target := rl.Vector3{h.hall_camera.x, 1.5, h.hall_camera.y + 2}
	return {position = target + rl.Vector3{0, 18, 22}, target = target, up = {0, 1, 0}, fovy = 44, projection = .PERSPECTIVE}
}

// Back in the hall, the robot just outside the door of station `i`.
@(private)
hub_hall_return_to :: proc(h: ^Campaign_Hub, i: int) {
	h.hall_from = i
	hubworld.room_place_before(&h.hall_room, &h.hall, i)
	h.hall_camera = hub_hall_camera_goal(h.hall.position)
}

// Opens the game of a station, as the page's buttons did.
@(private = "file")
hub_open_casino_game :: proc(h: ^Campaign_Hub, frame: ^host.Frame, kind: arcade.Casino_Kind) {
	wallet := arcade.Casino_Wallet{data = h, balance = hub_balance, debit = hub_debit, credit = hub_credit, changed = hub_wallet_changed, commit = hub_wallet_commit,
		transaction = &h.saved.casino, random_state = &h.saved.casino_random}
	scene := arcade.casino_create(kind, wallet, h.options.seed)
	if h.smoke_world {
		games := HALL_SMOKE_GAME_NAMES
		hall_smoke_game_name = games[int(kind)]
		scene.after_present = hub_hall_smoke_game_present
	}
	h.in_game = true
	host.push(frame, scene)
}

@(private = "file")
hub_hall_enter :: proc(h: ^Campaign_Hub, i: int, frame: ^host.Frame) {
	h.hall_from = i
	ui.cancel_interaction(frame.ui)
	if i == h.hall_room.exit {
		hub_fade_to(h, .Plaza_From_Casino)
		return
	}
	hub_open_casino_game(h, frame, arcade.Casino_Kind(i))
}

// The station under the pointer: its box under the ray from the camera, else the floor
// where the ray lands.
@(private = "file")
hub_hall_pick :: proc(h: ^Campaign_Hub, frame: ^host.Frame, camera: rl.Camera3D) -> (i: int, found: bool) {
	ray := rl.GetScreenToWorldRayEx(frame.mouse, camera, 960, 540)
	origin, direction := [3]f32{ray.position.x, ray.position.y, ray.position.z}, [3]f32{ray.direction.x, ray.direction.y, ray.direction.z}
	nearest := f32(1e9)
	for k in 0..<h.hall_room.count {
		if distance, hit := hubworld.station_ray_hits(h.hall_room.stations[k], origin, direction); hit && distance < nearest { i, found, nearest = k, true, distance }
	}
	if found || direction.y > -0.0001 { return }
	ground := -origin.y / direction.y
	return hubworld.room_station_at(&h.hall_room, {origin.x + direction.x * ground, origin.z + direction.z * ground}, 0.8)
}

@(private)
hub_hall_update :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	ctx := frame.ui
	p := ctx.theme.palette
	ui.label(ctx, {28, 18, 650, 40}, "IL CASINÒ", .Title, p.text)
	camera := hub_hall_camera(h)
	h.hall_hover = nil
	if hovered, found := hub_hall_pick(h, frame, camera); found {
		h.hall_hover = hovered
		if input.mouse_pressed(frame.devices, .LEFT) { hubworld.room_walk_to(&h.hall_room, &h.hall, hovered) }
	}
	dt := min(frame.dt, 0.05)
	entered, did_enter := hubworld.room_step(&h.hall_room, &h.hall, hub_walk_wish(frame), dt)
	goal := hub_hall_camera_goal(h.hall.position)
	h.hall_camera += (goal - h.hall_camera) * min(dt * 4, 1)
	// The room's sounds: a murmur, a slot now and then, the wheel's ticks near the roulette.
	near_wheel := hubworld.station_distance(h.hall_room.stations[hubworld.Casino_Station.Roulette], h.hall.position) < 5
	cues := hubworld.ambience_step(&h.ambience, dt, near_wheel)
	if .Murmur in cues { audio.play(frame.audio, .Hall_Murmur, 0.6) }
	if .Slot in cues { audio.play(frame.audio, .Hall_Slot, 0.5) }
	if .Wheel in cues { audio.play(frame.audio, .Hall_Wheel, 0.5) }
	if did_enter { hub_hall_enter(h, entered, frame); return }
	ui.label(ctx, {33, 508, 880, 24}, "WASD o frecce per muoverti. Clic su una struttura per andarci. La porta a destra torna in piazza.", .Small, p.text_dim)
	if h.notice_time > 0 { ui.label(ctx, {32, 483, 890, 28}, h.notice, .Small, p.warning) }
	if h.save_failed { ui.label(ctx, {32, 460, 890, 22}, "Salvataggio non riuscito. Il progresso resta in memoria; riprova prima di uscire.", .Small, p.warning) }
}

@(private)
hub_hall_draw :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	camera := hub_hall_camera(h)
	render.draw_hub_casino(&h.hall_room, &h.hall, camera, h.hall_hover)
	render.draw_hub_casino_labels(frame.theme, &h.hall_room, &h.hall, camera, 960, 540, campaign.depot_credits(&h.progress), h.hall_hover)
}

// THE SMOKE of the hall (--smoke-hub-world, see hub_world_smoke): each game opens,
// is captured and closed; the robot is then in front of its station.
@(private = "file")
HALL_SMOKE_GAME_NAMES :: [4]cstring{"odin_pp_hub_casino_gioco_ranch.png", "odin_pp_hub_casino_gioco_fuga.png", "odin_pp_hub_casino_gioco_roulette.png", "odin_pp_hub_casino_gioco_d20.png"}
@(private = "file")
HALL_SMOKE_STATION_NAMES :: [4]cstring{"odin_pp_hub_casino_ranch.png", "odin_pp_hub_casino_fuga.png", "odin_pp_hub_casino_roulette.png", "odin_pp_hub_casino_d20.png"}
@(private = "file")
hall_smoke_game_name: cstring

@(private = "file")
hub_hall_smoke_game_present :: proc(data: rawptr, frame: ^host.Frame) {
	if frame.index%45 != 0 { return }
	artifacts.screenshot(hall_smoke_game_name)
	host.pop(frame)
}

// One frame of the hall's part of the smoke. Returns true once the whole walk is done.
@(private)
hub_hall_smoke :: proc(h: ^Campaign_Hub) -> bool {
	room := &h.hall_room
	names := HALL_SMOKE_STATION_NAMES
	station := h.smoke_hall
	switch h.smoke_phase {
	case 10:
		// The dissolve is over: the hall, the robot at its middle.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 6 {
			assert(h.page == .Casino_Hall && !h.fade.active, "the hall smoke: the dissolve did not end in the hall")
			artifacts.screenshot("odin_pp_hub_casino_sala.png")
		}
		if h.smoke_wait >= 8 { h.smoke_phase, h.smoke_wait, h.smoke_hall = 11, 0, 0 }
	case 11:
		hubworld.room_walk_to(room, &h.hall, station)
		h.smoke_phase, h.smoke_wait, h.smoke_shot = 12, 0, false
	case 12:
		h.smoke_wait += 1
		assert(h.smoke_wait < 1200, "the hall smoke: the robot did not reach a door")
		if !h.smoke_shot && station < 4 && hubworld.station_distance(room.stations[station], h.hall.position) < 2.4 {
			artifacts.screenshot(names[station])
			h.smoke_shot = true
		}
		if station < 4 && h.in_game { h.smoke_phase, h.smoke_wait = 13, 0 }
		if station == h.hall_room.exit && h.fade.active {
			assert(h.fade_to == .Plaza_From_Casino, "the hall smoke: the way out does not lead to the plaza")
			h.smoke_phase, h.smoke_wait = 14, 0
		}
	case 13:
		// A game is open (it closes itself after its capture): back in the hall, in front of its station.
		if h.in_game { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 {
			assert(h.page == .Casino_Hall && h.hall_from == station, "the hall smoke: back in the wrong place")
			assert(!hubworld.station_in_door(room.stations[station], h.hall.position, hubworld.DOOR_REARM_MARGIN), "the hall smoke: the robot came back on the door")
			if station == int(hubworld.Casino_Station.Roulette) { artifacts.screenshot("odin_pp_hub_casino_ritorno_sala.png") }
		}
		if h.smoke_wait >= 4 { h.smoke_phase, h.smoke_hall = 11, station+1 }
	case 14:
		// Out through the way to the plaza: in front of the Casinò.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 { assert(h.page == .World && h.plaza_from == .Casino, "the hall smoke: the way out did not reach the plaza") }
		if h.smoke_wait == 4 { artifacts.screenshot("odin_pp_hub_casino_ritorno_piazza.png") }
		if h.smoke_wait >= 5 { return true }
	}
	return false
}
