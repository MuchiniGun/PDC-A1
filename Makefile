CC ?= gcc
ifeq ($(origin CC), default)
CC = gcc
endif
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

.PHONY: all originals reference smoke test-comparator check-validation check-critical-baseline check-critical-team check-critical check-locks-setup check-locks check-part2a clean

all: originals

PART2B_NAMES := basic reduced-default reduced-forces-cyclic reduced-all-cyclic
PART2B_BINS := $(addprefix $(BUILD_DIR)/part2b-,$(PART2B_NAMES))
.PHONY: check-build-modes
check-build-modes: reference $(PART2B_BINS) $(addsuffix -validate,$(PART2B_BINS)) $(addsuffix -no-output,$(PART2B_BINS))
	$(CC) --version
	bash tests/check_build_modes.sh

.PHONY: check-basic
$(BUILD_DIR)/part2b-basic: part2b_basic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-basic-validate: part2b_basic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-basic-no-output: part2b_basic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-basic: reference $(BUILD_DIR)/part2b-basic $(BUILD_DIR)/part2b-basic-validate $(BUILD_DIR)/part2b-basic-no-output
	bash tests/check_part2b.sh basic

.PHONY: check-reduced-default
$(BUILD_DIR)/part2b-reduced-default: part2b_reduced_default.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-default-validate: part2b_reduced_default.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-default-no-output: part2b_reduced_default.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-reduced-default: reference $(BUILD_DIR)/part2b-reduced-default $(BUILD_DIR)/part2b-reduced-default-validate $(BUILD_DIR)/part2b-reduced-default-no-output
	bash tests/check_part2b.sh reduced-default

originals: $(ORIGINAL_BINS)

.PHONY: check-reduced-all-cyclic
$(BUILD_DIR)/part2b-reduced-all-cyclic: part2b_reduced_all_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-all-cyclic-validate: part2b_reduced_all_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-all-cyclic-no-output: part2b_reduced_all_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-reduced-all-cyclic: reference $(BUILD_DIR)/part2b-reduced-all-cyclic $(BUILD_DIR)/part2b-reduced-all-cyclic-validate $(BUILD_DIR)/part2b-reduced-all-cyclic-no-output
	bash tests/check_part2b.sh reduced-all-cyclic

.PHONY: check-reduced-forces-cyclic
$(BUILD_DIR)/part2b-reduced-forces-cyclic: part2b_reduced_forces_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-forces-cyclic-validate: part2b_reduced_forces_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/part2b-reduced-forces-cyclic-no-output: part2b_reduced_forces_cyclic.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-reduced-forces-cyclic: reference $(BUILD_DIR)/part2b-reduced-forces-cyclic $(BUILD_DIR)/part2b-reduced-forces-cyclic-validate $(BUILD_DIR)/part2b-reduced-forces-cyclic-no-output
	bash tests/check_part2b.sh reduced-forces-cyclic

reference: $(REFERENCE_BINS)

$(BUILD_DIR)/locks: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< $(LDLIBS) -o $@

$(BUILD_DIR)/locks-validate: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DVALIDATE $< $(LDLIBS) -o $@

$(BUILD_DIR)/locks-no-output: part2a_locks.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) -DNO_OUTPUT $< $(LDLIBS) -o $@

check-locks-setup: reference $(BUILD_DIR)/locks $(BUILD_DIR)/locks-validate $(BUILD_DIR)/locks-no-output
	bash tests/check_locks_setup.sh

check-locks: reference $(BUILD_DIR)/locks $(BUILD_DIR)/locks-validate $(BUILD_DIR)/locks-no-output
	bash tests/check_locks_setup.sh
	bash tests/check_locks.sh

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
	bash tests/check_part2a.sh critical

check-part2a: reference $(BUILD_DIR)/critical $(BUILD_DIR)/critical-validate $(BUILD_DIR)/critical-no-output $(BUILD_DIR)/locks $(BUILD_DIR)/locks-validate $(BUILD_DIR)/locks-no-output
	bash tests/check_part2a.sh critical
	bash tests/check_part2a.sh locks
	bash tests/check_standalone.sh

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
