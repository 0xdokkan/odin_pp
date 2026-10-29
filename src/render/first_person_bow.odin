package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// FIRST PERSON ARCHER behind his eyes (game/first_person_bow.odin): the
// prototype's look (Fase 6; the compound bow and its art are Fase 7's). The
// bow held up in the left hand on the gloves' small canvas, its string drawn
// back with the charge and an arrow on it in the nocked arrow's colour; in
// the world the arrows flying (a shaft and a head of their status's colour, a
// streak behind them longer the faster they go) and stuck where they stopped;
// the critical zones as targets on their faces. Over the view: a ring round
// the crosshair filling with the draw, its four notches the levels, the
// bounces it gives beside it; the guide's dots along the path to its second
// bounce while drawing (the user's choice); the nocked arrow and the next.

// Each arrow's colour and name (docs/piano-prima-persona.md, sezione 8).
@(rodata)
FIRST_PERSON_BOW_COLORS := [game.Bow_Arrow_Kind]rl.Color{
	.Poison = {96, 214, 92, 255}, .Burn = {246, 128, 44, 255}, .Ice = {150, 214, 255, 255},
	.Stun = {250, 222, 70, 255}, .Barbed = {196, 36, 52, 255},
}
@(rodata)
FIRST_PERSON_BOW_NAMES := [game.Bow_Arrow_Kind]cstring{
	.Poison = "VELENOSA", .Burn = "INCENDIARIA", .Ice = "DI GHIACCIO", .Stun = "STORDENTE", .Barbed = "DENTATA",
}
// The guide's points at most, and the step of its dots (cells).
FIRST_PERSON_BOW_GUIDE :: 6
FIRST_PERSON_BOW_GUIDE_DOT :: f32(0.35)
FIRST_PERSON_BOW_RING :: f32(26)
FIRST_PERSON_BOW_TEAL :: rl.Color{80, 230, 196, 255}

// What the board keeps of the bow each frame its view is on.
First_Person_Bow_View :: struct {
	drawing: bool,
	charge: f32,
	queue: [2]game.Bow_Arrow_Kind,
	arrows: [game.BOW_ARROWS]game.Bow_Arrow,
	zones: [game.BOW_ZONES]game.Bow_Zone,
	zone_count: int,
	// The path a release now would fly, while drawing.
	guide: [FIRST_PERSON_BOW_GUIDE]game.Bow_Path_Point,
	guide_count: int,
	// The counts seen (the lab's sounds), the last blow and the last bounce.
	loosed, hits, bounces, zone_bounces: i32,
	last: game.Bow_Hit,
	bounce_at: [3]f32,
	bounce_zone: bool,
}

@(private)
follow_first_person_bow :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical.first_person.bow
	if !game.first_person_bow_active(room) { return }
	s := &room.first_person.bow
	v.drawing, v.charge, v.queue, v.arrows, v.zones = s.drawing, s.charge, s.queue, s.arrows, s.zones
	v.zone_count = int(s.zone_count)
	v.loosed, v.hits, v.bounces, v.zone_bounces, v.last = s.loosed, s.hits, s.bounces, s.zone_bounces, s.last
	v.bounce_at, v.bounce_zone = s.bounce_at, s.bounce_zone
	v.guide_count = 0
	if s.drawing { v.guide_count = game.bow_guide(room, first_person_aim(renderer), s.charge, v.guide[:]) }
}

