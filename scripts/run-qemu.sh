#!/usr/bin/env bash
# Run an RV64 executable under qemu-user with the V extension enabled.
#
#   bash scripts/run-qemu.sh <rv64-elf>
#
# qemu-user only gained RVV support in 8.x (Ubuntu 22.04 ships 6.2, which
# cannot execute RVV instructions), so this script prefers the 8.2 build in
# ~/qemu82 and rejects an older qemu instead of silently producing a confusing
# SIGILL. Program output goes to stdout; the selected qemu and its version go
# to stderr.
set -euo pipefail

SYSROOT=/usr/riscv64-linux-gnu

usage() {
  printf 'usage: %s <rv64-elf>\n' "$0" >&2
  exit 2
}

if [ "$#" -ne 1 ]; then
  usage
fi

EXE=$1
if [ ! -f "$EXE" ]; then
  printf 'error: not a file: %s\n' "$EXE" >&2
  exit 1
fi
EXE=$(cd "$(dirname "$EXE")" && pwd)/$(basename "$EXE")

if [ -n "${QEMU_RISCV64:-}" ]; then
  QEMU=$QEMU_RISCV64
elif [ -x "$HOME/qemu82/bin/qemu-riscv64" ]; then
  QEMU="$HOME/qemu82/bin/qemu-riscv64"
elif command -v qemu-riscv64 >/dev/null 2>&1; then
  QEMU=$(command -v qemu-riscv64)
else
  printf 'error: qemu-riscv64 not found.\n' >&2
  printf 'fix:   install qemu-user >= 8 (the system 6.2 lacks RVV), or set QEMU_RISCV64\n' >&2
  exit 1
fi

if [ ! -d "$SYSROOT" ]; then
  printf 'error: missing RISC-V sysroot %s\n' "$SYSROOT" >&2
  printf 'fix:   sudo apt-get install -y gcc-riscv64-linux-gnu libc6-dev-riscv64-cross\n' >&2
  exit 1
fi

VERSION=$("$QEMU" --version | head -n 1)
printf 'qemu: %s (%s)\n' "$VERSION" "$QEMU" >&2
MAJOR=$(printf '%s\n' "$VERSION" | sed -E 's/.*version ([0-9]+)\..*/\1/')
case "$MAJOR" in
  ''|*[!0-9]*)
    printf 'error: cannot parse qemu version: %s\n' "$VERSION" >&2
    exit 1
    ;;
esac
if [ "$MAJOR" -lt 8 ]; then
  printf 'error: qemu-user %s has no RVV support; need >= 8 (e.g. ~/qemu82)\n' "$VERSION" >&2
  exit 1
fi

if ! file "$EXE" | grep -qi 'RISC-V'; then
  printf 'error: not a RISC-V ELF: %s\n' "$EXE" >&2
  file "$EXE" >&2
  exit 1
fi

exec "$QEMU" -cpu rv64,v=true -L "$SYSROOT" "$EXE"
