#!/usr/bin/env bash
# M2: cross-compile the native probe to RV64, run it under qemu-user, and
# assert that the RVV branch is present in the artifact and used at runtime.
#
#   bash scripts/cross-riscv.sh
#
# Toolchain split (docs/CROSS_COMPILE.md is the reference):
#   - clang-19 compiles src/native/kernel.c only: riscv64-linux-gnu-gcc 11.4 has
#     no riscv_vector.h and does not define __riscv_vector, while clang -19
#     provides the RVV intrinsics for -march=rv64gcv;
#   - riscv64-linux-gnu-gcc compiles all MoonBit-generated C plus the runtime
#     and links the executable (no --sysroot override: its default sysroot is
#     already /usr/riscv64-linux-gnu);
#   - qemu 8.2 user-mode executes the result with -cpu rv64,v=true.
#
# The MoonBit native backend shells out to $MOON_CC and expects `ar` / `ranlib`
# next to it, so this script generates a dispatch wrapper under
# scripts/.toolchain (git-ignored) and points MOON_CC at it.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TOOLCHAIN_DIR="$SCRIPT_DIR/.toolchain"
BUILD_DIR="$TOOLCHAIN_DIR/build"
SYSROOT=/usr/riscv64-linux-gnu
SELFTEST=SELFTEST_PASS
SMOKE=15,3,35,325

export PATH="$HOME/.moon/bin:$PATH"

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

need moon "install MoonBit (https://www.moonbitlang.com/download/)"
need clang-19 "sudo apt-get install -y clang-19   # RVV intrinsics live here"
need riscv64-linux-gnu-gcc "sudo apt-get install -y gcc-riscv64-linux-gnu"
need riscv64-linux-gnu-ar "sudo apt-get install -y binutils-riscv64-linux-gnu"
need riscv64-linux-gnu-ranlib "sudo apt-get install -y binutils-riscv64-linux-gnu"
need riscv64-linux-gnu-objdump "sudo apt-get install -y binutils-riscv64-linux-gnu"
need file "sudo apt-get install -y file"
need readelf "sudo apt-get install -y binutils"

if [ ! -d "$SYSROOT" ]; then
  printf 'error: missing RISC-V sysroot %s\n' "$SYSROOT" >&2
  printf 'fix:   sudo apt-get install -y gcc-riscv64-linux-gnu libc6-dev-riscv64-cross\n' >&2
  exit 1
fi

mkdir -p "$TOOLCHAIN_DIR"
cat > "$TOOLCHAIN_DIR/cc" <<'CC_EOF'
#!/usr/bin/env bash
# MOON_CC dispatch for scripts/cross-riscv.sh.
# Only src/native/kernel.c needs the RVV intrinsics (clang, --target +
# --sysroot); the MoonBit-generated C, the runtime and the final link use the
# cross GCC, whose default sysroot is already /usr/riscv64-linux-gnu.
set -euo pipefail
CLANG=${RVV_CLANG:-clang-19}
GCC=${RVV_GCC:-riscv64-linux-gnu-gcc}
SYSROOT=${RVV_SYSROOT:-/usr/riscv64-linux-gnu}
want_clang=0
for arg in "$@"; do
  case "$arg" in
    */kernel.c|kernel.c) want_clang=1 ;;
  esac
done
if [ "$want_clang" -eq 1 ]; then
  # -gdwarf-4: Ubuntu 22.04 binutils 2.38 cannot read the DWARF-5 rnglists
  # clang-19 emits by default (objdump/readelf print "Unrecognized form 0x22").
  exec "$CLANG" --target=riscv64-linux-gnu --sysroot="$SYSROOT" \
    -march=rv64gcv -mabi=lp64d -gdwarf-4 "$@"
fi
exec "$GCC" -march=rv64gcv -mabi=lp64d "$@"
CC_EOF
chmod +x "$TOOLCHAIN_DIR/cc"
ln -sf "$(command -v riscv64-linux-gnu-ar)" "$TOOLCHAIN_DIR/ar"
ln -sf "$(command -v riscv64-linux-gnu-ranlib)" "$TOOLCHAIN_DIR/ranlib"

cd "$REPO_ROOT"

# Clean cross build so the artifacts below cannot be stale.
rm -rf "$BUILD_DIR"

printf '== toolchain\n'
printf '   moon:   %s\n' "$(moon version | head -n 1)"
printf '   clang:  %s\n' "$(clang-19 --version | head -n 1)"
printf '   gcc:    %s\n' "$(riscv64-linux-gnu-gcc --version | head -n 1)"
printf '   qemu:   %s\n' "$( [ -x "$HOME/qemu82/bin/qemu-riscv64" ] && "$HOME/qemu82/bin/qemu-riscv64" --version | head -n 1 || qemu-riscv64 --version | head -n 1 )"

printf '== moon build --target native (MOON_CC=%s)\n' "$TOOLCHAIN_DIR/cc"
MOON_CC="$TOOLCHAIN_DIR/cc" moon build --target native --target-dir "$BUILD_DIR"

EXE=$(find "$BUILD_DIR/native" -type f -name 'probe.exe' -print -quit)
[ -n "$EXE" ] || fail "probe executable not found under $BUILD_DIR/native"
KOBJ=$(find "$BUILD_DIR/native" -type f -name 'kernel.o' -print -quit)
[ -n "$KOBJ" ] || fail "kernel object not found under $BUILD_DIR/native"
printf '== artifact: %s\n' "$EXE"
printf '== kernel object: %s\n' "$KOBJ"

printf '== kernel object compiler (readelf -p .comment)\n'
readelf -p .comment "$KOBJ"
readelf -p .comment "$KOBJ" | grep -qi clang \
  || fail "kernel.o was not compiled by clang (RVV intrinsics need clang)"

printf '== file\n'
file "$EXE"
file "$EXE" | grep -qi 'RISC-V' || fail "artifact is not a RISC-V ELF"

printf '== readelf -h\n'
readelf -h "$EXE"
readelf -h "$EXE" | grep -q 'Machine:.*RISC-V' \
  || fail "readelf does not report Machine: RISC-V"

printf '== RVV instructions in artifact (riscv64-linux-gnu-objdump -d)\n'
VSETVLI=$(riscv64-linux-gnu-objdump -d "$EXE" | grep -c 'vsetvli' || true)
VLE32=$(riscv64-linux-gnu-objdump -d "$EXE" | grep -c 'vle32' || true)
printf '   vsetvli: %s\n' "$VSETVLI"
printf '   vle32:   %s\n' "$VLE32"
[ "$VSETVLI" -ge 1 ] || fail "no vsetvli in the artifact: RVV branch is missing"
[ "$VLE32" -ge 1 ] || fail "no vle32 in the artifact: RVV branch is missing"

printf '== qemu run (8.x user-mode, -cpu rv64,v=true)\n'
OUTPUT=$("$SCRIPT_DIR/run-qemu.sh" "$EXE")
printf '%s\n' "$OUTPUT"

printf '%s\n' "$OUTPUT" | grep -qx "$SELFTEST" \
  || fail "expected $SELFTEST, got: $(printf '%s' "$OUTPUT" | tr '\n' ' ')"
printf '%s\n' "$OUTPUT" | grep -qx "$SMOKE" \
  || fail "expected smoke line $SMOKE, got: $(printf '%s' "$OUTPUT" | tr '\n' ' ')"

printf '== OK: RVV branch present in the artifact and self test passed under qemu\n'