// The bow on the gloves' small canvas (`w` by `h`), coming up from under the
// view `ready` 0..1: a recurve's curve of carbon with magenta tips, held
// left of the crosshair, its string drawn back with the charge, the arrow on it.
@(private)
draw_first_person_bow_pixel :: proc(renderer: ^Renderer, w, h: i32, ready: f32) {
	v := &renderer.tactical.first_person.bow
	lift := (1-ready)*0.7
	at :: proc(p: [2]f32, w, h: i32, lift: f32) -> rl.Vector2 {
		return {f32(w)*0.5+p.x*f32(h), f32(h)*0.5-(p.y-lift)*f32(h)}
	}
	// The bow's line: from the lower tip to the upper, bulging left.
	points: [9]rl.Vector2
	for k in 0..<9 {
		u := f32(k)/8
		y := -0.66+u*0.62
		x := -0.36-0.05*math.sin(u*math.PI)
		points[k] = at({x, y}, w, h, lift)
	}
	for k in 0..<8 {
		thick := f32(h)*(0.022 if k >= 3 && k <= 4 else 0.014)
		rl.DrawLineEx(points[k], points[k+1], thick, {44, 34, 84, 255})
	}
	rl.DrawLineEx(points[3], points[5], f32(h)*0.03, {24, 18, 48, 255})
	rl.DrawCircleV(points[0], f32(h)*0.012, {255, 64, 206, 255})
	rl.DrawCircleV(points[8], f32(h)*0.012, {255, 64, 206, 255})
	// The string, drawn back toward the eye with the charge.
	nock := at({-0.31+0.08*v.charge, -0.36-0.04*v.charge}, w, h, lift)
	rl.DrawLineEx(points[0], nock, 1, {236, 226, 200, 255})
	rl.DrawLineEx(points[8], nock, 1, {236, 226, 200, 255})
	// The arrow on it, toward the crosshair, in the nocked arrow's colour.
	head := at({-0.16, -0.22}, w, h, lift)
	rl.DrawLineEx(nock, head, 2, {214, 222, 232, 255})
	rl.DrawCircleV(head, f32(h)*0.008, FIRST_PERSON_BOW_COLORS[v.queue[0]])
}

// The world's arrows and zones for the board's translucent pass (indices past
// the tracers' and their sparks').
@(private)
collect_first_person_bow_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	f := &renderer.tactical.first_person
	if !f.engaged || f.weapon != .Bow { return }
	base := 2*len(f.tracers)
	for arrow, k in f.bow.arrows {
		if arrow.state == .None { continue }
		append(entries, Tactical_Alpha_Entry{kind = .First_Person, first_person = i32(base+k), position = {arrow.at.x-0.5, arrow.at.z-0.5}})
	}
	for zone, k in f.bow.zones[:f.bow.zone_count] {
		append(entries, Tactical_Alpha_Entry{kind = .First_Person, first_person = i32(base+game.BOW_ARROWS+k),
			position = {f32(zone.cell.x), f32(zone.cell.y)}})
	}
}

// An arrow (index < BOW_ARROWS) or a zone of the bow's, in the world.
@(private)
draw_first_person_bow_entry :: proc(renderer: ^Renderer, index: int) {
	f := &renderer.tactical.first_person
	if index < game.BOW_ARROWS {
		arrow := f.bow.arrows[index]
		if arrow.state == .None { return }
		tip := rl.Vector3{arrow.at.x, arrow.at.y, arrow.at.z}
		way := rl.Vector3{arrow.way.x, arrow.way.y, arrow.way.z}
		color := FIRST_PERSON_BOW_COLORS[arrow.kind]
		tail := tip-way*0.6
		rl.DrawCylinderEx(tail, tip-way*0.08, 0.012, 0.012, 4, {214, 222, 232, 255})
		rl.DrawCylinderEx(tip-way*0.08, tip, 0.03, 0.002, 4, color)
		rl.DrawCylinderEx(tail, tail+way*0.1, 0.028, 0.028, 3, {60, 240, 255, 255})
		if arrow.state == .Flying {
			streak := min(arrow.speed*0.03, 1.6)
			rl.DrawLine3D(tail, tail-way*streak, color_with_opacity(color, 0.7))
		}
		return
	}
	zone := f.bow.zones[index-game.BOW_ARROWS]
	open := game.direction_offset(game.Move_Direction(zone.face))
	n := rl.Vector3{f32(open.x), 0, f32(open.y)}
	centre := rl.Vector3{f32(zone.cell.x)+0.5+n.x*0.51, zone.floor+game.FIRST_PERSON_EYE_HEIGHT, f32(zone.cell.y)+0.5+n.z*0.51}
	// The circle is drawn in the XY plane: a face along x turns it a quarter round Y.
	axis, angle := rl.Vector3{0, 1, 0}, f32(90 if n.x != 0 else 0)
	pulse := 0.5+0.5*f32(math.sin(renderer.sprite_assets.elapsed*4))
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	rl.DrawCircle3D(centre, 0.24, axis, angle, {241, 239, 230, 255})
	rl.DrawCircle3D(centre, 0.17, axis, angle, {196, 36, 52, 255})
	rl.DrawCircle3D(centre, 0.10, axis, angle, {241, 239, 230, 255})
	rl.DrawCircle3D(centre, 0.04+0.03*pulse, axis, angle, {255, 214, 80, 255})
}

