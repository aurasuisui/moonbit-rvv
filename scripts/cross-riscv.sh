#!/usr/bin/env bash
# M0: cross-compile the native probe to RV64 and run it under qemu-user.
#
#   bash scripts/cross-riscv.sh
#
# The MoonBit native backend shells out to $MOON_CC and expects `ar` /
# `ranlib` next to it, so this script generates a small wrapper directory
# under scripts/.toolchain (git-ignored) and points MOON_CC at it.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TOOLCHAIN_DIR="$SCRIPT_DIR/.toolchain"
BUILD_DIR="$TOOLCHAIN_DIR/build"
SYSROOT=/usr/riscv64-linux-gnu
EXPECTED=42

export PATH="$HOME/.moon/bin:$PATH"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: missing dependency: %s\n' "$1" >&2
    printf 'fix:   sudo apt-get install -y %s\n' "$2" >&2
    exit 1
  fi
}

need moon "moon (see https://www.moonbitlang.com/download/)"
need riscv64-linux-gnu-gcc "gcc-riscv64-linux-gnu"
need riscv64-linux-gnu-ar "binutils-riscv64-linux-gnu"
need riscv64-linux-gnu-ranlib "binutils-riscv64-linux-gnu"
need qemu-riscv64 "qemu-user"
need file "file"
need readelf "binutils"

if [ ! -d "$SYSROOT" ]; then
  printf 'error: missing RISC-V sysroot %s\n' "$SYSROOT" >&2
  printf 'fix:   sudo apt-get install -y gcc-riscv64-linux-gnu libc6-dev-riscv64-cross\n' >&2
  exit 1
fi

mkdir -p "$TOOLCHAIN_DIR"
cat > "$TOOLCHAIN_DIR/cc" <<'CC_EOF'
#!/usr/bin/env bash
exec riscv64-linux-gnu-gcc -march=rv64gcv -mabi=lp64d "$@"
CC_EOF
chmod +x "$TOOLCHAIN_DIR/cc"
ln -sf "$(command -v riscv64-linux-gnu-ar)" "$TOOLCHAIN_DIR/ar"
ln -sf "$(command -v riscv64-linux-gnu-ranlib)" "$TOOLCHAIN_DIR/ranlib"

cd "$REPO_ROOT"

printf '== moon build --target native (MOON_CC=%s)\n' "$TOOLCHAIN_DIR/cc"
MOON_CC="$TOOLCHAIN_DIR/cc" moon build --target native --target-dir "$BUILD_DIR"

EXE=$(find "$BUILD_DIR/native" -type f -name 'probe.exe' -print -quit)
if [ -z "$EXE" ]; then
  printf 'error: probe executable not found under %s\n' "$BUILD_DIR/native" >&2
  exit 1
fi
printf '== artifact: %s\n' "$EXE"

printf '== file\n'
file "$EXE"
if ! file "$EXE" | grep -qi 'RISC-V'; then
  fail "artifact is not a RISC-V ELF"
fi

printf '== readelf -h\n'
readelf -h "$EXE"
if ! readelf -h "$EXE" | grep -q 'Machine:.*RISC-V'; then
  fail "readelf does not report Machine: RISC-V"
fi

printf '== qemu-riscv64 -L %s\n' "$SYSROOT"
OUTPUT=$("$SCRIPT_DIR/run-qemu.sh" "$EXE")
printf '%s\n' "$OUTPUT"

if [ "$OUTPUT" != "$EXPECTED" ]; then
  fail "expected $EXPECTED, got $OUTPUT"
fi
