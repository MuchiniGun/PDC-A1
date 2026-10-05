"""Check that invalid runs cannot become accepted benchmark measurements."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from benchmark import ROOT, parse_result, run_batch, validate_config


class BenchmarkTests(unittest.TestCase):
    def setUp(self):
        # Use sample output to test rejection cases without running the simulation
        self.team = "requested_team=4\nobserved_team=4\n"
        self.config = json.loads((ROOT / "bench/pilot.json").read_text())

    def test_valid_internal_time(self):
        self.assertEqual(parse_result("Elapsed time = 1.25e-02 seconds\n", self.team, 0, 4), 0.0125)

    def test_failed_process(self):
        with self.assertRaises(ValueError):
            parse_result("Elapsed time = 1 seconds\n", self.team, 1, 4)

    def test_invalid_times(self):
        for value in ("0", "-1", "nan", "inf", "nonsense"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_result(f"Elapsed time = {value} seconds\n", self.team, 0, 4)

    def test_missing_or_extra_output(self):
        for output in ("", "Elapsed time = 1 seconds\nextra\n", "state,0\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_result(output, self.team, 0, 4)

    def test_team_mismatch_and_extra_diagnostics(self):
        for team in ("", "requested_team=4\nobserved_team=2\n", self.team + "warning\n"):
            with self.subTest(team=team), self.assertRaises(ValueError):
                parse_result("Elapsed time = 1 seconds\n", team, 0, 4)

    def test_pilot_config(self):
        validate_config(self.config)

    def test_invalid_config(self):
        for key, value in (("threads", [1, 1]), ("repeats", 0), ("delta_t", float("nan")),
                           ("timeout_seconds", 0), ("cooling_seconds", -1)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_config({**self.config, key: value})

    def test_existing_results_are_preserved(self):
        # Try reusing a results folder and check that its old data survives.
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "raw.csv"
            marker.write_text("previous results\n")
            with self.assertRaises(FileExistsError):
                run_batch(self.config, output)
            self.assertEqual(marker.read_text(), "previous results\n")


if __name__ == "__main__":
    unittest.main()
