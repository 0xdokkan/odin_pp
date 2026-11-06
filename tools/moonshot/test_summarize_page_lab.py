"""Dati sintetici per verificare il parser, mai risultati del gioco."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import summarize_page_lab as report


def fixture_log(print_fields=""):
    lines = ["PAGE LAB DRIVER logical=1920x1080 raster=1920x1080 profile=off audio=off"]
    for stage, act in enumerate(report.ACTS):
        # Mean of 1..600 is 300.5; warmup is deliberately much slower.
        lines.append(f"PAGE LAB BENCHMARK act={act} canvas=1920x1080 samples=600 "
                     "mean_ms=300.500000 p95_ms=570.000000 p99_ms=594.000000 max_ms=600.000000 "
                     "vertices=100 triangles=50 model_capacity_bytes=1000 context_capacity_bytes=2000 shaders=1 meshes=0"
                     + print_fields)
        for frame in range(1, report.FRAMES_PER_ACT + 1):
            measured = int(frame > report.WARMUP)
            ms = frame - report.WARMUP if measured else 10000
            lines.append(f"PAGE LAB FRAME CSV,{stage},{frame},{measured},{ms:.9f},{ms / 2:.9f},{ms / 4:.9f}")
    return "\n".join(lines) + "\n"


class PageLabReportTest(unittest.TestCase):
    def test_complete_log_excludes_warmup_and_computes_all_scopes(self):
        result = report.summarize_text(fixture_log() + "  1525600000 maximum resident set size\n")
        self.assertTrue(result["complete"], result["errors"])
        self.assertEqual(result["observed_csv_lines"], 2640)
        self.assertEqual(result["process_peak_rss_bytes"], 1525600000)
        stage = result["stages"][0]
        self.assertEqual(stage["warmup_count"], 60)
        self.assertEqual(stage["scopes"]["frame"], {
            "count": 600, "median_ms": 300.5, "mean_ms": 300.5,
            "p95_ms": 570, "p99_ms": 594, "max_ms": 600,
        })
        self.assertEqual(stage["scopes"]["update"]["median_ms"], 150.25)
        self.assertEqual(stage["scopes"]["draw"]["p95_ms"], 142.5)
        self.assertIsNone(result["print_upload_check"])

    def test_print_atlas_has_one_upload_beyond_initial_frames(self):
        result = report.summarize_text(fixture_log(" textures=1 print_uploads=1 print_bytes=262144"))
        self.assertTrue(result["complete"], result["errors"])
        self.assertEqual(result["print_upload_check"], {
            "textures": 1, "print_uploads": 1, "print_bytes": 262144,
            "after_total_frames": [660, 1320, 1980, 2640],
        })
        self.assertIn("Il contatore cumulativo print_uploads resta 1", report.markdown({"runs": [{"log": "synthetic", **result}]}))

    def test_print_fields_are_an_all_or_none_contract(self):
        valid = " textures=1 print_uploads=1 print_bytes=262144"
        for field in valid.split():
            with self.subTest(missing=field):
                result = report.summarize_text(fixture_log(valid.replace(" " + field, "")))
                self.assertFalse(result["complete"])
                self.assertIsNone(result["print_upload_check"])
        mixed = fixture_log(valid).replace(valid, "", 1)
        self.assertFalse(report.summarize_text(mixed)["complete"])

    def test_invalid_texture_or_repeated_upload_is_rejected(self):
        valid = " textures=1 print_uploads=1 print_bytes=262144"
        cases = (("textures=1", "textures=0"), ("textures=1", "textures=2"),
                 ("print_uploads=1", "print_uploads=2"), ("print_bytes=262144", "print_bytes=0"),
                 ("print_bytes=262144", "print_bytes=-1"), ("print_bytes=262144", "print_bytes=nan"))
        for old, new in cases:
            with self.subTest(value=new):
                text = fixture_log(valid)
                # Change only the last checkpoint: early frames cannot mask a later upload.
                before, after = text.rsplit(old, 1)
                result = report.summarize_text(before + new + after)
                self.assertFalse(result["complete"])
                self.assertIsNone(result["print_upload_check"])

    def test_atlas_byte_count_must_stay_constant(self):
        text = fixture_log(" textures=1 print_uploads=1 print_bytes=262144")
        result = report.summarize_text(text.replace("print_bytes=262144", "print_bytes=524288", 1))
        self.assertFalse(result["complete"])

    def test_truncated_last_csv_is_not_a_complete_replica(self):
        text = fixture_log().rsplit("PAGE LAB FRAME CSV,", 1)[0]
        result = report.summarize_text(text)
        self.assertFalse(result["complete"])
        self.assertEqual(result["observed_summary_lines"], 4)
        self.assertEqual(result["observed_csv_lines"], 2639)
        self.assertEqual(result["stages"], [])

    def test_bad_times_fail_in_warmup_measured_and_summary(self):
        cases = (
            ("10000.000000000", "nan"),
            ("1.000000000", "inf"),
            ("1.000000000", "-1"),
            ("mean_ms=300.500000", "mean_ms=NaN"),
        )
        for before, after in cases:
            with self.subTest(after=after):
                result = report.summarize_text(fixture_log().replace(before, after, 1))
                self.assertFalse(result["complete"])
                self.assertEqual(result["stages"], [])

    def test_counts_alone_cannot_hide_duplicate_or_wrong_measured_row(self):
        for old, new in (("CSV,0,62,1,", "CSV,0,61,1,"), ("CSV,0,60,0,", "CSV,0,60,1,")):
            result = report.summarize_text(fixture_log().replace(old, new, 1))
            self.assertFalse(result["complete"])
            self.assertEqual(result["observed_csv_lines"], 2640)

    def test_summary_must_match_raw_frames_and_real_raster(self):
        cases = (("p95_ms=570.000000", "p95_ms=571.000000"),
                 ("raster=1920x1080", "raster=3840x2160"),
                 ("canvas=1920x1080", "canvas=960x540"),
                 ("shaders=1", "shaders=0"), ("meshes=0", "meshes=1"),
                 ("act=Walk", "act=Still"))
        for old, new in cases:
            with self.subTest(new=new):
                result = report.summarize_text(fixture_log().replace(old, new, 1))
                self.assertFalse(result["complete"])

    def test_nearest_rank_preserves_maximum_without_moving_p99(self):
        result = report.frame_stats([1] * 99 + [1000])
        self.assertEqual(result["p95_ms"], 1)
        self.assertEqual(result["p99_ms"], 1)
        self.assertEqual(result["max_ms"], 1000)
        self.assertEqual(result["median_ms"], 1)

    def test_absent_rss_is_not_zero_and_multiple_processes_are_rejected(self):
        self.assertIsNone(report.summarize_text(fixture_log())["process_peak_rss_bytes"])
        result = report.summarize_text(fixture_log() + "10 maximum resident set size\n20 maximum resident set size\n")
        self.assertFalse(result["complete"])
        self.assertIsNone(result["process_peak_rss_bytes"])

    def test_cli_preserves_incomplete_replica_and_returns_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            valid, partial = folder / "valid.log", folder / "partial.log"
            valid.write_text(fixture_log(), encoding="utf-8")
            partial.write_text("PAGE LAB FRAME CSV,0,1,0", encoding="utf-8")
            output = folder / "report"
            with contextlib.redirect_stdout(io.StringIO()):
                status = report.main([str(valid), str(partial), "--output-dir", str(output)])
            self.assertEqual(status, 2)
            results = json.loads((output / "page-lab-summary.json").read_text(encoding="utf-8"))
            self.assertEqual(len(results["runs"]), 2)
            self.assertTrue(results["runs"][0]["complete"])
            self.assertFalse(results["runs"][1]["complete"])
            self.assertEqual(len(results["runs"][0]["log_sha256"]), 64)
            markdown = (output / "page-lab-summary.md").read_text(encoding="utf-8")
            self.assertIn("incompleto/non valido", markdown)
            self.assertIn("non sommabili", markdown)


if __name__ == "__main__":
    unittest.main()
