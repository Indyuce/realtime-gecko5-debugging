#include <stdio.h>
#include <stdint.h>
#include <defs.h>
#ifdef __OR1300__
#include "spr.h"

__weak void bus_error_handler() {
    asm volatile ("l.trap 15");
    puts("bus error!");
}

__weak void data_page_fault_handler() {
    puts("Data page fault");
}

__weak void instruction_page_fault_handler() {
    puts("i page fault");
}

__weak void tick_timer_handler() {
    puts("tick");
}

__weak void allignment_exception_handler() {
    asm volatile ("l.trap 15");
    puts("allig!");
}

__weak void illegal_instruction_handler() {
    puts("???? ");
}

__weak void external_interrupt_handler() {
    puts("ping");
}

__weak void dtlb_miss_handler() {
    puts("dtlb");
}

__weak void itlb_miss_handler() {
    puts("itlb");
}

__weak void range_exception_handler() {
    puts("Range!");
}

__weak void system_call_handler() {
    puts("Syscall");
}

__weak void trap_handler() {
    uint32_t value;
    puts("\n\nTrap!");
    printf("EPCR = 0x%08X\n", SPR_READ(32));
    printf("EEAR = 0x%08X\n", SPR_READ(48));
    printf("ESR  = 0x%08X\n", SPR_READ(64));
    printf("Instruction = 0x%08X\n", SPR_READ(80));
    int i;
    for (i = 0 ; i < 32; i++) {
      printf("r%02d = 0x%08X\n", i, SPR_READ2(1024,i));
    }
    for (i = 0 ; i < 256; i++) {
      printf ("0x%08X\n", SPR_READ2(0x3100,i));
    }
    while (1) {};
}

__weak void break_point_handler() {
    puts("Break");
}

#else

__weak void i_cache_error_handler() {
    puts("I$ error!");
}

__weak void d_cache_error_handler() {
    puts("D$ error!");
}

__weak void illegal_instruction_handler() {
    puts("????");
}

__weak void external_interrupt_handler() {
    puts("ping");
}

__weak void system_call_handler() {
    puts("Syscall");
}

#endif
