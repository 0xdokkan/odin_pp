package activities

import host "../engine/host"
import arena "../minigames/arena"
import fps "../minigames/fps"
import platform2d "../minigames/platform2d"
import platform3d "../minigames/platform3d"
import puzzle "../minigames/puzzle"

// Minigames offered by the menu, in display order. A run opens only the
// ring, from a square of Tesla coils.
MINIGAME_COUNT :: 6

minigame_info :: proc(index: int) -> (host.Minigame_Info, bool) {
	switch index {
	case 0:
		return platform2d.info(), true
	case 1:
		return platform3d.info(), true
	case 2:
		return arena.info(), true
	case 3:
		return fps.info(), true
	case 4:
		return puzzle.info(), true
	case 5:
		return ring_minigame_info(), true
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

// Captures exercise the real simulation without accepting stray live mouse
// input (especially important when the FPS has captured the desktop cursor).
minigame_capture_scene :: proc(index: int, config: host.Minigame_Config) -> host.Scene {
	switch index {
	case 0: return platform2d.create_autoplay(config)
	case 1: return platform3d.create_autoplay(config)
	case 2: return arena.create_autoplay(config)
	case 3: return fps.create_autoplay(config)
	case 4:
		scene := puzzle.create(config)
		puzzle.autoplay(&scene,2)
		return scene
	case 5:
		scene := ring_minigame_create(config)
		g := cast(^Ring_Minigame)host.shell_of(&scene).hooks.data
		g.demo=true
		return scene
	}
	return {}
}
