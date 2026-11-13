/*
 * M4 / P1(b) -- runtime parity: the shipping C kernel vs the benchmark kernels.
 *
 * Built twice by scripts/bench_parity.sh as RV64 Linux user-mode executables and
 * run under qemu-user 8.2 with the V extension enabled:
 *
 *   A1  gcc -march=rv64gc       src/native/kernel.c (C scalar branch)
 *       vs bench/kernels.c      k_*(..., reps = 1)
 *   A2  clang-19 -march=rv64gcv src/native/kernel.c (RVV intrinsics branch)
 *       vs bench/kernels_rvv.c  k_*(..., reps = 1)
 *
 * Why this exists: the 45-row table in docs/BENCHMARKS.md is measured on
 * bench/kernels*.c, which are separate implementations that only claim to
 * mirror src/native/kernel.c. Without a runtime comparison the two can drift
 * apart and the published numbers would no longer describe the shipped code
 * (defect P1 in docs/plans/v0.1.0.md). This harness proves, at run time, that
 * both sides agree value by value / element by element on every primitive.
 *
 * Scope: the "auto" benchmark tier has no shipping counterpart -- the shipped
 * kernel is either the plain-C scalar branch or the RVV intrinsics branch,
 * never auto-vectorized plain C -- so it is not part of the parity comparison
 * (documented in docs/BENCHMARKS.md section 6).
 *
 * Inputs: the same deterministic data as bench/main.c (same LCG seed, same
 * pins a[0] = INT32_MAX and a[1] = INT32_MIN), for
 * n in {0, 1, 2, 3, 5, 7, 17, 1024} -- the sizes of the M2 exit criteria and of
 * rvv_selftest(), so the tail (n not a multiple of VLMAX) is covered too.
 *
 * Output protocol (parsed by scripts/bench_parity.sh):
 *
 *   PARITY_OK                                  every comparison passed
 *   PARITY_FAIL:<primitive>:<A1|A2>:<n>        first mismatch, then exit 1
 *
 * -DPARITY_PAIR='"A1"' / '"A2"' names the pair in failure lines.
 * -DPARITY_EXPECT_RVV makes the harness first run rvv_selftest() and require 0,
 * which proves the A2 binary really executed the RVV branch (return code 600
 * means "RVV branch compiled but not executed"); without that guard A2 could
 * silently degrade to a scalar-vs-RVV comparison.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bench.h"

/* src/native/kernel.c -- the shipped kernel. Declared here because kernel.c is
 * a native-stub source file, not a header (see docs/NATIVE_ABI.md). */
int64_t rvv_sum(const int32_t *a, int32_t n);
int32_t rvv_count_ge(const int32_t *a, int32_t n, int32_t thr);
void rvv_prefix_sum(int32_t *a, int32_t n);
int32_t rvv_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out);
int64_t rvv_dot(const int32_t *a, const int32_t *b, int32_t n);
int32_t rvv_selftest(void);

#ifndef PARITY_PAIR
#define PARITY_PAIR "?"
#endif

#define PARITY_MAX_N 1024

/* Same sizes as rvv_selftest() and as the M2 exit criteria. */
static const int32_t kSizes[] = {0, 1, 2, 3, 5, 7, 17, 1024};
static const int32_t kThresholds[] = {INT32_MIN, 0, INT32_MAX};

#define NSIZES ((int)(sizeof kSizes / sizeof kSizes[0]))
#define NTHRESHOLDS ((int)(sizeof kThresholds / sizeof kThresholds[0]))

static int32_t a_buf[PARITY_MAX_N];
static int32_t b_buf[PARITY_MAX_N];
static int32_t ref_buf[PARITY_MAX_N];
static int32_t got_buf[PARITY_MAX_N];
static int32_t out_ref[PARITY_MAX_N];
static int32_t out_got[PARITY_MAX_N];

/* Byte-identical to bench/main.c fill(): the parity input is the benchmark
 * input, so a mismatch also means the table does not describe this data. */
static void fill(int32_t *dst, int32_t n, uint32_t seed) {
  uint32_t x = seed;
  for (int32_t i = 0; i < n; i++) {
    x = x * 1664525u + 1013904223u;
    dst[i] = bench_wrap_i32(x);
  }
  if (n > 0) dst[0] = INT32_MAX;
  if (n > 1) dst[1] = INT32_MIN;
}

static void fail(const char *primitive, int32_t n) {
  printf("PARITY_FAIL:%s:%s:%d\n", primitive, PARITY_PAIR, (int)n);
  fflush(stdout);
  exit(1);
}

/* One size, every primitive. The benchmark kernels do REPS identical passes per
 * call; reps = 1 is the single-pass semantic the shipped kernel implements. */
static void check_size(int32_t n) {
  fill(a_buf, n, 0x9E3779B9u);
  fill(b_buf, n, 0x85EBCA6Bu);

  /* sum: Int64 result, bit for bit. */
  if (rvv_sum(a_buf, n) != k_sum(a_buf, n, 1)) fail("sum", n);

  /* count_ge: below / inside / above the Int32 range. */
  for (int t = 0; t < NTHRESHOLDS; t++) {
    const int32_t thr = kThresholds[t];
    if (rvv_count_ge(a_buf, n, thr) != k_count_ge(a_buf, n, thr, 1)) {
      fail("count_ge", n);
    }
  }

  /* prefix_sum: in place, so each side gets its own copy of the input. */
  memcpy(ref_buf, a_buf, (size_t)n * sizeof a_buf[0]);
  memcpy(got_buf, a_buf, (size_t)n * sizeof a_buf[0]);
  rvv_prefix_sum(ref_buf, n);
  k_prefix_sum(got_buf, n, 1);
  if (memcmp(ref_buf, got_buf, (size_t)n * sizeof a_buf[0]) != 0) {
    fail("prefix_sum", n);
  }

  /* filter: output length and every emitted element, order included. */
  for (int t = 0; t < NTHRESHOLDS; t++) {
    const int32_t thr = kThresholds[t];
    int32_t want;
    int32_t have;
    memset(out_ref, 0xA5, sizeof out_ref);
    memset(out_got, 0x5A, sizeof out_got);
    want = rvv_filter(a_buf, n, thr, out_ref);
    have = k_filter(a_buf, n, thr, out_got, 1);
    if (want != have) fail("filter", n);
    if (memcmp(out_ref, out_got, (size_t)want * sizeof a_buf[0]) != 0) {
      fail("filter", n);
    }
  }

  /* dot: Int64 result, bit for bit (a and b are both pinned to the extremes). */
  if (rvv_dot(a_buf, b_buf, n) != k_dot(a_buf, b_buf, n, 1)) fail("dot", n);
}

int main(void) {
#if defined(PARITY_EXPECT_RVV)
  /* 0 means the internal scalar-vs-RVV self test passed, i.e. the RVV branch of
   * src/native/kernel.c exists in this build and did execute. */
  int32_t selftest = rvv_selftest();
  if (selftest != 0) {
    printf("PARITY_FAIL:kernel_selftest:%s:%d\n", PARITY_PAIR, (int)selftest);
    fflush(stdout);
    return 1;
  }
#endif

  for (int i = 0; i < NSIZES; i++) check_size(kSizes[i]);

  printf("PARITY_OK\n");
  fflush(stdout);
  return 0;
}
