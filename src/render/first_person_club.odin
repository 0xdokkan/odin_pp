package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"

// BENVENUTI A NAPOLI's club on the board (game/first_person_club.odin;
// docs/piano-napoli.md, Fase 2). Behind his back rather than his eyes: as the
// card's cue plays the camera flies from the board's own view to a pivot over
// the player's right shoulder (CLUB_PIVOT_RIGHT, CLUB_PIVOT_HEIGHT) and stands
// CLUB_ARM behind it along the view, which the mouse turns (yaw, and a little up
// and down: CLUB_PITCH_UP, CLUB_PITCH_DOWN), looking through the pivot. The arm
// is a spring arm: five rays from the pivot back toward the camera (its own and
// four round it) meet what the bow's arrows meet (game.first_person_point_blocked),
// and the camera stands CLUB_ARM_MARGIN short of the first; nearer at once, back
// out over CLUB_ARM_RETURN_SECONDS (the arm springs back slowly, as a camera
// pressed to a wall does in most third person games). Close to him his card
// fades, down to CLUB_FADE_LEAST, and while he hides the cell he aims at it
// shows CLUB_COVER_SHOWN of itself (his 3D model, napoli_models.odin). Between his steps the pivot follows his card's
// glide, smoothed a little. The cell the blow will strike is marked on its
// floor; the club, a provisional stick with a green head, rests on his
// shoulder, rises over his head and comes down on that cell (its look comes in
// Fase 5).

CLUB_PIVOT_RIGHT :: f32(0.35)
CLUB_PIVOT_HEIGHT :: f32(1.45)
CLUB_ARM :: f32(1.4)
CLUB_ARM_LEAST :: f32(0.2)
CLUB_ARM_MARGIN :: f32(0.15)
CLUB_ARM_RETURN_SECONDS :: f32(0.3)
// The four rays round the camera's own, at the camera's end (cells).
CLUB_ARM_RAY_SPREAD :: f32(0.12)
CLUB_ARM_RAY_STEP :: f32(0.03)
CLUB_PITCH_UP :: f32(20*math.PI/180)
CLUB_PITCH_DOWN :: f32(30*math.PI/180)
// The look as the camera comes behind him: a little down, so the cell in
// front and its mark show over his shoulder.
CLUB_START_PITCH :: f32(-0.2)
// The arm's fade beyond which the club is not drawn (it would cross the lens).
CLUB_HIDE_FADE :: f32(0.3)
// The arm's length at which his card starts to fade and the least it shows.
CLUB_FADE_FROM :: f32(0.9)
CLUB_FADE_TO :: f32(0.35)
CLUB_FADE_LEAST :: f32(0.2)
// How quickly the pivot follows his card (seconds), and how far it may lag
// before it jumps (a dodge, a pull).
CLUB_PIVOT_LAG :: f32(0.06)
CLUB_PIVOT_JUMP :: f32(2.5)
// The provisional club: its length, the head's radius, the grip at his right
// hand (to his right, up from his floor).
CLUB_LENGTH :: f32(0.95)
// The grandpa's is a giant one.
CLUB_NONNO_LENGTH :: f32(1.25)
// His model's height and half width, for whether it hides the cell he aims at
// (club_model_covers), and how much of it shows then.
CLUB_MODEL_HEIGHT :: f32(1.45)
CLUB_MODEL_HALF :: f32(0.28)
CLUB_COVER_SHOWN :: f32(0.5)
// Seconds the model takes to fade out of the way, or back.
CLUB_COVER_SECONDS :: f32(0.12)
// How far his legs swing for a cell walked (radians).
CLUB_STRIDE_PER_CELL :: f32(4.5)
CLUB_MARK_COLOR :: rl.Color{238, 196, 92, 255}
CLUB_MARK_SWING_COLOR :: rl.Color{226, 88, 64, 255}

