/*
 * M3 HTIF platform layer for spike.
 *
 * spike has no UART; the only console is the HTIF tohost/fromhost queue that
 * the host polls. Each character is one "console putchar" command:
 *   tohost = (dev << 56) | (cmd << 48) | payload, dev=1 (console), cmd=1 (putchar)
 * and the store is complete when spike clears tohost again.
 *
 * Exit: writing (code << 1) | 1 to tohost asks spike to terminate with that
 * exit code (spike's HTIF syscall convention).
 *
 * The only counter this harness reads is rdinstret (retired instructions).
 * scripts/bench.sh asserts that no file under bench/ or scripts/ touches the
 * cycle CSR: this benchmark never reports cycles, because spike's cycle count
 * depends on a pipeline model and is not the metric (docs/BENCHMARKS.md).
 */
#include "bench.h"

volatile uint64_t tohost;
volatile uint64_t fromhost;

static void htif_console(uint64_t payload) {
  tohost = (1ull << 56) | (1ull << 48) | (payload & 0xffu);
  while (tohost != 0) {
  }
}

void putc_(char c) { htif_console((uint64_t)(unsigned char)c); }

void puts_(const char *s) {
  while (*s) putc_(*s++);
}

void put_u64(uint64_t v) {
  char buf[24];
  int i = 0;
  if (v == 0) {
    putc_('0');
    return;
  }
  while (v) {
    buf[i++] = (char)('0' + (int)(v % 10));
    v /= 10;
  }
  while (i--) putc_(buf[i]);
}

/* 0x + exactly 16 hex digits: the checksum column is compared as text by
 * scripts/bench.sh, so the width must not depend on the value. */
void put_hex64(uint64_t v) {
  static const char digits[] = "0123456789abcdef";
  char buf[16];
  for (int i = 15; i >= 0; i--) {
    buf[i] = digits[v & 15u];
    v >>= 4;
  }
  puts_("0x");
  for (int i = 0; i < 16; i++) putc_(buf[i]);
}

void put_hex(uint64_t v) {
  char buf[17];
  int i = 0;
  if (v == 0) {
    puts_("0x0");
    return;
  }
  while (v) {
    int d = (int)(v & 15u);
    buf[i++] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
    v >>= 4;
  }
  puts_("0x");
  while (i--) putc_(buf[i]);
}

void on_trap(uint64_t cause, uint64_t epc, uint64_t tval) {
  puts_("\nTRAP cause=");
  put_hex(cause);
  puts_(" epc=");
  put_hex(epc);
  puts_(" tval=");
  put_hex(tval);
  puts_("\n");
  exit_qemu(1);
}

void exit_qemu(int code) {
  tohost = (((uint64_t)(unsigned)code) << 1) | 1;
  for (;;) {
  }
}

uint64_t rdinstret_(void) {
  uint64_t v;
  __asm__ volatile("rdinstret %0" : "=r"(v) : : "memory");
  return v;
}
