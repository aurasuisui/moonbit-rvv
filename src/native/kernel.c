/*
 * aurasuisui/rvv -- native C kernel (M2).
 *
 * Every public primitive below has two branches selected at compile time:
 *
 *   - scalar: plain C over int32_t (hosts without the V extension, e.g.
 *     x86_64, and RISC-V toolchains that do not provide riscv_vector.h);
 *   - RVV:   <riscv_vector.h> intrinsics guarded by __riscv_vector (clang with
 *     -march=rv64gcv; GNU GCC 11 has no riscv_vector.h and does not define
 *     __riscv_vector).
 *
 * Semantics are specified in docs/SPEC.md:
 *   - sum / dot accumulate in int64_t;
 *   - prefix_sum wraps modulo 2^32 (implemented with unsigned arithmetic, or
 *     the hardware's modular vadd, so no signed-overflow UB);
 *   - filter preserves order;
 *   - dot length mismatch is rejected by the MoonBit side before reaching C.
 *
 * rvv_selftest() compares the scalar and RVV branches over fixed sizes and is
 * used by the native probe (SELFTEST_PASS / SELFTEST_FAIL:<code>). The MoonBit
 * side of the ABI (pointer, element width, length) is documented in
 * docs/NATIVE_ABI.md and exercised by the 40 black-box tests.
 */
#include <stdint.h>
#include <string.h>

#if defined(__riscv_vector)
#include <riscv_vector.h>
#define RVV_KERNEL 1
#else
#define RVV_KERNEL 0
#endif

/*
 * Bit-exact conversions from unsigned to signed without relying on
 * implementation-defined behaviour.
 */
static int32_t i32_from_u32(uint32_t u) {
  int32_t r;
  memcpy(&r, &u, sizeof r);
  return r;
}

static int64_t i64_from_u64(uint64_t u) {
  int64_t r;
  memcpy(&r, &u, sizeof r);
  return r;
}

/* ------------------------------------------------------------------ */
/* scalar branch                                                       */
/* ------------------------------------------------------------------ */

static int64_t scalar_sum(const int32_t *a, int32_t n) {
  uint64_t acc = 0;
  for (int32_t i = 0; i < n; i++) {
    acc += (uint64_t)(int64_t)a[i];
  }
  return i64_from_u64(acc);
}

static int32_t scalar_count_ge(const int32_t *a, int32_t n, int32_t thr) {
  int32_t count = 0;
  for (int32_t i = 0; i < n; i++) {
    if (a[i] >= thr) count++;
  }
  return count;
}

static void scalar_prefix_sum(int32_t *a, int32_t n) {
  uint32_t acc = 0;
  for (int32_t i = 0; i < n; i++) {
    acc += (uint32_t)a[i];
    a[i] = i32_from_u32(acc);
  }
}

static int32_t scalar_filter(const int32_t *a, int32_t n, int32_t thr,
                             int32_t *out) {
  int32_t j = 0;
  for (int32_t i = 0; i < n; i++) {
    if (a[i] >= thr) out[j++] = a[i];
  }
  return j;
}

static int64_t scalar_dot(const int32_t *a, const int32_t *b, int32_t n) {
  uint64_t acc = 0;
  for (int32_t i = 0; i < n; i++) {
    acc += (uint64_t)((int64_t)a[i] * (int64_t)b[i]);
  }
  return i64_from_u64(acc);
}

/* ------------------------------------------------------------------ */
/* RVV branch                                                          */
/* ------------------------------------------------------------------ */

#if RVV_KERNEL

/* Bumped by every RVV entry point; rvv_selftest() requires the expected number
 * of executions, which proves the intrinsics branch ran under qemu/spike. */
static volatile uint32_t rvv_exec_count;

static int64_t rvv_sum_v(const int32_t *a, int32_t n) {
  rvv_exec_count++;
  const size_t max_vl = __riscv_vsetvlmax_e64m2();
  vint64m2_t acc = __riscv_vmv_v_x_i64m2(0, max_vl);
  int32_t i = 0;
  while (i < n) {
    size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
    vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
    acc = __riscv_vwadd_wv_i64m2(acc, v, vl);
    i += (int32_t)vl;
  }
  vint64m1_t red = __riscv_vredsum_vs_i64m2_i64m1(
      acc, __riscv_vmv_v_x_i64m1(0, 1), max_vl);
  return (int64_t)__riscv_vmv_x_s_i64m1_i64(red);
}

