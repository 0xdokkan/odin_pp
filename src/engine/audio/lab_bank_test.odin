package audio

import "core:c"
import "core:testing"
import rl "vendor:raylib"

// Every embedded lab sound decodes as the build made it: 44.1 kHz mono,
// never silent, a one-shot within a few seconds and the ambience exactly
// its 24-second loop. (Decoding needs no audio device.)
@(test)
test_lab_sounds_decode :: proc(t: ^testing.T) {
	rl.SetTraceLogLevel(.WARNING)
	for sfx in Lab_Sfx {
		bytes := LAB_SFX_OGG[sfx]
		testing.expectf(t, len(bytes) > 1000, "%v is not embedded", sfx)
		wave := rl.LoadWaveFromMemory(".ogg", raw_data(bytes), c.int(len(bytes)))
		defer rl.UnloadWave(wave)
		if !testing.expectf(t, wave.data != nil, "%v does not decode", sfx) { continue }
		testing.expectf(t, wave.sampleRate == 44100 && wave.channels == 1, "%v: %d Hz, %d channels", sfx, wave.sampleRate, wave.channels)
		seconds := f32(wave.frameCount)/44100
		if LAB_SFX_LOOP[sfx] {
			testing.expectf(t, wave.frameCount == 24*44100, "%v loops over %d frames", sfx, wave.frameCount)
		} else {
			testing.expectf(t, seconds > 0.1 && seconds < 3.5, "%v lasts %.2f s", sfx, seconds)
		}
		rl.WaveFormat(&wave, 44100, 16, 1)
		peak := 0
		for sample in ([^]i16)(wave.data)[:wave.frameCount] { peak = max(peak, abs(int(sample))) }
		testing.expectf(t, peak > 1000, "%v is silent (peak %d)", sfx, peak)
	}
}

// Without an audio device the lab's bank stays empty and every call is a
// harmless no-op.
@(test)
test_lab_bank_without_a_device_is_silent :: proc(t: ^testing.T) {
	if rl.IsAudioDeviceReady() { return }
	bank: Lab_Bank
	testing.expect(t, !lab_bank_load(&bank))
	lab_play(&bank, .Ui_Beat_Tick)
	lab_ambience(&bank, true, .Amb_Crypt_Loop)
	lab_bank_unload(&bank)
	testing.expect(t, !bank.ready && !bank.ambience_on)
}

// The bus limiter holds a pile-up under the ceiling at once and lets go of
// it smoothly.
@(test)
test_lab_limiter_holds_the_ceiling :: proc(t: ^testing.T) {
	lab_limiter_gain = 1
	defer lab_limiter_gain = 1
	buffer: [2*400]f32
	for i in 0..<len(buffer)/2 {
		level := f32(1.4) if i >= 100 && i < 200 else 0.3
		buffer[2*i], buffer[2*i+1] = level, -level
	}
	lab_limiter(&buffer, 400)
	worst: f32
	for sample in buffer { worst = max(worst, abs(sample)) }
	testing.expectf(t, worst <= LAB_LIMIT+1e-5, "peak %v over the ceiling", worst)
	// Quiet before the blast passes untouched; after it the gain recovers
	// a little each frame, never jumping.
	testing.expect(t, abs(buffer[0]-0.3) < 1e-6)
	testing.expect(t, buffer[2*399] > buffer[2*201] && buffer[2*399] < 0.3)
}
