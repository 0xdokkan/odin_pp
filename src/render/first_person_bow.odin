package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// FIRST PERSON ARCHER behind his eyes (game/first_person_bow.odin): the
// compound bow in the hands (first_person_compound.odin, Fase 7); in the
// world the arrows flying (a steel shaft, cyan fletching, a head of their
// status's colour, a streak of it behind them longer the faster they go) and
// stuck where they stopped; the critical zones as paper targets on their
// faces (the user's choice), ink round them, a light in the middle pulsing.
// Each bounce throws a burst of sparks where it struck, gold and a ring on a
// zone. Over the view: a ring round the crosshair filling with the draw, its
// four notches the levels, the bounces it gives beside it; the guide's dots
// along the path to its second bounce while drawing (the user's choice); the
// quiver round the crosshair (the user's choice): the nocked arrow's mark at
// the ring's left, the next's smaller under it, and the nocked one's name.

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
// A bounce's sparks: how long they fly.
FIRST_PERSON_BOW_SPARKS :: f64(0.28)

// Each arrow's mark in the quiver, 7 by 7 ('#' its colour, 'w' white, '.' none):
// a drop of venom, a flame, a snowflake, stars, a drop of blood.
@(rodata)
FIRST_PERSON_BOW_MARKS := [game.Bow_Arrow_Kind][7]string{
	.Poison = {"...#...", "..###..", ".#####.", "#######", "##w####", ".#####.", "..###.."},
	.Burn = {"...#...", "..##...", "..###.#", ".#####.", "##w####", "#######", ".#####."},
	.Ice = {"#..#..#", ".#.#.#.", "..###..", "###w###", "..###..", ".#.#.#.", "#..#..#"},
	.Stun = {"#.....#", ".#...#.", "...#...", "..#w#..", "...#...", ".#...#.", "#.....#"},
	.Barbed = {"...#...", "...#...", "..###..", ".#####.", "##w####", "#######", ".#####."},
}

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
	// The counts seen (the lab's sounds), the last blow and the last bounce,
	// when it was (sprite clock) and its number in its arrow's flight.
	loosed, hits, bounces, zone_bounces: i32,
	last: game.Bow_Hit,
	bounce_at: [3]f32,
	bounce_zone: bool,
	bounce_time: f64,
	bounce_order: i16,
}

