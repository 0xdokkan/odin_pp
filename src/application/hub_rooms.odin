package application

import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import audio "../engine/audio"
import hubworld "../hubworld"
import render "../render"
import arcade "../memoryarcade"
import campaign "../campaign"
import campaignui "../campaignui"
import game "../game"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"

// THE ROOMS BEHIND THE PLAZA'S DOORS (Fasi 9 and 10 of docs/piano-griglia.md; the arcade
// hall of Fase 11 is the next): entering a building dissolves into its room, where the
// robot walks up to a station. In the casino's hall a station opens a game exactly as
// the old page did, with the depot's wallet; in the depot it opens the panel of the
// same name. The way out dissolves back to the plaza, in front of the building. Coming
// back from a game or a panel the robot is in front of its station.

Hub_Room :: enum u8 { Casino, Depot, Arcade }

// Where a dissolve of the hub ends up.
Hub_Fade_Target :: enum u8 { Room, Plaza }

@(private)
hub_fade_to :: proc(h: ^Campaign_Hub, target: Hub_Fade_Target, room: Hub_Room) {
	h.fade_to = target
	h.fade_room = room
	hubworld.fade_begin(&h.fade)
}

// Sets up `kind`'s room with the robot at its middle.
@(private)
hub_room_setup :: proc(h: ^Campaign_Hub, kind: Hub_Room) {
	h.room_kind = kind
	switch kind {
	case .Casino: h.room = hubworld.casino_room()
	case .Depot: h.room = hubworld.depot_room()
	case .Arcade:
		_, unlocked := hub_unlocked_arcades(&h.progress)
		h.room = hubworld.arcade_room(unlocked)
	}
	hubworld.room_place_at_centre(&h.room_world)
	h.room_camera = {}
	h.room_from = 0
	h.ambience = hubworld.ambience_start(u32(h.options.seed))
}

// The building of the plaza a room belongs to.
@(private)
hub_room_building :: proc(kind: Hub_Room) -> hubworld.Building {
	switch kind {
	case .Casino: return .Casino
	case .Depot: return .Storage
	case .Arcade: return .Arcade
	}
	return .Casino
}

// The room behind a building's door.
@(private)
hub_room_of_building :: proc(b: hubworld.Building) -> Hub_Room {
	#partial switch b {
	case .Storage: return .Depot
	case .Arcade: return .Arcade
	}
	return .Casino
}

