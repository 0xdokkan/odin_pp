package render

import rl "vendor:raylib"
import game "../game"

// NIDO DI RAGNI's spiderlings on the board (docs/piano-ia.md, Fase 9), provisional until its Fase 10: little dark
// bodies running between the cells, drawn from the room as the arrows in flight are (game/spider_nest.odin). Only on the
// cells the player sees.

draw_spiderlings :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.player == nil || room.phase != .Combat { return }
	swarm := &room.player.tactical.spiders
	for spider in swarm.items[:swarm.count] {
		cell := spider.position
		if !tactical_render_visible(renderer, cell) { continue }
		t := clamp(spider.travelled, 0, 1)
		x := f32(spider.from.x)+(f32(cell.x)-f32(spider.from.x))*t+0.5
		z := f32(spider.from.y)+(f32(cell.y)-f32(spider.from.y))*t+0.5
		ground := 0.09+cell_overlay_ground(cell)
		rl.DrawCube({x, ground, z}, 0.16, 0.1, 0.16, {14, 12, 18, 255})
		rl.DrawCube({x, ground+0.02, z}, 0.28, 0.02, 0.05, {14, 12, 18, 255})
		rl.DrawCube({x, ground+0.02, z}, 0.05, 0.02, 0.28, {14, 12, 18, 255})
	}
}
