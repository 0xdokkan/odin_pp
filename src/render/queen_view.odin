package render

import "core:math"
import rl "vendor:raylib"
import game "../game"

// REGINA on the board (game/queen.odin, docs/piano-ia.md, Fase 12): a chess piece of ivory and dark gold in the resin of the
// other objects, turned on a lathe in stacked tiers, her crown in eight points; a ring of ticks at her foot for the seconds
// left. She slides down her line leaving a trail of gold on the cells she crosses; on her blow she leans into her foe as a
// piece that captures; at the end she topples and is gone. Ivory and gold, far from the IA's cyan, the red and orange of
// the threats and the green of the foes' moves.

QUEEN_IVORY :: rl.Color{226, 216, 190, 255}
QUEEN_IVORY_SHADE :: rl.Color{170, 154, 124, 255}
QUEEN_GOLD :: rl.Color{178, 132, 48, 255}
QUEEN_GOLD_LIGHT :: rl.Color{236, 192, 96, 255}
// The part of her run's cue she takes to run.
QUEEN_RUN_PART :: f32(0.35)
// How far her head goes at the height of her lean, along the way to her foe, in cells a cell of her height.
QUEEN_LEAN :: f32(0.42)

@(private = "file")
Queen_Tier :: struct { y, height, width: f32, color: rl.Color }

// Her turned profile, from the floor.
@(private = "file")
QUEEN_TIERS := [?]Queen_Tier{
	{0.00, 0.07, 0.58, QUEEN_IVORY_SHADE},
	{0.07, 0.05, 0.50, QUEEN_IVORY},
	{0.12, 0.04, 0.43, QUEEN_GOLD},
	{0.16, 0.08, 0.34, QUEEN_IVORY},
	{0.24, 0.09, 0.28, QUEEN_IVORY},
	{0.33, 0.10, 0.24, QUEEN_IVORY},
	{0.43, 0.10, 0.21, QUEEN_IVORY},
	{0.53, 0.08, 0.19, QUEEN_IVORY},
	{0.61, 0.04, 0.33, QUEEN_GOLD},
	{0.65, 0.03, 0.24, QUEEN_IVORY},
	{0.68, 0.04, 0.20, QUEEN_IVORY},
	{0.72, 0.04, 0.25, QUEEN_IVORY},
	{0.76, 0.05, 0.31, QUEEN_IVORY},
}

// How far along her run she is, `progress` into its cue: it takes the first part, as her blow lands when she arrives.
@(private)
queen_run_progress :: proc(progress: f32) -> f32 { return min(clamp(progress, 0, 1)/QUEEN_RUN_PART, 1) }

// How far she leans, 0 to 1, `progress` into her blow: into it fast, back slowly.
@(private)
queen_lean :: proc(progress: f32) -> f32 {
	p := clamp(progress, 0, 1)
	return p/0.25 if p < 0.25 else 1-(p-0.25)/0.75
}

// The piece, `lean` cells a cell of height along (lean_x, lean_z), and `fall` of the way to lying on the floor along it.
@(private = "file")
draw_queen_piece :: proc(renderer: ^Renderer, cx, cz, ground, lean_x, lean_z, fall: f32) {
	stand := 1-fall
	at :: proc(cx, cz, ground, lean_x, lean_z, fall, y: f32) -> rl.Vector3 {
		return {cx+lean_x*y, ground+y*(1-fall)+0.03*fall, cz+lean_z*y}
	}
	for tier in QUEEN_TIERS {
		p := at(cx, cz, ground, lean_x, lean_z, fall, tier.y+tier.height/2)
		height := tier.height*(stand+0.35*fall)
		width := tier.width*(1-0.15*fall)
		draw_resin_cube_v(renderer, p, {width, height, width}, tier.color)
	}
	// The crown: eight points, a gold bead on each, the orb in the middle.
	crown := at(cx, cz, ground, lean_x, lean_z, fall, 0.86)
	for point in 0..<8 {
		angle := f32(point)*math.PI/4
		x, z := math.cos(angle)*0.145, math.sin(angle)*0.145
		rl.DrawCube({crown.x+x, crown.y, crown.z+z}, 0.05, 0.1*(stand+0.4*fall), 0.05, QUEEN_IVORY)
		rl.DrawSphereEx({crown.x+x, crown.y+0.06*stand, crown.z+z}, 0.03, 5, 6, QUEEN_GOLD_LIGHT)
	}
	orb := at(cx, cz, ground, lean_x, lean_z, fall, 0.96)
	rl.DrawSphereEx(orb, 0.06, 6, 8, QUEEN_GOLD_LIGHT)
}