@(private)
follow_first_person_bow :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical.first_person.bow
	if !game.first_person_bow_active(room) { return }
	s := &room.first_person.bow
	if s.bounces != v.bounces {
		v.bounce_time = renderer.sprite_assets.elapsed
		// The bounce's place in its arrow's flight: the most bounced arrow near it.
		v.bounce_order = 1
		for arrow in s.arrows {
			d := arrow.at-s.bounce_at
			if arrow.state != .None && d.x*d.x+d.y*d.y+d.z*d.z < 0.01 { v.bounce_order = max(arrow.bounced, 1) }
		}
	}
	v.drawing, v.charge, v.queue, v.arrows, v.zones = s.drawing, s.charge, s.queue, s.arrows, s.zones
	v.zone_count = int(s.zone_count)
	v.loosed, v.hits, v.bounces, v.zone_bounces, v.last = s.loosed, s.hits, s.bounces, s.zone_bounces, s.last
	v.bounce_at, v.bounce_zone = s.bounce_at, s.bounce_zone
	v.guide_count = 0
	if s.drawing { v.guide_count = game.bow_guide(room, first_person_aim(renderer), s.charge, v.guide[:]) }
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
		// The streak first, behind it: its colour, longer and brighter the faster it flies.
		if arrow.state == .Flying {
			streak := min(arrow.speed*0.035, 2.0)
			heat := clamp((arrow.speed-12)/48, 0, 1)
			rl.DrawCylinderEx(tail-way*streak, tail, 0.002, 0.014+0.012*heat, 4, color_with_opacity(color, 0.45+0.4*heat))
		}
		rl.DrawCylinderEx(tail, tip-way*0.08, 0.012, 0.012, 4, {214, 222, 232, 255})
		rl.DrawCylinderEx(tip-way*0.08, tip, 0.03, 0.002, 4, color)
		rl.DrawCylinderEx(tail, tail+way*0.1, 0.028, 0.028, 3, {60, 240, 255, 255})
		return
	}
	zone := f.bow.zones[index-game.BOW_ARROWS]
	open := game.direction_offset(game.Move_Direction(zone.face))
	n := rl.Vector3{f32(open.x), 0, f32(open.y)}
	centre := rl.Vector3{f32(zone.cell.x)+0.5+n.x*0.5, zone.floor+game.FIRST_PERSON_EYE_HEIGHT, f32(zone.cell.y)+0.5+n.z*0.5}
	pulse := 0.5+0.5*f32(math.sin(renderer.sprite_assets.elapsed*4))
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	// A paper target in ink, its rings, the light in its middle pulsing, a glow
	// round it: filled discs standing out of the face, each a hair nearer the room.
	// One flat fan of triangles each (no sides, no caps: a tenth of a cylinder's work).
	disc :: proc(centre, n: rl.Vector3, off, radius: f32, color: rl.Color) {
		SIDES :: 20
		side := rl.Vector3{-n.z, 0, n.x}
		up := rl.Vector3{0, 1, 0}
		c := centre+n*off
		rlgl.Begin(rlgl.TRIANGLES)
		rlgl.Color4ub(color.r, color.g, color.b, color.a)
		for k in 0..<SIDES {
			a0 := f32(k)*math.TAU/SIDES
			a1 := f32(k+1)*math.TAU/SIDES
			p0 := c+(side*math.cos(a0)+up*math.sin(a0))*radius
			p1 := c+(side*math.cos(a1)+up*math.sin(a1))*radius
			rlgl.Vertex3f(c.x, c.y, c.z)
			rlgl.Vertex3f(p0.x, p0.y, p0.z)
			rlgl.Vertex3f(p1.x, p1.y, p1.z)
		}
		rlgl.End()
	}
	disc(centre, n, 0.000, 0.30+0.04*pulse, color_with_opacity({255, 214, 80, 255}, 0.25*pulse))
	disc(centre, n, 0.002, 0.27, LIVING_TOKEN_INK)
	disc(centre, n, 0.004, 0.25, {241, 239, 230, 255})
	disc(centre, n, 0.006, 0.18, {196, 36, 52, 255})
	disc(centre, n, 0.008, 0.12, {241, 239, 230, 255})
	disc(centre, n, 0.010, 0.06, {196, 36, 52, 255})
	disc(centre, n, 0.012, 0.025+0.025*pulse, {255, 214, 80, 255})
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
	// The quiver round the crosshair: the nocked arrow's mark at the ring's
	// left, the next's smaller under it, the nocked one's name under the ring.
	mark :: proc(kind: game.Bow_Arrow_Kind, at: rl.Vector2, pixel: f32, alpha: f32) {
		rows := FIRST_PERSON_BOW_MARKS[kind]
		color := FIRST_PERSON_BOW_COLORS[kind]
		rl.DrawRectangleV(at-{pixel, pixel}, {pixel*9, pixel*9}, color_with_opacity(LIVING_TOKEN_INK, 0.85*alpha))
		for row, y in rows {
			for c, x in row {
				if c == '.' { continue }
				tone := rl.WHITE if c == 'w' else color
				rl.DrawRectangleV(at+{f32(x)*pixel, f32(y)*pixel}, {pixel, pixel}, color_with_opacity(tone, alpha))
			}
		}
	}
	mark(v.queue[0], {cx-r-14-7*3, cy-7*3*0.5-6}, 3, 1)
	mark(v.queue[1], {cx-r-14-7*2, cy+12}, 2, 0.7)
	now_name := FIRST_PERSON_BOW_NAMES[v.queue[0]]
	size := 16
	width := gothic_text_width(renderer, now_name, size)
	gothic_text(renderer, now_name, cx-width*0.5+2, cy+r+12, size, LIVING_TOKEN_INK)
	gothic_text(renderer, now_name, cx-width*0.5, cy+r+10, size, FIRST_PERSON_BOW_COLORS[v.queue[0]])
	// A bounce's sparks where it struck: white and cyan, gold and a ring on a zone.
	since := renderer.sprite_assets.elapsed-v.bounce_time
	if v.bounce_time > 0 && since >= 0 && since < FIRST_PERSON_BOW_SPARKS {
		p := v.bounce_at
		ahead := rl.Vector3DotProduct(rl.Vector3{p.x, p.y, p.z}-camera.position, rl.Vector3Normalize(camera.target-camera.position))
		if ahead > 0.2 {
			s := rl.GetWorldToScreenEx({p.x, p.y, p.z}, camera, i32(w), i32(h))
			u := f32(since/FIRST_PERSON_BOW_SPARKS)
			reach := (28+10*f32(v.bounce_order))/max(ahead, 1)*4
			for k in 0..<10 {
				a := f32(k)*math.TAU/10+0.3
				out := rl.Vector2{math.cos(a), math.sin(a)}*reach*(1-(1-u)*(1-u))
				color := rl.Color{255, 214, 80, 255} if v.bounce_zone else (rl.WHITE if k%2 == 0 else rl.Color{60, 240, 255, 255})
				rl.DrawLineEx(s+out*0.45, s+out, 2, color_with_opacity(color, 1-u))
			}
			if v.bounce_zone { rl.DrawRing(s, reach*u, reach*u+2, 0, 360, 32, color_with_opacity({255, 214, 80, 255}, 1-u)) }
		}
	}
}
