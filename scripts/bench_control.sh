#!/usr/bin/env bash
# M3 control experiment: separate the confounded factors of the main table.
#
#   bash scripts/bench_control.sh
#
# The main 45-row table (scripts/bench.sh) compares three tiers that differ in
# TWO dimensions at once:
#
#   tier    compiler/opt          ISA
#   scalar  gcc 10.2  -O2         rv64gc  (no V)
#   auto    clang 19  -O3         rv64gcv (V, plain C auto-vectorized)
#   rvv     clang 19  -O2         rv64gcv (V, hand-written intrinsics)
#
# so "auto beats rvv" cannot be attributed to the vectorization strategy alone:
# it is also a -O3-vs-O2 and a different-source-file comparison. This script
# holds one variable at a time at N=8192 / REPS=8:
#
#   (1) clang -O3 -march=rv64gc   on bench/kernels.c      -> same compiler+opt as
#       auto, no V: the delta to auto is the vectorization gain itself;
#   (2) clang -O2 -march=rv64gc   on bench/kernels.c      -> same compiler+opt as
#       rvv, no V: the delta to scalar isolates gcc-vs-clang at -O2;
#   (3) clang -O3 -march=rv64gcv  on bench/kernels_rvv.c  -> same intrinsics as
#       rvv, one opt level higher: isolates -O2 vs -O3 on the RVV kernels.
#
# Every control ELF is run twice (determinism), and every N=8192 checksum must
# match the main table for the same (primitive, N); the control experiment can
# therefore not silently change the workload. The main table is read-only here:
# bench/results.md is parsed, never written.
#
# Asserts:
#   1. every control ELF prints 15 RESULT lines and is deterministic over two runs;
#   2. every (primitive, N=8192) checksum equals the main table's checksum;
#   3. the two -march=rv64gc control objects contain no vector instructions
#      (sanity check of the "no V" premise; skipped without llvm-objdump).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BENCH_DIR="$REPO_ROOT/bench"
BUILD_DIR="$REPO_ROOT/_build/bench-control"
MAIN_RESULTS="$BENCH_DIR/results.md"
N_FOCUS=8192
REPS_FOCUS=8

GCC=${BENCH_GCC:-riscv64-unknown-elf-gcc}
CLANG=${BENCH_CLANG:-clang-19}
OBJCOPY=${BENCH_OBJCOPY:-riscv64-unknown-elf-objcopy}
SPIKE=${BENCH_SPIKE:-$HOME/spike/bin/spike}
SPIKE_ISA=rv64gcv_zicntr

PRIMS=(sum count_ge prefix_sum filter dot)
CTLS=(clang_o2_nov clang_o3_nov rvv_o3)
TIERS=(scalar auto rvv)

GCC_CFLAGS=(-march=rv64gc -mabi=lp64d -mcmodel=medany -O2 -ffreestanding
            -fno-builtin -nostdlib -Wall -Wextra)
CLANG_RV64GC=(--target=riscv64-unknown-elf -march=rv64gc -mabi=lp64d
              -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -Wall -Wextra)
CLANG_RV64GCV=(--target=riscv64-unknown-elf -march=rv64gcv -mabi=lp64d
               -mcmodel=medany -ffreestanding -fno-builtin -nostdlib -Wall -Wextra)

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

need "$GCC" "sudo apt-get install -y gcc-riscv64-unknown-elf"
need "$CLANG" "sudo apt-get install -y clang-19"
need "$OBJCOPY" "sudo apt-get install -y binutils-riscv64-unknown-elf"
need readelf "sudo apt-get install -y binutils"
need timeout "coreutils"
[ -x "$SPIKE" ] || fail "spike not found at '$SPIKE' (set BENCH_SPIKE=/path/to/spike)"
[ -f "$MAIN_RESULTS" ] || fail "$MAIN_RESULTS is missing; run 'bash scripts/bench.sh' first"

LLVM_OBJDUMP=$(command -v llvm-objdump-19 || command -v llvm-objdump || true)

GCC_VERSION=$("$GCC" -dumpversion)
CLANG_VERSION=$("$CLANG" -dumpversion)

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

printf '== toolchain\n'
printf '   gcc:    %s (%s)\n' "$GCC" "$GCC_VERSION"
printf '   clang:  %s (%s)\n' "$CLANG" "$CLANG_VERSION"
printf '== build\n'
"$GCC" "${GCC_CFLAGS[@]}" -c "$BENCH_DIR/crt0.S" -o "$BUILD_DIR/crt0.o"
"$GCC" "${GCC_CFLAGS[@]}" -c "$BENCH_DIR/platform_htif.c" -o "$BUILD_DIR/platform_htif.o"
"$GCC" "${GCC_CFLAGS[@]}" -DBENCH_TIER='"control"' \
  -c "$BENCH_DIR/main.c" -o "$BUILD_DIR/main.o"