@(private)
draw_queen_object :: proc(renderer: ^Renderer, object: Presentation_Grid_Object, bounds: rl.BoundingBox) {
	cx, cz := (bounds.min.x+bounds.max.x)*0.5, (bounds.min.z+bounds.max.z)*0.5
	ground := bounds.min.y
	lean_x, lean_z := f32(0), f32(0)
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		// The run: from the cell she left, quickly.
		if cue.kind == .Queen_Ran && cue.event.target == object.entity {
			left := 1-queen_run_progress(presentation_cue_progress(cue))
			cx += (f32(cue.event.from_position.x)-f32(cue.event.to_position.x))*left
			cz += (f32(cue.event.from_position.y)-f32(cue.event.to_position.y))*left
		}
		// The blow: she leans into her foe, as a piece that captures.
		if cue.kind == .Queen_Struck && cue.event.source == object.entity {
			lean := queen_lean(presentation_cue_progress(cue))*QUEEN_LEAN
			lean_x = lean*f32(sign_of(cue.event.to_position.x-cue.event.from_position.x))
			lean_z = lean*f32(sign_of(cue.event.to_position.y-cue.event.from_position.y))
		}
	}
	draw_queen_piece(renderer, cx, cz, ground, lean_x, lean_z, 0)
	on := GOTHIC_RED if object.life <= 3 else QUEEN_GOLD_LIGHT
	draw_seconds_ring(cx, cz, ground, 0.4, object.life, game.QUEEN_SECONDS, on)
}

// Whether she is toppling on the board now.
queen_toppling :: proc(renderer: ^Renderer) -> bool {
	for offset in 0..<renderer_active_cue_count(renderer) {
		if cue, found := renderer_active_cue_at(renderer, offset); found && cue.started && cue.kind == .Queen_Closed { return true }
	}
	return false
}

@(private = "file")
sign_of :: proc(v: int) -> int { return 1 if v > 0 else (-1 if v < 0 else 0) }

// Her run's trail, her blow's gleam on the foe, her fall.
@(private)
draw_queen_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	from, to := cue.event.from_position, cue.event.to_position
	#partial switch cue.kind {
	case .Queen_Ran:
		dx, dy := sign_of(to.x-from.x), sign_of(to.y-from.y)
		cells := max(abs(to.x-from.x), abs(to.y-from.y))
		for k in 0..=cells {
			// Each cell lights as she passes; they all go out with the cue.
			if queen_run_progress(p)*f32(cells+1) < f32(k) { continue }
			fade := 1-p
			x, z := f32(from.x+dx*k)+0.5, f32(from.y+dy*k)+0.5
			ground := cell_overlay_ground({x = from.x+dx*k, y = from.y+dy*k, layer = from.layer})+0.02
			rl.DrawCube({x, ground, z}, 0.62, 0.012, 0.62, color_with_opacity(QUEEN_GOLD, 0.65*fade))
			rl.DrawCube({x, ground+0.008, z}, 0.3, 0.012, 0.3, color_with_opacity(QUEEN_GOLD_LIGHT, 0.85*fade))
		}
	case .Queen_Struck:
		if !tactical_render_visible(renderer, to) { return }
		cx, cz, ground := f32(to.x)+0.5, f32(to.y)+0.5, cell_overlay_ground(to)
		rl.BeginBlendMode(.ADDITIVE)
		marley_glow(cx, ground+0.55, cz, 0.3+0.3*p, QUEEN_GOLD_LIGHT, 0.85*(1-p))
		rl.EndBlendMode()
		for spark in 0..<8 {
			angle := f32(spark)*math.PI/4
			reach := 0.15+0.4*p
			rl.DrawCube({cx+math.cos(angle)*reach, ground+0.55, cz+math.sin(angle)*reach}, 0.04, 0.04, 0.04, color_with_opacity(QUEEN_GOLD_LIGHT, 1-p))
		}
	case .Queen_Closed:
		// The piece topples: her object left with the world's beat.
		if !tactical_render_visible(renderer, to) { return }
		fall := p*p
		draw_queen_piece(renderer, f32(to.x)+0.5, f32(to.y)+0.5, cell_overlay_ground(to)+0.03, fall*0.7, fall*0.25, fall)
	}
}
