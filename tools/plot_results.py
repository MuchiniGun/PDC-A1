#!/usr/bin/env python3
"""Plot runtime, speedup and efficiency from the benchmark summary."""
import argparse
import csv
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # Save figures
import matplotlib.pyplot as plt

from benchmark import VARIANTS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    threads = config["threads"]
    with args.input.open(newline="") as source:
        rows = list(csv.DictReader(source))
    data = {(row["variant"], int(row["threads"])): row for row in rows}
    expected = {(variant, p) for variant in VARIANTS for p in threads}
    if len(rows) != len(data) or data.keys() != expected:
        raise ValueError("Summary has missing, duplicate or unexpected configurations")

    plots = [("runtime", "mean_seconds", "Mean runtime", "Mean wall-clock time (seconds)"),
             ("speedup", "speedup", "Speedup", "Speedup relative to the same variant at 1 thread"),
             ("efficiency", "efficiency_percent", "Parallel efficiency", "Parallel efficiency (%)")]
    for row in rows:
        if int(row["repeats"]) != config["repeats"]:
            raise ValueError("Repeat count does not match the configuration")
        for _, field, _, _ in plots:
            value = float(row[field])
            if not math.isfinite(value) or value <= 0:
                raise ValueError(f"Invalid plotted value: {field}")

    args.output.mkdir(parents=True, exist_ok=False)
    # Keep each variant's colour and marker the same in all three figures.
    colours = ["#0072B2", "#D55E00", "#009E73", "#CC79A7"]
    markers = ["o", "s", "^", "D"]
    for name, field, title, ylabel in plots:
        fig, ax = plt.subplots(figsize=(7, 4.5), constrained_layout=True)
        for variant, colour, marker in zip(VARIANTS, colours, markers):
            values = [float(data[variant, p][field]) for p in threads]
            ax.plot(threads, values, color=colour, marker=marker,
                    label=variant.replace("-", " ").title(), linewidth=1.6)
        fig.suptitle(title, fontsize=14)
        ax.set_title(f"n={config['n']}, steps={config['n_steps']}, dt={config['delta_t']}; "
                     f"{config['repeats']} repeats per configuration", fontsize=9)
        ax.set_xlabel("Number of OpenMP threads")
        ax.set_ylabel(ylabel)
        ax.set_xticks(threads)
        ax.set_ylim(bottom=0)
        ax.grid(alpha=0.25)
        ax.legend(fontsize=9)
        fig.savefig(args.output / f"{name}.png", dpi=300)
        fig.savefig(args.output / f"{name}.svg")
        plt.close(fig)
    print(f"Saved 3 graphs as PNG and SVG in {args.output}")


if __name__ == "__main__":
    main()
