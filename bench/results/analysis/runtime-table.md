# Mean wall-clock time (seconds)

1600 particles, 1000 steps, dt=0.001; 5 measured repeats per configuration.

| Variant | 1 threads | 4 threads | 8 threads | 16 threads | 32 threads |
| --- | ---: | ---: | ---: | ---: | ---: |
| Basic | 11.639444 | 3.104776 | 2.919163 | 2.774793 | 2.717654 |
| Reduced Default | 4.606539 | 2.133574 | 1.416260 | 1.599893 | 1.691361 |
| Reduced Forces Cyclic | 4.570193 | 1.244142 | 1.428103 | 1.537290 | 1.655695 |
| Reduced All Cyclic | 4.580105 | 1.342691 | 1.644049 | 1.565755 | 1.644474 |

Speedup = the same variant's one-thread mean / its mean at p threads.
Efficiency (%) = 100 × speedup / p.
CV (%) = 100 × sample standard deviation / mean.
All valid measurements are retained; the minimum is supporting data, not the reported average.