"$CLANG" "${CLANG_RV64GC[@]}"  -O2 -c "$BENCH_DIR/kernels.c"     -o "$BUILD_DIR/k_clang_o2_nov.o"
"$CLANG" "${CLANG_RV64GC[@]}"  -O3 -c "$BENCH_DIR/kernels.c"     -o "$BUILD_DIR/k_clang_o3_nov.o"
"$CLANG" "${CLANG_RV64GCV[@]}" -O3 -c "$BENCH_DIR/kernels_rvv.c" -o "$BUILD_DIR/k_rvv_o3.o"

for obj in k_clang_o2_nov k_clang_o3_nov k_rvv_o3; do
  "$OBJCOPY" --remove-section=.riscv.attributes "$BUILD_DIR/$obj.o" 2>/dev/null || true
done
for ctl in "${CTLS[@]}"; do
  "$GCC" -nostdlib -T "$BENCH_DIR/link.ld" -o "$BUILD_DIR/ctl_$ctl.elf" \
    "$BUILD_DIR/crt0.o" "$BUILD_DIR/platform_htif.o" "$BUILD_DIR/main.o" \
    "$BUILD_DIR/k_$ctl.o"
  readelf -h "$BUILD_DIR/ctl_$ctl.elf" >"$BUILD_DIR/readelf_$ctl.txt"
  grep -q 'Machine:.*RISC-V' "$BUILD_DIR/readelf_$ctl.txt" \
    || fail "ctl_$ctl.elf is not a RISC-V ELF"
  printf '   %s\n' "$BUILD_DIR/ctl_$ctl.elf"
done

vector_count() {  # $1 = object, $2 = function name
  "$LLVM_OBJDUMP" -d --no-show-raw-insn --mattr=+m,+a,+f,+d,+c,+v "$1" | awk -v f="$2" '
    $0 ~ "^[0-9a-f]+ <" f ">:" { cur = 1; next }
    /^[0-9a-f]+ </ { cur = 0 }
    cur && $2 ~ /^v/ { n++ }
    END { print n + 0 }'
}
if [ -n "$LLVM_OBJDUMP" ]; then
  for ctl in clang_o2_nov clang_o3_nov; do
    v=0
    for prim in "${PRIMS[@]}"; do
      v=$((v + $(vector_count "$BUILD_DIR/k_$ctl.o" "k_$prim")))
    done
    [ "$v" -eq 0 ] || fail "control $ctl (-march=rv64gc) contains $v vector instructions"
  done
  printf '   sanity: the two -march=rv64gc controls contain 0 vector instructions\n'
fi

printf '== spike runs (each control twice, --isa=%s)\n' "$SPIKE_ISA"
run_ctl() {  # $1 = control name, $2 = output log
  timeout 900 "$SPIKE" --isa="$SPIKE_ISA" "$BUILD_DIR/ctl_$1.elf" >"$2" 2>&1 \
    || fail "spike failed for control $1 (log: $2)"
  grep -qx 'DONE' "$2" || fail "control $1 did not reach DONE (log: $2)"
}
for ctl in "${CTLS[@]}"; do
  run_ctl "$ctl" "$BUILD_DIR/run1_$ctl.log"
  run_ctl "$ctl" "$BUILD_DIR/run2_$ctl.log"
  printf '   %-14s runs=2 done\n' "$ctl"
done

for ctl in "${CTLS[@]}"; do
  awk '$1 == "RESULT" { printf "%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $6 }' \
    "$BUILD_DIR/run1_$ctl.log" >"$BUILD_DIR/$ctl.tsv"
  rows=$(wc -l <"$BUILD_DIR/$ctl.tsv")
  [ "$rows" -eq 15 ] || fail "control $ctl produced $rows RESULT lines, want 15"
  if ! diff -q <(grep '^RESULT' "$BUILD_DIR/run1_$ctl.log") \
               <(grep '^RESULT' "$BUILD_DIR/run2_$ctl.log") >/dev/null; then
    fail "control $ctl is not deterministic across two runs"
  fi
done

