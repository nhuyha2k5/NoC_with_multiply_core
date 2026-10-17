#include "soc.h"
// 4-hart firmware. hart0 is the master; harts 1..3 are workers.
// Results and handshakes use the uncached window; stacks and benchmark data
// are cached and rely on MESI coherence (one writer per flag word). The
// shared counter is protected by the hardware test-and-set lock (Ibex has no
// A extension).
static const volatile uint32_t rom_probe[2]={0x13579bdfu,0x2468ace0u};
static volatile uint32_t ram_probe=0x5a17c0deu;
static volatile uint32_t flush_sink;
static int wait_mask(uint32_t address,uint32_t mask,uint32_t value,uint32_t limit){
  uint32_t start=cycle_count();
  while((REG(address)&mask)!=value){
    if(address==MARK+4 && (REG(MARK+4)&24u))return -2;
    if(cycle_count()-start>limit)return -1;
  }
  return 0;
}
// PLIC driver: drain every pending claim, clear the source in its IP, then
// complete with the same ID while the source is still enabled.
void handle_trap(uint32_t cause){
  if(cause==0x8000000bu){
    uint32_t id;
    while((id=REG(CTX+4))!=0){
      if(id==4||id==5){REG(DMA+16)=6;REG(MARK+4)|=id==4?1u:8u;}
      else if(id==6||id==7){REG(ACC+20)=6;REG(MARK+4)|=id==6?2u:16u;}
      else if(id==2||id==3||id==9||id==10){
        uint32_t h=id<4u?id-2u:id-7u;
        REG(MAILBOX+12)=1u<<h;
        REG(MARK+4)|=h==0u?4u:32u;
      }
      else if(id==1)REG(UART+12)=1;
      else if(id==8){REG(GPIO+24)=0xffu;REG(MARK+4)|=64u;}
      fence_rw();REG(CTX+4)=id;
    }
  }else if(cause==0x80000003u){REG(CLINT_MSIP(HART))=0;REG(MARK+8)=1;}
  else if(cause==0x80000007u){REG(CLINT_MTIMECMP(HART)+4u)=0xffffffffu;REG(MARK+12)=1;}
  else {REG(MARK)=0xbad00000u|cause;for(;;){}}
}

// ---------------------------------------------------------------------------
// Shared data (cached region).
#define MM_N 16u
#define MM_A ((uint32_t *)0x20001000u)
#define MM_B ((uint32_t *)0x20001400u)
#define MM_C1 ((uint32_t *)0x20001800u)
#define MM_C2 ((uint32_t *)0x20001c00u)
#define MM_C4 ((uint32_t *)0x20002000u)
#define SUM_WORDS 512u
#define SUM_DATA ((uint32_t *)0x20002400u)
#define FLUSH_REGION ((volatile uint32_t *)0x20003000u)
#define COUNTER ((volatile uint32_t *)0x20000e00u)
#define JOB ((volatile uint32_t *)0x20000f00u)    // [0]=epoch [1]=type [2]=harts; hart0 writes
#define DONE(h) (((volatile uint32_t *)0x20000f40u)[h]) // worker h writes
#define PART(h) (((volatile uint32_t *)0x20000f80u)[h]) // partial sums
#define UC_A 0x2000a000u
#define UC_B 0x2000a400u
#define UC_C 0x2000a800u
#define LOCK_ITERS 32u
enum {P_MM1=0,P_MM2=4,P_MM4=8,P_SUM1=12,P_SUM2=16,P_SUM4=20,P_ACC_ENGINE=24,P_ACC_E2E=28,
      P_STATUS=32,P_PHASE=36,P_SUM=40,P_FLUSH=44,P_DISPATCH_COLD=48,P_DISPATCH_WARM=52,
      P_COUNTER=56,P_MMSUM=60};
enum {JOB_FLUSH=1,JOB_MATMUL=2,JOB_SUM=3,JOB_NOP=4};

static void cache_flush(void){
  // 128 consecutive words cover every index of the direct-mapped D-cache.
  uint32_t s=0;
  for(uint32_t i=0;i<128;i++)s+=FLUSH_REGION[i];
  flush_sink=s;
}
static void matmul_rows(uint32_t r0,uint32_t r1,uint32_t *c){
  for(uint32_t i=r0;i<r1;i++)
    for(uint32_t j=0;j<MM_N;j++){
      uint32_t acc=0;
      for(uint32_t k=0;k<MM_N;k++)acc+=MM_A[i*MM_N+k]*MM_B[k*MM_N+j];
      c[i*MM_N+j]=acc;
    }
}
static uint32_t sum_range(uint32_t a,uint32_t b){
  uint32_t s=0;
  for(uint32_t i=a;i<b;i++)s+=SUM_DATA[i];
  return s;
}
static uint32_t *mm_out(uint32_t n){return n==1u?MM_C1:(n==2u?MM_C2:MM_C4);}
// Same workload split into n equal contiguous slices; hart h runs slice h.
static void run_job(uint32_t type,uint32_t h,uint32_t n){
  if(type==JOB_FLUSH)cache_flush();
  else if(type==JOB_MATMUL)matmul_rows(MM_N*h/n,MM_N*(h+1u)/n,mm_out(n));
  else if(type==JOB_SUM)PART(h)=sum_range(SUM_WORDS*h/n,SUM_WORDS*(h+1u)/n);
}
static void lock_test(void){
  for(uint32_t k=0;k<LOCK_ITERS;k++){lock_acquire(0);COUNTER[0]=COUNTER[0]+1u;lock_release(0);}
}

