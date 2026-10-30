"""Encodes a stereo music master as Ogg Vorbis, inside Blender (its audio
module, aud, is the Vorbis encoder at hand, as in encode_ogg.py).

    blender -b --factory-startup --python tools/audio/encode_music.py -- IN.wav OUT.ogg [BITRATE]

The FIRST PERSON BRAWLER's loop (docs/piano-prima-persona.md, Fase 3):

    "$PY" tools/audio/music_brawler.py SCRATCH
    blender -b --factory-startup --python tools/audio/encode_music.py -- SCRATCH/music_brawler.wav assets/audio/music/brawler.ogg

44.1 kHz stereo at BITRATE bits per second (192 kbit/s if not given), exactly
as long as the WAV, so the loop stays seamless.
"""
import sys

import aud

argv = sys.argv[sys.argv.index("--") + 1:]
source, target = argv[0], argv[1]
bitrate = int(argv[2]) if len(argv) > 2 else 192000
sound = aud.Sound(source)
sound.write(target, 44100, aud.CHANNELS_STEREO, aud.FORMAT_FLOAT32, aud.CONTAINER_OGG, aud.CODEC_VORBIS, bitrate)
print("ENCODED", target)
