/* File:     mpi_nbody_basic.c
 * Purpose:  Implement a 2-dimensional n-body solver that uses the
 *           basic algorithm.  This version uses an in-place Allgather
 *
 * Compile:  mpicc -g -Wall -o mpi_nbody_basic mpi_nbody_basic.c -lm
 *           To turn off output (e.g., when timing), define NO_OUTPUT
 *           To get verbose output, define DEBUG
 *
 * Run:      mpiexec -n <number of processes> ./mpi_nbody_basic
 *              <number of particles> <number of timesteps>  <size of timestep>
 *              <output frequency> <g|i>
 *              'g': generate initial conditions using a random number
 *                   generator
 *              'i': read initial conditions from stdin
 *              number of particles should be evenly divisible by the number
 *                 of MPI processes
 *           A stepsize of 0.01 seems to work well with automatically
 *           generated data.
 *
 * Input:    If 'g' is specified on the command line, none.
 *           If 'i', mass, initial position and initial velocity of
 *              each particle
 * Output:   If the output frequency is k, then position and velocity of
 *              each particle at every kth timestep.  This value is
 *              ignored (but still necessary) if NO_OUTPUT is defined
 *
 *    for each timestep t {
 *       for each particle i I own
 *          compute F(i), the total force on i
 *       for each particle i I own
 *          update position and velocity of i using F(i) = ma
 *       Allgather positions
 *       if (output step) {
 *          Allgather velocities
 *          Output new positions and velocities
 *       }
 *    }
 *
 * Force:    The force on particle i due to particle k is given by
 *
 *    -G m_i m_k (s_i - s_k)/|s_i - s_k|^3
 *
 * Here, m_j is the mass of particle j, s_j is its position vector
 * (at time t), and G is the gravitational constant (see below).
 *
 * Note that the force on particle k due to particle i is
 * -(force on i due to k).  So we could approximately halve the number
 * of force computations.  This version of the program does not
 * exploit this.
 *
 * Integration:  We use Euler's method:
 *
 *    v_i(t+1) = v_i(t) + h v'_i(t)
 *    s_i(t+1) = s_i(t) + h v_i(t)
 *
 * Here, v_i(u) is the velocity of the ith particle at time u and
 * s_i(u) is its position.
 *
 * Notes:
 * 1.  Each process stores the masses of all the particles:  the
 *     masses array has dimension n = number of particles.
 *
 * IPP:  Section 6.1.9 (pp. 290 and ff.)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>

#define DIM 2  /* Two-dimensional system */
#define X 0    /* x-coordinate subscript */
#define Y 1    /* y-coordinate subscript */

typedef double vect_t[DIM];  /* Vector type for position, etc. */

/* Global variables.  Except or vel all are unchanged after being set */
const double G = 6.673e-11;  /* Gravitational constant. */
                             /* Units are m^3/(kg*s^2)  */
int my_rank, comm_sz;
MPI_Comm comm;
MPI_Datatype vect_mpi_t;

/* Scratch array used by process 0 for global velocity I/O */
vect_t *vel = NULL;

void Usage(char* prog_name);
void Get_args(int argc, char* argv[], int* n_p, int* n_steps_p,
      double* delta_t_p, int* output_freq_p, char* g_i_p);
void Get_init_cond(double masses[], vect_t pos[],
      double loc_masses[], vect_t owned_pos[],
      vect_t loc_vel[], int n, int loc_n);
void Gen_init_cond(double masses[], vect_t pos[],
      double loc_masses[], vect_t owned_pos[],
      vect_t loc_vel[], int n, int loc_n);
void Output_state(double time, vect_t pos[],
      vect_t owned_pos[], vect_t loc_vel[], int n, int loc_n);

// calc force on local body i exerted by the other owned bodies
void Compute_local_force(int i, double masses[], vect_t pos[],
      int loc_n, vect_t force) {

   force[X] = force[Y] = 0.0;

   for (int k = 0; k < loc_n; k++) {
      // if it's the same body skip because that can't happen
      if (k == i)
         continue;

      // displacements
      double dx = pos[i][X] - pos[k][X];
      double dy = pos[i][Y] - pos[k][Y];

      // distance cubed gives
      double len = sqrt(dx*dx + dy*dy);
      double len_3 = len*len*len;

      double mg = -G*masses[i]*masses[k]; // -G to direct graviy to source
      double factor = mg / len_3;

      // add body's contribution to the total force
      force[X] += dx * factor;
      force[Y] += dy * factor;
   }
}

