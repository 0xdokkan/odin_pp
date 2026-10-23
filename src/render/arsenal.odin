package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"
import tween "../engine/tween"
import gfx "../engine/gfx"

// CANNONE, BUCO NERO and DINOSAURO on the board (game/cannon.odin,
// black_hole.odin, dinosaur.odin).
//
//   - the cannon: a steel stand and a barrel along its way (brass; a red neon
//     emitter for the laser), that kicks back on every world beat; a shot is a
//     paper cannonball cut out like the board's props (flying to the first foe
//     with smoke puffs behind it) or a beam of red light along the whole line;
//     at its end it falls apart in pieces;
//   - the hole: a black disc on the floor with the 3x3 it hurts and the 5x5 it
//     draws outlined, spiral arms turning round it, a dark sphere floating over
//     it and motes spiralling in; a beat sends a ring across the pull;
//   - the ride: the dinosaur's paper print under the player's card, the card
//     lifted to its saddle, walking in step with the player; a Giganotosauro's
//     stomp sends a shockwave across the four cells round him.

ARSENAL_BALL_SIZE :: 12
// How tall the dinosaurs' 40-pixel canvas stands in the world.
DINO_WORLD_HEIGHT :: f32(1.9)
DINO_MARGIN :: 3
DINO_KINDS :: 4
// The row of the canvas the dinosaur's feet end on (dino_art.odin).
DINO_FEET_ROWS :: 39
HOLE_SLOTS :: 4
ARSENAL_MOUNT_SECONDS :: f32(0.35)
// The dinosaur's own attack: its lunge, in seconds.
DINO_ATTACK_SECONDS :: f64(0.46)

CANNON_STEEL :: rl.Color{62, 66, 78, 255}
CANNON_STEEL_DARK :: rl.Color{34, 36, 46, 255}
CANNON_BRASS :: rl.Color{206, 156, 70, 255}
CANNON_NEON :: rl.Color{255, 64, 64, 255}
HOLE_VIOLET :: rl.Color{150, 92, 255, 255}
HOLE_EMBER :: rl.Color{255, 120, 48, 255}
HOLE_VOID :: rl.Color{4, 2, 10, 255}

DINO_AURA := [DINO_KINDS]rl.Color{
	{124, 220, 96, 255},
	{255, 150, 64, 255},
	{80, 220, 210, 255},
	{255, 80, 64, 255},
}

Arsenal_View :: struct {
	// The prints, made the first time they are drawn, cut from paper: the ball,
	// a puff of smoke, the dinosaurs (kind*2 + frame).
	ball, puff: rl.Texture2D,
	dinos: [DINO_KINDS*DINO_ART_FRAMES]rl.Texture2D,
	// How far the player is up on his dinosaur, 0 (on the floor) to 1 (seated),
	// and which one it is (kept while he climbs down).
	mount: f32,
	kind: game.Dino_Kind,
	last_time: f64,
	// The walk: seconds of stride, seconds the player is still counted as
	// moving, where he was and the side he faces.
	stride, moving: f32,
	last_at: view.Vec2,
	faces_right: bool,
	// The dinosaur's attack (the player's card never swings while he rides): when
	// it began (the player's clock) and the way it goes, in cells.
	attack_started: f64,
	attack_dir: view.Vec2,
	// When each hole was first seen (its opening).
	hole_born: [HOLE_SLOTS]struct{entity: game.Entity_Ref, born: f64},
}

@(private)
destroy_arsenal_view :: proc(renderer: ^Renderer) {
	a := &renderer.tactical.arsenal
	if a.ball.id != 0 { rl.UnloadTexture(a.ball) }
	if a.puff.id != 0 { rl.UnloadTexture(a.puff) }
	for texture in a.dinos { if texture.id != 0 { rl.UnloadTexture(texture) } }
	a^ = {}
}

// --------------------------------------------------------------------------
// Following the room.

// Once per frame, before the camera: the ride's climb and the walk, on the
// world's clock (still while the world is held).
@(private)
update_tactical_arsenal :: proc(renderer: ^Renderer, room: ^game.Room) {
	a := &renderer.tactical.arsenal
	snapshot := renderer.tactical.snapshot
	if snapshot == nil || room == nil { return }
	now := tactical_world_time(renderer)
	dt := f32(clamp(now-a.last_time, 0, 0.1))
	a.last_time = now
	ride := snapshot.ride
	if ride.active {
		if a.mount <= 0 { a.last_at, a.stride, a.moving = snapshot.player.position, 0, 0 }
		a.kind = ride.kind
		a.mount = min(f32(1), a.mount+dt/ARSENAL_MOUNT_SECONDS)
	} else {
		a.mount = max(f32(0), a.mount-dt/(ARSENAL_MOUNT_SECONDS*0.8))
	}
	if a.mount <= 0 { return }
	// Where the rider stands, without the lunge of an attack: the walk is the dinosaur's feet.
	at, _ := living_card_position(renderer, game.PLAYER_ENTITY, .Player, snapshot.player.position)
	off := tactical_ride_offset(renderer)
	at -= off
	step := at-a.last_at
	// It faces as the player's card does (his living card turns toward where he
	// goes or means to go, a bump included).
	if actor := living_find(renderer, game.PLAYER_ENTITY, gfx.Flipbook_Character.Pilgrim); actor != nil { a.faces_right = !actor.facing_left }
	if abs(step.x)+abs(step.y) > 0.0005 { a.moving = 0.22 } else { a.moving = max(f32(0), a.moving-dt) }
	if a.moving > 0 { a.stride += dt }
	a.last_at = at
}

