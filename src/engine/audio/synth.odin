// Procedural sound: an sfxr-style effect synthesiser and a tiny chiptune
// sequencer. Generation is pure and deterministic (noise comes from a seeded
// stream), so sounds are tested headless and need no asset files.
package audio

import "core:math"
import rng "../rng"

SAMPLE_RATE :: 22050

Wave_Shape :: enum u8 {
	Square,
	Saw,
	Triangle,
	Sine,
	Noise,
}

Synth_Params :: struct {
	shape:        Wave_Shape,
	// Start frequency in Hz and its change in Hz per second.
	frequency:    f32,
	slide:        f32,
	// Frequency never drops below this (keeps slides audible).
	min_frequency: f32,
	attack:       f32,
	sustain:      f32,
	decay:        f32,
	// Extra level during sustain, 0..1, for a percussive punch.
	punch:        f32,
	duty:         f32, // square only, 0..1
	vibrato_rate: f32,
	vibrato_depth: f32, // fraction of frequency
	// Arpeggio: after `arp_time` seconds the frequency is multiplied once.
	arp_time:     f32,
	arp_multiply: f32,
	volume:       f32,
	seed:         u64,
}

// Renders a mono effect as 16-bit samples. The caller owns the slice.
synth_render :: proc(p: Synth_Params, allocator := context.allocator) -> []i16 {
	total_time := max(p.attack, 0) + max(p.sustain, 0) + max(p.decay, 0)
	count := max(int(total_time*SAMPLE_RATE), 1)
	samples := make([]i16, count, allocator)
	noise := rng.create(p.seed ~ 0xA0D10)
	noise_value := rng.float_signed(&noise)
	phase := f32(0)
	frequency := p.frequency
	arp_done := false
	volume := clamp(p.volume, 0, 1)
	duty := clamp(p.duty, 0.05, 0.95) if p.duty > 0 else 0.5
	for i in 0..<count {
		t := f32(i) / SAMPLE_RATE
		if !arp_done && p.arp_time > 0 && t >= p.arp_time {
			frequency *= p.arp_multiply
			arp_done = true
		}
		frequency = max(frequency+p.slide/SAMPLE_RATE, max(p.min_frequency, 20))
		f := frequency
		if p.vibrato_depth > 0 {
			f *= 1 + p.vibrato_depth*math.sin(2*math.PI*p.vibrato_rate*t)
		}
		previous_phase := phase
		phase += f / SAMPLE_RATE
		phase -= math.floor(phase)
		value: f32
		switch p.shape {
		case .Square:
			value = 1 if phase < duty else -1
		case .Saw:
			value = 2*phase - 1
		case .Triangle:
			value = 4*abs(phase-0.5) - 1
		case .Sine:
			value = math.sin(2 * math.PI * phase)
		case .Noise:
			// New noise value each half period keeps the pitch audible.
			if math.floor(phase*2) != math.floor(previous_phase*2) {
				noise_value = rng.float_signed(&noise)
			}
			value = noise_value
		}
		samples[i] = i16(clamp(value*envelope(p, t)*volume, -1, 1) * 32000)
	}
	return samples
}

@(private)
envelope :: proc "contextless" (p: Synth_Params, t: f32) -> f32 {
	if t < p.attack {
		return t / p.attack
	}
	t2 := t - max(p.attack, 0)
	if t2 < p.sustain {
		return 1 + p.punch*(1-t2/max(p.sustain, 1e-4))
	}
	t3 := t2 - max(p.sustain, 0)
	if p.decay <= 0 {
		return 0
	}
	return max(1-t3/p.decay, 0)
}

// Named effects every minigame can use.
Sfx :: enum u8 {
	Blip,
	Confirm,
	Back,
	Jump,
	Land,
	Coin,
	Power_Up,
	Shoot,
	Laser,
	Hit,
	Hurt,
	Explosion,
	Dash,
	Step,
	Push,
	Win,
	Lose,
}