/*--------------------------------------------------------------------*/
int main(int argc, char* argv[]) {
   int n;                      /* Total number of particles  */
   int loc_n;                  /* Number of my particles     */
   int n_steps;                /* Number of timesteps        */
   int step;                   /* Current step               */
   int loc_part;               /* Current local particle     */
   int output_freq;            /* Frequency of output        */
   double delta_t;             /* Size of timestep           */
   double t;                   /* Current Time               */
   double* masses = NULL;     /* Root-only initialisation scratch. */
   vect_t* pos = NULL;         /* Root-only initialisation/output scratch. */
   vect_t* loc_vel;            /* Velocities of my particles */
   vect_t* ring_forces;        /* Totals for ring forces     */
   double* loc_masses;         /* Masses owned by this rank  */
   vect_t* owned_pos;          /* Storage for owned pos      */
   double* travel;             /* Packed */

   char g_i;                   /*_G_en or _i_nput init conds */
   double start, finish;       /* For timings                */

   MPI_Init(&argc, &argv);
   comm = MPI_COMM_WORLD;
   MPI_Comm_size(comm, &comm_sz);
   MPI_Comm_rank(comm, &my_rank);

   // logic to define the ring topology
   // basically defining each process's neighour

   // need the rank to send
   int next_rank = (my_rank + 1) % comm_sz;

   // rank to receive from
   int prev_rank = (my_rank + comm_sz - 1) % comm_sz;

   Get_args(argc, argv, &n, &n_steps, &delta_t, &output_freq, &g_i);
   loc_n = n/comm_sz;  /* n should be evenly divisible by comm_sz */
   if (my_rank == 0) {
      masses = malloc(n * sizeof(double));
      pos = malloc(n * sizeof(vect_t));
      if (masses == NULL || pos == NULL)
         MPI_Abort(comm, 1);
   }
   ring_forces = malloc(loc_n * sizeof(vect_t));
   if (ring_forces == NULL) {
      MPI_Abort(comm, 1);
   }
   loc_vel = malloc(loc_n*sizeof(vect_t));

   loc_masses = malloc(loc_n * sizeof(double));
   owned_pos = malloc(loc_n * sizeof(vect_t));

   if (loc_masses == NULL || owned_pos == NULL || loc_vel == NULL) {
      MPI_Abort(comm, 1);
   }

   if (my_rank == 0) {
      vel = malloc(n * sizeof(vect_t));
      if (vel == NULL)
         MPI_Abort(comm, 1);
   }
   MPI_Type_contiguous(DIM, MPI_DOUBLE, &vect_mpi_t);
   MPI_Type_commit(&vect_mpi_t);

   if (g_i == 'i')
      Get_init_cond(masses, pos, loc_masses, owned_pos, loc_vel, n, loc_n);
   else
      Gen_init_cond(masses, pos, loc_masses, owned_pos, loc_vel, n, loc_n);

   /* Masses are now owned locally; discard root initialisation scratch. */
   free(masses);
   masses = NULL;

   travel = malloc(3 * loc_n * sizeof(double));
   if (travel == NULL) {
      MPI_Abort(comm, 1);
   }

   // pack the fields and their positions
   for (int i = 0; i < loc_n; i++) {
      travel[i] = loc_masses[i];
      travel[loc_n + 2*i] = owned_pos[i][X];
      travel[loc_n + 2*i + 1] = owned_pos[i][Y];
   }

   start = MPI_Wtime();

#  ifndef NO_OUTPUT
   Output_state(0.0, pos, owned_pos, loc_vel, n, loc_n);
#  endif
   for (step = 1; step <= n_steps; step++) {
      t = step*delta_t;

      // Start each owned body's force sum with local contributions
      for (loc_part = 0; loc_part < loc_n; loc_part++) {
         Compute_local_force(loc_part, loc_masses, owned_pos,
               loc_n, ring_forces[loc_part]);
      }

      // will be packing the rank's bodies into one message
      // reload our own current block before every ring pass
      for (int i = 0; i < loc_n; i++) {
         travel[i] = loc_masses[i];
         travel[loc_n + 2*i] = owned_pos[i][X];
         travel[loc_n + 2*i + 1] = owned_pos[i][Y];
      }

      // exchanging the messages for each rank
      for (int stage = 0; stage < comm_sz - 1; stage++) {
         MPI_Sendrecv_replace(
            travel, 3 * loc_n, MPI_DOUBLE,
            next_rank, 1,
            prev_rank, 1,
            comm, MPI_STATUS_IGNORE
         );

         for (int i = 0; i < loc_n; i++) {
            for (int k = 0; k < loc_n; k++) {
               // Get the source position from the packed buffer
               double dx = owned_pos[i][X] - travel[loc_n + 2*k];
               double dy = owned_pos[i][Y] - travel[loc_n + 2*k + 1];

               double len = sqrt(dx*dx + dy*dy);
               double len_3 = len*len*len;

               double mg = -G * loc_masses[i] * travel[k]; // tiems with body mass
               double factor = mg / len_3;

               ring_forces[i][X] += dx * factor;
               ring_forces[i][Y] += dy * factor;
            }
         }
      }

      // updates owned bodies using the completed ring forces
      for (int i = 0; i < loc_n; i++) {
         double factor = delta_t / loc_masses[i];

         // Euler position update using the old velocity
         owned_pos[i][X] += delta_t * loc_vel[i][X];
         owned_pos[i][Y] += delta_t * loc_vel[i][Y];

         // Update velocity using acceleration = force / mass
         loc_vel[i][X] += factor * ring_forces[i][X];
         loc_vel[i][Y] += factor * ring_forces[i][Y];
      }

#     ifndef NO_OUTPUT
      if (step % output_freq == 0)
         Output_state(t, pos, owned_pos, loc_vel, n, loc_n);
#     endif
   }

   finish = MPI_Wtime();
   if (my_rank == 0)
      printf("Elapsed time = %e seconds\n", finish-start);

   MPI_Type_free(&vect_mpi_t);
   free(pos);
   free(ring_forces);
   free(loc_vel);
   // freeing up masses and position mem
   free(loc_masses);
   free(owned_pos);
   free(travel);

   if (my_rank == 0) free(vel);

   MPI_Finalize();

   return 0;
}  /* main */