First_Person_Club_View :: struct {
	// The arm's length now, and the room's limit for it this frame.
	arm, limit: f32,
	// How much his card has faded (0: whole).
	fade: f32,
	// The pivot as it follows him, and whether it has been placed.
	pivot: rl.Vector3,
	placed: bool,
	// The sprite clock at the last frame, for the arm's and the pivot's easing.
	clock: f64,
	// The cell marked on the floor and whether the blow reaches it.
	aimed: grid.Position,
	reaches: bool,
	// The rules' blow as last seen: its time in, its way; the impacts seen.
	swing_at: f32,
	swing_way: [2]i8,
	swinging: bool,
	impacts_seen: i32,
	impact_at: f64,
	// BENVENUTI A NAPOLI's grandpa (game/napoli_nonno.odin): his body as last
	// seen (a cell's corner, as the snapshot's positions), how far his club is
	// out of his pocket (0..1), and whether he is the one shown.
	body: [2]f32,
	drawn: f32,
	nonno: bool,
	// His model: how much shows (1, or CLUB_COVER_SHOWN while it hides the cell
	// he aims at), its legs' swing and how far into a stride, where it stood,
	// the sprite clock at the last frame.
	shown, walk, stride: f32,
	last: [2]f32,
	walked: bool,
	model_clock: f64,
}

// The club the rules swing now: the club's view's, or the grandpa's.
@(private)
club_rules :: proc(room: ^game.Room) -> (club: ^game.First_Person_Club, ok: bool) {
	if game.first_person_club_active(room) { return &room.first_person.club, true }
	if game.napoli_nonno_active(room) { return &room.first_person.nonno.club, true }
	return
}

// Where the one behind whose back the camera stands is (a cell's corner): the
// grandpa's free body, else the player's card (`p`).
@(private)
club_anchor :: proc(renderer: ^Renderer, room: ^game.Room, p: [2]f32) -> [2]f32 {
	c := &renderer.tactical.first_person.club
	if game.napoli_nonno_active(room) { return c.body }
	return p
}

// Whether the view of the weapon in hand looks from behind his back.
first_person_third_person :: proc(renderer: ^Renderer) -> bool {
	if renderer == nil { return false }
	return game.FIRST_PERSON_WEAPONS[renderer.tactical.first_person.weapon].third_person
}

// The pitch the mouse may give the view with the weapon in hand.
first_person_pitch_limits :: proc(weapon: game.First_Person_Weapon) -> (up, down: f32) {
	if game.FIRST_PERSON_WEAPONS[weapon].third_person { return CLUB_PITCH_UP, CLUB_PITCH_DOWN }
	return game.FIRST_PERSON_PITCH_LIMIT, game.FIRST_PERSON_PITCH_LIMIT
}

// The view's look as a unit vector (x east, y up, z south).
@(private = "file")
club_look :: proc(yaw, pitch: f32) -> rl.Vector3 {
	return {math.cos(yaw)*math.cos(pitch), math.sin(pitch), math.sin(yaw)*math.cos(pitch)}
}