#if HART == 0
static uint32_t job_epoch;
static void post_job(uint32_t type,uint32_t n){
  JOB[1]=type;JOB[2]=n;fence_rw();
  JOB[0]=++job_epoch;fence_rw();
  for(uint32_t h=1;h<n;h++)REG(mailbox_slot(h))=job_epoch;   // doorbell -> PLIC -> hart h
}
static int wait_job(uint32_t n){
  uint32_t start=cycle_count();
  for(uint32_t h=1;h<n;h++)
    while(DONE(h)!=job_epoch)if(cycle_count()-start>4000000u)return -1;
  fence_rw();
  return 0;
}
static void phase(uint32_t p){REG(PAR+P_PHASE)=p;}
static int flush_all(void){post_job(JOB_FLUSH,NHARTS);cache_flush();return wait_job(NHARTS);}
// Cold-cache timed kernel on n harts: phase p before, p+1 after.
static int bench(uint32_t type,uint32_t n,uint32_t offset,uint32_t p){
  if(flush_all())return -1;
  phase(p);
  uint32_t t=cycle_count();
  if(n>1u)post_job(type,n);
  run_job(type,0,n);
  if(n>1u&&wait_job(n))return -1;
  REG(PAR+offset)=cycle_count()-t;
  phase(p+1u);
  return 0;
}
static int same(const uint32_t *a,const uint32_t *b){
  for(uint32_t i=0;i<MM_N*MM_N;i++)if(a[i]!=b[i])return 0;
  return 1;
}
static uint32_t total_sum(uint32_t n){uint32_t s=0;for(uint32_t h=0;h<n;h++)s+=PART(h);return s;}

static int parallel_benchmarks(void){
  uint32_t status=0,t;
  for(uint32_t i=0;i<MM_N;i++)
    for(uint32_t k=0;k<MM_N;k++){
      MM_A[i*MM_N+k]=(uint32_t)((int32_t)((i*7u+k*3u)%11u)-5);
      MM_B[i*MM_N+k]=(uint32_t)((int32_t)((i*5u+k*2u)%13u)-6);
    }
  for(uint32_t i=0;i<SUM_WORDS;i++)SUM_DATA[i]=i*2654435761u;
  fence_rw();

  // Matrix 16x16 on 1, 2 and 4 harts (rows split evenly).
  if(bench(JOB_MATMUL,1,P_MM1,1)||bench(JOB_MATMUL,2,P_MM2,3)||bench(JOB_MATMUL,4,P_MM4,5))return -1;
  status|=(uint32_t)same(MM_C1,MM_C2);
  status|=(uint32_t)same(MM_C1,MM_C4)<<1;
  uint32_t mmsum=0;
  for(uint32_t i=0;i<MM_N*MM_N;i++)mmsum+=MM_C1[i]*(i+1u);
  REG(PAR+P_MMSUM)=mmsum;

  // Same matrices on the accelerator (uncached window), end to end.
  phase(7);t=cycle_count();
  for(uint32_t i=0;i<MM_N*MM_N;i++){REG(UC_A+i*4)=MM_A[i];REG(UC_B+i*4)=MM_B[i];}
  REG(MARK+4)&=~2u;
  REG(ACC)=UC_A;REG(ACC+4)=UC_B;REG(ACC+8)=UC_C;REG(ACC+12)=MM_N;REG(ACC+24)=3;
  fence_rw();REG(ACC+16)=1;
  if(wait_mask(MARK+4,2,2,2000000u))return -2;
  dma_acquire();
  uint32_t ok=1;
  for(uint32_t i=0;i<MM_N*MM_N;i++)if(REG(UC_C+i*4)!=MM_C1[i])ok=0;
  REG(PAR+P_ACC_E2E)=cycle_count()-t;REG(PAR+P_ACC_ENGINE)=REG(ACC+28);phase(8);
  status|=ok<<2;

  // Memory-bound reduction over 512 words on 1, 2 and 4 harts.
  if(bench(JOB_SUM,1,P_SUM1,9))return -1;
  uint32_t s1=total_sum(1);
  if(bench(JOB_SUM,2,P_SUM2,11))return -1;
  uint32_t s2=total_sum(2);
  if(bench(JOB_SUM,4,P_SUM4,13))return -1;
  uint32_t s4=total_sum(4);
  REG(PAR+P_SUM)=s1;
  status|=(uint32_t)(s1==s2)<<3;
  status|=(uint32_t)(s1==s4)<<4;
  t=cycle_count();if(flush_all())return -1;REG(PAR+P_FLUSH)=cycle_count()-t;

  // Job dispatch overhead: empty job to all three workers (mailbox doorbell
  // -> PLIC -> worker trap/claim/complete -> DONE flag), cold then warm.
  t=cycle_count();post_job(JOB_NOP,NHARTS);if(wait_job(NHARTS))return -1;REG(PAR+P_DISPATCH_COLD)=cycle_count()-t;
  t=cycle_count();post_job(JOB_NOP,NHARTS);if(wait_job(NHARTS))return -1;REG(PAR+P_DISPATCH_WARM)=cycle_count()-t;

  status|=(uint32_t)(REG(PAR+P_COUNTER)==NHARTS*LOCK_ITERS)<<5;

  // GPIO rising edge on bit 0 -> PLIC source 8 -> claim/clear/complete.
  REG(GPIO+16)=1u;REG(GPIO+12)=1u;
  phase(15);
  if(wait_mask(MARK+4,64,64,200000u))return -3;
  status|=64u;
  REG(PAR+P_STATUS)=status;
  return 0;
}