/*---------------------------------------------------------------------
 * Function: Usage
 * Purpose:  Print instructions for command-line and exit
 * In arg:
 *    prog_name:  the name of the program as typed on the command-line
 */
void Usage(char* prog_name) {

   fprintf(stderr, "usage: mpiexec -n <number of processes> %s\n", prog_name);
   fprintf(stderr, "   <number of particles> <number of timesteps>\n");
   fprintf(stderr, "   <size of timestep> <output frequency>\n");
   fprintf(stderr, "   <g|i>\n");
   fprintf(stderr, "   'g': program should generate init conds\n");
   fprintf(stderr, "   'i': program should get init conds from stdin\n");

   exit(0);
}  /* Usage */


/*---------------------------------------------------------------------
 * Function:  Get_args
 * Purpose:   Get command line args
 * In args:
 *    argc:            number of command line args
 *    argv:            command line args
 * Out args:
 *    n_p:             pointer to n, the number of particles
 *    n_steps_p:       pointer to n_steps, the number of timesteps
 *    delta_t_p:       pointer to delta_t, the size of each timestep
 *    output_freq_p:   pointer to output_freq, which is the number of
 *                     timesteps between steps whose output is printed
 *    g_i_p:           pointer to char which is 'g' if the init conds
 *                     should be generated by the program and 'i' if
 *                     they should be read from stdin
 */
void Get_args(int argc, char* argv[], int* n_p, int* n_steps_p,
      double* delta_t_p, int* output_freq_p, char* g_i_p) {
   if (my_rank == 0) {
      if (argc != 6) Usage(argv[0]);
      *n_p = strtol(argv[1], NULL, 10);
      *n_steps_p = strtol(argv[2], NULL, 10);
      *delta_t_p = strtod(argv[3], NULL);
      *output_freq_p = strtol(argv[4], NULL, 10);
      *g_i_p = argv[5][0];
   }
   MPI_Bcast(n_p, 1, MPI_INT, 0, comm);
   MPI_Bcast(n_steps_p, 1, MPI_INT, 0, comm);
   MPI_Bcast(delta_t_p, 1, MPI_DOUBLE, 0, comm);
   MPI_Bcast(output_freq_p, 1, MPI_INT, 0, comm);
   MPI_Bcast(g_i_p, 1, MPI_CHAR, 0, comm);

   if (*n_p <= 0 || *n_steps_p < 0 || *delta_t_p <= 0) {
      if (my_rank == 0) Usage(argv[0]);
      MPI_Finalize();
      exit(0);
   }
   if (*g_i_p != 'g' && *g_i_p != 'i') {
      if (my_rank == 0) Usage(argv[0]);
      MPI_Finalize();
      exit(0);
   }
#  ifdef DEBUG
   if (my_rank == 0) {
      printf("n = %d\n", *n_p);
      printf("n_steps = %d\n", *n_steps_p);
      printf("delta_t = %e\n", *delta_t_p);
      printf("output_freq = %d\n", *output_freq_p);
      printf("g_i = %c\n", *g_i_p);
   }
#  endif
}  /* Get_args */