# The main table is parsed read-only; field layout of the 45-row table:
#   | # | primitive | N | REPS | tier | compiler | VLEN | instret | chk | ratio |
main_inst() {  # $1 = primitive, $2 = tier
  awk -F'|' -v p="$1" -v t="$2" '
    { for (i = 2; i <= 11; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
      if ($3 == p && $4 == "8192" && $6 == t) { print $9; exit } }' \
    "$MAIN_RESULTS"
}
main_chk() {  # $1 = primitive, $2 = tier
  awk -F'|' -v p="$1" -v t="$2" '
    { for (i = 2; i <= 11; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
      if ($3 == p && $4 == "8192" && $6 == t) { print $10; exit } }' \
    "$MAIN_RESULTS"
}
ctl_inst() {  # $1 = control, $2 = primitive
  awk -F'\t' -v p="$2" '$1 == p && $2 == 8192 { print $4; exit }' "$BUILD_DIR/$1.tsv"
}
ctl_chk() {  # $1 = control, $2 = primitive
  awk -F'\t' -v p="$2" '$1 == p && $2 == 8192 { print $5; exit }' "$BUILD_DIR/$1.tsv"
}

# checksums must match the main table for the same (primitive, N=8192)
for prim in "${PRIMS[@]}"; do
  want=$(main_chk "$prim" scalar)
  [ -n "$want" ] || fail "cannot read the main-table checksum for $prim N=8192"
  for tier in "${TIERS[@]}"; do
    got=$(main_chk "$prim" "$tier")
    [ "$got" = "$want" ] || fail "main table: $prim tier $tier chk $got != $want"
  done
  for ctl in "${CTLS[@]}"; do
    got=$(ctl_chk "$ctl" "$prim")
    [ "$got" = "$want" ] || fail "control $ctl: $prim chk $got != main $want"
  done
done

# ---------------------------------------------------------------------------
# 4. control table + derived ratios
# ---------------------------------------------------------------------------
{
  for prim in "${PRIMS[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$prim" \
      "$(main_inst "$prim" scalar)" "$(ctl_inst clang_o2_nov "$prim")" \
      "$(ctl_inst clang_o3_nov "$prim")" "$(main_inst "$prim" auto)" \
      "$(main_inst "$prim" rvv)" "$(ctl_inst rvv_o3 "$prim")"
  done
} >"$BUILD_DIR/control.tsv"

printf '== control table (N=%s, REPS=%s, spike instret; every checksum equals the main table)\n' \
  "$N_FOCUS" "$REPS_FOCUS"
awk -F'\t' '
  BEGIN {
    printf "   %-11s %10s %10s %10s %10s %10s %10s\n", "primitive", "(1)scalar", "(2)clangO2", "(3)clangO3", "(4)auto", "(5)rvv", "(6)rvvO3"
    printf "   %-11s %10s %10s %10s %10s %10s %10s\n", "", "gcc O2", "clang O2", "clang O3", "clang O3+V", "clang O2+V", "clang O3+V"
  }
  { printf "   %-11s %10s %10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $5, $6, $7 }' \
  "$BUILD_DIR/control.tsv"

printf '== derived ratios (<1.00 = fewer instructions than the reference)\n'
awk -F'\t' '
  BEGIN {
    printf "   %-11s %12s %12s %12s %12s %12s\n", "primitive", "(2)/(1)", "(3)/(1)", "(4)/(3)", "(6)/(5)", "(6)/(4)"
  }
  { printf "   %-11s %12.2f %12.2f %12.2f %12.2f %12.2f\n", $1, $3/$2, $4/$2, $5/$4, $7/$6, $7/$5 }' \
  "$BUILD_DIR/control.tsv"
printf '   legend:\n'
printf '     (2)/(1)  clang vs gcc at -O2, no V        (3)/(1)  clang -O3 vs gcc -O2, no V\n'
printf '     (4)/(3)  vectorization itself (same clang -O3, V vs no V)\n'
printf '     (6)/(5)  -O3 vs -O2 on the RVV intrinsics (6)/(4)  strategy, both clang -O3 + V\n'
printf '     note: (4)/(1) = (3)/(1) x (4)/(3), i.e. compiler/opt effect x vectorization effect\n'

# Markdown copy of the control table (build dir is git-ignored).
{
  printf '| 原语 | (1) scalar gcc -O2 | (2) clang -O2 noV | (3) clang -O3 noV | (4) auto clang -O3 +V | (5) rvv clang -O2 +V | (6) clang -O3 +V intrinsics |\n'
  printf '|---|---:|---:|---:|---:|---:|---:|\n'
  awk -F'\t' '{ printf "| `%s` | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7 }' \
    "$BUILD_DIR/control.tsv"
} >"$BUILD_DIR/control-table.md"

printf '== OK: control determinism and main-table checksum equality verified\n'
printf '   table: %s\n' "${BUILD_DIR#"$REPO_ROOT"/}/control-table.md"
printf '   CONTROL_OK\n'