// The dinosaur's attack begins, toward `dir` (cells): a lunge with its head down.
// The player's card does not swing: this is the attack he rides (the living
// cards hand it here instead of starting the clip).
@(private)
arsenal_begin_attack :: proc(renderer: ^Renderer, dir: view.Vec2) {
	a := &renderer.tactical.arsenal
	now := renderer.sprite_assets.elapsed
	// One lunge per blow, whatever cues the blow makes.
	if a.attack_dir != {} && now-a.attack_started < 0.18 { return }
	length := math.sqrt(dir.x*dir.x+dir.y*dir.y)
	a.attack_dir = {0, -1} if length < 0.001 else dir/length
	a.attack_started = now
}

// How far into its attack the dinosaur is: 0..1, or false when it is not.
@(private = "file")
arsenal_attack_progress :: proc(renderer: ^Renderer) -> (p: f32, active: bool) {
	a := &renderer.tactical.arsenal
	if a.attack_dir == {} { return }
	p = f32((renderer.sprite_assets.elapsed-a.attack_started)/DINO_ATTACK_SECONDS)
	return p, p >= 0 && p < 1
}

// The lunge's shape: it draws back, strikes forward and returns.
@(private = "file")
arsenal_lunge :: proc(p: f32) -> f32 {
	if p < 0.3 { return -0.16*tween.smoothstep(p/0.3) }
	if p < 0.5 { return -0.16+0.76*tween.smoothstep((p-0.3)/0.2) }
	return 0.6*(1-tween.smoothstep((p-0.5)/0.5))
}

// How far the lunge has carried the dinosaur and the rider on its back (cells),
// added to the card place (living_card_position).
@(private)
tactical_ride_offset :: proc(renderer: ^Renderer) -> (offset: view.Vec2) {
	a := &renderer.tactical.arsenal
	if a.mount <= 0 { return }
	if p, active := arsenal_attack_progress(renderer); active { offset = a.attack_dir*(arsenal_lunge(p)*(1.2 if a.kind == .Giga else 1)) }
	return
}

// Where the dinosaur is in its walk: 0 or 1 (standing, it keeps the first).
@(private = "file")
arsenal_dino_frame :: proc(a: ^Arsenal_View) -> int {
	if a.moving <= 0 { return 0 }
	return int(a.stride/0.16)%DINO_ART_FRAMES
}

// How high the player's card is lifted by the saddle now (the Lazzo's lift
// also lifts what the card carries: tactical_lasso_lift).
@(private)
tactical_ride_lift :: proc(renderer: ^Renderer) -> f32 {
	if renderer == nil { return 0 }
	a := &renderer.tactical.arsenal
	if a.mount <= 0 { return 0 }
	kind := Dino_Art(a.kind)
	seat := DINO_ART_SEAT[kind]
	bob := DINO_ART_BOB[kind][arsenal_dino_frame(a)]
	unit := DINO_WORLD_HEIGHT/f32(DINO_ART_H)
	return f32(DINO_FEET_ROWS-1-seat.y+bob)*unit*tween.smoothstep(a.mount)
}

// The cue of `kind` about `entity` (as its target) that plays now, how far.
@(private = "file")
arsenal_cue_progress :: proc(renderer: ^Renderer, kind: Presentation_Cue_Kind, entity: game.Entity_Ref) -> (progress: f32, found: bool) {
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, present := renderer_active_cue_at(renderer, offset)
		if !present || !cue.started || cue.kind != kind || cue.event.target != entity { continue }
		return presentation_cue_progress(cue), true
	}
	return
}

// --------------------------------------------------------------------------
// The cannon, on its stand.

// The beat's kick: the barrel slides back and comes forward again.
@(private = "file")
cannon_recoil :: proc(renderer: ^Renderer) -> f32 {
	beat := f32(math.mod(tactical_world_time(renderer), 1))
	return 0.1*math.exp(-beat*9)
}

