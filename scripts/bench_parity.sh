#!/usr/bin/env bash
# M4 / P1(b): runtime parity -- the shipping C kernel vs the benchmark kernels.
#
#   bash scripts/bench_parity.sh
#
# The 45-row table in docs/BENCHMARKS.md is measured on bench/kernels*.c, which
# are SEPARATE implementations that only claim to mirror src/native/kernel.c.
# This script proves at run time that they still agree, so the published numbers
# keep describing the shipped code (defect P1 in docs/plans/v0.1.0.md).
#
# Two hosted RV64 Linux user-mode executables are built and run under qemu-user
# 8.2 with the V extension enabled; bench/parity_main.c is the driver of both:
#
#   A1  gcc -march=rv64gc        src/native/kernel.c (C scalar branch)
#       vs bench/kernels.c       k_*(..., reps = 1)
#   A2  clang-19 -march=rv64gcv  src/native/kernel.c (RVV intrinsics branch)
#       vs bench/kernels_rvv.c   k_*(..., reps = 1)
#
# Inputs are the same deterministic data as bench/main.c (same LCG seeds,
# a[0] = INT32_MAX, a[1] = INT32_MIN) for n = 0 1 2 3 5 7 17 1024. For each
# primitive the two sides are compared value by value / element by element:
# sum and dot as Int64 bit patterns, count_ge at three thresholds, prefix_sum
# element by element, filter by output length and every emitted element.
#
# A mismatch prints PARITY_FAIL:<primitive>:<A1|A2>:<n> and exits non-zero;
# success prints PARITY_OK.
#
# Asserts:
#   1. A1 (scalar branch) agrees with bench/kernels.c on all 5 primitives;
#   2. A2 (RVV branch) agrees with bench/kernels_rvv.c on all 5 primitives;
#   3. A2 really runs the RVV branch: the harness calls rvv_selftest() first and
#      requires 0 (600 means "RVV branch compiled but not executed");
#   4. A1 really is the scalar branch and A2 really is the RVV branch: the
#      vector-instruction counts of the two kernel objects are 0 and > 0
#      (checked with llvm-objdump when available, skipped otherwise).
#
# Scope: the "auto" benchmark tier has no shipping counterpart (the shipped
# kernel is plain-C scalar or RVV intrinsics, never auto-vectorized plain C), so
# it is not part of the comparison. See docs/BENCHMARKS.md section 6.
#
# Not a benchmark: no instruction counts and no performance claim come out of
# this script; the metric SSOT stays docs/BENCHMARKS.md.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BENCH_DIR="$REPO_ROOT/bench"
SRC_DIR="$REPO_ROOT/src"
BUILD_DIR="$REPO_ROOT/_build/parity"   # git-ignored via the "_build/" rule

GCC=${PARITY_GCC:-riscv64-linux-gnu-gcc}
CLANG=${PARITY_CLANG:-clang-19}
SYSROOT=${PARITY_SYSROOT:-/usr/riscv64-linux-gnu}
QEMU_RUNNER="$SCRIPT_DIR/run-qemu.sh"   # picks qemu 8.2 and checks the version

SIZES=(0 1 2 3 5 7 17 1024)

BASE_CFLAGS=(-O2 -Wall -Wextra -mabi=lp64d)
GCC_RV64GC=(-march=rv64gc)
GCC_RV64GCV=(-march=rv64gcv)
CLANG_RV64GCV=(--target=riscv64-linux-gnu "--sysroot=$SYSROOT" -march=rv64gcv
               -mabi=lp64d)

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: missing dependency: %s\n' "$1" >&2
    printf 'fix:   %s\n' "$2" >&2
    exit 1
  fi
}

need "$GCC" "sudo apt-get install -y gcc-riscv64-linux-gnu"
need "$CLANG" "sudo apt-get install -y clang-19   # RVV intrinsics live here"
[ -d "$SYSROOT" ] || fail "missing RISC-V sysroot $SYSROOT (fix: sudo apt-get install -y gcc-riscv64-linux-gnu libc6-dev-riscv64-cross)"
[ -f "$BENCH_DIR/parity_main.c" ] || fail "missing $BENCH_DIR/parity_main.c"

# Optional: RVV-capable disassembler (Ubuntu 22.04 binutils cannot decode RVV
# 1.0). Only the branch-identity sanity checks depend on it.
LLVM_OBJDUMP=$(command -v llvm-objdump-19 || command -v llvm-objdump || true)

