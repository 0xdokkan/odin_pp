package render

import "core:math"
import rl "vendor:raylib"
import game "../game"

// FOES LIGHT UP AS THEY ACT (the user's wish, 2026-10-29: behind the sword's
// eyes he could not tell when a foe was striking, and cannot keep watching the
// ground). A foe whose intent strikes glows red, one shielding an ally or
// throwing a bomb glows purple (the user's choice: the Custode's shield and the
// bombs), in every view: its whole card, paper and print, takes the colour. The
// glow grows with the intent's countdown (tactical_enemy_seconds), pulsing
// faster as the blow comes, and holds at its brightest over the last
// FOE_GLOW_PEAK seconds (the sword's perfect parry window); it fades out in
// FOE_GLOW_FADE once the foe is done.

FOE_GLOW_RED :: rl.Color{255, 46, 52, 255}
FOE_GLOW_PURPLE :: rl.Color{176, 70, 255, 255}
FOE_GLOW_PEAK :: game.SWORD_PERFECT_PARRY
FOE_GLOW_FADE :: f32(0.15)
// How fast the pulses come: FOE_GLOW_BEAT / (seconds left + FOE_GLOW_LEAD) a second.
FOE_GLOW_BEAT :: f32(4)
FOE_GLOW_LEAD :: f32(0.3)
// The pulses' tops: dim as it is planned, this much more just before the last FOE_GLOW_PEAK seconds.
FOE_GLOW_DIM :: f32(0.3)
FOE_GLOW_GROWN :: f32(0.48)
FOE_GLOW_MAX :: 64

Foe_Glow :: struct {
	entity: game.Entity_Ref,
	color: rl.Color,
	amount: f32,
}

// What the board keeps of the foes' glows each frame.
Foe_Glow_View :: struct {
	glows: [FOE_GLOW_MAX]Foe_Glow,
	count: int,
	at: f64,
}

// The colour an intent glows with, if any.
foe_glow_color :: proc(kind: game.Enemy_Intent_Kind) -> (color: rl.Color, glows: bool) {
	#partial switch kind {
	case .Attack, .Charge: return FOE_GLOW_RED, true
	case .Protect, .Bombard: return FOE_GLOW_PURPLE, true
	}
	return {}, false
}

// How bright an intent glows with `left` of its `total` seconds to go (0..1):
// from a faint light as it is planned, growing and pulsing faster, steady at
// its brightest over the last FOE_GLOW_PEAK seconds.
foe_glow_amount :: proc(left, total: f32) -> f32 {
	if left <= FOE_GLOW_PEAK { return 1 }
	span := max(total, left, FOE_GLOW_PEAK+0.01)
	grown := clamp(1-(left-FOE_GLOW_PEAK)/(span-FOE_GLOW_PEAK), 0, 1)
	// The pulses' phase: its rate rises as the blow comes (FOE_GLOW_BEAT / (left + FOE_GLOW_LEAD)).
	phase := FOE_GLOW_BEAT*f32(math.ln(f64(span+FOE_GLOW_LEAD)/f64(left+FOE_GLOW_LEAD)))
	pulse := 0.5-0.5*math.cos(2*math.PI*phase)
	return (FOE_GLOW_DIM+FOE_GLOW_GROWN*grown*grown)*(0.55+0.45*pulse)
}

// Once a frame, with the room: each acting foe's glow; those done fade out.
@(private)
update_foe_glows :: proc(renderer: ^Renderer, room: ^game.Room) {
	g := &renderer.tactical.foe_glow
	now := renderer.sprite_assets.elapsed
	step := f32(clamp(now-g.at, 0, 0.1))
	g.at = now
	before := g.glows
	count := g.count
	g.count = 0
	if room == nil { return }
	for &foe in room.enemies {
		if g.count == len(g.glows) { break }
		if game.enemy_is_out_of_play(room, foe.id) { continue }
		color, glows := foe_glow_color(foe.intent.kind)
		if !glows { continue }
		left := game.tactical_enemy_seconds(room, &foe)
		g.glows[g.count] = {entity = game.enemy_entity(foe.id), color = color,
			amount = foe_glow_amount(left, game.tactical_enemy_intent_seconds(&foe))}
		g.count += 1
	}
	// The glows gone this frame fade out.
	for old in before[:count] {
		if g.count == len(g.glows) { break }
		if old.amount <= 0 { continue }
		kept := false
		for glow in g.glows[:g.count] { kept = kept || glow.entity == old.entity }
		if kept { continue }
		g.glows[g.count] = {entity = old.entity, color = old.color, amount = max(old.amount-step/FOE_GLOW_FADE, 0)}
		g.count += 1
	}
}

// The glow of `entity` now (0 when none).
foe_glow :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (color: rl.Color, amount: f32) {
	g := &renderer.tactical.foe_glow
	for glow in g.glows[:g.count] {
		if glow.entity == entity { return glow.color, glow.amount }
	}
	return
}

// A colour `amount` of the way from `from` to `to`.
@(private)
foe_glow_mix :: proc(from, to: rl.Color, amount: f32) -> rl.Color {
	a := clamp(amount, 0, 1)
	mix :: proc(x, y: u8, a: f32) -> u8 { return u8(f32(x)+(f32(y)-f32(x))*a) }
	return {mix(from.r, to.r, a), mix(from.g, to.g, a), mix(from.b, to.b, a), from.a}
}