@(private)
draw_cannon_object :: proc(renderer: ^Renderer, object: Presentation_Grid_Object, centre: rl.Vector3) {
	falling, collapsing := arsenal_cue_progress(renderer, .Cannon_Broken, object.entity)
	collapse := falling if collapsing else 0
	base := centre.y-0.43-collapse*0.18
	cx, cz := centre.x, centre.z
	// The platform and its four legs.
	draw_resin_cube(renderer, {cx, base+0.05, cz}, 0.72, 0.1, 0.72, CANNON_STEEL_DARK)
	for sx in ([2]f32{-1, 1}) {
		for sz in ([2]f32{-1, 1}) {
			draw_resin_cube(renderer, {cx+sx*0.25, base+0.22, cz+sz*0.25}, 0.11, 0.3, 0.11, CANNON_STEEL)
		}
	}
	// The cradle, and the barrel along its way kicked back by the beat.
	draw_resin_cube(renderer, {cx, base+0.42, cz}, 0.42, 0.2, 0.42, CANNON_STEEL)
	step := game.direction_offset(object.facing)
	recoil := cannon_recoil(renderer)*(1-collapse)
	reach := f32(0.3)-recoil
	barrel := rl.Color{CANNON_NEON.r, 96, 96, 255} if object.laser else CANNON_BRASS
	across := f32(0.2)
	size := rl.Vector3{0.66 if step.x != 0 else across, across, 0.66 if step.y != 0 else across}
	muzzle_y := base+0.58
	draw_resin_cube_v(renderer, {cx+f32(step.x)*reach, muzzle_y-collapse*0.1, cz+f32(step.y)*reach}, size, barrel)
	// The muzzle's ring and, behind it, the breech.
	ring := rl.Vector3{0.28 if step.x != 0 else 0.3, 0.3, 0.28 if step.y != 0 else 0.3}
	ring.x, ring.z = (0.1 if step.x != 0 else 0.3), (0.1 if step.y != 0 else 0.3)
	draw_resin_cube_v(renderer, {cx+f32(step.x)*(reach+0.31), muzzle_y-collapse*0.1, cz+f32(step.y)*(reach+0.31)}, ring, CANNON_STEEL_DARK)
	draw_resin_cube_v(renderer, {cx-f32(step.x)*0.16, muzzle_y-collapse*0.1, cz-f32(step.y)*0.16}, {0.3, 0.3, 0.3}, CANNON_STEEL)
	if object.laser {
		// A neon core along the barrel, humming.
		hum := 0.55+0.45*math.sin(f32(tactical_world_time(renderer))*14)
		core := rl.Color{255, u8(90+90*hum), u8(90+60*hum), 255}
		rl.DrawCube({cx+f32(step.x)*(reach+0.1), muzzle_y+0.115, cz+f32(step.y)*(reach+0.1)},
			0.5 if step.x != 0 else 0.05, 0.04, 0.5 if step.y != 0 else 0.05, core)
	}
	// A lamp on the cradle: green while it has time, red at the end.
	left := f32(object.life)/f32(max(object.max_life, 1))
	lamp := rl.Color{u8(60+190*(1-left)), u8(60+190*left), 70, 255}
	rl.DrawCube({cx, base+0.545, cz}, 0.1, 0.05, 0.1, lamp)
}

// The pieces of a cannon falling apart, and a puff over them.
@(private = "file")
draw_cannon_debris :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	at := rl.Vector3{f32(cue.event.from_position.x)+0.5, 0.45, f32(cue.event.from_position.y)+0.5}
	for piece in 0..<9 {
		seed := gothic_hash(piece, 7)
		angle := f32(seed%628)/100
		speed := 0.5+f32(seed/628%100)/100
		x := at.x+math.cos(angle)*speed*p*0.9
		z := at.z+math.sin(angle)*speed*p*0.9
		y := max(f32(0.05), at.y+1.4*p-2.6*p*p)
		size := 0.08+f32(seed/62800%5)*0.025
		colour := CANNON_BRASS if piece%3 == 0 else CANNON_STEEL
		rl.DrawCube({x, y, z}, size, size, size, color_with_opacity(colour, 1-p*0.6))
	}
	a := &renderer.tactical.arsenal
	if a.puff.id == 0 { a.puff = marley_puff_texture() }
	for puff in 0..<4 {
		rise := p*(0.6+0.2*f32(puff))
		marley_draw_print(renderer, a.puff, at+{(f32(puff)-1.5)*0.18, 0.1+rise, (f32(puff%2)-0.5)*0.2}, 0.5*(1-p*0.4), f32(puff)*50+p*80, {255, 255, 255, u8(210*(1-p))})
	}
}

// --------------------------------------------------------------------------
// A shot.

// The muzzle's point for a cannon at `cell` aimed `way`.
@(private = "file")
cannon_muzzle :: proc(cell: grid.Position, way: game.Move_Direction) -> rl.Vector3 {
	step := game.direction_offset(way)
	return {f32(cell.x)+0.5+f32(step.x)*0.62, 0.62, f32(cell.y)+0.5+f32(step.y)*0.62}
}

