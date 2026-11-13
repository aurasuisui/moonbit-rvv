/*
 * M3 bare-metal entry point for the spike instruction-count benchmark.
 *
 * The harness runs on spike in machine mode with no firmware (spike loads the
 * ELF directly at 0x80000000):
 *   - set mstatus.VS = Initial, otherwise the first vector instruction traps
 *     (bench/kernels_rvv.c is the only file that needs it, but every tier gets
 *     the same crt0 so the driver code is identical across tiers);
 *   - install the trap handler so a bad kernel prints cause/epc instead of
 *     silently spinning;
 *   - call main and halt; main exits through HTIF before returning.
 */
  .section .text.init
  .globl _start
_start:
  la sp, _stack_top
  li t0, (1 << 9)          /* mstatus.VS = Initial: enable vector state */
  csrs mstatus, t0
  la t0, trap_entry
  csrw mtvec, t0
  call main
1:
  j 1b

  .section .text
  .globl trap_entry
trap_entry:
  csrr a0, mcause
  csrr a1, mepc
  csrr a2, mtval
  call on_trap
1:
  j 1b
