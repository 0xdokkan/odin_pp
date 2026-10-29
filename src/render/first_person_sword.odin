package render

import "core:math"
import game "../game"

// FIRST PERSON FENCER behind his eyes (game/first_person_sword.odin): the view
// looks the way the rules face, turning a quarter in FIRST_PERSON_SWORD_TURN
// seconds when Q or E turns them, level (the mouse is the blade's). The board
// keeps what it draws the blade from (follow_first_person_sword).

FIRST_PERSON_SWORD_TURN :: f64(0.15)

// What the board keeps of the sword each frame its view is on.
First_Person_Sword_View :: struct {
	// The blade's point (screen heights) and whether a swing is on, the last
	// cut and the count of cuts, parries and grapples seen.
	tip: [2]f32,
	swinging: bool,
	last: game.Sword_Strike,
	strikes, parries, perfect_parries, grapples: i32,
	// The sprite clock at the last frame followed (the turn's pace).
	seen_at: f64,
}

@(private)
follow_first_person_sword :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	now := renderer.sprite_assets.elapsed
	dt := clamp(now-f.sword.seen_at, 0, 0.1)
	f.sword.seen_at = now
	if !game.first_person_sword_active(room) { return }
	s := &room.first_person.sword
	f.sword.tip, f.sword.swinging, f.sword.last = s.tip, s.swing.active, s.last
	f.sword.strikes, f.sword.parries, f.sword.perfect_parries, f.sword.grapples = s.strikes, s.parries, s.perfect_parries, s.grapples
	// The view turns toward the rules' facing, a quarter in FIRST_PERSON_SWORD_TURN, level.
	if !f.engaged { return }
	target := game.first_person_yaw(s.facing)
	gap := first_person_wrap(target-f.yaw)
	step := f32(math.PI/2*dt/FIRST_PERSON_SWORD_TURN)
	f.yaw = target if abs(gap) <= step else first_person_wrap(f.yaw+(step if gap > 0 else -step))
	f.pitch = 0
}