// The ball in flight (a paper print spinning, smoke behind it), the muzzle's
// flash and smoke, the strike's spark; or the beam.
@(private = "file")
draw_cannon_shot :: proc(renderer: ^Renderer, room: ^game.Room, cue: ^Presentation_Cue) {
	a := &renderer.tactical.arsenal
	event := cue.event
	p := presentation_cue_progress(cue)
	laser := event.duration == 1
	// Which way it was aimed: along the line from the cannon to its last cell.
	delta := grid.Position{event.to_position.x-event.from_position.x, event.to_position.y-event.from_position.y}
	way := game.Move_Direction.East
	switch {
	case delta.y < 0: way = .North
	case delta.y > 0: way = .South
	case delta.x < 0: way = .West
	case delta.x > 0: way = .East
	case:
		// A blocked cannon (a wall right in front): aimed by its object.
		if object, found := presentation_grid_object_in_view(&renderer.timeline.view, event.source); found { way = object.facing }
	}
	muzzle := cannon_muzzle(event.from_position, way)
	target := rl.Vector3{f32(event.to_position.x)+0.5, 0.62, f32(event.to_position.y)+0.5}
	if delta.x == 0 && delta.y == 0 { target = muzzle }
	t := tactical_world_time(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	// The flash and the smoke at the muzzle.
	if p < 0.4 {
		k := 1-p/0.4
		rl.BeginBlendMode(.ADDITIVE)
		marley_glow(muzzle.x, muzzle.y, muzzle.z, 0.5*(0.5+k), CANNON_NEON if laser else rl.Color{255, 190, 90, 255}, 0.9*k)
		rl.DrawSphereEx(muzzle, 0.16*k+0.04, 6, 8, color_with_opacity(rl.Color{255, 236, 190, 255}, 0.9*k))
		rl.EndBlendMode()
	}
	if a.puff.id == 0 { a.puff = marley_puff_texture() }
	for puff in 0..<3 {
		age := p-f32(puff)*0.08
		if age <= 0 || age > 0.9 { continue }
		marley_draw_print(renderer, a.puff, muzzle+{0, 0.06+age*0.7, 0}+{f32(puff-1)*0.1, 0, 0}, 0.34+age*0.3, f32(puff)*60+age*90, {255, 255, 255, u8(200*(1-age))})
	}
	if laser {
		draw_cannon_beam(renderer, muzzle, target, p)
		return
	}
	// The ball: it flies the line over the cue's first part, then it is gone
	// (or its strike is on the foe).
	flight := clamp(p/0.7, f32(0), f32(1))
	if a.ball.id == 0 { a.ball = arsenal_ball_texture() }
	if flight < 1 || event.target == game.SYSTEM_ENTITY {
		at := muzzle+(target-muzzle)*flight
		at.y += 0.05*math.sin(flight*math.PI)
		// A soft shadow under it on the floor.
		rl.BeginBlendMode(.ALPHA)
		marley_glow(at.x, 0.03, at.z, 0.16, {0, 0, 8, 255}, 0.5)
		rl.EndBlendMode()
		rlgl.DrawRenderBatchActive()
		for puff in 1..=4 {
			back := muzzle+(target-muzzle)*max(f32(0), flight-f32(puff)*0.05)
			marley_draw_print(renderer, a.puff, back+{0, 0.04, 0}, 0.2-0.03*f32(puff), f32(puff)*55+p*200, {255, 255, 255, u8(220*(1-f32(puff)/5))})
		}
		fade := f32(1) if flight < 1 else clamp(1-(p-0.7)/0.2, f32(0), f32(1))
		marley_draw_print(renderer, a.ball, at, 0.3*(1+0.06*math.sin(f32(t)*40)), p*700, {255, 255, 255, u8(255*fade)})
	}
	// The strike: a ring and sparks on the foe it reached.
	if event.target != game.SYSTEM_ENTITY && p > 0.68 {
		k := (p-0.68)/0.32
		cell_x, cell_z := f32(event.to_position.x)+0.5, f32(event.to_position.y)+0.5
		rl.BeginBlendMode(.ADDITIVE)
		marley_glow(cell_x, 0.04, cell_z, 0.3+0.5*k, rl.Color{255, 190, 90, 255}, 0.8*(1-k))
		for spark in 0..<6 {
			angle := f32(spark)*math.PI/3+f32(spark%2)*0.4
			reach := 0.15+0.4*k
			rl.DrawCube({cell_x+math.cos(angle)*reach, 0.62+0.2*math.sin(k*math.PI), cell_z+math.sin(angle)*reach}, 0.05, 0.05, 0.05, color_with_opacity(rl.Color{255, 220, 140, 255}, 1-k))
		}
		rl.EndBlendMode()
	}
}

// The laser's beam: a white-hot core in a red glow, wide at the flash and
// thinning out, along the whole line, with a flare at the muzzle and at the end
// and on every foe on it.
@(private = "file")
draw_cannon_beam :: proc(renderer: ^Renderer, from, to: rl.Vector3, p: f32) {
	eye := renderer.tactical.camera.position
	fade := (1-p)*(1-p)
	flicker := 0.85+0.15*math.sin(f32(tactical_world_time(renderer))*60)
	rl.BeginBlendMode(.ADDITIVE)
	marley_beam(eye, from, to, 0.2*flicker, 0.2*flicker, CANNON_NEON, 0.55*fade, 0.45*fade)
	marley_beam(eye, from, to, 0.11*flicker, 0.11*flicker, {255, 150, 120, 255}, 0.9*fade, 0.85*fade)
	marley_beam(eye, from, to, 0.04, 0.04, {255, 250, 240, 255}, fade, fade)
	marley_glow(from.x, from.y, from.z, 0.5, CANNON_NEON, 0.8*fade)
	marley_glow(to.x, 0.04, to.z, 0.55, CANNON_NEON, 0.8*fade)
	for enemy in renderer.tactical.snapshot.enemies[:renderer.tactical.snapshot.enemy_count] {
		if !enemy.visible { continue }
		// A foe on the beam's line (its cell between the muzzle and the end).
		on_x := abs(enemy.position.y+0.5-from.z) < 0.4 && (enemy.position.x+0.5-from.x)*(enemy.position.x+0.5-to.x) <= 0
		on_z := abs(enemy.position.x+0.5-from.x) < 0.4 && (enemy.position.y+0.5-from.z)*(enemy.position.y+0.5-to.z) <= 0
		if (on_x && abs(from.x-to.x) > 0.01) || (on_z && abs(from.z-to.z) > 0.01) {
			marley_glow(enemy.position.x+0.5, 0.05, enemy.position.y+0.5, 0.6, {255, 230, 210, 255}, 0.85*fade)
		}
	}
	rl.EndBlendMode()
}

@(private = "file")
arsenal_ball_texture :: proc() -> rl.Texture2D {
	pixels: [ARSENAL_BALL_SIZE*ARSENAL_BALL_SIZE]rl.Color
	for y in 0..<ARSENAL_BALL_SIZE {
		for x in 0..<ARSENAL_BALL_SIZE {
			dx, dy := f32(x)-5.5, f32(y)-5.5
			d := dx*dx+dy*dy
			if d > 5.2*5.2 { continue }
			shade := rl.Color{30, 32, 42, 255}
			if dx+dy > 2.6 && d > 3.4*3.4 { shade = rl.Color{14, 14, 22, 255} }
			pixels[y*ARSENAL_BALL_SIZE+x] = shade
		}
	}
	// A glint, and an ember on the rim from the powder.
	for point in ([?][2]int{{3, 3}, {4, 3}, {3, 4}}) { pixels[point.y*ARSENAL_BALL_SIZE+point.x] = rl.Color{190, 198, 220, 255} }
	for point in ([?][2]int{{9, 8}, {8, 9}}) { pixels[point.y*ARSENAL_BALL_SIZE+point.x] = rl.Color{255, 140, 50, 255} }
	return marley_paper_texture(pixels[:], ARSENAL_BALL_SIZE, ARSENAL_BALL_SIZE, 2, 1)
}

// --------------------------------------------------------------------------
// The hole.

@(private = "file")
hole_born :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f64 {
	a := &renderer.tactical.arsenal
	now := tactical_world_time(renderer)
	free_slot := -1
	for &slot, index in a.hole_born {
		if slot.entity == entity { return slot.born }
		if slot.entity.id == 0 && free_slot < 0 { free_slot = index }
	}
	// A hole no longer on the board frees its slot.
	if free_slot < 0 { free_slot = 0 }
	a.hole_born[free_slot] = {entity, now}
	return now
}

// A hole on the floor: the area it hurts (and the one it draws in) outlined
// and darkened, the disc, the arms.
@(private)
draw_arsenal_floor :: proc(renderer: ^Renderer, room: ^game.Room) {
	snapshot := renderer.tactical.snapshot
	if snapshot == nil { return }
	any_hole := false
	for object in snapshot.objects[:snapshot.object_count] {
		if object.kind == .Devouring_Hole && object.visible { any_hole = true; break }
	}
	if !any_hole { return }
	t := tactical_world_time(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling(); rlgl.EnableDepthMask() }
	for object in snapshot.objects[:snapshot.object_count] {
		if object.kind != .Devouring_Hole || !object.visible { continue }
		cell := grid.Position{int(object.position.x), int(object.position.y)}
		if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
		open := clamp(f32(t-hole_born(renderer, object.entity))/0.6, f32(0), f32(1))
		if closing, closed := arsenal_cue_progress(renderer, .Black_Hole_Closed, object.entity); closed { open = min(open, 1-closing) }
		draw_hole_floor(renderer, room, object, tween.smoothstep(open), t)
	}
}

@(private = "file")
draw_hole_floor :: proc(renderer: ^Renderer, room: ^game.Room, object: Presentation_Grid_Object, open: f32, t: f64) {
	cx, cz := object.position.x+0.5, object.position.y+0.5
	r := f32(object.radius)
	hurt, pull := r+0.5, r+1.5
	beat := f32(math.mod(t, 1))
	// The cells: the whole 5x5 a little darker, the 3x3 darker still; a bar of
	// violet along each of their edges.
	rl.BeginBlendMode(.ALPHA)
	for dy in -int(r)-1..=int(r)+1 {
		for dx in -int(r)-1..=int(r)+1 {
			cell := grid.Position{int(object.position.x)+dx, int(object.position.y)+dy}
			if !marley_cell_drawn(renderer, room, cell) { continue }
			floor := marley_floor_height(renderer, cell)
			inside := abs(dx) <= int(r) && abs(dy) <= int(r)
			shade := u8(150*open) if inside else u8(70*open)
			marley_square(f32(cell.x)+0.5, floor+0.012, f32(cell.y)+0.5, 0.5, {4, 2, 12, shade})
		}
	}
	rl.EndBlendMode()
	rl.BeginBlendMode(.ADDITIVE)
	pulse := 0.6+0.4*math.sin(f32(t)*3)
	marley_frame(cx, 0.045, cz, hurt*open, 0.05, HOLE_VIOLET)
	marley_frame(cx, 0.044, cz, pull*open, 0.03, rl.Color{HOLE_VIOLET.r, HOLE_VIOLET.g, HOLE_VIOLET.b, u8(110+50*pulse)})
	// A ring across the pull on every beat, going inward.
	ring := pull*(1-beat)*open
	marley_frame(cx, 0.046, cz, max(ring, 0.1), 0.03, rl.Color{200, 170, 255, u8(180*(1-beat)*open)})
	rl.EndBlendMode()
	// The disc.
	rl.BeginBlendMode(.ALPHA)
	disc := (0.95+0.12*math.sin(f32(t)*2.4))*open
	marley_glow(cx, 0.05, cz, disc*1.45, HOLE_VOID, 0.95)
	marley_glow(cx, 0.052, cz, disc*0.9, HOLE_VOID, 1)
	rl.EndBlendMode()
	// The arms: three spirals of lights turning inward, violet at their
	// start, orange where they plunge.
	rl.BeginBlendMode(.ADDITIVE)
	for arm in 0..<3 {
		for step in 0..<26 {
			k := f32(step)/26
			angle := f32(arm)*2*math.PI/3+f32(t)*2.4+k*5.2
			radius := (1.35-1.1*k)*open*(0.8+0.2*r)
			colour := rl.Color{u8(f32(HOLE_VIOLET.r)+(f32(HOLE_EMBER.r)-f32(HOLE_VIOLET.r))*k), u8(f32(HOLE_VIOLET.g)+(f32(HOLE_EMBER.g)-f32(HOLE_VIOLET.g))*k),
				u8(f32(HOLE_VIOLET.b)+(f32(HOLE_EMBER.b)-f32(HOLE_VIOLET.b))*k), 255}
			marley_square(cx+math.cos(angle)*radius, 0.054, cz+math.sin(angle)*radius, 0.035+0.03*(1-k), color_with_opacity(colour, 0.9*open))
		}
	}
	rl.EndBlendMode()
}

// The hole's dark sphere over the floor with a violet rim, and the motes that
// spiral in to it from the pull's edge.
@(private)
draw_arsenal_sky :: proc(renderer: ^Renderer, room: ^game.Room) {
	snapshot := renderer.tactical.snapshot
	if snapshot == nil { return }
	t := tactical_world_time(renderer)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	for object in snapshot.objects[:snapshot.object_count] {
		if object.kind != .Devouring_Hole || !object.visible { continue }
		cell := grid.Position{int(object.position.x), int(object.position.y)}
		if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
		open := clamp(f32(t-hole_born(renderer, object.entity))/0.6, f32(0), f32(1))
		if closing, closed := arsenal_cue_progress(renderer, .Black_Hole_Closed, object.entity); closed { open = min(open, 1-closing) }
		open = tween.smoothstep(open)
		cx, cz := object.position.x+0.5, object.position.y+0.5
		centre := rl.Vector3{cx, 0.5+0.06*math.sin(f32(t)*2.2), cz}
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawSphereEx(centre, 0.44*open, 10, 14, color_with_opacity(HOLE_VIOLET, 0.28))
		rl.DrawSphereEx(centre, 0.52*open, 10, 14, color_with_opacity(HOLE_EMBER, 0.12))
		// The motes spiralling inward.
		pull := f32(object.radius)+1.5
		for mote in 0..<16 {
			u := f32(math.mod(t*0.5+f64(mote)/16, 1))
			angle := f32(mote)*2.4+u*5
			radius := pull*(1-u)*open
			rl.DrawCube({cx+math.cos(angle)*radius, 0.1+0.5*u, cz+math.sin(angle)*radius}, 0.05, 0.05, 0.05, color_with_opacity(rl.Color{210, 180, 255, 255}, 0.8*(1-u*0.6)))
		}
		rl.EndBlendMode()
		rl.BeginBlendMode(.ALPHA)
		rl.DrawSphereEx(centre, 0.34*open, 12, 16, HOLE_VOID)
		rl.EndBlendMode()
	}
	// The cues of the arsenal that have their own drawing.
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		#partial switch cue.kind {
		case .Cannon_Fired: draw_cannon_shot(renderer, room, cue)
		case .Cannon_Broken: draw_cannon_debris(renderer, cue)
		case .Black_Hole_Swallowed: draw_hole_swallow(renderer, cue)
		case .Dino_Stomp: draw_dino_stomp(renderer, room, cue)
		case .Ride_Begun, .Ride_Ended: draw_dino_roar(renderer, cue)
		}
	}
}

