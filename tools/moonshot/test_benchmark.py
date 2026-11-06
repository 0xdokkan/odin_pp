"""Controlli dei dati pubblicati, senza avviare il gioco."""
import unittest
from unittest.mock import patch
import json
from pathlib import Path
import tempfile
import benchmark


class ResultsTest(unittest.TestCase):
    def test_archived_logs_do_not_require_original_machine_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            logs = output / "logs"
            logs.mkdir()
            records = [dict(error="", scale=1, seed=42, biome=b) for b in ("Cyber", "Snow", "Space")]
            (logs / "headless-1-speed-r1.log").write_text("\n".join(json.dumps(r) for r in records))
            metadata = dict(log="C:\\old\\logs\\headless-1-speed-r1.log", exit_code=0,
                            case=dict(group="headless", scale=1))
            (logs / "headless-1-speed-r1.json").write_text(json.dumps(metadata))
            benchmark.report(output)
            self.assertTrue(json.loads((output / "results.json").read_text())[0]["complete"])

    def test_changed_source_or_compiler_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            source = output / "scale-1/src/main.odin"
            source.parent.mkdir(parents=True)
            source.write_text("originale")
            manifest = {"odin": "compiler originale", "source_hashes": {
                "scale-1/src/main.odin": benchmark.sha(source)}}
            benchmark.write_json(output / "manifest.json", manifest)
            selection = [{"scale": 1}]
            with patch.object(benchmark, "execute") as execute:
                with patch.object(benchmark, "command_text", return_value="compiler diverso"):
                    with self.assertRaisesRegex(RuntimeError, "Compilatore diverso"):
                        benchmark.build(output, "odin", selection)
                source.write_text("modificato")
                with patch.object(benchmark, "command_text", return_value=manifest["odin"]):
                    with self.assertRaisesRegex(RuntimeError, "Copia modificata"):
                        benchmark.build(output, "odin", selection)
                execute.assert_not_called()

    def test_percentiles_do_not_hide_a_spike(self):
        result = benchmark.frame_stats([10.0] * 99 + [150.0])
        self.assertEqual(result["p95_ms"], 10)
        self.assertEqual(result["p99_ms"], 10)
        self.assertEqual(result["max_ms"], 150)
        self.assertEqual(result["over_budget"], 1)

    def test_bad_samples_are_rejected(self):
        for samples in ([], [float("nan")], [-1.0], [float("inf")]):
            with self.assertRaises(ValueError):
                benchmark.frame_stats(samples)

    def test_rss_units_are_platform_specific(self):
        self.assertEqual(benchmark.rss_bytes(" 12345 maximum resident set size"), 12345)
        self.assertEqual(benchmark.rss_bytes("Maximum resident set size (kbytes): 12"), 12288)
        self.assertIsNone(benchmark.rss_bytes("RSS non disponibile"))

    def test_warmup_is_not_mixed_into_statistics(self):
        rows = []
        for index, ms in enumerate((1000, 8, 12)):
            row = dict.fromkeys(benchmark.FRAME_FIELDS, "0")
            row.update(stage="25", frame=str(index + 1), frame_ms=str(ms), measured=str(int(index > 0)))
            rows.append(row)
        result = benchmark.summarize_frames(rows)[25]
        self.assertEqual(result["mean_ms"], 10)
        self.assertEqual(result["first_frame_ms"], 1000)
        self.assertEqual(result["warmup_count"], 1)

    def test_incomplete_csv_is_not_silently_accepted(self):
        with self.assertRaises(ValueError):
            benchmark.parse_frames("EXPEDITION FRAME CSV,1,2,3")

    def test_csv_header_is_not_a_frame(self):
        text = "EXPEDITION FRAME CSV," + ",".join(benchmark.DRIVER_HEADER) + "\n"
        text += "EXPEDITION FRAME CSV," + ",".join(["0"] * len(benchmark.FRAME_FIELDS))
        self.assertEqual(len(benchmark.parse_frames(text)), 1)

    def test_partial_log_preserves_failed_run_in_report(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            logs = output / "logs"
            logs.mkdir()
            log = logs / "interrupted.log"
            log.write_text('EXPEDITION FRAME CSV,0,1,0')
            metadata = {"log": str(log), "exit_code": None, "case": {"group": "graphics", "stages": [0]}}
            (logs / "baseline-none-r1.json").write_text(json.dumps(metadata))
            benchmark.report(output)
            results = json.loads((output / "results.json").read_text())
            self.assertEqual(len(results), 1)
            self.assertFalse(results[0]["complete"])
            self.assertIn("parse_error", results[0])


if __name__ == "__main__":
    unittest.main()
