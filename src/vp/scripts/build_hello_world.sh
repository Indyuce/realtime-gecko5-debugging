cd ../programs/helloWorld

# Clean previous builds and build the hello world program for mem1420 target
make clean mem1420

# Copy the built ELF file to the scripts directory
mv build-release/hello.elf ../../scripts/

# Go back to previous directory
cd ../../scripts/

# Launch GDB to connect to the OpenRISC target
./open_gdb.sh
