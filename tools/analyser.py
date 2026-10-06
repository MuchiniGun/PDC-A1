#!/usr/bin/env python3
"""Summarise repeated timings without changing the raw measurements."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics

from benchmark import VARIANTS

def read_measurements(path, config):
    if config["label"] != "MEASURED" or 1 not in config["threads"] or config["repeats"] < 2:
        raise ValueError("analysis needs measured data, a one-thread baseline and at least two repeats")
    expected = {(variant, threads, repeat) for variant in VARIANTS
                for threads in config["threads"] for repeat in range(1, config["repeats"] + 1)}
    measurements = {}
    with path.open(newline="") as source:
        for row in csv.DictReader(source):
            key = (row["variant"], int(row["threads"]), int(row["repetition"]))
            if key not in expected or key in measurements:
                raise ValueError(f"Unexpected or duplicate run: {key}")
            if (int(row["n"]) != config["n"] or int(row["n_steps"]) != config["n_steps"]
                    or float(row["delta_t"]) != config["delta_t"]):
                raise ValueError("Workload does not match the configuration")
            elapsed = float(row["elapsed_seconds"])
            if not math.isfinite(elapsed) or elapsed <= 0:
                raise ValueError("Timing must be finite and positive")
            measurements[key] = elapsed

    if measurements.keys() != expected:
        raise ValueError(f"missing {len(expected - measurements.keys())} measurements")
    return measurements


def summarise(measurements, config):
    results = []
    for variant in VARIANTS:
        baseline = statistics.mean(measurements[variant, 1, repeat]
                                   for repeat in range(1, config["repeats"] + 1))
        for threads in config["threads"]:
            times = [measurements[variant, threads, repeat]
                     for repeat in range(1, config["repeats"] + 1)]
            mean = statistics.mean(times)
            # Sample standard deviation describes the spread of repeated runs
            stdev = statistics.stdev(times)
            # Compare each variant with its own one-thread mean, not with Basic.
            speedup = baseline / mean
            results.append({
                "variant": variant, "threads": threads, "repeats": len(times),
                "mean_seconds": mean, "stdev_seconds": stdev,
                "min_seconds": min(times), "max_seconds": max(times),
                "cv_percent": 100 * stdev / mean,
                "speedup": speedup, "efficiency_percent": 100 * speedup / threads,
            })
    return results


def write_results(output, results, config):
    output.mkdir(parents=True, exist_ok=False)
    with (output / "summary.csv").open("w", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    table = ["# Mean wall-clock time (seconds)", "",
             "| Variant | " + " | ".join(f"{p} threads" for p in config["threads"]) + " |",
             "| --- | " + " | ".join("---:" for _ in config["threads"]) + " |"]
    for variant in VARIANTS:
        means = [row["mean_seconds"] for row in results if row["variant"] == variant]
        label = variant.replace("-", " ").title()
        table.append(f"| {label} | " + " | ".join(f"{value:.6f}" for value in means) + " |")
    (output / "runtime-table.md").write_text("\n".join(table) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        measurements = read_measurements(args.input, config)
        results = summarise(measurements, config)
        write_results(args.output, results, config)
        print(f"Analysis complete: {len(measurements)} measurements, {len(results)} configurations")
        print(f"Summary and runtime table saved in {args.output}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Analysis stopped: {error}\n")


if __name__ == "__main__":
    main()
