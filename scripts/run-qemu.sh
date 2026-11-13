#!/usr/bin/env bash
# Run an RV64 executable under qemu-user and assert the M0 probe value (42).
#
# Usage: bash scripts/run-qemu.sh <rv64-elf>
set -euo pipefail

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

if ! command -v qemu-riscv64 >/dev/null 2>&1; then
  printf 'error: qemu-riscv64 not found.\n' >&2
  printf 'fix:   sudo apt-get install -y qemu-user\n' >&2
  exit 1
fi

if [ ! -d /usr/riscv64-linux-gnu ]; then
  printf 'error: missing RISC-V sysroot /usr/riscv64-linux-gnu.\n' >&2
  printf 'fix:   sudo apt-get install -y gcc-riscv64-linux-gnu libc6-dev-riscv64-cross\n' >&2
  exit 1
fi

if ! file "$EXE" | grep -qi 'RISC-V'; then
  printf 'error: not a RISC-V ELF: %s\n' "$EXE" >&2
  file "$EXE" >&2
  exit 1
fi

OUTPUT=$(qemu-riscv64 -L /usr/riscv64-linux-gnu "$EXE")
printf '%s\n' "$OUTPUT"

if [ "$OUTPUT" != "42" ]; then
  printf 'error: expected probe output 42, got %s\n' "$OUTPUT" >&2
  exit 1
fi
