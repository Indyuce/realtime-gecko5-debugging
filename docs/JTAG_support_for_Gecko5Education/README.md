# JTAG Support for Gecko5Education

This project is an EPFL semester project in the LAP laboratory that focuses on implementing and testing robust JTAG (Joint Test Action Group) communication and control for the Gecko5Education board.
The primary objective is to develop low-level infrastructure that enables JTAG-based access to internal system components, providing a foundation for concrete and useful applications.

This project is articulated into two milestones: 

- Milestone 1 (tag : milestone-1) :Establish basic communication via the JTAG interface and demonstrate control using the on-board RGB LEDs.
- Milestone 2 : Extend the JTAG interface to support memory access and peripheral control by enabling read and write operations to any component on the bus architecture.

In summary, this project aimed to transform the previously underutilized JTAG interface of the Gecko5Education board into a powerful low-level communication path 
that can be used by EPFL students in future projects.
Both milestones were successfully completed: reliable communication with the board was achieved, 
and the interface was extended to provide full access to memory and peripherals.
As a result, software can now interact with the board through a high-level abstraction of the JTAG interface, 
hiding much of the underlying complexity.

## Features

This project offers the following features:

- **JATG Support to control RGB LEDs**: Basic functionality to turn on/off and change colors of the RGB LEDs on the Gecko5Education board.
- **Peripheral Access**: Read and write operations to access various peripherals connected to the board or integrated in the OpenRisc based architecture.
- **Final report**: A comprehensive report detailing the design, implementation, and testing of the JTAG interface.
- **Scripts and configuration files**: For easy setup and testing of the JTAG interface.

## Getting Started

### Prerequisites

- **Gecko5Education board**
- **JTAG programming/debugging tool**: In this project, we used the OpenOCD tool.
- **OCD-CAD-SUITE**: A binary software distrubution : [OCD-CAD-SUITE](https://github.com/YosysHQ/oss-cad-suite-build)
- **Python 3**: Required for running scripts to control the JTAG interface.
- **Optional: Verilog simulator**: Such as ModelSim, Vivado, or any other compatible simulator.

### Build & Simulation

1. Clone this repository.

    ```bash
    git clone https://github.com/nosloc/JATG_support_for_Gecko5Education
    cd JATG_support_for_Gecko5Education
    ```
2. Fill the corresponding path to the OCD-CAD-SUITE in the `config.cfg` file located in the `project/scripts/` directory.

    ```bash
    nano project/scripts/config.cfg
    ```

#### Milestone 1: Basic JTAG Communication

3. Check out the milestone-1 tag.

    ```bash
    git checkout milestone-1
    ```

4. Synthesize and load the design onto the Gecko5Education board using the provided scripts.

    ```bash
    ./project/scripts/synthesize.sh
    ```

5. Run the python script to choose the LEDs you want to turn on.

    ```bash
    python3 project/scripts/jtag_control_leds.py
    ```

#### Milestone 2: Extended JTAG Functionality

3. Check out the latest version of the project.

    ```bash
    git checkout main
    ```

4. Synthesize and load the design onto the Gecko5Education board using the provided scripts.

    ```bash
    cd /project/systems/singleCore/scripts
    ./synthesize.sh
    ```

5a. Interact with the JTAG interface using low-level commands.
1. Run the OpenOCD server to connect to the Gecko5Education board.

    ```bash
    cd project/scripts
    openocd -f config.cfg
    ```
2. In a separate terminal, connect to the OpenOCD server using telnet.

    ```bash
    telnet localhost 4444
    ```
3. Use the provided JTAG commands explained in the report to read/write memory or control peripherals.

5b. Use the provide C programm

1. Run the OpenOCD server to connect to the Gecko5Education board.

    ```bash
    cd project/scripts
    openocd -f config.cfg
    ```

2. On a separated terminal compile the C program to interact with the JTAG interface.

    ```bash
    cd project/scripts
    gcc jtag_interface.c -o jtag_interface
    ```

2. Run the compiled program to interact with the JTAG interface (all options are available in the report).

    ```bash
    ./jtag_interface -h
    ```

    ```bash
    ./jtag_interface -r -addr 0x000100 -bs 4 -s 100
    ./jtag_interface -w -addr 0x000100 -bs 4 -s 100
    ```

## Directory Structure

- `/project/modules/jtag_interface` — Verilog source modules for the added JTAG interface
- `/project/modules/jtag_interface/testbenches/` — Testbenches for simulation of the JTAG interface
- `/project/scripts/` — Scripts for higher level communication and openocd configuration
- `/project/systems/singleCore/scripts/` — Scripts for synthesis and loading the design onto the Gecko5Education board
- `/project/systems/singleCore/verilog` — top-level design files for the Gecko5Education board
- `/tests/` - Tests related to the first milestone
- `/report/` - All report related files, including the final report and presentation slides
- `/notes/` - Weekly notes throughout the semester
