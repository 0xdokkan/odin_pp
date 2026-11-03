package render

import "core:math"
import rl "vendor:raylib"
import grid "../engine/grid"
import game "../game"

// NIDO DI RAGNI on the board (game/spider_nest.odin, docs/piano-ia.md, Fase 10). The nest: a dome of white silk in the
// resin of the other objects, its eggs showing through, its threads pulled tight to the floor, a ring of ticks round it
// for the seconds left; every blow tears it a little more (its tears are the object's `radius`); at no seconds it sags
// and goes. The spiderlings: small, dark, eight legs in jerks, drawn from the room as the arrows in flight are, only on
// the cells the player sees. A small flash on the bite, shreds of silk on a blow.

NEST_SILK :: rl.Color{214, 209, 222, 255}
NEST_SILK_SHADE :: rl.Color{146, 140, 166, 255}
NEST_EGG :: rl.Color{238, 214, 158, 255}
NEST_TEAR :: rl.Color{38, 26, 48, 255}
SPIDER_BODY :: rl.Color{30, 22, 40, 255}
SPIDER_LEG :: rl.Color{58, 48, 72, 255}
SPIDER_MARK :: rl.Color{226, 70, 96, 255}
// The tears that show: past them the dome is in rags already.
NEST_TEARS_SHOWN :: 6
// The steps of a spiderling's legs in a second.
SPIDER_LEG_STEPS :: f32(14)

// The dome's tiers, its width at the floor and its height.
@(private = "file")
NEST_TIERS :: 7
@(private = "file")
NEST_WIDTH :: f32(0.78)
@(private = "file")
NEST_HEIGHT :: f32(0.42)

// The tears a nest shows after `blows` blows.
@(private)
nest_tears_shown :: proc(blows: i32) -> int { return clamp(int(blows), 0, NEST_TEARS_SHOWN) }

// Whether a nest is sagging on the board now.
nest_sagging :: proc(renderer: ^Renderer) -> bool {
	for offset in 0..<renderer_active_cue_count(renderer) {
		if cue, found := renderer_active_cue_at(renderer, offset); found && cue.started && cue.kind == .Spider_Nest_Closed { return true }
	}
	return false
}

// The jerk of the legs at `age`: 0 or 1, the two sets of legs in turn.
@(private)
spider_leg_jerk :: proc(age: f32) -> int { return int(age*SPIDER_LEG_STEPS)%2 }

// The dome of silk, `sag` of its height.
@(private = "file")
draw_nest_dome :: proc(renderer: ^Renderer, cx, cz, ground, sag: f32) {
	height := NEST_HEIGHT/NEST_TIERS*sag
	for index in 0..<NEST_TIERS {
		up := (f32(index)+0.5)/NEST_TIERS
		width := NEST_WIDTH*math.sqrt(1-up*up)
		color := rl.ColorLerp(NEST_SILK_SHADE, NEST_SILK, up)
		draw_resin_cube_v(renderer, {cx, ground+height*(f32(index)+0.5), cz}, {width, height, width}, color)
	}
}

