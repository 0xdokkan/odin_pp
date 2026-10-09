package main

import host "engine/host"
import arena "minigames/arena"

// Minigames offered by the menu and by run challenges, in display order. The
// order also feeds challenge selection (seed modulo count), so appending keeps
// earlier seeds stable while reordering does not.
MINIGAME_COUNT :: 1

minigame_info :: proc(index: int) -> (host.Minigame_Info, bool) {
	switch index {
	case 0:
		return arena.info(), true
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
