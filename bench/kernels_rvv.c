/*
 * M3 benchmark -- hand-written RVV intrinsics kernels.
 *
 * Built with clang-19 -O2 --target=riscv64-unknown-elf -march=rv64gcv.
 * The algorithms follow the semantic reference in src/native/kernel.c (the
 * shipping C kernel) so the benchmark measures the same strategy the library
 * actually uses:
 *
 *   sum, dot   e32m1 loads widened into e64m2 accumulators
 *              (vwadd.wv / vwmacc.vv), one vredsum at the end;
 *   count_ge   vmsge.vx + vcpop.m, accumulated in a scalar;
 *   filter     vmsge.vx + vcpop.m + vcompress.vm, order preserving;
 *   prefix_sum chunked Hillis-Steele scan (vslideup + vadd) with a scalar
 *              carry between chunks; all 32-bit adds are modular.
 *
 * Vector length is chosen at run time with vsetvl (e32m1), so the code is
 * VLEN-agnostic; on this spike VLEN=128 makes VLMAX(e32m1) = 4.
 */
#include <riscv_vector.h>

#include "bench.h"

/* (vlenb << 32) | vlmax(e32m1); read by bench/main.c and printed as VLPROBE. */
uint64_t bench_vl_probe(void) {
  uint64_t vlenb;
  __asm__ volatile("csrr %0, vlenb" : "=r"(vlenb));
  return (vlenb << 32) | (uint64_t)__riscv_vsetvlmax_e32m1();
}

int64_t k_sum(const int32_t *a, int32_t n, int32_t reps) {
  uint64_t total = 0;
  for (int32_t r = 0; r < reps; r++) {
    const size_t vlmax64 = __riscv_vsetvlmax_e64m2();
    vint64m2_t acc = __riscv_vmv_v_x_i64m2(0, vlmax64);
    int32_t i = 0;
    while (i < n) {
      size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
      vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
      acc = __riscv_vwadd_wv_i64m2(acc, v, vl);
      i += (int32_t)vl;
    }
    vint64m1_t red = __riscv_vredsum_vs_i64m2_i64m1(
        acc, __riscv_vmv_v_x_i64m1(0, 1), vlmax64);
    total += (uint64_t)__riscv_vmv_x_s_i64m1_i64(red);
  }
  return (int64_t)total;
}

int32_t k_count_ge(const int32_t *a, int32_t n, int32_t thr, int32_t reps) {
  uint32_t total = 0;
  for (int32_t r = 0; r < reps; r++) {
    uint32_t c = 0;
    int32_t i = 0;
    while (i < n) {
      size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
      vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
      vbool32_t m = __riscv_vmsge_vx_i32m1_b32(v, thr, vl);
      c += (uint32_t)__riscv_vcpop_m_b32(m, vl);
      i += (int32_t)vl;
    }
    total += c;
  }
  return bench_wrap_i32(total);
}

void k_prefix_sum(int32_t *a, int32_t n, int32_t reps) {
  const size_t vlmax = __riscv_vsetvlmax_e32m1();
  const vint32m1_t zero = __riscv_vmv_v_x_i32m1(0, vlmax);
  for (int32_t r = 0; r < reps; r++) {
    int32_t carry = 0;
    int32_t i = 0;
    while (i < n) {
      size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
      vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
      /* Intra-chunk inclusive scan: 32-bit modular adds, so the result matches
       * the scalar uint32_t accumulator bit for bit. */
      for (size_t off = 1; off < vl; off <<= 1) {
        v = __riscv_vadd_vv_i32m1(v, __riscv_vslideup_vx_i32m1(zero, v, off, vl),
                                  vl);
      }
      v = __riscv_vadd_vx_i32m1(v, carry, vl);
      vint32m1_t last = __riscv_vslidedown_vx_i32m1(v, vl - 1, vl);
      carry = __riscv_vmv_x_s_i32m1_i32(last);
      __riscv_vse32_v_i32m1(a + i, v, vl);
      i += (int32_t)vl;
    }
  }
}

int32_t k_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out,
                 int32_t reps) {
  int32_t j = 0;
  for (int32_t r = 0; r < reps; r++) {
    j = 0;
    int32_t i = 0;
    while (i < n) {
      size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
      vint32m1_t v = __riscv_vle32_v_i32m1(a + i, vl);
      vbool32_t m = __riscv_vmsge_vx_i32m1_b32(v, thr, vl);
      size_t cnt = __riscv_vcpop_m_b32(m, vl);
      __riscv_vse32_v_i32m1(out + j, __riscv_vcompress_vm_i32m1(v, m, vl), cnt);
      j += (int32_t)cnt;
      i += (int32_t)vl;
    }
  }
  return j;
}

int64_t k_dot(const int32_t *a, const int32_t *b, int32_t n, int32_t reps) {
  uint64_t total = 0;
  for (int32_t r = 0; r < reps; r++) {
    const size_t vlmax64 = __riscv_vsetvlmax_e64m2();
    vint64m2_t acc = __riscv_vmv_v_x_i64m2(0, vlmax64);
    int32_t i = 0;
    while (i < n) {
      size_t vl = __riscv_vsetvl_e32m1((size_t)(n - i));
      vint32m1_t va = __riscv_vle32_v_i32m1(a + i, vl);
      vint32m1_t vb = __riscv_vle32_v_i32m1(b + i, vl);
      acc = __riscv_vwmacc_vv_i64m2(acc, va, vb, vl);
      i += (int32_t)vl;
    }
    vint64m1_t red = __riscv_vredsum_vs_i64m2_i64m1(
        acc, __riscv_vmv_v_x_i64m1(0, 1), vlmax64);
    total += (uint64_t)__riscv_vmv_x_s_i64m1_i64(red);
  }
  return (int64_t)total;
}
