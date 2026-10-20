package render

import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"

// Current intent is printed beside the health figures, using the same seven
// pixel rows. Shapes remain distinct without colour; committed wind-ups use
// red ink without an extra sticker, ring or animation above the enemy.
Intent_Icon :: enum u8 {None, Strike, Shoot, Charge, Bombard, Protect, Move, Retreat, Wait, Recover, Interrupted}

INTENT_GLYPH_SIZE :: 7

// Rows top to bottom; bit 6 is the leftmost pixel. Exhaustive enum tables
// keep a newly added intent from silently losing its glyph or colour.
@(private, rodata)
INTENT_GLYPHS := [Intent_Icon][INTENT_GLYPH_SIZE]u8{
	.None = {},
	.Strike = {0b0000011, 0b0000111, 0b0001110, 0b1011100, 0b0111000, 0b0010100, 0b1100000},
	.Shoot = {0b0010000, 0b0100010, 0b1000001, 0b1111111, 0b1000001, 0b0100010, 0b0010000},
	.Charge = {0b1001000, 0b1101100, 0b0110110, 0b0011011, 0b0110110, 0b1101100, 0b1001000},
	.Bombard = {0b0000101, 0b0000010, 0b0011100, 0b0111110, 0b1101111, 0b1111111, 0b0111110},
	.Protect = {0b1111111, 0b1000001, 0b1001001, 0b1011101, 0b1001001, 0b0100010, 0b0011100},
	.Move = {0b0111000, 0b0101000, 0b0111000, 0b0101000, 0b0101110, 0b1100001, 0b1111111},
	.Retreat = {0b0010000, 0b0100000, 0b1111110, 0b0100001, 0b0010001, 0b0000001, 0b0001110},
	.Wait = {0b1111111, 0b0100010, 0b0010100, 0b0001000, 0b0010100, 0b0100010, 0b1111111},
	.Recover = {0b0011100, 0b0100010, 0b1000000, 0b1000001, 0b1000101, 0b0100111, 0b0011111},
	.Interrupted = {0b1100011, 0b1110111, 0b0111110, 0b0011100, 0b0111110, 0b1110111, 0b1100011},
}

@(private = "file", rodata)
INTENT_COLORS := [Intent_Icon]rl.Color{
	.None = {13, 20, 30, 255},
	.Strike = {38, 45, 56, 255},
	.Shoot = {37, 84, 117, 255},
	.Charge = {145, 37, 42, 255},
	.Bombard = {115, 69, 24, 255},
	.Protect = {37, 84, 117, 255},
	.Move = {58, 70, 78, 255},
	.Retreat = {97, 65, 103, 255},
	.Wait = {115, 69, 24, 255},
	.Recover = {77, 79, 107, 255},
	.Interrupted = {145, 37, 42, 255},
}

@(private)
tactical_intent_icon :: proc(room: ^game.Room, enemy: ^game.Enemy) -> Intent_Icon {
	if enemy.health <= 0 || game.enemy_is_out_of_play(room, enemy.id) { return .None }
	if game.enemy_is_staggered(room, enemy) { return .Interrupted }
	switch enemy.intent.kind {
	case .None: return .None
	case .Wait: return .Wait
	case .Recover: return .Recover
	case .Protect: return .Protect
	case .Charge: return .Charge
	case .Bombard: return .Bombard
	case .Attack:
		if enemy.archetype == .Archer { return .Shoot }
		if enemy.archetype == .Bomber || enemy.archetype == .Demolitionist { return .Bombard }
		return .Strike
	case .Move:
		// Moving away from the hero is a retreat, not an approach.
		hero := room.player.position
		before := grid_distance(enemy.intent.origin, hero)
		after := grid_distance(enemy.intent.destination, hero)
		return .Retreat if after > before else .Move
	}
	return .None
}

@(private = "file")
grid_distance :: proc(a, b: grid.Position) -> int {
	return max(abs(a.x-b.x), abs(a.y-b.y))
}

// `at` is the top-left ink pixel inside the health tag. The caller aligns it
// to the figures; this routine never extends outside its seven-pixel square.
@(private)
draw_compact_intent :: proc(at: rl.Vector2, icon: Intent_Icon, pixel: f32, alarm: bool = false, alpha: f32 = 1) {
	if icon == .None || pixel <= 0 || alpha <= 0 { return }
	color := color_with_opacity(LIVING_TOKEN_DAMAGE if alarm else INTENT_COLORS[icon], alpha)
	for row in 0..<INTENT_GLYPH_SIZE {
		draw_pixel_row(INTENT_GLYPHS[icon][row], INTENT_GLYPH_SIZE, at.x, at.y+f32(row)*pixel, pixel, color)
	}
}
