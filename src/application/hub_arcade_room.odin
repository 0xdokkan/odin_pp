package application

import artifacts "../devtools/artifacts"
import activities "../activities"
import campaign "../campaign"
import hubworld "../hubworld"
import host "../engine/host"

// INSIDE THE ARCADE HALL (Fase 11 of docs/piano-griglia.md): a room of the hub (see
// hub_rooms.odin) where each cabinet the player has unlocked is a place the robot
// walks up to; entering it plays that minigame exactly as the old page's "GIOCA"
// button did, and the record on the sign follows the game just played. The places
// not yet unlocked hold a covered cabinet that says nothing about its game.

// What the hall shows: the unlocked cabinets (the same list as the old page and the
// records page, `hub_unlocked_arcades`), each with its game, name and record.
@(private)
hub_arcade_view :: proc(c: ^campaign.Campaign) -> (view: hubworld.Arcade_View) {
	if c == nil { return }
	indices, count := hub_unlocked_arcades(c)
	view.count = count
	for k in 0..<count {
		index := indices[k]
		info, _ := activities.minigame_info(index)
		view.game[k] = index
		view.title[k] = info.title
		view.record[k] = hub_record_line(c, index)
		view.stars[k] = c.records[index].best_stars
	}
	return
}

// The minigame the cabinet at `station` plays: ok only for a lit cabinet.
@(private)
hub_arcade_game :: proc(c: ^campaign.Campaign, station: int) -> (index: int, ok: bool) {
	indices, count := hub_unlocked_arcades(c)
	if station < 0 || station >= count { return }
	return indices[station], true
}

@(private)
hub_open_arcade_game :: proc(h: ^Campaign_Hub, frame: ^host.Frame, station: int) {
	index, ok := hub_arcade_game(&h.progress, station)
	if !ok { return }
	info, _ := activities.minigame_info(index)
	scene := info.create({seed = h.options.seed~u64(h.clock*1000)})
	if h.smoke_world {
		names := ARCADE_SMOKE_GAME_NAMES
		hall_smoke_game_name = names[min(h.smoke_hall, len(names)-1)]
		scene.after_present = hub_hall_smoke_game_present
	}
	h.in_game = true
	host.push(frame, scene)
}

// THE SMOKE of the hall (hub_world_smoke): the hall with nothing unlocked, then with
// some biomes won; the robot walks to the first and the last lit cabinet, each game
// opens, is captured and closed, and the robot is back in front of its cabinet; then
// out by the way to the plaza.
@(private = "file")
ARCADE_SMOKE_GAME_NAMES :: [3]cstring{"odin_pp_hub_arcade_gioco_primo.png", "odin_pp_hub_arcade_gioco_ultimo.png", "odin_pp_hub_arcade_gioco_ultimo.png"}
@(private = "file")
ARCADE_SMOKE_NEAR_NAMES :: [2]cstring{"odin_pp_hub_arcade_cabinato.png", "odin_pp_hub_arcade_cabinato_ultimo.png"}
@(private = "file")
ARCADE_SMOKE_BIOMES :: [5]campaign.Biome{.Cyber, .City, .West, .Egypt, .Jungle}

// The stations the smoke walks to: the first lit cabinet, the last, the way out.
@(private = "file")
hub_arcade_smoke_station :: proc(h: ^Campaign_Hub) -> int {
	_, count := hub_unlocked_arcades(&h.progress)
	switch h.smoke_hall {
	case 0: return 0
	case 1: return max(count-1, 0)
	}
	return hubworld.ARCADE_EXIT
}

@(private)
hub_arcade_smoke :: proc(h: ^Campaign_Hub) -> bool {
	room := &h.room
	station := hub_arcade_smoke_station(h)
	switch h.smoke_phase {
	case 30:
		// The dissolve is over: the hall with nothing unlocked.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 6 {
			assert(h.page == .Room && h.room_kind == .Arcade && !h.fade.active, "the arcade smoke: the dissolve did not end in the hall")
			_, count := hub_unlocked_arcades(&h.progress)
			assert(count == 0, "the arcade smoke: a cabinet is lit before any biome is won")
			artifacts.screenshot("odin_pp_hub_arcade_vuota.png")
		}
		if h.smoke_wait >= 8 {
			// Some biomes won: the hall as it is on the next visit.
			for b in ARCADE_SMOKE_BIOMES { h.progress.won[b] = true }
			campaign.record_result(&h.progress, 0, 1500, 2, true)
			hub_room_setup(h, .Arcade)
			h.smoke_phase, h.smoke_wait, h.smoke_hall = 31, 0, 0
		}
	case 31:
		h.smoke_wait += 1
		if h.smoke_wait == 4 {
			_, count := hub_unlocked_arcades(&h.progress)
			assert(count > 1 && count < hubworld.ARCADE_SLOTS, "the arcade smoke: the hall should have some, not all, cabinets lit")
			artifacts.screenshot("odin_pp_hub_arcade_sala.png")
		}
		if h.smoke_wait >= 6 { h.smoke_phase, h.smoke_wait = 32, 0 }
	case 32:
		hubworld.room_walk_to(room, &h.room_world, station)
		h.smoke_phase, h.smoke_wait, h.smoke_shot = 33, 0, false
	case 33:
		h.smoke_wait += 1
		assert(h.smoke_wait < 2400, "the arcade smoke: the robot did not reach a door")
		near := ARCADE_SMOKE_NEAR_NAMES
		if !h.smoke_shot && h.smoke_hall < 2 && hubworld.station_distance(room.stations[station], h.room_world.position) < 2.6 {
			artifacts.screenshot(near[h.smoke_hall])
			h.smoke_shot = true
		}
		if h.smoke_hall < 2 && h.in_game { h.smoke_phase, h.smoke_wait = 34, 0 }
		if station == h.room.exit && h.fade.active {
			assert(h.fade_to == .Plaza, "the arcade smoke: the way out does not lead to the plaza")
			h.smoke_phase, h.smoke_wait = 35, 0
		}
	case 34:
		// A game is open (it closes itself after its capture): back in the hall, in front of its cabinet.
		if h.in_game { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 {
			assert(h.page == .Room && h.room_from == station, "the arcade smoke: back in the wrong place")
			assert(!hubworld.station_in_door(room.stations[station], h.room_world.position, hubworld.DOOR_REARM_MARGIN), "the arcade smoke: the robot came back on the door")
		}
		if h.smoke_wait == 4 && h.smoke_hall == 0 { artifacts.screenshot("odin_pp_hub_arcade_ritorno.png") }
		if h.smoke_wait >= 5 { h.smoke_phase, h.smoke_hall = 32, h.smoke_hall+1 }
	case 35:
		// Out through the way to the plaza: in front of the Sala giochi.
		if h.fade.active { return false }
		h.smoke_wait += 1
		if h.smoke_wait == 1 { assert(h.page == .World && h.plaza_from == .Arcade, "the arcade smoke: the way out did not reach the plaza") }
		if h.smoke_wait == 4 { artifacts.screenshot("odin_pp_hub_arcade_ritorno_piazza.png") }
		if h.smoke_wait >= 5 { return true }
	}
	return false
}
