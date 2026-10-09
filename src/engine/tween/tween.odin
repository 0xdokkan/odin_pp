// Easing curves and frame-rate independent smoothing. One implementation
// replaces the smoothstep copies scattered through the renderer.
package tween

import "core:math"

Ease :: enum u8 {
	Linear,
	Smoothstep,
	In_Quad,
	Out_Quad,
	In_Out_Quad,
	In_Cubic,
	Out_Cubic,
	In_Out_Cubic,
	In_Sine,
	Out_Sine,
	In_Out_Sine,
	In_Expo,
	Out_Expo,
	In_Back,
	Out_Back,
	Out_Elastic,
	Out_Bounce,
}

// Maps progress t in [0, 1] (clamped) through the curve. Every curve starts at
// 0 and ends at 1; Back and Elastic overshoot in between.
ease :: proc "contextless" (kind: Ease, t: f32) -> f32 {
	x := clamp(t, 0, 1)
	switch kind {
	case .Linear:
		return x
	case .Smoothstep:
		return smoothstep(x)
	case .In_Quad:
		return x * x
	case .Out_Quad:
		return 1 - (1-x)*(1-x)
	case .In_Out_Quad:
		return 2*x*x if x < 0.5 else 1 - (-2*x+2)*(-2*x+2)/2
	case .In_Cubic:
		return x * x * x
	case .Out_Cubic:
		u := 1 - x
		return 1 - u*u*u
	case .In_Out_Cubic:
		if x < 0.5 {
			return 4 * x * x * x
		}
		u := -2*x + 2
		return 1 - u*u*u/2
	case .In_Sine:
		return 1 - math.cos(x*math.PI/2)
	case .Out_Sine:
		return math.sin(x * math.PI / 2)
	case .In_Out_Sine:
		return -(math.cos(math.PI*x) - 1) / 2
	case .In_Expo:
		return 0 if x == 0 else math.pow(2, 10*x-10)
	case .Out_Expo:
		return 1 if x == 1 else 1 - math.pow(2, -10*x)
	case .In_Back:
		c1 :: f32(1.70158)
		c3 :: c1 + 1
		return c3*x*x*x - c1*x*x
	case .Out_Back:
		c1 :: f32(1.70158)
		c3 :: c1 + 1
		u := x - 1
		return 1 + c3*u*u*u + c1*u*u
	case .Out_Elastic:
		if x == 0 || x == 1 {
			return x
		}
		c4 :: f32(2 * math.PI / 3)
		return math.pow(2, -10*x)*math.sin((x*10-0.75)*c4) + 1
	case .Out_Bounce:
		return out_bounce(x)
	}
	return x
}

// Hermite smoothstep without clamping: callers that already keep t in [0, 1]
// share one definition (the renderer had seven copies).
smoothstep :: proc "contextless" (t: f32) -> f32 {
	return t * t * (3 - 2*t)
}

@(private)
out_bounce :: proc "contextless" (x: f32) -> f32 {
	n1 :: f32(7.5625)
	d1 :: f32(2.75)
	if x < 1/d1 {
		return n1 * x * x
	} else if x < 2/d1 {
		u := x - 1.5/d1
		return n1*u*u + 0.75
	} else if x < 2.5/d1 {
		u := x - 2.25/d1
		return n1*u*u + 0.9375
	}
	u := x - 2.625/d1
	return n1*u*u + 0.984375
}

lerp :: proc "contextless" (a, b: $T, t: f32) -> T {
	return a + (b-a)*t
}

// 0 when value == a, 1 when value == b; unclamped.
inverse_lerp :: proc "contextless" (a, b, value: f32) -> f32 {
	if a == b {
		return 0
	}
	return (value - a) / (b - a)
}

remap :: proc "contextless" (value, in_a, in_b, out_a, out_b: f32) -> f32 {
	return lerp(out_a, out_b, inverse_lerp(in_a, in_b, value))
}

// Moves toward target by at most max_delta, never overshooting.
approach :: proc "contextless" (current, target, max_delta: f32) -> f32 {
	if current < target {
		return min(current+max_delta, target)
	}
	return max(current-max_delta, target)
}

// Exponential smoothing that behaves the same at 30 or 240 fps. `rate` is the
// fraction of the gap closed per second, expressed as a decay constant.
damp :: proc "contextless" (current, target: $T, rate, dt: f32) -> T {
	return lerp(current, target, 1-math.exp(-rate*dt))
}

// Value animated from `from` to `to` over `duration` seconds.
Tween :: struct($T: typeid) {
	from, to: T,
	duration: f32,
	elapsed:  f32,
	curve:    Ease,
}

make_tween :: proc(from, to: $T, duration: f32, curve := Ease.Out_Cubic) -> Tween(T) {
	return Tween(T){from = from, to = to, duration = duration, curve = curve}
}

tween_update :: proc(tw: ^Tween($T), dt: f32) -> T {
	tw.elapsed = min(tw.elapsed+dt, tw.duration)
	return tween_value(tw^)
}

tween_value :: proc(tw: Tween($T)) -> T {
	if tw.duration <= 0 {
		return tw.to
	}
	return lerp(tw.from, tw.to, ease(tw.curve, tw.elapsed/tw.duration))
}

tween_done :: proc(tw: Tween($T)) -> bool {
	return tw.elapsed >= tw.duration
}

// Ping-pong wave in [0, 1] with the given period, for pulses and bobbing.
pulse01 :: proc "contextless" (time, period: f32) -> f32 {
	if period <= 0 {
		return 0
	}
	return 0.5 - 0.5*math.cos(2*math.PI*time/period)
}
