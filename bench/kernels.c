/*
 * M3 benchmark -- plain-C kernels, one source for two tiers.
 *
 *   scalar: riscv64-unknown-elf-gcc 10.2 -O2 -march=rv64gc
 *           (no V extension in the ISA string, so GCC cannot vectorize)
 *   auto:   clang-19 -O3 --target=riscv64-unknown-elf -march=rv64gcv
 *           (same source, LLVM free to auto-vectorize)
 *
 * Each function does REPS identical passes over the input, so one measured
 * call brackets exactly the work of REPS passes and the driver's loop overhead
 * is not part of the number.
 *
 * Semantics mirror docs/SPEC.md:
 *   - sum / dot accumulate in 64-bit (modular, i.e. bit-exact Int64 wrap);
 *   - prefix_sum accumulates in uint32_t, so the 32-bit wrap of SPEC 4.3 is
 *     defined behaviour rather than signed-overflow UB;
 *   - filter preserves the input order (out[0..j) is the stable subsequence).
 */
#include "bench.h"

/* Tiers without V report no VLEN (see bench_vl_probe). */
uint64_t bench_vl_probe(void) { return 0; }

int64_t k_sum(const int32_t *a, int32_t n, int32_t reps) {
  uint64_t acc = 0;
  for (int32_t r = 0; r < reps; r++) {
    for (int32_t i = 0; i < n; i++) acc += (uint64_t)(int64_t)a[i];
  }
  return (int64_t)acc;
}

int32_t k_count_ge(const int32_t *a, int32_t n, int32_t thr, int32_t reps) {
  uint32_t total = 0;
  for (int32_t r = 0; r < reps; r++) {
    uint32_t c = 0;
    for (int32_t i = 0; i < n; i++) {
      if (a[i] >= thr) c++;
    }
    total += c;
  }
  return bench_wrap_i32(total);
}

void k_prefix_sum(int32_t *a, int32_t n, int32_t reps) {
  for (int32_t r = 0; r < reps; r++) {
    uint32_t acc = 0;
    for (int32_t i = 0; i < n; i++) {
      acc += (uint32_t)a[i];
      a[i] = bench_wrap_i32(acc);
    }
  }
}

int32_t k_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out,
                 int32_t reps) {
  int32_t j = 0;
  for (int32_t r = 0; r < reps; r++) {
    j = 0;
    for (int32_t i = 0; i < n; i++) {
      if (a[i] >= thr) out[j++] = a[i];
    }
  }
  return j;
}

int64_t k_dot(const int32_t *a, const int32_t *b, int32_t n, int32_t reps) {
  uint64_t acc = 0;
  for (int32_t r = 0; r < reps; r++) {
    for (int32_t i = 0; i < n; i++) {
      acc += (uint64_t)((int64_t)a[i] * (int64_t)b[i]);
    }
  }
  return (int64_t)acc;
}
