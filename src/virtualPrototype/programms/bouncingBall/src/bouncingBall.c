#include <stdio.h>
#include <vga.h>
#include <swap.h>

int main() {
  int xdir, ydir, xpos, ypos, index;
  volatile unsigned int *leds =(unsigned int *) 0x50000C00;
  volatile unsigned int *seven = (unsigned int *) 0x50000060;
  volatile unsigned int supervisor;
  vga_clear();
#ifdef __OR1300__
  /* enable the caches */
  asm volatile ("l.mfspr %[out1],r0,17":[out1]"=r"(supervisor));
  supervisor |= 3<<3;
  asm volatile ("l.mtspr r0,%[in1],17"::[in1]"r"(supervisor));
#endif
  printf("Bouncing ball demo.\n");
  xdir = ydir = 1;
  xpos = ypos = 5;
  while (1) {
    index = ypos * 12 + xpos;
    leds[index] = 0;
    if (ypos == 9) ydir = -1;
    if (ypos == 0) ydir = 1;
    if (xpos == 11) xdir = -1;
    if (xpos == 0) xdir = 1;
    ypos += ydir;
    xpos += xdir;
    index = ypos * 12 + xpos;
    leds[index] = swap_u32(2);
    index = (xpos&0xFF)<<8 | (ypos&0xFF);
    seven[4] = swap_u32(index);
    asm volatile ("l.nios_rrr r0,%[in1],r0,0x6"::[in1]"r"(100000)); //wait 0.1 sec.
  }
}
