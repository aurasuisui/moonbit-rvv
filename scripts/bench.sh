#!/usr/bin/env bash
# M3: spike retired-instruction benchmark for the five primitives.
#
#   bash scripts/bench.sh
#
# Builds one bare-metal ELF per implementation tier (scalar / auto / rvv), runs
# each under spike twice, asserts the invariants below, and renders
# bench/results.md (5 primitives x 3 sizes x 3 tiers = 45 data rows).
#
# Asserts:
#   1. every ELF prints exactly 15 RESULT lines (5 primitives x 3 sizes);
#   2. run-to-run determinism: the same ELF run twice yields bit-identical
#      instret and checksum columns;
#   3. the three tiers agree on every (primitive, size) checksum;
#   4. no file under bench/ or scripts/ reads the cycle CSR -- the metric is
#      retired instructions only (docs/BENCHMARKS.md);
#   5. the rvv tier really executes vector instructions on VLEN=128
#      (VLPROBE reports vlenb=16, vlen=128, vlmax(e32m1)=4);
#   6. runtime parity: src/native/kernel.c returns exactly what bench/kernels*.c
#      returns for every primitive (scripts/bench_parity.sh, M4 / P1(b)).
#
# Metric: spike retired instructions (rdinstret) around one kernel call that
# performs REPS passes over the input. spike must run with zicntr enabled.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BENCH_DIR="$REPO_ROOT/bench"
BUILD_DIR="$REPO_ROOT/_build/bench"   # git-ignored via the "_build/" rule
RESULTS="$BENCH_DIR/results.md"

GCC=${BENCH_GCC:-riscv64-unknown-elf-gcc}
CLANG=${BENCH_CLANG:-clang-19}
OBJCOPY=${BENCH_OBJCOPY:-riscv64-unknown-elf-objcopy}
SPIKE=${BENCH_SPIKE:-$HOME/spike/bin/spike}
SPIKE_ISA=rv64gcv_zicntr

SIZES=(1024 8192 65536)
REPS=(16 8 4)
PRIMS=(sum count_ge prefix_sum filter dot)
TIERS=(scalar auto rvv)

GCC_CFLAGS=(-march=rv64gc -mabi=lp64d -mcmodel=medany -O2 -ffreestanding
            -fno-builtin -nostdlib -Wall -Wextra)
