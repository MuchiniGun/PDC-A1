# PDC-A1
Parallel and Distributed Computing Assignment 1, new repository out of GH Classroom

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