@(private)
draw_spider_nest :: proc(renderer: ^Renderer, object: Presentation_Grid_Object, bounds: rl.BoundingBox) {
	cx, cz := (bounds.min.x+bounds.max.x)*0.5, (bounds.min.z+bounds.max.z)*0.5
	ground := bounds.min.y
	sag := f32(1)
	if closing, closed := arsenal_cue_progress(renderer, .Spider_Nest_Closed, object.entity); closed { sag = 1-0.9*closing }
	// A blow shakes it; between blows it breathes, something moving under the silk.
	if struck, hit := arsenal_cue_progress(renderer, .Spider_Nest_Struck, object.entity); hit {
		cx += 0.05*(1-struck)*math.sin(struck*40)
	}
	breath := 1+0.02*math.sin(f32(tactical_world_time(renderer))*3.4)

	// The threads, pulled tight from the dome to the floor.
	top := ground+0.3*sag
	for corner in 0..<6 {
		angle := f32(corner)*math.PI/3+0.4
		reach := f32(0.62)
		rl.DrawLine3D({cx+math.cos(angle)*0.2, top, cz+math.sin(angle)*0.2}, {cx+math.cos(angle)*reach, ground+0.02, cz+math.sin(angle)*reach}, NEST_SILK)
	}

	// The dome.
	draw_nest_dome(renderer, cx, cz, ground, sag*breath)
	// The eggs, through the silk of the second tier.
	eggs := [5][2]f32{{-0.2, 0.34}, {0.12, 0.34}, {0.33, 0.1}, {0.34, -0.16}, {-0.05, 0.34}}
	for egg, index in eggs {
		rl.DrawSphereEx({cx+egg.x, ground+0.2*sag+f32(index%2)*0.04, cz+egg.y}, 0.05, 6, 8, NEST_EGG)
	}
	// Its tears, dark gashes on the sides the camera sees.
	for tear in 0..<nest_tears_shown(object.radius) {
		seed := gothic_hash(tear, 17)
		along := f32(seed%70)/100-0.35
		high := ground+(0.1+f32(seed/70%22)/100)*sag
		if tear%2 == 0 {
			rl.DrawCube({cx+along*0.8, high, cz+0.385-(high-ground)*0.1}, 0.17, 0.05, 0.02, NEST_TEAR)
		} else {
			rl.DrawCube({cx+0.385-(high-ground)*0.1, high, cz+along*0.8}, 0.02, 0.05, 0.17, NEST_TEAR)
		}
	}

	on := GOTHIC_RED if object.life <= 3 else rl.Color{196, 150, 255, 255}
	draw_seconds_ring(cx, cz, ground, 0.47, object.life, game.SPIDER_NEST_SECONDS, on)
}

// A ring of ticks on the floor round a thing that lasts: one a second of its `total`, lit while it is left.
@(private)
draw_seconds_ring :: proc(cx, cz, ground, radius: f32, life, total: i32, on: rl.Color) {
	lit := int(clamp(life, 0, total))
	for tick in 0..<int(total) {
		angle := f32(tick)/f32(total)*2*math.PI-math.PI/2
		color := on if tick < lit else rl.Color{52, 44, 68, 255}
		rl.DrawCube({cx+math.cos(angle)*radius, ground+0.012, cz+math.sin(angle)*radius}, 0.05, 0.016, 0.05, color)
	}
}

// A thin bar through `centre`, `length` along `way`.
@(private = "file")
spider_bar :: proc(centre, way: rl.Vector3, length, thick: f32, color: rl.Color) {
	rl.DrawCube(centre, thick+abs(way.x)*length, thick, thick+abs(way.z)*length, color)
}

// One spiderling at (x, z), on the floor `ground`, going along `way` (a step of a cell, or none).
@(private = "file")
draw_spiderling :: proc(x, z, ground: f32, way: grid.Position, age: f32) {
	along := rl.Vector3{f32(way.x), 0, f32(way.y)}
	if way.x == 0 && way.y == 0 { along = {1, 0, 0} }
	across := rl.Vector3{along.z, 0, along.x}
	jerk := spider_leg_jerk(age)
	body := rl.Vector3{x, ground+0.09+0.012*f32(jerk), z}
	// A pale ring of silk on the floor under it: dark on a dark floor it would be lost.
	rl.BeginBlendMode(.ALPHA)
	marley_glow(x, ground+0.015, z, 0.2, NEST_SILK, 0.34)
	rl.EndBlendMode()
	// Eight legs, four a side, each out from the body and down to the floor; the two sets step in turn.
	for k in 0..<4 {
		offset := -0.075+f32(k)*0.05
		for side in ([2]f32{-1, 1}) {
			lifted := (k+int(side+1)/2+jerk)%2
			reach := along*(offset+f32(lifted)*0.02)
			knee := body+reach+across*side*0.075+rl.Vector3{0, 0.022*f32(1-lifted), 0}
			foot := body+reach*1.5+across*side*0.14-rl.Vector3{0, 0.07-0.03*f32(lifted), 0}
			spider_bar(knee, across, 0.1, 0.018, SPIDER_LEG)
			spider_bar(foot, across, 0.05, 0.016, SPIDER_LEG)
			spider_bar((knee+foot)*0.5+across*side*0.02, {}, 0, 0.022, SPIDER_LEG)
		}
	}
	// The abdomen with its red mark, the head in front.
	rl.DrawCube(body-along*0.05, 0.13, 0.095, 0.13, SPIDER_BODY)
	rl.DrawCube(body-along*0.05+rl.Vector3{0, 0.05, 0}, 0.055, 0.008, 0.055, SPIDER_MARK)
	rl.DrawCube(body+along*0.07-rl.Vector3{0, 0.012, 0}, 0.075, 0.07, 0.075, SPIDER_BODY)
}

