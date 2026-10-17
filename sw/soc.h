#ifndef SOC_H
#define SOC_H
#include <stdint.h>
// 4-hart SoC memory map (see rtl/router/router_pkg.sv).
static inline uint32_t cycle_count(void){uint32_t v;__asm__ volatile("rdcycle %0":"=r"(v));return v;}
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define NHARTS 4u
#define UART 0x30000000u
#define GPIO 0x30001000u
#define MAILBOX 0x30003000u
#define DMA 0x30004000u
#define ACC 0x30005000u
#define NOC_CTRL 0x30006000u
#define TAS 0x30007000u
#define CLINT 0x02000000u
#define CLINT_MSIP(h) (CLINT+4u*(h))
#define CLINT_MTIMECMP(h) (CLINT+0x4000u+8u*(h))
#define CLINT_MTIME (CLINT+0xbff8u)
#define UNCACHED_BASE 0x20008000u
#define UNCACHED_END 0x2000c000u
#define PLIC 0x0c000000u
#define PLIC_ENABLE(c) (PLIC+0x2000u+(c)*0x80u)
#define CTX (PLIC+0x200000u+HART*0x1000u)
// Per-hart status block in the uncached window (16 words per hart).
#define MARK_OF(h) (0x2000be00u+(h)*0x40u)
#define MARK MARK_OF(HART)
// Benchmark results written by hart0 (64 words, uncached).
#define PAR 0x2000bd00u
static inline void fence_rw(void){__asm__ volatile("fence rw,rw" ::: "memory");}
// Mailbox slot and PLIC source that interrupt hart h.
static inline uint32_t mailbox_slot(uint32_t h){return h<2u?MAILBOX+4u*h:MAILBOX+0x10u+4u*(h-2u);}
static inline uint32_t mailbox_source(uint32_t h){return h<2u?2u+h:7u+h;}
static inline int dma_range_ok(uint32_t addr,uint32_t bytes){
  return (addr&3u)==0 && bytes!=0 && (bytes&3u)==0 &&
    addr>=UNCACHED_BASE && addr<UNCACHED_END && bytes<=UNCACHED_END-addr;
}
static inline void dma_acquire(void){fence_rw();}
static inline void dma_release(void){fence_rw();}
// DMA is deliberately non-coherent. Both buffers must remain inside the
// uncached window; ownership transfers at START and after DONE/ERROR.
static inline int dma_start_copy(uint32_t src,uint32_t dst,uint32_t bytes){
  if(!dma_range_ok(src,bytes)||!dma_range_ok(dst,bytes))return -1;
  if(!(src+bytes<=dst||dst+bytes<=src))return -1;
  if(REG(DMA+16)&1u)return -2;
  REG(DMA+16)=6u;
  REG(DMA)=src;REG(DMA+4)=dst;REG(DMA+8)=bytes;
  REG(DMA+20)=3u;
  dma_release();
  REG(DMA+12)=1u;
  return 0;
}
static inline void irq_enable(void){
  uint32_t mask=(1u<<11)|(1u<<7)|(1u<<3);
  __asm__ volatile("csrw mie,%0; csrsi mstatus,8"::"r"(mask):"memory");
}
// Hardware test-and-set lock: a read returns 0 when the lock was free (and
// takes it); writing 0 releases it.
static inline void lock_acquire(uint32_t i){while(REG(TAS+4u*i)!=0u){}fence_rw();}
static inline void lock_release(uint32_t i){fence_rw();REG(TAS+4u*i)=0u;}
// CLINT 64-bit time (hi/lo/hi read) and per-hart compare.
static inline uint64_t mtime_read(void){
  uint32_t hi,lo;
  do{hi=REG(CLINT_MTIME+4u);lo=REG(CLINT_MTIME);}while(hi!=REG(CLINT_MTIME+4u));
  return ((uint64_t)hi<<32)|lo;
}
static inline void timer_arm(uint32_t hart,uint32_t delta){
  uint64_t t=mtime_read()+delta;
  REG(CLINT_MTIMECMP(hart)+4u)=0xffffffffu;   // no spurious match while updating
  REG(CLINT_MTIMECMP(hart))=(uint32_t)t;
  REG(CLINT_MTIMECMP(hart)+4u)=(uint32_t)(t>>32);
}
static inline int uart_put(uint32_t ch){
  uint32_t start=cycle_count();
  while(!(REG(UART+4)&2))if(cycle_count()-start>2000000u)return -1;
  REG(UART)=ch;return 0;
}
static inline void uart_puts(const char *s){while(*s)uart_put((uint8_t)*s++);}
static inline void uart_dec(uint32_t v){
  char b[11];int i=0;
  do{b[i++]=(char)('0'+v%10u);v/=10u;}while(v);
  while(i)uart_put((uint8_t)b[--i]);
}
static inline void uart_hex(uint32_t v){
  for(int i=7;i>=0;i--){uint32_t d=(v>>(4*i))&15u;uart_put(d<10u?'0'+d:'a'+d-10u);}
}
#endif
