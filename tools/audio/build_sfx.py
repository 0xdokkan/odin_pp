"""Builds the game's procedural sound effects (the mechanics lab's sounds).

    PY="C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe"
    "$PY" tools/audio/build_sfx.py [options]

Options
  --only A[,B]     only these families (sfx_<family>.py) or sound names;
                   does not rewrite the Odin table
  --preview DIR    per sound: a spectrogram PNG (with its animation marks), the
                   WAV and its measurements in report.json; per family a reel
                   (every sound in turn, 0.6 s apart)
  --no-write       leave assets/ and src/ alone (with --preview)

Outputs
  assets/audio/lab/<name>.ogg            Ogg Vorbis, 44.1 kHz mono, 192 kbit/s
  src/engine/audio/lab_sfx_data.odin     the Lab_Sfx table (generated)

The masters are 16-bit WAVs; the game carries them as Vorbis (a third of the
size, and raylib decodes it to the very sample). Blender's audio module does
the encoding (encode_ogg.py): BLENDER names blender.exe when it is not the one
this Python came with.
"""
import glob
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp  # noqa: E402
from registry import SOUNDS  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "lab")
ODIN_OUT = os.path.join(ROOT, "src", "engine", "audio", "lab_sfx_data.odin")
OGG_BITRATE = 192000


def args():
    argv = sys.argv[1:]
    opts = {"only": None, "preview": None, "write": True}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            opts["only"] = set(argv[i + 1].split(","))
            i += 1
        elif a == "--preview":
            opts["preview"] = argv[i + 1]
            i += 1
        elif a == "--no-write":
            opts["write"] = False
        i += 1
    return opts


def load_families():
    for path in sorted(glob.glob(os.path.join(HERE, "sfx_*.py"))):
        importlib.import_module(os.path.splitext(os.path.basename(path))[0])


def family_of(entry):
    return entry["module"][len("sfx_"):] if entry["module"].startswith("sfx_") else entry["module"]


def master(name, entry):
    seed = zlib.crc32(name.encode()) & 0x7FFFFFFF
    dry = np.asarray(entry["fn"](seed), dtype=float)
    if dry.ndim != 1 or not len(dry) or not np.all(np.isfinite(dry)):
        raise ValueError("%s: the recipe must return a finite mono array" % name)
    if entry["loop"]:
        # A seamless loop: the hall's tail wraps around onto the start.
        ir = dsp.room_ir(entry["rt60"])
        wet = dsp.convolve(dry, ir)
        folded = np.zeros(len(dry))
        for start in range(0, len(wet), len(dry)):
            part = wet[start:start + len(dry)]
            folded[:len(part)] += part
        rms_dry = np.sqrt(np.mean(dry ** 2)) + 1e-12
        rms_wet = np.sqrt(np.mean(folded ** 2)) + 1e-12
        x = dry + entry["wet"] * folded * (rms_dry / rms_wet)
        x = dsp.highpass(x - np.mean(x), 25, 1)
    else:
        # A recipe may stop while something still rings: never on a click.
        dry = dsp.fade(dry, 0.0, 0.006)
        x = dsp.hall(dry, entry["wet"], entry["rt60"])
        x = dsp.remove_dc(x)
        x = dsp.trim_tail(x)
    return dsp.normalize_loudness(x, entry["loudness"])


def blender_exe():
    if os.environ.get("BLENDER"):
        return os.environ["BLENDER"]
    # <blender>/<version>/python/bin/python.exe
    here = os.path.dirname(os.path.abspath(sys.executable))
    guess = os.path.normpath(os.path.join(here, "..", "..", "..", "blender.exe"))
    if os.path.exists(guess):
        return guess
    raise SystemExit("set BLENDER to blender.exe (it encodes the Vorbis files)")


def _ogg_crc_table():
    table = []
    for index in range(256):
        crc = index << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
        table.append(crc)
    return table


OGG_CRC_TABLE = _ogg_crc_table()


def ogg_crc(page):
    """The Ogg page checksum (CRC-32, polynomial 0x04C11DB7, not reflected)."""
    crc = 0
    for byte in page:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ OGG_CRC_TABLE[(crc >> 24) ^ byte]
    return crc


def fix_ogg_serial(path, serial):
    """The muxer picks a random stream serial: a fixed one per sound keeps a
    rebuild of unchanged recipes byte for byte the same."""
    data = bytearray(open(path, "rb").read())
    at = 0
    while at < len(data):
        if data[at:at + 4] != b"OggS":
            raise ValueError("%s: not an Ogg page at %d" % (path, at))
        segments = data[at + 26]
        size = 27 + segments + sum(data[at + 27:at + 27 + segments])
        data[at + 14:at + 18] = serial.to_bytes(4, "little")
        data[at + 22:at + 26] = bytes(4)
        data[at + 22:at + 26] = ogg_crc(data[at:at + size]).to_bytes(4, "little")
        at += size
    with open(path, "wb") as f:
        f.write(data)