// How far back from `pivot` along `back` the arm reaches before it meets the
// room on `layer` (cells), at most `arm`: five rays, the camera's own and four
// round it, spreading as they go.
club_arm_limit :: proc(room: ^game.Room, pivot, back, right, up: rl.Vector3, arm: f32, layer: i8) -> f32 {
	if room == nil { return arm }
	base := board_base_drawn()
	offsets := [5][2]f32{{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	limit := arm
	met := false
	for offset in offsets {
		t := f32(0)
		for t < limit {
			t = min(t+CLUB_ARM_RAY_STEP, limit)
			spread := CLUB_ARM_RAY_SPREAD*t/arm
			at := pivot+back*t+right*(offset.x*spread)+up*(offset.y*spread)
			cell := grid.Position{x = int(math.floor(at.x)), y = int(math.floor(at.z)), layer = layer}
			if game.first_person_point_blocked(room, cell, at.y+base) {
				limit, met = t, true
				break
			}
		}
	}
	if !met { return arm }
	return max(limit-CLUB_ARM_MARGIN, CLUB_ARM_LEAST)
}

// The spring arm's length after `dt` seconds toward `limit`: nearer at once,
// back out slowly (95% of the way in CLUB_ARM_RETURN_SECONDS).
club_arm_ease :: proc(arm, limit, dt: f32) -> f32 {
	if arm <= 0 || limit < arm { return limit }
	return arm+(limit-arm)*(1-math.exp(-dt*3/CLUB_ARM_RETURN_SECONDS))
}

// The camera behind his back this frame: the pivot following his card at
// `p` (its glide, cell units), the arm sprung against the room. Where it
// stands and the way it looks.
@(private)
frame_first_person_club_camera :: proc(renderer: ^Renderer, room: ^game.Room, p: [2]f32, now: f64) -> (position, look: rl.Vector3) {
	f := &renderer.tactical.first_person
	c := &f.club
	dt := f32(clamp(now-c.clock, 0, 0.25)) if c.clock > 0 else 0
	c.clock = now
	look = club_look(f.yaw, f.pitch)
	flat := rl.Vector3Normalize({look.x, 0, look.z})
	right := rl.Vector3{-flat.z, 0, flat.x}
	ground := entity_point_ground(game.PLAYER_ENTITY, p)
	wanted := rl.Vector3{p.x+0.5, ground+CLUB_PIVOT_HEIGHT, p.y+0.5}+right*CLUB_PIVOT_RIGHT
	if !c.placed || rl.Vector3Distance(c.pivot, wanted) > CLUB_PIVOT_JUMP || dt <= 0 {
		c.pivot, c.placed = wanted, true
	} else {
		c.pivot += (wanted-c.pivot)*(1-math.exp(-dt/CLUB_PIVOT_LAG))
	}
	back := -look
	up := rl.Vector3CrossProduct(right, look)
	layer := room.player.position.layer if room != nil && room.player != nil else i8(grid.GROUND_LAYER)
	c.limit = club_arm_limit(room, c.pivot, back, right, up, CLUB_ARM, layer)
	c.arm = club_arm_ease(c.arm, c.limit, dt)
	c.fade = clamp((CLUB_FADE_FROM-c.arm)/(CLUB_FADE_FROM-CLUB_FADE_TO), 0, 1)*(1-CLUB_FADE_LEAST)
	return c.pivot+back*c.arm, look
}

// Once a frame (update_tactical_first_person): the rules' blow and the cell aimed.
@(private)
follow_first_person_club :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	club, ok := club_rules(room)
	if !ok {
		c.swinging = false
		return
	}
	c.nonno = game.napoli_nonno_active(room)
	c.drawn = 1
	if c.nonno {
		n := &room.first_person.nonno
		c.body = {n.body.body.x-0.5, n.body.body.y-0.5}
		c.drawn = 1-clamp(n.draw_left/game.NAPOLI_NONNO_DRAW_SECONDS, 0, 1)
	}
	c.swinging, c.swing_at, c.swing_way = club.blow.active, club.blow.at, club.blow.way
	if club.blow.active {
		c.aimed, c.reaches = game.club_cell(room, club.blow.from, club.blow.way)
	} else if c.nonno {
		c.aimed, c.reaches = game.club_cell(room, room.player.position, game.napoli_nonno_aim(room, f.yaw))
		// No mark before the club is out of his pocket.
		c.reaches = c.reaches && c.drawn >= 1
	} else {
		c.aimed, c.reaches = game.club_aimed_cell(room, f.yaw)
	}
	club_follow_model(renderer, room)
	if club.impacts > c.impacts_seen {
		c.impacts_seen = club.impacts
		c.impact_at = renderer.sprite_assets.elapsed
		// The floor's or a thing's blow has no foe's wound to juice it (club_juice.odin).
		if club.last.hit != .Foe { juice_club_floor(renderer, club.last) }
		if club.last.hit == .Foe && club.last.stagger > 0 { juice_club_daze(renderer, club.last.target) }
	}
}

// The club's angle from straight up toward the blow's way (radians) and his
// right hand's place in his own frame (right, up, front) `at` seconds into a
// blow: resting on his shoulder, raised back over his head, down in front of
// him on the cell, back.
// `lean` tips it out to his right (a part of its length): at rest it stands up
// beside him, away from the camera over his right shoulder; raised and struck
// it is straight over him.
club_swing_pose :: proc(swinging: bool, at: f32) -> (angle: f32, hand: [3]f32, lean: f32) {
	REST, RAISED, STRUCK :: f32(0.25), f32(-2.2), f32(1.95)
	LEAN_REST :: f32(0.45)
	HAND_REST, HAND_RAISED, HAND_STRUCK :: [3]f32{0.3, 0.88, 0.12}, [3]f32{0.08, 1.5, -0.02}, [3]f32{0.03, 0.95, 0.42}
	if !swinging { return REST, HAND_REST, LEAN_REST }
	if at < game.CLUB_WINDUP_SECONDS {
		u := at/game.CLUB_WINDUP_SECONDS
		k := 1-(1-u)*(1-u)
		return REST+(RAISED-REST)*k, HAND_REST+(HAND_RAISED-HAND_REST)*k, LEAN_REST*(1-k)
	}
	// The fall is quick (a tenth of the recovery), then the club comes back.
	u := (at-game.CLUB_WINDUP_SECONDS)/game.CLUB_RECOVER_SECONDS
	if u < 0.12 {
		k := (u/0.12)*(u/0.12)
		return RAISED+(STRUCK-RAISED)*k, HAND_RAISED+(HAND_STRUCK-HAND_RAISED)*k, 0
	}
	k := clamp((u-0.12)/0.88, 0, 1)
	k = k*k*(3-2*k)
	return STRUCK+(REST-STRUCK)*k, HAND_STRUCK+(HAND_REST-HAND_STRUCK)*k, LEAN_REST*k
}

club_swing_angle :: proc(swinging: bool, at: f32) -> f32 {
	angle, _, _ := club_swing_pose(swinging, at)
	return angle
}

// Whether the model standing at `feet` (`height` tall, `half` wide to either
// side) hides `target` from `camera` on a canvas of `size`: the target farther
// than him and inside his outline on the screen.
club_model_covers :: proc(camera: rl.Camera3D, size: [2]f32, feet: rl.Vector3, height, half: f32, target: rl.Vector3) -> bool {
	look := rl.Vector3Normalize(camera.target-camera.position)
	if rl.Vector3DotProduct(target-camera.position, look) <= rl.Vector3DotProduct(feet-camera.position, look) { return false }
	w, h := i32(size.x), i32(size.y)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(look, {0, 1, 0}))
	low := rl.GetWorldToScreenEx(feet, camera, w, h)
	top := rl.GetWorldToScreenEx(feet+{0, height, 0}, camera, w, h)
	side := rl.GetWorldToScreenEx(feet+{0, height*0.5, 0}+right*half, camera, w, h)
	mid := rl.GetWorldToScreenEx(feet+{0, height*0.5, 0}, camera, w, h)
	at := rl.GetWorldToScreenEx(target, camera, w, h)
	reach := abs(side.x-mid.x)
	return at.y >= min(top.y, low.y) && at.y <= max(top.y, low.y) && abs(at.x-mid.x) <= reach
}

