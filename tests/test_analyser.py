"""Check the calculations using small timings whose answers we know."""
import csv
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from analyser import VARIANTS, read_measurements, summarise

RAW_FIELDS = ["variant", "threads", "repetition", "n", "n_steps", "delta_t", "elapsed_seconds"]


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.config = {"label": "MEASURED", "n": 4, "n_steps": 3, "delta_t": 0.01,
                       "threads": [1, 4], "repeats": 2, "timeout_seconds": 120, "cooling_seconds": 0}
        self.rows = [[v, p, r, 4, 3, 0.01, t] for v in VARIANTS
                     for p, times in ((1, (8, 10)), (4, (2, 4))) for r, t in enumerate(times, 1)]

    def read_rows(self, rows):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "raw.csv"
            with path.open("w", newline="") as destination:
                writer = csv.writer(destination)
                writer.writerow(RAW_FIELDS)
                writer.writerows(rows)
            return read_measurements(path, self.config)

    def test_known_statistics(self):
        results = summarise(self.read_rows(self.rows), self.config)
        self.assertEqual(len(results), 8)
        row = results[1]
        self.assertEqual(row["mean_seconds"], 3)
        self.assertAlmostEqual(row["stdev_seconds"], math.sqrt(2))
        self.assertEqual((row["min_seconds"], row["max_seconds"]), (2, 4))
        self.assertAlmostEqual(row["cv_percent"], 100 * math.sqrt(2) / 3)
        # Ratio of means is 9/3, not the average of 8/2 and 10/4.
        self.assertEqual(row["speedup"], 3)
        self.assertEqual(row["efficiency_percent"], 75)

    def test_one_thread_baselines(self):
        for row in summarise(self.read_rows(self.rows), self.config):
            if row["threads"] == 1:
                self.assertEqual(row["speedup"], 1)
                self.assertEqual(row["efficiency_percent"], 100)

    def test_each_variant_has_its_own_baseline(self):
        for row in self.rows:
            if row[0] == "reduced-default":
                row[-1] *= 2
        results = summarise(self.read_rows(self.rows), self.config)
        self.assertEqual(results[3]["speedup"], 3)

    def test_missing_repeat(self):
        with self.assertRaises(ValueError):
            self.read_rows(self.rows[:-1])

    def test_duplicate_repeat(self):
        with self.assertRaises(ValueError):
            self.read_rows(self.rows + [self.rows[0]])

    def test_invalid_values_and_settings(self):
        for column, value in ((0, "unknown"), (1, 32), (2, 3), (3, 7), (4, 9),
                              (5, 0.02), (6, "nan"), (6, "inf"), (6, 0), (6, -1)):
            rows = [row.copy() for row in self.rows]
            rows[0][column] = value
            with self.subTest(column=column, value=value), self.assertRaises(ValueError):
                self.read_rows(rows)

    def test_pilot_data_rejected(self):
        self.config["label"] = "PILOT"
        with self.assertRaises(ValueError):
            self.read_rows(self.rows)

    def test_missing_baseline_rejected(self):
        self.config["threads"] = [4]
        with self.assertRaises(ValueError):
            self.read_rows(self.rows)


if __name__ == "__main__":
    unittest.main()
