package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import level "../level"

// WHAT THE RENDERERS KNOW OF THE STRUCTURES THIS FRAME (Fase 6 of docs/piano-griglia.md):
// for each building of the map, how whole its envelope (walls and roof) is drawn, whether
// its roof shows, and which one the robot is inside. The target comes from the pure
// game.structure_visibility; the opacity shown eases toward it in about a fifth of a
// second, so a fight (the robot going cell by cell) does not make a building flicker.

Structure_Views :: struct {
	geometry_id: u64,
	count:       int,
	opacity:     [level.MAX_STRUCTURES_PER_LEVEL]f32,
	roof:        [level.MAX_STRUCTURES_PER_LEVEL]bool,
	stage:       [level.MAX_STRUCTURES_PER_LEVEL]game.Structure_Stage,
	// The structure the robot is inside, or -1.
	inside:      int,
	ready:       bool,
}

// (The level the views were last computed for, so the dimming can find the footprint it applies to.)

// How many seconds the opacity takes to settle (a time constant: five of them is complete).
STRUCTURE_FADE_SECONDS :: f32(0.07)

// Once per frame, before the board is drawn.
@(private)
update_structure_views :: proc(renderer: ^Renderer, room: ^game.Room) {
	views := &renderer.tactical.structures
	views.inside = -1
	renderer.tactical.structure_room_data = nil
	if room == nil || room.level_data == nil { views.count = 0; return }
	data := room.level_data
	renderer.tactical.structure_room_data = data
	count := min(len(data.structures), level.MAX_STRUCTURES_PER_LEVEL)
	snap := !views.ready || views.geometry_id != data.geometry_id || views.count != count
	views.ready, views.geometry_id, views.count = true, data.geometry_id, count
	if count == 0 { return }
	at, _ := living_card_position(renderer, game.PLAYER_ENTITY, .Player, renderer.tactical.snapshot.player.position)
	robot := [2]f32{at.x+0.5, at.y+0.5}
	dt := expedition_frame_dt(renderer) if renderer.tactical.expedition else clamp(rl.GetFrameTime(), 0, 0.1)
	ease := 1-math.exp(-dt/STRUCTURE_FADE_SECONDS)
	for i in 0..<count {
		target := game.structure_visibility(data, i, robot)
		if snap { views.opacity[i] = target.opacity } else { views.opacity[i] += (target.opacity-views.opacity[i])*ease }
		views.roof[i], views.stage[i] = target.roof, target.stage
		if target.inside { views.inside = i }
	}
}

// The building's envelope is drawn in the sorted pass (it is not whole), not with the opaque board.
@(private)
structure_envelope_pending :: proc(renderer: ^Renderer, data: ^level.Level, index: int) -> bool {
	views := &renderer.tactical.structures
	if index < 0 || index >= views.count || !level.structure_is_building(data.structures[index].id) { return false }
	return views.opacity[index] < 0.995
}

// A building's opacity (1 for anything else).
@(private)
structure_opacity :: proc(renderer: ^Renderer, data: ^level.Level, index: int) -> f32 {
	views := &renderer.tactical.structures
	if index < 0 || index >= views.count || !level.structure_is_building(data.structures[index].id) { return 1 }
	return views.opacity[index]
}

@(private)
structure_color_alpha :: proc(color: rl.Color, opacity: f32) -> rl.Color {
	return {color.r, color.g, color.b, u8(clamp(f32(color.a)*opacity, 0, 255))}
}

// A tint for each structure (the walls' body), set against the lab's blue stone.
@(private)
structure_tint :: proc(id: level.Structure_Id) -> rl.Color {
	switch id {
	case .Cottage: return {58, 82, 112, 255}
	case .Hut: return {86, 74, 62, 255}
	case .Temple: return {92, 86, 124, 255}
	case .Cart: return {96, 70, 48, 255}
	case .Fountain: return {52, 98, 120, 255}
	case .Statue: return {88, 92, 104, 255}
	case .Machine: return {70, 78, 70, 255}
	case .Ruin: return {74, 68, 82, 255}
	case .Pen: return {96, 80, 54, 255}
	case .Count: return RESIN_WALL
	}
	return RESIN_WALL
}
