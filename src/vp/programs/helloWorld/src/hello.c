#include <stdio.h>
#include <vga.h>
#include <spr.h>

uint32_t read_register(uint32_t address) {
  uint32_t value;
  asm volatile("l.lwz %0, 0(%1)" : "=r"(value) : "r"(address));
  return value;
}

void write_register(uint32_t address, uint32_t value) {
  asm volatile("l.sw 0(%0), %1" :: "r"(address), "r"(value));
}
int main () {
  int reg;
  vga_clear();
  printf("Hello World!\n" );
  asm volatile ("l.ori %[out1],r1,0":[out1]"=r"(reg));
  printf("My stacktop = 0x%08X\n", reg);

  uint32_t address = 0x01000000; // Example address

  for (int i = 0; i < 10; i++) {
    uint32_t value = read_register(address + i * 4);
    printf("Value at address 0x%08X: 0x%08X\n", address + i * 4, value);
  }
  return 0;
}