sfx_params :: proc "contextless" (sfx: Sfx) -> Synth_Params {
	switch sfx {
	case .Blip:
		return {shape = .Square, frequency = 880, sustain = 0.03, decay = 0.04, duty = 0.5, volume = 0.35}
	case .Confirm:
		return {shape = .Square, frequency = 660, sustain = 0.05, decay = 0.12, arp_time = 0.05, arp_multiply = 1.5, volume = 0.4}
	case .Back:
		return {shape = .Square, frequency = 520, sustain = 0.04, decay = 0.1, arp_time = 0.04, arp_multiply = 0.75, volume = 0.35}
	case .Jump:
		return {shape = .Square, frequency = 300, slide = 2400, sustain = 0.08, decay = 0.1, duty = 0.35, volume = 0.35}
	case .Land:
		return {shape = .Noise, frequency = 180, slide = -600, sustain = 0.02, decay = 0.08, volume = 0.3, seed = 2}
	case .Coin:
		return {shape = .Square, frequency = 990, sustain = 0.05, decay = 0.2, punch = 0.4, arp_time = 0.06, arp_multiply = 1.34, volume = 0.35}
	case .Power_Up:
		return {shape = .Square, frequency = 330, slide = 1500, sustain = 0.25, decay = 0.2, vibrato_rate = 14, vibrato_depth = 0.04, volume = 0.35}
	case .Shoot:
		return {shape = .Saw, frequency = 900, slide = -5000, min_frequency = 120, sustain = 0.05, decay = 0.08, punch = 0.5, volume = 0.3}
	case .Laser:
		return {shape = .Square, frequency = 1400, slide = -9000, min_frequency = 200, sustain = 0.06, decay = 0.08, duty = 0.2, volume = 0.3}
	case .Hit:
		return {shape = .Noise, frequency = 900, slide = -3000, sustain = 0.03, decay = 0.1, punch = 0.6, volume = 0.4, seed = 5}
	case .Hurt:
		return {shape = .Saw, frequency = 420, slide = -1600, sustain = 0.06, decay = 0.18, punch = 0.3, volume = 0.4}
	case .Explosion:
		return {shape = .Noise, frequency = 260, slide = -300, min_frequency = 40, sustain = 0.15, decay = 0.5, punch = 0.8, volume = 0.5, seed = 9}
	case .Dash:
		return {shape = .Noise, frequency = 1800, slide = -4000, sustain = 0.04, decay = 0.12, volume = 0.28, seed = 13}
	case .Step:
		return {shape = .Noise, frequency = 500, sustain = 0.01, decay = 0.03, volume = 0.15, seed = 17}
	case .Push:
		return {shape = .Triangle, frequency = 140, slide = -200, sustain = 0.05, decay = 0.08, volume = 0.45}
	case .Win:
		return {shape = .Square, frequency = 523, sustain = 0.3, decay = 0.4, arp_time = 0.15, arp_multiply = 1.5, vibrato_rate = 6, vibrato_depth = 0.02, volume = 0.4}
	case .Lose:
		return {shape = .Saw, frequency = 330, slide = -260, sustain = 0.35, decay = 0.4, vibrato_rate = 5, vibrato_depth = 0.05, volume = 0.4}
	}
	return {}
}

Music_Mood :: enum u8 {
	Menu,
	Action,
	Tense,
	Calm,
}

// One bar per chord; each bar has 8 steps (eighth notes).
@(private)
Mood_Pattern :: struct {
	bpm:   f32,
	roots: [8]f32, // semitone offsets of each bar's chord root
	minor: bool,
	lead:  Wave_Shape,
}

@(private)
mood_pattern :: proc "contextless" (mood: Music_Mood) -> Mood_Pattern {
	switch mood {
	case .Menu:
		return {bpm = 96, roots = {0, -4, -7, -2, 0, -4, -5, -5}, minor = true, lead = .Triangle}
	case .Action:
		return {bpm = 140, roots = {0, 0, -4, -4, -7, -7, -2, -5}, minor = true, lead = .Square}
	case .Tense:
		return {bpm = 120, roots = {0, 1, 0, -1, 0, 1, 3, -1}, minor = true, lead = .Saw}
	case .Calm:
		return {bpm = 84, roots = {0, 5, 7, 5, 0, 5, 7, 7}, minor = false, lead = .Sine}
	}
	return {}
}