static void report_line(const char *kernel,uint32_t harts,uint32_t cycles,uint32_t check,uint32_t pass){
  uart_puts("BENCH kernel=");uart_puts(kernel);
  uart_puts(" harts=");uart_dec(harts);
  uart_puts(" cycles=");uart_dec(cycles);
  uart_puts(" checksum=");uart_hex(check);
  uart_puts(pass?" status=PASS\n":" status=FAIL\n");
}
static void uart_report(uint32_t ok){
  uint32_t st=REG(PAR+P_STATUS),mm=REG(PAR+P_MMSUM),sum=REG(PAR+P_SUM);
  report_line("matmul16",1,REG(PAR+P_MM1),mm,1);
  report_line("matmul16",2,REG(PAR+P_MM2),mm,st&1u);
  report_line("matmul16",4,REG(PAR+P_MM4),mm,st&2u);
  report_line("sum512",1,REG(PAR+P_SUM1),sum,1);
  report_line("sum512",2,REG(PAR+P_SUM2),sum,st&8u);
  report_line("sum512",4,REG(PAR+P_SUM4),sum,st&16u);
  uart_puts("LOCK count=");uart_dec(REG(PAR+P_COUNTER));uart_puts((st&32u)?" status=PASS\n":" status=FAIL\n");
  uart_puts(ok?"RESULT PASS status=":"RESULT FAIL status=");uart_hex(st);uart_puts("\n");
}
#else
static void worker_loop(void){
  uint32_t last=0;
  for(;;){
    // Sleep until a job is posted. MIE is cleared around the check so a
    // mailbox IRQ that arrives between the check and WFI still wakes us.
    for(;;){
      __asm__ volatile("csrci mstatus,8":::"memory");
      if(JOB[0]!=last){__asm__ volatile("csrsi mstatus,8":::"memory");break;}
      __asm__ volatile("wfi");
      __asm__ volatile("csrsi mstatus,8":::"memory");
    }
    last=JOB[0];fence_rw();
    uint32_t n=JOB[2];
    if(HART<n)run_job(JOB[1],HART,n);
    fence_rw();DONE(HART)=last;
  }
}
#endif