// The zone changes at the darkest moment of the dissolve.
@(private)
hub_fade_switch :: proc(h: ^Campaign_Hub) {
	switch h.fade_to {
	case .Room:
		hub_room_setup(h, h.fade_room)
		h.page = .Room
	case .Plaza:
		hub_world_return_to(h, hub_room_building(h.fade_room))
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
hub_room_camera_goal :: proc(at: hubworld.Vec2) -> [2]f32 {
	return {at.x * 0.35, at.y * 0.4}
}

@(private)
hub_room_camera :: proc(h: ^Campaign_Hub) -> rl.Camera3D {
	target := rl.Vector3{h.room_camera.x, 1.5, h.room_camera.y + 2}
	return {position = target + rl.Vector3{0, 18, 22}, target = target, up = {0, 1, 0}, fovy = 44, projection = .PERSPECTIVE}
}

// Back in the room, the robot just outside the door of station `i`.
@(private)
hub_room_return_to :: proc(h: ^Campaign_Hub, i: int) {
	h.page = .Room
	h.room_from = i
	hubworld.room_place_before(&h.room, &h.room_world, i)
	h.room_camera = hub_room_camera_goal(h.room_world.position)
}

// Opens the game of a casino station, as the old page's buttons did.
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

// Opens the panel of a depot station: the backpack, the character, the card archive.
@(private)
hub_open_depot_panel :: proc(h: ^Campaign_Hub, station: int) {
	h.inventory.panel = campaignui.Panel(station)
	h.inventory.selected = {}
	h.inventory.dragging = false
	h.inventory.card_page = 0
	h.page = .Storage
}

// The panel closed: back in the depot, in front of the station it was opened from.
@(private)
hub_storage_closed :: proc(h: ^Campaign_Hub) {
	if h.room_kind == .Depot && h.room.count > 0 { hub_room_return_to(h, h.room_from) } else { hub_world_return_to(h, .Storage) }
}

// What the depot shows of the campaign: the gear the backpack holds, what the depot
// stores, and how many of the cards are known.
@(private)
hub_depot_view :: proc(c: ^campaign.Campaign) -> (view: hubworld.Depot_View) {
	if c == nil { return }
	if c.backpack.weapon.kind == .Weapon { view.gear.has_weapon, view.gear.weapon = true, c.backpack.weapon.variant }
	for relic, i in c.backpack.relics {
		if relic.kind == .Relic { view.gear.has_relic[i], view.gear.relic[i] = true, relic.variant }
	}
	for page in c.depot { view.stored += page.count }
	for id in game.Card_Id.Strike..<game.Card_Id.Count {
		if game.card_is_lab_only(id) { continue }
		view.total += 1
		if c.discovered[id] { view.discovered += 1 }
	}
	return
}

@(private = "file")
hub_room_enter :: proc(h: ^Campaign_Hub, i: int, frame: ^host.Frame) {
	h.room_from = i
	ui.cancel_interaction(frame.ui)
	if i == h.room.exit {
		hub_fade_to(h, .Plaza, h.room_kind)
		return
	}
	switch h.room_kind {
	case .Casino: hub_open_casino_game(h, frame, arcade.Casino_Kind(i))
	case .Depot: hub_open_depot_panel(h, i)
	case .Arcade: hub_open_arcade_game(h, frame, i)
	}
}

// The station under the pointer: its box under the ray from the camera, else the floor
// where the ray lands.
@(private = "file")
hub_room_pick :: proc(h: ^Campaign_Hub, frame: ^host.Frame, camera: rl.Camera3D) -> (i: int, found: bool) {
	ray := rl.GetScreenToWorldRayEx(frame.mouse, camera, 960, 540)
	origin, direction := [3]f32{ray.position.x, ray.position.y, ray.position.z}, [3]f32{ray.direction.x, ray.direction.y, ray.direction.z}
	nearest := f32(1e9)
	for k in 0..<h.room.count {
		if h.room.stations[k].decor { continue }
		if distance, hit := hubworld.station_ray_hits(h.room.stations[k], origin, direction); hit && distance < nearest { i, found, nearest = k, true, distance }
	}
	if found || direction.y > -0.0001 { return }
	ground := -origin.y / direction.y
	return hubworld.room_station_at(&h.room, {origin.x + direction.x * ground, origin.z + direction.z * ground}, 0.8)
}

@(private)
hub_room_update :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	ctx := frame.ui
	p := ctx.theme.palette
	ui.label(ctx, {28, 18, 650, 40}, h.room.name, .Title, p.text)
	camera := hub_room_camera(h)
	h.room_hover = nil
	if hovered, found := hub_room_pick(h, frame, camera); found {
		h.room_hover = hovered
		if input.mouse_pressed(frame.devices, .LEFT) { hubworld.room_walk_to(&h.room, &h.room_world, hovered) }
	}
	dt := min(frame.dt, 0.05)
	entered, did_enter := hubworld.room_step(&h.room, &h.room_world, hub_walk_wish(frame), dt)
	goal := hub_room_camera_goal(h.room_world.position)
	h.room_camera += (goal - h.room_camera) * min(dt * 4, 1)
	if h.room_kind == .Casino {
		// The room's sounds: a murmur, a slot now and then, the wheel's ticks near the roulette.
		near_wheel := hubworld.station_distance(h.room.stations[hubworld.Casino_Station.Roulette], h.room_world.position) < 5
		cues := hubworld.ambience_step(&h.ambience, dt, near_wheel)
		if .Murmur in cues { audio.play(frame.audio, .Hall_Murmur, 0.6) }
		if .Slot in cues { audio.play(frame.audio, .Hall_Slot, 0.5) }
		if .Wheel in cues { audio.play(frame.audio, .Hall_Wheel, 0.5) }
	}
	if did_enter { hub_room_enter(h, entered, frame); return }
	hint := "WASD o frecce per muoverti. Clic su una struttura per andarci. La porta a destra torna in piazza."
	switch h.room_kind {
	case .Casino:
	case .Depot: hint = "WASD o frecce per muoverti. Clic su un oggetto per andarci. La porta in basso a destra torna in piazza."
	case .Arcade: hint = "WASD o frecce per muoverti. Clic su un cabinato per giocare. La porta in basso torna in piazza."
	}
	ui.label(ctx, {33, 508, 880, 24}, hint, .Small, p.text_dim)
	if h.notice_time > 0 { ui.label(ctx, {32, 483, 890, 28}, h.notice, .Small, p.warning) }
	if h.save_failed { ui.label(ctx, {32, 460, 890, 22}, "Salvataggio non riuscito. Il progresso resta in memoria; riprova prima di uscire.", .Small, p.warning) }
}

@(private)
hub_room_draw :: proc(h: ^Campaign_Hub, frame: ^host.Frame) {
	camera := hub_room_camera(h)
	switch h.room_kind {
	case .Casino:
		render.draw_hub_casino(&h.room, &h.room_world, camera, h.room_hover)
		render.draw_hub_casino_labels(frame.theme, &h.room, &h.room_world, camera, 960, 540, campaign.depot_credits(&h.progress), h.room_hover)
	case .Depot:
		render.draw_hub_depot(&h.room, &h.room_world, camera, h.room_hover, hub_depot_view(&h.progress))
		render.draw_hub_depot_labels(frame.theme, &h.room, &h.room_world, camera, 960, 540, h.room_hover)
	case .Arcade:
		view := hub_arcade_view(&h.progress)
		render.draw_hub_arcade(&h.room, &h.room_world, camera, h.room_hover, view)
		render.draw_hub_arcade_labels(frame.theme, &h.room, &h.room_world, camera, 960, 540, h.room_hover, view)
	}
}

// THE SMOKES of the rooms (--smoke-hub-world, see hub_world_smoke). The casino: each
// game opens, is captured and closed. The depot: each panel opens, is captured and
// closed. Each time the robot is then in front of its station.
@(private = "file")
HALL_SMOKE_GAME_NAMES :: [4]cstring{"odin_pp_hub_casino_gioco_ranch.png", "odin_pp_hub_casino_gioco_fuga.png", "odin_pp_hub_casino_gioco_roulette.png", "odin_pp_hub_casino_gioco_d20.png"}
@(private = "file")
HALL_SMOKE_STATION_NAMES :: [4]cstring{"odin_pp_hub_casino_ranch.png", "odin_pp_hub_casino_fuga.png", "odin_pp_hub_casino_roulette.png", "odin_pp_hub_casino_d20.png"}
@(private = "file")
DEPOT_SMOKE_STATION_NAMES :: [3]cstring{"odin_pp_hub_depot_zaino.png", "odin_pp_hub_depot_manichino.png", "odin_pp_hub_depot_archivio.png"}
@(private = "file")
DEPOT_SMOKE_PANEL_NAMES :: [3]cstring{"odin_pp_hub_depot_pannello_zaino.png", "odin_pp_hub_depot_pannello_personaggio.png", "odin_pp_hub_depot_pannello_archivio.png"}
@(private)
hall_smoke_game_name: cstring

@(private)
hub_hall_smoke_game_present :: proc(data: rawptr, frame: ^host.Frame) {
	if frame.index%45 != 0 { return }
	artifacts.screenshot(hall_smoke_game_name)
	host.pop(frame)
}

// Phases of the smoke at the plaza's doors: 10 to 14 the casino, 20 to 25 the depot,
// 30 to 35 the arcade hall.
HUB_SMOKE_CASINO :: 10
HUB_SMOKE_DEPOT :: 20
HUB_SMOKE_ARCADE :: 30

// One frame of a room's part of the smoke. Returns true once the whole walk is done.
@(private)
hub_room_smoke :: proc(h: ^Campaign_Hub) -> bool {
	if h.smoke_phase >= HUB_SMOKE_ARCADE { return hub_arcade_smoke(h) }
	if h.smoke_phase >= HUB_SMOKE_DEPOT { return hub_depot_smoke(h) }
	return hub_casino_smoke(h)
}

@(private = "file")
hub_casino_smoke :: proc(h: ^Campaign_Hub) -> bool {
	room := &h.room
	names := HALL_SMOKE_STATION_NAMES
	station := h.smoke_hall
	switch h.smoke_phase {
	case 10:
		// The dissolve is over: the hall, the robot at its middle.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 6 {
			assert(h.page == .Room && h.room_kind == .Casino && !h.fade.active, "the hall smoke: the dissolve did not end in the hall")
			artifacts.screenshot("odin_pp_hub_casino_sala.png")
		}
		if h.smoke_wait >= 8 { h.smoke_phase, h.smoke_wait, h.smoke_hall = 11, 0, 0 }
	case 11:
		hubworld.room_walk_to(room, &h.room_world, station)
		h.smoke_phase, h.smoke_wait, h.smoke_shot = 12, 0, false
	case 12:
		h.smoke_wait += 1
		assert(h.smoke_wait < 1200, "the hall smoke: the robot did not reach a door")
		if !h.smoke_shot && station < 4 && hubworld.station_distance(room.stations[station], h.room_world.position) < 2.4 {
			artifacts.screenshot(names[station])
			h.smoke_shot = true
		}
		if station < 4 && h.in_game { h.smoke_phase, h.smoke_wait = 13, 0 }
		if station == h.room.exit && h.fade.active {
			assert(h.fade_to == .Plaza, "the hall smoke: the way out does not lead to the plaza")
			h.smoke_phase, h.smoke_wait = 14, 0
		}
	case 13:
		// A game is open (it closes itself after its capture): back in the hall, in front of its station.
		if h.in_game { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 {
			assert(h.page == .Room && h.room_from == station, "the hall smoke: back in the wrong place")
			assert(!hubworld.station_in_door(room.stations[station], h.room_world.position, hubworld.DOOR_REARM_MARGIN), "the hall smoke: the robot came back on the door")
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

@(private = "file")
hub_depot_smoke :: proc(h: ^Campaign_Hub) -> bool {
	room := &h.room
	stations := DEPOT_SMOKE_STATION_NAMES
	panels := DEPOT_SMOKE_PANEL_NAMES
	station := h.smoke_hall
	switch h.smoke_phase {
	case 20:
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 6 {
			assert(h.page == .Room && h.room_kind == .Depot && !h.fade.active, "the depot smoke: the dissolve did not end in the depot")
			artifacts.screenshot("odin_pp_hub_depot_sala.png")
		}
		if h.smoke_wait >= 8 { h.smoke_phase, h.smoke_wait, h.smoke_hall = 21, 0, 0 }
	case 21:
		hubworld.room_walk_to(room, &h.room_world, station)
		h.smoke_phase, h.smoke_wait, h.smoke_shot = 22, 0, false
	case 22:
		h.smoke_wait += 1
		assert(h.smoke_wait < 1200, "the depot smoke: the robot did not reach a door")
		if !h.smoke_shot && station < 3 && hubworld.station_distance(room.stations[station], h.room_world.position) < 2.6 {
			artifacts.screenshot(stations[station])
			h.smoke_shot = true
		}
		if station < 3 && h.page == .Storage {
			assert(h.inventory.panel == campaignui.Panel(station), "the depot smoke: a station opened the wrong panel")
			h.smoke_phase, h.smoke_wait = 23, 0
		}
		if station == h.room.exit && h.fade.active {
			assert(h.fade_to == .Plaza, "the depot smoke: the way out does not lead to the plaza")
			h.smoke_phase, h.smoke_wait = 24, 0
		}
	case 23:
		// The panel is up for a few frames, then it is closed as its button does.
		h.smoke_wait += 1
		if h.smoke_wait == 4 { artifacts.screenshot(panels[station]) }
		if h.smoke_wait >= 5 {
			hub_storage_closed(h)
			assert(h.page == .Room && h.room_from == station, "the depot smoke: back in the wrong place")
			assert(!hubworld.station_in_door(room.stations[station], h.room_world.position, hubworld.DOOR_REARM_MARGIN), "the depot smoke: the robot came back on the door")
			h.smoke_phase, h.smoke_wait = 25, 0
		}
	case 25:
		h.smoke_wait += 1
		if h.smoke_wait == 4 && station == int(hubworld.Depot_Station.Character) { artifacts.screenshot("odin_pp_hub_depot_ritorno.png") }
		if h.smoke_wait >= 5 { h.smoke_phase, h.smoke_hall = 21, station+1 }
	case 24:
		// Out through the way to the plaza: in front of the Deposito.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 { assert(h.page == .World && h.plaza_from == .Storage, "the depot smoke: the way out did not reach the plaza") }
		if h.smoke_wait == 4 { artifacts.screenshot("odin_pp_hub_depot_ritorno_piazza.png") }
		if h.smoke_wait >= 5 { return true }
	}
	return false
}
