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
// fades further, down to CLUB_FADE_LEAST (it shows only CLUB_CARD_SHOWN of
// itself anyway, so a foe in front shows through it). Between his steps the pivot follows his card's
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
// His card behind his back shows this much of itself, so that a foe in front
// of him shows through it (the provisional card is as wide as half the view;
// his model seen from behind comes with Fase 5).
CLUB_CARD_SHOWN :: f32(0.5)
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
CLUB_HEAD_RADIUS :: f32(0.14)
CLUB_GRIP_RIGHT :: f32(0.26)
CLUB_GRIP_HEIGHT :: f32(0.78)
CLUB_MARK_COLOR :: rl.Color{238, 196, 92, 255}
CLUB_MARK_SWING_COLOR :: rl.Color{226, 88, 64, 255}
CLUB_HANDLE_COLOR :: rl.Color{168, 48, 40, 255}
CLUB_HEAD_COLOR :: rl.Color{58, 142, 70, 255}

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
	if !game.first_person_club_active(room) {
		c.swinging = false
		return
	}
	club := &room.first_person.club
	c.swinging, c.swing_at, c.swing_way = club.blow.active, club.blow.at, club.blow.way
	if club.blow.active {
		c.aimed, c.reaches = game.club_cell(room, club.blow.from, club.blow.way)
	} else {
		c.aimed, c.reaches = game.club_aimed_cell(room, f.yaw)
	}
	if club.impacts > c.impacts_seen {
		c.impacts_seen = club.impacts
		c.impact_at = renderer.sprite_assets.elapsed
	}
}

// The club's angle from straight up toward the blow's way (radians) `at`
// seconds into a blow: resting on his shoulder, raised back over his head,
// down on the cell, back.
club_swing_angle :: proc(swinging: bool, at: f32) -> f32 {
	REST :: f32(-0.5)
	RAISED :: f32(-2.2)
	STRUCK :: f32(1.95)
	if !swinging { return REST }
	if at < game.CLUB_WINDUP_SECONDS {
		u := at/game.CLUB_WINDUP_SECONDS
		return REST+(RAISED-REST)*(1-(1-u)*(1-u))
	}
	// The fall is quick (a tenth of the recovery), then the club comes back.
	u := (at-game.CLUB_WINDUP_SECONDS)/game.CLUB_RECOVER_SECONDS
	if u < 0.12 {
		k := u/0.12
		return RAISED+(STRUCK-RAISED)*k*k
	}
	k := (u-0.12)/0.88
	return STRUCK+(REST-STRUCK)*(k*k*(3-2*k))
}

// With the floor's marks: the cell the blow will strike (red while it falls),
// while the view is his.
@(private)
draw_first_person_club_mark :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	if !first_person_third_person(renderer) || f.amount <= 0 || !game.first_person_club_active(room) || !c.reaches { return }
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

// In the props' pass (the resin light on): the provisional club in his right
// hand, swung in the blow's way (else the view's), while the view is his.
@(private)
draw_first_person_club :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	c := &f.club
	if !first_person_third_person(renderer) || f.amount < FIRST_PERSON_AK_FROM || room == nil || room.player == nil ||
	   renderer.tactical.snapshot == nil || !renderer.tactical.snapshot.player.visible || c.fade > CLUB_HIDE_FADE { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	p := renderer.tactical.snapshot.player.position
	floor := entity_point_ground(game.PLAYER_ENTITY, p)
	look := club_look(f.yaw, 0)
	way := rl.Vector3Normalize({look.x, 0, look.z})
	if c.swinging && (c.swing_way.x != 0 || c.swing_way.y != 0) {
		way = rl.Vector3Normalize({f32(c.swing_way.x), 0, f32(c.swing_way.y)})
	}
	right := rl.Vector3{-way.z, 0, way.x}
	grip := rl.Vector3{p.x+0.5, floor+CLUB_GRIP_HEIGHT, p.y+0.5}+right*CLUB_GRIP_RIGHT
	angle := club_swing_angle(c.swinging, c.swing_at)
	along := rl.Vector3{0, math.cos(angle), 0}+way*math.sin(angle)
	head := grip+along*CLUB_LENGTH
	rl.DrawCylinderEx(grip-along*0.08, head, 0.045, 0.07, 10, CLUB_HANDLE_COLOR)
	rl.DrawSphereEx(head, CLUB_HEAD_RADIUS, 10, 10, CLUB_HEAD_COLOR)
	rl.DrawSphereEx(head+along*0.04, CLUB_HEAD_RADIUS*0.7, 8, 8, rl.Color{86, 172, 92, 255})
}
