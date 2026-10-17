.option norvc
.section .vectors,"ax"
.global _start
.rept 32
  j trap_entry
.endr
_start:
  la sp, __stack_top
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la t0, __data_load
  la t1, __data_start
  la t2, __data_end
4: bgeu t1,t2,5f
  lw t3,0(t0)
  sw t3,0(t1)
  addi t0,t0,4
  addi t1,t1,4
  j 4b
5:
  la t0, __bss_start
  la t1, __bss_end
1: bgeu t0,t1,2f
  sw zero,0(t0)
  addi t0,t0,4
  j 1b
2: call main
3: wfi
  j 3b
trap_entry:
  addi sp,sp,-64
  sw ra,0(sp)
  sw t0,4(sp)
  sw t1,8(sp)
  sw t2,12(sp)
  sw t3,16(sp)
  sw t4,20(sp)
  sw t5,24(sp)
  sw t6,28(sp)
  sw a0,32(sp)
  sw a1,36(sp)
  sw a2,40(sp)
  sw a3,44(sp)
  sw a4,48(sp)
  sw a5,52(sp)
  sw a6,56(sp)
  sw a7,60(sp)
  csrr a0,mcause
  call handle_trap
  lw ra,0(sp)
  lw t0,4(sp)
  lw t1,8(sp)
  lw t2,12(sp)
  lw t3,16(sp)
  lw t4,20(sp)
  lw t5,24(sp)
  lw t6,28(sp)
  lw a0,32(sp)
  lw a1,36(sp)
  lw a2,40(sp)
  lw a3,44(sp)
  lw a4,48(sp)
  lw a5,52(sp)
  lw a6,56(sp)
  lw a7,60(sp)
  addi sp,sp,64
  mret
