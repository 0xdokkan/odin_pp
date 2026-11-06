#!/usr/bin/env python3
"""Fase 0: copie isolate, compilazioni separate, corse seriali e prove grezze.

Solo libreria standard Python. Non modifica sorgenti del gioco o profili utente.
Eseguire prepare, build, run in quest'ordine; run non compila mai.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
SCALES = (1, 2, 4, 8)
BASE_STAGES = (0, 25, 26, 39, 40, 63, 88, 195, 196, 197)
SCALE_STAGES = (0, 25, 26)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_text(args):
    return subprocess.check_output(args, cwd=REPO, text=True).strip()


def prepare(output, odin):
    output.mkdir(parents=True, exist_ok=False)
    (output / "logs").mkdir()
    (output / "bin").mkdir()
    manifest = {
        "schema": 1, "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "commit": command_text(["git", "rev-parse", "HEAD"]),
        "platform": platform.platform(), "machine": platform.machine(),
        "python": sys.version, "odin": command_text([odin, "version"]),
        "seed": 42, "source_hashes": {},
        "limits": ["Nessuna misura Windows se eseguito su Mac", "RSS distinto da heap e GPU",
                   "Stesso stage a scala diversa non garantisce geometria visibile identica"],
    }
    (output / "source.patch").write_text(command_text(["git", "diff", "--", "src"]), encoding="utf-8")
    for scale in SCALES:
        destination = output / f"scale-{scale}"
        for folder in ("src", "assets", "tools/moonshot/probe"):
            shutil.copytree(REPO / folder, destination / folder)
        # Patch deliberatamente confinata alle copie, lasciando intatti i guardrail.
        path = destination / "src/expedition/world.odin"
        source = path.read_text(encoding="utf-8")
        original = "return legacy_map_size(b)*2 }"
        if source.count(original) != 1:
            raise RuntimeError("map_size cambiato: controllare la patch di scala prima di misurare")
        path.write_text(source.replace(original, f"return legacy_map_size(b)*2*{scale} }}"), encoding="utf-8")
        for folder in ("src", "assets", "tools/moonshot/probe"):
            for f in sorted((destination / folder).rglob("*")):
                if f.is_file():
                    manifest["source_hashes"][str(f.relative_to(output))] = sha(f)
    write_json(output / "manifest.json", manifest)


def cases():
    result = []
    for scale in SCALES:
        for optimization in ("none", "speed"):
            result.append(dict(id=f"headless-{scale}-{optimization}", group="headless",
                               scale=scale, optimization=optimization))
    for optimization in ("none", "speed"):
        result.append(dict(id=f"baseline-{optimization}", group="graphics", scale=1,
                           optimization=optimization, stages=BASE_STAGES, walk_samples=240))
    for scale in (2, 4, 8):
        result.append(dict(id=f"scale-{scale}-speed", group="graphics", scale=scale,
                           optimization="speed", stages=SCALE_STAGES, walk_samples=1200))
    return result


def selected(group, case_filter):
    return [c for c in cases() if (group == "all" or c["group"] == group)
            and (not case_filter or c["id"] in case_filter.split(","))]


def execute(args, cwd, log, timeout):
    started = time.monotonic()
    # Variabili degli smoke non ereditate: potrebbero cambiare scene e salvataggi.
    env = {k: v for k, v in os.environ.items() if not k.startswith("ODIN_PP_")}
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(args, cwd=cwd, env=env, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=os.name != "nt")
        try:
            process.wait(timeout=timeout)
            result = dict(exit_code=process.returncode, timeout=False)
        except subprocess.TimeoutExpired:
            # Uccidere anche il figlio del wrapper time; nessun gioco rimane aperto dopo timeout.
            if os.name == "nt":
                process.kill()
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            result = dict(exit_code=None, timeout=True)
    result.update(command=[str(a) for a in args], cwd=str(cwd), log=str(log), timeout_seconds=timeout,
                  elapsed_seconds=time.monotonic() - started)
    return result


def binary(output, case):
    return output / "bin" / (case["id"] + (".exe" if os.name == "nt" else ""))


def build(output, odin, selection):
    manifest = json.loads((output / "manifest.json").read_text())
    compiler_version = command_text([odin, "version"])
    if compiler_version != manifest["odin"]:
        raise RuntimeError("Compilatore diverso dalla preparazione: creare una nuova sessione")
    selected_scales = {f"scale-{case['scale']}" for case in selection}
    for relative, expected in manifest["source_hashes"].items():
        if Path(relative).parts[0] in selected_scales and sha(output / relative) != expected:
            raise RuntimeError("Copia modificata dopo prepare: " + relative)
    for case in selection:
        source = output / f"scale-{case['scale']}"
        package = "src" if case["group"] == "graphics" else "tools/moonshot/probe"
        args = [odin, "build", str(source / package), f"-o:{case['optimization']}",
                "-out:" + str(binary(output, case)), "-define:MOONSHOT_SCALE=" + str(case["scale"])]
        if case["group"] == "graphics":
            stages = "," + ",".join(map(str, case["stages"])) + ","
            args += ["-define:EXPEDITION_BENCHMARK=true", "-define:EXPEDITION_BENCHMARK_CSV=true",
                     "-define:EXPEDITION_BENCHMARK_FIXED_DT=true",
                     "-define:EXPEDITION_BENCHMARK_STAGES=" + stages,
                     "-define:EXPEDITION_BENCHMARK_FIRST=0",
                     "-define:EXPEDITION_BENCHMARK_LAST=" + str(max(case["stages"])),
                     "-define:EXPEDITION_BENCHMARK_WARMUP=60",
                     "-define:EXPEDITION_BENCHMARK_SAMPLES=600",
                     "-define:EXPEDITION_BENCHMARK_WALK_SAMPLES=" + str(case["walk_samples"])]
        result = execute(args, source, output / "logs" / ("build-" + case["id"] + ".log"), 240)
        result["case"] = case
        result["odin"] = compiler_version
        if result["exit_code"] == 0:
            result["binary_sha256"] = sha(binary(output, case))
        write_json(output / "logs" / ("build-" + case["id"] + ".json"), result)
        print("build", case["id"], result["exit_code"], flush=True)
        if result["exit_code"] != 0:
            raise RuntimeError("Compilazione fallita: " + result["log"])


def rss_bytes(text):
    mac = re.search(r"(\d+)\s+maximum resident set size", text)
    linux = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    return int(mac[1]) if mac else (int(linux[1]) * 1024 if linux else None)


def run(output, selection, repetitions, timeout):
    # Ordine alternato fra ripetizioni: nessuna build o corsa in parallelo.
    for rep in range(1, repetitions + 1):
        order = selection if rep % 2 else list(reversed(selection))
        for case in order:
            name = f"{case['id']}-r{rep}"
            result_path = output / "logs" / (name + ".json")
            if result_path.exists():
                print("già registrato", name, flush=True)
                continue
            executable = binary(output, case)
            compiled = json.loads((output / "logs" / ("build-" + case["id"] + ".json")).read_text())
            if sha(executable) != compiled.get("binary_sha256"):
                raise RuntimeError("Binario diverso da quello registrato: " + str(executable))
            args = [str(executable)]
            if case["group"] == "graphics":
                args += ["--smoke-expedition", "--seed=42"]
            else:
                args += ["--biome=scale-set", "--samples=1", "--seed=42",
                         "--advisor-work=128", "--advisor-ms=5000"]
            if sys.platform == "darwin":
                args = ["/usr/bin/time", "-l", *args]
            elif sys.platform.startswith("linux") and Path("/usr/bin/time").exists():
                args = ["/usr/bin/time", "-v", *args]
            print("avvio", name, flush=True)
            result = execute(args, output / f"scale-{case['scale']}",
                             output / "logs" / (name + ".log"), timeout)
            result.update(case=case, repetition=rep, binary_sha256=compiled["binary_sha256"],
                          runner_sha256=sha(Path(__file__)))
            result["process_peak_rss_bytes"] = rss_bytes(Path(result["log"]).read_text(errors="replace"))
            write_json(result_path, result)
            print("fine", name, "exit", result["exit_code"], "secondi", round(result["elapsed_seconds"], 1), flush=True)


def frame_stats(values):
    if not values or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("Campioni assenti o non validi")
    ordered = sorted(values)
    percentile = lambda p: ordered[math.ceil(len(ordered) * p) - 1]
    return dict(count=len(values), mean_ms=statistics.mean(values), median_ms=statistics.median(values),
                p95_ms=percentile(.95), p99_ms=percentile(.99), max_ms=max(values),
                over_budget=sum(v > 16.67 for v in values))


FRAME_FIELDS = ("stage", "frame", "measured", "biome", "frame_ms", "draw_ms", "simulation_dt", "world_clock",
                "position_x", "position_y", "cell_x", "cell_y", "layer", "phase", "mounted",
                "camera_x", "camera_y", "camera_z", "target_x", "target_y", "target_z",
                "rebuilds", "uploads", "sun_renders")
DRIVER_HEADER = ("stage,stage_frame,measured,biome,frame_ms,wrapped_draw_ms,simulation_dt,world_clock,"
                 "roam_x,roam_y,cell_x,cell_y,layer,phase,mounted,camera_x,camera_y,camera_z,"
                 "target_x,target_y,target_z,geometry_rebuilds,geometry_uploads,sun_renders").split(",")


def parse_frames(text):
    rows = []
    for line in text.splitlines():
        if line.startswith("EXPEDITION FRAME CSV,"):
            values = next(csv.reader([line]))[1:]
            if len(values) != len(FRAME_FIELDS):
                raise ValueError("Schema CSV non riconosciuto")
            if values[0] == "stage":
                if values != DRIVER_HEADER:
                    raise ValueError("Ordine delle colonne del driver cambiato")
                continue
            rows.append(dict(zip(FRAME_FIELDS, values)))
    return rows


def summarize_frames(rows):
    stages = {}
    for stage in sorted({int(r["stage"]) for r in rows}):
        selected_rows = [r for r in rows if int(r["stage"]) == stage]
        measured = [r for r in selected_rows if r["measured"] == "1"]
        stats = frame_stats([float(r["frame_ms"]) for r in measured])
        stats["warmup_count"] = len(selected_rows) - len(measured)
        stats["first_frame_ms"] = float(selected_rows[0]["frame_ms"])
        stats["warmup_max_ms"] = max(float(r["frame_ms"]) for r in selected_rows if r["measured"] == "0")
        state_fields = ("simulation_dt", "world_clock", "position_x", "position_y", "cell_x", "cell_y", "layer",
                        "phase", "mounted", "camera_x", "camera_y", "camera_z", "target_x", "target_y", "target_z")
        trace = [[r[k] for k in state_fields] for r in selected_rows]
        stats["trajectory_sha256"] = hashlib.sha256(json.dumps(trace).encode()).hexdigest()
        stats["first_cell"] = [selected_rows[0][k] for k in ("cell_x", "cell_y", "layer")]
        stats["last_cell"] = [selected_rows[-1][k] for k in ("cell_x", "cell_y", "layer")]
        stages[stage] = stats
    return stages


def report(output):
    # Il parser del formato CSV viene mantenuto separato dal driver; tutti i log restano autorevoli.
    summary = []
    for path in sorted((output / "logs").glob("*-r*.json")):
        row = json.loads(path.read_text())
        # The archive can be extracted on another machine (including across OS families).
        log_name = Path(row["log"].replace("\\", "/")).name
        text = (output / "logs" / log_name).read_text(errors="replace")
        row["reported_statistics"] = [line for line in text.splitlines()
                                      if line.startswith(("EXPEDITION BENCHMARK stage=", "CPU SCENE stage=",
                                                          "GEOMETRY RESIDENT stage=", "EXPEDITION STOCK"))]
        try:
            row["samples"] = []
            if row["case"]["group"] == "headless":
                for line in text.splitlines():
                    if line.startswith("{"):
                        row["samples"].append(json.loads(line))
                row["complete"] = row["exit_code"] == 0 and len(row["samples"]) == 3 and all(
                    not r["error"] and r["scale"] == row["case"]["scale"] and r["seed"] == 42
                    for r in row["samples"]) and {r["biome"] for r in row["samples"]} == {"Cyber", "Snow", "Space"}
            else:
                frames = parse_frames(text)
                with (output / "logs" / (path.stem + ".csv")).open("w", newline="", encoding="utf-8") as f:
                    writer = csv.DictWriter(f, fieldnames=FRAME_FIELDS)
                    writer.writeheader()
                    writer.writerows(frames)
                row["stages"] = summarize_frames(frames)
                row["complete"] = row["exit_code"] == 0 and set(row["stages"]) == set(row["case"]["stages"])
                for stage, stats in row["stages"].items():
                    expected = row["case"]["walk_samples"] if stage in (25, 26) else 600
                    row["complete"] &= stats["count"] == expected and stats["warmup_count"] == 60
                    stage_rows = [r for r in frames if int(r["stage"]) == stage]
                    row["complete"] &= [int(r["frame"]) for r in stage_rows] == list(range(1, expected + 61))
        except (ValueError, KeyError, TypeError) as error:
            row["complete"] = False
            row["parse_error"] = str(error)
        summary.append(row)
    write_json(output / "results.json", summary)
    print("Rapporto:", output / "results.json", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "build", "run", "report"))
    parser.add_argument("--output", type=Path, default=REPO / "build/moonshot-fase0")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--group", choices=("all", "headless", "graphics"), default="all")
    parser.add_argument("--cases", default="", help="ID separati da virgola, vedi README")
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.repetitions < 1 or args.timeout < 1:
        parser.error("repetitions e timeout devono essere positivi")
    output = args.output.resolve()
    selection = selected(args.group, args.cases)
    if not selection:
        parser.error("nessun caso selezionato")
    if args.mode == "prepare":
        prepare(output, args.odin)
    elif args.mode == "build":
        build(output, args.odin, selection)
    elif args.mode == "run":
        run(output, selection, args.repetitions, args.timeout)
    else:
        report(output)


if __name__ == "__main__":
    main()