int main(void){
  uint32_t boot_cycle=cycle_count();
  REG(MARK)=0;REG(MARK+4)=0;REG(MARK+8)=0;REG(MARK+12)=0;
  if(rom_probe[0]!=0x13579bdfu||rom_probe[1]!=0x2468ace0u||ram_probe!=0x5a17c0deu){
    REG(MARK)=0xbad000da;for(;;){__asm__ volatile("wfi");}
  }
#if HART == 0
  for(uint32_t i=0;i<64;i++)REG(PAR+i*4)=0;
  // Job flags and the lock counter are defined before the workers are
  // released by the IPI below.
  JOB[0]=0;JOB[1]=0;JOB[2]=0;COUNTER[0]=0;
  for(uint32_t h=0;h<NHARTS;h++){DONE(h)=0;PART(h)=0;}
  fence_rw();
  REG(GPIO+4)=255;REG(GPIO)=1;
  // Priorities: sources 1..7 = ID, GPIO lowest, worker mailboxes as hart1's.
  for(uint32_t s=1;s<=7;s++)REG(PLIC+s*4)=s;
  REG(PLIC+8*4)=1;REG(PLIC+9*4)=3;REG(PLIC+10*4)=3;
  // Context 0 (hart0): UART, mailbox->hart0, DMA, accelerator, GPIO.
  REG(PLIC_ENABLE(0))=(1u<<1)|(1u<<2)|(1u<<4)|(1u<<5)|(1u<<6)|(1u<<7)|(1u<<8);
  REG(CTX)=0;
  irq_enable();
  for(uint32_t h=1;h<NHARTS;h++)
    if(wait_mask(MARK_OF(h),0xffffffffu,0x11111111u,1000000u)){
      REG(MARK)=0xbad00010u|h;for(;;){__asm__ volatile("wfi");}
    }
  // Release the workers with a CLINT software interrupt each.
  for(uint32_t h=1;h<NHARTS;h++)REG(CLINT_MSIP(h))=1;
  timer_arm(0,2000);
  lock_test();
  for(uint32_t i=0;i<16;i++)REG(0x20008000u+i*4)=0xabc00000u+i;
  for(uint32_t i=0;i<9;i++){
    REG(0x20009000u+i*4)=i+1;
    REG(0x20009400u+i*4)=(i/3==i%3);
  }
  REG(ACC)=0x20009000;REG(ACC+4)=0x20009400;REG(ACC+8)=0x20009800;REG(ACC+12)=3;REG(ACC+24)=3;
  if(dma_start_copy(0x20008000u,0x20008400u,64u)){
    REG(MARK)=0xbad00013u;for(;;){__asm__ volatile("wfi");}
  }
  fence_rw();REG(ACC+16)=1;
  if(wait_mask(MARK+4,7,7,1000000u)||wait_mask(MARK+12,1,1,1000000u)){
    REG(MARK)=0xbad00011;for(;;){__asm__ volatile("wfi");}
  }
  dma_acquire();
  uint32_t ok=1;
  for(uint32_t i=0;i<16;i++)if(REG(0x20008400u+i*4)!=0xabc00000u+i)ok=0;
  for(uint32_t i=0;i<9;i++)if(REG(0x20009800u+i*4)!=i+1)ok=0;
  REG(MARK+16)=REG(DMA+24);REG(MARK+20)=REG(ACC+28);
  // Every worker has finished its lock increments once it reports done.
  for(uint32_t h=1;h<NHARTS;h++)
    if(wait_mask(MARK_OF(h),0xffffffffu,0x600d0000u|h,2000000u)){
      REG(MARK)=0xbad00014u;for(;;){__asm__ volatile("wfi");}
    }
  lock_acquire(0);REG(PAR+P_COUNTER)=COUNTER[0];lock_release(0);
  int par=parallel_benchmarks();
  if(par){REG(MARK)=0xbad00020u|(uint32_t)(-par);for(;;){__asm__ volatile("wfi");}}
  if(REG(PAR+P_STATUS)!=0x7fu)ok=0;
  REG(MARK+24)=cycle_count()-boot_cycle;
  uart_report(ok);
  REG(GPIO)=ok?0x5a:0xe1;
  fence_rw();REG(MARK)=ok?0x600d0000u:0xbad00000u;
#else
  // Context HART: this hart's mailbox source, used for job notification.
  REG(PLIC_ENABLE(HART))=1u<<mailbox_source(HART);
  REG(CTX)=0;
  irq_enable();REG(MARK)=0x11111111u;
  if(wait_mask(MARK+8,1,1,1000000u)){
    REG(MARK)=0xbad00012;for(;;){__asm__ volatile("wfi");}
  }
  lock_test();
#if HART == 1
  // Multiword Fibonacci(100), exact unsigned 128-bit representation.
  uint32_t fib_cycle=cycle_count();
  uint32_t a[4],b[4],t[4];
  for(uint32_t j=0;j<4;j++){a[j]=0;b[j]=0;}b[0]=1;
  for(uint32_t i=0;i<100;i++){
    uint32_t carry=0;
    for(uint32_t j=0;j<4;j++){
      uint32_t x=a[j]+b[j],c1=x<a[j],y=x+carry,c2=y<x;
      t[j]=y;carry=c1|c2;
    }
    for(uint32_t j=0;j<4;j++){a[j]=b[j];b[j]=t[j];}
  }
  for(uint32_t j=0;j<4;j++)REG(0x2000bf80u+j*4)=a[j];
  REG(MARK+16)=cycle_count()-fib_cycle;
#endif
  REG(MARK+24)=cycle_count()-boot_cycle;
  fence_rw();
#if HART == 1
  REG(mailbox_slot(0))=0xf100;   // mailbox -> PLIC source 2 -> hart0
#endif
  REG(MARK)=0x600d0000u|HART;
  worker_loop();
#endif
  for(;;){__asm__ volatile("wfi");}
}
