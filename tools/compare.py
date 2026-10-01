#!/usr/bin/env python3
"""Compare state,time / particle,id,mass,x,y,vx,vy records.

Usage: python3 tools/compare.py reference.csv candidate.csv
The reference is the expected serial result; the candidate is the result
we want to check. Both files must use the precise -DVALIDATE output format.

Exit 0: agreement; 1: numerical/structure mismatch; 2: invalid input.
"""
import argparse
import math
import re
import sys
from pathlib import Path


def read_states(path):
    """Read and check the file before attempting any numerical comparison."""
    # Store results as states[time][particle_id] = (mass, x, y, vx, vy).
    # will make it easier to match particles by identity
    states = {}
    # current points to the particle dictionary
    current = None
    ended = False

    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        fields = line.split(",")

        try:
            if ended:
                raise ValueError("record after elapsed time")
            if line.startswith("Elapsed time = "):
                match = re.fullmatch(r"Elapsed time = (\S+) seconds", line)
                if not match or not math.isfinite(float(match[1])):
                    raise ValueError("invalid elapsed time")
                ended = True
            elif fields[0] == "state" and len(fields) == 2:
                time = float(fields[1])
                if not math.isfinite(time) or time < 0:
                    raise ValueError("invalid state time")
                if states and time <= max(states):
                    raise ValueError("state times must increase")
                current = {}
                states[time] = current
            elif fields[0] == "particle" and len(fields) == 7:
                # Particle ID needs to be non-negative integer,
                # and have a state header
                if current is None or not re.fullmatch(r"0|[1-9][0-9]*", fields[1]):
                    raise ValueError("particle before state or invalid id")
                particle = int(fields[1])
                values = tuple(map(float, fields[2:]))
                # NaN and infinity need to fail
                if particle in current or not all(map(math.isfinite, values)):
                    raise ValueError("duplicate particle or non-finite value")
                current[particle] = values
            else:
                raise ValueError("unexpected record or wrong field count")
        except ValueError as error:
            # filename and line number to help find the error ouptput
            raise ValueError(f"{path}:{number}: {error}") from error
    if not states or any(not particles for particles in states.values()):
        raise ValueError(f"{path}: empty state stream or empty state")
    ids = set(next(iter(states.values())))

    # checks ids for consistency
    if ids != set(range(len(ids))) or any(set(p) != ids for p in states.values()):
        raise ValueError(f"{path}: missing or inconsistent particle ids")
    return states


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference")
    parser.add_argument("candidate")
    parser.add_argument("--rtol", type=float, default=1e-10)
    parser.add_argument("--atol", type=float, default=1e-6,
                        help="absolute tolerance for position (m) and velocity (m/s)")
    args = parser.parse_args()

    if any(not math.isfinite(v) or v < 0 for v in (args.rtol, args.atol)):
        parser.error("tolerances must be finite and non-negative")
    try:
        reference = read_states(args.reference)
        candidate = read_states(args.candidate)
    except (OSError, ValueError) as error:
        print(f"INVALID INPUT: {error}", file=sys.stderr)
        return 2

    # Compare the structure first so every expected time and particle is checked.
    # State times must match exactly because both runs use the same timestep.
    if reference.keys() != candidate.keys() or any(
            reference[t].keys() != candidate[t].keys() for t in reference):
        print("FAIL: state times or particle ids differ")
        return 1
    first = None
    worst = 0.0
    worst_location = "none (exact agreement)"

    for time, particles in reference.items():
        for particle, values in particles.items():
            for field, expected, actual in zip(
                    ("mass", "x", "y", "vx", "vy"), values, candidate[time][particle]):
                error = abs(actual - expected)

                # Allow small position/velocity differences using:
                #   |actual - expected| <= atol + rtol * |expected|
                # atol handles values near zero; rtol scales with the value.
                limit = 0.0 if field == "mass" else args.atol + args.rtol * abs(expected)
                # scaled error <= 1 is within tolerance; > 1 is a failure.
                scaled = error / limit if limit else (math.inf if error else 0.0)
                location = f"time={time:g} particle={particle} {field}: error={error:.6g}, limit={limit:.6g}"

                if scaled > worst:
                    worst, worst_location = scaled, location
                if error > limit and first is None:
                    first = location
    print(f"{'FAIL' if first else 'PASS'}: max_scaled_error={worst:.6g}; {worst_location}")
    if first:
        print(f"first mismatch: {first}")
    return 1 if first else 0


if __name__ == "__main__":
    sys.exit(main())
