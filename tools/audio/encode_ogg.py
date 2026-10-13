"""Encodes mastered WAVs as Ogg Vorbis; build_sfx.py runs it inside Blender.

    blender -b --factory-startup --python encode_ogg.py -- WAV_DIR OUT_DIR BITRATE

Blender's audio module (aud, FFmpeg underneath) is the one Vorbis encoder at
hand without installing anything. Every WAV in WAV_DIR becomes OUT_DIR/<name>.ogg,
44.1 kHz mono at BITRATE bits per second, exactly as long as the WAV.
"""
import os
import sys

import aud

argv = sys.argv[sys.argv.index("--") + 1:]
wav_dir, out_dir, bitrate = argv[0], argv[1], int(argv[2])
count = 0
for entry in sorted(os.listdir(wav_dir)):
    if not entry.endswith(".wav"):
        continue
    sound = aud.Sound(os.path.join(wav_dir, entry))
    target = os.path.join(out_dir, entry[:-len(".wav")] + ".ogg")
    sound.write(target, 44100, aud.CHANNELS_MONO, aud.FORMAT_FLOAT32, aud.CONTAINER_OGG, aud.CODEC_VORBIS, bitrate)
    count += 1
print("ENCODED", count)