static int32_t rvv_count_ge_v(const int32_t *a, int32_t n, int32_t thr) {
  rvv_exec_count++;
  int32_t count = 0;
  int32_t i = 0;
  while (i < n) {
    size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
    vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
    vbool32_t m = __riscv_vmsge_vx_i32m1_b32(v, thr, vl);
    count += (int32_t)__riscv_vcpop_m_b32(m, vl);
    i += (int32_t)vl;
  }
  return count;
}

static void rvv_prefix_sum_v(int32_t *a, int32_t n) {
  rvv_exec_count++;
  int32_t i = 0;
  int32_t carry = 0;
  while (i < n) {
    size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
    vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
    /* Hillis-Steele inclusive scan with vl < 32-bit-element lanes. The zero
     * merge operand makes slideup produce 0 in the vacated lanes, so the
     * vector add leaves them unchanged. */
    vint32m1_t zero = __riscv_vmv_v_x_i32m1(0, vl);
    for (size_t off = 1; off < vl; off <<= 1) {
      vint32m1_t shifted = __riscv_vslideup_vx_i32m1(zero, v, off, vl);
      v = __riscv_vadd_vv_i32m1(v, shifted, vl);
    }
    v = __riscv_vadd_vx_i32m1(v, carry, vl);
    vint32m1_t last = __riscv_vslidedown_vx_i32m1(v, vl - 1, vl);
    carry = __riscv_vmv_x_s_i32m1_i32(last);
    __riscv_vse32_v_i32m1(a + i, v, vl);
    i += (int32_t)vl;
  }
}

static int32_t rvv_filter_v(const int32_t *a, int32_t n, int32_t thr,
                            int32_t *out) {
  rvv_exec_count++;
  int32_t j = 0;
  int32_t i = 0;
  while (i < n) {
    size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
    vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
    vbool32_t m = __riscv_vmsge_vx_i32m1_b32(v, thr, vl);
    size_t cnt = __riscv_vcpop_m_b32(m, vl);
    vint32m1_t packed = __riscv_vcompress_vm_i32m1(v, m, vl);
    __riscv_vse32_v_i32m1(out + j, packed, cnt);
    j += (int32_t)cnt;
    i += (int32_t)vl;
  }
  return j;
}

static int64_t rvv_dot_v(const int32_t *a, const int32_t *b, int32_t n) {
  rvv_exec_count++;
  const size_t max_vl = __riscv_vsetvlmax_e64m2();
  vint64m2_t acc = __riscv_vmv_v_x_i64m2(0, max_vl);
  int32_t i = 0;
  while (i < n) {
    size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
    vint32m1_t va = __riscv_vle32_v_i32m1(a + i, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b + i, vl);
    acc = __riscv_vwmacc_vv_i64m2(acc, va, vb, vl);
    i += (int32_t)vl;
  }
  vint64m1_t red = __riscv_vredsum_vs_i64m2_i64m1(
      acc, __riscv_vmv_v_x_i64m1(0, 1), max_vl);
  return (int64_t)__riscv_vmv_x_s_i64m1_i64(red);
}

#endif /* RVV_KERNEL */

/* ------------------------------------------------------------------ */
/* public entry points                                                 */
/* ------------------------------------------------------------------ */

int64_t rvv_sum(const int32_t *a, int32_t n) {
#if RVV_KERNEL
  return rvv_sum_v(a, n);
#else
  return scalar_sum(a, n);
#endif
}

int32_t rvv_count_ge(const int32_t *a, int32_t n, int32_t thr) {
#if RVV_KERNEL
  return rvv_count_ge_v(a, n, thr);
#else
  return scalar_count_ge(a, n, thr);
#endif
}

void rvv_prefix_sum(int32_t *a, int32_t n) {
#if RVV_KERNEL
  rvv_prefix_sum_v(a, n);
#else
  scalar_prefix_sum(a, n);
#endif
}