// With the floor's marks: the cell the blow will strike (red while it falls),
// while the view is his.
@(private)
draw_first_person_club_mark :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	if _, swung := club_rules(room); !first_person_third_person(renderer) || f.amount <= 0 || !swung || !c.reaches { return }
	rlgl.DrawRenderBatchActive()
	defer rlgl.DrawRenderBatchActive()
	ground := cell_overlay_ground(c.aimed)+0.03
	x, z := f32(c.aimed.x), f32(c.aimed.y)
	color := color_with_opacity(CLUB_MARK_SWING_COLOR if c.swinging else CLUB_MARK_COLOR, 0.85*clamp(f.amount, 0, 1))
	edge :: f32(0.07)
	inset :: f32(0.06)
	bars := [4][4]f32{{x+inset, z+inset, 1-2*inset, edge}, {x+inset, z+1-inset-edge, 1-2*inset, edge},
		{x+inset, z+inset, edge, 1-2*inset}, {x+1-inset-edge, z+inset, edge, 1-2*inset}}
	for bar in bars {
		rl.DrawCubeV({bar[0]+bar[2]*0.5, ground, bar[1]+bar[3]*0.5}, {bar[2], 0.01, bar[3]}, color)
	}
}

// In the props' pass: him and his club as 3D paper models (napoli_models.odin)
// while the view is his: the Viandante from behind, both hands on the ace of
// clubs swung in the blow's way (else the view's); or the grandpa at the
// seaside, his giant club coming out of his shorts' pocket first, his mouth
// open at it. The model fades through its dither when it hides the cell he
// aims at, and more as the camera is pressed close to him.
@(private)
draw_first_person_club :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	if !first_person_third_person(renderer) || f.amount < FIRST_PERSON_AK_FROM || room == nil || room.player == nil ||
	   renderer.tactical.snapshot == nil || !renderer.tactical.snapshot.player.visible { return }
	p := club_anchor(renderer, room, renderer.tactical.snapshot.player.position)
	floor := entity_point_ground(game.PLAYER_ENTITY, p)
	look := club_look(f.yaw, 0)
	way := rl.Vector3Normalize({look.x, 0, look.z})
	if c.swinging && (c.swing_way.x != 0 || c.swing_way.y != 0) {
		way = rl.Vector3Normalize({f32(c.swing_way.x), 0, f32(c.swing_way.y)})
	}
	right := rl.Vector3{-way.z, 0, way.x}
	frame := napoli_model_frame({p.x+0.5, floor, p.y+0.5}, way)
	angle, hand, lean := club_swing_pose(c.swinging, c.swing_at)
	length := CLUB_NONNO_LENGTH if c.nonno else CLUB_LENGTH
	pocket := c.nonno && c.drawn < 1
	if pocket {
		// Out of the pocket, longer and longer, pointing down, then up onto his shoulder.
		u := c.drawn
		rise := max(u-0.7, 0)/0.3
		hand = [3]f32{0.2, 0.5, 0.06}+([3]f32{0.24, 0.95, 0.18}-[3]f32{0.2, 0.5, 0.06})*rise
		angle = math.PI+(0.25-math.PI)*rise
		lean *= rise
		length *= 0.15+0.85*min(u/0.7, 1)
	}
	grip := napoli_model_point(frame, hand)
	along := rl.Vector3Normalize(rl.Vector3{0, math.cos(angle), 0}+way*math.sin(angle)+right*lean)
	model: Napoli_Model
	if c.fade <= CLUB_HIDE_FADE { napoli_club_model(&model, grip, along, right, length) }
	second := napoli_club_second_hand(grip, along, length)
	if pocket { second = napoli_model_point(frame, {-0.24, 0.62, 0.04}) }
	walk := math.sin(c.walk)*c.stride
	if c.nonno {
		napoli_nonno_model(&model, frame, grip, second, walk, pocket)
	} else {
		napoli_pilgrim_model(&model, frame, grip, second, walk)
	}
	alpha := c.shown*(1-c.fade)*clamp(f.amount, 0, 1)
	draw_napoli_model(&renderer.tactical.napoli.models, &model, alpha)
}

