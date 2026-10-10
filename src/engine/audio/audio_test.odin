package audio

import "core:testing"

@(test)
test_every_effect_renders_bounded_non_silent_samples :: proc(t: ^testing.T) {
	for sfx in Sfx {
		samples := synth_render(sfx_params(sfx))
		defer delete(samples)
		testing.expectf(t, len(samples) > 100, "%v too short", sfx)
		peak := 0
		for s in samples {
			peak = max(peak, abs(int(s)))
		}
		testing.expectf(t, peak > 1000 && peak <= 32767, "%v peak %v", sfx, peak)
	}
}

@(test)
test_synthesis_is_deterministic :: proc(t: ^testing.T) {
	a := synth_render(sfx_params(.Explosion))
	defer delete(a)
	b := synth_render(sfx_params(.Explosion))
	defer delete(b)
	testing.expect_value(t, len(a), len(b))
	for i in 0..<len(a) {
		if a[i] != b[i] {
			testing.fail_now(t, "noise differs between renders")
		}
	}
}

@(test)
test_music_loop_and_wav_header :: proc(t: ^testing.T) {
	samples := music_render(.Action, 3)
	defer delete(samples)
	testing.expect(t, len(samples) > SAMPLE_RATE) // several seconds
	bytes := wav_encode(samples)
	defer delete(bytes)
	testing.expect_value(t, string(bytes[0:4]), "RIFF")
	testing.expect_value(t, string(bytes[8:12]), "WAVE")
	testing.expect_value(t, string(bytes[36:40]), "data")
	testing.expect_value(t, len(bytes), 44+len(samples)*2)
}

@(test)
test_bank_calls_are_safe_without_device :: proc(t: ^testing.T) {
	b: Bank
	play(&b, .Coin)
	play_music(&b, .Menu)
	bank_update(&b)
	stop_music(&b)
	set_muted(&b, true)
	play(nil, .Coin)
	testing.expect(t, !b.music_playing)
}
