CC ?= gcc
CFLAGS ?= -O2 -g -Wall -Wextra
OMPFLAGS ?= -fopenmp
LDLIBS ?= -lm

BUILD_DIR := build
ORIGINAL_BINS := $(BUILD_DIR)/reference-original \
	$(BUILD_DIR)/shared-original \
	$(BUILD_DIR)/basic-original \
	$(BUILD_DIR)/reduced-original
REFERENCE_BINS := $(BUILD_DIR)/reference-observation \
	$(BUILD_DIR)/reference-precise $(BUILD_DIR)/shared-precise

.PHONY: all originals reference smoke test-comparator check-validation check-critical-baseline check-critical-team check-critical check-locks-setup clean

all: originals

originals: $(ORIGINAL_BINS)

reference: $(REFERENCE_BINS)

$(BUILD_DIR)/locks: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/locks-validate: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/locks-no-output: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-locks-setup: reference $(BUILD_DIR)/locks $(BUILD_DIR)/locks-validate $(BUILD_DIR)/locks-no-output
	bash tests/check_locks_setup.sh

$(BUILD_DIR)/critical: part2a_critical.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/critical-validate: part2a_critical.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/critical-no-output: part2a_critical.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-critical-baseline: reference $(BUILD_DIR)/critical $(BUILD_DIR)/critical-validate $(BUILD_DIR)/critical-no-output
	bash tests/check_critical_baseline.sh

check-critical-team: reference $(BUILD_DIR)/critical $(BUILD_DIR)/critical-validate $(BUILD_DIR)/critical-no-output
	bash tests/check_critical_team.sh

check-critical: reference $(BUILD_DIR)/critical $(BUILD_DIR)/critical-validate $(BUILD_DIR)/critical-no-output
	bash tests/check_critical.sh

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/reference-original: nbody_red.c timer.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) nbody_red.c $(LDLIBS) -o $@

$(BUILD_DIR)/reference-observation: reference_nbody_red.c timer.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) reference_nbody_red.c $(LDLIBS) -o $@

$(BUILD_DIR)/reference-precise: reference_nbody_red.c timer.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -DVALIDATE reference_nbody_red.c $(LDLIBS) -o $@

$(BUILD_DIR)/shared-precise: reference_shared_forces.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/shared-original: nbody_shared_forces.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) nbody_shared_forces.c $(LDLIBS) -o $@

$(BUILD_DIR)/basic-original: omp_nbody_basic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) omp_nbody_basic.c $(LDLIBS) -o $@

$(BUILD_DIR)/reduced-original: omp_nbody_red.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) omp_nbody_red.c $(LDLIBS) -o $@

$(BUILD_DIR)/omp-smoke.c: | $(BUILD_DIR)
	printf '%s\n' '#include <omp.h>' '#include <stdio.h>' '' \
		'int main(void) {' \
		'    #pragma omp parallel num_threads(2)' \
		'    {' \
		'        #pragma omp single' \
		'        printf("observed_team=%d _OPENMP=%d\\n", omp_get_num_threads(), _OPENMP);' \
		'    }' \
		'    return 0;' \
		'}' > $@

$(BUILD_DIR)/omp-smoke: $(BUILD_DIR)/omp-smoke.c
	$(CC) $(CFLAGS) $(OMPFLAGS) $< -o $@

smoke: $(BUILD_DIR)/omp-smoke
	./$(BUILD_DIR)/omp-smoke

test-comparator:
	bash tests/test_compare_states.sh

check-validation: reference
	bash tests/test_compare_states.sh
	bash tests/check_references.sh

clean:
	rm -rf $(BUILD_DIR)