// Renders a seamless loop: bass, arpeggio and hi-hat over eight bars.
music_render :: proc(mood: Music_Mood, seed: u64, base_frequency := f32(110), allocator := context.allocator) -> []i16 {
	pattern := mood_pattern(mood)
	step_time := 60 / pattern.bpm / 2
	steps := 8 * 8
	count := int(f32(steps) * step_time * SAMPLE_RATE)
	samples := make([]i16, count, allocator)
	r := rng.create(seed)
	third := f32(3) if pattern.minor else f32(4)
	chord := [3]f32{0, third, 7}
	// Melody choices are fixed per bar so the loop repeats identically.
	arp_order: [8][8]int
	for bar in 0..<8 {
		for s in 0..<8 {
			arp_order[bar][s] = rng.int_range(&r, 0, 2)
		}
	}
	noise := rng.create(seed ~ 0x4A7)
	phases: [3]f32
	for i in 0..<count {
		t := f32(i) / SAMPLE_RATE
		step := min(int(t/step_time), steps-1)
		bar := step / 8
		in_step := t - f32(step)*step_time
		root := pattern.roots[bar]
		bass_f := base_frequency * semitone(root)
		lead_f := base_frequency * 4 * semitone(root+chord[arp_order[bar][step%8]])
		gate := max(1-in_step/step_time, 0)

		phases[0] += bass_f / SAMPLE_RATE
		phases[1] += lead_f / SAMPLE_RATE
		for &ph in phases {
			ph -= math.floor(ph)
		}
		bass := 4*abs(phases[0]-0.5) - 1
		lead := wave_value(pattern.lead, phases[1])
		hat: f32
		if step%2 == 1 && in_step < 0.03 {
			hat = rng.float_signed(&noise) * (1 - in_step/0.03)
		}
		mix := bass*0.35 + lead*0.18*gate + hat*0.12
		samples[i] = i16(clamp(mix, -1, 1) * 26000)
	}
	return samples
}

@(private)
semitone :: proc "contextless" (offset: f32) -> f32 {
	return math.pow(2, offset/12)
}

@(private)
wave_value :: proc "contextless" (shape: Wave_Shape, phase: f32) -> f32 {
	switch shape {
	case .Square:
		return 1 if phase < 0.5 else -1
	case .Saw:
		return 2*phase - 1
	case .Triangle:
		return 4*abs(phase-0.5) - 1
	case .Sine:
		return math.sin(2 * math.PI * phase)
	case .Noise:
		return 0
	}
	return 0
}

// Wraps mono 16-bit samples in a RIFF/WAVE container, so raylib can stream
// them as looping music. The caller owns the bytes.
wav_encode :: proc(samples: []i16, allocator := context.allocator) -> []u8 {
	data_bytes := len(samples) * 2
	out := make([]u8, 44+data_bytes, allocator)
	put_tag :: proc(b: []u8, at: int, tag: string) {
		copy(b[at:at+4], tag)
	}
	put_u32 :: proc(b: []u8, at: int, v: u32) {
		b[at] = u8(v)
		b[at+1] = u8(v >> 8)
		b[at+2] = u8(v >> 16)
		b[at+3] = u8(v >> 24)
	}
	put_u16 :: proc(b: []u8, at: int, v: u16) {
		b[at] = u8(v)
		b[at+1] = u8(v >> 8)
	}
	put_tag(out, 0, "RIFF")
	put_u32(out, 4, u32(36+data_bytes))
	put_tag(out, 8, "WAVE")
	put_tag(out, 12, "fmt ")
	put_u32(out, 16, 16)
	put_u16(out, 20, 1) // PCM
	put_u16(out, 22, 1) // mono
	put_u32(out, 24, SAMPLE_RATE)
	put_u32(out, 28, SAMPLE_RATE*2)
	put_u16(out, 32, 2)
	put_u16(out, 34, 16)
	put_tag(out, 36, "data")
	put_u32(out, 40, u32(data_bytes))
	for s, i in samples {
		put_u16(out, 44+i*2, u16(s))
	}
	return out
}