draw_spiderlings :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.player == nil || room.phase != .Combat { return }
	swarm := &room.player.tactical.spiders
	for spider in swarm.items[:swarm.count] {
		cell := spider.position
		if !tactical_render_visible(renderer, cell) { continue }
		t := clamp(spider.travelled, 0, 1)
		x := f32(spider.from.x)+(f32(cell.x)-f32(spider.from.x))*t+0.5
		z := f32(spider.from.y)+(f32(cell.y)-f32(spider.from.y))*t+0.5
		way := grid.Position{x = cell.x-spider.from.x, y = cell.y-spider.from.y}
		draw_spiderling(x, z, cell_overlay_ground(cell), way, spider.age)
	}
}

// The cues of the nest on the board: the flash of a bite on the foe, the shreds of a blow, a spiderling's little puff,
// the nest's last rags.
@(private)
draw_spider_nest_cue :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	cell := cue.event.to_position
	if !tactical_render_visible(renderer, cell) { return }
	cx, cz, ground := f32(cell.x)+0.5, f32(cell.y)+0.5, cell_overlay_ground(cell)
	#partial switch cue.kind {
	case .Spider_Bite:
		rl.BeginBlendMode(.ADDITIVE)
		marley_glow(cx, ground+0.5, cz, 0.28+0.2*p, {255, 96, 120, 255}, 0.8*(1-p))
		rl.EndBlendMode()
		for piece in 0..<5 {
			angle := f32(piece)*1.26
			rl.DrawCube({cx+math.cos(angle)*0.3*p, ground+0.5+0.2*p, cz+math.sin(angle)*0.3*p}, 0.035, 0.035, 0.035, color_with_opacity(rl.Color{255, 230, 200, 255}, 1-p))
		}
	case .Spider_Nest_Struck, .Spider_Nest_Closed:
		// Its object goes with the world's beat: the cue lets it down the rest of the way.
		if cue.kind == .Spider_Nest_Closed { draw_nest_dome(renderer, cx, cz, ground+0.03, 1-0.9*p) }
		rags := 8 if cue.kind == .Spider_Nest_Struck else 14
		for piece in 0..<rags {
			seed := gothic_hash(piece, 23)
			angle := f32(seed%628)/100
			speed := 0.45+f32(seed/628%60)/100
			x := cx+math.cos(angle)*speed*p
			z := cz+math.sin(angle)*speed*p
			y := max(ground+0.03, ground+0.3+1.1*p-1.9*p*p)
			rl.DrawCube({x, y, z}, 0.07, 0.015, 0.05, color_with_opacity(NEST_SILK, 1-p*0.7))
		}
	case .Spider_Hatched:
		rl.BeginBlendMode(.ALPHA)
		marley_glow(cx, ground+0.04, cz, 0.3+0.35*p, NEST_SILK, 0.5*(1-p))
		rl.EndBlendMode()
	case .Spider_Died:
		rl.BeginBlendMode(.ALPHA)
		marley_glow(cx, ground+0.04, cz, 0.12+0.1*p, NEST_SILK, 0.4*(1-p))
		rl.EndBlendMode()
	}
}
