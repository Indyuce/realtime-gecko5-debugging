#include <vga.h>

void vga_puts(const char* str) {
    while (*str)
        vga_putc(*str++);
}
