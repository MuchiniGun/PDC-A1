#!/usr/bin/env python3
"""
    Collect the programs' internal wall-clock times, 1 process at a time.
"""
import argparse
import csv
from datetime import datetime
import json
import math
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = ("basic", "reduced-default", "reduced-forces-cyclic", "reduced-all-cyclic")


def validate_config(config):
    # Reject invalid settings before building result files.
    if config["label"] not in ("PILOT", "MEASURED"):
        raise ValueError("label must be PILOT or MEASURED")
    for key in ("n", "n_steps", "repeats"):
        if type(config[key]) is not int or config[key] <= 0:
            raise ValueError(f"{key} must be a positive integer")
    threads = config["threads"]
    if not isinstance(threads, list) or not threads or any(
        type(p) is not int or p <= 0 for p in threads
    ) or len(set(threads)) != len(threads):
        raise ValueError("threads must contain unique positive integers")
    for key in ("delta_t", "timeout_seconds", "cooling_seconds"):
        value = config[key]
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ValueError(f"{key} must be finite and non-negative")
        if key != "cooling_seconds" and value == 0:
            raise ValueError(f"{key} must be positive")


def parse_result(stdout, stderr, returncode, threads):
    # Only accept a successful run with one timing line and the right team.
    if returncode != 0:
        raise ValueError(f"program exited with status {returncode}")
    match = re.fullmatch(r"Elapsed time = (\S+) seconds\n?", stdout)
    if not match:
        raise ValueError("expected exactly one elapsed-time line")
    # Use the program's timer, so process startup is not part of the measurement.
    elapsed = float(match[1])
    if not math.isfinite(elapsed) or elapsed <= 0:
        raise ValueError("elapsed time must be finite and positive")
    if stderr.splitlines() != [f"requested_team={threads}", f"observed_team={threads}"]:
        raise ValueError("unexpected team size or diagnostic output")
    return elapsed


def run_batch(config, output):
    validate_config(config)
    # To prevent a rerun from overwriting earlier evidence
    output.mkdir(parents=True, exist_ok=False)
    (output / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    env = os.environ.copy()
    # Stop OpenMP from automatically reducing the requested team size
    env["OMP_DYNAMIC"] = "FALSE"
    with (output / "metadata.txt").open("w") as metadata:
        try:
            metadata.write(f"Started: {datetime.now().astimezone().isoformat()}\n")
            metadata.write(f"Platform: {platform.platform()}\n")
            metadata.write("Input: generated (g); output frequency: n_steps\n")
            metadata.write("Order: repeat, variant, threads; no warm-ups; retain all valid runs\n")
            metadata.write("On failure: stop, preserve partial batch, restart in a new directory\n")
            metadata.write("OpenMP environment:\n")
            for key in sorted(env):
                if key.startswith(("OMP_", "GOMP_", "KMP_")):
                    metadata.write(f"{key}={env[key]}\n")
            # Record just the relevant machine and build informatio
            for command in (["git", "rev-parse", "HEAD"], ["git", "status", "--short"], ["lscpu"]):
                result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
                metadata.write(f"$ {shlex.join(command)}\n{result.stdout}")
            # Incase container has few resources than host machine
            for name in ("cpu.max", "cpuset.cpus.effective", "memory.max"):
                path = Path("/sys/fs/cgroup") / name
                if path.exists():
                    metadata.write(f"{path}: {path.read_text().strip()}\n")
            metadata.flush()
            # Compile first so compiler activity doesn't interfere with the timings.
            with (output / "build.log").open("w") as build_log:
                subprocess.run(["make", "-B", "benchmark-build"], cwd=ROOT,
                               stdout=build_log, stderr=subprocess.STDOUT, check=True)
            for variant in VARIANTS:
                result = subprocess.run(["ldd", f"build/part2b-{variant}-no-output"],
                                        cwd=ROOT, capture_output=True, text=True, check=True)
                metadata.write(f"{variant} runtime libraries:\n{result.stdout}")
            metadata.flush()
            with (output / "raw.csv").open("w", newline="") as raw, (output / "order.txt").open("w") as order:
                writer = csv.writer(raw)
                writer.writerow(["variant", "threads", "repetition", "n", "n_steps", "delta_t", "elapsed_seconds"])
                count = 0
                for repeat in range(1, config["repeats"] + 1):
                    for variant in VARIANTS:
                        for threads in config["threads"]:
                            name = f"{variant}-t{threads}-r{repeat}"
                            command = [f"./build/part2b-{variant}-no-output", str(threads),
                                       str(config["n"]), str(config["n_steps"]), str(config["delta_t"]),
                                       str(config["n_steps"]), "g"]
                            order.write(f"{datetime.now().astimezone().isoformat()} {name}: {shlex.join(command)}\n")
                            order.flush()
                            stdout_path, stderr_path = output / f"{name}.stdout", output / f"{name}.stderr"
                            # Wait for this run to finish before starting another one.
                            with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
                                result = subprocess.run(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                                        stdout=stdout, stderr=stderr, timeout=config["timeout_seconds"])
                            elapsed = parse_result(stdout_path.read_text(), stderr_path.read_text(), result.returncode, threads)
                            writer.writerow([variant, threads, repeat, config["n"], config["n_steps"], config["delta_t"], elapsed])
                            # Save each accepted result in case a later run fails.
                            raw.flush()
                            count += 1
                            print(f"{config['label']} {name}: {elapsed:g} seconds", flush=True)
                            # Any cooling pause is outside the program's measured time.
                            time.sleep(config["cooling_seconds"])
            metadata.write(f"Completed: {datetime.now().astimezone().isoformat()}; {count} accepted runs\n")
            print(f"{config['label']} complete: {count} accepted runs; results in {output}")
        except (Exception, KeyboardInterrupt) as error:
            metadata.write(f"FAILED: {datetime.now().astimezone().isoformat()} {type(error).__name__}: {error}\n")
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        run_batch(json.loads(args.config.read_text()), args.output.resolve())
    except (Exception, KeyboardInterrupt) as error:
        parser.exit(1, f"Benchmark stopped: {error}\n")


if __name__ == "__main__":
    main()
