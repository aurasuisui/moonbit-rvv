/*
 * M3 spike instruction-count benchmark -- driver.
 *
 * One ELF per implementation tier (scalar / auto / rvv). Each ELF runs the
 * same 15 measurements (5 primitives x N in {1024, 8192, 65536}) and prints one
 * line per measurement; scripts/bench.sh parses the lines, asserts that the
 * three tiers agree on every checksum, asserts run-to-run determinism and
 * renders bench/results.md.
 *
 * Output protocol (whitespace separated, parsed by scripts/bench.sh):
 *
 *   TIER <tier>
 *   VLPROBE <vlenb> <vlen> <vlmax_e32m1>     (0 0 0 when the tier has no V)
 *   INFO n=<n> reps=<reps>
 *   RESULT <prim> <n> <reps> <instret> <chk>  (chk is 0x + 16 hex digits)
 *   DONE
 *
 * What is measured: rdinstret (retired instructions) around one kernel call
 * that performs REPS passes over the input. The counter is read only before
 * and after the call; the checksum and the input regeneration run outside the
 * measured region. The cycle CSR is never read anywhere in this harness.
 *
 * REPS is fixed per size (16 / 8 / 4) so the total number of element visits is
 * bounded: N * REPS = 16384, 65536 and 262144 per measurement.
 */
#include "bench.h"

/* Set by scripts/bench.sh: -DBENCH_TIER='"scalar"' and so on. */
#ifndef BENCH_TIER
#define BENCH_TIER "unknown"
#endif

#define N_SIZES 3
#define MAX_N 65536

static const int32_t kSizes[N_SIZES] = {1024, 8192, 65536};
static const int32_t kReps[N_SIZES] = {16, 8, 4};

/* Signed threshold in the middle of the Int32 range: count_ge accepts about
 * half of the elements and filter emits about half of them. */
static const int32_t kThr = 0;

static int32_t a_buf[MAX_N];
static int32_t b_buf[MAX_N];
static int32_t out_buf[MAX_N];

/* Deterministic input; the first two elements pin Int32 max/min so the
 * extreme values from SPEC section 3 are part of every measurement with n >= 2. */
static void fill(int32_t *dst, int32_t n, uint32_t seed) {
  uint32_t x = seed;
  for (int32_t i = 0; i < n; i++) {
    x = x * 1664525u + 1013904223u;
    dst[i] = bench_wrap_i32(x);
  }
  if (n > 0) dst[0] = INT32_MAX;
  if (n > 1) dst[1] = INT32_MIN;
}

/* FNV-1a 64 over the int32 element sequence. Only used to compare tiers, so a
 * cheap order-sensitive hash is enough; it never runs inside a measured region. */
#define FNV_OFFSET 0xcbf29ce484222325ull
#define FNV_PRIME 0x100000001b3ull

static uint64_t fnv_u32(uint64_t h, uint32_t v) {
  h ^= (uint64_t)v;
  h *= FNV_PRIME;
  return h;
}

static uint64_t fnv_seq(const int32_t *a, int32_t n) {
  uint64_t h = FNV_OFFSET;
  for (int32_t i = 0; i < n; i++) h = fnv_u32(h, (uint32_t)a[i]);
  return h;
}

static void report(const char *prim, int32_t n, int32_t reps, uint64_t inst,
                   uint64_t chk) {
  puts_("RESULT ");
  puts_(prim);
  putc_(' ');
  put_u64((uint64_t)n);
  putc_(' ');
  put_u64((uint64_t)reps);
  putc_(' ');
  put_u64(inst);
  putc_(' ');
  put_hex64(chk);
  puts_("\n");
}

static void bench_size(int32_t n, int32_t reps) {
  uint64_t t0, t1;

  puts_("INFO n=");
  put_u64((uint64_t)n);
  puts_(" reps=");
  put_u64((uint64_t)reps);
  puts_("\n");

  /* sum */
  fill(a_buf, n, 0x9E3779B9u);
  t0 = rdinstret_();
  int64_t r_sum = k_sum(a_buf, n, reps);
  t1 = rdinstret_();
  report("sum", n, reps, t1 - t0, (uint64_t)r_sum);

  /* count_ge */
  fill(a_buf, n, 0x9E3779B9u);
  t0 = rdinstret_();
  int32_t r_cnt = k_count_ge(a_buf, n, kThr, reps);
  t1 = rdinstret_();
  report("count_ge", n, reps, t1 - t0, (uint64_t)(uint32_t)r_cnt);

  /* prefix_sum (mutates a_buf; refilled before every later measurement) */
  fill(a_buf, n, 0x9E3779B9u);
  t0 = rdinstret_();
  k_prefix_sum(a_buf, n, reps);
  t1 = rdinstret_();
  report("prefix_sum", n, reps, t1 - t0, fnv_seq(a_buf, n));

  /* filter */
  fill(a_buf, n, 0x9E3779B9u);
  t0 = rdinstret_();
  int32_t r_filt = k_filter(a_buf, n, kThr, out_buf, reps);
  t1 = rdinstret_();
  {
    uint64_t chk = fnv_seq(out_buf, r_filt);
    chk = fnv_u32(chk, (uint32_t)r_filt);
    report("filter", n, reps, t1 - t0, chk);
  }

  /* dot */
  fill(a_buf, n, 0x9E3779B9u);
  fill(b_buf, n, 0x85EBCA6Bu);
  t0 = rdinstret_();
  int64_t r_dot = k_dot(a_buf, b_buf, n, reps);
  t1 = rdinstret_();
  report("dot", n, reps, t1 - t0, (uint64_t)r_dot);
}

int main(void) {
  uint64_t probe = bench_vl_probe();

  puts_("TIER " BENCH_TIER "\n");
  puts_("VLPROBE ");
  put_u64(probe >> 32);
  putc_(' ');
  put_u64((probe >> 32) * 8u);
  putc_(' ');
  put_u64(probe & 0xffffffffull);
  puts_("\n");

  for (int s = 0; s < N_SIZES; s++) bench_size(kSizes[s], kReps[s]);

  puts_("DONE\n");
  exit_qemu(0);
  return 0;
}