/*---------------------------------------------------------------------
 * Function:   Get_init_cond
 * Purpose:    Read in initial conditions:  mass, position and velocity
 *             for each particle
 * In args:
 *    n:       total number of particles
 *    loc_n:   number of particles assigned to this process
 * Out args:
 *    masses:  global array of the masses of the particles
 *    pos:     global array of positions
 *    loc_vel: local array of velocities assigned to this process.
 *
 * Global var:
 *    vel:     Scratch.  Used by process 0 for global velocities
 */
void Get_init_cond(double masses[], vect_t pos[],
      double loc_masses[], vect_t owned_pos[],
      vect_t loc_vel[], int n, int loc_n) {
   int part;

   if (my_rank == 0) {
      printf("For each particle, enter (in order):\n");
      printf("   its mass, its x-coord, its y-coord, ");
      printf("its x-velocity, its y-velocity\n");
      for (part = 0; part < n; part++) {
         scanf("%lf", &masses[part]);
         scanf("%lf", &pos[part][X]);
         scanf("%lf", &pos[part][Y]);
         scanf("%lf", &vel[part][X]);
         scanf("%lf", &vel[part][Y]);
      }
   }
   /* Distribute one owned block to each rank, including rank 0. */
   MPI_Scatter(masses, loc_n, MPI_DOUBLE,
         loc_masses, loc_n, MPI_DOUBLE, 0, comm);
   MPI_Scatter(pos, loc_n, vect_mpi_t,
         owned_pos, loc_n, vect_mpi_t, 0, comm);
   MPI_Scatter(vel, loc_n, vect_mpi_t,
         loc_vel, loc_n, vect_mpi_t, 0, comm);
}  /* Get_init_cond */

/*---------------------------------------------------------------------
 * Function:  Gen_init_cond
 * Purpose:   Generate initial conditions:  mass, position and velocity
 *            for each particle
 * In args:
 *    n:       total number of particles
 *    loc_n:   number of particles assigned to this process
 * Out args:
 *    masses:  global array of the masses of the particles
 *    pos:     global array of positions
 *    loc_vel: local array of velocities assigned to this process.
 * Global var:
 *    vel:     Scratch.  Used by process 0 for global velocities
 *
 * Note:      The initial conditions place all particles at
 *            equal intervals on the nonnegative x-axis with
 *            identical masses, and identical initial speeds
 *            parallel to the y-axis.  However, some of the
 *            velocities are in the positive y-direction and
 *            some are negative.
 */
void Gen_init_cond(double masses[], vect_t pos[],
      double loc_masses[], vect_t owned_pos[],
      vect_t loc_vel[], int n, int loc_n) {
   int part;
   double mass = 5.0e24;
   double gap = 1.0e5;
   double speed = 3.0e4;

   if (my_rank == 0) {
//    srandom(1);
      for (part = 0; part < n; part++) {
         masses[part] = mass;
         pos[part][X] = part*gap;
         pos[part][Y] = 0.0;
         vel[part][X] = 0.0;
//       if (random()/((double) RAND_MAX) >= 0.5)
         if (part % 2 == 0)
            vel[part][Y] = speed;
         else
            vel[part][Y] = -speed;
      }
   }

   /* Distribute one owned block to each rank, including rank 0. */
   MPI_Scatter(masses, loc_n, MPI_DOUBLE,
         loc_masses, loc_n, MPI_DOUBLE, 0, comm);
   MPI_Scatter(pos, loc_n, vect_mpi_t,
         owned_pos, loc_n, vect_mpi_t, 0, comm);
   MPI_Scatter(vel, loc_n, vect_mpi_t,
         loc_vel, loc_n, vect_mpi_t, 0, comm);
}  /* Gen_init_cond */


/*---------------------------------------------------------------------
 * Function:   Output_state
 * Purpose:    Print the current state of the system
 * In args:
 *    time:    current time
 *    pos:     changed to root-only output scratch
 *    owned_pos: local owned positions to gather
 *    loc_vel: local array of my particle velocities
 *    n:       total number of particles
 *    loc_n:   number of my particles
 */
void Output_state(double time, vect_t pos[],
      vect_t owned_pos[], vect_t loc_vel[], int n, int loc_n) {
   int part;

   // Collect owned positions on rank 0 in global body order
   MPI_Gather(owned_pos, loc_n, vect_mpi_t,
         pos, loc_n, vect_mpi_t, 0, comm);

   MPI_Gather(loc_vel, loc_n, vect_mpi_t, vel, loc_n, vect_mpi_t,
         0, comm);
   if (my_rank == 0) {
      printf("%.2f\n", time);
      for (part = 0; part < n; part++) {
         printf("%3d %10.3e ", part, pos[part][X]);
         printf("  %10.3e ", pos[part][Y]);
         printf("  %10.3e ", vel[part][X]);
         printf("  %10.3e\n", vel[part][Y]);
      }
      printf("\n");
   }
}  /* Output_state */
