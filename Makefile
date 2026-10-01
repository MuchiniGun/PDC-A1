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

.PHONY: all originals reference smoke test-comparator check-validation clean

all: originals

originals: $(ORIGINAL_BINS)

reference: $(REFERENCE_BINS)

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
