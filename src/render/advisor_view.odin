package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"

// THE IA'S ADVICE ON THE BOARD (docs/piano-ia.md, Fase 5), in one colour, cyan (IA_COLOR), different signs:
// - a step (VAI, or SCHIVA when it leaves a threatened cell): a footprint on the cell to go to, an arrow from the player;
// - a bump (COLPISCI) or an arrow of Feretro (FRECCIA): a sight on the foe's cell, breathing slowly;
// - a card (CARTA): a cyan frame round the card in the hand (tactical_hand.odin); while the player holds it, the frame
//   goes to the target's cell (the foe, the floor or the player himself);
// - a defence (DIFENDI): the frame on the right key in the defence panel (tactical_hud.odin), and the dodge's landing;
// - a wait (ASPETTA): a small clock under the player; the refocus (RIMESCOLA): the word only;
// - the warning: a red «!» with the life the player's own move risks, over him for half a second;
// - no advice (still thinking, or a case it cannot play out): «IA: ...», never a wrong sign.
// The word goes over the player. Nothing is drawn on a cell the player cannot see: the advice reveals nothing.
// The pilot (run/advisor_driver.odin) sets it every frame; nothing while the IA is off or stands still (the views).

Advice_Mark :: enum u8 { None, Step, Bump, Wait, Defend, Card, Refocus }

Advice_View :: struct {
	mark: Advice_Mark,
	cell: grid.Position,
	word: cstring,
	// A card's advice: the card in hand, its target on `cell`.
	card_id: u32,
	// A defence's advice: the key of the panel to press (`defense`), or the key now awaited (`key`); a dodge lands on
	// `cell`.
	defense: game.Defense_Mode,
	has_defense: bool,
	key: game.Move_Direction,
	has_key: bool,
	// Seconds since this advice was first shown (the sight breathes with them).
	age: f32,
	// The warning: its text («! -3»), shown while `warning_left` lasts.
	warning: cstring,
	warning_left: f32,
}

ADVICE_WARNING_SECONDS :: f32(0.5)
ADVICE_WARNING_COLOR :: rl.Color{235, 64, 52, 255}

advice_shown :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return renderer.tactical.advice.mark != .None && game.ia_active(room)
}

// The cell where a sign of the advice goes on the floor, if one does, and the player can see it.
advice_floor_cell :: proc(renderer: ^Renderer, room: ^game.Room, active_card: u32) -> (cell: grid.Position, ok: bool) {
	if !advice_shown(renderer, room) { return }
	advice := renderer.tactical.advice
	switch advice.mark {
	case .None, .Refocus: return
	case .Step, .Bump: cell = advice.cell
	case .Wait: cell = room.player.position
	case .Card:
		// On the board only while the player holds the card.
		if active_card == 0 || active_card != advice.card_id { return }
		cell = advice.cell
	case .Defend:
		// The panel holds the key; the floor only a dodge's landing.
		if advice.has_defense && advice.defense != .Dodge { return }
		if advice.cell == room.player.position { return }
		cell = advice.cell
	}
	return cell, tactical_render_visible(renderer, cell)
}

@(private = "file")
advice_ground :: proc(cell: grid.Position) -> rl.Vector3 {
	return {f32(cell.x)+0.5, 0.05+cell_overlay_ground(cell), f32(cell.y)+0.5}
}

// A disc lying on the floor (a stack of thin cylinders: the floor's wires are thin).
@(private = "file")
floor_disc :: proc(center: rl.Vector3, radius: f32, color: rl.Color) {
	rl.DrawCylinder(center, radius, radius, 0.012, 16, color)
}

// A ring on the floor, a few wires thick.
@(private = "file")
floor_ring :: proc(center: rl.Vector3, radius: f32, color: rl.Color) {
	for k in 0..<4 { rl.DrawCircle3D({center.x, center.y+0.004*f32(k), center.z}, radius+0.008*f32(k), {1, 0, 0}, 90, color) }
}

// A footprint: two soles side by side, each with its toes, pointing `way` (wide as the cell: a sprite standing on it
// hides less of it).
@(private = "file")
draw_footprint :: proc(center: rl.Vector3, way: rl.Vector2) {
	side := rl.Vector2{-way.y, way.x}
	for foot in ([2]f32{-1, 1}) {
		heel := rl.Vector2{center.x, center.z}+side*(0.15*foot)-way*0.16
		floor_disc({heel.x, center.y, heel.y}, 0.1, IA_COLOR)
		sole := heel+way*0.17
		floor_disc({sole.x, center.y, sole.y}, 0.12, IA_COLOR)
		for toe in 0..<3 {
			spot := sole+way*0.17+side*(0.06*f32(toe-1))
			floor_disc({spot.x, center.y, spot.y}, 0.032, IA_COLOR)
		}
	}
}

