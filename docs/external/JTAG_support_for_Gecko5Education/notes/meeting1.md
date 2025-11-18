# Meeting 1

Thursday february the 7th

## Questions asked

### 1. What do you expect from me now that a have some understanding of the field ?

- A Lattice FPGA with a simple JTAG interface already inmplemented a very simple JTAG interface.
- The FPGA runs an openRISC processor

#### Goals of the projects

The board have two empty components in the JTAG Chain that can be used  

1. The first one should be used to be able to write in the SRAM faster than using UART implementation that is actually using.
2. Use the second component to be able to use GDB so that it is possible to debug the program that is running on the processor  

Those two objectives implies that :  

1. Implement the IP core of the FPGA, that will be used for both parts (ideally light a light to prove that it works)
2. Write data in the SRAM
3. Create a software that take a program as input and write it in the SRAM for all the machines
4. Bridge the JTAG core to openOCD or just parts used by GDB
5. bridge openOCD and GDB

### 2. I remembered you talking about three "milestones" in this project waht are they again ?

1. IP core that works
2. Load program in the SRAM
3. Be able to use GDB

### 3. What is th hardware used ?

- A Lattice FPGA with a simple JTAG interface already inmplemented a very simple JTAG interface.
- The FPGA runs an openRISC processor

### 4. What the debugger should be able to do by the end of the project ?

- Be able to use GDB
- For Peak and Poke the memory it is part of the write data in the SRAM

### 5. For this project do i need to have access to a the real FPGA for testing my implementation for example ?

Yes I have acces to it now a Latice ECP5 FPGA with openRISC. GECKO5EDUCATION

### 6. Why having a video about using openOCD in propel if you said I should be quartus ?  

No need for this video neither quartus we will use open source software to synthesize (Compile HDL Code), Place and Route, load the bit stream in the memory.

### 7. What is already implemented what should i strat with, where can i find thiose resssources?

I now have access to the course Embeded system design that should help me for getting the necessary ressources (Open risc that is used, the tools used to replace Quartus ...)

### 8. OpenOCD was very  present in the documentation you gave me, in wich way is it related to the project?

Do the link betweeen JTAG IP core and GDB

### 9.  What are the next steps : If I have ideas try to figure out the next steps if not what are nexts steps you think i should do ?

Continue reading info on internet + create a timeline for the project
