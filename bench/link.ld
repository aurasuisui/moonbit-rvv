/* M3 benchmark image layout: load at 0x80000000 (spike default RAM base),
 * 1 MiB stack above .bss. The kernels use static buffers of 3 x 256 KiB, so
 * the image stays well inside spike's default 2048 MiB of memory. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.init) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.bss*) *(.sbss*) *(COMMON) }
  . = ALIGN(16);
  . += 0x100000;
  _stack_top = .;
}
