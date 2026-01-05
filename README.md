# Realtime debugging on Gecko5 or1k virtual prototype

Custom OpenOCD source available [here](https://github.com/Indyuce/openocd-gecko5)

## File Content

| Folder | Content   |
|--------|-----------|
| `src/vp` | Source code of the virtual prototype, and scripts to run OpenOCD and GDB. `src/vp/modules/jtag` contains code and testbenches for the up-to-date JTAG interface. `src/vp/modules/jtag_interface` contains the code for the JTAG interface of the last semester project, it is only kept for reference. `src/vp/modules/adv_debug_if` contains Verilog code of the ADI. |
| `report` | Report source code |
| `notes` | Weekly meeting notes |
| `docs` | Additional, external documentation (FPGA, OR, ADI, course slides..) |
| `src/or1ksim` | Source code of an or1k simulator. We thought about using it for tests but it turns out it implements a GDB RSP server directly, so it's impossible to use it alongside OpenOCD. It turned out useless for this project |
| `src/or1k_programs` | Some programs to try GDB with |

## References (see report for exhaustive list)

- [Antoine Colson's work](https://github.com/nosloc/JTAG_support_for_Gecko5Education) on implementation a JTAG interface for the OR1200 CPU.
- [OpenOCD User Docs](https://openocd.org/pages/documentation.html). Click hyperlink "PDF" to download
- [OpenOCD Dev Docs](https://openocd.org/doc/doxygen/html/index.html)
- [OpenRISC ork1sim simulator](https://openrisc.io/implementations.html#or1ksim). A C simulator for OR1200 processor featuring a server which GDB can connect to for debugging.
- [GDB RSP protocol](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Packets.html) packet list
- [Debugging or1k on FPGAs using GDB](https://openrisc.io/tutorials/docs/Debugging.html), a tutorial on how to hook OpenOCD onto a or1k target CPU when placed on a FPGA
- [Supported CPU configs](https://openocd.org/doc/html/CPU-Configuration.html) for OpenOCD indicating JTAG TAP controlers supported by the CPU debugging tools of OpenOCD