// Once a frame: his model's stride as he goes, and whether it hides the cell he
// aims at from the camera (last frame's: the camera is framed after).
@(private = "file")
club_follow_model :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	now := renderer.sprite_assets.elapsed
	dt := f32(clamp(now-c.model_clock, 0, 0.25)) if c.model_clock > 0 else 0
	c.model_clock = now
	p := club_anchor(renderer, room, renderer.tactical.snapshot.player.position if renderer.tactical.snapshot != nil else {})
	moved := f32(0)
	if c.walked { moved = rl.Vector2Length(p-c.last) }
	if moved > 1.5 { moved = 0 }
	c.last, c.walked = p, true
	c.walk += moved*CLUB_STRIDE_PER_CELL
	moving := f32(1) if dt > 0 && moved/dt > 0.4 else 0
	ease := 1-math.exp(-dt/CLUB_COVER_SECONDS) if dt > 0 else 1
	c.stride += (moving-c.stride)*ease
	goal := f32(1)
	if c.reaches && f.amount > 0 {
		floor := entity_point_ground(game.PLAYER_ENTITY, p)
		target := rl.Vector3{f32(c.aimed.x)+0.5, cell_overlay_ground(c.aimed)+0.6, f32(c.aimed.y)+0.5}
		if club_model_covers(renderer.tactical.camera, {renderer.canvas_width, renderer.canvas_height}, {p.x+0.5, floor, p.y+0.5},
			CLUB_MODEL_HEIGHT, CLUB_MODEL_HALF, target) { goal = CLUB_COVER_SHOWN }
	}
	if c.shown <= 0 { c.shown = 1 }
	c.shown += (goal-c.shown)*ease
}
