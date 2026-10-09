package main

import host "engine/host"
import arena "minigames/arena"
import fps "minigames/fps"
import platform2d "minigames/platform2d"
import puzzle "minigames/puzzle"

// Minigames offered by the menu and by run challenges, in display order.
// Challenges pick `seed % MINIGAME_COUNT`, so editing the list changes which
// minigame a given run seed offers.
MINIGAME_COUNT :: 4

minigame_info :: proc(index: int) -> (host.Minigame_Info, bool) {
	switch index {
	case 0:
		return platform2d.info(), true
	case 1:
		return arena.info(), true
	case 2:
		return fps.info(), true
	case 3:
		return puzzle.info(), true
	}
	return {}, false
}

minigame_index_by_id :: proc(id: string) -> int {
	for i := 0; i < MINIGAME_COUNT; i += 1 {
		if info, ok := minigame_info(i); ok && info.id == id {
			return i
		}
	}
	return -1
}
