package main

import host "engine/host"

// Minigames offered by the menu and by run challenges, in display order.
MINIGAME_COUNT :: 0

minigame_info :: proc(index: int) -> (host.Minigame_Info, bool) {
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
