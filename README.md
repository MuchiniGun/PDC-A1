# PDC-A1
Parallel and Distributed Computing Assignment 1

## Dev environment

Open this repo folder in VS Code and select **Dev Containers: Reopen in Container** with Docker Desktop running. I had to make a compy of the docker config in `.devcontainer/devcontainer.json`, this allows you to open in dev container.

## Build and run the unchanged MPI baseline

From the repository root (currently `/workspaces/PDC-A1`):

```bash
mpicc -g -Wall -o /tmp/mpi_nbody_basic mpi_nbody_basic.c -lm
mpirun -n 1 /tmp/mpi_nbody_basic 4 2 0.01 1 g
mpirun -n 2 /tmp/mpi_nbody_basic 4 2 0.01 1 g
mpirun -n 4 /tmp/mpi_nbody_basic 4 2 0.01 1 g
```

## Part 2: OpenMP N-body simulation

Run these commands in the dev containers (linux) with AMD64
Measurements used GCC 11.4.0 with libgomp. Python 3 is needed for the tools, and Matplotlib is needed to plot graphs. The shell tests also use `timeout`.

### Source files

| File | Implementation |
| --- | --- |
| `part2a_critical.c` | Shared force array protected by a critical section |
| `part2a_locks.c` | Shared force array protected by per-particle locks |
| `part2b_basic.c` | Each particle calculates its own force |
| `part2b_reduced_default.c` | Pair calculations with per-thread forces; no schedule clauses |
| `part2b_reduced_forces_cyclic.c` | Cyclic scheduling on the pair-force loop |
| `part2b_reduced_all_cyclic.c` | Cyclic scheduling on all four work-sharing loops |

I've kept the original source files. I've made copies that look like `reference_*.c` which add precise output for comparison. Each Part 2A file can compile without project headers:

```bash
gcc -O2 -g -Wall -Wextra -fopenmp part2a_critical.c -lm -o /tmp/pdc-critical
gcc -O2 -g -Wall -Wextra -fopenmp part2a_locks.c -lm -o /tmp/pdc-locks
/tmp/pdc-critical 4 7 20 0.01 1 g
```

### Arguments and build modes

All six implementations use:

```text
program threads particles steps delta_t output_frequency g|i
```

Threads, particles and output frequency must be positive integers. Steps may be zero; `delta_t` must be finite and positive. Mode `g` generates the initial particles. Mode `i` reads five values per particle from standard input:
mass, x position, y position, x velocity and y velocity. Like:

```bash
make build/critical
./build/critical 4 4 3 0.01 1 i < tests/inputs/noncollinear-4.txt
```

The Makefile uses `-O2 -g -Wall -Wextra -fopenmp` and links `-lm`.

### Checks

Run the following to validate correctness:

```bash
make check-validation
make check-part2a
make check-part2b
make check-benchmark-workload
python3 -B tests/test_benchmark.py
python3 -B tests/test_analyser.py
```

Part 2A performs 156 matrix comparisons and two standalone comparisons.
Part 2B performs 312 comparisons. The final benchmark workload has a separate

### Benchmark and reproduce the figures

`bench/config.json` fixes 1,600 particles, 1,000 steps, `delta_t=0.001`, generated
input, threads 1/4/8/16/32 and five repeats: 100 measurements.

The runner compiles first, then runs one program at a time. It reads the program's `omp_get_wtime()` result. Timing includes
the parallel region, synchronisation and team overhead, and excludes particle allocation, input generation and diagnostic printing.

Running the benchmark tests:
```bash
python3 tools/benchmark.py --config bench/config.json --output build/new-batch
python3 tools/analyser.py --input bench/results/final/raw.csv --config bench/results/final/config.json --output build/new-analysis
python3 tools/plot_results.py --input build/new-analysis/summary.csv --config bench/results/final/config.json --output build/new-figures
```

These commands collect a new batch, then reproduce the analysis and figures from the saved final batch.

The analysis reports arithmetic means, sample standard deviations, min/max and coefficients of variation. Speedup is each variant's one-thread mean divided by its mean at the selected thread count. Efficiency is `100 * speedup / threads`.

Saved raw data and batch settings are in `bench/results/final/`; Summaries are in `bench/results/analysis/`
Report figures are in `bench/figures/`.