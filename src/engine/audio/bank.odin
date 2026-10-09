package audio

import "core:c"
import rl "vendor:raylib"

// Voices per effect: overlapping plays rotate through aliases instead of
// restarting the same sound.
VOICES :: 4

// Owns the generated effects and the current music loop. Every call is a no-op
// when the audio device could not be opened, so games never branch on it.
Bank :: struct {
	ready:         bool,
	sounds:        [Sfx][VOICES]rl.Sound,
	next_voice:    [Sfx]int,
	master:        f32,
	sfx_volume:    f32,
	music_volume:  f32,
	muted:         bool,
	music:         rl.Music,
	music_bytes:   []u8,
	music_mood:    Music_Mood,
	music_playing: bool,
}

bank_create :: proc() -> ^Bank {
	b := new(Bank)
	b.master = 0.8
	b.sfx_volume = 1
	b.music_volume = 0.45
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		return b
	}
	b.ready = true
	for sfx in Sfx {
		samples := synth_render(sfx_params(sfx), context.temp_allocator)
		wave := rl.Wave{
			frameCount = c.uint(len(samples)),
			sampleRate = SAMPLE_RATE,
			sampleSize = 16,
			channels   = 1,
			data       = raw_data(samples),
		}
		// LoadSoundFromWave copies the samples into the audio buffer.
		base := rl.LoadSoundFromWave(wave)
		b.sounds[sfx][0] = base
		for v in 1..<VOICES {
			b.sounds[sfx][v] = rl.LoadSoundAlias(base)
		}
	}
	rl.SetMasterVolume(b.master)
	return b
}

bank_destroy :: proc(b: ^Bank) {
	if b == nil {
		return
	}
	if b.ready {
		stop_music(b)
		for sfx in Sfx {
			for v in 1..<VOICES {
				rl.UnloadSoundAlias(b.sounds[sfx][v])
			}
			rl.UnloadSound(b.sounds[sfx][0])
		}
		rl.CloseAudioDevice()
	}
	free(b)
}

// pitch varies the effect (1 = original); volume scales the effect level.
play :: proc(b: ^Bank, sfx: Sfx, volume := f32(1), pitch := f32(1)) {
	if b == nil || !b.ready || b.muted {
		return
	}
	voice := b.next_voice[sfx]
	b.next_voice[sfx] = (voice + 1) % VOICES
	s := b.sounds[sfx][voice]
	rl.SetSoundVolume(s, clamp(volume*b.sfx_volume, 0, 1))
	rl.SetSoundPitch(s, clamp(pitch, 0.25, 4))
	rl.PlaySound(s)
}

// Starts (or keeps) a looping procedural track for the given mood.
play_music :: proc(b: ^Bank, mood: Music_Mood, seed: u64 = 1) {
	if b == nil || !b.ready {
		return
	}
	if b.music_playing && b.music_mood == mood {
		return
	}
	stop_music(b)
	samples := music_render(mood, seed, allocator = context.temp_allocator)
	b.music_bytes = wav_encode(samples)
	b.music = rl.LoadMusicStreamFromMemory(".wav", raw_data(b.music_bytes), c.int(len(b.music_bytes)))
	if !rl.IsMusicValid(b.music) {
		delete(b.music_bytes)
		b.music_bytes = nil
		return
	}
	b.music.looping = true
	b.music_mood = mood
	b.music_playing = true
	rl.SetMusicVolume(b.music, 0 if b.muted else b.music_volume)
	rl.PlayMusicStream(b.music)
}

stop_music :: proc(b: ^Bank) {
	if b == nil || !b.music_playing {
		return
	}
	rl.StopMusicStream(b.music)
	rl.UnloadMusicStream(b.music)
	// The stream decodes from the WAV bytes, so they live until unloading.
	delete(b.music_bytes)
	b.music_bytes = nil
	b.music_playing = false
}

// Must run every frame while music plays, to refill the stream buffers.
bank_update :: proc(b: ^Bank) {
	if b == nil || !b.ready || !b.music_playing {
		return
	}
	rl.UpdateMusicStream(b.music)
}

set_muted :: proc(b: ^Bank, muted: bool) {
	if b == nil {
		return
	}
	b.muted = muted
	if b.ready && b.music_playing {
		rl.SetMusicVolume(b.music, 0 if muted else b.music_volume)
	}
}

set_master_volume :: proc(b: ^Bank, volume: f32) {
	if b == nil {
		return
	}
	b.master = clamp(volume, 0, 1)
	if b.ready {
		rl.SetMasterVolume(b.master)
	}
}
