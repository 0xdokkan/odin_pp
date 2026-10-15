"""Where sound recipes register themselves (see SOUND_SPEC.md).

A family module (sfx_<family>.py) decorates one function per sound:

    from registry import sound

    @sound("ghoul_attack", loudness=-18, wet=0.22, marks=(0.06, 0.118, 0.243))
    def ghoul_attack(seed):
        ...            # build and return a dry mono float array (dsp.SR)

`seed` is fixed per sound name, so a build is reproducible; derive every
random choice from it (seed+1, seed+2...). The build adds the stone hall
(`wet`, `rt60`), removes DC, trims the silent tail and normalizes to
`loudness` (dB, dsp.loudness_db). `marks` are the animation moments (s) the
sound is built to land on; previews draw them. `loop` keeps the length exact
and skips trimming (seamless loops).
"""

SOUNDS = {}


def sound(name, loudness, wet=0.2, rt60=1.6, marks=(), loop=False, note=""):
    def register(fn):
        if name in SOUNDS:
            raise ValueError("sound %s registered twice" % name)
        SOUNDS[name] = {"fn": fn, "loudness": loudness, "wet": wet, "rt60": rt60,
                        "marks": tuple(marks), "loop": loop, "note": note,
                        "module": fn.__module__}
        return fn
    return register