// The floor's sign, in the world's pass.
draw_advice_floor :: proc(renderer: ^Renderer, room: ^game.Room, active_card: u32 = 0) {
	cell, ok := advice_floor_cell(renderer, room, active_card)
	if !ok { return }
	advice := renderer.tactical.advice
	center := advice_ground(cell)
	faint := rl.Color{IA_COLOR.r, IA_COLOR.g, IA_COLOR.b, 45}
	#partial switch advice.mark {
	case .Step, .Defend:
		// In the shadow the arrow leaves the shadow, not the body that waits.
		origin := room.player.tactical.shadow_position if game.tactical_shadow_active(room) else room.player.position
		from := advice_ground(origin)
		way := rl.Vector2Normalize({center.x-from.x, center.z-from.z})
		if way == {} { way = {0, -1} }
		rl.DrawPlane(center, {0.84, 0.84}, faint)
		draw_footprint(center, way)
		// The arrow from the player: a shaft, then its head, stopping short of the footprint.
		start := rl.Vector3{from.x+way.x*0.3, from.y+0.03, from.z+way.y*0.3}
		tip := rl.Vector3{center.x-way.x*0.38, center.y+0.03, center.z-way.y*0.38}
		length := rl.Vector3Length(tip-start)
		if length > 0.15 {
			neck := tip-rl.Vector3{way.x, 0, way.y}*0.16
			rl.DrawCylinderEx(start, neck, 0.035, 0.035, 8, IA_COLOR)
			rl.DrawCylinderEx(neck, tip, 0.1, 0, 8, IA_COLOR)
		}
	case .Bump:
		// The sight breathes: a little wider and back, about once a second.
		breath := 1+0.07*math.sin(advice.age*6)
		// Wider than the foe standing on it, its four ticks reaching past the cell's edges.
		floor_ring(center, 0.46*breath, IA_COLOR)
		floor_ring(center, 0.22*breath, IA_COLOR)
		for k in 0..<4 {
			angle := f32(k)*math.PI/2
			x, z := math.cos(angle), math.sin(angle)
			rl.DrawCube({center.x+x*0.5*breath, center.y+0.01, center.z+z*0.5*breath}, 0.07+abs(x)*0.22, 0.02, 0.07+abs(z)*0.22, IA_COLOR)
		}
	case .Card:
		rl.DrawPlane(center, {0.86, 0.86}, faint)
		for k in 0..<3 { rl.DrawCubeWires({center.x, center.y+0.004*f32(k), center.z}, 0.86-0.03*f32(k), 0.01, 0.86-0.03*f32(k), IA_COLOR) }
	case .Wait:
		// A small clock under the player's feet: its face, twelve marks, two hands.
		floor_ring(center, 0.34, IA_COLOR)
		for k in 0..<12 {
			angle := f32(k)*math.PI/6
			rl.DrawCube({center.x+math.cos(angle)*0.28, center.y+0.01, center.z+math.sin(angle)*0.28}, 0.035, 0.02, 0.035, IA_COLOR)
		}
		hand := advice.age*2
		rl.DrawCylinderEx({center.x, center.y+0.02, center.z}, {center.x+math.cos(hand)*0.22, center.y+0.02, center.z+math.sin(hand)*0.22}, 0.02, 0.02, 6, IA_COLOR)
		rl.DrawCylinderEx({center.x, center.y+0.02, center.z}, {center.x, center.y+0.02, center.z-0.14}, 0.025, 0.025, 6, IA_COLOR)
	}
}

// The word over the player, and the warning over the word, with the labels.
draw_advice_word :: proc(renderer: ^Renderer, room: ^game.Room) {
	advice := renderer.tactical.advice
	p := room.player.position
	over := tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 1.75)
	if advice_shown(renderer, room) && advice.word != nil { draw_tactical_label(renderer, over, advice.word, "", IA_COLOR) }
	// WHEN IT DOES NOT KNOW (Fase 7): no advice yet, or none it can stand by: no sign, only «IA: ...». Never a wrong one.
	if game.ia_active(room) && advice.mark == .None { draw_tactical_label(renderer, over, "IA: ...", "", IA_COLOR) }
	if advice.warning != nil && advice.warning_left > 0 && game.ia_active(room) {
		draw_tactical_label(renderer, {over.x, over.y-30}, advice.warning, "", ADVICE_WARNING_COLOR)
	}
}

// The defence panel's key the IA advises (tactical_hud.odin): its frame.
advice_frames_defense :: proc(renderer: ^Renderer, room: ^game.Room, mode: game.Defense_Mode) -> bool {
	advice := renderer.tactical.advice
	return advice_shown(renderer, room) && advice.mark == .Defend && advice.has_defense && advice.defense == mode
}

advice_frames_key :: proc(renderer: ^Renderer, room: ^game.Room) -> (key: game.Move_Direction, ok: bool) {
	advice := renderer.tactical.advice
	if !advice_shown(renderer, room) || advice.mark != .Defend || !advice.has_key { return }
	return advice.key, true
}
