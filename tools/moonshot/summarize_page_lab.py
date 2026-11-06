#!/usr/bin/env python3
"""Verifica e riassume i log del laboratorio pagina, senza avviare il gioco."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys


ACTS = ("Still", "Walk", "Climb", "Flight")
WARMUP = 60
SAMPLES = 600
FRAMES_PER_ACT = WARMUP + SAMPLES
SUMMARY_PREFIX = "PAGE LAB BENCHMARK act="
CSV_PREFIX = "PAGE LAB FRAME CSV,"
DRIVER_PREFIX = "PAGE LAB DRIVER "
SUMMARY_FIELDS = {
    "act", "canvas", "samples", "mean_ms", "p95_ms", "p99_ms", "max_ms",
    "vertices", "triangles", "model_capacity_bytes", "context_capacity_bytes",
    "shaders", "meshes",
}
SUMMARY_INTS = {
    "samples", "vertices", "triangles", "model_capacity_bytes",
    "context_capacity_bytes", "shaders", "meshes",
}
PRINT_FIELDS = {"textures", "print_uploads", "print_bytes"}
SUMMARY_TIMES = ("mean_ms", "p95_ms", "p99_ms", "max_ms")
SCOPES = ("frame", "update", "draw")


def time_value(text):
    value = float(text)
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"tempo non finito o negativo: {text}")
    return value


def frame_stats(values):
    if not values:
        raise ValueError("nessun campione")
    ordered = sorted(time_value(value) for value in values)
    try:
        mean = math.fsum(ordered) / len(ordered)
    except OverflowError as error:
        raise ValueError("somma dei tempi fuori intervallo") from error
    return {
        "count": len(ordered),
        "median_ms": statistics.median(ordered),
        "mean_ms": mean,
        "p95_ms": ordered[(len(ordered) * 95 + 99) // 100 - 1],
        "p99_ms": ordered[(len(ordered) * 99 + 99) // 100 - 1],
        "max_ms": ordered[-1],
    }


def parse_fields(text):
    result = {}
    for token in text.split():
        if token.count("=") != 1:
            raise ValueError(f"campo malformato: {token}")
        name, value = token.split("=")
        if not name or not value or name in result:
            raise ValueError(f"campo vuoto o duplicato: {token}")
        result[name] = value
    return result


def parse_summary(line):
    result = parse_fields(line[len("PAGE LAB BENCHMARK "):])
    if result.keys() not in (SUMMARY_FIELDS, SUMMARY_FIELDS | PRINT_FIELDS):
        raise ValueError("campi del riepilogo mancanti o inattesi")
    for name in SUMMARY_INTS | (PRINT_FIELDS & result.keys()):
        result[name] = int(result[name])
        if result[name] < 0:
            raise ValueError(f"{name} negativo")
    for name in SUMMARY_TIMES:
        result[name] = time_value(result[name])
    if result["canvas"] != "1920x1080":
        raise ValueError("canvas riepilogo diverso da 1920x1080")
    if result["samples"] != SAMPLES:
        raise ValueError(f"samples diverso da {SAMPLES}")
    if result["shaders"] != 1 or result["meshes"] != 0:
        raise ValueError("attesi uno shader e zero mesh posseduti dal laboratorio")
    if "textures" in result:
        if result["textures"] != 1 or result["print_uploads"] != 1 or result["print_bytes"] <= 0:
            raise ValueError("stampa: richiesti textures=1, print_uploads=1 e print_bytes>0")
    for name in ("vertices", "triangles", "model_capacity_bytes", "context_capacity_bytes"):
        if result[name] == 0:
            raise ValueError(f"{name} nullo")
    return result


def parse_frame(line):
    cells = line[len(CSV_PREFIX):].split(",")
    if len(cells) != 6:
        raise ValueError("riga CSV incompleta o con campi in eccesso")
    stage, frame, measured = map(int, cells[:3])
    return {
        "stage": stage, "frame_index": frame, "measured": measured,
        **{scope: time_value(value) for scope, value in zip(SCOPES, cells[3:])},
    }


def summarize_text(text):
    """Conserva gli errori; solo un protocollo completo riceve statistiche."""
    errors, summaries, frames, drivers = [], [], [], []
    summary_count = frame_count = 0
    rss = []
    for number, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        try:
            if line.startswith(SUMMARY_PREFIX):
                summary_count += 1
                summaries.append(parse_summary(line))
            elif line.startswith(CSV_PREFIX):
                frame_count += 1
                frames.append(parse_frame(line))
            elif line.startswith(DRIVER_PREFIX):
                driver = parse_fields(line[len(DRIVER_PREFIX):])
                drivers.append(driver)
                if driver != {"logical": "1920x1080", "raster": "1920x1080", "profile": "off", "audio": "off"}:
                    raise ValueError("driver: richiesti logical/raster1920x1080, profile/audio off")
            elif match := re.fullmatch(r"(\d+)\s+maximum resident set size", line):
                rss.append(int(match.group(1)))
                if rss[-1] <= 0:
                    raise ValueError("RSS massima non positiva")
        except (ValueError, OverflowError) as error:
            errors.append(f"riga {number}: {error}")
    if len(drivers) != 1:
        errors.append(f"atteso un banner DRIVER, trovati {len(drivers)}")
    if summary_count != len(ACTS):
        errors.append(f"attesi {len(ACTS)} riepiloghi, trovati {summary_count}")
    if frame_count != len(ACTS) * FRAMES_PER_ACT:
        errors.append(f"attese {len(ACTS) * FRAMES_PER_ACT} righe CSV, trovate {frame_count}")
    if tuple(summary["act"] for summary in summaries) != ACTS:
        errors.append("ordine dei riepiloghi diverso da Still, Walk, Climb, Flight")
    prints = [summary for summary in summaries if "textures" in summary]
    if prints and len(prints) != len(ACTS):
        errors.append("metadati stampa presenti solo in parte degli atti")
    if prints and len({summary["print_bytes"] for summary in prints}) != 1:
        errors.append("print_bytes cambia tra gli atti: atlas non costante")
    if len(rss) > 1:
        errors.append("più misure RSS nello stesso log: provenienza del processo ambigua")
    for index, row in enumerate(frames):
        stage, frame = divmod(index, FRAMES_PER_ACT)
        frame += 1
        if (row["stage"], row["frame_index"]) != (stage, frame):
            errors.append(f"ordine CSV errato alla riga campione {index + 1}: atteso stage{stage}/frame{frame}")
            break
        if row["measured"] != int(frame > WARMUP):
            errors.append(f"flag measured errato a stage{stage}/frame{frame}")
            break
    stages = []
    if not errors:
        for stage, (act, summary) in enumerate(zip(ACTS, summaries)):
            measured = frames[stage * FRAMES_PER_ACT + WARMUP:(stage + 1) * FRAMES_PER_ACT]
            try:
                scopes = {scope: frame_stats([row[scope] for row in measured]) for scope in SCOPES}
            except ValueError as error:
                errors.append(f"{act}: {error}")
                break
            # Summary prints six decimals; CSV prints nine. Allow only that
            # rounding difference, not a drift masked by a relative tolerance.
            for name in SUMMARY_TIMES:
                if not math.isclose(summary[name], scopes["frame"][name], rel_tol=0, abs_tol=5.01e-7):
                    errors.append(f"{act}: {name} del riepilogo non concorda con CSV")
            stages.append({
                "stage": stage, "act": act, "warmup_count": WARMUP,
                "measured_count": SAMPLES, "scopes": scopes, "reported": summary,
            })
    return {
        "complete": not errors,
        "errors": errors,
        "observed_summary_lines": summary_count,
        "observed_csv_lines": frame_count,
        "process_peak_rss_bytes": rss[0] if len(rss) == 1 else None,
        "rss_source": "Darwin /usr/bin/time -l; maximum resident set size in bytes" if len(rss) == 1 else None,
        "driver": drivers[0] if len(drivers) == 1 else None,
        "print_upload_check": {
            "textures": 1, "print_uploads": 1, "print_bytes": prints[0]["print_bytes"],
            "after_total_frames": [(index + 1) * FRAMES_PER_ACT for index in range(len(ACTS))],
        } if not errors and prints else None,
        "stages": stages if not errors else [],
    }


def summarize_log(path):
    path = path.resolve()
    result = {"log": str(path)}
    try:
        data = path.read_bytes()
        result.update(log_sha256=hashlib.sha256(data).hexdigest(), log_bytes=len(data))
        result.update(summarize_text(data.decode("utf-8")))
    except (OSError, UnicodeError) as error:
        result.update(complete=False, errors=[str(error)], stages=[])
    return result


def markdown(report):
    lines = [
        "# Laboratorio pagina: misure verificate", "",
        "Ogni replica valida contiene quattro atti, ciascuno con 60 frame di riscaldamento "
        "esclusi e 600 misurati. Mediana e percentili sono calcolati sui singoli campioni "
        "di ciascun atto; p95/p99 usano il rango superiore (nearest rank).", "",
        "I tempi sono in millisecondi. Frame è il tempo del fotogramma raylib; update e draw "
        "sono misure CPU interne al frame. Gli scope sono annidati e non sommabili. "
        "Draw misura la preparazione/invio dei comandi, non un timer GPU.", "",
        "La completezza riguarda il protocollo presente nel log, non certifica l'exit code "
        "del processo, l'ottimizzazione della build o il sistema usato. "
        "Le repliche incomplete restano elencate e non contribuiscono a statistiche.", "",
    ]
    for index, run in enumerate(report["runs"], 1):
        lines += [f"## Replica {index}", "", f"Log: `{run['log']}`", ""]
        if "log_sha256" in run:
            lines += [f"SHA-256: `{run['log_sha256']}`", ""]
        lines += [f"Esito protocollo: **{'completo' if run['complete'] else 'incompleto/non valido'}**.", ""]
        rss = run.get("process_peak_rss_bytes")
        if rss is not None:
            lines += [f"RSS massima del processo: {rss / (1024 * 1024):.3f} MiB "
                      f"({rss} byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.", ""]
        else:
            lines += ["RSS massima: non disponibile in forma univoca nel log.", ""]
        if not run["complete"]:
            lines += [f"- {error}" for error in run["errors"]] + [""]
            continue
        lines += [
            "Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: "
            "uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.", "",
        ]
        print_check = run.get("print_upload_check")
        if print_check is not None:
            lines += [
                f"Atlas della stampa: una texture, {print_check['print_bytes']} byte dichiarati costanti. "
                "Il contatore cumulativo print_uploads resta 1 ai checkpoint dopo 660, 1320, 1980 e 2640 frame "
                "(oltre i primi 13): nessun nuovo caricamento segnalato. Il log non contiene un checksum dei pixel.", "",
            ]
        else:
            lines += ["Log precedente: contatori della texture e dei caricamenti della stampa non disponibili.", ""]
        lines += [
            "| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |",
            "|---|---|---:|---:|---:|---:|---:|---:|",
        ]
        for stage in run["stages"]:
            for scope in SCOPES:
                values = stage["scopes"][scope]
                numbers = " | ".join(f"{values[name]:.6f}" for name in
                                     ("median_ms", "mean_ms", "p95_ms", "p99_ms", "max_ms"))
                lines.append(f"| {stage['act']} | {scope} | {values['count']} | {numbers} |")
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--output-dir", "--output", required=True, type=Path)
    args = parser.parse_args(argv)
    paths = [path.resolve() for path in args.logs]
    if len(paths) != len(set(paths)):
        parser.error("lo stesso log non può essere contato come più repliche")
    output = args.output_dir.resolve()
    destinations = (output / "page-lab-summary.json", output / "page-lab-summary.md")
    if any(path in destinations for path in paths):
        parser.error("la destinazione non può sovrascrivere un log di ingresso")
    report = {
        "schema": 1,
        "protocol": {"acts": list(ACTS), "warmup_per_act": WARMUP, "samples_per_act": SAMPLES,
                     "canvas": [1920, 1080], "percentiles": "nearest_rank",
                     "scopes_additive": False, "gpu_timer": False},
        "runs": [summarize_log(path) for path in paths],
    }
    output.mkdir(parents=True, exist_ok=True)
    destinations[0].write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    destinations[1].write_text(markdown(report), encoding="utf-8")
    for destination in destinations:
        print(destination)
    return 0 if all(run["complete"] for run in report["runs"]) else 2


if __name__ == "__main__":
    sys.exit(main())