// The foe the hole swallows: a streak where it spins and a flash at the end.
@(private = "file")
draw_hole_swallow :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	centre := rl.Vector3{f32(cue.event.to_position.x)+0.5, 0.3, f32(cue.event.to_position.y)+0.5}
	rl.BeginBlendMode(.ADDITIVE)
	marley_glow(centre.x, 0.06, centre.z, 0.4+0.5*p, HOLE_VIOLET, 0.6*p)
	if p > 0.8 {
		k := (p-0.8)/0.2
		rl.DrawSphereEx({centre.x, 0.5, centre.z}, 0.3*(1-k), 8, 10, color_with_opacity(rl.Color{240, 220, 255, 255}, 1-k))
	}
	rl.EndBlendMode()
}

// --------------------------------------------------------------------------
// The ride.

@(private = "file")
arsenal_dino_texture :: proc(a: ^Arsenal_View, kind: Dino_Art, frame: int) -> rl.Texture2D {
	index := int(kind)*DINO_ART_FRAMES+frame
	if a.dinos[index].id == 0 {
		pixels := dino_art_pixels(kind, frame)
		a.dinos[index] = marley_paper_texture(pixels[:], DINO_ART_W, DINO_ART_H, DINO_MARGIN, 2)
	}
	return a.dinos[index]
}