def encode_ogg(masters):
    """masters: {name: mastered float array}. Writes OUT_DIR/<name>.ogg."""
    work = tempfile.mkdtemp(prefix="odin_pp_sfx_")
    try:
        for name, x in masters.items():
            dsp.write_wav(os.path.join(work, name + ".wav"), x)
        os.makedirs(OUT_DIR, exist_ok=True)
        done = subprocess.run([blender_exe(), "-b", "--factory-startup", "--python", os.path.join(HERE, "encode_ogg.py"),
                               "--", work, OUT_DIR, str(OGG_BITRATE)], capture_output=True, text=True)
        if "ENCODED %d" % len(masters) not in done.stdout:
            raise SystemExit("Vorbis encoding failed: " + done.stdout[-2000:] + done.stderr[-2000:])
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for name in masters:
        fix_ogg_serial(os.path.join(OUT_DIR, name + ".ogg"), zlib.crc32(name.encode()) & 0x7FFFFFFF)


def odin_name(name):
    return "_".join(part.capitalize() for part in name.split("_"))


def write_odin(names):
    lines = [
        "// Generated by tools/audio/build_sfx.py. Do not edit by hand: change the",
        "// recipes in tools/audio/sfx_*.py and rebuild (see tools/audio/SOUND_SPEC.md).",
        "package audio",
        "",
        "// The mechanics lab's procedural sound effects: every action of every",
        "// character, every card and the room itself (lab_sounds.odin plays them).",
        "Lab_Sfx :: enum u16 {",
    ]
    lines += ["\t%s," % odin_name(n) for n in names]
    lines += ["}", "", "// Ogg Vorbis files (lab_bank.odin decodes them).", "@(rodata)", "LAB_SFX_OGG := [Lab_Sfx][]u8{"]
    lines += ["\t.%s = #load(\"../../../assets/audio/lab/%s.ogg\")," % (odin_name(n), n) for n in names]
    lines += ["}", "", "// Seamless loops (the room's ambience).", "@(rodata)", "LAB_SFX_LOOP := #partial [Lab_Sfx]bool{"]
    lines += ["\t.%s = true," % odin_name(n) for n in names if SOUNDS[n]["loop"]]
    lines += ["}", ""]
    with open(ODIN_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    opts = args()
    load_families()
    names = sorted(SOUNDS)
    chosen = [n for n in names if opts["only"] is None or n in opts["only"] or family_of(SOUNDS[n]) in opts["only"]]
    if not chosen:
        raise SystemExit("no sound matches --only")
    report = {}
    reels = {}
    masters = {}
    for name in chosen:
        entry = SOUNDS[name]
        x = master(name, entry)
        facts = dsp.analyze(x)
        facts["family"] = family_of(entry)
        facts["target_loudness"] = entry["loudness"]
        facts["marks_ms"] = [round(m * 1000) for m in entry["marks"]]
        report[name] = facts
        print("%-28s %5d ms  peak %6.1f  loud %6.1f  centroid %5d Hz" % (
            name, facts["duration_ms"], facts["peak_dbfs"], facts["loudness_db"], facts["centroid_hz"]))
        if opts["write"]:
            masters[name] = x
        if opts["preview"]:
            dsp.write_wav(os.path.join(opts["preview"], name + ".wav"), x)
            dsp.spectrogram_png(os.path.join(opts["preview"], name + ".png"), x, marks=entry["marks"])
            reels.setdefault(facts["family"], []).append(x)
    if opts["preview"]:
        for family, sounds in reels.items():
            gap = dsp.silence(0.6)
            reel = np.concatenate([np.concatenate([s, gap]) for s in sounds])
            dsp.write_wav(os.path.join(opts["preview"], "reel_%s.wav" % family), reel)
        path = os.path.join(opts["preview"], "report.json")
        old = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                old = json.load(f)
        old.update(report)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(old, f, indent=1, sort_keys=True)
    if masters:
        encode_ogg(masters)
    if opts["write"] and opts["only"] is None:
        # Sounds no recipe makes any more are removed with the table.
        for path in glob.glob(os.path.join(OUT_DIR, "*.*")):
            stem, ext = os.path.splitext(os.path.basename(path))
            if ext != ".ogg" or stem not in SOUNDS:
                os.remove(path)
        write_odin(names)
        print("WROTE", ODIN_OUT)
    print("DONE", len(chosen))


if __name__ == "__main__":
    main()