# Vector instruction count over a whole object file.
vec_count() {  # $1 = object
  "$LLVM_OBJDUMP" -d --no-show-raw-insn --mattr=+m,+a,+f,+d,+c,+v "$1" |
    awk '$2 ~ /^v/ { n++ } END { print n + 0 }'
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

printf '== parity: shipping kernel vs bench kernel (RV64 Linux user mode)\n'
printf '   gcc:   %s\n' "$("$GCC" --version | head -n 1)"
printf '   clang: %s\n' "$("$CLANG" --version | head -n 1)"
printf '   sizes: %s\n' "${SIZES[*]}"

# ---------------------------------------------------------------------------
# A1: gcc rv64gc -- src/native/kernel.c C scalar branch vs bench/kernels.c
# ---------------------------------------------------------------------------
printf '== build A1: gcc -march=rv64gc  src/native/kernel.c (scalar) vs bench/kernels.c\n'
"$GCC" "${GCC_RV64GC[@]}" "${BASE_CFLAGS[@]}" \
  -c "$SRC_DIR/native/kernel.c" -o "$BUILD_DIR/a1_shipping_kernel.o"
"$GCC" "${GCC_RV64GC[@]}" "${BASE_CFLAGS[@]}" -I "$BENCH_DIR" \
  -c "$BENCH_DIR/kernels.c" -o "$BUILD_DIR/a1_bench_kernels.o"
"$GCC" "${GCC_RV64GC[@]}" "${BASE_CFLAGS[@]}" -I "$BENCH_DIR" \
  -DPARITY_PAIR='"A1"' -c "$BENCH_DIR/parity_main.c" -o "$BUILD_DIR/a1_main.o"
"$GCC" "${GCC_RV64GC[@]}" -mabi=lp64d \
  -o "$BUILD_DIR/parity_a1.exe" \
  "$BUILD_DIR/a1_main.o" "$BUILD_DIR/a1_shipping_kernel.o" \
  "$BUILD_DIR/a1_bench_kernels.o"

# ---------------------------------------------------------------------------
# A2: clang rv64gcv -- src/native/kernel.c RVV branch vs bench/kernels_rvv.c
# ---------------------------------------------------------------------------
# kernel.c goes to clang exactly as in the release cross recipe
# (docs/CROSS_COMPILE.md section 3); parity_main.c and the link stay with the
# cross GCC, which owns the glibc sysroot.
printf '== build A2: clang -march=rv64gcv src/native/kernel.c (RVV) vs bench/kernels_rvv.c\n'
"$CLANG" "${CLANG_RV64GCV[@]}" -O2 -Wall -Wextra \
  -c "$SRC_DIR/native/kernel.c" -o "$BUILD_DIR/a2_shipping_kernel.o"
"$CLANG" "${CLANG_RV64GCV[@]}" -O2 -Wall -Wextra -I "$BENCH_DIR" \
  -c "$BENCH_DIR/kernels_rvv.c" -o "$BUILD_DIR/a2_bench_kernels.o"
"$GCC" "${GCC_RV64GCV[@]}" "${BASE_CFLAGS[@]}" -I "$BENCH_DIR" \
  -DPARITY_PAIR='"A2"' -DPARITY_EXPECT_RVV \
  -c "$BENCH_DIR/parity_main.c" -o "$BUILD_DIR/a2_main.o"
"$GCC" "${GCC_RV64GCV[@]}" -mabi=lp64d \
  -o "$BUILD_DIR/parity_a2.exe" \
  "$BUILD_DIR/a2_main.o" "$BUILD_DIR/a2_shipping_kernel.o" \
  "$BUILD_DIR/a2_bench_kernels.o"

for exe in parity_a1.exe parity_a2.exe; do
  [ -f "$BUILD_DIR/$exe" ] || fail "missing $BUILD_DIR/$exe"
done

# ---------------------------------------------------------------------------
# Branch identity: A1 must be the scalar branch, A2 must be the RVV branch
# ---------------------------------------------------------------------------
if [ -n "$LLVM_OBJDUMP" ]; then
  A1_VINSNS=$(vec_count "$BUILD_DIR/a1_shipping_kernel.o")
  A2_VINSNS=$(vec_count "$BUILD_DIR/a2_shipping_kernel.o")
  printf '== branch identity (vector instructions in the src/native/kernel.c objects)\n'
  printf '   A1 gcc -march=rv64gc    : %s (want 0: scalar branch)\n' "$A1_VINSNS"
  printf '   A2 clang -march=rv64gcv : %s (want > 0: RVV branch)\n' "$A2_VINSNS"
  [ "$A1_VINSNS" -eq 0 ] || fail "A1 kernel object has $A1_VINSNS vector instructions: not the scalar branch"
  [ "$A2_VINSNS" -gt 0 ] || fail "A2 kernel object has no vector instructions: not the RVV branch"
else
  printf '== branch identity: skipped (no llvm-objdump); A2 is still guarded by rvv_selftest()\n'
fi

# ---------------------------------------------------------------------------
# Run both pairs under qemu-user 8.2 (V enabled) and assert PARITY_OK
# ---------------------------------------------------------------------------
run_pair() {  # $1 = tag, $2 = executable, $3 = description
  local tag=$1
  local exe=$2
  local desc=$3
  local log="$BUILD_DIR/run_$tag.log"
  local err="$BUILD_DIR/qemu_$tag.err"
  local status=0

  printf '== run %s: %s\n' "$tag" "$desc"
  bash "$QEMU_RUNNER" "$exe" >"$log" 2>"$err" || status=$?
  if [ "$status" -ne 0 ]; then
    cat "$log" >&2 || true
    cat "$err" >&2 || true
    fail "pair $tag exited with status $status (log: $log)"
  fi
  if ! grep -qx 'PARITY_OK' "$log"; then
    cat "$log" >&2 || true
    cat "$err" >&2 || true
    fail "pair $tag did not print PARITY_OK (log: $log)"
  fi
  printf '   %s PARITY_OK\n' "$tag"
}

run_pair A1 "$BUILD_DIR/parity_a1.exe" 'gcc rv64gc scalar branch vs bench/kernels.c'
run_pair A2 "$BUILD_DIR/parity_a2.exe" 'clang rv64gcv RVV branch vs bench/kernels_rvv.c'

printf '== OK: the shipping kernel and the bench kernels agree\n'
printf '   A1 scalar: src/native/kernel.c vs bench/kernels.c     (5 primitives x %s sizes)\n' "${#SIZES[@]}"
printf '   A2 RVV   : src/native/kernel.c vs bench/kernels_rvv.c (5 primitives x %s sizes)\n' "${#SIZES[@]}"
printf '   not covered: the auto tier (no shipping counterpart; see docs/BENCHMARKS.md section 6)\n'
printf 'PARITY_OK\n'