// The player's place in the sorted cards: right behind him.
@(private)
collect_dino_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	a := &renderer.tactical.arsenal
	snapshot := renderer.tactical.snapshot
	if a.mount <= 0 || !snapshot.player.visible || first_person_hides_player(renderer) { return }
	append(entries, Tactical_Alpha_Entry{kind = .Dino, entity = game.PLAYER_ENTITY, position = snapshot.player.position,
		opacity = snapshot.player.opacity})
}

// The dinosaur's paper print, mirrored to face the way the player walks,
// standing on the floor with its saddle where the player's card stands.
@(private)
draw_dino_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	a := &renderer.tactical.arsenal
	kind := Dino_Art(a.kind)
	frame := arsenal_dino_frame(a)
	texture := arsenal_dino_texture(a, kind, frame)
	if texture.id == 0 { return }
	at, _ := living_card_position(renderer, game.PLAYER_ENTITY, .Player, entry.position)
	unit := DINO_WORLD_HEIGHT/f32(DINO_ART_H)
	mount := tween.smoothstep(a.mount)
	t := tactical_world_time(renderer)
	// It drops in from above and settles; climbing down, it shrinks away.
	drop := (1-mount)*(1-mount)*1.1
	breath := 1+0.012*math.sin(f32(t)*5) if a.moving <= 0 else f32(1)
	size := rl.Vector2{f32(texture.width)*unit*mount*breath, f32(texture.height)*unit*mount*breath}
	right := flipbook_camera_right(renderer)
	seat := DINO_ART_SEAT[kind]
	// The print turns round as the player card does: it narrows, flips, widens.
	faces_right := a.faces_right
	turned := f32(1)
	if actor := living_find(renderer, game.PLAYER_ENTITY, gfx.Flipbook_Character.Pilgrim); actor != nil {
		faces_right = !actor.facing_left
		turn := (renderer.sprite_assets.elapsed-actor.turn_started)/LIVING_TURN_SECONDS
		if actor.turn_started >= 0 && turn < 1 {
			turned = max(f32(0.04), abs(f32(math.cos(turn*math.PI))))
			if turn < 0.5 { faces_right = !faces_right }
		}
	}
	sign := f32(1) if faces_right else f32(-1)
	// The attack: a head-down lunge (squashed as it strikes, the nose dipping);
	// a stomp (a Giganotosauro step, a crush) lands heavy.
	squash, tilt := f32(0), f32(0)
	if p, active := arsenal_attack_progress(renderer); active {
		strike := math.sin(clamp((p-0.25)/0.35, f32(0), f32(1))*math.PI)
		squash, tilt = 0.10*strike, 14*strike
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if found && cue.started && cue.kind == .Dino_Stomp { squash = max(squash, 0.14*math.sin(presentation_cue_progress(cue)*math.PI)) }
	}
	size.x *= (1+squash*0.8)*turned
	size.y *= 1-squash
	shift := f32(DINO_ART_W/2-seat.x)*unit*sign*mount
	feet := f32(DINO_FEET_ROWS+DINO_MARGIN)
	centre := rl.Vector3{at.x+0.5+right.x*shift, 0.05+(feet-f32(texture.height)*0.5)*unit*mount+drop, at.y+0.5+right.z*shift}
	aura := DINO_AURA[kind]
	// Its aura on the floor under it, and the paper's shadow.
	rlgl.DrawRenderBatchActive()
	rl.BeginBlendMode(.ADDITIVE)
	marley_glow(at.x+0.5, 0.052, at.y+0.5, 0.75*mount, aura, 0.35*mount)
	rl.EndBlendMode()
	rl.BeginBlendMode(.ALPHA)
	marley_glow(at.x+0.5, 0.05, at.y+0.5, 0.7*mount, {0, 0, 8, 255}, 0.4*mount)
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	source := rl.Rectangle{0, 0, f32(texture.width)*sign, f32(texture.height)}
	tint := color_with_opacity(rl.WHITE, entry.opacity)
	// Clockwise on the screen is the nose going down for a print that faces right.
	rl.DrawBillboardPro(renderer.tactical.camera, texture, source, centre, {0, 1, 0}, size, size*0.5, -tilt*sign, tint)
}

