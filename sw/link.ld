OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0, LENGTH = 16K
         RAM (rw) : ORIGIN = RAM_ORIGIN, LENGTH = 8K }
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) } > ROM
  .rodata : { *(.rodata*) *(.srodata*) . = ALIGN(4); } > ROM
  .data : {
    . = ALIGN(4); __data_start = .; *(.data*) *(.sdata*) . = ALIGN(4); __data_end = .;
  } > RAM AT> ROM
  __data_load = LOADADDR(.data);
  PROVIDE(__global_pointer$ = __data_start + 0x800);
  .bss (NOLOAD) : {
    . = ALIGN(4); __bss_start = .; *(.bss*) *(.sbss*) *(COMMON)
    . = ALIGN(4); __bss_end = .;
  } > RAM
  __stack_top = ORIGIN(RAM)+LENGTH(RAM);
  ASSERT(LOADADDR(.data)+SIZEOF(.data)<=ORIGIN(ROM)+LENGTH(ROM),"Boot image exceeds ROM")
  ASSERT(__bss_end<__stack_top-1024,"Insufficient stack")
}