// Over the view: the draw's ring and its levels, the bounces it gives, the
// guide's dots, the nocked arrow and the next.
@(private)
draw_first_person_bow_hud :: proc(renderer: ^Renderer) {
	f := &renderer.tactical.first_person
	v := &f.bow
	w, h := renderer.canvas_width, renderer.canvas_height
	cx, cy := math.round(w*0.5), math.round(h*0.5)
	camera := renderer.tactical.camera
	// The guide, as dots along its path.
	for k in 0..<v.guide_count-1 {
		a, b := v.guide[k].at, v.guide[k+1].at
		d := b-a
		length := math.sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
		dots := int(length/FIRST_PERSON_BOW_GUIDE_DOT)
		for j in 1..=dots {
			p := a+d*(f32(j)/f32(dots+1))
			ahead := rl.Vector3DotProduct(rl.Vector3{p.x, p.y, p.z}-camera.position, rl.Vector3Normalize(camera.target-camera.position))
			if ahead <= 0.2 { continue }
			s := rl.GetWorldToScreenEx({p.x, p.y, p.z}, camera, i32(w), i32(h))
			rl.DrawRectangleV({math.round(s.x)-2, math.round(s.y)-2}, {4, 4}, LIVING_TOKEN_INK)
			rl.DrawRectangleV({math.round(s.x)-1, math.round(s.y)-1}, {2, 2}, FIRST_PERSON_BOW_TEAL if k == 0 else rl.Color{255, 214, 80, 255})
		}
	}
	// The ring: dark, filling teal with the draw, gold when full; four notches.
	r := FIRST_PERSON_BOW_RING
	rl.DrawRing({cx, cy}, r-3, r+1, 0, 360, 48, color_with_opacity(LIVING_TOKEN_INK, 0.6))
	if v.drawing {
		full := v.charge >= 1
		rl.DrawRing({cx, cy}, r-2, r, -90, -90+360*v.charge, 48, rl.Color{255, 214, 80, 255} if full else FIRST_PERSON_BOW_TEAL)
	}
	for k in 1..=4 {
		a := f32(-90+90*k)*math.PI/180
		p := rl.Vector2{cx+math.cos(a)*r, cy+math.sin(a)*r}
		rl.DrawRectangleV({p.x-2, p.y-2}, {4, 4}, GOTHIC_PAPER)
	}
	if v.drawing {
		bounces := game.bow_level(v.charge)
		text := cstring("0") if bounces == 0 else (cstring("1") if bounces == 1 else (cstring("2") if bounces == 2 else (cstring("3") if bounces == 3 else cstring("4"))))
		gothic_text(renderer, text, cx+r+8, cy-12, 22, GOTHIC_PAPER)
	}
	// The nocked arrow and the next, under the crosshair.
	now_name, next_name := FIRST_PERSON_BOW_NAMES[v.queue[0]], FIRST_PERSON_BOW_NAMES[v.queue[1]]
	size := 18
	width := gothic_text_width(renderer, now_name, size)
	gothic_text(renderer, now_name, cx-width*0.5+2, cy+r+12, size, LIVING_TOKEN_INK)
	gothic_text(renderer, now_name, cx-width*0.5, cy+r+10, size, FIRST_PERSON_BOW_COLORS[v.queue[0]])
	small := 14
	width = gothic_text_width(renderer, next_name, small)
	gothic_text(renderer, next_name, cx-width*0.5, cy+r+32, small, color_with_opacity(FIRST_PERSON_BOW_COLORS[v.queue[1]], 0.75))
}
