package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"

// A foe's glow (foe_glow.odin): red for a blow, a charge; purple for a shield
// and a bomb (the user's choice); none for a step, a wait, a recovery. It grows
// as the blow comes, never dark while acting, its brightest and steady over
// the last FOE_GLOW_PEAK seconds; its pulses come faster as the blow comes.
@(test)
test_foe_glow_grows_to_the_blow :: proc(t: ^testing.T) {
	for kind in game.Enemy_Intent_Kind {
		color, glows := foe_glow_color(kind)
		#partial switch kind {
		case .Attack, .Charge: testing.expectf(t, glows && color == FOE_GLOW_RED, "%v is not red", kind)
		case .Protect, .Bombard: testing.expectf(t, glows && color == FOE_GLOW_PURPLE, "%v is not purple", kind)
		case: testing.expectf(t, !glows, "%v glows", kind)
		}
	}
	total := f32(4)
	// Its envelope (the pulses' tops) grows; it is never dark.
	last := f32(0)
	for step in 0..=39 {
		left := total-f32(step)*0.1
		amount := foe_glow_amount(left, total)
		testing.expectf(t, amount > 0.15 && amount <= 1, "%f s left: %f", left, amount)
		top := (FOE_GLOW_DIM+FOE_GLOW_GROWN*(1-(left-FOE_GLOW_PEAK)/(total-FOE_GLOW_PEAK))*(1-(left-FOE_GLOW_PEAK)/(total-FOE_GLOW_PEAK)))
		if left > FOE_GLOW_PEAK {
			testing.expectf(t, amount <= top+1e-4 && top >= last-1e-4, "%f s left: %f over its top %f", left, amount, top)
			last = top
		}
	}
	for left in ([?]f32{0.25, 0.2, 0.1, 0}) { testing.expect_value(t, foe_glow_amount(left, total), f32(1)) }
	// More pulses in the last second than in the first (each pulse its light
	// over the halfway between its envelope's dim and bright).
	count :: proc(from, to, total: f32) -> int {
		n, up := 0, false
		for k in 0..<400 {
			left := from+(to-from)*f32(k)/400
			grown := 1-(left-FOE_GLOW_PEAK)/(total-FOE_GLOW_PEAK)
			high := foe_glow_amount(left, total)/(FOE_GLOW_DIM+FOE_GLOW_GROWN*grown*grown) > 0.775
			if high && !up { n += 1 }
			up = high
		}
		return n
	}
	testing.expect(t, count(1.25, 0.26, total) > count(4, 3, total), "the pulses do not quicken")
	testing.expect(t, foe_glow_mix(rl.WHITE, FOE_GLOW_RED, 1) == FOE_GLOW_RED && foe_glow_mix(rl.WHITE, FOE_GLOW_RED, 0) == rl.WHITE)
}