// A Giganotosauro's stomp: a shockwave out across the four cells round him,
// dust where each lands.
@(private = "file")
draw_dino_stomp :: proc(renderer: ^Renderer, room: ^game.Room, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	at := cue.event.from_position
	cx, cz := f32(at.x)+0.5, f32(at.y)+0.5
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	// A crush (the foe has a name): he has walked onto it; dust and a sharp ring.
	if cue.event.target != game.SYSTEM_ENTITY {
		a := &renderer.tactical.arsenal
		if a.puff.id == 0 { a.puff = marley_puff_texture() }
		rl.BeginBlendMode(.ADDITIVE)
		marley_glow(cx, 0.06, cz, 0.3+0.9*p, DINO_AURA[3], 0.9*(1-p))
		marley_frame(cx, 0.062, cz, 0.2+0.8*p, 0.05, color_with_opacity(DINO_AURA[3], 0.9*(1-p)))
		rl.EndBlendMode()
		rlgl.DrawRenderBatchActive()
		for puff in 0..<6 {
			angle := f32(puff)*math.PI/3+0.4
			reach := 0.2+0.55*p
			marley_draw_print(renderer, a.puff, {cx+math.cos(angle)*reach, 0.12+0.25*p, cz+math.sin(angle)*reach}, 0.28+0.18*p, f32(puff)*40+p*120, {255, 255, 255, u8(220*(1-p))})
		}
	}
	rl.BeginBlendMode(.ADDITIVE)
	marley_glow(cx, 0.06, cz, 0.4+1.3*p, DINO_AURA[3], 0.85*(1-p))
	for offset in ([4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
		cell := grid.Position{at.x+offset.x, at.y+offset.y}
		if !marley_cell_drawn(renderer, room, cell) { continue }
		marley_square(f32(cell.x)+0.5, 0.058, f32(cell.y)+0.5, 0.46, color_with_opacity(DINO_AURA[3], 0.5*(1-p)))
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// The roar of mounting and dismounting: a ring in the dinosaur's colour.
@(private = "file")
draw_dino_roar :: proc(renderer: ^Renderer, cue: ^Presentation_Cue) {
	p := presentation_cue_progress(cue)
	kind := game.Dino_Kind(cue.event.duration) if cue.kind == .Ride_Begun else renderer.tactical.arsenal.kind
	at := cue.event.from_position
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	for ring in 0..<2 {
		k := clamp(p*1.4-f32(ring)*0.25, f32(0), f32(1))
		marley_frame(f32(at.x)+0.5, 0.06, f32(at.y)+0.5, 0.3+1.1*k, 0.05, color_with_opacity(DINO_AURA[int(kind)%DINO_KINDS], 0.85*(1-k)))
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// --------------------------------------------------------------------------
// Labels, chip and previews.

// What the emplacements say over themselves: their name and the seconds left.
@(private)
draw_emplacement_labels :: proc(renderer: ^Renderer, room: ^game.Room) {
	snapshot := renderer.tactical.snapshot
	for object in snapshot.objects[:snapshot.object_count] {
		if (object.kind != .Field_Cannon && object.kind != .Devouring_Hole) || !object.visible { continue }
		cell := grid.Position{int(object.position.x), int(object.position.y)}
		if !tactical_render_visible(renderer, cell) { continue }
		name := "BUCO NERO"
		height := f32(0.8)
		if object.kind == .Field_Cannon {
			name = "LASER" if object.laser else "CANNONE"
			height = 1.0
		}
		p := tactical_project(renderer, {object.position.x+0.5, object.position.y+0.5}, height)
		draw_tactical_label(renderer, p, fmt.ctprintf("%s %ds", name, object.life), "", GOTHIC_RED if object.life <= 3 else GOTHIC_PAPER)
	}
}

// The ride's chip under VITA (RAPTOR 14s).
@(private)
ride_chip :: proc(renderer: ^Renderer, short: bool) -> (text: cstring, shown: bool) {
	ride := renderer.tactical.snapshot.ride
	if !ride.active { return }
	name := game.dino_name(ride.kind)
	if short && len(name) > 3 { name = name[:3] }
	return fmt.ctprintf("%s %ds", name, ride.remaining), true
}

// The cannon's aim while it is held over the board: its line of fire from the
// cell under the pointer, along the way the wheel gave (or the one from the
// player), to the first foe (all of them, for the laser) or the wall; a bar at
// each end and an arrow.
@(private)
draw_cannon_preview :: proc(renderer: ^Renderer, room: ^game.Room, card: game.Card_Instance, cell: grid.Position, valid: bool) {
	aim := renderer.tactical.flood_aim
	if !aim.active || room == nil || room.player == nil { return }
	laser := card.definition_id == .Laser_Cannon
	way := aim.way
	line := game.cannon_line(room, cell, way, laser)
	step := game.direction_offset(way)
	good := rl.Color{255, 96, 96, 255} if valid else rl.Color{150, 150, 150, 255}
	probe := grid.Position{cell.x+step.x, cell.y+step.y}
	beyond := grid.Position{line.last.x+step.x, line.last.y+step.y}
	for probe != beyond && grid.contains(&room.level_data.tiles, probe) {
		draw_card_range_cell(renderer, probe, {255, 80, 80, 44}, {255, 150, 150, 120})
		probe = {probe.x+step.x, probe.y+step.y}
	}
	for index in 0..<line.foe_count {
		for enemy in room.enemies {
			if enemy.id == line.foes[index] { draw_card_range_cell(renderer, enemy.position, {255, 236, 236, 70}, {255, 236, 236, 255}) }
		}
	}
	from := to_raylib(tactical_project(renderer, {f32(cell.x)+0.5, f32(cell.y)+0.5}, 0.6))
	last := line.last
	if last == cell { last = {cell.x+step.x, cell.y+step.y} }
	to := to_raylib(tactical_project(renderer, {f32(last.x)+0.5, f32(last.y)+0.5}, 0.6))
	along := to-from
	length := math.sqrt(along.x*along.x+along.y*along.y)
	if length > 1 {
		along /= length
		side := rl.Vector2{-along.y, along.x}
		rl.DrawLineEx(from, to, 6, good)
		head := f32(30)
		rl.DrawTriangle(to+along*head*0.4, to-along*head*0.6-side*head*0.55, to-along*head*0.6+side*head*0.55, rl.Color{255, 236, 236, 255})
		run := math.mod(f32(tactical_world_time(renderer))*70, f32(56))
		for offset := run; offset < length-head; offset += 56 {
			at := from+along*offset
			rl.DrawLineEx(at-along*8+side*9, at+along*4, 3, good)
			rl.DrawLineEx(at-along*8-side*9, at+along*4, 3, good)
		}
	}
	flood_label(renderer, "ROTELLA: MIRA", {from.x, from.y+44}, rl.Color{255, 236, 236, 255})
}

// The hole's two areas while the card is held: the 3x3 it hurts and the 5x5
// round it that it draws in (the generic light shows its cast range only).
@(private)
draw_black_hole_preview :: proc(renderer: ^Renderer, room: ^game.Room, card: game.Card_Instance, cell: grid.Position, valid: bool) {
	radius := int(game.black_hole_radius(card.upgrade_level))
	for dy in -radius-1..=radius+1 {
		for dx in -radius-1..=radius+1 {
			spot := grid.Position{cell.x+dx, cell.y+dy}
			if !grid.contains(&room.level_data.tiles, spot) || game.cell_blocks_movement(room, spot) { continue }
			inside := abs(dx) <= radius && abs(dy) <= radius
			if inside && valid {
				draw_card_range_cell(renderer, spot, {110, 70, 230, 70}, {190, 150, 255, 220})
			} else if inside {
				draw_card_range_cell(renderer, spot, {120, 120, 120, 40}, {150, 150, 150, 160})
			} else if valid {
				draw_card_range_cell(renderer, spot, {80, 60, 160, 28}, {150, 120, 230, 110})
			}
		}
	}
}
