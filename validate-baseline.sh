#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p /tmp/pdc-vali
mpicc -g -Wall -o /tmp/mpi_nbody_basic mpi_nbody_basic.c -lm

mpirun -n 1 /tmp/mpi_nbody_basic 4 2 0.01 1 g > /tmp/pdc-vali/r1.txt
mpirun -n 1 /tmp/mpi_nbody_basic 4 2 0.01 1 g > /tmp/pdc-vali/r2.txt
mpirun -n 2 /tmp/mpi_nbody_basic 4 2 0.01 1 g > /tmp/pdc-vali/p2.txt
mpirun -n 4 /tmp/mpi_nbody_basic 4 2 0.01 1 g > /tmp/pdc-vali/p4.txt

for name in r1 r2 p2 p4; do
    sed '/^Elapsed time =/d' "/tmp/pdc-vali/$name.txt" \
        > "/tmp/pdc-vali/$name.state"
done

for name in r2 p2 p4; do
    diff -u /tmp/pdc-vali/r1.state "/tmp/pdc-vali/$name.state"
done

echo "PASS: repeated and multi-process baseline outputs match."