CLANG_TARGET=(--target=riscv64-unknown-elf -march=rv64gcv -mabi=lp64d
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

need "$GCC" "sudo apt-get install -y gcc-riscv64-unknown-elf   # bare-metal RV64 GCC"
need "$CLANG" "sudo apt-get install -y clang-19               # RVV intrinsics + auto-vectorization"
need "$OBJCOPY" "sudo apt-get install -y binutils-riscv64-unknown-elf"
need readelf "sudo apt-get install -y binutils"
need timeout "coreutils"
[ -x "$SPIKE" ] || fail "spike not found at '$SPIKE' (fix: install spike and/or set BENCH_SPIKE=/path/to/spike)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

GCC_VERSION=$("$GCC" -dumpversion)
CLANG_VERSION=$("$CLANG" -dumpversion)
"$SPIKE" --help >"$BUILD_DIR/spike-help.txt" 2>&1 || true
SPIKE_VERSION=$(awk 'NR == 1 { print; exit }' "$BUILD_DIR/spike-help.txt")
[ -n "$SPIKE_VERSION" ] || fail "could not determine the spike version from '$SPIKE --help'"

# Optional: RVV-capable disassembler for the per-kernel vectorization diagnosis.
# Ubuntu 22.04's binutils cannot decode RVV 1.0, so llvm-objdump is used when
# present; the primary results do not depend on it.
LLVM_OBJDUMP=$(command -v llvm-objdump-19 || command -v llvm-objdump || true)

# ---------------------------------------------------------------------------
# 0. metric hygiene: nothing may read the cycle CSR
# ---------------------------------------------------------------------------
# Split so that this checker does not match its own pattern.
CYCLE_CSR="rd""cycle"
if grep -rn --binary-files=without-match --exclude-dir=.toolchain -- "$CYCLE_CSR" \
    "$BENCH_DIR" "$SCRIPT_DIR" >/dev/null 2>&1; then
  fail "found a cycle-CSR read under bench/ or scripts/; only retired instructions are allowed"
fi

# ---------------------------------------------------------------------------
# 1. build one ELF per tier
# ---------------------------------------------------------------------------
printf '== toolchain\n'
printf '   spike:  %s\n' "$SPIKE_VERSION"
printf '   gcc:    %s (%s)\n' "$GCC" "$GCC_VERSION"
printf '   clang:  %s (%s)\n' "$CLANG" "$CLANG_VERSION"
if [ -n "$LLVM_OBJDUMP" ]; then
  printf '   objdump:%s\n' "$LLVM_OBJDUMP"
fi

printf '== build\n'
"$GCC" "${GCC_CFLAGS[@]}" -c "$BENCH_DIR/crt0.S" -o "$BUILD_DIR/crt0.o"
"$GCC" "${GCC_CFLAGS[@]}" -c "$BENCH_DIR/platform_htif.c" -o "$BUILD_DIR/platform_htif.o"
for tier in "${TIERS[@]}"; do
  "$GCC" "${GCC_CFLAGS[@]}" -DBENCH_TIER="\"$tier\"" \
    -c "$BENCH_DIR/main.c" -o "$BUILD_DIR/main_$tier.o"
done
# scalar: plain C by gcc -O2 -march=rv64gc (no V in the ISA string: no vectorizing)
"$GCC" "${GCC_CFLAGS[@]}" -c "$BENCH_DIR/kernels.c" -o "$BUILD_DIR/k_scalar.o"
# auto: the same plain C by clang -O3 -march=rv64gcv (LLVM free to vectorize)
"$CLANG" "${CLANG_TARGET[@]}" -O3 -c "$BENCH_DIR/kernels.c" -o "$BUILD_DIR/k_auto.o"
# rvv: hand-written intrinsics by clang -O2 -march=rv64gcv
"$CLANG" "${CLANG_TARGET[@]}" -O2 -c "$BENCH_DIR/kernels_rvv.c" -o "$BUILD_DIR/k_rvv.o"
# Drop .riscv.attributes so GCC 10.2's linker does not reject objects whose
# attribute string mentions the V extension (same workaround as the M2 harness).
for obj in k_auto k_rvv; do
  "$OBJCOPY" --remove-section=.riscv.attributes "$BUILD_DIR/$obj.o" 2>/dev/null || true
done
for tier in "${TIERS[@]}"; do
  "$GCC" -nostdlib -T "$BENCH_DIR/link.ld" -o "$BUILD_DIR/bench_$tier.elf" \
    "$BUILD_DIR/crt0.o" "$BUILD_DIR/platform_htif.o" "$BUILD_DIR/main_$tier.o" \
    "$BUILD_DIR/k_$tier.o"
done
for tier in "${TIERS[@]}"; do
  elf="$BUILD_DIR/bench_$tier.elf"
  [ -f "$elf" ] || fail "missing $elf"
  readelf -h "$elf" >"$BUILD_DIR/readelf_$tier.txt"
  grep -q 'Machine:.*RISC-V' "$BUILD_DIR/readelf_$tier.txt" \
    || fail "$elf is not a RISC-V ELF"
done
printf '   %s\n' "$BUILD_DIR"/bench_*.elf

# Per-kernel vector instruction count (diagnosis for the auto tier).
vector_count() {  # $1 = object, $2 = function name
  "$LLVM_OBJDUMP" -d --no-show-raw-insn --mattr=+m,+a,+f,+d,+c,+v "$1" | awk -v f="$2" '
    $0 ~ "^[0-9a-f]+ <" f ">:" { cur = 1; next }
    /^[0-9a-f]+ </ { cur = 0 }
    cur && $2 ~ /^v/ { n++ }
    END { print n + 0 }'
}
if [ -n "$LLVM_OBJDUMP" ]; then
  rvv_vinsns=$(vector_count "$BUILD_DIR/k_rvv.o" k_sum)
  [ "$rvv_vinsns" -gt 0 ] || fail "the rvv tier compiled to no vector instructions"
fi

# ---------------------------------------------------------------------------
# 2. run each tier twice
# ---------------------------------------------------------------------------
printf '== spike runs (each tier twice, --isa=%s)\n' "$SPIKE_ISA"
run_tier() {  # $1 = tier, $2 = output log
  timeout 900 "$SPIKE" --isa="$SPIKE_ISA" "$BUILD_DIR/bench_$1.elf" >"$2" 2>&1 \
    || fail "spike failed for tier $1 (log: $2)"
  grep -qx 'DONE' "$2" || fail "tier $1 did not reach DONE (log: $2)"
}
for tier in "${TIERS[@]}"; do
  run_tier "$tier" "$BUILD_DIR/run1_$tier.log"
  run_tier "$tier" "$BUILD_DIR/run2_$tier.log"
  printf '   %-6s runs=2 done\n' "$tier"
done

# ---------------------------------------------------------------------------
# 3. parse and assert
# ---------------------------------------------------------------------------
for tier in "${TIERS[@]}"; do
  awk '$1 == "RESULT" { printf "%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $6 }' \
    "$BUILD_DIR/run1_$tier.log" >"$BUILD_DIR/$tier.tsv"
  rows=$(wc -l <"$BUILD_DIR/$tier.tsv")
  [ "$rows" -eq 15 ] || fail "tier $tier produced $rows RESULT lines, want 15"
  for prim in "${PRIMS[@]}"; do
    for size in "${SIZES[@]}"; do
      awk -F'\t' -v p="$prim" -v n="$size" \
        '$1 == p && $2 == n { found = 1 } END { exit !found }' \
        "$BUILD_DIR/$tier.tsv" || fail "tier $tier is missing RESULT $prim $size"
    done
  done
  # (2) determinism: identical RESULT lines across two runs of the same ELF
  if ! diff -q <(grep '^RESULT' "$BUILD_DIR/run1_$tier.log") \
               <(grep '^RESULT' "$BUILD_DIR/run2_$tier.log") >/dev/null; then
    fail "tier $tier is not deterministic across two runs"
  fi
done

# (3) checksum equality across tiers
paste -d'|' "$BUILD_DIR/scalar.tsv" "$BUILD_DIR/auto.tsv" "$BUILD_DIR/rvv.tsv" |
  awk -F'|' '
    { split($1, s, "\t"); split($2, a, "\t"); split($3, r, "\t")
      if (s[5] != a[5] || s[5] != r[5]) {
        printf "  checksum mismatch: %s n=%s scalar=%s auto=%s rvv=%s\n",
               s[1], s[2], s[5], a[5], r[5]
        bad = 1
      } }
    END { exit bad }' || fail "the three tiers disagree on a checksum"

# (5) VLEN proof from the rvv tier
probe=$(awk '$1 == "VLPROBE" { printf "%s %s %s", $2, $3, $4 }' "$BUILD_DIR/run1_rvv.log")
[ "$probe" = "16 128 4" ] || fail "unexpected VLEN probe '$probe' (want '16 128 4' = vlenb vlen vlmax)"
VLENB=16
VLEN=128
VLMAX=4

# ---------------------------------------------------------------------------
# 4. render bench/results.md
# ---------------------------------------------------------------------------
printf '== results (instret; relative to scalar in parentheses)\n'

paste -d'|' "$BUILD_DIR/scalar.tsv" "$BUILD_DIR/auto.tsv" "$BUILD_DIR/rvv.tsv" |
  awk -F'|' '
    BEGIN { printf "   %-11s %7s %12s %18s %18s\n", "primitive", "N", "scalar", "auto", "rvv" }
    { split($1, s, "\t"); split($2, a, "\t"); split($3, r, "\t")
      printf "   %-11s %7s %12s %10s(%5.2f) %10s(%5.2f)\n",
             s[1], s[2], s[4], a[4], a[4] / s[4], r[4], r[4] / s[4] }'

printf '== render %s\n' "${RESULTS#"$REPO_ROOT"/}"

paste -d'|' "$BUILD_DIR/scalar.tsv" "$BUILD_DIR/auto.tsv" "$BUILD_DIR/rvv.tsv" |
  awk -F'|' -v gv="$GCC_VERSION" -v cv="$CLANG_VERSION" -v vl="$VLEN" '
    { split($1, s, "\t"); split($2, a, "\t"); split($3, r, "\t")
      row++
      printf "| %d | `%s` | %s | %s | scalar | gcc %s | %s | %s | `%s` | 1.00x(基准) |\n",
             row, s[1], s[2], s[3], gv, vl, s[4], s[5]
      row++
      printf "| %d | `%s` | %s | %s | auto | clang %s | %s | %s | `%s` | %.2fx |\n",
             row, s[1], s[2], s[3], cv, vl, a[4], a[5], a[4] / s[4]
      row++
      printf "| %d | `%s` | %s | %s | rvv | clang %s | %s | %s | `%s` | %.2fx |\n",
             row, s[1], s[2], s[3], cv, vl, r[4], r[5], r[4] / s[4] }' \
    >"$BUILD_DIR/results_table.md"

for mode in auto rvv; do
  paste -d'|' "$BUILD_DIR/scalar.tsv" "$BUILD_DIR/auto.tsv" "$BUILD_DIR/rvv.tsv" |
    awk -F'|' -v mode="$mode" '
      { split($1, s, "\t"); split($2, a, "\t"); split($3, r, "\t")
        p = s[1]
        if (!(p in seen)) { seen[p] = 1; order[++np] = p }
        ratio[p, s[2]] = (mode == "auto") ? a[4] / s[4] : r[4] / s[4] }
      END {
        for (i = 1; i <= np; i++) {
          p = order[i]
          printf "| `%s` | %.2fx | %.2fx | %.2fx |\n",
                 p, ratio[p, "1024"], ratio[p, "8192"], ratio[p, "65536"]
        }
      }' >"$BUILD_DIR/matrix_$mode.md"
done

paste -d'|' "$BUILD_DIR/scalar.tsv" "$BUILD_DIR/auto.tsv" "$BUILD_DIR/rvv.tsv" |
  awk -F'|' '
    { split($1, s, "\t"); split($2, a, "\t"); split($3, r, "\t")
      printf "| `%s` | %s | `%s` | `%s` | `%s` | %s |\n",
             s[1], s[2], s[5], a[5], r[5],
             (s[5] == a[5] && s[5] == r[5]) ? "一致" : "**不一致**" }' \
  >"$BUILD_DIR/checksums.md"

if [ -n "$LLVM_OBJDUMP" ]; then
  {
    printf '| 内核函数 | scalar | auto | rvv |\n'
    printf '|---|---:|---:|---:|\n'
    for prim in "${PRIMS[@]}"; do
      fn="k_$prim"
      printf '| `%s` | %s | %s | %s |\n' "$fn" \
        "$(vector_count "$BUILD_DIR/k_scalar.o" "$fn")" \
        "$(vector_count "$BUILD_DIR/k_auto.o" "$fn")" \
        "$(vector_count "$BUILD_DIR/k_rvv.o" "$fn")"
    done
  } >"$BUILD_DIR/vector-diag.md"
  auto_vectorized=$(awk -F'|' 'NR > 2 { gsub(/ /, "", $4); if ($4 + 0 > 0) n++ } END { print n + 0 }' \
    "$BUILD_DIR/vector-diag.md")
  auto_note="$auto_vectorized/5 个内核函数在 auto 档生成了向量指令"
else
  printf '| (skipped: no llvm-objdump) | - | - | - |\n' >"$BUILD_DIR/vector-diag.md"
  auto_note="未安装 llvm-objdump,跳过反汇编诊断"
fi

# ---------------------------------------------------------------------------
# 5. bench/results.md (machine generated, no timestamps: byte-stable)
# ---------------------------------------------------------------------------
{
  cat <<'MD'
# spike 退休指令数基准结果

> **生成物,请勿手改。** 由 `bash scripts/bench.sh` 生成;口径、结论与限制见
> [`../docs/BENCHMARKS.md`](../docs/BENCHMARKS.md)。

## 环境与口径

| 项 | 值 |
|---|---|
MD
  printf '| spike | %s |\n' "$SPIKE_VERSION"
  printf '| 运行 | `spike --isa=%s _build/bench/bench_<tier>.elf` |\n' "$SPIKE_ISA"
  printf '| VLEN | %s bit(rvv 档 VLPROBE:vlenb=%s → vlen=%s,vlmax(e32m1)=%s) |\n' \
    "$VLEN" "$VLENB" "$VLEN" "$VLMAX"
  printf '| 计数 | `rdinstret` 退休指令数(**不是周期**;spike 上逐位可复现) |\n'
  printf '| scalar 档 | riscv64-unknown-elf-gcc %s,`-O2 -march=rv64gc`(ISA 无 V,不会向量化) |\n' "$GCC_VERSION"
  printf '| auto 档 | clang %s,`-O3 -march=rv64gcv`(同一份 plain C,交给 LLVM 自动向量化) |\n' "$CLANG_VERSION"
  printf '| rvv 档 | clang %s,`-O2 -march=rv64gcv`(手写 RVV intrinsics) |\n' "$CLANG_VERSION"
  printf '| 规模 / REPS | N=1024/REPS=16、8192/8、65536/4(每次测量元素访问数 = N × REPS) |\n'
  printf '| 输入 | 固定 LCG 种子,`a[0]=INT32_MAX`、`a[1]=INT32_MIN`、`thr=0`;三档用同一套输入 |\n'
  cat <<'MD'

## 45 行总表(5 原语 × 3 规模 × 3 档)

每次测量 = 一次内核调用,内核内部对输入做 REPS 遍;`instret` 是 spike 退休指令数,
`相对 scalar` = 该行 instret ÷ 同 (原语, N) 的 scalar instret(< 1.00 表示比 scalar 少退休指令)。
`chk` 是跨档校验和(sum/dot:64 位结果位型;count_ge:计数;prefix_sum/filter:结果序列的 FNV-1a 64)。

| # | 原语 | N | REPS | 档 | 编译器 | VLEN | instret | chk | 相对 scalar |
|---:|---|---:|---:|---|---|---:|---:|---|---:|
MD
  cat "$BUILD_DIR/results_table.md"
  cat <<'MD'

## 相对 scalar 比值矩阵

自动向量化档(auto)÷ 标量档(scalar):

| 原语 | N=1024 | N=8192 | N=65536 |
|---|---:|---:|---:|
MD
  cat "$BUILD_DIR/matrix_auto.md"
  cat <<'MD'

手写 RVV 档(rvv)÷ 标量档(scalar):

| 原语 | N=1024 | N=8192 | N=65536 |
|---|---:|---:|---:|
MD
  cat "$BUILD_DIR/matrix_rvv.md"
  cat <<'MD'

## 三档校验和对照(脚本断言逐位相同)

| 原语 | N | scalar chk | auto chk | rvv chk | 三档一致 |
|---|---:|---|---|---|---|
MD
  cat "$BUILD_DIR/checksums.md"
  cat <<'MD'

## 向量化诊断

每档目标文件中各内核函数的向量指令条数(`llvm-objdump -d`;Ubuntu 22.04 的
binutils 解不出 RVV 1.0 编码,因此用 LLVM 反汇编器):

MD
  cat "$BUILD_DIR/vector-diag.md"
  printf '\n%s。\n' "$auto_note"
  cat <<'MD'

## 脚本断言(本次运行全部通过)

1. 每档 15 条 `RESULT`(5 原语 × 3 规模);缺行即失败。
2. 确定性:每个 ELF 连跑两次,`RESULT` 行(instret 与 chk)逐位相同。
3. 校验和:15 个 (原语, N) 的三档 `chk` 完全相同。
4. 口径:`bench/` 与 `scripts/` 中不存在对 cycle CSR 的读取。
5. VLEN:rvv 档 VLPROBE = `vlenb=16 vlen=128 vlmax(e32m1)=4`。
MD
} >"$RESULTS"

data_rows=$(grep -cE '^\| [0-9]+ \|' "$RESULTS")
[ "$data_rows" -eq 45 ] || fail "results table has $data_rows data rows, want 45"

printf '== wrote %s (%d data rows)\n' "${RESULTS#"$REPO_ROOT"/}" "$data_rows"

# ---------------------------------------------------------------------------
# 6. runtime parity: shipping kernel vs bench kernels (M4 / P1(b))
# ---------------------------------------------------------------------------
# The table above is measured on bench/kernels*.c, which are separate
# implementations of src/native/kernel.c. scripts/bench_parity.sh proves at run
# time that both sides still return identical values (A1 scalar pair, A2 RVV
# pair, n = 0 1 2 3 5 7 17 1024). Its build artifacts go to _build/parity; the
# log stays next to the other bench evidence in _build/bench.
printf '== parity: shipping kernel vs bench kernels (qemu-user 8.2, RV64)\n'
PARITY_LOG="$BUILD_DIR/parity.log"
if ! bash "$SCRIPT_DIR/bench_parity.sh" >"$PARITY_LOG" 2>&1; then
  cat "$PARITY_LOG" >&2
  fail "scripts/bench_parity.sh failed (log: $PARITY_LOG)"
fi
grep -qx "PARITY_OK" "$PARITY_LOG" \
  || { cat "$PARITY_LOG" >&2; fail "parity did not print PARITY_OK (log: $PARITY_LOG)"; }
if grep -q "PARITY_FAIL" "$PARITY_LOG"; then
  cat "$PARITY_LOG" >&2
  fail "parity reported a mismatch (log: $PARITY_LOG)"
fi
grep -E '^   A[12] PARITY_OK$' "$PARITY_LOG" | sed 's/^   /   parity /' || true
printf '   PARITY_OK\n'

printf '   BENCH_OK\n'
