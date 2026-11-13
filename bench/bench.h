/*
 * M3 spike instruction-count benchmark -- shared declarations.
 *
 * bench/kernels.c     plain C, compiled twice: gcc -O2 -march=rv64gc (scalar)
 *                     and clang -O3 -march=rv64gcv (auto-vectorized).
 * bench/kernels_rvv.c hand-written RVV intrinsics (clang -O2 -march=rv64gcv).
 *
 * Every tier exports the same five prototypes, so a single bench/main.c is
 * linked against each object file and the driver code is byte-identical
 * across tiers. Semantics follow docs/SPEC.md: Int64 accumulation for
 * sum/dot, 32-bit wrapping for prefix_sum, order-preserving filter.
 */
#ifndef BENCH_H
#define BENCH_H

#include <stdint.h>

/* ---- HTIF platform (bench/platform_htif.c) ---- */
void putc_(char c);
void puts_(const char *s);
void put_u64(uint64_t v);
void put_hex(uint64_t v);
void put_hex64(uint64_t v);
void on_trap(uint64_t cause, uint64_t epc, uint64_t tval);
void exit_qemu(int code);
uint64_t rdinstret_(void);

/* ---- tier kernels (bench/kernels.c or bench/kernels_rvv.c) ---- */
int64_t k_sum(const int32_t *a, int32_t n, int32_t reps);
int32_t k_count_ge(const int32_t *a, int32_t n, int32_t thr, int32_t reps);
void k_prefix_sum(int32_t *a, int32_t n, int32_t reps);
int32_t k_filter(const int32_t *a, int32_t n, int32_t thr, int32_t *out,
                 int32_t reps);
int64_t k_dot(const int32_t *a, const int32_t *b, int32_t n, int32_t reps);

/* VLEN probe: (vlenb << 32) | vlmax(e32m1); returns 0 for tiers without V. */
uint64_t bench_vl_probe(void);

/* Implementation-defined but bit-exact on GCC/clang for RISC-V: the low 32
 * bits reinterpreted as two's complement. Used so prefix_sum's 32-bit modular
 * wrap (SPEC 4.3) never relies on signed overflow UB. */
static inline int32_t bench_wrap_i32(uint32_t u) { return (int32_t)u; }

#endif /* BENCH_H */