int32_t rvv_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out) {
#if RVV_KERNEL
  return rvv_filter_v(a, n, thr, out);
#else
  return scalar_filter(a, n, thr, out);
#endif
}

int64_t rvv_dot(const int32_t *a, const int32_t *b, int32_t n) {
#if RVV_KERNEL
  return rvv_dot_v(a, b, n);
#else
  return scalar_dot(a, b, n);
#endif
}

/* ------------------------------------------------------------------ */
/* C self test: scalar branch vs RVV branch                            */
/* ------------------------------------------------------------------ */

/*
 * Fixed sizes used by the self test (also the sizes in the M2 exit criteria).
 * Return codes: 0 = pass; otherwise 100 * primitive + (case index + 1):
 *   1xx sum, 2xx count_ge, 3xx prefix_sum, 4xx filter, 5xx dot,
 *   600 = the RVV branch was compiled but not executed.
 * On builds without __riscv_vector there is no RVV branch to compare and the
 * function returns 0; the scalar branch is covered by the MoonBit black-box
 * tests (40 cases, native target).
 */
int32_t rvv_selftest(void) {
#if !RVV_KERNEL
  return 0;
#else
#define SELFTEST_MAX_N 1024
  static const int32_t sizes[] = {0, 1, 2, 3, 5, 7, 17, 1024};
  const int32_t cases = (int32_t)(sizeof sizes / sizeof sizes[0]);
  int32_t a[SELFTEST_MAX_N];
  int32_t b[SELFTEST_MAX_N];
  int32_t ref[SELFTEST_MAX_N];
  int32_t got[SELFTEST_MAX_N];
  int32_t out_ref[SELFTEST_MAX_N];
  int32_t out_got[SELFTEST_MAX_N];
  uint32_t state;

  for (int32_t c = 0; c < cases; c++) {
    const int32_t n = sizes[c];
    const int32_t code = c + 1;

    /* Deterministic data; the first two elements pin Int32::max/min so the
     * extremes are part of every case with n >= 2. */
    state = 0x9E3779B9u;
    for (int32_t i = 0; i < n; i++) {
      state = state * 1664525u + 1013904223u;
      a[i] = i32_from_u32(state);
    }
    if (n > 0) a[0] = INT32_MAX;
    if (n > 1) a[1] = INT32_MIN;

    /* sum */
    if (scalar_sum(a, n) != rvv_sum_v(a, n)) return 100 + code;

    /* count_ge: below / inside / above the data range */
    {
      static const int32_t thresholds[] = {INT32_MIN, 0, INT32_MAX};
      for (int32_t t = 0; t < 3; t++) {
        if (scalar_count_ge(a, n, thresholds[t]) !=
            rvv_count_ge_v(a, n, thresholds[t])) {
          return 200 + code;
        }
      }
    }

    /* prefix_sum */
    memcpy(ref, a, (size_t)n * sizeof(int32_t));
    memcpy(got, a, (size_t)n * sizeof(int32_t));
    scalar_prefix_sum(ref, n);
    rvv_prefix_sum_v(got, n);
    if (memcmp(ref, got, (size_t)n * sizeof(int32_t)) != 0) return 300 + code;

    /* filter */
    {
      int32_t want = scalar_filter(a, n, 0, out_ref);
      int32_t have = rvv_filter_v(a, n, 0, out_got);
      if (want != have) return 400 + code;
      if (memcmp(out_ref, out_got, (size_t)want * sizeof(int32_t)) != 0) {
        return 400 + code;
      }
    }

    /* dot */
    state = 0x85EBCA6Bu;
    for (int32_t i = 0; i < n; i++) {
      state = state * 1664525u + 1013904223u;
      b[i] = i32_from_u32(state);
    }
    if (scalar_dot(a, b, n) != rvv_dot_v(a, b, n)) return 500 + code;
  }

  /* Calls per case: sum 1, count_ge 3, prefix_sum 1, filter 1, dot 1 = 7. */
  if (rvv_exec_count != (uint32_t)cases * 7u) return 600;

  return 0;
#endif /* RVV_KERNEL */
}
